# トラックボールの正規化 (trackball-calib.ps1) のテスト

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'trackball-calib.ps1')

$common = Get-KcExpected 'common' $script:ExpectedDir
$thresholds = $common.thresholds
# ファームの設定は期待値の JSON の形を使い、値は計測ページの例に合わせて固定する (ファームの調整でテストが変わらないように)
function Copy-Firmware([string]$Id, [hashtable]$Values) {
    $fw = (Get-KcExpected $Id $script:ExpectedDir).interactive.trackball.firmware[0] | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    foreach ($k in $Values.Keys) { $fw.$k = $Values[$k] }
    return $fw
}
$kukey = Copy-Firmware 'kukey42' @{ cpi = 1000; matrix = @(995, -497, -305, 2163); divisor = 1000; xy_scaler = @(1, 1) }
$lismRight = Copy-Firmware 'lism' @{}
$afrb = Copy-Firmware 'aroundfortyrb' @{ cpi = 400; xy_scaler = @(2, 1) }

# 「KUKEY42 真円計測」ページの例のデータ (＼ 45°、縦横比 3 の楕円) と同じ点を作る
function New-ExampleSamples {
    $out = New-Object 'System.Collections.Generic.List[object]'
    $s = [math]::Sqrt(0.5)
    [long]$seed = 7
    for ($i = 0; $i -lt 900; $i++) {
        $dir = 1
        if ($i -ge 450) { $dir = -1 }
        $t = ($i / 90) * [math]::PI * 2 * $dir
        $seed = ($seed * 16807) % 2147483647
        $speed = 6 + 4 * ($seed / 2147483647)
        $vx = - [math]::Sin($t) * $speed
        $vy = [math]::Cos($t) * $speed
        $x = $s * (3 * $vx - $vy)
        $y = $s * (3 * $vx + $vy)
        $seed = ($seed * 16807) % 2147483647
        $nx = Get-KcRound ($x + ($seed / 2147483647 - 0.5) * 2)
        $seed = ($seed * 16807) % 2147483647
        $ny = Get-KcRound ($y + ($seed / 2147483647 - 0.5) * 2)
        $out.Add(@([double]$nx, [double]$ny))
    }
    return , $out.ToArray()
}

$example = New-ExampleSamples

Test-Case '計測ページの例のデータを同じように作れる' {
    Assert-Equal 900 $example.Count
    Assert-Equal '-3,4' ($example[0] -join ',')
    Assert-Equal '-12,1' ($example[4] -join ',')
    Assert-Equal -72 (($example | ForEach-Object { $_[0] } | Measure-Object -Sum).Sum)
    Assert-Equal -87 (($example | ForEach-Object { $_[1] } | Measure-Object -Sum).Sum)
}

Test-Case '楕円の当てはめが計測ページ (JavaScript) と一致する' {
    # node で計測ページと同じ計算をした値: ratio 2.98728777316451、theta 0.7821138887398241
    $f = Get-KcEllipseFit $example
    Assert-Equal 900 $f.N
    Assert-Near 2.98728777316451 $f.Ratio 1e-9
    Assert-Near 0.7821138887398241 $f.Theta 1e-9
    $split = Split-KcBySpeed $example $f
    Assert-Near 3.0224889257376524 $split[0].Ratio 1e-9 '遅い動き'
    Assert-Near 2.968126143976296 $split[1].Ratio 1e-9 '速い動き'
}

Test-Case '補正行列: 行列式 1、補正後は真円' {
    $f = Get-KcEllipseFit $example
    $m = Get-KcCorrectionMatrix $f 1.0
    Assert-Near 1.0 ($m[0][0] * $m[1][1] - $m[0][1] * $m[1][0]) 1e-9 '行列式'
    $after = Get-KcEllipseFit @(foreach ($p in $example) { , (Invoke-KcMatrix $m $p) })
    Assert-Near 1.0 $after.Ratio 1e-6 '補正後の縦横比'
}

