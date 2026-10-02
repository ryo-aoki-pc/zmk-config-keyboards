# トラックボールの正規化: X/Y の比率と傾き (楕円補正) と、キーボード間の速さ (LisM 基準)。
# 計算だけを行う (Windows の API を使わない)。keyboard-check.ps1 から dot-source して使う。
#
# 楕円補正の計算は「KUKEY42 真円計測」ページ (fit / correction / splitBySpeed) と同じ:
#   ボールを一定の速さで円を描くように回したときの移動量 (dx, dy) の共分散 C を求め、
#   C^(-1/2) を行列式 1 に正規化した行列で、楕円を同じ面積の円に戻す。
# 計測ページはブラウザで OS の加速が入った値を測っていたが、こちらは Raw Input の生の値
# (そのボールのデバイスだけ) を使うので、補正の強さは既定で 100% にする。
# ファームのカーソルの加速 (ZMK の trackball_accel、Keyball の KEYBALL_ACCEL_*) は、記録した移動量から
# 取り除いてから計算する (Remove-KcAccel)。

# 移動量の点 (@(dx, dy) の並び) に楕円を当てはめる。点が 8 未満なら $null
function Get-KcEllipseFit($Samples) {
    $xx = 0.0; $xy = 0.0; $yy = 0.0; $n = 0
    foreach ($p in $Samples) {
        $x = [double]$p[0]
        $y = [double]$p[1]
        if ($x -eq 0 -and $y -eq 0) {
            continue
        }
        $xx += $x * $x; $xy += $x * $y; $yy += $y * $y; $n++
    }
    if ($n -lt 8) {
        return $null
    }
    $xx /= $n; $xy /= $n; $yy /= $n
    $tr = $xx + $yy
    $det = $xx * $yy - $xy * $xy
    $disc = [math]::Sqrt([math]::Max($tr * $tr / 4 - $det, 0))
    $l1 = $tr / 2 + $disc
    $l2 = [math]::Max($tr / 2 - $disc, $l1 * 1e-6)
    $theta = 0.5 * [math]::Atan2(2 * $xy, $xx - $yy)
    return [pscustomobject]@{ N = $n; L1 = $l1; L2 = $l2; Theta = $theta; Ratio = [math]::Sqrt($l1 / $l2) }
}

# 長軸の向き (度)。画面の座標 (y が下向き) で、＼ が正、／ が負
function Get-KcTiltDeg($Fit) {
    return ($Fit.Theta * 180.0 / [math]::PI)
}

# 楕円を円に戻す行列 C^(-strength/2) (行列式 1 に正規化)。$Strength は 0〜1
function Get-KcCorrectionMatrix($Fit, [double]$Strength = 1.0) {
    $c = [math]::Cos($Fit.Theta)
    $s = [math]::Sin($Fit.Theta)
    $a = [math]::Pow($Fit.L1, - $Strength / 2)
    $b = [math]::Pow($Fit.L2, - $Strength / 2)
    $k = [math]::Pow($Fit.L1 * $Fit.L2, $Strength / 4)
    $m01 = ($a - $b) * $c * $s * $k
    return , @(
        [double[]]@((($a * $c * $c + $b * $s * $s) * $k), $m01),
        [double[]]@($m01, (($a * $s * $s + $b * $c * $c) * $k))
    )
}

function Join-KcMatrix($A, $B) {
    return , @(
        [double[]]@(($A[0][0] * $B[0][0] + $A[0][1] * $B[1][0]), ($A[0][0] * $B[0][1] + $A[0][1] * $B[1][1])),
        [double[]]@(($A[1][0] * $B[0][0] + $A[1][1] * $B[1][0]), ($A[1][0] * $B[0][1] + $A[1][1] * $B[1][1]))
    )
}

function Invoke-KcMatrix($M, $P) {
    return , [double[]]@(($M[0][0] * [double]$P[0] + $M[0][1] * [double]$P[1]), ($M[1][0] * [double]$P[0] + $M[1][1] * [double]$P[1]))
}

