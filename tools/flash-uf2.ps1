<#
.SYNOPSIS
    XIAO nRF52840 (Adafruit nRF52 UF2 ブートローダ) に .uf2 ファームウェアを書き込みます。

.DESCRIPTION
    エクスプローラで .uf2 をブートローダのドライブへコピーすると、ブートローダは最後のブロックを
    受け取った直後に書き込みを確定して再起動し、USB ドライブが消えます。エクスプローラはその後で
    コピー先ファイルの属性やタイムスタンプを設定しようとするため、書き込み自体は完了しているのに
    「予期しないエラーが発生したため、ファイルをコピーできません。
      エラー 0x800701B1: 存在しないデバイスを指定しました。」
    が表示されます。

    このスクリプトは次の手順で書き込み、成否を判定します。
      1. .uf2 の中身 (UF2 ブロック / nRF52840 のファミリ ID / 書き込み先アドレス) を検証する
      2. ブートローダのドライブ (INFO_UF2.TXT があるドライブ) が現れるのを待つ
      3. ファイルサイズを先に確保してからデータだけを書き込む
      4. ドライブが消えたこと (= ブートローダが全ブロックを受け取って再起動したこと) で成功と判定する

.PARAMETER Path
    書き込む .uf2 ファイル。

.PARAMETER Drive
    ブートローダのドライブ (例: E:)。省略時は自動で検出します。

.PARAMETER WaitSeconds
    ブートローダのドライブが現れるまで待つ秒数。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-uf2.ps1 AroundForty-RB_right_central.uf2

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-uf2.ps1 settings_reset-seeeduino_xiao_ble-zmk.uf2 E:
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [Parameter(Position = 1)]
    [string]$Drive,

    [int]$WaitSeconds = 60
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-Hex([string]$Value) { [Convert]::ToUInt32($Value, 16) }

# UF2 の定数 (https://github.com/microsoft/uf2)
$UF2_MAGIC_START0 = Get-Hex '0A324655'
$UF2_MAGIC_START1 = Get-Hex '9E5D5157'
$UF2_MAGIC_END = Get-Hex '0AB16F30'
$UF2_FLAG_NOT_MAIN_FLASH = Get-Hex '00000001'
$UF2_FLAG_FAMILY_ID_PRESENT = Get-Hex '00002000'
$UF2_FAMILY_NRF52840 = Get-Hex 'ADA52840'

# Adafruit nRF52 ブートローダ (SoftDevice S140 v7) のアプリケーション領域
$APP_START = Get-Hex '00027000'
$BOOTLOADER_START = Get-Hex '000F4000'

function Stop-WithError([string]$Message) {
    Write-Host ''
    Write-Host "失敗: $Message" -ForegroundColor Red
    exit 1
}

function Test-Uf2DriveRoot([string]$Root) {
    try {
        return [System.IO.File]::Exists([System.IO.Path]::Combine($Root, 'INFO_UF2.TXT'))
    } catch {
        return $false
    }
}

function Find-Uf2DriveRoot {
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -eq [System.IO.DriveType]::Network -or $d.DriveType -eq [System.IO.DriveType]::CDRom) {
            continue
        }
        try {
            if ($d.IsReady -and (Test-Uf2DriveRoot $d.RootDirectory.FullName)) {
                $d.RootDirectory.FullName
            }
        } catch {
            # 準備できていないドライブ (カードリーダーなど) は無視する
        }
    }
}

# ---------------------------------------------------------------------------
# 1. .uf2 の検証
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Stop-WithError "ファイルが見つかりません: $Path"
}
$uf2File = (Resolve-Path -LiteralPath $Path).ProviderPath
$bytes = [System.IO.File]::ReadAllBytes($uf2File)

if ($bytes.Length -eq 0 -or ($bytes.Length % 512) -ne 0) {
    Stop-WithError "UF2 ファイルではありません (サイズが 512 バイトの倍数ではありません): $uf2File"
}

