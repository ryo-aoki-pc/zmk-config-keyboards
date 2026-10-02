# テスト用の偽のデバイス (VIA の Keyball39、Vial の KQ-mini、ZMK Studio)。
# 期待値の JSON から「意図どおりの状態」のデバイスを作り、テストで一部を書き換えて使う。
# 読み取り専用でないコマンドを受け取ると例外を出す (許可リストの確認も兼ねる)。
#
# 偽のデバイスの状態は $script:FakeDeviceStates に番号で入れ、問い合わせ用の scriptblock は
# [scriptblock]::Create で作る (GetNewClosure() で作ると、呼び出し方によってはスクリプトの関数が
# 見えなくなるため)。

if (-not (Get-Variable -Name FakeDeviceStates -Scope Script -ErrorAction SilentlyContinue)) {
    $script:FakeDeviceStates = @{}
}

function Register-FakeDevice([hashtable]$State) {
    $id = $script:FakeDeviceStates.Count + 1
    $script:FakeDeviceStates[$id] = $State
    return $id
}

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
    $id = Register-FakeDevice $State
    $State.Query = [scriptblock]::Create("param([byte[]]`$Command, [int]`$EchoLen) Invoke-FakeQmkQuery `$script:FakeDeviceStates[$id] `$Command `$EchoLen")
    return $State
}

function Invoke-FakeQmkQuery([hashtable]$s, [byte[]]$Command, [int]$EchoLen) {
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
            } elseif ($c1 -eq 0 -and $null -ne $s.KeyballAccel -and $Command[2] -eq 3) {
                [Array]::Copy($s.KeyballAccel, 0, $r, 3, $s.KeyballAccel.Length)
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
        MacroCount = 16; MacroBytes = $macro.ToArray(); KeyballStatus = $null; KeyballAccel = $null
    }
}

# Keyball のファームのコマンド (08 00 01) の応答 ([3] 以降)
function New-FakeKeyballStatusBytes($Status) {
    $b = New-Object byte[] 29
    $b[0] = [byte](Get-KcProp $Status 'format' 1)
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
    $b[26] = [byte](Get-KcProp $Status 'aml_threshold' 0)
    return , $b
}

# Keyball のファームのコマンド (08 00 03) の応答 ([3] 以降)
function New-FakeKeyballAccelBytes($Accel) {
    $b = New-Object byte[] 9
    $i = 0
    foreach ($k in @('min_factor', 'max_factor', 'speed_threshold', 'speed_max')) {
        [Array]::Copy((ConvertTo-FakeBytesBE ([int]$Accel.$k) 2), 0, $b, $i, 2)
        $i += 2
    }
    $b[8] = [byte]$Accel.interval_ms
    return , $b
}

# 期待値どおりの Keyball39 (VIA)。-OldFirmware で 08 00 01 / 03 の無いファーム
function New-FakeKeyball($Expected, [switch]$OldFirmware) {
    $v = $Expected.readout.via
    $status = $null
    $accel = $null
    if (-not $OldFirmware) {
        $status = New-FakeKeyballStatusBytes $v.status
        $accel = New-FakeKeyballAccelBytes (@($Expected.interactive.trackball.firmware)[0].accel)
    }
    return New-FakeQmkDevice @{
        Vial = $false; Protocol = 0x000C; Uptime = 30000; LayoutOptions = [int]$v.layout_options.value
        Layers = [int]$v.layer_count; Keymap = (Copy-FakeKeymap $v.keymap)
        MacroCount = 16; MacroBytes = (New-Object byte[] 599); KeyballStatus = $status; KeyballAccel = $accel
    }
}

# ---------------------------------------------------------------------------
# ZMK Studio (zmk-studio.ps1 の関数を使って応答を作る)
# ---------------------------------------------------------------------------

function New-FakeStudioResponse([int]$RequestId, [int]$Subsystem, [byte[]]$Payload) {
    $rr = Join-KcBytes @((New-KcPbVarint 1 $RequestId), (New-KcPbBytes $Subsystem $Payload))
    return , (New-KcPbBytes 1 $rr)
}

# 期待値どおりの Studio。$State.Keymap[layer][pos] = @{ b; p1; p2 } を書き換えると状態が変わる
#   Silent: 応答しない (BLE に出力しているとき)、Notify: 応答の前に通知を挟む、Chunk: 1 回に読めるバイト数
function New-FakeStudio($Expected, $Common, [string]$Name = '') {
    if (-not $Name) {
        $Name = [string]$Expected.device.product
    }
    $ids = @{}
    $next = 300
    foreach ($b in $Common.zmk_behaviors) {
        $ids[[string]$b.display] = $next
        $next += 7
    }
    $keymap = @()
    foreach ($layer in $Expected.readout.zmk.bindings) {
        $row = @()
        foreach ($x in $layer) {
            if (-not $ids.ContainsKey([string]$x.b)) {
                $ids[[string]$x.b] = $next
                $next += 7
            }
            $row += , @{ b = [string]$x.b; p1 = [long]$x.p1; p2 = [long]$x.p2 }
        }
        $keymap += , $row
    }
    $layouts = @([string]$Expected.physical.layout_name)
    if ($Expected.id -eq 'lism') {
        $layouts += '40-Key Layout'
    }
    $state = @{
        Name = $Name; Ids = $ids; Keymap = $keymap; Layouts = $layouts; Active = 0; Unsaved = $false; Lock = 1
        Silent = $false; Notify = $true; Chunk = 7; LayerIds = $null
        Out = (New-Object 'System.Collections.Generic.List[byte]'); In = (New-KcStudioFrameDecoder)
        Requests = (New-Object 'System.Collections.Generic.List[string]')
    }
    $id = Register-FakeDevice $state
    $state.Transport = @{
        Write = [scriptblock]::Create("param([byte[]]`$Bytes) Invoke-FakeStudioWrite `$script:FakeDeviceStates[$id] `$Bytes")
        Read  = [scriptblock]::Create("param([int]`$TimeoutMs) Invoke-FakeStudioRead `$script:FakeDeviceStates[$id] `$TimeoutMs")
    }
    return $state
}

