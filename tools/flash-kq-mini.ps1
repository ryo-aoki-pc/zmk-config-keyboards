<#
.SYNOPSIS
    Keyboard Quantizer Mini (vial-qmk-kq-mini) にファームウェアを書き込みます。

.DESCRIPTION
    .uf2 を指定しなければ、vial-qmk-kq-mini の firmware-latest リリース (custom ブランチの
    最新ビルド) をダウンロードして書き込みます。書き込みは flash-uf2.ps1 が行い、
    KQ-mini はシリアルポート経由で自動的にブートローダに切り替えます。

.PARAMETER Path
    書き込む .uf2 ファイル。省略すると最新のファームウェアをダウンロードします。

.PARAMETER Drive
    ブートローダのドライブ (例: E:)。省略時は自動で検出します。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-kq-mini.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-kq-mini.ps1 sekigon_keyboard_quantizer_mini_vial.uf2
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [Parameter(Position = 1)]
    [string]$Drive
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\firmware-latest.ps1')

if (-not $Path) {
    try {
        $Path = Get-FirmwareLatest -Repo 'ryo-aoki-pc/vial-qmk-kq-mini' -Asset 'sekigon_keyboard_quantizer_mini_vial.uf2' `
            -OutDir (Join-Path $PSScriptRoot '.cache\firmware')
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
