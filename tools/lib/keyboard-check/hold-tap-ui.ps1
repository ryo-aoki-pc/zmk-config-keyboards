# タップホールドのタイミングを見るウィンドウ (keyboard-check.ps1 -Mode HoldTap) の流れ。
# はじめに、調べるキーの組み合わせ (hold-tap のキー → 一緒に押すキー) を実際に押して選ぶ。
# そのあとは ZMK のログ版ファームのログを読み、組み合わせを押した 1 回分を、押した瞬間からリアルタイムにグラフに出す
# (押している間は「今」までを描き、選んだキーを全部離すか、tapping-term + 100 ms たったらその回を残す。
# 次に hold-tap のキーを押したら切り替える。途中で選んでいないキーを押した回は出さない)。
# ウィンドウ (KcHoldTapForm) には $Ctx.Form 経由で触る (WPF の型に触れないので、tests/hold-tap-ui.Tests.ps1 が偽物で確かめる)。
# 時刻 ($PcMs) は呼び出し側の PC の時計 (ms)。Invoke-KcHoldTap だけが Windows 専用。
# expected.ps1 / hold-tap-sim.ps1 / hold-tap.ps1 / zmk-log.ps1 が先に読み込まれている前提 (Invoke-KcHoldTap は
# input-test.ps1 / zmk-studio.ps1 / layer-trace.ps1 も)。

$script:KcHtLiveMinMs = 50      # 押している最中に計算し直す間隔の最小
$script:KcHtLiveSyncMs = 250    # ウィンドウの「今」を合わせ直す間隔
$script:KcHtSettleMs = 300      # 選んだキーを全部離してから、ファームの時刻でこの間たったら 1 回分を終える
$script:KcHtCutLagMs = 150      # 打ち切る時刻を過ぎても行が来なければ、この分待ってから打ち切る (ログは遅れて届く)
$script:KcHtTermMin = 50
$script:KcHtTermMax = 500
$script:KcHtDefaultStatus = 'flavor と tapping-term は、このウィンドウの中で計算に使うだけで、キーボードには書き込みません'

$script:KcHtLegend = @(
    @('判定待ち', $script:KcHtBarUndecided), @('タップ', $script:KcHtBarTap), @('ホールド', $script:KcHtBarHold),
    @('ほかのキー', $script:KcHtBarPlain), @('届いたキー', $script:KcHtBarKey), @('修飾キー', $script:KcHtBarMod),
    @('レイヤー', $script:KcHtBarLayer)
)

function New-KcHoldTapContext($Form, $Model) {
    $behavior = 'mt'
    if (-not $Model.Behaviors.ContainsKey($behavior)) { $behavior = @($Model.Behaviors.Keys | Sort-Object)[0] }
    return @{
        Form = $Form; Model = $Model; Config = (New-KcHtConfig); Behavior = $behavior
        Capture = (New-KcHtCapture $Model); Clock = (New-KcHtClock)
        Combo = $null; Picking = ''; PickTarget = -1; PrevCombo = $null; LastDone = $null; Warned = $false
        Episode = $null; Result = $null; Sweeps = $null; Range = $null; SummaryKey = ''
        LiveSig = ''; LiveAt = [double]-1e9; LiveSynced = [double]-1e9
    }
}

function Initialize-KcHoldTapUi($Ctx) {
    $form = $Ctx.Form
    $form.SetTexts('タップホールドのタイミング',
        ('{0}: 調べるキーの組み合わせを押して選び、そのキーを押すと、押した瞬間からの判定をグラフに出します。' -f $Ctx.Model.Name) +
        '右手側にログ版のファームを書き込み、USB でつないでください。このウィンドウを前面にしておくと、押したキーはどこにも入力されません。')
    $form.SetLabels('flavor', 'tapping-term', 'キーマップの値に戻す', '変更あり (このウィンドウの中だけ)', '閉じる', '今 {0} ms')
    $form.SetLegend([string[]]@($script:KcHtLegend | ForEach-Object { $_[0] }), [int[]]@($script:KcHtLegend | ForEach-Object { $_[1] }))
    Show-KcHtSettings $Ctx
    $form.SetStatus($script:KcHtDefaultStatus, 0)
    Start-KcHtPicking $Ctx
}

