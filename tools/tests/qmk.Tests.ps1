# VIA / Vial の読み出し検査 (qmk.ps1) のテスト。偽のデバイス (fake-devices.ps1) を使う

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'results.ps1')
. (Join-Path $script:KcLib 'qmk.ps1')
. (Join-Path $script:TestsDir 'fake-devices.ps1')

$common = Get-KcExpected 'common' $script:ExpectedDir
$kqExp = Get-KcExpected 'kq-mini' $script:ExpectedDir
$kbExp = Get-KcExpected 'keyball39' $script:ExpectedDir

function Get-StatusOf($Results, [string]$Item) {
    $r = @($Results | Where-Object { $_.Item -eq $Item })
    if ($r.Count -eq 0) {
        throw "結果に $Item がありません"
    }
    return $r[0]
}

function Get-FailItems($Results) {
    return ((@($Results | Where-Object { $_.Status -eq 'FAIL' }) | ForEach-Object { $_.Item }) -join ', ')
}

Test-Case '許可リスト: 読み取りコマンドだけ通す' {
    foreach ($ok in @(@(0x01), @(0x02, 0x01), @(0x02, 0x02), @(0x08, 0x02, 0x01), @(0x08, 0x00, 0x01), @(0x08, 0x00, 0x03), @(0x0C), @(0x0D), @(0x0E, 0, 0, 28),
            @(0x11), @(0x12, 0, 0, 28), @(0xFE, 0x00), @(0xFE, 0x05), @(0xFE, 0x09, 0, 0), @(0xFE, 0x0A, 7, 0), @(0xFE, 0x0D, 0x05, 3))) {
        Assert-True (Test-KcQmkCommandAllowed ([byte[]]$ok)) ('許可されるべき: ' + ($ok -join ' '))
    }
    foreach ($ng in @(@(0x03), @(0x05, 0, 0, 0, 0, 4), @(0x06), @(0x07), @(0x09), @(0x0A), @(0x0B), @(0x0F), @(0x10), @(0x13),
            @(0x02, 0x03), @(0x07, 0x02, 0x01), @(0x08, 0x00, 0x04), @(0xFE, 0x06), @(0xFE, 0x07), @(0xFE, 0x0B), @(0xFE, 0x0C),
            @(0xFE, 0x0D, 0x02), @(0xFE, 0x0D, 0x06), @(0xFE, 0x04))) {
        Assert-True (-not (Test-KcQmkCommandAllowed ([byte[]]$ng))) ('拒否されるべき: ' + ($ng -join ' '))
    }
    $dev = New-FakeKqMini $kqExp
    Assert-Throws { Invoke-KcQmk $dev.Query ([byte[]](0xFE, 0x06)) 0 } '*読み取り専用でない*'
    Assert-Equal 0 $dev.Log.Count '拒否したコマンドはデバイスに送らない'
}

Test-Case 'キーマップのバッファの変換 (ビッグエンディアン)' {
    $bytes = [byte[]](0x00, 0x14, 0x52, 0x22, 0x7E, 0x00, 0x00, 0x01)
    $km = ConvertFrom-KcViaKeymapBuffer $bytes 2 1 2
    Assert-Equal 0x14 $km[0][0][0]
    Assert-Equal 0x5222 $km[0][0][1]
    Assert-Equal 0x7E00 $km[1][0][0]
    Assert-Equal 1 $km[1][0][1]
}

Test-Case 'マクロのバイト列: 拡張キーコードの表記の違いをそろえる' {
    $basic = ConvertFrom-KcMacroBytes ([byte[]](1, 1, 0x04, 1, 4, 11, 1))
    $ext = ConvertFrom-KcMacroBytes ([byte[]](1, 5, 0x04, 0x00, 1, 4, 11, 1))
    Assert-Equal ($basic -join ' ') ($ext -join ' ')
    Assert-Equal 'tap:0004 delay:10' ($basic -join ' ')
    $hi = ConvertFrom-KcMacroBytes ([byte[]](1, 5, 0x01, 0xFF))
    Assert-Equal 'tap:0100' ($hi -join ' ')
    $split = Split-KcMacroBuffer ([byte[]](1, 2, 0, 0, 3, 0)) 4
    Assert-Equal 4 $split.Count
    Assert-Equal 2 @($split[0]).Count
    Assert-Equal 0 @($split[1]).Count
    Assert-Equal 0 @($split[3]).Count
}

