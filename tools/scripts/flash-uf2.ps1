<#
.SYNOPSIS
    UF2 ブートローダ (XIAO nRF52840 / BLE Micro Pro Boost / RP2040) に .uf2 ファームウェアを書き込みます。

.DESCRIPTION
    書き込み先のボードは .uf2 のファミリ ID と書き込み先アドレスから自動で判定します。
      - nRF52840: Seeed XIAO nRF52840 (Adafruit nRF52 UF2 ブートローダ)。LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa
      - BMP     : BLE Micro Pro Boost (BLE Micro Pro の UF2 ブートローダ。ドライブ名は BLEMICROPRO)。torabo-tsuki-lp
                  XIAO とファミリ ID が同じなので、書き込み先の先頭アドレス (BMP は 0x26000、XIAO は 0x27000) で見分ける
      - RP2040  : Keyboard Quantizer Mini (RP2040 の ROM ブートローダ。ドライブ名は RPI-RP2)

    エクスプローラで .uf2 をブートローダのドライブへコピーすると、ブートローダは最後のブロックを
    受け取った直後に書き込みを確定して再起動し、USB ドライブが消えます。エクスプローラはその後で
    コピー先ファイルの属性やタイムスタンプを設定しようとするため、書き込み自体は完了しているのに
    「予期しないエラーが発生したため、ファイルをコピーできません。
      エラー 0x800701B1: 存在しないデバイスを指定しました。」
    が表示されます。

    このスクリプトは次の手順で書き込み、成否を判定します。
      1. .uf2 の中身 (UF2 ブロック / ファミリ ID / 書き込み先アドレス) を検証する
      2. ブートローダのドライブ (INFO_UF2.TXT があり、その内容 (BMP はボリュームラベル) が対象のボードと合うドライブ) が現れるのを待つ。
         RP2040 の場合は、先に Keyboard Quantizer Mini のシリアルポートへ dfu コマンドを送って
         ブートローダに切り替える
      3. ファイルサイズを先に確保してからデータだけを書き込む
      4. ドライブが消えたこと (= ブートローダが全ブロックを受け取って再起動したこと) で成功と判定する。
         BMP は電源スイッチが OFF のまま USB 給電で再起動するとブートローダに戻るため、ドライブが再び現れても成功とする

.PARAMETER Path
    書き込む .uf2 ファイル。

.PARAMETER Drive
    ブートローダのドライブ (例: E:)。省略時は自動で検出します。

.PARAMETER WaitSeconds
    ブートローダのドライブが現れるまで待つ秒数。

.PARAMETER Target
    書き込み先のボード (nRF52840 / BMP / RP2040)。複数指定できます。指定すると、.uf2 がどのボード用でもない場合に中止します。

.PARAMETER NoAutoBootloader
    RP2040 のとき、Keyboard Quantizer Mini をシリアルポート経由でブートローダに切り替えません。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash-uf2.ps1 AroundForty-RB_right_central.uf2

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash-uf2.ps1 settings_reset-seeeduino_xiao_ble-zmk.uf2 E:

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash-uf2.ps1 torabo_tsuki_lp_right_central.uf2

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash-uf2.ps1 sekigon_keyboard_quantizer_mini_vial.uf2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [Parameter(Position = 1)]
    [string]$Drive,

    [int]$WaitSeconds = 60,

    [ValidateSet('nRF52840', 'BMP', 'RP2040')]
    [string[]]$Target,

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

