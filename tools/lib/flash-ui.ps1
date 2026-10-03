# 書き込みツール (flash.ps1) の画面の流れ。機種とビルドを選ぶ → ダウンロード → 手順ごとに書き込む。
# ウィンドウ (KcFlashForm)・ビルドの一覧の取得・ダウンロード・子プロセスは $Ctx 経由で使い、WPF の型には触れない
# (テストでは偽物を渡して、Windows 以外でも流れを確かめる)。firmware-release.ps1 と flash-plan.ps1 が先に読み込まれている前提。
#
# $Ctx:
#   Form          ウィンドウ (KcFlashForm と同じメソッドを持つもの)
#   ToolsDir      tools フォルダ
#   WaitSeconds   1 回の書き込みで、ブートローダが現れるのを待つ秒数
#   GetBuilds     { param($Repo) } → Get-FirmwareBuildList の戻り値
#   Download      { param($Repo, $Tag, $Assets, $OnFile) } → Save-FirmwareBuild の戻り値
#   NewChild      { param($Command) } → 子プロセス (TakeLines / HasExited / ExitCode / Killed / Kill / Dispose)
#   SaveSettings  { param($Settings) } (覚えておく設定。不要なら何もしない)
#   Now           { } → 今の時刻 (UTC)
#   Settings      前回の設定 (Keyboard / LismRight / LismLeft / KeyballCount)
#   State         画面の状態 (New-FlashUiContext が作る)

# KcFlashForm の定数と同じ値 (windows.Tests.ps1 が一致を確かめる)
$script:FlashUiPageSelect = 0
$script:FlashUiPageRun = 1
$script:FlashUiLevelInfo = 0
$script:FlashUiLevelOk = 1
$script:FlashUiLevelNg = 2
$script:FlashUiLevelWarn = 3
$script:FlashUiLevelFaint = 4
$script:FlashUiStepPending = 0
$script:FlashUiStepActive = 1
$script:FlashUiStepDone = 2
$script:FlashUiStepFailed = 3
$script:FlashUiKinds = @{ latest = 0; pr = 1; custom = 2 }
$script:FlashUiPrStates = @{ '' = 0; open = 1; merged = 2; closed = 3 }
$script:FlashUiStyleChoices = 0
$script:FlashUiStyleSegments = 1
$script:FlashUiListTtlMinutes = 10
$script:FlashUiCancel = 'flash-ui: cancelled'

function New-FlashUiContext($Form, [string]$ToolsDir, [int]$WaitSeconds, [scriptblock]$GetBuilds, [scriptblock]$Download,
    [scriptblock]$NewChild, [scriptblock]$SaveSettings = { param($Settings) }, [scriptblock]$Now = { [DateTime]::UtcNow },
    [hashtable]$Settings = @{}) {
    return @{
        Form         = $Form
        ToolsDir     = $ToolsDir
        WaitSeconds  = $WaitSeconds
        GetBuilds    = $GetBuilds
        Download     = $Download
        NewChild     = $NewChild
        SaveSettings = $SaveSettings
        Now          = $Now
        Settings     = $Settings
        State        = @{
            Phase = 'select'; Keyboard = ''; Mode = 'Both'; Central = ''; Right = 'trackball'; Left = 'trackball'; Count = 2
            Filter = 'all'; Lists = @{}; Builds = @(); Source = $null; Tag = ''; Steps = @(); Missing = @()
            Build = $null; Paths = $null; Index = 0; Child = $null; StepStart = $null; FailText = ''; LastLine = ''
            Exit = $false; Result = ''; Flashed = 0
        }
    }
}

function Get-FlashUiSetting([hashtable]$Settings, [string]$Name, $Default) {
    if ($null -ne $Settings -and $Settings.ContainsKey($Name) -and $null -ne $Settings[$Name] -and [string]$Settings[$Name] -ne '') {
        return $Settings[$Name]
    }
    return $Default
}

# ---------------------------------------------------------------------------
# 選ぶ画面
# ---------------------------------------------------------------------------

