# 実機の回帰テスト (regression.ps1 / regression-test.ps1) のテスト。チェックリスト (tools/regression/checks.json) の
# 検証、選択、判定の関数 (PASS と 1 点だけ違う FAIL・成り立たない測定)、thread analyzer の行、PR 本文の検査、
# 偽のウィンドウと偽の Probe で流す手順 (抜き挿し・ブートローダ・ログ版・スリープ・ドラッグなど)。Windows 以外でも動く。

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'results.ps1')
. (Join-Path $script:KcLib 'input-eval.ps1')
. (Join-Path $script:KcLib 'behavior-eval.ps1')
. (Join-Path $script:KcLib 'zmk-log.ps1')
. (Join-Path $script:KcLib 'input-test.ps1')
. (Join-Path $script:KcLib 'behavior-test.ps1')
. (Join-Path $script:ToolsDir 'lib\input-monitor\devices.ps1')
. (Join-Path $script:ToolsDir 'lib\flash-plan.ps1')
. (Join-Path $script:KcLib 'regression.ps1')
. (Join-Path $script:KcLib 'regression-test.ps1')

$script:RgCommon = Get-KcExpected 'common' $script:ExpectedDir
$script:RgScan = New-KcScanTable $script:RgCommon
$script:RgChecksPath = Join-Path $script:ToolsDir 'regression\checks.json'
$script:RgRepos = Get-KcRegressionRepos ([System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $script:ToolsDir) '.gitmodules')))

function Get-RgUsage([string]$Legend) {
    return (Get-KcUsageByLegend $Legend $script:RgScan)
}

# usage → Raw Input のキーの記録 (押す / 離す)
function New-RgKey([long]$Time, [string]$Legend, [bool]$Break = $false, [long]$Device = 1) {
    $u = Get-RgUsage $Legend
    $k = $script:RgScan.ByUsage[$u]
    return (New-KcKeyEvent $Time ([int]$k.scan) ([int]$k.prefix) $Break $Device)
}

function New-RgTap([long]$Time, [string]$Legend, [long]$Device = 1) {
    return @((New-RgKey $Time $Legend $false $Device), (New-RgKey ($Time + 40) $Legend $true $Device))
}

function New-RgMoves([long]$From, [long]$To, [long]$Step = 100, [long]$Device = 2) {
    $out = @()
    for ($t = $From; $t -le $To; $t += $Step) {
        $out += (New-KcMouseEvent $t 3 1 0 0 0 $Device)
    }
    return $out
}

# 壊した checks.json の誤り (1 件の check を $Mutate で変える)
function Get-RgDocErrors([scriptblock]$Mutate) {
    $c = [pscustomobject]@{ id = 'sample-check'; title = '題名'; symptom = '症状'; prs = @('zmk-config-keyboards#1'); boards = @('all'); handler = 'manual'
        params = [pscustomobject]@{ question = '問い' } }
    & $Mutate $c
    $doc = [pscustomobject]@{ schema = 1; checks = @($c) }
    return , (Test-KcRegressionDocument $doc $script:RgRepos)
}

# ---------------------------------------------------------------------------
# チェックリスト
# ---------------------------------------------------------------------------

Test-Case 'checks.json: 誤りが無い (形・repo・handler・params)' {
    $doc = Read-KcRegressionDocument $script:RgChecksPath
    $errors = Test-KcRegressionDocument $doc $script:RgRepos
    Assert-Equal 0 $errors.Count ($errors -join ' / ')
}

Test-Case 'checks.json: どの handler も使われ、関数がある。どの項目も 1 台以上に当てはまる' {
    $checks = Get-KcRegressionChecks (Read-KcRegressionDocument $script:RgChecksPath)
    $unused = Get-KcRegressionUnusedHandlers $checks
    Assert-Equal 0 $unused.Count ('使われていない handler: ' + ($unused -join ', '))
    foreach ($h in @($script:KcRegressionHandlers.Keys)) {
        Assert-True ($null -ne (Get-Command -Name $script:KcRegressionHandlers[$h].Fn -CommandType Function -ErrorAction SilentlyContinue)) ('関数が無い: ' + $h)
    }
    foreach ($c in $checks) {
        $n = @($script:KcRegressionBoards | Where-Object { Test-KcRegressionApplies $c $_ }).Count
        Assert-True ($n -gt 0) ('どの機種にも当てはまらない: ' + $c.Id)
    }
}

Test-Case 'checks.json: 過去の修正の主な PR が、どれかの項目に入っている' {
    $checks = Get-KcRegressionChecks (Read-KcRegressionDocument $script:RgChecksPath)
    $all = @($checks | ForEach-Object { @($_.Prs) })
    foreach ($pr in @('zmk-config-LisM#26', 'zmk-config-keyboards#52', 'zmk-config-keyboards#39', 'zmk-config-keyboards#30', 'zmk-config-keyboards#28',
            'zmk-config-keyboards#18', 'zmk-config-keyboards#27', 'zmk-config-keyboards#20', 'vial-qmk-kq-mini#14', 'zmk-config-keyboards#23')) {
        Assert-True ($all -contains $pr) ('PR が無い: ' + $pr)
    }
}

Test-Case '壊した checks.json: それぞれ 1 件の誤りになる' {
    Assert-Equal 0 (Get-RgDocErrors { param($c) }).Count '正しいもの'
    $cases = @(
        @({ param($c) $c | Add-Member -NotePropertyName 'firmwre' -NotePropertyValue 'any' }, '*知らない項目 firmwre*'),
        @({ param($c) $c.id = 'Bad_Id' }, '*kebab-case*'),
        @({ param($c) $c.symptom = ' ' }, '*symptom*'),
        @({ param($c) $c.prs = @() }, '*prs*空*'),
        @({ param($c) $c.prs = @('LisM-26') }, '*<repo>#<番号>*'),
        @({ param($c) $c.prs = @('unknown-repo#3') }, '*unknown-repo*'),
        @({ param($c) $c.boards = @('Corne') }, '*Corne*'),
        @({ param($c) $c | Add-Member -NotePropertyName 'firmware' -NotePropertyValue 'beta' }, '*firmware*'),
        @({ param($c) $c | Add-Member -NotePropertyName 'minutes' -NotePropertyValue (-1) }, '*minutes*'),
        @({ param($c) $c | Add-Member -NotePropertyName 'default' -NotePropertyValue 'yes' }, '*default*'),
        @({ param($c) $c.handler = 'magic' }, '*handler の magic*'),
        @({ param($c) $c.params = [pscustomobject]@{} }, '*params.question*'),
        @({ param($c) $c.handler = 'input-test'; $c.params = [pscustomobject]@{ test = 'jump' } }, '*params.test*'),
        @({ param($c) $c.handler = 'replug'; $c.params = [pscustomobject]@{ repeat = 1; targets = @([pscustomobject]@{ label = 'x'; plug = 'p'; unplug = 'u' }) } }, '*targets の 1 件目に keys*'),
        @({ param($c) $c.handler = 'replug'; $c.params = [pscustomobject]@{ repeat = 1; targets = @([pscustomobject]@{ label = 'x'; plug = 'p'; unplug = 'u'; keys = @('Q'); start = 'on' }) } }, '*start*'),
        @({ param($c) $c.handler = 'bootmagic'; $c.params = [pscustomobject]@{ sides = @([pscustomobject]@{ label = '左' }) } }, '*sides の 1 件目に key*')
    )
    foreach ($case in $cases) {
        $errors = Get-RgDocErrors $case[0]
        Assert-Equal 1 $errors.Count ($case[1] + ': ' + ($errors -join ' / '))
        Assert-True ($errors[0] -like $case[1]) $errors[0]
    }
    $doc = [pscustomobject]@{ schema = 1; checks = @(
            [pscustomobject]@{ id = 'a'; title = 't'; symptom = 's'; prs = @('keyball#1'); boards = @('all'); handler = 'drag-hold' },
            [pscustomobject]@{ id = 'a'; title = 't'; symptom = 's'; prs = @('keyball#1'); boards = @('all'); handler = 'drag-hold' }) }
    $errors = Test-KcRegressionDocument $doc $script:RgRepos
    Assert-Equal 1 $errors.Count ($errors -join ' / ')
    Assert-True ($errors[0] -like '*重なって*') $errors[0]
    $errors = Test-KcRegressionDocument ([pscustomobject]@{ schema = 2; checks = @() }) $script:RgRepos
    Assert-Equal 2 $errors.Count ($errors -join ' / ')
}

Test-Case '絞り込み: 機種とファームで、行える項目と既定が決まる' {
    $checks = Get-KcRegressionChecks (Read-KcRegressionDocument $script:RgChecksPath)
    $lismNormal = Select-KcRegressionChecks $checks 'LisM' 'normal'
    $byId = @{}
    foreach ($e in $lismNormal) { $byId[$e.Check.Id] = $e }
    Assert-True $byId.ContainsKey('lism-usb-plug') 'LisM だけの項目'
    Assert-True (-not $byId.ContainsKey('kq-drag-hold')) 'KQ-mini だけの項目は出さない'
    Assert-True (-not $byId['logging-soak'].Ready) 'ログ版の項目は、通常版では行えない'
    Assert-True ($byId['logging-soak'].Need -like '*ログ版*') $byId['logging-soak'].Need
    Assert-True (-not $byId['keymap-readout'].Default) '読み出しは Studio 版のときだけ既定'
    Assert-True (-not $byId['bootmagic'].Default) 'ブートローダは既定にしない'
    Assert-True (-not $byId['idle-wake'].Default) 'スリープは既定にしない'
    Assert-True $byId['ball-alive'].Default 'ボールの項目は既定'
    Assert-Equal (@(1..$lismNormal.Count) -join ',') (@($lismNormal | ForEach-Object { $_.Index }) -join ',') '番号は 1 から'
    $lismLog = Select-KcRegressionChecks $checks 'LisM' 'logging'
    Assert-True (@($lismLog | Where-Object { $_.Check.Id -eq 'logging-soak' })[0].Default) 'ログ版なら既定'
    $kq = Select-KcRegressionChecks $checks 'KqMini' ''
    $kqIds = @($kq | ForEach-Object { $_.Check.Id })
    Assert-True ($kqIds -contains 'kq-drag-hold' -and $kqIds -contains 'vim-visual-exit') ($kqIds -join ',')
    Assert-True ($kqIds -notcontains 'logging-soak' -and $kqIds -notcontains 'lism-usb-plug') ($kqIds -join ',')
    Assert-True (@($kq | Where-Object { $_.Check.Id -eq 'keymap-readout' })[0].Ready) 'QMK の機種は、ファームの答えに関係なく読み出せる'
    $kbEntries = Select-KcRegressionChecks $checks 'Keyball39' ''
    $kb = @($kbEntries | ForEach-Object { $_.Check.Id })
    Assert-True ($kb -notcontains 'vim-visual-exit' -and $kb -notcontains 'kq-drag-hold' -and $kb -contains 'ball-alive') ($kb -join ',')
}

