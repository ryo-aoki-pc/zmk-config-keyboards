<#
.SYNOPSIS
    ZMK キーボード (LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa / torabo-tsuki-lp) にファームウェアを書き込みます。

.DESCRIPTION
    -Keyboard と -Mode を指定すると、ウィンドウを出さずにコンソールで書き込みます。各キーボードの
    リポジトリのリリース (既定は firmware-latest。-Tag / -Pr で PR や過去のビルド) から必要な .uf2 を
    ダウンロードし、右手側 (セントラル) → 左手側 (ペリフェラル) の順に flash-uf2.ps1 で書き込みます。
    torabo-tsuki-lp (BLE Micro Pro Boost) は、電源スイッチの操作も案内します。

    -Keyboard と -Mode のどちらかを省くと、書き込みツールのウィンドウ (flash.ps1) を開きます。

    .uf2 ファイルを指定した場合は、ダウンロードせずにそのファイルだけを書き込みます。

.PARAMETER Path
    書き込む .uf2 ファイル。指定するとダウンロードせず、このファイルだけを書き込みます。

.PARAMETER Keyboard
    機種 (LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa / torabo-tsuki-lp)。

.PARAMETER Mode
    書き込む内容。
      Both      : 右 → 左
      ResetBoth : 設定リセットしてから左右 (右: settings_reset → 本体、左: settings_reset → 本体)
      Right     : 右だけ
      Left      : 左だけ
      ResetOnly : 設定リセットだけ (右 → 左)

.PARAMETER Studio
    右手側 (セントラル) に ZMK Studio 対応版を書き込みます。

.PARAMETER Logging
    右手側 (セントラル) にログ版 (USB の COM ポートにデバッグログを出す版。tools/keyboard-check.cmd の
    「レイヤーの動きを見る」用) を書き込みます。-Studio とは一緒に使えません。

.PARAMETER LeftVariant
    LisM の左手側の版 (trackball / non_trackball)。既定は trackball。

.PARAMETER RightVariant
    LisM の右手側の版 (trackball / non_trackball)。既定は trackball。

.PARAMETER Tag
    ダウンロードするリリースのタグ (例: firmware-custom-1a2b3c4)。既定は firmware-latest (custom の最新)。
    選べるタグは flash.ps1 -Keyboard <機種> -List で表示できます。

.PARAMETER Pr
    PR のビルド (firmware-pr-<番号>) を書き込みます。-Tag とは一緒に使えません。

.PARAMETER WaitSeconds
    1 回の書き込みごとに、ブートローダのドライブが現れるまで待つ秒数。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-zmk.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-zmk.ps1 -Keyboard LisM -Mode ResetBoth

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-zmk.ps1 -Keyboard Pyuron -Mode Right -Studio

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-zmk.ps1 -Keyboard LisM -Mode Both -Pr 27
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [ValidateSet('LisM', 'AroundFortyRB', 'KUKEY42', 'Pyuron', 'roBa', 'torabo-tsuki-lp')]
    [string]$Keyboard,

    [ValidateSet('Both', 'ResetBoth', 'Right', 'Left', 'ResetOnly')]
    [string]$Mode,

    [switch]$Studio,

    [switch]$Logging,

    [ValidateSet('trackball', 'non_trackball')]
    [string]$LeftVariant = 'trackball',

    [ValidateSet('trackball', 'non_trackball')]
    [string]$RightVariant = 'trackball',

    [string]$Tag,

    [int]$Pr = 0,

    [int]$WaitSeconds = 120
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\firmware-release.ps1')
. (Join-Path $PSScriptRoot 'lib\flash-plan.ps1')

$FLASH_UF2 = Join-Path $PSScriptRoot 'flash-uf2.ps1'
$CACHE_DIR = Join-Path $PSScriptRoot '.cache\firmware'

function Stop-WithError([string]$Message) {
    Write-Host ''
    Write-Host "失敗: $Message" -ForegroundColor Red
    exit 1
}

function Read-Answer([string]$Prompt) {
    $answer = Read-Host $Prompt
    if ($null -eq $answer) { Stop-WithError '入力がありません。' }
    return $answer.Trim()
}

function Show-FlashPlan($Steps) {
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $s = $Steps[$i]
        Write-Host ("  [{0}/{1}] {2} ({3}): {4}" -f ($i + 1), $Steps.Count, $s.Side, $s.What, $s.Asset)
    }
}

