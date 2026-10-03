# ZMK のログ版ファーム (zmk-usb-logging) のログを読み、押したキーのレイヤーの遷移と解決をまとめる。
# keyboard-check.ps1 の -Mode Trace (layer-trace.ps1) から使う。Windows の API を使わないので、どの OS でもテストできる。
# expected.ps1 / behavior-eval.ps1 が先に読み込まれている前提。
#
# ログの行 (ZMK v0.3.0。Zephyr の log_output。色の ESC シーケンス付き):
#   [00:00:12.345,678] <dbg> zmk: 関数名: 本文
# 使う行:
#   physical_layouts_kscan_process_msgq: Row: 0, col: 3, position: 3, pressed: true   (セントラル側のキー)
#   peripheral_event_work_callback: Trigger key position state change for 12          (ペリフェラル側のキー。押す / 離すは無い)
#   zmk_keymap_apply_position_state: layer_id: 2 position: 12, binding name: MM_VIM_D (上のレイヤーから順に)
#   zmk_keymap_position_state_changed: behavior processing to continue to next layer   (&trans → 下のレイヤーへ)
#   set_layer_state: layer_changed: layer 2 state 1
#   mo_keymap_binding_pressed: position 36 layer 2 / to_keymap_binding_pressed: position 23 layer 4
#   on_keymap_binding_pressed: position 6 keycode 0x7004B                               (&kp)
#   hid_listener_keycode_pressed: usage_page 0x07 keycode 0x4B implicit_mods 0x00 explicit_mods 0x01
#   on_hold_tap_binding_pressed: 34 new undecided hold_tap / decide_hold_tap: 34 decided hold-interrupt (balanced decision moment other-key-up)
#   on_tap_dance_binding_pressed: 12 created new tap dance / 12 tap dance pressed
#   tap_dance_timer_handler: Tap dance has been decided via timer. Counter reached: 1
#   tap_dance_position_state_changed_listener: Tap dance interrupted, activating tap-dance at 12
#   position_state_changed_listener: 34 capturing 15 down event / 34 bubbling 15 up event  (hold-tap の判定待ちの間)
#   release_captured_events: Releasing key position event for position 15 pressed
#   on_hold_tap_binding_released: 34 cleaning up hold-tap / decide_retro_tap: 34 retro tap
#   --- 5 messages dropped ---

$script:KcLogLinePattern = '^\[(\d+):(\d+):(\d+)\.(\d+),(\d+)\]\s*<(\w+)>\s*([\w-]+):\s*(?:(\w+):\s*)?(.*)$'

# ESC シーケンス (色) と行末を取り除く
function Remove-KcAnsi([string]$Text) {
    return ([regex]::Replace($Text, '\x1B\[[0-9;]*[A-Za-z]', '')).Trim()
}

