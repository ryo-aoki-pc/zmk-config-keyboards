<#
.SYNOPSIS
    UF2 ブートローダ (XIAO nRF52840 / RP2040) に .uf2 ファームウェアを書き込みます。

.DESCRIPTION
    書き込み先のボードは .uf2 のファミリ ID から自動で判定します。
      - nRF52840: Seeed XIAO nRF52840 (Adafruit nRF52 UF2 ブートローダ)。LisM / AroundFortyRB / KUKEY42 / Pyuron
      - RP2040  : Keyboard Quantizer Mini (RP2040 の ROM ブートローダ。ドライブ名は RPI-RP2)

    エクスプローラで .uf2 をブートローダのドライブへコピーすると、ブートローダは最後のブロックを
    受け取った直後に書き込みを確定して再起動し、USB ドライブが消えます。エクスプローラはその後で
    コピー先ファイルの属性やタイムスタンプを設定しようとするため、書き込み自体は完了しているのに
    「予期しないエラーが発生したため、ファイルをコピーできません。
      エラー 0x800701B1: 存在しないデバイスを指定しました。」
    が表示されます。

    このスクリプトは次の手順で書き込み、成否を判定します。
      1. .uf2 の中身 (UF2 ブロック / ファミリ ID / 書き込み先アドレス) を検証する
      2. ブートローダのドライブ (INFO_UF2.TXT があり、その内容が対象のボードと合うドライブ) が現れるのを待つ。
         RP2040 の場合は、先に Keyboard Quantizer Mini のシリアルポートへ dfu コマンドを送って
         ブートローダに切り替える
      3. ファイルサイズを先に確保してからデータだけを書き込む
      4. ドライブが消えたこと (= ブートローダが全ブロックを受け取って再起動したこと) で成功と判定する

.PARAMETER Path
    書き込む .uf2 ファイル。

.PARAMETER Drive
    ブートローダのドライブ (例: E:)。省略時は自動で検出します。

.PARAMETER WaitSeconds
    ブートローダのドライブが現れるまで待つ秒数。

.PARAMETER Target
    書き込み先のボード (nRF52840 / RP2040)。指定すると、.uf2 のファミリ ID が一致しない場合に中止します。

.PARAMETER NoAutoBootloader
    RP2040 のとき、Keyboard Quantizer Mini をシリアルポート経由でブートローダに切り替えません。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-uf2.ps1 AroundForty-RB_right_central.uf2

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-uf2.ps1 settings_reset-seeeduino_xiao_ble-zmk.uf2 E:

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\flash-uf2.ps1 sekigon_keyboard_quantizer_mini_vial.uf2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [Parameter(Position = 1)]
    [string]$Drive,

    [int]$WaitSeconds = 60,

    [ValidateSet('nRF52840', 'RP2040')]
    [string]$Target,

    [switch]$NoAutoBootloader
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

# 対応するボード。FamilyId は UF2 のファミリ ID、AppStart-AppEnd は書き込んでよい範囲、
# InfoPattern はブートローダのドライブの INFO_UF2.TXT に含まれるはずの文字列。
$BOARDS = @(
    [pscustomobject]@{
        Name        = 'nRF52840'
        Description = 'nRF52840 (Seeed XIAO nRF52840)'
        FamilyId    = Get-Hex 'ADA52840'
        # Adafruit nRF52 ブートローダ (SoftDevice S140 v7) のアプリケーション領域
        AppStart    = Get-Hex '00027000'
        AppEnd      = Get-Hex '000F4000'
        InfoPattern = 'nRF52840'
    },
    [pscustomobject]@{
        Name        = 'RP2040'
        Description = 'RP2040 (Keyboard Quantizer Mini)'
        FamilyId    = Get-Hex 'E48BFF56'
        # RP2040 の XIP フラッシュ (最大 16 MB)
        AppStart    = Get-Hex '10000000'
        AppEnd      = Get-Hex '11000000'
        InfoPattern = 'RPI-RP2'
    }
)

# Keyboard Quantizer Mini (vial-qmk-kq-mini) の USB デバイス。ファームウェアの CLI に
# シリアル (CDC) で "dfu" + Enter を送るとブートローダ (RPI-RP2 ドライブ) に切り替わる。
$KQMINI_PNP_DEVICE_ID = 'USB\VID_FEED&PID_999C*'

# vial-qmk の virtser_task (tmk_core/protocol/chibios/usb_main.c) は、CDC のエンドポイントサイズ
# (CDC_EPSIZE = 16 バイト) ちょうど読めたときだけ受信データを CLI に渡し、それより短いパケットは
# 捨てる。"`rdfu`r" (5 バイト) をそのまま送っても届かないので、CLI が無視する NUL で 16 バイトに埋めて
# 1 パケットで送る。
$KQMINI_CDC_EPSIZE = 16