# ---------------------------------------------------------------------------
# .uf2 が指定されたら、そのファイルだけを書き込む
# ---------------------------------------------------------------------------
if ($Path) {
    # XIAO 用か BMP 用かは flash-uf2.ps1 が書き込み先アドレスで判定する
    & $FLASH_UF2 -Path $Path -Target nRF52840, BMP -WaitSeconds $WaitSeconds
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# 機種と書き込む内容が決まっていなければ、書き込みツールのウィンドウを開く
# ---------------------------------------------------------------------------
if (-not ($Keyboard -and $Mode)) {
    $guiArgs = @{}
    if ($Keyboard) {
        $guiArgs['Keyboard'] = $Keyboard
    }
    & (Join-Path $PSScriptRoot 'flash.ps1') @guiArgs
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# 1. 書き込む内容を決める
# ---------------------------------------------------------------------------
if ($Studio -and $Logging) {
    Stop-WithError '-Studio と -Logging は一緒に使えません。'
}
try {
    $releaseTag = Get-FirmwareTag $Tag $Pr
} catch {
    Stop-WithError $_.Exception.Message
}
$config = $script:FlashKeyboards[$Keyboard]
$mcu = $script:FlashMcus[$config.Mcu]
if (-not (Test-FlashHasVariants $Keyboard) -and ($PSBoundParameters.ContainsKey('LeftVariant') -or $PSBoundParameters.ContainsKey('RightVariant'))) {
    Write-Warning "$Keyboard にはトラックボールの有無による版が無いため、-LeftVariant / -RightVariant は無視します。"
}
$central = ''
if ($Studio) { $central = 'studio' }
if ($Logging) { $central = 'logging' }
$steps = @(Get-FlashPlan -Keyboard $Keyboard -Mode $Mode -Central $central -Right $RightVariant -Left $LeftVariant)

Write-Host ''
Write-Host "書き込む内容: $Keyboard ($($config.Repo) の $releaseTag)"
Show-FlashPlan $steps

# ---------------------------------------------------------------------------
# 2. 必要なファイルを先にすべてダウンロードする (途中で通信に失敗して片側だけ書かれるのを避ける)
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "ファームウェアをダウンロードしています: $($config.Repo) ($releaseTag)"
try {
    $saved = Save-FirmwareBuild -Repo $config.Repo -Tag $releaseTag -Assets @($steps | ForEach-Object { $_.Asset }) -OutDir $CACHE_DIR
} catch {
    Stop-WithError $_.Exception.Message
}
$paths = $saved.Paths
Show-FirmwareBuildInfo $saved.Info

# ---------------------------------------------------------------------------
# 3. 1 つずつ書き込む
# ---------------------------------------------------------------------------
for ($i = 0; $i -lt $steps.Count; $i++) {
    $s = $steps[$i]
    Write-Host ''
    Write-Host ("[{0}/{1}] {2}に{3}を書き込みます: {4}" -f ($i + 1), $steps.Count, $s.Side, $s.What, $s.Asset) -ForegroundColor Cyan
    Write-Host ('  ' + $s.Prepare)
    & $FLASH_UF2 -Path $paths[$s.Asset] -Target $s.Target -WaitSeconds $WaitSeconds
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host "$($i + 1) 番目で中断しました。残りは次のとおりです:" -ForegroundColor Yellow
        for ($j = $i; $j -lt $steps.Count; $j++) {
            Write-Host ("  {0} ({1}): {2}" -f $steps[$j].Side, $steps[$j].What, $paths[$steps[$j].Asset])
        }
        Write-Host '  もう一度このスクリプトを実行するか、上のファイルを tools\flash-uf2.cmd にドラッグ＆ドロップして書き込んでください。'
        exit 1
    }
    # BMP の設定リセットは、書き込んだあとに一度起動させないと動かない
    if ($s.AfterReset) {
        Write-Host ''
        Write-Host ('  ' + $s.AfterReset) -ForegroundColor Yellow
        if ($s.Pause) {
            $null = Read-Answer '  終わったら Enter'
        }
    }
}

Write-Host ''
Write-Host "完了: $Keyboard に $($steps.Count) 個のファームウェアを書き込みました。" -ForegroundColor Green
if (@($steps | Where-Object { $_.IsReset }).Count -gt 0) {
    Write-Host '  設定リセットでペアリング情報も消えています。PC の Bluetooth 設定から古い登録を削除して、再ペアリングしてください。'
}
exit 0
