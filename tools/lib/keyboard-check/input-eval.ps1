# 実動作テストの判定 (キーやボールの入力の記録 → 合否)。Windows の API を使わないので、どの OS でもテストできる。
# keyboard-check.ps1 から dot-source して使う。expected.ps1 が先に読み込まれている前提。
#
# 配列を返す関数 (return , $x) の結果は、いったん変数に入れてからパイプに通す
# (直接パイプに通すと配列が 1 つのオブジェクトとして渡る)。
#
# 入力の記録は、InputTestForm.cs が Raw Input から作る次の形のオブジェクトの並び:
#   Time (ms)、Device (デバイスのハンドル)、Kind ('key' / 'mouse')
#   キー: Scan (スキャンコード)、Prefix (0 / 0xE0 / 0xE1)、Break (離したとき $true)
#   マウス: Dx、Dy、Buttons (RI_MOUSE_* のフラグ)、Wheel、HWheel (1 ノッチ 120、手前 / 左が負)

# ボタンのフラグ (RI_MOUSE_BUTTON_n_DOWN / _UP)
$script:KcMouseButtonFlags = @(
    @(1, 0x0001, 0x0002), @(2, 0x0004, 0x0008), @(3, 0x0010, 0x0020), @(4, 0x0040, 0x0080), @(5, 0x0100, 0x0200)
)

function New-KcKeyEvent([long]$Time, [int]$Scan, [int]$Prefix = 0, [bool]$Break = $false, [long]$Device = 1) {
    return [pscustomobject]@{ Time = $Time; Device = $Device; Kind = 'key'; Scan = $Scan; Prefix = $Prefix; Break = $Break; Dx = 0; Dy = 0; Buttons = 0; Wheel = 0; HWheel = 0 }
}

function New-KcMouseEvent([long]$Time, [int]$Dx = 0, [int]$Dy = 0, [int]$Buttons = 0, [int]$Wheel = 0, [int]$HWheel = 0, [long]$Device = 2) {
    return [pscustomobject]@{ Time = $Time; Device = $Device; Kind = 'mouse'; Scan = 0; Prefix = 0; Break = $false; Dx = $Dx; Dy = $Dy; Buttons = $Buttons; Wheel = $Wheel; HWheel = $HWheel }
}

# キーの記録 → [{Usage; Down; Time}] (押しっぱなしのリピートはまとめる)。表に無いキーの Usage は -1
function ConvertTo-KcKeyActions($Events, $ScanTable) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    $held = @{}
    foreach ($e in @($Events)) {
        if ($e.Kind -ne 'key') {
            continue
        }
        $key = '{0}:{1}' -f [int]$e.Prefix, [int]$e.Scan
        $usage = -1
        if ($ScanTable.ByScan.ContainsKey($key)) {
            $usage = [int]$ScanTable.ByScan[$key]
        }
        $id = if ($usage -ge 0) { [string]$usage } else { $key }
        if ($e.Break) {
            $held.Remove($id)
            $out.Add([pscustomobject]@{ Usage = $usage; Code = $key; Down = $false; Time = [long]$e.Time })
        } elseif (-not $held.ContainsKey($id)) {
            $held[$id] = $true
            $out.Add([pscustomobject]@{ Usage = $usage; Code = $key; Down = $true; Time = [long]$e.Time })
        }
    }
    return , $out.ToArray()
}

function Get-KcKeyLabel($Action, $ScanTable) {
    if ($Action.Usage -ge 0) {
        return (Get-KcUsageLabel $Action.Usage $ScanTable)
    }
    return ('スキャンコード ' + $Action.Code)
}

# 押したキーがすべて離され、最後の入力から $SettleMs たったか
function Test-KcKeysSettled($Events, $ScanTable, [long]$NowMs, [int]$SettleMs) {
    $actions = ConvertTo-KcKeyActions $Events $ScanTable
    if ($actions.Count -eq 0) {
        return $false
    }
    $down = @{}
    foreach ($a in $actions) {
        if ($a.Down) { $down[$a.Code] = $true } else { $down.Remove($a.Code) }
    }
    if ($down.Count -gt 0) {
        return $false
    }
    return (($NowMs - $actions[$actions.Count - 1].Time) -ge $SettleMs)
}

