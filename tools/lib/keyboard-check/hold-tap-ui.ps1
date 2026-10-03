# タップホールドのタイミングを見るウィンドウ (keyboard-check.ps1 -Mode HoldTap) の流れ。
# ウィンドウ (KcHoldTapForm) には $Ctx.Form 経由で触る (WPF の型に触れないので、tests/hold-tap-ui.Tests.ps1 が偽物で確かめる)。
# Invoke-KcHoldTap だけが Windows 専用 (ウィンドウを開き、ログ版ファームの COM ポートを読む)。
# expected.ps1 / hold-tap-sim.ps1 / hold-tap.ps1 / zmk-log.ps1 が先に読み込まれている前提 (Invoke-KcHoldTap は
# input-test.ps1 / zmk-studio.ps1 / layer-trace.ps1 も)。

# ---------------------------------------------------------------------------
# 状態
# ---------------------------------------------------------------------------

function New-KcHoldTapContext($Form, $Model, [string]$CacheDir = '') {
    $live = ($Model.Engine -eq 'zmk')
    $capture = $null
    if ($live) { $capture = New-KcHtCapture $Model }
    $target = -1
    if ($Model.Targets.Count -gt 0) { $target = $Model.Targets[0].Pos }
    $state = @{
        Model = $Model; Config = (New-KcHtConfig $Model); Target = $target; Preset = 'roll'; Same = $false
        Events = @(); TargetIndex = 0; Selected = $script:KcHtHandleNone; Range = $null; Result = $null; Base = $null
        Sweeps = $null; Episode = $null; Episodes = (New-Object 'System.Collections.Generic.List[object]'); Follow = $true
        Live = $live; Capture = $capture; Raw = (New-Object System.Text.StringBuilder); Saved = $null
    }
    return @{ Form = $Form; State = $state; CacheDir = $CacheDir }
}

# ---------------------------------------------------------------------------
# 表示
# ---------------------------------------------------------------------------

$script:KcHtLegend = @(
    @('判定待ち', $script:KcHtBarUndecided), @('タップ', $script:KcHtBarTap), @('ホールド', $script:KcHtBarHold),
    @('ほかのキー', $script:KcHtBarPlain), @('届いたキー', $script:KcHtBarKey), @('修飾キー', $script:KcHtBarMod),
    @('レイヤー', $script:KcHtBarLayer), @('キーマップの値で計算 (設定を変えたとき)', $script:KcHtBarBaseline)
)

function Initialize-KcHoldTapUi($Ctx) {
    $st = $Ctx.State
    $form = $Ctx.Form
    $m = $st.Model
    if ($m.Engine -eq 'qmk') {
        $sub = ('{0}: KQ-mini (vial-qmk) の tap-hold を、Vial の設定 (QMK Settings の Tap-Hold) で計算します。' +
            'グラフの丸 (押す・離す時刻、TAPPING_TERM の線) をドラッグすると、結果が変わる時刻が分かります。') -f $m.Name
    } else {
        $sub = ('{0}: ZMK v0.3.0 の hold-tap を、キーマップの設定で計算します。グラフの丸 (押す・離す時刻、tapping-term の線) を' +
            'ドラッグすると、結果が変わる時刻が分かります。ログ版のファームを USB でつなぐと、実際に押したキーも読み込みます。') -f $m.Name
    }
    $form.SetTexts('タップホールドのタイミング', $sub)
    $form.SetCaptions('対象のキー (hold-tap)', '押し方', '実際に押したもの (ログ版ファーム)', '設定')
    $form.SetButtonTexts('閉じる', '保存', 'クリア', 'キーマップの値に戻す')
    $form.SetButtons($true, $st.Live)
    $legend = @($script:KcHtLegend)
    if ($st.Live) { $legend += , @('ファームが送ったもの', $script:KcHtBarFirmware) }
    $form.SetLegend([string[]]@($legend | ForEach-Object { $_[0] }), [int[]]@($legend | ForEach-Object { $_[1] }))
    if ($m.Targets.Count -eq 0) {
        $form.SetChartMessage('この機種のキーマップには hold-tap (&mt / &lt など) がありません')
        return
    }
    Show-KcHtKeyChoices $Ctx
    Show-KcHtPresets $Ctx
    Show-KcHtEpisodes $Ctx
    Show-KcHtParams $Ctx
    Set-KcHtPresetScenario $Ctx
    Update-KcHoldTapView $Ctx
}

