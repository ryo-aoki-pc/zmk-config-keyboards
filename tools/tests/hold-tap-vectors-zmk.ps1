# ZMK v0.3.0 の hold-tap のテスト (zmkfirmware/zmk の app/tests/hold-tap、MIT ライセンス) を写したもの。
# hold-tap-zmk.ps1 のシミュレータが、ZMK のテストと同じログの行 (keycode_events.snapshot) を出すかを確かめる。
#   Keys     : 位置 0〜3 のバインディング (テストのキーマップ。行 x 2 + 列)
#   Events   : p<位置>@<ms> = 押す、r<位置>@<ms> = 離す (ZMK_MOCK_PRESS / RELEASE の待ちを足した時刻)
#   Retro    : events.patterns に retro tap の行 (decide_retro_tap / update_hold_status_for_retro_tap) も入る
# 写していないもの: hold-while-undecided/4-linger-sk (&sk を使う)

$script:KcHtZmkVectors = @(
    @{
        Name = 'balanced/1-dn-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@10'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (balanced decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/2-dn-timer-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@500'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/3a-moddn-dn-modup-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p3@0 p0@10 r3@110 r0@120'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (balanced decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/3b-moddn-dn-modup-timer-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p3@0 p0@10 r3@60 r0@360'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/3c-kcdn-dn-kcup-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p2@0 p0@10 r2@110 r0@120'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided tap (balanced decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/3d-kcdn-dn-kcup-timer-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p2@0 p0@10 r2@110 r0@510'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/4a-dn-htdn-timer-htup-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p1@200 r1@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided tap (balanced decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/4a-dn-kcdn-timer-kcup-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@200 r2@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/4b-dn-kcdn-kcup-timer-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@100 r2@200 r0@400'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (balanced decision moment other-key-up)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/4c-dn-kcdn-kcup-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@10 r2@20 r0@30'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (balanced decision moment other-key-up)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/4d-dn-kcdn-timer-up-kcup'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@100 r0@200 r2@400'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (balanced decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00'
        )
    },
    @{
        Name = 'balanced/5-quick-tap'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@10 p0@20 r0@420'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (balanced decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (balanced decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/6-retro-tap'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = -1; PriorIdle = -1; RetroTap = $true; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'none' },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'none' }
        )
        Events = 'p0@0 r0@10 p0@20 r0@420 p0@430 p2@830 r2@840 r0@850'
        Retro = $true
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (balanced decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'decide_retro_tap: 0 retro tap',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'update_hold_status_for_retro_tap: Update hold tap 0 status to hold-interrupt',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/7-positional/2-dn-timer-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 r0@500'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/7-positional/4a-dn-ntgdn-timer-ntgup-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p3@200 r3@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/7-positional/4a-dn-tgdn-timer-tgup-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p2@200 r2@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/7-positional/on-release-no-trigger'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $true; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p1@10 p3@20 r2@30 r1@40 r0@50'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided hold-interrupt (balanced decision moment other-key-up)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided tap (balanced decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/7-positional/on-release-trigger'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $true; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p1@10 p2@20 r2@30 r1@40 r0@50'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (balanced decision moment other-key-up)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided hold-interrupt (balanced decision moment other-key-up)',
            'kp_pressed: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/7-positional/tgdn-dn-ntgdn-timer-ntgup-tgup-up'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p2@0 p0@10 p3@20 r3@420 r2@430 r0@440'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/8-require-prior-idle/1-basic'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 300; PriorIdle = 100; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL C'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0x00; Label = 'C' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'none' }
        )
        Events = 'p0@0 r0@10 p0@260 r0@660 p0@1060 p2@1460 r2@1470 r0@1480 p2@1880 p0@1890 r2@2290 r0@2300'
        Retro = $true
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (balanced decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (balanced decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (balanced decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/8-require-prior-idle/2-double-hold'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 300; PriorIdle = 100; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL C'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0x00; Label = 'C' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'none' }
        )
        Events = 'p0@0 p1@400 p2@800 r2@810 r0@820 r1@830'
        Retro = $true
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap'
        )
    },
    @{
        Name = 'balanced/many-nested'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = -1; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_GUI H'; Hold = @{ Kind = 'kp'; Usage = 0xE3; Mods = 0x00; Label = 'Win' }; Tap = @{ Kind = 'kp'; Usage = 0x0B; Mods = 0x00; Label = 'H' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_ALT L'; Hold = @{ Kind = 'kp'; Usage = 0xE2; Mods = 0x00; Label = 'Alt' }; Tap = @{ Kind = 'kp'; Usage = 0x0F; Mods = 0x00; Label = 'L' } }
        )
        Events = 'p0@0 p1@100 p2@200 p3@300 r0@400 r1@500 r2@600 r3@700'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 2 new undecided hold_tap',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_decide: 2 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE3 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 3 new undecided hold_tap',
            'ht_binding_released: 1 cleaning up hold-tap',
            'ht_decide: 3 decided hold-timer (balanced decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE2 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE3 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 2 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE2 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 3 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/1-dn-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@10'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (hold-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/2-dn-timer-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@500'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (hold-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/3a-moddn-dn-modup-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p3@0 p0@10 r3@110 r0@120'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (hold-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/3b-moddn-dn-modup-timer-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p3@0 p0@10 r3@60 r0@360'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (hold-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/3c-kcdn-dn-kcup-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p2@0 p0@10 r2@110 r0@120'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided tap (hold-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/3d-kcdn-dn-kcup-timer-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p2@0 p0@10 r2@110 r0@510'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided hold-timer (hold-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/4a-dn-htdn-timer-htup-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p1@200 r1@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided tap (hold-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/4a-dn-kcdn-timer-kcup-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@200 r2@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/4b-dn-kcdn-kcup-timer-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@100 r2@200 r0@400'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/4c-dn-kcdn-kcup-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@10 r2@20 r0@30'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/4d-dn-kcdn-timer-up-kcup'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@100 r0@200 r2@400'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00'
        )
    },
    @{
        Name = 'hold-preferred/5-quick-tap'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@10 p0@20 r0@420'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (hold-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (hold-preferred decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/6-retro-tap'
        Behaviors = @{ hp = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = -1; PriorIdle = -1; RetroTap = $true; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'hp'; Src = '&hp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'none' },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'none' }
        )
        Events = 'p0@0 r0@10 p0@20 r0@420 p0@430 p2@830 r2@840 r0@850'
        Retro = $true
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (hold-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (hold-preferred decision moment timer)',
            'decide_retro_tap: 0 retro tap',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (hold-preferred decision moment timer)',
            'update_hold_status_for_retro_tap: Update hold tap 0 status to hold-interrupt',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/7-positional/2-dn-timer-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 r0@500'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (hold-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/7-positional/4a-dn-ntgdn-timer-ntgup-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p3@200 r3@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/7-positional/4a-dn-tgdn-timer-tgup-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p2@200 r2@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/7-positional/on-release-no-trigger'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $true; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p1@10 p3@20 r2@30 r1@40 r0@50'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided hold-interrupt (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/7-positional/on-release-trigger'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $true; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p1@10 p2@20 r2@30 r1@40 r0@50'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided hold-interrupt (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/7-positional/tgdn-dn-ntgdn-timer-ntgup-tgup-up'
        Behaviors = @{ ht_hold = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_hold'; Src = '&ht_hold LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p2@0 p0@10 p3@20 r3@420 r2@430 r0@440'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/8-require-prior-idle/1-basic'
        Behaviors = @{ hp = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 300; PriorIdle = 100; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'hp'; Src = '&hp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'hp'; Src = '&hp LEFT_CONTROL G'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0A; Mods = 0x00; Label = 'G' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'none' }
        )
        Events = 'p0@0 r0@10 p0@260 r0@660 p0@1060 p2@1070 r2@1080 r0@1090 p2@1490 p0@1500 r2@1900 r0@1910'
        Retro = $true
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (hold-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (hold-preferred decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (hold-preferred decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (hold-preferred decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-preferred/8-require-prior-idle/2-double-hold'
        Behaviors = @{ hp = @{ Flavor = 'hold-preferred'; Term = 300; QuickTap = 300; PriorIdle = 100; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'hp'; Src = '&hp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'hp'; Src = '&hp LEFT_CONTROL G'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0A; Mods = 0x00; Label = 'G' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'none' }
        )
        Events = 'p0@0 p1@400 p2@800 r2@810 r0@820 r1@830'
        Retro = $true
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (hold-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided hold-timer (hold-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-while-undecided/1-tap'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $true; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT A'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0x00; Label = 'A' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL B'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0x00; Label = 'B' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@10'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 hold behavior pressed while undecided',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided tap (balanced decision moment key-up)',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x04 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x04 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-while-undecided/2-hold'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 100; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $true; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT A'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0x00; Label = 'A' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL B'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0x00; Label = 'B' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@150'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 hold behavior pressed while undecided',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided hold-timer (balanced decision moment timer)',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'hold-while-undecided/3-linger'
        Behaviors = @{ ht_bal = @{ Flavor = 'balanced'; Term = 100; QuickTap = 300; PriorIdle = -1; RetroTap = $false; Hwu = $true; HwuLinger = $true; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_SHIFT A'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x04; Mods = 0x00; Label = 'A' } },
            @{ Kind = 'ht'; Behavior = 'ht_bal'; Src = '&ht_bal LEFT_CONTROL B'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x05; Mods = 0x00; Label = 'B' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@10'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 hold behavior pressed while undecided',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided tap (balanced decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x04 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x04 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/1-dn-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@10'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/2-dn-timer-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@500'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/3a-moddn-dn-modup-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p3@0 p0@10 r3@110 r0@120'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/3b-moddn-dn-modup-timer-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p3@0 p0@10 r3@60 r0@360'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/3c-kcdn-dn-kcup-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p2@0 p0@10 r2@110 r0@120'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/3d-kcdn-dn-kcup-timer-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p2@0 p0@10 r2@110 r0@510'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/4a-dn-htdn-timer-htup-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p1@200 r1@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/4a-dn-kcdn-timer-kcup-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@200 r2@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/4b-dn-kcdn-kcup-timer-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@100 r2@200 r0@400'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/4c-dn-kcdn-kcup-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@10 r2@20 r0@30'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/4d-dn-kcdn-timer-up-kcup'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@100 r0@200 r2@400'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00'
        )
    },
    @{
        Name = 'tap-preferred/5-quick-tap'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@10 p0@20 r0@420'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/6-nested-timeouts'
        Behaviors = @{ tp_short = @{ Flavor = 'tap-preferred'; Term = 100; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() }; tp_long = @{ Flavor = 'tap-preferred'; Term = 200; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp_long'; Src = '&tp_long LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp_short'; Src = '&tp_short LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p1@20 r1@40 r0@240'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/7-positional/2-dn-timer-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 r0@500'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/7-positional/4a-dn-ntgdn-timer-ntgup-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p3@200 r3@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/7-positional/4a-dn-tgdn-timer-tgup-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p2@200 r2@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/7-positional/on-release-no-trigger'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $true; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p1@10 p3@20 r2@30 r1@40 r0@50'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/7-positional/on-release-trigger'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $true; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p0@0 p1@10 p2@20 r2@30 r1@40 r0@50'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/7-positional/tgdn-dn-ntgdn-timer-ntgup-tgup-up'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @(2) } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0x08; Mods = 0x00; Label = 'E' }
        )
        Events = 'p2@0 p0@10 p3@20 r3@420 r2@430 r0@440'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x08 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/8-require-prior-idle/1-basic'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 300; PriorIdle = 100; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL C'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0x00; Label = 'C' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'none' }
        )
        Events = 'p0@0 r0@10 p0@260 r0@660 p0@1060 p2@1460 r2@1470 r0@1480 p2@1880 p0@1890 r2@2290 r0@2300'
        Retro = $true
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-preferred decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-preferred/8-require-prior-idle/2-double-hold'
        Behaviors = @{ tp = @{ Flavor = 'tap-preferred'; Term = 300; QuickTap = 300; PriorIdle = 100; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'tp'; Src = '&tp LEFT_CONTROL C'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x06; Mods = 0x00; Label = 'C' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'none' }
        )
        Events = 'p0@0 p1@10 p2@410 r2@420 r0@430 r1@440'
        Retro = $true
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided hold-timer (tap-preferred decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/1-dn-up'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@10'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/2-dn-timer-up'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@500'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/3a-moddn-dn-modup-up'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p3@0 p0@10 r3@110 r0@120'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/3b-moddn-dn-modup-timer-up'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p3@0 p0@10 r3@60 r0@360'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE4 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/3c-kcdn-dn-kcup-up'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p2@0 p0@10 r2@110 r0@120'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/3d-kcdn-dn-kcup-timer-up'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p2@0 p0@10 r2@110 r0@510'
        Retro = $false
        Expect = @(
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/4a-dn-htdn-timer-htup-up'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p1@200 r1@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (tap-unless-interrupted decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided tap (tap-unless-interrupted decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/4a-dn-kcdn-timer-kcup-up'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@200 r2@400 r0@410'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (tap-unless-interrupted decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/4b-dn-kcdn-kcup-timer-up'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@100 r2@200 r0@400'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (tap-unless-interrupted decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/4c-dn-kcdn-kcup-up'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@10 r2@20 r0@30'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (tap-unless-interrupted decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/4d-dn-kcdn-timer-up-kcup'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p2@100 r0@200 r2@400'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided hold-interrupt (tap-unless-interrupted decision moment other-key-down)',
            'kp_pressed: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0xE1 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00'
        )
    },
    @{
        Name = 'tap-unless-interrupted/5-quick-tap'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 200; PriorIdle = -1; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@10 p0@20 r0@420'
        Retro = $false
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/6-require-prior-idle/1-basic'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 300; PriorIdle = 100; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 r0@10 p0@260 r0@660 p0@1060 p2@1460 r2@1470 r0@1480 p2@1880 p0@1890 r2@2290 r0@2300'
        Retro = $true
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment key-up)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment quick-tap)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap'
        )
    },
    @{
        Name = 'tap-unless-interrupted/6-require-prior-idle/2-double-hold'
        Behaviors = @{ ht_tui = @{ Flavor = 'tap-unless-interrupted'; Term = 300; QuickTap = 300; PriorIdle = 100; RetroTap = $false; Hwu = $false; HwuLinger = $false; TriggerOnRelease = $false; TriggerPositions = @() } }
        Keys = @(
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_SHIFT F'; Hold = @{ Kind = 'kp'; Usage = 0xE1; Mods = 0x00; Label = 'Shift' }; Tap = @{ Kind = 'kp'; Usage = 0x09; Mods = 0x00; Label = 'F' } },
            @{ Kind = 'ht'; Behavior = 'ht_tui'; Src = '&ht_tui LEFT_CONTROL J'; Hold = @{ Kind = 'kp'; Usage = 0xE0; Mods = 0x00; Label = 'Ctrl' }; Tap = @{ Kind = 'kp'; Usage = 0x0D; Mods = 0x00; Label = 'J' } },
            @{ Kind = 'kp'; Usage = 0x07; Mods = 0x00; Label = 'D' },
            @{ Kind = 'kp'; Usage = 0xE4; Mods = 0x00; Label = 'RCtrl' }
        )
        Events = 'p0@0 p1@400 p2@800 r2@810 r0@820 r1@830'
        Retro = $true
        Expect = @(
            'ht_binding_pressed: 0 new undecided hold_tap',
            'ht_decide: 0 decided tap (tap-unless-interrupted decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_pressed: 1 new undecided hold_tap',
            'ht_decide: 1 decided tap (tap-unless-interrupted decision moment timer)',
            'kp_pressed: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'kp_pressed: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x07 implicit_mods 0x00 explicit_mods 0x00',
            'kp_released: usage_page 0x07 keycode 0x09 implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 0 cleaning up hold-tap',
            'kp_released: usage_page 0x07 keycode 0x0D implicit_mods 0x00 explicit_mods 0x00',
            'ht_binding_released: 1 cleaning up hold-tap'
        )
    }
)
