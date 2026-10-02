# Raw Input のデバイス (キーボード・マウス) の特定: パスの解析 (USB / BLE、VID / PID、BLE のアドレス)、機種のラベル、
# 同じ物理デバイスのまとめ。input-monitor.ps1 から dot-source して使う。
# パスの解析やラベル (ConvertFrom-ImDevicePath / Get-ImDeviceLabel / New-ImDevice / Group-ImDevice) はどの OS でも動く。
# Resolve-ImDevice / Get-ImConnectedDevices だけが Windows の API (Raw Input / HID / CIM) を使う。
# lib/keyboard-check/rawhid.ps1 (Import-KcCSharp / Get-KcPresentDevice / $script:KcHidInterfaceGuid) と
# input-test.ps1 (Import-KcInputForm) が先に読み込まれている前提。
#
# Raw Input が返すデバイスのパスの例:
#   USB: \\?\HID#VID_1D50&PID_615E&MI_00&Col01#8&2f3a1b2c&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}
#   BLE: \\?\HID#{00001812-0000-1000-8000-00805f9b34fb}_DEV_VID&021d50_PID&615e_REV&0001_c3f2a1b0d9e8&Col01#9&1a2b3c4d&0&0000#{884b96c3-...}
#   末尾の GUID はキーボード (884b96c3-...) かマウス (378de44c-...) のクラス。BLE の VID の前の 2 桁は VID の種類 (02 = USB-IF)。
#   ZMK は 1 つの HID インターフェイスにキーボード (Col01)・コンシューマ (Col02)・マウス (Col03) を載せているので、
#   Col を除いた部分が同じなら同じキーボード (GroupKey)。VID / PID (と BLE のアドレス) が同じなら同じ機種 (FamilyKey)。

$script:ImClassGuidKeyboard = '884B96C3-56EF-11D1-BC8C-00A0C91405DD'
$script:ImClassGuidMouse = '378DE44C-56EF-11D1-BC8C-00A0C91405DD'

# 既知の機種 (VID / PID → ラベル)。UseName: 製品名 (USB の product string / BLE の名前) が取れればそれを使う
$script:ImKnownDevices = @(
    @{ Vid = '1D50'; Pid = '615E'; Label = 'ZMK'; UseName = $true },
    @{ Vid = '5957'; PidHigh = '02'; Label = 'Keyball39'; UseName = $false },
    @{ Vid = 'FEED'; Pid = '999C'; Label = 'KQ-mini + Keyball39'; UseName = $false }
)

function ConvertFrom-ImDevicePath([string]$Path) {
    $info = [pscustomobject]@{
        Path = [string]$Path; Transport = 'Other'; Vid = ''; Pid = ''; Addr = ''; Collection = 0; Interface = -1
        Instance = ''; Class = ''; GroupKey = [string]$Path; FamilyKey = [string]$Path
    }
    if (-not $Path) {
        return $info
    }
    $p = $Path.ToUpperInvariant()
    if ($p -match '\{([0-9A-F-]+)\}$') {
        if ($Matches[1] -eq $script:ImClassGuidKeyboard) {
            $info.Class = 'keyboard'
        } elseif ($Matches[1] -eq $script:ImClassGuidMouse) {
            $info.Class = 'mouse'
        }
    }
    if ($p -match '^\\\\\?\\HID#\{00001812-0000-1000-8000-00805F9B34FB\}_DEV_VID&([0-9A-F]{2})([0-9A-F]{4})_PID&([0-9A-F]{4})(?:_REV&[0-9A-F]{4})?_([0-9A-F]{12})(?:&COL([0-9A-F]{2}))?#([^#]+)#') {
        $info.Transport = 'BLE'
        $info.Vid = $Matches[2]
        $info.Pid = $Matches[3]
        $info.Addr = $Matches[4]
        if ($Matches[5]) {
            $info.Collection = [Convert]::ToInt32($Matches[5], 16)
        }
        $info.Instance = $Matches[6]
        $info.FamilyKey = 'BLE:{0}:{1}:{2}' -f $info.Vid, $info.Pid, $info.Addr
        $info.GroupKey = $info.FamilyKey
    } elseif ($p -match '^\\\\\?\\HID#VID_([0-9A-F]{4})&PID_([0-9A-F]{4})(?:&MI_([0-9A-F]{2}))?(?:&COL([0-9A-F]{2}))?#([^#]+)#') {
        $info.Transport = 'USB'
        $info.Vid = $Matches[1]
        $info.Pid = $Matches[2]
        if ($Matches[3]) {
            $info.Interface = [Convert]::ToInt32($Matches[3], 16)
        }
        if ($Matches[4]) {
            $info.Collection = [Convert]::ToInt32($Matches[4], 16)
        }
        $info.Instance = $Matches[5]
        $info.FamilyKey = 'USB:{0}:{1}' -f $info.Vid, $info.Pid
        # インスタンス ID の末尾 (&0000 / &0001 …) はコレクションの番号なので除く
        $info.GroupKey = 'USB:{0}:{1}:{2}:{3}' -f $info.Vid, $info.Pid, $info.Interface, ($info.Instance -replace '&[0-9A-F]+$', '')
    }
    return $info
}

