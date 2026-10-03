# ZMK のログ版ファームのログの解析 (zmk-log.ps1) のテスト。ZMK v0.3.0 の LOG_DBG の書式で作ったログを使う

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'input-eval.ps1')
. (Join-Path $script:KcLib 'behavior-eval.ps1')
. (Join-Path $script:KcLib 'zmk-log.ps1')

$common = Get-KcExpected 'common' $script:ExpectedDir
$scan = New-KcScanTable $common
$lism = Get-KcExpected 'lism' $script:ExpectedDir

# ログの行を作る (時刻はミリ秒)
function New-ZlLine([double]$Ms, [string]$Func, [string]$Msg, [string]$Level = 'dbg') {
    $ts = [TimeSpan]::FromMilliseconds([math]::Floor($Ms))
    $us = [int](($Ms - [math]::Floor($Ms)) * 1000)
    return ('[{0:00}:{1:00}:{2:00}.{3:000},{4:000}] <{5}> zmk: {6}: {7}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds, $us, $Level, $Func, $Msg)
}

# セントラル (右手側) / ペリフェラル (左手側) のキー
function New-ZlPos([double]$Ms, [int]$Pos, [bool]$Pressed, [bool]$Central) {
    if ($Central) {
        $p = 'false'
        if ($Pressed) { $p = 'true' }
        return (New-ZlLine $Ms 'zmk_physical_layouts_kscan_process_msgq' ('Row: 0, col: 0, position: {0}, pressed: {1}' -f $Pos, $p))
    }
    return (New-ZlLine $Ms 'peripheral_event_work_callback' ('Trigger key position state change for {0}' -f $Pos))
}

function New-ZlApply([double]$Ms, [int]$Layer, [int]$Pos, [string]$Device) {
    return (New-ZlLine $Ms 'zmk_keymap_apply_position_state' ('layer_id: {0} position: {1}, binding name: {2}' -f $Layer, $Pos, $Device))
}

function New-ZlKey([double]$Ms, [int]$Pos, [long]$Keycode, [int]$Usage, [int]$Implicit, [int]$Explicit, [bool]$Pressed) {
    $s = 'released'
    if ($Pressed) { $s = 'pressed' }
    return @(
        (New-ZlLine $Ms ('on_keymap_binding_' + $s) ('position {0} keycode 0x{1:X2}' -f $Pos, $Keycode)),
        (New-ZlLine ($Ms + 0.1) ('hid_listener_keycode_' + $s) ('usage_page 0x07 keycode 0x{0:X2} implicit_mods 0x{1:X2} explicit_mods 0x{2:X2}' -f $Usage, $Implicit, $Explicit))
    )
}

function New-ZlLayer([double]$Ms, [int]$Layer, [bool]$On) {
    $s = 0
    if ($On) { $s = 1 }
    return (New-ZlLine $Ms 'set_layer_state' ('layer_changed: layer {0} state {1}' -f $Layer, $s))
}

function New-ZlMo([double]$Ms, [int]$Pos, [int]$Layer, [bool]$Pressed) {
    $s = 'released'
    if ($Pressed) { $s = 'pressed' }
    return @((New-ZlLine $Ms ('mo_keymap_binding_' + $s) ('position {0} layer {1}' -f $Pos, $Layer)), (New-ZlLayer ($Ms + 0.1) $Layer $Pressed))
}

function Invoke-ZlTrace([string[]]$Lines) {
    $st = New-KcLayerTrace $lism
    foreach ($l in $Lines) {
        Update-KcLayerTrace $st (ConvertFrom-KcZmkLogLine $l)
    }
    return $st
}

function Get-ZlPress($State, [int]$Pos, [int]$Nth = 1) {
    $n = 0
    foreach ($e in $State.Events) {
        if ($e.Pos -eq $Pos -and $e.Pressed) {
            $n++
            if ($n -eq $Nth) { return $e }
        }
    }
    throw ('位置 {0} の {1} 回目の押下がありません' -f $Pos, $Nth)
}

Test-Case '行の解析: 色・時刻・関数名、知らない行、欠落' {
    # ESC は [char]27 で書く (`e は PowerShell 6 から。5.1 では ESC にならない)
    $esc = [string][char]27
    $r = ConvertFrom-KcZmkLogLine ($esc + '[1;34m' + (New-ZlApply 12345.678 2 12 'MM_VIM_D') + $esc + "[0m`r")
    Assert-Equal 'apply' $r.Type
    Assert-Equal 2 $r.Layer
    Assert-Equal 12 $r.Pos
    Assert-Equal 'MM_VIM_D' $r.Device
    Assert-Near 12345.678 $r.Time 0.0001
    Assert-Equal 'zmk_keymap_apply_position_state' $r.Func
    $p = ConvertFrom-KcZmkLogLine (New-ZlPos 1 15 $false $true)
    Assert-Equal 'position' $p.Type
    Assert-Equal $false $p.Pressed
    Assert-Equal 'central' $p.Source
    $q = ConvertFrom-KcZmkLogLine (New-ZlPos 1 15 $true $false)
    Assert-Equal $null $q.Pressed 'ペリフェラルは押す / 離すが分からない'
    Assert-Equal 'other' (ConvertFrom-KcZmkLogLine (New-ZlLine 1 'bt_connected' 'Connected 11:22')).Type
    Assert-Equal 'dropped' (ConvertFrom-KcZmkLogLine '--- 5 messages dropped ---').Type
    Assert-Equal $null (ConvertFrom-KcZmkLogLine '   ')
    $h = ConvertFrom-KcZmkLogLine (New-ZlLine 1 'decide_hold_tap' '34 decided hold-interrupt (balanced decision moment other-key-up)')
    Assert-Equal 'ht_decided' $h.Type
    Assert-Equal 'hold-interrupt' $h.Decision
    Assert-Equal 'other-key-up' $h.Moment
    $k = ConvertFrom-KcZmkLogLine (New-ZlLine 1 'on_keymap_binding_pressed' 'position 6 keycode 0x107001B')
    Assert-Equal 'kp' $k.Type
    Assert-Equal 0x107001B $k.Keycode
    Assert-True $k.Pressed
}

Test-Case 'hold-tap の判定待ちの間の行 (保留・素通し・流し直し・後片付け)' {
    $c = ConvertFrom-KcZmkLogLine (New-ZlLine 1 'position_state_changed_listener' '34 capturing 15 down event')
    Assert-Equal 'ht_capture' $c.Type
    Assert-Equal 34 $c.Pos
    Assert-Equal 15 $c.Other
    Assert-True $c.Pressed
    $b = ConvertFrom-KcZmkLogLine (New-ZlLine 1 'position_state_changed_listener' '34 bubbling 12 up event')
    Assert-Equal 'ht_bubble' $b.Type
    Assert-Equal $false $b.Pressed
    $k = ConvertFrom-KcZmkLogLine (New-ZlLine 1 'keycode_state_changed_listener' '34 capturing 0xE1 down event')
    Assert-Equal 'other' $k.Type '修飾キーの保留は位置ではない'
    $r = ConvertFrom-KcZmkLogLine (New-ZlLine 1 'release_captured_events' 'Releasing key position event for position 15 released')
    Assert-Equal 'ht_replay' $r.Type
    Assert-Equal 15 $r.Pos
    Assert-Equal $false $r.Pressed
    Assert-Equal 'ht_cleanup' (ConvertFrom-KcZmkLogLine (New-ZlLine 1 'on_hold_tap_binding_released' '34 cleaning up hold-tap')).Type
    Assert-Equal 'ht_retro' (ConvertFrom-KcZmkLogLine (New-ZlLine 1 'decide_retro_tap' '34 retro tap')).Type
    Assert-Equal 'ht_retro_hold' (ConvertFrom-KcZmkLogLine (New-ZlLine 1 'update_hold_status_for_retro_tap' 'Update hold tap 34 status to hold-interrupt')).Type
    Assert-Equal 'ht_hwu' (ConvertFrom-KcZmkLogLine (New-ZlLine 1 'decide_hold_tap' '34 hold behavior pressed while undecided')).Type
}

Test-Case '途中で切れた行をつなぐ' {
    $buf = ''
    $a = Split-KcLogChunk ([ref]$buf) "abc`r`nde"
    Assert-Equal 'abc' ($a -join '|')
    $b = Split-KcLogChunk ([ref]$buf) "f`r`n`r`ngh"
    Assert-Equal 'def' ($b -join '|')
    Assert-Equal 'gh' $buf
}

Test-Case 'SYM を押したまま Q: レイヤーがオンになり、SYM の 1 が送られる (ペリフェラルのキー)' {
    $lines = @(
        (New-ZlPos 10000 35 $true $false), (New-ZlApply 10000.1 0 35 'momentary_layer')) + (New-ZlMo 10000.2 35 1 $true) + @(
        (New-ZlPos 10100 0 $true $false), (New-ZlApply 10100.1 1 0 'key_press')) + (New-ZlKey 10100.2 0 0x7001E 0x1E 0 0 $true) + @(
        (New-ZlPos 10150 0 $false $false), (New-ZlApply 10150.1 1 0 'key_press')) + (New-ZlKey 10150.2 0 0x7001E 0x1E 0 0 $false) + @(
        (New-ZlPos 10200 35 $false $false), (New-ZlApply 10200.1 0 35 'momentary_layer')) + (New-ZlMo 10200.2 35 1 $false)
    $st = Invoke-ZlTrace $lines
    Assert-Equal 4 $st.Events.Count
    $sym = Get-ZlPress $st 35
    Assert-Equal 'SYM オン' ($sym.LayerChanges -join ',')
    Assert-True (@($sym.Steps | Where-Object { $_ -eq '押している間 SYM' }).Count -eq 1) ($sym.Steps -join ',')
    $q = Get-ZlPress $st 0
    Assert-Equal 1 $q.Resolved.Layer
    Assert-Equal '&kp N1' $q.Resolved.Src
    Assert-Equal '1' (Format-KcStrokeList $q.Outputs $scan)
    Assert-Equal '0' (@($st.Active) -join ',') '離すと BASE だけ'
    Assert-Equal 0 $st.Held.Count
    Assert-True ((Format-KcTraceEvent $st $q $scan) -like '*SYM: &kp N1 → 1*') (Format-KcTraceEvent $st $q $scan)
}

Test-Case '図の表示: 最上位のレイヤーの表示。押しているレイヤーキーは、押したときのレイヤーの表示のまま' {
    $pos = [int[]]@($lism.physical.keys | ForEach-Object { [int]$_.pos })
    $base = @($lism.interactive.behaviors.layers[0].legends)
    $vim = @($lism.interactive.behaviors.layers[2].legends)
    $idx36 = [array]::IndexOf($pos, 36)
    $idx6 = [array]::IndexOf($pos, 6)
    $st = Invoke-ZlTrace @()
    $lg = Get-KcTraceLegends $st $pos
    Assert-Equal 0 $lg.Top
    Assert-Equal $pos.Count $lg.Legends.Count
    Assert-Equal ([string]$base[6]) $lg.Legends[$idx6]
    $before = $lg.Signature
    # VIM_BASE (36) を押したまま: VIM_BASE レイヤーの 36 は &none (表示なし) だが、押しているキーは BASE の「VIM_BASE」のまま
    $st = Invoke-ZlTrace (@((New-ZlPos 1000 36 $true $true), (New-ZlApply 1000.1 0 36 'momentary_layer')) + (New-ZlMo 1000.2 36 2 $true))
    Assert-Equal '' ([string]$vim[36]) '前提: VIM_BASE レイヤーの 36 は表示なし'
    $lg = Get-KcTraceLegends $st $pos
    Assert-Equal 2 $lg.Top
    Assert-Equal 'VIM_BASE' $lg.Legends[$idx36]
    Assert-Equal ([string]$vim[6]) $lg.Legends[$idx6]
    Assert-True ($lg.Signature -ne $before) '表示が変わったことが分かる'
    # 離すと BASE の表示に戻る
    $st = Invoke-ZlTrace (@((New-ZlPos 1000 36 $true $true), (New-ZlApply 1000.1 0 36 'momentary_layer')) + (New-ZlMo 1000.2 36 2 $true) +
        @((New-ZlPos 1200 36 $false $true), (New-ZlApply 1200.1 0 36 'momentary_layer')) + (New-ZlMo 1200.2 36 2 $false))
    $lg = Get-KcTraceLegends $st $pos
    Assert-Equal 0 $lg.Top
    Assert-Equal 'VIM_BASE' $lg.Legends[$idx36]
    Assert-Equal ([string]$base[6]) $lg.Legends[$idx6]
    Assert-Equal $before $lg.Signature
}

Test-Case '&trans で下のレイヤーへ: VIM_BASE の Win の位置は BASE の &kp LEFT_WIN' {
    $lines = @(
        (New-ZlPos 1000 36 $true $true), (New-ZlApply 1000.1 0 36 'momentary_layer')) + (New-ZlMo 1000.2 36 2 $true) + @(
        (New-ZlPos 1100 31 $true $false), (New-ZlApply 1100.1 2 31 'transparent'),
        (New-ZlLine 1100.2 'zmk_keymap_position_state_changed' 'behavior processing to continue to next layer'),
        (New-ZlApply 1100.3 0 31 'key_press')) + (New-ZlKey 1100.4 31 0x70008 0xE3 0 0 $true)
    $st = Invoke-ZlTrace $lines
    $w = Get-ZlPress $st 31
    Assert-Equal 2 $w.Chain.Count
    Assert-True $w.Chain[0].Trans '&trans'
    Assert-Equal 0 $w.Resolved.Layer
    Assert-Equal '&kp LEFT_WIN' $w.Resolved.Src
    $rows = Get-KcTraceCascade $st $w
    Assert-Equal 'VIM_BASE:trans,BASE:on' ((@($rows | ForEach-Object { '{0}:{1}' -f $_.Name, $_.State })) -join ',')
    Assert-True ((Format-KcTraceEvent $st $w $scan) -like '*&trans で 1 つ下へ*')
}

Test-Case 'モッドモーフ: Ctrl を押したまま U → PgUp (Ctrl はマスクされる)' {
    $lines = @(
        (New-ZlPos 1000 36 $true $true), (New-ZlApply 1000.1 0 36 'momentary_layer')) + (New-ZlMo 1000.2 36 2 $true) + @(
        (New-ZlPos 1100 10 $true $false), (New-ZlApply 1100.1 2 10 'key_press')) + (New-ZlKey 1100.2 10 0x700E0 0xE0 0 0 $true) + @(
        (New-ZlPos 1200 6 $true $true), (New-ZlApply 1200.1 2 6 'MM_VIM_U')) + (New-ZlKey 1200.2 6 0x7004B 0x4B 0 0x01 $true)
    $st = Invoke-ZlTrace $lines
    $u = Get-ZlPress $st 6
    Assert-Equal '&mm_vim_u' $u.Resolved.Src
    Assert-True ($u.Steps[0] -like 'mm_vim_u: Ctrl を押している → &kp PAGE_UP') $u.Steps[0]
    Assert-Equal 'PgUp' (Format-KcStrokeList $u.Outputs $scan) 'マスクで Ctrl は付かない'
    # 修飾なし
    $lines2 = @(
        (New-ZlPos 1000 36 $true $true), (New-ZlApply 1000.1 0 36 'momentary_layer')) + (New-ZlMo 1000.2 36 2 $true) + @(
        (New-ZlPos 1200 6 $true $true), (New-ZlApply 1200.1 2 6 'MM_VIM_U')) + (New-ZlKey 1200.2 6 0x107001D 0x1D 0x01 0 $true)
    $u2 = Get-ZlPress (Invoke-ZlTrace $lines2) 6
    Assert-True ($u2.Steps[0] -like 'mm_vim_u: Ctrl なし → &kp LC(Z)') $u2.Steps[0]
    Assert-Equal 'Ctrl+Z' (Format-KcStrokeList $u2.Outputs $scan)
}

Test-Case 'ホールドタップ: Space を押したまま H。捕まった H は、ホールドに決まってから VIM_BASE で解決される' {
    $lines = @(
        (New-ZlPos 1000 34 $true $false), (New-ZlApply 1000.1 0 34 'layer_tap'),
        (New-ZlLine 1000.2 'on_hold_tap_binding_pressed' '34 new undecided hold_tap'),
        (New-ZlPos 1100 15 $true $true), (New-ZlLine 1100.1 'position_state_changed_listener' '34 capturing 15 down event'),
        (New-ZlPos 1150 15 $false $true), (New-ZlLine 1150.1 'position_state_changed_listener' '34 capturing 15 up event'),
        (New-ZlLine 1150.2 'decide_hold_tap' '34 decided hold-interrupt (balanced decision moment other-key-up)')) +
    (New-ZlMo 1150.3 34 2 $true) + @(
        (New-ZlApply 1150.5 2 15 'key_press')) + (New-ZlKey 1150.6 15 0x70050 0x50 0 0 $true) + @(
        (New-ZlApply 1150.8 2 15 'key_press')) + (New-ZlKey 1150.9 15 0x70050 0x50 0 0 $false)
    $st = Invoke-ZlTrace $lines
    $h = Get-ZlPress $st 15
    Assert-Equal 2 $h.Resolved.Layer
    Assert-Equal '&kp LEFT' $h.Resolved.Src
    Assert-Equal '←' (Format-KcStrokeList $h.Outputs $scan)
    $sp = Get-ZlPress $st 34
    $steps = $sp.Steps -join ' / '
    Assert-True ($steps -like '*ホールド (ほかのキー) に決定 (balanced、ほかのキーを離した)*') $steps
    Assert-True ($steps -like '*押している間 VIM_BASE*') $steps
    $rel = @($st.Events | Where-Object { $_.Pos -eq 15 -and -not $_.Pressed })[0]
    Assert-True $rel.Done '離したほうも解決済み'
}

Test-Case 'タップダンス: VIM_BASE で D を 2 回。2 回目の押下でマクロ' {
    $lines = @(
        (New-ZlPos 1000 36 $true $true), (New-ZlApply 1000.1 0 36 'momentary_layer')) + (New-ZlMo 1000.2 36 2 $true) + @(
        (New-ZlPos 1100 12 $true $false), (New-ZlApply 1100.1 2 12 'MM_VIM_D'),
        (New-ZlLine 1100.2 'on_tap_dance_binding_pressed' '12 created new tap dance'),
        (New-ZlLine 1100.3 'on_tap_dance_binding_pressed' '12 tap dance pressed'),
        (New-ZlPos 1150 12 $false $false), (New-ZlApply 1150.1 2 12 'MM_VIM_D'),
        (New-ZlLine 1150.2 'on_tap_dance_binding_released' '12 tap dance keybind released'),
        (New-ZlPos 1200 12 $true $false), (New-ZlApply 1200.1 2 12 'MM_VIM_D'),
        (New-ZlLine 1200.3 'on_tap_dance_binding_pressed' '12 tap dance pressed')) +
    (New-ZlKey 1200.5 12 0x7004A 0x4A 0 0 $true) + (New-ZlKey 1200.7 12 0x7004A 0x4A 0 0 $false) +
    (New-ZlKey 1300 12 0x207004D 0x4D 0x02 0 $true) + (New-ZlKey 1300.5 12 0x207004D 0x4D 0x02 0 $false) +
    (New-ZlKey 1400 12 0x107001B 0x1B 0x01 0 $true)
    $st = Invoke-ZlTrace $lines
    $first = Get-ZlPress $st 12 1
    $second = Get-ZlPress $st 12 2
    Assert-True (($first.Steps -join ' / ') -like '*mm_vim_d: Ctrl なし → &mm_vim_shift_d / mm_vim_shift_d: Shift なし → &td_vim_d / タップダンス: 1 回目*') ($first.Steps -join ' / ')
    Assert-True (($second.Steps -join ' / ') -like '*タップダンス: 2 回目*') ($second.Steps -join ' / ')
    Assert-Equal 'Home、Shift+End、Ctrl+X' (Format-KcStrokeList $second.Outputs $scan)
    Assert-Equal 0 $first.Outputs.Count
}

Test-Case 'ボールで AML になった (キーと関係ないレイヤーの変化)、ログの欠落、期待値と違うビヘイビア' {
    $lines = @(
        (New-ZlPos 1000 0 $true $false), (New-ZlApply 1000.1 0 0 'key_press')) + (New-ZlKey 1000.2 0 0x70014 0x14 0 0 $true) + @(
        (New-ZlLayer 5000 8 $true), '--- 3 messages dropped ---',
        (New-ZlPos 6000 1 $true $false), (New-ZlApply 6000.1 0 1 'MM_SOMETHING'))
    $st = Invoke-ZlTrace $lines
    $sys = @($st.Events | Where-Object { $_.Pos -lt 0 })
    Assert-Equal 1 $sys.Count
    Assert-Equal 'MOUS オン' ($sys[0].LayerChanges -join ',')
    Assert-True ((Format-KcTraceEvent $st $sys[0] $scan) -like '*レイヤーの変化: MOUS オン*')
    Assert-Equal 3 $st.Dropped
    Assert-True ($st.Active.Contains(8))
    $w = Get-ZlPress $st 1
    Assert-True $w.Mismatch 'ログのデバイス名が期待値 (key_press) と違う'
    $rows = Get-KcTraceCascade $st $w
    Assert-True (@($rows | Where-Object { $_.Text -like '*期待値と違う*' }).Count -eq 1)
    Assert-Equal '' ((@(Get-KcTraceCascade $st (Get-ZlPress $st 0)) | Where-Object { $_.State -eq 'trans' }) -join '')
}

Test-Case '期待値: ZMK の機種はデバイス名とレイヤーごとの表示を持つ' {
    foreach ($id in @('lism', 'kukey42', 'aroundfortyrb', 'pyuron', 'roba', 'torabo-tsuki-lp')) {
        $e = Get-KcExpected $id $script:ExpectedDir
        $st = New-KcLayerTrace $e
        Assert-True ($st.Defs.ContainsKey('key_press')) $id
        Assert-True ($st.Defs.ContainsKey('momentary_layer')) $id
        foreach ($l in @($e.interactive.behaviors.layers)) {
            Assert-Equal @($e.physical.keys).Count @($l.devs).Count ('{0} {1}' -f $id, $l.name)
        }
    }
}

# 書き込みツール (lib/flash-plan.ps1) は、$FlashKeyboards のセントラルの名前に _studio / _logging を付けてダウンロードする。
# その名前が、各リポジトリの build.yaml (期待値の studio_artifacts / logging_artifacts) にあること
Test-Case 'アセット名: 書き込みツールのセントラル + _studio / _logging が build.yaml にある' {
    . (Join-Path $script:ToolsDir 'lib\flash-plan.ps1')
    $count = 0
    foreach ($key in @($script:FlashKeyboards.Keys)) {
        $k = $script:FlashKeyboards[$key]
        if ($k.Kind -ne 'zmk') {
            continue
        }
        $id = ([string]$key).ToLowerInvariant()
        $right = [string]$k.Right
        $names = @($right)
        if ($right.Contains('{v}')) { $names = @($right.Replace('{v}', 'trackball'), $right.Replace('{v}', 'non_trackball')) }
        $e = Get-KcExpected $id $script:ExpectedDir
        foreach ($n in $names) {
            Assert-True (@($e.device.studio_artifacts) -contains ($n + '_studio')) ('{0}: {1}_studio' -f $id, $n)
            Assert-True (@($e.device.logging_artifacts) -contains ($n + '_logging')) ('{0}: {1}_logging' -f $id, $n)
        }
        Assert-Equal $names.Count @($e.device.logging_artifacts).Count ('{0} のログ版の数' -f $id)
        $count++
    }
    Assert-Equal 6 $count 'ZMK の機種の数'
}