Test-Case '選択の文字列: Enter・all・番号と範囲・誤り' {
    Assert-Equal '1,3' ((ConvertFrom-KcRegressionSelection '' 5 @(1, 3)) -join ',')
    Assert-Equal '1,2,3,4,5' ((ConvertFrom-KcRegressionSelection 'all' 5 @(1)) -join ',')
    Assert-Equal '2,4,5' ((ConvertFrom-KcRegressionSelection '2,4-5' 5 @(1)) -join ',')
    Assert-Equal '2,3' ((ConvertFrom-KcRegressionSelection ' 2、3 ' 5 @(1)) -join ',')
    Assert-Equal '3' ((ConvertFrom-KcRegressionSelection '3,3' 5 @(1)) -join ',')
    foreach ($bad in @('0', '6', '3-2', 'x', '1-', ',')) {
        Assert-True ($null -eq (ConvertFrom-KcRegressionSelection $bad 5 @(1))) ('誤りにする: ' + $bad)
    }
}

Test-Case '-Check の id: 知らない id を分け、all ですべて' {
    $checks = Get-KcRegressionChecks (Read-KcRegressionDocument $script:RgChecksPath)
    $entries = Select-KcRegressionChecks $checks 'LisM' 'normal'
    $r = Resolve-KcRegressionIds $entries @('ball-alive,lism-usb-plug', 'nope')
    Assert-Equal 'ball-alive,lism-usb-plug' (@($r.Selected | ForEach-Object { $_.Check.Id }) -join ',')
    Assert-Equal 'nope' ($r.Unknown -join ',')
    $r = Resolve-KcRegressionIds $entries @('kq-drag-hold')
    Assert-Equal 'kq-drag-hold' ($r.Unknown -join ',') 'ほかの機種の項目は、この機種には無い'
    Assert-Equal $entries.Count (Resolve-KcRegressionIds $entries @('all')).Selected.Count
}

Test-Case '一覧と前回の結果: 既定の印・準備・PR・前回' {
    $checks = Get-KcRegressionChecks (Read-KcRegressionDocument $script:RgChecksPath)
    $entries = Select-KcRegressionChecks $checks 'LisM' 'normal'
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('kc-reg-{0}.json' -f [guid]::NewGuid())
    try {
        Assert-Equal 0 (Read-KcRegressionHistory $path).Count '無ければ空'
        Add-KcRegressionHistory $path @(@{ time = '2026-10-20 10:00:00'; board = 'LisM'; check = 'ball-alive'; status = 'PASS'; hash = 'x' })
        Add-KcRegressionHistory $path @(@{ time = '2026-10-21 10:00:00'; board = 'LisM'; check = 'ball-alive'; status = 'FAIL'; hash = 'y' },
            @{ time = '2026-10-21T11:00:00'; board = 'KUKEY42'; check = 'ball-alive'; status = 'PASS'; hash = 'y' })
        $h = Read-KcRegressionHistory $path
        Assert-Equal 3 $h.Count
        Assert-Equal 'FAIL' (Get-KcRegressionLast $h 'LisM' 'ball-alive').status '同じ機種の新しいもの'
        $lines = Format-KcRegressionList $entries $h 'LisM'
        $text = $lines -join "`n"
        Assert-True ($text -like '*`* *ボールを転がし続けても*前回: FAIL (2026-10-21)*') $text
        Assert-True ($text -like '*右手側が「ログ版」のとき*') $text
        Assert-True ($text -like '*PR: zmk-config-LisM#26, zmk-config-keyboards#38*') $text
        Assert-Equal '2026-10-21 11:00' (Format-KcRegressionTime ([datetime]'2026-10-21T11:00:00')) 'DateTime になっていても日付で出す'
        [System.IO.File]::WriteAllText($path, '{ broken')
        Assert-Equal 0 (Read-KcRegressionHistory $path).Count '壊れていれば空'
    } finally {
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
    }
    $c = $checks[0]
    Assert-Equal (Get-KcRegressionCheckHash $c) (Get-KcRegressionCheckHash $c) 'ハッシュは同じ内容で同じ'
    Assert-True ((Get-KcRegressionCheckHash $c) -ne (Get-KcRegressionCheckHash $checks[1])) '内容が違えば違う'
}

Test-Case '項目の判定: 中の行のいちばん悪いもの。INFO と参考は数えない' {
    $r = New-KcResultList
    [void](Add-KcResult -Results $r -Category 'c' -Item 'a' -Status PASS)
    [void](Add-KcResult -Results $r -Category 'c' -Item 'i' -Status INFO)
    Assert-Equal 'PASS' (Get-KcRegressionStatus $r)
    [void](Add-KcResult -Results $r -Category 'c' -Item 's' -Status SKIP)
    Assert-Equal 'SKIP' (Get-KcRegressionStatus $r) '一部をスキップしたら PASS にしない'
    [void](Add-KcResult -Results $r -Category 'c' -Item 'w' -Status WARN)
    Assert-Equal 'WARN' (Get-KcRegressionStatus $r)
    [void](Add-KcResult -Results $r -Category 'c' -Item 'f' -Status FAIL)
    Assert-Equal 'FAIL' (Get-KcRegressionStatus $r)
    $only = New-KcResultList
    [void](Add-KcResult -Results $only -Category 'c' -Item 'ref' -Status WARN -Reference)
    Assert-Equal 'SKIP' (Get-KcRegressionStatus $only) '参考の行だけなら SKIP'
}

Test-Case 'デバイスの見分け: ZMK・KQ-mini は VID / PID、Keyball39 は PID の上位バイト' {
    $lism = Get-KcExpected 'lism' $script:ExpectedDir
    $kb = Get-KcExpected 'keyball39' $script:ExpectedDir
    Assert-True (Test-KcRgDeviceMatch $lism '1d50' '615e') '大文字・小文字は問わない'
    Assert-True (-not (Test-KcRgDeviceMatch $lism '1D50' '615F'))
    Assert-True (Test-KcRgDeviceMatch $kb '5957' '0201') 'Keyball39 は 02xx'
    Assert-True (-not (Test-KcRgDeviceMatch $kb '5957' '0101'))
    $usb = ConvertFrom-ImDevicePath '\\?\HID#VID_1D50&PID_615E&MI_00&Col01#8&2f3a1b2c&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}'
    $ble = ConvertFrom-ImDevicePath '\\?\HID#{00001812-0000-1000-8000-00805f9b34fb}_DEV_VID&021d50_PID&615e_REV&0001_c3f2a1b0d9e8&Col01#9&1a2b3c4d&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}'
    Assert-True ((Test-KcRgDeviceMatch $lism $usb.Vid $usb.Pid) -and $usb.Transport -eq 'USB') 'USB'
    Assert-True ((Test-KcRgDeviceMatch $lism $ble.Vid $ble.Pid) -and $ble.Transport -eq 'BLE') 'BLE'
}

# ---------------------------------------------------------------------------
# 判定
# ---------------------------------------------------------------------------

Test-Case 'ボールが止まらない: PASS / 途中で止まりキーは届く (STOPPED) / 操作が足りない' {
    $ok = @(New-RgMoves 1200 20800) + @(New-RgTap 11000 'A') + @(New-RgTap 19500 'A')
    $r = Test-KcBallAlive $ok 1000 21000 3000 $script:RgScan
    Assert-Equal 'PASS' $r.Status $r.Actual
    $stop = @(New-RgMoves 1200 6000) + @(New-RgTap 11000 'A') + @(New-RgTap 19500 'A')
    $r = Test-KcBallAlive $stop 1000 21000 3000 $script:RgScan
    Assert-Equal 'STOPPED' $r.Status $r.Actual
    Assert-True ($r.Actual -like '*途中で止まった*') $r.Actual
    $dead = @(New-RgTap 11000 'A') + @(New-RgTap 19500 'A')
    $r = Test-KcBallAlive $dead 1000 21000 3000 $script:RgScan
    Assert-Equal 'STOPPED' $r.Status '初めから動かないのも同じ (#52 の症状)'
    $r = Test-KcBallAlive @(New-RgMoves 1200 20800) 1000 21000 3000 $script:RgScan
    Assert-Equal 'NONE' $r.Status 'キーが届かない'
    $r = Test-KcBallAlive @(New-RgMoves 1200 6000) 1000 21000 3000 $script:RgScan
    Assert-Equal 'NONE' $r.Status '人がやめただけ (キーも無い)'
    $zero = @(New-RgMoves 0 0) + @(New-RgTap 0 'A')
    $r = Test-KcBallAlive $zero 0 20000 3000 $script:RgScan
    Assert-Equal 'NONE' $r.Status '時刻が全部 0'
    Assert-Equal 'NONE' (Test-KcBallAlive @() 0 20000 3000 $script:RgScan).Status '何も無い'
}

