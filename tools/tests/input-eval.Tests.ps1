# 実動作テストの判定 (input-eval.ps1) のテスト

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'input-eval.ps1')

$common = Get-KcExpected 'common' $script:ExpectedDir
$scan = New-KcScanTable $common
$lism = Get-KcExpected 'lism' $script:ExpectedDir

# usage → スキャンコードのキーイベント (押す / 離す)
function New-TapEvents([int[]]$Usages, [long]$Start = 0) {
    $events = @()
    $t = $Start
    foreach ($u in $Usages) {
        $k = $scan.ByUsage[$u]
        $events += New-KcKeyEvent $t ([int]$k.scan) ([int]$k.prefix) $false
        $t += 5
    }
    foreach ($u in $Usages) {
        $k = $scan.ByUsage[$u]
        $events += New-KcKeyEvent $t ([int]$k.scan) ([int]$k.prefix) $true
        $t += 5
    }
    return , $events
}

Test-Case 'タップ: 期待したキーだけなら PASS' {
    $tap = @($lism.interactive.taps | Where-Object { $_.pos -eq 10 })[0]   # A (タップ) / 左 Ctrl (ホールド)
    Assert-Equal 'PASS' (Test-KcTap (New-TapEvents @(0x04)) $tap $scan).Status
    Assert-Equal 'HOLD' (Test-KcTap (New-TapEvents @(0xE0)) $tap $scan).Status
    $bad = Test-KcTap (New-TapEvents @(0x05)) $tap $scan
    Assert-Equal 'FAIL' $bad.Status
    Assert-Equal 'B' $bad.Actual
    Assert-Equal 'NONE' (Test-KcTap @() $tap $scan).Status
}

Test-Case 'タップ: Win キー (E0 付きのスキャンコード) とオートリピート' {
    $tap = @($lism.interactive.taps | Where-Object { $_.pos -eq 31 })[0]
    Assert-Equal 0xE3 ([int]$tap.usage)
    $events = @(
        (New-KcKeyEvent 0 0x5B 0xE0 $false), (New-KcKeyEvent 30 0x5B 0xE0 $false), (New-KcKeyEvent 60 0x5B 0xE0 $false),
        (New-KcKeyEvent 90 0x5B 0xE0 $true)
    )
    $actions = ConvertTo-KcKeyActions $events $scan
    Assert-Equal 1 @($actions | Where-Object { $_.Down }).Count 'リピートはまとめる'
    Assert-Equal 'PASS' (Test-KcTap $events $tap $scan).Status
    # 左 Alt (E0 なし) と右 Alt (E0 付き) は区別する
    $alt = @($lism.interactive.taps | Where-Object { $_.pos -eq 32 })[0]
    Assert-Equal 'FAIL' (Test-KcTap @((New-KcKeyEvent 0 0x38 0xE0 $false), (New-KcKeyEvent 9 0x38 0xE0 $true)) $alt $scan).Status
}

Test-Case 'すべて離して一定時間たったら判定する' {
    $events = New-TapEvents @(0x04)
    Assert-True (-not (Test-KcKeysSettled @($events[0]) $scan 1000 300)) '押したまま'
    Assert-True (-not (Test-KcKeysSettled $events $scan 100 300)) 'まだ待つ'
    Assert-True (Test-KcKeysSettled $events $scan 400 300) '判定できる'
}

Test-Case '向き: 正しい / 逆 / X と Y の入れ替わり' {
    $right = Measure-KcMotion @((New-KcMouseEvent 0 30 2), (New-KcMouseEvent 8 40 -1), (New-KcMouseEvent 16 35 3))
    $r = Test-KcDirection $right '+x'
    Assert-Equal 'PASS' $r.Status
    Assert-True ([math]::Abs($r.Angle) -lt 5)
    $inv = Test-KcDirection (Measure-KcMotion @((New-KcMouseEvent 0 -100 0))) '+x'
    Assert-Equal 'FAIL' $inv.Status
    Assert-Equal '向きが逆です' $inv.Message
    $swap = Test-KcDirection (Measure-KcMotion @((New-KcMouseEvent 0 0 100))) '+x'
    Assert-Equal 'X と Y が入れ替わっています' $swap.Message
    Assert-Equal 'PASS' (Test-KcDirection (Measure-KcMotion @((New-KcMouseEvent 0 5 100))) '+y').Status
    Assert-Equal 'NONE' (Test-KcDirection (Measure-KcMotion @((New-KcMouseEvent 0 5 5))) '+y').Status
}

