<#
.SYNOPSIS
    ZMK キーボード (LisM / AroundFortyRB / KUKEY42 / Pyuron) に最新のファームウェアを書き込みます。

.DESCRIPTION
    各キーボードのリポジトリの firmware-latest リリース (custom ブランチの最新ビルド) から必要な .uf2 を
    ダウンロードし、右手側 (セントラル) → 左手側 (ペリフェラル) の順に flash-uf2.ps1 で書き込みます。

    引数を付けずに実行すると、機種と書き込む内容をメニューで選びます。
    -Keyboard と -Mode を指定すると、メニューを出さずにすぐ書き込みます。

    .uf2 ファイルを指定した場合は、ダウンロードせずにそのファイルだけを書き込みます。

.PARAMETER Path
    書き込む .uf2 ファイル。指定するとメニューやダウンロードをせず、このファイルだけを書き込みます。

.PARAMETER Keyboard
    機種 (LisM / AroundFortyRB / KUKEY42 / Pyuron)。

.PARAMETER Mode
    書き込む内容。
      Both      : 右 → 左
      ResetBoth : 設定リセットしてから左右 (右: settings_reset → 本体、左: settings_reset → 本体)
      Right     : 右だけ
      Left      : 左だけ
      ResetOnly : 設定リセットだけ (右 → 左)

.PARAMETER Studio
    右手側 (セントラル) に ZMK Studio 対応版を書き込みます。

.PARAMETER LeftVariant
    LisM の左手側の版 (trackball / non_trackball)。

.PARAMETER RightVariant
    LisM の右手側の版 (trackball / non_trackball)。

.PARAMETER WaitSeconds
    1 回の書き込みごとに、ブートローダのドライブが現れるまで待つ秒数。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-zmk.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-zmk.ps1 -Keyboard LisM -Mode ResetBoth

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-zmk.ps1 -Keyboard Pyuron -Mode Right -Studio
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [ValidateSet('LisM', 'AroundFortyRB', 'KUKEY42', 'Pyuron')]
    [string]$Keyboard,

    [ValidateSet('Both', 'ResetBoth', 'Right', 'Left', 'ResetOnly')]
    [string]$Mode,

    [switch]$Studio,

    [ValidateSet('trackball', 'non_trackball')]
    [string]$LeftVariant,

    [ValidateSet('trackball', 'non_trackball')]
    [string]$RightVariant,

    [int]$WaitSeconds = 120
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\firmware-latest.ps1')

# ---------------------------------------------------------------------------
# 機種ごとの設定と既定値
# ---------------------------------------------------------------------------
# Right / Left は build.yaml の artifact-name。{v} は LisM のトラックボール有無 (trackball / non_trackball)。
# セントラルの ZMK Studio 対応版は、Right の後ろに _studio が付く。
$KEYBOARDS = [ordered]@{
    LisM          = @{ Repo = 'ryo-aoki-pc/zmk-config-LisM'; Right = 'lism_right_central_{v}'; Left = 'lism_left_peripheral_{v}' }
    AroundFortyRB = @{ Repo = 'ryo-aoki-pc/zmk-config-AroundFortyRB'; Right = 'AroundForty-RB_right_central'; Left = 'AroundForty-RB_left_peripheral' }
    KUKEY42       = @{ Repo = 'ryo-aoki-pc/zmk-config-KUKEY42'; Right = 'KUKEY42_right_central'; Left = 'KUKEY42_left_peripheral' }
    Pyuron        = @{ Repo = 'ryo-aoki-pc/zmk-config-Pyuron'; Right = 'Pyuron_right_central'; Left = 'Pyuron_left_peripheral' }
}
$SETTINGS_RESET = 'settings_reset-seeeduino_xiao_ble-zmk'

# 既定値 (メニューの確認画面で切り替えられる)
$DEFAULT_STUDIO = $false               # セントラルに ZMK Studio 対応版を書くか
$DEFAULT_LISM_RIGHT = 'trackball'      # LisM 右手側: trackball / non_trackball
$DEFAULT_LISM_LEFT = 'trackball'       # LisM 左手側: trackball / non_trackball

