"""tools/expected/behaviors.py (ZMK のビヘイビアのシミュレータとテストの手順) のテスト。

    python -m unittest discover -s tools/expected -v

キーマップの解析に zmk-keymap-docgen (submodule) を使うので、submodule が無いときは飛ばす。
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import behaviors as bh  # noqa: E402
import generate as g  # noqa: E402


def docgen():
    try:
        return g.import_docgen(g.Sources())
    except g.GenError:
        return None


DOCGEN = docgen()

# 位置: 0〜5 が左手、6〜11 が右手 (2 段 × 6 列)
FRAGMENT = r'''
#include <behaviors.dtsi>
#include <dt-bindings/zmk/keys.h>
#define BASE 0
#define NAV 1
#define VIS 2

/ {
    combos {
        compatible = "zmk,combos";
        combo_tab { key-positions = <0 1>; bindings = <&kp TAB>; };
        combo_nav { key-positions = <8 9>; bindings = <&kp HOME>; layers = <1>; };
    };
    macros {
        mac: mac {
            compatible = "zmk,behavior-macro";
            #binding-cells = <0>;
            bindings = <&kp HOME>, <&macro_wait_time 100>, <&kp LS(END)>, <&macro_wait_time 100>, <&kp LC(X)>;
            label = "MAC";
        };
        mac_s: mac_s {
            compatible = "zmk,behavior-macro";
            #binding-cells = <0>;
            bindings = <&kp LS(END)>, <&macro_wait_time 100>, <&kp LC(X)>;
        };
        mac_exit: mac_exit {
            compatible = "zmk,behavior-macro";
            #binding-cells = <0>;
            bindings = <&macro_release>, <&kp LSHIFT &kp RSHIFT>, <&macro_tap>, <&kp RIGHT>, <&to BASE>;
        };
    };
    behaviors {
        td_x: td_x {
            compatible = "zmk,behavior-tap-dance";
            #binding-cells = <0>;
            bindings = <&none>, <&mac>;
        };
        mm_inner: mm_inner {
            compatible = "zmk,behavior-mod-morph";
            #binding-cells = <0>;
            bindings = <&td_x>, <&mac_s>;
            mods = <(MOD_LSFT|MOD_RSFT)>;
        };
        mm_outer: mm_outer {
            compatible = "zmk,behavior-mod-morph";
            label = "MM_OUTER";
            #binding-cells = <0>;
            bindings = <&mm_inner>, <&kp PAGE_DOWN>;
            mods = <(MOD_LCTL|MOD_RCTL)>;
        };
        mm_u: mm_u {
            compatible = "zmk,behavior-mod-morph";
            #binding-cells = <0>;
            bindings = <&kp LC(Z)>, <&kp PAGE_UP>;
            mods = <(MOD_LCTL|MOD_RCTL)>;
        };
        mm_keep: mm_keep {
            compatible = "zmk,behavior-mod-morph";
            #binding-cells = <0>;
            bindings = <&kp A>, <&kp B>;
            mods = <(MOD_LSFT)>;
            keep-mods = <(MOD_LSFT)>;
        };
        mm_v: mm_v {
            compatible = "zmk,behavior-mod-morph";
            #binding-cells = <0>;
            bindings = <&to VIS>, <&kp X>;
            mods = <(MOD_LSFT|MOD_RSFT)>;
        };
    };
    keymap {
        compatible = "zmk,keymap";
        BASE_LAYER {
            bindings = <
&kp Q  &kp W   &kp E     &kp R      &kp T     &mo NAV        &kp Y  &kp U      &kp I    &kp O    &kp P   &kp L
&mt LCTRL A  &kp S  &kp D  &kp F  &lt NAV G  &kp Z           &kp H  &kp J      &kp K    &kp M    &kp N   &bootloader
            >;
        };
        NAV_LAYER {
            bindings = <
&mm_u  &mm_outer  &mm_keep  &mm_v  &kp N1  &trans          &kp LEFT  &kp N2  &kp N3  &kp N4  &kp N5  &trans
&kp LCTRL  &kp LSHIFT  &kp ESC  &trans  &trans  &trans    &kp DOWN  &trans  &trans  &trans  &trans  &trans
            >;
        };
        VIS_LAYER {
            bindings = <
&kp LS(LEFT)  &none  &none  &mac_exit  &none  &none      &kp F3  &none  &none  &none  &none  &none
&kp LCTRL  &kp LSHIFT  &none  &none  &none  &none          &none  &none  &none  &none  &none  &none
            >;
        };
    };
};
'''


def fragment_keys() -> list[dict]:
    keys = []
    for pos in range(24):
        row, col = divmod(pos, 12)
        x = col if col < 6 else col + 2
        keys.append({'pos': pos, 'x': float(x), 'y': float(row), 'w': 1, 'h': 1,
                     'hand': 'left' if col < 6 else 'right'})
    return keys


@unittest.skipIf(DOCGEN is None, 'submodule (zmk-keymap-docgen) がありません')
class TestSim(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        kd, zv, _ = DOCGEN
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'test.keymap'
            p.write_text(FRAGMENT, encoding='utf-8')
            cls.km = g.ZmkKeymap(kd, zv, p)
        cls.zv = zv
        cls.model = bh.Model.from_keymap(cls.km, lambda t: g.zmk_keycode(zv, t))

    def sim(self) -> bh.Sim:
        return bh.Sim(self.model)

    def strokes(self, sim: bh.Sim) -> list[tuple[int, int, int]]:
        return [(s.usage, s.mods, s.opt) for s in sim.out]

    def test_parse(self):
        b = self.model.behaviors
        self.assertEqual(b['mm_u'].mods, 0x11)
        self.assertEqual(b['mm_keep'].keep_mods, 0x02)
        self.assertEqual(b['mac_exit'].bindings, ['&macro_release', '&kp LSHIFT', '&kp RSHIFT', '&macro_tap',
                                                  '&kp RIGHT', '&to 0'])
        self.assertEqual(b['mm_outer'].device, 'MM_OUTER')
        self.assertEqual(b['mm_u'].device, 'mm_u')
        self.assertEqual([(c.name, c.positions, c.layers) for c in self.model.combos],
                         [('combo_tab', [0, 1], []), ('combo_nav', [8, 9], [1])])

    def test_mod_morph_masks_the_mods(self):
        s = self.sim()
        s.press(5)
        s.tap(0)
        self.assertEqual(self.strokes(s), [(0x1D, 0x01, 0)], '修飾なし: Ctrl+Z (暗黙の修飾)')
        s.press(12)  # Ctrl (NAV の &kp LCTRL)
        s.tap(0)
        self.assertEqual(self.strokes(s)[-1], (0x4B, 0, 0), 'Ctrl あり: PgUp (Ctrl はマスクされる)')

    def test_keep_mods(self):
        s = self.sim()
        s.press(5)
        s.press(13)  # Shift
        s.tap(2)
        self.assertEqual(self.strokes(s), [(0x05, 0x02, 0)], 'keep-mods の Shift は残る')

    def test_nested_morph_only_outer_mask(self):
        s = self.sim()
        s.press(5)
        s.press(12)
        s.press(13)
        s.tap(1)
        self.assertEqual(self.strokes(s), [(0x4E, 0x02, 0)], 'Ctrl+Shift → 外側の Ctrl だけマスク: Shift+PgDn')

    def test_morph_macro_optional_mods(self):
        s = self.sim()
        s.press(5)
        s.press(13)
        s.tap(1)
        self.assertEqual(self.strokes(s), [(0x4D, 0x02, 0), (0x1B, 0x01, 0x02)],
                         'Shift → [Shift+End, Ctrl+X (Shift は付いても可)]')

    def test_tap_dance(self):
        s = self.sim()
        s.press(5)
        s.tap(1, 2)
        self.assertEqual(self.strokes(s), [(0x4A, 0, 0), (0x4D, 0x02, 0), (0x1B, 0x01, 0)], '2 回でマクロ')
        s = self.sim()
        s.press(5)
        s.tap(1)
        s.tap(6)
        self.assertEqual(self.strokes(s), [(0x50, 0, 0)], '1 回 (&none) は、別のキーで決まって何も出ない')
        s = self.sim()
        s.press(5)
        s.tap(1)
        s.settle()
        self.assertEqual(self.strokes(s), [], '1 回 (&none) は、時間切れでも何も出ない')

    def test_to_layer_and_macro_release(self):
        s = self.sim()
        s.press(5)
        s.tap(3)
        self.assertEqual(s.layers, {0, 2}, '&to で VIS だけ (押したままの &mo NAV は消える)')
        s.release(5)
        self.assertEqual(s.layers, {0, 2}, '&mo を離しても VIS のまま')
        s.tap(0)
        s.press(13)  # VIS の Shift
        s.tap(3)
        self.assertEqual(s.layers, {0})
        s.tap(6)
        self.assertEqual(self.strokes(s), [(0x50, 0x02, 0), (0x4F, 0, 0), (0x1C, 0, 0)],
                         'マクロの &macro_release で Shift が離れ、押したままでも Y に Shift が付かない')

    def test_layer_tap_hold_and_trans(self):
        s = self.sim()
        s.press(16, hold=True)
        s.tap(6)
        s.tap(15)
        s.release(16)
        s.tap(16)
        self.assertEqual(self.strokes(s), [(0x50, 0, 0), (0x09, 0, 0), (0x0A, 0, 0)],
                         '&lt のホールドで NAV、&trans は BASE の F、タップで G')

    def test_hold_tap_hold(self):
        s = self.sim()
        s.press(12, hold=True)
        s.tap(6)
        self.assertEqual(self.strokes(s), [(0x1C, 0x01, 0)])

    def test_combo(self):
        s = self.sim()
        s.combo([0, 1])
        s.combo([8, 9])
        self.assertEqual(self.strokes(s), [(0x2B, 0, 0), (0x0C, 0, 0), (0x12, 0, 0)],
                         'BASE のコンボ / layers 付きのコンボは BASE では個別のキー')
        s = self.sim()
        s.press(5)
        s.combo([8, 9])
        self.assertEqual(self.strokes(s), [(0x4A, 0, 0)])

    def test_danger(self):
        s = self.sim()
        with self.assertRaises(bh.Danger):
            s.tap(23)

    def test_builder(self):
        names = ['BASE', 'NAV', 'VIS']
        b = bh.Builder(self.model, [dict(k, legend=self.km.legend(self.km.layers[0][k['pos']])) for k in fragment_keys()],
                       names, g.hid_label, {}, 'test')
        b.build()
        data = b.to_json()
        kinds = {s['kind'] for s in data['scenarios']}
        self.assertEqual(kinds, {'layer', 'hold_tap', 'mod_morph', 'tap_dance', 'to_layer', 'combo'})
        danger_adj = {p for p in range(24) if any(b.adjacent(p, 23) for _ in [0])} | {23}
        for sc in data['scenarios']:
            steps = [st['actions'] for st in sc['steps']]
            outs, layers, _ = b.run(steps)
            self.assertEqual(layers, {0}, f'{sc["title"]} は BASE で終わる')
            for st, out in zip(sc['steps'], outs):
                self.assertTrue(st['expect'], f'{sc["title"]}: {st["text"]} に期待する入力がある')
                self.assertEqual(st['expect'], [x.to_json() for x in out])
                for a in st['actions']:
                    self.assertNotIn(a.get('pos'), danger_adj, f'{st["text"]}: 押さないキーの隣')
        # Ctrl+Esc にならない (NAV の Ctrl + ESC は手順に入れない)
        texts = [st['expect_text'] for sc in data['scenarios'] for st in sc['steps']]
        self.assertNotIn('Ctrl+Esc', texts)
        td = [sc for sc in data['scenarios'] if sc['kind'] == 'tap_dance'][0]
        self.assertEqual(td['steps'][0]['expect_text'], 'Home、Shift+End、Ctrl+X')
        to = [sc for sc in data['scenarios'] if sc['kind'] == 'to_layer'][0]
        self.assertEqual([st['role'] for st in to['steps']], ['enter', 'exit'])
        self.assertEqual(to['steps'][-1]['expect_text'], '→、Q')
        self.assertIn('recover', to)
        self.assertEqual(to['recover']['check'], {'usage': 0x14, 'mods': 0})

    def test_denied(self):
        b = bh.Builder(self.model, [dict(k, legend='') for k in fragment_keys()], ['A', 'B', 'C'],
                       g.hid_label, {}, 'test')
        self.assertTrue(b.denied([bh.Stroke(0x29, 0x01)]))
        self.assertTrue(b.denied([bh.Stroke(0x2B, 0x40)]))
        self.assertTrue(b.denied([bh.Stroke(0x04, 0x08)]))
        self.assertFalse(b.denied([bh.Stroke(0x29, 0)]))


def load(name: str) -> dict:
    return json.loads((HERE / f'{name}.json').read_text(encoding='utf-8'))


class TestGenerated(unittest.TestCase):
    """コミットした期待値 (tools/expected/*.json) の手順の不変条件"""

    BOARDS = ['lism', 'kukey42', 'aroundfortyrb', 'pyuron', 'roba', 'torabo-tsuki-lp', 'kq-mini']

    def test_invariants(self):
        for name in self.BOARDS:
            data = load(name)
            beh = data['interactive']['behaviors']
            keys = {k['pos']: k for k in data['physical']['keys']}
            layers = {info['index']: info for info in beh['layers']}
            self.assertTrue(beh['scenarios'], name)
            for sc in beh['scenarios']:
                for st in sc['steps']:
                    where = f'{name}: {sc["title"]}: {st["text"]}'
                    self.assertTrue(st['expect'], where)
                    for s in st['expect']:
                        f = bh.fold_mods(s['mods'] | s.get('opt', 0))
                        self.assertFalse(f & bh.GUI, where)
                        self.assertFalse(f & bh.CTRL and s['usage'] == 0x29, where)
                    for a in st['actions']:
                        for p in a.get('positions', [a['pos']] if 'pos' in a else []):
                            self.assertIn(p, keys, where)
                            self.assertTrue(keys[p].get('present', True), where)
                            self.assertNotIn(p, layers[a.get('layer', st['layer'])]['danger'], where)
                    for layer in st['path']:
                        self.assertIn(layer, layers, where)
                if sc['kind'] == 'to_layer' or 'to_layer' in sc:
                    self.assertEqual(sc['steps'][-1]['path'][-1], 0, f'{name}: {sc["title"]} は BASE に戻る')
                    self.assertIn('recover', sc)
        kb = load('keyball39')['interactive']['behaviors']
        self.assertEqual(kb['scenarios'], [])
        self.assertTrue(kb['not_tested'])

    def test_lism_known_cases(self):
        """README・CLAUDE.md の説明と同じ動きになっている (LisM の VIM レイヤー)"""
        beh = load('lism')['interactive']['behaviors']
        by_text = {st['text']: st for sc in beh['scenarios'] for st in sc['steps']}
        self.assertEqual(by_text['「VIM_BASE」と「A (Ctrl)」を押したまま、「U」をタップ']['expect'],
                         [{'usage': 0x4B, 'mods': 0}])
        self.assertEqual(by_text['「VIM_BASE」と「Z (Shift)」を押したまま、「D」をタップ']['expect'],
                         [{'usage': 0x4D, 'mods': 0x02}, {'usage': 0x1B, 'mods': 0x01, 'opt': 0x02}])
        self.assertEqual(by_text['「VIM_BASE」を押したまま、「D」を素早く 2 回タップ']['expect'],
                         [{'usage': 0x4A, 'mods': 0}, {'usage': 0x4D, 'mods': 0x02}, {'usage': 0x1B, 'mods': 0x01}])
        self.assertEqual(by_text['「SYM」を押したまま、「Q」をタップ']['expect'], [{'usage': 0x1E, 'mods': 0}])
        self.assertEqual(beh['combos'], 0)
        self.assertEqual(beh['devices']['MM_VIM_U']['mods'], 0x11)
        self.assertEqual(beh['layers'][2]['devs'][6], 'MM_VIM_U')
        self.assertEqual(beh['layers'][0]['devs'][34], 'layer_tap')

    def test_func_layer_avoids_reset_and_bootloader(self):
        beh = load('lism')['interactive']['behaviors']
        func = [sc for sc in beh['scenarios'] if sc['kind'] == 'layer' and sc['layer'] == 6][0]
        taps = {a['label'] for st in func['steps'] for a in st['actions'] if a['op'] == 'tap'}
        self.assertTrue(taps <= {'F4', 'F5', 'F6', 'F7'}, taps)


if __name__ == '__main__':
    unittest.main()