function Initialize-FlashUi($Ctx, [string]$Keyboard = '') {
    $f = $Ctx.Form
    $f.SetTexts('FLASH', 'ファームウェアの書き込み', '')
    $f.SetCaptions('機種', 'ビルド', 'オプション', '手順', 'ログ')
    $f.SetButtonTexts('閉じる', '戻る', '中止', '再試行', '続ける', '書き込む', '更新')
    $keys = @($script:FlashKeyboards.Keys)
    $names = @($keys | ForEach-Object { [string]$_ })
    $details = @($keys | ForEach-Object { $script:FlashMcus[$script:FlashKeyboards[$_].Mcu].Label })
    $groups = @($keys | ForEach-Object { if ($script:FlashKeyboards[$_].Kind -eq 'zmk') { 'ZMK' } else { 'QMK / Vial' } })
    $f.SetKeyboards([string[]]$keys, [string[]]$names, [string[]]$details, [string[]]$groups)
    $f.SetBuildFilters([string[]]@('all', 'pr', 'custom'), [string[]]@('すべて', 'PR', 'custom'), 'all')
    Show-FlashUiSelect $Ctx

    $s = $Ctx.State
    $s.Right = [string](Get-FlashUiSetting $Ctx.Settings 'LismRight' 'trackball')
    $s.Left = [string](Get-FlashUiSetting $Ctx.Settings 'LismLeft' 'trackball')
    if (-not $script:FlashVariants.Contains($s.Right)) { $s.Right = 'trackball' }
    if (-not $script:FlashVariants.Contains($s.Left)) { $s.Left = 'trackball' }
    $count = 2
    [void][int]::TryParse([string](Get-FlashUiSetting $Ctx.Settings 'KeyballCount' 2), [ref]$count)
    $s.Count = if ($count -eq 1) { 1 } else { 2 }

    if (-not $Keyboard -or -not $script:FlashKeyboards.Contains($Keyboard)) {
        $Keyboard = [string](Get-FlashUiSetting $Ctx.Settings 'Keyboard' '')
    }
    if (-not $script:FlashKeyboards.Contains($Keyboard)) {
        $Keyboard = $keys[0]
    }
    Select-FlashUiKeyboard $Ctx $Keyboard
}

function Show-FlashUiSelect($Ctx) {
    $f = $Ctx.Form
    $Ctx.State.Phase = 'select'
    $f.ShowPage($script:FlashUiPageSelect)
    $f.SetButtons($true, $false, $false, $false, $false, $true)
    $f.SetCloseGuard($false)
    $f.SetProgress(0, 0)
    $f.SetStatus('', $script:FlashUiLevelInfo)
}

function Save-FlashUiSettings($Ctx) {
    $s = $Ctx.State
    $settings = @{ Keyboard = $s.Keyboard; LismRight = $s.Right; LismLeft = $s.Left; KeyballCount = $s.Count }
    try {
        & $Ctx.SaveSettings $settings
    } catch {
        # 設定を覚えられなくても続ける
    }
}

function Select-FlashUiKeyboard($Ctx, [string]$Keyboard) {
    $s = $Ctx.State
    $k = Get-FlashKeyboard $Keyboard
    $s.Keyboard = $Keyboard
    # 書き込む内容とセントラルの版は、機種を選ぶたびに既定に戻す (ログ版などを誤って書かないように)
    $s.Mode = 'Both'
    $s.Central = ''
    $s.Tag = ''
    $Ctx.Form.SelectKeyboard($Keyboard)
    $Ctx.Form.SetTexts('FLASH', ('{0} に書き込む' -f $Keyboard), ('{0} · {1}' -f $k.Repo, $script:FlashMcus[$k.Mcu].Label))
    Update-FlashUiOptions $Ctx
    Update-FlashUiBuilds $Ctx $false
    Save-FlashUiSettings $Ctx
}

function Get-FlashUiOptionValue($Ctx, [string]$Group) {
    $s = $Ctx.State
    switch ($Group) {
        'mode' { return $s.Mode }
        'central' { return $s.Central }
        'right' { return $s.Right }
        'left' { return $s.Left }
        'count' { return [string]$s.Count }
    }
    return ''
}

