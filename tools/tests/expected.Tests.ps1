# 期待値の読み込み、キーコード・バインディングの表示名、結果の集計のテスト

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'results.ps1')

$common = Get-KcExpected 'common' $script:ExpectedDir
$lism = Get-KcExpected 'lism' $script:ExpectedDir
$kq = Get-KcExpected 'kq-mini' $script:ExpectedDir

Test-Case '期待値の JSON を読める' {
    foreach ($id in @('common', 'kq-mini', 'keyball39', 'lism', 'kukey42', 'aroundfortyrb', 'pyuron', 'roba', 'torabo-tsuki-lp')) {
        $d = Get-KcExpected $id $script:ExpectedDir
        Assert-Equal 2 $d.schema "$id の schema"
        Assert-Equal $id $d.id "$id の id"
    }
    Assert-Equal 'Mod-Tap' $lism.readout.zmk.bindings[0][10].b
}

Test-Case 'Get-KcProp は無いプロパティで既定値を返す' {
    Assert-Equal 'x' (Get-KcProp $lism 'no_such_property' 'x')
    Assert-Equal 'LisM' (Get-KcProp $lism 'name')
    Assert-Equal 3 (Get-KcProp @{ a = 3 } 'a')
    Assert-Equal $null (Get-KcProp $null 'a')
}

Test-Case 'QMK キーコードの表示名' {
    $names = New-KcQmkNames $common $kq
    Assert-Equal 'KC_A' (Format-KcQmkKeycode 0x04 $names)
    Assert-Equal 'MT(LCTL, KC_A)' (Format-KcQmkKeycode 0x2104 $names)
    Assert-Equal 'MT(RCTL, KC_MINUS)' (Format-KcQmkKeycode 0x312D $names)
    Assert-Equal 'LT(2, KC_SPACE)' (Format-KcQmkKeycode 0x422C $names)
    Assert-Equal 'MO(6) FUNCTION' (Format-KcQmkKeycode 0x5226 $names)
    Assert-Equal 'LCTL(KC_RIGHT)' (Format-KcQmkKeycode 0x014F $names)
    Assert-Equal 'TD(2)' (Format-KcQmkKeycode 0x5702 $names)
    Assert-Equal 'M11' (Format-KcQmkKeycode 0x770B $names)
    Assert-Equal 'MM_VIM_W (キャリア)' (Format-KcQmkKeycode 0x7E03 $names)
    Assert-Equal 'KC_BTN1' (Format-KcQmkKeycode 0xD1 $names)
    Assert-Equal 'QK_BOOT' (Format-KcQmkKeycode 0x7C00 $names)
}

Test-Case 'ZMK バインディングの表示名' {
    $names = New-KcZmkNames $common $lism
    Assert-Equal '&mt LEFT_CONTROL A' (Format-KcZmkBinding 'Mod-Tap' 0x000700E0 0x00070004 $names)
    Assert-Equal '&lt VIM_BASE SPACE' (Format-KcZmkBinding 'Layer-Tap' 2 0x0007002C $names)
    Assert-Equal '&kp LS(LC(RIGHT_ARROW))' (Format-KcZmkBinding 'Key Press' 0x0307004F 0 $names)
    Assert-Equal '&bt BT_SEL 1' (Format-KcZmkBinding 'Bluetooth' 3 1 $names)
    Assert-Equal '&bt BT_CLR' (Format-KcZmkBinding 'Bluetooth' 0 0 $names)
    Assert-Equal '&out OUT_USB' (Format-KcZmkBinding 'Output Selection' 1 0 $names)
    Assert-Equal '&mkp MB4' (Format-KcZmkBinding 'Mouse Key Press' 8 0 $names)
    Assert-Equal '&trans' (Format-KcZmkBinding 'Transparent' 0 0 $names)
    Assert-Equal '&mm_vim_w' (Format-KcZmkBinding 'MM_VIM_W' 0 0 $names)
}

Test-Case 'スキャンコード表' {
    $t = New-KcScanTable $common
    Assert-Equal 4 $t.ByScan['0:30']
    Assert-Equal 0xE3 $t.ByScan['224:91']
    Assert-Equal 'Space' (Get-KcUsageLabel 0x2C $t)
}

Test-Case '結果の集計と終了コード' {
    $r = New-KcResultList
    [void](Add-KcResult -Results $r -Category 'A' -Item 'x' -Status PASS)
    Assert-Equal 0 (Get-KcExitCode $r)
    [void](Add-KcResult -Results $r -Category 'A' -Item 'y' -Status WARN)
    Assert-Equal 0 (Get-KcExitCode $r)
    [void](Add-KcResult -Results $r -Category 'A' -Item 'z' -Status FAIL -Details @('1', '2'))
    Assert-Equal 1 (Get-KcExitCode $r)
    $empty = New-KcResultList
    [void](Add-KcResult -Results $empty -Category 'A' -Item 'x' -Status SKIP)
    Assert-Equal 2 (Get-KcExitCode $empty)
    $lines = Format-KcResultLines $r[2]
    Assert-Equal 3 $lines.Count
}