# ($Pid は PowerShell の自動変数なので、引数は $ProductId)
function Get-ImKnownDevice([string]$Vid, [string]$ProductId) {
    foreach ($k in $script:ImKnownDevices) {
        if ($k.Vid -ne $Vid) {
            continue
        }
        if ($k.ContainsKey('Pid') -and $k.Pid -eq $ProductId) {
            return $k
        }
        if ($k.ContainsKey('PidHigh') -and $ProductId.Length -eq 4 -and $ProductId.Substring(0, 2) -eq $k.PidHigh) {
            return $k
        }
    }
    return $null
}

# 表示用のラベル (例: 'LisM (BLE)'、'Keyball39 (USB)'、'その他 (USB VID 046D / PID C52B)')
function Get-ImDeviceLabel($Info, [string]$Name) {
    $known = Get-ImKnownDevice $Info.Vid $Info.Pid
    if ($null -ne $known) {
        $base = $known.Label
        if ($known.UseName -and $Name) {
            $base = $Name
        }
        return ('{0} ({1})' -f $base, $Info.Transport)
    }
    if ($Info.Transport -eq 'USB') {
        if ($Name) {
            return ('{0} (USB VID {1} / PID {2})' -f $Name, $Info.Vid, $Info.Pid)
        }
        return ('その他 (USB VID {0} / PID {1})' -f $Info.Vid, $Info.Pid)
    }
    if ($Info.Transport -eq 'BLE') {
        $n = $Name
        if (-not $n) {
            $n = $Info.Addr
        }
        return ('{0} (BLE)' -f $n)
    }
    $p = [string]$Info.Path
    if ($p.Length -gt 40) {
        $p = $p.Substring(0, 40) + '…'
    }
    if (-not $p) {
        $p = '不明'
    }
    return ('その他 ({0})' -f $p)
}

# Raw Input のパス (末尾がキーボード / マウスのクラスの GUID) → HID インターフェイスのパス (Find-KcRawHidInterface と同じ形)
function Get-ImHidInterfacePath([string]$Path) {
    return ($Path -replace '\{[0-9A-Fa-f-]+\}$', $script:KcHidInterfaceGuid)
}

function New-ImDevice([int]$Id, [long]$Handle, [string]$Kind, $Info, [string]$Name) {
    return [pscustomobject]@{
        Id = $Id; Handle = $Handle; Kind = $Kind; Path = [string]$Info.Path; Transport = [string]$Info.Transport
        Vid = [string]$Info.Vid; Pid = [string]$Info.Pid; Addr = [string]$Info.Addr; Collection = [int]$Info.Collection
        Name = [string]$Name; Label = (Get-ImDeviceLabel $Info $Name); GroupKey = [string]$Info.GroupKey; FamilyKey = [string]$Info.FamilyKey
    }
}

# 記録の JSON に書く形 (キーは小文字)
function ConvertTo-ImDeviceJson($Device) {
    return [ordered]@{
        id = [int]$Device.Id; kind = [string]$Device.Kind; path = [string]$Device.Path; transport = [string]$Device.Transport
        vid = [string]$Device.Vid; pid = [string]$Device.Pid; addr = [string]$Device.Addr; collection = [int]$Device.Collection
        name = [string]$Device.Name; label = [string]$Device.Label; group = [string]$Device.GroupKey; family = [string]$Device.FamilyKey
    }
}

function ConvertFrom-ImDeviceJson($Obj) {
    $info = ConvertFrom-ImDevicePath ([string](Get-KcProp $Obj 'path' ''))
    $d = New-ImDevice -Id ([int](Get-KcProp $Obj 'id' 0)) -Handle 0 -Kind ([string](Get-KcProp $Obj 'kind' '')) -Info $info -Name ([string](Get-KcProp $Obj 'name' ''))
    # 記録した時点のラベルとまとめ方をそのまま使う
    foreach ($pair in @(@('Label', 'label'), @('GroupKey', 'group'), @('FamilyKey', 'family'), @('Transport', 'transport'))) {
        $v = Get-KcProp $Obj $pair[1] $null
        if ($null -ne $v -and [string]$v) {
            $d.($pair[0]) = [string]$v
        }
    }
    return $d
}