function Update-FlashUiOptions($Ctx) {
    $f = $Ctx.Form
    $f.ClearOptionGroups()
    foreach ($g in (Get-FlashOptionGroups $Ctx.State.Keyboard $Ctx.State.Mode)) {
        $style = if ($g.Style -eq 'choices') { $script:FlashUiStyleChoices } else { $script:FlashUiStyleSegments }
        $f.AddOptionGroup($g.Key, $g.Caption, $style, [string[]]$g.Keys, [string[]]$g.Labels, [string[]]$g.Details,
            [string](Get-FlashUiOptionValue $Ctx $g.Key), [bool]$g.Visible)
    }
}

# ビルドの一覧を取得する (同じリポジトリは 10 分間取り直さない。$Refresh なら取り直す)
function Update-FlashUiBuilds($Ctx, [bool]$Refresh) {
    $s = $Ctx.State
    $f = $Ctx.Form
    $repo = $script:FlashKeyboards[$s.Keyboard].Repo
    $now = & $Ctx.Now
    $cached = $null
    if ($s.Lists.ContainsKey($repo)) {
        $cached = $s.Lists[$repo]
    }
    if ($Refresh -or $null -eq $cached -or ($now - $cached.LoadedAt).TotalMinutes -ge $script:FlashUiListTtlMinutes) {
        $f.SetBuilds([string[]]@(), [int[]]@(), [string[]]@(), [string[]]@(), [string[]]@(), [int[]]@(), [string[]]@(), [string[]]@(), '')
        $f.SetBuildsMessage('ビルドの一覧を読み込んでいます...', $script:FlashUiLevelInfo)
        $f.SetSource('読み込み中', $script:FlashUiLevelInfo)
        $f.SetStartEnabled($false)
        $result = $null
        try {
            $result = & $Ctx.GetBuilds $repo
        } catch {
            $result = @{ Builds = @(); Source = 'fallback'; Message = ('一覧を取得できませんでした: {0}' -f $_.Exception.Message); Level = $script:FlashUiLevelNg; FetchedAt = $null }
        }
        $cached = @{ Result = $result; LoadedAt = $now }
        $s.Lists[$repo] = $cached
    }
    $result = $cached.Result
    $s.Builds = @($result.Builds)
    $s.Source = $result
    switch ([string]$result.Source) {
        'api' {
            $when = ''
            if ($null -ne $result.FetchedAt) {
                $when = ' (' + ([DateTime]$result.FetchedAt).ToLocalTime().ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture) + ')'
            }
            $f.SetSource(('GitHub から取得{0}' -f $when), $script:FlashUiLevelOk)
        }
        'cache' { $f.SetSource('前回の一覧', $script:FlashUiLevelWarn) }
        default { $f.SetSource('最新だけ', $script:FlashUiLevelWarn) }
    }
    if (-not $s.Tag -or -not @($s.Builds | Where-Object { $_.Tag -eq $s.Tag })) {
        $s.Tag = ''
        $first = @(Select-FirmwareBuilds $s.Builds $s.Filter)
        if ($first.Count -gt 0) {
            $s.Tag = $first[0].Tag
        }
    }
    Show-FlashUiBuilds $Ctx
    Update-FlashUiPlan $Ctx
}

