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

# 'p10@0 p15@50 r15@100 r10@140' → 1 回分 (対象は最初に 0 ms に押したキー)
function New-HtEpisode([string]$Text, [bool]$Live = $false, $Decisions = @()) {
    $events = ConvertTo-HtEvents $Text
    $ti = 0
    for ($i = 0; $i -lt $events.Count; $i++) {
        if ($events[$i].Down -and $events[$i].T -eq 0) { $ti = $i; break }
    }
    foreach ($e in $events) {
        $role = 'partner'
        if ($e.Pos -eq $events[$ti].Pos) { $role = 'target' } elseif ($e.T -lt 0) { $role = 'prior' }
        $e.Role = $role
    }
    # 一緒に押すキー: 対象でない最初のキー (無ければ H)
    $partner = 15
    foreach ($e in $events) {
        if ($e.Pos -ne $events[$ti].Pos) { $partner = $e.Pos; break }
    }
    return @{ Seq = 1; Target = $events[$ti].Pos; Partner = $partner; T0 = 0; Events = $events; TargetIndex = $ti; Decisions = @($Decisions); Hid = @()
        Dropped = $false; Uncertain = $false; Cut = $false; Limit = 650; Live = $Live }
}

# 1 回分を、設定 $Config で計算する
function Invoke-HtEpisode($Episode, $Config = $null, $Now = $null) {
    if ($null -eq $Config) { $Config = New-KcHtConfig }
    $r = Invoke-KcHtRun (Get-KcHtKeymapWith $script:HtLism $Config) $Episode.Events
    $range = Get-KcHtRange $Episode (Get-KcHtSetting $script:HtLism $Config 'mt').Term
    $sw = Get-KcHtReleaseSweeps $script:HtLism $Config $Episode $range
    $d = [KcHtText]::DecisionFor($r, $Episode.TargetIndex)
    $status = ''
    if ($null -ne $d) { $status = $d.Status }
    return @{ Result = $r; Range = $range; Sweeps = $sw; Status = $status; Decision = $d; Strokes = [KcHtText]::Strokes($r)
        Summary = (Get-KcHtSummary $script:HtLism $Config $Episode $r $sw $Now) }
}

Test-Case 'モデル: LisM はキーマップの &mt / &lt (balanced 150)、KQ-mini と Keyball39 は対象外' {
    Assert-Equal 'LisM' $script:HtLism.Name
    Assert-Equal 'mt' (Get-KcHtBehavior $script:HtLism 10)
    Assert-Equal 'lt' (Get-KcHtBehavior $script:HtLism 34)
    Assert-Equal '' (Get-KcHtBehavior $script:HtLism 15) 'H は hold-tap ではない'
    $s = Get-KcHtSetting $script:HtLism (New-KcHtConfig) 'mt'
    Assert-Equal 'balanced' $s.Flavor
    Assert-Equal 150 $s.Term
    Assert-Equal $false $s.Changed
    Assert-Equal 'A (Ctrl)' (Get-KcHtKeyName $script:HtLism 10)
    Assert-Equal $null (New-KcHtModel (Get-KcExpected 'kq-mini' $script:ExpectedDir))
    Assert-Equal $null (New-KcHtModel (Get-KcExpected 'keyball39' $script:ExpectedDir))
}