function Stop-WithError([string]$Message) {
    Write-Host ''
    Write-Host "失敗: $Message" -ForegroundColor Red
    exit 1
}

function Get-Uf2Info([string]$Root) {
    try {
        return [System.IO.File]::ReadAllText([System.IO.Path]::Combine($Root, 'INFO_UF2.TXT'))
    } catch {
        return $null
    }
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

function Test-BoardInfo([string]$Root, $Board) {
    $info = Get-Uf2Info $Root
    return ($null -ne $info -and $info.Contains($Board.InfoPattern))
}

function Find-KqMiniSerialPort {
    try {
        $entities = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass = 'Ports'")
    } catch {
        return
    }
    foreach ($e in $entities) {
        if ($e.PNPDeviceID -like $KQMINI_PNP_DEVICE_ID -and $e.Name -match '\((COM\d+)\)') {
            $Matches[1]
        }
    }
}

function Send-KqMiniDfu([string]$Port) {
    # 先頭の CR で入力途中の行があれば確定させてから dfu を送る
    $command = [System.Text.Encoding]::ASCII.GetBytes("`rdfu`r")
    $packet = New-Object byte[] $KQMINI_CDC_EPSIZE
    [Array]::Copy($command, $packet, $command.Length)

    $serial = New-Object System.IO.Ports.SerialPort -ArgumentList $Port, 115200
    $serial.WriteTimeout = 2000
    $serial.DtrEnable = $true
    try {
        $serial.Open()
        $serial.Write($packet, 0, $packet.Length)
        Start-Sleep -Milliseconds 300
    } finally {
        # ブートローダに切り替わってポートが消えると Close で例外になることがある
        try { $serial.Close() } catch { }
        $serial.Dispose()
    }
}

# KQ-mini をブートローダに切り替える。切り替えを指示できたら $true を返す。
function Request-KqMiniBootloader {
    $ports = @(Find-KqMiniSerialPort)
    if ($ports.Count -eq 0) {
        Write-Host '  Keyboard Quantizer Mini のシリアルポート (VID FEED / PID 999C) が見つかりません。'
        return $false
    }
    if ($ports.Count -gt 1) {
        Write-Host "  Keyboard Quantizer Mini が複数つながっています ($($ports -join ', '))。自動では切り替えません。"
        return $false
    }
    try {
        Send-KqMiniDfu $ports[0]
    } catch {
        Write-Host "  $($ports[0]) に dfu コマンドを送れませんでした: $($_.Exception.Message)"
        return $false
    }
    Write-Host "  Keyboard Quantizer Mini ($($ports[0])) に dfu コマンドを送り、ブートローダに切り替えました。"
    return $true
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
$board = $null
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
    if (($flags -band $UF2_FLAG_FAMILY_ID_PRESENT) -eq 0) {
        Stop-WithError "ブロック $i にファミリ ID がありません。書き込み先のボードを判定できません。"
    }
    if ($null -eq $board) {
        $board = $BOARDS | Where-Object { $_.FamilyId -eq $family } | Select-Object -First 1
        if ($null -eq $board) {
            $names = ($BOARDS | ForEach-Object { $_.Name }) -join ' / '
            Stop-WithError ("対応していないボード用の UF2 です (family ID: 0x{0:X8})。対応しているのは {1} です。" -f $family, $names)
        }
        if ($Target -and $board.Name -ne $Target) {
            Stop-WithError "$Target 用ではなく $($board.Description) 用の UF2 です。書き込むファイルを確認してください: $uf2File"
        }
    } elseif ($family -ne $board.FamilyId) {
        Stop-WithError ("ブロック $i のファミリ ID (0x{0:X8}) が他のブロック (0x{1:X8}) と違います。ファイルが壊れている可能性があります。" -f $family, $board.FamilyId)
    }
    if ($payloadSize -ne 256 -or ($addr % 256) -ne 0) {
        Stop-WithError ("ブロック $i の形式がブートローダの要件 (256 バイト単位) と合いません (addr 0x{0:X8}, size {1})。" -f $addr, $payloadSize)
    }
    if ($blockNo -ne $i -or $numBlocks -ne $blockCount) {
        Stop-WithError "ブロック番号が不正です (ブロック $i : blockNo=$blockNo, numBlocks=$numBlocks, 実ブロック数=$blockCount)。ファイルが壊れている可能性があります。"
    }
    if ($addr -lt $board.AppStart -or ($addr + 256) -gt $board.AppEnd) {
        Stop-WithError ("書き込み先 0x{0:X8} が {1} の書き込み可能な領域 (0x{2:X8}-0x{3:X8}) の外です。" -f $addr, $board.Name, $board.AppStart, $board.AppEnd)
    }
    if ($addr -lt $minAddr) { $minAddr = $addr }
    if (($addr + 256) -gt $maxEnd) { $maxEnd = $addr + 256 }
}

Write-Host "ファームウェア: $([System.IO.Path]::GetFileName($uf2File))"
Write-Host ("  {0} / {1} ブロック / 0x{2:X8}-0x{3:X8} ({4:N0} バイト)" -f $board.Description, $blockCount, $minAddr, $maxEnd, ($blockCount * 256))

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
$ignored = @{}
while ($true) {
    if ($Drive) {
        # 明示されたドライブは INFO_UF2.TXT の内容に関わらず使う (合わなければ下で警告する)
        $found = @(if (Test-Uf2DriveRoot $Drive) { $Drive })
    } else {
        $found = @()
        foreach ($r in @(Find-Uf2DriveRoot)) {
            if (Test-BoardInfo $r $board) {
                $found += $r
            } elseif (-not $ignored.ContainsKey($r)) {
                # 別のボード (例: XIAO と KQ-mini) のブートローダには書き込まない
                $ignored[$r] = $true
                Write-Host "  $r は $($board.Name) のブートローダではないため無視します (INFO_UF2.TXT に $($board.InfoPattern) がありません)。" -ForegroundColor DarkGray
            }
        }
    }
    if ($found.Count -eq 1) {
        $root = $found[0]
        break
    }
    if ($found.Count -gt 1) {
        Stop-WithError "$($board.Name) のブートローダのドライブが複数あります ($($found -join ', '))。書き込み先を 2 番目の引数で指定してください (例: E:)。"
    }
    if (-not $announced) {
        Write-Host ''
        Write-Host 'ブートローダのドライブを待っています...'
        if ($board.Name -eq 'RP2040') {
            $switched = $false
            if (-not $NoAutoBootloader) {
                $switched = Request-KqMiniBootloader
            }
            if (-not $switched) {
                Write-Host '  Keyboard Quantizer Mini の FUNC レイヤーの QK_BOOT キーを押してください。'
            }
        } else {
            Write-Host '  リセットボタンを素早く 2 回押すか、BT レイヤーの &bootloader キーを押してください。'
        }
        $announced = $true
    }
    if ((Get-Date) -gt $deadline) {
        $message = "$WaitSeconds 秒待っても $($board.Name) のブートローダのドライブ (INFO_UF2.TXT に $($board.InfoPattern) があるドライブ) が見つかりませんでした。"
        if ($ignored.Count -gt 0) {
            $message += "`n  無視したドライブ ($($ignored.Keys -join ', ')) に書き込む場合は、2 番目の引数でドライブを指定してください。"
        }
        Stop-WithError $message
    }
    Start-Sleep -Milliseconds 500
}

Write-Host ''
Write-Host "書き込み先: $root"
$info = Get-Uf2Info $root
if ($null -eq $info) { $info = '' }
foreach ($line in ($info.Trim() -split "`r?`n")) {
    Write-Host "  $line"
}
if (-not $info.Contains($board.InfoPattern)) {
    Write-Warning "INFO_UF2.TXT に $($board.InfoPattern) の記載がありません。$($board.Description) 以外のボードに書き込もうとしていないか確認してください。"
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
    Stop-WithError "書き込み後もブートローダのドライブが残っています。ブートローダがファームウェアを受け付けていません。`n  ボードを USB から抜き差ししてから、もう一度試してください。"
}

Start-Sleep -Seconds 3
if (Test-Uf2DriveRoot $root) {
    Stop-WithError 'ドライブが一度消えた後、ブートローダが再び起動しました。ファームウェアが起動していない可能性があります。'
}

Write-Host ''
Write-Host '成功: ブートローダが全ブロックを受け取り、ボードが再起動しました。' -ForegroundColor Green
if ($board.Name -eq 'RP2040') {
    Write-Host '  Keyboard Quantizer Mini は、LED が点灯して入力できるようになるまで数十秒かかることがあります。'
}
if ($writeError) {
    Write-Host "  (ドライブ切断によるエラー「$($writeError.Message.Trim())」は、" -ForegroundColor DarkGray
    Write-Host '   ブートローダが書き込み完了直後に再起動するために出る想定どおりのものです)' -ForegroundColor DarkGray
}
exit 0