# 速さで半分に分けて当てはめる (補正後の大きさで分ける)。加速が無ければ両方の縦横比は同じになる
function Split-KcBySpeed($Samples, $Fit) {
    $moving = @($Samples | Where-Object { [double]$_[0] -ne 0 -or [double]$_[1] -ne 0 })
    if ($null -eq $Fit -or $moving.Count -lt 40) {
        return , @($null, $null)
    }
    $m = Get-KcCorrectionMatrix $Fit 1.0
    $i = 0
    $withSpeed = foreach ($p in $moving) {
        $q = Invoke-KcMatrix $m $p
        [pscustomobject]@{ P = $p; Speed = [math]::Sqrt($q[0] * $q[0] + $q[1] * $q[1]); Index = $i }
        $i++
    }
    # 速さが同じ点は元の順 (計測ページの JavaScript の安定ソートと同じ)
    $sorted = @($withSpeed | Sort-Object -Property Speed, Index)
    $mid = [math]::Floor($sorted.Count / 2)
    $slow = @($sorted[0..($mid - 1)] | ForEach-Object { , $_.P })
    $fast = @($sorted[$mid..($sorted.Count - 1)] | ForEach-Object { , $_.P })
    return , @((Get-KcEllipseFit $slow), (Get-KcEllipseFit $fast))
}

# 0 から遠ざかる方向に丸める (JavaScript の Math.round と同じ。.NET の既定は偶数丸め)
function Get-KcRound([double]$Value) {
    return [long][math]::Floor($Value + 0.5)
}

# $Value に近い分数 n / d (d は 1〜$MaxDen、n は 1 以上)
function Get-KcRational([double]$Value, [int]$MaxDen = 16) {
    $best = @(1, 1)
    $bestErr = [double]::MaxValue
    for ($d = 1; $d -le $MaxDen; $d++) {
        $n = [math]::Max(1, (Get-KcRound ($Value * $d)))
        $err = [math]::Abs($n / $d - $Value)
        if ($err -lt $bestErr - 1e-12) {
            $best = @([long]$n, [long]$d)
            $bestErr = $err
        }
    }
    return , $best
}

function Format-KcDtsNumber([long]$Value) {
    if ($Value -lt 0) {
        return ('({0})' -f $Value)
    }
    return [string]$Value
}

# ---------------------------------------------------------------------------
# カーソルの加速を取り除く
# ---------------------------------------------------------------------------
# ZMK (zmk-input-processor-xy-accel) と Keyball39 (keymap.c) は、ボールを転がす速さ (カウント/秒) に応じて
# 移動量に倍率を掛ける (速さ 0 で min-factor、speed-threshold で等倍、speed-max 以上で max-factor)。
# 楕円と速さは加速の前の値で比べる (補正はファームの加速より前に入れるため。加速の後の値で測ると、
# 速く動く長軸の向きほど大きく出て、楕円が実際より細長くなる)。
# 記録した移動量 (加速の後) から、その時点の速さを直前の $WindowMs の移動量で求め、加速の曲線を逆に
# たどって倍率で割り戻す。ファームの処理 (速さの平均のとり方、1 報告の遅れ) と完全には一致しないが、
# ファームの処理を真似た計算 (tests/trackball-calib.Tests.ps1) では、縦横比と 1 回転あたりのカウントの
# 誤差は 3% 以内になる。

# 倍率 (1.0 = 等倍)
function Get-KcAccelFactor($Accel, [double]$Speed) {
    $min = [double]$Accel.min_factor
    $max = [double]$Accel.max_factor
    $thr = [double]$Accel.speed_threshold
    $smax = [double]$Accel.speed_max
    if ($Speed -ge $smax) {
        return ($max / 1000.0)
    }
    if ($Speed -le $thr) {
        return (($min + (1000.0 - $min) * $Speed / $thr) / 1000.0)
    }
    return ((1000.0 + ($max - 1000.0) * ($Speed - $thr) / ($smax - $thr)) / 1000.0)
}