Test-Case 'キーを速く打っても AML にならない: PASS / クリック / 欠けた文字 / 足りない' {
    $u = [int[]]@((Get-RgUsage 'D'), (Get-RgUsage 'F'), (Get-RgUsage 'J'), (Get-RgUsage 'K'))
    $ev = @()
    $t = 1000
    foreach ($round in 1..3) {
        foreach ($l in @('D', 'F', 'J', 'K')) { $ev += New-RgTap $t $l; $t += 90 }
    }
    $ev += New-KcMouseEvent 1500 1 0
    Assert-Equal 'PASS' (Test-KcTypingNoAml $ev $u 3 $script:RgScan).Status 'わずかな動きはあってよい'
    $click = $ev + @((New-KcMouseEvent 2000 0 0 0x0001), (New-KcMouseEvent 2050 0 0 0x0002))
    Assert-Equal 'FAIL' (Test-KcTypingNoAml $click $u 3 $script:RgScan).Status 'クリックが出た'
    $wheel = $ev + @(New-KcMouseEvent 2000 0 0 0 -120)
    Assert-Equal 'FAIL' (Test-KcTypingNoAml $wheel $u 3 $script:RgScan).Status 'ホイールが出た'
    $lost = @($ev | Where-Object { -not ($_.Kind -eq 'key' -and $_.Scan -eq $script:RgScan.ByUsage[(Get-RgUsage 'D')].scan -and $_.Time -lt 1100) })
    $lost += New-RgTap 5000 'F'
    $r = Test-KcTypingNoAml $lost $u 3 $script:RgScan
    Assert-Equal 'FAIL' $r.Status 'D が 2 回しか届かない'
    Assert-True ($r.Message -like '*「D」が 2 回*') $r.Message
    Assert-Equal 'NONE' (Test-KcTypingNoAml @(New-RgTap 1000 'D') $u 3 $script:RgScan).Status '足りない'
}

Test-Case 'AML が残る (aml-extend): クリック / 文字 / 動かした / 遅い' {
    $btn = 1
    $d = Get-RgUsage 'D'
    $f = Get-RgUsage 'F'
    $click = @((New-KcMouseEvent 3000 0 0 0x0001), (New-KcMouseEvent 3050 0 0 0x0002))
    Assert-Equal 'PASS' (Test-KcAmlStillOn $click $btn $d $f 10 $script:RgScan 2000 10000).Status
    $letters = @(New-RgTap 3000 'D') + @(New-RgTap 3100 'F')
    Assert-Equal 'FAIL' (Test-KcAmlStillOn $letters $btn $d $f 10 $script:RgScan 2000 10000).Status 'AML が切れて文字になった'
    $moved = @(New-RgMoves 2500 2900 50) + $click
    Assert-Equal 'NONE' (Test-KcAmlStillOn $moved $btn $d $f 10 $script:RgScan 2000 10000).Status 'ボールを動かしたら確かめられない'
    $late = @((New-KcMouseEvent 11500 0 0 0x0001), (New-KcMouseEvent 11550 0 0 0x0002))
    Assert-Equal 'NONE' (Test-KcAmlStillOn $late $btn $d $f 10 $script:RgScan 2000 10000).Status 'タイムアウトの近くでは確かめられない'
    Assert-Equal 'NONE' (Test-KcAmlStillOn @() $btn $d $f 10 $script:RgScan 2000 10000).Status '入力なし'
    $clickThenLetter = $click + @(New-RgTap 3500 'F')
    Assert-Equal 'PASS' (Test-KcAmlStillOn $clickThenLetter $btn $d $f 10 $script:RgScan 2000 10000).Status 'クリックが先なら、AML は残っていた'
    $letterThenClick = @(New-RgTap 2900 'F') + $click
    Assert-Equal 'FAIL' (Test-KcAmlStillOn $letterThenClick $btn $d $f 10 $script:RgScan 2000 10000).Status '文字が先'
    $upOnly = @((New-KcMouseEvent 2100 0 0 0x0002)) + $click
    Assert-Equal 'PASS' (Test-KcAmlStillOn $upOnly $btn $d $f 10 $script:RgScan 2000 10000).Status '前の操作のボタンの解放では時刻を数えない'
}

Test-Case 'ドラッグ中のキー (KQ-mini#14): PASS / 途中で離れた / Ctrl なし / 順番 / 動きなし' {
    $ctrl = @(224, 228)
    $ctrlScan = $script:RgScan.ByUsage[224]
    function New-RgCtrl([long]$T, [bool]$Up) { New-KcKeyEvent $T ([int]$ctrlScan.scan) ([int]$ctrlScan.prefix) $Up 1 }
    $ok = @((New-KcMouseEvent 1000 0 0 0x0001)) + @(New-RgMoves 1100 1400) + @((New-RgCtrl 1500 $false), (New-RgCtrl 1900 $true)) +
    @(New-RgMoves 2000 2200) + @((New-KcMouseEvent 2500 0 0 0x0002))
    Assert-Equal 'PASS' (Test-KcDragHold $ok 1 $ctrl $script:RgScan).Status
    $dropped = @((New-KcMouseEvent 1000 0 0 0x0001)) + @(New-RgMoves 1100 1400) + @((New-RgCtrl 1500 $false), (New-KcMouseEvent 1510 0 0 0x0002), (New-RgCtrl 1900 $true))
    Assert-Equal 'FAIL' (Test-KcDragHold $dropped 1 $ctrl $script:RgScan).Status 'Ctrl を押したときにボタンが離れた'
    $twice = $ok + @((New-KcMouseEvent 2600 0 0 0x0001), (New-KcMouseEvent 2700 0 0 0x0002))
    Assert-Equal 'FAIL' (Test-KcDragHold $twice 1 $ctrl $script:RgScan).Status 'ボタンを押し直した'
    $noCtrl = @((New-KcMouseEvent 1000 0 0 0x0001)) + @(New-RgMoves 1100 1400) + @((New-KcMouseEvent 2500 0 0 0x0002))
    Assert-Equal 'NONE' (Test-KcDragHold $noCtrl 1 $ctrl $script:RgScan).Status 'Ctrl なしのドラッグは合格にしない'
    $early = @((New-RgCtrl 500 $false), (New-RgCtrl 700 $true)) + $noCtrl
    Assert-Equal 'NONE' (Test-KcDragHold $early 1 $ctrl $script:RgScan).Status 'Ctrl がボタンより先'
    $still = @((New-KcMouseEvent 1000 0 0 0x0001), (New-RgCtrl 1500 $false), (New-RgCtrl 1900 $true), (New-KcMouseEvent 2500 0 0 0x0002))
    Assert-Equal 'NONE' (Test-KcDragHold $still 1 $ctrl $script:RgScan).Status 'ドラッグ中の動きなし'
    Assert-Equal 'NONE' (Test-KcDragHold @() 1 $ctrl $script:RgScan).Status 'ボタンなし'
    $second = @((New-KcMouseEvent 1000 0 0 0x0001)) + @(New-RgMoves 1100 1400) + @((New-RgCtrl 1500 $false), (New-RgCtrl 1700 $true), (New-RgCtrl 1800 $false), (New-KcMouseEvent 1810 0 0 0x0002), (New-RgCtrl 2000 $true))
    Assert-Equal 'FAIL' (Test-KcDragHold $second 1 $ctrl $script:RgScan).Status '2 回目の Ctrl でボタンが離れた'
    $twiceOk = @((New-KcMouseEvent 1000 0 0 0x0001)) + @(New-RgMoves 1100 1400) + @((New-RgCtrl 1500 $false), (New-RgCtrl 1700 $true), (New-RgCtrl 1800 $false), (New-RgCtrl 2000 $true), (New-KcMouseEvent 2500 0 0 0x0002))
    Assert-Equal 'PASS' (Test-KcDragHold $twiceOk 1 $ctrl $script:RgScan).Status 'Ctrl を 2 回押しても切れない'
    $heldUp = @((New-KcMouseEvent 1000 0 0 0x0001)) + @(New-RgMoves 1100 1400) + @((New-RgCtrl 1500 $false), (New-KcMouseEvent 1900 0 0 0x0002))
    Assert-Equal 'FAIL' (Test-KcDragHold $heldUp 1 $ctrl $script:RgScan).Status 'Ctrl を押したままボタンが離れた'
}