$blockCount = $bytes.Length / 512
$minAddr = [uint32]::MaxValue
$maxEnd = [uint32]0
for ($i = 0; $i -lt $blockCount; $i++) {
    $o = $i * 512
    $magic0 = [BitConverter]::ToUInt32($bytes, $o)
    $magic1 = [BitConverter]::ToUInt32($bytes, $o + 4)
    $flags = [BitConverter]::ToUInt32($bytes, $o + 8)
    $addr = [BitConverter]::ToUInt32($bytes, $o + 12)
    $payloadSize = [BitConverter]::ToUInt32($bytes, $o + 16)
    $blockNo = [BitConverter]::ToUInt32($bytes, $o + 20)
    $numBlocks = [BitConverter]::ToUInt32($bytes, $o + 24)
    $family = [BitConverter]::ToUInt32($bytes, $o + 28)
    $magicEnd = [BitConverter]::ToUInt32($bytes, $o + 508)

    if ($magic0 -ne $UF2_MAGIC_START0 -or $magic1 -ne $UF2_MAGIC_START1 -or $magicEnd -ne $UF2_MAGIC_END) {
        Stop-WithError "UF2 ファイルではありません (ブロック $i のマジック番号が不正です): $uf2File"
    }
    if (($flags -band $UF2_FLAG_NOT_MAIN_FLASH) -ne 0) {
        Stop-WithError "ブロック $i がフラッシュ書き込み対象外 (not main flash) になっています。"
    }
    if (($flags -band $UF2_FLAG_FAMILY_ID_PRESENT) -eq 0 -or $family -ne $UF2_FAMILY_NRF52840) {
        Stop-WithError ("nRF52840 用の UF2 ではありません (family ID: 0x{0:X8})。" -f $family)
    }
    if ($payloadSize -ne 256 -or ($addr % 256) -ne 0) {
        Stop-WithError ("ブロック $i の形式がブートローダの要件 (256 バイト単位) と合いません (addr 0x{0:X8}, size {1})。" -f $addr, $payloadSize)
    }
    if ($blockNo -ne $i -or $numBlocks -ne $blockCount) {
        Stop-WithError "ブロック番号が不正です (ブロック $i : blockNo=$blockNo, numBlocks=$numBlocks, 実ブロック数=$blockCount)。ファイルが壊れている可能性があります。"
    }
    if ($addr -lt $APP_START -or ($addr + 256) -gt $BOOTLOADER_START) {
        Stop-WithError ("書き込み先 0x{0:X8} がアプリケーション領域 (0x{1:X8}-0x{2:X8}) の外です。" -f $addr, $APP_START, $BOOTLOADER_START)
    }
    if ($addr -lt $minAddr) { $minAddr = $addr }
    if (($addr + 256) -gt $maxEnd) { $maxEnd = $addr + 256 }
}

Write-Host "ファームウェア: $([System.IO.Path]::GetFileName($uf2File))"
Write-Host ("  nRF52840 / {0} ブロック / 0x{1:X8}-0x{2:X8} ({3:N0} バイト)" -f $blockCount, $minAddr, $maxEnd, ($blockCount * 256))

# ---------------------------------------------------------------------------
# 2. ブートローダのドライブを待つ
# ---------------------------------------------------------------------------
$root = $null
if ($Drive) {
    if ($Drive -match '^[A-Za-z]:?\\?$') {
        $Drive = $Drive.Substring(0, 1).ToUpperInvariant() + ':\'
    }
}

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$announced = $false
while ($true) {
    if ($Drive) {
        $found = @(if (Test-Uf2DriveRoot $Drive) { $Drive })
    } else {
        $found = @(Find-Uf2DriveRoot)
    }
    if ($found.Count -eq 1) {
        $root = $found[0]
        break
    }
    if ($found.Count -gt 1) {
        Stop-WithError "ブートローダのドライブが複数あります ($($found -join ', '))。書き込み先を 2 番目の引数で指定してください (例: E:)。"
    }
    if (-not $announced) {
        Write-Host ''
        Write-Host 'ブートローダのドライブを待っています...'
        Write-Host '  リセットボタンを素早く 2 回押すか、BT レイヤーの &bootloader キーを押してください。'
        $announced = $true
    }
    if ((Get-Date) -gt $deadline) {
        Stop-WithError "$WaitSeconds 秒待ってもブートローダのドライブ (INFO_UF2.TXT があるドライブ) が見つかりませんでした。"
    }
    Start-Sleep -Milliseconds 500
}