function Show-FlashUiBuilds($Ctx) {
    $s = $Ctx.State
    $visible = @(Select-FirmwareBuilds $s.Builds $s.Filter)
    $keys = @(); $kinds = @(); $badges = @(); $titles = @(); $details = @(); $states = @(); $stateTexts = @(); $tips = @()
    foreach ($b in $visible) {
        $label = Format-FirmwareBuildLabel $b
        $keys += $b.Tag
        $kinds += [int]$script:FlashUiKinds[$b.Kind]
        $badges += $label.Badge
        $titles += $label.Title
        $details += $label.Detail
        $states += [int]$script:FlashUiPrStates[[string]$b.State]
        $stateTexts += $label.StateText
        $tips += $label.Tooltip
    }
    $Ctx.Form.SetBuilds([string[]]$keys, [int[]]$kinds, [string[]]$badges, [string[]]$titles, [string[]]$details,
        [int[]]$states, [string[]]$stateTexts, [string[]]$tips, $s.Tag)

    $message = ''
    $level = $script:FlashUiLevelInfo
    if ($null -ne $s.Source -and $s.Source.Message) {
        $message = [string]$s.Source.Message
        $level = [int]$s.Source.Level
    }
    if ($visible.Count -eq 0) {
        $empty = 'ビルドがありません。'
        if ($s.Filter -eq 'pr') {
            $empty = 'PR のビルドはありません (各リポジトリの PR の CI が作ります。古いものから自動で削除されます)。'
        }
        if ($message) { $message += "`n" }
        $message += $empty
        if ($level -eq $script:FlashUiLevelInfo) { $level = $script:FlashUiLevelWarn }
    }
    $Ctx.Form.SetBuildsMessage($message, $level)
}

function Get-FlashUiBuild($Ctx) {
    $s = $Ctx.State
    if (-not $s.Tag) {
        return $null
    }
    foreach ($b in @($s.Builds)) {
        if ($b.Tag -eq $s.Tag) {
            return $b
        }
    }
    return $null
}

function Get-FlashUiStepTitle($Step, [int]$Index, [int]$Count) {
    return ('[{0}/{1}] {2}: {3}' -f ($Index + 1), $Count, $Step.Side, $Step.What)
}

function Update-FlashUiPlan($Ctx) {
    $s = $Ctx.State
    $f = $Ctx.Form
    $s.Steps = @(Get-FlashPlan -Keyboard $s.Keyboard -Mode $s.Mode -Central $s.Central -Right $s.Right -Left $s.Left -Count $s.Count)
    $titles = @(); $details = @(); $states = @()
    for ($i = 0; $i -lt $s.Steps.Count; $i++) {
        $titles += (Get-FlashUiStepTitle $s.Steps[$i] $i $s.Steps.Count)
        $details += $s.Steps[$i].Asset
        $states += $script:FlashUiStepPending
    }
    $f.SetSteps([string[]]$titles, [string[]]$details, [int[]]$states)

    $build = Get-FlashUiBuild $Ctx
    $notes = @()
    $level = $script:FlashUiLevelInfo
    $enabled = $true
    if ($null -eq $build) {
        $notes += 'ビルドを選んでください。'
        $enabled = $false
    } else {
        $s.Missing = @(Get-FlashMissingAssets $s.Steps $build.Assets)
        if ($s.Missing.Count -gt 0) {
            $notes += ('このビルドには次のファイルがありません: {0}' -f ($s.Missing -join ', '))
            $notes += '後から足したファームウェア (ログ版など) は、古いビルドにはありません。別のビルドか、別の版を選んでください。'
            $level = $script:FlashUiLevelNg
            $enabled = $false
        } else {
            if ($build.Kind -eq 'pr') {
                $sha = [string]$build.Commit
                if ($sha.Length -gt 7) { $sha = $sha.Substring(0, 7) }
                $notes += ('PR #{0} のビルドです。PR をマージした状態のコミット ({1}) をビルドしたものです。' -f $build.Pr, $sha)
            } elseif ($build.Kind -eq 'custom') {
                $notes += 'custom ブランチの過去のビルドです。'
            }
            if ($s.Mode -in @('ResetBoth', 'ResetOnly')) {
                $notes += '設定リセットでペアリング情報も消えます。書き込んだ後、PC の Bluetooth 設定から古い登録を削除して再ペアリングしてください。'
                $level = $script:FlashUiLevelWarn
            }
            if ($s.Central -eq 'logging' -and (Test-FlashModeHasCentral $s.Mode)) {
                $notes += 'ログ版は、調べ終わったら通常版に戻してください。'
                $level = $script:FlashUiLevelWarn
            }
        }
    }
    $f.SetPlanNote(($notes -join "`n"), $level)
    $f.SetStartEnabled($enabled)
}

