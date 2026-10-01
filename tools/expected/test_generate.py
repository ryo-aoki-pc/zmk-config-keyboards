"""tools/expected/generate.py のテスト。

    python -m unittest discover -s tools/expected -v

submodule (git submodule update --init) が無いときは、submodule を使うテストを飛ばす。
"""
from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import generate as g  # noqa: E402

KQ_VIL = (g.ROOT / 'vial-qmk-kq-mini/keyboards/sekigon/keyboard_quantizer/mini/keymaps/vial/KEYMAP.vil')


def have_submodules() -> bool:
    try:
        src = g.Sources()
        for name in g.SUBMODULES:
            src.path(name)
        return True
    except g.GenError:
        return False


class TestTables(unittest.TestCase):
    def test_scan_codes(self):
        self.assertEqual(g.HID_SCAN[0x04][:2], (0x1E, 0))          # A
        self.assertEqual(g.HID_SCAN[0x2C][:2], (0x39, 0))          # Space
        self.assertEqual(g.HID_SCAN[0xE3][:2], (0x5B, 0xE0))       # 左 Win
        self.assertEqual(g.HID_SCAN[0x4F][:2], (0x4D, 0xE0))       # →
        self.assertEqual(g.HID_SCAN[0x87][:2], (0x73, 0))          # JIS ろ

    def test_dumps_is_valid_json(self):
        obj = {'a': [1, 2, [3, 4]], 'b': {'x': 'あ', 'y': None}, 'c': [{'k': 1}, {'k': 2}]}
        self.assertEqual(json.loads(g.dumps(obj)), obj)