# Zephyr v3.5 の thread analyzer の行 (LOG_INF。zmk-log.Tests.ps1 と同じ時刻の書式)
function New-RgTa([double]$Ms, [string]$Body) {
    $ts = [TimeSpan]::FromMilliseconds([math]::Floor($Ms))
    return ('[{0:00}:{1:00}:{2:00}.{3:000},000] <inf> thread_analyzer: {4}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds, $Body)
}

function New-RgTaThread([double]$Ms, [string]$Name, [int]$Usage, [int]$Size) {
    $pct = [int][math]::Floor(100 * $Usage / $Size)
    return (New-RgTa $Ms (' {0,-20}: STACK: unused {1} usage {2} / {3} ({4} %); CPU: 0 %' -f $Name, ($Size - $Usage), $Usage, $Size, $pct))
}

Test-Case 'thread analyzer の行: 見出し・スレッド・ISR・空白や長い名前・取得失敗・色・printk' {
    $h = ConvertFrom-KcThreadAnalyzerLine (New-RgTa 30000 'Thread analyze:')
    Assert-Equal 'header' $h.Kind
    Assert-Near 30000 $h.Time 0.01
    $t = ConvertFrom-KcThreadAnalyzerLine (New-RgTaThread 30001 'input' 576 2048)
    Assert-Equal 'thread|input|576|2048|28|0' ('{0}|{1}|{2}|{3}|{4}|{5}' -f $t.Kind, $t.Name, $t.Usage, $t.Size, $t.Pct, $t.Cpu)
    $isr = ConvertFrom-KcThreadAnalyzerLine (New-RgTa 30002 ' ISR0             : STACK: unused 1688 usage 360 / 2048 (17 %)')
    Assert-Equal 'thread|ISR0|360|-1' ('{0}|{1}|{2}|{3}' -f $isr.Kind, $isr.Name, $isr.Usage, $isr.Cpu)
    Assert-Equal 'BT RX' (ConvertFrom-KcThreadAnalyzerLine (New-RgTaThread 30003 'BT RX' 920 3072)).Name '空白を含む名前'
    $long = 'zmk_split_bt_central_run_q'
    Assert-Equal $long (ConvertFrom-KcThreadAnalyzerLine (New-RgTaThread 30004 $long 600 2048)).Name '20 文字を超える名前'
    $e = ConvertFrom-KcThreadAnalyzerLine (New-RgTa 30005 ' sysworkq            : unable to get stack space (-22)')
    Assert-Equal 'error|sysworkq' ('{0}|{1}' -f $e.Kind, $e.Name)
    $color = ([char]27) + '[0m' + (New-RgTaThread 30006 'sysworkq' 1456 3072) + ([char]27) + '[0m'
    Assert-Equal 'sysworkq' (ConvertFrom-KcThreadAnalyzerLine $color).Name '色の ESC シーケンス'
    $pk = ConvertFrom-KcThreadAnalyzerLine ' main                : STACK: unused 1200 usage 848 / 2048 (41 %); CPU: 0 %'
    Assert-Equal 'thread|main|-1' ('{0}|{1}|{2}' -f $pk.Kind, $pk.Name, $pk.Time) 'printk (前に何も付かない)'
    Assert-True ($null -eq (ConvertFrom-KcThreadAnalyzerLine '[00:00:01.000,000] <dbg> zmk: hid_listener_keycode_pressed: usage_page 0x07 keycode 0x04 implicit_mods 0x00 explicit_mods 0x00')) 'ほかの行は $null'
    Assert-True ($null -eq (ConvertFrom-KcThreadAnalyzerLine '')) '空行'
}

Test-Case 'fatal の行: Zephyr の fatal error を見つけ、ふつうの行は見つけない' {
    foreach ($l in @('[00:00:05.000,000] <err> os: ***** MPU FAULT *****', '[00:00:05.000,000] <err> os: >>> ZEPHYR FATAL ERROR 2: Stack overflow on CPU 0',
            '[00:00:05.000,000] <err> os: Halting system')) {
        Assert-True (Test-KcZmkLogFatal $l) $l
    }
    Assert-True (-not (Test-KcZmkLogFatal (New-RgTaThread 1 'input' 576 2048))) 'thread analyzer の行'
    Assert-True (-not (Test-KcZmkLogFatal '[00:00:05.000,000] <err> zmk: Failed to send report (-128)')) 'ほかの err'
}

Test-Case 'ログ版の判定: 余裕あり / 使用率が高い / 再起動 / fatal / ダンプが足りない / 通常版と比べる' {
    $dump = { param($ms, $inp, $sys) @((New-RgTa $ms 'Thread analyze:'), (New-RgTaThread ($ms + 1) 'input' $inp 2048), (New-RgTaThread ($ms + 2) 'sysworkq' $sys 3072)) }
    $ok = @(& $dump 30000 576 1456) + @(& $dump 60000 600 1500)
    $soak = Measure-KcLoggingSoak $ok
    Assert-Equal '2|2|0|0' ('{0}|{1}|{2}|{3}' -f $soak.Dumps, $soak.Threads.Count, $soak.Rewinds, $soak.Fatal.Count)
    Assert-Equal 600 @($soak.Threads | Where-Object { $_.Name -eq 'input' })[0].Usage '最大を残す'
    $rows = Get-KcLoggingSoakRows $soak 2 75 90 1024 75
    $st = @($rows | ForEach-Object { '{0}={1}' -f $_.Item, $_.Status }) -join ' / '
    Assert-True ($st -like '*再起動・異常が無い=PASS*スタックの余裕 (75 % 未満)=PASS*入力スレッド (通常版の 1024 バイトと比べた目安)=INFO*') $st
    $warn = Get-KcLoggingSoakRows (Measure-KcLoggingSoak (@(& $dump 30000 576 2400) + @(& $dump 60000 576 2400))) 2 75 90 1024 75
    Assert-Equal 'WARN' @($warn | Where-Object { $_.Item -like 'スタックの余裕*' })[0].Status '78 %'
    $fail = Get-KcLoggingSoakRows (Measure-KcLoggingSoak (@(& $dump 30000 1900 1456) + @(& $dump 60000 576 1456))) 2 75 90 1024 75
    Assert-Equal 'FAIL' @($fail | Where-Object { $_.Item -like 'スタックの余裕*' })[0].Status '92 %'
    Assert-Equal 'WARN' @($fail | Where-Object { $_.Item -like '入力スレッド*' })[0].Status '1900 / 1024 は通常版では足りない (目安)'
    $reboot = @(& $dump 30000 576 1456) + @(& $dump 2000 576 1456)
    Assert-Equal 'FAIL' (Get-KcLoggingSoakRows (Measure-KcLoggingSoak $reboot) 2 75 90 1024 75)[0].Status '時刻が戻った (再起動)'
    $fatal = $ok + @('[00:01:05.000,000] <err> os: >>> ZEPHYR FATAL ERROR 2: Stack overflow on CPU 0')
    Assert-Equal 'FAIL' (Get-KcLoggingSoakRows (Measure-KcLoggingSoak $fatal) 2 75 90 1024 75)[0].Status 'fatal'
    $one = Get-KcLoggingSoakRows (Measure-KcLoggingSoak @(& $dump 30000 576 1456)) 2 75 90 1024 75
    Assert-Equal 'WARN' @($one | Where-Object { $_.Item -eq 'thread analyzer' })[0].Status 'ダンプが 1 回'
    $none = Get-KcLoggingSoakRows (Measure-KcLoggingSoak @('[00:00:01.000,000] <dbg> zmk: x: y')) 2 75 90 1024 75
    Assert-Equal 'PASS,WARN' (@($none | ForEach-Object { $_.Status }) -join ',') 'thread analyzer が無い'
}

Test-Case 'UF2 のドライブ: マイコンごとの見分け方と Board-ID' {
    $xiao = "UF2 Bootloader 0.6.0`r`nModel: Seeed XIAO nRF52840`r`nBoard-ID: nRF52840-SeeedXiao-v1`r`n"
    Assert-True (Test-KcUf2DriveBoard 'XIAO' 'XIAO-SENSE' $xiao)
    Assert-True (-not (Test-KcUf2DriveBoard 'XIAO' 'BLEMICROPRO' $xiao)) 'BMP のラベルなら XIAO ではない'
    Assert-True (Test-KcUf2DriveBoard 'BMP' 'BLEMICROPRO' $xiao)
    Assert-True (-not (Test-KcUf2DriveBoard 'BMP' 'XIAO-SENSE' $xiao))
    Assert-True (-not (Test-KcUf2DriveBoard 'XIAO' 'RPI-RP2' "Model: Raspberry Pi RP2`r`nBoard-ID: RPI-RP2`r`n")) 'KQ-mini のドライブ'
    Assert-Equal 'nRF52840-SeeedXiao-v1' (Get-KcUf2BoardId $xiao)
    Assert-Equal '' (Get-KcUf2BoardId '')
}

Test-Case 'bootmagic のキー: ドライブより前に離された / 後に離された / 離されない / 届かない' {
    $q = Get-RgUsage 'Q'
    $fw = @((New-RgKey 1000 'Q' $false 11), (New-RgKey 1300 'Q' $true 11))
    Assert-Equal 'PASS' (Test-KcBootmagicRelease $fw $q 2500 $script:RgScan).Status 'ファームが離した'
    $finger = @((New-RgKey 1000 'Q' $false 11), (New-RgKey 2600 'Q' $true 11))
    Assert-Equal 'WARN' (Test-KcBootmagicRelease $finger $q 2500 $script:RgScan).Status 'ドライブが現れてから指を離した (見分けられない)'
    $stuck = @((New-RgKey 1000 'Q' $false 11))
    Assert-Equal 'FAIL' (Test-KcBootmagicRelease $stuck $q 2500 $script:RgScan).Status '離されない'
    $again = @((New-RgKey 500 'Q' $false 11), (New-RgKey 600 'Q' $true 11), (New-RgKey 1000 'Q' $false 11))
    Assert-Equal 'FAIL' (Test-KcBootmagicRelease $again $q 2500 $script:RgScan).Status '前に一度離していても、最後が押したまま'
    Assert-Equal 'NONE' (Test-KcBootmagicRelease @() $q 2500 $script:RgScan).Status '届かない'
}

Test-Case 'PR 本文の「実機の回帰テスト」: 無い・空・テンプレートのまま・知らない id・正しい書き方' {
    $ids = @('ball-alive', 'lism-usb-plug')
    Assert-True ((Test-KcRegressionPrBody "## 概要`n直した" $ids)[0] -like '*節がありません*') '節が無い'
    $tpl = [System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $script:ToolsDir) '.github\pull_request_template.md'))
    Assert-True ((Test-KcRegressionPrBody $tpl $ids).Count -gt 0) 'テンプレートのまま'
    Assert-True ((Test-KcRegressionPrBody "## 実機の回帰テスト`n`n## 確認`n- 不要: x" $ids).Count -gt 0) '次の節の行は数えない'
    Assert-True ((Test-KcRegressionPrBody "## 実機の回帰テスト`n- 不要: <理由>" $ids)[0] -like '*空のまま*') '置き換えていない'
    Assert-True ((Test-KcRegressionPrBody "## 実機の回帰テスト`n- 追加・更新: ball-alive" $ids)[0] -like '*checks.json の id を*') 'id を ` で囲んでいない'
    Assert-True ((Test-KcRegressionPrBody "## 実機の回帰テスト`n- 追加・更新: ``nope``" $ids)[0] -like '*nope*') '知らない id'
    Assert-Equal 0 (Test-KcRegressionPrBody "## 実機の回帰テスト`r`n- 追加・更新: ``ball-alive``、``lism-usb-plug```r`n" $ids).Count '追加・更新'
    Assert-Equal 0 (Test-KcRegressionPrBody "### 実機の回帰テスト`n* 既存のテスト: tools/tests/zmk-log.Tests.ps1`n" $ids).Count '既存のテスト'
    Assert-Equal 0 (Test-KcRegressionPrBody "## 実機の回帰テスト`n<!-- 書き方 -->`n- 不要： 文書だけの変更`n## 確認`n" $ids).Count '不要 (全角のコロン)'
}