Test-Case 'KUKEY42: 今の行列に掛けた matrix の行が計測ページと同じ' {
    # 計測ページ (強さ 100%、今のファーム <995 -497 -305 2163>) の出力: matrix = <1319 (-1815) (-925) 2789>;
    $rec = New-KcEllipseRecommendation -Samples $example -Firmware $kukey -Thresholds $thresholds
    Assert-Equal 'WARN' $rec.Status
    Assert-Equal 'matrix = <1319 (-1815) (-925) 2789>;' $rec.Lines[0]
    Assert-Equal 'divisor = <1000>;' $rec.Lines[1]
    Assert-True ($rec.Lines[2] -like '// 計測: tools/keyboard-check*縦横比 2.99*') $rec.Lines[2]
    Assert-Equal '1.00' $rec.PredictedRatio
}

Test-Case '真円に近ければ PASS' {
    $circle = @()
    for ($i = 0; $i -lt 400; $i++) {
        $t = $i / 40 * [math]::PI * 2
        $circle += , @([double](Get-KcRound (-[math]::Sin($t) * 8)), [double](Get-KcRound ([math]::Cos($t) * 8)))
    }
    $rec = New-KcEllipseRecommendation -Samples $circle -Firmware $lismRight -Thresholds $thresholds
    Assert-Equal 'PASS' $rec.Status
}

Test-Case '傾きの無い楕円: zip_x_scaler / zip_y_scaler の推奨値' {
    $pts = @()
    for ($i = 0; $i -lt 400; $i++) {
        $t = $i / 40 * [math]::PI * 2
        $pts += , @(([math]::Cos($t) * 10), ([math]::Sin($t) * 20))
    }
    $rec = New-KcEllipseRecommendation -Samples $pts -Firmware $lismRight -Thresholds $thresholds
    Assert-Equal 'WARN' $rec.Status
    # 面積を保つので X は √2 倍、Y は 1/√2 倍 (分母 16 以下の分数で近似: 17/12、7/10)
    Assert-Equal '<&zip_x_scaler 17 12>, <&zip_y_scaler 7 10>' $rec.Lines[0]
}

Test-Case '点が少ないと SKIP、速さがばらつくと注意を出す' {
    $rec = New-KcEllipseRecommendation -Samples @(@(1, 2), @(3, 4)) -Firmware $lismRight -Thresholds $thresholds
    Assert-Equal 'SKIP' $rec.Status
    $pts = @()
    for ($i = 0; $i -lt 400; $i++) {
        $t = $i / 40 * [math]::PI * 2
        $sp = 3
        if ($i % 2 -eq 0) { $sp = 30 }
        # 速いときだけ X が伸びる (加速の影響)
        $k = 1.0
        if ($sp -eq 30) { $k = 1.8 }
        $pts += , @(([math]::Cos($t) * $sp * $k), ([math]::Sin($t) * $sp))
    }
    $rec = New-KcEllipseRecommendation -Samples $pts -Firmware $lismRight -Thresholds $thresholds
    Assert-True (@($rec.Notes | Where-Object { $_ -like '*一定の速さ*' }).Count -eq 1) ($rec.Notes -join ' / ')
}

Test-Case '分数の近似' {
    Assert-Equal '2,1' ((Get-KcRational 2.0 16) -join ',')
    Assert-Equal '3,2' ((Get-KcRational 1.5 16) -join ',')
    Assert-Equal '1,16' ((Get-KcRational 0.06 16) -join ',')
    foreach ($v in @(0.7, 1.13, 1.414, 2.37)) {
        $r = Get-KcRational $v 16
        Assert-True ([math]::Abs($r[0] / $r[1] - $v) / $v -lt 0.02) "$v の誤差"
    }
}