function Show-KcHtKeyChoices($Ctx) {
    $st = $Ctx.State
    $keys = @($st.Model.Targets | ForEach-Object { [string]$_.Pos })
    $labels = @($st.Model.Targets | ForEach-Object {
            if ($st.Model.Engine -eq 'qmk') { Get-KcHtKeyName $st.Model $_.Pos } else { '{0} &{1}' -f (Get-KcHtKeyName $st.Model $_.Pos), $_.Behavior }
        })
    $Ctx.Form.SetKeyChoices([string[]]$keys, [string[]]$labels, [string]$st.Target)
}

function Show-KcHtPresets($Ctx) {
    $st = $Ctx.State
    $defs = @(Get-KcHtPresetDefs $st.Model $st.Target)
    $sel = $st.Preset
    if ($null -ne $st.Episode) { $sel = '' }
    $side = 'opposite'
    if ($st.Same) { $side = 'same' }
    $Ctx.Form.SetPresets([string[]]@($defs | ForEach-Object { $_.Id }), [string[]]@($defs | ForEach-Object { $_.Label }),
        [string[]]@($defs | ForEach-Object { $_.Detail }), $sel,
        [string[]]@('opposite', 'same'), [string[]]@('相手は反対の手', '相手は同じ手'), $side)
}

function Show-KcHtEpisodes($Ctx) {
    $st = $Ctx.State
    $eps = $st.Episodes.ToArray()
    [array]::Reverse($eps)
    $sel = ''
    if ($null -ne $st.Episode) { $sel = [string]$st.Episode.Seq }
    $follow = '0'
    if ($st.Follow) { $follow = '1' }
    $Ctx.Form.SetEpisodes([string[]]@($eps | ForEach-Object { [string]$_.Seq }), [string[]]@($eps | ForEach-Object { $_.Label }),
        [string[]]@($eps | ForEach-Object { $_.Compare.Text }), [int[]]@($eps | ForEach-Object { [int]$_.Compare.Level }), $sel,
        'キーボードの hold-tap のキー (A や Space など) を押すと、1 回ずつここに並びます (新しい順)。', $st.Live,
        [string[]]@('1', '0'), [string[]]@('新しいものを表示する', '切り替えない'), $follow)
}

# キーマップの値と違えば「変更 (キーマップ: …)」
function Get-KcHtChangedText($Model, $Config, [int]$Target, $Def) {
    $base = New-KcHtConfig $Model
    $a = [string](Get-KcHtParamValue $Model $Config $Target $Def.Name)
    $b = [string](Get-KcHtParamValue $Model $base $Target $Def.Name)
    if ($a -eq $b) { return '' }
    $text = $b
    if ($Def.Type -eq 'slider') {
        if ($b -eq '0' -and $Def.OffText) { $text = $Def.OffText }
    } else {
        $i = [array]::IndexOf([string[]]$Def.Keys, $b)
        if ($i -ge 0) { $text = $Def.Labels[$i] }
    }
    $who = 'キーマップ'
    if ($Model.Engine -eq 'qmk') { $who = 'Vial' }
    return ('変更 ({0}: {1})' -f $who, $text)
}

