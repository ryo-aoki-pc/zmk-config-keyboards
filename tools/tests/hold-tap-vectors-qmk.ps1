# QMK の tap-hold のテスト (vial-qmk の tests/tap_hold_configurations、GPL-2.0-or-later) を写したもの。
# HoldTapSim.cs の QMK のシミュレータが、QMK のテストと同じ HID のレポートの並びを出すかを確かめる。
#   Settings : テストの config.h (TAPPING_TERM 200)。ChordalCompiled / FlowCompiled は CHORDAL_HOLD / FLOW_TAP_TERM が
#              ビルドに入っているか (vial-qmk は両方入っている)
#   Hands    : chordal hold の左右 (テストの chordal_hold_layout)
#   Keys     : Pos = 行 x 16 + 列。Layer = レイヤー
#   Events   : p<位置>@<ms> = 押す、r<位置>@<ms> = 離す (run_one_scan_loop が 1ms)
#   Expect   : 送られる HID のレポート (修飾キーは E0〜E7 の usage。16 進で小さい順)
# 写していないもの (11 件。キーボードの関数を直接呼ぶテスト、コンボ、ワンショットなど):
#   retro_tapping/regular_to_left_gui_mod_over_tap_term (keycode DUMMY_MOD_NEUTRALIZER_KEYCODE)
#   retro_tapping/mod_under_tap_term_to_mod_over_tap_term (keycode DUMMY_MOD_NEUTRALIZER_KEYCODE)
#   retro_tapping/mod_under_tap_term_to_mod_over_tap_term_offset (keycode DUMMY_MOD_NEUTRALIZER_KEYCODE)
#   retro_tapping/mod_over_tap_term_to_mod_over_tap_term (keycode DUMMY_MOD_NEUTRALIZER_KEYCODE)
#   chordal_hold/permissive_hold/chordal_hold_handedness (stmt EXPECT_EQ(chordal_hold_handedness({.col = 0, .row = 0}), 'L')
#   chordal_hold/permissive_hold/get_chordal_hold_default (stmt auto make_record = [](uint8_t row, uint8_t col, keyevent_typ)
#   chordal_hold/permissive_hold_flow_tap/chordal_hold_handedness (stmt EXPECT_EQ(chordal_hold_handedness({.col = 0, .row = 0}), 'L')
#   chordal_hold/permissive_hold_flow_tap/get_chordal_hold_default (stmt auto make_record = [](uint8_t row, uint8_t col, keyevent_typ)
#   flow_tap/hotkey_taps (stmt for (KeymapKey* mod_key : {&ctrl_key, &alt_key, &gui_key}) {)
#   flow_tap/combo_key (stmt tap_combo({mod_tap_key, layer_tap_key}))
#   flow_tap/oneshot_mod_key (stmt EXPECT_CALL(driver, send_keyboard_mock(KeyboardReport(KC_LSF)