# 加速の後の速さ $After から、加速の前の速さ v (v × 倍率(v) = $After) を求める
function Get-KcAccelSpeedBefore($Accel, [double]$After) {
    if ($After -le 0) {
        return 0.0
    }
    $min = [double]$Accel.min_factor / 1000.0
    $max = [double]$Accel.max_factor / 1000.0
    $thr = [double]$Accel.speed_threshold
    $smax = [double]$Accel.speed_max
    if ($After -le $thr) {
        # v × (min + (1 - min) × v / thr) = After
        $a = (1.0 - $min) / $thr
        $b = $min
    } elseif ($After -lt $smax * $max) {
        # v × (1 + (max - 1) × (v - thr) / (smax - thr)) = After
        $a = ($max - 1.0) / ($smax - $thr)
        $b = 1.0 - $a * $thr
    } else {
        return ($After / $max)
    }
    if ($a -le 1e-15) {
        return ($After / $b)
    }
    return ((- $b + [math]::Sqrt($b * $b + 4 * $a * $After)) / (2 * $a))
}

# 1 回の報告の移動量 (速さの計算に使う)。Keyball は「大きいほう + 小さいほうの半分」で近似している
function Get-KcAccelDistance($Accel, [double]$X, [double]$Y) {
    $ax = [math]::Abs($X)
    $ay = [math]::Abs($Y)
    if ([string]$Accel.model -eq 'keyball') {
        if ($ax -gt $ay) {
            return ($ax + $ay / 2)
        }
        return ($ay + $ax / 2)
    }
    return [math]::Sqrt($ax * $ax + $ay * $ay)
}

# $Samples: @(dx, dy, 時刻 ms) の並び (時刻の順)。$Accel: 期待値の firmware[].accel
# 戻り値: Samples (加速の前の @(dx, dy, 時刻))、Dx、Dy、Saturated (1 回の報告の上限に達した数。Keyball は ±127)
function Remove-KcAccel($Samples, $Accel, [int]$WindowMs = 40, [int]$IdleMs = 50) {
    $list = @($Samples)
    $out = New-Object 'System.Collections.Generic.List[object]'
    $dist = New-Object 'double[]' $list.Count
    for ($i = 0; $i -lt $list.Count; $i++) {
        $dist[$i] = Get-KcAccelDistance $Accel ([double]$list[$i][0]) ([double]$list[$i][1])
    }
    $clamp = [int](Get-KcProp $Accel 'clamp' 0)
    $sx = 0.0; $sy = 0.0; $sat = 0
    $j = 0; $sum = 0.0; $prevT = $null
    for ($i = 0; $i -lt $list.Count; $i++) {
        $p = $list[$i]
        $t = [double]$p[2]
        if ($null -eq $prevT -or $t - $prevT -gt $IdleMs) {
            # 止まっていた。ファームは最小の倍率から始め直すので、区間も最初から
            $j = $i
            $sum = 0.0
        }
        $prevT = $t
        $sum += $dist[$i]
        while ($j -lt $i -and [double]$list[$j][2] -le $t - $WindowMs) {
            $sum -= $dist[$j]
            $j++
        }
        $f = Get-KcAccelFactor $Accel (Get-KcAccelSpeedBefore $Accel ($sum * 1000.0 / $WindowMs))
        if ($clamp -gt 0 -and ([math]::Abs([double]$p[0]) -ge $clamp -or [math]::Abs([double]$p[1]) -ge $clamp)) {
            $sat++
        }
        $x = [double]$p[0] / $f
        $y = [double]$p[1] / $f
        $sx += $x
        $sy += $y
        $out.Add(@($x, $y, $t))
    }
    return [pscustomobject]@{ Samples = $out.ToArray(); Dx = $sx; Dy = $sy; Saturated = $sat }
}

