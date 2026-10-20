<#
.SYNOPSIS
    実機なしのキーボードシミュレータを Windows の画面で操作します。
.DESCRIPTION
    機種とシナリオを選び、既存のシミュレータで期待値を検証します。
    入力、期待値、実際の出力と、指定した時刻のキーの押下状態を表示します。
    実行中は中止でき、JSON/JUnit レポートは tools/.cache/simulator/gui に残します。
.PARAMETER Scenario
    最初に開くシナリオ JSON またはフォルダ。省略時は標準シナリオです。
.PARAMETER Board
    最初に選択する機種 ID。
.PARAMETER Python
    モデルを読み込む Python 3.10 以上のコマンド名またはパス。
.PARAMETER NoConsole
    コンソールが見えない状態で起動したことを伝えます (tools\keyboard-sim.cmd が付けます)。
    画面を開けなかったときなどの失敗を、メッセージボックスでも出します。
    コンソールを隠すスイッチではありません (隠すのは .cmd が使う conhost.exe --headless です)。
.EXAMPLE
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File tools/scripts/keyboard-sim-gui.ps1
.EXAMPLE
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File tools/scripts/keyboard-sim-gui.ps1 -Board lism
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Scenario = '',
    [string]$Board = '',
    [string]$Python = 'python',
    [switch]$NoConsole
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# -NoConsole: ウィンドウ用の .cmd が、headless の conhost (見えないコンソール) で起動したとき。
# コンソールの文字は誰にも見えないので、起動できなかった理由などの失敗はメッセージボックスでも出す
function Show-NoConsoleError([string]$Message) {
    if (-not $NoConsole) {
        return
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($Message, 'キーボードシミュレータ',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1, [System.Windows.Forms.MessageBoxOptions]::DefaultDesktopOnly)
    } catch {
        # メッセージボックスも出せなければ、何もできない
    }
}

# どこで止まっても (読み込み・ウィンドウを開く・ループの中)、-NoConsole なら理由を見せてから終える
trap {
    if ($NoConsole) {
        Show-NoConsoleError ('失敗: {0}' -f $_.Exception.Message)
        exit 1
    }
    break
}

# Windows PowerShell 5.1 を -File で起動すると (keyboard-sim.cmd)、param の既定値の中では $PSScriptRoot が空なので、ここで決める
if (-not $Scenario) {
    $Scenario = Join-Path $PSScriptRoot '../simulator/scenarios'
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    Write-Host '失敗: GUI は Windows 専用です。画面なしの実行には tools/scripts/keyboard-sim.ps1 を使ってください。' -ForegroundColor Red
    exit 1
}

$toolsDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $toolsDir 'lib/keyboard-check/keyboard-sim.ps1')
. (Join-Path $toolsDir 'lib/keyboard-check/keyboard-sim-ui.ps1')
. (Join-Path $toolsDir 'lib/keyboard-check/rawhid.ps1')
. (Join-Path $toolsDir 'lib/keyboard-check/input-test.ps1')

$form = $null
$ctx = $null
$consoleMode = $null
$exitCode = 0
try {
    Import-KcInputForm
    Import-KcCSharp 'ChildProcess.cs' 'KcChildProcess'
    $hostExe = (Get-Process -Id $PID).Path
    $cliPath = Join-Path $PSScriptRoot 'keyboard-sim.ps1'
    $form = [KcSimulatorForm]::Launch('キーボードシミュレータ')
    $consoleMode = [KcConsoleMode]::DisableQuickEdit()
    $labels = [ordered]@{
        TitleText = 'キーボードシミュレータ'
        SubtitleText = '機種とシナリオを選び、キー・レイヤー・マウスの出力を確認します。'
        BoardsCaption = '機種'
        ScenariosCaption = 'シナリオ'
        PictureCaption = '入力したキーの位置'
        ReplayCaption = '入力と出力を時刻で確認'
        InputsCaption = '入力'
        ExpectedCaption = '期待値'
        ActualCaption = '実際の出力'
        LogCaption = '実行ログ'
        OpenButton = 'JSON を開く'
        StandardButton = '標準に戻す'
        ReportButton = 'レポート'
        RunButton = '選択を実行'
        RunAllButton = 'この機種を全件実行'
        CancelButton = '中止'
        CloseButton = '閉じる'
        PlayButton = '再生 / 一時停止'
    }
    $form.SetLabels([string[]]@($labels.Keys), [string[]]@($labels.Values))
    $ctx = New-KcSimUiContext -Form $form -ScenarioPath $Scenario -Python $Python -ToolsDir $toolsDir `
        -CacheDir (Join-Path $toolsDir '.cache/simulator/gui') `
        -NewChild {
            param($InputFile, $ReportFile, $JUnitFile, $PythonCommand)
            $command = New-KcSimUiChildCommand -ScriptPath $cliPath -InputFile $InputFile `
                -ReportFile $ReportFile -JUnitFile $JUnitFile -Python $PythonCommand
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
            $arguments = '-NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
            [KcChildProcess]::Start($hostExe, $arguments, $toolsDir, 65001)
        } `
        -OpenReport { param($Path) Invoke-Item -LiteralPath $Path }
    Initialize-KcSimUi $ctx
    if ($Board) { Invoke-KcSimUiAction $ctx ('board:' + $Board) }
    if (-not $NoConsole) {
        Write-Host 'シミュレータの画面を開きました。この画面を閉じると実行中の検証も終了します。'
    }
    while (-not $ctx.State.Exit -and -not $form.IsClosed) {
        try {
            foreach ($action in $form.TakeActions()) {
                Invoke-KcSimUiAction $ctx $action
                if ($ctx.State.Exit) { break }
            }
            if (-not $ctx.State.Exit) { Update-KcSimUi $ctx }
        } catch {
            Stop-KcSimUi $ctx
            $form.SetBusy($false, $true)
            $form.SetSummary('処理に失敗しました', $_.Exception.Message, 2)
            $form.AppendLog($_.Exception.Message)
        }
        Start-Sleep -Milliseconds 50
    }
} catch {
    Write-Host ('失敗: シミュレータの画面を開けません: ' + $_.Exception.Message) -ForegroundColor Red
    Show-NoConsoleError ('失敗: シミュレータの画面を開けません: ' + $_.Exception.Message)
    $exitCode = 1
} finally {
    if ($null -ne $ctx) { Stop-KcSimUi $ctx }
    if ($null -ne $form) {
        $form.RequestClose()
        [void]$form.WaitClosed(3000)
        $form.Dispose()
    }
    if ($null -ne $consoleMode) { [KcConsoleMode]::Restore($consoleMode) }
}
exit $exitCode