# ログの 1 行 → レコード (Type ごとに項目が違う)。使わない行は Type = other、空行は $null
function ConvertFrom-KcZmkLogLine([string]$Line) {
    $text = Remove-KcAnsi $Line
    if (-not $text) {
        return $null
    }
    $m = [regex]::Match($text, '^-+\s*(\d+)\s+messages? dropped\s*-+$')
    if ($m.Success) {
        return [pscustomobject]@{ Type = 'dropped'; Time = -1.0; Count = [int]$m.Groups[1].Value; Text = $text }
    }
    $m = [regex]::Match($text, $script:KcLogLinePattern)
    if (-not $m.Success) {
        return [pscustomobject]@{ Type = 'other'; Time = -1.0; Text = $text; Level = ''; Func = '' }
    }
    $g = $m.Groups
    $time = ((([double]$g[1].Value * 60 + [double]$g[2].Value) * 60 + [double]$g[3].Value) * 1000) + [double]$g[4].Value + [double]$g[5].Value / 1000.0
    $level = $g[6].Value
    $func = $g[8].Value
    $msg = $g[9].Value
    $r = [ordered]@{ Type = 'other'; Time = $time; Level = $level; Func = $func; Text = $msg }
    $pressedFn = $null
    if ($func -match '_pressed$') { $pressedFn = $true } elseif ($func -match '_released$') { $pressedFn = $false }
    $mm = $null
    if (($mm = [regex]::Match($msg, '^Row: (\d+), col: (\d+), position: (\d+), pressed: (true|false)')).Success) {
        $r.Type = 'position'; $r.Pos = [int]$mm.Groups[3].Value; $r.Pressed = ($mm.Groups[4].Value -eq 'true'); $r.Source = 'central'
    } elseif (($mm = [regex]::Match($msg, '^Trigger key position state change for (\d+)')).Success) {
        $r.Type = 'position'; $r.Pos = [int]$mm.Groups[1].Value; $r.Pressed = $null; $r.Source = 'peripheral'
    } elseif (($mm = [regex]::Match($msg, '^layer_id: (\d+) position: (\d+), binding name: (\S+)')).Success) {
        $r.Type = 'apply'; $r.Layer = [int]$mm.Groups[1].Value; $r.Pos = [int]$mm.Groups[2].Value; $r.Device = $mm.Groups[3].Value
    } elseif ($msg -match '^behavior processing to continue to next layer') {
        $r.Type = 'continue'
    } elseif (($mm = [regex]::Match($msg, '^layer_changed: layer (\d+) state (\d+)')).Success) {
        $r.Type = 'layer'; $r.Layer = [int]$mm.Groups[1].Value; $r.On = ([int]$mm.Groups[2].Value -ne 0)
    } elseif ($func -match '^(mo|to)_keymap_binding_(pressed|released)$' -and ($mm = [regex]::Match($msg, '^position (\d+) layer (\d+)')).Success) {
        $r.Type = $Matches[1]; $r.Pos = [int]$mm.Groups[1].Value; $r.Layer = [int]$mm.Groups[2].Value; $r.Pressed = $pressedFn
    } elseif (($mm = [regex]::Match($msg, '^position (\d+) keycode 0x([0-9A-Fa-f]+)')).Success) {
        $r.Type = 'kp'; $r.Pos = [int]$mm.Groups[1].Value; $r.Keycode = [Convert]::ToInt64($mm.Groups[2].Value, 16); $r.Pressed = $pressedFn
    } elseif (($mm = [regex]::Match($msg, '^usage_page 0x([0-9A-Fa-f]+) keycode 0x([0-9A-Fa-f]+) implicit_mods 0x([0-9A-Fa-f]+) explicit_mods 0x([0-9A-Fa-f]+)')).Success) {
        $r.Type = 'hid'; $r.Page = [Convert]::ToInt32($mm.Groups[1].Value, 16); $r.Usage = [Convert]::ToInt32($mm.Groups[2].Value, 16)
        $r.Implicit = [Convert]::ToInt32($mm.Groups[3].Value, 16); $r.Explicit = [Convert]::ToInt32($mm.Groups[4].Value, 16); $r.Pressed = $pressedFn
    } elseif (($mm = [regex]::Match($msg, '^(\d+) new undecided hold_tap')).Success) {
        $r.Type = 'ht_new'; $r.Pos = [int]$mm.Groups[1].Value
    } elseif (($mm = [regex]::Match($msg, '^(\d+) decided ([\w-]+) \(([\w-]+) decision moment ([\w-]+)\)')).Success) {
        $r.Type = 'ht_decided'; $r.Pos = [int]$mm.Groups[1].Value; $r.Decision = $mm.Groups[2].Value
        $r.Flavor = $mm.Groups[3].Value; $r.Moment = $mm.Groups[4].Value
    } elseif (($mm = [regex]::Match($msg, '^(\d+) tap dance pressed')).Success) {
        $r.Type = 'td_press'; $r.Pos = [int]$mm.Groups[1].Value
    } elseif (($mm = [regex]::Match($msg, '^Tap dance has been decided via timer\. Counter reached: (\d+)')).Success) {
        $r.Type = 'td_timer'; $r.Count = [int]$mm.Groups[1].Value
    } elseif (($mm = [regex]::Match($msg, '^Tap dance interrupted, activating tap-dance at (\d+)')).Success) {
        $r.Type = 'td_interrupt'; $r.Pos = [int]$mm.Groups[1].Value
    } elseif (($mm = [regex]::Match($msg, '^combo: capturing position event (\d+)')).Success) {
        $r.Type = 'combo'; $r.Pos = [int]$mm.Groups[1].Value
    } elseif (($mm = [regex]::Match($msg, '^(\d+) (capturing|bubbling) (\d+) (down|up) event')).Success) {
        # hold-tap の判定待ちの間のほかのキー (capturing = 判定まで保留、bubbling = そのまま通す)。
        # 修飾キーの保留 ('34 capturing 0xE1 down event') は位置ではないので当たらない
        $r.Type = 'ht_' + $mm.Groups[2].Value.Replace('capturing', 'capture').Replace('bubbling', 'bubble')
        $r.Pos = [int]$mm.Groups[1].Value; $r.Other = [int]$mm.Groups[3].Value; $r.Pressed = ($mm.Groups[4].Value -eq 'down')
    } elseif (($mm = [regex]::Match($msg, '^Releasing key position event for position (\d+) (pressed|released)')).Success) {
        $r.Type = 'ht_replay'; $r.Pos = [int]$mm.Groups[1].Value; $r.Pressed = ($mm.Groups[2].Value -eq 'pressed')
    } elseif (($mm = [regex]::Match($msg, '^(\d+) cleaning up hold-tap')).Success) {
        $r.Type = 'ht_cleanup'; $r.Pos = [int]$mm.Groups[1].Value
    } elseif (($mm = [regex]::Match($msg, '^(\d+) retro tap')).Success) {
        $r.Type = 'ht_retro'; $r.Pos = [int]$mm.Groups[1].Value
    } elseif (($mm = [regex]::Match($msg, '^Update hold tap (\d+) status to hold-interrupt')).Success) {
        $r.Type = 'ht_retro_hold'; $r.Pos = [int]$mm.Groups[1].Value
    } elseif (($mm = [regex]::Match($msg, '^(\d+) hold behavior pressed while undecided')).Success) {
        $r.Type = 'ht_hwu'; $r.Pos = [int]$mm.Groups[1].Value
    }
    return [pscustomobject]$r
}