# ---------------------------------------------------------------------------
# 書き込む画面
# ---------------------------------------------------------------------------

function Set-FlashUiRunButtons($Ctx, [string]$Phase) {
    $f = $Ctx.Form
    switch ($Phase) {
        { $_ -in @('download', 'run') } { $f.SetButtons($false, $false, $true, $false, $false, $false); $f.SetCloseGuard($true) }
        'pause' { $f.SetButtons($false, $false, $true, $false, $true, $false); $f.SetCloseGuard($true) }
        { $_ -in @('failed', 'cancelled') } { $f.SetButtons($true, $true, $false, $true, $false, $false); $f.SetCloseGuard($false) }
        'done' { $f.SetButtons($true, $true, $false, $false, $false, $false); $f.SetCloseGuard($false) }
    }
}

function Start-FlashUiRun($Ctx) {
    $s = $Ctx.State
    $f = $Ctx.Form
    $build = Get-FlashUiBuild $Ctx
    if ($null -eq $build -or $s.Steps.Count -eq 0) {
        return
    }
    Update-FlashUiPlan $Ctx
    if ($s.Missing.Count -gt 0) {
        return
    }
    $k = $script:FlashKeyboards[$s.Keyboard]
    $label = Format-FirmwareBuildLabel $build
    $s.Build = $build
    $s.Paths = $null
    $s.Index = 0
    $s.Flashed = 0
    $s.Phase = 'download'
    $s.Result = ''
    $f.ShowPage($script:FlashUiPageRun)
    $f.ClearLog()
    Set-FlashUiRunButtons $Ctx 'download'
    $f.SetBanner('ダウンロードしています', ('{0} の {1}: {2} ({3})' -f $k.Repo, $label.Badge, $label.Title, $build.Tag), $script:FlashUiLevelInfo)
    $f.AppendLog(('{0} の {1} ({2}) をダウンロードします。' -f $k.Repo, $label.Badge, $build.Tag), $script:FlashUiLevelInfo, $false)

    $assets = @($s.Steps | ForEach-Object { $_.Asset } | Select-Object -Unique)
    # $OnFile は Save-FirmwareBuild の中から呼ばれる (変数はこの関数のものが見える)
    $ctxForProgress = $Ctx
    $onFile = {
        param($Index, $Count, $Asset)
        $ctxForProgress.Form.SetProgress($Index, $Count)
        $ctxForProgress.Form.SetStatus(('ダウンロード中 ({0}/{1}): {2}' -f ($Index + 1), $Count, $Asset), $script:FlashUiLevelInfo)
        $ctxForProgress.Form.AppendLog(('  {0}' -f $Asset), $script:FlashUiLevelFaint, $false)
        foreach ($a in @($ctxForProgress.Form.TakeActions())) {
            if ($a -eq 'close') { $ctxForProgress.State.Exit = $true }
            if ($a -eq 'cancel' -or $a -eq 'close') { throw $script:FlashUiCancel }
        }
    }
    try {
        $saved = & $Ctx.Download $k.Repo $build.DownloadTag $assets $onFile
    } catch {
        $f.SetProgress(0, 0)
        if ($_.Exception.Message -eq $script:FlashUiCancel) {
            $s.Phase = 'cancelled'
            $s.Result = 'cancelled'
            $f.SetBanner('中止しました', 'ダウンロードを中止しました。', $script:FlashUiLevelWarn)
            $f.SetStatus('中止しました', $script:FlashUiLevelWarn)
        } else {
            $s.Phase = 'failed'
            $s.Result = 'failed'
            $f.SetBanner('ダウンロードに失敗しました', $_.Exception.Message, $script:FlashUiLevelNg)
            $f.AppendLog(('失敗: {0}' -f $_.Exception.Message), $script:FlashUiLevelNg, $false)
            $f.SetStatus('ダウンロードに失敗しました', $script:FlashUiLevelNg)
        }
        Set-FlashUiRunButtons $Ctx $s.Phase
        return
    }
    $s.Paths = $saved.Paths
    $f.SetProgress(0, 0)
    if ($null -ne $saved.Info) {
        foreach ($key in @('commit', 'built')) {
            if ($saved.Info.ContainsKey($key)) {
                $f.AppendLog(('  {0}: {1}' -f $key, $saved.Info[$key]), $script:FlashUiLevelFaint, $false)
            }
        }
    }
    Start-FlashUiStep $Ctx
}