Test-Case '速さの計測: 1 回転あたりのカウントと実効 CPI' {
    $strokes = @(
        @{ Axis = 'x'; Dx = 2000; Dy = 30; Revolutions = 2 },
        @{ Axis = 'x'; Dx = 2040; Dy = -10; Revolutions = 2 },
        @{ Axis = 'y'; Dx = 0; Dy = 1600; Revolutions = 2 },
        @{ Axis = 'y'; Dx = 0; Dy = 1640; Revolutions = 2 }
    )
    $m = Get-KcSpeedMeasurement $strokes 34
    Assert-Near 1010.2 $m.PerRevX 0.2
    Assert-Near 810 $m.PerRevY 0.01
    Assert-Near ([math]::Sqrt($m.PerRevX * 810)) $m.PerRev 1e-9
    Assert-Near ($m.PerRev / ([math]::PI * 34 / 25.4)) $m.Cpi 1e-9
    Assert-True ($m.Spread -lt 0.03) '2 回の差'
    $none = Get-KcSpeedMeasurement $strokes $null
    Assert-Equal $null $none.Cpi
}

Test-Case '速さの推奨値: ZMK の倍率と PMW3610 の CPI' {
    $m = [pscustomobject]@{ PerRevX = 1000; PerRevY = 1000; PerRev = 1000; Spread = 0; Cpi = 600.0; DiameterMm = 34 }
    $ref = [pscustomobject]@{ Cpi = 900.0; PerRev = 1500; Source = 'LisM right' }
    $rec = New-KcSpeedRecommendation -Measurement $m -Reference $ref -Firmware $afrb -Thresholds $thresholds
    Assert-Equal 'WARN' $rec.Status
    Assert-Near 1.5 $rec.Scale 1e-9
    Assert-Equal 'cpi = <600>;' $rec.Lines[0]                   # 400 の 1.5 倍 (CPI を先に出す)
    Assert-Equal '<&zip_xy_scaler 3 1>' $rec.Lines[1]          # 今の 2/1 の 1.5 倍
    Assert-True (@($rec.Notes | Where-Object { $_ -like '*<&trackball_accel> より前*' }).Count -eq 1) ($rec.Notes -join ' / ')
    Assert-True (@($rec.Notes | Where-Object { $_ -like '*細かさが落ちる*' }).Count -eq 1) ($rec.Notes -join ' / ')
    $ok = New-KcSpeedRecommendation -Measurement $m -Reference ([pscustomobject]@{ Cpi = 630.0; PerRev = 1050; Source = 'x' }) -Firmware $kukey -Thresholds $thresholds
    Assert-Equal 'PASS' $ok.Status
    $noRef = New-KcSpeedRecommendation -Measurement $m -Reference $null -Firmware $kukey -Thresholds $thresholds
    Assert-Equal 'INFO' $noRef.Status
}