# 受け取った文字 (途中で切れた行を含む) を行に分ける。$Buffer は前回の残り ([ref])
function Split-KcLogChunk([ref]$Buffer, [string]$Chunk) {
    $all = $Buffer.Value + $Chunk
    $parts = $all -split "`r?`n"
    $Buffer.Value = $parts[$parts.Count - 1]
    if ($parts.Count -le 1) {
        return , @()
    }
    return , @($parts[0..($parts.Count - 2)] | Where-Object { $_ })
}

# 期待値 (interactive.behaviors) からの表 (名前 → definitions の中身)
function New-KcLayerTrace($Expected) {
    $beh = $Expected.interactive.behaviors
    $defs = @{}
    $byName = @{}
    foreach ($p in @($beh.devices.PSObject.Properties)) {
        $defs[$p.Name] = $p.Value
        $byName[[string]$p.Value.name] = $p.Value
    }
    $layers = @{}
    foreach ($l in @($beh.layers)) {
        $layers[[int]$l.index] = $l
    }
    $active = New-Object 'System.Collections.Generic.SortedSet[int]'
    [void]$active.Add(0)
    return @{
        Expected = $Expected; Layers = $layers; Defs = $defs; DefsByName = $byName
        Bindings = @($Expected.readout.zmk.bindings)
        Active = $active; Held = @{}; ModCount = @{}; TdCount = $null
        Events = (New-Object 'System.Collections.Generic.List[object]'); Seq = 0
        Last = $null; LastApply = $null; Dropped = 0; Lines = 0; LastTime = 0.0; Changed = $true
    }
}

function Get-KcTraceLayerName($State, [int]$Layer) {
    if ($State.Layers.ContainsKey($Layer)) {
        return [string]$State.Layers[$Layer].name
    }
    return ('L{0}' -f $Layer)
}

function Get-KcTraceKeyName($State, [int]$Pos) {
    foreach ($k in @($State.Expected.physical.keys)) {
        if ([int]$k.pos -eq $Pos) {
            $legend = [string]$k.legend
            if ($legend) { return $legend }
            break
        }
    }
    return ('位置 {0}' -f $Pos)
}

# 期待値のキーマップのバインディング (src) と、ZMK のデバイス名
function Get-KcTraceBinding($State, [int]$Layer, [int]$Pos) {
    $src = ''
    $dev = ''
    if ($Layer -lt $State.Bindings.Count) {
        $row = @($State.Bindings[$Layer])
        if ($Pos -lt $row.Count) { $src = [string]$row[$Pos].src }
    }
    if ($State.Layers.ContainsKey($Layer)) {
        $devs = @(Get-KcProp $State.Layers[$Layer] 'devs' @())
        if ($Pos -lt $devs.Count) { $dev = [string]$devs[$Pos] }
    }
    return @{ Src = $src; Dev = $dev }
}

function Get-KcTraceExplicit($State) {
    $mods = 0
    foreach ($k in @($State.ModCount.Keys)) {
        if ($State.ModCount[$k] -gt 0) {
            $mods = $mods -bor (1 -shl ([int]$k - 0xE0))
        }
    }
    return $mods
}

