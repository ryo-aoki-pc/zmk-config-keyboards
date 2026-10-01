# 期待値 (tools/expected/*.json) の読み込みと、キーコード・バインディングの表示名。
# keyboard-check.ps1 から dot-source して使う。Windows PowerShell 5.1 / PowerShell 7 の両方で動く。

# JSON を UTF-8 で読む (Get-Content は既定で ANSI として読むため日本語が化ける)
function Read-KcJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "期待値のファイルがありません: $Path"
    }
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return ($text | ConvertFrom-Json)
}

$script:KcExpectedCache = @{}

# 期待値の JSON (id: common / kq-mini / keyball39 / lism / kukey42 / aroundfortyrb / pyuron / roba / torabo-tsuki-lp) を読む
function Get-KcExpected([string]$Id, [string]$Dir) {
    $key = "$Dir|$Id"
    if (-not $script:KcExpectedCache.ContainsKey($key)) {
        $script:KcExpectedCache[$key] = Read-KcJson (Join-Path $Dir "$Id.json")
    }
    return $script:KcExpectedCache[$key]
}

# StrictMode でも使えるプロパティの取得 (無ければ $Default)
function Get-KcProp($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) {
        return $Default
    }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $Default
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) {
        return $Default
    }
    return $p.Value
}

# [[値, 名前], ...] → @{ 値 = 名前 }
function New-KcLookup($Pairs) {
    $map = @{}
    foreach ($pair in @($Pairs)) {
        $map[[long]$pair[0]] = [string]$pair[1]
    }
    return $map
}

function Format-KcHex([long]$Value, [int]$Digits = 4) {
    return ('0x{0:X' + $Digits + '}') -f $Value
}

# ---------------------------------------------------------------------------
# QMK キーコード (Keyball39: keycodes 0.0.3 / KQ-mini: 0.0.7。表示に使う範囲は同じ)
# ---------------------------------------------------------------------------

# $Common: common.json、$Expected: 機種の JSON (custom_keycodes / layers を使う)
function New-KcQmkNames($Common, $Expected) {
    $custom = @{}
    $readout = Get-KcProp $Expected 'readout'
    foreach ($kind in @('via', 'vial')) {
        $r = Get-KcProp $readout $kind
        if ($null -ne $r) {
            $custom = New-KcLookup (Get-KcProp $r 'custom_keycodes' @())
        }
    }
    $layers = @{}
    foreach ($l in @(Get-KcProp $Expected 'layers' @())) {
        $layers[[int]$l.index] = [string]$l.name
    }
    return @{
        Basic  = New-KcLookup $Common.qmk_basic_names
        Custom = $custom
        Layers = $layers
    }
}

$script:KcQmkModNames = @{ 1 = 'CTL'; 2 = 'SFT'; 4 = 'ALT'; 8 = 'GUI' }
$script:KcQmkRgbNames = @{
    0x7820 = 'RGB_TOG'; 0x7821 = 'RGB_MOD'; 0x7822 = 'RGB_RMOD'; 0x7823 = 'RGB_HUI'; 0x7824 = 'RGB_HUD'
    0x7825 = 'RGB_SAI'; 0x7826 = 'RGB_SAD'; 0x7827 = 'RGB_VAI'; 0x7828 = 'RGB_VAD'
}

function Format-KcQmkMods([int]$Mod5) {
    $side = 'L'
    if ($Mod5 -band 0x10) {
        $side = 'R'
    }
    $parts = @()
    foreach ($bit in @(1, 2, 4, 8)) {
        if ($Mod5 -band $bit) {
            $parts += ($side + $script:KcQmkModNames[$bit])
        }
    }
    if ($parts.Count -eq 0) {
        return '0'
    }
    return ($parts -join '|')
}

function Format-KcQmkBasic([int]$Value, $Names) {
    if ($Names.Basic.ContainsKey([long]$Value)) {
        return $Names.Basic[[long]$Value]
    }
    return (Format-KcHex $Value 2)
}

# 16 ビットの QMK キーコード → 表示名 (例: LCTL_T(KC_A)、LT(2, KC_SPACE)、MO(6))
function Format-KcQmkKeycode([int]$Value, $Names) {
    if ($Names.Custom.ContainsKey([long]$Value)) {
        return $Names.Custom[[long]$Value]
    }
    if ($Value -le 0xFF) {
        return (Format-KcQmkBasic $Value $Names)
    }
    if ($Value -le 0x1FFF) {
        # QK_MODS: 修飾付きのキー
        $mods = ($Value -shr 8) -band 0x1F
        $inner = Format-KcQmkBasic ($Value -band 0xFF) $Names
        return ('{0}({1})' -f (Format-KcQmkMods $mods), $inner)
    }
    if ($Value -le 0x3FFF) {
        $mods = ($Value -shr 8) -band 0x1F
        return ('MT({0}, {1})' -f (Format-KcQmkMods $mods), (Format-KcQmkBasic ($Value -band 0xFF) $Names))
    }
    if ($Value -le 0x4FFF) {
        return ('LT({0}, {1})' -f (($Value -shr 8) -band 0xF), (Format-KcQmkBasic ($Value -band 0xFF) $Names))
    }
    $layerOps = @(
        @(0x5200, 'TO'), @(0x5220, 'MO'), @(0x5240, 'DF'), @(0x5260, 'TG'), @(0x5280, 'OSL'), @(0x52C0, 'TT')
    )
    foreach ($op in $layerOps) {
        if ($Value -ge $op[0] -and $Value -lt ($op[0] + 0x20)) {
            $n = $Value - $op[0]
            $text = '{0}({1})' -f $op[1], $n
            if ($Names.Layers.ContainsKey($n)) {
                $text += ' ' + $Names.Layers[$n]
            }
            return $text
        }
    }
    if ($Value -ge 0x52A0 -and $Value -lt 0x52C0) {
        return ('OSM({0})' -f (Format-KcQmkMods ($Value -band 0x1F)))
    }
    if ($Value -ge 0x5700 -and $Value -le 0x57FF) {
        return ('TD({0})' -f ($Value - 0x5700))
    }
    if ($Value -ge 0x7700 -and $Value -le 0x777F) {
        return ('M{0}' -f ($Value - 0x7700))
    }
    if ($script:KcQmkRgbNames.ContainsKey($Value)) {
        return $script:KcQmkRgbNames[$Value]
    }
    if ($Value -eq 0x7C00) {
        return 'QK_BOOT'
    }
    if ($Value -eq 0x7C01) {
        return 'QK_REBOOT'
    }
    if ($Value -ge 0x7E00 -and $Value -le 0x7E3F) {
        return ('USER{0:D2}' -f ($Value - 0x7E00))
    }
    return (Format-KcHex $Value 4)
}