Test-Case '設定: flavor と tapping-term を変えると判定が変わる。キーマップの値に戻すと上書きが消える' {
    $roll = New-HtEpisode 'p10@0 p15@50 r10@90 r15@130'
    $nest = New-HtEpisode 'p10@0 p15@50 r15@100 r10@140'
    Assert-Equal 'tap' (Invoke-HtEpisode $roll).Status
    Assert-Equal 'A H' (Invoke-HtEpisode $roll).Strokes
    Assert-Equal 'hold-interrupt' (Invoke-HtEpisode $nest).Status
    Assert-Equal 'Ctrl+H' (Invoke-HtEpisode $nest).Strokes
    $cfg = New-KcHtConfig
    Set-KcHtSetting $script:HtLism $cfg 'mt' 'flavor' 'hold-preferred'
    Assert-True (Get-KcHtSetting $script:HtLism $cfg 'mt').Changed
    Assert-Equal 'hold-interrupt' (Invoke-HtEpisode $roll $cfg).Status 'hold-preferred はほかのキーを押したらホールド'
    Assert-Equal 'balanced' (Get-KcHtSetting $script:HtLism $cfg 'lt').Flavor '&lt は変わらない'
    Set-KcHtSetting $script:HtLism $cfg 'mt' 'flavor' 'tap-preferred'
    Assert-Equal 'tap' (Invoke-HtEpisode $nest $cfg).Status 'tap-preferred は 140ms < 150ms でタップ'
    Set-KcHtSetting $script:HtLism $cfg 'mt' 'term' 120
    Assert-Equal 'hold-timer' (Invoke-HtEpisode $nest $cfg).Status
    $copy = Copy-KcHtConfig $cfg
    Set-KcHtSetting $script:HtLism $copy 'mt' 'term' 200
    Assert-Equal 120 (Get-KcHtSetting $script:HtLism $cfg 'mt').Term 'コピーは別'
    Set-KcHtSetting $script:HtLism $cfg 'mt' 'flavor' 'balanced'
    Set-KcHtSetting $script:HtLism $cfg 'mt' 'term' 150
    Assert-Equal 0 $cfg.Count 'キーマップの値と同じなら持たない'
}

Test-Case '離す時刻ごとの結果: 1ms ずつ動かした区間が、1 回ずつ計算した結果と同じ。flavor ごとの帯も出す' {
    $km = Get-KcHtKeymapWith $script:HtLism (New-KcHtConfig)
    foreach ($text in @('p10@0 p15@50 r10@90 r15@130', 'p10@0 p15@50 r15@100 r10@140', 'p15@-40 p10@0 r15@40 r10@100', 'p10@0 r10@80')) {
        $ep = New-HtEpisode $text
        $x = Invoke-HtEpisode $ep
        $rel = Get-KcHtReleaseIndex $ep
        Assert-Equal ([long]$ep.Events[$rel].T) $x.Sweeps.Release
        $segs = @($x.Sweeps.Segments)
        Assert-True ($segs.Count -ge 1) $text
        Assert-Equal 1 $segs[0].From
        for ($i = 1; $i -lt $segs.Count; $i++) { Assert-Equal ($segs[$i - 1].To + 1) $segs[$i].From ('{0}: 区間がつながる' -f $text) }
        foreach ($s in $segs) {
            foreach ($t in @($s.From, $s.To)) {
                $ev = @(for ($i = 0; $i -lt $ep.Events.Count; $i++) {
                        $e = $ep.Events[$i]
                        if ($i -eq $rel) { @{ Pos = $e.Pos; Down = $e.Down; T = [long]$t } } else { $e }
                    })
                $r = Invoke-KcHtRun $km $ev
                $d = [KcHtText]::DecisionFor($r, $ep.TargetIndex)
                Assert-Equal $s.Status $d.Status ('{0}: {1} ms に離す' -f $text, $t)
                Assert-Equal $s.Text ([KcHtText]::Strokes($r))
            }
        }
        Assert-Equal ($script:KcHtFlavors -join ',') (($x.Sweeps.Flavors | ForEach-Object { $_.Flavor }) -join ',')
        Assert-Equal 'balanced' (@($x.Sweeps.Flavors | Where-Object { $_.Current })[0].Flavor)
    }
    $roll = Invoke-HtEpisode (New-HtEpisode 'p10@0 p15@50 r10@90 r15@130')
    Assert-Equal '〜130 ms: タップ → A H / 131 ms〜: ホールド (ほかのキー) → Ctrl+H' (Format-KcHtSegments $roll.Sweeps.Segments)
}