# 押下 / 解放 1 つの記録
function New-KcTraceEvent($State, [int]$Pos, [bool]$Pressed, [double]$Time, [string]$Source) {
    $State.Seq++
    $e = [pscustomobject]@{
        Seq = $State.Seq; Time = $Time; Pos = $Pos; Pressed = $Pressed; Source = $Source; Key = (Get-KcTraceKeyName $State $Pos)
        Before = @($State.Active); Chain = (New-Object 'System.Collections.Generic.List[object]'); Resolved = $null; Done = $false
        Steps = (New-Object 'System.Collections.Generic.List[string]'); Outputs = (New-Object 'System.Collections.Generic.List[object]')
        LayerChanges = (New-Object 'System.Collections.Generic.List[string]'); Mask = 0; Explicit = (Get-KcTraceExplicit $State)
        Mismatch = $false
    }
    $State.Events.Add($e)
    while ($State.Events.Count -gt 300) {
        $State.Events.RemoveAt(0)
    }
    return $e
}

# 位置の押下 / 解放のうち、まだレイヤーが決まっていない最も古いもの (ホールドタップに捕まった入力は後で解決される)
function Find-KcTraceUnresolved($State, [int]$Pos) {
    foreach ($e in $State.Events) {
        if ($e.Pos -eq $Pos -and -not $e.Done) {
            return $e
        }
    }
    return $null
}

# 位置の最後の押下 (ビヘイビアの出力を付ける先)
function Find-KcTracePress($State, [int]$Pos) {
    for ($i = $State.Events.Count - 1; $i -ge 0; $i--) {
        $e = $State.Events[$i]
        if ($e.Pos -eq $Pos -and $e.Pressed) {
            return $e
        }
    }
    return $null
}

# モッドモーフの分岐: 押した時点の明示的な修飾で、どの binding になったか (ログには出ないので、期待値の定義から決める)
function Resolve-KcTraceMorph($State, $Event, [string]$Device) {
    $def = $null
    if ($State.Defs.ContainsKey($Device)) { $def = $State.Defs[$Device] }
    $depth = 0
    while ($null -ne $def -and [string]$def.kind -eq 'mod_morph' -and $depth -lt 6) {
        $depth++
        $mods = [int]$def.mods
        $bindings = @($def.bindings)
        $hit = ($Event.Explicit -band $mods) -ne 0
        $mtext = Format-KcModsText $mods
        if ($hit) {
            $Event.Mask = $mods -band (-bnot [int](Get-KcProp $def 'keep_mods' 0))
            $Event.Steps.Add(('{0}: {1} を押している → {2}' -f $def.name, $mtext, $bindings[1]))
            $next = $bindings[1]
        } else {
            $Event.Steps.Add(('{0}: {1} なし → {2}' -f $def.name, $mtext, $bindings[0]))
            $next = $bindings[0]
        }
        $head = ($next -split '\s+')[0].TrimStart('&')
        $def = $null
        if ($State.DefsByName.ContainsKey($head)) { $def = $State.DefsByName[$head] }
    }
}

