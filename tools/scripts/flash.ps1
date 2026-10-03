<#
.SYNOPSIS
    キーボードにファームウェアを書き込むツールです (ウィンドウで操作します)。
    最新のビルドのほか、PR のビルドや custom の過去のビルドも選べます。

.DESCRIPTION
    機種 (LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa / torabo-tsuki-lp / Keyball39 / KQ-mini) と
    ビルドを選び、画面の案内に従って書き込みます。ビルドは、各リポジトリの CI が置くリリースから選びます。
      最新            firmware-latest (custom ブランチの最新ビルド)
      PR #番号        firmware-pr-<番号> (PR のビルド。PR をマージした状態のコミットをビルドしたもの)
      custom          firmware-custom-<sha7> (custom ブランチの過去のビルド)
    書き込みは手順ごとに flash-uf2.ps1 / flash-keyball.ps1 を別のプロセスで実行し、その出力を
    ウィンドウのログに表示します。

    .uf2 / .hex を指定すると、ウィンドウを出さずに、そのファイルだけを書き込みます
    (.uf2 は flash-uf2.ps1、.hex は flash-keyball.ps1)。

.PARAMETER Path
    書き込む .uf2 / .hex ファイル。指定すると、ウィンドウを出さずにこのファイルだけを書き込みます。

.PARAMETER Keyboard
    最初に選んでおく機種。省略すると、前回選んだ機種。

.PARAMETER WaitSeconds
    1 回の書き込みで、ブートローダが現れるまで待つ秒数。ウィンドウの「中止」で、いつでも止められます。

.PARAMETER List
    ウィンドウを出さずに、-Keyboard の機種のビルドの一覧を表示します。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash.ps1 -Keyboard Keyball39

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash.ps1 -Keyboard LisM -List
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [ValidateSet('LisM', 'AroundFortyRB', 'KUKEY42', 'Pyuron', 'roBa', 'torabo-tsuki-lp', 'Keyball39', 'KQ-mini')]
    [string]$Keyboard,

    [ValidateRange(10, 3600)]
    [int]$WaitSeconds = 600,

    [switch]$List
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# このスクリプトは tools\scripts にある。lib・expected・.cache は tools の下
$TOOLS_DIR = Split-Path -Parent $PSScriptRoot
. (Join-Path $TOOLS_DIR 'lib\firmware-release.ps1')
. (Join-Path $TOOLS_DIR 'lib\flash-plan.ps1')
. (Join-Path $TOOLS_DIR 'lib\flash-ui.ps1')

$CACHE_DIR = Join-Path $TOOLS_DIR '.cache'
$FIRMWARE_DIR = Join-Path $CACHE_DIR 'firmware'
$SETTINGS_FILE = Join-Path $CACHE_DIR 'flash-settings.json'

function Stop-WithError([string]$Message) {
    Write-Host ''
    Write-Host "失敗: $Message" -ForegroundColor Red
    exit 1
}

# 前回の選択 (機種・LisM の版・Keyball の台数)。読めなければ空
function Read-FlashSettings {
    $settings = @{}
    if (-not (Test-Path -LiteralPath $SETTINGS_FILE)) {
        return $settings
    }
    try {
        $json = ConvertFrom-Json ([System.IO.File]::ReadAllText($SETTINGS_FILE, [System.Text.Encoding]::UTF8))
        foreach ($name in @('Keyboard', 'LismRight', 'LismLeft', 'KeyballCount')) {
            $value = Get-FirmwareProp $json $name
            if ($null -ne $value) {
                $settings[$name] = [string]$value
            }
        }
    } catch {
        # 壊れていたら使わない
    }
    return $settings
}

function Save-FlashSettings([hashtable]$Settings) {
    [void](New-Item -ItemType Directory -Force -Path $CACHE_DIR)
    $text = ConvertTo-Json ([pscustomobject]$Settings)
    [System.IO.File]::WriteAllText($SETTINGS_FILE, $text, (New-Object System.Text.UTF8Encoding $false))
}