Test-Case '計測結果の保存と基準の選び方' {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('kc-calib-{0}.json' -f [guid]::NewGuid())
    try {
        $none = Read-KcCalibCache $path
        Assert-Equal 0 @($none).Count
        Save-KcCalibEntry $path ([pscustomobject]@{ time = '2026-10-01T10:00'; keyboard = 'lism'; ball = 'left'; per_rev = 1200; cpi = 800 })
        Save-KcCalibEntry $path ([pscustomobject]@{ time = '2026-10-01T10:05'; keyboard = 'lism'; ball = 'right'; per_rev = 1300; cpi = 850 })
        Save-KcCalibEntry $path ([pscustomobject]@{ time = '2026-10-01T10:10'; keyboard = 'kukey42'; ball = 'right'; per_rev = 900; cpi = 600 })
        $all = Read-KcCalibCache $path
        Assert-Equal 3 @($all).Count
        $ref = Get-KcSpeedReference $all
        Assert-Equal 850 $ref.Cpi
        Assert-True ($ref.Source -like 'LisM right*')
    } finally {
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# カーソルの加速を取り除く
# ---------------------------------------------------------------------------

$zmkAccel = [pscustomobject]@{ model = 'zmk'; label = 'trackball_accel'; min_factor = 500; max_factor = 1300; speed_threshold = 1000; speed_max = 4000 }
$keyballAccel = [pscustomobject]@{ model = 'keyball'; label = 'KEYBALL_ACCEL_*'; min_factor = 500; max_factor = 1300; speed_threshold = 1000; speed_max = 4000; interval_ms = 8; clamp = 127 }

Test-Case '加速の倍率と、その逆算' {
    # README の「カーソルの加速の調整」の表
    $table = @(@(0, 0.5), @(500, 0.75), @(1000, 1.0), @(2500, 1.15), @(4000, 1.3), @(9000, 1.3))
    foreach ($row in $table) {
        Assert-Near $row[1] (Get-KcAccelFactor $zmkAccel $row[0]) 1e-12 ('速さ {0}' -f $row[0])
    }
    foreach ($v in @(0.0, 1.0, 200.0, 999.0, 1000.0, 1500.0, 3999.0, 4000.0, 8000.0)) {
        $after = $v * (Get-KcAccelFactor $zmkAccel $v)
        Assert-Near $v (Get-KcAccelSpeedBefore $zmkAccel $after) 1e-6 ('速さ {0}' -f $v)
    }
    $flat = [pscustomobject]@{ model = 'zmk'; min_factor = 1000; max_factor = 1000; speed_threshold = 1000; speed_max = 4000 }
    Assert-Near 700.0 (Get-KcAccelSpeedBefore $flat 700.0) 1e-9 '加速なし'
    Assert-Near 5.0 (Get-KcAccelDistance $zmkAccel 3 -4) 1e-12
    Assert-Near 5.0 (Get-KcAccelDistance $keyballAccel -4 2) 1e-12 'Keyball は大きいほう + 小さいほうの半分'
}

# --- ファームの処理を真似た計算 (zmk-input-processor-xy-accel と keyball39 via の keymap.c) ---

# センサーの報告: 速度 (カウント/秒) を積分して整数に丸める。$VelX / $VelY: 時刻 (秒) ごとの速度の配列を作る関数の代わりに、
# 報告ごとの速度を渡す
function New-SimReports([double[]]$Vx, [double[]]$Vy, [double]$PeriodMs, [double]$T0) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    $ax = 0.0; $ay = 0.0; $qx = 0; $qy = 0
    for ($i = 0; $i -lt $Vx.Length; $i++) {
        $ax += $Vx[$i] * $PeriodMs / 1000.0
        $ay += $Vy[$i] * $PeriodMs / 1000.0
        $nx = [long][math]::Round($ax)
        $ny = [long][math]::Round($ay)
        $out.Add(@(([long][math]::Floor($T0 + ($i + 1) * $PeriodMs)), ($nx - $qx), ($ny - $qy)))
        $qx = $nx; $qy = $ny
    }
    return , $out.ToArray()
}

function Get-SimFactor([long]$Speed) {
    if ($Speed -ge 4000) { return 1300 }
    if ($Speed -le 1000) { return 500 + [long][math]::Floor(500 * $Speed / 1000) }
    return 1000 + [long][math]::Floor(300 * ($Speed - 1000) / 3000)
}

# ZMK: 報告の終わりに 8ms 以上の区間の速さを求めて直前の値と平均し、次の報告の倍率にする。50ms 止まると最小の倍率から
function Invoke-SimZmkAccel($Reports) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    $last = 0; $ws = 0; $wd = 0; $speed = 0; $f = 500; $rx = 0; $ry = 0
    foreach ($r in $Reports) {
        $t = [long]$r[0]; $x = [long]$r[1]; $y = [long]$r[2]
        if ($last -eq 0 -or $t - $last -gt 50) {
            $speed = 0; $f = 500; $ws = $t - 50; $wd = 0
        }
        $tx = $x * $f + $rx
        $ox = [long][math]::Truncate($tx / 1000)
        $rx = $tx - $ox * 1000
        $ty = $y * $f + $ry
        $oy = [long][math]::Truncate($ty / 1000)
        $ry = $ty - $oy * 1000
        $wd += [long][math]::Floor([math]::Sqrt($x * $x + $y * $y))
        $last = $t
        $el = $t - $ws
        if ($el -ge 8) {
            $sp = [long][math]::Floor($wd * 1000 / [math]::Min($el, 50))
            $speed = [long][math]::Floor(($speed + $sp) / 2)
            $f = Get-SimFactor $speed
            $ws = $t; $wd = 0
        }
        if ($ox -ne 0 -or $oy -ne 0) {
            $out.Add(@([double]$ox, [double]$oy, [double]($t + ($out.Count % 2))))
        }
    }
    return , $out.ToArray()
}

