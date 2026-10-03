# タップホールドのタイミングのウィンドウの流れ (lib/keyboard-check/hold-tap-ui.ps1) のテスト。ウィンドウは偽物を使う
# (Windows 以外でも、初期表示・プリセット・ドラッグ・設定の変更・ログ版ファームのエピソード・保存を確かめる)。

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'hold-tap-sim.ps1')
. (Join-Path $script:KcLib 'hold-tap.ps1')
. (Join-Path $script:KcLib 'zmk-log.ps1')
. (Join-Path $script:KcLib 'hold-tap-ui.ps1')

$script:HtuFormMethods = @('SetTexts', 'SetCaptions', 'SetButtonTexts', 'SetButtons', 'SetPort', 'SetStatus', 'SetLegend',
    'SetKeyChoices', 'SetPresets', 'SetEpisodes', 'ClearParams', 'SetParamsNote', 'AddChoiceParam', 'AddSliderParam',
    'SetParamValue', 'SetSummary', 'SetChartMessage', 'SetChartRange', 'SetLanes', 'SetBars', 'SetSpans', 'SetMarks',
    'SetArrows', 'SetHandles', 'RenderChart')

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

# 名前が $Param の AddChoiceParam / AddSliderParam / SetParamValue のうち最後のもの
function Get-HtuParam($Form, [string]$Param) {
    $last = $null
    foreach ($c in $Form.Calls) {
        if (($c[0] -eq 'AddChoiceParam' -or $c[0] -eq 'AddSliderParam' -or $c[0] -eq 'SetParamValue') -and $c[1] -eq $Param) { $last = $c }
    }
    if ($null -eq $last) { throw "$Param の設定がありません" }
    # 値と「変更」の表示: Choice (6, 7) / Slider (5, 7) / SetParamValue (2, 3)
    switch ($last[0]) {
        'AddChoiceParam' { return @{ Value = [string]$last[6]; Changed = [string]$last[7] } }
        'AddSliderParam' { return @{ Value = [string]$last[5]; Changed = [string]$last[7] } }
        default { return @{ Value = [string]$last[2]; Changed = [string]$last[3] } }
    }
}

function New-HtuContext([string]$Name) {
    $model = New-KcHtModel (Get-KcExpected $Name $script:ExpectedDir)
    $ctx = New-KcHoldTapContext -Form (New-HtuForm) -Model $model -CacheDir ''
    Initialize-KcHoldTapUi $ctx
    return $ctx
}

function Invoke-Htu($Ctx, [string[]]$Actions) {
    $Ctx.Form.Calls.Clear()
    $r = ''
    foreach ($a in (Get-KcHoldTapCoalescedActions $Actions)) {
        $r = Invoke-KcHoldTapAction $Ctx $a
        if ($r -eq 'close') { break }
    }
    return $r
}

function Format-HtuEvents($Events) {
    return ((@($Events) | ForEach-Object { '{0}{1}@{2}' -f @('r', 'p')[[int]$_.Down], $_.Pos, $_.T }) -join ' ')
}