$script:KcHtQmkVectors = @(
    @{
        Name = 'default_mod_tap/tap_regular_key_while_mod_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'default_mod_tap/tap_a_mod_tap_key_while_another_mod_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'default_mod_tap/tap_regular_key_while_layer_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 2; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'default_mod_tap/tap_mod_tap_hold_key_two_times'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@1 p1@2 r1@202'
        Expect = @(
            'report: 13',
            'report: (empty)',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'default_mod_tap/tap_mod_tap_hold_key_twice_and_hold_on_second_time'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@1 p1@2 r1@202'
        Expect = @(
            'report: 13',
            'report: (empty)',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'default_mod_tap/tap_and_hold_mod_tap_hold_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@201'
        Expect = @(
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'permissive_hold/tap_regular_key_while_mod_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: E1',
            'report: 04 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'permissive_hold/tap_a_mod_tap_key_while_another_mod_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: E1',
            'report: 04 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'permissive_hold/tap_regular_key_while_layer_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 2; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'hold_on_other_key_press/short_distinct_taps_of_mod_tap_key_and_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; HoldOnOtherKeyPress = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 r1@1 p2@2 r2@3'
        Expect = @(
            'report: 13',
            'report: (empty)',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'hold_on_other_key_press/long_distinct_taps_of_mod_tap_key_and_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; HoldOnOtherKeyPress = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 r1@202 p2@203 r2@204'
        Expect = @(
            'report: E1',
            'report: (empty)',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'hold_on_other_key_press/short_distinct_taps_of_layer_tap_key_and_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; HoldOnOtherKeyPress = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 r1@1 p2@2 r2@3'
        Expect = @(
            'report: 13',
            'report: (empty)',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'hold_on_other_key_press/long_distinct_taps_of_layer_tap_key_and_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; HoldOnOtherKeyPress = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 r1@202 p2@203 r2@204'
        Expect = @(
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'hold_on_other_key_press/tap_regular_key_while_mod_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; HoldOnOtherKeyPress = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: E1',
            'report: 04 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'hold_on_other_key_press/tap_a_mod_tap_key_while_another_mod_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; HoldOnOtherKeyPress = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: E1',
            'report: 04 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'hold_on_other_key_press/tap_regular_key_while_layer_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; HoldOnOtherKeyPress = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 2; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'hold_on_other_key_press/nested_tap_of_layer_0_layer_tap_keys'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; HoldOnOtherKeyPress = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } },
            @{ Pos = 2; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x14; Mods = 0; Label = 'Q' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 14',
            'report: (empty)'
        )
    },
    @{
        Name = 'hold_on_other_key_press/nested_tap_of_layer_tap_keys'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; HoldOnOtherKeyPress = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 2; Label = 'L2' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 2; Layer = 1; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 2; Label = 'L2' }; Tap = @{ Kind = 'kp'; Usage = 0x14; Mods = 0; Label = 'Q' } } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 14',
            'report: (empty)'
        )
    },
    @{
        Name = 'hold_on_other_key_press/roll_mod_tap_key_with_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; HoldOnOtherKeyPress = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p2@1 r1@2 r2@3'
        Expect = @(
            'report: E1',
            'report: 04 E1',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'hold_on_other_key_press/roll_layer_tap_key_with_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; HoldOnOtherKeyPress = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 2; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p2@1 r1@2 r2@3'
        Expect = @(
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'quick_tap/tap_regular_key_while_layer_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 100; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 2; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'quick_tap/tap_key_and_tap_again_before_quick_tap_term'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 100; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@1 p1@92 r1@93'
        Expect = @(
            'report: 13',
            'report: (empty)',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'quick_tap/tap_key_and_hold_again_before_quick_tap_term'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 100; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@1 p1@91 r1@292'
        Expect = @(
            'report: 13',
            'report: (empty)',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'quick_tap/tap_key_and_tap_again_after_quick_tap_term'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 100; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@1 p1@112 r1@113'
        Expect = @(
            'report: 13',
            'report: (empty)',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'quick_tap/tap_key_and_hold_again_after_quick_tap_term'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 100; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@1 p1@111 r1@312'
        Expect = @(
            'report: 13',
            'report: (empty)',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'retro_tapping/tap_and_hold_mod_tap_hold_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; RetroTapping = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@200'
        Expect = @(
            'report: E1',
            'report: (empty)',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'retro_tapping/regular_to_mod_over_tap_term'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; RetroTapping = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p2@0 p1@1 r2@202 r1@203'
        Expect = @(
            'report: 05',
            'report: 05 E1',
            'report: E1',
            'report: (empty)',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'retro_tapping/regular_to_mod_under_tap_term'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; RetroTapping = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p2@0 p1@1 r2@2 r1@3'
        Expect = @(
            'report: 05',
            'report: (empty)',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'retro_tapping/mod_under_tap_term_to_regular'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; RetroTapping = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x08; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p2@1 r1@2 r2@3'
        Expect = @(
            'report: 13',
            'report: 05 13',
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'retro_tapping/mod_over_tap_term_to_regular'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; RetroTapping = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p2@201 r1@202 r2@203'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'retro_tapping/mod_under_tap_term_to_mod_under_tap_term'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; RetroTapping = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x08; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } }
        )
        Events = 'p2@0 p1@1 r2@2 r1@3'
        Expect = @(
            'report: 04',
            'report: (empty)',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'retro_tapping/mod_over_tap_term_to_mod_under_tap_term'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; RetroTapping = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x08; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } }
        )
        Events = 'p2@0 p1@201 r2@202 r1@203'
        Expect = @(
            'report: E1',
            'report: 13 E1',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'retro_tapping/mod_to_mod_to_mod'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; RetroTapping = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x04; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x15; Mods = 0; Label = 'R' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 3; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@201 r1@402 p3@403 r2@604 r3@605'
        Expect = @(
            'report: E2',
            'report: E1 E2',
            'report: E1',
            'report: E0 E1',
            'report: E0',
            'report: (empty)',
            'report: E1',
            'report: 06 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'retro_tapping/HoldA_SHFT_T_KeyReportsShift'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; RetroTapping = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 7; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p7@0 r7@201'
        Expect = @(
            'report: E1',
            'report: (empty)',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'retro_tapping/ANewTapWithinTappingTermIsBuggy'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; RetroTapping = $true; ChordalCompiled = $false; FlowCompiled = $false }
        Hands = @{  }
        Keys = @(
            @{ Pos = 7; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p7@0 r7@1 p7@2 r7@3 p7@204 r7@205 p7@406 r7@606'
        Expect = @(
            'report: 13',
            'report: (empty)',
            'report: 13',
            'report: (empty)',
            'report: 13',
            'report: (empty)',
            'report: E1',
            'report: (empty)',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/default/chord_nested_press_settled_as_tap'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/default/chord_rolled_press_settled_as_tap'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p9@1 r1@2 r9@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/default/non_chord_with_mod_tap_settled_as_tap'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/default/tap_mod_tap_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@199'
        Expect = @(
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/default/hold_mod_tap_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@201'
        Expect = @(
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/default/two_mod_taps_same_hand_hold_til_timeout'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 8 = 'R'; 9 = 'R' }
        Keys = @(
            @{ Pos = 8; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x10; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p8@0 p9@1 r8@202 r9@203'
        Expect = @(
            'report: E4',
            'report: E4 E5',
            'report: E5',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/default/three_mod_taps_same_hand_streak_roll'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L'; 3 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 3; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p3@2 r1@3 r2@4 r3@5'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 05',
            'report: (empty)',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/default/tap_regular_key_while_layer_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/chord_nested_press_settled_as_hold'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: E1',
            'report: 04 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/chord_rolled_press_settled_as_tap'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p9@1 r1@2 r9@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/non_chord_with_mod_tap_settled_as_tap'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/tap_mod_tap_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@199'
        Expect = @(
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/hold_mod_tap_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@201'
        Expect = @(
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/two_mod_taps_same_hand_hold_til_timeout'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 8 = 'R'; 9 = 'R' }
        Keys = @(
            @{ Pos = 8; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x10; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p8@0 p9@1 r8@202 r9@203'
        Expect = @(
            'report: E4',
            'report: E4 E5',
            'report: E5',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/two_mod_taps_nested_press_opposite_hands'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/two_mod_taps_nested_press_same_hand'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/three_mod_taps_same_hand_streak_roll'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L'; 3 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 3; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p3@2 r1@3 r2@4 r3@5'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 05',
            'report: (empty)',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/three_mod_taps_same_hand_streak_orders'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L'; 3 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 3; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p3@2 r3@3 r2@4 r1@5 p1@206 p2@207 p3@208 r3@209 r1@210 r2@211 p1@412 p2@413 p3@414 r2@415 r3@416 r1@417'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 04 05',
            'report: 04',
            'report: (empty)',
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 04 05',
            'report: 05',
            'report: (empty)',
            'report: 04',
            'report: 04 05',
            'report: 04',
            'report: 04 06',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/three_mod_taps_opposite_hands_roll'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p9@2 r1@3 r2@4 r9@5'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 05',
            'report: (empty)',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/three_mod_taps_two_left_one_right'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p9@2 r9@3 r2@4 r1@5 p1@206 p2@207 p9@208 r9@209 r1@210 r2@211'
        Expect = @(
            'report: E1',
            'report: E0 E1',
            'report: 06 E0 E1',
            'report: E0 E1',
            'report: E1',
            'report: (empty)',
            'report: E1',
            'report: E0 E1',
            'report: 06 E0 E1',
            'report: E0 E1',
            'report: E0',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/three_mod_taps_one_held_two_tapped'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 8 = 'R'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 8; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p8@1 p9@2 r9@3 r8@4 r1@5 p1@206 p8@207 p9@208 r9@209 r1@210 r8@211'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: 05 06 E1',
            'report: 05 E1',
            'report: E1',
            'report: (empty)',
            'report: E1',
            'report: 05 E1',
            'report: 05 06 E1',
            'report: 05 E1',
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/two_mod_taps_one_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 8 = 'R'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 8; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } }
        )
        Events = 'p1@0 p8@1 p9@2 r8@3 r9@4 r1@5 p1@206 p8@207 p9@208 r9@209 r1@210 r8@211'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: 05 06 E1',
            'report: 06 E1',
            'report: E1',
            'report: (empty)',
            'report: E1',
            'report: 05 E1',
            'report: 05 06 E1',
            'report: 05 E1',
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/tap_regular_key_while_layer_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'none' } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/nested_tap_of_layer_0_layer_tap_keys'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x14; Mods = 0; Label = 'Q' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: 14',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/lt_mt_one_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 2; Layer = 1; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x1B; Mods = 0; Label = 'X' } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'none' } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'none' } }
        )
        Events = 'p1@0 p2@1 p9@2 r9@3 r2@4 r1@5'
        Expect = @(
            'report: E0',
            'report: 1B E0',
            'report: E0',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/nested_tap_of_layer_tap_keys'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 2; Label = 'L2' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 2; Label = 'L2' }; Tap = @{ Kind = 'kp'; Usage = 0x14; Mods = 0; Label = 'Q' } } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: 14',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/roll_layer_tap_key_with_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p9@1 r1@2 r9@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold/two_mod_tap_keys_stuttered_press'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@0 p2@201 r1@202 p1@203 r2@204 r1@205'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: 05',
            'report: 04 05',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/chord_with_mod_tap_settled_as_hold'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: E1',
            'report: 04 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/chord_nested_press_settled_as_hold'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: E1',
            'report: 04 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/chord_rolled_press_settled_as_hold'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p9@1 r1@2 r9@3'
        Expect = @(
            'report: E1',
            'report: 04 E1',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/non_chord_with_mod_tap_settled_as_tap'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/tap_mod_tap_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@199'
        Expect = @(
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/hold_mod_tap_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@201'
        Expect = @(
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/two_mod_taps_same_hand_hold_til_timeout'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 8 = 'R'; 9 = 'R' }
        Keys = @(
            @{ Pos = 8; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x10; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p8@0 p9@1 r8@202 r9@203'
        Expect = @(
            'report: E4',
            'report: E4 E5',
            'report: E5',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/two_mod_taps_nested_press_opposite_hands'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/two_mod_taps_nested_press_same_hand'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/three_mod_taps_same_hand_streak_roll'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L'; 3 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 3; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p3@2 r1@3 r2@4 r3@5'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 05',
            'report: (empty)',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/three_mod_taps_same_hand_streak_orders'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L'; 3 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 3; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p3@2 r3@3 r2@4 r1@5 p1@206 p2@207 p3@208 r3@209 r1@210 r2@211 p1@412 p2@413 p3@414 r2@415 r3@416 r1@417'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 04 05',
            'report: 04',
            'report: (empty)',
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 04 05',
            'report: 05',
            'report: (empty)',
            'report: 04',
            'report: 04 05',
            'report: 04',
            'report: 04 06',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/three_mod_taps_two_left_one_right'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p9@2 r9@3 r2@4 r1@5 p1@6 p2@7 p9@8 r9@9 r1@10 r2@11'
        Expect = @(
            'report: E1',
            'report: E0 E1',
            'report: 06 E0 E1',
            'report: E0 E1',
            'report: E1',
            'report: (empty)',
            'report: E1',
            'report: E0 E1',
            'report: 06 E0 E1',
            'report: E0 E1',
            'report: E0',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/three_mod_taps_one_held_two_tapped'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 8 = 'R'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 8; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p8@1 p9@2 r9@3 r8@4 r1@5 p1@206 p8@207 p9@208 r9@209 r1@210 r8@211'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: 05 06 E1',
            'report: 05 E1',
            'report: E1',
            'report: (empty)',
            'report: E1',
            'report: 05 E1',
            'report: 05 06 E1',
            'report: 05 E1',
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/tap_regular_key_while_layer_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'none' } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/long_distinct_taps_of_layer_tap_key_and_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 r1@202 p9@203 r9@204'
        Expect = @(
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/nested_tap_of_layer_0_layer_tap_keys'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x14; Mods = 0; Label = 'Q' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: 14',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/lt_mt_one_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 2; Layer = 1; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x1B; Mods = 0; Label = 'X' } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'none' } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'none' } }
        )
        Events = 'p1@0 p2@1 p9@2 r9@3 r2@4 r1@5'
        Expect = @(
            'report: E0',
            'report: 1B E0',
            'report: E0',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/nested_tap_of_layer_tap_keys'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 2; Label = 'L2' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 2; Label = 'L2' }; Tap = @{ Kind = 'kp'; Usage = 0x14; Mods = 0; Label = 'Q' } } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: 14',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/roll_layer_tap_key_with_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p9@1 r1@2 r9@3'
        Expect = @(
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/hold_on_other_key_press/two_mod_tap_keys_stuttered_press'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; HoldOnOtherKeyPress = $true; ChordalCompiled = $true; FlowCompiled = $false }
        Hands = @{ 1 = 'L'; 2 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@0 p2@201 r1@202 p1@203 r2@204 r1@205'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: 05',
            'report: 04 05',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/chord_nested_press_settled_as_hold'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: E1',
            'report: 04 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/chord_rolled_press_settled_as_tap'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p9@1 r1@2 r9@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/non_chord_with_mod_tap_settled_as_tap'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 2 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/tap_mod_tap_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@199'
        Expect = @(
            'report: 13',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/hold_mod_tap_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } }
        )
        Events = 'p1@0 r1@201'
        Expect = @(
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/two_mod_taps_same_hand_hold_til_timeout'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 8 = 'R'; 9 = 'R' }
        Keys = @(
            @{ Pos = 8; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x10; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p8@0 p9@1 r8@202 r9@203'
        Expect = @(
            'report: E4',
            'report: E4 E5',
            'report: E5',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/two_mod_taps_nested_press_opposite_hands'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/two_mod_taps_nested_press_same_hand'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 2 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@0 p2@1 r2@2 r1@3'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/three_mod_taps_same_hand_streak_roll'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 2 = 'L'; 3 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 3; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p3@2 r1@3 r2@4 r3@5'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 05 06',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/three_mod_taps_same_hand_streak_orders'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 2 = 'L'; 3 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 3; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p3@2 r3@3 r2@4 r1@5 p1@206 p2@207 p3@208 r3@209 r1@210 r2@211 p1@412 p2@413 p3@414 r2@415 r3@416 r1@417'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 04 05',
            'report: 04',
            'report: (empty)',
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 04 05',
            'report: 05',
            'report: (empty)',
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 04 06',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/three_mod_taps_opposite_hands_roll'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 2 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p9@2 r1@3 r2@4 r9@5'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 05 06',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/three_mod_taps_two_left_one_right'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 2 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p2@1 p9@2 r9@3 r2@4 r1@5 p1@206 p2@207 p9@208 r9@209 r1@210 r2@211'
        Expect = @(
            'report: E1',
            'report: E0 E1',
            'report: 06 E0 E1',
            'report: E0 E1',
            'report: E1',
            'report: (empty)',
            'report: E1',
            'report: E0 E1',
            'report: 06 E0 E1',
            'report: E0 E1',
            'report: E0',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/three_mod_taps_one_held_two_tapped'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 8 = 'R'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 8; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x20; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p1@0 p8@1 p9@2 r9@3 r8@4 r1@5 p1@206 p8@207 p9@208 r9@209 r1@210 r8@211'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: 05 06 E1',
            'report: 05 E1',
            'report: E1',
            'report: (empty)',
            'report: E1',
            'report: 05 E1',
            'report: 05 06 E1',
            'report: 05 E1',
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/two_mod_taps_one_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 8 = 'R'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 8; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } }
        )
        Events = 'p1@0 p8@1 p9@2 r8@3 r9@4 r1@5 p1@206 p8@207 p9@208 r9@209 r1@210 r8@211'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: 05 06 E1',
            'report: 06 E1',
            'report: E1',
            'report: (empty)',
            'report: E1',
            'report: 05 E1',
            'report: 05 06 E1',
            'report: 05 E1',
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/tap_regular_key_while_layer_tap_key_is_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'none' } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/nested_tap_of_layer_0_layer_tap_keys'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x14; Mods = 0; Label = 'Q' } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: 14',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/lt_mt_one_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 2 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 2; Layer = 1; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x1B; Mods = 0; Label = 'X' } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'none' } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'none' } }
        )
        Events = 'p1@0 p2@1 p9@2 r9@3 r2@4 r1@5'
        Expect = @(
            'report: E0',
            'report: 1B E0',
            'report: E0',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/nested_tap_of_layer_tap_keys'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 1; Layer = 1; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 2; Label = 'L2' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 2; Label = 'L2' }; Tap = @{ Kind = 'kp'; Usage = 0x14; Mods = 0; Label = 'Q' } } }
        )
        Events = 'p1@0 p9@1 r9@2 r1@3'
        Expect = @(
            'report: 14',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/roll_layer_tap_key_with_regular_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 9 = 'R' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x13; Mods = 0; Label = 'P' } } },
            @{ Pos = 9; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 9; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } }
        )
        Events = 'p1@0 p9@1 r1@2 r9@3'
        Expect = @(
            'report: 13',
            'report: 04 13',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'chordal_hold/permissive_hold_flow_tap/two_mod_tap_keys_stuttered_press'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; ChordalHold = $true; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $true; FlowCompiled = $true }
        Hands = @{ 1 = 'L'; 2 = 'L' }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@0 p2@201 r1@202 p1@203 r2@204 r1@205'
        Expect = @(
            'report: E1',
            'report: 05 E1',
            'report: 05',
            'report: 04 05',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/distinct_taps'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } },
            @{ Pos = 3; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x04; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x07; Mods = 0; Label = 'D' } } }
        )
        Events = 'p0@0 r0@151 p1@152 r1@304 p2@305 r2@457 p3@458 r3@610 p1@761 r1@913 p2@914 r2@1116'
        Expect = @(
            'report: 04',
            'report: (empty)',
            'report: 05',
            'report: (empty)',
            'report: 06',
            'report: (empty)',
            'report: 07',
            'report: (empty)',
            'report: 05',
            'report: (empty)',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/rolled_press'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p0@0 r0@1 p1@2 p2@3 r1@205 r2@206'
        Expect = @(
            'report: 04',
            'report: (empty)',
            'report: 05',
            'report: 05 06',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/long_flow_tap_settled_as_held'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p0@0 r0@1 p1@153 r1@354'
        Expect = @(
            'report: 04',
            'report: (empty)',
            'report: E1',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/holding_multiple_mod_taps'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p0@0 r0@1 p1@153 p2@154 p0@349 r0@359 r1@360 r2@361'
        Expect = @(
            'report: 04',
            'report: (empty)',
            'report: E1',
            'report: E0 E1',
            'report: 04 E0 E1',
            'report: E0 E1',
            'report: E0',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/holding_mod_tap_with_regular_mod'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0; Label = 'Shift' } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p0@0 r0@1 p1@153 p2@154 p0@349 r0@359 r1@360 r2@361'
        Expect = @(
            'report: 04',
            'report: (empty)',
            'report: E1',
            'report: E0 E1',
            'report: 04 E0 E1',
            'report: E0 E1',
            'report: E0',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/layer_tap_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 0; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } }
        )
        Events = 'p0@0 r0@1 p1@2 r1@204 p0@205 r0@206 p1@358 p0@560 r0@561 r1@562'
        Expect = @(
            'report: 04',
            'report: (empty)',
            'report: 05',
            'report: (empty)',
            'report: 04',
            'report: (empty)',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/layer_tap_ignored_with_disabled_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'none' } },
            @{ Pos = 0; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x29; Mods = 0; Label = 'Esc' } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@0 p0@201 r0@202 r1@203 p2@204 r2@405'
        Expect = @(
            'report: 29',
            'report: (empty)',
            'report: E0',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/layer_tap_ignored_with_disabled_key_complex'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x14; Mods = 0; Label = 'Q' } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x2C; Mods = 0; Label = 'Space' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x17; Mods = 0; Label = 'T' } } },
            @{ Pos = 3; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x40; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x0C; Mods = 0; Label = 'I' } } },
            @{ Pos = 3; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x4F; Mods = 0; Label = '→' } }
        )
        Events = 'p0@0 r0@1 p1@153 p3@154 r3@155 r1@156 p2@157 p0@158 r0@159 r2@160'
        Expect = @(
            'report: 14',
            'report: (empty)',
            'report: 4F',
            'report: (empty)',
            'report: E0',
            'report: 14 E0',
            'report: E0',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/layer_tap_ignored_with_enabled_key'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'none' } },
            @{ Pos = 0; Layer = 1; Binding = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@0 p0@201 r0@202 r1@203 p2@204 r2@406'
        Expect = @(
            'report: 06',
            'report: (empty)',
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/quick_tap'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } }
        )
        Events = 'p1@0 r1@1 p1@2 r1@204'
        Expect = @(
            'report: 04',
            'report: (empty)',
            'report: 04',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/rolling_mt_mt'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x02; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } }
        )
        Events = 'p1@151 p2@152 r1@153 r2@355'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 05',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/rolling_lt_mt_regular'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } }
        )
        Events = 'p0@151 p1@152 p2@153 r0@154 r1@356 r2@357'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 05 06',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/rolling_lt_regular_mt'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'LT'; Hold = @{ Kind = 'mo'; Layer = 1; Label = 'L1' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p0@151 p1@152 p2@153 r0@154 r1@356 r2@357'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 05 06',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/rolling_mt_mt_mt'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x08; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x04; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p0@151 p1@152 p2@153 r0@154 r1@356 r2@357'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 04 05 06',
            'report: 05 06',
            'report: 06',
            'report: (empty)'
        )
    },
    @{
        Name = 'flow_tap/roll_release_132'
        Settings = @{ TappingTerm = 200; QuickTapTerm = 200; PermissiveHold = $true; FlowTapTerm = 150; ChordalCompiled = $false; FlowCompiled = $true }
        Hands = @{  }
        Keys = @(
            @{ Pos = 0; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x01; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0; Label = 'A' } } },
            @{ Pos = 1; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x08; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0; Label = 'B' } } },
            @{ Pos = 2; Layer = 0; Binding = @{ Kind = 'ht'; Behavior = 'MT'; Hold = @{ Kind = 'mods'; Mods = 0x04; Label = 'mods' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0; Label = 'C' } } }
        )
        Events = 'p0@151 p1@152 p2@303 r0@304 r2@305 r1@306'
        Expect = @(
            'report: 04',
            'report: 04 05',
            'report: 05',
            'report: 05 06',
            'report: 05',
            'report: (empty)'
        )
    }
)