# ---------------------------------------------------------------------------
# キーの組み合わせ (実際に押して選ぶ)
# ---------------------------------------------------------------------------

# 左の欄の組み合わせ
function Show-KcHtCombo($Ctx) {
    $m = $Ctx.Model
    $hint = ''
    $button = '押して選び直す'
    if ($Ctx.Picking -eq 'target') {
        $text = '? + ?'
        $hint = 'hold-tap のキーを押してください'
    } elseif ($Ctx.Picking -eq 'partner') {
        $text = '{0} + ?' -f (Get-KcHtKeyName $m $Ctx.PickTarget)
        $hint = '一緒に押すキーを押してください'
    } else {
        $text = Format-KcHtCombo $m $Ctx.Combo
    }
    if ($Ctx.Picking) {
        $button = ''
        if ($null -ne $Ctx.PrevCombo) { $button = 'やめる' }
    }
    $Ctx.Form.SetCombo('キーの組み合わせ', $text, $hint, $button)
}

function Format-KcHtCombo($Model, $Combo) {
    return ('{0} + {1}' -f (Get-KcHtKeyName $Model $Combo.Target), (Get-KcHtKeyName $Model $Combo.Partner))
}

# 選び始める (今の回は捨てる)
function Start-KcHtPicking($Ctx) {
    $Ctx.PrevCombo = $Ctx.Combo
    $Ctx.Picking = 'target'
    $Ctx.PickTarget = -1
    $Ctx.Capture.Combo = $null
    $Ctx.Capture.Ep = $null
    $Ctx.Episode = $null
    $Ctx.LiveSig = ''
    $Ctx.Form.SetLive($false, [double]0)
    $Ctx.Form.SetSummary('', [string[]]@(), 0)
    $Ctx.Form.SetChartMessage('① hold-tap のキー (A や Space など) を押してください。ログ版のファームをつないでおいてください')
    Show-KcHtCombo $Ctx
}

# 選んでいるあいだに押したキー
function Step-KcHtPicking($Ctx, [int]$Pos, [double]$PcMs) {
    $m = $Ctx.Model
    if ($Ctx.Picking -eq 'target') {
        if (-not (Get-KcHtBehavior $m $Pos)) {
            $Ctx.Form.SetStatus(('{0} は hold-tap のキーではありません。hold-tap のキー (A や Space など) を押してください' -f (Get-KcHtKeyName $m $Pos)), 3)
            return
        }
        $Ctx.PickTarget = $Pos
        $Ctx.Picking = 'partner'
        $Ctx.Form.SetStatus($script:KcHtDefaultStatus, 0)
        $Ctx.Form.SetChartMessage(('② {0} と一緒に押すキーを押してください' -f (Get-KcHtKeyName $m $Pos)))
        Show-KcHtCombo $Ctx
        return
    }
    if ($Pos -eq $Ctx.PickTarget) { return }
    $Ctx.LastDone = $null
    Set-KcHtCombo $Ctx @{ Target = $Ctx.PickTarget; Partner = $Pos } $PcMs
}

# 組み合わせを決める。前に終わった回 ($Ctx.LastDone) があれば出す
function Set-KcHtCombo($Ctx, $Combo, [double]$PcMs) {
    $m = $Ctx.Model
    $Ctx.Combo = $Combo
    $Ctx.Picking = ''
    $Ctx.PickTarget = -1
    $Ctx.PrevCombo = $null
    $Ctx.Capture.Combo = $Combo
    $Ctx.Behavior = Get-KcHtBehavior $m $Combo.Target
    Update-KcHtLimit $Ctx
    Show-KcHtSettings $Ctx
    Show-KcHtCombo $Ctx
    $Ctx.Form.SetStatus($script:KcHtDefaultStatus, 0)
    $Ctx.Warned = $false
    if ($null -ne $Ctx.LastDone) {
        Show-KcHtEpisode $Ctx $Ctx.LastDone $PcMs
    } else {
        Show-KcHtWaiting $Ctx
    }
}