Test-Case '押している最中: 仮の「離す」で、今離すとどうなるかを出す (A を押したまま)' {
    $ep = New-HtEpisode 'p10@0' $true
    $x = Invoke-HtEpisode $ep $null 87
    Assert-Equal $null $x.Sweeps.Release
    Assert-Equal '〜149 ms: タップ → A / 150 ms〜: ホールド (時間切れ) → Ctrl' (Format-KcHtSegments $x.Sweeps.Segments)
    Assert-Equal '判定待ち' $x.Summary.Title
    Assert-Equal '今離すと: タップ → A。150 ms を過ぎると ホールド (時間切れ) → Ctrl' $x.Summary.Lines[0]
    Assert-Equal 0 $x.Summary.Level
    $later = Invoke-HtEpisode $ep $null 160
    Assert-Equal 'ホールド (時間切れ) に決定 (150 ms)' $later.Summary.Title
    Assert-Equal 2 $later.Summary.Level
    Assert-True ($later.Summary.Key -ne $x.Summary.Key) '区間をまたぐと変わる'
    Assert-Equal (Invoke-HtEpisode $ep $null 120).Summary.Key $x.Summary.Key '同じ区間なら同じ'
    # H を押したまま (balanced): 今離すとタップ、H を離すとホールド
    $ep2 = New-HtEpisode 'p10@0 p15@50' $true
    $y = Invoke-HtEpisode $ep2 $null 70
    Assert-Equal '判定待ち' $y.Summary.Title
    Assert-True ($y.Summary.Lines[0] -like '今離すと: タップ → A H。*') $y.Summary.Lines[0]
}

Test-Case '要約: 決め手、保留されたキー、ファームの判定と違うとき' {
    $nest = New-HtEpisode 'p10@0 p15@50 r15@100 r10@140'
    $x = Invoke-HtEpisode $nest
    Assert-Equal 'ホールド (ほかのキー): PC に届くのは Ctrl+H' $x.Summary.Title
    Assert-Equal '決め手: 100 ms に H を離した (押している間に、ほかのキーを押して離した) (balanced)' $x.Summary.Lines[0]
    Assert-Equal 'H は判定まで保留され、50 ms 遅れて送られた' $x.Summary.Lines[1]
    Assert-Equal 2 $x.Summary.Lines.Count 'ファームと同じ (判定がログに無い) なら出さない'
    $fw = New-HtEpisode 'p10@0 p15@50 r15@100 r10@140' $false @(@{ Pos = 10; Status = 'tap'; Moment = 'key-up'; Flavor = 'balanced'; T = 140 })
    $y = Invoke-HtEpisode $fw
    Assert-True ($y.Summary.Lines[2] -like 'ファームの判定は タップ (140 ms)。計算と違う*') ($y.Summary.Lines -join ' / ')
    $cfg = New-KcHtConfig
    Set-KcHtSetting $script:HtLism $cfg 'mt' 'flavor' 'tap-preferred'
    $same = New-HtEpisode 'p10@0 p15@50 r15@100 r10@140' $false @(@{ Pos = 10; Status = 'hold-interrupt'; Moment = 'other-key-up'; Flavor = 'balanced'; T = 100 })
    $z = Invoke-HtEpisode $same $cfg
    Assert-Equal 'tap' $z.Status
    Assert-True ($z.Summary.Lines[-1] -like '*設定を変えたので違う') ($z.Summary.Lines -join ' / ')
}