# タップの判定。$Tap: 期待値の taps の 1 件 (usage、hold_usage、mods)
#   PASS: 期待したキーだけが出た / HOLD: ホールドの修飾キーだけが出た (長押しと判定された)
#   NONE: 何も出ない / FAIL: 違うキーが出た
function Test-KcTap($Events, $Tap, $ScanTable) {
    $all = ConvertTo-KcKeyActions $Events $ScanTable
    $actions = @($all | Where-Object { $_.Down })
    $labels = @($actions | ForEach-Object { Get-KcKeyLabel $_ $ScanTable })
    $actual = $labels -join ' + '
    if ($actions.Count -eq 0) {
        return [pscustomobject]@{ Status = 'NONE'; Actual = '(入力なし)' }
    }
    $usages = @($actions | ForEach-Object { $_.Usage })
    $expected = [int]$Tap.usage
    $mods = [int](Get-KcProp $Tap 'mods' 0)
    $expectedMods = @()
    for ($i = 0; $i -lt 8; $i++) {
        if ($mods -band (1 -shl $i)) {
            $expectedMods += (0xE0 + $i)
        }
    }
    $others = @($usages | Where-Object { $_ -ne $expected })
    if ($usages -contains $expected) {
        $extra = @($others | Where-Object { $expectedMods -notcontains $_ })
        $missingMods = @($expectedMods | Where-Object { $usages -notcontains $_ })
        if ($extra.Count -eq 0 -and $missingMods.Count -eq 0) {
            return [pscustomobject]@{ Status = 'PASS'; Actual = $actual }
        }
    }
    $hold = Get-KcProp $Tap 'hold_usage' $null
    if ($null -ne $hold -and $usages.Count -eq 1 -and $usages[0] -eq [int]$hold) {
        return [pscustomobject]@{ Status = 'HOLD'; Actual = $actual }
    }
    return [pscustomobject]@{ Status = 'FAIL'; Actual = $actual }
}

# マウスの記録の集計
function Measure-KcMotion($Events) {
    $dx = 0; $dy = 0; $ax = 0; $ay = 0; $n = 0
    $wheelPos = 0; $wheelNeg = 0; $hPos = 0; $hNeg = 0; $wheelSum = 0; $hSum = 0
    $buttons = New-Object 'System.Collections.Generic.List[object]'
    $samples = New-Object 'System.Collections.Generic.List[object]'
    foreach ($e in @($Events)) {
        if ($e.Kind -ne 'mouse') {
            continue
        }
        if ($e.Dx -ne 0 -or $e.Dy -ne 0) {
            $dx += $e.Dx; $dy += $e.Dy
            $ax += [math]::Abs($e.Dx); $ay += [math]::Abs($e.Dy)
            $n++
            $samples.Add(@([double]$e.Dx, [double]$e.Dy, [double]$e.Time))
        }
        if ($e.Wheel -gt 0) { $wheelPos++ } elseif ($e.Wheel -lt 0) { $wheelNeg++ }
        if ($e.HWheel -gt 0) { $hPos++ } elseif ($e.HWheel -lt 0) { $hNeg++ }
        $wheelSum += $e.Wheel
        $hSum += $e.HWheel
        foreach ($b in $script:KcMouseButtonFlags) {
            if ($e.Buttons -band $b[1]) { $buttons.Add([pscustomobject]@{ Button = $b[0]; Down = $true; Time = [long]$e.Time }) }
            if ($e.Buttons -band $b[2]) { $buttons.Add([pscustomobject]@{ Button = $b[0]; Down = $false; Time = [long]$e.Time }) }
        }
    }
    return [pscustomobject]@{
        Dx = $dx; Dy = $dy; AbsX = $ax; AbsY = $ay; Count = $n; Samples = $samples.ToArray()
        WheelPos = $wheelPos; WheelNeg = $wheelNeg; WheelSum = $wheelSum
        HWheelPos = $hPos; HWheelNeg = $hNeg; HWheelSum = $hSum
        Buttons = $buttons.ToArray()
    }
}

