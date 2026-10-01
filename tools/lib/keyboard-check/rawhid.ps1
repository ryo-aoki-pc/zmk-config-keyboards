# VIA / Vial の raw HID インターフェイスの検出と、C# ヘルパー (RawHid.cs) の読み込み。
# keyboard-check.ps1 から dot-source して使う (Windows のみ)。

$script:KcLibDir = $PSScriptRoot
$script:KcHidInterfaceGuid = '{4d1e55b2-f16f-11cf-88cb-001111000030}'
$script:KcViaUsage = 'UP:FF60_U:0061' # VIA / Vial の raw HID (Usage Page FF60 / Usage 61) のハードウェア ID

# tools/lib/keyboard-check/<File>.cs を Add-Type で読み込む (読み込み済みなら何もしない)
function Import-KcCSharp([string]$File, [string]$TypeName, [string[]]$References = @()) {
    if ($TypeName -as [type]) {
        return
    }
    $path = Join-Path $script:KcLibDir $File
    $source = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if ($References.Count -gt 0) {
        Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies $References
    } else {
        Add-Type -TypeDefinition $source -Language CSharp
    }
}

# 接続中の PnP デバイスのうち、DeviceID が WQL の LIKE パターンに一致するもの
function Get-KcPresentDevice([string]$Pattern, [string]$Class = '') {
    $filter = "DeviceID LIKE '{0}' AND Present = TRUE" -f $Pattern.Replace('\', '\\')
    if ($Class) {
        $filter += " AND PNPClass = '$Class'"
    }
    return @(Get-CimInstance -ClassName Win32_PnPEntity -Filter $filter -ErrorAction SilentlyContinue)
}

# VIA / Vial の raw HID インターフェイスを探す。$ProductMask を指定すると PID の上位バイトだけで比べる
function Find-KcRawHidInterface([string]$Vid, [string]$ProductId = '', [int]$ProductHighByte = -1) {
    $found = @()
    foreach ($dev in (Get-KcPresentDevice "HID\VID_${Vid}&PID_%")) {
        if ($dev.DeviceID -notmatch "^HID\\VID_${Vid}&PID_([0-9A-F]{4})") {
            continue
        }
        $pid16 = [Convert]::ToInt32($Matches[1], 16)
        if ($ProductId -and $Matches[1] -ne $ProductId) {
            continue
        }
        if ($ProductHighByte -ge 0 -and ($pid16 -shr 8) -ne $ProductHighByte) {
            continue
        }
        if (-not (@($dev.HardwareID) -match $script:KcViaUsage)) {
            continue
        }
        $found += [pscustomobject]@{
            Vid       = $Vid
            ProductId = $pid16
            DeviceId  = $dev.DeviceID
            Path      = '\\?\' + ($dev.DeviceID -replace '\\', '#') + '#' + $script:KcHidInterfaceGuid
        }
    }
    return , $found
}

# 問い合わせ用の scriptblock (& $query <コマンド> <エコーの長さ> → 32 バイトの応答)
function New-KcRawHidQuery([string]$Path, [int]$TimeoutMs = 1500) {
    Import-KcCSharp 'RawHid.cs' 'KcRawHid'
    return {
        param([byte[]]$Command, [int]$EchoLen)
        return , ([KcRawHid]::Query($Path, $Command, $TimeoutMs, $EchoLen))
    }.GetNewClosure()
}

# ほかのアプリ (Vial / VIA / Remap) が同じデバイスと通信していないか
function Test-KcRawHidBusy([string]$Path, [int]$ListenMs = 300) {
    Import-KcCSharp 'RawHid.cs' 'KcRawHid'
    return ([KcRawHid]::CountTraffic($Path, $ListenMs) -gt 0)
}