# 移動量を $BinMs ごとにまとめる (1 カウント単位の誤差を減らす)。円を 1 周する時間より十分短い区間なので、
# 楕円の形は変わらない
function Join-KcSamplesByTime($Samples, [int]$BinMs) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    $cur = $null
    $sx = 0.0; $sy = 0.0
    foreach ($p in @($Samples)) {
        $k = [math]::Floor([double]$p[2] / $BinMs)
        if ($null -ne $cur -and $k -ne $cur) {
            $out.Add(@($sx, $sy, ($cur * $BinMs)))
            $sx = 0.0; $sy = 0.0
        }
        $cur = $k
        $sx += [double]$p[0]
        $sy += [double]$p[1]
    }
    if ($null -ne $cur) {
        $out.Add(@($sx, $sy, ($cur * $BinMs)))
    }
    return , $out.ToArray()
}

# 補正を入れる場所の説明 (加速より前に入れる)
function Get-KcInsertNote($Firmware) {
    $accel = Get-KcProp $Firmware 'accel' $null
    if ($null -eq $accel -or [string]$accel.model -ne 'zmk') {
        return ''
    }
    return ('。<&{0}> より前に置く (加速は補正の後の速さで倍率を決めるため)' -f $accel.label)
}

# ---------------------------------------------------------------------------
# (1) X/Y の比率と傾き
# ---------------------------------------------------------------------------