# 向きの判定。$Expect: '+x' (右) / '+y' (手前 = 画面の下)
function Test-KcDirection($Motion, [string]$Expect, [int]$MinCounts = 40) {
    $mag = [math]::Sqrt([double]$Motion.Dx * $Motion.Dx + [double]$Motion.Dy * $Motion.Dy)
    if ($mag -lt $MinCounts) {
        return [pscustomobject]@{ Status = 'NONE'; Angle = 0.0; Actual = ('移動量が少なすぎます ({0:F0})' -f $mag) }
    }
    $expAngle = 0.0
    if ($Expect -eq '+y') { $expAngle = 90.0 }
    if ($Expect -eq '-x') { $expAngle = 180.0 }
    if ($Expect -eq '-y') { $expAngle = -90.0 }
    $angle = [math]::Atan2([double]$Motion.Dy, [double]$Motion.Dx) * 180.0 / [math]::PI
    $dev = $angle - $expAngle
    while ($dev -gt 180) { $dev -= 360 }
    while ($dev -le -180) { $dev += 360 }
    $actual = 'X {0:+#;-#;0} / Y {1:+#;-#;0} ({2:+0;-0;0}°ずれ)' -f $Motion.Dx, $Motion.Dy, $dev
    if ([math]::Abs($dev) -le 45) {
        return [pscustomobject]@{ Status = 'PASS'; Angle = $dev; Actual = $actual }
    }
    $msg = '向きが逆です'
    if ([math]::Abs([math]::Abs($dev) - 90) -lt 45) {
        $msg = 'X と Y が入れ替わっています'
    }
    return [pscustomobject]@{ Status = 'FAIL'; Angle = $dev; Actual = $actual; Message = $msg }
}

# スクロールの判定。$Expect: 'wheel-' (手前へ転がす → 下へスクロール) / 'hwheel+' (右へ → 右へ)
function Test-KcScroll($Motion, [string]$Expect, [int]$MinEvents = 2, [int]$CursorWarn = 150) {
    $vertical = $Expect.StartsWith('wheel')
    $positive = $Expect.EndsWith('+')
    if ($vertical) { $good = $Motion.WheelPos; $bad = $Motion.WheelNeg; $other = $Motion.HWheelPos + $Motion.HWheelNeg }
    else { $good = $Motion.HWheelPos; $bad = $Motion.HWheelNeg; $other = $Motion.WheelPos + $Motion.WheelNeg }
    if (-not $positive) {
        $t = $good; $good = $bad; $bad = $t
    }
    $cursor = [math]::Abs($Motion.Dx) + [math]::Abs($Motion.Dy)
    $actual = 'ホイール 上 {0} / 下 {1}、横 右 {2} / 左 {3}、カーソル移動 {4}' -f $Motion.WheelPos, $Motion.WheelNeg, $Motion.HWheelPos, $Motion.HWheelNeg, $cursor
    if ($good + $bad + $other -eq 0) {
        $msg = 'スクロールしませんでした'
        if ($cursor -gt $CursorWarn) {
            $msg = 'スクロールにならず、カーソルが動きました (スクロールレイヤーになっていない)'
        }
        return [pscustomobject]@{ Status = 'FAIL'; Actual = $actual; Message = $msg }
    }
    if ($good -ge $MinEvents -and $good -gt ($bad + $other)) {
        $status = 'PASS'
        $msg = ''
        if ($cursor -gt $CursorWarn) {
            $status = 'WARN'
            $msg = 'スクロール中にカーソルも動きました'
        }
        return [pscustomobject]@{ Status = $status; Actual = $actual; Message = $msg }
    }
    if ($bad -gt $good -and $bad -ge $other) {
        return [pscustomobject]@{ Status = 'FAIL'; Actual = $actual; Message = 'スクロールの向きが逆です' }
    }
    if ($other -gt $good) {
        return [pscustomobject]@{ Status = 'FAIL'; Actual = $actual; Message = '縦と横のスクロールが入れ替わっています' }
    }
    return [pscustomobject]@{ Status = 'FAIL'; Actual = $actual; Message = 'スクロールが少なすぎます (ゆっくり大きめに転がしてください)' }
}

