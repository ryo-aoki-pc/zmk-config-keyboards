#!/usr/bin/env python3
"""チェックアウト済みの設定を読み取り、シミュレータ用モデルを出力する。

期待値 JSON は入力にしない。submodule のファイルと参照は変更しない。
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location('simulator_source_parser', ROOT / 'tools/expected/generate.py')
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)
bh = gen.behaviors

BOARD_IDS = tuple(b['id'] for b in gen.ZMK_BOARDS) + ('keyball39', 'kq-mini')
KQ_PATH = 'vial-qmk-kq-mini'
KQ_KEYMAP = 'keyboards/sekigon/keyboard_quantizer/mini/keymaps/vial'
# 下記の実装だけを、既定マウス設定でそのまま通せることを確認している。
# 別実装になった場合は連携テストのマウスを拒否し、再検証を必要とする。
KQ_MOUSE_SOURCE_SHA256 = 'fc14526847ad5d604df060a3d6497de196efceeaa75e13f459cb47c887b8a9cc'


class ModelError(ValueError):
    """元の設定を安全に解釈できない。"""


def _unsupported(src: str, reason: str, **extra) -> dict:
    return {'kind': 'other', 'src': src, 'reason': reason, **extra}


def source_entry(root: Path, relative: str, files: list[str]) -> dict:
    path = root / relative
    result = subprocess.run(['git', '-C', str(path), 'rev-parse', 'HEAD'],
                            text=True, capture_output=True, check=True)
    unique = sorted(set(files))
    # 同じ HEAD の未コミット変更もレポートで区別できるようにする。
    hashes = {name: hashlib.sha256((path / name).read_bytes()).hexdigest() for name in unique}
    return {'submodule': relative, 'commit': result.stdout.strip(), 'files': unique, 'sha256': hashes}


def _int_prop(body: str, name: str, default: int | None = None) -> int:
    value = bh.parse_int_prop(body, name)
    if value is None:
        if re.search(r'(?<![\w-])' + re.escape(name) + r'\s*=', body):
            raise ModelError(f'{name} の値を解釈できません')
        if default is None:
            raise ModelError(f'{name} がありません')
        return default
    return value


def _mod_prop(body: str, name: str) -> int:
    match = re.search(r'(?<![\w-])' + re.escape(name) + r'\s*=\s*<(.*?)>\s*;', body, re.S)
    if not match:
        return 0
    residue = re.sub(r'MOD_[LR](?:CTL|SFT|ALT|GUI)|[()|\s]', '', match.group(1))
    if residue:
        raise ModelError(f'{name} の修飾を解釈できません: {residue}')
    return bh.parse_mod_expr(body, name)


class ZmkBindings:
    def __init__(self, km, zv, macro_wait_ms=15, macro_tap_ms=30):
        self.km, self.zv = km, zv
        self.hold_taps = gen.zmk_hold_tap_config(km)
        self.macro_wait_ms, self.macro_tap_ms = macro_wait_ms, macro_tap_ms

    def binding(self, text: str, stack: tuple[str, ...] = ()) -> dict:
        head, args = bh.split_binding(text)

        def arity(count):
            if len(args) != count:
                raise ModelError(f'引数の数が違います: {text}')

        if head in ('none', 'trans'):
            arity(0)
            return {'kind': head, 'src': text}
        if head == 'kp':
            arity(1)
            return {**gen.zmk_kp_entry(self.zv, args[0]), 'src': text}
        if head in ('mo', 'to', 'tog'):
            arity(1)
            layer = int(args[0])
            if not 0 <= layer < len(self.km.layers):
                raise ModelError(f'レイヤー番号が範囲外です: {text}')
            return {'kind': head, 'layer': layer, 'src': text}
        if head == 'mkp':
            arity(1)
            mask = gen.ZMK_MOUSE_BUTTONS.get(args[0])
            if mask is None:
                raise ModelError(f'マウスボタンを解釈できません: {text}')
            return {'kind': 'button', 'usage': mask.bit_length(), 'src': text}
        if head in self.hold_taps:
            arity(2)
            config = self.hold_taps[head]
            return {'kind': 'ht', 'behavior': head, 'src': text,
                    'hold': self.binding(config['bindings'][0] + ' ' + args[0], stack),
                    'tap': self.binding(config['bindings'][1] + ' ' + args[1], stack)}
        if head in self.km.custom:
            arity(0)
            if head in stack:
                raise ModelError(f'ビヘイビアが循環参照しています: {" → ".join((*stack, head))}')
            node = self.km.custom[head]
            if node['cells']:
                raise ModelError(f'引数付きビヘイビアには対応していません: {text}')
            body = node['body']
            match = re.search(r'compatible\s*=\s*"([^"]+)"', body)
            if not match:
                raise ModelError(f'compatible がありません: {text}')
            compatible = match.group(1)
            groups = bh.parse_binding_groups(body)
            children = [b for group in groups for b in group]
            nested = (*stack, head)
            result = {'src': text, 'behavior': head}
            if compatible == 'zmk,behavior-mod-morph':
                if len(children) != 2:
                    raise ModelError(f'mod-morph の分岐数が違います: {text}')
                return {**result, 'kind': 'morph', 'mask_mods': _mod_prop(body, 'mods'),
                        'keep_mods': _mod_prop(body, 'keep-mods'),
                        'bindings': [self.binding(b, nested) for b in children]}
            if compatible == 'zmk,behavior-tap-dance':
                if not children:
                    raise ModelError(f'tap-dance の分岐がありません: {text}')
                return {**result, 'kind': 'dance', 'term': _int_prop(body, 'tapping-term-ms', 200),
                        'bindings': [self.binding(b, nested) for b in children]}
            if compatible == 'zmk,behavior-macro':
                mode, steps = 'tap', []
                for child in children:
                    action, parameters = bh.split_binding(child)
                    if action in ('macro_tap', 'macro_press', 'macro_release'):
                        if parameters:
                            raise ModelError(f'マクロ制御の引数が違います: {child}')
                        mode = action.removeprefix('macro_')
                    elif action in ('macro_wait_time', 'macro_tap_time'):
                        if len(parameters) != 1 or not parameters[0].isdigit():
                            raise ModelError(f'マクロ時間の引数が違います: {child}')
                        steps.append({'kind': action.removeprefix('macro_'), 'ms': int(parameters[0])})
                    elif action == 'macro_pause_for_release':
                        if parameters:
                            raise ModelError(f'マクロ制御の引数が違います: {child}')
                        steps.append({'kind': 'pause'})
                    else:
                        steps.append({'kind': mode, 'binding': self.binding(child, nested)})
                return {**result, 'kind': 'macro', 'wait_ms': _int_prop(body, 'wait-ms', self.macro_wait_ms),
                        'tap_ms': _int_prop(body, 'tap-ms', self.macro_tap_ms), 'steps': steps}
            return _unsupported(text, f'未対応のカスタムビヘイビア: {compatible}')
        # 知っているが、HID 以外の副作用などを再現しない標準ビヘイビア。
        if head in self.km.builtin:
            self.km.encode(text)  # 引数とキーコードも検証する。
            return _unsupported(text, f'未対応の標準ビヘイビア: &{head}')
        raise ModelError(f'知らないビヘイビアです: {text}')


def _transform(processors: str) -> int:
    result = 0
    for match in re.finditer(r'&zip_(?:xy|scroll)_transform\s+([^>]*)', processors):
        expression = match.group(1)
        known = {'INPUT_TRANSFORM_X_INVERT': 1, 'INPUT_TRANSFORM_Y_INVERT': 2, 'INPUT_TRANSFORM_XY_SWAP': 4}
        residue = expression
        for name, bit in known.items():
            if name in expression:
                result |= bit
            residue = residue.replace(name, '')
        if re.sub(r'[()|\s]', '', residue):
            raise ModelError(f'軸の変換を解釈できません: {expression}')
    return result


def _node_body(kd, text: str, label: str) -> str:
    match = re.search(r'(?:&|\b)' + re.escape(label) + r'\s*(?::\s*[\w-]+\s*)?\{', text)
    if not match:
        raise ModelError(f'入力リスナーがありません: {label}')
    start, end = kd.find_balanced_block(text, match.end() - 1)
    return text[start:end]


def zmk_pointer(board, base: Path, km, kd) -> dict:
    firmware, gates, _ = gen.zmk_trackball_firmware(board, base)
    raw = gen.zmk_trackball_firmware_base(board, base)
    body = _node_body(kd, km.text, 'zip_temp_layer')
    excluded = re.search(r'excluded-positions\s*=\s*<([^>]*)>', body)
    out = {'engine': 'zmk', 'transport': 'usb', 'aml_layer': km.layer_index('MOUS'), 'scroll_layer': km.layer_index('SCRL'),
           'prior_idle_ms': _int_prop(body, 'require-prior-idle-ms', 0),
           'excluded_positions': [int(x) for x in excluded.group(1).split()] if excluded else [],
           'listeners': []}
    for entry, source, gate in zip(firmware, raw, gates):
        side = entry['side']
        text = source['processors']
        gate_label = gate['label'] if gate else 'zip_temp_layer'
        aml = re.search(r'&' + re.escape(gate_label) + r'\s+(\d+)\s+(\d+)', text)
        if not aml or int(aml.group(1)) != out['aml_layer']:
            raise ModelError(f'AML のレイヤーを解釈できません: {board["id"]}/{side}')
        timeout = int(aml.group(2))
        threshold = gate['threshold'] if gate else 0
        if out.get('aml_timeout_ms', timeout) != timeout or out.get('aml_threshold', threshold) != threshold:
            raise ModelError('左右で異なる AML 条件には対応していません')
        out.update(aml_timeout_ms=timeout, aml_threshold=threshold)
        cursor_transform = _transform(text)
        if board['id'] == 'lism':
            relative, label = 'snippets/trackball-central/trackball.overlay', 'central_listener' if side == 'right' else 'peripheral_listener'
        elif board['id'] == 'pyuron':
            relative, label = board['dtsi'], 'trackball_listener_' + ('L' if side == 'left' else 'R')
        else:
            relative = next(f for f in board['files'] if f.endswith('_R.overlay') or f.endswith('_right.overlay'))
            label = 'pointing_listener' if board['id'] == 'torabo-tsuki-lp' else 'trackball_listener'
        listener = _node_body(kd, gen.strip_c_comments(gen.read_text(base / relative)), label)
        chains = gen.scroll_chains(listener, out['scroll_layer'])
        scroll_transform = 0
        if board['id'] == 'kukey42':
            conf = gen.read_text(base / 'boards/shields/KUKEY42/KUKEY42_R.conf')
            tick = re.search(r'^CONFIG_PMW3610_SCROLL_TICK=(\d+)$', conf, re.M)
            if not tick:
                raise ModelError('KUKEY42 のスクロール単位がありません')
            scroll_scaler = [1, int(tick.group(1))]
            # ドライバの X 反転は既定の HWHEEL 反転を打ち消す。
            scroll_x_sign = 1 if 'CONFIG_PMW3610_INVERT_SCROLL_X=y' in conf else -1
            scroll_y_sign = 1 if 'CONFIG_PMW3610_INVERT_SCROLL_Y=y' in conf else -1
        else:
            if len(chains) != 1:
                raise ModelError(f'スクロールチェーンを一意に決められません: {board["id"]}/{side}')
            scroll_proc = chains[0][1]
            scroll_transform = _transform(scroll_proc)
            scale = re.search(r'&zip_scroll_scaler\s+(\d+)\s+(\d+)', scroll_proc)
            if not scale or '&zip_xy_to_scroll_mapper' not in scroll_proc:
                raise ModelError(f'スクロール処理を解釈できません: {board["id"]}/{side}')
            scroll_scaler = [int(scale.group(1)), int(scale.group(2))]
            scroll_x_sign, scroll_y_sign = 1, 1
            if not re.search(r'&zip_temp_layer\s+' + str(out['aml_layer']) + r'\s+' + str(timeout), scroll_proc):
                raise ModelError(f'スクロール中の AML 更新を解釈できません: {board["id"]}/{side}')
        if board['id'] == 'lism' and side == 'left':
            split_text = gen.strip_c_comments(gen.read_text(base / 'snippets/trackball-peripheral/trackball.overlay'))
            split_transform = _transform(_node_body(kd, split_text, 'trackball_split'))
            if split_transform & 4:
                raise ModelError('分割側の軸入れ替えには対応していません')
            cursor_transform ^= split_transform
            scroll_transform ^= split_transform
        rate = re.search(r'&trackball_rate_limit\s+(\d+)', text)
        if rate:
            rate_body = _node_body(kd, gen.strip_c_comments(gen.read_text(base / relative)), 'trackball_rate_limit')
            if 'limit-ble-only;' not in rate_body:
                raise ModelError('USB に適用されるレポート制限には対応していません')
        out['listeners'].append({'side': side, 'transform': cursor_transform, 'scroll_transform': scroll_transform,
                                 'x_scaler': entry['x_scaler'], 'y_scaler': entry['y_scaler'],
                                 'xy_scaler': entry['xy_scaler'], 'scroll_scaler': scroll_scaler,
                                 'scroll_x_sign': scroll_x_sign, 'scroll_y_sign': scroll_y_sign,
                                 'accel': entry['accel'], 'rate_limit_ms': int(rate.group(1)) if rate else 0,
                                 'sensor': entry['sensor'], 'cpi': entry['cpi'],
                                 'scroll_supported': board['id'] != 'kukey42'})
        if board['id'] == 'kukey42':
            out['listeners'][-1]['unsupported_scroll_reason'] = (
                'PMW3610 ドライバ側のスクロール処理は外部リポジトリの main を参照しているため再現対象外です')
    return out


def _zmk(board, sources, kd, zv, root) -> dict:
    base = sources.path(board['sub'])
    km = gen.ZmkKeymap(kd, zv, base / board['keymap'])
    lengths = {len(layer) for layer in km.layers}
    if len(lengths) != 1 or not next(iter(lengths)):
        raise ModelError('レイヤーごとのキー数がそろっていません')
    count = lengths.pop()
    conf_files = sorted(base.rglob('*.conf'))
    options = {}
    for path in conf_files:
        for name, value in re.findall(r'^(CONFIG_ZMK_(?:HID_SEPARATE_MOD_RELEASE_REPORT|MACRO_DEFAULT_WAIT_MS|MACRO_DEFAULT_TAP_MS))=(\w+)\s*$',
                                      gen.read_text(path), re.M):
            if name in options and options[name] != value:
                raise ModelError(f'構成によって {name} が異なります。対象を一意に決められません')
            options[name] = value
    separate_release = options.get('CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT', 'n')
    if separate_release not in ('y', 'n'):
        raise ModelError('CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT は y/n が必要です')
    parser = ZmkBindings(km, zv, int(options.get('CONFIG_ZMK_MACRO_DEFAULT_WAIT_MS', '15')),
                         int(options.get('CONFIG_ZMK_MACRO_DEFAULT_TAP_MS', '30')))
    keys = gen.physical_keys(kd, base / board['layout'], count)
    for key in keys:
        key.update(present=True, on={str(i): parser.binding(layer[key['pos']]) for i, layer in enumerate(km.layers)})
    combos = bh.parse_combos(kd, km.text)
    if combos:
        raise ModelError('コンボの時間判定には対応していません')
    return {'schema_version': 1, 'id': board['id'], 'name': board['name'], 'engine': 'zmk',
            'sources': [source_entry(root, gen.SUBMODULES[board['sub']], board['files'] + ['config/west.yml'] +
                                    [str(path.relative_to(base)) for path in conf_files]),
                        source_entry(root, 'zmk-keymap-docgen', ['keymap_docgen.py']),
                        source_entry(root, 'zmk-input-processor-xy-accel', ['src/input_processor_xy_accel.c']),
                        source_entry(root, 'zmk-input-processor-aml-threshold', ['src/input_processor_aml_threshold.c'])],
            'layers': [{'index': i, 'name': km.layer_name(i)} for i in range(len(km.layers))],
            'keys': keys, 'behaviors': parser.hold_taps,
            'custom_behaviors': {name: parser.binding('&' + name) for name in km.custom if name not in parser.hold_taps},
            'settings': {},
            'zmk_settings': {'separate_mod_release_report': separate_release == 'y'},
            'pointer': zmk_pointer(board, base, km, kd),
            'limitations': ['USB 接続時の入力処理を対象とする。BLE のレポート集約と無線通信は対象外。']}


class QmkBindings:
    def __init__(self, zv, vial=None):
        self.zv, self.vial = zv, vial
        self.names = gen.qmk_name_table(zv, '')
        self.names.update({name: value for value, name in zv.V6_BASIC_NAMES.items()})
        self.carriers = set()

    def token(self, token: str) -> int:
        if token in self.names:
            return self.names[token]
        if re.fullmatch(r'M\d+', token):
            return 0x7700 + int(token[1:])
        if re.fullmatch(r'USER\d+', token):
            return 0x7E00 + int(token[4:])
        match = re.fullmatch(r'(\w+)\((.*)\)', token)
        if match:
            name, arg = match.groups()
            if name in ('MO', 'TO', 'TG', 'TD') and arg.isdigit():
                return {'MO': 0x5220, 'TO': 0x5200, 'TG': 0x5260, 'TD': 0x5700}[name] | int(arg)
            wraps = {v: k for k, v in self.zv.MOD5_TO_WRAP_NAME.items()}
            if name in wraps:
                return (wraps[name] << 8) | self.token(arg)
        raise ModelError(f'Vial のキーコードを解釈できません: {token}')

    def binding(self, value: int, layer: int = -1, stack: tuple[int, ...] = (), overrides=True) -> dict:
        if type(value) is not int or not 0 <= value <= 65535:
            raise ModelError(f'QMK キーコードが範囲外です: {value}')
        src = f'0x{value:04X}'
        if value in stack:
            raise ModelError(f'Vial のビヘイビアが循環参照しています: {src}')
        if value in self.carriers:
            return {'kind': 'none', 'src': src, 'carrier': True}
        if value == 0:
            return {'kind': 'none', 'src': src}
        if value == 1:
            return {'kind': 'trans', 'src': src}
        if 0xD1 <= value <= 0xD8:
            return {'kind': 'button', 'usage': value - 0xD0, 'src': src}
        if 4 <= value <= 0xA4 or 0xE0 <= value <= 0xE7:
            return {'kind': 'kp', 'usage': value, 'mods': 0, 'src': src}
        if 0x100 <= value < 0x2000:
            entry = gen.qmk_entry(value, {})
            if entry['kind'] == 'kp':
                return {**entry, 'src': src}
        if 0x2000 <= value < 0x5000:
            return {**gen.qmk_entry(value, {}), 'src': src}
        for base, kind in ((0x5200, 'to'), (0x5220, 'mo'), (0x5260, 'tog')):
            if base <= value < base + 32:
                return {'kind': kind, 'layer': value - base, 'src': src}
        if self.vial and 0x5700 <= value < 0x5800:
            index = value - 0x5700
            dances = self.vial.get('tap_dance', [])
            if index >= len(dances) or len(dances[index]) != 5:
                raise ModelError(f'Vial tap dance がありません: {src}')
            row = dances[index]
            return {'kind': 'qdance', 'term': row[4], 'src': src,
                    'bindings': [self.binding(self.token(token), layer, (*stack, value), False) for token in row[:4]]}
        if self.vial and 0x7700 <= value < 0x7780:
            index = value - 0x7700
            macros = self.vial.get('macro', [])
            if index >= len(macros):
                raise ModelError(f'Vial マクロがありません: {src}')
            steps = []
            for action in macros[index]:
                if len(action) < 2 or action[0] not in ('tap', 'down', 'up', 'delay'):
                    raise ModelError(f'Vial マクロの命令を解釈できません: {action}')
                if action[0] == 'delay':
                    if len(action) != 2 or type(action[1]) is not int or action[1] < 0:
                        raise ModelError(f'Vial マクロの時間が不正です: {action}')
                    steps.append({'kind': 'wait', 'ms': action[1]})
                else:
                    for token in action[1:]:
                        steps.append({'kind': {'tap': 'tap', 'down': 'press', 'up': 'release'}[action[0]],
                                      'binding': self.binding(self.token(token), layer, (*stack, value), False)})
            return {'kind': 'qmacro', 'wait_ms': 0, 'tap_ms': 0, 'steps': steps, 'src': src}
        return _unsupported(src, '未対応の QMK キーコードです')


def _keyball(sources, kd, zv, vd, root):
    kb = gen.Keyball(sources, kd, zv, vd)
    parser = QmkBindings(zv)
    keys = []
    for key in kb.keys:
        keys.append({**key, 'on': {str(i): parser.binding(kb.cell(i, key['pos']), i) for i in range(len(kb.keymap))}})
    config = gen.read_text(kb.paths['config'])
    library_header = gen.read_text(kb.paths['lib_h'])
    keymap_text = gen.read_text(kb.paths['keymap'])
    excluded = []
    for letter in ('D', 'K'):
        row = gen.define_int(keymap_text, f'KEYBALL_{letter}_KEYPOS_ROW')
        col = gen.define_int(keymap_text, f'KEYBALL_{letter}_KEYPOS_COL')
        matches = [key['pos'] for key in keys if key['matrix'] == [row, col]]
        if len(matches) != 1:
            raise ModelError(f'Keyball の AML 除外位置を解釈できません: {letter}')
        excluded.extend(matches)
    inhibitor = gen.define_int(config, 'KEYBALL_SCROLLBALL_INHIVITOR')
    if inhibitor is None:
        inhibitor = gen.define_int(library_header, 'KEYBALL_SCROLLBALL_INHIVITOR')
    if inhibitor is None:
        raise ModelError('Keyball のスクロール抑制時間がありません')
    pointer = {'engine': 'keyball', 'transport': 'usb', 'aml_layer': kb.status['aml_layer'], 'scroll_layer': kb.status['scroll_layer'],
               'aml_timeout_ms': kb.status['aml_timeout'], 'prior_idle_ms': kb.status['aml_delay'],
               'aml_threshold': kb.aml_threshold, 'excluded_positions': excluded, 'scroll_inhibitor_ms': inhibitor,
               'listeners': [{'side': 'right', 'transform': 4, 'scroll_transform': 6,
                              'x_scaler': [kb.xy_scale[0], 1000] if kb.xy_scale else [1, 1],
                              'y_scaler': [kb.xy_scale[1], 1000] if kb.xy_scale else [1, 1],
                              'scroll_scaler': [1, 1 << (kb.status['scroll_div'] - 1)],
                              'scroll_x_sign': 1, 'scroll_y_sign': 1,
                              'accel': kb.accel, 'report_interval_ms': kb.accel['interval_ms'] if kb.accel else 8}]}
    return {'schema_version': 1, 'id': 'keyball39', 'name': 'Keyball39', 'engine': 'qmk',
            'sources': [source_entry(root, 'keyball', [str(p.relative_to(root / 'keyball')) for n, p in kb.paths.items() if n != 'dir'] +
                                     ['qmk_firmware/keyboards/keyball/lib/keyball/keyball.c'])],
            'layers': [{'index': i, 'name': f'L{i}'} for i in range(len(kb.keymap))],
            'keys': keys, 'behaviors': {}, 'settings': dict(gen.KQ_HT_DEFAULTS), 'pointer': pointer}


def _kq_mouse_passthrough(vial, config, parser, base: Path, root: Path) -> tuple[bool, str]:
    """量子化側を通さず連携できる、既定のマウス設定だけを厳密に確認する。"""
    mouse_source = gen.read_text(base / 'quantizer_mouse.c')
    if hashlib.sha256(mouse_source.encode('utf-8')).hexdigest() != KQ_MOUSE_SOURCE_SHA256:
        return False, 'quantizer_mouse.c が検証済みの実装と異なるため、マウスの連携は未対応です'
    columns = gen.define_int(config, 'MATRIX_COLS_DEFAULT')
    gesture_row = gen.define_int(config, 'MATRIX_MSGES_ROW')
    if columns != 8 or gesture_row != 31:
        return False, 'マウスまたはジェスチャーの行列配置が検証済みの設定と異なります'
    codes = gen.read_text(root / KQ_PATH / 'quantum/keycodes.h')
    names = ['QK_MOUSE_CURSOR_' + direction for direction in ('UP', 'DOWN', 'LEFT', 'RIGHT')]
    names += [f'QK_MOUSE_BUTTON_{i}' for i in range(1, 9)]
    names += ['QK_MOUSE_WHEEL_' + direction for direction in ('UP', 'DOWN', 'LEFT', 'RIGHT')]
    names += [f'QK_MOUSE_ACCELERATION_{i}' for i in range(3)]
    mouse_codes = []
    for name in names:
        match = re.search(r'\b' + name + r'\s*=\s*(0x[0-9A-Fa-f]+|\d+)\s*,', codes)
        if not match:
            raise ModelError(f'QMK のマウスキー定義がありません: {name}')
        mouse_codes.append(int(match.group(1), 0))
    if mouse_codes != list(range(0xCD, 0xE0)):
        return False, 'QMK のマウスキー番号が検証済みの定義と異なります'
    for layer_index, layer in enumerate(vial['layout']):
        for code in mouse_codes:
            row, col = code // columns + 1, code & 7
            expected = code if layer_index == 0 else 1
            if layer[row][col] != expected:
                return False, f'L{layer_index} のマウスキー 0x{code:02X} が既定の通過設定ではありません'
        # process_gesture は4方向を使う。未使用セルも保守的に既定値だけ許す。
        if layer[gesture_row] != [0 if layer_index == 0 else 1] * columns:
            return False, f'L{layer_index} に既定以外のジェスチャー設定があります'
    for override in vial.get('key_override', []):
        if override.get('options', 0) & 0x80:
            code = parser.token(override['trigger'])
            if code in mouse_codes or code in (0, 1):
                return False, 'マウスまたはジェスチャー入力に対する key override は連携テストでは未対応です'
    return True, '全レイヤーのマウス入力は既定の通過設定で、ジェスチャー割当とマウス用 override はありません'


def _kq(sources, kd, zv, vd, root):
    base = root / KQ_PATH / KQ_KEYMAP
    vial = json.loads(gen.read_text(base / 'KEYMAP.vil'))
    if vial.get('version') != 1 or vial.get('vial_protocol') != 6:
        raise ModelError('未対応の Vial ファイル形式です')
    matrix = vial.get('layout')
    if not matrix or any(len(layer) != 32 or any(len(row) != 8 for row in layer) for layer in matrix):
        raise ModelError('KQ-mini の行列サイズは 32×8 である必要があります')
    if any(type(code) is not int or not 0 <= code <= 65535 for layer in matrix for row in layer for code in row):
        raise ModelError('Vial の行列は 0..65535 の整数だけを指定してください')
    if vial.get('combo'):
        raise ModelError('Vial コンボには対応していません')
    config = gen.read_text(base / 'config.h')
    if gen.define_int(config, 'DYNAMIC_KEYMAP_LAYER_COUNT') != len(matrix):
        raise ModelError('Vial のレイヤー数が config.h と一致しません')
    parser = QmkBindings(zv, vial)
    keymap_text = gen.strip_c_comments(gen.read_text(base / 'keymap.c'))
    handled_custom = {int(n) for n in re.findall(r'case\s+QK_KB_(\d+)\s*:', keymap_text)}
    for override in vial.get('key_override', []):
        if not override.get('options', 0) & 0x80:
            continue
        trigger = parser.token(override['trigger'])
        if 0x7E03 <= trigger <= 0x7E3F and trigger - 0x7E00 not in handled_custom:
            # 現在の process_record_user は QK_KB_0..2 だけを処理する。
            # その他の carrier は key override に一致しなければ何も送らない。
            parser.carriers.add(trigger)
    overrides = []
    for override in vial.get('key_override', []):
        if not override.get('options', 0) & 0x80:
            continue
        item = {key: override[key] for key in ('layers', 'trigger_mods', 'negative_mod_mask', 'suppressed_mods', 'options')}
        for key, value in item.items():
            maximum = 0xFFFF if key == 'layers' else 0xFF
            if type(value) is not int or not 0 <= value <= maximum:
                raise ModelError(f'Vial key override の {key} が不正です')
        item['trigger'] = f'0x{parser.token(override["trigger"]):04X}'
        item['replacement'] = parser.binding(parser.token(override['replacement']), overrides=False)
        overrides.append(item)
    settings = dict(gen.KQ_HT_DEFAULTS)
    for qsid, name in gen.KQ_HT_SETTINGS.items():
        if str(qsid) in vial.get('settings', {}):
            value = vial['settings'][str(qsid)]
            if type(value) is not int or value < 0:
                raise ModelError(f'Vial 設定 {name} の値が不正です')
            settings[name] = value
    keys = []
    for usage in range(240):
        row, col = zv.hid_to_matrix(usage)
        keys.append({'pos': usage, 'usage': usage, 'matrix': [row, col], 'present': True,
                     'hand': 'left' if col < 4 else 'right' if col > 4 else '*',
                     'qmk_hand': gen.kq_chordal_hand(usage),
                     'on': {str(i): parser.binding(layer[row][col], i) for i, layer in enumerate(matrix)}})
    mouse_verified, mouse_reason = _kq_mouse_passthrough(vial, config, parser, base, root)
    return {'schema_version': 1, 'id': 'kq-mini', 'name': 'Keyboard Quantizer Mini', 'engine': 'qmk',
            'sources': [source_entry(root, KQ_PATH, [KQ_KEYMAP + '/' + name for name in
                                                   ('KEYMAP.vil', 'config.h', 'keymap.c', 'quantizer_mouse.c')] +
                                     ['quantum/keycodes.h', 'quantum/process_keycode/process_key_override.c',
                                      'quantum/process_keycode/process_key_override.h', 'quantum/vial.c',
                                      'quantum/quantum.c', 'quantum/action_util.c']),
                        source_entry(root, 'zmk-keymap-docgen', ['zmk_to_vial.py'])],
            'layers': [{'index': i, 'name': f'L{i}'} for i in range(len(matrix))],
            'keys': keys, 'behaviors': {}, 'settings': settings, 'qmk_overrides': overrides, 'pointer': None,
            'requires': ['qmk_key_override'] if overrides else [],
            'mouse_passthrough_verified': mouse_verified, 'mouse_passthrough_reason': mouse_reason,
            'input_domain': 'HID usage (0..239。修飾キーは 0xE0..0xE7)'}


def export_keyboard(keyboard: str, root: Path = ROOT) -> dict:
    """機種の全レイヤーを読み取る。対応しない既知動作は other として明示する。"""
    if keyboard not in BOARD_IDS:
        raise ModelError(f'知らない機種です: {keyboard}')
    root = Path(root)
    sources = gen.Sources({name: root / path for name, path in gen.SUBMODULES.items()})
    kd, zv, vd = gen.import_docgen(sources)
    try:
        if keyboard == 'keyball39':
            return _keyball(sources, kd, zv, vd, root)
        if keyboard == 'kq-mini':
            return _kq(sources, kd, zv, vd, root)
        return _zmk(next(b for b in gen.ZMK_BOARDS if b['id'] == keyboard), sources, kd, zv, root)
    except ModelError:
        raise
    except (gen.GenError, KeyError, TypeError, IndexError, ValueError) as exc:
        raise ModelError(f'{keyboard}: 設定を読み取れません: {exc}') from exc


def validate_output_path(path: Path, root: Path = ROOT) -> Path:
    """エクスポート先で元の設定や親の追跡ファイルを上書きしない。"""
    resolved, root = path.resolve(), root.resolve()
    try:
        relative = resolved.relative_to(root)
    except ValueError:
        return resolved
    protected = set(gen.SUBMODULES.values()) | {KQ_PATH, 'zmk-input-processor-xy-accel',
                                               'zmk-input-processor-aml-threshold', '.git'}
    if relative.parts and relative.parts[0] in protected:
        raise ModelError('出力先にはサブモジュールや Git 管理領域を指定できません')
    if resolved.parent == Path(__file__).resolve().parent and resolved.suffix == '.py':
        raise ModelError('出力先にはシミュレータのソースを指定できません')
    tracked = subprocess.run(['git', '-C', str(root), 'ls-files', '--error-unmatch', '--', str(relative)],
                             text=True, capture_output=True)
    if tracked.returncode == 0:
        raise ModelError('出力先には親リポジトリの追跡ファイルを指定できません')
    if tracked.returncode != 1:
        raise ModelError('出力先が追跡ファイルでないことを確認できません')
    return resolved


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--keyboard', required=True, choices=BOARD_IDS)
    parser.add_argument('--output', type=Path, help='出力先。省略時は標準出力')
    args = parser.parse_args(argv)
    try:
        output = validate_output_path(args.output) if args.output else None
        result = json.dumps(export_keyboard(args.keyboard), ensure_ascii=True, indent=2) + '\n'
        if output:
            output.write_text(result, encoding='utf-8')
        else:
            print(result, end='')
        return 0
    except (ModelError, gen.GenError, OSError, subprocess.CalledProcessError) as exc:
        print(f'失敗: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