Write-Host ''
Write-Host "書き込み先: $root"
$info = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($root, 'INFO_UF2.TXT'))
foreach ($line in ($info.Trim() -split "`r?`n")) {
    Write-Host "  $line"
}
if ($info -notmatch 'nRF52840') {
    Write-Warning 'INFO_UF2.TXT に nRF52840 の記載がありません。XIAO nRF52840 以外のボードに書き込もうとしていないか確認してください。'
}

# ---------------------------------------------------------------------------
# 3. 書き込み
# ---------------------------------------------------------------------------
# ファイル名はブートローダには関係ないので、ディレクトリエントリが 1 つで済む 8.3 形式にする。
# 先に SetLength でサイズを確定させ (FAT とディレクトリエントリを先に書かせ)、
# 最後のデータブロックの後に書き込むものが残らないようにする。
$dest = [System.IO.Path]::Combine($root, 'FIRMWARE.UF2')
$chunkSize = 64KB
$written = 0
$writeError = $null

Write-Host ''
Write-Host '書き込み中...'
try {
    $fs = New-Object System.IO.FileStream -ArgumentList @(
        $dest,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None,
        1,
        [System.IO.FileOptions]::WriteThrough
    )
    try {
        $fs.SetLength($bytes.Length)
        while ($written -lt $bytes.Length) {
            $n = [Math]::Min($chunkSize, $bytes.Length - $written)
            $fs.Write($bytes, $written, $n)
            $written += $n
        }
    } finally {
        $fs.Dispose()
    }
} catch {
    # 最後のブロックを受け取ったブートローダが再起動してドライブが消えると、
    # クローズ時の更新で例外になる。成否は下のドライブの消失で判定する。
    $writeError = $_.Exception
    while ($writeError.InnerException) { $writeError = $writeError.InnerException }
}

if ($written -lt $bytes.Length) {
    $reason = if ($writeError) { $writeError.Message } else { '不明' }
    Stop-WithError ("書き込みの途中で失敗しました ({0:N0} / {1:N0} バイト): {2}`n  USB ケーブルや USB ポートを変えて、もう一度試してください。" -f $written, $bytes.Length, $reason)
}

# ---------------------------------------------------------------------------
# 4. 判定: ブートローダが全ブロックを受け取るとリセットしてドライブが消える
# ---------------------------------------------------------------------------
$gone = $false
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline) {
    if (-not (Test-Uf2DriveRoot $root)) {
        $gone = $true
        break
    }
    Start-Sleep -Milliseconds 250
}

if (-not $gone) {
    Stop-WithError "書き込み後もブートローダのドライブが残っています。ブートローダがファームウェアを受け付けていません。`n  キーボードを USB から抜き差ししてから、もう一度試してください。"
}

Start-Sleep -Seconds 3
if (Test-Uf2DriveRoot $root) {
    Stop-WithError 'ドライブが一度消えた後、ブートローダが再び起動しました。ファームウェアが起動していない可能性があります。'
}

Write-Host ''
Write-Host '成功: ブートローダが全ブロックを受け取り、キーボードが再起動しました。' -ForegroundColor Green
if ($writeError) {
    Write-Host "  (ドライブ切断によるエラー「$($writeError.Message.Trim())」は、" -ForegroundColor DarkGray
    Write-Host '   ブートローダが書き込み完了直後に再起動するために出る想定どおりのものです)' -ForegroundColor DarkGray
}
exit 0
