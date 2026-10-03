<#
.SYNOPSIS
    Keyboard Quantizer Mini (vial-qmk-kq-mini) にファームウェアを書き込みます。

.DESCRIPTION
    .uf2 を指定しなければ、vial-qmk-kq-mini のリリース (既定は firmware-latest = custom ブランチの
    最新ビルド。-Tag / -Pr で PR や過去のビルド) をダウンロードして書き込みます。書き込みは
    flash-uf2.ps1 が行い、KQ-mini はシリアルポート経由で自動的にブートローダに切り替えます。

    tools\scripts\flash-kq-mini.cmd をダブルクリックすると、KQ-mini を選んだ状態で書き込みツールのウィンドウ (flash.ps1) が開きます。

.PARAMETER Path
    書き込む .uf2 ファイル。省略すると最新のファームウェアをダウンロードします。

.PARAMETER Drive
    ブートローダのドライブ (例: E:)。省略時は自動で検出します。

.PARAMETER Tag
    ダウンロードするリリースのタグ (例: firmware-custom-1a2b3c4)。既定は firmware-latest (custom の最新)。
    選べるタグは flash.ps1 -Keyboard KQ-mini -List で表示できます。

.PARAMETER Pr
    PR のビルド (firmware-pr-<番号>) を書き込みます。-Tag とは一緒に使えません。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash-kq-mini.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash-kq-mini.ps1 sekigon_keyboard_quantizer_mini_vial.uf2
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [Parameter(Position = 1)]
    [string]$Drive,

    [string]$Tag,

    [int]$Pr = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# このスクリプトは tools\scripts にある。lib・expected・.cache は tools の下
$TOOLS_DIR = Split-Path -Parent $PSScriptRoot
. (Join-Path $TOOLS_DIR 'lib\firmware-release.ps1')
. (Join-Path $TOOLS_DIR 'lib\flash-plan.ps1')

if (-not $Path) {
    try {
        $kqmini = $script:FlashKeyboards['KQ-mini']
        $Path = Get-FirmwareAsset -Repo $kqmini.Repo -Asset $kqmini.Asset -OutDir (Join-Path $TOOLS_DIR '.cache\firmware') `
            -Tag (Get-FirmwareTag $Tag $Pr)
    } catch {
        Write-Host ''
        Write-Host "失敗: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    Write-Host ''
}

$flashArgs = @{ Path = $Path; Target = 'RP2040' }
if ($Drive) { $flashArgs.Drive = $Drive }
& (Join-Path $PSScriptRoot 'flash-uf2.ps1') @flashArgs
exit $LASTEXITCODE