Test-Case 'KQ-mini: 期待値どおりなら全部 PASS' {
    $dev = New-FakeKqMini $kqExp
    $r = New-KcResultList
    Invoke-KcKqMiniReadout -Query $dev.Query -Expected $kqExp -Common $common -Results $r
    Assert-Equal '' (Get-FailItems $r) 'FAIL の項目'
    foreach ($item in @('Vial の ID', 'キーマップ', 'タップホールドの設定', 'タップダンス', 'キーオーバーライド', 'コンボ', '代替リピート', 'マクロ')) {
        Assert-Equal 'PASS' (Get-StatusOf $r $item).Status $item
    }
    Assert-Equal 'FE 00' $dev.Log[0] '最初に Vial の ID を問い合わせる'
}

Test-Case 'KQ-mini: キーを 1 つ変えると、その 1 セルだけ FAIL' {
    $dev = New-FakeKqMini $kqExp
    $dev.Keymap[0][1][4] = 0x05   # HID 0x04 (A) のセル: LCTL_T(KC_A) → KC_B
    $r = New-KcResultList
    Invoke-KcKqMiniReadout -Query $dev.Query -Expected $kqExp -Common $common -Results $r
    $km = Get-StatusOf $r 'キーマップ'
    Assert-Equal 'FAIL' $km.Status
    Assert-Equal 1 @($km.Details).Count
    Assert-True ($km.Details[0] -like '*L0 BASE_QWERTY*KC_A (行 1 列 4)*MT(LCTL, KC_A)*KC_B*') $km.Details[0]
    Assert-Equal 'キーマップ' (Get-FailItems $r)
}

Test-Case 'KQ-mini: マウスの中継のセルが違うと Hint で知らせる' {
    $dev = New-FakeKqMini $kqExp
    $dev.Keymap[0][26][7] = 0xDB  # KC_MS_LEFT → KC_WH_L (X がスクロールになる)
    $r = New-KcResultList
    Invoke-KcKqMiniReadout -Query $dev.Query -Expected $kqExp -Common $common -Results $r
    $km = Get-StatusOf $r 'キーマップ'
    Assert-True ($km.Hint -like '*マウスの中継*マウスの X*') $km.Hint
}

Test-Case 'KQ-mini: tapping term・コンボ・キーオーバーライドの違いを見つける' {
    $dev = New-FakeKqMini $kqExp
    $dev.Settings[7] = 200
    $dev.Combo[2] = ConvertTo-FakeStruct @(0x04, 0x05, 0, 0, 0x06)
    $ko = [byte[]]$dev.KeyOverride[0].Clone()
    $ko[4] = 0x08   # layers
    $dev.KeyOverride[0] = $ko
    $r = New-KcResultList
    Invoke-KcKqMiniReadout -Query $dev.Query -Expected $kqExp -Common $common -Results $r
    Assert-Equal 'タップホールドの設定, キーオーバーライド, コンボ' (Get-FailItems $r)
    Assert-True ((Get-StatusOf $r 'タップホールドの設定').Details[0] -like '*tapping_term*150*200*') 'tapping term'
    Assert-True ((Get-StatusOf $r 'キーオーバーライド').Details[0] -like '*mm_vim_w*layers*') 'key override'
}