function Start-FlashUiStep($Ctx) {
    $s = $Ctx.State
    $f = $Ctx.Form
    $step = $s.Steps[$s.Index]
    $title = Get-FlashUiStepTitle $step $s.Index $s.Steps.Count
    $s.Phase = 'run'
    $s.FailText = ''
    $s.LastLine = ''
    $f.SetStepState($s.Index, $script:FlashUiStepActive)
    $f.SetProgress($s.Index, $s.Steps.Count)
    $f.SetBanner(('{0} を書き込みます' -f $title), $step.Prepare, $script:FlashUiLevelInfo)
    $f.AppendLog('', $script:FlashUiLevelInfo, $false)
    $f.AppendLog(('{0} ({1})' -f $title, $step.Asset), $script:FlashUiLevelInfo, $false)
    Set-FlashUiRunButtons $Ctx 'run'
    $command = Get-FlashStepCommand $step $s.Paths[$step.Asset] $Ctx.ToolsDir $Ctx.WaitSeconds
    try {
        $s.Child = & $Ctx.NewChild $command
    } catch {
        $s.Child = $null
        Complete-FlashUiStep $Ctx 1 $false ('書き込みを始められませんでした: {0}' -f $_.Exception.Message)
        return
    }
    $s.StepStart = & $Ctx.Now
}