# 組み合わせを選んだあと、まだ回が無いとき
function Show-KcHtWaiting($Ctx) {
    $m = $Ctx.Model
    $Ctx.Episode = $null
    $Ctx.Form.SetLive($false, [double]0)
    $Ctx.Form.SetSummary(('{0} を押すと、ここに判定が出ます' -f (Get-KcHtKeyName $m $Ctx.Combo.Target)), [string[]]@(), 0)
    $Ctx.Form.SetChartMessage(('{0} を押すと、ここにグラフが出ます。ほかのキーを押した回は出しません' -f (Format-KcHtCombo $m $Ctx.Combo)))
}

# 1 回分の長さ (今の tapping-term + 100 ms)。組み合わせを決めたときと、設定を変えたとき
function Update-KcHtLimit($Ctx) {
    if (-not $Ctx.Behavior -or -not $Ctx.Model.Behaviors.ContainsKey($Ctx.Behavior)) { return }
    $Ctx.Capture.LimitMs = Get-KcHtLimitMs (Get-KcHtSetting $Ctx.Model $Ctx.Config $Ctx.Behavior).Term
}

# 左の設定の欄 (今の回の対象のキーの behavior)
function Show-KcHtSettings($Ctx) {
    $m = $Ctx.Model
    $b = $Ctx.Behavior
    $s = Get-KcHtSetting $m $Ctx.Config $b
    $base = $m.Behaviors[$b]
    $Ctx.Form.SetSettings(('&{0} の設定' -f $b), [string[]]$script:KcHtFlavors,
        [string[]]@($script:KcHtFlavors | ForEach-Object { $script:KcHtFlavorText[$_] }), $s.Flavor, [int]$s.Term,
        $script:KcHtTermMin, $script:KcHtTermMax, ('キーマップの値: {0} / {1} ms' -f $base.Flavor, $base.Term), [bool]$s.Changed)
}

# グラフのモデル → ウィンドウ
function Show-KcHoldTapChart($Form, $Chart) {
    $Form.SetChartMessage('')
    $Form.SetChartRange([double]$Chart.From, [double]$Chart.To)
    $l = $Chart.Lanes.ToArray()
    $Form.SetLanes([string[]]@($l | ForEach-Object { [string]$_.Title }), [string[]]@($l | ForEach-Object { [string]$_.Note }),
        [int[]]@($l | ForEach-Object { [int]$_.Kind }), [string[]]@($l | ForEach-Object { [string]$_.Action }))
    $b = $Chart.Bars.ToArray()
    $Form.SetBars([int[]]@($b | ForEach-Object { [int]$_.Lane }), [double[]]@($b | ForEach-Object { [double]$_.From }),
        [double[]]@($b | ForEach-Object { [double]$_.To }), [int[]]@($b | ForEach-Object { [int]$_.Style }),
        [string[]]@($b | ForEach-Object { [string]$_.Text }))
    $k = $Chart.Marks.ToArray()
    $Form.SetMarks([int[]]@($k | ForEach-Object { [int]$_.LaneFrom }), [int[]]@($k | ForEach-Object { [int]$_.LaneTo }),
        [double[]]@($k | ForEach-Object { [double]$_.At }), [int[]]@($k | ForEach-Object { [int]$_.Style }),
        [string[]]@($k | ForEach-Object { [string]$_.Text }))
    $a = $Chart.Arrows.ToArray()
    $Form.SetArrows([int[]]@($a | ForEach-Object { [int]$_.FromLane }), [double[]]@($a | ForEach-Object { [double]$_.FromAt }),
        [int[]]@($a | ForEach-Object { [int]$_.ToLane }), [double[]]@($a | ForEach-Object { [double]$_.ToAt }))
    $Form.RenderChart()
}