# AML の発動に要る動きの大きさ。大きいほう + 小さいほうの半分 (√(X² + Y²) の近似。ファームと同じ計算)
function Get-KcAmlDistance([double]$Dx, [double]$Dy) {
    $ax = [math]::Abs($Dx)
    $ay = [math]::Abs($Dy)
    if ($ax -gt $ay) {
        return $ax + [math]::Floor($ay / 2)
    }
    return $ay + [math]::Floor($ax / 2)
}

# 最初のキーの押下 (またはマウスボタン) より前のボールの動き。Distance: 正味の大きさ、Path: 道のり Σ(|dx|+|dy|)
function Measure-KcMotionBeforeKey($Events) {
    $dx = 0; $dy = 0; $path = 0
    foreach ($e in @($Events)) {
        if ($e.Kind -eq 'key') {
            if (-not $e.Break) { break }
            continue
        }
        if ($e.Buttons -ne 0) { break }
        $dx += $e.Dx; $dy += $e.Dy
        $path += [math]::Abs($e.Dx) + [math]::Abs($e.Dy)
    }
    return [pscustomobject]@{ Dx = $dx; Dy = $dy; Distance = (Get-KcAmlDistance $dx $dy); Path = $path }
}

# キーを押す前のボールの動きが、AML の発動に要る量 ($Threshold) に足りなかったら、やり直しの結果 (NONE)。
# 足りていれば $null。AML にならないまま文字が出たのを FAIL や PASS にしないために使う
function Test-KcAmlMotion($Events, [int]$Threshold) {
    if ($Threshold -le 0) {
        return $null
    }
    $m = Measure-KcMotionBeforeKey $Events
    if ($m.Distance -ge $Threshold) {
        return $null
    }
    return [pscustomobject]@{ Status = 'NONE'; Actual = ('キーを押す前のボールの動き {0}' -f $m.Distance)
        Message = ('ボールの動きが小さすぎます (AML はカーソルが {0} 以上動いたときに発動します)。もう少し大きく転がしてください' -f $Threshold) }
}

# キーで押したマウスボタンが、押して離されたか
function Test-KcButtonClicked($Motion, [int]$Button) {
    $down = @($Motion.Buttons | Where-Object { $_.Button -eq $Button -and $_.Down })
    $up = @($Motion.Buttons | Where-Object { $_.Button -eq $Button -and -not $_.Down })
    return ($down.Count -gt 0 -and $up.Count -gt 0)
}

# AML のクリック: ボールを転がしたあと、スクロールキーを押しながらクリックキー → ボタンが出て、キーは出ない
function Test-KcAmlClick($Events, [int]$Button, $ScanTable, [int[]]$AllowedUsages = @(), [int]$Threshold = 0) {
    $motion = Measure-KcMotion $Events
    $all = ConvertTo-KcKeyActions $Events $ScanTable
    $keys = @($all | Where-Object { $_.Down -and $AllowedUsages -notcontains $_.Usage })
    $clicked = Test-KcButtonClicked $motion $Button
    $keyText = (@($keys | ForEach-Object { Get-KcKeyLabel $_ $ScanTable }) -join ' + ')
    if ($keys.Count -gt 0) {
        $small = Test-KcAmlMotion $Events $Threshold
        if ($null -ne $small) {
            return $small
        }
        return [pscustomobject]@{ Status = 'FAIL'; Actual = ('キー入力: ' + $keyText); Message = 'AML (マウスレイヤー) になっていません (キーがそのまま入力されました)' }
    }
    if ($clicked) {
        return [pscustomobject]@{ Status = 'PASS'; Actual = ('ボタン {0} のクリック' -f $Button) }
    }
    $other = @($motion.Buttons | Where-Object { $_.Down } | ForEach-Object { $_.Button })
    if ($other.Count -gt 0) {
        return [pscustomobject]@{ Status = 'FAIL'; Actual = ('ボタン {0}' -f ($other -join ', ')); Message = '違うボタンが押されました' }
    }
    return [pscustomobject]@{ Status = 'NONE'; Actual = '(クリックなし)' }
}