# $Firmware: 期待値の trackball.firmware の 1 件 (correction / matrix / divisor / listener / accel)
# $Samples: @(dx, dy) または @(dx, dy, 時刻 ms) の並び。時刻があれば、加速を取り除いて
# calib_bin_ms ごとにまとめてから当てはめる
# 戻り値: Status (PASS / WARN / INFO / SKIP)、数値、overlay に貼る行 (Lines)、説明 (Notes)
function New-KcEllipseRecommendation {
    param(
        [Parameter(Mandatory = $true)] $Samples,
        [Parameter(Mandatory = $true)] $Firmware,
        [Parameter(Mandatory = $true)] $Thresholds,
        [double]$Strength = 1.0
    )
    $accel = Get-KcProp $Firmware 'accel' $null
    $timed = (@($Samples).Count -gt 0 -and @($Samples)[0].Count -ge 3)
    $method = ''
    if ($timed) {
        if ($null -ne $accel) {
            $pre = Remove-KcAccel $Samples $accel ([int]$Thresholds.accel_window_ms) ([int]$Thresholds.accel_idle_ms)
            $Samples = $pre.Samples
            $method = '加速を除く、'
        }
        $binned = Join-KcSamplesByTime $Samples ([int]$Thresholds.calib_bin_ms)
        $Samples = $binned
        $method += ('{0}ms ごと、' -f [int]$Thresholds.calib_bin_ms)
    }
    $fit = Get-KcEllipseFit $Samples
    if ($null -eq $fit -or $fit.N -lt [int]$Thresholds.calib_min_points) {
        $n = 0
        if ($null -ne $fit) { $n = $fit.N }
        return [pscustomobject]@{ Status = 'SKIP'; Message = ('点が少なすぎます ({0} 点)。もう少し長く回してください' -f $n); Fit = $fit; Lines = @(); Notes = @() }
    }
    $split = Split-KcBySpeed $Samples $fit
    $notes = @()
    if ($null -ne $split[0] -and $null -ne $split[1]) {
        $rs = $split[0].Ratio
        $rf = $split[1].Ratio
        if ([math]::Abs($rs - $rf) / [math]::Min($rs, $rf) -gt [double]$Thresholds.calib_speed_split_tolerance) {
            $notes += ('遅い動き (縦横比 {0:F2}) と速い動き ({1:F2}) で縦横比が違います。なるべく一定の速さで回してください (直らないときは、キーボードのカーソルの加速の設定が期待値と違う可能性があります)' -f $rs, $rf)
        }
    }
    $m = Get-KcCorrectionMatrix $fit $Strength
    $corrected = @(foreach ($p in $Samples) { , (Invoke-KcMatrix $m $p) })
    $after = Get-KcEllipseFit $corrected
    $tilt = Get-KcTiltDeg $fit
    $summary = '縦横比 {0:F2}、長軸の傾き {1:+0;-0;0}°、点 {2}' -f $fit.Ratio, $tilt, $fit.N
    $comment = '// 計測: tools/keyboard-check (Raw Input、{4}補正の強さ {0}%) / 縦横比 {1:F2} / 傾き {2:+0;-0;0}° / 点 {3}' -f [int]($Strength * 100), $fit.Ratio, $tilt, $fit.N, $method

    $status = 'PASS'
    if ($fit.Ratio -gt [double]$Thresholds.ellipse_ratio_pass) {
        $status = 'WARN'
    }
    $lines = @()
    $kind = [string]$Firmware.correction
    if ($kind -eq 'matrix') {
        $div = [int]$Firmware.divisor
        $cur = @($Firmware.matrix)
        $t = @(
            [double[]]@(([double]$cur[0] / $div), ([double]$cur[1] / $div)),
            [double[]]@(([double]$cur[2] / $div), ([double]$cur[3] / $div))
        )
        $nm = Join-KcMatrix $m $t
        $vals = @($nm[0][0], $nm[0][1], $nm[1][0], $nm[1][1]) | ForEach-Object { Format-KcDtsNumber (Get-KcRound ($_ * $div)) }
        $lines += ('matrix = <{0}>;' -f ($vals -join ' '))
        $lines += ('divisor = <{0}>;' -f $div)
        $lines += $comment
        $notes += ('{0} の matrix / divisor をこの行に置き換える (今の行列 <{1}> / {2} に補正を掛けた値)' -f $Firmware.listener, (@($cur | ForEach-Object { Format-KcDtsNumber $_ }) -join ' '), $div)
    } elseif ($kind -eq 'zip_scaler') {
        $off = [math]::Max([math]::Abs($m[0][1]), [math]::Abs($m[1][0]))
        $diag = [math]::Max([math]::Abs($m[0][0]), [math]::Abs($m[1][1]))
        if ($off -le 0.05 * $diag) {
            $sx = Get-KcRational $m[0][0] ([int]$Thresholds.scaler_max_denominator)
            $sy = Get-KcRational $m[1][1] ([int]$Thresholds.scaler_max_denominator)
            $lines += ('<&zip_x_scaler {0} {1}>, <&zip_y_scaler {2} {3}>' -f $sx[0], $sx[1], $sy[0], $sy[1])
            $lines += $comment
            $notes += ('{0} の input-processors に追加する (X を {1:F3} 倍、Y を {2:F3} 倍){3}' -f $Firmware.listener, $m[0][0], $m[1][1], (Get-KcInsertNote $Firmware))
        } else {
            $lines += ('X'' = {0:F3} X + {1:F3} Y、Y'' = {2:F3} X + {3:F3} Y' -f $m[0][0], $m[0][1], $m[1][0], $m[1][1])
            $lines += $comment
            $notes += '傾きがあるため、軸ごとの倍率 (zip_x_scaler / zip_y_scaler) では直せません。KUKEY42 の 2x2 行列の入力プロセッサ (zmk-config-KUKEY42/src/input_processor_xy_matrix.c) を移植して、この行列を使ってください'
        }
    } else {
        if ($status -eq 'WARN') {
            $status = 'INFO'
        }
        $lines += ('X'' = {0:F3} X + {1:F3} Y、Y'' = {2:F3} X + {3:F3} Y' -f $m[0][0], $m[0][1], $m[1][0], $m[1][1])
        $lines += $comment
        $notes += ('{0}。X と Y を別々に補正する設定はありません' -f $Firmware.listener)
    }
    $afterText = ''
    if ($null -ne $after) {
        $afterText = '{0:F2}' -f $after.Ratio
    }
    return [pscustomobject]@{
        Status = $status; Summary = $summary; Fit = $fit; Matrix = $m; Tilt = $tilt
        PredictedRatio = $afterText; Lines = $lines; Notes = $notes; Message = ''
    }
}