function Invoke-FakeStudioWrite([hashtable]$s, [byte[]]$Bytes) {
    Add-KcStudioFrameBytes $s.In $Bytes
    while ($s.In.Frames.Count -gt 0) {
        $req = ConvertFrom-KcProtobuf ([byte[]]$s.In.Frames.Dequeue())
        $id = [int](Get-KcPbUInt $req 1)
        $sub = 0
        foreach ($n in @(3, 4, 5)) { if (Test-KcPbHas $req $n) { $sub = $n } }
        $inner = ConvertFrom-KcProtobuf (Get-KcPbMessage $req $sub)
        $which = [int]$inner[0].Number
        $s.Requests.Add(('{0}.{1}' -f $sub, $which))
        if ($s.Silent) { continue }
        $payload = $null
        if ($sub -eq 3 -and $which -eq 1) {
            $info = Join-KcBytes @((New-KcPbBytes 1 ([System.Text.Encoding]::UTF8.GetBytes($s.Name))), (New-KcPbBytes 2 ([byte[]](1, 2, 3, 0xAB))))
            $payload = New-KcPbBytes 1 $info
        } elseif ($sub -eq 3 -and $which -eq 2) {
            $payload = New-KcPbVarint 2 $s.Lock
        } elseif ($sub -eq 4 -and $which -eq 1) {
            $packed = Join-KcBytes @($s.Ids.Values | Sort-Object | ForEach-Object { , (ConvertTo-KcVarint ([uint64]$_)) })
            $payload = New-KcPbBytes 1 (New-KcPbBytes 1 $packed)
        } elseif ($sub -eq 4 -and $which -eq 2) {
            $bid = [long](Get-KcPbUInt (ConvertFrom-KcProtobuf ([byte[]]$inner[0].Value)) 1)
            $nm = ($s.Ids.GetEnumerator() | Where-Object { $_.Value -eq $bid } | Select-Object -First 1).Key
            $payload = New-KcPbBytes 2 (Join-KcBytes @((New-KcPbVarint 1 $bid), (New-KcPbBytes 2 ([System.Text.Encoding]::UTF8.GetBytes($nm)))))
        } elseif ($sub -eq 5 -and $which -eq 1) {
            $layers = @()
            for ($l = 0; $l -lt $s.Keymap.Count; $l++) {
                $lid = $l
                if ($null -ne $s.LayerIds) { $lid = $s.LayerIds[$l] }
                $parts = @()
                if ($lid -ne 0) { $parts += , (New-KcPbVarint 1 $lid) }
                foreach ($x in $s.Keymap[$l]) {
                    $bparts = @((New-KcPbVarint 1 (ConvertTo-KcZigZag $s.Ids[$x.b])))
                    if ($x.p1 -ne 0) { $bparts += , (New-KcPbVarint 2 ([uint64]$x.p1)) }
                    if ($x.p2 -ne 0) { $bparts += , (New-KcPbVarint 3 ([uint64]$x.p2)) }
                    $parts += , (New-KcPbBytes 3 (Join-KcBytes $bparts))
                }
                $layers += , (New-KcPbBytes 1 (Join-KcBytes $parts))
            }
            $layers += , (New-KcPbVarint 2 $s.Keymap.Count)
            $payload = New-KcPbBytes 1 (Join-KcBytes $layers)
        } elseif ($sub -eq 5 -and $which -eq 3) {
            $u = 0
            if ($s.Unsaved) { $u = 1 }
            $payload = New-KcPbVarint 3 $u
        } elseif ($sub -eq 5 -and $which -eq 6) {
            $parts = @()
            if ($s.Active -ne 0) { $parts += , (New-KcPbVarint 1 $s.Active) }
            foreach ($nm in $s.Layouts) {
                $parts += , (New-KcPbBytes 2 (Join-KcBytes @((New-KcPbBytes 1 ([System.Text.Encoding]::UTF8.GetBytes($nm))), (New-KcPbBytes 2 ([byte[]]@())))))
            }
            $payload = New-KcPbBytes 6 (Join-KcBytes $parts)
        } else {
            throw ('読み取り専用でない Studio の RPC を受け取りました: {0}.{1}' -f $sub, $which)
        }
        if ($s.Notify) {
            $note = New-KcPbBytes 2 (New-KcPbBytes 5 (New-KcPbVarint 1 1))
            $s.Out.AddRange([byte[]](ConvertTo-KcStudioFrame $note))
        }
        $s.Out.AddRange([byte[]](ConvertTo-KcStudioFrame (New-FakeStudioResponse $id $sub $payload)))
    }
}

function Invoke-FakeStudioRead([hashtable]$s, [int]$TimeoutMs) {
    $n = [math]::Min($s.Chunk, $s.Out.Count)
    if ($n -eq 0) {
        Start-Sleep -Milliseconds 10
    }
    $chunk = New-Object byte[] $n
    if ($n -gt 0) {
        $s.Out.CopyTo(0, $chunk, 0, $n)
        $s.Out.RemoveRange(0, $n)
    }
    return , $chunk
}
