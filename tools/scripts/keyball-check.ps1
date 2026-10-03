<#
.SYNOPSIS
    Keyball (QMK / VIA) がトラックボールを認識しているかを読み取り専用で確認します。

.DESCRIPTION
    Keyball のファームウェアは、起動時に左右それぞれがトラックボールのセンサー (PMW3360) を検出し、
    USB を挿した側が反対側に問い合わせてボールの有無を確定します。確定した結果は VIA の
    layout options (Ball availability) に保存されます。センサーが応答しないと「ボール無し」となり、
    キーは動くのにトラックボールだけ動かなくなります。

    このスクリプトは VIA の読み取りコマンド (get 系) だけを送り、次の情報を表示します。
    キーマップや設定を書き換えるコマンドは送りません。
      - Ball availability (None / Right / Left / Dual)
      - 起動からの経過時間
      - RGB ライティングの状態 (LED の消費電流が大きいと電源の余裕が小さくなるため)

    Keyboard Quantizer Mini などの変換器を経由すると Keyball の VIA に届かないため、
    Keyball を PC に直接つないで実行してください。

.PARAMETER Watch
    1 秒ごとに読み取り、Ball availability の変化と再起動を表示し続けます (Ctrl+C で終了)。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\keyball-check.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\keyball-check.ps1 -Watch
