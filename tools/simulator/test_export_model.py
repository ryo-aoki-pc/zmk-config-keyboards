"""期待値ファイルから独立したソース読み取りと、未対応時の扱いを検証する。"""
import copy
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_model as export


class ExportModels(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.models = {name: export.export_keyboard(name) for name in export.BOARD_IDS}
        sources = export.gen.Sources()
        cls.kd, cls.zv, cls.vd = export.gen.import_docgen(sources)

    def test_full_layers_for_every_keyboard(self):
        expected = {'lism': (42, 10), 'kukey42': (43, 10), 'aroundfortyrb': (42, 10),
                    'pyuron': (40, 10), 'roba': (43, 10), 'torabo-tsuki-lp': (66, 10),
                    'keyball39': (42, 4), 'kq-mini': (240, 8)}
        for name, (key_count, layer_count) in expected.items():
            with self.subTest(keyboard=name):
                model = self.models[name]
                self.assertEqual(len(model['keys']), key_count)
                self.assertEqual(len(model['layers']), layer_count)
                for key in model['keys']:
                    self.assertEqual(set(key['on']), set(map(str, range(layer_count))))
                self.assertRegex(model['sources'][0]['commit'], r'^[0-9a-f]{40}$')
        self.assertEqual(sum(k['present'] for k in self.models['keyball39']['keys']), 39)

    def test_export_does_not_read_expected_json_or_write_sources(self):
        original = Path.read_text

        def guard(path, *args, **kwargs):
            if path.parent == export.ROOT / 'tools/expected' and path.suffix == '.json':
                self.fail('期待値 JSON をモデルの入力にしてはいけない')
            return original(path, *args, **kwargs)

        with patch.object(Path, 'read_text', guard), patch.object(Path, 'write_text', side_effect=AssertionError('書き込みは禁止')):
            for name in export.BOARD_IDS:
                export.export_keyboard(name)

    def test_changes_to_keymap_change_model_without_regenerating_expectations(self):
        original = export.gen.read_text

        def changed(path):
            text = original(path)
            if str(path).endswith('/config/lism.keymap'):
                text = text.replace('&kp Q', '&kp F1', 1)
            return text

        with patch.object(export.gen, 'read_text', changed):
            model = export.export_keyboard('lism')
        self.assertEqual(model['keys'][0]['on']['0']['usage'], 58)
        self.assertEqual(self.models['lism']['keys'][0]['on']['0']['usage'], 20)

    def test_pointer_settings_are_read_from_source(self):
        original = export.gen.read_text

        def changed(path):
            text = original(path)
            if str(path).endswith('/boards/shields/lism/lism.dtsi'):
                text = text.replace('threshold = <10>', 'threshold = <17>')
            return text

        with patch.object(export.gen, 'read_text', changed):
            model = export.export_keyboard('lism')
        self.assertEqual(model['pointer']['aml_threshold'], 17)
        self.assertEqual(self.models['lism']['pointer']['aml_threshold'], 10)

    def test_lism_morph_and_macro_retain_timing_controls(self):
        bindings = [b for key in self.models['lism']['keys'] for b in key['on'].values()]
        morph = next(b for b in bindings if b.get('behavior') == 'mm_vim_o')
        self.assertEqual(morph['kind'], 'morph')
        self.assertEqual(morph['mask_mods'], 0x22)
        macro = morph['bindings'][0]
        self.assertEqual(macro['kind'], 'macro')
        self.assertEqual(macro['wait_ms'], 15)
        self.assertEqual(macro['tap_ms'], 30)
        self.assertEqual(macro['steps'][1], {'kind': 'wait_time', 'ms': 100})
        self.assertEqual(macro['steps'][2]['binding']['usage'], 40)

    def test_unknown_behavior_fails_during_export(self):
        original = export.gen.read_text

        def changed(path):
            text = original(path)
            return text.replace('&kp Q', '&unknown_simulator Q', 1) if str(path).endswith('/config/lism.keymap') else text

        with patch.object(export.gen, 'read_text', changed):
            with self.assertRaisesRegex(export.ModelError, '知らないビヘイビア'):
                export.export_keyboard('lism')

    def test_unknown_modifier_expression_is_not_silently_ignored(self):
        with self.assertRaises(export.ModelError):
            export._mod_prop('mods = <(MOD_LSFT | FUTURE_FLAG)>;', 'mods')
        self.assertEqual(export._mod_prop('mods = <(MOD_LSFT | MOD_RSFT)>;', 'mods'), 0x22)

    def test_system_behaviors_are_explicitly_unsupported(self):
        layer = [key['on']['7'] for key in self.models['lism']['keys']]
        bluetooth = next(binding for binding in layer if binding['src'].startswith('&bt'))
        self.assertEqual(bluetooth['kind'], 'other')
        self.assertIn('未対応', bluetooth['reason'])

    def test_kq_reads_actual_vial_not_lism_conversion(self):
        original = export.gen.read_text

        def changed(path):
            self.assertNotIn('zmk-config-LisM', str(path))
            text = original(path)
            if path.name == 'KEYMAP.vil':
                data = json.loads(text)
                # A の入力位置を、実際の .vil だけで B に置き換える。
                data['layout'][0][1][4] = 5
                data['settings']['7'] = 173
                return json.dumps(data)
            return text

        with patch.object(export.gen, 'read_text', changed):
            model = export.export_keyboard('kq-mini')
        self.assertEqual(model['keys'][4]['on']['0']['usage'], 5)
        self.assertEqual(model['settings']['tapping_term'], 173)
        self.assertEqual(model['keys'][224]['matrix'], [0, 0])
        self.assertEqual(self.models['kq-mini']['keys'][4]['on']['0']['kind'], 'ht')

    def test_vial_macros_dances_and_overrides_remain_distinct(self):
        vial = json.loads(export.gen.read_text(export.ROOT / export.KQ_PATH / export.KQ_KEYMAP / 'KEYMAP.vil'))
        parser = export.QmkBindings(self.zv, vial)
        dance = parser.binding(0x5700, 2, overrides=False)
        self.assertEqual(dance['kind'], 'qdance')
        self.assertEqual(len(dance['bindings']), 4)
        self.assertEqual(dance['bindings'][2]['kind'], 'qmacro')
        self.assertEqual(dance['bindings'][2]['steps'][1], {'kind': 'wait', 'ms': 100})
        self.assertEqual(parser.binding(0x5700, 2)['kind'], 'qdance')
        overrides = self.models['kq-mini']['qmk_overrides']
        self.assertEqual(len(overrides), 18)
        self.assertEqual(overrides[0]['trigger'], '0x7E03')
        self.assertEqual(overrides[0]['replacement']['usage'], 79)
        self.assertEqual(overrides[0]['negative_mod_mask'], 0x11)
        carrier = self.models['kq-mini']['keys'][26]['on']['2']
        self.assertTrue(carrier['carrier'])
        self.assertEqual(carrier['kind'], 'none')

    def test_vial_invalid_macro_fails_instead_of_noop(self):
        vial = {'macro': [[['send_text', 'secret']]]}
        with self.assertRaisesRegex(export.ModelError, '命令'):
            export.QmkBindings(self.zv, vial).binding(0x7700)

    def test_kq_mouse_passthrough_requires_all_layer_identity(self):
        self.assertTrue(self.models['kq-mini']['mouse_passthrough_verified'])
        original = export.gen.read_text
        for layer_index, code in ((0, 0xCF), (3, 0xD1), (7, 0xD9)):
            with self.subTest(layer=layer_index, code=code):
                def changed(path):
                    text = original(path)
                    if path.name == 'KEYMAP.vil':
                        data = json.loads(text)
                        data['layout'][layer_index][code // 8 + 1][code & 7] = 4
                        return json.dumps(data)
                    return text

                with patch.object(export.gen, 'read_text', changed):
                    model = export.export_keyboard('kq-mini')
                self.assertFalse(model['mouse_passthrough_verified'])
                self.assertIn('マウスキー', model['mouse_passthrough_reason'])

    def test_kq_gesture_and_mouse_overrides_disable_passthrough(self):
        original = export.gen.read_text
        for change in ('gesture', 'override'):
            with self.subTest(change=change):
                def changed(path):
                    text = original(path)
                    if path.name == 'KEYMAP.vil':
                        data = json.loads(text)
                        if change == 'gesture':
                            data['layout'][6][31][0] = 4
                        else:
                            data['key_override'][0]['trigger'] = 'KC_BTN1'
                        return json.dumps(data)
                    return text

                with patch.object(export.gen, 'read_text', changed):
                    model = export.export_keyboard('kq-mini')
                self.assertFalse(model['mouse_passthrough_verified'])

    def test_kq_invalid_unused_matrix_cell_fails(self):
        original = export.gen.read_text

        def changed(path):
            text = original(path)
            if path.name == 'KEYMAP.vil':
                data = json.loads(text)
                data['layout'][0][31][7] = 'KC_A'
                return json.dumps(data)
            return text

        with patch.object(export.gen, 'read_text', changed), self.assertRaisesRegex(export.ModelError, '整数'):
            export.export_keyboard('kq-mini')

    def test_kq_unreviewed_mouse_code_disables_passthrough(self):
        original = export.gen.read_text

        def changed(path):
            text = original(path)
            return text.replace('return (16);', 'return (32);') if path.name == 'quantizer_mouse.c' else text

        with patch.object(export.gen, 'read_text', changed):
            model = export.export_keyboard('kq-mini')
        self.assertFalse(model['mouse_passthrough_verified'])
        self.assertIn('quantizer_mouse.c', model['mouse_passthrough_reason'])

    def test_pointer_limits_and_sensor_orientation_are_explicit(self):
        self.assertFalse(self.models['kukey42']['pointer']['listeners'][0]['scroll_supported'])
        self.assertIn('PMW3610', self.models['kukey42']['pointer']['listeners'][0]['unsupported_scroll_reason'])
        left, right = self.models['pyuron']['pointer']['listeners']
        self.assertEqual((left['transform'], right['transform']), (5, 6))
        keyball = self.models['keyball39']['pointer']['listeners'][0]
        self.assertEqual((keyball['transform'], keyball['scroll_transform']), (4, 6))

    def test_output_cannot_overwrite_repository_sources(self):
        for relative in ('README.md', 'zmk-config-LisM/config/lism.keymap',
                         'vial-qmk-kq-mini/new.json', 'tools/simulator/export_model.py', '.git/config'):
            with self.subTest(path=relative), self.assertRaises(export.ModelError):
                export.validate_output_path(export.ROOT / relative)
        output = export.ROOT / 'tools/.cache/simulator-source-model.json'
        self.assertEqual(export.validate_output_path(output), output)


if __name__ == '__main__':
    unittest.main()
