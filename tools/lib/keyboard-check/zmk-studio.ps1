# ZMK Studio (ZMK v0.3.0) の RPC による読み出し検査。keyboard-check.ps1 から dot-source して使う。
# expected.ps1 と results.ps1 が先に読み込まれている前提。
#
# Studio 版のファーム (flash-zmk の「s」/ -Studio) を書いた右手側 (セントラル) を USB でつなぐと、
# USB のシリアルポートで RPC を受け付ける (CONFIG_ZMK_STUDIO_LOCKING=n なのでアンロックは不要)。
#   フレーム: 0xAB (SOF) + データ + 0xAD (EOF)。データ中の 0xAB / 0xAC / 0xAD は 0xAC (ESC) を前に付ける
#   データ: zmk.studio.Request / Response (protobuf、zmk-studio-messages @ 6cb4c28)
# 送るのは読み取りの RPC だけ (get_device_info / get_lock_state / list_all_behaviors /
# get_behavior_details / get_keymap / get_physical_layouts / check_unsaved_changes)。
#
# Studio は、キーボードが今キー入力を送っている先 (USB か BLE) でしか応答しない。BLE に出力しているときは
# 応答が無いので、USB 出力 (&out OUT_USB) に切り替えるよう案内する。

$script:KcStudioSof = 0xAB
$script:KcStudioEsc = 0xAC
$script:KcStudioEof = 0xAD
$script:KcStudioErrors = @{
    0 = '一般的なエラー'; 1 = 'ロックされています (UNLOCK_REQUIRED)'; 2 = 'この RPC はありません (RPC_NOT_FOUND)'
    3 = '要求を解釈できません (MSG_DECODE_FAILED)'; 4 = '応答を作れません (MSG_ENCODE_FAILED)'
}

# ---------------------------------------------------------------------------
# protobuf (必要な分だけ)
# ---------------------------------------------------------------------------

function ConvertTo-KcVarint([uint64]$Value) {
    $out = New-Object 'System.Collections.Generic.List[byte]'
    do {
        $b = [byte]($Value -band 0x7F)
        $Value = $Value -shr 7
        if ($Value -ne 0) {
            $b = $b -bor 0x80
        }
        $out.Add($b)
    } while ($Value -ne 0)
    return , $out.ToArray()
}

function ConvertTo-KcZigZag([long]$Value) {
    if ($Value -ge 0) {
        return [uint64]($Value * 2)
    }
    return [uint64]((-$Value) * 2 - 1)
}

function ConvertFrom-KcZigZag([uint64]$Value) {
    if (($Value -band 1) -eq 0) {
        return [long]($Value -shr 1)
    }
    return [long](0 - [long](($Value + 1) -shr 1))
}

# 1 つのフィールド: 数値 (varint) / バイト列 (length-delimited)
function New-KcPbVarint([int]$Number, [uint64]$Value) {
    $tag = ConvertTo-KcVarint ([uint64]($Number -shl 3))
    return , ([byte[]]($tag + (ConvertTo-KcVarint $Value)))
}

function New-KcPbBytes([int]$Number, [byte[]]$Payload) {
    $tag = ConvertTo-KcVarint ([uint64](($Number -shl 3) -bor 2))
    $len = ConvertTo-KcVarint ([uint64]$Payload.Length)
    return , ([byte[]]($tag + $len + $Payload))
}

function Join-KcBytes([object[]]$Parts) {
    $list = New-Object 'System.Collections.Generic.List[byte]'
    foreach ($p in $Parts) {
        if ($null -ne $p) {
            $list.AddRange([byte[]]$p)
        }
    }
    return , $list.ToArray()
}