function Show-KcHtParams($Ctx) {
    $st = $Ctx.State
    $m = $st.Model
    $form = $Ctx.Form
    $form.ClearParams()
    if ($m.Engine -eq 'qmk') {
        $form.SetParamsNote('Vial の QMK Settings (Tap-Hold) と同じ項目です。変えた値はこのウィンドウの中だけで使い、KQ-mini には書き込みません。')
    } else {
        $t = Get-KcHtTarget $m $st.Target
        $form.SetParamsNote(('&{0} の設定 (&{0} のキーすべてに効きます)。変えた値はこのウィンドウの中だけで使い、キーボードには書き込みません。' -f $t.Behavior))
    }
    foreach ($d in (Get-KcHtParamDefs $m)) {
        $value = Get-KcHtParamValue $m $st.Config $st.Target $d.Name
        $changed = Get-KcHtChangedText $m $st.Config $st.Target $d
        if ($d.Type -eq 'slider') {
            $form.AddSliderParam($d.Name, $d.Caption, [int]$d.Min, [int]$d.Max, [int]$value, [string]$d.OffText, $changed)
        } else {
            $cols = 0
            if (@($d.Keys).Count -gt 3) { $cols = 2 }
            $form.AddChoiceParam($d.Name, $d.Caption, [string[]]$d.Keys, [string[]]$d.Labels, [string[]]$d.Details, [string]$value, $changed, $cols)
        }
    }
}

# 設定の表示を今の値に合わせる (リセット・ドラッグ・比較の行から変えたとき)
function Update-KcHtParamValues($Ctx) {
    $st = $Ctx.State
    foreach ($d in (Get-KcHtParamDefs $st.Model)) {
        $value = Get-KcHtParamValue $st.Model $st.Config $st.Target $d.Name
        $Ctx.Form.SetParamValue($d.Name, [string]$value, (Get-KcHtChangedText $st.Model $st.Config $st.Target $d))
    }
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
        [string[]]@($b | ForEach-Object { [string]$_.Text }), [int[]]@($b | ForEach-Object { [int]$_.Start }),
        [int[]]@($b | ForEach-Object { [int]$_.End }))
    $s = $Chart.Spans.ToArray()
    $Form.SetSpans([int[]]@($s | ForEach-Object { [int]$_.LaneFrom }), [int[]]@($s | ForEach-Object { [int]$_.LaneTo }),
        [double[]]@($s | ForEach-Object { [double]$_.From }), [double[]]@($s | ForEach-Object { [double]$_.To }),
        [string[]]@($s | ForEach-Object { [string]$_.Text }))
    $k = $Chart.Marks.ToArray()
    $Form.SetMarks([int[]]@($k | ForEach-Object { [int]$_.LaneFrom }), [int[]]@($k | ForEach-Object { [int]$_.LaneTo }),
        [double[]]@($k | ForEach-Object { [double]$_.At }), [int[]]@($k | ForEach-Object { [int]$_.Style }),
        [string[]]@($k | ForEach-Object { [string]$_.Text }), [int[]]@($k | ForEach-Object { [int]$_.Handle }))
    $a = $Chart.Arrows.ToArray()
    $Form.SetArrows([int[]]@($a | ForEach-Object { [int]$_.FromLane }), [double[]]@($a | ForEach-Object { [double]$_.FromAt }),
        [int[]]@($a | ForEach-Object { [int]$_.ToLane }), [double[]]@($a | ForEach-Object { [double]$_.ToAt }))
    $h = $Chart.Handles.ToArray()
    $Form.SetHandles([int[]]@($h | ForEach-Object { [int]$_.Id }), [double[]]@($h | ForEach-Object { [double]$_.Min }),
        [double[]]@($h | ForEach-Object { [double]$_.Max }), [string[]]@($h | ForEach-Object { [string]$_.Tip }), [int]$Chart.Selected)
    $Form.RenderChart()
}

# ---------------------------------------------------------------------------
# 入力 (プリセット / エピソード)
# ---------------------------------------------------------------------------

function Set-KcHtPresetScenario($Ctx) {
    $st = $Ctx.State
    if (@(Get-KcHtPresetDefs $st.Model $st.Target | Where-Object { $_.Id -eq $st.Preset }).Count -eq 0) { $st.Preset = 'roll' }
    $pr = New-KcHtPreset $st.Model $st.Config $st.Target $st.Preset -Same:$st.Same
    $st.Events = $pr.Events
    $st.TargetIndex = $pr.TargetIndex
    $st.Selected = $pr.Handle
    $st.Episode = $null
    $st.Range = $null
}