# Keyball: 8ms ごとに、移動量 (大きいほう + 小さいほうの半分) の 16 倍と直前の値を平均して倍率を決める (256 = 等倍)
function Invoke-SimKeyballAccel($Reports) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    $min = 128; $max = 332; $thr = 128; $smax = 512
    $speed = 0; $rx = 0; $ry = 0
    foreach ($r in $Reports) {
        $t = [long]$r[0]; $x = [long]$r[1]; $y = [long]$r[2]
        $ax = [math]::Abs($x); $ay = [math]::Abs($y)
        if ($ax -gt $ay) { $d = $ax + [math]::Floor($ay / 2) } else { $d = $ay + [math]::Floor($ax / 2) }
        $d = [math]::Min($d, 1023)
        $speed = [long][math]::Floor(($speed + $d * 16) / 2)
        if ($speed -ge $smax) { $f = $max }
        elseif ($speed -le $thr) { $f = $min + [long][math]::Floor((256 - $min) * $speed / $thr) }
        else { $f = 256 + [long][math]::Floor(($max - 256) * ($speed - $thr) / ($smax - $thr)) }
        $tx = $x * $f + $rx
        $ox = [long][math]::Floor($tx / 256)
        $rx = $tx - $ox * 256
        $ty = $y * $f + $ry
        $oy = [long][math]::Floor($ty / 256)
        $ry = $ty - $oy * 256
        $ox = [math]::Max(-127, [math]::Min(127, $ox))
        $oy = [math]::Max(-127, [math]::Min(127, $oy))
        if ($ox -ne 0 -or $oy -ne 0) {
            $out.Add(@([double]$ox, [double]$oy, [double]($t + ($out.Count % 2))))
        }
    }
    return , $out.ToArray()
}

# 縦横比 3 (＼ 45°) の楕円を、速さを 0.4〜1.6 倍に変えながら 10 秒右回り → 10 秒左回り
function New-SimEllipse([double]$Base, [double]$PeriodMs) {
    $n = [int](20000 / $PeriodMs)
    $vx = New-Object 'double[]' $n
    $vy = New-Object 'double[]' $n
    $a = [math]::Sqrt(3.0); $b = 1 / [math]::Sqrt(3.0)
    $c = [math]::Cos([math]::PI / 4); $s = [math]::Sin([math]::PI / 4)
    $m00 = $a * $c * $c + $b * $s * $s; $m01 = ($a - $b) * $c * $s; $m11 = $a * $s * $s + $b * $c * $c
    $ph = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $t = ($i + 0.5) * $PeriodMs / 1000.0
        $k = 1.0 + 0.6 * [math]::Sin(2 * [math]::PI * $t / 3.7)
        $d = 1.0
        if ($t -ge 10.0) { $d = -1.0 }
        $ph += 2 * [math]::PI / 1.2 * $k * $PeriodMs / 1000.0 * $d
        $ux = - [math]::Sin($ph) * $Base * $k * $d
        $uy = [math]::Cos($ph) * $Base * $k * $d
        $vx[$i] = $m00 * $ux + $m01 * $uy
        $vy[$i] = $m01 * $ux + $m11 * $uy
    }
    return , (New-SimReports $vx $vy $PeriodMs 1000)
}

# 右へ $Total カウント: 速さは山なり ($Ms ミリ秒)
function New-SimStroke([double]$Total, [double]$Ms, [double]$PeriodMs) {
    $n = [int](($Ms + 300) / $PeriodMs)
    $vx = New-Object 'double[]' $n
    $vy = New-Object 'double[]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $t = ($i + 0.5) * $PeriodMs
        $v = 0.0
        if ($t -lt $Ms) { $v = $Total * ([math]::PI / ($Ms / 1000.0)) / 2 * [math]::Sin([math]::PI * $t / $Ms) }
        $vx[$i] = $v
        $vy[$i] = $v * 0.05
    }
    return , (New-SimReports $vx $vy $PeriodMs 1000)
}