# 対応するボード。FamilyId は UF2 のファミリ ID、AppStart-AppEnd は書き込んでよい範囲。
# ファミリ ID が同じボードは、書き込み先の先頭アドレスが AppStart と一致するほうを選ぶ。
# ブートローダのドライブは、VolumeLabel があればボリュームラベルで、無ければ INFO_UF2.TXT に
# InfoPattern が含まれるかで見分ける (Match はその説明)。
# BootloaderHint はドライブを待つあいだの案内 (1 要素 1 行)、AfterFlashHint は書き込み後の案内。
# ReturnsToBootloader は、書き込み後の再起動でブートローダに戻ることがあるボード。
$BOARDS = @(
    [pscustomobject]@{
        Name                = 'nRF52840'
        Description         = 'nRF52840 (Seeed XIAO nRF52840)'
        FamilyId            = Get-Hex 'ADA52840'
        # Adafruit nRF52 ブートローダ (SoftDevice S140 v7) のアプリケーション領域
        AppStart            = Get-Hex '00027000'
        AppEnd              = Get-Hex '000F4000'
        InfoPattern         = 'nRF52840'
        VolumeLabel         = $null
        Match               = 'INFO_UF2.TXT に nRF52840 があるドライブ'
        BootloaderHint      = @(
            'リセットボタンを素早く 2 回押すか、Q (左手側) / P (右手側) を押したまま USB ケーブルを挿してください (ドライブが現れたら離す)。'
            'FUNC レイヤーの &bootloader キー (右: FUNC + N / 左: FUNC + B) でも切り替えられます。'
            '左手側を FUNC + B で切り替えるときは、右手側の電源を入れておいてください (右手側を経由して切り替えるため)。'
        )
        AfterFlashHint      = $null
        ReturnsToBootloader = $false
    },
    [pscustomobject]@{
        Name                = 'BMP'
        Description         = 'nRF52840 (BLE Micro Pro Boost)'
        FamilyId            = Get-Hex 'ADA52840'
        # bmp_boost (SoftDevice S140 v6) のアプリケーション領域。0xE0000 からはブートローダ
        AppStart            = Get-Hex '00026000'
        AppEnd              = Get-Hex '000E0000'
        InfoPattern         = $null
        VolumeLabel         = 'BLEMICROPRO'
        Match               = 'ボリュームラベルが BLEMICROPRO のドライブ'
        BootloaderHint      = @(
            '電源スイッチを OFF にしてから USB ケーブルでつなぐか、スイッチ ON のまま Q (左手側) / P (右手側) を押しながら USB ケーブルでつないでください (ドライブが現れたら離す)。'
            'FUNC レイヤーの &bootloader キー (右: FUNC + N / 左: FUNC + B) でも切り替えられます。'
            '左手側を FUNC + B で切り替えるときは、右手側の電源を入れておいてください (右手側を経由して切り替えるため)。'
        )
        AfterFlashHint      = '電源スイッチが OFF のときは、USB ケーブルを抜き、電源スイッチを ON にしてから USB ケーブルを差し直すと、書き込んだファームウェアで起動します (settings_reset はこのときに設定を消します)。'
        ReturnsToBootloader = $true
    },
    [pscustomobject]@{
        Name                = 'RP2040'
        Description         = 'RP2040 (Keyboard Quantizer Mini)'
        FamilyId            = Get-Hex 'E48BFF56'
        # RP2040 の XIP フラッシュ (最大 16 MB)
        AppStart            = Get-Hex '10000000'
        AppEnd              = Get-Hex '11000000'
        InfoPattern         = 'RPI-RP2'
        VolumeLabel         = $null
        Match               = 'INFO_UF2.TXT に RPI-RP2 があるドライブ'
        BootloaderHint      = @('Keyboard Quantizer Mini の FUNC レイヤーの QK_BOOT キーを押してください。')
        AfterFlashHint      = 'Keyboard Quantizer Mini は、LED が点灯して入力できるようになるまで数十秒かかることがあります。'
        ReturnsToBootloader = $false
    }
)

# Keyboard Quantizer Mini (vial-qmk-kq-mini) の USB デバイス。ファームウェアの CLI に
# シリアル (CDC) で "dfu" + Enter を送るとブートローダ (RPI-RP2 ドライブ) に切り替わる。
$KQMINI_PNP_DEVICE_ID = 'USB\VID_FEED&PID_999C*'

# 古いファームウェアの virtser_task (tmk_core/protocol/chibios/usb_main.c) は、CDC のエンドポイントサイズ
# (CDC_EPSIZE = 16 バイト) ちょうど読めたときだけ受信データを CLI に渡し、それより短いパケットは
# 捨てる。"`rdfu`r" (5 バイト) をそのまま送っても届かないので、CLI が無視する NUL で 16 バイトに埋めて
# 1 パケットで送る。ファームウェア側は vial-qmk-kq-mini#13 (上流 QMK #26356) で直したが、
# それより前のファームウェアが入った KQ-mini も切り替えられるように埋めて送り続ける。
$KQMINI_CDC_EPSIZE = 16