# ---------------------------------------------------------------------------
# 手順 (偽のウィンドウと偽の Probe)
# ---------------------------------------------------------------------------

# テスト用のウィンドウ (KcInputTestForm) の偽物。$Script (param($form)) を、メッセージを処理するたびに呼ぶ。
# Script は、いまの指示 ($form.Instruction) を見て、入力 ($form.Push) やボタン ($form.Actions) を入れる。
# Script が使う値は $Data ($form.Data) で渡す (GetNewClosure で閉じると、このファイルの関数が見えなくなるため)
function New-RgForm([scriptblock]$Script, [int]$Step = 15, [hashtable]$Data = @{}) {
    $f = [pscustomobject]@{
        Now = [long]1000; Step = $Step; Script = $Script; Data = $Data; Events = (New-Object 'System.Collections.Generic.List[object]')
        Actions = (New-Object 'System.Collections.Generic.Queue[string]'); Title = ''; Instruction = ''; Detail = ''; Status = ''
        Texts = (New-Object 'System.Collections.Generic.List[string]'); Buttons = ''; Done = @{}; IsForeground = $true
    }
    $f | Add-Member -MemberType ScriptProperty -Name NowMs -Value { $this.Now }
    $f | Add-Member -MemberType ScriptMethod -Name SetTexts -Value { param($t, $i, $d) $this.Title = $t; $this.Instruction = $i; $this.Detail = $d; $this.Texts.Add($t + ' | ' + $i) }
    $f | Add-Member -MemberType ScriptMethod -Name SetButtonTexts -Value { param($a, $b, $c, $d) $this.Buttons = '{0}/{1}/{2}/{3}' -f $a, $b, $c, $d }
    $f | Add-Member -MemberType ScriptMethod -Name SetStatus -Value { param($t, $l) $this.Status = $t }
    $f | Add-Member -MemberType ScriptMethod -Name TakeAction -Value { if ($this.Actions.Count -gt 0) { return $this.Actions.Dequeue() }; return '' }
    $f | Add-Member -MemberType ScriptMethod -Name TakeEvents -Value { $a = $this.Events.ToArray(); $this.Events.Clear(); return , $a }
    $f | Add-Member -MemberType ScriptMethod -Name ClearEvents -Value { $this.Events.Clear() }
    # $Events (KcInputEvent 相当) の時刻を、いまからの相対の ms として入れる
    $f | Add-Member -MemberType ScriptMethod -Name Push -Value { param($Events) foreach ($e in @($Events)) { $e.Time = $this.Now + [long]$e.Time; $this.Events.Add($e) } }
    # 題名と指示が変わってから最初に 1 回だけ $true (同じ指示で 2 回目以降の Script を飛ばすため)
    $f | Add-Member -MemberType ScriptMethod -Name Once -Value { param($Key) $k = $this.Title + '|' + $this.Instruction + '|' + $Key; if ($this.Done.ContainsKey($k)) { return $false }; $this.Done[$k] = $true; return $true }
    foreach ($m in @('SetButtons', 'SetProgress', 'Confine', 'MaskWinKey', 'Activate', 'Close', 'Dispose', 'SetKeyState', 'ClearKeyStates',
            'ClearKeyBadges', 'ResetKeyLegends', 'SetSequence', 'ClearOutputs', 'SetLayerPath', 'SetLayerOverview', 'SetExtraLegendTexts', 'SetKeyLegendTexts')) {
        $f | Add-Member -MemberType ScriptMethod -Name $m -Value { }
    }
    return $f
}

# 偽の Probe。$State.Devices (Handle / Transport / Vid / Pid)、$State.Drives (Root / Label / Info)、$State.Log (行の Queue) を見る
function New-RgProbe($State) {
    return @{
        ListInputDevices = { return , @($State.Devices) }.GetNewClosure()
        DeviceName       = { param($h) if (@($State.Devices | Where-Object { $_.Handle -eq $h }).Count -gt 0) { 'dev' } else { '' } }.GetNewClosure()
        FindUf2Drives    = { return , @($State.Drives) }.GetNewClosure()
        NewLogReader     = { param($p) @{ ActiveName = 'COM9'; Candidates = @($State.Ports) } }.GetNewClosure()
        ReadLog          = { param($r) $l = @(); while ($State.Log.Count -gt 0) { $l += $State.Log.Dequeue() }; @{ Lines = $l; Status = $null; Level = 0 } }.GetNewClosure()
        CloseLog         = { param($r) $State.Closed = $true }.GetNewClosure()
        KeepAwake        = { param($on) $State.Awake += @([bool]$on) }.GetNewClosure()
        ReadHost         = { param($p) $State.Answers.Dequeue() }.GetNewClosure()
        WriteHost        = { param($t, $c) $State.Printed.Add([string]$t) }.GetNewClosure()
    }
}

function New-RgState {
    return @{
        Devices = @([pscustomobject]@{ Handle = [long]11; Type = 1; Transport = 'BLE'; Vid = '1D50'; Pid = '615E' },
            [pscustomobject]@{ Handle = [long]12; Type = 0; Transport = 'BLE'; Vid = '1D50'; Pid = '615E' })
        Drives = @(); Log = (New-Object 'System.Collections.Generic.Queue[string]'); Closed = $false; Awake = @(); Ports = @('COM9')
        Answers = (New-Object 'System.Collections.Generic.Queue[string]'); Printed = (New-Object 'System.Collections.Generic.List[string]')
    }
}

function Get-RgCheck([string]$Id) {
    # Get-KcRegressionChecks は配列を 1 つの値として返す (return , $x) ので、変数に受けてから回す
    $all = Get-KcRegressionChecks (Read-KcRegressionDocument $script:RgChecksPath)
    foreach ($c in $all) {
        if ($c.Id -eq $Id) { return $c }
    }
    throw ('checks.json に無い id: ' + $Id)
}

# 1 つの handler を偽物で流す。戻り値: @{ Outcome; Rows (Item=Status); Results; Ctx }
function Invoke-RgHandler([string]$Board, [string]$Id, $Form, $State, $Check = $null, $Expected = $null) {
    function Invoke-KcPump { $script:RgForm.Now += $script:RgForm.Step; & $script:RgForm.Script $script:RgForm }
    $script:RgForm = $Form
    $boardId = @{ LisM = 'lism'; KqMini = 'kq-mini'; KUKEY42 = 'kukey42'; 'torabo-tsuki-lp' = 'torabo-tsuki-lp' }[$Board]
    if ($null -eq $Expected) { $Expected = Get-KcExpected $boardId $script:ExpectedDir }
    if ($null -eq $Check) { $Check = Get-RgCheck $Id }
    $results = New-KcResultList
    $ctx = New-KcInputContext $Expected $script:RgCommon $results @{}
    $ctx.Options = @{ Board = $Board; Port = ''; CacheDir = '' }
    $ctx.Probe = New-RgProbe $State
    $ctx.Form = $Form
    $ctx.Balls = @(@($Expected.interactive.trackball.balls) | Select-Object -Last 1)
    $ctx.Keyboard = [long]11
    $ctx.Mouse = [long]12
    $ctx.Devices = @([long]11, [long]12)
    $ctx.Transport = ''
    $ctx.Check = $Check
    $ctx.Category = 'rg'
    $fn = $script:KcRegressionHandlers[$Check.Handler].Fn
    $o = & $fn $ctx $Check
    $rows = @($results | ForEach-Object { '{0}={1}' -f $_.Item, $_.Status })
    return @{ Outcome = $o; Rows = $rows; Results = $results; Ctx = $ctx; Text = ($rows -join ' / ') }
}

Test-Case '手順 manual: コンソールで、はい / いいえ / 誤った入力のやり直し' {
    $st = New-RgState
    foreach ($a in @('x', '1')) { $st.Answers.Enqueue($a) }
    $r = Invoke-RgHandler 'LisM' 'ble-battery' (New-RgForm {}) $st
    Assert-Equal '確認=PASS' $r.Text
    Assert-True (($st.Printed -join "`n") -like '*電池残量*1〜3 の番号*') ($st.Printed -join "`n")
    $st.Answers.Enqueue('2')
    $r = Invoke-RgHandler 'LisM' 'ble-battery' (New-RgForm {}) $st
    Assert-Equal '確認=FAIL' $r.Text
    Assert-True ($r.Results[0].Hint -like '*CONFIG_BT_BAS*') 'FAIL には、項目の fail_hint を足す'
}