function Set-KcHtEpisodeScenario($Ctx, $Episode) {
    $st = $Ctx.State
    if ($null -eq (Get-KcHtTarget $st.Model $Episode.Target)) {
        $Ctx.Form.SetStatus(('{0} は BASE の hold-tap ではないので、グラフに出せません' -f (Get-KcHtKeyName $st.Model $Episode.Target)), 3)
        return $false
    }
    $st.Episode = $Episode
    if ($st.Target -ne $Episode.Target) {
        $st.Target = $Episode.Target
        Show-KcHtKeyChoices $Ctx
        Show-KcHtParams $Ctx
    }
    $st.Events = $Episode.Events
    $st.TargetIndex = $Episode.TargetIndex
    # 対象のキーを離した時刻を選ぶ
    $st.Selected = $Episode.TargetIndex
    for ($i = $Episode.TargetIndex + 1; $i -lt $Episode.Events.Count; $i++) {
        if ($Episode.Events[$i].Pos -eq $Episode.Target) { $st.Selected = $i; break }
    }
    $st.Range = $null
    return $true
}

function Add-KcHtEpisode($Ctx, $Episode) {
    $st = $Ctx.State
    $Episode.Compare = Compare-KcHtFirmware $st.Model $Episode
    $Episode.Label = Format-KcHtEpisode $st.Model $Episode
    $st.Episodes.Add($Episode)
    while ($st.Episodes.Count -gt 50) { $st.Episodes.RemoveAt(0) }
    if ($st.Follow -and (Set-KcHtEpisodeScenario $Ctx $Episode)) {
        Show-KcHtPresets $Ctx
        Update-KcHoldTapView $Ctx
    }
    Show-KcHtEpisodes $Ctx
}

# ---------------------------------------------------------------------------
# 計算して表示する
# ---------------------------------------------------------------------------

# -Quick: ドラッグ中。帯は前の計算のまま (動かしている入力の帯は、その入力の時刻によらない)
function Update-KcHoldTapView($Ctx, [switch]$Quick) {
    $st = $Ctx.State
    $m = $st.Model
    if ($st.Target -lt 0 -or $st.Events.Count -eq 0) { return }
    $km = Get-KcHtKeymapWith $m $st.Config
    $st.Result = Invoke-KcHtRun $m $km $st.Events
    $st.Base = $null
    if ((Get-KcHtChangedParams $m $st.Config $st.Target).Count -gt 0) {
        $st.Base = Invoke-KcHtRun $m $m.Keymap $st.Events
    }
    $pressT = [long]$st.Events[$st.TargetIndex].T
    $term = Get-KcHtTerm $m $st.Config $st.Target
    $st.Range = Get-KcHtRange $st.Events $st.Result $pressT $term $st.Range
    $t = Get-KcHtTarget $m $st.Target
    if (-not $Quick -or $null -eq $st.Sweeps -or $st.Sweeps.Selected -ne $st.Selected) {
        $compare = New-Object 'System.Collections.Generic.List[object]'
        foreach ($c in (Get-KcHtCompareConfigs $m $st.Config $st.Target)) {
            $compare.Add(@{ Label = $c.Label; Current = $c.Current; Action = $c.Action
                    Segments = (Get-KcHtSweep $m $c.Keymap $st.Events $st.TargetIndex $st.Selected $st.Range $t.Behavior) })
        }
        $termSweep = $null
        if ($st.Selected -ne $script:KcHtHandleTerm) {
            $termSweep = Get-KcHtSweep $m $km $st.Events $st.TargetIndex $script:KcHtHandleTerm $st.Range $t.Behavior
        }
        $st.Sweeps = @{
            Selected = $st.Selected
            Handle = (Get-KcHtSweep $m $km $st.Events $st.TargetIndex $st.Selected $st.Range $t.Behavior)
            Compare = $compare.ToArray(); Term = $termSweep
        }
    }
    # 要約
    $sum = Get-KcHtSummary $m $st.Config $st.Target $st.Events $st.TargetIndex $st.Result
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in $sum.Lines) { $lines.Add($l) }
    $selName = 'tapping-term'
    if ($m.Engine -eq 'qmk') { $selName = 'TAPPING_TERM' }
    if ($st.Selected -ge 0 -and $st.Selected -lt $st.Events.Count) { $selName = Format-KcHtEventName $m $st.Events[$st.Selected] }
    if ($null -ne $st.Sweeps -and @($st.Sweeps.Handle).Count -gt 0) {
        $lines.Add(('「{0}」の時刻を変えると: {1}' -f $selName, (Format-KcHtSegments $m $st.Sweeps.Handle)))
    }
    if ($null -ne $st.Episode) {
        $lines.Insert(0, ('ログ版ファームで実際に押したもの: {0}' -f $st.Episode.Compare.Text))
    }
    $Ctx.Form.SetSummary($sum.Title, $lines.ToArray(), [int]$sum.Level)
    # グラフ
    $view = @{
        Model = $m; Config = $st.Config; Target = $st.Target; Events = $st.Events; TargetIndex = $st.TargetIndex
        Selected = $st.Selected; Result = $st.Result; Base = $st.Base; Firmware = $null; Range = $st.Range; Sweeps = $st.Sweeps
    }
    if ($null -ne $st.Episode) { $view.Firmware = @{ Decisions = $st.Episode.Decisions; Hid = $st.Episode.Hid } }
    Show-KcHoldTapChart $Ctx.Form (Get-KcHoldTapChart $view)
    if ($st.Selected -eq $script:KcHtHandleTerm) {
        $Ctx.Form.SetStatus(('{0}: {1} ms (押した時刻から)。線をドラッグすると変えられます' -f $selName, $term), 0)
    } elseif ($st.Selected -ge 0 -and $st.Selected -lt $st.Events.Count) {
        $Ctx.Form.SetStatus(('{0}: {1} ms。丸をドラッグすると時刻が変わります (グラフの帯は、この時刻を変えたときの結果)' -f $selName, $st.Events[$st.Selected].T), 0)
    }
}