@unittest.skipUnless(have_submodules(), 'submodule がありません (git submodule update --init)')
class TestGenerate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = g.Sources()
        cls.files = g.generate(cls.sources)
        cls.data = {k: json.loads(v) for k, v in cls.files.items()}
        cls.kd, cls.zv, cls.vd = g.import_docgen(cls.sources)

    def test_deterministic(self):
        self.assertEqual(g.generate(g.Sources()), self.files)

    def test_committed_files_are_current(self):
        for name, text in self.files.items():
            p = HERE / name
            self.assertTrue(p.exists(), f'{name} がありません')
            self.assertEqual(p.read_text(encoding='utf-8'), text, f'{name} が古い (generate.py を実行してください)')

    def test_zmk_keycode(self):
        self.assertEqual(g.zmk_keycode(self.zv, 'Q'), 0x00070014)
        self.assertEqual(g.zmk_keycode(self.zv, 'LEFT_CONTROL'), 0x000700E0)
        self.assertEqual(g.zmk_keycode(self.zv, 'LS(LC(RIGHT))'), 0x0307004F)
        with self.assertRaises(g.GenError):
            g.zmk_keycode(self.zv, 'NO_SUCH_KEY')

    def test_lism_bindings(self):
        d = self.data['lism.json']
        b = d['readout']['zmk']['bindings']
        self.assertEqual(len(b), 10)
        self.assertTrue(all(len(layer) == 42 for layer in b))
        self.assertEqual((b[0][10]['b'], b[0][10]['p1'], b[0][10]['p2']), ('Mod-Tap', 0x000700E0, 0x00070004))
        self.assertEqual((b[0][34]['b'], b[0][34]['p1'], b[0][34]['p2']), ('Layer-Tap', 2, 0x0007002C))
        self.assertEqual((b[7][0]['b'], b[7][0]['p1'], b[7][0]['p2']), ('Bluetooth', 3, 0))
        self.assertEqual((b[9][13]['b'], b[9][13]['p1']), ('Mouse Key Press', 1))
        self.assertEqual(b[2][1]['b'], 'MM_VIM_W')
        self.assertIn('mm_vim_w', b[2][1]['accept'])
        self.assertEqual(d['physical']['layout_name'], '42-Key Layout')

    def test_zmk_interactive(self):
        for name in ('lism', 'kukey42', 'aroundfortyrb', 'pyuron'):
            d = self.data[f'{name}.json']
            it = d['interactive']
            keys = it['trackball']['keys']
            self.assertEqual(keys['left']['scroll']['legend'], 'D', name)
            self.assertEqual(keys['left']['click']['legend'], 'F', name)
            self.assertEqual(keys['left']['shift']['usage'], 0xE1, name)
            self.assertEqual(keys['right']['scroll']['legend'], 'K', name)
            self.assertEqual(keys['right']['after_timeout']['usage'], 0x0D, name)  # J
            self.assertEqual(it['trackball']['aml']['timeout_ms'], 10000, name)
            self.assertEqual(it['output_switch']['usb']['legend'], 'U', name)
            taps = {t['pos']: t for t in it['taps']}
            self.assertEqual(taps[10]['usage'], 0x04, name)        # A (タップ)
            self.assertEqual(taps[10]['hold_usage'], 0xE0, name)   # A (ホールド = 左 Ctrl)
            total = len(it['taps']) + len(it['skipped'])
            self.assertEqual(total, d['readout']['zmk']['key_count'], name)

    def test_trackball_firmware(self):
        kukey = self.data['kukey42.json']['interactive']['trackball']['firmware'][0]
        self.assertEqual(kukey['correction'], 'matrix')
        self.assertEqual(len(kukey['matrix']), 4)
        self.assertGreater(kukey['divisor'], 0)
        afrb = self.data['aroundfortyrb.json']['interactive']['trackball']['firmware'][0]
        for fw in (kukey, afrb):
            # PMW3610 の CPI は 200 刻み
            self.assertEqual(fw['cpi'] % 200, 0)
            self.assertTrue(200 <= fw['cpi'] <= 3200)
        self.assertEqual(len(afrb['xy_scaler']), 2)
        self.assertTrue(all(v > 0 for v in afrb['xy_scaler']))
        self.assertEqual([f['side'] for f in self.data['pyuron.json']['interactive']['trackball']['firmware']],
                         ['left', 'right'])

    def test_keyball(self):
        v = self.data['keyball39.json']['readout']['via']
        self.assertEqual(v['layer_count'], 4)
        self.assertEqual(v['keymap'][0][0][0], 0x14)        # KC_Q
        self.assertEqual(v['keymap'][1][1][2], 0x5222)      # MO(2) (D)
        self.assertEqual(v['keymap'][2][1][3], 0xD1)        # KC_BTN1 (F)
        self.assertEqual(v['keymap'][3][0][0], 0x7820)      # RGB_TOG
        self.assertEqual(v['keymap'][3][3][1], 0x7E00)      # KBC_RST
        self.assertEqual(v['status']['cpi'], 5)
        self.assertEqual(v['status']['scroll_div'], 5)
        self.assertEqual(v['status']['aml_timeout'], 10000)
        keys = self.data['keyball39.json']['physical']['keys']
        self.assertEqual(sum(1 for k in keys if k['present']), 39)

    def test_kq_mini(self):
        d = self.data['kq-mini.json']
        v = d['readout']['vial']
        self.assertEqual(len(v['keymap']), 8)
        self.assertEqual(len(v['keymap'][0]), 32)
        r, c = self.zv.hid_to_matrix(0x04)
        self.assertEqual(v['keymap'][0][r][c], 0x2104)      # LCTL_T(KC_A)
        self.assertEqual({s['qsid']: s['value'] for s in v['settings']}[7], 150)
        self.assertEqual(len(v['tap_dance']['entries']), 4)
        self.assertEqual(len(v['key_override']['entries']), 18)
        self.assertEqual(len(v['macro']['entries']), 16)
        self.assertEqual(d['device']['vial_uid'], [0x05, 0xE4, 0xA1, 0x7F, 0xDC, 0x87, 0xCB, 0x2A])
        taps = {t['pos']: t for t in d['interactive']['taps']}
        self.assertEqual(taps[33]['usage'], 0x2C)            # Space (LT)
        self.assertEqual(taps[10]['hold_usage'], 0xE0)
        skipped = {s['pos'] for s in d['interactive']['skipped']}
        self.assertIn(30, skipped)                           # FUNC (MO)

    @unittest.skipUnless(KQ_VIL.exists(), 'vial-qmk-kq-mini の KEYMAP.vil がありません')
    def test_kq_mini_matches_firmware_vil(self):
        vil = json.loads(KQ_VIL.read_text(encoding='utf-8'))
        self.assertEqual(self.data['kq-mini.json']['readout']['vial']['keymap'], vil['layout'])


if __name__ == '__main__':
    unittest.main()
