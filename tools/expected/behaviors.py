"""ZMK のビヘイビアを真似て、keyboard-check の実動作テストの手順と期待する入力を作る (generate.py から使う)。

キーボードの中身 (モッドモーフの mods、タップダンス、マクロ、&to の切り替え、ホールドタップの長押し) は
ZMK Studio でも読み出せないので、キーを押したとき PC に届く入力 (Raw Input) で確かめる。ここでは
ZMK v0.3.0 の動きを真似た小さなシミュレータで、手順 (どのキーを押したまま、どのキーをタップするか) ごとに
PC に届くはずの入力を求める。

真似る規則 (ZMK v0.3.0 のソースで確かめたもの):
  - レイヤー: 既定のレイヤー 0 は常に有効。キーを押すと、有効な最上位のレイヤーから &trans を飛ばして
    バインディングを決める。離すときは押したときのバインディングを離す
  - &mo / &lt (ホールド): 押している間だけレイヤーを有効にする
  - &to: 既定と行き先以外のレイヤーを無効にする (押したままの &mo を後で離しても何も起きない)
  - 修飾キー: 明示的な修飾は修飾ごとの押下カウントで持つ (&macro_release で離すと、利用者が押したままでも
    PC では離れる)。報告の修飾 = (明示 & ~マスク) | 押したキーの暗黙の修飾 (LC() など)
  - mod-morph: 押した時点の明示的な修飾に mods があればモーフ側を押し、mods (keep-mods を除く) をマスクする。
    離すとマスクを消す。入れ子では、修飾が合った外側のモーフのマスクだけが効く
  - tap-dance: 押すたびに数え、bindings の数に達したら (2 個なら 2 回目の押下で) 決まる。達しないときは
    時間切れか、別のキーを押したときに決まる
  - マクロ: tap / press / release のモード、&to、待ち。待ちの後の入力は、モーフのキーを先に離すとマスクが
    外れるので、そのとき押している修飾が付いても可 (opt) とする
  - コンボ: key-positions を同時に押す。layers があれば、有効な最上位のレイヤーがそこに含まれるときだけ

出力の「ストローク」は、修飾以外のキーを押した瞬間の {usage, mods (HID の修飾のバイト), opt (付いても可の修飾)}。
修飾キーだけの出入りは数えない (マスクで出入りすることがあるため)。
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

# ZMK の MOD_* (= HID の修飾のバイト)
MOD_BITS = {
    'MOD_LCTL': 0x01, 'MOD_LSFT': 0x02, 'MOD_LALT': 0x04, 'MOD_LGUI': 0x08,
    'MOD_RCTL': 0x10, 'MOD_RSFT': 0x20, 'MOD_RALT': 0x40, 'MOD_RGUI': 0x80,
}
# 左右をまとめた修飾 (判定は左右を区別しない)
CTRL, SHIFT, ALT, GUI = 1, 2, 4, 8
MOD_LABELS = [(CTRL, 'Ctrl'), (SHIFT, 'Shift'), (ALT, 'Alt'), (GUI, 'Win')]

# 押さないキー (押すとキーボードの状態や接続が変わる)
DANGER_HEADS = frozenset({'bt', 'out', 'sys_reset', 'bootloader', 'studio_unlock', 'soft_off', 'ext_power',
                          'rgb_ug', 'bl'})

# 標準ビヘイビアの ZMK のデバイス名 (app/dts/behaviors/*.dtsi のノード名。ログの binding name に出る)
BUILTIN_DEVICES = {
    'kp': 'key_press', 'mt': 'mod_tap', 'lt': 'layer_tap', 'mo': 'momentary_layer', 'to': 'to_layer',
    'tog': 'toggle_layer', 'sl': 'sticky_layer', 'sk': 'sticky_key', 'kt': 'key_toggle', 'trans': 'transparent',
    'none': 'none', 'bt': 'bluetooth', 'out': 'outputs', 'sys_reset': 'sysreset', 'bootloader': 'bootload',
    'mkp': 'mouse_key_press', 'caps_word': 'caps_word', 'key_repeat': 'key_repeat', 'gresc': 'grave_escape',
    'studio_unlock': 'studio_unlock',
}

# 代表キー・確認のキーに使う usage: 文字・数字・F1〜F12・ナビゲーション (Ins/Home/PgUp/Del/End/PgDn/矢印)・BS。
# 記号は JIS の PC や KQ-mini の JP/US の読み替えで変わり、GRAVE は IME を切り替えるので使わない
SAFE_USAGES = frozenset(list(range(0x04, 0x28)) + list(range(0x3A, 0x46)) + list(range(0x49, 0x53)) + [0x2A])
LETTERS = frozenset(range(0x04, 0x1E))

# 手順に入れない組み合わせ (ほかのウィンドウやシステムが反応する)
DENIED = [
    (CTRL, 0x29, 'Ctrl+Esc (スタートメニュー)'), (CTRL | SHIFT, 0x29, 'Ctrl+Shift+Esc (タスクマネージャー)'),
    (ALT, 0x2B, 'Alt+Tab'), (ALT, 0x3D, 'Alt+F4'), (ALT, 0x29, 'Alt+Esc'), (ALT, 0x2C, 'Alt+Space'),
    (CTRL | ALT, 0x4C, 'Ctrl+Alt+Del'),
]


class Unsupported(Exception):
    """真似できないビヘイビア (手順に入れない)"""


class Danger(Exception):
    """押さないキー、またはその隣のキーを押す手順"""


def fold_mods(mods: int) -> int:
    """HID の修飾のバイト → 左右をまとめた Ctrl / Shift / Alt / Win"""
    return (mods | (mods >> 4)) & 0x0F


def mods_label(mods: int) -> str:
    f = fold_mods(mods)
    return '+'.join(name for bit, name in MOD_LABELS if f & bit)


def is_modifier(usage: int) -> bool:
    return 0xE0 <= usage <= 0xE7


def split_binding(binding: str) -> tuple[str, list[str]]:
    parts = binding.split()
    return parts[0].lstrip('&'), parts[1:]


def split_behaviors(group: str) -> list[str]:
    """'<&kp LSHIFT &kp RSHIFT>' の中身 → ['&kp LSHIFT', '&kp RSHIFT']"""
    return [m.strip() for m in re.findall(r'&[^&]+', group) if m.strip()]


def parse_binding_groups(body: str) -> list[list[str]]:
    m = re.search(r'\bbindings\s*=\s*(.*?);', body, re.DOTALL)
    if not m:
        return []
    return [split_behaviors(g) for g in re.findall(r'<([^>]*)>', m.group(1))]


def parse_mod_expr(body: str, prop: str) -> int:
    m = re.search(r'(?<![\w-])' + re.escape(prop) + r'\s*=\s*<(.*?)>\s*;', body, re.DOTALL)
    if not m:
        return 0
    value = 0
    for tok in re.findall(r'MOD_[LR](?:CTL|SFT|ALT|GUI)', m.group(1)):
        value |= MOD_BITS[tok]
    return value


def parse_int_prop(body: str, prop: str) -> int | None:
    m = re.search(r'(?<![\w-])' + re.escape(prop) + r'\s*=\s*<\s*(\d+)\s*>', body)
    return int(m.group(1)) if m else None


@dataclass
class Behavior:
    name: str            # ノードラベル (キーマップの &name)
    node: str            # ノード名
    device: str          # ZMK のデバイス名 (label → ノード名)。ログの binding name
    compatible: str
    bindings: list[str]  # mod-morph / tap-dance: 各 binding。マクロ: 手順を平らにしたもの
    mods: int = 0
    keep_mods: int = 0
    tapping_term: int | None = None

    @property
    def kind(self) -> str:
        return {
            'zmk,behavior-mod-morph': 'mod_morph', 'zmk,behavior-tap-dance': 'tap_dance',
            'zmk,behavior-macro': 'macro', 'zmk,behavior-hold-tap': 'hold_tap',
        }.get(self.compatible, 'other')


@dataclass
class Combo:
    name: str
    positions: list[int]
    binding: str
    layers: list[int] = field(default_factory=list)
    timeout: int | None = None


def parse_custom(custom: dict[str, dict]) -> dict[str, Behavior]:
    out = {}
    for name, n in custom.items():
        body = n['body']
        cm = re.search(r'compatible\s*=\s*"([^"]+)"', body)
        compatible = cm.group(1) if cm else ''
        groups = parse_binding_groups(body)
        if compatible == 'zmk,behavior-macro':
            bindings = [b for g in groups for b in g]
        else:
            bindings = [g[0] for g in groups if g]
        out[name] = Behavior(
            name=name, node=n['node'], device=n['label'] or n['node'], compatible=compatible, bindings=bindings,
            mods=parse_mod_expr(body, 'mods'), keep_mods=parse_mod_expr(body, 'keep-mods'),
            tapping_term=parse_int_prop(body, 'tapping-term-ms'))
    return out


def parse_combos(kd, text: str) -> list[Combo]:
    content = kd.extract_named_block(text, 'combos')
    if not content:
        return []
    out = []
    i = 0
    pat = re.compile(r'([\w-]+)\s*\{')
    while True:
        m = pat.search(content, i)
        if not m:
            break
        rng = kd.find_balanced_block(content, m.end() - 1)
        if not rng:
            break
        body = content[rng[0]:rng[1]]
        i = rng[1] + 1
        km = re.search(r'key-positions\s*=\s*<([^>]*)>', body)
        groups = parse_binding_groups(body)
        if not km or not groups or not groups[0]:
            continue
        lm = re.search(r'(?<![\w-])layers\s*=\s*<([^>]*)>', body)
        out.append(Combo(name=m.group(1), positions=[int(x) for x in km.group(1).split()],
                         binding=groups[0][0], layers=[int(x) for x in lm.group(1).split()] if lm else [],
                         timeout=parse_int_prop(body, 'timeout-ms')))
    return out


class Model:
    """シミュレータに渡すキーマップ。layers[レイヤー][位置] = バインディングの文字列"""

    def __init__(self, layers: list[list[str]], behaviors: dict[str, Behavior], keycode, combos: list[Combo]):
        self.layers = layers
        self.behaviors = behaviors
        self.keycode = keycode
        self.combos = combos

    @classmethod
    def from_keymap(cls, km, keycode) -> 'Model':
        return cls(km.layers, parse_custom(km.custom), keycode, parse_combos(km.kd, km.text))

    def binding(self, layer: int, pos: int) -> str:
        return self.layers[layer][pos]

    def device(self, binding: str) -> str:
        head, _ = split_binding(binding)
        if head in self.behaviors:
            return self.behaviors[head].device
        return BUILTIN_DEVICES.get(head, head)


@dataclass
class Stroke:
    usage: int
    mods: int
    opt: int = 0

    def to_json(self) -> dict:
        d = {'usage': self.usage, 'mods': self.mods}
        if self.opt:
            d['opt'] = self.opt
        return d


class Sim:
    """ZMK の動きを真似る。press / release / tap / combo の後、out にストロークがたまる"""

    def __init__(self, model: Model):
        self.m = model
        self.layers = {0}
        self.mod_count = [0] * 8
        self.masked = 0
        self.out: list[Stroke] = []
        self.held: dict[int, tuple[str, bool]] = {}
        self.order: list[int] = []
        self.morph: dict[tuple[str, int], str] = {}
        self.td: dict | None = None
        self.macro_mask = 0
        self.in_macro = False
        self.macro_first = False

    # ---- 状態

    def explicit(self) -> int:
        return sum(1 << i for i in range(8) if self.mod_count[i] > 0)

    def top(self) -> int:
        return max(self.layers)

    def resolve(self, pos: int) -> tuple[int, str]:
        for layer in sorted(self.layers, reverse=True):
            b = self.m.binding(layer, pos)
            if split_binding(b)[0] != 'trans':
                return layer, b
        return 0, '&none'

    # ---- キー

    def press(self, pos: int, hold: bool = False) -> None:
        self._interrupt(pos)
        _, b = self.resolve(pos)
        self.held[pos] = (b, hold)
        self.order.append(pos)
        if self.td is not None and self.td['pos'] == pos:
            self.td['down'] = True
        self.invoke(b, pos, True, hold)

    def release(self, pos: int) -> None:
        b, hold = self.held.pop(pos)
        self.order.remove(pos)
        if self.td is not None and self.td['pos'] == pos:
            self.td['down'] = False
        self.invoke(b, pos, False, hold)

    def tap(self, pos: int, count: int = 1) -> None:
        for _ in range(count):
            self.press(pos)
            self.release(pos)

    def release_all(self) -> None:
        for pos in reversed(list(self.order)):
            self.release(pos)

    def settle(self) -> None:
        """時間がたった (タップダンスがタイマーで決まる)"""
        td = self.td
        if td is not None and td['pressed'] is None:
            b = td['beh'].bindings[td['count'] - 1]
            td['pressed'] = b
            self.invoke(b, td['pos'], True)
            if not td['down']:
                self.invoke(b, td['pos'], False)
                self.td = None

    def combo(self, positions: list[int]) -> None:
        self._interrupt(-1)
        top = self.top()
        for i, c in enumerate(self.m.combos):
            if sorted(c.positions) == sorted(positions) and (not c.layers or top in c.layers):
                self.invoke(c.binding, -1 - i, True)
                self.invoke(c.binding, -1 - i, False)
                return
        for p in positions:
            self.press(p)
        for p in positions:
            self.release(p)

    # ---- ビヘイビア

    def invoke(self, binding: str, pos: int, pressed: bool, hold: bool = False) -> None:
        head, args = split_binding(binding)
        if head in DANGER_HEADS:
            raise Danger(binding)
        if head == 'kp':
            self._kp(args[0], pressed)
        elif head == 'mt':
            self._kp(args[0] if hold else args[1], pressed)
        elif head == 'lt':
            if hold:
                self._layer(int(args[0]), pressed)
            else:
                self._kp(args[1], pressed)
        elif head == 'mo':
            self._layer(int(args[0]), pressed)
        elif head == 'to':
            if pressed:
                self.layers = {0, int(args[0])}
        elif head in ('none', 'trans'):
            pass
        elif head in self.m.behaviors:
            self._custom(self.m.behaviors[head], pos, pressed)
        else:
            raise Unsupported(binding)

    def _layer(self, layer: int, on: bool) -> None:
        if on:
            self.layers.add(layer)
        elif layer != 0:
            self.layers.discard(layer)

    def _kp(self, token: str, pressed: bool) -> None:
        v = self.m.keycode(token)
        page, usage, imods = (v >> 16) & 0xFF, v & 0xFFFF, (v >> 24) & 0xFF
        if page != 0x07:
            raise Unsupported(f'&kp {token}')
        if is_modifier(usage):
            i = usage - 0xE0
            if pressed:
                self.mod_count[i] += 1
            else:
                self.mod_count[i] = max(0, self.mod_count[i] - 1)
            return
        if not pressed:
            return
        explicit = self.explicit()
        mods = (explicit & ~self.masked) | imods
        opt = 0
        if self.in_macro and self.macro_first:
            # マクロの 2 つ目以降: モーフのキーを先に離すとマスクが外れる
            opt = explicit & self.macro_mask & ~mods
        self.out.append(Stroke(usage, mods, opt))
        if self.in_macro:
            self.macro_first = True

    def _custom(self, beh: Behavior, pos: int, pressed: bool) -> None:
        kind = beh.kind
        if kind == 'mod_morph':
            key = (beh.name, pos)
            if pressed:
                if self.explicit() & beh.mods:
                    self.masked = beh.mods & ~beh.keep_mods
                    chosen = beh.bindings[1]
                else:
                    chosen = beh.bindings[0]
                self.morph[key] = chosen
                self.invoke(chosen, pos, True)
            else:
                chosen = self.morph.pop(key)
                self.invoke(chosen, pos, False)
                self.masked = 0
        elif kind == 'tap_dance':
            if pressed:
                td = self.td
                if td is None or td['name'] != beh.name or td['pos'] != pos:
                    td = self.td = {'name': beh.name, 'pos': pos, 'beh': beh, 'count': 0, 'pressed': None,
                                    'down': True}
                td['count'] += 1
                if td['count'] >= len(beh.bindings):
                    b = beh.bindings[-1]
                    td['pressed'] = b
                    self.invoke(b, pos, True)
            else:
                td = self.td
                if td is not None and td['pressed'] is not None:
                    self.invoke(td['pressed'], pos, False)
                    self.td = None
        elif kind == 'macro':
            if pressed:
                self._macro(beh, pos)
        else:
            raise Unsupported(f'&{beh.name} ({beh.compatible})')

    def _macro(self, beh: Behavior, pos: int) -> None:
        saved = (self.in_macro, self.macro_mask, self.macro_first)
        self.in_macro, self.macro_mask, self.macro_first = True, self.masked, False
        mode = 'tap'
        for b in beh.bindings:
            head, _ = split_binding(b)
            if head in ('macro_tap', 'macro_press', 'macro_release'):
                mode = head[len('macro_'):]
                continue
            if head in ('macro_wait_time', 'macro_tap_time'):
                continue
            if head.startswith('macro_'):
                raise Unsupported(f'&{beh.name} の {b}')
            if mode in ('tap', 'press'):
                self.invoke(b, pos, True)
            if mode in ('tap', 'release'):
                self.invoke(b, pos, False)
        self.in_macro, self.macro_mask, self.macro_first = saved

    def _interrupt(self, pos: int) -> None:
        td = self.td
        if td is None or td['pos'] == pos or td['pressed'] is not None:
            return
        b = td['beh'].bindings[td['count'] - 1]
        td['pressed'] = b
        self.invoke(b, td['pos'], True)
        if not td['down']:
            self.invoke(b, td['pos'], False)
            self.td = None


# ============================================================================
# 手順 (シナリオ) の生成
# ============================================================================

def key_names(keys: list[dict]) -> dict[int, str]:
    """位置 → 物理キーの呼び名 (BASE の表示)。同じ表示のキーが複数あれば (左) (右 1) のように区別する"""
    names = {}
    groups: dict[str, list[dict]] = {}
    for k in keys:
        legend = k.get('legend') or ''
        names[k['pos']] = legend if legend else f'位置 {k["pos"]}'
        if legend and k.get('present', True):
            groups.setdefault(legend, []).append(k)
    for legend, ks in groups.items():
        if len(ks) < 2:
            continue
        for hand, hname in (('left', '左'), ('right', '右')):
            same = sorted((k for k in ks if k.get('hand') == hand), key=lambda k: (k['x'], k['y']))
            for i, k in enumerate(same):
                names[k['pos']] = f'{legend} ({hname}{" " + str(i + 1) if len(same) > 1 else ""})'
    return names


def describe_actions(actions: list[dict]) -> str:
    """アクションの並び → 「SYM」を押したまま、「Q」をタップ"""
    parts = []
    holds = []
    for a in actions:
        if a['op'] == 'hold':
            name = a['key'] if a['role'] == 'layer' else f"{a['key']} ({a['label']})"
            holds.append(f'「{name}」')
            continue
        if holds:
            parts.append('と'.join(holds) + 'を押したまま')
            holds = []
        if a['op'] == 'tap':
            c = a.get('count', 1)
            parts.append(f"「{a['key']}」を" + (f'素早く {c} 回タップ' if c > 1 else 'タップ'))
        elif a['op'] == 'release':
            parts.append('全部離して')
        elif a['op'] == 'combo':
            parts.append('「' + '」「'.join(a['keys']) + '」を同時に押す')
    return '、'.join(parts)


def stroke_label(s: Stroke | dict, hid_label) -> str:
    usage = s.usage if isinstance(s, Stroke) else s['usage']
    mods = s.mods if isinstance(s, Stroke) else s['mods']
    m = mods_label(mods)
    return (m + '+' if m else '') + hid_label(usage)


class Builder:
    """1 台のキーボードのシナリオを作る。

    keys: 期待値の physical.keys (pos, x, y, w, h, hand, legend)
    names: レイヤーの表示名 (別名)
    skip_layers: テストしないレイヤー (AML のレイヤーなど) → 理由
    """

    MAX_DEPTH = 3

    def __init__(self, model: Model, keys: list[dict], names: list[str], hid_label, skip_layers: dict[int, str],
                 board: str):
        self.m = model
        self.keys = keys
        self.names = names
        self.hid_label = hid_label
        self.skip_layers = skip_layers
        self.board = board
        self.n = len(keys)
        self.center = {k['pos']: (k['x'] + k['w'] / 2, k['y'] + k['h'] / 2) for k in keys}
        self.hand = {k['pos']: k['hand'] for k in keys}
        self.names_by_pos = key_names(keys)
        self.not_tested: list[dict] = []
        self.scenarios: list[dict] = []
        self.done_behaviors: set[str] = set()

    # ---- 表示

    def key_name(self, pos: int) -> str:
        return self.names_by_pos[pos]

    def short(self, binding: str, depth: int = 0) -> str:
        """キーの図に出す短い表示"""
        head, args = split_binding(binding)
        try:
            if head == 'kp':
                v = self.m.keycode(args[0])
                usage, imods = v & 0xFFFF, (v >> 24) & 0xFF
                m = mods_label(imods)
                return (m.replace('Ctrl', 'C').replace('Shift', 'S').replace('Alt', 'A').replace('Win', 'W') + '+'
                        if m else '') + self.hid_label(usage)
            if head == 'mt':
                return self.short(f'&kp {args[1]}') + '\n' + self.short(f'&kp {args[0]}')
            if head == 'lt':
                return self.short(f'&kp {args[1]}') + '\n' + self.names[int(args[0])]
            if head == 'mo':
                return self.names[int(args[0])]
            if head == 'to':
                return '→' + self.names[int(args[0])]
            if head == 'none':
                return ''
            if head == 'trans':
                return '▽'
            if head == 'mkp':
                return args[0] if args else 'MB'
            if head == 'bt':
                return ' '.join(args).replace('BT_', '')
            if head == 'out':
                return args[0].replace('OUT_', '') if args else 'OUT'
            if head == 'sys_reset':
                return 'RESET'
            if head == 'bootloader':
                return 'BOOT'
            beh = self.m.behaviors.get(head)
            if beh is not None and depth < 6:
                if beh.kind == 'mod_morph' and len(beh.bindings) >= 2:
                    a = self.short(beh.bindings[0], depth + 1).split('\n')[0]
                    b = self.short(beh.bindings[1], depth + 1).split('\n')[0]
                    return f'{a}\n{mods_label(beh.mods)}:{b}' if a else f'{mods_label(beh.mods)}:{b}'
                if beh.kind == 'tap_dance':
                    parts = [self.short(x, depth + 1).split('\n')[0] for x in beh.bindings]
                    return ' / '.join(f'×{i + 1}:{p}' for i, p in enumerate(parts) if p)
                if beh.kind == 'macro':
                    return re.sub(r'^macro_(vim_)?', '', beh.name)
        except Exception:  # noqa: BLE001  表示だけなので、分からないものはそのまま出す
            pass
        return head

    def layer_info(self) -> list[dict]:
        out = []
        for i, layer in enumerate(self.m.layers):
            danger = [p for p, b in enumerate(layer) if split_binding(b)[0] in DANGER_HEADS]
            out.append({'index': i, 'name': self.names[i], 'legends': [self.short(b) for b in layer],
                        'danger': danger, 'devs': [self.m.device(b) for b in layer]})
        return out

    # ---- シミュレーション

    def run(self, steps: list[list[dict]]) -> tuple[list[list[Stroke]], set[int], Sim]:
        """手順 (アクションの並び) を順に実行する。手順の終わりに全部離して時間を置く"""
        sim = Sim(self.m)
        outs = []
        for actions in steps:
            start = len(sim.out)
            for a in actions:
                self._check_safe(sim, a)
                op = a['op']
                if op == 'hold':
                    sim.press(a['pos'], hold=True)
                elif op == 'tap':
                    sim.tap(a['pos'], a.get('count', 1))
                elif op == 'release':
                    sim.release_all()
                    sim.settle()
                elif op == 'combo':
                    sim.combo(a['positions'])
                else:
                    raise ValueError(op)
            sim.release_all()
            sim.settle()
            outs.append(sim.out[start:])
        return outs, set(sim.layers), sim

    def danger_now(self, sim: Sim) -> set[int]:
        return {p for p in range(self.n) if split_binding(sim.resolve(p)[1])[0] in DANGER_HEADS}

    def adjacent(self, a: int, b: int) -> bool:
        (ax, ay), (bx, by) = self.center[a], self.center[b]
        return abs(ax - bx) < 1.5 and abs(ay - by) < 1.5

    def _check_safe(self, sim: Sim, action: dict) -> None:
        positions = action['positions'] if action['op'] == 'combo' else ([action['pos']] if 'pos' in action else [])
        danger = self.danger_now(sim)
        for p in positions:
            if p in danger or any(self.adjacent(p, d) for d in danger):
                raise Danger(f'位置 {p} は押さないキー (またはその隣)')
            if action['op'] == 'hold':
                _, b = sim.resolve(p)
                head, args = split_binding(b)
                if head in ('kp', 'mt'):
                    tok = args[0]
                    usage = self.m.keycode(tok) & 0xFFFF
                    if usage in (0xE2, 0xE3, 0xE6, 0xE7):
                        raise Danger('Win / Alt を押したままにしない')

    def denied(self, strokes: list[Stroke]) -> str | None:
        for s in strokes:
            f = fold_mods(s.mods | s.opt)
            if f & GUI or s.usage in (0xE3, 0xE7):
                return 'Win キーの組み合わせ'
            for mods, usage, what in DENIED:
                if s.usage == usage and (f & mods) == mods:
                    return what
        return None

    def try_run(self, steps):
        try:
            outs, layers, sim = self.run(steps)
        except (Danger, Unsupported):
            return None
        if any(self.denied(o) for o in outs):
            return None
        return outs, layers, sim

    # ---- アクション

    def act_hold(self, sim_state: Sim, pos: int, role: str) -> dict:
        _, b = sim_state.resolve(pos)
        head, args = split_binding(b)
        if role == 'layer':
            label = self.names[int(args[0])] if head in ('mo', 'lt') else self.short(b)
        else:
            label = self.short(f'&kp {args[0]}') if head in ('kp', 'mt') else self.short(b)
        return {'op': 'hold', 'pos': pos, 'role': role, 'key': self.key_name(pos), 'label': label,
                'layer': sim_state.top()}

    def act_tap(self, sim_state: Sim, pos: int, count: int = 1, role: str = 'key') -> dict:
        _, b = sim_state.resolve(pos)
        a = {'op': 'tap', 'pos': pos, 'key': self.key_name(pos), 'label': self.short(b).split('\n')[0],
             'layer': sim_state.top(), 'role': role}
        if count != 1:
            a['count'] = count
        return a

    def state_after(self, actions: list[dict]) -> Sim:
        """アクションを実行し、押したままの状態の Sim を返す (離さない)"""
        sim = Sim(self.m)
        for a in actions:
            if a['op'] == 'hold':
                sim.press(a['pos'], hold=True)
            elif a['op'] == 'tap':
                sim.tap(a['pos'], a.get('count', 1))
            elif a['op'] == 'release':
                sim.release_all()
                sim.settle()
        return sim

    # ---- レイヤーのたどり方

    def momentary_paths(self, prefix: list[dict]) -> dict[tuple[frozenset, int], list[dict]]:
        """prefix (&to で入る手順など) の後、&mo / &lt を押したままたどれる状態。
        (有効なレイヤー, 最後に押したレイヤーキー) → 押したままにするアクションの並び"""
        found: dict[tuple[frozenset, int], list[dict]] = {}
        frontier: list[list[dict]] = [[]]
        for _ in range(self.MAX_DEPTH):
            nxt = []
            for path in frontier:
                sim = self.state_after(prefix + path)
                held = {a['pos'] for a in path}
                n_lt = sum(1 for a in path if a.get('lt'))
                for pos in range(self.n):
                    if pos in held:
                        continue
                    _, b = sim.resolve(pos)
                    head, args = split_binding(b)
                    if head not in ('mo', 'lt'):
                        continue
                    layer = int(args[0])
                    if layer in sim.layers:
                        continue
                    is_lt = head == 'lt'
                    if is_lt and n_lt >= 1:
                        continue  # &lt が 2 つ重なると、タイマー頼みになる
                    a = self.act_hold(sim, pos, 'layer')
                    if is_lt:
                        a['lt'] = True
                    new = path + [a]
                    layers = frozenset(sim.layers | {layer})
                    key = (layers, pos)
                    old = found.get(key)
                    score = (len(new), sum(1 for x in new if x.get('lt')))
                    if old is None or score < (len(old), sum(1 for x in old if x.get('lt'))):
                        found[key] = new
                        nxt.append(new)
            frontier = nxt
        return found

    @staticmethod
    def path_score(holds: list[dict]) -> tuple:
        return (len(holds), sum(1 for a in holds if a.get('lt')), [a['pos'] for a in holds])

    def reps(self, prefix: list[dict], holds: list[dict], count: int, exclude: set[int] = frozenset()) -> list[int]:
        """そのレイヤーの代表キー (レイヤー自身に書かれた &kp の文字・数字・矢印など。BASE と出力が違うものを優先、左右から)"""
        sim = self.state_after(prefix + holds)
        top = sim.top()
        held = {a['pos'] for a in holds} | set(exclude)
        # その下のレイヤー (top が無いとき) と出力が違うキーを優先する
        under = Sim(self.m)
        under.layers = set(sim.layers) - {top} or {0}
        cands = []
        for pos in range(self.n):
            if pos in held:
                continue
            layer, b = sim.resolve(pos)
            head, args = split_binding(b)
            if layer != top or head != 'kp':
                continue
            try:
                v = self.m.keycode(args[0])
            except Exception:  # noqa: BLE001
                continue
            usage, imods = v & 0xFFFF, (v >> 24) & 0xFF
            if usage not in SAFE_USAGES or (v >> 16) & 0xFF != 0x07:
                continue
            r = self.try_run([prefix + holds + [self.act_tap(sim, pos)]])
            if r is None:
                continue
            outs = r[0][0]
            if len(outs) < 1:
                continue
            _, bb = under.resolve(pos)
            same = bb == b
            cands.append(((1 if same else 0, 1 if imods else 0, 0 if usage in LETTERS else 1, pos), pos))
        cands.sort()
        if not cands or count == 1:
            return [cands[0][1]] if cands else []
        # 2 つ目からは、下のレイヤーと出力が違うキーだけ (同じなら確かめる意味が薄い)
        picked = [cands[0][1]]
        other = 'right' if self.hand[picked[0]] == 'left' else 'left'
        rest = [pos for key, pos in cands[1:] if key[0] == 0]
        rest.sort(key=lambda p: 0 if self.hand[p] == other else 1)
        return picked + rest[:count - 1]

    def base_stroke(self) -> dict:
        """BASE の確かめのキーをタップしたときの入力 (BASE に戻せたかの確認)"""
        sim = Sim(self.m)
        sim.tap(self.base_key)
        return sim.out[0].to_json()

    def base_check_key(self) -> int:
        """BASE に戻ったことを確かめるキー (BASE の文字のキー)"""
        sim = Sim(self.m)
        for pos in range(self.n):
            _, b = sim.resolve(pos)
            head, args = split_binding(b)
            if head == 'kp' and (self.m.keycode(args[0]) & 0xFFFF) in LETTERS:
                return pos
        raise ValueError('BASE に文字のキーがありません')

    # ---- 手順の作成

    def step(self, actions: list[dict], strokes: list[Stroke], path: list[int], text: str, note: str = '',
             src: str = '', td_ms: int | None = None, role: str = 'test') -> dict:
        layer = path[-1] if path else 0
        s = {'role': role, 'text': text, 'actions': actions, 'path': path, 'layer': layer,
             'expect': [x.to_json() for x in strokes],
             'expect_text': '、'.join(stroke_label(x, self.hid_label) for x in strokes) or '(何も入力されない)'}
        if note:
            s['note'] = note
        if src:
            s['src'] = src
        if td_ms:
            s['td_ms'] = td_ms
        return s

    def describe(self, actions: list[dict]) -> str:
        return describe_actions(actions)

    def path_of(self, sim_states: list[int]) -> list[int]:
        out = []
        for layer in sim_states:
            if not out or out[-1] != layer:
                out.append(layer)
        return out

    def layer_path(self, prefix: list[dict], holds: list[dict]) -> list[int]:
        path = [0]
        sim = Sim(self.m)
        for a in prefix + holds:
            if a['op'] == 'hold':
                sim.press(a['pos'], hold=True)
            elif a['op'] == 'tap':
                sim.tap(a['pos'], a.get('count', 1))
            elif a['op'] == 'release':
                sim.release_all()
                sim.settle()
            path.append(sim.top())
        return self.path_of(path)

    # ---- 種類ごと

    def build(self) -> None:
        self.base_key = self.base_check_key()
        base_paths = self.momentary_paths([])
        self.build_layers(base_paths)
        self.build_hold_taps()
        contexts = self.contexts(base_paths)
        self.build_to_layers(contexts)
        self.build_morphs_and_tds(contexts)
        self.build_combos(base_paths)
        for layer, why in sorted(self.skip_layers.items()):
            self.not_tested.append({'what': f'{self.names[layer]} レイヤー', 'reason': why})

    def build_layers(self, paths) -> None:
        by_layer: dict[int, list[tuple]] = {}
        for (layers, last), holds in paths.items():
            top = max(layers)
            if top in self.skip_layers:
                continue
            by_layer.setdefault(top, []).append((len(holds), last, holds))
        for top in sorted(by_layer):
            entries = sorted(by_layer[top], key=lambda e: (e[0], sum(1 for a in e[2] if a.get('lt')), e[1]))
            # 入り方 (最後のレイヤーキー) ごとに 1 つ
            seen = set()
            steps = []
            for i, (_, last, holds) in enumerate(entries):
                if last in seen:
                    continue
                seen.add(last)
                for pos in self.reps([], holds, 2 if not steps else 1):
                    sim = self.state_after(holds)
                    actions = holds + [self.act_tap(sim, pos)]
                    r = self.try_run([actions])
                    if r is None:
                        continue
                    _, b = sim.resolve(pos)
                    path = self.layer_path([], holds)
                    steps.append(self.step(actions, r[0][0], path, self.describe(actions),
                                           f'{self.names[top]} レイヤーの「{self.short(b)}」({b})', b))
            if not steps:
                self.not_tested.append({'what': f'{self.names[top]} レイヤー', 'reason': '確かめられる安全なキーがない'})
                continue
            self.scenarios.append({'id': f'layer-{top}', 'kind': 'layer', 'title': f'{self.names[top]} レイヤー',
                                   'layer': top, 'steps': steps})

    def build_hold_taps(self) -> None:
        sim = Sim(self.m)
        steps = []
        for pos in range(self.n):
            _, b = sim.resolve(pos)
            head, args = split_binding(b)
            if head != 'mt':
                continue
            mod = self.m.keycode(args[0]) & 0xFFFF
            if mod in (0xE2, 0xE3, 0xE6, 0xE7):
                self.not_tested.append({'what': f'「{self.key_name(pos)}」の長押し ({b})', 'reason': 'Win / Alt は押したままにしない'})
                continue
            other = 'right' if self.hand[pos] == 'left' else 'left'
            row = self.center[pos][1]
            partners = []
            for p in range(self.n):
                if self.hand[p] != other:
                    continue
                _, pb = sim.resolve(p)
                ph, pa = split_binding(pb)
                if ph != 'kp' or (self.m.keycode(pa[0]) & 0xFFFF) not in LETTERS:
                    continue
                partners.append((abs(self.center[p][1] - row), p))
            for _, p in sorted(partners):
                hold = self.act_hold(sim, pos, 'mod')
                actions = [hold, self.act_tap(sim, p)]
                r = self.try_run([actions])
                if r is None or len(r[0][0]) != 1:
                    continue
                steps.append(self.step(actions, r[0][0], [0], self.describe(actions),
                                       f'「{self.key_name(pos)}」を長押しすると {hold["label"]} になる ({b})', b))
                break
        if steps:
            self.scenarios.append({'id': 'hold-tap', 'kind': 'hold_tap', 'title': '長押し (mod-tap)', 'layer': 0,
                                   'steps': steps})

    def contexts(self, base_paths) -> list[dict]:
        """モッドモーフ・タップダンスを探す状態: BASE から押したままたどる状態と、&to で入るレイヤー"""
        ctxs = [{'prefix': [], 'holds': [], 'to': None}]
        best: dict[frozenset, list[dict]] = {}
        for (layers, _), holds in base_paths.items():
            if max(layers) in self.skip_layers:
                continue
            old = best.get(layers)
            if old is None or self.path_score(holds) < self.path_score(old):
                best[layers] = holds
        for layers in sorted(best, key=lambda s: (len(best[s]), sorted(s))):
            ctxs.append({'prefix': [], 'holds': best[layers], 'to': None})
        self.base_contexts = list(ctxs)
        # &to で入るレイヤー
        self.to_entries: dict[int, list[dict]] = {}
        for ctx in list(ctxs):
            sim = self.state_after(ctx['holds'])
            held = {a['pos'] for a in ctx['holds']}
            for pos in range(self.n):
                if pos in held:
                    continue
                for mods in self.mod_cases(sim, pos, held):
                    actions = ctx['holds'] + mods + [self.act_tap(sim, pos)]
                    r = self.try_run([actions])
                    if r is None:
                        continue
                    layers = r[1]
                    if layers == {0}:
                        continue
                    to = max(layers)
                    if to in self.skip_layers:
                        continue
                    _, b = sim.resolve(pos)
                    entry = {'actions': actions, 'strokes': r[0][0], 'binding': b, 'mods': [m['label'] for m in mods],
                             'path': self.layer_path([], ctx['holds']) + [to]}
                    lst = self.to_entries.setdefault(to, [])
                    if any(e['binding'] == b and e['mods'] == entry['mods'] for e in lst):
                        continue
                    lst.append(entry)
        for to in sorted(self.to_entries):
            entries = self.to_entries[to]
            entries.sort(key=lambda e: (len(e['mods']), len(e['strokes']), len(e['actions'])))
            primary = entries[0]
            prefix = primary['actions'] + [{'op': 'release'}]
            sim = self.state_after(prefix)
            ctxs.append({'prefix': prefix, 'holds': [], 'to': to, 'entry': primary})
            for (layers, _), holds in self.momentary_paths(prefix).items():
                if max(layers) in self.skip_layers or max(layers) == to:
                    continue
                if not any(c['to'] == to and [a['pos'] for a in c['holds']] == [a['pos'] for a in holds] for c in ctxs):
                    ctxs.append({'prefix': prefix, 'holds': holds, 'to': to, 'entry': primary})
        return ctxs

    def exits(self, prefix: list[dict], to: int) -> list[dict]:
        """&to のレイヤーから BASE に戻るキー (バインディングごとに 1 つ)"""
        sim = self.state_after(prefix)
        out = []
        for pos in range(self.n):
            _, b = sim.resolve(pos)
            if any(e['binding'] == b for e in out):
                continue
            act = self.act_tap(sim, pos, role='exit')
            r = self.try_run([prefix, [act]])
            if r is None or r[1] != {0}:
                continue
            out.append({'actions': [act], 'strokes': r[0][1], 'binding': b, 'pos': pos})
        # ほかのアプリに届いても害の無い出口 (矢印など、Ctrl なし) を先に
        out.sort(key=lambda e: (0 if all(s.usage in range(0x49, 0x53) and not fold_mods(s.mods) & CTRL
                                         for s in e['strokes']) else 1, len(e['strokes']), e['pos']))
        return out

    def mod_sources(self, sim: Sim, mask: int, exclude: set[int]) -> list[int]:
        """mask の修飾になるキー (&kp LCTRL など)。左の修飾を優先。Win / Alt は使わない"""
        out = []
        for pos in range(self.n):
            if pos in exclude:
                continue
            _, b = sim.resolve(pos)
            head, args = split_binding(b)
            if head not in ('kp', 'mt'):
                continue
            usage = self.m.keycode(args[0]) & 0xFFFF
            if not is_modifier(usage) or usage in (0xE2, 0xE3, 0xE6, 0xE7):
                continue
            bit = 1 << (usage - 0xE0)
            if bit & mask:
                out.append((0 if head == 'kp' else 1, 0 if usage < 0xE4 else 1, pos))
        return [p for *_, p in sorted(out)]

    def morph_chain(self, binding: str) -> list[Behavior]:
        chain = []
        head, _ = split_binding(binding)
        while head in self.m.behaviors and self.m.behaviors[head].kind == 'mod_morph' and len(chain) < 4:
            beh = self.m.behaviors[head]
            chain.append(beh)
            head, _ = split_binding(beh.bindings[0])
        return chain

    def mod_cases(self, sim: Sim, pos: int, held: set[int]) -> list[list[dict]]:
        """モーフの分岐ごとの、押したままにする修飾キー ([] = 修飾なし)"""
        _, b = sim.resolve(pos)
        cases: list[list[dict]] = [[]]
        used = 0
        for beh in self.morph_chain(b):
            mask = beh.mods & ~used
            used |= beh.mods
            srcs = self.mod_sources(sim, mask, held | {pos})
            if srcs:
                cases.append([self.act_hold(sim, srcs[0], 'mod')])
        return cases

    def cleanup(self, prefix_state: list[dict], to: int) -> dict:
        ex = self.exits(prefix_state, to)
        if not ex:
            raise ValueError(f'{self.names[to]} から BASE に戻るキーがありません')
        return ex[0]

    def build_to_layers(self, ctxs) -> None:
        sim_base = Sim(self.m)
        base_act = self.act_tap(sim_base, self.base_key, role='check')
        for to in sorted(self.to_entries):
            entries = self.to_entries[to]
            primary = entries[0]
            prefix = primary['actions'] + [{'op': 'release'}]
            exits = self.exits(prefix, to)
            if not exits:
                self.not_tested.append({'what': f'{self.names[to]} レイヤー (&to)', 'reason': 'BASE に戻るキーがない'})
                continue
            nested = [c for c in ctxs if c['to'] == to and c['holds']]
            for i in range(max(len(entries), len(exits))):
                entry = entries[i % len(entries)]
                ex = exits[i % len(exits)]
                enter = entry['actions'] + [{'op': 'release'}]
                sim = self.state_after(enter)
                reps = self.reps(enter, [], 1)
                if not reps:
                    continue
                test = [self.act_tap(sim, reps[0])]
                steps_actions = [enter + test]
                labels = []
                if i == 0:
                    for c in nested:
                        r2 = self.reps(c['prefix'], c['holds'], 1)
                        if r2:
                            nsim = self.state_after(c['prefix'] + c['holds'])
                            steps_actions.append(c['holds'] + [self.act_tap(nsim, r2[0])])
                            labels.append(c)
                final = [dict(ex['actions'][0]), dict(base_act)]
                steps_actions.append(final)
                r = self.try_run(steps_actions)
                if r is None or r[1] != {0}:
                    continue
                outs = r[0]
                steps = []
                e_bind = entry['binding']
                mods = '・'.join(entry['mods'])
                steps.append(self.step(enter + test, outs[0], entry['path'], self.describe(enter + test),
                                       f'{e_bind}{" (" + mods + ")" if mods else ""} で {self.names[to]} に切り替わり、'
                                       f'離した後も「{self.key_name(reps[0])}」が {self.names[to]} の「{test[0]["label"]}」になる',
                                       e_bind, role='enter'))
                for j, c in enumerate(labels):
                    acts = steps_actions[1 + j]
                    path = self.layer_path(c['prefix'], c['holds'])
                    steps.append(self.step(acts, outs[1 + j], path, self.describe(acts),
                                           f'{self.names[to]} から {self.names[path[-1]]} レイヤー', ''))
                steps.append(self.step(final, outs[-1], [to, 0], self.describe(final),
                                       f'{ex["binding"]} で BASE に戻り、「{self.key_name(self.base_key)}」が BASE の文字になる',
                                       ex['binding'], role='exit'))
                self.scenarios.append({'id': f'to-{to}-{i + 1}', 'kind': 'to_layer',
                                       'title': f'{self.names[to]} への切り替え ({i + 1})', 'layer': to,
                                       'to_layer': to, 'steps': steps,
                                       'recover': {'actions': [dict(exits[0]['actions'][0]), dict(base_act)],
                                                   'text': self.describe([exits[0]['actions'][0], base_act]),
                                                   'check': self.base_stroke()}})

    def build_morphs_and_tds(self, ctxs) -> None:
        sim_base = Sim(self.m)
        base_act = self.act_tap(sim_base, self.base_key, role='check')
        for ctx in ctxs:
            prefix = ctx['prefix']
            sim = self.state_after(prefix + ctx['holds'])
            held = {a['pos'] for a in ctx['holds']}
            path = self.layer_path(prefix, ctx['holds'])
            for pos in range(self.n):
                if pos in held:
                    continue
                layer, b = sim.resolve(pos)
                head, _ = split_binding(b)
                beh = self.m.behaviors.get(head)
                if beh is None or head in self.done_behaviors:
                    continue
                if beh.kind == 'mod_morph':
                    self.done_behaviors.add(head)
                    self.build_morph(ctx, sim, pos, b, path, held, base_act)
                # モーフの修飾なし側をたどった先のタップダンス
                tail = b
                for m in self.morph_chain(b):
                    tail = m.bindings[0]
                th, _ = split_binding(tail)
                tbeh = self.m.behaviors.get(th)
                if tbeh is not None and tbeh.kind == 'tap_dance' and th not in self.done_behaviors:
                    self.done_behaviors.add(th)
                    self.build_td(ctx, sim, pos, b, tbeh, path, base_act)

    def finish(self, ctx: dict, steps_actions: list[list[dict]], base_act: dict):
        """&to のレイヤーの中のテストなら、最後に BASE へ戻る手順を足して実行する"""
        extra = None
        if ctx['to'] is not None:
            ex = self.cleanup(ctx['prefix'], ctx['to'])
            extra = [dict(ex['actions'][0]), dict(base_act)]
            steps_actions = steps_actions + [extra]
        r = self.try_run(steps_actions)
        if r is None or r[1] != {0}:
            return None, extra
        return r, extra

    def build_morph(self, ctx, sim, pos, binding, path, held, base_act) -> None:
        beh = self.m.behaviors[split_binding(binding)[0]]
        cases = self.mod_cases(sim, pos, held)
        steps_actions = []
        notes = []
        for mods in cases:
            actions = ctx['holds'] + mods + [self.act_tap(sim, pos)]
            if not steps_actions and ctx['to'] is not None:
                actions = ctx['prefix'] + actions
            r = self.try_run([ctx['prefix'] + ctx['holds'] + mods + [self.act_tap(sim, pos)]] if ctx['to'] is not None
                             else [actions])
            if r is None:
                continue
            strokes, layers = r[0][0], r[1]
            if not strokes or layers != ({0} if ctx['to'] is None else {0, ctx['to']}):
                continue  # &none の分岐、タップダンスの 1 回、&to (レイヤーの切り替えで確かめる)
            if mods and self.is_noop_morph(ctx, sim, pos, mods, strokes):
                continue
            steps_actions.append(actions)
            what = '修飾なし' if not mods else f'{mods[0]["label"]} あり'
            notes.append(f'{beh.name}: {what} → {self.morph_choice(binding, sim, mods)}')
        if not steps_actions:
            return
        r, extra = self.finish(ctx, steps_actions, base_act)
        if r is None:
            return
        steps = []
        for i, acts in enumerate(steps_actions):
            steps.append(self.step(acts, r[0][i], path, self.describe(acts), notes[i], binding))
        if extra is not None:
            steps.append(self.step(extra, r[0][-1], [ctx['to'], 0], self.describe(extra),
                                   'BASE に戻す (戻ったことを確かめる)', '', role='cleanup'))
        sc = {'id': f'morph-{beh.name}', 'kind': 'mod_morph', 'title': f'モッドモーフ {beh.name}',
              'behavior': beh.name, 'layer': path[-1], 'steps': steps}
        self.add_recover(sc, ctx, base_act)
        self.scenarios.append(sc)

    def morph_choice(self, binding: str, sim: Sim, mods: list[dict]) -> str:
        """修飾キーを押したままのとき、モーフの入れ子のどの binding になるか"""
        bits = 0
        for a in mods:
            _, b = sim.resolve(a['pos'])
            head, args = split_binding(b)
            usage = self.m.keycode(args[0]) & 0xFFFF
            bits |= 1 << (usage - 0xE0)
        chain = self.morph_chain(binding)
        for beh in chain:
            if bits & beh.mods:
                return beh.bindings[1]
        return chain[-1].bindings[0] if chain else binding

    def is_noop_morph(self, ctx, sim, pos, mods, strokes) -> bool:
        """モーフ側の出力が、モーフが無くても同じ (修飾キー + 修飾なし側) なら確かめる意味がない"""
        _, b = sim.resolve(pos)
        chain = self.morph_chain(b)
        if not chain:
            return False
        tail = chain[-1].bindings[0]
        plain = Sim(self.m)
        for a in ctx['prefix'] + ctx['holds'] + mods:
            if a['op'] == 'hold':
                plain.press(a['pos'], hold=True)
            elif a['op'] == 'tap':
                plain.tap(a['pos'], a.get('count', 1))
            elif a['op'] == 'release':
                plain.release_all()
                plain.settle()
        start = len(plain.out)
        try:
            plain.invoke(tail, pos, True)
            plain.invoke(tail, pos, False)
            plain.settle()
        except (Danger, Unsupported):
            return False
        got = [(s.usage, fold_mods(s.mods)) for s in plain.out[start:]]
        return got == [(s.usage, fold_mods(s.mods)) for s in strokes]

    def build_td(self, ctx, sim, pos, binding, td: Behavior, path, base_act) -> None:
        steps_actions = []
        notes = []
        for count in range(1, len(td.bindings) + 1):
            tap = self.act_tap(sim, pos, count)
            actions = ctx['holds'] + [tap]
            if not steps_actions and ctx['to'] is not None:
                actions = ctx['prefix'] + actions
            r = self.try_run([ctx['prefix'] + ctx['holds'] + [tap]] if ctx['to'] is not None else [actions])
            if r is None or not r[0][0]:
                continue
            steps_actions.append(actions)
            notes.append(f'{td.name}: {count} 回 → {td.bindings[count - 1]}')
        if not steps_actions:
            return
        r, extra = self.finish(ctx, steps_actions, base_act)
        if r is None:
            return
        term = td.tapping_term or 200
        steps = []
        for i, acts in enumerate(steps_actions):
            steps.append(self.step(acts, r[0][i], path, self.describe(acts), notes[i], binding, td_ms=term))
        if extra is not None:
            steps.append(self.step(extra, r[0][-1], [ctx['to'], 0], self.describe(extra),
                                   'BASE に戻す (戻ったことを確かめる)', '', role='cleanup'))
        sc = {'id': f'td-{td.name}', 'kind': 'tap_dance', 'title': f'タップダンス {td.name}', 'behavior': td.name,
              'layer': path[-1], 'steps': steps}
        self.add_recover(sc, ctx, base_act)
        self.scenarios.append(sc)

    def add_recover(self, sc: dict, ctx: dict, base_act: dict) -> None:
        if ctx['to'] is None:
            return
        ex = self.cleanup(ctx['prefix'], ctx['to'])
        acts = [dict(ex['actions'][0]), dict(base_act)]
        sc['to_layer'] = ctx['to']
        sc['recover'] = {'actions': acts, 'text': self.describe(acts), 'check': self.base_stroke()}

    def build_combos(self, base_paths) -> None:
        if not self.m.combos:
            return
        steps = []
        for c in self.m.combos:
            holds: list[dict] = []
            if c.layers and 0 not in c.layers:
                cand = [h for (layers, _), h in base_paths.items() if max(layers) in c.layers]
                if not cand:
                    self.not_tested.append({'what': f'コンボ {c.name}', 'reason': 'レイヤーにたどり着けない'})
                    continue
                holds = min(cand, key=len)
            act = {'op': 'combo', 'positions': c.positions, 'keys': [self.key_name(p) for p in c.positions],
                   'key': '+'.join(self.key_name(p) for p in c.positions),
                   'label': self.short(c.binding).split('\n')[0], 'role': 'combo'}
            actions = holds + [act]
            r = self.try_run([actions])
            if r is None or not r[0][0]:
                self.not_tested.append({'what': f'コンボ {c.name}', 'reason': '出力が確かめられない (押さないキーや、修飾だけなど)'})
                continue
            steps.append(self.step(actions, r[0][0], self.layer_path([], holds), self.describe(actions),
                                   f'コンボ {c.name} ({c.binding})', c.binding))
        if steps:
            self.scenarios.append({'id': 'combo', 'kind': 'combo', 'title': 'コンボ', 'layer': 0, 'steps': steps})

    # ---- 出力

    def to_json(self) -> dict:
        kinds = ['layer', 'hold_tap', 'mod_morph', 'tap_dance', 'to_layer', 'combo']
        scenarios = sorted(self.scenarios, key=lambda s: kinds.index(s['kind']))
        return {
            'layers': self.layer_info(),
            'scenarios': scenarios,
            'combos': len(self.m.combos),
            'not_tested': self.not_tested,
        }


def devices(model: Model) -> dict:
    """ZMK のデバイス名 → ビヘイビアの中身 (ログ版ファームのログを読むため)"""
    out = {}
    for head, dev in BUILTIN_DEVICES.items():
        out[dev] = {'name': head, 'kind': head}
    for name, beh in model.behaviors.items():
        d = {'name': name, 'kind': beh.kind, 'bindings': beh.bindings}
        if beh.kind == 'mod_morph':
            d['mods'] = beh.mods
            if beh.keep_mods:
                d['keep_mods'] = beh.keep_mods
        if beh.kind == 'tap_dance':
            d['tapping_term'] = beh.tapping_term or 200
        out[beh.device] = d
    return out


def translate(data: dict, pos_map: dict[int, int], keys: list[dict], layer_keep: set[int]) -> dict:
    """シナリオの位置を別の配列 (KQ-mini の Keyball39) に置き換える。置き換えられないシナリオは落とす"""
    names = key_names(keys)
    n = len(keys)

    def tr_action(a: dict) -> dict:
        a = dict(a)
        if 'pos' in a:
            a['pos'] = pos_map[a['pos']]
            a['key'] = names[a['pos']]
        if 'positions' in a:
            a['positions'] = [pos_map[p] for p in a['positions']]
        return a

    scenarios = []
    dropped = []
    for sc in data['scenarios']:
        try:
            if sc['kind'] == 'combo':
                raise KeyError('combo')
            new = dict(sc)
            new['steps'] = []
            seen = set()
            for st in sc['steps']:
                s2 = dict(st)
                s2['actions'] = [tr_action(a) for a in st['actions']]
                used = [a['pos'] for a in s2['actions'] if 'pos' in a]
                holds = [a['pos'] for a in s2['actions'] if a['op'] == 'hold']
                if len(set(holds)) != len(holds) or any(p >= n for p in used):
                    raise KeyError('dup')
                if any(layer not in layer_keep for layer in st['path']):
                    raise KeyError('layer')
                s2['text'] = describe_actions(s2['actions'])
                sig = repr(([(a['op'], a.get('pos'), a.get('count', 1)) for a in s2['actions']], s2['expect']))
                if sig in seen:
                    continue  # 2 つの位置が同じキーになった (LisM の FUNC 40 → Keyball の 30 など)
                seen.add(sig)
                new['steps'].append(s2)
            if 'recover' in sc:
                new['recover'] = dict(sc['recover'])
                new['recover']['actions'] = [tr_action(a) for a in sc['recover']['actions']]
                new['recover']['text'] = describe_actions(new['recover']['actions'])
            scenarios.append(new)
        except KeyError:
            dropped.append(sc['title'])
    layers = []
    inv: dict[int, int] = {}
    for src, dst in pos_map.items():
        inv.setdefault(dst, src)
    for info in data['layers']:
        if info['index'] not in layer_keep:
            continue
        leg = [''] * n
        for dst, src in inv.items():
            leg[dst] = info['legends'][src]
        layers.append({'index': info['index'], 'name': info['name'], 'legends': leg,
                       'danger': sorted({pos_map[p] for p in info['danger'] if p in pos_map})})
    not_tested = list(data['not_tested'])
    for t in dropped:
        not_tested.append({'what': t, 'reason': 'KQ-mini + Keyball39 に無いキー・レイヤーを使う'})
    return {'layers': layers, 'scenarios': scenarios, 'combos': 0, 'not_tested': not_tested}
