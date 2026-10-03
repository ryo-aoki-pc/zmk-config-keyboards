# タップホールドのシミュレータ (hold-tap-sim.ps1 / hold-tap-qmk.ps1) と、タイミングのグラフの計算 (hold-tap.ps1) のテスト

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'hold-tap-sim.ps1')
. (Join-Path $script:KcLib 'hold-tap.ps1')
. (Join-Path $script:KcLib 'zmk-log.ps1')
. (Join-Path $script:TestsDir 'hold-tap-vectors-zmk.ps1')
. (Join-Path $script:TestsDir 'hold-tap-vectors-qmk.ps1')

# 'p0@0 r0@10' → @(@{ Pos = 0; Down = $true; T = 0 }, ...)
function ConvertTo-HtEvents([string]$Text) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($tok in ($Text -split '\s+')) {
        if (-not $tok) { continue }
        if ($tok -notmatch '^([pr])(\d+)@(-?\d+)$') { throw "入力の書き方が違います: $tok" }
        $out.Add(@{ Pos = [int]$Matches[2]; Down = ($Matches[1] -eq 'p'); T = [long]$Matches[3] })
    }
    return , $out.ToArray()
}

# 位置ごとのバインディングの並び (レイヤー 0 だけ) → シミュレータのキーマップ
function New-HtTestKeymap($Keys, $Behaviors) {
    $map = @{}
    for ($i = 0; $i -lt @($Keys).Count; $i++) {
        $map[$i] = @{ 0 = @($Keys)[$i] }
    }
    return @{ Keys = $map; Behaviors = $Behaviors }
}

Test-Case 'ZMK: app/tests/hold-tap の全件で、ZMK と同じログの行を出す' {
    $prefixes = @('kp_', 'mo_', 'ht_binding_', 'ht_decide')
    $bad = New-Object 'System.Collections.Generic.List[string]'
    foreach ($v in $script:KcHtZmkVectors) {
        $km = New-HtTestKeymap $v.Keys $v.Behaviors
        $r = Invoke-KcZmkHoldTap -Keymap $km -Events (ConvertTo-HtEvents $v.Events) -TickMs 10 -Trace
        $allow = $prefixes
        if ($v.Retro) { $allow = $prefixes + @('decide_retro_tap', 'update_hold_status_for_retro_tap') }
        $got = @($r.Lines | Where-Object {
                $line = $_
                @($allow | Where-Object { $line.StartsWith($_) }).Count -gt 0
            })
        $want = @($v.Expect)
        if (($got -join "`n") -ne ($want -join "`n")) {
            $bad.Add(('{0}:{1}  期待:{1}    {2}{1}  実際:{1}    {3}' -f $v.Name, "`n", ($want -join "`n    "), ($got -join "`n    ")))
        }
    }
    if ($bad.Count -gt 0) {
        throw ('{0} / {1} 件が違います{2}{3}' -f $bad.Count, @($script:KcHtZmkVectors).Count, "`n", (($bad | Select-Object -First 3) -join "`n"))
    }
}

Test-Case 'QMK: tests/tap_hold_configurations で、QMK と同じ HID のレポートを出す' {
    $bad = New-Object 'System.Collections.Generic.List[string]'
    foreach ($v in $script:KcHtQmkVectors) {
        $keys = @{}
        foreach ($k in $v.Keys) {
            if (-not $keys.ContainsKey($k.Pos)) { $keys[$k.Pos] = @{} }
            $keys[$k.Pos][$k.Layer] = $k.Binding
        }
        $km = @{ Keys = $keys; Qmk = $v.Settings; Hands = $v.Hands }
        $r = Invoke-KcQmkTapHold -Keymap $km -Events (ConvertTo-HtEvents $v.Events) -Trace
        $got = @($r.Lines | Where-Object { $_.StartsWith('report: ') })
        $want = @($v.Expect)
        if (($got -join "`n") -ne ($want -join "`n")) {
            $bad.Add(('{0}:{1}  入力: {4}{1}  期待:{1}    {2}{1}  実際:{1}    {3}' -f $v.Name, "`n", ($want -join "`n    "), ((@($r.Lines)) -join "`n    "), $v.Events))
        }
    }
    if ($bad.Count -gt 0) {
        throw ('{0} / {1} 件が違います{2}{3}' -f $bad.Count, @($script:KcHtQmkVectors).Count, "`n", (($bad | Select-Object -First 4) -join "`n"))
    }
}

