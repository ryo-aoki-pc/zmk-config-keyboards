#!/usr/bin/env python3
"""tools/keyboard-check の期待値 (tools/expected/*.json) を submodule から生成する。

検査ツール (tools/scripts/keyboard-check.ps1) は、ここで生成した JSON を「意図した設定」として、
キーボードから読み出した設定や、キーを押したときの動作と比べる。

    python tools/expected/generate.py            # 期待値を書き出す
    python tools/expected/generate.py --check    # コミット済みの期待値が最新か確かめる (CI 用)

入力は submodule (git submodule update --init が必要):
  - zmk-keymap-docgen: キーマップのパーサーと ZMK → Vial 変換 (zmk_to_vial.py)
  - zmk-config-LisM / KUKEY42 / AroundFortyRB / Pyuron: ZMK のキーマップ・overlay・conf
  - keyball: Keyball39 (via) の keymap.c / config.h
KQ-mini の期待値は、KQ-mini のファームと同じく lism.keymap を zmk_to_vial.py で変換して求める。

標準ライブラリだけで動く (Python 3.10 以上)。
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # submodule に __pycache__ を作らない

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import behaviors  # noqa: E402  (tools/expected/behaviors.py)

SCHEMA = 2
GENERATOR = 'tools/expected/generate.py'

# 名前 → submodule のパス
SUBMODULES = {
    'docgen': 'zmk-keymap-docgen',
    'LisM': 'zmk-config-LisM',
    'KUKEY42': 'zmk-config-KUKEY42',
    'AroundFortyRB': 'zmk-config-AroundFortyRB',
    'Pyuron': 'zmk-config-Pyuron',
    'roBa': 'zmk-config-roBa',
    'torabo': 'zmk-keyboard-torabo-tsuki-lp',
    'keyball': 'keyball',
}


class GenError(Exception):
    pass


# ============================================================================
# submodule
# ============================================================================

class Sources:
    """submodule (または --source で指定したパス) の場所とコミットを扱う。"""

    def __init__(self, overrides: dict[str, Path] | None = None):
        self.overrides = overrides or {}
        self.warnings: list[str] = []

    def path(self, name: str) -> Path:
        if name in self.overrides:
            p = self.overrides[name]
        else:
            p = ROOT / SUBMODULES[name]
        if not p.is_dir() or not any(p.iterdir()):
            raise GenError(f'{SUBMODULES[name]} がありません。git submodule update --init を実行してください')
        return p

    def commit(self, name: str) -> str:
        p = self.path(name)
        head = _git(p, 'rev-parse', 'HEAD')
        pinned = self.pinned(name)
        if pinned and head != pinned:
            msg = (f'{SUBMODULES[name]}: 使っているコミット {head[:7]} が、このリポジトリの参照 {pinned[:7]} と違います')
            if msg not in self.warnings:
                self.warnings.append(msg)
        return head

    def pinned(self, name: str) -> str | None:
        out = _git(ROOT, 'ls-files', '-s', '--', SUBMODULES[name], check=False)
        m = re.match(r'160000 ([0-9a-f]{40}) ', out or '')
        return m.group(1) if m else None

    def source_entry(self, name: str, files: list[str]) -> dict:
        return {'submodule': SUBMODULES[name], 'commit': self.commit(name), 'files': files}


def _git(cwd: Path, *args: str, check: bool = True) -> str:
    try:
        r = subprocess.run(['git', '-C', str(cwd), *args], capture_output=True, text=True, check=check)
    except (OSError, subprocess.CalledProcessError) as e:
        if check:
            raise GenError(f'git {" ".join(args)} に失敗しました ({cwd}): {e}') from e
        return ''
    return r.stdout.strip()


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding='utf-8')
    except OSError as e:
        raise GenError(f'{path} を読めません: {e}') from e


def import_docgen(sources: Sources):
    path = str(sources.path('docgen'))
    if path not in sys.path:
        sys.path.insert(0, path)
    import keymap_docgen as kd  # noqa: E402
    import vial_keymap_docgen as vd  # noqa: E402
    import zmk_to_vial as zv  # noqa: E402
    return kd, zv, vd


# ============================================================================
# 共通テーブル
# ============================================================================

# HID usage (Keyboard/Keypad page) → (Set-1 スキャンコード, 前置 (0 / 0xE0 / 0xE1), 表示ラベル)。
# Windows の Raw Input は、キーを HID usage ではなくスキャンコード (MakeCode と E0 フラグ) で渡す。
# 対応は Microsoft の "Keyboard Scan Code Specification" による。キー配列 (JIS / US) に依存しない。
HID_SCAN: dict[int, tuple[int, int, str]] = {}


def _build_hid_scan() -> None:
    letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    letter_scan = [0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26, 0x32,
                   0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C]
    for i, ch in enumerate(letters):
        HID_SCAN[0x04 + i] = (letter_scan[i], 0, ch)
    for i, ch in enumerate('1234567890'):
        HID_SCAN[0x1E + i] = (0x02 + i, 0, ch)
    HID_SCAN.update({
        0x28: (0x1C, 0, 'Enter'), 0x29: (0x01, 0, 'Esc'), 0x2A: (0x0E, 0, 'BS'), 0x2B: (0x0F, 0, 'Tab'),
        0x2C: (0x39, 0, 'Space'), 0x2D: (0x0C, 0, '-'), 0x2E: (0x0D, 0, '='), 0x2F: (0x1A, 0, '['),
        0x30: (0x1B, 0, ']'), 0x31: (0x2B, 0, '\\'), 0x32: (0x2B, 0, '#'), 0x33: (0x27, 0, ';'),
        0x34: (0x28, 0, "'"), 0x35: (0x29, 0, '`'), 0x36: (0x33, 0, ','), 0x37: (0x34, 0, '.'),
        0x38: (0x35, 0, '/'), 0x39: (0x3A, 0, 'Caps'),
    })
    for i in range(10):
        HID_SCAN[0x3A + i] = (0x3B + i, 0, f'F{i + 1}')
    HID_SCAN[0x44] = (0x57, 0, 'F11')
    HID_SCAN[0x45] = (0x58, 0, 'F12')
    HID_SCAN.update({
        0x46: (0x37, 0xE0, 'PrtSc'), 0x47: (0x46, 0, 'ScrLk'), 0x48: (0x45, 0xE1, 'Pause'),
        0x49: (0x52, 0xE0, 'Ins'), 0x4A: (0x47, 0xE0, 'Home'), 0x4B: (0x49, 0xE0, 'PgUp'),
        0x4C: (0x53, 0xE0, 'Del'), 0x4D: (0x4F, 0xE0, 'End'), 0x4E: (0x51, 0xE0, 'PgDn'),
        0x4F: (0x4D, 0xE0, '→'), 0x50: (0x4B, 0xE0, '←'), 0x51: (0x50, 0xE0, '↓'), 0x52: (0x48, 0xE0, '↑'),
        0x53: (0x45, 0, 'NumLk'), 0x54: (0x35, 0xE0, 'KP/'), 0x55: (0x37, 0, 'KP*'), 0x56: (0x4A, 0, 'KP-'),
        0x57: (0x4E, 0, 'KP+'), 0x58: (0x1C, 0xE0, 'KPEnt'), 0x59: (0x4F, 0, 'KP1'), 0x5A: (0x50, 0, 'KP2'),
        0x5B: (0x51, 0, 'KP3'), 0x5C: (0x4B, 0, 'KP4'), 0x5D: (0x4C, 0, 'KP5'), 0x5E: (0x4D, 0, 'KP6'),
        0x5F: (0x47, 0, 'KP7'), 0x60: (0x48, 0, 'KP8'), 0x61: (0x49, 0, 'KP9'), 0x62: (0x52, 0, 'KP0'),
        0x63: (0x53, 0, 'KP.'), 0x64: (0x56, 0, '\\(ISO)'), 0x65: (0x5D, 0xE0, 'App'),
        0x87: (0x73, 0, 'ろ'), 0x88: (0x70, 0, 'かな'), 0x89: (0x7D, 0, '¥'), 0x8A: (0x79, 0, '変換'),
        0x8B: (0x7B, 0, '無変換'), 0x90: (0xF2, 0, '한/영'), 0x91: (0xF1, 0, '漢字'),
        0xE0: (0x1D, 0, 'Ctrl'), 0xE1: (0x2A, 0, 'Shift'), 0xE2: (0x38, 0, 'Alt'), 0xE3: (0x5B, 0xE0, 'Win'),
        0xE4: (0x1D, 0xE0, 'RCtrl'), 0xE5: (0x36, 0, 'RShift'), 0xE6: (0x38, 0xE0, 'RAlt'), 0xE7: (0x5C, 0xE0, 'RWin'),
    })


_build_hid_scan()

# ZMK の暗黙の修飾 (LC() など) → キーコードの最上位バイトのビット
ZMK_IMPLICIT_MODS = {'LC': 0x01, 'LS': 0x02, 'LA': 0x04, 'LG': 0x08,
                     'RC': 0x10, 'RS': 0x20, 'RA': 0x40, 'RG': 0x80}

# ZMK v0.3.0 の標準ビヘイビア (app/dts/behaviors/*.dtsi の display-name)
ZMK_BEHAVIORS = [
    ('kp', 'Key Press', ['keycode']),
    ('mt', 'Mod-Tap', ['keycode', 'keycode']),
    ('lt', 'Layer-Tap', ['layer', 'keycode']),
    ('mo', 'Momentary Layer', ['layer']),
    ('to', 'To Layer', ['layer']),
    ('tog', 'Toggle Layer', ['layer']),
    ('sl', 'Sticky Layer', ['layer']),
    ('sk', 'Sticky Key', ['keycode']),
    ('kt', 'Key Toggle', ['keycode']),
    ('trans', 'Transparent', []),
    ('none', 'None', []),
    ('bt', 'Bluetooth', ['bt', 'int']),
    ('out', 'Output Selection', ['out']),
    ('sys_reset', 'Reset', []),
    ('bootloader', 'Bootloader', []),
    ('mkp', 'Mouse Key Press', ['mouse_button']),
    ('caps_word', 'Caps Word', []),
    ('key_repeat', 'Key Repeat', []),
    ('gresc', 'Grave/Escape', []),
    ('studio_unlock', 'Studio Unlock', []),
]
ZMK_BT = {'BT_CLR': 0, 'BT_NXT': 1, 'BT_PRV': 2, 'BT_SEL': 3, 'BT_CLR_ALL': 4, 'BT_DISC': 5}
ZMK_OUT = {'OUT_TOG': 0, 'OUT_USB': 1, 'OUT_BLE': 2}
ZMK_MOUSE_BUTTONS = {'MB1': 1, 'LCLK': 1, 'MB2': 2, 'RCLK': 2, 'MB3': 4, 'MCLK': 4, 'MB4': 8, 'MB5': 16}

# QMK の基本キーコード (0x00〜0xFF) の表示名。値は KQ-mini (QMK keycodes 0.0.7) と Keyball (0.0.9) で共通。
# 表示名は旧名のまま (Keyball の keymap.c の MS_BTN1 などの新しい名前は qmk_name_table で引く)
QMK_MOUSE_NAMES = {
    0xCD: 'KC_MS_U', 0xCE: 'KC_MS_D', 0xCF: 'KC_MS_L', 0xD0: 'KC_MS_R',
    0xD1: 'KC_BTN1', 0xD2: 'KC_BTN2', 0xD3: 'KC_BTN3', 0xD4: 'KC_BTN4', 0xD5: 'KC_BTN5',
    0xD6: 'KC_BTN6', 0xD7: 'KC_BTN7', 0xD8: 'KC_BTN8',
    0xD9: 'KC_WH_U', 0xDA: 'KC_WH_D', 0xDB: 'KC_WH_L', 0xDC: 'KC_WH_R',
    0xDD: 'KC_ACL0', 0xDE: 'KC_ACL1', 0xDF: 'KC_ACL2',
}

# 判定のしきい値 (ツール側はここから読む)
THRESHOLDS = {
    'ellipse_ratio_pass': 1.10,       # 楕円の縦横比 (長軸 ÷ 短軸) がこれ以下なら PASS
    'calib_min_points': 250,          # 楕円計測に必要な点の数 (calib_bin_ms ごとにまとめた数)
    'calib_bin_ms': 40,               # 楕円計測の移動量をこの間隔ごとにまとめる (1 カウント単位の誤差を減らす)
    'accel_window_ms': 40,            # カーソルの加速を取り除くとき、速さを測る区間
    'accel_idle_ms': 50,              # これより長く止まっていたら、加速は最小の倍率から始まる (ファームと同じ)
    'calib_speed_split_tolerance': 0.15,  # 遅い動きと速い動きの縦横比の差 (これを超えたらやり直し)
    'speed_tolerance': 0.10,          # 基準 (LisM) との速さの差がこれ以内なら PASS
    'speed_repeat_tolerance': 0.10,   # 回転数の計測を 2 回したときの差
    'scaler_max_denominator': 16,     # zip_x_scaler などの分母の上限
    'tap_settle_ms': 300,             # キーを離してから判定するまでの待ち
    'behavior_settle_ms': 700,        # レイヤー・ビヘイビアのテストで、期待の数の入力が出てから判定するまでの待ち (マクロの待ちを含む)
    'aml_timeout_margin_ms': 2000,    # AML のタイムアウトを確かめるときの余裕
}

# 期待する向き (ユーザーの決定: スクロールはホイールと同じ向き)
EXPECT_DIRECTIONS = {
    'scroll_toward': 'wheel-',  # 手前へ転がす → 下へスクロール (WHEEL が負)
    'scroll_right': 'hwheel+',  # 右へ転がす → 右へスクロール (HWHEEL が正)
}


def hid_label(usage: int) -> str:
    return HID_SCAN[usage][2] if usage in HID_SCAN else f'0x{usage:02X}'


def gen_common(zv) -> dict:
    zmk_names: dict[int, str] = {}
    for name, (_, value) in zv.ZMK_KEYCODES.items():
        zmk_names.setdefault(value, name)
    hid_keys = []
    for usage in sorted(HID_SCAN):
        scan, prefix, label = HID_SCAN[usage]
        hid_keys.append({
            'usage': usage, 'scan': scan, 'prefix': prefix, 'label': label,
            'zmk': zmk_names.get(usage, ''), 'qmk': zv.V6_BASIC_NAMES.get(usage, ''),
        })
    qmk_basic = {**zv.V6_BASIC_NAMES, **QMK_MOUSE_NAMES}
    return {
        'schema': SCHEMA, 'generator': GENERATOR, 'id': 'common', 'name': '共通テーブル', 'kind': 'common',
        'hid_keys': hid_keys,
        'qmk_basic_names': [[v, qmk_basic[v]] for v in sorted(qmk_basic)],
        'zmk_behaviors': [{'head': h, 'display': d, 'params': p} for h, d, p in ZMK_BEHAVIORS],
        'zmk_bt': [[v, n] for n, v in ZMK_BT.items()],
        'zmk_out': [[v, n] for n, v in ZMK_OUT.items()],
        'zmk_mouse_buttons': [[1, 'MB1'], [2, 'MB2'], [4, 'MB3'], [8, 'MB4'], [16, 'MB5']],
        'zmk_mods': [[v, n] for n, v in ZMK_IMPLICIT_MODS.items()],
        # Vial の QMK settings (QSID → 名前と幅)。値の幅は vial-qmk の qmk_settings.c と同じ
        'qmk_settings': [{'qsid': q, 'name': n, 'type': t} for q, (t, n) in sorted(zv.QMK_SETTINGS.items())],
        'thresholds': THRESHOLDS,
        'expect': EXPECT_DIRECTIONS,
    }


# ============================================================================
# ZMK
# ============================================================================

def zmk_keycode(zv, token: str) -> int:
    """ZMK のキーコード (例 'A', 'LC(X)', 'LS(LC(RIGHT))') → バインディングの値。
    (修飾 << 24) | (0x07 << 16) | usage。"""
    token = token.strip()
    m = re.fullmatch(r'(\w+)\s*\((.+)\)', token)
    if m:
        fn, inner = m.group(1), m.group(2)
        if fn not in ZMK_IMPLICIT_MODS:
            raise GenError(f'知らない修飾関数です: {token}')
        return zmk_keycode(zv, inner) | (ZMK_IMPLICIT_MODS[fn] << 24)
    if token in zv.ZMK_KEYCODES:
        return (0x07 << 16) | zv.ZMK_KEYCODES[token][1]
    raise GenError(f'知らない ZMK キーコードです: {token}')


def parse_nodes(kd, text: str, block: str) -> dict[str, dict]:
    """'behaviors { a: b { ... }; }' のノードを {ラベル: {node, body, label, display}} にする。"""
    content = kd.extract_named_block(text, block)
    out: dict[str, dict] = {}
    if not content:
        return out
    i = 0
    while True:
        m = re.compile(r'(\w+)\s*:\s*([\w,@-]+)\s*\{').search(content, i)
        if not m:
            break
        rng = kd.find_balanced_block(content, m.end() - 1)
        if not rng:
            break
        body = content[rng[0]:rng[1]]
        lm = re.search(r'\blabel\s*=\s*"([^"]*)"', body)
        dm = re.search(r'display-name\s*=\s*"([^"]*)"', body)
        cm = re.search(r'#binding-cells\s*=\s*<\s*(\d+)\s*>', body)
        out[m.group(1)] = {'node': m.group(2), 'body': body,
                           'label': lm.group(1) if lm else None,
                           'display': dm.group(1) if dm else None,
                           'cells': int(cm.group(1)) if cm else 0}
        i = rng[1] + 1
    return out


class ZmkKeymap:
    def __init__(self, kd, zv, path: Path):
        self.kd, self.zv = kd, zv
        raw = read_text(path)
        text = kd.strip_comments(raw)
        self.defines = kd.parse_defines(text)
        self.text = kd.expand_defines(text, self.defines)
        self.layer_names = kd.parse_all_layer_names(self.text)
        if not self.layer_names:
            raise GenError(f'{path}: レイヤーが見つかりません')
        self.layers = [kd.split_layer_bindings(kd.parse_layer(self.text, n) or '') for n in self.layer_names]
        self.custom = {**parse_nodes(kd, self.text, 'macros'), **parse_nodes(kd, self.text, 'behaviors')}
        self.alias_by_index = {v: k for k, v in self.defines.items()}
        self.builtin = {h: d for h, d, _ in ZMK_BEHAVIORS}

    def layer_index(self, alias: str) -> int:
        if alias not in self.defines:
            raise GenError(f'レイヤーの別名 {alias} がキーマップにありません')
        return self.defines[alias]

    def encode(self, binding: str) -> dict:
        """バインディング → Studio の get_keymap と同じ形 {b, p1, p2, src}。"""
        parts = binding.split()
        head = parts[0].lstrip('&')
        args = parts[1:]
        kc = lambda t: zmk_keycode(self.zv, t)  # noqa: E731
        out = {'b': None, 'p1': 0, 'p2': 0, 'src': binding}

        def need(n):
            if len(args) != n:
                raise GenError(f'引数の数が違います: {binding}')

        if head == 'kp' or head == 'sk' or head == 'kt':
            need(1)
            out['p1'] = kc(args[0])
        elif head == 'mt':
            need(2)
            out['p1'], out['p2'] = kc(args[0]), kc(args[1])
        elif head == 'lt':
            need(2)
            out['p1'], out['p2'] = int(args[0]), kc(args[1])
        elif head in ('mo', 'to', 'tog', 'sl'):
            need(1)
            out['p1'] = int(args[0])
        elif head in ('trans', 'none', 'sys_reset', 'bootloader', 'caps_word', 'key_repeat', 'gresc',
                      'studio_unlock'):
            need(0)
        elif head == 'bt':
            if not args or args[0] not in ZMK_BT:
                raise GenError(f'知らない &bt の引数です: {binding}')
            out['p1'] = ZMK_BT[args[0]]
            out['p2'] = int(args[1]) if len(args) > 1 else 0
        elif head == 'out':
            need(1)
            if args[0] not in ZMK_OUT:
                raise GenError(f'知らない &out の引数です: {binding}')
            out['p1'] = ZMK_OUT[args[0]]
        elif head == 'mkp':
            need(1)
            if args[0] not in ZMK_MOUSE_BUTTONS:
                raise GenError(f'知らない &mkp の引数です: {binding}')
            out['p1'] = ZMK_MOUSE_BUTTONS[args[0]]
        elif head in self.custom:
            node = self.custom[head]
            if node['cells'] != len(args) or args:
                raise GenError(f'引数付きのカスタムビヘイビアには対応していません: {binding}')
            # Studio の表示名は display-name → label → ノード名 の順 (ZMK の DEVICE_DT_NAME)
            name = node['display'] or node['label'] or node['node']
            out['b'] = name
            accept = []
            for n in (name, node['label'], node['node'], head, head.upper()):
                if n and n not in accept:
                    accept.append(n)
            out['accept'] = accept
            return out
        else:
            raise GenError(f'知らないビヘイビアです: {binding}')
        out['b'] = self.builtin[head]
        return out

    def tap(self, binding: str) -> dict:
        """BASE のキーをタップしたときに出るキー (usage)。出ないキーは skip を返す。"""
        parts = binding.split()
        head = parts[0].lstrip('&')
        if head == 'kp':
            v = zmk_keycode(self.zv, parts[1])
            usage, mods = v & 0xFFFF, (v >> 24) & 0xFF
            r = {'usage': usage}
            if mods:
                r['mods'] = mods
            return r
        if head == 'mt':
            return {'usage': zmk_keycode(self.zv, parts[2]) & 0xFFFF,
                    'hold_usage': zmk_keycode(self.zv, parts[1]) & 0xFFFF}
        if head == 'lt':
            return {'usage': zmk_keycode(self.zv, parts[2]) & 0xFFFF,
                    'hold_layer': self.layer_name(int(parts[1]))}
        if head in ('mo', 'to', 'tog', 'sl'):
            return {'skip': 'レイヤーキー'}
        if head == 'none':
            return {'skip': '割り当てなし'}
        if head == 'trans':
            return {'skip': '透過'}
        return {'skip': 'カスタム動作'}

    def layer_name(self, idx: int) -> str:
        return self.alias_by_index.get(idx, self.layer_names[idx] if idx < len(self.layer_names) else str(idx))

    def legend(self, binding: str) -> str:
        parts = binding.split()
        head = parts[0].lstrip('&')
        if head in ('kp', 'mt', 'lt'):
            v = zmk_keycode(self.zv, parts[-1]) & 0xFFFF
            return hid_label(v)
        if head in ('mo', 'to', 'tog'):
            return self.layer_name(int(parts[1]))
        if head == 'none':
            return ''
        return head


ZMK_BOARDS = [
    {
        'id': 'lism', 'name': 'LisM', 'sub': 'LisM',
        'keymap': 'config/lism.keymap', 'layout': 'config/lism.json',
        'dtsi': 'boards/shields/lism/lism.dtsi', 'kconfig': 'boards/shields/lism/Kconfig.defconfig',
        'scroll': {'scaler': [1, 16]},
        'files': ['config/lism.keymap', 'config/lism.json', 'boards/shields/lism/lism.dtsi', 'build.yaml',
                  'snippets/trackball-central/trackball.overlay',
                  'snippets/trackball-peripheral/trackball.overlay',
                  'snippets/non-trackball-central/non_trackball.overlay'],
        'balls': ['left', 'right'], 'ask_balls': True,
    },
    {
        'id': 'kukey42', 'name': 'KUKEY42', 'sub': 'KUKEY42',
        'keymap': 'config/KUKEY42.keymap', 'layout': 'config/KUKEY42.json',
        'dtsi': 'boards/shields/KUKEY42/KUKEY42.dtsi', 'kconfig': 'boards/shields/KUKEY42/Kconfig.defconfig',
        'scroll': {'tick': 32},
        'files': ['config/KUKEY42.keymap', 'config/KUKEY42.json', 'boards/shields/KUKEY42/KUKEY42.dtsi',
                  'boards/shields/KUKEY42/KUKEY42_R.overlay', 'boards/shields/KUKEY42/KUKEY42_R.conf', 'build.yaml'],
        'balls': ['right'], 'ask_balls': False,
    },
    {
        'id': 'aroundfortyrb', 'name': 'AroundFortyRB', 'sub': 'AroundFortyRB',
        'keymap': 'config/AroundForty-RB.keymap', 'layout': 'config/AroundForty-RB.json',
        'dtsi': 'boards/shields/AroundForty-RB/AroundForty-RB.dtsi',
        'kconfig': 'boards/shields/AroundForty-RB/Kconfig.defconfig',
        'scroll': {'scaler': [1, 32], 'why': 'CPI 800 のため'},
        'files': ['config/AroundForty-RB.keymap', 'config/AroundForty-RB.json',
                  'boards/shields/AroundForty-RB/AroundForty-RB.dtsi',
                  'boards/shields/AroundForty-RB/AroundForty-RB_R.overlay', 'build.yaml'],
        'balls': ['right'], 'ask_balls': False,
    },
    {
        'id': 'pyuron', 'name': 'Pyuron', 'sub': 'Pyuron',
        'keymap': 'config/Pyuron.keymap', 'layout': 'config/Pyuron.json',
        'dtsi': 'boards/shields/Pyuron/Pyuron.dtsi', 'kconfig': 'boards/shields/Pyuron/Kconfig.defconfig',
        'scroll': {'scaler': [1, 16]},
        'files': ['config/Pyuron.keymap', 'config/Pyuron.json', 'boards/shields/Pyuron/Pyuron.dtsi',
                  'boards/shields/Pyuron/Pyuron_R.overlay', 'boards/shields/Pyuron/Pyuron_L.overlay', 'build.yaml'],
        'balls': ['left', 'right'], 'ask_balls': False,
    },
    {
        'id': 'roba', 'name': 'roBa', 'sub': 'roBa',
        'keymap': 'config/roBa.keymap', 'layout': 'config/roBa.json',
        'dtsi': 'boards/shields/roBa/roBa.dtsi', 'kconfig': 'boards/shields/roBa/Kconfig.defconfig',
        'scroll': {'scaler': [1, 32], 'why': 'CPI 800 のため'},
        'files': ['config/roBa.keymap', 'config/roBa.json', 'boards/shields/roBa/roBa.dtsi',
                  'boards/shields/roBa/roBa_R.overlay', 'boards/shields/roBa/roBa_R.conf', 'build.yaml'],
        'balls': ['right'], 'ask_balls': False,
    },
    {
        'id': 'torabo-tsuki-lp', 'name': 'torabo-tsuki-lp', 'sub': 'torabo',
        'keymap': 'config/keymap.keymap', 'layout': 'config/info.json',
        'dtsi': 'boards/shields/torabo_tsuki_lp/torabo_tsuki_lp.dtsi',
        'kconfig': 'boards/shields/torabo_tsuki_lp/Kconfig.defconfig',
        'scroll': {'scaler': [1, 1], 'why': '実機で調整した値 + スムーズスクロール'},
        'files': ['config/keymap.keymap', 'config/info.json', 'boards/shields/torabo_tsuki_lp/torabo_tsuki_lp.dtsi',
                  'boards/shields/torabo_tsuki_lp/torabo_tsuki_lp_layouts.dtsi',
                  'boards/shields/torabo_tsuki_lp/torabo_tsuki_lp_right.overlay',
                  'boards/shields/torabo_tsuki_lp/torabo_tsuki_lp_left.overlay', 'build.yaml'],
        'balls': ['right'], 'ask_balls': False,
    },
]


def search(path: Path, pattern: str, what: str, flags: int = 0) -> re.Match:
    m = re.search(pattern, read_text(path), flags)
    if not m:
        raise GenError(f'{path} に {what} が見つかりません (パターン: {pattern})')
    return m


def strip_c_comments(text: str) -> str:
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    return re.sub(r'//[^\n]*', '', text)


XY_ACCEL_PROPS = ('min-factor', 'max-factor', 'speed-threshold', 'speed-max')


def xy_accel_nodes(base: Path, files: list[str]) -> dict[str, dict]:
    """ファイルで定義したカーソルの加速 (zmk,input-processor-xy-accel) のノード。ラベル → 値"""
    out: dict[str, dict] = {}
    for rel in files:
        p = base / rel
        if not p.exists():
            continue
        t = strip_c_comments(read_text(p))
        for m in re.finditer(r'(\w+)\s*:\s*[\w-]+\s*\{([^{}]*?compatible\s*=\s*"zmk,input-processor-xy-accel"[^{}]*)\}', t):
            vals = {}
            for prop in XY_ACCEL_PROPS:
                pm = re.search(rf'{prop}\s*=\s*<\s*(\d+)\s*>', m.group(2))
                if not pm:
                    raise GenError(f'{rel} の {m.group(1)} に {prop} がありません')
                vals[prop.replace('-', '_')] = int(pm.group(1))
            out[m.group(1)] = {'model': 'zmk', 'label': m.group(1), **vals}
    return out


def accel_in(nodes: dict[str, dict], processors: str) -> dict | None:
    """listener の input-processors に入っている加速のノード (無ければ None)。"""
    for ref in re.findall(r'&(\w+)', processors):
        if ref in nodes:
            return dict(nodes[ref])
    return None


def accel_text(a: dict | None) -> str:
    if a is None:
        return 'なし'
    return (f'min-factor {a["min_factor"]} / max-factor {a["max_factor"]} / '
            f'speed-threshold {a["speed_threshold"]} / speed-max {a["speed_max"]}')


def same_accel(a: dict | None, b: dict | None) -> bool:
    if a is None or b is None:
        return a is b
    return all(a[k.replace('-', '_')] == b[k.replace('-', '_')] for k in XY_ACCEL_PROPS)


def accel_consistency(what: str, a: dict | None, baseline: dict | None) -> dict:
    if same_accel(a, baseline):
        return {'level': 'ok', 'message': f'{what}: {accel_text(a)} (LisM 基準と同じ)'}
    return {'level': 'warn', 'message': f'{what}: {accel_text(a)} (LisM 基準: {accel_text(baseline)})'}


AML_THRESHOLD_DEFAULT = 10  # zmk-input-processor-aml-threshold の binding の既定値


def aml_threshold_nodes(base: Path, files: list[str]) -> dict[str, dict]:
    """ファイルで定義した AML の発動条件 (zmk,input-processor-aml-threshold) のノード。ラベル → 値"""
    out: dict[str, dict] = {}
    for rel in files:
        p = base / rel
        if not p.exists():
            continue
        t = strip_c_comments(read_text(p))
        for m in re.finditer(r'(\w+)\s*:\s*[\w-]+\s*\{([^{}]*?compatible\s*=\s*"zmk,input-processor-aml-threshold"[^{}]*)\}', t):
            tm = re.search(r'temp-layer\s*=\s*<\s*&(\w+)\s*>', m.group(2))
            if not tm:
                raise GenError(f'{rel} の {m.group(1)} に temp-layer がありません')
            th = re.search(r'threshold\s*=\s*<\s*(\d+)\s*>', m.group(2))
            out[m.group(1)] = {'label': m.group(1), 'temp_layer': tm.group(1),
                               'threshold': int(th.group(1)) if th else AML_THRESHOLD_DEFAULT}
    return out


def aml_threshold_in(nodes: dict[str, dict], processors: str) -> dict | None:
    """listener の input-processors に入っている AML の発動条件のノード (無ければ None)。"""
    for ref in re.findall(r'&(\w+)', processors):
        if ref in nodes:
            return dict(nodes[ref])
    return None


def aml_threshold_text(a: dict | None) -> str:
    return 'なし (わずかな動きでも AML が発動する)' if a is None else f'{a["label"]} の threshold {a["threshold"]}'


def listener_block(text: str, name: str, path: Path) -> str:
    """ノード (name { ... } または &name { ... }) の中身。子ノード (スクロール) より前の部分。"""
    m = re.search(rf'(?:&|\b){re.escape(name)}\s*(?::\s*[\w-]+\s*)?\{{(.*?)\n\s*\}};', text, re.DOTALL)
    if not m:
        raise GenError(f'{path} に {name} が見つかりません')
    body = m.group(1)
    child = re.search(r'\n\s*[\w-]+\s*\{', body)
    return body[:child.start()] if child else body


def scroll_chains(text: str, scrl: int) -> list[tuple[str, str]]:
    """リスナーの子ノードのうち、SCRL レイヤーで使うもの (ノード名, input-processors)。"""
    out = []
    for m in re.finditer(r'([\w-]+)\s*\{\s*layers\s*=\s*<([^>]*)>\s*;\s*input-processors\s*=(.*?);', text, re.DOTALL):
        if str(scrl) in m.group(2).split():
            out.append((m.group(1), re.sub(r'\s+', ' ', m.group(3)).strip()))
    return out


def keeps_aml(processors: str, mous: int) -> bool:
    """チェーンが AML (MOUSE_MOVE) のタイムアウトを延ばすか (zip_temp_layer <MOUS> 10000 を通る)。"""
    return bool(re.search(rf'&zip_temp_layer\s+{mous}\s+10000\b', processors))


def scroll_aml_consistency(board: dict, base: Path, mous: int, scrl: int) -> dict:
    """スクロール中も AML を延ばすか (LisM 基準: スクロールのチェーンの先頭に zip_temp_layer <MOUS> 10000)。"""
    chains: list[tuple[str, str]] = []
    for rel in board['files']:
        p = base / rel
        if not p.exists():
            continue
        t = strip_c_comments(read_text(p))
        t = re.sub(r'\bSCRL\b', str(scrl), re.sub(r'\bMOUS\b', str(mous), t))
        where = '/'.join(Path(rel).parts[-2:])
        chains += [(f'{where} の {name}', proc) for name, proc in scroll_chains(t, scrl)]
    if 'tick' in board['scroll']:
        # KUKEY42: ドライバ (scroll-layers) のホイールは、カーソルと同じ trackball_listener を通る
        rel = 'boards/shields/KUKEY42/KUKEY42_R.overlay'
        proc = listener_block(strip_c_comments(read_text(base / rel)), 'trackball_listener', base / rel)
        chains.append(('KUKEY42/KUKEY42_R.overlay の trackball_listener (ドライバのスクロール)', proc))
    if not chains:
        return {'level': 'warn', 'message': 'スクロールのチェーンが見つかりません (スクロール中に AML を延ばすか確かめられません)'}
    missing = [name for name, proc in chains if not keeps_aml(proc, mous)]
    if missing:
        return {'level': 'warn', 'message': (
            f'スクロール中に AML を延ばさないチェーンがあります ({", ".join(missing)})。'
            f'D / K を押したまま 10 秒以上スクロールすると AML が切れます (LisM 基準: 先頭に zip_temp_layer {mous} 10000)')}
    return {'level': 'ok', 'message': (
        f'スクロール中も AML を延ばす: zip_temp_layer {mous} 10000 を通る ({", ".join(name for name, _ in chains)})')}


def zmk_trackball_firmware(board: dict, base: Path) -> tuple[list[dict], list[dict | None]]:
    """ボールごとの、今のファームの設定 (正規化の推奨値を作るため) と、AML の発動条件 (整合のチェック用)。"""
    entries = zmk_trackball_firmware_base(board, base)
    nodes = xy_accel_nodes(base, board['files'])
    gates = aml_threshold_nodes(base, board['files'])
    amls = []
    for e in entries:
        processors = e.pop('processors')
        e['accel'] = accel_in(nodes, processors)
        e['xy_scaler_set'] = bool(re.search(r'&zip_xy_scaler\b', processors))
        amls.append(aml_threshold_in(gates, processors))
    return entries, amls


def zmk_trackball_firmware_base(board: dict, base: Path) -> list[dict]:
    bid = board['id']
    if bid == 'lism':
        central = 'snippets/trackball-central/trackball.overlay'
        ct = strip_c_comments(read_text(base / central))
        cp = listener_block(ct, 'central_listener', base / central)
        pp = listener_block(ct, 'peripheral_listener', base / central)
        out = []
        for side, proc, listener in (
                ('right', cp, f'zmk-config-LisM/{central} の central_listener'),
                ('left', pp, ('zmk-config-LisM の右手側 (セントラル) の snippet (trackball-central/trackball.overlay '
                              'と non-trackball-central/non_trackball.overlay) の peripheral_listener'))):
            sm = re.search(r'&zip_xy_scaler\s+(\d+)\s+(\d+)', proc)
            out.append({'side': side, 'sensor': 'paw3222', 'cpi': None, 'cpi_source': None, 'cpi_setting': None,
                        'xy_scaler': [int(sm.group(1)), int(sm.group(2))] if sm else [1, 1],
                        'matrix': None, 'divisor': None, 'correction': 'zip_scaler', 'listener': listener,
                        'processors': proc})
        return out
    if bid == 'kukey42':
        conf = base / 'boards/shields/KUKEY42/KUKEY42_R.conf'
        overlay = base / 'boards/shields/KUKEY42/KUKEY42_R.overlay'
        cpi = int(search(conf, r'(?m)^CONFIG_PMW3610_CPI=(\d+)', 'CONFIG_PMW3610_CPI').group(1))
        text = strip_c_comments(read_text(overlay))
        m = re.search(r'trackball_matrix\s*:\s*trackball_matrix\s*\{(.*?)\};', text, re.DOTALL)
        if not m:
            raise GenError(f'{overlay} に trackball_matrix が見つかりません')
        mm = re.search(r'matrix\s*=\s*<([^>]*)>', m.group(1))
        dm = re.search(r'divisor\s*=\s*<\s*(\d+)\s*>', m.group(1))
        if not mm or not dm:
            raise GenError(f'{overlay} の trackball_matrix に matrix / divisor がありません')
        values = [int(v.strip('()')) for v in mm.group(1).split()]
        if len(values) != 4:
            raise GenError(f'{overlay} の matrix は 4 要素である必要があります')
        procs = ' '.join(m.group(1) for m in re.finditer(r'input-processors\s*=(.*?);', text, re.DOTALL))
        return [{'side': 'right', 'sensor': 'pmw3610', 'cpi': cpi,
                 'cpi_source': 'zmk-config-KUKEY42/boards/shields/KUKEY42/KUKEY42_R.conf の CONFIG_PMW3610_CPI',
                 'cpi_setting': {'template': 'CONFIG_PMW3610_CPI={cpi}', 'step': 200, 'min': 200, 'max': 3200},
                 'xy_scaler': [1, 1], 'matrix': values, 'divisor': int(dm.group(1)), 'correction': 'matrix',
                 'listener': 'zmk-config-KUKEY42/boards/shields/KUKEY42/KUKEY42_R.overlay の trackball_matrix',
                 'processors': procs}]
    if bid == 'aroundfortyrb':
        overlay = base / 'boards/shields/AroundForty-RB/AroundForty-RB_R.overlay'
        text = strip_c_comments(read_text(overlay))
        cm = re.search(r'compatible\s*=\s*"pixart,pmw3610";.*?cpi\s*=\s*<\s*(\d+)\s*>', text, re.DOTALL)
        if not cm:
            raise GenError(f'{overlay} にトラックボールの cpi が見つかりません')
        lm = re.search(r'trackball_listener\s*\{.*?input-processors\s*=(.*?);', text, re.DOTALL)
        if not lm:
            raise GenError(f'{overlay} に trackball_listener が見つかりません')
        sm = re.search(r'&zip_xy_scaler\s+(\d+)\s+(\d+)', lm.group(1))
        scaler = [int(sm.group(1)), int(sm.group(2))] if sm else [1, 1]
        return [{'side': 'right', 'sensor': 'pmw3610', 'cpi': int(cm.group(1)),
                 'cpi_source': 'zmk-config-AroundFortyRB/boards/shields/AroundForty-RB/AroundForty-RB_R.overlay の trackball の cpi',
                 'cpi_setting': {'template': 'cpi = <{cpi}>;', 'step': 200, 'min': 200, 'max': 3200},
                 'xy_scaler': scaler, 'matrix': None, 'divisor': None, 'correction': 'zip_scaler',
                 'listener': 'zmk-config-AroundFortyRB/boards/shields/AroundForty-RB/AroundForty-RB_R.overlay の trackball_listener',
                 'processors': lm.group(1)}]
    if bid == 'pyuron':
        dtsi = base / 'boards/shields/Pyuron/Pyuron.dtsi'
        text = strip_c_comments(read_text(dtsi))
        out = []
        for side, suffix in (('left', 'L'), ('right', 'R')):
            m = re.search(rf'trackball_listener_{suffix}\s*:\s*trackball_listener_{suffix}\s*\{{(.*?)\n\s*\}};', text,
                          re.DOTALL)
            if not m:
                raise GenError(f'{dtsi} に trackball_listener_{suffix} が見つかりません')
            proc = m.group(1).split('scroller')[0]
            sm = re.search(r'&zip_xy_scaler\s+(\d+)\s+(\d+)', proc)
            out.append({'side': side, 'sensor': 'paw3222', 'cpi': None, 'cpi_source': None, 'cpi_setting': None,
                        'xy_scaler': [int(sm.group(1)), int(sm.group(2))] if sm else [1, 1],
                        'matrix': None, 'divisor': None, 'correction': 'zip_scaler',
                        'listener': f'zmk-config-Pyuron/boards/shields/Pyuron/Pyuron.dtsi の trackball_listener_{suffix}',
                        'processors': proc})
        return out
    if bid == 'roba':
        rel = 'boards/shields/roBa/roBa_R.overlay'
        conf = base / 'boards/shields/roBa/roBa_R.conf'
        cpi = int(search(conf, r'(?m)^CONFIG_PMW3610_CPI=(\d+)', 'CONFIG_PMW3610_CPI').group(1))
        proc = listener_block(strip_c_comments(read_text(base / rel)), 'trackball_listener', base / rel)
        sm = re.search(r'&zip_xy_scaler\s+(\d+)\s+(\d+)', proc)
        return [{'side': 'right', 'sensor': 'pmw3610', 'cpi': cpi,
                 'cpi_source': 'zmk-config-roBa/boards/shields/roBa/roBa_R.conf の CONFIG_PMW3610_CPI',
                 'cpi_setting': {'template': 'CONFIG_PMW3610_CPI={cpi}', 'step': 200, 'min': 200, 'max': 3200},
                 'xy_scaler': [int(sm.group(1)), int(sm.group(2))] if sm else [1, 1],
                 'matrix': None, 'divisor': None, 'correction': 'zip_scaler',
                 'listener': f'zmk-config-roBa/{rel} の trackball_listener', 'processors': proc}]
    if bid == 'torabo-tsuki-lp':
        rel = 'boards/shields/torabo_tsuki_lp/torabo_tsuki_lp_right.overlay'
        proc = listener_block(strip_c_comments(read_text(base / rel)), 'pointing_listener', base / rel)
        sm = re.search(r'&zip_xy_scaler\s+(\d+)\s+(\d+)', proc)
        return [{'side': 'right', 'sensor': 'paw3222', 'cpi': None, 'cpi_source': None, 'cpi_setting': None,
                 'xy_scaler': [int(sm.group(1)), int(sm.group(2))] if sm else [1, 1],
                 'matrix': None, 'divisor': None, 'correction': 'zip_scaler',
                 'listener': f'zmk-keyboard-torabo-tsuki-lp/{rel} の pointing_listener', 'processors': proc}]
    raise GenError(f'知らない機種です: {bid}')


def zmk_consistency(board: dict, base: Path, km: ZmkKeymap, mous: int, scrl: int,
                    firmware: list[dict], amls: list[dict | None], baseline_accel: dict | None,
                    baseline_aml: dict | None) -> list[dict]:
    """静的な整合チェック (情報 / 警告)。検査ツールは表示するだけ。"""
    out: list[dict] = []
    text = km.text
    zm = re.search(r'&zip_temp_layer\s*\{(.*?)\};', text, re.DOTALL)
    excluded: list[int] = []
    idle = None
    if zm:
        em = re.search(r'excluded-positions\s*=\s*<([^>]*)>', zm.group(1))
        if em:
            excluded = [int(v) for v in em.group(1).split()]
        im = re.search(r'require-prior-idle-ms\s*=\s*<\s*(\d+)\s*>', zm.group(1))
        idle = int(im.group(1)) if im else None
    mouse_move = km.layers[mous]
    # &trans は BASE と同じキー (押すと AML が切れる) なので、割り当てに数えない
    assigned = [i for i, b in enumerate(mouse_move) if b.split()[0] not in ('&none', '&trans')]
    if sorted(assigned) == sorted(excluded):
        out.append({'level': 'ok', 'message': f'AML の除外位置 ({" ".join(map(str, excluded))}) が MOUSE_MOVE の割り当てと一致'})
    else:
        out.append({'level': 'warn',
                    'message': f'AML の除外位置 ({" ".join(map(str, excluded))}) と MOUSE_MOVE の割り当て位置 '
                               f'({" ".join(map(str, assigned))}) が違います'})
    out.append({'level': 'ok' if idle == 200 else 'warn', 'message': f'require-prior-idle-ms = {idle} (LisM 基準 200)'})

    temp_layers: set[tuple[int, int]] = set()
    scalers: set[tuple[int, int]] = set()
    # zip_temp_layer と同じ 2 つの値 (レイヤー、タイムアウト) を付ける AML の発動条件のノードも数える
    temp_labels = ['zip_temp_layer'] + sorted(aml_threshold_nodes(base, board['files']))
    temp_re = r'&(?:' + '|'.join(temp_labels) + r')\s+(\d+)\s+(\d+)'
    for rel in board['files']:
        p = base / rel
        if not p.exists():
            continue
        t = strip_c_comments(read_text(p))
        t = re.sub(r'\bMOUS\b', str(mous), t)
        for m in re.finditer(temp_re, t):
            temp_layers.add((int(m.group(1)), int(m.group(2))))
        for m in re.finditer(r'&zip_scroll_scaler\s+(\d+)\s+(\d+)', t):
            scalers.add((int(m.group(1)), int(m.group(2))))
    names = ' / '.join(temp_labels)
    if temp_layers == {(mous, 10000)}:
        out.append({'level': 'ok', 'message': f'{names} はすべて {mous} 10000 (AML: MOUSE_MOVE、10 秒)'})
    else:
        out.append({'level': 'warn', 'message': f'{names} の設定がそろっていません: {sorted(temp_layers)}'})
    out.append(scroll_aml_consistency(board, base, mous, scrl))
    # スクロールの速さ: README の「共通基盤」の表の値 (LisM は 1/16。CPI などが違う機種は例外として書いてある)
    want = board['scroll']
    why = f'、{want["why"]}' if 'why' in want else ''
    if 'scaler' in want:
        exp = tuple(want['scaler'])
        txt = ', '.join(f'{a}/{b}' for a, b in sorted(scalers)) or 'なし'
        out.append({'level': 'ok' if scalers == {exp} else 'warn',
                    'message': f'スクロールの倍率 zip_scroll_scaler: {txt} (README の共通基盤: {exp[0]}/{exp[1]}{why})'})
    if 'tick' in want:
        conf = read_text(base / 'boards/shields/KUKEY42/KUKEY42_R.conf')
        tm = re.search(r'(?m)^CONFIG_PMW3610_SCROLL_TICK=(\d+)', conf)
        tick = int(tm.group(1)) if tm else None
        out.append({'level': 'ok' if tick == want['tick'] else 'warn',
                    'message': f'スクロールはドライバの scroll-layers で行う: CONFIG_PMW3610_SCROLL_TICK={tick} '
                               f'(README の共通基盤: {want["tick"]})'})
    # カーソルの加速: LisM 基準と同じ値か
    for fw in firmware:
        a = fw['accel']
        name = {'right': '右のボール', 'left': '左のボール'}.get(fw['side'], fw['side'])
        if a is None:
            out.append({'level': 'warn', 'message': f'カーソルの加速 ({name}): listener に入っていません'})
        else:
            out.append(accel_consistency(f'カーソルの加速 ({name}) {a["label"]}', a, baseline_accel))
    # AML の発動条件: カーソル移動の listener に aml_threshold が入っていて、LisM 基準と同じ値か
    for fw, g in zip(firmware, amls):
        name = {'right': '右のボール', 'left': '左のボール'}.get(fw['side'], fw['side'])
        same = g is not None and baseline_aml is not None and g['threshold'] == baseline_aml['threshold']
        out.append({'level': 'ok' if same else 'warn',
                    'message': f'AML の発動条件 ({name}): {aml_threshold_text(g)} (LisM 基準: {aml_threshold_text(baseline_aml)})'})
    if board['id'] == 'lism':
        # 左ボールのスクロールは、右手側の版 (trackball / non_trackball) の peripheral_listener で処理する
        def scroller(rel: str) -> str:
            t = strip_c_comments(read_text(base / rel))
            m = re.search(r'&peripheral_listener\s*\{.*?scroller\s*\{.*?input-processors\s*=(.*?);', t, re.DOTALL)
            return re.sub(r'\s+', ' ', m.group(1)).strip() if m else ''
        nodes = xy_accel_nodes(base, board['files'])
        gates = aml_threshold_nodes(base, board['files'])
        procs, aml_procs = [], []
        for rel in ('snippets/trackball-central/trackball.overlay', 'snippets/non-trackball-central/non_trackball.overlay'):
            t = strip_c_comments(read_text(base / rel))
            block = listener_block(t, 'peripheral_listener', base / rel)
            procs.append(accel_in(nodes, block))
            aml_procs.append(aml_threshold_in(gates, block))
        if not same_accel(procs[0], procs[1]):
            out.append({'level': 'warn', 'message': (
                f'左ボールのカーソルの加速が、右手側の版で違います (trackball-central: {accel_text(procs[0])} / '
                f'non-trackball-central: {accel_text(procs[1])})')})
        if aml_procs[0] != aml_procs[1]:
            out.append({'level': 'warn', 'message': (
                f'左ボールの AML の発動条件が、右手側の版で違います (trackball-central: {aml_threshold_text(aml_procs[0])} / '
                f'non-trackball-central: {aml_threshold_text(aml_procs[1])})')})
        a = scroller('snippets/trackball-central/trackball.overlay')
        b = scroller('snippets/non-trackball-central/non_trackball.overlay')
        if a != b:
            out.append({'level': 'warn', 'message': (
                '左ボールのスクロールの処理が、右手側の版で違います (trackball-central: ' + a +
                ' / non-trackball-central: ' + b + ')。右手側の版によって左ボールのスクロールの向きが変わる可能性があります')})
    return out


def physical_keys(kd, layout_path: Path, count: int) -> list[dict]:
    coords, labels, geom, unit, rowcol = kd.load_physical_layout(layout_path)
    if not geom or len(geom) != count:
        raise GenError(f'{layout_path} のキー数 ({len(geom or [])}) がキーマップ ({count}) と違います')
    xs = [g['x'] + (g['w'] or 1) / 2 for g in geom]
    mid = (min(xs) + max(xs)) / 2
    keys = []
    for i, g in enumerate(geom):
        keys.append({'pos': i, 'x': g['x'], 'y': g['y'], 'w': g['w'] or 1, 'h': g['h'] or 1,
                     'hand': 'left' if xs[i] < mid else 'right'})
    return keys


def find_positions(layer: list[str], pred) -> list[int]:
    return [i for i, b in enumerate(layer) if pred(b.split())]


def zmk_product(board: dict, base: Path) -> str:
    """ZMK Studio のデバイス名 (CONFIG_ZMK_KEYBOARD_NAME の既定値)。"""
    m = search(base / board['kconfig'], r'config\s+ZMK_KEYBOARD_NAME\s+default\s+"([^"]+)"', 'ZMK_KEYBOARD_NAME',
               re.DOTALL)
    return m.group(1)


def gen_zmk(board: dict, sources: Sources, kd, zv, baseline_accel: dict | None,
            baseline_aml: dict | None, baseline_ht: dict[str, dict] | None) -> dict:
    base = sources.path(board['sub'])
    km = ZmkKeymap(kd, zv, base / board['keymap'])
    n_layers = len(km.layer_names)
    counts = {len(l) for l in km.layers}
    if len(counts) != 1:
        raise GenError(f'{board["name"]}: レイヤーごとのキー数がそろっていません {counts}')
    key_count = counts.pop()
    mous, scrl, bt = km.layer_index('MOUS'), km.layer_index('SCRL'), km.layer_index('BT')
    base_layer = km.layers[0]

    bindings = [[km.encode(b) for b in layer] for layer in km.layers]

    keys = physical_keys(kd, base / board['layout'], key_count)
    for k in keys:
        k['legend'] = km.legend(base_layer[k['pos']])

    # 物理レイアウト名 (chosen zmk,physical-layout の display-name)
    dtsi = strip_c_comments(read_text(base / board['dtsi']))
    cm = re.search(r'zmk,physical-layout\s*=\s*&(\w+)\s*;', dtsi)
    if not cm:
        raise GenError(f'{board["dtsi"]} に chosen zmk,physical-layout がありません')
    lm = (re.search(re.escape(cm.group(1)) + r'\s*:\s*[\w-]+\s*\{[^}]*?display-name\s*=\s*"([^"]+)"', dtsi, re.DOTALL) or
          re.search(r'&' + re.escape(cm.group(1)) + r'\s*\{[^}]*?display-name\s*=\s*"([^"]+)"', dtsi, re.DOTALL))
    layout_name = lm.group(1) if lm else None

    # Studio 版のアーティファクト (build.yaml)
    build = read_text(base / 'build.yaml')
    studio = re.findall(r'(?m)^\s*artifact-name:\s*(\S+_studio)\s*$', build)
    logging = re.findall(r'(?m)^\s*artifact-name:\s*(\S+_logging)\s*$', build)

    # 実動作テスト: BASE のタップ
    taps, skipped = [], []
    for pos, b in enumerate(base_layer):
        t = km.tap(b)
        entry = {'pos': pos, 'legend': keys[pos]['legend'], 'src': b}
        if 'skip' in t:
            entry['reason'] = t['skip']
            skipped.append(entry)
            continue
        if t['usage'] not in HID_SCAN:
            raise GenError(f'{board["name"]}: スキャンコードの表に無いキーです: {b}')
        entry.update(t)
        if t['usage'] in (0xE3, 0xE7):
            entry['special'] = 'gui'
        taps.append(entry)

    # トラックボールのテストで押すキー (手ごと)
    def is_mo(layer_idx):
        return lambda p: p[0] == '&mo' and int(p[1]) == layer_idx
    def is_mod(usages):
        return lambda p: p[0] == '&kp' and zmk_keycode(zv, p[1]) & 0xFFFF in usages
    scroll_pos = find_positions(km.layers[mous], is_mo(scrl))
    click_pos = find_positions(km.layers[scrl], lambda p: p[0] == '&mkp' and ZMK_MOUSE_BUTTONS.get(p[1]) == 1)
    # 修飾キーは MOUSE_SCROLL にだけある (MOUSE_MOVE では &trans。押すと AML が切れる)
    shift_pos = find_positions(km.layers[scrl], is_mod((0xE1, 0xE5)))
    ctrl_pos = find_positions(km.layers[scrl], is_mod((0xE0, 0xE4)))
    hand_keys = {}
    for hand in ('left', 'right'):
        def pick(cands):
            c = [p for p in cands if keys[p]['hand'] == hand]
            return c[0] if c else None
        s, c, sh, ct = pick(scroll_pos), pick(click_pos), pick(shift_pos), pick(ctrl_pos)
        if s is None or c is None or sh is None or ct is None:
            continue
        after = km.tap(base_layer[c])
        if 'usage' not in after:
            raise GenError(f'{board["name"]}: クリックキーの位置 {c} が BASE でキーを出しません')

        def release(pos: int, mod: str) -> dict:
            # AML 中に押すと AML が切れ、BASE と同じくタップで文字が出る
            t = km.tap(base_layer[pos])
            if 'usage' not in t:
                raise GenError(f'{board["name"]}: {mod} の位置 {pos} が BASE でキーを出しません')
            return {'pos': pos, 'legend': keys[pos]['legend'], 'mod': mod, 'usage': t['usage']}
        # AML が切れていれば、スクロールキーの位置で BASE の文字が出る (AML のタイムアウト・しきい値のテスト)
        scroll_tap = km.tap(base_layer[s])
        if 'usage' not in scroll_tap:
            raise GenError(f'{board["name"]}: スクロールキーの位置 {s} が BASE でキーを出しません')
        hand_keys[hand] = {
            'scroll': {'pos': s, 'legend': keys[s]['legend'], 'usage': scroll_tap['usage']},
            'click': {'pos': c, 'legend': keys[c]['legend'], 'button': 1},
            'shift': {'pos': sh, 'legend': keys[sh]['legend'],
                      'usage': zmk_keycode(zv, km.layers[scrl][sh].split()[1]) & 0xFFFF},
            'release_ctrl': release(ct, 'Ctrl'),
            'release_shift': release(sh, 'Shift'),
            'after_timeout': {'pos': c, 'legend': keys[c]['legend'], 'usage': after['usage']},
        }
    if set(hand_keys) != {'left', 'right'}:
        raise GenError(f'{board["name"]}: 左右両方にスクロール / クリック / Shift / Ctrl のキーが必要です')

    # USB 出力への切り替え (Studio は USB 出力中でないと応答しない)
    bt_key = find_positions(base_layer, is_mo(bt))
    usb = find_positions(km.layers[bt], lambda p: p[0] == '&out' and p[1] == 'OUT_USB')
    ble = find_positions(km.layers[bt], lambda p: p[0] == '&out' and p[1] == 'OUT_BLE')
    output_switch = None
    if bt_key and usb:
        output_switch = {
            'layer_key': {'pos': bt_key[0], 'legend': keys[bt_key[0]]['legend']},
            'usb': {'pos': usb[0], 'legend': keys[usb[0]]['legend']},
            'ble': {'pos': ble[0], 'legend': keys[ble[0]]['legend']} if ble else None,
        }

    # AML (MOUSE_MOVE) の設定
    aml_timeout = None
    mm = re.search(r'&mkp_input_listener\s*\{\s*input-processors\s*=\s*<&zip_temp_layer\s+(\d+)\s+(\d+)>', km.text)
    if mm:
        aml_timeout = int(mm.group(2))
    zm = re.search(r'&zip_temp_layer\s*\{(.*?)\};', km.text, re.DOTALL)
    idle = None
    if zm:
        im = re.search(r'require-prior-idle-ms\s*=\s*<\s*(\d+)\s*>', zm.group(1))
        idle = int(im.group(1)) if im else None
    if aml_timeout is None:
        raise GenError(f'{board["name"]}: &mkp_input_listener の zip_temp_layer が見つかりません')

    layers = []
    for i, name in enumerate(km.layer_names):
        layers.append({'index': i, 'name': name, 'alias': km.alias_by_index.get(i, '')})

    files = board['files']
    firmware, amls = zmk_trackball_firmware(board, base)
    # AML の発動に要る動きの量 (実動作テスト用)。ボールごとに違えば小さいほう、入っていないボールがあれば 0
    aml_threshold = min((g['threshold'] if g else 0) for g in amls) if amls else 0
    hold_tap, ht_consistency = zmk_hold_tap(km, zv, keys, baseline_ht)
    return {
        'schema': SCHEMA, 'generator': GENERATOR, 'id': board['id'], 'name': board['name'], 'kind': 'zmk',
        'sources': [sources.source_entry(board['sub'], files),
                    sources.source_entry('docgen', ['keymap_docgen.py', 'zmk_to_vial.py'])],
        'device': {'usb_vid': '1D50', 'usb_pid': '615E', 'product': zmk_product(board, base),
                   'studio_artifacts': studio, 'logging_artifacts': logging},
        'layers': layers,
        'physical': {'layout_name': layout_name, 'keys': keys},
        'readout': {'zmk': {'layer_count': n_layers, 'key_count': key_count, 'bindings': bindings}},
        'interactive': {
            'taps': taps, 'skipped': skipped,
            'trackball': {
                'balls': board['balls'], 'ask_balls': board['ask_balls'],
                'aml': {'layer': mous, 'scroll_layer': scrl, 'timeout_ms': aml_timeout, 'require_prior_idle_ms': idle,
                        'threshold': aml_threshold},
                'keys': hand_keys,
                'firmware': firmware,
            },
            'output_switch': output_switch,
            'behaviors': zmk_behaviors(board, km, zv, keys, mous, scrl),
            'hold_tap': hold_tap,
        },
        'consistency': (zmk_consistency(board, base, km, mous, scrl, firmware, amls, baseline_accel, baseline_aml)
                        + ht_consistency),
    }


def zmk_behaviors(board: dict, km: ZmkKeymap, zv, keys: list[dict], mous: int, scrl: int) -> dict:
    """実動作テストの「レイヤー・ビヘイビア」の手順と期待する入力 (behaviors.py のシミュレータで求める)"""
    model = behaviors.Model.from_keymap(km, lambda t: zmk_keycode(zv, t))
    names = [km.alias_by_index.get(i) or n for i, n in enumerate(km.layer_names)]
    skip = {mous: 'AML (ボールを転がすと入るレイヤー) は、AML のテストで確かめる',
            scrl: 'AML の中のスクロールのレイヤーは、AML のテストで確かめる'}
    for i, layer in enumerate(km.layers):
        heads = {behaviors.split_binding(b)[0] for b in layer} - {'trans', 'none', 'mo', 'lt'}
        if heads and heads <= behaviors.DANGER_HEADS:
            skip.setdefault(i, 'Bluetooth の接続先や出力が変わるキーだけなので押さない')
    b = behaviors.Builder(model, keys, names, hid_label, skip, board['id'])
    try:
        b.build()
    except (behaviors.Danger, behaviors.Unsupported, ValueError) as e:
        raise GenError(f'{board["name"]}: レイヤー・ビヘイビアのテストを作れません: {e}') from e
    data = b.to_json()
    data['devices'] = behaviors.devices(model)
    return data


# ============================================================================
# タップホールドの設定 (keyboard-check の「タップホールドのタイミングを見る」のシミュレータに渡す)
# ============================================================================

# ZMK v0.3.0 の組み込みの hold-tap (app/dts/behaviors/mod_tap.dtsi / layer_tap.dtsi)。
# 書かれていない項目の既定値は app/dts/bindings/behaviors/zmk,behavior-hold-tap.yaml
ZMK_HT_DEFAULTS = {
    'flavor': 'hold-preferred', 'tapping_term_ms': None, 'quick_tap_ms': -1, 'require_prior_idle_ms': -1,
    'retro_tap': False, 'hold_while_undecided': False, 'hold_while_undecided_linger': False,
    'hold_trigger_on_release': False, 'hold_trigger_key_positions': [], 'bindings': ['&kp', '&kp'],
}
ZMK_HT_BUILTIN = {
    'mt': {'flavor': 'hold-preferred', 'tapping_term_ms': 200, 'bindings': ['&kp', '&kp']},
    'lt': {'flavor': 'tap-preferred', 'tapping_term_ms': 200, 'bindings': ['&mo', '&kp']},
}
ZMK_HT_FLAVORS = ('hold-preferred', 'balanced', 'tap-preferred', 'tap-unless-interrupted')


def ht_props(body: str, base: dict) -> dict:
    """hold-tap のノード (または &mt { ... } の上書き) の本体 → 設定。書かれていない項目は base のまま。"""
    d = {k: (list(v) if isinstance(v, list) else v) for k, v in base.items()}
    fm = re.search(r'(?<![\w-])flavor\s*=\s*"([\w-]+)"', body)
    if fm:
        if fm.group(1) not in ZMK_HT_FLAVORS:
            raise GenError(f'知らない flavor です: {fm.group(1)}')
        d['flavor'] = fm.group(1)
    for prop, key in (('tapping-term-ms', 'tapping_term_ms'), ('tapping_term_ms', 'tapping_term_ms'),
                      ('quick-tap-ms', 'quick_tap_ms'), ('quick_tap_ms', 'quick_tap_ms'),
                      ('require-prior-idle-ms', 'require_prior_idle_ms')):
        v = behaviors.parse_int_prop(body, prop)
        if v is not None:
            d[key] = v
    for prop, key in (('retro-tap', 'retro_tap'), ('hold-while-undecided', 'hold_while_undecided'),
                      ('hold-while-undecided-linger', 'hold_while_undecided_linger'),
                      ('hold-trigger-on-release', 'hold_trigger_on_release')):
        if re.search(r'(?<![\w-])' + re.escape(prop) + r'\s*;', body):
            d[key] = True
    pm = re.search(r'(?<![\w-])hold-trigger-key-positions\s*=\s*<([^>]*)>', body)
    if pm:
        d['hold_trigger_key_positions'] = [int(x, 0) for x in pm.group(1).split()]
    bm = re.search(r'(?<![\w-])bindings\s*=\s*<\s*(&\w+)\s*>\s*,\s*<\s*(&\w+)\s*>', body)
    if bm:
        d['bindings'] = [bm.group(1), bm.group(2)]
    if re.search(r'(?<![\w-])global-quick-tap\s*;', body):
        # 古い書き方: quick-tap-ms をすべてのキーに対して使う (= require-prior-idle-ms)
        d['require_prior_idle_ms'] = d['quick_tap_ms']
    return d


def zmk_hold_tap_config(km: ZmkKeymap) -> dict[str, dict]:
    """キーマップで使える hold-tap (組み込みの mt / lt と behaviors の中の hold-tap) と、その設定。
    ルートの '&mt { ... };' の上書きを反映する。"""
    out: dict[str, dict] = {}
    for name, b in ZMK_HT_BUILTIN.items():
        out[name] = {**ZMK_HT_DEFAULTS, **b, 'source': 'ZMK の既定値'}
    for name, node in km.custom.items():
        if re.search(r'compatible\s*=\s*"zmk,behavior-hold-tap"', node['body']):
            out[name] = {**ht_props(node['body'], ZMK_HT_DEFAULTS), 'source': f'behaviors の {node["node"]}'}
    for m in re.finditer(r'(?<![\w-])&(\w+)\s*\{(.*?)\};', km.text, re.DOTALL):
        if m.group(1) in out:
            out[m.group(1)] = {**ht_props(m.group(2), out[m.group(1)]), 'source': f'キーマップの &{m.group(1)} {{ }}'}
    for name, d in out.items():
        if d['tapping_term_ms'] is None:
            raise GenError(f'hold-tap {name} に tapping-term-ms がありません')
    return out


def ht_text(cfg: dict) -> str:
    parts = [cfg['flavor'], f'tapping-term {cfg["tapping_term_ms"]}', f'quick-tap {cfg["quick_tap_ms"]}']
    if cfg['require_prior_idle_ms'] >= 0:
        parts.append(f'require-prior-idle {cfg["require_prior_idle_ms"]}')
    for key, label in (('retro_tap', 'retro-tap'), ('hold_while_undecided', 'hold-while-undecided'),
                       ('hold_trigger_on_release', 'hold-trigger-on-release')):
        if cfg[key]:
            parts.append(label)
    if cfg['hold_trigger_key_positions']:
        parts.append('hold-trigger-key-positions ' + ' '.join(map(str, cfg['hold_trigger_key_positions'])))
    return ' / '.join(parts)


def ht_same(a: dict, b: dict) -> bool:
    keys = [k for k in ZMK_HT_DEFAULTS if k != 'bindings']
    return all(a.get(k) == b.get(k) for k in keys)


def zmk_kp_entry(zv, token: str) -> dict:
    v = zmk_keycode(zv, token)
    usage, mods = v & 0xFFFF, (v >> 24) & 0xFF
    label = hid_label(usage)
    if mods:
        label = behaviors.mods_label(mods) + '+' + label
    return {'kind': 'kp', 'usage': usage, 'mods': mods, 'label': label}


def zmk_ht_entry(km: ZmkKeymap, zv, binding: str, hts: dict[str, dict]) -> dict:
    """キーのバインディング → シミュレータが使う形 (kind: ht / kp / mo / none / trans / other)。"""
    head, args = behaviors.split_binding(binding)

    def sub(dev: str, arg: str) -> dict:
        if dev == '&kp':
            return zmk_kp_entry(zv, arg)
        if dev == '&mo':
            return {'kind': 'mo', 'layer': int(arg), 'label': km.layer_name(int(arg))}
        return {'kind': 'other', 'label': f'{dev} {arg}'}

    if head in hts:
        if len(args) != 2:
            raise GenError(f'hold-tap の引数の数が違います: {binding}')
        cfg = hts[head]
        return {'kind': 'ht', 'behavior': head, 'src': binding,
                'hold': sub(cfg['bindings'][0], args[0]), 'tap': sub(cfg['bindings'][1], args[1])}
    if head == 'kp':
        return zmk_kp_entry(zv, args[0])
    if head == 'mo':
        return {'kind': 'mo', 'layer': int(args[0]), 'label': km.layer_name(int(args[0]))}
    if head in ('none', 'trans'):
        return {'kind': head}
    return {'kind': 'other', 'label': km.legend(binding) or head, 'src': binding}


def zmk_hold_tap(km: ZmkKeymap, zv, keys: list[dict], baseline: dict[str, dict] | None) -> tuple[dict, list[dict]]:
    """「タップホールドのタイミングを見る」に渡すもの と 整合チェック。
    keys: キーごとに、BASE と、BASE から &mo / hold-tap のホールドで入れるレイヤーのバインディング
    (&trans は書かない。下のレイヤーに落ちる)。"""
    hts = zmk_hold_tap_config(km)
    reach = [0]
    i = 0
    while i < len(reach):
        for b in km.layers[reach[i]]:
            e = zmk_ht_entry(km, zv, b, hts)
            nxt = e['layer'] if e['kind'] == 'mo' else e['hold'].get('layer') if e['kind'] == 'ht' else None
            if nxt is not None and nxt not in reach and 0 <= nxt < len(km.layers):
                reach.append(nxt)
        i += 1
    layers = sorted(reach)
    out_keys = []
    for k in keys:
        on = {}
        for li in layers:
            e = zmk_ht_entry(km, zv, km.layers[li][k['pos']], hts)
            if e['kind'] != 'trans':
                on[str(li)] = e
        out_keys.append({'pos': k['pos'], 'on': on})
    used = sorted({e['behavior'] for k in out_keys for e in k['on'].values() if e['kind'] == 'ht'})
    behaviors_out = {name: {k: v for k, v in hts[name].items()} for name in used}
    consistency = []
    for name in used:
        cfg = hts[name]
        if baseline is None or name not in baseline:
            continue
        same = ht_same(cfg, baseline[name])
        consistency.append({'level': 'ok' if same else 'warn',
                            'message': f'タップホールド &{name}: {ht_text(cfg)} (LisM 基準: {ht_text(baseline[name])})'})
    data = {'engine': 'zmk', 'behaviors': behaviors_out, 'layers': layers, 'keys': out_keys}
    return data, consistency


# KQ-mini (vial-qmk) の QMK の設定 (Vial の QSID)。書かれていないものは既定値。tap_code_delay の既定値は TAP_CODE_DELAY で、
# vial-qmk の quantum/qmk_settings.h は先に quantum/action.h (TAP_CODE_DELAY 0) を読み込むので 0
KQ_HT_SETTINGS = {7: 'tapping_term', 18: 'tap_code_delay', 22: 'permissive_hold', 23: 'hold_on_other_key_press',
                  24: 'retro_tapping', 25: 'quick_tap_term', 26: 'chordal_hold', 27: 'flow_tap_term'}
KQ_HT_DEFAULTS = {'tapping_term': 200, 'tap_code_delay': 0, 'permissive_hold': 0, 'hold_on_other_key_press': 0,
                  'retro_tapping': 0, 'quick_tap_term': 200, 'chordal_hold': 0, 'flow_tap_term': 0}


def kq_chordal_hand(code: int) -> str:
    """KQ-mini の chordal hold の左右 (QMK が info.json から作る chordal_hold_layout)。
    KQ-mini の info.json の LAYOUT は 32 行 x 8 列 (x = 列、幅 1) の左右対称な格子なので、vial-qmk の
    lib/python/qmk/cli/generate/keyboard_c.py の _gen_chordal_hold_layout は x - 4.0 の符号で左右を決める
    (列 0〜3 は L、4 は '*'、5〜7 は R)。列は HID コード & 7 (zmk_to_vial.hid_to_matrix) なので、
    物理的な手とは関係なく、キーのコードで決まる。"""
    col = code & 7
    return 'L' if col < 4 else '*' if col == 4 else 'R'


def qmk_entry(value: int, layer_names: dict[int, str]) -> dict:
    """KQ-mini のキーコード → シミュレータが使う形。"""
    if value == 0x0001:
        return {'kind': 'trans'}
    if value == 0x0000:
        return {'kind': 'none'}
    if 0x0004 <= value <= 0x00E7:
        return {'kind': 'kp', 'usage': value, 'mods': 0, 'label': QMK_LABEL_OVERRIDES.get(value, hid_label(value))}
    if 0x0100 <= value < 0x2000 and 0x04 <= (value & 0xFF) <= 0xE7:
        # LCTL(KC_X) など。QMK の 5 ビットの修飾 → HID の修飾のバイト
        mod5 = (value >> 8) & 0x1F
        mods = (mod5 & 0x0F) << (4 if mod5 & 0x10 else 0)
        usage = value & 0xFF
        return {'kind': 'kp', 'usage': usage, 'mods': mods,
                'label': behaviors.mods_label(mods) + '+' + hid_label(usage)}
    if 0x2000 <= value < 0x4000:
        mod5 = (value >> 8) & 0x1F
        mods = (mod5 & 0x0F) << (4 if mod5 & 0x10 else 0)
        tap = qmk_entry(value & 0xFF, layer_names)
        return {'kind': 'ht', 'behavior': 'MT', 'src': f'MT(0x{mod5:02X}, {tap.get("label", "")})',
                'hold': {'kind': 'mods', 'mods': mods, 'label': behaviors.mods_label(mods)}, 'tap': tap}
    if 0x4000 <= value < 0x5000:
        layer = (value >> 8) & 0x0F
        tap = qmk_entry(value & 0xFF, layer_names)
        name = layer_names.get(layer, f'L{layer}')
        return {'kind': 'ht', 'behavior': 'LT', 'src': f'LT({layer}, {tap.get("label", "")})',
                'hold': {'kind': 'mo', 'layer': layer, 'label': name}, 'tap': tap}
    if 0x5220 <= value < 0x5240:
        layer = value & 0x1F
        return {'kind': 'mo', 'layer': layer, 'label': layer_names.get(layer, f'L{layer}')}
    return {'kind': 'other', 'label': f'0x{value:04X}'}


def kq_hold_tap(conv, zv, kb: Keyball, keys: list[dict], settings: list[dict],
                layer_names: dict[int, str]) -> tuple[dict, list[dict]]:
    by_name = {s['name']: s['value'] for s in settings}
    st = {name: by_name.get(name, KQ_HT_DEFAULTS[name]) for name in KQ_HT_SETTINGS.values()}
    cells = {}
    for k in keys:
        code = kb.cell(0, k['pos'])
        if k['present'] and 0x04 <= code <= 0xE7:
            cells[k['pos']] = (code, tuple(zv.hid_to_matrix(code)))
    reach = [0]
    i = 0
    while i < len(reach):
        for code, (r, c) in cells.values():
            e = qmk_entry(conv.matrix[reach[i]][r][c], layer_names)
            nxt = e['layer'] if e['kind'] == 'mo' else e['hold'].get('layer') if e['kind'] == 'ht' else None
            if nxt is not None and nxt not in reach and nxt < len(conv.matrix):
                reach.append(nxt)
        i += 1
    layers = sorted(reach)
    out_keys = []
    for k in keys:
        if k['pos'] not in cells:
            continue
        code, (r, c) = cells[k['pos']]
        on = {}
        for li in layers:
            e = qmk_entry(conv.matrix[li][r][c], layer_names)
            if e['kind'] != 'trans':
                on[str(li)] = e
        out_keys.append({'pos': k['pos'], 'usage': code, 'qmk_hand': kq_chordal_hand(code), 'on': on})
    consistency = []
    same = (st['tapping_term'] == 150 and st['permissive_hold'] == 1 and st['hold_on_other_key_press'] == 0
            and st['quick_tap_term'] == 0)
    consistency.append({'level': 'ok' if same else 'warn', 'message': (
        f'タップホールド: tapping_term {st["tapping_term"]} / permissive_hold {st["permissive_hold"]} / '
        f'hold_on_other_key_press {st["hold_on_other_key_press"]} / quick_tap_term {st["quick_tap_term"]} '
        '(LisM の balanced / tapping-term 150 / quick-tap 0 に相当するのは 150 / 1 / 0 / 0)')})
    if st['chordal_hold']:
        hand_map = {'left': 'L', 'right': 'R'}
        diff = [k for k in out_keys
                if any(e['kind'] == 'ht' for e in k['on'].values())
                and k['qmk_hand'] != hand_map[next(x for x in keys if x['pos'] == k['pos'])['hand']]]
        if diff:
            consistency.append({'level': 'warn', 'message': (
                'chordal hold の左右が物理的な手と違うキーがあります (KQ-mini の左右はキーのコードで決まる): '
                + ', '.join(next(x for x in keys if x['pos'] == k['pos'])['legend'] or str(k['pos']) for k in diff))})
    return {'engine': 'qmk', 'settings': st, 'layers': layers, 'keys': out_keys}, consistency


# ============================================================================
# QMK (Keyball39 / KQ-mini)
# ============================================================================

QMK_SHORT = {
    'KC_ENT': 0x28, 'KC_ESC': 0x29, 'KC_BSPC': 0x2A, 'KC_SPC': 0x2C, 'KC_MINS': 0x2D, 'KC_EQL': 0x2E,
    'KC_LBRC': 0x2F, 'KC_RBRC': 0x30, 'KC_BSLS': 0x31, 'KC_SCLN': 0x33, 'KC_QUOT': 0x34, 'KC_GRV': 0x35,
    'KC_COMM': 0x36, 'KC_SLSH': 0x38, 'KC_CAPS': 0x39, 'KC_PSCR': 0x46, 'KC_SCRL': 0x47, 'KC_PAUS': 0x48,
    'KC_INS': 0x49, 'KC_PGUP': 0x4B, 'KC_DEL': 0x4C, 'KC_PGDN': 0x4E, 'KC_RGHT': 0x4F, 'KC_APP': 0x65,
    'KC_LCTL': 0xE0, 'KC_LSFT': 0xE1, 'KC_LALT': 0xE2, 'KC_LGUI': 0xE3, 'KC_RCTL': 0xE4, 'KC_RSFT': 0xE5,
    'KC_RALT': 0xE6, 'KC_RGUI': 0xE7,
}
QMK_SPECIAL = {
    'RGB_TOG': 0x7820, 'RGB_MOD': 0x7821, 'RGB_RMOD': 0x7822, 'RGB_HUI': 0x7823, 'RGB_HUD': 0x7824,
    'RGB_SAI': 0x7825, 'RGB_SAD': 0x7826, 'RGB_VAI': 0x7827, 'RGB_VAD': 0x7828,
    # QMK 0.30 で RGB_* が削除され、UG_* になった (値は同じ)
    'UG_TOGG': 0x7820, 'UG_NEXT': 0x7821, 'UG_PREV': 0x7822, 'UG_HUEU': 0x7823, 'UG_HUED': 0x7824,
    'UG_SATU': 0x7825, 'UG_SATD': 0x7826, 'UG_VALU': 0x7827, 'UG_VALD': 0x7828,
    'QK_BOOT': 0x7C00, 'QK_RBT': 0x7C01,
}


def qmk_name_table(zv, keyball_h: str) -> dict[str, int]:
    """QMK のキーコード名 → 値。keymap.c に出てくる名前を引けるだけ用意する。
    QMK 0.22 (keycodes 0.0.3) と 0.34 (0.0.9) のどちらの名前も引ける (KC_BTN1 / MS_BTN1 など)。"""
    t: dict[str, int] = {}
    for qmk_name, value in zv.ZMK_KEYCODES.values():
        t[qmk_name] = value
    for value, name in zv.V6_BASIC_NAMES.items():
        t.setdefault(name, value)
    t.update(QMK_SHORT)
    for value, name in QMK_MOUSE_NAMES.items():
        t[name] = value
    for i in range(1, 9):
        t[f'KC_MS_BTN{i}'] = 0xD0 + i
        t[f'MS_BTN{i}'] = 0xD0 + i               # QMK 0.26 以降の名前
        t[f'QK_MOUSE_BUTTON_{i}'] = 0xD0 + i
    t.update(QMK_SPECIAL)
    for m in re.finditer(r'(\w+)\s*=\s*QK_KB_(\d+)', keyball_h):
        t[m.group(1)] = 0x7E00 + int(m.group(2))
    return t


def qmk_token_value(table: dict[str, int], token: str) -> int:
    if token == '&trans':
        return 0x0001
    if token == '&none':
        return 0x0000
    m = re.fullmatch(r'(MO|TO|TG)\((\d+)\)', token)
    if m:
        return {'MO': 0x5220, 'TO': 0x5200, 'TG': 0x5260}[m.group(1)] | int(m.group(2))
    if token in table:
        return table[token]
    raise GenError(f'知らない QMK キーコードです: {token}')


def qmk_tap(value: int) -> dict:
    """QMK キーコードをタップしたときに出るキー。"""
    if value in (0x0000, 0x0001):
        return {'skip': '割り当てなし'}
    if 0x0004 <= value <= 0x00A4 or 0x00E0 <= value <= 0x00E7:
        return {'usage': value}
    if 0x2000 <= value < 0x4000:  # MT
        mod5 = (value >> 8) & 0x1F
        bit = {1: 0, 2: 1, 4: 2, 8: 3}.get(mod5 & 0x0F)
        r = {'usage': value & 0xFF}
        if bit is not None:
            r['hold_usage'] = 0xE0 + bit + (4 if mod5 & 0x10 else 0)
        return r
    if 0x4000 <= value < 0x5000:  # LT
        return {'usage': value & 0xFF, 'hold_layer': f'L{(value >> 8) & 0x0F}'}
    if 0x5200 <= value < 0x5300:
        return {'skip': 'レイヤーキー'}
    return {'skip': 'カスタム動作'}


def keyball_paths(sources: Sources) -> dict[str, Path]:
    kb = sources.path('keyball') / 'qmk_firmware/keyboards/keyball'
    # QMK 0.34 では keyboard.json (QMK 0.22 では info.json)
    info = kb / 'keyball39/keyboard.json'
    if not info.exists():
        info = kb / 'keyball39/info.json'
    return {
        'dir': kb,
        'keymap': kb / 'keyball39/keymaps/via/keymap.c',
        'config': kb / 'keyball39/keymaps/via/config.h',
        'h': kb / 'keyball39/keyball39.h',
        'info': info,
        'lib_h': kb / 'lib/keyball/keyball.h',
    }


def define_int(text: str, name: str) -> int | None:
    m = re.search(rf'(?m)^\s*#\s*define\s+{name}\s+(\d+)\b', strip_c_comments(text))
    return int(m.group(1)) if m else None


class Keyball:
    """Keyball39 (via) の keymap.c と設定。"""

    def __init__(self, sources: Sources, kd, zv, vd):
        p = keyball_paths(sources)
        self.paths = p
        keymap_c = read_text(p['keymap'])
        h_text = read_text(p['h'])
        lib_h = read_text(p['lib_h'])
        config_h = read_text(p['config'])
        self.table = qmk_name_table(zv, lib_h)
        macro = vd.detect_layout_macro_name(keymap_c)
        if not macro:
            raise GenError(f'{p["keymap"]} に LAYOUT が見つかりません')
        self.arg_to_matrix = vd.parse_layout_macro(h_text, macro)
        present_cells = set(vd.parse_layout_macro(h_text, 'LAYOUT_right_ball').values())
        layers = vd.parse_qmk_keymap_c(keymap_c)
        self.rows, self.cols = 8, 6
        self.tokens = [toks for _, toks in layers]
        self.keymap = []
        for toks in self.tokens:
            if len(toks) != len(self.arg_to_matrix):
                raise GenError(f'keymap.c のキー数 ({len(toks)}) が {macro} ({len(self.arg_to_matrix)}) と違います')
            grid = [[0] * self.cols for _ in range(self.rows)]
            for i, tok in enumerate(toks):
                r, c = self.arg_to_matrix[i]
                grid[r][c] = qmk_token_value(self.table, tok)
            self.keymap.append(grid)
        info = json.loads(read_text(p['info']))
        entries = info['layouts']['LAYOUT_no_ball']['layout']
        if len(entries) != len(self.arg_to_matrix):
            raise GenError(f'{p["info"].name} の LAYOUT_no_ball のキー数が LAYOUT と違います')
        self.keys = []
        for i, e in enumerate(entries):
            r, c = self.arg_to_matrix[i]
            self.keys.append({'pos': i, 'matrix': [r, c], 'x': e['x'], 'y': e['y'], 'w': e.get('w', 1),
                              'h': e.get('h', 1), 'label': e.get('label', ''),
                              'hand': 'left' if r < 4 else 'right', 'present': (r, c) in present_cells})

        # 設定 (config.h → keyball.h の既定値)
        def need(name, *texts):
            for t in texts:
                v = define_int(t, name)
                if v is not None:
                    return v
            raise GenError(f'{name} が config.h / keyball.h に見つかりません')
        cpi = need('KEYBALL_CPI_DEFAULT', config_h, lib_h)
        sdiv = need('KEYBALL_SCROLL_DIV_DEFAULT', config_h, lib_h)
        aml_layer = need('AUTO_MOUSE_DEFAULT_LAYER', config_h)
        aml_time = need('AUTO_MOUSE_TIME', config_h)
        aml_delay = need('AUTO_MOUSE_DELAY', config_h)
        scroll_layer = need('KEYBALL_SCROLL_LAYER', keymap_c)
        km_text = strip_c_comments(keymap_c)
        if 'keyball_set_scrollsnap_mode(KEYBALL_SCROLLSNAP_MODE_FREE)' not in km_text:
            raise GenError('keymap.c でスクロールスナップを FREE にしていません')
        if 'set_auto_mouse_enable(true)' not in km_text:
            raise GenError('keymap.c で AML を有効にしていません')
        # カーソルの加速 (keymap.c の keyball_on_apply_motion_to_mouse_move。値は config.h)
        self.accel = None
        accel_vals = {k: define_int(config_h, f'KEYBALL_ACCEL_{k.upper()}')
                      for k in ('min_factor', 'max_factor', 'speed_threshold', 'speed_max')}
        if all(v is not None for v in accel_vals.values()):
            if 'keyball_on_apply_motion_to_mouse_move' not in km_text:
                raise GenError('config.h に KEYBALL_ACCEL_* がありますが、keymap.c に加速の処理がありません')
            # 速さは 8ms ごとの移動量 (大きいほう + 小さいほうの半分) から求め、1 回の報告は ±127 で頭打ちになる
            self.accel = {'model': 'keyball', 'label': 'KEYBALL_ACCEL_*', **accel_vals,
                          'interval_ms': need('KEYBALL_REPORTMOUSE_INTERVAL', config_h, lib_h), 'clamp': 127}
        # AML の発動に要る動きの量 (keymap.c の auto_mouse_activation。値は config.h)
        self.aml_threshold = define_int(config_h, 'KEYBALL_AML_THRESHOLD')
        if self.aml_threshold is not None and 'auto_mouse_activation' not in km_text:
            raise GenError('config.h に KEYBALL_AML_THRESHOLD がありますが、keymap.c に auto_mouse_activation がありません')
        self.status = {
            'format': 1, 'model': 39, 'cpi': cpi // 100, 'scroll_div': sdiv, 'scroll_snap': 2,
            'aml_enabled': True, 'aml_layer': aml_layer, 'aml_timeout': aml_time, 'aml_delay': aml_delay,
            'scroll_layer': scroll_layer, 'cpi_default': cpi // 100, 'scroll_div_default': sdiv,
        }
        if self.aml_threshold is not None:
            # 08 00 01 の形式 2 から [29] で返す
            self.status.update({'format': 2, 'aml_threshold': self.aml_threshold})

    def cell(self, layer: int, pos: int) -> int:
        r, c = self.arg_to_matrix[pos]
        return self.keymap[layer][r][c]

    def trackball_keys(self, tap_of_pos) -> dict:
        """トラックボールのテストで押すキー。tap_of_pos(pos) は BASE でタップしたときの usage。"""
        aml, scrl = self.status['aml_layer'], self.status['scroll_layer']
        out = {}
        for hand in ('left', 'right'):
            ks = [k for k in self.keys if k['hand'] == hand and k['present']]
            scroll = [k for k in ks if self.cell(aml, k['pos']) == (0x5220 | scrl)]
            click = [k for k in ks if self.cell(scrl, k['pos']) == 0xD1]
            # 修飾キーはスクロールレイヤーにだけある (AML レイヤーでは KC_TRNS。押すと AML が切れる)
            shift = [k for k in ks if self.cell(scrl, k['pos']) in (0xE1, 0xE5)]
            ctrl = [k for k in ks if self.cell(scrl, k['pos']) in (0xE0, 0xE4)]
            if not (scroll and click and shift and ctrl):
                raise GenError(f'Keyball39: {hand} にスクロール / クリック / Shift / Ctrl のキーがありません')
            c = click[0]['pos']
            after = tap_of_pos(c)
            sh, ct = shift[0]['pos'], ctrl[0]['pos']
            out[hand] = {
                'scroll': {'pos': scroll[0]['pos'], 'usage': tap_of_pos(scroll[0]['pos'])},
                'click': {'pos': c, 'button': 1},
                'shift': {'pos': sh, 'usage': self.cell(scrl, sh)},
                'release_ctrl': {'pos': ct, 'mod': 'Ctrl', 'usage': tap_of_pos(ct)},
                'release_shift': {'pos': sh, 'mod': 'Shift', 'usage': tap_of_pos(sh)},
                'after_timeout': {'pos': c, 'usage': after},
            }
        return out

    def firmware(self) -> list[dict]:
        return [{'side': 'right', 'sensor': 'pmw3360', 'cpi': self.status['cpi'] * 100,
                 'cpi_source': 'keyball/qmk_firmware/keyboards/keyball/keyball39/keymaps/via/config.h の KEYBALL_CPI_DEFAULT (既定 500)',
                 'cpi_setting': {'template': '#define KEYBALL_CPI_DEFAULT {cpi}', 'step': 100, 'min': 100, 'max': 12000},
                 'xy_scaler': [1, 1], 'xy_scaler_set': False, 'matrix': None, 'divisor': None, 'correction': 'cpi_only',
                 'listener': 'Keyball のファーム (X/Y を別々に補正する機能は無い)', 'accel': self.accel}]


QMK_LABEL_OVERRIDES = {0xE6: 'RAlt', 0x39: 'Caps'}


def qmk_legend(value: int, layer_names: dict[int, str] | None = None) -> str:
    if value in (0, 1):
        return ''
    if value <= 0xFF:
        return QMK_LABEL_OVERRIDES.get(value, hid_label(value))
    if 0x2000 <= value < 0x5000:
        return hid_label(value & 0xFF)
    if 0x5200 <= value < 0x5300:
        n = value & 0x1F
        return (layer_names or {}).get(n, f'L{n}')
    return f'0x{value:04X}'


def add_legends(keys: list[dict], legend_of_pos) -> None:
    for k in keys:
        k['legend'] = legend_of_pos(k['pos'])


def gen_keyball(kb: Keyball, sources: Sources, lism_aml: dict, baseline_accel: dict | None) -> dict:
    keys = [dict(k) for k in kb.keys]
    names = {1: 'AML', 2: 'SCROLL', 3: '設定'}
    add_legends(keys, lambda pos: qmk_legend(kb.cell(0, pos), names))
    tb_keys = kb.trackball_keys(lambda pos: kb.cell(0, pos))
    for hand in tb_keys.values():
        for v in hand.values():
            v['legend'] = keys[v['pos']]['legend']
    tokens = [[t for t in toks] for toks in kb.tokens]
    st = kb.status
    consistency = [
        {'level': 'ok' if st['aml_timeout'] == lism_aml['timeout_ms'] else 'warn',
         'message': f'AML のタイムアウト AUTO_MOUSE_TIME = {st["aml_timeout"]} (LisM {lism_aml["timeout_ms"]})'},
        {'level': 'ok' if st['aml_delay'] == lism_aml['require_prior_idle_ms'] else 'warn',
         'message': f'AML の発動条件 AUTO_MOUSE_DELAY = {st["aml_delay"]} (LisM require-prior-idle-ms {lism_aml["require_prior_idle_ms"]})'},
        {'level': 'ok' if kb.aml_threshold == lism_aml['threshold'] else 'warn',
         'message': f'AML のしきい値 KEYBALL_AML_THRESHOLD = {kb.aml_threshold} (LisM {lism_aml["threshold"]})'},
        {'level': 'ok' if 2 ** (st['scroll_div'] - 1) == 16 else 'warn',
         'message': f'スクロールの倍率 1/{2 ** (st["scroll_div"] - 1)} (KEYBALL_SCROLL_DIV_DEFAULT {st["scroll_div"]}、LisM 1/16)'},
        accel_consistency('カーソルの加速 KEYBALL_ACCEL_*', kb.accel, baseline_accel),
    ]
    return {
        'schema': SCHEMA, 'generator': GENERATOR, 'id': 'keyball39', 'name': 'Keyball39', 'kind': 'via',
        'sources': [sources.source_entry('keyball', [
            'qmk_firmware/keyboards/keyball/keyball39/keymaps/via/keymap.c',
            'qmk_firmware/keyboards/keyball/keyball39/keymaps/via/config.h',
            'qmk_firmware/keyboards/keyball/keyball39/keyball39.h',
            f'qmk_firmware/keyboards/keyball/keyball39/{kb.paths["info"].name}',
            'qmk_firmware/keyboards/keyball/lib/keyball/keyball.h']),
            sources.source_entry('docgen', ['vial_keymap_docgen.py'])],
        'device': {'usb_vid': '5957', 'usb_pid': '0200', 'usage_page': 'FF60', 'usage': '61'},
        'layers': [{'index': 0, 'name': 'BASE (LisM の BASE 相当)'}, {'index': 1, 'name': 'AML (MOUSE_MOVE 相当)'},
                   {'index': 2, 'name': 'SCROLL (MOUSE_SCROLL 相当)'}, {'index': 3, 'name': '設定'}],
        'physical': {'layout': 'LAYOUT_right_ball', 'keys': keys},
        'readout': {'via': {
            'protocol_min': 12, 'layer_count': len(kb.keymap), 'rows': kb.rows, 'cols': kb.cols,
            'keymap': kb.keymap, 'tokens': tokens,
            'layout_options': {'mask': 3, 'value': 1, 'ball': 'Right'},
            'macros_empty': True,
            'status': kb.status,
            'custom_keycodes': [[v, n] for n, v in sorted(kb.table.items(), key=lambda x: x[1]) if 0x7E00 <= v <= 0x7E3F],
        }},
        'interactive': {
            'taps': [], 'skipped': [],
            'trackball': {
                'balls': ['right'], 'ask_balls': False,
                'aml': {'layer': st['aml_layer'], 'scroll_layer': st['scroll_layer'],
                        'timeout_ms': st['aml_timeout'], 'require_prior_idle_ms': st['aml_delay'],
                        'threshold': kb.aml_threshold or 0},
                'keys': tb_keys,
                'firmware': kb.firmware(),
            },
            'output_switch': None,
            'behaviors': {'layers': [], 'scenarios': [], 'combos': 0, 'not_tested': [
                {'what': 'レイヤー・ビヘイビア', 'reason': 'Keyball39 は LisM の BASE のキーをそのまま送るだけ (レイヤー・タップホールド・'
                                                          'タップダンスなどは KQ-mini が担当)。KQ-mini につないで検査してください'}]},
        },
        'consistency': consistency,
    }


# KQ-mini の vial.json の customKeycodes[0..2] (OS ごとのキーの読み替え)。3 以降は zmk_to_vial のキャリア
KQ_OS_CUSTOM = ['DISABLE_KEY_OS_OVERRIDE', 'ENABLE_US_KEY_ON_JP_OS_OVERRIDE', 'ENABLE_JP_KEY_ON_US_OS_OVERRIDE']


def gen_kq_mini(sources: Sources, kd, zv, kb: Keyball, lism_behaviors: dict) -> dict:
    lism = sources.path('LisM')
    keymap = lism / 'config/lism.keymap'
    vialmap = lism / 'config/lism.vialmap.json'
    try:
        conv = zv.Converter(keymap, zv.load_config(vialmap)).convert()
    except zv.ConvertError as e:
        raise GenError(f'zmk_to_vial の変換に失敗しました: {e}') from e
    if conv.warnings:
        raise GenError('zmk_to_vial の変換で警告が出ました: ' + ' / '.join(conv.warnings))
    cfg = conv.config
    layer_count = int(cfg.get('layer_count', 8))
    layer_names = {}
    layers = []
    for vial_idx in range(layer_count):
        zmk_idx = next((z for z, v in conv.layer_map.items() if v == vial_idx), None)
        if zmk_idx is None:
            layers.append({'index': vial_idx, 'name': '(未使用)', 'zmk_index': None})
        else:
            name = conv.zmk_layer_names[zmk_idx]
            layers.append({'index': vial_idx, 'name': name, 'zmk_index': zmk_idx})
            alias = {v: k for k, v in conv.defines.items()}.get(zmk_idx)
            layer_names[vial_idx] = alias or name

    custom = [[0x7E00 + i, n] for i, n in enumerate(KQ_OS_CUSTOM)]
    for c in conv.carriers:
        custom.append([c.keycode, f'{c.zmk_name.upper()} (キャリア)'])

    tap_dances = []
    for td in sorted(conv.tap_dances, key=lambda t: t.index):
        tap_dances.append({'index': td.index, 'name': td.zmk_name, 'on_tap': td.on_tap, 'on_hold': td.on_hold,
                           'on_double_tap': td.on_double_tap, 'on_tap_hold': td.on_tap_hold, 'term': td.tapping_term})
    kos = []
    for i, ko in enumerate(conv.key_overrides):
        kos.append({'index': i, 'name': ko.zmk_name, 'description': ko.description,
                    'trigger': ko.trigger, 'replacement': ko.replacement, 'layers': ko.layers or 0xFFFF,
                    'trigger_mods': ko.trigger_mods, 'negative_mod_mask': ko.negative_mod_mask,
                    'suppressed_mods': ko.suppressed_mods, 'options': ko.options})
    macros = []
    for i in range(16):
        m = next((x for x in conv.macros if x.index == i), None)
        data = zv.macro_bytes(m.actions) if m else b''
        macros.append({'index': i, 'name': m.zmk_name if m else '', 'hex': data.hex(' ').upper()})
    settings = []
    for qsid, value in sorted(((int(k), int(v)) for k, v in cfg['settings'].items())):
        ctype, name = zv.qmk_setting_info(qsid)
        settings.append({'qsid': qsid, 'name': name, 'type': ctype, 'value': value})
    uid = [int(b, 0) if isinstance(b, str) else int(b) for b in (cfg.get('vial_uid') or [])]

    # 実動作テスト: Keyball39 の BASE のキー → KQ-mini の BASE で変換されたキー
    def kq_value(pos: int) -> int | None:
        code = kb.cell(0, pos)
        if not (0x04 <= code <= 0xE7):
            return None
        r, c = zv.hid_to_matrix(code)
        return conv.matrix[0][r][c]

    def kq_legend(pos: int) -> str:
        v = kq_value(pos)
        return '' if v is None else qmk_legend(v, layer_names)

    keys = [dict(k) for k in kb.keys]
    add_legends(keys, kq_legend)
    taps, skipped = [], []
    for k in keys:
        if not k['present']:
            continue
        v = kq_value(k['pos'])
        entry = {'pos': k['pos'], 'legend': k['legend'],
                 'src': f'Keyball {kb.tokens[0][k["pos"]]} → KQ-mini {zv.keycode_c_expr(v) if v is not None else "-"}'}
        t = qmk_tap(v) if v is not None else {'skip': '割り当てなし'}
        if 'skip' in t:
            entry['reason'] = t['skip']
            skipped.append(entry)
            continue
        if 'hold_layer' in t:
            n = int(t['hold_layer'][1:])
            t['hold_layer'] = layer_names.get(n, t['hold_layer'])
        entry.update(t)
        if t['usage'] in (0xE3, 0xE7):
            entry['special'] = 'gui'
        taps.append(entry)

    def tap_usage(pos: int) -> int:
        t = qmk_tap(kq_value(pos) or 0)
        if 'usage' not in t:
            raise GenError(f'KQ-mini: Keyball の位置 {pos} が BASE でキーを出しません')
        return t['usage']
    tb_keys = kb.trackball_keys(tap_usage)
    for hand in tb_keys.values():
        for v in hand.values():
            v['legend'] = keys[v['pos']]['legend']
    st = kb.status
    hold_tap, ht_consistency = kq_hold_tap(conv, zv, kb, keys, settings, layer_names)

    return {
        'schema': SCHEMA, 'generator': GENERATOR, 'id': 'kq-mini', 'name': 'Keyboard Quantizer Mini (+ Keyball39)',
        'kind': 'vial',
        'sources': [sources.source_entry('LisM', ['config/lism.keymap', 'config/lism.vialmap.json']),
                    sources.source_entry('docgen', ['zmk_to_vial.py']),
                    sources.source_entry('keyball', ['qmk_firmware/keyboards/keyball/keyball39/keymaps/via/keymap.c'])],
        'device': {'usb_vid': 'FEED', 'usb_pid': '999C', 'usage_page': 'FF60', 'usage': '61', 'vial_uid': uid},
        'layers': layers,
        'physical': {'layout': 'Keyball39 (LAYOUT_right_ball)', 'keys': keys},
        'readout': {'vial': {
            'layer_count': layer_count, 'rows': zv.MATRIX_ROWS, 'cols': zv.MATRIX_COLS,
            'keymap': conv.matrix,
            'tap_dance': {'count': 32, 'entries': tap_dances},
            'key_override': {'count': 32, 'entries': kos},
            'combo': {'count': 32, 'expect_empty': True},
            'alt_repeat': {'count': 32, 'expect_empty': True},
            'macro': {'count': 16, 'entries': macros},
            'settings': settings,
            'custom_keycodes': custom,
            # マウスの中継 (quantizer_mouse.c): このセルの値で X / Y / ホイール / ボタンの扱いが決まる
            'mouse_cells': [
                {'row': 26, 'col': 7, 'what': 'マウスの X (KC_MS_L 以外だとスクロールになるか転送されない)'},
                {'row': 26, 'col': 5, 'what': 'マウスの Y (KC_MS_U 以外だとスクロールになるか転送されない)'},
                {'row': 28, 'col': 1, 'what': 'ホイール上'}, {'row': 28, 'col': 2, 'what': 'ホイール下'},
                {'row': 28, 'col': 3, 'what': 'ホイール左'}, {'row': 28, 'col': 4, 'what': 'ホイール右'},
                {'row': 27, 'col': 1, 'what': 'マウスボタン 1'}, {'row': 27, 'col': 2, 'what': 'マウスボタン 2'},
            ],
        }},
        'interactive': {
            'taps': taps, 'skipped': skipped,
            'trackball': {
                'balls': ['right'], 'ask_balls': False,
                'aml': {'layer': st['aml_layer'], 'scroll_layer': st['scroll_layer'],
                        'timeout_ms': st['aml_timeout'], 'require_prior_idle_ms': st['aml_delay'],
                        'threshold': kb.aml_threshold or 0},
                'keys': tb_keys,
                'firmware': kb.firmware() + [{'side': 'kq-mini', 'sensor': None, 'cpi': None, 'cpi_source': None, 'cpi_setting': None,
                                              'xy_scaler': [1, 1], 'xy_scaler_set': False, 'matrix': None, 'divisor': None,
                                              'correction': 'none', 'accel': None,
                                              'listener': 'KQ-mini はマウスを等倍で中継する (倍率は変えられない)'}],
            },
            'output_switch': None,
            'behaviors': kq_behaviors(conv, zv, kb, keys, lism_behaviors),
            'hold_tap': hold_tap,
        },
        'consistency': ht_consistency,
    }


def kq_behaviors(conv, zv, kb: Keyball, keys: list[dict], lism_behaviors: dict) -> dict:
    """LisM のレイヤー・ビヘイビアのテストを、Keyball39 の位置に置き換える。
    LisM の位置 → (zmk_to_vial の position_matrix) KQ-mini の行列 ← (hid_to_matrix) Keyball の BASE のキーコード"""
    by_cell: dict[tuple[int, int], list[int]] = {}
    for k in keys:
        if not k['present']:
            continue
        code = kb.cell(0, k['pos'])
        if 0x04 <= code <= 0xE7:
            by_cell.setdefault(tuple(zv.hid_to_matrix(code)), []).append(k['pos'])
    pos_map = {}
    for lpos, cell in sorted(conv.position_matrix.items()):
        if cell is None:
            continue
        cands = by_cell.get(tuple(cell), [])
        if cands:
            pos_map[lpos] = lpos if lpos in cands else cands[0]
    data = behaviors.translate(lism_behaviors, pos_map, keys, set(conv.layer_map))
    data['note'] = ('LisM のキーマップから作った手順を、Keyball39 の位置に置き換えたもの。KQ-mini のキーオーバーライドは、'
                    '修飾キーより先に、タップしたキーを離す')
    return data


# ============================================================================
# JSON 出力 (決定的な整形)
# ============================================================================

def _is_scalar(v) -> bool:
    return v is None or isinstance(v, (bool, int, float, str))


def dumps(obj, indent: int = 0) -> str:
    pad = '  ' * indent
    pad1 = '  ' * (indent + 1)
    if _is_scalar(obj):
        return json.dumps(obj, ensure_ascii=False)
    if isinstance(obj, dict):
        if not obj:
            return '{}'
        if len(obj) <= 12 and all(_is_scalar(v) or (isinstance(v, list) and all(_is_scalar(x) for x in v) and len(v) <= 8)
                                 for v in obj.values()):
            one = '{' + ', '.join(f'{json.dumps(k, ensure_ascii=False)}: {dumps(v)}' for k, v in obj.items()) + '}'
            if len(one) <= 200:
                return one
        items = [f'{pad1}{json.dumps(k, ensure_ascii=False)}: {dumps(v, indent + 1)}' for k, v in obj.items()]
        return '{\n' + ',\n'.join(items) + '\n' + pad + '}'
    if isinstance(obj, (list, tuple)):
        if not obj:
            return '[]'
        if all(_is_scalar(v) for v in obj):
            return '[' + ', '.join(json.dumps(v, ensure_ascii=False) for v in obj) + ']'
        items = [pad1 + dumps(v, indent + 1) for v in obj]
        return '[\n' + ',\n'.join(items) + '\n' + pad + ']'
    raise TypeError(f'JSON にできない値です: {obj!r}')


def generate(sources: Sources) -> dict[str, str]:
    kd, zv, vd = import_docgen(sources)
    out: dict[str, dict] = {'common.json': gen_common(zv)}
    lism = None
    # カーソルの加速の基準: LisM の trackball_accel
    lism_board = ZMK_BOARDS[0]
    baseline = xy_accel_nodes(sources.path(lism_board['sub']), [lism_board['dtsi']]).get('trackball_accel')
    if baseline is None:
        raise GenError(f'{lism_board["dtsi"]} に trackball_accel がありません')
    # AML の発動条件の基準: LisM の aml_threshold
    baseline_aml = aml_threshold_nodes(sources.path(lism_board['sub']), [lism_board['dtsi']]).get('aml_threshold')
    # タップホールドの基準: LisM の &mt / &lt
    baseline_ht = zmk_hold_tap_config(ZmkKeymap(kd, zv, sources.path(lism_board['sub']) / lism_board['keymap']))
    for board in ZMK_BOARDS:
        data = gen_zmk(board, sources, kd, zv, baseline, baseline_aml, baseline_ht)
        out[f'{board["id"]}.json'] = data
        if board['id'] == 'lism':
            lism = data
    kb = Keyball(sources, kd, zv, vd)
    out['keyball39.json'] = gen_keyball(kb, sources, lism['interactive']['trackball']['aml'], baseline)
    out['kq-mini.json'] = gen_kq_mini(sources, kd, zv, kb, lism['interactive']['behaviors'])
    return {name: dumps(data) + '\n' for name, data in out.items()}


def without_commits(text: str):
    """期待値の JSON から、元にした submodule のコミット (sources[].commit) を除いたもの。"""
    data = json.loads(text)
    for src in data.get('sources', []):
        src.pop('commit', None)
    return data


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description='tools/keyboard-check の期待値 (tools/expected/*.json) を生成する')
    ap.add_argument('--check', action='store_true', help='生成し直した結果とコミット済みのファイルを比べる (差があれば終了コード 1)')
    ap.add_argument('--only', action='append', default=[], help='このファイルだけ書き出す (例: lism)')
    ap.add_argument('--source', action='append', default=[], metavar='NAME=PATH',
                    help=f'submodule の代わりに使うパス (NAME: {", ".join(SUBMODULES)})')
    ap.add_argument('--out-dir', type=Path, default=HERE, help=argparse.SUPPRESS)
    args = ap.parse_args(argv)

    overrides = {}
    for s in args.source:
        name, _, path = s.partition('=')
        if name not in SUBMODULES or not path:
            ap.error(f'--source は NAME=PATH の形で、NAME は {", ".join(SUBMODULES)} のどれかです')
        overrides[name] = Path(path).resolve()
    sources = Sources(overrides)
    try:
        files = generate(sources)
    except GenError as e:
        print(f'エラー: {e}', file=sys.stderr)
        return 2
    for w in sources.warnings:
        print(f'警告: {w}', file=sys.stderr)
    if args.only:
        wanted = {o if o.endswith('.json') else f'{o}.json' for o in args.only}
        files = {k: v for k, v in files.items() if k in wanted}

    if args.check:
        stale, commit_only = [], []
        for name, text in files.items():
            p = args.out_dir / name
            if not p.exists():
                stale.append(name)
                continue
            old = p.read_text(encoding='utf-8')
            if old == text:
                continue
            if without_commits(old) == without_commits(text):
                commit_only.append(name)
            else:
                stale.append(name)
        if stale:
            print('期待値が submodule の内容と合っていません: ' + ', '.join(stale), file=sys.stderr)
            print('python tools/expected/generate.py を実行して、結果をコミットしてください。', file=sys.stderr)
            return 1
        if commit_only:
            # submodule の参照だけが進み、期待値の内容は変わらない (CI を失敗にはしない)
            print('submodule のコミットだけが違います (期待値の内容は同じ): ' + ', '.join(commit_only))
        print(f'期待値は最新です ({len(files)} ファイル)')
        return 0

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        (args.out_dir / name).write_text(text, encoding='utf-8', newline='\n')
        print(f'書き出しました: {(args.out_dir / name).relative_to(ROOT) if args.out_dir == HERE else args.out_dir / name}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