Test-Case 'グラフのモデル: レーン・判定と tapping-term の線・保留の矢印・帯 (押している最中は離していないキーを開いたまま)' {
    $nest = New-HtEpisode 'p10@0 p15@50 r15@100 r10@140'
    $x = Invoke-HtEpisode $nest
    Assert-Equal -100 $x.Range.From
    $ch = Get-KcHoldTapChart $script:HtLism (New-KcHtConfig) $nest $x.Result $x.Sweeps $x.Range
    $titles = @($ch.Lanes | ForEach-Object { $_.Title })
    Assert-Equal '押したキー,A (Ctrl),H,PC に届く入力,A,Ctrl,H,A (Ctrl) を離す時刻ごとの結果,今の設定' (($titles | Select-Object -First 9) -join ',') 'PC に届く入力は組み合わせから前もって並べる'
    Assert-Equal 0 @($ch.Bars | Where-Object { $_.Lane -eq 4 }).Count 'A は届いていない (レーンだけ)'
    Assert-Equal 650 $x.Range.To '右端は tapping-term + 500 ms'
    Assert-Equal 650 $x.Sweeps.To '帯も右端まで'
    Assert-Equal '&mt' $ch.Lanes[1].Note
    $styles = @($ch.Bars | Where-Object { $_.Lane -eq 1 } | ForEach-Object { $_.Style })
    Assert-Equal "$($script:KcHtBarUndecided),$($script:KcHtBarHold)" ($styles -join ',') '判定待ち → ホールド'
    Assert-Equal 150 @($ch.Marks | Where-Object { $_.Style -eq $script:KcHtMarkTerm })[0].At
    Assert-Equal 100 @($ch.Marks | Where-Object { $_.Style -eq $script:KcHtMarkDecision })[0].At
    Assert-Equal 0 @($ch.Marks | Where-Object { $_.Style -eq $script:KcHtMarkFirmware }).Count
    Assert-Equal 140 @($ch.Marks | Where-Object { $_.Style -eq $script:KcHtMarkCursor })[0].At '実際に離した時刻'
    # 線の文と順 (ウィンドウはこの順に番号を振り、文をグラフの下に並べる)
    Assert-Equal 'tapping-term (150 ms)|判定: ホールド (ほかのキー) (100 ms)|離した時刻 (140 ms)' (($ch.Marks | ForEach-Object { $_.Text }) -join '|')
    Assert-Equal 1 $ch.Arrows.Count 'H の押下は判定まで保留'
    $actions = @($ch.Lanes | Where-Object { $_.Action } | ForEach-Object { $_.Action })
    Assert-Equal 'flavor:hold-preferred,flavor:balanced,flavor:tap-preferred,flavor:tap-unless-interrupted' ($actions -join ',')
    # ファームの判定が違えば線を出す
    $fw = New-HtEpisode 'p10@0 p15@50 r15@100 r10@140' $false @(@{ Pos = 10; Status = 'tap'; Moment = 'key-up'; Flavor = 'balanced'; T = 140 })
    $ch2 = Get-KcHoldTapChart $script:HtLism (New-KcHtConfig) $fw $x.Result $x.Sweeps $x.Range
    Assert-Equal 140 @($ch2.Marks | Where-Object { $_.Style -eq $script:KcHtMarkFirmware })[0].At
    Assert-Equal 'ファームの判定: タップ (140 ms)' $ch2.Marks[2].Text '3 番目はファームの判定'
    # 押している最中: 横軸は終わった回と同じ。離していないキーは開いたまま、帯のカーソルは無い
    $live = New-HtEpisode 'p10@0 p15@50' $true
    $y = Invoke-HtEpisode $live $null 70
    Assert-Equal 650 $y.Range.To '押している最中も、右端は tapping-term + 500 ms'
    Assert-Equal 650 $y.Sweeps.To
    $ch3 = Get-KcHoldTapChart $script:HtLism (New-KcHtConfig) $live $y.Result $y.Sweeps $y.Range
    $a = @($ch3.Bars | Where-Object { $_.Lane -eq 1 })
    Assert-Equal $script:KcHtOpenEnd $a[-1].To
    Assert-Equal 0 @($ch3.Marks | Where-Object { $_.Style -eq $script:KcHtMarkCursor }).Count
    # 一緒に押すキーを押さなかった回でも、そのレーンと届きうる入力のレーンを出す
    $tap = New-HtEpisode 'p10@0 r10@80'
    $z = Invoke-HtEpisode $tap
    $ch4 = Get-KcHoldTapChart $script:HtLism (New-KcHtConfig) $tap $z.Result $z.Sweeps $z.Range
    Assert-Equal '押したキー,A (Ctrl),H,PC に届く入力,A,Ctrl,H' ((@($ch4.Lanes | ForEach-Object { $_.Title }) | Select-Object -First 7) -join ',')
}

