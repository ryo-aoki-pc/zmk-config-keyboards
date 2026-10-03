# タップホールドのタイミングを見るウィンドウ (keyboard-check.ps1 -Mode HoldTap) の流れ。
# ZMK のログ版ファームのログを読み、hold-tap のキーを押した 1 回分を、押した瞬間からリアルタイムにグラフに出す
# (押している間は「今」までを描き、全部離したらその回を残す。次に hold-tap のキーを押したら切り替える)。
# ウィンドウ (KcHoldTapForm) には $Ctx.Form 経由で触る (WPF の型に触れないので、tests/hold-tap-ui.Tests.ps1 が偽物で確かめる)。
# 時刻 ($PcMs) は呼び出し側の PC の時計 (ms)。Invoke-KcHoldTap だけが Windows 専用。
# expected.ps1 / hold-tap-sim.ps1 / hold-tap.ps1 / zmk-log.ps1 が先に読み込まれている前提 (Invoke-KcHoldTap は
# input-test.ps1 / zmk-studio.ps1 / layer-trace.ps1 も)。

$script:KcHtLiveMinMs = 50      # 押している最中に計算し直す間隔の最小
$script:KcHtLiveSyncMs = 250    # ウィンドウの「今」を合わせ直す間隔
$script:KcHtIdleMs = 400        # 全部離してから、この間ログが来なければ 1 回分を終える
$script:KcHtTermMin = 50
$script:KcHtTermMax = 500

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
        Episode = $null; Result = $null; Sweeps = $null; Range = $null; SummaryKey = ''
        LiveSig = ''; LiveAt = [double]-1e9; LiveSynced = [double]-1e9; LastLine = [double]-1e9
    }
}

function Initialize-KcHoldTapUi($Ctx) {
    $form = $Ctx.Form
    $form.SetTexts('タップホールドのタイミング',
        ('{0}: hold-tap のキー (A や Space など) を押すと、押した瞬間からの判定をグラフに出します。' -f $Ctx.Model.Name) +
        '右手側にログ版のファームを書き込み、USB でつないでください。このウィンドウを前面にしておくと、押したキーはどこにも入力されません。')
    $form.SetLabels('flavor', 'tapping-term', 'キーマップの値に戻す', '変更あり (このウィンドウの中だけ)', '閉じる', '今 {0} ms')
    $form.SetLegend([string[]]@($script:KcHtLegend | ForEach-Object { $_[0] }), [int[]]@($script:KcHtLegend | ForEach-Object { $_[1] }))
    Show-KcHtSettings $Ctx
    $form.SetSummary('hold-tap のキーを押すと、ここに判定が出ます', [string[]]@(), 0)
    $form.SetChartMessage('ログ版のファームをつないで、hold-tap のキー (A や Space など) を押してください')
    $form.SetStatus('flavor と tapping-term は、このウィンドウの中で計算に使うだけで、キーボードには書き込みません', 0)
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
    $Ctx.Range = Get-KcHtRange $ep $Ctx.Result $term $now
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

# 回を出す (押している最中のものも、終わったものも)。BASE の hold-tap でなければ出さない
function Show-KcHtEpisode($Ctx, $Episode, [double]$PcMs) {
    $behavior = Get-KcHtBehavior $Ctx.Model $Episode.Target
    if (-not $behavior) {
        $Ctx.Form.SetStatus(('{0} は BASE の hold-tap ではないので、グラフに出しません' -f (Get-KcHtKeyName $Ctx.Model $Episode.Target)), 3)
        return
    }
    $Ctx.Episode = $Episode
    if ($behavior -ne $Ctx.Behavior) {
        $Ctx.Behavior = $behavior
        Show-KcHtSettings $Ctx
    }
    Update-KcHoldTapView $Ctx $PcMs
}

# ログの行 (読めた分)。時計を合わせ、1 回分を切り出す
function Add-KcHoldTapLogLines($Ctx, [string[]]$Lines, [double]$PcMs) {
    foreach ($line in @($Lines)) {
        $rec = ConvertFrom-KcZmkLogLine $line
        if ($null -eq $rec) { continue }
        $Ctx.LastLine = $PcMs
        if ($rec.Time -ge 0) { Update-KcHtClock $Ctx.Clock ([double]$rec.Time) $PcMs }
        $done = Update-KcHtCapture $Ctx.Capture $rec
        if ($null -ne $done) {
            $Ctx.LiveSig = ''
            Show-KcHtEpisode $Ctx $done $PcMs
        }
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

# ループの毎回: 押している最中の回の中身が変わったら出し直す・「今」の文を変える・全部離したら回を終える
function Update-KcHoldTapLive($Ctx, [double]$PcMs) {
    $cap = $Ctx.Capture
    if ($null -eq $cap.Ep) { return }
    if ((Test-KcHtCaptureIdle $cap) -and $PcMs - $Ctx.LastLine -gt $script:KcHtIdleMs) {
        $done = Complete-KcHtCapture $cap
        $Ctx.LiveSig = ''
        if ($null -ne $done) { Show-KcHtEpisode $Ctx $done $PcMs }
        return
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

# 1 つの操作 (flavor:<名前> / term:<ms> / reset / close)。'close' を返したら終わる
function Invoke-KcHoldTapAction($Ctx, [string]$Action, [double]$PcMs) {
    $parts = $Action.Split([char[]]@(':'), 2)
    $arg = ''
    if ($parts.Count -gt 1) { $arg = $parts[1] }
    switch ($parts[0]) {
        'close' { return 'close' }
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