$script:HtLism = New-KcHtModel (Get-KcExpected 'lism' $script:ExpectedDir)
$script:HtKq = New-KcHtModel (Get-KcExpected 'kq-mini' $script:ExpectedDir)

# 期待値からの計算: 対象のキーとプリセットの入力で、判定と届く入力
function Invoke-HtPreset($Model, [int]$Target, [string]$Preset, [hashtable]$Params = @{}) {
    $cfg = New-KcHtConfig $Model
    foreach ($k in $Params.Keys) { Set-KcHtParamValue $Model $cfg $Target $k ([string]$Params[$k]) }
    $pr = New-KcHtPreset $Model $cfg $Target $Preset
    $r = Invoke-KcHtRun $Model (Get-KcHtKeymapWith $Model $cfg) $pr.Events
    $d = [KcHtText]::DecisionFor($r, $pr.TargetIndex)
    $status = ''
    if ($null -ne $d) { $status = $d.Status }
    return @{ Status = $status; Strokes = [KcHtText]::Strokes($r); Result = $r; Preset = $pr; Config = $cfg; Decision = $d }
}

Test-Case 'モデル: LisM はキーマップの &mt / &lt (balanced 150 / quick-tap 0)、KQ-mini は Vial の設定、Keyball39 は無し' {
    Assert-Equal 'zmk' $script:HtLism.Engine
    $a = Get-KcHtTarget $script:HtLism 10
    Assert-Equal 'A' $a.TapLabel
    Assert-Equal 'Ctrl' $a.HoldLabel
    Assert-Equal 'mt' $a.Behavior
    $sp = Get-KcHtTarget $script:HtLism 34
    Assert-True $sp.HoldIsLayer 'Space は &lt (レイヤー)'
    $cfg = New-KcHtConfig $script:HtLism
    Assert-Equal 'balanced' (Get-KcHtParamValue $script:HtLism $cfg 10 'flavor')
    Assert-Equal 150 (Get-KcHtParamValue $script:HtLism $cfg 10 'term')
    Assert-Equal 0 (Get-KcHtParamValue $script:HtLism $cfg 10 'quick')
    Assert-Equal 'A (Ctrl)' (Get-KcHtKeyName $script:HtLism 10)
    Assert-Equal 'qmk' $script:HtKq.Engine
    $kc = New-KcHtConfig $script:HtKq
    Assert-Equal 150 (Get-KcHtParamValue $script:HtKq $kc 10 'term')
    Assert-Equal '1' (Get-KcHtParamValue $script:HtKq $kc 10 'permissive')
    Assert-Equal $null (New-KcHtModel (Get-KcExpected 'keyball39' $script:ExpectedDir))
}

Test-Case 'プリセット: どの機種・対象でも、押す → 離すの順で、相手は反対の手の文字キー' {
    foreach ($id in @('lism', 'kukey42', 'aroundfortyrb', 'pyuron', 'roba', 'torabo-tsuki-lp', 'kq-mini')) {
        $m = New-KcHtModel (Get-KcExpected $id $script:ExpectedDir)
        $cfg = New-KcHtConfig $m
        foreach ($t in $m.Targets) {
            foreach ($p in (Get-KcHtPresetDefs $m $t.Pos)) {
                $pr = New-KcHtPreset $m $cfg $t.Pos $p.Id
                $down = @{}
                foreach ($e in $pr.Events) {
                    Assert-True ($e.Pos -ge 0) ('{0} {1} {2}: 相手のキーが見つからない' -f $id, $t.Pos, $p.Id)
                    $was = $down.ContainsKey($e.Pos) -and $down[$e.Pos]
                    Assert-True ($was -ne $e.Down) ('{0} {1} {2}: 押す / 離すの順' -f $id, $t.Pos, $p.Id)
                    $down[$e.Pos] = $e.Down
                }
                Assert-True $pr.Events[$pr.TargetIndex].Down ('{0} {1}: 判定を見るのは押下' -f $id, $p.Id)
                Assert-Equal $t.Pos $pr.Events[$pr.TargetIndex].Pos
            }
            $partner = Get-KcHtPartner $m $t.Pos
            Assert-True ($m.Keys[$partner].Hand -ne $m.Keys[$t.Pos].Hand) ('{0} {1}: 反対の手' -f $id, $t.Pos)
        }
    }
}