# ---------------------------------------------------------------------------
# (2) キーボード間の速さ
# ---------------------------------------------------------------------------

# 回転数を決めて転がした計測から、1 回転あたりのカウントを求める。
#   $Strokes: @{ Axis = 'x' / 'y'; Dx; Dy; Revolutions }
#   戻り値: PerRevX、PerRevY、PerRev (幾何平均)、Spread (同じ軸の 2 回の差の最大、割合)、Cpi (直径があれば実効 CPI)
function Get-KcSpeedMeasurement($Strokes, $DiameterMm = $null) {
    $per = @{ x = @(); y = @() }
    foreach ($s in @($Strokes)) {
        $c = [math]::Sqrt([double]$s.Dx * $s.Dx + [double]$s.Dy * $s.Dy) / [double]$s.Revolutions
        $per[[string]$s.Axis] += $c
    }
    $spread = 0.0
    $means = @{}
    foreach ($axis in @('x', 'y')) {
        $v = @($per[$axis])
        if ($v.Count -eq 0) {
            throw ('{0} 方向の計測がありません' -f $axis)
        }
        $mean = ($v | Measure-Object -Average).Average
        $means[$axis] = $mean
        if ($v.Count -ge 2) {
            $d = (($v | Measure-Object -Maximum).Maximum - ($v | Measure-Object -Minimum).Minimum) / $mean
            $spread = [math]::Max($spread, $d)
        }
    }
    $perRev = [math]::Sqrt($means['x'] * $means['y'])
    $cpi = $null
    if ($null -ne $DiameterMm -and [double]$DiameterMm -gt 0) {
        $cpi = $perRev / ([math]::PI * [double]$DiameterMm / 25.4)
    }
    return [pscustomobject]@{ PerRevX = $means['x']; PerRevY = $means['y']; PerRev = $perRev; Spread = $spread; Cpi = $cpi; DiameterMm = $DiameterMm }
}

