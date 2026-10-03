# タップホールドのシミュレータ (HoldTapSim.cs) の読み込みと、PowerShell の値からの変換。
# keyboard-check.ps1 から dot-source して使う。WPF を使わないので、どの OS でも動く。
#
# シミュレータは C# (HoldTapSim.cs) で、ZMK v0.3.0 (behavior_hold_tap.c) と QMK (vial-qmk の action_tapping.c) の
# 処理をそのまま写している。グラフの「離す時刻ごとの結果」は 1 回の表示で数百回計算するので、PowerShell では遅い。
#
# キーマップ (ハッシュテーブルで書くとき):
#   @{ Keys = @{ <位置> = @{ <レイヤー> = <バインディング> } }; Behaviors = @{ <名前> = <ZMK の設定> };
#      Qmk = <QMK の設定>; Hands = @{ <位置> = 'L' / 'R' / '*' } }
#   バインディング: @{ Kind = 'kp'; Usage; Mods; Label } / @{ Kind = 'mo'; Layer; Label } /
#     @{ Kind = 'ht'; Behavior; Hold; Tap; Src } / @{ Kind = 'mods'; Mods; Label } (QMK の mod-tap のホールド) /
#     @{ Kind = 'none' } / @{ Kind = 'other'; Label }
#   ZMK の設定: @{ Flavor; Term; QuickTap; PriorIdle; RetroTap; Hwu; HwuLinger; TriggerOnRelease; TriggerPositions }
#   QMK の設定: @{ TappingTerm; PermissiveHold; HoldOnOtherKeyPress; RetroTapping; QuickTapTerm; ChordalHold;
#                 FlowTapTerm; TapCodeDelay }
#   Cells: QMK のマトリクスのセル (同じセルの位置は QMK では同じキー。KQ-mini は Keyball の BASE の HID コード)
# 入力: @(@{ Pos; Down; T }) (T は ms)

$script:KcHtLibDir = $PSScriptRoot

function Import-KcHoldTapSim {
    if ('KcZmkHoldTapSim' -as [type]) { return }
    $source = [System.IO.File]::ReadAllText((Join-Path $script:KcHtLibDir 'HoldTapSim.cs'), [System.Text.Encoding]::UTF8)
    Add-Type -TypeDefinition $source -Language CSharp
}

function Get-KcHtValue($Object, [string]$Name, $Default) {
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    return $p.Value
}

function ConvertTo-KcHtBinding($Value) {
    Import-KcHoldTapSim
    if ($Value -is [KcHtBinding]) { return $Value }
    $b = New-Object KcHtBinding
    if ($null -eq $Value) { return $b }
    $b.Kind = [string](Get-KcHtValue $Value 'Kind' 'none')
    $b.Usage = [int](Get-KcHtValue $Value 'Usage' -1)
    $b.Mods = [int](Get-KcHtValue $Value 'Mods' 0)
    $b.Layer = [int](Get-KcHtValue $Value 'Layer' -1)
    $b.Label = [string](Get-KcHtValue $Value 'Label' '')
    $b.Behavior = [string](Get-KcHtValue $Value 'Behavior' '')
    $b.Src = [string](Get-KcHtValue $Value 'Src' '')
    $hold = Get-KcHtValue $Value 'Hold' $null
    $tap = Get-KcHtValue $Value 'Tap' $null
    if ($null -ne $hold) { $b.Hold = ConvertTo-KcHtBinding $hold }
    if ($null -ne $tap) { $b.Tap = ConvertTo-KcHtBinding $tap }
    return $b
}

function ConvertTo-KcHtZmkConfig($Value) {
    Import-KcHoldTapSim
    if ($Value -is [KcHtZmkConfig]) { return $Value }
    $c = New-Object KcHtZmkConfig
    $c.Flavor = [string](Get-KcHtValue $Value 'Flavor' 'hold-preferred')
    $c.Term = [int](Get-KcHtValue $Value 'Term' 200)
    $c.QuickTap = [int](Get-KcHtValue $Value 'QuickTap' -1)
    $c.PriorIdle = [int](Get-KcHtValue $Value 'PriorIdle' -1)
    $c.RetroTap = [bool](Get-KcHtValue $Value 'RetroTap' $false)
    $c.Hwu = [bool](Get-KcHtValue $Value 'Hwu' $false)
    $c.HwuLinger = [bool](Get-KcHtValue $Value 'HwuLinger' $false)
    $c.TriggerOnRelease = [bool](Get-KcHtValue $Value 'TriggerOnRelease' $false)
    $c.TriggerPositions = [int[]]@(Get-KcHtValue $Value 'TriggerPositions' @())
    return $c
}