# レコード 1 つで状態を進める
function Update-KcLayerTrace($State, $Rec) {
    if ($null -eq $Rec) {
        return
    }
    $State.Lines++
    if ($Rec.Time -ge 0) {
        $State.LastTime = $Rec.Time
    }
    # 直前の layer_id の行の次: &trans (continue) なら同じ押下の次のレイヤーの行が続く。それ以外なら、その押下は解決済み
    if ($Rec.Type -ne 'continue' -and $null -ne $State.LastApply) {
        $la = $State.LastApply
        if (-not ($la.Item.Trans -and $Rec.Type -eq 'apply' -and $Rec.Pos -eq $la.Event.Pos)) {
            $la.Event.Done = $true
        }
        $State.LastApply = $null
    }
    switch ($Rec.Type) {
        'dropped' {
            $State.Dropped += $Rec.Count
        }
        'position' {
            $pressed = $Rec.Pressed
            if ($null -eq $pressed) {
                $pressed = -not $State.Held.ContainsKey($Rec.Pos)
            }
            if ($pressed) { $State.Held[$Rec.Pos] = $true } else { $State.Held.Remove($Rec.Pos) }
            $State.Last = New-KcTraceEvent $State $Rec.Pos $pressed $Rec.Time $Rec.Source
        }
        'apply' {
            $e = Find-KcTraceUnresolved $State $Rec.Pos
            if ($null -eq $e) {
                # 位置の行が欠けた (ログの欠落など)。ここから記録を始める
                $e = New-KcTraceEvent $State $Rec.Pos $true $Rec.Time '?'
            }
            $b = Get-KcTraceBinding $State $Rec.Layer $Rec.Pos
            $item = [pscustomobject]@{ Layer = $Rec.Layer; Device = $Rec.Device; Src = $b.Src; Trans = $false
                Mismatch = ($b.Dev -and $b.Dev -ne $Rec.Device) }
            $e.Chain.Add($item)
            $e.Resolved = $item
            if ($item.Mismatch) { $e.Mismatch = $true }
            $State.LastApply = @{ Event = $e; Item = $item }
            $State.Last = $e
            if ($e.Pressed) {
                $e.Explicit = Get-KcTraceExplicit $State
                Resolve-KcTraceMorph $State $e $Rec.Device
            }
        }
        'continue' {
            if ($null -ne $State.LastApply) {
                $State.LastApply.Item.Trans = $true
            }
        }
        'layer' {
            $name = Get-KcTraceLayerName $State $Rec.Layer
            if ($Rec.On) {
                [void]$State.Active.Add($Rec.Layer)
                $text = '{0} オン' -f $name
            } else {
                [void]$State.Active.Remove($Rec.Layer)
                $text = '{0} オフ' -f $name
            }
            $target = $State.Last
            if ($null -eq $target -or ($Rec.Time -ge 0 -and $target.Pos -ge 0 -and ($Rec.Time - $target.Time) -gt 250)) {
                # キーと関係なく変わった (ボールを転がして AML になった、など)
                $target = New-KcTraceEvent $State -1 $true $Rec.Time 'system'
                $target.Key = 'レイヤーの変化'
                $target.Done = $true
                $State.Last = $target
            }
            $target.LayerChanges.Add($text)
        }
        { $_ -eq 'mo' -or $_ -eq 'to' } {
            $e = Find-KcTracePress $State $Rec.Pos
            if ($null -ne $e -and $Rec.Pressed) {
                $what = '押している間 {0}'
                if ($Rec.Type -eq 'to') { $what = '{0} に切り替え (&to)' }
                $e.Steps.Add(($what -f (Get-KcTraceLayerName $State $Rec.Layer)))
                $State.Last = $e
            }
        }
        'kp' {
            $e = Find-KcTracePress $State $Rec.Pos
            if ($null -ne $e) { $State.Last = $e }
        }
        'hid' {
            if ($Rec.Usage -ge 0xE0 -and $Rec.Usage -le 0xE7 -and $Rec.Implicit -eq 0) {
                $c = 0
                if ($State.ModCount.ContainsKey($Rec.Usage)) { $c = $State.ModCount[$Rec.Usage] }
                if ($Rec.Pressed) { $c++ } elseif ($c -gt 0) { $c-- }
                $State.ModCount[$Rec.Usage] = $c
            } elseif ($Rec.Pressed -and $null -ne $State.Last -and $Rec.Page -eq 7) {
                $mask = $State.Last.Mask
                $mods = (($Rec.Explicit -band (-bnot $mask)) -bor $Rec.Implicit)
                $State.Last.Outputs.Add([pscustomobject]@{ Usage = $Rec.Usage; Mods = $mods })
            }
        }
        'ht_new' {
            $e = Find-KcTracePress $State $Rec.Pos
            if ($null -ne $e) { $e.Steps.Add('ホールドタップ: タップかホールドかを待つ') }
        }
        'ht_decided' {
            $e = Find-KcTracePress $State $Rec.Pos
            if ($null -ne $e) {
                $d = @{ 'tap' = 'タップ'; 'hold-timer' = 'ホールド (時間)'; 'hold-interrupt' = 'ホールド (ほかのキー)' }[$Rec.Decision]
                if (-not $d) { $d = $Rec.Decision }
                $mo = @{ 'key-up' = 'このキーを離した'; 'other-key-down' = 'ほかのキーを押した'; 'other-key-up' = 'ほかのキーを離した'
                    'quick-tap' = '続けてタップ'; 'timer' = '時間がたった' }[$Rec.Moment]
                if (-not $mo) { $mo = $Rec.Moment }
                $e.Steps.Add(('ホールドタップ: {0} に決定 ({1}、{2})' -f $d, $Rec.Flavor, $mo))
                $State.Last = $e
            }
        }
        'td_press' {
            $e = Find-KcTracePress $State $Rec.Pos
            if ($null -ne $e) {
                $n = 1
                $prev = $State.TdCount
                if ($null -ne $prev -and $prev.Pos -eq $Rec.Pos) { $n = $prev.N + 1 }
                $State.TdCount = @{ Pos = $Rec.Pos; N = $n }
                $e.Steps.Add(('タップダンス: {0} 回目' -f $n))
            }
        }
        'td_timer' {
            if ($null -ne $State.TdCount) {
                $e = Find-KcTracePress $State $State.TdCount.Pos
                if ($null -ne $e) {
                    $e.Steps.Add(('タップダンス: 時間切れで {0} 回に決定' -f $Rec.Count))
                    $State.Last = $e
                }
            }
            $State.TdCount = $null
        }
        'td_interrupt' {
            $e = Find-KcTracePress $State $Rec.Pos
            if ($null -ne $e) {
                $n = 1
                if ($null -ne $State.TdCount -and $State.TdCount.Pos -eq $Rec.Pos) { $n = $State.TdCount.N }
                $e.Steps.Add(('タップダンス: ほかのキーを押したので {0} 回に決定' -f $n))
                $State.Last = $e
            }
            $State.TdCount = $null
        }
    }
    $State.Changed = $true
}

