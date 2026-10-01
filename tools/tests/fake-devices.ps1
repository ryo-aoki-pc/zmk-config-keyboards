# テスト用の偽のデバイス (VIA の Keyball39、Vial の KQ-mini、ZMK Studio)。
# 期待値の JSON から「意図どおりの状態」のデバイスを作り、テストで一部を書き換えて使う。
# 読み取り専用でないコマンドを受け取ると例外を出す (許可リストの確認も兼ねる)。

function ConvertTo-FakeBytesBE([long]$Value, [int]$Length) {
    $b = New-Object byte[] $Length
    for ($i = $Length - 1; $i -ge 0; $i--) {
        $b[$i] = [byte]($Value -band 0xFF)
        $Value = $Value -shr 8
    }
    return , $b
}

function ConvertTo-FakeBytesLE([long]$Value, [int]$Length) {
    $b = New-Object byte[] $Length
    for ($i = 0; $i -lt $Length; $i++) {
        $b[$i] = [byte]($Value -band 0xFF)
        $Value = $Value -shr 8
    }
    return , $b
}

# [レイヤー][行][列] → VIA のキーマップのバッファ (ビッグエンディアン)
function ConvertTo-FakeKeymapBytes($Keymap) {
    $list = New-Object 'System.Collections.Generic.List[byte]'
    foreach ($layer in $Keymap) {
        foreach ($row in $layer) {
            foreach ($kc in $row) {
                $list.Add([byte](([int]$kc -shr 8) -band 0xFF))
                $list.Add([byte]([int]$kc -band 0xFF))
            }
        }
    }
    return , $list.ToArray()
}

function Copy-FakeKeymap($Keymap) {
    $out = @()
    foreach ($layer in $Keymap) {
        $rows = @()
        foreach ($row in $layer) {
            $rows += , ([int[]]@($row))
        }
        $out += , $rows
    }
    return , $out
}

# ---------------------------------------------------------------------------
# VIA / Vial のデバイス
# ---------------------------------------------------------------------------