# 押している最中の回の「今」(対象を押した時刻からの ms)
function Get-KcHtLiveNow($Ctx, [double]$PcMs) {
    $ep = $Ctx.Episode
    $last = [double]0
    foreach ($e in $ep.Events) {
        if ($e.T -gt $last) { $last = [double]$e.T }
    }
    $fw = Get-KcHtClockNow $Ctx.Clock $PcMs
    if ($null -eq $fw) { return $last }
    return [Math]::Max($last, $fw - $ep.T0)
}

# 今の回を計算して出す
function Update-KcHoldTapView($Ctx, [double]$PcMs) {
    $ep = $Ctx.Episode
    if ($null -eq $ep) { return }
    $m = $Ctx.Model
    $now = $null
    if ($ep.Live) { $now = Get-KcHtLiveNow $Ctx $PcMs }
    $term = (Get-KcHtSetting $m $Ctx.Config $Ctx.Behavior).Term
    $Ctx.Result = Invoke-KcHtRun (Get-KcHtKeymapWith $m $Ctx.Config) $ep.Events
    $Ctx.Range = Get-KcHtRange $ep $term
    $Ctx.Sweeps = Get-KcHtReleaseSweeps $m $Ctx.Config $ep $Ctx.Range
    $sum = Get-KcHtSummary $m $Ctx.Config $ep $Ctx.Result $Ctx.Sweeps $now
    $Ctx.SummaryKey = $sum.Key
    $Ctx.Form.SetSummary($sum.Title, [string[]]$sum.Lines, [int]$sum.Level)
    Show-KcHoldTapChart $Ctx.Form (Get-KcHoldTapChart $m $Ctx.Config $ep $Ctx.Result $Ctx.Sweeps $Ctx.Range)
    if ($ep.Live) {
        $Ctx.Form.SetLive($true, [double]$now)
        $Ctx.LiveSynced = $PcMs
    } else {
        $Ctx.Form.SetLive($false, [double]0)
    }
    $Ctx.LiveAt = $PcMs
}

# 回を出す (押している最中のものも、終わったものも)。対象は選んだ hold-tap のキー
function Show-KcHtEpisode($Ctx, $Episode, [double]$PcMs) {
    $Ctx.Episode = $Episode
    if ($Ctx.Warned) {
        $Ctx.Warned = $false
        $Ctx.Form.SetStatus($script:KcHtDefaultStatus, 0)
    }
    Update-KcHoldTapView $Ctx $PcMs
}

# 切り出しの結果: 終わった回を残す / 捨てた回のことを伝え、前に終わった回に戻す
function Invoke-KcHtCaptureResult($Ctx, $Result, [double]$PcMs) {
    $Ctx.LiveSig = ''
    if ($Result.Kind -eq 'done') {
        if ($null -eq $Result.Episode) { return }
        $Ctx.LastDone = $Result.Episode
        Show-KcHtEpisode $Ctx $Result.Episode $PcMs
        return
    }
    $m = $Ctx.Model
    if ($null -ne $Ctx.LastDone) {
        Show-KcHtEpisode $Ctx $Ctx.LastDone $PcMs
    } else {
        Show-KcHtWaiting $Ctx
    }
    $Ctx.Form.SetStatus(('{0} を押したので、この回は出しません (選んだ組み合わせ: {1})' -f (Get-KcHtKeyName $m $Result.Pos), (Format-KcHtCombo $m $Ctx.Combo)), 3)
    $Ctx.Warned = $true
}