# ---------------------------------------------------------------------------
# ファイルが指定されたら、そのファイルだけを書き込む
# ---------------------------------------------------------------------------
if ($Path) {
    if ([System.IO.Path]::GetExtension($Path) -eq '.hex') {
        & (Join-Path $PSScriptRoot 'flash-keyball.ps1') -Path $Path
    } else {
        # どのボード用かは flash-uf2.ps1 が .uf2 の中身 (ファミリ ID と書き込み先アドレス) で判定する
        & (Join-Path $PSScriptRoot 'flash-uf2.ps1') -Path $Path -Target nRF52840, BMP, RP2040
    }
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# ビルドの一覧をコンソールに表示する
# ---------------------------------------------------------------------------
if ($List) {
    if (-not $Keyboard) {
        Stop-WithError '-List には -Keyboard も指定してください。'
    }
    $repo = $script:FlashKeyboards[$Keyboard].Repo
    Write-Host "ビルドの一覧: $repo"
    $result = Get-FirmwareBuildList -Repo $repo -CacheDir $FIRMWARE_DIR
    if ($result.Message) {
        Write-Host $result.Message -ForegroundColor Yellow
    }
    foreach ($b in (Select-FirmwareBuilds $result.Builds 'all')) {
        $label = Format-FirmwareBuildLabel $b
        $state = ''
        if ($label.StateText) {
            $state = ' [{0}]' -f $label.StateText
        }
        Write-Host ''
        Write-Host ('{0}{1}  {2}' -f $label.Badge, $state, $label.Title) -ForegroundColor Cyan
        Write-Host ('  {0}' -f $label.Detail)
        Write-Host ('  タグ: {0}' -f $b.Tag) -ForegroundColor DarkGray
    }
    exit 0
}

# ---------------------------------------------------------------------------
# ウィンドウを開く
# ---------------------------------------------------------------------------
if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    Stop-WithError 'ウィンドウは Windows でしか開けません (-List と、ファイルの指定は使えます)。'
}
. (Join-Path $TOOLS_DIR 'lib\keyboard-check\rawhid.ps1')
. (Join-Path $TOOLS_DIR 'lib\keyboard-check\input-test.ps1')
try {
    Import-KcInputForm
    Import-KcCSharp 'ChildProcess.cs' 'KcChildProcess'
} catch {
    Stop-WithError "ウィンドウを用意できませんでした: $($_.Exception.Message)"
}

$hostExe = (Get-Process -Id $PID).Path
$settings = Read-FlashSettings
$form = [KcFlashForm]::Launch('ファームウェアの書き込み')
$consoleMode = [KcConsoleMode]::DisableQuickEdit()
Write-Host 'ファームウェアの書き込みツールのウィンドウを開きました。'
Write-Host '書き込みが終わるまで、この画面は閉じないでください (閉じると書き込みも止まります)。'

$ctx = New-FlashUiContext -Form $form -ToolsDir $TOOLS_DIR -WaitSeconds $WaitSeconds -Settings $settings `
    -GetBuilds { param($Repo) Get-FirmwareBuildList -Repo $Repo -CacheDir $FIRMWARE_DIR } `
    -Download { param($Repo, $Tag, $Assets, $OnFile) Save-FirmwareBuild -Repo $Repo -Tag $Tag -Assets $Assets -OutDir $FIRMWARE_DIR -OnFile $OnFile -Quiet } `
    -NewChild {
        param($Command)
        $arguments = '-NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -EncodedCommand ' + (ConvertTo-FlashEncodedCommand $Command)
        [KcChildProcess]::Start($hostExe, $arguments, $TOOLS_DIR, 65001)
    } `
    -SaveSettings { param($Settings) Save-FlashSettings $Settings }

$errors = 0
try {
    Initialize-FlashUi $ctx $Keyboard
    while (-not $ctx.State.Exit) {
        try {
            foreach ($action in (Get-FlashUiCoalescedActions $form.TakeActions())) {
                Invoke-FlashUiAction $ctx $action
                if ($ctx.State.Exit) {
                    break
                }
            }
            Update-FlashUiTick $ctx
        } catch {
            # 想定していないエラー: ウィンドウに出して続ける (書き込み中なら止める)
            $errors++
            $form.AppendLog(('失敗: {0}' -f $_.Exception.Message), $script:FlashUiLevelNg, $false)
            $form.SetStatus('エラーが起きました (ログを見てください)', $script:FlashUiLevelNg)
            if ($ctx.State.Phase -eq 'run') {
                Stop-FlashUiChild $ctx
            }
            if ($errors -ge 20) {
                throw
            }
        }
        Start-Sleep -Milliseconds 80
    }
} finally {
    Stop-FlashUiChild $ctx
    if ($null -ne $ctx.State.Child) {
        try { $ctx.State.Child.Dispose() } catch { }
    }
    $form.RequestClose()
    [void]$form.WaitClosed(3000)
    [KcConsoleMode]::Restore($consoleMode)
    try { $Host.UI.RawUI.FlushInputBuffer() } catch { }
}

Write-Host ''
switch ($ctx.State.Result) {
    'done' {
        Write-Host ('完了: {0} に {1} 個のファームウェアを書き込みました。' -f $ctx.State.Keyboard, $ctx.State.Flashed) -ForegroundColor Green
        exit 0
    }
    'failed' {
        Write-Host '失敗: 書き込みが終わらないまま閉じました。' -ForegroundColor Red
        exit 1
    }
    'cancelled' {
        Write-Host '中止しました。' -ForegroundColor Yellow
        exit 1
    }
    default {
        Write-Host '書き込みツールを閉じました。'
        exit 0
    }
}