$MODES = [ordered]@{
    Both      = '左右に書き込む (右 → 左)'
    ResetBoth = '設定リセットしてから左右に書き込む (ペアリング情報も消えます)'
    Right     = '右手側 (セントラル) だけ'
    Left      = '左手側 (ペリフェラル) だけ'
    ResetOnly = '設定リセットだけ (右 → 左)'
}

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

# 番号で選ばせる。Enter だけなら $Default を返す ($Default が無ければ聞き直す)。
function Select-Item([string]$Title, [string[]]$Keys, [string[]]$Labels, [string]$Default) {
    Write-Host ''
    Write-Host $Title
    for ($i = 0; $i -lt $Keys.Length; $i++) {
        $mark = if ($Keys[$i] -eq $Default) { ' (Enter)' } else { '' }
        Write-Host ("  {0}. {1}{2}" -f ($i + 1), $Labels[$i], $mark)
    }
    while ($true) {
        $answer = Read-Answer '番号'
        if ($answer -eq '' -and $Default) { return $Default }
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Keys.Length) {
            return $Keys[$n - 1]
        }
        Write-Host "  1 から $($Keys.Length) の番号を入力してください。" -ForegroundColor Yellow
    }
}

function Get-FlashPlan($Config, [string]$StepMode, [bool]$UseStudio, [string]$Right, [string]$Left) {
    $centralName = $Config.Right.Replace('{v}', $Right)
    if ($UseStudio) { $centralName += '_studio' }
    $peripheralName = $Config.Left.Replace('{v}', $Left)

    $rightReset = [pscustomobject]@{ Side = '右手側'; What = '設定リセット'; Asset = "$SETTINGS_RESET.uf2" }
    $rightMain = [pscustomobject]@{ Side = '右手側'; What = 'セントラル'; Asset = "$centralName.uf2" }
    $leftReset = [pscustomobject]@{ Side = '左手側'; What = '設定リセット'; Asset = "$SETTINGS_RESET.uf2" }
    $leftMain = [pscustomobject]@{ Side = '左手側'; What = 'ペリフェラル'; Asset = "$peripheralName.uf2" }

    switch ($StepMode) {
        'Both' { return @($rightMain, $leftMain) }
        'ResetBoth' { return @($rightReset, $rightMain, $leftReset, $leftMain) }
        'Right' { return @($rightMain) }
        'Left' { return @($leftMain) }
        'ResetOnly' { return @($rightReset, $leftReset) }
    }
}

function Show-FlashPlan($Steps) {
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $s = $Steps[$i]
        Write-Host ("  [{0}/{1}] {2} ({3}): {4}" -f ($i + 1), $Steps.Count, $s.Side, $s.What, $s.Asset)
    }
}

function Switch-Variant([string]$Value) {
    if ($Value -eq 'trackball') { return 'non_trackball' }
    return 'trackball'
}