Test-Case '横軸と、組み合わせで届きうる入力: 右端は tapping-term + 500 ms、左端は先に押したキーから (-500 ms まで)' {
    Assert-Equal 650 (Get-KcHtLimitMs 150)
    Assert-Equal '-100,650' ('{0},{1}' -f (Get-KcHtRange (New-HtEpisode 'p10@0 r10@80') 150).From, (Get-KcHtRange (New-HtEpisode 'p10@0 r10@80') 150).To)
    Assert-Equal 750 (Get-KcHtRange (New-HtEpisode 'p10@0 r10@80') 250).To
    Assert-Equal 700 (Get-KcHtRange (New-HtEpisode 'p10@0 r10@80') 155).To '50 ms 単位に切り上げ'
    Assert-Equal -100 (Get-KcHtRange (New-HtEpisode 'p15@-40 p10@0 r15@40 r10@100') 150).From
    Assert-Equal -500 (Get-KcHtRange (New-HtEpisode 'p15@-900 p10@0 r15@40 r10@100') 150).From
    $f = { param($t, $p) ((Get-KcHtComboOutputs $script:HtLism (New-KcHtConfig) $t $p) | ForEach-Object { '{0}[{1}]' -f $_.Title, $_.Key }) -join ', ' }
    Assert-Equal 'A[key:4], Ctrl[key:224], H[key:11]' (& $f 10 15)
    Assert-Equal 'Enter[key:40], SYM[layer:1], Esc[key:41], Z[key:29], Shift[key:225]' (& $f 37 20) '一緒に押すキーが hold-tap なら、そのホールドも'
}

Test-Case '時計: いちばん遅れの少ない行に合わせて「今」を推定し、ファームの時刻が戻ったら作り直す' {
    $c = New-KcHtClock
    Assert-Equal $null (Get-KcHtClockNow $c 0)
    # 本当のずれは 990 ms。行は 0〜60 ms 遅れて届く
    Update-KcHtClock $c 1000 70
    Update-KcHtClock $c 1005 75
    Update-KcHtClock $c 1020 30
    Update-KcHtClock $c 1030 100
    Assert-Equal 990 $c.Offset
    Assert-Equal 1090 (Get-KcHtClockNow $c 100)
    # 5 秒より前の行は使わない
    Update-KcHtClock $c 6990 6070
    Assert-Equal 920 $c.Offset
    # 再起動 (ファームの時刻が戻った)
    Update-KcHtClock $c 5 6100
    Assert-Equal -6095 $c.Offset
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
    $cap = New-KcHtCapture $script:HtLism @{ Target = 10; Partner = 15 } 650
    $eps = @()
    foreach ($l in $lines) {
        $r = Update-KcHtCapture $cap (ConvertFrom-KcZmkLogLine $l)
        if ($null -ne $r) {
            Assert-Equal 'done' $r.Kind
            $eps += $r.Episode
        }
    }
    Assert-Equal 1 $eps.Count
    $ep = $eps[0]
    Assert-Equal 10 $ep.Target
    Assert-Equal 15 $ep.Partner
    Assert-Equal $false $ep.Cut '650 ms より後の行で終えたが、全部離していたので打ち切りではない'
    Assert-Equal 'p10@0 p15@60 r15@100 r10@150' (($ep.Events | ForEach-Object { '{0}{1}@{2}' -f @('r', 'p')[[int]$_.Down], $_.Pos, $_.T }) -join ' ')
    Assert-Equal 0 $ep.TargetIndex
    Assert-Equal 'hold-interrupt' $ep.Decisions[0].Status
    Assert-Equal 100 $ep.Decisions[0].T
    Assert-Equal 4 @($ep.Hid).Count
    Assert-True $ep.Uncertain '左手側のキーは押す / 離すを数えた'
    $x = Invoke-HtEpisode $ep
    Assert-Equal 'hold-interrupt' $x.Status 'ファームの判定と同じ'
    Assert-Equal 0 @($x.Summary.Lines | Where-Object { $_ -like 'ファーム*' }).Count
}

Test-Case 'ログ: 欠けたエピソードは比べない。左手側の押す / 離すのずれは hold-tap の行で直す' {
    $cap = New-KcHtCapture $script:HtLism @{ Target = 10; Partner = 15 } 650
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
    Assert-True ($null -ne $ep) '選んだキーをすべて離した'
    Assert-True $ep.Dropped
    Assert-Equal 'p10@0 r10@80' (($ep.Events | Where-Object { $_.T -ge 0 } | ForEach-Object { '{0}{1}@{2}' -f @('r', 'p')[[int]$_.Down], $_.Pos, $_.T }) -join ' ')
    Assert-True ((Invoke-HtEpisode $ep).Summary.Lines[-1] -like 'ログが欠けた*')
}