# 子プロセスの出力を中継し、終わったら次へ進む (メインのループから呼ぶ)
function Update-FlashUiTick($Ctx) {
    $s = $Ctx.State
    if ($s.Phase -ne 'run' -or $null -eq $s.Child) {
        return
    }
    $child = $s.Child
    foreach ($line in @($child.TakeLines())) {
        if ($null -eq $line) { continue }
        $text = [string]$line.Text
        $level = ConvertTo-FlashLogLevel $text ([bool]$line.IsError)
        if ($level -lt 0) { continue }
        $Ctx.Form.AppendLog($text, $level, [bool]$line.Partial)
        if ($level -eq $script:FlashUiLevelNg -and -not $s.FailText) {
            $s.FailText = ($text -replace '^\s*失敗:\s*', '')
        } elseif ($s.FailText -and $text -match '^\s{2,}\S') {
            $s.FailText += "`n" + $text.Trim()
        }
        # 下の欄には、字下げしていない行 (いま何をしているか) を出す。字下げした案内と薄い行は出さない
        if ($text.Trim() -and $text -notmatch '^\s' -and $level -ne $script:FlashUiLevelFaint) {
            $s.LastLine = $text.Trim()
        }
    }
    $elapsed = (& $Ctx.Now) - $s.StepStart
    $Ctx.Form.SetStatus(('{0}  ({1}:{2:00})' -f $s.LastLine, [int][Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds), $script:FlashUiLevelInfo)
    if ($child.HasExited) {
        $exitCode = [int]$child.ExitCode
        $killed = [bool]$child.Killed
        try { $child.Dispose() } catch { }
        $s.Child = $null
        if ($killed) {
            Complete-FlashUiStep $Ctx $exitCode $true ''
        } else {
            Complete-FlashUiStep $Ctx $exitCode $false ''
        }
    }
}

function Complete-FlashUiStep($Ctx, [int]$ExitCode, [bool]$Killed, [string]$Message) {
    $s = $Ctx.State
    $f = $Ctx.Form
    $step = $s.Steps[$s.Index]
    $title = Get-FlashUiStepTitle $step $s.Index $s.Steps.Count
    $next = Get-FlashNextPhase $s.Steps $s.Index $ExitCode $Killed
    if ($next -in @('next', 'pause', 'done')) {
        $f.SetStepState($s.Index, $script:FlashUiStepDone)
        $s.Flashed++
    } else {
        $f.SetStepState($s.Index, $script:FlashUiStepFailed)
    }
    switch ($next) {
        'next' {
            $s.Index++
            Start-FlashUiStep $Ctx
        }
        'pause' {
            $s.Phase = 'pause'
            $f.SetBanner(('{0} を起動させてください' -f $title), ($step.AfterReset + ' 終わったら「続ける」を押してください。'), $script:FlashUiLevelWarn)
            $f.SetStatus('設定リセットの起動を待っています', $script:FlashUiLevelWarn)
            Set-FlashUiRunButtons $Ctx 'pause'
        }
        'done' {
            $s.Phase = 'done'
            $s.Result = 'done'
            $f.SetProgress($s.Steps.Count, $s.Steps.Count)
            $text = @()
            if ($step.AfterReset) { $text += $step.AfterReset }
            $kind = $script:FlashKeyboards[$s.Keyboard].Kind
            if (@($s.Steps | Where-Object { $_.IsReset }).Count -gt 0) {
                $text += '設定リセットでペアリング情報も消えています。PC の Bluetooth 設定から古い登録を削除して、再ペアリングしてください。'
            }
            if ($kind -eq 'keyball') { $text += 'Keyball を KQ-mini に接続し直してください。' }
            if ($kind -eq 'kqmini') { $text += 'KQ-mini の LED が点灯して入力できるようになるまで、数十秒かかることがあります。' }
            $f.SetBanner(('完了: {0} に {1} 個のファームウェアを書き込みました' -f $s.Keyboard, $s.Steps.Count), ($text -join "`n"), $script:FlashUiLevelOk)
            $f.SetStatus('完了', $script:FlashUiLevelOk)
            Set-FlashUiRunButtons $Ctx 'done'
        }
        'cancelled' {
            $s.Phase = 'cancelled'
            $s.Result = 'cancelled'
            $f.SetBanner('中止しました', ('{0} の途中で中止しました。「再試行」でこの手順からやり直せます。' -f $title), $script:FlashUiLevelWarn)
            $f.AppendLog('中止しました。', $script:FlashUiLevelWarn, $false)
            $f.SetStatus('中止しました', $script:FlashUiLevelWarn)
            Set-FlashUiRunButtons $Ctx 'cancelled'
        }
        default {
            $s.Phase = 'failed'
            $s.Result = 'failed'
            $reason = $Message
            if (-not $reason) { $reason = $s.FailText }
            if (-not $reason) { $reason = '終了コード {0} で終わりました。' -f $ExitCode }
            if ($Message) { $f.AppendLog(('失敗: {0}' -f $Message), $script:FlashUiLevelNg, $false) }
            $f.SetBanner(('{0} の書き込みに失敗しました' -f $title), ($reason + "`n「再試行」でこの手順からやり直せます。"), $script:FlashUiLevelNg)
            $f.SetStatus('失敗しました', $script:FlashUiLevelNg)
            Set-FlashUiRunButtons $Ctx 'failed'
        }
    }
}

function Stop-FlashUiChild($Ctx) {
    $child = $Ctx.State.Child
    if ($null -ne $child) {
        try { $child.Kill() } catch { }
    }
}

# ---------------------------------------------------------------------------
# 操作
# ---------------------------------------------------------------------------

# 続けて届いた操作のうち、機種・ビルド・絞り込みの選択は最後のものだけを使う
function Get-FlashUiCoalescedActions($Actions) {
    $list = @($Actions | Where-Object { $null -ne $_ -and [string]$_ -ne '' })
    $last = @{}
    for ($i = 0; $i -lt $list.Count; $i++) {
        $prefix = ([string]$list[$i]).Split(':')[0]
        if ($prefix -in @('keyboard', 'build', 'filter')) {
            $last[$prefix] = $i
        }
    }
    $result = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $list.Count; $i++) {
        $prefix = ([string]$list[$i]).Split(':')[0]
        if ($last.ContainsKey($prefix) -and $last[$prefix] -ne $i) {
            continue
        }
        [void]$result.Add([string]$list[$i])
    }
    return $result.ToArray()
}