# ---------------------------------------------------------------------------
# .uf2 が指定されたら、そのファイルだけを書き込む
# ---------------------------------------------------------------------------
if ($Path) {
    & $FLASH_UF2 -Path $Path -Target nRF52840 -WaitSeconds $WaitSeconds
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# 1. 機種と書き込む内容を決める
# ---------------------------------------------------------------------------
$interactive = -not ($Keyboard -and $Mode)
if ($interactive) {
    Write-Host 'ZMK キーボードに最新のファームウェアを書き込みます。'
}
if (-not $Keyboard) {
    $keys = @($KEYBOARDS.Keys)
    $Keyboard = Select-Item '機種を選んでください:' $keys $keys ''
}
if (-not $Mode) {
    $Mode = Select-Item '書き込む内容を選んでください:' @($MODES.Keys) @($MODES.Values) 'Both'
}

$config = $KEYBOARDS[$Keyboard]
$hasVariants = $config.Right.Contains('{v}')
if (-not $hasVariants -and ($LeftVariant -or $RightVariant)) {
    Write-Warning "$Keyboard にはトラックボールの有無による版が無いため、-LeftVariant / -RightVariant は無視します。"
}
$useStudio = $DEFAULT_STUDIO -or [bool]$Studio
$right = if ($RightVariant) { $RightVariant } else { $DEFAULT_LISM_RIGHT }
$left = if ($LeftVariant) { $LeftVariant } else { $DEFAULT_LISM_LEFT }

$hasCentral = $Mode -in @('Both', 'ResetBoth', 'Right')
$hasPeripheral = $Mode -in @('Both', 'ResetBoth', 'Left')
while ($true) {
    $steps = @(Get-FlashPlan $config $Mode $useStudio $right $left)
    Write-Host ''
    Write-Host "書き込む内容: $Keyboard ($($config.Repo) の firmware-latest)"
    Show-FlashPlan $steps
    if (-not $interactive) { break }

    $options = @('Enter: 開始')
    if ($hasCentral) {
        $options += if ($useStudio) { 's: 通常版に切り替え' } else { 's: ZMK Studio 対応版に切り替え' }
    }
    if ($hasVariants -and $hasCentral) { $options += 'r: 右のトラックボール有無を切り替え' }
    if ($hasVariants -and $hasPeripheral) { $options += 'l: 左のトラックボール有無を切り替え' }
    $options += 'q: 中止'
    Write-Host ''
    Write-Host ($options -join ' / ')
    $answer = (Read-Answer '選択').ToLowerInvariant()
    if ($answer -eq '') { break }
    elseif ($answer -eq 'q') { Write-Host '中止しました。'; exit 1 }
    elseif ($answer -eq 's' -and $hasCentral) { $useStudio = -not $useStudio }
    elseif ($answer -eq 'r' -and $hasVariants -and $hasCentral) { $right = Switch-Variant $right }
    elseif ($answer -eq 'l' -and $hasVariants -and $hasPeripheral) { $left = Switch-Variant $left }
    else { Write-Host '  表示されている文字を入力してください。' -ForegroundColor Yellow }
}

# ---------------------------------------------------------------------------
# 2. 必要なファイルを先にすべてダウンロードする (途中で通信に失敗して片側だけ書かれるのを避ける)
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "最新のファームウェアをダウンロードしています: $($config.Repo) (firmware-latest)"
$paths = @{}
try {
    foreach ($asset in @($steps | ForEach-Object { $_.Asset } | Select-Object -Unique)) {
        $paths[$asset] = Get-FirmwareLatest -Repo $config.Repo -Asset $asset -OutDir $CACHE_DIR -Quiet
    }
} catch {
    Stop-WithError $_.Exception.Message
}
Show-FirmwareBuildInfo -Repo $config.Repo -OutDir $CACHE_DIR

# ---------------------------------------------------------------------------
# 3. 1 つずつ書き込む
# ---------------------------------------------------------------------------
for ($i = 0; $i -lt $steps.Count; $i++) {
    $s = $steps[$i]
    Write-Host ''
    Write-Host ("[{0}/{1}] {2}に{3}を書き込みます: {4}" -f ($i + 1), $steps.Count, $s.Side, $s.What, $s.Asset) -ForegroundColor Cyan
    Write-Host "  $($s.Side)の XIAO をブートローダにしてください (もう片側には触れないでください)。"
    & $FLASH_UF2 -Path $paths[$s.Asset] -Target nRF52840 -WaitSeconds $WaitSeconds
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host "$($i + 1) 番目で中断しました。残りは次のとおりです:" -ForegroundColor Yellow
        for ($j = $i; $j -lt $steps.Count; $j++) {
            Write-Host ("  {0} ({1}): {2}" -f $steps[$j].Side, $steps[$j].What, $paths[$steps[$j].Asset])
        }
        Write-Host '  もう一度このスクリプトを実行するか、上のファイルを tools\flash-uf2.cmd にドラッグ＆ドロップして書き込んでください。'
        exit 1
    }
}

Write-Host ''
Write-Host "完了: $Keyboard に $($steps.Count) 個のファームウェアを書き込みました。" -ForegroundColor Green
if (@($steps | Where-Object { $_.What -eq '設定リセット' }).Count -gt 0) {
    Write-Host '  設定リセットでペアリング情報も消えています。PC の Bluetooth 設定から古い登録を削除して、再ペアリングしてください。'
}
exit 0