function ConvertTo-KcHtQmkSettings($Value) {
    Import-KcHoldTapSim
    if ($Value -is [KcHtQmkSettings]) { return $Value }
    $q = New-Object KcHtQmkSettings
    $q.TappingTerm = [int](Get-KcHtValue $Value 'TappingTerm' 200)
    $q.PermissiveHold = [bool](Get-KcHtValue $Value 'PermissiveHold' $false)
    $q.HoldOnOtherKeyPress = [bool](Get-KcHtValue $Value 'HoldOnOtherKeyPress' $false)
    $q.RetroTapping = [bool](Get-KcHtValue $Value 'RetroTapping' $false)
    $q.QuickTapTerm = [int](Get-KcHtValue $Value 'QuickTapTerm' 200)
    $q.ChordalHold = [bool](Get-KcHtValue $Value 'ChordalHold' $false)
    $q.FlowTapTerm = [int](Get-KcHtValue $Value 'FlowTapTerm' 0)
    $q.TapCodeDelay = [int](Get-KcHtValue $Value 'TapCodeDelay' 0)
    $q.ChordalCompiled = [bool](Get-KcHtValue $Value 'ChordalCompiled' $true)
    $q.FlowCompiled = [bool](Get-KcHtValue $Value 'FlowCompiled' $true)
    return $q
}

# ハッシュテーブルのキーマップ → KcHtKeymap (KcHtKeymap ならそのまま)
function ConvertTo-KcHtKeymap($Keymap) {
    Import-KcHoldTapSim
    if ($Keymap -is [KcHtKeymap]) { return $Keymap }
    $km = New-Object KcHtKeymap
    $keys = Get-KcHtValue $Keymap 'Keys' @{}
    foreach ($pos in @($keys.Keys)) {
        $on = $keys[$pos]
        foreach ($layer in @($on.Keys)) {
            $km.Set([int]$pos, [int]$layer, (ConvertTo-KcHtBinding $on[$layer]))
        }
    }
    $behaviors = Get-KcHtValue $Keymap 'Behaviors' @{}
    foreach ($name in @($behaviors.Keys)) {
        $km.SetBehavior([string]$name, (ConvertTo-KcHtZmkConfig $behaviors[$name]))
    }
    $qmk = Get-KcHtValue $Keymap 'Qmk' $null
    if ($null -ne $qmk) { $km.Qmk = ConvertTo-KcHtQmkSettings $qmk }
    $hands = Get-KcHtValue $Keymap 'Hands' @{}
    foreach ($pos in @($hands.Keys)) {
        $km.SetHand([int]$pos, [char]([string]$hands[$pos])[0])
    }
    $cells = Get-KcHtValue $Keymap 'Cells' @{}
    foreach ($pos in @($cells.Keys)) {
        $km.SetCell([int]$pos, [int]$cells[$pos])
    }
    return $km
}

# @(@{ Pos; Down; T }) → KcHtInput[]
function ConvertTo-KcHtInputs($Events) {
    Import-KcHoldTapSim
    $list = New-Object 'System.Collections.Generic.List[KcHtInput]'
    foreach ($e in @($Events)) {
        if ($e -is [KcHtInput]) { $list.Add($e); continue }
        $list.Add([KcHtInput]::Make([int](Get-KcHtValue $e 'Pos' 0), [bool](Get-KcHtValue $e 'Down' $false), [long](Get-KcHtValue $e 'T' 0)))
    }
    return , $list.ToArray()
}

# ZMK v0.3.0。-TickMs 10 は ZMK のテスト (native_posix) と同じ時間の進み方 (HoldTapSim.cs の説明)
function Invoke-KcZmkHoldTap {
    param(
        [Parameter(Mandatory = $true)] $Keymap,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] $Events,
        [int]$TickMs = 0,
        [switch]$Trace
    )
    $km = ConvertTo-KcHtKeymap $Keymap
    return [KcZmkHoldTapSim]::Run($km, (ConvertTo-KcHtInputs $Events), $TickMs, [bool]$Trace)
}

# QMK (vial-qmk、KQ-mini)。キーマップの Qmk (設定) と Hands / Cells を使う
function Invoke-KcQmkTapHold {
    param(
        [Parameter(Mandatory = $true)] $Keymap,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] $Events,
        [switch]$Trace
    )
    $km = ConvertTo-KcHtKeymap $Keymap
    return [KcQmkTapHoldSim]::Run($km, (ConvertTo-KcHtInputs $Events), [bool]$Trace)
}