# ログの行 (読めた分)。時計を合わせ、組み合わせを選ぶか、1 回分を切り出す
function Add-KcHoldTapLogLines($Ctx, [string[]]$Lines, [double]$PcMs) {
    foreach ($line in @($Lines)) {
        $rec = ConvertFrom-KcZmkLogLine $line
        if ($null -eq $rec) { continue }
        if ($rec.Time -ge 0) { Update-KcHtClock $Ctx.Clock ([double]$rec.Time) $PcMs }
        $r = Update-KcHtCapture $Ctx.Capture $rec
        if ($Ctx.Picking) {
            if ($Ctx.Capture.Pressed -ge 0) { Step-KcHtPicking $Ctx $Ctx.Capture.Pressed $PcMs }
            continue
        }
        if ($null -ne $r) { Invoke-KcHtCaptureResult $Ctx $r $PcMs }
    }
}

# 押している最中の回の中身が変わったかを見る文字列
function Get-KcHtLiveSignature($Snapshot) {
    $last = $null
    if ($Snapshot.Events.Count -gt 0) { $last = $Snapshot.Events[$Snapshot.Events.Count - 1] }
    $lastText = ''
    if ($null -ne $last) { $lastText = '{0}{1}@{2}' -f [int]$last.Down, $last.Pos, $last.T }
    return ('{0}|{1}|{2}|{3}|{4}|{5}' -f $Snapshot.Seq, $Snapshot.Events.Count, $lastText, @($Snapshot.Decisions).Count, @($Snapshot.Hid).Count, $Snapshot.Dropped)
}

# ループの毎回: 押している最中の回の中身が変わったら出し直す・「今」の文を変える・
# 選んだキーを全部離したか、tapping-term + 100 ms を過ぎたら回を終える (ファームの時計で)
function Update-KcHoldTapLive($Ctx, [double]$PcMs) {
    $cap = $Ctx.Capture
    if ($null -eq $cap.Ep) { return }
    $fw = Get-KcHtClockNow $Ctx.Clock $PcMs
    if ($null -ne $fw) {
        $done = $null
        if ($fw -gt $cap.Ep.CutAt + $script:KcHtCutLagMs) {
            $done = Complete-KcHtCapture $cap -Cut
        } elseif ((Test-KcHtCaptureIdle $cap) -and $fw - $cap.Ep.LastT -gt $script:KcHtSettleMs) {
            $done = Complete-KcHtCapture $cap
        }
        if ($null -ne $done) {
            Invoke-KcHtCaptureResult $Ctx @{ Kind = 'done'; Episode = $done } $PcMs
            return
        }
    }
    $snap = Get-KcHtCaptureSnapshot $cap
    $sig = Get-KcHtLiveSignature $snap
    $showing = ($null -ne $Ctx.Episode -and $Ctx.Episode.Live -and $Ctx.Episode.Seq -eq $snap.Seq)
    $now = $null
    if ($showing) { $now = Get-KcHtLiveNow $Ctx $PcMs }
    if ($sig -ne $Ctx.LiveSig -and $PcMs - $Ctx.LiveAt -ge $script:KcHtLiveMinMs) {
        $Ctx.LiveSig = $sig
        Show-KcHtEpisode $Ctx $snap $PcMs
        return
    }
    if (-not $showing) { return }
    $sum = Get-KcHtSummary $Ctx.Model $Ctx.Config $Ctx.Episode $Ctx.Result $Ctx.Sweeps $now
    if ($sum.Key -ne $Ctx.SummaryKey) {
        $Ctx.SummaryKey = $sum.Key
        $Ctx.Form.SetSummary($sum.Title, [string[]]$sum.Lines, [int]$sum.Level)
    }
    if ($PcMs - $Ctx.LiveSynced -ge $script:KcHtLiveSyncMs) {
        $Ctx.Form.SetLive($true, [double]$now)
        $Ctx.LiveSynced = $PcMs
    }
}

# 続けて届いた操作をまとめる: tapping-term は最後のものだけ
function Get-KcHoldTapCoalescedActions([string[]]$Actions) {
    $out = New-Object 'System.Collections.Generic.List[string]'
    foreach ($a in @($Actions)) {
        if (-not $a) { continue }
        if ($a.StartsWith('term:')) {
            for ($i = $out.Count - 1; $i -ge 0; $i--) {
                if ($out[$i].StartsWith('term:')) { $out.RemoveAt($i) }
            }
        }
        $out.Add($a)
    }
    return , $out.ToArray()
}