# Shift + クリック: Shift を押した → ボタンを押した → (ボタンを離した) → Shift を離した、の順
function Test-KcShiftClick($Events, [int]$ShiftUsage, [int]$Button, $ScanTable, [int]$Threshold = 0) {
    $motion = Measure-KcMotion $Events
    $actions = ConvertTo-KcKeyActions $Events $ScanTable
    $shiftDown = @($actions | Where-Object { $_.Usage -eq $ShiftUsage -and $_.Down })
    $shiftUp = @($actions | Where-Object { $_.Usage -eq $ShiftUsage -and -not $_.Down })
    $others = @($actions | Where-Object { $_.Down -and $_.Usage -ne $ShiftUsage })
    $btnDown = @($motion.Buttons | Where-Object { $_.Button -eq $Button -and $_.Down })
    if ($others.Count -gt 0) {
        $small = Test-KcAmlMotion $Events $Threshold
        if ($null -ne $small) {
            return $small
        }
        $t = (@($others | ForEach-Object { Get-KcKeyLabel $_ $ScanTable }) -join ' + ')
        return [pscustomobject]@{ Status = 'FAIL'; Actual = ('キー入力: ' + $t); Message = 'Shift 以外のキーが入力されました (AML になっていないか、修飾キーになっていない)' }
    }
    if ($btnDown.Count -eq 0) {
        return [pscustomobject]@{ Status = 'NONE'; Actual = '(クリックなし)' }
    }
    if ($shiftDown.Count -eq 0) {
        return [pscustomobject]@{ Status = 'FAIL'; Actual = 'クリックだけ'; Message = 'Shift が送られませんでした' }
    }
    $click = $btnDown[0].Time
    $ok = $shiftDown[0].Time -le $click -and ($shiftUp.Count -eq 0 -or $shiftUp[$shiftUp.Count - 1].Time -ge $click)
    if ($ok) {
        return [pscustomobject]@{ Status = 'PASS'; Actual = 'Shift を押したままクリック' }
    }
    return [pscustomobject]@{ Status = 'FAIL'; Actual = 'Shift とクリックが重なっていません'; Message = 'クリックの時点で Shift が押されていませんでした' }
}

# AML になっていない: スクロールキー (D) を押したままクリックキー (F) を押すと、どちらも文字が出る (クリックは出ない)。
# F だけでは確かめられない (ZMK は F を押すと、keymap より先に zip_temp_layer が AML を切るので、AML 中でも文字が出る)。
# AML 中なら D はスクロールレイヤーのキー (文字は出ない) になり、F はクリックになる
function Test-KcAmlOff($Events, [int]$ScrollUsage, [int]$ClickUsage, $ScanTable, [string]$AmlMessage = 'AML が切れていません') {
    $motion = Measure-KcMotion $Events
    $all = ConvertTo-KcKeyActions $Events $ScanTable
    $keys = @($all | Where-Object { $_.Down })
    $clicked = @($motion.Buttons | Where-Object { $_.Down })
    $t = (@($keys | ForEach-Object { Get-KcKeyLabel $_ $ScanTable }) -join ' + ')
    if ($clicked.Count -gt 0) {
        $actual = 'クリック'
        if ($t) { $actual = $t + ' + クリック' }
        return [pscustomobject]@{ Status = 'FAIL'; Actual = $actual; Message = $AmlMessage }
    }
    if ($keys.Count -eq 0) {
        return [pscustomobject]@{ Status = 'NONE'; Actual = '(入力なし)' }
    }
    $hasScroll = @($keys | Where-Object { $_.Usage -eq $ScrollUsage }).Count -gt 0
    $hasClick = @($keys | Where-Object { $_.Usage -eq $ClickUsage }).Count -gt 0
    if ($hasScroll -and $hasClick) {
        return [pscustomobject]@{ Status = 'PASS'; Actual = $t }
    }
    if ($hasClick) {
        return [pscustomobject]@{ Status = 'FAIL'; Actual = $t; Message = ('{0} (スクロールのキーが文字になりませんでした)' -f $AmlMessage) }
    }
    if ($hasScroll) {
        return [pscustomobject]@{ Status = 'NONE'; Actual = $t; Message = 'クリックのキーが押されていません' }
    }
    return [pscustomobject]@{ Status = 'FAIL'; Actual = $t; Message = '期待と違うキーが入力されました' }
}