# 押下 1 つの解決の要約 (時系列の 1 行)
function Format-KcTraceEvent($State, $Event, $ScanTable) {
    if ($Event.Pos -lt 0) {
        return ('{0,9:F3}  ・ {1}: {2}' -f ($Event.Time / 1000.0), $Event.Key, ($Event.LayerChanges -join '、'))
    }
    $arrow = '↑'
    if ($Event.Pressed) { $arrow = '↓' }
    $text = '{0,9:F3}  {1} {2,-3} 「{3}」' -f ($Event.Time / 1000.0), $arrow, $Event.Pos, $Event.Key
    if ($null -ne $Event.Resolved) {
        $text += '  {0}: {1}' -f (Get-KcTraceLayerName $State $Event.Resolved.Layer), $Event.Resolved.Src
        $trans = @($Event.Chain | Where-Object { $_.Trans }).Count
        if ($trans -gt 0) { $text += (' (&trans で {0} つ下へ)' -f $trans) }
    }
    if ($Event.Pressed -and $Event.Outputs.Count -gt 0) {
        $text += ' → ' + (Format-KcStrokeList $Event.Outputs $ScanTable)
    }
    if ($Event.LayerChanges.Count -gt 0) {
        $text += ' [' + ($Event.LayerChanges -join '、') + ']'
    }
    return $text
}

# 押下 1 つの解決の詳しい表示: レイヤーの段 (上から)。見たレイヤー・&trans で下へ・決まったレイヤー・見なかったレイヤー
#   戻り値: [{Layer; Name; Text; State}] State: on = 決まった / trans = 下へ / skip = 有効だが見なかった / off = 無効
function Get-KcTraceCascade($State, $Event) {
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $active = @($Event.Before)
    $seen = @{}
    foreach ($c in $Event.Chain) {
        $seen[[int]$c.Layer] = $c
    }
    $order = @($State.Layers.Keys | Sort-Object -Descending)
    $resolvedLayer = -1
    if ($null -ne $Event.Resolved) { $resolvedLayer = [int]$Event.Resolved.Layer }
    foreach ($l in $order) {
        $name = Get-KcTraceLayerName $State $l
        if ($seen.ContainsKey($l)) {
            $c = $seen[$l]
            if ($c.Trans) {
                $rows.Add([pscustomobject]@{ Layer = $l; Name = $name; Text = ('{0} → 下のレイヤーへ' -f $c.Src); State = 'trans' })
            } else {
                $t = $c.Src
                if ($c.Mismatch) { $t += (' (ログでは {0}。期待値と違う)' -f $c.Device) }
                $rows.Add([pscustomobject]@{ Layer = $l; Name = $name; Text = $t; State = 'on' })
            }
        } elseif ($active -contains $l -or $l -eq 0) {
            $why = '有効 (見ない)'
            if ($resolvedLayer -ge 0 -and $l -gt $resolvedLayer) { $why = '有効' }
            $rows.Add([pscustomobject]@{ Layer = $l; Name = $name; Text = $why; State = 'skip' })
        }
    }
    return , $rows.ToArray()
}