# メッセージ → フィールドの一覧 [{Number; Wire; Value}] (Value: varint は UInt64、length-delimited は byte[])
function ConvertFrom-KcProtobuf([byte[]]$Bytes) {
    $fields = New-Object 'System.Collections.Generic.List[object]'
    if ($null -eq $Bytes) {
        return , $fields.ToArray()
    }
    $pos = 0
    $n = $Bytes.Length
    while ($pos -lt $n) {
        [uint64]$key = 0
        $shift = 0
        do {
            if ($pos -ge $n) { throw 'protobuf のタグが途中で切れています' }
            $b = $Bytes[$pos++]
            $key = $key -bor ([uint64]($b -band 0x7F) -shl $shift)
            $shift += 7
        } while ($b -band 0x80)
        $number = [int]($key -shr 3)
        $wire = [int]($key -band 7)
        switch ($wire) {
            0 {
                [uint64]$v = 0
                $shift = 0
                do {
                    if ($pos -ge $n) { throw 'protobuf の数値が途中で切れています' }
                    $b = $Bytes[$pos++]
                    $v = $v -bor ([uint64]($b -band 0x7F) -shl $shift)
                    $shift += 7
                } while ($b -band 0x80)
                $fields.Add([pscustomobject]@{ Number = $number; Wire = 0; Value = $v })
            }
            2 {
                [uint64]$len = 0
                $shift = 0
                do {
                    if ($pos -ge $n) { throw 'protobuf の長さが途中で切れています' }
                    $b = $Bytes[$pos++]
                    $len = $len -bor ([uint64]($b -band 0x7F) -shl $shift)
                    $shift += 7
                } while ($b -band 0x80)
                if ($pos + [int]$len -gt $n) { throw 'protobuf のデータが途中で切れています' }
                $payload = New-Object byte[] ([int]$len)
                [Array]::Copy($Bytes, $pos, $payload, 0, [int]$len)
                $pos += [int]$len
                $fields.Add([pscustomobject]@{ Number = $number; Wire = 2; Value = $payload })
            }
            1 {
                $pos += 8
                $fields.Add([pscustomobject]@{ Number = $number; Wire = 1; Value = $null })
            }
            5 {
                $pos += 4
                $fields.Add([pscustomobject]@{ Number = $number; Wire = 5; Value = $null })
            }
            default { throw ('protobuf の知らない wire type です: {0}' -f $wire) }
        }
    }
    return , $fields.ToArray()
}

# 番号が $Number のフィールドを順に出力する (呼び出し側で @() に入れる)
function Get-KcPbAll($Fields, [int]$Number) {
    foreach ($f in $Fields) {
        if ($f.Number -eq $Number) {
            $f
        }
    }
}

# 数値のフィールド (無ければ $Default。proto3 は 0 を省くので既定値は 0)
function Get-KcPbUInt($Fields, [int]$Number, [uint64]$Default = 0) {
    $all = @(Get-KcPbAll $Fields $Number | Where-Object { $_.Wire -eq 0 })
    if ($all.Count -eq 0) {
        return $Default
    }
    return [uint64]$all[$all.Count - 1].Value
}

function Get-KcPbMessage($Fields, [int]$Number) {
    $all = @(Get-KcPbAll $Fields $Number | Where-Object { $_.Wire -eq 2 })
    if ($all.Count -eq 0) {
        return $null
    }
    return , ([byte[]]$all[$all.Count - 1].Value)
}

function Get-KcPbString($Fields, [int]$Number) {
    $b = Get-KcPbMessage $Fields $Number
    if ($null -eq $b) {
        return ''
    }
    return [System.Text.Encoding]::UTF8.GetString($b)
}

function Test-KcPbHas($Fields, [int]$Number) {
    return (@(Get-KcPbAll $Fields $Number).Count -gt 0)
}

# repeated uint32 (packed と unpacked の両方)
function Get-KcPbRepeatedUInt($Fields, [int]$Number) {
    $out = New-Object 'System.Collections.Generic.List[uint64]'
    foreach ($f in (Get-KcPbAll $Fields $Number)) {
        if ($f.Wire -eq 0) {
            $out.Add([uint64]$f.Value)
        } elseif ($f.Wire -eq 2) {
            $b = [byte[]]$f.Value
            $pos = 0
            while ($pos -lt $b.Length) {
                [uint64]$v = 0
                $shift = 0
                do {
                    $x = $b[$pos++]
                    $v = $v -bor ([uint64]($x -band 0x7F) -shl $shift)
                    $shift += 7
                } while ($x -band 0x80)
                $out.Add($v)
            }
        }
    }
    return , $out.ToArray()
}

# ---------------------------------------------------------------------------
# フレーム
# ---------------------------------------------------------------------------

function ConvertTo-KcStudioFrame([byte[]]$Payload) {
    $list = New-Object 'System.Collections.Generic.List[byte]'
    $list.Add([byte]$script:KcStudioSof)
    foreach ($b in $Payload) {
        if ($b -eq $script:KcStudioSof -or $b -eq $script:KcStudioEsc -or $b -eq $script:KcStudioEof) {
            $list.Add([byte]$script:KcStudioEsc)
        }
        $list.Add($b)
    }
    $list.Add([byte]$script:KcStudioEof)
    return , $list.ToArray()
}