Test-Case '結果の行 (レポートの書式) は変わらない' {
    $r = New-KcResultList
    [void](Add-KcResult -Results $r -Category 'LisM: キーマップ' -Item 'レイヤー 3' -Status FAIL -Expected 'A' -Actual 'B' `
            -Details @(1..22 | ForEach-Object { "位置 $_" }) -Hint "1 行目`n2 行目")
    [void](Add-KcResult -Results $r -Category 'LisM: 実動作' -Item 'キーのタップ' -Status PASS -Actual '43 / 43 キーが一致' -Expected '43 / 43 キーが一致')
    [void](Add-KcResult -Results $r -Category 'LisM: 実動作' -Item 'しきい値' -Status SKIP -Expected '10 以上')
    [void](Add-KcResult -Results $r -Category 'LisM: 実動作' -Item 'キーボード' -Status INFO)
    $expected = @('[FAIL] LisM: キーマップ: レイヤー 3 (期待: A / 実際: B)') + @(1..20 | ForEach-Object { "    - 位置 $_" }) +
        @('    - ほか 2 件 (-Report で全件を書き出せます)', '    → 1 行目', '    → 2 行目')
    Assert-Equal ($expected -join "`n") ((Format-KcResultLines $r[0]) -join "`n")
    Assert-Equal '[PASS] LisM: 実動作: キーのタップ (43 / 43 キーが一致)' ((Format-KcResultLines $r[1]) -join "`n")
    Assert-Equal '[SKIP] LisM: 実動作: しきい値 (10 以上)' ((Format-KcResultLines $r[2]) -join "`n")
    Assert-Equal '[INFO] LisM: 実動作: キーボード' ((Format-KcResultLines $r[3]) -join "`n")
}

Test-Case 'コンソールの結果表示 (判定のバッジ・Category の見出し)' {
    $r = New-KcResultList
    [void](Add-KcResult -Results $r -Category 'A' -Item 'x' -Status PASS -Actual '1')
    Assert-Equal 'PASS' (Get-KcVerdict $r).Status
    [void](Add-KcResult -Results $r -Category 'A' -Item 'y' -Status WARN -Hint "h1`nh2")
    Assert-Equal 'WARN' (Get-KcVerdict $r).Status
    [void](Add-KcResult -Results $r -Category 'B' -Item 'z' -Status FAIL -Expected 'e' -Actual 'a' -Details @(1..25 | ForEach-Object { "d$_" }))
    [void](Add-KcResult -Results $r -Category 'B' -Item 'w' -Status SKIP)
    [void](Add-KcResult -Results $r -Category 'C' -Item 'v' -Status INFO -Reference)
    $v = Get-KcVerdict $r
    Assert-Equal 'FAIL' $v.Status
    Assert-Equal '意図と違う設定があります。' $v.Text
    $empty = New-KcResultList
    [void](Add-KcResult -Results $empty -Category 'A' -Item 'x' -Status SKIP)
    Assert-Equal 'WARN' (Get-KcVerdict $empty).Status
    # コンソールが無い (子プロセスなど) ときも動く
    Write-KcSummary $r 'タイトル' 6>$null
    Write-KcSummary (New-KcResultList) 'からっぽ' 6>$null
    Assert-True ((Get-KcRuleText).Length -ge 30) '区切りの線'
}

Test-Case 'レポートを UTF-8 (BOM 付き) で書き出す' {
    $r = New-KcResultList
    [void](Add-KcResult -Results $r -Category 'キーマップ' -Item 'レイヤー 0' -Status FAIL -Details @(1..30 | ForEach-Object { "差分 $_" }))
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('kc-report-{0}.txt' -f [guid]::NewGuid())
    try {
        Export-KcReport $r $path @('ヘッダー')
        $bytes = [System.IO.File]::ReadAllBytes($path)
        Assert-Equal 0xEF $bytes[0]
        $text = [System.IO.File]::ReadAllText($path)
        Assert-True ($text.Contains('差分 30')) '詳細を省略しない'
    } finally {
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
    }
}

Test-Case '参考の項目だけなら「何も検査できなかった」(終了コード 2)' {
    $r = New-KcResultList
    [void](Add-KcResult -Results $r -Category 'A' -Item 'x' -Status WARN -Reference)
    Assert-Equal 2 (Get-KcExitCode $r)
}