# 1 つの操作 (pick / flavor:<名前> / term:<ms> / reset / close)。'close' を返したら終わる
function Invoke-KcHoldTapAction($Ctx, [string]$Action, [double]$PcMs) {
    $parts = $Action.Split([char[]]@(':'), 2)
    $arg = ''
    if ($parts.Count -gt 1) { $arg = $parts[1] }
    switch ($parts[0]) {
        'close' { return 'close' }
        'pick' {
            # 選んでいる途中なら、やめて前の組み合わせに戻す
            if ($Ctx.Picking -and $null -ne $Ctx.PrevCombo) {
                Set-KcHtCombo $Ctx $Ctx.PrevCombo $PcMs
            } elseif (-not $Ctx.Picking) {
                Start-KcHtPicking $Ctx
            }
            return ''
        }
        'flavor' {
            if ($script:KcHtFlavors -notcontains $arg) { return '' }
            Set-KcHtSetting $Ctx.Model $Ctx.Config $Ctx.Behavior 'flavor' $arg
        }
        'term' {
            $t = 0
            if (-not [int]::TryParse($arg, [ref]$t)) { return '' }
            $t = [Math]::Min($script:KcHtTermMax, [Math]::Max($script:KcHtTermMin, $t))
            Set-KcHtSetting $Ctx.Model $Ctx.Config $Ctx.Behavior 'term' $t
        }
        'reset' { $Ctx.Config = New-KcHtConfig }
        default { return '' }
    }
    Update-KcHtLimit $Ctx
    Show-KcHtSettings $Ctx
    Update-KcHoldTapView $Ctx $PcMs
    return ''
}

# ---------------------------------------------------------------------------
# 入口 (Windows のみ)
# ---------------------------------------------------------------------------

function Invoke-KcHoldTap {
    param(
        [Parameter(Mandatory = $true)] $Expected,
        [string]$Port = ''
    )
    $model = New-KcHtModel $Expected
    if ($null -eq $model) { throw ('{0} は ZMK のキーボードではありません' -f $Expected.name) }
    Import-KcInputForm
    Import-KcHoldTapSim
    $form = [KcHoldTapForm]::Launch('タップホールドのタイミング')
    $consoleMode = [KcConsoleMode]::DisableQuickEdit()
    $ctx = New-KcHoldTapContext -Form $form -Model $model
    $reader = New-KcLogPortReader $Port
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $form.SetPort('COM ポートを探しています', 0)
    try {
        Initialize-KcHoldTapUi $ctx
        $form.MaskWinKey($true)
        $stop = $false
        while (-not $stop) {
            foreach ($a in (Get-KcHoldTapCoalescedActions $form.TakeActions())) {
                if ((Invoke-KcHoldTapAction $ctx $a $clock.Elapsed.TotalMilliseconds) -eq 'close') {
                    $stop = $true
                    break
                }
            }
            if ($stop) { break }
            $read = Read-KcLogPortLines $reader
            if ($null -ne $read.Status) { $form.SetPort($read.Status, $read.Level) }
            if ($read.Lines.Count -gt 0) { Add-KcHoldTapLogLines $ctx $read.Lines $clock.Elapsed.TotalMilliseconds }
            Update-KcHoldTapLive $ctx $clock.Elapsed.TotalMilliseconds
            Start-Sleep -Milliseconds 15
        }
    } finally {
        Close-KcLogPortReader $reader
        $form.MaskWinKey($false)
        $form.RequestClose()
        [void]$form.WaitClosed(3000)
        [KcConsoleMode]::Restore($consoleMode)
        try { $Host.UI.RawUI.FlushInputBuffer() } catch { }
    }
}