#>
[CmdletBinding()]
param(
    [switch]$Watch
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$KEYBALL_VID = '5957'
$KQ_MINI_ID = 'VID_FEED&PID_999C'
$HID_INTERFACE_GUID = '{4d1e55b2-f16f-11cf-88cb-001111000030}'
$VIA_USAGE = 'UP:FF60_U:0061' # VIA の raw HID (Usage Page FF60 / Usage 61) のハードウェア ID

# PID の上位バイト -> 機種 (lib/keyball/keyball.h の KEYBALL_MODEL と同じ対応)
$MODELS = @{ 0x00 = 'Keyball46'; 0x01 = 'Keyball61'; 0x02 = 'Keyball39'; 0x03 = 'one47'; 0x04 = 'Keyball44' }
$BALL_NAMES = @('None', 'Right', 'Left', 'Dual')

if (-not ('KeyballVia' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class KeyballVia {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    const uint GENERIC_READ = 0x80000000;
    const uint GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ_WRITE = 3;
    const uint OPEN_EXISTING = 3;
    const uint FILE_FLAG_OVERLAPPED = 0x40000000;

    // Sends a VIA command as a 32-byte raw HID report (report ID 0) and returns the
    // 32-byte response that echoes the command, or 0xFF (id_unhandled) first.
    public static byte[] Query(string path, byte[] command, int timeoutMs) {
        using (SafeFileHandle handle = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ_WRITE, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero)) {
            if (handle.IsInvalid) {
                throw new IOException("cannot open the VIA interface (Win32 error " + Marshal.GetLastWin32Error() + ")");
            }
            using (FileStream stream = new FileStream(handle, FileAccess.ReadWrite, 1, true)) {
                byte[] report = new byte[33];
                Array.Copy(command, 0, report, 1, command.Length);
                stream.Write(report, 0, report.Length);
                stream.Flush();
                for (int i = 0; i < 8; i++) {
                    byte[] input = new byte[33];
                    var read = stream.ReadAsync(input, 0, input.Length);
                    if (!read.Wait(timeoutMs)) {
                        throw new TimeoutException("no response from VIA");
                    }
                    bool match = input[1] == 0xFF;
                    if (!match) {
                        match = true;
                        for (int j = 0; j < command.Length && j < 3; j++) {
                            if (input[1 + j] != command[j]) {
                                match = false;
                                break;
                            }
                        }
                    }
                    if (match) {
                        byte[] response = new byte[32];
                        Array.Copy(input, 1, response, 0, response.Length);
                        return response;
                    }
                }
                throw new IOException("no matching response from VIA");
            }
        }
    }
}
'@
}

# 接続中の PnP デバイスのうち、DeviceID が WQL の LIKE パターンに一致するものを返す
function Get-PresentDevice([string]$Pattern) {
    $filter = "DeviceID LIKE '{0}' AND Present = TRUE" -f $Pattern.Replace('\', '\\')
    return @(Get-CimInstance -ClassName Win32_PnPEntity -Filter $filter -ErrorAction SilentlyContinue)
}

# VIA の raw HID インターフェイス (Usage Page FF60 / Usage 61) を持つ Keyball を探す
function Find-Keyball {
    $found = @()
    foreach ($dev in (Get-PresentDevice "HID\VID_${KEYBALL_VID}&PID_%")) {
        if ($dev.DeviceID -notmatch "^HID\\VID_${KEYBALL_VID}&PID_([0-9A-F]{4})") {
            continue
        }
        $productId = [Convert]::ToInt32($Matches[1], 16)
        if (-not (@($dev.HardwareID) -match $VIA_USAGE)) {
            continue
        }
        $model = $MODELS[$productId -shr 8]
        if ($null -eq $model) {
            $model = 'Keyball (不明な機種)'
        }
        $found += [pscustomobject]@{
            Model     = $model
            ProductId = $productId
            Path      = '\\?\' + ($dev.DeviceID -replace '\\', '#') + '#' + $HID_INTERFACE_GUID
        }
    }
    return , $found
}

function Invoke-Via([string]$Path, [byte[]]$Command) {
    $response = [KeyballVia]::Query($Path, $Command, 1500)
    if ($response[0] -eq 0xFF) {
        return $null # id_unhandled: このファームウェアでは使えないコマンド
    }
    return , $response
}

function ConvertFrom-BigEndian([byte[]]$Bytes, [int]$Offset) {
    return ([uint32]$Bytes[$Offset] -shl 24) -bor ([uint32]$Bytes[$Offset + 1] -shl 16) -bor ([uint32]$Bytes[$Offset + 2] -shl 8) -bor [uint32]$Bytes[$Offset + 3]
}

function Read-KeyballStatus($Keyball) {
    $path = $Keyball.Path
    $version = Invoke-Via $path ([byte[]](0x01))
    $protocol = ([int]$version[1] -shl 8) -bor [int]$version[2]
    $uptime = ConvertFrom-BigEndian (Invoke-Via $path ([byte[]](0x02, 0x01))) 2
    $layout = ConvertFrom-BigEndian (Invoke-Via $path ([byte[]](0x02, 0x02))) 2

    # RGB ライティング: VIA プロトコル 12 以降は id_custom_get_value + rgblight チャンネル (2)
    if ($protocol -ge 12) {
        $brightness = Invoke-Via $path ([byte[]](0x08, 0x02, 0x01))
        $effect = Invoke-Via $path ([byte[]](0x08, 0x02, 0x02))
        $color = Invoke-Via $path ([byte[]](0x08, 0x02, 0x04))
        $at = 3
    } else {
        $brightness = Invoke-Via $path ([byte[]](0x08, 0x80))
        $effect = Invoke-Via $path ([byte[]](0x08, 0x81))
        $color = Invoke-Via $path ([byte[]](0x08, 0x83))
        $at = 2
    }
    $rgb = $null
    if ($null -ne $brightness -and $null -ne $effect -and $null -ne $color) {
        $rgb = [pscustomobject]@{
            Effect     = [int]$effect[$at]
            Brightness = [int]$brightness[$at]
            Hue        = [int]$color[$at]
            Saturation = [int]$color[$at + 1]
        }
    }

    return [pscustomobject]@{
        Protocol = $protocol
        UptimeMs = $uptime
        Layout   = $layout
        Ball     = $BALL_NAMES[[int]($layout -band 3)]
        Rgb      = $rgb
    }
}

function Write-Status($Keyball, $Status) {
    Write-Host ('{0} (VID {1} / PID {2:X4}, VIA プロトコル 0x{3:X4})' -f $Keyball.Model, $KEYBALL_VID, $Keyball.ProductId, $Status.Protocol)
    Write-Host ('  起動からの経過時間 : {0:F1} 秒' -f ($Status.UptimeMs / 1000.0))
    if ($Keyball.Model -eq 'one47') {
        Write-Host '  Ball availability  : (one47 は layout options にボールの検出結果を保存しません)'
    } else {
        Write-Host ('  Ball availability  : {0}' -f $Status.Ball)
    }
    if ($null -eq $Status.Rgb) {
        Write-Host '  RGB ライティング   : (取得できません)'
    } elseif ($Status.Rgb.Effect -eq 0) {
        Write-Host '  RGB ライティング   : 消灯'
    } else {
        Write-Host ('  RGB ライティング   : 点灯 (エフェクト {0}、明るさ {1}/255、色相 {2}、彩度 {3})' -f $Status.Rgb.Effect, $Status.Rgb.Brightness, $Status.Rgb.Hue, $Status.Rgb.Saturation)
    }
}

function Write-Advice($Keyball, $Status) {
    Write-Host ''
    if ($Keyball.Model -eq 'one47') {
        return
    }
    if ($Status.Ball -ne 'None') {
        Write-Host ('判定: {0} のトラックボールを認識しています。' -f $Status.Ball) -ForegroundColor Green
        Write-Host '  それでもカーソルが動かない場合は、OLED の Ball: 行が変化するかと、PC / 変換器側を確認してください。'
        return
    }
    if ($Status.UptimeMs -lt 6000) {
        Write-Host '判定: 起動直後のため、左右の問い合わせが終わっていない可能性があります。数秒後に再実行してください。' -ForegroundColor Yellow
        return
    }
    Write-Host '判定: どちらの半分のトラックボールも認識していません。' -ForegroundColor Red
    Write-Host '  1. USB をボールがある側の半分に挿し替えて、もう一度実行してください (TRRS ケーブルは通電中に抜き差ししない)。'
    Write-Host '     - ボール側に挿しても None: その半分のセンサー (PMW3360) が応答していません。USB を抜いてから、'
    Write-Host '       ボール基板を 7 ピン L 字コンスルーに垂直に差し直す / Pro Micro のコンスルー / 信号線ジャンパ 4 箇所を点検してください。'
    Write-Host '     - ボール側に挿すと認識する: センサーは正常です。左右の通信 (TRRS ケーブル) と起動タイミングを確認してください。'
    if ($null -ne $Status.Rgb -and $Status.Rgb.Effect -ne 0) {
        Write-Host '  2. LED が点灯しています。VIA で消灯・保存してから挿し直すと、電源不足が原因かどうかを切り分けられます。'
    }
    Write-Host '  詳しくは README.md の「Keyball39 のトラックボールが動かない場合」を参照してください。'
}

function Test-KqMini {
    return (Get-PresentDevice "USB\${KQ_MINI_ID}\%").Count -gt 0
}

function Write-NotFound {
    Write-Host 'Keyball (VID 5957) の VIA インターフェイスが見つかりません。' -ForegroundColor Red
    if (Test-KqMini) {
        Write-Host '  Keyboard Quantizer Mini が接続されています。変換器を経由すると Keyball の VIA に届かないため、'
        Write-Host '  Keyball を PC に直接つないで実行してください。'
    } else {
        Write-Host '  Keyball を PC に直接つなぎ、VIA 対応のファームウェア (keyball39:via など) が書き込まれているか確認してください。'
    }
}

if (-not $Watch) {
    $keyballs = Find-Keyball
    if ($keyballs.Count -eq 0) {
        Write-NotFound
        exit 2
    }
    $allOk = $true
    foreach ($keyball in $keyballs) {
        try {
            $status = Read-KeyballStatus $keyball
        } catch {
            Write-Host ('{0}: 読み取りに失敗しました: {1}' -f $keyball.Model, $_.Exception.Message) -ForegroundColor Red
            $allOk = $false
            continue
        }
        Write-Status $keyball $status
        Write-Advice $keyball $status
        if ($status.Ball -eq 'None' -and $keyball.Model -ne 'one47') {
            $allOk = $false
        }
    }
    if ($allOk) {
        exit 0
    }
    exit 1
}

Write-Host '1 秒ごとに読み取ります (Ctrl+C で終了)。'
$lastState = $null
$lastUptime = [uint32]0
$keyball = $null
while ($true) {
    if ($null -eq $keyball) {
        $found = Find-Keyball
        if ($found.Count -gt 0) {
            $keyball = $found[0]
        }
    }
    $state = '未接続'
    $uptime = $null
    if ($null -ne $keyball) {
        try {
            $status = Read-KeyballStatus $keyball
            $state = 'Ball availability: ' + $status.Ball
            $uptime = $status.UptimeMs
        } catch {
            $state = '読み取り失敗 (切断中または起動中)'
            $keyball = $null
        }
    }
    $rebooted = $null -ne $uptime -and $uptime -lt $lastUptime
    if ($state -ne $lastState -or $rebooted) {
        $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $state
        if ($null -ne $uptime) {
            $line += ('  (起動から {0:F1} 秒)' -f ($uptime / 1000.0))
        }
        Write-Host $line
        $lastState = $state
    }
    if ($null -ne $uptime) {
        $lastUptime = $uptime
    }
    Start-Sleep -Seconds 1
}