Test-Case 'LisM の A (balanced 150): ロールはタップ、包むとホールド、flavor と term で変わる' {
    $roll = Invoke-HtPreset $script:HtLism 10 'roll'
    Assert-Equal 'tap' $roll.Status
    Assert-Equal 'A H' $roll.Strokes
    $nest = Invoke-HtPreset $script:HtLism 10 'nest'
    Assert-Equal 'hold-interrupt' $nest.Status
    Assert-Equal 'other-key-up' $nest.Decision.Moment
    Assert-Equal 'Ctrl+H' $nest.Strokes
    Assert-Equal 'hold-interrupt' (Invoke-HtPreset $script:HtLism 10 'roll' @{ flavor = 'hold-preferred' }).Status 'hold-preferred はほかのキーを押したらホールド'
    Assert-Equal 'tap' (Invoke-HtPreset $script:HtLism 10 'nest' @{ flavor = 'tap-preferred' }).Status 'tap-preferred は 140ms < 150ms でタップ'
    Assert-Equal 'hold-timer' (Invoke-HtPreset $script:HtLism 10 'nest' @{ flavor = 'tap-preferred'; term = 120 }).Status
    Assert-Equal 'tap' (Invoke-HtPreset $script:HtLism 10 'prior' @{ idle = 150 }).Status 'require-prior-idle 150 で、直前のキーから 120ms は quick-tap'
    Assert-Equal 'tap' (Invoke-HtPreset $script:HtLism 10 'double' @{ quick = 200 }).Status 'quick-tap 200 で押し直しはタップ'
    $pos = Invoke-HtPreset $script:HtLism 10 'nest' @{ positional = 'opposite' }
    Assert-Equal 'hold-interrupt' $pos.Status '反対の手の H ならホールド'
    $same = New-KcHtConfig $script:HtLism
    Set-KcHtParamValue $script:HtLism $same 10 'positional' 'opposite'
    $pr = New-KcHtPreset $script:HtLism $same 10 'nest' -Same
    $r = Invoke-KcHtRun $script:HtLism (Get-KcHtKeymapWith $script:HtLism $same) $pr.Events
    $d = [KcHtText]::DecisionFor($r, $pr.TargetIndex)
    Assert-Equal 'tap' $d.Status '同じ手のキーならタップ'
    Assert-True $d.Positional
    $changed = Get-KcHtChangedParams $script:HtLism $same 10
    Assert-Equal 'positional' ($changed -join ',')
}

Test-Case 'KQ-mini (QMK): PERMISSIVE_HOLD で包むとホールド、オフなら TAPPING_TERM まで待つ' {
    Assert-Equal 'hold' (Invoke-HtPreset $script:HtKq 10 'nest').Status
    Assert-Equal 'permissive' (Invoke-HtPreset $script:HtKq 10 'nest').Decision.Moment
    Assert-Equal 'tap' (Invoke-HtPreset $script:HtKq 10 'nest' @{ permissive = 0 }).Status
    Assert-Equal 'hold' (Invoke-HtPreset $script:HtKq 10 'roll' @{ permissive = 0; hoop = 1 }).Status
    # A の KQ-mini の手は '*' (HID コード 0x04 の列 4) なので、chordal hold でもホールドになる
    Assert-Equal 'hold' (Invoke-HtPreset $script:HtKq 10 'nest' @{ chordal = 1 }).Status
    # Z (0x1D、列 5 = R) を押したまま J (0x0D、列 5 = R) を押して離す: KQ-mini では同じ手なのでタップ
    $j = @($script:HtKq.Keys.Values | Where-Object { $null -ne $_.Base -and $_.Base.Kind -eq 'kp' -and $_.Base.Usage -eq 0x0D })[0].Pos
    $ev = @(@{ Pos = 20; Down = $true; T = 0 }, @{ Pos = $j; Down = $true; T = 50 }, @{ Pos = $j; Down = $false; T = 90 }, @{ Pos = 20; Down = $false; T = 130 })
    $cfg = New-KcHtConfig $script:HtKq
    Assert-Equal 'hold' ([KcHtText]::DecisionFor((Invoke-KcHtRun $script:HtKq (Get-KcHtKeymapWith $script:HtKq $cfg) $ev), 0)).Status
    Set-KcHtParamValue $script:HtKq $cfg 20 'chordal' '1'
    $d = [KcHtText]::DecisionFor((Invoke-KcHtRun $script:HtKq (Get-KcHtKeymapWith $script:HtKq $cfg) $ev), 0)
    Assert-Equal 'tap' $d.Status
    Assert-Equal 'chordal' $d.Moment
}