# ログ版ファームの行 (zmk-log.Tests.ps1 と同じ書式)
function New-HtuLog([double]$Ms, [string]$Func, [string]$Msg) {
    $ts = [TimeSpan]::FromMilliseconds([math]::Floor($Ms))
    $us = [int](($Ms - [math]::Floor($Ms)) * 1000)
    return ('[{0:00}:{1:00}:{2:00}.{3:000},{4:000}] <dbg> zmk: {5}: {6}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds, $us, $Func, $Msg)
}

# A (位置 10、左手側 = ペリフェラル) を押したまま H (位置 15) を押して離す 1 回分 ($T0 から)
function Get-HtuEpisodeLines([double]$T0) {
    return @(
        (New-HtuLog ($T0 + 0.2) 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
        (New-HtuLog ($T0 + 0.4) 'on_hold_tap_binding_pressed' '10 new undecided hold_tap'),
        (New-HtuLog ($T0 + 60.3) 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: true'),
        (New-HtuLog ($T0 + 60.4) 'position_state_changed_listener' '10 capturing 15 down event'),
        (New-HtuLog ($T0 + 100.1) 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: false'),
        (New-HtuLog ($T0 + 100.2) 'position_state_changed_listener' '10 capturing 15 up event'),
        (New-HtuLog ($T0 + 100.3) 'decide_hold_tap' '10 decided hold-interrupt (balanced decision moment other-key-up)'),
        (New-HtuLog ($T0 + 100.4) 'hid_listener_keycode_pressed' 'usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00'),
        (New-HtuLog ($T0 + 100.5) 'hid_listener_keycode_pressed' 'usage_page 0x07 keycode 0x0B implicit_mods 0x00 explicit_mods 0x00'),
        (New-HtuLog ($T0 + 100.6) 'hid_listener_keycode_released' 'usage_page 0x07 keycode 0x0B implicit_mods 0x00 explicit_mods 0x00'),
        (New-HtuLog ($T0 + 150.0) 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
        (New-HtuLog ($T0 + 150.1) 'hid_listener_keycode_released' 'usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00'),
        (New-HtuLog ($T0 + 150.2) 'on_hold_tap_binding_released' '10 cleaning up hold-tap')
    )
}

function Add-HtuEpisode($Ctx, [double]$T0) {
    foreach ($l in (Get-HtuEpisodeLines $T0)) {
        $ep = Update-KcHtCapture $Ctx.State.Capture (ConvertFrom-KcZmkLogLine $l)
        if ($null -ne $ep) { Add-KcHtEpisode $Ctx $ep }
    }
    $ep = Complete-KcHtCapture $Ctx.State.Capture
    Assert-True ($null -ne $ep) 'エピソードが終わる'
    Add-KcHtEpisode $Ctx $ep
}

Test-Case 'LisM: 最初は A (&mt) のロール。キーマップの値 (balanced 150) で、タップの結果と帯を出す' {
    $ctx = New-HtuContext 'lism'
    $f = $ctx.Form
    $keys = Get-HtuLast $f 'SetKeyChoices'
    Assert-Equal '10,19,20,29,34,37' $keys[1]
    Assert-Equal 'A (Ctrl) &mt' $keys[2][0]
    Assert-Equal '10' $keys[3]
    Assert-Equal 'roll' (Get-HtuLast $f 'SetPresets')[4]
    Assert-Equal 'balanced' (Get-HtuParam $f 'flavor').Value
    Assert-Equal '' (Get-HtuParam $f 'flavor').Changed
    Assert-Equal '150' (Get-HtuParam $f 'term').Value
    Assert-Equal 'p10@0 p15@50 r10@90 r15@130' (Format-HtuEvents $ctx.State.Events)
    $sum = Get-HtuLast $f 'SetSummary'
    Assert-True ($sum[1] -like 'タップ:*') $sum[1]
    Assert-Equal 1 $sum[3] 'タップの色'
    Assert-True (@($sum[2] | Where-Object { $_ -like '「A (Ctrl) を離す」の時刻を変えると:*' }).Count -eq 1) ($sum[2] -join ' / ')
    Assert-Equal $true (Get-HtuLast $f 'SetButtons')[2] 'ZMK はログ版のエピソードを消せる'
    Assert-Equal $true (Get-HtuLast $f 'SetEpisodes')[7] 'エピソードの欄を出す'
    # グラフ: レーンの数と、ハンドル (4 つの入力 + tapping-term)
    $lanes = Get-HtuLast $f 'SetLanes'
    Assert-Equal '押したキー' $lanes[1][0]
    Assert-True (@($lanes[4] | Where-Object { $_ -eq 'param:flavor:hold-preferred' }).Count -eq 1) 'flavor の比較の行は押すと切り替わる'
    $h = Get-HtuLast $f 'SetHandles'
    Assert-Equal "0,1,2,3,$($script:KcHtHandleTerm)" $h[1]
    Assert-Equal 2 $h[5] '対象のキーを離す時刻を選ぶ'
    Assert-Equal 1 @(Get-HtuCalls $f 'RenderChart').Count
}

Test-Case 'KQ-mini: Vial の設定 (PERMISSIVE_HOLD) で計算し、ログ版の欄は出さない' {
    $ctx = New-HtuContext 'kq-mini'
    $f = $ctx.Form
    Assert-Equal 'A (Ctrl)' (Get-HtuLast $f 'SetKeyChoices')[2][0]
    Assert-Equal '150' (Get-HtuParam $f 'term').Value
    Assert-Equal '1' (Get-HtuParam $f 'permissive').Value
    Assert-True ((Get-HtuLast $f 'SetParamsNote')[1] -like '*Vial*')
    Assert-Equal $false (Get-HtuLast $f 'SetButtons')[2]
    Assert-Equal $false (Get-HtuLast $f 'SetEpisodes')[7]
    Assert-True (@((Get-HtuLast $f 'SetLanes')[4] | Where-Object { $_ -eq 'param:mode:default' }).Count -eq 1)
    # 包むと、PERMISSIVE_HOLD でホールド
    [void](Invoke-Htu $ctx @('preset:nest'))
    Assert-True ((Get-HtuLast $f 'SetSummary')[1] -like 'ホールド*') (Get-HtuLast $f 'SetSummary')[1]
    [void](Invoke-Htu $ctx @('param:mode:default'))
    Assert-Equal '0' (Get-HtuParam $f 'permissive').Value
    Assert-Equal '変更 (Vial: オン)' (Get-HtuParam $f 'permissive').Changed
    Assert-True ((Get-HtuLast $f 'SetSummary')[1] -like 'タップ*') (Get-HtuLast $f 'SetSummary')[1]
}

Test-Case '操作のまとめ: ドラッグと設定のスライダーは最後のものだけ。drop の前の同じ drag は消す' {
    $got = Get-KcHoldTapCoalescedActions @('drag:2:100', 'drag:2:110', 'param:term:160', 'drag:3:50', 'param:term:170', 'drop:2:120', 'drag:2:130', 'preset:nest', 'drag:-1:5')
    Assert-Equal 'drag:3:50,param:term:170,drop:2:120,drag:2:130,preset:nest,drag:-1:5' ($got -join ',')
    Assert-Equal 0 (Get-KcHoldTapCoalescedActions @()).Count
}

Test-Case 'ドラッグ: 離す時刻を動かすと結果が変わる。ドラッグ中は帯を計算し直さず、離したら計算し直す' {
    $ctx = New-HtuContext 'lism'
    $f = $ctx.Form
    $sweeps = $ctx.State.Sweeps
    [void](Invoke-Htu $ctx @('drag:2:140'))
    Assert-Equal 'p10@0 p15@50 r10@140 r15@130' (Format-HtuEvents $ctx.State.Events)
    Assert-True ((Get-HtuLast $f 'SetSummary')[1] -like 'ホールド (ほかのキー)*') (Get-HtuLast $f 'SetSummary')[1]
    Assert-True ([object]::ReferenceEquals($sweeps, $ctx.State.Sweeps)) 'ドラッグ中は前の帯のまま'
    Assert-True ((Get-HtuLast $f 'SetStatus')[1] -like 'A (Ctrl) を離す: 140 ms*')
    [void](Invoke-Htu $ctx @('drop:2:150'))
    Assert-True (-not [object]::ReferenceEquals($sweeps, $ctx.State.Sweeps)) '離したら計算し直す'
    # 別の入力を掴んだら、ドラッグ中でも帯を作り直す (帯は掴んだ入力を動かしたもの)
    $sweeps = $ctx.State.Sweeps
    [void](Invoke-Htu $ctx @('drag:1:40'))
    Assert-Equal 1 $ctx.State.Selected
    Assert-True (-not [object]::ReferenceEquals($sweeps, $ctx.State.Sweeps))
    # 同じキーの前後を越えない
    [void](Invoke-Htu $ctx @('drop:2:-50'))
    Assert-Equal 1 $ctx.State.Events[2].T
}

Test-Case 'tapping-term の線: ドラッグで term が変わり、設定の欄に「変更」を出す。戻すとキーマップの値' {
    $ctx = New-HtuContext 'lism'
    $f = $ctx.Form
    [void](Invoke-Htu $ctx @("drag:$($script:KcHtHandleTerm):170", "drop:$($script:KcHtHandleTerm):180"))
    Assert-Equal 180 $ctx.State.Config.Zmk['mt'].Term
    Assert-Equal '180' (Get-HtuParam $f 'term').Value
    Assert-Equal '変更 (キーマップ: 150)' (Get-HtuParam $f 'term').Changed
    $marks = Get-HtuLast $f 'SetMarks'
    $i = [array]::IndexOf([int[]]$marks[4], $script:KcHtMarkTerm)
    Assert-Equal 180 $marks[3][$i]
    Assert-True ((Get-HtuLast $f 'SetStatus')[1] -like 'tapping-term: 180 ms*')
    # 範囲の外は 50〜500 に収める
    [void](Invoke-Htu $ctx @("drop:$($script:KcHtHandleTerm):10"))
    Assert-Equal 50 $ctx.State.Config.Zmk['mt'].Term
    [void](Invoke-Htu $ctx @('reset'))
    Assert-Equal 150 $ctx.State.Config.Zmk['mt'].Term
    Assert-Equal '' (Get-HtuParam $f 'term').Changed
}

Test-Case '設定: flavor を変えると結果が変わり、キーマップの値の結果を重ねる' {
    $ctx = New-HtuContext 'lism'
    $f = $ctx.Form
    [void](Invoke-Htu $ctx @('param:flavor:hold-preferred'))
    Assert-Equal 'hold-preferred' (Get-HtuParam $f 'flavor').Value
    Assert-Equal '変更 (キーマップ: balanced)' (Get-HtuParam $f 'flavor').Changed
    Assert-True ((Get-HtuLast $f 'SetSummary')[1] -like 'ホールド*')
    Assert-True ($null -ne $ctx.State.Base) 'キーマップの値でも計算する'
    $styles = (Get-HtuLast $f 'SetBars')[4]
    Assert-True (@($styles | Where-Object { $_ -eq $script:KcHtBarBaseline }).Count -gt 0) 'キーマップの値の出力を重ねる'
    $marks = Get-HtuLast $f 'SetMarks'
    Assert-True (@($marks[4] | Where-Object { $_ -eq $script:KcHtMarkBaseline }).Count -eq 1) 'キーマップの値の判定の線'
    # スライダーの値 (quick-tap 0 = なし)
    [void](Invoke-Htu $ctx @('param:quick:120', 'param:quick:0'))
    Assert-Equal -1 $ctx.State.Config.Zmk['mt'].QuickTap
    # 反対の手だけでホールド (hold-trigger-key-positions)。ロールの相手は反対の手なので変わらない
    [void](Invoke-Htu $ctx @('param:positional:opposite'))
    Assert-Equal 'opposite' (Get-HtuParam $f 'positional').Value
    Assert-True ((Get-HtuLast $f 'SetSummary')[1] -like 'ホールド*')
    [void](Invoke-Htu $ctx @('partner:same'))
    Assert-True ((Get-HtuLast $f 'SetSummary')[1] -like 'タップ*') '同じ手のキーならタップ'
    [void](Invoke-Htu $ctx @('reset'))
    Assert-True ($null -eq $ctx.State.Base)
    Assert-Equal 'off' (Get-HtuParam $f 'positional').Value
}

Test-Case '対象のキー: &lt に変えると、プリセットと設定の欄を作り直す。無いプリセットはロールにする' {
    $ctx = New-HtuContext 'lism'
    $f = $ctx.Form
    [void](Invoke-Htu $ctx @('preset:double'))
    [void](Invoke-Htu $ctx @('key:34'))
    Assert-Equal 34 $ctx.State.Target
    Assert-Equal 'double' $ctx.State.Preset
    Assert-Equal 34 $ctx.State.Events[$ctx.State.TargetIndex].Pos
    Assert-True ((Get-HtuLast $f 'SetParamsNote')[1] -like '&lt の設定*')
    Assert-Equal 'balanced' (Get-HtuParam $f 'flavor').Value
    [void](Invoke-Htu $ctx @('param:flavor:tap-preferred'))
    Assert-Equal 'tap-preferred' $ctx.State.Config.Zmk['lt'].Flavor
    Assert-Equal 'balanced' $ctx.State.Config.Zmk['mt'].Flavor '&mt は変えない'
    $ctx.State.Preset = 'nothing'
    [void](Invoke-Htu $ctx @('key:10'))
    Assert-Equal 'roll' $ctx.State.Preset
    [void](Invoke-Htu $ctx @('partner:same'))
    Assert-Equal 'left' $ctx.State.Model.Keys[$ctx.State.Events[1].Pos].Hand
}

Test-Case 'ログ版ファーム: 押したもの (エピソード) を最新に追って表示し、ファームの判定を重ねる' {
    $ctx = New-HtuContext 'lism'
    $f = $ctx.Form
    $f.Calls.Clear()
    Add-HtuEpisode $ctx 5000
    Assert-Equal 1 $ctx.State.Episodes.Count
    Assert-True ($null -ne $ctx.State.Episode) '最新を表示'
    Assert-Equal 'p10@0 p15@60 r15@100 r10@150' (Format-HtuEvents $ctx.State.Events)
    Assert-Equal 3 $ctx.State.Selected '対象のキーを離す時刻を選ぶ'
    $sum = Get-HtuLast $f 'SetSummary'
    Assert-True ($sum[2][0] -like 'ログ版ファームで実際に押したもの: ファームの判定 (ホールド (ほかのキー)) と*') $sum[2][0]
    $marks = Get-HtuLast $f 'SetMarks'
    Assert-True (@($marks[4] | Where-Object { $_ -eq $script:KcHtMarkFirmware }).Count -eq 1) 'ファームの判定の線'
    $eps = Get-HtuLast $f 'SetEpisodes'
    Assert-Equal '1' $eps[1]
    Assert-Equal 1 $eps[4][0] '一致'
    Assert-Equal '1' $eps[5]
    Assert-Equal '' (Get-HtuLast $f 'SetPresets')[4] 'プリセットは選ばない'
    # プリセットを選ぶと追わない
    [void](Invoke-Htu $ctx @('preset:nest'))
    Assert-True ($null -eq $ctx.State.Episode)
    Add-HtuEpisode $ctx 9000
    Assert-True ($null -eq $ctx.State.Episode) '追わないときは表示を変えない'
    Assert-Equal '2,1' (Get-HtuLast $f 'SetEpisodes')[1] '新しい順'
    [void](Invoke-Htu $ctx @('episode:1'))
    Assert-Equal 1 $ctx.State.Episode.Seq
    Assert-Equal $false $ctx.State.Follow '古いものを選んだら追わない'
    [void](Invoke-Htu $ctx @('follow:1'))
    Assert-Equal 2 $ctx.State.Episode.Seq
    # クリアするとプリセットに戻る
    [void](Invoke-Htu $ctx @('clear'))
    Assert-Equal 0 $ctx.State.Episodes.Count
    Assert-True ($null -eq $ctx.State.Episode)
    Assert-Equal 0 @((Get-HtuLast $f 'SetEpisodes')[1]).Count
}

Test-Case '保存: 設定・入力・結果とエピソードを .txt に、ログを .log に書く。close で終わる' {
    $ctx = New-HtuContext 'lism'
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('kc-holdtap-' + [guid]::NewGuid().ToString('N'))
    $ctx.CacheDir = $dir
    try {
        Add-HtuEpisode $ctx 5000
        [void]$ctx.State.Raw.AppendLine('[00:00:05.000,200] <dbg> zmk: test')
        Assert-Equal '' (Invoke-Htu $ctx @('save'))
        $path = $ctx.State.Saved
        Assert-True (Test-Path -LiteralPath $path)
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        Assert-True ($text -like 'タップホールドのタイミング: LisM*') $text
        Assert-True ($text -like '*設定: &mt: balanced / tapping-term 150*') $text
        Assert-True ($text -like '*実際に押したもの (ログ版ファーム):*') $text
        Assert-True (Test-Path -LiteralPath ([System.IO.Path]::ChangeExtension($path, '.log')))
        Assert-True ((Get-HtuLast $ctx.Form 'SetStatus')[1] -like '保存しました:*')
    } finally {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    }
    Assert-Equal 'close' (Invoke-Htu $ctx @('close', 'preset:nest'))
}