# AML のしきい値: わずかな動き (道のりがしきい値未満) のあと、AML になっていない。
# 道のり Σ(|dx|+|dy|) は、ZMK・Keyball の判定 (向き付きの合計の、大きいほう + 小さいほうの半分) 以上になるので、
# 道のりがしきい値未満なら AML は必ず発動しない (誤って FAIL にしない)
function Test-KcAmlThreshold($Events, [int]$ScrollUsage, [int]$ClickUsage, [int]$Threshold, $ScanTable) {
    $m = Measure-KcMotionBeforeKey $Events
    if ($m.Path -eq 0) {
        return [pscustomobject]@{ Status = 'NONE'; Actual = '(ボールの動きなし)'; Message = 'ボールが動いていません。そっと触れて、カーソルを少しだけ動かしてください' }
    }
    if ($m.Path -ge $Threshold) {
        return [pscustomobject]@{ Status = 'NONE'; Actual = ('ボールの動き {0}' -f $m.Path)
            Message = ('動かしすぎです (しきい値 {0} 未満で確かめます)。カーソルが数ドット動くだけにしてください' -f $Threshold) }
    }
    $t = Test-KcAmlOff $Events $ScrollUsage $ClickUsage $ScanTable ('わずかな動き ({0}) で AML になりました (しきい値の無い古いファーム)' -f $m.Path)
    $t.Actual = ('動き {0}: {1}' -f $m.Path, $t.Actual)
    return $t
}

# AML 中に修飾キーの位置 (Ctrl / Shift) をタップ: AML が切れて、BASE と同じ文字が出る
function Test-KcAmlRelease($Events, [int]$Usage, $ScanTable, [int]$Threshold = 0) {
    $all = ConvertTo-KcKeyActions $Events $ScanTable
    $keys = @($all | Where-Object { $_.Down })
    if ($keys.Count -eq 0) {
        return [pscustomobject]@{ Status = 'NONE'; Actual = '(入力なし)' }
    }
    # AML にならないまま押しても文字は出るので、動きが足りなければ確かめたことにならない
    $small = Test-KcAmlMotion $Events $Threshold
    if ($null -ne $small) {
        return $small
    }
    $t = (@($keys | ForEach-Object { Get-KcKeyLabel $_ $ScanTable }) -join ' + ')
    if (@($keys | Where-Object { $_.Usage -eq $Usage }).Count -gt 0) {
        return [pscustomobject]@{ Status = 'PASS'; Actual = $t }
    }
    if (@($keys | Where-Object { $_.Usage -lt 0xE0 -or $_.Usage -gt 0xE7 }).Count -eq 0) {
        return [pscustomobject]@{ Status = 'FAIL'; Actual = $t; Message = '修飾キーだけが入力されました (AML が切れていない。長押しになった場合は短く押してやり直す)' }
    }
    return [pscustomobject]@{ Status = 'FAIL'; Actual = $t; Message = '期待と違うキーが入力されました' }
}

# ボールの位置 (left / right) → テストで押すキー (ボールと反対の手)
function Get-KcHandKeys($Trackball, [string]$Ball) {
    $hand = 'left'
    if ($Ball -eq 'left') {
        $hand = 'right'
    }
    return $Trackball.keys.$hand
}