Test-Case '帯: 離す時刻を 1ms ずつ動かした結果が、1 回ずつ計算した結果と同じ' {
    foreach ($m in @($script:HtLism, $script:HtKq)) {
        $cfg = New-KcHtConfig $m
        foreach ($preset in @('roll', 'nest', 'double', 'prior')) {
            $pr = New-KcHtPreset $m $cfg 10 $preset
            $km = Get-KcHtKeymapWith $m $cfg
            $range = @{ From = -200; To = 400 }
            foreach ($handle in 0..($pr.Events.Count - 1)) {
                $segs = @(Get-KcHtSweep $m $km $pr.Events $pr.TargetIndex $handle $range 'mt')
                Assert-True ($segs.Count -ge 1) ('{0} {1}: 区間がある' -f $preset, $handle)
                for ($i = 1; $i -lt $segs.Count; $i++) {
                    Assert-Equal ($segs[$i - 1].To + 1) $segs[$i].From ('{0}: 区間がつながる' -f $preset)
                }
                foreach ($s in $segs) {
                    foreach ($t in @($s.From, $s.To)) {
                        $ev = Set-KcHtEventTime $pr.Events $handle $t
                        $r = Invoke-KcHtRun $m $km $ev
                        $d = [KcHtText]::DecisionFor($r, $pr.TargetIndex)
                        $st = ''
                        if ($null -ne $d) { $st = $d.Status }
                        Assert-Equal $s.Status $st ('{0} 入力 {1} を {2} ms' -f $preset, $handle, $t)
                        Assert-Equal $s.Text ([KcHtText]::Strokes($r))
                    }
                }
            }
        }
    }
    $text = Format-KcHtSegments $script:HtLism @(
        @{ From = 51; To = 130; Status = 'tap'; Text = 'A H' }, @{ From = 131; To = 400; Status = 'hold-interrupt'; Text = 'Ctrl+H' })
    Assert-Equal '〜130 ms: タップ → A H / 131 ms〜: ホールド (ほかのキー) → Ctrl+H' $text
}

Test-Case 'グラフのモデル: レーン・判定の線・tapping-term の線・動かせる入力' {
    $m = $script:HtLism
    $cfg = New-KcHtConfig $m
    $pr = New-KcHtPreset $m $cfg 10 'nest'
    $km = Get-KcHtKeymapWith $m $cfg
    $r = Invoke-KcHtRun $m $km $pr.Events
    $range = Get-KcHtRange $pr.Events $r 0 150
    Assert-Equal -100 $range.From
    $view = @{ Model = $m; Config = $cfg; Target = 10; Events = $pr.Events; TargetIndex = $pr.TargetIndex; Selected = $pr.Handle
        Result = $r; Base = $null; Firmware = $null; Range = $range; Sweeps = @{ Handle = (Get-KcHtSweep $m $km $pr.Events 0 $pr.Handle $range 'mt'); Compare = @(); Term = $null } }
    $ch = Get-KcHoldTapChart $view
    $titles = @($ch.Lanes | ForEach-Object { $_.Title })
    Assert-Equal '押したキー,A (Ctrl),H,PC に届く入力,Ctrl,H' (($titles | Select-Object -First 6) -join ',')
    $styles = @($ch.Bars | Where-Object { $_.Lane -eq 1 } | ForEach-Object { $_.Style })
    Assert-Equal "$($script:KcHtBarUndecided),$($script:KcHtBarHold)" ($styles -join ',') '判定待ち → ホールド'
    $term = @($ch.Marks | Where-Object { $_.Style -eq $script:KcHtMarkTerm })
    Assert-Equal 150 $term[0].At
    Assert-Equal $script:KcHtHandleTerm $term[0].Handle
    $dec = @($ch.Marks | Where-Object { $_.Style -eq $script:KcHtMarkDecision })
    Assert-Equal 100 $dec[0].At
    Assert-Equal 1 $ch.Arrows.Count 'H の押下は判定まで保留'
    Assert-Equal 5 $ch.Handles.Count
    Assert-Equal 2 $ch.Selected
}