function Get-ImKindLabel([string]$Kind) {
    if ($Kind -eq 'key') {
        return 'キーボード'
    }
    if ($Kind -eq 'mouse') {
        return 'マウス'
    }
    return $Kind
}

function Format-ImDeviceLine($Device) {
    return ('#{0} {1} {2}' -f $Device.Id, $Device.Label, (Get-ImKindLabel $Device.Kind))
}

# 同じ物理デバイス (GroupKey) ごとにまとめる。@{ GroupKey = @(device…) } (順序は最初に現れた順)
function Group-ImDevice($Devices) {
    $groups = [ordered]@{}
    foreach ($d in @($Devices)) {
        $key = [string]$d.GroupKey
        if (-not $groups.Contains($key)) {
            $groups[$key] = @()
        }
        $groups[$key] += $d
    }
    return $groups
}

# 接続中のデバイスの一覧 (1 行 1 物理デバイス。例: 'LisM (BLE)  キーボード / マウス  [C3F2A1B0D9E8]')
function Format-ImConnectedLines($Devices) {
    $lines = @()
    $groups = Group-ImDevice $Devices
    foreach ($key in @($groups.Keys)) {
        $members = @($groups[$key])
        $kinds = @($members | ForEach-Object { Get-ImKindLabel $_.Kind } | Select-Object -Unique)
        $line = '{0,-32} {1}' -f $members[0].Label, ($kinds -join ' / ')
        if ($members[0].Transport -eq 'BLE' -and $members[0].Addr) {
            $line += ('  [{0}]' -f $members[0].Addr)
        }
        $lines += $line
    }
    if ($lines.Count -eq 0) {
        $lines += '(キーボード・マウスが見つかりません)'
    }
    return , $lines
}

# ---------------------------------------------------------------------------
# Windows 専用 (Raw Input / HID / CIM)
# ---------------------------------------------------------------------------

# USB の product string (例: 'LisM'、'Keyball39')。Raw Input のパスで開けなければ HID インターフェイスのパスで試す
function Get-ImProductName([string]$Path) {
    if (-not $Path) {
        return ''
    }
    try {
        Import-KcCSharp 'RawHid.cs' 'KcRawHid'
        $n = [KcRawHid]::GetProductString($Path)
        if (-not $n) {
            $n = [KcRawHid]::GetProductString((Get-ImHidInterfacePath $Path))
        }
        return [string]$n
    } catch {
        return ''
    }
}

# BLE のデバイス名 (ペアリングした名前。PnP の BTHLE\DEV_<アドレス> の Name)
function Get-ImBleName([string]$Addr) {
    if (-not $Addr) {
        return ''
    }
    try {
        $devs = @(Get-KcPresentDevice ('BTHLE\DEV_{0}%' -f $Addr))
        foreach ($d in $devs) {
            if ($d.Name) {
                return [string]$d.Name
            }
        }
    } catch {
        # CIM が使えないときは名前なし
    }
    return ''
}

# Raw Input のハンドル → デバイスの情報 ($Kind: 'key' / 'mouse')
function Resolve-ImDevice([long]$Handle, [string]$Kind, [int]$Id) {
    $path = ''
    try {
        $path = [string][KcInputTestForm]::GetDeviceName($Handle)
    } catch {
        $path = ''
    }
    $info = ConvertFrom-ImDevicePath $path
    $name = ''
    if ($info.Transport -ne 'Other') {
        $name = Get-ImProductName $path
        if (-not $name -and $info.Transport -eq 'BLE') {
            $name = Get-ImBleName $info.Addr
        }
    }
    return (New-ImDevice -Id $Id -Handle $Handle -Kind $Kind -Info $info -Name $name)
}

# 接続中のキーボード・マウス (Raw Input の一覧)。番号は 1 から
function Get-ImConnectedDevices {
    $out = @()
    $id = 0
    foreach ($d in @([KcInputMonitorForm]::ListDevices())) {
        $kind = 'mouse'
        if ($d.Type -eq 1) {
            $kind = 'key'
        }
        $id++
        $out += (Resolve-ImDevice ([long]$d.Handle) $kind $id)
    }
    return , $out
}