# キーボードを Q / P + USB でブートローダにすると、押したキーがもう片側や PC 経由でこのコンソールに
# 入力されることがある。残っていると .cmd の pause がそれを読んで、結果を読む前に窓が閉じるので、
# 終了する前に捨てる。コンソールが無いホストでは何もしない。
function Clear-ConsoleInput {
    try { $Host.UI.RawUI.FlushInputBuffer() } catch { }
}

function Stop-WithError([string]$Message) {
    Clear-ConsoleInput
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

function Get-VolumeLabel([string]$Root) {
    try {
        return (New-Object System.IO.DriveInfo -ArgumentList $Root).VolumeLabel
    } catch {
        return $null
    }
}

# $Root が $Board のブートローダのドライブか。ボリュームラベルで見分けるボード (BMP) のドライブは、
# INFO_UF2.TXT の内容に関わらず他のボードのドライブとはみなさない。
function Test-BoardInfo([string]$Root, $Board) {
    $label = Get-VolumeLabel $Root
    if ($Board.VolumeLabel) {
        return ($label -eq $Board.VolumeLabel)
    }
    foreach ($b in $BOARDS) {
        if ($b.VolumeLabel -and $label -eq $b.VolumeLabel) { return $false }
    }
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
        $sameFamily = @($BOARDS | Where-Object { $_.FamilyId -eq $family })
        if ($sameFamily.Count -eq 0) {
            $names = ($BOARDS | ForEach-Object { $_.Name }) -join ' / '
            Stop-WithError ("対応していないボード用の UF2 です (family ID: 0x{0:X8})。対応しているのは {1} です。" -f $family, $names)
        }
        # XIAO と BMP はファミリ ID が同じなので、先頭ブロックの書き込み先がアプリケーション領域の
        # 先頭と一致するほうに決める
        $board = $sameFamily | Where-Object { $_.AppStart -eq $addr } | Select-Object -First 1
        if ($null -eq $board) {
            if ($sameFamily.Count -gt 1) {
                $starts = ($sameFamily | ForEach-Object { '{0}: 0x{1:X8}' -f $_.Name, $_.AppStart }) -join ' / '
                Stop-WithError ("先頭の書き込み先 0x{0:X8} が、どのボードのアプリケーション領域の先頭 ({1}) とも一致しません。" -f $addr, $starts)
            }
            # ボードは 1 つに決まる。書き込み先は下の範囲チェックで確認する
            $board = $sameFamily[0]
        }
        if ($Target -and $Target -notcontains $board.Name) {
            Stop-WithError "$($Target -join ' / ') 用ではなく $($board.Description) 用の UF2 です。書き込むファイルを確認してください: $uf2File"
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
                Write-Host "  $r は $($board.Name) のブートローダではないため無視します ($($board.Match)ではありません)。" -ForegroundColor DarkGray
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
                foreach ($line in $board.BootloaderHint) { Write-Host "  $line" }
            }
        } else {
            foreach ($line in $board.BootloaderHint) { Write-Host "  $line" }
        }
        $announced = $true
    }
    if ((Get-Date) -gt $deadline) {
        $message = "$WaitSeconds 秒待っても $($board.Name) のブートローダのドライブ ($($board.Match)) が見つかりませんでした。"
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
if (-not (Test-BoardInfo $root $board)) {
    Write-Warning "$root は $($board.Match)ではありません。$($board.Description) 以外のボードに書き込もうとしていないか確認してください。"
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
if ((Test-Uf2DriveRoot $root) -and -not $board.ReturnsToBootloader) {
    Stop-WithError ("ドライブが一度消えた後、ブートローダが再び起動しました。ファームウェアが起動していない可能性があります。`n" +
        '  Q / P を押したままだった場合は、書き込んだファームウェアが起動してまたブートローダに入っただけで、書き込みはできています。' +
        'キーを離して、リセットボタンを 1 回押すか、USB ケーブルを挿し直してください。')
}

Write-Host ''
Write-Host '成功: ブートローダが全ブロックを受け取り、ボードが再起動しました。' -ForegroundColor Green
if ($board.AfterFlashHint) {
    Write-Host "  $($board.AfterFlashHint)"
}
if ($writeError) {
    Write-Host "  (ドライブ切断によるエラー「$($writeError.Message.Trim())」は、" -ForegroundColor DarkGray
    Write-Host '   ブートローダが書き込み完了直後に再起動するために出る想定どおりのものです)' -ForegroundColor DarkGray
}
Clear-ConsoleInput
exit 0