# ---------------------------------------------------------------------------
# 操作
# ---------------------------------------------------------------------------

# 続けて届いた操作をまとめる: drag / param は同じものの最後だけ (drop はそれまでの同じ drag を消す)
function Get-KcHoldTapCoalescedActions([string[]]$Actions) {
    $out = New-Object 'System.Collections.Generic.List[string]'
    foreach ($a in @($Actions)) {
        if (-not $a) { continue }
        $key = $null
        if ($a -match '^(drag|drop):(-?\d+):') { $key = 'drag:' + $Matches[2] + ':' }
        elseif ($a -match '^(param:[\w-]+:)') { $key = $Matches[1] }
        if ($null -ne $key) {
            for ($i = $out.Count - 1; $i -ge 0; $i--) {
                $o = $out[$i]
                if ($o.StartsWith($key) -or ($key.StartsWith('drag:') -and $o.StartsWith('drop:' + $key.Substring(5)))) {
                    if ($o.StartsWith('drop:')) { break }
                    $out.RemoveAt($i)
                }
            }
        }
        $out.Add($a)
    }
    return , $out.ToArray()
}

# 1 つの操作。'close' を返したら終わる
function Invoke-KcHoldTapAction($Ctx, [string]$Action) {
    $st = $Ctx.State
    $parts = $Action.Split([char[]]@(':'), 3)
    $verb = $parts[0]
    $arg = ''
    if ($parts.Count -gt 1) { $arg = $parts[1] }
    switch ($verb) {
        'close' { return 'close' }
        'key' {
            $st.Target = [int]$arg
            $st.Follow = $false
            Set-KcHtPresetScenario $Ctx
            Show-KcHtPresets $Ctx
            Show-KcHtParams $Ctx
            Show-KcHtEpisodes $Ctx
            Update-KcHoldTapView $Ctx
        }
        'preset' {
            $st.Preset = $arg
            $st.Follow = $false
            Set-KcHtPresetScenario $Ctx
            Show-KcHtPresets $Ctx
            Show-KcHtEpisodes $Ctx
            Update-KcHoldTapView $Ctx
        }
        'partner' {
            $st.Same = ($arg -eq 'same')
            if ($null -eq $st.Episode) {
                Set-KcHtPresetScenario $Ctx
                Update-KcHoldTapView $Ctx
            }
        }
        'episode' {
            $ep = $null
            foreach ($e in $st.Episodes) {
                if ([string]$e.Seq -eq $arg) { $ep = $e }
            }
            if ($null -ne $ep -and (Set-KcHtEpisodeScenario $Ctx $ep)) {
                $st.Follow = ($st.Episodes.Count -gt 0 -and [object]::ReferenceEquals($ep, $st.Episodes[$st.Episodes.Count - 1]))
                Show-KcHtPresets $Ctx
                Show-KcHtEpisodes $Ctx
                Update-KcHoldTapView $Ctx
            }
        }
        'follow' {
            $st.Follow = ($arg -eq '1')
            if ($st.Follow -and $st.Episodes.Count -gt 0) {
                if (Set-KcHtEpisodeScenario $Ctx $st.Episodes[$st.Episodes.Count - 1]) {
                    Show-KcHtPresets $Ctx
                    Update-KcHoldTapView $Ctx
                }
            }
            Show-KcHtEpisodes $Ctx
        }
        'param' {
            $value = ''
            if ($parts.Count -gt 2) { $value = $parts[2] }
            Set-KcHtParamValue $st.Model $st.Config $st.Target $arg $value
            # 比較の行から flavor / 設定を変えたとき、左の欄も合わせる
            Update-KcHtParamValues $Ctx
            Update-KcHoldTapView $Ctx
        }
        'reset' {
            $st.Config = New-KcHtConfig $st.Model
            Update-KcHtParamValues $Ctx
            Update-KcHoldTapView $Ctx
        }
        'select' {
            $st.Selected = [int]$arg
            Update-KcHoldTapView $Ctx
        }
        { $_ -eq 'drag' -or $_ -eq 'drop' } {
            $id = [int]$arg
            $ms = [long]$parts[2]
            $st.Selected = $id
            if ($id -eq $script:KcHtHandleTerm) {
                $pressT = [long]$st.Events[$st.TargetIndex].T
                $term = [int][Math]::Min(500, [Math]::Max(50, $ms - $pressT))
                Set-KcHtParamValue $st.Model $st.Config $st.Target 'term' ([string]$term)
                Update-KcHtParamValues $Ctx
            } elseif ($id -ge 0 -and $id -lt $st.Events.Count) {
                $st.Events = Set-KcHtEventTime $st.Events $id $ms
            }
            Update-KcHoldTapView $Ctx -Quick:($verb -eq 'drag')
        }
        'clear' {
            $st.Episodes.Clear()
            [void]$st.Raw.Clear()
            if ($null -ne $st.Episode) {
                Set-KcHtPresetScenario $Ctx
                Show-KcHtPresets $Ctx
                Update-KcHoldTapView $Ctx
            }
            Show-KcHtEpisodes $Ctx
        }
        'save' {
            $path = Save-KcHoldTap $Ctx
            $st.Saved = $path
            $Ctx.Form.SetStatus(('保存しました: {0}' -f $path), 1)
        }
    }
    return ''
}

