# タップホールドのタイミングのウィンドウの流れ (lib/keyboard-check/hold-tap-ui.ps1) のテスト。ウィンドウは偽物を使い、
# ログ版ファームのログの行を、届いた PC の時刻つきで流す (Windows 以外でも、組み合わせの選び方・押している最中の表示・
# 回の切り替え・打ち切り・設定を確かめる)。

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'hold-tap-sim.ps1')
. (Join-Path $script:KcLib 'hold-tap.ps1')
. (Join-Path $script:KcLib 'zmk-log.ps1')
. (Join-Path $script:KcLib 'hold-tap-ui.ps1')

$script:HtuFormMethods = @('SetTexts', 'SetLabels', 'SetPort', 'SetStatus', 'SetLegend', 'SetSettings', 'SetCombo', 'SetSummary',
    'SetChartMessage', 'SetChartRange', 'SetLanes', 'SetBars', 'SetMarks', 'SetArrows', 'RenderChart', 'SetLive')

# KcHoldTapForm の偽物: 呼ばれたメソッドと引数を Calls に記録する
function New-HtuForm {
    $form = [pscustomobject]@{ Calls = (New-Object System.Collections.ArrayList) }
    foreach ($m in $script:HtuFormMethods) {
        $form | Add-Member -MemberType ScriptMethod -Name $m -Value ([scriptblock]::Create("[void]`$this.Calls.Add((@('$m') + `$args))"))
    }
    return $form
}

function Get-HtuCalls($Form, [string]$Name) {
    foreach ($c in $Form.Calls) {
        if ($c[0] -eq $Name) {
            , $c
        }
    }
}

function Get-HtuLast($Form, [string]$Name) {
    $calls = @(Get-HtuCalls $Form $Name)
    if ($calls.Count -eq 0) {
        throw "$Name が呼ばれていません"
    }
    return , $calls[$calls.Count - 1]
}

# -NoPick: 組み合わせを選ぶ前のまま。既定では A (Ctrl) + H を選んでおく (PC の時刻 100〜250 ms)
function New-HtuContext([switch]$NoPick) {
    $model = New-KcHtModel (Get-KcExpected 'lism' $script:ExpectedDir)
    $ctx = New-KcHoldTapContext -Form (New-HtuForm) -Model $model
    Initialize-KcHoldTapUi $ctx
    if (-not $NoPick) {
        Step-Htu $ctx 100 'A-down'
        Step-Htu $ctx 150 'A-up'
        Step-Htu $ctx 200 'H-tap-down'
        Step-Htu $ctx 250 'H-tap-up'
    }
    return $ctx
}