Test-Case 'スクロール: ホイールと同じ向きが PASS' {
    $down = Measure-KcMotion @((New-KcMouseEvent 0 0 0 0 -120), (New-KcMouseEvent 30 0 0 0 -120), (New-KcMouseEvent 60 0 0 0 -120))
    Assert-Equal 'PASS' (Test-KcScroll $down 'wheel-').Status
    $up = Measure-KcMotion @((New-KcMouseEvent 0 0 0 0 120), (New-KcMouseEvent 30 0 0 0 120))
    $r = Test-KcScroll $up 'wheel-'
    Assert-Equal 'FAIL' $r.Status
    Assert-Equal 'スクロールの向きが逆です' $r.Message
    $h = Measure-KcMotion @((New-KcMouseEvent 0 0 0 0 0 120), (New-KcMouseEvent 30 0 0 0 0 120))
    Assert-Equal 'PASS' (Test-KcScroll $h 'hwheel+').Status
    Assert-Equal '縦と横のスクロールが入れ替わっています' (Test-KcScroll $h 'wheel-').Message
    $cursor = Measure-KcMotion @((New-KcMouseEvent 0 0 300))
    Assert-True ((Test-KcScroll $cursor 'wheel-').Message -like '*スクロールレイヤーになっていない*')
}

Test-Case 'AML のクリック、Shift + クリック、タイムアウト' {
    $click = @((New-KcMouseEvent 0 0 0 0x0001), (New-KcMouseEvent 40 0 0 0x0002))
    Assert-Equal 'PASS' (Test-KcAmlClick $click 1 $scan).Status
    $typed = (New-TapEvents @(0x07)) + (New-TapEvents @(0x09) 50)
    Assert-Equal 'FAIL' (Test-KcAmlClick $typed 1 $scan).Status
    Assert-Equal 'NONE' (Test-KcAmlClick @() 1 $scan).Status

    $shift = $scan.ByUsage[0xE1]
    $sc = @(
        (New-KcKeyEvent 0 ([int]$shift.scan) 0 $false), (New-KcMouseEvent 50 0 0 0x0001), (New-KcMouseEvent 90 0 0 0x0002),
        (New-KcKeyEvent 120 ([int]$shift.scan) 0 $true)
    )
    Assert-Equal 'PASS' (Test-KcShiftClick $sc 0xE1 1 $scan).Status
    $late = @((New-KcMouseEvent 0 0 0 0x0001), (New-KcMouseEvent 10 0 0 0x0002), (New-KcKeyEvent 50 ([int]$shift.scan) 0 $false), (New-KcKeyEvent 60 ([int]$shift.scan) 0 $true))
    Assert-Equal 'FAIL' (Test-KcShiftClick $late 0xE1 1 $scan).Status
    $z = (New-TapEvents @(0x1D)) + $sc
    Assert-Equal 'FAIL' (Test-KcShiftClick $z 0xE1 1 $scan).Status

    Assert-Equal 'PASS' (Test-KcAfterTimeout (New-TapEvents @(0x09)) 0x09 $scan).Status
    Assert-Equal 'FAIL' (Test-KcAfterTimeout $click 0x09 $scan).Status
}

Test-Case 'AML の Ctrl / Shift での解除' {
    Assert-Equal 'PASS' (Test-KcAmlRelease (New-TapEvents @(0x1D)) 0x1D $scan).Status
    $modOnly = Test-KcAmlRelease (New-TapEvents @(0xE1)) 0x1D $scan
    Assert-Equal 'FAIL' $modOnly.Status
    Assert-True ($modOnly.Message -like '*修飾キーだけ*')
    Assert-Equal 'FAIL' (Test-KcAmlRelease (New-TapEvents @(0x09)) 0x1D $scan).Status
    Assert-Equal 'NONE' (Test-KcAmlRelease @() 0x1D $scan).Status
}

Test-Case 'ボールと反対の手のキーを使う' {
    $tb = $lism.interactive.trackball
    Assert-Equal 'D' (Get-KcHandKeys $tb 'right').scroll.legend
    Assert-Equal 'K' (Get-KcHandKeys $tb 'left').scroll.legend
    Assert-Equal 'A' (Get-KcHandKeys $tb 'right').release_ctrl.legend
    Assert-Equal '/' (Get-KcHandKeys $tb 'left').release_shift.legend
}