# 今の入力・設定・結果と、読み込んだエピソードを tools/.cache/keyboard-check/hold-tap/ に保存する。戻り値: .txt のパス
function Save-KcHoldTap($Ctx) {
    $st = $Ctx.State
    $m = $st.Model
    $dir = Join-Path $Ctx.CacheDir 'hold-tap'
    [void](New-Item -ItemType Directory -Force -Path $dir)
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $txt = Join-Path $dir ('{0}.txt' -f $stamp)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add(('タップホールドのタイミング: {0}' -f $m.Name))
    $lines.Add(('設定: {0}' -f (Format-KcHtConfig $m $st.Config $st.Target)))
    $lines.Add(('入力: {0}' -f ((@($st.Events) | ForEach-Object { '{0} {1} ms' -f (Format-KcHtEventName $m $_), $_.T }) -join ' / ')))
    if ($null -ne $st.Result) {
        $sum = Get-KcHtSummary $m $st.Config $st.Target $st.Events $st.TargetIndex $st.Result
        $lines.Add(('結果: {0}' -f $sum.Title))
        foreach ($l in $sum.Lines) { $lines.Add('  ' + $l) }
    }
    if ($null -ne $st.Sweeps) {
        $lines.Add(('選んだ入力を動かすと: {0}' -f (Format-KcHtSegments $m $st.Sweeps.Handle)))
        foreach ($c in @($st.Sweeps.Compare)) { $lines.Add(('  {0}: {1}' -f $c.Label, (Format-KcHtSegments $m $c.Segments))) }
    }
    if ($st.Episodes.Count -gt 0) {
        $lines.Add('')
        $lines.Add('実際に押したもの (ログ版ファーム):')
        foreach ($e in $st.Episodes) {
            $lines.Add(('  {0}  ({1})' -f $e.Label, $e.Compare.Text))
            $lines.Add(('    {0}' -f ((@($e.Events) | ForEach-Object { '{0}{1}@{2}' -f @('↑', '↓')[[int]$_.Down], (Get-KcHtKeyName $m $_.Pos), $_.T }) -join ' ')))
        }
    }
    $utf8 = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($txt, ($lines -join "`r`n") + "`r`n", $utf8)
    if ($st.Raw.Length -gt 0) {
        [System.IO.File]::WriteAllText([System.IO.Path]::ChangeExtension($txt, '.log'), $st.Raw.ToString(), $utf8)
    }
    return $txt
}