function Invoke-FlashUiAction($Ctx, [string]$Action) {
    $s = $Ctx.State
    $parts = $Action.Split([char[]]@(':'), 3)
    $name = $parts[0]
    $arg = ''
    if ($parts.Count -gt 1) { $arg = $parts[1] }
    $arg2 = ''
    if ($parts.Count -gt 2) { $arg2 = $parts[2] }

    if ($name -eq 'close') {
        Stop-FlashUiChild $Ctx
        $s.Exit = $true
        return
    }
    if ($s.Phase -eq 'select') {
        switch ($name) {
            'keyboard' {
                if ($script:FlashKeyboards.Contains($arg) -and $arg -ne $s.Keyboard) {
                    Select-FlashUiKeyboard $Ctx $arg
                }
            }
            'build' {
                if (@($s.Builds | Where-Object { $_.Tag -eq $arg }).Count -gt 0) {
                    $s.Tag = $arg
                    Update-FlashUiPlan $Ctx
                }
            }
            'filter' {
                if ($arg -in @('all', 'pr', 'custom')) {
                    $s.Filter = $arg
                    $visible = @(Select-FirmwareBuilds $s.Builds $s.Filter)
                    if (@($visible | Where-Object { $_.Tag -eq $s.Tag }).Count -eq 0) {
                        $s.Tag = ''
                        if ($visible.Count -gt 0) { $s.Tag = $visible[0].Tag }
                    }
                    Show-FlashUiBuilds $Ctx
                    Update-FlashUiPlan $Ctx
                }
            }
            'option' {
                switch ($arg) {
                    'mode' {
                        if ($script:FlashModes.Contains($arg2) -and $arg2 -ne $s.Mode) {
                            $s.Mode = $arg2
                            Update-FlashUiOptions $Ctx
                        }
                    }
                    'central' { if ($script:FlashCentrals.Contains($arg2)) { $s.Central = $arg2 } }
                    'right' { if ($script:FlashVariants.Contains($arg2)) { $s.Right = $arg2 } }
                    'left' { if ($script:FlashVariants.Contains($arg2)) { $s.Left = $arg2 } }
                    'count' { if ($arg2 -in @('1', '2')) { $s.Count = [int]$arg2 } }
                }
                Update-FlashUiPlan $Ctx
                Save-FlashUiSettings $Ctx
            }
            'refresh' { Update-FlashUiBuilds $Ctx $true }
            'start' { Start-FlashUiRun $Ctx }
        }
        return
    }
    switch ($name) {
        'cancel' {
            if ($s.Phase -eq 'run') {
                Stop-FlashUiChild $Ctx
            } elseif ($s.Phase -eq 'pause') {
                # 設定リセットは書き込み済み。「再試行」は次の手順から
                $s.Index++
                $s.Phase = 'cancelled'
                $s.Result = 'cancelled'
                $Ctx.Form.SetBanner('中止しました', '「再試行」で次の手順から続けられます。', $script:FlashUiLevelWarn)
                $Ctx.Form.SetStatus('中止しました', $script:FlashUiLevelWarn)
                Set-FlashUiRunButtons $Ctx 'cancelled'
            }
        }
        'continue' {
            if ($s.Phase -eq 'pause') {
                $s.Index++
                Start-FlashUiStep $Ctx
            }
        }
        'retry' {
            if ($s.Phase -in @('failed', 'cancelled')) {
                if ($null -eq $s.Paths) {
                    Start-FlashUiRun $Ctx
                } else {
                    Start-FlashUiStep $Ctx
                }
            }
        }
        'back' {
            if ($s.Phase -in @('failed', 'cancelled', 'done')) {
                Show-FlashUiSelect $Ctx
                Update-FlashUiPlan $Ctx
            }
        }
    }
}