# ログ版ファームの行 (zmk-log.Tests.ps1 と同じ書式)
function New-HtuLog([double]$Ms, [string]$Func, [string]$Msg) {
    $ts = [TimeSpan]::FromMilliseconds([math]::Floor($Ms))
    $us = [int](($Ms - [math]::Floor($Ms)) * 1000)
    return ('[{0:00}:{1:00}:{2:00}.{3:000},{4:000}] <dbg> zmk: {5}: {6}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds, $us, $Func, $Msg)
}

# A (位置 10、左手側) の押す / 離す、H (位置 15、右手側) の押す / 離す、判定、HID の行。ファームの時刻 = PC の時刻 + 4000
function Get-HtuLines([string]$What, [double]$Fw) {
    switch ($What) {
        'A-down' {
            return @((New-HtuLog ($Fw + 0.2) 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
                (New-HtuLog ($Fw + 0.4) 'on_hold_tap_binding_pressed' '10 new undecided hold_tap'))
        }
        'H-down' {
            return @((New-HtuLog ($Fw + 0.3) 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: true'),
                (New-HtuLog ($Fw + 0.4) 'position_state_changed_listener' '10 capturing 15 down event'))
        }
        'H-up-hold' {
            return @((New-HtuLog ($Fw + 0.1) 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: false'),
                (New-HtuLog ($Fw + 0.2) 'position_state_changed_listener' '10 capturing 15 up event'),
                (New-HtuLog ($Fw + 0.3) 'decide_hold_tap' '10 decided hold-interrupt (balanced decision moment other-key-up)'),
                (New-HtuLog ($Fw + 0.4) 'hid_listener_keycode_pressed' 'usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00'),
                (New-HtuLog ($Fw + 0.5) 'hid_listener_keycode_pressed' 'usage_page 0x07 keycode 0x0B implicit_mods 0x00 explicit_mods 0x00'),
                (New-HtuLog ($Fw + 0.6) 'hid_listener_keycode_released' 'usage_page 0x07 keycode 0x0B implicit_mods 0x00 explicit_mods 0x00'))
        }
        'A-up' {
            return @((New-HtuLog ($Fw + 0.0) 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
                (New-HtuLog ($Fw + 0.1) 'hid_listener_keycode_released' 'usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00'),
                (New-HtuLog ($Fw + 0.2) 'on_hold_tap_binding_released' '10 cleaning up hold-tap'))
        }
        # A を押していないときの H、選んでいないキー J (位置 16、右手側)
        'H-tap-down' { return @((New-HtuLog ($Fw + 0.3) 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: true')) }
        'H-tap-up' { return @((New-HtuLog ($Fw + 0.3) 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: false')) }
        'J-down' { return @((New-HtuLog ($Fw + 0.3) 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 6, position: 16, pressed: true')) }
        'J-up' { return @((New-HtuLog ($Fw + 0.3) 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 6, position: 16, pressed: false')) }
    }
}

# PC の時刻 $Pc に $What の行が届き、ループが 1 回まわる
function Step-Htu($Ctx, [double]$Pc, [string]$What = '', [double]$Fw = -1) {
    $Ctx.Form.Calls.Clear()
    if ($What) {
        if ($Fw -lt 0) { $Fw = $Pc + 4000 }
        Add-KcHoldTapLogLines $Ctx (Get-HtuLines $What $Fw) $Pc
    }
    Update-KcHoldTapLive $Ctx $Pc
}

function Invoke-Htu($Ctx, [string[]]$Actions, [double]$Pc = 0) {
    $Ctx.Form.Calls.Clear()
    $r = ''
    foreach ($a in (Get-KcHoldTapCoalescedActions $Actions)) {
        $r = Invoke-KcHoldTapAction $Ctx $a $Pc
        if ($r -eq 'close') { break }
    }
    return $r
}

Test-Case '組み合わせを選ぶ: hold-tap のキー → 一緒に押すキーの順に押す。hold-tap でないキーは ① で受け付けない' {
    $ctx = New-HtuContext -NoPick
    $f = $ctx.Form
    $s = Get-HtuLast $f 'SetSettings'
    Assert-Equal '&mt の設定' $s[1]
    Assert-Equal 'hold-preferred,balanced,tap-preferred,tap-unless-interrupted' ($s[2] -join ',')
    Assert-Equal 'balanced' $s[4]
    Assert-Equal 150 $s[5]
    Assert-Equal 'キーマップの値: balanced / 150 ms' $s[8]
    Assert-Equal $false $s[9]
    Assert-True ((Get-HtuLast $f 'SetChartMessage')[1] -like '① hold-tap のキー*') '① の案内'
    Assert-Equal 'キーの組み合わせ|? + ?|hold-tap のキーを押してください|' ((Get-HtuLast $f 'SetCombo')[1..4] -join '|') 'はじめは「やめる」が無い'
    Assert-Equal '' (Get-HtuLast $f 'SetSummary')[1] '結果の欄は出さない'
    Step-Htu $ctx 50
    Assert-Equal 0 $f.Calls.Count 'ログが無ければ何もしない'
    # H は hold-tap ではない
    Step-Htu $ctx 100 'H-tap-down'
    Assert-Equal 'H は hold-tap のキーではありません。hold-tap のキー (A や Space など) を押してください' (Get-HtuLast $f 'SetStatus')[1]
    Assert-Equal 3 (Get-HtuLast $f 'SetStatus')[2]
    Step-Htu $ctx 150 'H-tap-up'
    # A → ② の案内
    Step-Htu $ctx 300 'A-down'
    Assert-Equal '② A (Ctrl) と一緒に押すキーを押してください' (Get-HtuLast $f 'SetChartMessage')[1]
    Assert-Equal 'A (Ctrl) + ?' (Get-HtuLast $f 'SetCombo')[2]
    Assert-Equal 0 (Get-HtuLast $f 'SetStatus')[2] '警告を消す'
    # A を押したまま H を押すと決まる (A を離すのは、そのあとでもよい)
    Step-Htu $ctx 350 'H-tap-down'
    Assert-Equal 'キーの組み合わせ|A (Ctrl) + H||押して選び直す' ((Get-HtuLast $f 'SetCombo')[1..4] -join '|')
    Assert-Equal '&mt の設定' (Get-HtuLast $f 'SetSettings')[1]
    Assert-Equal 'A (Ctrl) を押すと、ここに判定が出ます' (Get-HtuLast $f 'SetSummary')[1]
    Assert-True ((Get-HtuLast $f 'SetChartMessage')[1] -like 'A (Ctrl) + H を押すと、ここにグラフが出ます*')
    Assert-Equal 10 $ctx.Combo.Target
    Assert-Equal 15 $ctx.Combo.Partner
    Assert-Equal 650 $ctx.Capture.LimitMs
    Step-Htu $ctx 400 'H-tap-up'
    Step-Htu $ctx 450 'A-up'
    Assert-Equal $null $ctx.Capture.Ep '選んでいるあいだに押したキーからは回を作らない'
    # &lt のキーを選ぶと、&lt の設定を出す
    [void](Invoke-Htu $ctx @('pick') 500)
    $f.Calls.Clear()
    Add-KcHoldTapLogLines $ctx @((New-HtuLog 4600.2 'zmk_physical_layouts_kscan_process_msgq' 'Row: 3, col: 7, position: 37, pressed: true'),
        (New-HtuLog 4600.4 'on_hold_tap_binding_pressed' '37 new undecided hold_tap')) 600
    Add-KcHoldTapLogLines $ctx @((New-HtuLog 4650.3 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: true')) 650
    Assert-Equal 'Enter (SYM) + H' (Get-HtuLast $f 'SetCombo')[2]
    Assert-Equal '&lt の設定' (Get-HtuLast $f 'SetSettings')[1]
}

Test-Case '押している最中: A を押した瞬間から「今」を進め、区間をまたいだら結果の文だけを変える' {
    $ctx = New-HtuContext
    $f = $ctx.Form
    Step-Htu $ctx 1000 'A-down'
    $live = Get-HtuLast $f 'SetLive'
    Assert-Equal $true $live[1]
    Assert-Near 0.4 $live[2] 0.01 '押した瞬間 (ファームの時刻 5000.4 = 今)'
    Assert-Equal '判定待ち' (Get-HtuLast $f 'SetSummary')[1]
    Assert-True ((Get-HtuLast $f 'SetSummary')[2][0] -like '今離すと: タップ → A。150 ms を過ぎると ホールド (時間切れ) → Ctrl') ((Get-HtuLast $f 'SetSummary')[2] -join ' / ')
    Assert-Equal 'A (Ctrl)' (Get-HtuLast $f 'SetLanes')[1][1]
    Assert-True $ctx.Episode.Live
    # 87 ms: 同じ区間なので、何も送らない
    Step-Htu $ctx 1087
    Assert-Equal 0 $f.Calls.Count
    # 160 ms: tapping-term を過ぎて、ホールドに決まった
    Step-Htu $ctx 1160
    Assert-Equal 'ホールド (時間切れ) に決定 (150 ms)' (Get-HtuLast $f 'SetSummary')[1]
    Assert-Equal 0 @(Get-HtuCalls $f 'SetLanes').Count '結果の文だけ'
    # 250 ms ごとに「今」を合わせ直す
    Step-Htu $ctx 1260
    Assert-Near 260.4 (Get-HtuLast $f 'SetLive')[2] 0.01
}

Test-Case '押している最中の変化: 50 ms 以内はまとめ、全部離して 300 ms たつとその回を残す。次に押すと切り替わる' {
    $ctx = New-HtuContext
    $f = $ctx.Form
    Step-Htu $ctx 1000 'A-down'
    Step-Htu $ctx 1030 'H-down'
    Assert-Equal 0 @(Get-HtuCalls $f 'SetLanes').Count '前の計算から 30 ms'
    Step-Htu $ctx 1055
    Assert-True (@((Get-HtuLast $f 'SetLanes')[1]) -contains 'H') 'H を押した'
    Step-Htu $ctx 1100 'H-up-hold'
    Assert-Equal 0 @(Get-HtuCalls $f 'SetLanes').Count '前の計算から 45 ms'
    Step-Htu $ctx 1115
    Assert-Equal 'ホールド (ほかのキー) に決定 (100 ms)' (Get-HtuLast $f 'SetSummary')[1]
    Step-Htu $ctx 1150 'A-up'
    Assert-True $ctx.Episode.Live '離したばかりは、まだ押している最中の回'
    Step-Htu $ctx 1400
    Assert-True $ctx.Episode.Live 'ファームの時計で 300 ms たつまで待つ'
    Step-Htu $ctx 1600
    Assert-Equal $false $ctx.Episode.Live
    Assert-Equal $false (Get-HtuLast $f 'SetLive')[1]
    Assert-Equal 'ホールド (ほかのキー): PC に届くのは Ctrl+H' (Get-HtuLast $f 'SetSummary')[1]
    Assert-Equal 'p10@0 p15@30 r15@100 r10@150' (($ctx.Episode.Events | ForEach-Object { '{0}{1}@{2}' -f @('r', 'p')[[int]$_.Down], $_.Pos, $_.T }) -join ' ')
    $cursor = @((Get-HtuLast $f 'SetMarks')[4] | Where-Object { $_ -eq $script:KcHtMarkCursor })
    Assert-Equal 1 $cursor.Count '実際に離した時刻'
    # 次に押すと、新しい回に切り替わる
    Step-Htu $ctx 3000 'A-down'
    Assert-True $ctx.Episode.Live
    Assert-Equal 2 $ctx.Episode.Seq
    Assert-Equal '判定待ち' (Get-HtuLast $f 'SetSummary')[1]
}

Test-Case '設定: flavor と tapping-term で計算し直し、ファームの判定と違えば線と文で示す。戻すとキーマップの値' {
    $ctx = New-HtuContext
    $f = $ctx.Form
    Step-Htu $ctx 1000 'A-down'
    Step-Htu $ctx 1030 'H-down'
    Step-Htu $ctx 1100 'H-up-hold'
    Step-Htu $ctx 1140 'A-up'
    Step-Htu $ctx 1600
    Assert-Equal 'hold-interrupt' $ctx.Episode.Decisions[0].Status
    Assert-Equal '' (Invoke-Htu $ctx @('flavor:tap-preferred') 1700)
    $s = Get-HtuLast $f 'SetSettings'
    Assert-Equal 'tap-preferred' $s[4]
    Assert-Equal $true $s[9]
    Assert-True ((Get-HtuLast $f 'SetSummary')[1] -like 'タップ:*') (Get-HtuLast $f 'SetSummary')[1]
    Assert-True (@((Get-HtuLast $f 'SetSummary')[2]) -like '*設定を変えたので違う').Count -eq 1
    Assert-True (@((Get-HtuLast $f 'SetMarks')[4]) -contains $script:KcHtMarkFirmware) 'ファームの判定の線'
    [void](Invoke-Htu $ctx @('term:abc', 'term:1000') 1800)
    Assert-Equal 500 (Get-KcHtSetting $ctx.Model $ctx.Config 'mt').Term '50〜500 に収める'
    [void](Invoke-Htu $ctx @('flavor:nothing') 1800)
    Assert-Equal 'tap-preferred' (Get-KcHtSetting $ctx.Model $ctx.Config 'mt').Flavor '知らない flavor は無視'
    [void](Invoke-Htu $ctx @('reset') 1900)
    Assert-Equal $false (Get-HtuLast $f 'SetSettings')[9]
    Assert-Equal 0 @((Get-HtuLast $f 'SetMarks')[4] | Where-Object { $_ -eq $script:KcHtMarkFirmware }).Count
    Assert-Equal 'close' (Invoke-Htu $ctx @('close', 'reset'))
}

Test-Case '操作のまとめ: tapping-term は最後のものだけ' {
    Assert-Equal 'flavor:balanced,term:130' ((Get-KcHoldTapCoalescedActions @('term:120', 'flavor:balanced', 'term:130')) -join ',')
    Assert-Equal 0 (Get-KcHoldTapCoalescedActions @()).Count
}

Test-Case '選んでいないキー: 途中で押した回は出さず、前の回に戻す。全部離したあとなら、その回を残す' {
    $ctx = New-HtuContext
    $f = $ctx.Form
    # 前の回が無いとき: 待ちの案内に戻る
    Step-Htu $ctx 1000 'A-down'
    Assert-True $ctx.Episode.Live
    Step-Htu $ctx 1030 'J-down'
    Assert-Equal $null $ctx.Episode
    Assert-Equal 'J を押したので、この回は出しません (選んだ組み合わせ: A (Ctrl) + H)' (Get-HtuLast $f 'SetStatus')[1]
    Assert-Equal 3 (Get-HtuLast $f 'SetStatus')[2]
    Assert-Equal $false (Get-HtuLast $f 'SetLive')[1]
    Assert-True ((Get-HtuLast $f 'SetChartMessage')[1] -like 'A (Ctrl) + H を押すと*')
    Step-Htu $ctx 1080 'A-up'
    Step-Htu $ctx 1100 'J-up'
    Assert-Equal $null $ctx.Capture.Ep '捨てた回の残りからは回を作らない'
    # 1 回分を残す (次の回で警告を消す)
    Step-Htu $ctx 2000 'A-down'
    Assert-Equal 0 (Get-HtuLast $f 'SetStatus')[2] '新しい回で警告を消す'
    Step-Htu $ctx 2030 'H-down'
    Step-Htu $ctx 2100 'H-up-hold'
    Step-Htu $ctx 2140 'A-up'
    # 全部離したあとに J を押すと、その回をすぐに残す
    Step-Htu $ctx 2200 'J-down'
    Assert-Equal $false $ctx.Episode.Live
    Assert-Equal 2 $ctx.Episode.Seq
    Assert-Equal 'ホールド (ほかのキー): PC に届くのは Ctrl+H' (Get-HtuLast $f 'SetSummary')[1]
    Step-Htu $ctx 2250 'J-up'
    # 前の回があるとき: その回に戻る
    Step-Htu $ctx 3000 'A-down'
    Assert-Equal 3 $ctx.Episode.Seq
    Step-Htu $ctx 3060 'J-down'
    Assert-Equal 2 $ctx.Episode.Seq '前の回'
    Assert-Equal $false $ctx.Episode.Live
    Assert-Equal 'ホールド (ほかのキー): PC に届くのは Ctrl+H' (Get-HtuLast $f 'SetSummary')[1]
    Assert-Equal 3 (Get-HtuLast $f 'SetStatus')[2]
}

Test-Case '打ち切り: A を押したままでも、tapping-term + 500 ms でその回を残す。横軸の右端も同じ' {
    $ctx = New-HtuContext
    $f = $ctx.Form
    Step-Htu $ctx 1000 'A-down'
    Assert-Equal 650 (Get-HtuLast $f 'SetChartRange')[2] '押している最中も右端は 650 ms'
    Assert-Equal -100 (Get-HtuLast $f 'SetChartRange')[1]
    Step-Htu $ctx 1700
    Assert-True $ctx.Episode.Live 'ログは遅れて届くので、少し待つ'
    Step-Htu $ctx 1850
    Assert-Equal $false $ctx.Episode.Live
    Assert-True $ctx.Episode.Cut
    Assert-Equal $false (Get-HtuLast $f 'SetLive')[1]
    Assert-Equal 650 (Get-HtuLast $f 'SetChartRange')[2]
    Assert-Equal 'ホールド (時間切れ): PC に届くのは Ctrl' (Get-HtuLast $f 'SetSummary')[1]
    Assert-Equal '650 ms (tapping-term + 500 ms) で打ち切った。A (Ctrl) はまだ押していた' (Get-HtuLast $f 'SetSummary')[2][-1]
    # 離したあとに、次に A を押すと新しい回
    Step-Htu $ctx 2000 'A-up'
    Assert-Equal $null $ctx.Capture.Ep
    Step-Htu $ctx 2500 'A-down'
    Assert-True $ctx.Episode.Live
    Assert-Equal 2 $ctx.Episode.Seq
    # tapping-term を変えると、1 回分の長さと右端も変わる
    [void](Invoke-Htu $ctx @('term:250') 2550)
    Assert-Equal 750 $ctx.Capture.LimitMs
    Assert-Equal 750 (Get-HtuLast $f 'SetChartRange')[2]
}

Test-Case '選び直す: 「押して選び直す」で選び始め、途中の「やめる」で前の組み合わせと回に戻る' {
    $ctx = New-HtuContext
    $f = $ctx.Form
    Step-Htu $ctx 1000 'A-down'
    Step-Htu $ctx 1080 'A-up'
    Step-Htu $ctx 1500
    Assert-Equal 'タップ: PC に届くのは A' (Get-HtuLast $f 'SetSummary')[1]
    Assert-Equal '' (Invoke-Htu $ctx @('pick') 1600)
    Assert-Equal 'target' $ctx.Picking
    Assert-Equal '? + ?|hold-tap のキーを押してください|やめる' ((Get-HtuLast $f 'SetCombo')[2..4] -join '|')
    Assert-True ((Get-HtuLast $f 'SetChartMessage')[1] -like '① *')
    Assert-Equal $null $ctx.Capture.Combo '選んでいるあいだは回を作らない'
    # 選んでいるあいだに押しても回にならない
    Step-Htu $ctx 1700 'A-down'
    Assert-Equal 'partner' $ctx.Picking
    Assert-Equal $null $ctx.Capture.Ep
    # やめる: 前の組み合わせと、前の回に戻る
    [void](Invoke-Htu $ctx @('pick') 1750)
    Assert-Equal '' $ctx.Picking
    Assert-Equal 'A (Ctrl) + H|' ((Get-HtuLast $f 'SetCombo')[2..3] -join '|')
    Assert-Equal 'タップ: PC に届くのは A' (Get-HtuLast $f 'SetSummary')[1]
    Assert-Equal 15 $ctx.Capture.Combo.Partner
    Step-Htu $ctx 1800 'A-up'
    # 別の組み合わせにすると、前の回は消える
    [void](Invoke-Htu $ctx @('pick') 1900)
    Step-Htu $ctx 2000 'A-down'
    Step-Htu $ctx 2050 'J-down'
    Assert-Equal 'A (Ctrl) + J' (Get-HtuLast $f 'SetCombo')[2]
    Assert-Equal $null $ctx.Episode
    Assert-Equal 'A (Ctrl) を押すと、ここに判定が出ます' (Get-HtuLast $f 'SetSummary')[1]
}