# $State を書き換えるとデバイスの状態が変わる。& $State.Query <コマンド> <エコー長> で問い合わせる
function New-FakeQmkDevice([hashtable]$State) {
    $State.Log = New-Object 'System.Collections.Generic.List[string]'
    $State.VialMode = $false
    $query = {
        param([byte[]]$Command, [int]$EchoLen)
        $s = $State
        $s.Log.Add((($Command | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))
        $r = New-Object byte[] 32
        [Array]::Copy($Command, $r, $Command.Length)
        $c0 = [int]$Command[0]
        $c1 = 0
        if ($Command.Length -gt 1) { $c1 = [int]$Command[1] }
        switch ($c0) {
            0x01 {
                $p = $s.Protocol
                if ($s.VialMode) { $p = 9 }
                $r[1] = [byte]($p -shr 8); $r[2] = [byte]($p -band 0xFF)
            }
            0x02 {
                if ($c1 -eq 1) { [Array]::Copy((ConvertTo-FakeBytesBE $s.Uptime 4), 0, $r, 2, 4) }
                elseif ($c1 -eq 2) { [Array]::Copy((ConvertTo-FakeBytesBE $s.LayoutOptions 4), 0, $r, 2, 4) }
                else { throw "unexpected 02 $c1" }
            }
            0x08 {
                if ($c1 -eq 0 -and $null -ne $s.KeyballStatus -and $Command[2] -eq 1) {
                    [Array]::Copy($s.KeyballStatus, 0, $r, 3, $s.KeyballStatus.Length)
                } elseif ($c1 -eq 0 -and $null -ne $s.KeyballStatus -and $Command[2] -eq 2) {
                    $d = [System.Text.Encoding]::ASCII.GetBytes('2026-10-01-12:00:00')
                    [Array]::Copy($d, 0, $r, 3, $d.Length)
                } elseif ($c1 -eq 2) {
                    $r[3] = 100; $r[4] = 200
                } else {
                    $r[0] = 0xFF
                }
            }
            0x0C { $r[1] = [byte]$s.MacroCount }
            0x0D { $r[1] = [byte]($s.MacroBytes.Length -shr 8); $r[2] = [byte]($s.MacroBytes.Length -band 0xFF) }
            0x0E {
                $off = ([int]$Command[1] -shl 8) -bor [int]$Command[2]
                $n = [int]$Command[3]
                for ($i = 0; $i -lt $n -and ($off + $i) -lt $s.MacroBytes.Length; $i++) { $r[4 + $i] = $s.MacroBytes[$off + $i] }
            }
            0x11 { $r[1] = [byte]$s.Layers }
            0x12 {
                $bytes = ConvertTo-FakeKeymapBytes $s.Keymap
                $off = ([int]$Command[1] -shl 8) -bor [int]$Command[2]
                $n = [int]$Command[3]
                for ($i = 0; $i -lt $n -and ($off + $i) -lt $bytes.Length; $i++) { $r[4 + $i] = $bytes[$off + $i] }
            }
            0xFE {
                if (-not $s.Vial) { $r[0] = 0xFF; break }
                if ($c1 -ne 0 -and -not $s.VialMode) { $r[0] = 0xFF; break }
                $r = New-Object byte[] 32
                switch ($c1) {
                    0x00 {
                        $s.VialMode = $true
                        $r[0] = 6
                        for ($i = 0; $i -lt 8; $i++) { $r[4 + $i] = [byte]$s.Uid[$i] }
                    }
                    0x05 { for ($i = 0; $i -lt 32; $i++) { $r[$i] = 0xFF }; $r[0] = 1; $r[1] = [byte]$s.UnlockInProgress }
                    0x09 {
                        for ($i = 0; $i -lt 32; $i++) { $r[$i] = 0xFF }
                        $gt = [int]$Command[2] -bor ([int]$Command[3] -shl 8)
                        $o = 0
                        foreach ($q in ($s.Settings.Keys | Sort-Object)) {
                            if ($q -gt $gt -and $o -lt 32) {
                                $r[$o] = [byte]($q -band 0xFF); $r[$o + 1] = [byte]($q -shr 8); $o += 2
                            }
                        }
                    }
                    0x0A {
                        $q = [int]$Command[2] -bor ([int]$Command[3] -shl 8)
                        if ($s.Settings.ContainsKey($q)) {
                            [Array]::Copy((ConvertTo-FakeBytesLE $s.Settings[$q] 4), 0, $r, 1, 4)
                        } else {
                            $r[0] = 0xFF
                        }
                    }
                    0x0D {
                        $op = [int]$Command[2]
                        $idx = [int]$Command[3]
                        switch ($op) {
                            0x00 { $r[0] = 32; $r[1] = 32; $r[2] = 32; $r[3] = 32; $r[31] = 3 }
                            0x01 { [Array]::Copy($s.TapDance[$idx], 0, $r, 1, 10) }
                            0x03 { [Array]::Copy($s.Combo[$idx], 0, $r, 1, 10) }
                            0x05 { [Array]::Copy($s.KeyOverride[$idx], 0, $r, 1, 10) }
                            0x07 { [Array]::Copy($s.AltRepeat[$idx], 0, $r, 1, 6) }
                            default { throw ('書き込みのコマンドを受け取りました: FE 0D {0:X2}' -f $op) }
                        }
                    }
                    default { throw ('許可されていない Vial コマンドを受け取りました: FE {0:X2}' -f $c1) }
                }
            }
            default { throw ('許可されていないコマンドを受け取りました: {0:X2}' -f $c0) }
        }
        return , $r
    }.GetNewClosure()
    $State.Query = $query
    return $State
}

function ConvertTo-FakeStruct([int[]]$U16, [int[]]$U8 = @()) {
    $list = New-Object 'System.Collections.Generic.List[byte]'
    foreach ($v in $U16) { $list.Add([byte]($v -band 0xFF)); $list.Add([byte](($v -shr 8) -band 0xFF)) }
    foreach ($v in $U8) { $list.Add([byte]$v) }
    while ($list.Count -lt 10) { $list.Add(0) }
    return , $list.ToArray()
}

# 期待値どおりの KQ-mini (Vial)
function New-FakeKqMini($Expected) {
    $v = $Expected.readout.vial
    $settings = @{}
    for ($q = 1; $q -le 27; $q++) { if ($q -ne 8) { $settings[$q] = 0 } }
    foreach ($s in $v.settings) { $settings[[int]$s.qsid] = [long]$s.value }
    $td = @()
    for ($i = 0; $i -lt 32; $i++) { $td += , (ConvertTo-FakeStruct @(0, 0, 0, 0, 200)) }
    foreach ($t in $v.tap_dance.entries) {
        $td[[int]$t.index] = ConvertTo-FakeStruct @([int]$t.on_tap, [int]$t.on_hold, [int]$t.on_double_tap, [int]$t.on_tap_hold, [int]$t.term)
    }
    $ko = @()
    for ($i = 0; $i -lt 32; $i++) { $ko += , (ConvertTo-FakeStruct @(0, 0, 0xFFFF) @(0, 0, 0, 0x07)) }
    foreach ($k in $v.key_override.entries) {
        $ko[[int]$k.index] = ConvertTo-FakeStruct @([int]$k.trigger, [int]$k.replacement, [int]$k.layers) @([int]$k.trigger_mods, [int]$k.negative_mod_mask, [int]$k.suppressed_mods, [int]$k.options)
    }
    $combo = @()
    $alt = @()
    for ($i = 0; $i -lt 32; $i++) { $combo += , (ConvertTo-FakeStruct @(0, 0, 0, 0, 0)); $alt += , (New-Object byte[] 6) }
    $macro = New-Object 'System.Collections.Generic.List[byte]'
    foreach ($m in $v.macro.entries) {
        if ($m.hex) { foreach ($h in ($m.hex -split ' ')) { $macro.Add([Convert]::ToByte($h, 16)) } }
        $macro.Add(0)
    }
    while ($macro.Count -lt 2863) { $macro.Add(0) }
    return New-FakeQmkDevice @{
        Vial = $true; Protocol = 0x000C; Uptime = 60000; LayoutOptions = 0; Uid = @($Expected.device.vial_uid)
        UnlockInProgress = 0; Layers = [int]$v.layer_count; Keymap = (Copy-FakeKeymap $v.keymap)
        Settings = $settings; TapDance = $td; KeyOverride = $ko; Combo = $combo; AltRepeat = $alt
        MacroCount = 16; MacroBytes = $macro.ToArray(); KeyballStatus = $null
    }
}

# Keyball のファームのコマンド (08 00 01) の応答 ([3] 以降)
function New-FakeKeyballStatusBytes($Status) {
    $b = New-Object byte[] 29
    $b[0] = 1
    $b[1] = 39
    $b[2] = 0x01 -bor 0x02 -bor 0x10 -bor 0x40
    $b[3] = [byte]$Status.cpi
    $b[4] = 0
    $b[5] = [byte]$Status.scroll_div
    $b[6] = 0
    $b[7] = [byte]$Status.scroll_snap
    $b[8] = [byte]$Status.aml_layer
    [Array]::Copy((ConvertTo-FakeBytesBE $Status.aml_timeout 2), 0, $b, 9, 2)
    [Array]::Copy((ConvertTo-FakeBytesBE $Status.aml_delay 2), 0, $b, 11, 2)
    $b[13] = 25
    $b[14] = [byte]$Status.scroll_layer
    $b[24] = [byte]$Status.cpi_default
    $b[25] = [byte]$Status.scroll_div_default
    return , $b
}

# 期待値どおりの Keyball39 (VIA)。-OldFirmware で 08 00 01 の無いファーム
function New-FakeKeyball($Expected, [switch]$OldFirmware) {
    $v = $Expected.readout.via
    $status = $null
    if (-not $OldFirmware) {
        $status = New-FakeKeyballStatusBytes $v.status
    }
    return New-FakeQmkDevice @{
        Vial = $false; Protocol = 0x000C; Uptime = 30000; LayoutOptions = [int]$v.layout_options.value
        Layers = [int]$v.layer_count; Keymap = (Copy-FakeKeymap $v.keymap)
        MacroCount = 16; MacroBytes = (New-Object byte[] 599); KeyballStatus = $status
    }
}