# ログ版ファームの行 (zmk-log.Tests.ps1 と同じ書式)
function New-HtLog([double]$Ms, [string]$Func, [string]$Msg) {
    $ts = [TimeSpan]::FromMilliseconds([math]::Floor($Ms))
    $us = [int](($Ms - [math]::Floor($Ms)) * 1000)
    return ('[{0:00}:{1:00}:{2:00}.{3:000},{4:000}] <dbg> zmk: {5}: {6}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds, $us, $Func, $Msg)
}

Test-Case 'ログ: A (ペリフェラル) を押したまま H (セントラル) を押して離すと、1 回分を切り出し、ファームと計算が合う' {
    $lines = @(
        (New-HtLog 5000.2 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
        (New-HtLog 5000.4 'on_hold_tap_binding_pressed' '10 new undecided hold_tap'),
        (New-HtLog 5060.3 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: true'),
        (New-HtLog 5060.4 'position_state_changed_listener' '10 capturing 15 down event'),
        (New-HtLog 5100.1 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: false'),
        (New-HtLog 5100.2 'position_state_changed_listener' '10 capturing 15 up event'),
        (New-HtLog 5100.3 'decide_hold_tap' '10 decided hold-interrupt (balanced decision moment other-key-up)'),
        (New-HtLog 5100.4 'hid_listener_keycode_pressed' 'usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00'),
        (New-HtLog 5100.5 'hid_listener_keycode_pressed' 'usage_page 0x07 keycode 0x0B implicit_mods 0x00 explicit_mods 0x00'),
        (New-HtLog 5100.6 'hid_listener_keycode_released' 'usage_page 0x07 keycode 0x0B implicit_mods 0x00 explicit_mods 0x00'),
        (New-HtLog 5150.0 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
        (New-HtLog 5150.1 'hid_listener_keycode_released' 'usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00'),
        (New-HtLog 5150.2 'on_hold_tap_binding_released' '10 cleaning up hold-tap'),
        (New-HtLog 6000.0 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: true')
    )
    $cap = New-KcHtCapture $script:HtLism
    $eps = @()
    foreach ($l in $lines) {
        $ep = Update-KcHtCapture $cap (ConvertFrom-KcZmkLogLine $l)
        if ($null -ne $ep) { $eps += $ep }
    }
    Assert-Equal 1 $eps.Count
    $ep = $eps[0]
    Assert-Equal 10 $ep.Target
    Assert-Equal 'p10@0 p15@60 r15@100 r10@150' (($ep.Events | ForEach-Object { '{0}{1}@{2}' -f @('r', 'p')[[int]$_.Down], $_.Pos, $_.T }) -join ' ')
    Assert-Equal 0 $ep.TargetIndex
    Assert-Equal 'hold-interrupt' $ep.Decisions[0].Status
    Assert-Equal 100 $ep.Decisions[0].T
    Assert-Equal 4 @($ep.Hid).Count
    Assert-True $ep.Uncertain '左手側のキーは押す / 離すを数えた'
    $cmp = Compare-KcHtFirmware $script:HtLism $ep
    Assert-Equal 1 $cmp.Level $cmp.Text
    Assert-True ((Format-KcHtEpisode $script:HtLism $ep) -like '*A (Ctrl) + H → ホールド (ほかのキー)') (Format-KcHtEpisode $script:HtLism $ep)
}

Test-Case 'ログ: 欠けたエピソードは比べない。左手側の押す / 離すのずれは hold-tap の行で直す' {
    $cap = New-KcHtCapture $script:HtLism
    # 前に 10 を押したことになっている (ログが欠けて離すが届かなかった)
    $cap.Held[10] = $true
    $lines = @(
        (New-HtLog 1000 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
        (New-HtLog 1000.2 'on_hold_tap_binding_pressed' '10 new undecided hold_tap'),
        '--- 3 messages dropped ---',
        (New-HtLog 1080 'decide_hold_tap' '10 decided tap (balanced decision moment key-up)'),
        (New-HtLog 1080.1 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
        (New-HtLog 1080.2 'on_hold_tap_binding_released' '10 cleaning up hold-tap')
    )
    foreach ($l in $lines) { [void](Update-KcHtCapture $cap (ConvertFrom-KcZmkLogLine $l)) }
    $ep = Complete-KcHtCapture $cap
    Assert-True ($null -ne $ep) '判定待ちが無く、すべて離した'
    Assert-True $ep.Dropped
    Assert-Equal 'p10@0 r10@80' (($ep.Events | Where-Object { $_.T -ge 0 } | ForEach-Object { '{0}{1}@{2}' -f @('r', 'p')[[int]$_.Down], $_.Pos, $_.T }) -join ' ')
    Assert-Equal 0 (Compare-KcHtFirmware $script:HtLism $ep).Level
}