# ---------------------------------------------------------------------------
# ZMK のバインディング
# ---------------------------------------------------------------------------

function New-KcZmkNames($Common, $Expected) {
    $hid = @{}
    foreach ($k in @($Common.hid_keys)) {
        if ($k.zmk) {
            $hid[[long]$k.usage] = [string]$k.zmk
        }
    }
    $heads = @{}
    foreach ($b in @($Common.zmk_behaviors)) {
        $heads[[string]$b.display] = $b
    }
    $layers = @{}
    foreach ($l in @(Get-KcProp $Expected 'layers' @())) {
        $alias = Get-KcProp $l 'alias' ''
        if (-not $alias) {
            $alias = [string]$l.name
        }
        $layers[[int]$l.index] = $alias
    }
    return @{
        Hid      = $hid
        Heads    = $heads
        Bt       = New-KcLookup $Common.zmk_bt
        Out      = New-KcLookup $Common.zmk_out
        Mouse    = New-KcLookup $Common.zmk_mouse_buttons
        Mods     = @($Common.zmk_mods)
        Layers   = $layers
    }
}

# ZMK のキーコード ((修飾 << 24) | (ページ << 16) | usage) → 例: LS(LC(RIGHT_ARROW))
function Format-KcZmkKeycode([long]$Value, $Names) {
    $mods = ($Value -shr 24) -band 0xFF
    $page = ($Value -shr 16) -band 0xFF
    $usage = $Value -band 0xFFFF
    if ($page -eq 7 -and $Names.Hid.ContainsKey([long]$usage)) {
        $text = $Names.Hid[[long]$usage]
    } else {
        $text = 'page{0}:{1}' -f $page, (Format-KcHex $usage 2)
    }
    foreach ($m in $Names.Mods) {
        if ($mods -band [int]$m[0]) {
            $text = '{0}({1})' -f $m[1], $text
        }
    }
    return $text
}

function Format-KcZmkLayer([long]$Index, $Names) {
    if ($Names.Layers.ContainsKey([int]$Index)) {
        return $Names.Layers[[int]$Index]
    }
    return [string]$Index
}

# ビヘイビアの表示名と引数 → 例: &mt LEFT_CONTROL A、&lt VIM_BASE SPACE、&mm_vim_w
function Format-KcZmkBinding([string]$Behavior, [long]$P1, [long]$P2, $Names) {
    if (-not $Names.Heads.ContainsKey($Behavior)) {
        if ($P1 -eq 0 -and $P2 -eq 0) {
            return '&' + $Behavior.ToLowerInvariant()
        }
        return ('&{0} {1} {2}' -f $Behavior.ToLowerInvariant(), $P1, $P2)
    }
    $b = $Names.Heads[$Behavior]
    $parts = @('&' + $b.head)
    $params = @($b.params)
    $values = @($P1, $P2)
    for ($i = 0; $i -lt $params.Count; $i++) {
        $v = $values[$i]
        switch ([string]$params[$i]) {
            'keycode' { $parts += (Format-KcZmkKeycode $v $Names) }
            'layer' { $parts += (Format-KcZmkLayer $v $Names) }
            'bt' {
                if ($Names.Bt.ContainsKey($v)) { $parts += $Names.Bt[$v] } else { $parts += [string]$v }
            }
            'out' {
                if ($Names.Out.ContainsKey($v)) { $parts += $Names.Out[$v] } else { $parts += [string]$v }
            }
            'mouse_button' {
                if ($Names.Mouse.ContainsKey($v)) { $parts += $Names.Mouse[$v] } else { $parts += [string]$v }
            }
            default { $parts += [string]$v }
        }
    }
    if ($b.head -eq 'bt' -and $parts.Count -eq 3 -and $P1 -ne 3 -and $P1 -ne 5) {
        $parts = $parts[0..1]
    }
    return ($parts -join ' ')
}

# HID usage ↔ スキャンコードの表 (Raw Input のキーを usage に戻すため)
function New-KcScanTable($Common) {
    $byScan = @{}
    $byUsage = @{}
    foreach ($k in @($Common.hid_keys)) {
        $key = '{0}:{1}' -f [int]$k.prefix, [int]$k.scan
        if (-not $byScan.ContainsKey($key)) {
            $byScan[$key] = [int]$k.usage
        }
        $byUsage[[int]$k.usage] = $k
    }
    return @{ ByScan = $byScan; ByUsage = $byUsage }
}

function Get-KcUsageLabel([int]$Usage, $ScanTable) {
    if ($ScanTable.ByUsage.ContainsKey($Usage)) {
        return [string]$ScanTable.ByUsage[$Usage].label
    }
    return (Format-KcHex $Usage 2)
}