# 基準 (LisM) と比べた推奨値。$Reference: @{ Cpi; PerRev; Source }
function New-KcSpeedRecommendation {
    param(
        [Parameter(Mandatory = $true)] $Measurement,
        $Reference,
        [Parameter(Mandatory = $true)] $Firmware,
        [Parameter(Mandatory = $true)] $Thresholds
    )
    $value = $Measurement.Cpi
    $unit = '実効 CPI'
    $refValue = $null
    if ($null -ne $Reference) {
        $refValue = $Reference.Cpi
    }
    if ($null -eq $value) {
        $value = $Measurement.PerRev
        $unit = '1 回転あたりのカウント'
        if ($null -ne $Reference) {
            $refValue = $Reference.PerRev
        }
    }
    $summary = '{0} {1:F0} (X {2:F0} / Y {3:F0} カウント/回転)' -f $unit, $value, $Measurement.PerRevX, $Measurement.PerRevY
    if ($null -eq $refValue) {
        return [pscustomobject]@{ Status = 'INFO'; Summary = $summary; Scale = $null; Lines = @(); Notes = @('基準 (LisM) の計測がありません。LisM で計測すると比べられます (-SpeedReference でも指定できます)') }
    }
    $s = [double]$refValue / [double]$value
    $notes = @()
    if ($null -eq $Measurement.Cpi) {
        $notes += 'ボールの直径を入れずに計測したため、1 回転あたりで比べています (ボールの大きさが同じときだけ有効)'
    }
    $summary += ' / 基準 {0:F0} ({1}) の {2:F2} 倍' -f $refValue, $Reference.Source, (1 / $s)
    $status = 'PASS'
    if ([math]::Abs($s - 1) -gt [double]$Thresholds.speed_tolerance) {
        $status = 'WARN'
    }
    $lines = @()
    # CPI を変えられる機種は CPI を先に出す (README の「トラックボールの細かさ」: 倍率を 1 より大きくすると、
    # 1 カウントでカーソルが 2 以上飛ぶ)
    $cs = Get-KcProp $Firmware 'cpi_setting' $null
    $hasCpi = ($null -ne $cs -and $null -ne $Firmware.cpi)
    if ($hasCpi) {
        $step = [int]$cs.step
        $newCpi = [long]((Get-KcRound ([double]$Firmware.cpi * $s / $step)) * $step)
        $newCpi = [math]::Min([math]::Max($newCpi, [int]$cs.min), [int]$cs.max)
        $lines += ([string]$cs.template).Replace('{cpi}', [string]$newCpi)
        $notes += ('CPI を変える: {0} (今の CPI {1}、{2} 刻み)' -f $Firmware.cpi_source, $Firmware.cpi, $step)
    }
    $kind = [string]$Firmware.correction
    if ($kind -eq 'zip_scaler' -or $kind -eq 'matrix') {
        $cur = @($Firmware.xy_scaler)
        $ratio = $s * [double]$cur[0] / [double]$cur[1]
        $r = Get-KcRational $ratio ([int]$Thresholds.scaler_max_denominator)
        $lines += ('<&zip_xy_scaler {0} {1}>' -f $r[0], $r[1])
        $prefix = ''
        if ($hasCpi) {
            $prefix = 'または '
        }
        if ([bool](Get-KcProp $Firmware 'xy_scaler_set' $false) -or [int]$cur[0] -ne 1 -or [int]$cur[1] -ne 1) {
            $notes += ('{0}{1} の zip_xy_scaler {2} {3} をこの値に置き換える ({4:F2} 倍){5}' -f $prefix, $Firmware.listener, $cur[0], $cur[1], $s, (Get-KcInsertNote $Firmware))
        } else {
            $notes += ('{0}{1} の input-processors に追加する ({2:F2} 倍){3}' -f $prefix, $Firmware.listener, $s, (Get-KcInsertNote $Firmware))
        }
        if ($ratio -gt 1.0) {
            $notes += '倍率が 1 より大きいと、1 カウントでカーソルが 1 より大きく動く (細かさが落ちる)'
        }
    }
    if ($lines.Count -eq 0) {
        $notes += ('{0}。速さを変える設定はありません' -f $Firmware.listener)
        if ($status -eq 'WARN') {
            $status = 'INFO'
        }
    }
    return [pscustomobject]@{ Status = $status; Summary = $summary; Scale = $s; Lines = $lines; Notes = $notes }
}

# ---------------------------------------------------------------------------
# 計測結果の保存 (tools/.cache/keyboard-check/trackball.json、git の管理外)
# ---------------------------------------------------------------------------

function Read-KcCalibCache([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return , @()
    }
    try {
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $data = $text | ConvertFrom-Json
        return , @($data)
    } catch {
        return , @()
    }
}

function Save-KcCalibEntry([string]$Path, $Entry) {
    $existing = Read-KcCalibCache $Path
    $all = @($existing) + @($Entry)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Force -Path $dir)
    }
    $json = ConvertTo-Json -InputObject @($all) -Depth 6
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

# 基準: LisM の最新の速さの計測 (右のボールを優先)
function Get-KcSpeedReference($Entries) {
    $lism = @($Entries | Where-Object { $_.keyboard -eq 'lism' -and $null -ne (Get-KcProp $_ 'per_rev' $null) })
    if ($lism.Count -eq 0) {
        return $null
    }
    $right = @($lism | Where-Object { $_.ball -eq 'right' })
    $pick = $lism[$lism.Count - 1]
    if ($right.Count -gt 0) {
        $pick = $right[$right.Count - 1]
    }
    return [pscustomobject]@{ Cpi = (Get-KcProp $pick 'cpi' $null); PerRev = $pick.per_rev; Source = ('LisM {0} {1}' -f $pick.ball, $pick.time) }
}
