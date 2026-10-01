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

Test-Case '直線テストのずれは回転として補正に入る' {
    $pts = @()
    for ($i = 0; $i -lt 400; $i++) {
        $t = $i / 40 * [math]::PI * 2
        $pts += , @(([math]::Cos($t) * 10), ([math]::Sin($t) * 10))
    }
    $r = 10.0 * [math]::PI / 180
    $strokes = @(
        @{ Expect = '+x'; Dx = (500 * [math]::Cos($r)); Dy = (500 * [math]::Sin($r)) },
        @{ Expect = '+y'; Dx = (-500 * [math]::Sin($r)); Dy = (500 * [math]::Cos($r)) }
    )
    $rec = New-KcEllipseRecommendation -Samples $pts -Strokes $strokes -Firmware $lismRight -Thresholds $thresholds
    Assert-Near 10.0 $rec.Rotation 0.01 '回転'
    Assert-Equal 'WARN' $rec.Status
    $v = Invoke-KcMatrix $rec.Matrix @($strokes[0].Dx, $strokes[0].Dy)
    Assert-Near 0.0 ([math]::Atan2($v[1], $v[0]) * 180 / [math]::PI) 0.01 '補正後は真横'
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
    Assert-Equal '<&zip_xy_scaler 3 1>' $rec.Lines[0]          # 今の 2/1 の 1.5 倍
    Assert-Equal 'cpi = <600>;' $rec.Lines[1]                   # 400 の 1.5 倍
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