Test-Case 'KQ-mini: Vial のアンロック中は読まずに止める' {
    $dev = New-FakeKqMini $kqExp
    $dev.UnlockInProgress = 1
    $r = New-KcResultList
    Invoke-KcKqMiniReadout -Query $dev.Query -Expected $kqExp -Common $common -Results $r
    Assert-Equal 'SKIP' (Get-StatusOf $r 'Vial のロック').Status
    Assert-Equal 2 $dev.Log.Count 'FE 00 と FE 05 のあとは何も送らない'
}

Test-Case 'Keyball39: 期待値どおりなら全部 PASS' {
    $dev = New-FakeKeyball $kbExp
    $r = New-KcResultList
    Invoke-KcKeyballReadout -Query $dev.Query -Expected $kbExp -Common $common -Results $r
    Assert-Equal '' (Get-FailItems $r) 'FAIL の項目'
    Assert-Equal 'PASS' (Get-StatusOf $r 'キーマップ').Status
    Assert-Equal 'PASS' (Get-StatusOf $r 'CPI').Status
    Assert-Equal 'PASS' (Get-StatusOf $r 'AML のタイムアウト').Status
    Assert-Equal 'Right' (Get-StatusOf $r 'Ball availability').Actual
    Assert-Equal 'PASS' (Get-StatusOf $r 'マクロ').Status
    Assert-Equal 'PASS' (Get-StatusOf $r 'カーソルの加速').Status
    Assert-True ((Get-StatusOf $r 'カーソルの加速').Actual -like 'min-factor 500 / max-factor 1300*') (Get-StatusOf $r 'カーソルの加速').Actual
}

Test-Case 'Keyball39: カーソルの加速が期待値と違うと FAIL' {
    $dev = New-FakeKeyball $kbExp
    $dev.KeyballAccel[2] = 0x03      # max-factor 1000 (0x03E8): 加速なし
    $dev.KeyballAccel[3] = 0xE8
    $r = New-KcResultList
    Invoke-KcKeyballReadout -Query $dev.Query -Expected $kbExp -Common $common -Results $r
    Assert-Equal 'カーソルの加速' (Get-FailItems $r)
    Assert-True ((Get-StatusOf $r 'カーソルの加速').Actual -like '*max-factor 1000*') (Get-StatusOf $r 'カーソルの加速').Actual
}

Test-Case 'Keyball39: EEPROM に古い CPI が残っていると FAIL と Bootmagic の案内' {
    $dev = New-FakeKeyball $kbExp
    $dev.KeyballStatus[3] = 12
    $dev.LayoutOptions = 0
    $dev.Keymap[1][1][2] = 0      # D の MO(2) が消えた
    $r = New-KcResultList
    Invoke-KcKeyballReadout -Query $dev.Query -Expected $kbExp -Common $common -Results $r
    Assert-Equal 'キーマップ, Ball availability, CPI' (Get-FailItems $r)
    Assert-True ((Get-StatusOf $r 'CPI').Hint -like '*Bootmagic*') 'Bootmagic の案内'
    Assert-True ((Get-StatusOf $r 'キーマップ').Details[0] -like '*L1*L12 D*MO(2)*KC_NO*') (Get-StatusOf $r 'キーマップ').Details[0]
}

Test-Case 'Keyball39: 古いファームでは設定を SKIP' {
    $dev = New-FakeKeyball $kbExp -OldFirmware
    $r = New-KcResultList
    Invoke-KcKeyballReadout -Query $dev.Query -Expected $kbExp -Common $common -Results $r
    Assert-Equal '' (Get-FailItems $r)
    Assert-Equal 'SKIP' (Get-StatusOf $r 'トラックボールの設定 (CPI / スクロール / AML)').Status
    # 08 00 01 はあるが 08 00 03 の無いファーム
    $dev = New-FakeKeyball $kbExp
    $dev.KeyballAccel = $null
    $r = New-KcResultList
    Invoke-KcKeyballReadout -Query $dev.Query -Expected $kbExp -Common $common -Results $r
    Assert-Equal '' (Get-FailItems $r)
    Assert-Equal 'SKIP' (Get-StatusOf $r 'カーソルの加速').Status
}