# LisM の USB の抜き挿し: 挿す / 抜くの指示で、USB のデバイスを出し入れし、キーとボールを入れる。$DeadAt: その回の「挿した後」は何も届かない
function New-RgReplugForm($State, [int]$DeadAt = 0) {
    $plugs = @{ n = 0 }
    return New-RgForm {
        param($f)
        $State = $f.Data.State
        $DeadAt = $f.Data.DeadAt
        $plugs = $f.Data.Plugs
        if ($f.Instruction -like '*準備ができたら*' -and $f.Once('next')) { $f.Actions.Enqueue('next') }
        if ($f.Instruction -like '*USB を挿してください*' -and $f.Once('plug')) {
            $plugs.n++
            if ($f.Title -like '右手側*') {
                $State.Devices = @($State.Devices) + @([pscustomobject]@{ Handle = [long](20 + $plugs.n); Type = 1; Transport = 'USB'; Vid = '1D50'; Pid = '615E' })
            } else {
                $f.Actions.Enqueue('next')
            }
        }
        if ($f.Instruction -like '*USB を抜いてください*' -and $f.Once('unplug')) {
            if ($f.Title -like '右手側*') {
                $State.Devices = @($State.Devices | Where-Object { $_.Transport -ne 'USB' })
            } else {
                $f.Actions.Enqueue('next')
            }
        }
        if ($f.Instruction -like '*「Q」「P」を押し*' -and $f.Once('keys')) {
            $dead = ($DeadAt -gt 0 -and $f.Title -like ('右手側: 挿す / {0} 回目' -f $DeadAt))
            if (-not $dead) {
                $dev = [long](@($State.Devices | Where-Object { $_.Type -eq 1 })[-1].Handle)
                $f.Push(@(New-RgTap 100 'Q' $dev) + @(New-RgTap 300 'P' $dev) + @(New-RgMoves 400 800 100 12))
            }
        }
        if ($f.Instruction -like '*充電中なら*' -and $f.Once('yes')) { $f.Actions.Enqueue('next') }
    } 100 @{ State = $State; DeadAt = $DeadAt; Plugs = $plugs }
}

Test-Case '手順 replug (LisM の USB): 挿した後・抜いた後にキーとボールが届けば PASS、USB の認識も記録' {
    $st = New-RgState
    $r = Invoke-RgHandler 'LisM' 'lism-usb-plug' (New-RgReplugForm $st) $st
    Assert-Equal 'done' $r.Outcome
    Assert-Equal '右手側=PASS / 左手側=PASS / 目で確かめる=PASS' $r.Text
    $right = $r.Results[0]
    Assert-Equal '6 / 6 回、キーとボールが効いた' $right.Actual
    Assert-True ((@($right.Details) -join "`n") -like '*1 回目・挿した: USB を認識した*1 回目・抜いた: USB が切れた*') (@($right.Details) -join "`n")
}

Test-Case '手順 replug: 2 回目に挿した後に届かなければ FAIL (どの回か分かる)' {
    $st = New-RgState
    $r = Invoke-RgHandler 'LisM' 'lism-usb-plug' (New-RgReplugForm $st 2) $st
    Assert-True ($r.Text -like '右手側=FAIL / 左手側=PASS*') $r.Text
    Assert-True ((@($r.Results[0].Details) -join "`n") -like '*2 回目・挿した後: 15 秒たっても 「Q」、「P」、ボールの動き が届かない*') (@($r.Results[0].Details) -join "`n")
    Assert-True ($r.Results[0].Hint -like '*charge_indicator.c*') $r.Results[0].Hint
}

Test-Case '手順 replug: どのデバイスかを VID / PID で見分ける (ほかのデバイスの入力では合格にしない)' {
    $st = New-RgState
    $c = Get-RgCheck 'lism-usb-plug'
    $check = ConvertTo-KcRegressionCheck ([pscustomobject]@{ id = 'x'; title = 'x'; symptom = 's'; prs = @('keyball#1'); boards = @('LisM'); handler = 'replug'
            params = [pscustomobject]@{ repeat = 1; settle_ms = 100; targets = @([pscustomobject]@{ label = '左手側'; plug = 'USB を挿してください'; unplug = 'USB を抜いてください'; keys = @('Q'); ball = $false; usb = $false; respond_ms = 2000; check_after_unplug = $false }) } })
    $form = New-RgForm {
        param($f)
        if ($f.Instruction -like '*準備ができたら*' -and $f.Once('n')) { $f.Actions.Enqueue('next') }
        if ($f.Instruction -like '*USB を挿してください*' -and $f.Once('p')) { $f.Actions.Enqueue('next') }
        if ($f.Instruction -like '*USB を抜いてください*' -and $f.Once('u')) { $f.Actions.Enqueue('next') }
        # PC 本体のキーボード (ハンドル 99。VID / PID が違う) の入力
        if ($f.Instruction -like '*「Q」を押し*' -and $f.Once('k')) { $f.Push(@(New-RgTap 100 'Q' 99)) }
    } 50
    $st.Devices = @($st.Devices) + @([pscustomobject]@{ Handle = [long]99; Type = 1; Transport = 'USB'; Vid = '046D'; Pid = 'C31C' })
    $r = Invoke-RgHandler 'LisM' 'x' $form $st $check
    Assert-Equal '左手側=FAIL' $r.Text
    Assert-True ($null -ne $c) 'checks.json の項目もある'
}