# ---------------------------------------------------------------------------
# 入口 (Windows のみ)
# ---------------------------------------------------------------------------

# 戻り値: 保存したファイル ($null = 保存なし)
function Invoke-KcHoldTap {
    param(
        [Parameter(Mandatory = $true)] $Expected,
        [Parameter(Mandatory = $true)] [string]$CacheDir,
        [string]$Port = ''
    )
    $model = New-KcHtModel $Expected
    if ($null -eq $model) { throw ('{0} のキーマップには hold-tap がありません' -f $Expected.name) }
    Import-KcInputForm
    Import-KcHoldTapSim
    $form = [KcHoldTapForm]::Launch('タップホールドのタイミング')
    $consoleMode = [KcConsoleMode]::DisableQuickEdit()
    $ctx = New-KcHoldTapContext -Form $form -Model $model -CacheDir $CacheDir
    $reader = $null
    if ($ctx.State.Live) {
        $reader = New-KcLogPortReader $Port
        $form.SetPort('COM ポートを探しています', 0)
    } else {
        $form.SetPort('', -1)
    }
    try {
        Initialize-KcHoldTapUi $ctx
        $form.MaskWinKey($true)
        $lastLine = [DateTime]::Now
        $stop = $false
        while (-not $stop) {
            foreach ($a in (Get-KcHoldTapCoalescedActions $form.TakeActions())) {
                if ((Invoke-KcHoldTapAction $ctx $a) -eq 'close') {
                    $stop = $true
                    break
                }
            }
            if ($stop) { break }
            if ($null -ne $reader) {
                $read = Read-KcLogPortLines $reader
                if ($null -ne $read.Status) { $form.SetPort($read.Status, $read.Level) }
                foreach ($line in $read.Lines) {
                    $lastLine = [DateTime]::Now
                    $rec = ConvertFrom-KcZmkLogLine $line
                    if ($null -eq $rec) { continue }
                    [void]$ctx.State.Raw.AppendLine((Remove-KcAnsi $line))
                    $ep = Update-KcHtCapture $ctx.State.Capture $rec
                    if ($null -ne $ep) { Add-KcHtEpisode $ctx $ep }
                }
                # しばらくログが来なければ、今のエピソードを終える (すべて離していれば)
                if ($null -ne $ctx.State.Capture.Ep -and ([DateTime]::Now - $lastLine).TotalMilliseconds -gt 400) {
                    $ep = Complete-KcHtCapture $ctx.State.Capture
                    if ($null -ne $ep) { Add-KcHtEpisode $ctx $ep }
                }
            }
            Start-Sleep -Milliseconds 15
        }
    } finally {
        if ($null -ne $reader) { Close-KcLogPortReader $reader }
        $form.MaskWinKey($false)
        $form.RequestClose()
        [void]$form.WaitClosed(3000)
        [KcConsoleMode]::Restore($consoleMode)
        try { $Host.UI.RawUI.FlushInputBuffer() } catch { }
    }
    return $ctx.State.Saved
}