function New-KcStudioFrameDecoder {
    return @{
        State  = 'idle'
        Buffer = New-Object 'System.Collections.Generic.List[byte]'
        Frames = New-Object 'System.Collections.Generic.Queue[object]'
    }
}

# 受け取ったバイト列を状態機械に通し、そろったフレームを $Decoder.Frames に入れる
# (フレームが複数回の読み出しに分かれて届いても扱える。ZMK の msg_framing.c と同じ動き)
function Add-KcStudioFrameBytes($Decoder, [byte[]]$Bytes) {
    foreach ($b in $Bytes) {
        switch ($Decoder.State) {
            'idle' {
                if ($b -eq $script:KcStudioSof) {
                    $Decoder.Buffer.Clear()
                    $Decoder.State = 'data'
                }
            }
            'data' {
                if ($b -eq $script:KcStudioSof) {
                    $Decoder.Buffer.Clear()
                } elseif ($b -eq $script:KcStudioEsc) {
                    $Decoder.State = 'escaped'
                } elseif ($b -eq $script:KcStudioEof) {
                    $Decoder.Frames.Enqueue($Decoder.Buffer.ToArray())
                    $Decoder.Buffer.Clear()
                    $Decoder.State = 'idle'
                } else {
                    $Decoder.Buffer.Add($b)
                }
            }
            'escaped' {
                $Decoder.Buffer.Add($b)
                $Decoder.State = 'data'
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 要求と応答
# ---------------------------------------------------------------------------

# Request { request_id = 1; oneof subsystem { core = 3; behaviors = 4; keymap = 5 } }
function New-KcStudioRequest([int]$RequestId, [int]$Subsystem, [byte[]]$Inner) {
    return , (Join-KcBytes @((New-KcPbVarint 1 $RequestId), (New-KcPbBytes $Subsystem $Inner)))
}

$script:KcStudioRequests = @{
    GetDeviceInfo       = @{ Subsystem = 3; Inner = { New-KcPbVarint 1 1 } }
    GetLockState        = @{ Subsystem = 3; Inner = { New-KcPbVarint 2 1 } }
    ListAllBehaviors    = @{ Subsystem = 4; Inner = { New-KcPbVarint 1 1 } }
    GetKeymap           = @{ Subsystem = 5; Inner = { New-KcPbVarint 1 1 } }
    CheckUnsavedChanges = @{ Subsystem = 5; Inner = { New-KcPbVarint 3 1 } }
    GetPhysicalLayouts  = @{ Subsystem = 5; Inner = { New-KcPbVarint 6 1 } }
}

# Response { oneof { RequestResponse request_response = 1; Notification notification = 2 } }
# RequestResponse { request_id = 1; oneof { meta = 2; core = 3; behaviors = 4; keymap = 5 } }
function ConvertFrom-KcStudioResponse([byte[]]$Bytes) {
    $top = ConvertFrom-KcProtobuf $Bytes
    if (Test-KcPbHas $top 2) {
        return [pscustomobject]@{ Kind = 'notification'; RequestId = 0; Subsystem = 0; Payload = $null; MetaError = $null }
    }
    $rr = Get-KcPbMessage $top 1
    if ($null -eq $rr) {
        throw 'Studio の応答を解釈できません'
    }
    $f = ConvertFrom-KcProtobuf $rr
    $id = [int](Get-KcPbUInt $f 1)
    foreach ($sub in @(2, 3, 4, 5)) {
        $payload = Get-KcPbMessage $f $sub
        if ($null -ne $payload -or (Test-KcPbHas $f $sub)) {
            if ($null -eq $payload) {
                $payload = [byte[]]@()
            }
            $metaError = $null
            if ($sub -eq 2) {
                $mf = ConvertFrom-KcProtobuf $payload
                if (Test-KcPbHas $mf 2) {
                    $metaError = [int](Get-KcPbUInt $mf 2)
                } else {
                    $metaError = -1
                }
            }
            return [pscustomobject]@{ Kind = 'response'; RequestId = $id; Subsystem = $sub; Payload = $payload; MetaError = $metaError }
        }
    }
    return [pscustomobject]@{ Kind = 'response'; RequestId = $id; Subsystem = 0; Payload = [byte[]]@(); MetaError = $null }
}

# セッション: @{ Transport = @{ Write = { param([byte[]]$b) }; Read = { param([int]$timeoutMs) byte[] } }; ... }
function New-KcStudioSession($Transport) {
    return @{ Transport = $Transport; Decoder = (New-KcStudioFrameDecoder); NextId = 1 }
}

# 1 つの RPC を送り、同じ request_id の応答の中身 (subsystem の Response) を返す。通知は読み飛ばす
function Invoke-KcStudioRpc($Session, [int]$Subsystem, [byte[]]$Inner, [int]$TimeoutMs = 3000) {
    $id = $Session.NextId
    $Session.NextId = ($id % 120) + 1
    $frame = ConvertTo-KcStudioFrame (New-KcStudioRequest $id $Subsystem $Inner)
    & $Session.Transport.Write $frame
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ($true) {
        while ($Session.Decoder.Frames.Count -gt 0) {
            $resp = ConvertFrom-KcStudioResponse ([byte[]]$Session.Decoder.Frames.Dequeue())
            if ($resp.Kind -ne 'response' -or $resp.RequestId -ne $id) {
                continue
            }
            if ($resp.Subsystem -eq 2) {
                $msg = 'Studio がエラーを返しました'
                if ($script:KcStudioErrors.ContainsKey($resp.MetaError)) {
                    $msg += ': ' + $script:KcStudioErrors[$resp.MetaError]
                }
                $ex = New-Object System.InvalidOperationException($msg)
                $ex.Data['StudioError'] = $resp.MetaError
                throw $ex
            }
            return , ([byte[]]$resp.Payload)
        }
        $remaining = [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds
        if ($remaining -le 0) {
            $ex = New-Object System.TimeoutException('ZMK Studio から応答がありません')
            throw $ex
        }
        $chunk = & $Session.Transport.Read ([math]::Min($remaining, 200))
        if ($null -ne $chunk -and @($chunk).Count -gt 0) {
            Add-KcStudioFrameBytes $Session.Decoder ([byte[]]$chunk)
        }
    }
}

function Invoke-KcStudioNamed($Session, [string]$Name, [int]$TimeoutMs = 3000) {
    $r = $script:KcStudioRequests[$Name]
    return , (Invoke-KcStudioRpc $Session $r.Subsystem (& $r.Inner) $TimeoutMs)
}

function Read-KcStudioDeviceInfo($Session, [int]$TimeoutMs = 3000) {
    $core = ConvertFrom-KcProtobuf (Invoke-KcStudioNamed $Session 'GetDeviceInfo' $TimeoutMs)
    $info = ConvertFrom-KcProtobuf (Get-KcPbMessage $core 1)
    $serial = Get-KcPbMessage $info 2
    $serialHex = ''
    if ($null -ne $serial) {
        $serialHex = (@($serial) | ForEach-Object { '{0:X2}' -f $_ }) -join ''
    }
    return [pscustomobject]@{ Name = (Get-KcPbString $info 1); Serial = $serialHex }
}

function Read-KcStudioLockState($Session) {
    $core = ConvertFrom-KcProtobuf (Invoke-KcStudioNamed $Session 'GetLockState')
    return [int](Get-KcPbUInt $core 2)
}

# ビヘイビアの ID → 表示名 (display-name、無ければ label / ノード名)
function Read-KcStudioBehaviors($Session) {
    $b = ConvertFrom-KcProtobuf (Invoke-KcStudioNamed $Session 'ListAllBehaviors')
    $list = ConvertFrom-KcProtobuf (Get-KcPbMessage $b 1)
    $ids = Get-KcPbRepeatedUInt $list 1
    $names = @{}
    foreach ($id in $ids) {
        $inner = New-KcPbBytes 2 (New-KcPbVarint 1 $id)
        $resp = ConvertFrom-KcProtobuf (Invoke-KcStudioRpc $Session 4 $inner)
        $details = ConvertFrom-KcProtobuf (Get-KcPbMessage $resp 2)
        $names[[long]$id] = Get-KcPbString $details 2
    }
    return $names
}

function Read-KcStudioPhysicalLayouts($Session) {
    $k = ConvertFrom-KcProtobuf (Invoke-KcStudioNamed $Session 'GetPhysicalLayouts')
    $pl = ConvertFrom-KcProtobuf (Get-KcPbMessage $k 6)
    $layouts = @()
    foreach ($f in (Get-KcPbAll $pl 2)) {
        $lf = ConvertFrom-KcProtobuf ([byte[]]$f.Value)
        $layouts += [pscustomobject]@{ Name = (Get-KcPbString $lf 1); KeyCount = @(Get-KcPbAll $lf 2).Count }
    }
    return [pscustomobject]@{ Active = [int](Get-KcPbUInt $pl 1); Layouts = $layouts }
}

function Read-KcStudioKeymap($Session) {
    $k = ConvertFrom-KcProtobuf (Invoke-KcStudioNamed $Session 'GetKeymap' 5000)
    $km = ConvertFrom-KcProtobuf (Get-KcPbMessage $k 1)
    $layers = @()
    foreach ($lf in (Get-KcPbAll $km 1)) {
        $l = ConvertFrom-KcProtobuf ([byte[]]$lf.Value)
        $bindings = New-Object 'System.Collections.Generic.List[object]'
        foreach ($bf in (Get-KcPbAll $l 3)) {
            $b = ConvertFrom-KcProtobuf ([byte[]]$bf.Value)
            $bindings.Add([pscustomobject]@{
                    BehaviorId = (ConvertFrom-KcZigZag (Get-KcPbUInt $b 1))
                    P1         = [long](Get-KcPbUInt $b 2)
                    P2         = [long](Get-KcPbUInt $b 3)
                })
        }
        $layers += [pscustomobject]@{ Id = [int](Get-KcPbUInt $l 1); Name = (Get-KcPbString $l 2); Bindings = $bindings.ToArray() }
    }
    return [pscustomobject]@{ Layers = $layers; AvailableLayers = [int](Get-KcPbUInt $km 2) }
}

function Read-KcStudioUnsaved($Session) {
    $k = ConvertFrom-KcProtobuf (Invoke-KcStudioNamed $Session 'CheckUnsavedChanges')
    return ([int](Get-KcPbUInt $k 3) -ne 0)
}

# ---------------------------------------------------------------------------
# シリアルポート (Windows)
# ---------------------------------------------------------------------------

# Studio 版の ZMK の COM ポート (VID 1D50 / PID 615E)
function Find-KcStudioPort {
    $found = @()
    $devs = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass = 'Ports' AND Present = TRUE" -ErrorAction SilentlyContinue)
    foreach ($d in $devs) {
        if ($d.DeviceID -notlike 'USB\VID_1D50&PID_615E*') {
            continue
        }
        if ([string]$d.Name -match '\((COM\d+)\)') {
            $found += [pscustomobject]@{ Port = $Matches[1]; Name = [string]$d.Name; DeviceId = $d.DeviceID }
        }
    }
    return , $found
}

# USB で接続中の ZMK キーボード (Studio 版でなくても見つかる。HID としての接続)
function Find-KcZmkUsbDevice {
    $devs = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "DeviceID LIKE 'USB\\VID_1D50&PID_615E%' AND Present = TRUE" -ErrorAction SilentlyContinue)
    return , $devs
}

function Open-KcStudioPort([string]$Port) {
    $sp = New-Object System.IO.Ports.SerialPort($Port, 115200)
    $sp.DtrEnable = $true
    $sp.RtsEnable = $true
    $sp.ReadTimeout = 200
    $sp.WriteTimeout = 1000
    try {
        $sp.Open()
    } catch [System.UnauthorizedAccessException] {
        throw ('{0} を開けません。ほかのアプリ (ブラウザの ZMK Studio など) が使っています。閉じてから再実行してください' -f $Port)
    }
    $sp.DiscardInBuffer()
    $transport = @{
        Port  = $sp
        Write = { param([byte[]]$Bytes) $sp.Write($Bytes, 0, $Bytes.Length) }.GetNewClosure()
        Read  = {
            param([int]$TimeoutMs)
            $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
            while ($sp.BytesToRead -eq 0) {
                if ([DateTime]::UtcNow -ge $deadline) {
                    return , ([byte[]]@())
                }
                Start-Sleep -Milliseconds 10
            }
            $buf = New-Object byte[] $sp.BytesToRead
            $n = $sp.Read($buf, 0, $buf.Length)
            if ($n -lt $buf.Length) {
                $buf = $buf[0..($n - 1)]
            }
            return , ([byte[]]$buf)
        }.GetNewClosure()
    }
    return $transport
}

function Close-KcStudioPort($Transport) {
    if ($null -ne $Transport -and $Transport.ContainsKey('Port') -and $null -ne $Transport.Port) {
        try {
            $Transport.Port.Close()
        } catch {
            # 閉じられなくても続ける
        }
    }
}

# ---------------------------------------------------------------------------
# 読み出し検査
# ---------------------------------------------------------------------------

# 期待値のバインディングと一致するか (表示名は大文字小文字を区別しない)
function Test-KcZmkBindingMatch($Expected, [string]$ActualName, [long]$P1, [long]$P2) {
    $names = @([string]$Expected.b)
    $accept = Get-KcProp $Expected 'accept' $null
    if ($null -ne $accept) {
        $names += @($accept)
    }
    $nameOk = $false
    foreach ($n in $names) {
        if ([string]::Equals([string]$n, $ActualName, [System.StringComparison]::OrdinalIgnoreCase)) {
            $nameOk = $true
        }
    }
    return ($nameOk -and [long]$Expected.p1 -eq $P1 -and [long]$Expected.p2 -eq $P2)
}

# $ExpectedByName: @{ 'LisM' = <lism.json>; ... }。デバイス名から期待値を選ぶ。選んだ期待値を返す
# 読み出し検査で違っていた位置 ("レイヤー:位置")。実動作テストのレイヤー・ビヘイビアで、その位置を使う手順を飛ばす
$script:KcZmkMismatch = @{}

function Invoke-KcZmkReadout {
    param(
        [Parameter(Mandatory = $true)] $Session,
        [Parameter(Mandatory = $true)] [hashtable]$ExpectedByName,
        [Parameter(Mandatory = $true)] $Common,
        [Parameter(Mandatory = $true)] $Results,
        $Preferred = $null
    )
    $cat = 'ZMK Studio'
    $script:KcZmkMismatch = @{}
    try {
        $info = Read-KcStudioDeviceInfo $Session 3000
    } catch [System.TimeoutException] {
        [void](Add-KcResult -Results $Results -Category $cat -Item '接続' -Status SKIP -Actual '応答がありません' -Hint (
                "キーボードが BLE に出力しているときは、USB に応答しません。`n" +
                'BT レイヤーのキーを押しながら U (&out OUT_USB) を押して USB 出力に切り替えてから再実行してください (戻すときは B = OUT_BLE)'))
        return $Preferred
    }
    $expected = $null
    foreach ($k in $ExpectedByName.Keys) {
        if ([string]::Equals($k, $info.Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            $expected = $ExpectedByName[$k]
        }
    }
    if ($null -eq $expected) {
        [void](Add-KcResult -Results $Results -Category $cat -Item '機種' -Status FAIL -Actual $info.Name `
                -Expected (($ExpectedByName.Keys | Sort-Object) -join ' / ') -Hint '期待値の無いキーボードです')
        return $Preferred
    }
    $cat = '{0} (Studio)' -f $expected.name
    if ($null -ne $Preferred -and $Preferred.id -ne $expected.id) {
        [void](Add-KcResult -Results $Results -Category $cat -Item '機種' -Status WARN -Expected $Preferred.name -Actual $info.Name `
                -Hint ('接続されているのは {0} です。{0} の期待値で検査します' -f $info.Name))
    } else {
        [void](Add-KcResult -Results $Results -Category $cat -Item '機種' -Status PASS -Actual $info.Name)
    }

    $lock = Read-KcStudioLockState $Session
    if ($lock -ne 1) {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'Studio のロック' -Status WARN -Actual 'ロック中' `
                -Hint 'CONFIG_ZMK_STUDIO_LOCKING=n の Studio 版ではロックされないはずです。tools/flash-zmk.cmd で Studio 版 (s) を書き込み直してください')
    }

    $names = New-KcZmkNames $Common $expected
    try {
        $behaviors = Read-KcStudioBehaviors $Session
        $layouts = Read-KcStudioPhysicalLayouts $Session
        $keymap = Read-KcStudioKeymap $Session
        $unsaved = Read-KcStudioUnsaved $Session
    } catch [System.InvalidOperationException] {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'キーマップ' -Status SKIP -Actual $_.Exception.Message `
                -Hint 'Studio 版 (ロックなし) を書き込み直してから再実行してください')
        return $expected
    }

    # 物理レイアウト (LisM は 42 キーと 40 キーがあり、切り替えるとキーの割り当てが変わる)
    $expLayout = [string]$expected.physical.layout_name
    $layoutList = @($layouts.Layouts)
    $active = ''
    if ($layouts.Active -lt $layoutList.Count) {
        $active = [string]$layoutList[$layouts.Active].Name
    }
    if ($expLayout -and $active -ne $expLayout) {
        [void](Add-KcResult -Results $Results -Category $cat -Item '物理レイアウト' -Status FAIL -Expected $expLayout -Actual $active `
                -Hint 'ZMK Studio で物理レイアウトが切り替えられています。Studio で元のレイアウトに戻してください')
    } else {
        [void](Add-KcResult -Results $Results -Category $cat -Item '物理レイアウト' -Status PASS -Actual $active)
    }

    # キーマップ
    $exp = $expected.readout.zmk
    $expLayers = @($exp.bindings)
    $actLayers = @($keymap.Layers)
    $diffs = New-Object 'System.Collections.Generic.List[string]'
    $layerInfo = @($expected.layers)
    if ($actLayers.Count -ne $expLayers.Count) {
        $diffs.Add(('レイヤー数: 期待 {0} / 実際 {1}' -f $expLayers.Count, $actLayers.Count))
    }
    $reordered = @()
    $keys = @{}
    foreach ($k in @($expected.physical.keys)) {
        $keys[[int]$k.pos] = $k
    }
    $total = 0
    for ($l = 0; $l -lt [math]::Min($expLayers.Count, $actLayers.Count); $l++) {
        $al = $actLayers[$l]
        if ($al.Id -ne $l) {
            $reordered += ('{0} 番目のレイヤーの ID が {1}' -f $l, $al.Id)
        }
        $eb = @($expLayers[$l])
        $ab = @($al.Bindings)
        $lname = '{0}' -f $l
        if ($l -lt $layerInfo.Count) {
            $lname = 'L{0} {1}' -f $l, $layerInfo[$l].name
        }
        if ($eb.Count -ne $ab.Count) {
            $diffs.Add(('{0}: キー数 期待 {1} / 実際 {2}' -f $lname, $eb.Count, $ab.Count))
        }
        for ($p = 0; $p -lt [math]::Min($eb.Count, $ab.Count); $p++) {
            $total++
            $a = $ab[$p]
            $an = ''
            if ($behaviors.ContainsKey([long]$a.BehaviorId)) {
                $an = $behaviors[[long]$a.BehaviorId]
            }
            if (-not (Test-KcZmkBindingMatch $eb[$p] $an $a.P1 $a.P2)) {
                $legend = ''
                if ($keys.ContainsKey($p) -and $keys[$p].legend) {
                    $legend = ' ({0})' -f $keys[$p].legend
                }
                $actText = '(不明なビヘイビア {0})' -f $a.BehaviorId
                if ($an) {
                    $actText = Format-KcZmkBinding $an $a.P1 $a.P2 $names
                }
                $diffs.Add(('{0} / 位置 {1}{2}: 期待 {3} / 実際 {4}' -f $lname, $p, $legend, $eb[$p].src, $actText))
                $script:KcZmkMismatch[('{0}:{1}' -f $l, $p)] = $true
            }
        }
    }
    $hint = "ZMK Studio で変更して保存した内容が残っています。Studio の「Restore Stock Settings」か、`n" +
    'tools/flash-zmk.cmd の「設定リセットしてから左右に書き込む」で元に戻ります'
    Add-KcKeymapResult $Results $cat $diffs.ToArray() $total $hint
    if ($reordered.Count -gt 0) {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'レイヤーの順番' -Status WARN -Details $reordered `
                -Hint 'ZMK Studio でレイヤーを並べ替えたか、追加・削除しています')
    }
    if ($unsaved) {
        [void](Add-KcResult -Results $Results -Category $cat -Item '未保存の変更' -Status WARN -Actual 'あり' `
                -Hint 'ZMK Studio で変更して、まだ保存していない内容があります (キーボードの電源を切ると消えます)')
    }
    [void](Add-KcResult -Results $Results -Category $cat -Item 'トラックボールの設定' -Status INFO `
            -Actual 'Studio では読めません (実動作テストで確かめます)')
    return $expected
}