$simFirmware = [pscustomobject]@{ side = 'right'; correction = 'zip_scaler'; xy_scaler = @(1, 1); listener = 'x'; accel = $zmkAccel }
$simNoAccel = [pscustomobject]@{ side = 'right'; correction = 'zip_scaler'; xy_scaler = @(1, 1); listener = 'x'; accel = $null }

Test-Case '楕円: ファームの加速を取り除くと、本当の縦横比に戻る (ZMK)' {
    $reports = New-SimEllipse 800 15
    $post = Invoke-SimZmkAccel $reports
    $rec = New-KcEllipseRecommendation -Samples $post -Firmware $simFirmware -Thresholds $thresholds
    Assert-Near 3.0 $rec.Fit.Ratio 0.09 '加速を取り除いた縦横比 (3% 以内)'
    Assert-Near 45.0 $rec.Tilt 2.0 '傾き'
    Assert-True ($rec.Lines[-1] -like '*加速を除く*') $rec.Lines[-1]
    $raw = New-KcEllipseRecommendation -Samples $post -Firmware $simNoAccel -Thresholds $thresholds
    Assert-True ($raw.Fit.Ratio -gt 3.2) ('加速を取り除かないと細長く出る: {0:F3}' -f $raw.Fit.Ratio)
}

Test-Case '楕円: ファームの加速を取り除くと、本当の縦横比に戻る (Keyball)' {
    $reports = New-SimEllipse 800 8
    $post = Invoke-SimKeyballAccel $reports
    $fw = [pscustomobject]@{ side = 'right'; correction = 'cpi_only'; xy_scaler = @(1, 1); listener = 'Keyball'; accel = $keyballAccel }
    $rec = New-KcEllipseRecommendation -Samples $post -Firmware $fw -Thresholds $thresholds
    Assert-Near 3.0 $rec.Fit.Ratio 0.09 '加速を取り除いた縦横比 (3% 以内)'
}

Test-Case '速さ: ファームの加速を取り除くと、1 回転あたりのカウントが速さによらない' {
    foreach ($case in @(@(2000, 600), @(2000, 3000), @(6000, 1500))) {
        $reports = New-SimStroke $case[0] $case[1] 15
        $truth = 0.0
        foreach ($r in $reports) { $truth += $r[1] }
        $post = Invoke-SimZmkAccel $reports
        $pre = Remove-KcAccel $post $zmkAccel ([int]$thresholds.accel_window_ms) ([int]$thresholds.accel_idle_ms)
        Assert-Near 1.0 ($pre.Dx / $truth) 0.03 ('{0} カウント / {1}ms' -f $case[0], $case[1])
        Assert-Equal 0 $pre.Saturated
    }
    $reports = New-SimStroke 4000 1500 8
    $truth = 0.0
    foreach ($r in $reports) { $truth += $r[1] }
    $pre = Remove-KcAccel (Invoke-SimKeyballAccel $reports) $keyballAccel ([int]$thresholds.accel_window_ms) ([int]$thresholds.accel_idle_ms)
    Assert-Near 1.0 ($pre.Dx / $truth) 0.03 'Keyball'
    # 速すぎると 1 回の報告が ±127 で頭打ちになり、カウントが失われる → やり直しを促す
    $fast = Remove-KcAccel (Invoke-SimKeyballAccel (New-SimStroke 6000 500 8)) $keyballAccel 40 50
    Assert-True ($fast.Saturated -gt 0) 'Keyball の上限'
}

Test-Case '移動量を時間でまとめる' {
    $s = @(@(1.0, 0.0, 0.0), @(2.0, 1.0, 10.0), @(3.0, 0.0, 39.0), @(1.0, 1.0, 40.0), @(5.0, 5.0, 200.0))
    $b = Join-KcSamplesByTime $s 40
    Assert-Equal 3 @($b).Count
    Assert-Equal 6.0 $b[0][0]
    Assert-Equal 1.0 $b[0][1]
    Assert-Equal 40.0 $b[1][2]
    Assert-Equal 200.0 $b[2][2]
}