# ブートローダ (XIAO の左手側だけ): 押したまま挿すとドライブが現れ、リセットで消える。$NoRelease: ファームが Q を離さない
function New-RgBootForm($State, [bool]$NoRelease = $false, [bool]$DriveOnPlain = $false) {
    $drive = [pscustomobject]@{ Root = 'E:\'; Label = 'XIAO-SENSE'; Info = "Board-ID: nRF52840-SeeedXiao-v1`n" }
    return New-RgForm {
        param($f)
        $State = $f.Data.State
        $NoRelease = $f.Data.NoRelease
        $DriveOnPlain = $f.Data.DriveOnPlain
        $drive = $f.Data.Drive
        if ($f.Instruction -like '*電源スイッチを OFF*') {
            if ($f.Once('skip')) { $f.Actions.Enqueue('skip') }
        } elseif ($f.Instruction -like '*を押したまま USB を挿してください*') {
            if ($f.Once('hold')) {
                $f.Push(@(New-RgKey 50 'Q' $false 11))
                if (-not $NoRelease) { $f.Push(@(New-RgKey 300 'Q' $true 11)) }
                $f.Data.DriveAt = $f.Now + 1500
            }
            if ($f.Data.DriveAt -gt 0 -and $f.Now -ge $f.Data.DriveAt) { $State.Drives = @($drive); $f.Data.DriveAt = 0 }
        }
        if ($f.Instruction -like '*リセットボタンを 1 回*' -and $f.Once('reset')) { $State.Drives = @() }
        if ($f.Instruction -like '*何も押さずに*' -and $f.Once('plain')) {
            if ($DriveOnPlain) { $State.Drives = @($drive) }
            $f.Actions.Enqueue('next')
        }
        if ($f.Instruction -like '「Q」を押してください' -and $f.Once('q')) { $f.Push(@(New-RgTap 100 'Q' 11)) }
    } 100 @{ State = $State; NoRelease = $NoRelease; DriveOnPlain = $DriveOnPlain; Drive = $drive; DriveAt = [long]0 }
}

function Get-RgBootCheck {
    $c = Get-RgCheck 'bootmagic'
    $raw = $c.Raw | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $raw.params.sides = @($raw.params.sides[0])
    $raw.params.negative_ms = 1000
    return (ConvertTo-KcRegressionCheck $raw)
}

Test-Case '手順 bootmagic: ドライブが現れ、Q が離される。電源 OFF はスキップ。何も押さなければふだんどおり' {
    $st = New-RgState
    $r = Invoke-RgHandler 'LisM' 'bootmagic' (New-RgBootForm $st) $st (Get-RgBootCheck)
    Assert-Equal 'done' $r.Outcome
    Assert-Equal '左手側: 動作中に「Q」を押したまま挿す=PASS / 左手側: 電源 OFF から「Q」を押したまま挿して起動=SKIP / 左手側: 何も押さずに挿すと、ふだんどおり起動する=PASS' $r.Text
    Assert-True ((@($r.Results[0].Details) -join "`n") -like '*nRF52840-SeeedXiao-v1*ブートローダに入る前に離された*') (@($r.Results[0].Details) -join "`n")
}

Test-Case '手順 bootmagic: Q が離されない・何も押さずにドライブが現れる は FAIL' {
    $st = New-RgState
    $r = Invoke-RgHandler 'LisM' 'bootmagic' (New-RgBootForm $st $true $true) $st (Get-RgBootCheck)
    Assert-True ($r.Text -like '*動作中に「Q」を押したまま挿す=FAIL*何も押さずに挿すと、ふだんどおり起動する=FAIL') $r.Text
    Assert-True ($r.Results[0].Hint -like '*押されたまま*') $r.Results[0].Hint
}

Test-Case '手順 bootmagic: 前の手順のドライブが残ったままなら、次の手順は SKIP (残ったドライブで合格にしない)' {
    $State = New-RgState
    $drive = [pscustomobject]@{ Root = 'E:\'; Label = 'XIAO-SENSE'; Info = "Board-ID: nRF52840-SeeedXiao-v1`n" }
    $form = New-RgForm {
        param($f)
        $State = $f.Data.State
        if ($f.Instruction -like '*を押したまま USB を挿してください*' -and $f.Instruction -notlike '*電源スイッチを OFF*' -and $f.Once('h')) { $State.Drives = @($f.Data.Drive) }
        # リセットしない。ドライブが残っていると言われたら、そのまま「次へ」
        if ($f.Instruction -like 'ブートローダのドライブ (*' -and $f.Once('n')) { $f.Actions.Enqueue('next') }
    } 500 @{ State = $State; Drive = $drive }
    $raw = (Get-RgBootCheck).Raw | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $raw.params.leave_ms = 2000
    $r = Invoke-RgHandler 'LisM' 'bootmagic' $form $State (ConvertTo-KcRegressionCheck $raw)
    Assert-Equal '左手側: 動作中に「Q」を押したまま挿す=PASS / 左手側: 電源 OFF から「Q」を押したまま挿して起動=SKIP / 左手側: 何も押さずに挿すと、ふだんどおり起動する=SKIP' $r.Text
    Assert-True ($r.Results[1].Actual -like '*ドライブが残っている*') $r.Results[1].Actual
    Assert-True ((@($r.Results[0].Details) -join "`n") -like '*ドライブが消えませんでした*') (@($r.Results[0].Details) -join "`n")
}

Test-Case '手順 replug (KQ-mini): つないだ状態から始め、抜く → 挿す の後にキーとボールが効く' {
    $State = New-RgState
    $State.Devices = @([pscustomobject]@{ Handle = [long]11; Type = 1; Transport = 'USB'; Vid = 'FEED'; Pid = '999C' }, [pscustomobject]@{ Handle = [long]12; Type = 0; Transport = 'USB'; Vid = 'FEED'; Pid = '999C' })
    $form = New-RgForm {
        param($f)
        $State = $f.Data.State
        if ($f.Instruction -like '*準備ができたら*' -and $f.Once('s')) { $f.Actions.Enqueue('next') }
        if ($f.Title -like 'Keyball の抜き挿し*' -and $f.Instruction -like 'Keyball の USB を*' -and $f.Once('k')) { $f.Actions.Enqueue('next') }
        if ($f.Instruction -like 'KQ-mini を PC から抜いて*' -and $f.Once('u')) { $State.Devices = @() }
        if ($f.Instruction -like 'KQ-mini を PC に挿して*' -and $f.Once('p')) {
            $f.Data.N++
            $State.Devices = @([pscustomobject]@{ Handle = [long](30 + $f.Data.N); Type = 1; Transport = 'USB'; Vid = 'FEED'; Pid = '999C' }, [pscustomobject]@{ Handle = [long](40 + $f.Data.N); Type = 0; Transport = 'USB'; Vid = 'FEED'; Pid = '999C' })
        }
        if ($f.Instruction -like '*「Q」「P」を押し*' -and $f.Once('q')) {
            $kb = [long]@($State.Devices | Where-Object { $_.Type -eq 1 })[0].Handle
            $ms = [long]@($State.Devices | Where-Object { $_.Type -eq 0 })[0].Handle
            $f.Push(@(New-RgTap 100 'Q' $kb) + @(New-RgTap 300 'P' $kb) + @(New-RgMoves 400 800 100 $ms))
        }
    } 200 @{ State = $State; N = 0 }
    $r = Invoke-RgHandler 'KqMini' 'kq-keyball-replug' $form $State
    Assert-Equal 'Keyball の抜き挿し=PASS / KQ-mini の入れ直し (コールドブート)=PASS' $r.Text
    Assert-Equal '2 / 2 回、キーとボールが効いた' $r.Results[0].Actual '抜いた後は確かめない (2 回 = 挿した後だけ)'
    Assert-True ($form.Texts[1] -like 'Keyball の抜き挿し: 抜く / 1 回目*') ('抜くのが先: ' + $form.Texts[1])
}

Test-Case '手順 ball-alive: 2 回とも「転がしていなかった」なら SKIP (例外にしない)' {
    $form = New-RgForm {
        param($f)
        if ($f.Instruction -like 'カウントダウンが終わるまで*') {
            # 手順の始めの 4 秒だけ転がす (試すたびに SetTexts が呼ばれるので、Texts の数で試した回を見分ける)
            if ($f.Data.Start -ne $f.Texts.Count) { $f.Data.Start = $f.Texts.Count; $f.Data.At = $f.Now }
            if (($f.Now - $f.Data.At) -lt 4000) { $f.Push(@(New-KcMouseEvent 0 2 1 0 0 0 12)) }
            if ($f.Status -like '*を押してください*' -and $f.Once(('k' + $f.Status + $f.Texts.Count))) { $f.Push(@(New-RgTap 0 'A' 11)) }
        }
        if ($f.Instruction -like '*転がし続けていましたか*' -and $f.Data.Asked -ne $f.Texts.Count) { $f.Data.Asked = $f.Texts.Count; $f.Data.No++; $f.Actions.Enqueue('retry') }
    } 100 @{ Start = -1; At = [long]0; Asked = -1; No = 0 }
    $r = Invoke-RgHandler 'LisM' 'ball-alive' $form (New-RgState)
    Assert-Equal 'ボールが止まらない (右のボール)=SKIP' $r.Text
    Assert-Equal 2 $form.Data.No '2 回尋ねた'
}

Test-Case '手順 readout: 右手側がログ版なら、RPC を送らずに SKIP' {
    $results = New-KcResultList
    $ctx = @{ Options = @{ Board = 'LisM'; Firmware = 'logging'; Readout = { throw '読み出してはいけない' } }; Results = $results; Category = 'rg'; Check = (Get-RgCheck 'keymap-readout') }
    Assert-Equal 'done' (Invoke-KcRgReadout $ctx $ctx.Check)
    Assert-Equal '読み出し=SKIP' (@($results | ForEach-Object { '{0}={1}' -f $_.Item, $_.Status }) -join ' / ')
}

Test-Case '手順 logging-soak: COM ポートが無ければ待たずに SKIP、複数あれば WARN' {
    $State = New-RgState
    $State.Ports = @()
    $r = Invoke-RgHandler 'LisM' 'logging-soak' (New-RgForm {} 100) $State
    Assert-Equal 'ログ版が止まらない=SKIP' $r.Text
    Assert-True ($r.Results[0].Actual -like '*COM ポートが見つかりません*') $r.Results[0].Actual
    $State = New-RgState
    $State.Ports = @('COM9', 'COM10')
    $raw = (Get-RgCheck 'logging-soak').Raw | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $raw.params.start_ms = 1000
    $r = Invoke-RgHandler 'LisM' 'logging-soak' (New-RgForm {} 100) $State (ConvertTo-KcRegressionCheck $raw)
    Assert-Equal 'COM ポート=WARN / ログ版が止まらない=SKIP' $r.Text
}

Test-Case '手順 bootmagic (torabo-tsuki-lp): BMP はボリュームラベルで見分け、電源 OFF の手順は無い' {
    $State = New-RgState
    $drive = [pscustomobject]@{ Root = 'F:\'; Label = 'BLEMICROPRO'; Info = "Board-ID: BLE-MICRO-PRO`n" }
    $form = New-RgForm {
        param($f)
        $State = $f.Data.State
        $drive = $f.Data.Drive
        if ($f.Instruction -like '*を押したまま USB を挿してください*' -and $f.Once('h')) { $State.Drives = @($drive) }
        if ($f.Instruction -like '*電源スイッチを OFF → ON*' -and $f.Once('r')) { $State.Drives = @() }
        if ($f.Instruction -like '*何も押さずに*' -and $f.Once('p')) { $f.Actions.Enqueue('next') }
        if ($f.Instruction -like '「Q」を押してください' -and $f.Once('q')) { $f.Push(@(New-RgTap 100 'Q' 11)) }
    } 100 @{ State = $State; Drive = $drive }
    $r = Invoke-RgHandler 'torabo-tsuki-lp' 'bootmagic' $form $State (Get-RgBootCheck)
    Assert-Equal '左手側: 動作中に「Q」を押したまま挿す=PASS / 左手側: 何も押さずに挿すと、ふだんどおり起動する=PASS' $r.Text
}

Test-Case '手順 logging-soak: ログを読み、thread analyzer を判定する (ポートには何も送らない)' {
    $State = New-RgState
    $form = New-RgForm {
        param($f)
        $State = $f.Data.State
        if ($f.Instruction -like '*キーを 1 つ押して*' -and $f.Once('first')) { $State.Log.Enqueue('[00:00:10.000,000] <dbg> zmk: zmk_physical_layouts_kscan_process_msgq: Row: 0, col: 0, position: 0, pressed: true') }
        if ($f.Instruction -like '*し続けてください*') {
            if ($f.Once('d1')) { foreach ($l in @((New-RgTa 30000 'Thread analyze:'), (New-RgTaThread 30001 'input' 576 2048), (New-RgTaThread 30002 'sysworkq' 1456 3072))) { $State.Log.Enqueue($l) } }
            if ($f.Status -like 'thread analyzer 1 / 2*' -and $f.Once('d2')) { foreach ($l in @((New-RgTa 60000 'Thread analyze:'), (New-RgTaThread 60001 'input' 600 2048))) { $State.Log.Enqueue($l) } }
        }
        if ($f.Instruction -like '*最後に「P」を押して*') {
            if ($f.Once('p')) {
                $f.Push(@(New-RgTap 100 'P' 11) + @(New-RgMoves 200 600 100 12))
                $f.Data.LogAt = $f.Now + 400
            }
            if ($f.Data.LogAt -gt 0 -and $f.Now -ge $f.Data.LogAt) {
                $State.Log.Enqueue('[00:01:05.000,000] <dbg> zmk: hid_listener_keycode_pressed: usage_page 0x07 keycode 0x13 implicit_mods 0x00 explicit_mods 0x00')
                $f.Data.LogAt = 0
            }
        }
    } 100 @{ State = $State; LogAt = [long]0 }
    $r = Invoke-RgHandler 'LisM' 'logging-soak' $form $State
    Assert-Equal 'done' $r.Outcome
    Assert-Equal 'ログ版が止まらない=PASS / 再起動・異常が無い=PASS / スタックの余裕 (75 % 未満)=PASS / 入力スレッド (通常版の 1024 バイトと比べた目安)=INFO' $r.Text
    Assert-True $State.Closed 'ポートを閉じる'
}

Test-Case '手順 logging-soak: ログが届かなければ SKIP、最後のキーの後にログが無ければ FAIL' {
    $st = New-RgState
    $check = Get-RgCheck 'logging-soak'
    $raw = $check.Raw | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $raw.params.start_ms = 2000
    $raw.params.max_ms = 3000
    $raw.params.respond_ms = 2000
    $short = ConvertTo-KcRegressionCheck $raw
    $r = Invoke-RgHandler 'LisM' 'logging-soak' (New-RgForm {} 100) $st $short
    Assert-Equal 'ログ版が止まらない=SKIP' $r.Text
    $State = New-RgState
    $form = New-RgForm {
        param($f)
        $State = $f.Data.State
        if ($f.Instruction -like '*キーを 1 つ押して*' -and $f.Once('first')) { $State.Log.Enqueue('[00:00:10.000,000] <dbg> zmk: x: y') }
        if ($f.Instruction -like '*最後に「P」を押して*' -and $f.Once('p')) { $f.Push(@(New-RgTap 100 'P' 11) + @(New-RgMoves 200 600 100 12)) }
    } 100 @{ State = $State }
    $r = Invoke-RgHandler 'LisM' 'logging-soak' $form $State $short
    Assert-True ($r.Text -like 'ログ版が止まらない=FAIL*thread analyzer=WARN*') $r.Text
}

Test-Case '手順 ball-alive: 転がし続ければ PASS、途中で止まって「転がしていた」なら FAIL' {
    $st = New-RgState
    $form = New-RgForm {
        param($f)
        if ($f.Instruction -like 'カウントダウンが終わるまで*') {
            $f.Push(@(New-KcMouseEvent 0 2 1 0 0 0 12))
            if ($f.Status -like '*を押してください*' -and $f.Once(('k' + $f.Status))) { $f.Push(@(New-RgTap 0 'A' 11)) }
        }
    } 100
    $r = Invoke-RgHandler 'LisM' 'ball-alive' $form $st
    Assert-Equal 'ボールが止まらない (右のボール)=PASS' $r.Text
    $form = New-RgForm {
        param($f)
        if ($f.Instruction -like 'カウントダウンが終わるまで*') {
            if ($f.Now -lt 5000) { $f.Push(@(New-KcMouseEvent 0 2 1 0 0 0 12)) }
            if ($f.Status -like '*を押してください*' -and $f.Once(('k' + $f.Status))) { $f.Push(@(New-RgTap 0 'A' 11)) }
        }
        if ($f.Instruction -like '*転がし続けていましたか*' -and $f.Once('yes')) { $f.Actions.Enqueue('next') }
    } 100
    $r = Invoke-RgHandler 'LisM' 'ball-alive' $form (New-RgState)
    Assert-Equal 'ボールが止まらない (右のボール)=FAIL' $r.Text
}

Test-Case '手順 idle-wake: USB を抜かせ、スリープを止めずに待ち、起こしてから Q・P・ボール' {
    $State = New-RgState
    $State.Devices = @($State.Devices) + @([pscustomobject]@{ Handle = [long]31; Type = 1; Transport = 'USB'; Vid = '1D50'; Pid = '615E' })
    $exp = (Get-KcExpected 'lism' $script:ExpectedDir) | ConvertTo-Json -Depth 64 | ConvertFrom-Json
    $exp.device.sleep_timeout_ms = 3000
    $form = New-RgForm {
        param($f)
        $State = $f.Data.State
        if ($f.Instruction -like '*両手の USB を抜いて*' -and $f.Once('u')) { $State.Devices = @($State.Devices | Where-Object { $_.Transport -ne 'USB' }) }
        if ($f.Instruction -like '*触らずに置いて*' -and $f.Once('s')) { $f.Actions.Enqueue('next') }
        if ($f.Instruction -like '*起こしてください*' -and $f.Once('w')) { $f.Push(@(New-RgTap 100 'Q' 11) + @(New-RgTap 300 'P' 11) + @(New-RgMoves 400 800 100 12)) }
    } 250 @{ State = $State }
    $raw = (Get-RgCheck 'idle-wake').Raw | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $raw.params.margin_ms = 1000
    $r = Invoke-RgHandler 'LisM' 'idle-wake' $form $State (ConvertTo-KcRegressionCheck $raw) $exp
    Assert-Equal 'スリープから戻る=PASS' $r.Text
    Assert-Equal 'True,False' ($State.Awake -join ',') 'PC のスリープを止め、戻す'
    Assert-True ((@($r.Results[0].Details) -join "`n") -like '*スリープに入ったこと自体は確かめていません*') 'スリープは観測していない'
}

Test-Case '手順 drag-hold (KQ-mini): ボタンを押したまま Ctrl → PASS、Ctrl で離れたら FAIL' {
    $ctrlScan = $script:RgScan.ByUsage[224]
    $mk = {
        param([bool]$Drop)
        $cs = $ctrlScan
        return New-RgForm {
            param($f)
            $Drop = $f.Data.Drop
            $ctrlScan = $f.Data.CtrlScan
            # やり直し (1 回目が FAIL) のときも、同じ入力をもう一度入れる
            if ($f.Instruction -like 'ボールを転がしてから*' -and ($f.Now - [long]$f.Data.Last) -ge 3000) {
                $f.Data.Last = $f.Now
                $ev = @((New-KcMouseEvent 100 0 0 0x0001 0 0 12)) + @(New-RgMoves 200 400 100 12) + @((New-KcKeyEvent 500 ([int]$ctrlScan.scan) 0 $false 11))
                if ($Drop) { $ev += New-KcMouseEvent 510 0 0 0x0002 0 0 12 }
                $ev += @((New-KcKeyEvent 900 ([int]$ctrlScan.scan) 0 $true 11))
                if (-not $Drop) { $ev += New-KcMouseEvent 1200 0 0 0x0002 0 0 12 }
                $f.Push($ev)
            }
        } 100 @{ Drop = $Drop; CtrlScan = $cs; Last = [long]-100000 }
    }
    $st = New-RgState
    $st.Devices = @([pscustomobject]@{ Handle = [long]11; Type = 1; Transport = 'USB'; Vid = 'FEED'; Pid = '999C' }, [pscustomobject]@{ Handle = [long]12; Type = 0; Transport = 'USB'; Vid = 'FEED'; Pid = '999C' })
    Assert-Equal 'ドラッグ中にキーを押しても切れない=PASS' (Invoke-RgHandler 'KqMini' 'kq-drag-hold' (& $mk $false) $st).Text
    Assert-True ((Invoke-RgHandler 'KqMini' 'kq-drag-hold' (& $mk $true) $st).Text -like '*=FAIL') 'Ctrl で離れた'
}

function Invoke-RgWhole($Ids, $Form, $State, [string]$Path) {
    function Invoke-KcPump { $script:RgForm.Now += $script:RgForm.Step; & $script:RgForm.Script $script:RgForm }
    $script:RgForm = $Form
    # Readout は Invoke-KcRegressionTest の中から呼ばれる。そこにある $state と重ならない名前にする
    $rgOrder = $State.Order
    $checks = Get-KcRegressionChecks (Read-KcRegressionDocument $script:RgChecksPath)
    $all = Select-KcRegressionChecks $checks 'LisM' 'studio'
    $entries = @($all | Where-Object { @($Ids) -contains $_.Check.Id })
    $results = New-KcResultList
    $o = Invoke-KcRegressionTest -Expected (Get-KcExpected 'lism' $script:ExpectedDir) -Common $script:RgCommon -Results $results -Entries $entries -Options @{
        Board = 'LisM'; Firmware = 'studio'; Port = ''; CacheDir = ''; HistoryPath = $Path; Probe = (New-RgProbe $State); Form = $Form
        Readout = { param($res) $rgOrder.Add('readout'); [void](Add-KcResult -Results $res -Category 'LisM (Studio)' -Item 'キーマップ' -Status PASS) }
    }
    $rows = @($results | Where-Object { $_.Status -ne 'INFO' } | ForEach-Object { '{0}|{1}={2}' -f $_.Category, $_.Item, $_.Status })
    return @{ Outcome = $o; Text = ($rows -join ' / '); History = (Read-KcRegressionHistory $Path) }
}

Test-Case '全体: 読み出し → ウィンドウ → 答えるだけ、の順。前回の結果を残す' {
    $State = New-RgState
    $State.Order = New-Object 'System.Collections.Generic.List[string]'
    $State.Answers.Enqueue('1')
    $form = New-RgForm {
        param($f)
        if (-not $f.Data.Seen) { $f.Data.Seen = $true; $f.Data.State.Order.Add('window'); $f.Actions.Enqueue('skip') }
    } 100 @{ State = $State; Seen = $false }
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('kc-reg-{0}.json' -f [guid]::NewGuid())
    try {
        $r = Invoke-RgWhole @('ble-battery', 'ball-alive', 'keymap-readout') $form $State $path
        Assert-Equal 'done' $r.Outcome
        Assert-True ($r.Text -like '回帰: キーマップと設定が期待値どおり (読み出し)|LisM (Studio): キーマップ=PASS*回帰: Windows に電池残量が出る|確認=PASS') $r.Text
        Assert-Equal 'readout,window' ($State.Order -join ',') '読み出しが先、ウィンドウが後'
        Assert-Equal 0 $State.Answers.Count '答えるだけの項目も行った (コンソール)'
        $h = $r.History
        Assert-Equal 'keymap-readout=PASS,ball-alive=SKIP,ble-battery=PASS' (@($h | ForEach-Object { '{0}={1}' -f $_.check, $_.status }) -join ',')
        Assert-Equal 'studio' $h[0].firmware
        Assert-True ($h[0].expected -like '*zmk-config-LisM@*') $h[0].expected
        Assert-Equal 8 ([string]$h[0].hash).Length 'ハッシュ'
    } finally {
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
    }
}

Test-Case '全体: 中止すると、残りの項目は行わずに SKIP' {
    $State = New-RgState
    $State.Order = New-Object 'System.Collections.Generic.List[string]'
    $State.Answers.Enqueue('1')
    $form = New-RgForm { param($f) if ($f.Once('a')) { $f.Actions.Enqueue('abort') } } 100
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('kc-reg-{0}.json' -f [guid]::NewGuid())
    try {
        $r = Invoke-RgWhole @('ble-battery', 'ball-alive', 'aml-shift-click') $form $State $path
        Assert-Equal 'abort' $r.Outcome
        Assert-True ($r.Text -like '回帰: ボールを転がし続けても、カーソルが止まらない|回帰テスト=SKIP*回帰: AML で Shift + クリックができる|回帰テスト=SKIP*回帰: Windows に電池残量が出る|回帰テスト=SKIP') $r.Text
        Assert-Equal 1 $State.Answers.Count '中止の後は尋ねない'
    } finally {
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
    }
}