Test-Case 'ログ: 押している最中の回 (スナップショット) は、切り出しの状態を変えない' {
    $cap = New-KcHtCapture $script:HtLism @{ Target = 10; Partner = 15 } 650
    $lines = @(
        (New-HtLog 5000.2 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
        (New-HtLog 5000.4 'on_hold_tap_binding_pressed' '10 new undecided hold_tap'),
        (New-HtLog 5060.3 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: true'),
        (New-HtLog 5060.4 'position_state_changed_listener' '10 capturing 15 down event')
    )
    Assert-Equal $null (Get-KcHtCaptureSnapshot $cap)
    foreach ($l in $lines) { [void](Update-KcHtCapture $cap (ConvertFrom-KcZmkLogLine $l)) }
    $snap = Get-KcHtCaptureSnapshot $cap
    Assert-True $snap.Live
    Assert-Equal 5000 $snap.T0
    Assert-Equal 'p10@0 p15@60' (($snap.Events | ForEach-Object { '{0}{1}@{2}' -f @('r', 'p')[[int]$_.Down], $_.Pos, $_.T }) -join ' ')
    Assert-Equal 'target,partner' (($snap.Events | ForEach-Object { $_.Role }) -join ',')
    Assert-Equal 2 $cap.Ep.Events.Count 'スナップショットで変わらない'
    Assert-Equal $null (Complete-KcHtCapture $cap) 'まだ押している'
    Assert-True ($null -ne $cap.Ep)
}

# A (10、左手側) と H (15、右手側)、選んでいない J (16、右手側) と S (11、左手側) の行
function Get-HtComboLines([string]$What, [double]$Ms) {
    switch ($What) {
        'A' { return @((New-HtLog $Ms 'peripheral_event_work_callback' 'Trigger key position state change for 10')) }
        'A-new' {
            return @((New-HtLog $Ms 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
                (New-HtLog ($Ms + 0.2) 'on_hold_tap_binding_pressed' '10 new undecided hold_tap'))
        }
        'H-down' { return @((New-HtLog $Ms 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: true')) }
        'H-up' { return @((New-HtLog $Ms 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: false')) }
        'J-down' { return @((New-HtLog $Ms 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 6, position: 16, pressed: true')) }
        'J-up' { return @((New-HtLog $Ms 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 6, position: 16, pressed: false')) }
        'S' { return @((New-HtLog $Ms 'peripheral_event_work_callback' 'Trigger key position state change for 11')) }
        'decided-tap' { return @((New-HtLog $Ms 'decide_hold_tap' '10 decided tap (balanced decision moment key-up)')) }
        'decided-timer' { return @((New-HtLog $Ms 'decide_hold_tap' '10 decided hold-timer (balanced decision moment timer)')) }
    }
}

# 'A-new@1000 H-down@1040' の行を順に流し、戻り値 (done / discarded) を集める
function Invoke-HtCombo($Cap, [string]$Steps) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($s in ($Steps -split '\s+')) {
        $what, $ms = $s.Split('@')
        foreach ($l in (Get-HtComboLines $what ([double]$ms))) {
            $r = Update-KcHtCapture $Cap (ConvertFrom-KcZmkLogLine $l)
            if ($null -ne $r) { $out.Add($r) }
        }
    }
    return , $out.ToArray()
}

function Format-HtEvents($Episode) {
    return (($Episode.Events | ForEach-Object { '{0}{1}@{2}' -f @('r', 'p')[[int]$_.Down], $_.Pos, $_.T }) -join ' ')
}

Test-Case 'ログ: 選んだ組み合わせ (A + H) だけを入れる。選んでいないキーを途中で押した回は捨て、全部離したあとなら終える' {
    $cap = New-KcHtCapture $script:HtLism @{ Target = 10; Partner = 15 } 650
    # 選んでいないキーの押す / 離すと判定は入らない (A を押す前に押していた S を、途中で離す)
    $r = Invoke-HtCombo $cap 'S@900 A-new@1000 H-down@1040 S@1050 H-up@1090 A@1120 decided-tap@1120.1'
    Assert-Equal 0 $r.Count
    Assert-Equal 'p10@0 p15@40 r15@90 r10@120' (Format-HtEvents (Get-KcHtCaptureSnapshot $cap))
    # 全部離したあとに選んでいないキーを押すと、その回を終える
    $r = Invoke-HtCombo $cap 'J-down@1130'
    Assert-Equal 1 $r.Count
    Assert-Equal 'done' $r[0].Kind
    Assert-Equal 'p10@0 p15@40 r15@90 r10@120' (Format-HtEvents $r[0].Episode)
    Assert-Equal 1 @($r[0].Episode.Decisions).Count
    # A を押している途中で J を押すと、その回を捨てる
    $r = Invoke-HtCombo $cap 'J-up@1140 A-new@2000 J-down@2030'
    Assert-Equal 1 $r.Count
    Assert-Equal 'discarded' $r[0].Kind
    Assert-Equal 16 $r[0].Pos
    Assert-Equal 2 $r[0].Seq
    Assert-Equal $null $cap.Ep
    # 捨てた回の残り (A と J を離す) からは回を作らない。次に A を押すと新しい回
    $r = Invoke-HtCombo $cap 'A@2100 J-up@2110 A-new@3000'
    Assert-Equal 0 $r.Count
    Assert-Equal 3 $cap.Ep.Seq
    # H だけを押しても回は始まらない。組み合わせが無いあいだも始まらない
    $cap2 = New-KcHtCapture $script:HtLism @{ Target = 10; Partner = 15 } 650
    [void](Invoke-HtCombo $cap2 'H-down@100 H-up@150')
    Assert-Equal $null $cap2.Ep
    $cap3 = New-KcHtCapture $script:HtLism
    [void](Invoke-HtCombo $cap3 'A@100')
    Assert-Equal 10 $cap3.Pressed '押したキーは、その行の Pressed で分かる (組み合わせを選ぶのに使う)'
    [void](Invoke-HtCombo $cap3 'A@150')
    Assert-Equal -1 $cap3.Pressed '離した'
    # 左手側の数え違い (離したことになった) は、hold-tap の行で押したことに直し、そこで Pressed にする
    $cap3.Held[10] = $true
    [void](Invoke-HtCombo $cap3 'A-new@300')
    Assert-Equal 10 $cap3.Pressed
    Assert-Equal $null $cap3.Ep
}

Test-Case 'ログ: 先に押していた H を、回の前の入力として入れる' {
    $cap = New-KcHtCapture $script:HtLism @{ Target = 10; Partner = 15 } 650
    [void](Invoke-HtCombo $cap 'H-down@960 A-new@1000 H-up@1040 A@1100')
    $snap = Get-KcHtCaptureSnapshot $cap
    Assert-Equal 'p15@-40 p10@0 r15@40 r10@100' (Format-HtEvents $snap)
    Assert-Equal 1 $snap.TargetIndex
    Assert-Equal 'prior,target,partner,target' (($snap.Events | ForEach-Object { $_.Role }) -join ',')
}

Test-Case 'ログ: 押してから tapping-term + 500 ms を過ぎた行が来たら、その前で打ち切る' {
    $cap = New-KcHtCapture $script:HtLism @{ Target = 10; Partner = 15 } 650
    $r = Invoke-HtCombo $cap 'A-new@1000 decided-timer@1150 H-down@1600 H-up@1700'
    Assert-Equal 1 $r.Count
    Assert-Equal 'done' $r[0].Kind
    $ep = $r[0].Episode
    Assert-True $ep.Cut 'A を押したまま'
    Assert-Equal 650 $ep.Limit
    Assert-Equal 'p10@0 p15@600' (Format-HtEvents $ep) '1700 ms の H を離すは入らない'
    $x = Invoke-HtEpisode $ep
    Assert-Equal 'hold-timer' $x.Status
    Assert-Equal '650 ms (tapping-term + 500 ms) で打ち切った。A (Ctrl) はまだ押していた' $x.Summary.Lines[-1]
    Assert-Equal $null $x.Sweeps.Release '離していないので、離した時刻の線は無い'
    Assert-Equal $null $cap.Ep '打ち切ったあとは、次に A を押すまで回を作らない'
    # 行が来なくても、押したままなら -Cut で終えられる (ウィンドウがファームの時計で呼ぶ)
    [void](Invoke-HtCombo $cap 'A@1800 A-new@2000')
    $c = Complete-KcHtCapture $cap -Cut
    Assert-True $c.Cut
    Assert-Equal $null (Complete-KcHtCapture $cap)
}
