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


class TestAccelParser(unittest.TestCase):
    OVERLAY = '''
/ {
    /omit-if-no-ref/ trackball_accel: trackball_accel {
        compatible = "zmk,input-processor-xy-accel";
        #input-processor-cells = <0>;
        min-factor = <500>; // コメント
        max-factor = <1300>;
        speed-threshold = <1000>;
        speed-max = <4000>;
    };
};
&pointing_listener {
    input-processors =
        <&zip_xy_scaler 1 1>,
        <&trackball_accel>,
        <&zip_temp_layer 8 10000>;

    scroller {
        layers = <9>;
        input-processors = <&zip_xy_to_scroll_mapper>;
    };
};
'''

    def test_nodes_and_listener(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            Path(d, 'a.overlay').write_text(self.OVERLAY, encoding='utf-8')
            nodes = g.xy_accel_nodes(Path(d), ['a.overlay', 'missing.overlay'])
            text = g.strip_c_comments(self.OVERLAY)
            proc = g.listener_block(text, 'pointing_listener', Path(d, 'a.overlay'))
        self.assertEqual(nodes['trackball_accel']['min_factor'], 500)
        self.assertEqual(nodes['trackball_accel']['speed_max'], 4000)
        self.assertNotIn('scroll_mapper', proc)
        a = g.accel_in(nodes, proc)
        self.assertEqual(a['label'], 'trackball_accel')
        self.assertIsNone(g.accel_in(nodes, '<&zip_temp_layer 8 10000>'))
        self.assertTrue(g.same_accel(a, nodes['trackball_accel']))
        self.assertFalse(g.same_accel(a, None))
        self.assertEqual(g.accel_consistency('x', a, dict(a, max_factor=1000))['level'], 'warn')


class TestAmlThresholdParser(unittest.TestCase):
    OVERLAY = '''
/ {
    /omit-if-no-ref/ aml_threshold: aml_threshold {
        compatible = "zmk,input-processor-aml-threshold";
        #input-processor-cells = <2>;
        temp-layer = <&zip_temp_layer>; // コメント
        threshold = <12>;
    };
    aml_default: aml_default {
        compatible = "zmk,input-processor-aml-threshold";
        #input-processor-cells = <2>;
        temp-layer = <&zip_temp_layer>;
    };
};
&pointing_listener {
    input-processors =
        <&trackball_accel>,
        <&aml_threshold 8 10000>;

    scroller {
        layers = <9>;
        input-processors = <&zip_temp_layer 8 10000>, <&zip_xy_to_scroll_mapper>;
    };
};
'''

    def test_nodes_and_listener(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            Path(d, 'a.overlay').write_text(self.OVERLAY, encoding='utf-8')
            nodes = g.aml_threshold_nodes(Path(d), ['a.overlay', 'missing.overlay'])
            proc = g.listener_block(g.strip_c_comments(self.OVERLAY), 'pointing_listener', Path(d, 'a.overlay'))
        self.assertEqual(nodes['aml_threshold'], {'label': 'aml_threshold', 'temp_layer': 'zip_temp_layer', 'threshold': 12})
        self.assertEqual(nodes['aml_default']['threshold'], g.AML_THRESHOLD_DEFAULT)
        self.assertEqual(g.aml_threshold_in(nodes, proc)['threshold'], 12)
        self.assertIsNone(g.aml_threshold_in(nodes, '<&trackball_accel>, <&zip_temp_layer 8 10000>'))
        self.assertIn('なし', g.aml_threshold_text(None))

    def test_missing_temp_layer(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            Path(d, 'a.overlay').write_text('/ { x: x { compatible = "zmk,input-processor-aml-threshold"; }; };',
                                            encoding='utf-8')
            with self.assertRaises(g.GenError):
                g.aml_threshold_nodes(Path(d), ['a.overlay'])


class TestScrollAml(unittest.TestCase):
    OVERLAY = '''
&peripheral_listener {
    input-processors = <&trackball_accel>, <&aml_threshold MOUS 10000>;
    scroller {
        layers = <SCRL>; // コメント
        input-processors =
            <&zip_temp_layer MOUS 10000>,   // スクロール中も MOUS を維持する
            <&zip_xy_to_scroll_mapper>;
    };
};
&central_listener {
    scroller {
        layers = <9>;
        input-processors = <&zip_xy_to_scroll_mapper>, <&zip_scroll_scaler 1 16>;
    };
    other {
        layers = <3>;
        input-processors = <&zip_xy_to_scroll_mapper>;
    };
};
'''

    def test_chains(self):
        text = g.strip_c_comments(self.OVERLAY).replace('SCRL', '9').replace('MOUS', '8')
        chains = g.scroll_chains(text, 9)
        self.assertEqual([name for name, _ in chains], ['scroller', 'scroller'])
        self.assertTrue(g.keeps_aml(chains[0][1], 8))
        self.assertFalse(g.keeps_aml(chains[1][1], 8))
        self.assertFalse(g.keeps_aml('<&zip_temp_layer 8 5000>', 8))
        self.assertFalse(g.keeps_aml('<&zip_temp_layer 7 10000>', 8))

    def test_consistency(self):
        import tempfile
        board = {'files': ['a/b.overlay'], 'scroll': {'scaler': [1, 16]}}
        with tempfile.TemporaryDirectory() as d:
            Path(d, 'a').mkdir()
            p = Path(d, 'a/b.overlay')
            p.write_text(self.OVERLAY, encoding='utf-8')
            r = g.scroll_aml_consistency(board, Path(d), 8, 9)
            self.assertEqual(r['level'], 'warn')
            self.assertIn('a/b.overlay の scroller', r['message'])
            p.write_text(self.OVERLAY.replace('<&zip_xy_to_scroll_mapper>, <&zip_scroll_scaler 1 16>',
                                              '<&zip_temp_layer 8 10000>, <&zip_xy_to_scroll_mapper>'),
                         encoding='utf-8')
            self.assertEqual(g.scroll_aml_consistency(board, Path(d), 8, 9)['level'], 'ok')
            p.write_text('&x { input-processors = <&trackball_accel>; };', encoding='utf-8')
            r = g.scroll_aml_consistency(board, Path(d), 8, 9)
            self.assertEqual(r['level'], 'warn')
            self.assertIn('見つかりません', r['message'])


class TestHoldTapParser(unittest.TestCase):
    class FakeKeymap:
        def __init__(self, text: str, custom: dict | None = None):
            self.text = text
            self.custom = custom or {}

    def test_builtin_and_override(self):
        km = self.FakeKeymap('''
&mt {
    quick-tap-ms = <0>;
    tapping-term-ms = <150>;
    flavor = "balanced";
};
&zip_temp_layer { require-prior-idle-ms = <200>; };
''')
        hts = g.zmk_hold_tap_config(km)
        self.assertEqual((hts['mt']['flavor'], hts['mt']['tapping_term_ms'], hts['mt']['quick_tap_ms']),
                         ('balanced', 150, 0))
        self.assertEqual(hts['mt']['require_prior_idle_ms'], -1)       # &zip_temp_layer の値は使わない
        self.assertEqual((hts['lt']['flavor'], hts['lt']['tapping_term_ms']), ('tap-preferred', 200))  # ZMK の既定値
        self.assertEqual(hts['lt']['bindings'], ['&mo', '&kp'])
        self.assertIn('キーマップ', hts['mt']['source'])

    def test_custom_node(self):
        body = '''
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            flavor = "tap-unless-interrupted";
            tapping-term-ms = <220>;
            quick-tap-ms = <120>;
            global-quick-tap;
            retro-tap;
            hold-while-undecided;
            hold-trigger-key-positions = <1 2 0x10>;
            hold-trigger-on-release;
            bindings = <&kp>, <&sk>;
        '''
        km = self.FakeKeymap('''&hm { tapping-term-ms = <240>; };''',
                             {'hm': {'node': 'homerow', 'body': body}, 'm1': {'node': 'macro', 'body': 'x'}})
        h = g.zmk_hold_tap_config(km)['hm']
        self.assertEqual(h['flavor'], 'tap-unless-interrupted')
        self.assertEqual(h['tapping_term_ms'], 240)                    # ルートの上書き
        self.assertEqual(h['require_prior_idle_ms'], 120)              # global-quick-tap = quick-tap-ms
        self.assertTrue(h['retro_tap'] and h['hold_while_undecided'] and h['hold_trigger_on_release'])
        self.assertFalse(h['hold_while_undecided_linger'])
        self.assertEqual(h['hold_trigger_key_positions'], [1, 2, 16])
        self.assertEqual(h['bindings'], ['&kp', '&sk'])
        self.assertNotIn('m1', g.zmk_hold_tap_config(km))

    def test_bad_flavor(self):
        with self.assertRaises(g.GenError):
            g.zmk_hold_tap_config(self.FakeKeymap('&mt { flavor = "fast"; };'))

    def test_kq_chordal_hand(self):
        # KQ-mini の列 = HID コード & 7。列 0〜3 は L、4 は '*'、5〜7 は R
        self.assertEqual(g.kq_chordal_hand(0x04), '*')   # A
        self.assertEqual(g.kq_chordal_hand(0x1D), 'R')   # Z
        self.assertEqual(g.kq_chordal_hand(0x38), 'L')   # /
        self.assertEqual(g.kq_chordal_hand(0x09), 'L')   # F
        self.assertEqual(g.kq_chordal_hand(0x0D), 'R')   # J

    def test_qmk_entry(self):
        mt = g.qmk_entry(0x2104, {})                      # LCTL_T(KC_A)
        self.assertEqual((mt['kind'], mt['hold']['mods'], mt['tap']['usage']), ('ht', 0x01, 0x04))
        rmt = g.qmk_entry(0x3138, {})                     # RCTL_T(KC_SLSH)
        self.assertEqual(rmt['hold']['mods'], 0x10)
        lt = g.qmk_entry(0x422C, {2: 'VIM_BASE'})          # LT(2, KC_SPC)
        self.assertEqual((lt['hold']['kind'], lt['hold']['layer'], lt['hold']['label']), ('mo', 2, 'VIM_BASE'))
        self.assertEqual(g.qmk_entry(0x0101 | 0x1D, {})['mods'], 0x01)   # LCTL(KC_Z)
        self.assertEqual(g.qmk_entry(0x5221, {})['layer'], 1)            # MO(1)
        self.assertEqual(g.qmk_entry(0x0001, {})['kind'], 'trans')


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

    def test_qmk_names_old_and_new(self):
        # Keyball39 の keymap.c は QMK 0.22 (KC_BTN1 / RGB_TOG) と 0.34 (MS_BTN1 / UG_TOGG) のどちらの名前でも引ける
        from types import SimpleNamespace
        t = g.qmk_name_table(SimpleNamespace(ZMK_KEYCODES={}, V6_BASIC_NAMES={}), 'KBC_RST = QK_KB_0,')
        for i in range(1, 9):
            self.assertEqual(t[f'KC_BTN{i}'], 0xD0 + i)
            self.assertEqual(t[f'KC_MS_BTN{i}'], 0xD0 + i)
            self.assertEqual(t[f'MS_BTN{i}'], 0xD0 + i)
            self.assertEqual(t[f'QK_MOUSE_BUTTON_{i}'], 0xD0 + i)
        for old, new in [('RGB_TOG', 'UG_TOGG'), ('RGB_MOD', 'UG_NEXT'), ('RGB_RMOD', 'UG_PREV'),
                         ('RGB_HUI', 'UG_HUEU'), ('RGB_HUD', 'UG_HUED'), ('RGB_SAI', 'UG_SATU'),
                         ('RGB_SAD', 'UG_SATD'), ('RGB_VAI', 'UG_VALU'), ('RGB_VAD', 'UG_VALD')]:
            self.assertEqual(t[new], t[old], new)
        self.assertEqual(t['UG_TOGG'], 0x7820)
        self.assertEqual(t['KBC_RST'], 0x7E00)

    def test_keyball_layout_file(self):
        # QMK 0.34 の keyboard.json を優先し、無ければ QMK 0.22 の info.json を使う
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            kb39 = Path(d, 'qmk_firmware/keyboards/keyball/keyball39')
            kb39.mkdir(parents=True)
            src = g.Sources({'keyball': Path(d)})
            (kb39 / 'info.json').write_text('{}', encoding='utf-8')
            self.assertEqual(g.keyball_paths(src)['info'].name, 'info.json')
            (kb39 / 'keyboard.json').write_text('{}', encoding='utf-8')
            self.assertEqual(g.keyball_paths(src)['info'].name, 'keyboard.json')


@unittest.skipUnless(have_submodules(), 'submodule がありません (git submodule update --init)')
class TestGenerate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = g.Sources()
        cls.files = g.generate(cls.sources)
        cls.data = {k: json.loads(v) for k, v in cls.files.items()}
        cls.kd, cls.zv, cls.vd = g.import_docgen(cls.sources)

    def test_check_ignores_commit_only_changes(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(g.main(['--out-dir', d]), 0)
            p = Path(d, 'lism.json')
            text = p.read_text(encoding='utf-8')
            commit = json.loads(text)['sources'][0]['commit']
            p.write_text(text.replace(commit, '0' * 40), encoding='utf-8')
            self.assertEqual(g.main(['--check', '--out-dir', d]), 0)       # コミットだけ違う
            p.write_text(text.replace('"Mod-Tap"', '"Key Press"', 1), encoding='utf-8')
            self.assertEqual(g.main(['--check', '--out-dir', d]), 1)       # 内容が違う

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
        for name in [b['id'] for b in g.ZMK_BOARDS]:
            d = self.data[f'{name}.json']
            it = d['interactive']
            keys = it['trackball']['keys']
            self.assertEqual(keys['left']['scroll']['legend'], 'D', name)
            self.assertEqual(keys['left']['click']['legend'], 'F', name)
            self.assertEqual(keys['left']['shift']['usage'], 0xE1, name)
            self.assertEqual(keys['right']['scroll']['legend'], 'K', name)
            self.assert_release_keys(keys, name)
            self.assertEqual(keys['right']['after_timeout']['usage'], 0x0D, name)  # J
            self.assertEqual(it['trackball']['aml']['timeout_ms'], 10000, name)
            self.assertEqual(it['trackball']['aml']['threshold'], 10, name)
            self.assertEqual(keys['left']['scroll']['usage'], 0x07, name)   # D (AML が切れていれば文字)
            self.assertEqual(keys['right']['scroll']['usage'], 0x0E, name)  # K
            self.assertEqual(it['output_switch']['usb']['legend'], 'U', name)
            a = [t for t in it['taps'] if t['usage'] == 0x04]
            self.assertEqual(len(a), 1, name)                      # A (タップ)
            self.assertEqual(a[0]['hold_usage'], 0xE0, name)       # A (ホールド = 左 Ctrl)
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
        # カーソルの加速: ZMK はすべてのボールの listener に入っている
        for b in g.ZMK_BOARDS:
            for fw in self.data[f'{b["id"]}.json']['interactive']['trackball']['firmware']:
                self.assertEqual(fw['accel']['model'], 'zmk', b['id'])
                self.assertEqual(fw['accel']['label'], 'trackball_accel', b['id'])
        kb = self.data['keyball39.json']['interactive']['trackball']['firmware'][0]['accel']
        self.assertEqual(kb['model'], 'keyball')
        self.assertEqual(kb['clamp'], 127)
        kq = self.data['kq-mini.json']['interactive']['trackball']['firmware']
        self.assertEqual(kq[0]['accel'], kb)                 # KQ-mini 経由でも Keyball の加速
        self.assertIsNone(kq[1]['accel'])

    def test_scroll_keeps_aml(self):
        # LisM 基準: スクロール中も AML を延ばす (すべての ZMK の機種で ok)
        for b in g.ZMK_BOARDS:
            msgs = [c for c in self.data[f'{b["id"]}.json']['consistency'] if 'スクロール中' in c['message']]
            self.assertEqual([c['level'] for c in msgs], ['ok'], b['id'])

    def test_products(self):
        products = {b['id']: self.data[f'{b["id"]}.json']['device']['product'] for b in g.ZMK_BOARDS}
        self.assertEqual(products['lism'], 'LisM')
        self.assertEqual(products['roba'], 'roBa')
        self.assertEqual(products['torabo-tsuki-lp'], 'torabo-tsuki')
        self.assertEqual(self.data['lism.json']['physical']['layout_name'], '42-Key Layout')
        self.assertEqual(self.data['torabo-tsuki-lp.json']['physical']['layout_name'], 'L Layout')

    def assert_release_keys(self, keys: dict, name: str):
        # AML 中に修飾キーの位置をタップすると AML が切れ、BASE と同じ文字が出る
        self.assertEqual((keys['left']['release_ctrl']['usage'], keys['left']['release_shift']['usage']),
                         (0x04, 0x1D), name)                # A / Z
        self.assertEqual((keys['right']['release_ctrl']['usage'], keys['right']['release_shift']['usage']),
                         (0x2D, 0x38), name)                # - / /
        self.assertEqual(keys['left']['release_shift']['pos'], keys['left']['shift']['pos'], name)

    def test_keyball(self):
        v = self.data['keyball39.json']['readout']['via']
        self.assertEqual(v['layer_count'], 4)
        self.assertEqual(v['keymap'][0][0][0], 0x14)        # KC_Q
        self.assertEqual(v['keymap'][1][1][0], 0x01)        # KC_TRNS (A。押すと AML が切れる)
        self.assertEqual(v['keymap'][1][1][2], 0x5222)      # MO(2) (D)
        self.assertEqual(v['keymap'][2][1][0], 0xE0)        # KC_LCTL (A)
        self.assertEqual(v['keymap'][2][1][3], 0xD1)        # KC_BTN1 (F)
        self.assertEqual(v['keymap'][3][0][0], 0x7820)      # RGB_TOG
        self.assertEqual(v['keymap'][3][3][1], 0x7E00)      # KBC_RST
        self.assertEqual(v['status']['cpi'], 5)
        self.assertEqual(v['status']['scroll_div'], 5)
        self.assertEqual(v['status']['aml_timeout'], 10000)
        self.assertEqual(v['status']['format'], 2)
        self.assertEqual(v['status']['aml_threshold'], 10)
        for f in ('keyball39.json', 'kq-mini.json'):
            tb = self.data[f]['interactive']['trackball']['keys']
            self.assertEqual(tb['left']['shift']['usage'], 0xE1, f)
            self.assertEqual(tb['left']['scroll']['usage'], 0x07, f)
            self.assertEqual(self.data[f]['interactive']['trackball']['aml']['threshold'], 10, f)
            self.assert_release_keys(tb, f)
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

    def test_zmk_hold_tap(self):
        for name in [b['id'] for b in g.ZMK_BOARDS]:
            d = self.data[f'{name}.json']
            ht = d['interactive']['hold_tap']
            self.assertEqual(ht['engine'], 'zmk', name)
            for beh in ('mt', 'lt'):
                b = ht['behaviors'][beh]
                self.assertEqual((b['flavor'], b['tapping_term_ms'], b['quick_tap_ms']), ('balanced', 150, 0), name)
            self.assertIn(0, ht['layers'])
            keys = {k['pos']: k for k in ht['keys']}
            self.assertEqual(len(keys), d['readout']['zmk']['key_count'], name)
            a = [k for k in ht['keys'] if k['on']['0'].get('src', '').startswith('&mt LEFT_CONTROL A')]
            self.assertEqual(len(a), 1, name)
            e = a[0]['on']['0']
            self.assertEqual((e['hold']['usage'], e['tap']['usage'], e['tap']['label']), (0xE0, 0x04, 'A'), name)
            msgs = [c for c in d['consistency'] if c['message'].startswith('タップホールド &')]
            self.assertEqual({c['level'] for c in msgs}, {'ok'}, name)
        lism = {k['pos']: k for k in self.data['lism.json']['interactive']['hold_tap']['keys']}
        space = lism[34]['on']['0']
        self.assertEqual((space['behavior'], space['hold']['kind'], space['hold']['layer']), ('lt', 'mo', 2))
        # &lt で入る VIM_BASE の H は ← (&trans は書かず、下のレイヤーに落ちる)
        self.assertEqual(lism[15]['on']['2']['label'], '←')
        self.assertTrue(all(e['kind'] != 'trans' for k in lism.values() for e in k['on'].values()))

    def test_kq_hold_tap(self):
        ht = self.data['kq-mini.json']['interactive']['hold_tap']
        self.assertEqual(ht['engine'], 'qmk')
        self.assertEqual(ht['settings'], {'tapping_term': 150, 'tap_code_delay': 10, 'permissive_hold': 1,
                                          'hold_on_other_key_press': 0, 'retro_tapping': 0, 'quick_tap_term': 0,
                                          'chordal_hold': 0, 'flow_tap_term': 0})
        keys = {k['pos']: k for k in ht['keys']}
        a = keys[10]
        self.assertEqual((a['usage'], a['qmk_hand'], a['on']['0']['behavior']), (0x04, '*', 'MT'))
        self.assertEqual(keys[33]['on']['0']['hold']['kind'], 'mo')     # Space (LT)
        self.assertEqual([c['level'] for c in self.data['kq-mini.json']['consistency']], ['ok'])

    @unittest.skipUnless(KQ_VIL.exists(), 'vial-qmk-kq-mini の KEYMAP.vil がありません')
    def test_kq_mini_matches_firmware_vil(self):
        vil = json.loads(KQ_VIL.read_text(encoding='utf-8'))
        self.assertEqual(self.data['kq-mini.json']['readout']['vial']['keymap'], vil['layout'])


if __name__ == '__main__':
    unittest.main()
