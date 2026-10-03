# 入力イベントモニタ (tools/scripts/input-monitor.ps1、lib/input-monitor/*.ps1) のテスト。
# パスの解析・間隔の統計・停滞の検出・キーの時系列・AML ビュー・記録ファイルの往復は Windows の API を使わない。

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'rawhid.ps1')
. (Join-Path $script:KcLib 'input-eval.ps1')
. (Join-Path (Join-Path $script:ToolsDir 'lib\input-monitor') 'devices.ps1')
. (Join-Path (Join-Path $script:ToolsDir 'lib\input-monitor') 'analyze.ps1')

$imCommon = Get-KcExpected 'common' $script:ExpectedDir
$imScan = New-KcScanTable $imCommon
$script:ImEntry = Join-Path $script:ToolsDir 'scripts\input-monitor.ps1'
$script:ImHostExe = (Get-Process -Id $PID).Path

$imUsbKeyboardPath = '\\?\HID#VID_1D50&PID_615E&MI_00&Col01#8&2f3a1b2c&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}'
$imUsbMousePath = '\\?\HID#VID_1D50&PID_615E&MI_00&Col03#8&2f3a1b2c&0&0002#{378de44c-56ef-11d1-bc8c-00a0c91405dd}'
$imBleKeyboardPath = '\\?\HID#{00001812-0000-1000-8000-00805f9b34fb}_DEV_VID&021d50_PID&615e_REV&0001_c3f2a1b0d9e8&Col01#9&1a2b3c4d&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}'
$imBleMousePath = '\\?\HID#{00001812-0000-1000-8000-00805f9b34fb}_DEV_VID&021d50_PID&615e_REV&0001_c3f2a1b0d9e8&Col03#9&1a2b3c4d&0&0002#{378de44c-56ef-11d1-bc8c-00a0c91405dd}'

# usage → スキャンコードのキーの行 (押す / 離す)
function New-ImKeyRowByUsage([double]$Time, [int]$Usage, [bool]$Break = $false, [int]$Device = 1) {
    $k = $imScan.ByUsage[$Usage]
    return (New-ImKeyRow $Time ([int]$k.scan) ([int]$k.prefix) $Break $Device)
}

# 一定の間隔で動く移動の行
function New-ImMotionRows([double]$Start, [double]$IntervalMs, [int]$Count, [int]$Device = 2, [int]$Dx = 3, [int]$Dy = -1) {
    $rows = @()
    for ($i = 0; $i -lt $Count; $i++) {
        $rows += (New-ImMouseRow ($Start + $i * $IntervalMs) $Dx $Dy 0 0 0 $Device)
    }
    return , $rows
}

function New-ImTestDevices {
    $kb = New-ImDevice -Id 1 -Handle 11 -Kind 'key' -Info (ConvertFrom-ImDevicePath $imBleKeyboardPath) -Name 'LisM'
    $ms = New-ImDevice -Id 2 -Handle 12 -Kind 'mouse' -Info (ConvertFrom-ImDevicePath $imBleMousePath) -Name 'LisM'
    $other = New-ImDevice -Id 3 -Handle 13 -Kind 'mouse' -Info (ConvertFrom-ImDevicePath '\\?\HID#VID_046D&PID_C52B&MI_01&Col01#7&1&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}') -Name ''
    return , @($kb, $ms, $other)
}

# 記録のサンプル: 15 ms 一定の移動の途中に 200 ms の停滞 + 10 件のバースト、Ctrl / A の mod-tap、移動 → クリック、Shift → F、ホイール
function New-ImSampleRows {
    $rows = @()
    # 0〜3000 ms: 15 ms ごとの移動 (200 件)
    $rows += (New-ImMotionRows 0 15 200)
    # 3200 ms: 200 ms 止まったあと、10 件が 1 ms 間隔で届く
    $rows += (New-ImMotionRows 3185 1 10)
    # 3209〜4394 ms: 15 ms ごとの移動に戻る
    $rows += (New-ImMotionRows 3209 15 80)
    # 4600 ms: ボタン 1 のクリック (AML 中)
    $rows += (New-ImMouseRow 4600 0 0 0x0001 0 0 2)
    $rows += (New-ImMouseRow 4680 0 0 0x0002 0 0 2)
    # 5000 ms: Shift (長押し) → F (= AML 中の Shift + クリック相当だが、ここでは文字で確認)
    $rows += (New-ImKeyRowByUsage 5000 0xE1 $false)
    $rows += (New-ImKeyRowByUsage 5001 0x09 $false)
    $rows += (New-ImKeyRowByUsage 5080 0x09 $true)
    $rows += (New-ImKeyRowByUsage 5200 0xE1 $true)
    # 20000 ms: Ctrl / A の mod-tap (A を 155 ms 押した)
    $rows += (New-ImKeyRowByUsage 20000 0xE0 $false)
    $rows += (New-ImKeyRowByUsage 20000 0x04 $false)
    $rows += (New-ImKeyRowByUsage 20155 0x04 $true)
    $rows += (New-ImKeyRowByUsage 20200 0xE0 $true)
    # 20500 ms: ホイール (手前へ 2、右へ 1)
    $rows += (New-ImMouseRow 20500 0 0 0 -120 0 2)
    $rows += (New-ImMouseRow 20520 0 0 0 -120 0 2)
    $rows += (New-ImMouseRow 20540 0 0 0 0 120 2)
    # 21000 ms: , のタップ (ラベルに , を含む)
    $rows += (New-ImKeyRowByUsage 21000 0x36 $false)
    $rows += (New-ImKeyRowByUsage 21050 0x36 $true)
    return , $rows
}

function New-ImSampleRecording([string]$Dir) {
    $devices = New-ImTestDevices
    $rows = New-ImSampleRows
    $csv = Join-Path $Dir 'sample.csv'
    $json = Join-Path $Dir 'sample.json'
    Export-ImCsv $rows $devices $csv $imScan
    $marks = @([pscustomobject]@{ N = 1; T = 15000.0 })
    $meta = New-ImMeta @{ Started = '2026-10-02 12:34:56'; DurationMs = 21500; Os = 'test'; Ps = 'test'; GapMs = 50; IdleMs = 300; Seconds = 0; ShowMotion = $false; EventsFile = 'sample.csv' } $devices $devices $marks
    Export-ImMeta $meta $json
    return @{ Csv = $csv; Json = $json; Rows = $rows; Devices = $devices }
}

function New-ImTempDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('im-test-{0}' -f [guid]::NewGuid())
    [void](New-Item -ItemType Directory -Force -Path $dir)
    return $dir
}

# ---------------------------------------------------------------------------
# デバイス
# ---------------------------------------------------------------------------

Test-Case 'パスの解析: USB (MI / Col 付き)' {
    $i = ConvertFrom-ImDevicePath $imUsbKeyboardPath
    Assert-Equal 'USB' $i.Transport
    Assert-Equal '1D50' $i.Vid
    Assert-Equal '615E' $i.Pid
    Assert-Equal 0 $i.Interface
    Assert-Equal 1 $i.Collection
    Assert-Equal 'keyboard' $i.Class
    Assert-Equal '' $i.Addr
    $m = ConvertFrom-ImDevicePath $imUsbMousePath
    Assert-Equal 'mouse' $m.Class
    Assert-Equal 3 $m.Collection
    Assert-Equal $i.GroupKey $m.GroupKey '同じインターフェイスのコレクションは同じ GroupKey'
    Assert-Equal 'USB:1D50:615E' $m.FamilyKey
    $simple = ConvertFrom-ImDevicePath '\\?\HID#VID_FEED&PID_999C#6&abc&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}'
    Assert-Equal 'USB' $simple.Transport
    Assert-Equal -1 $simple.Interface
    Assert-Equal 0 $simple.Collection
}

Test-Case 'パスの解析: BLE (HID over GATT)' {
    $i = ConvertFrom-ImDevicePath $imBleMousePath
    Assert-Equal 'BLE' $i.Transport
    Assert-Equal '1D50' $i.Vid
    Assert-Equal '615E' $i.Pid
    Assert-Equal 'C3F2A1B0D9E8' $i.Addr
    Assert-Equal 3 $i.Collection
    Assert-Equal 'mouse' $i.Class
    Assert-Equal 'BLE:1D50:615E:C3F2A1B0D9E8' $i.GroupKey
    Assert-Equal $i.GroupKey (ConvertFrom-ImDevicePath $imBleKeyboardPath).GroupKey
    $other = ConvertFrom-ImDevicePath ($imBleKeyboardPath -replace 'c3f2a1b0d9e8', '001122334455')
    Assert-True ($other.GroupKey -ne $i.GroupKey) '別のアドレスは別の GroupKey'
}

Test-Case 'パスの解析: その他 (ACPI / RDP / 空)' {
    $acpi = ConvertFrom-ImDevicePath '\\?\ACPI#PNP0303#4&2d4a1b3c&0#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}'
    Assert-Equal 'Other' $acpi.Transport
    Assert-Equal 'keyboard' $acpi.Class
    Assert-Equal '' $acpi.Vid
    $rdp = ConvertFrom-ImDevicePath '\\?\Root#RDP_KBD#0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}'
    Assert-Equal 'Other' $rdp.Transport
    $empty = ConvertFrom-ImDevicePath ''
    Assert-Equal 'Other' $empty.Transport
    Assert-Equal '' $empty.Class
}

Test-Case 'ラベル: ZMK は製品名、Keyball39 / KQ-mini / その他' {
    Assert-Equal 'LisM (BLE)' (Get-ImDeviceLabel (ConvertFrom-ImDevicePath $imBleKeyboardPath) 'LisM')
    Assert-Equal 'KUKEY42 (USB)' (Get-ImDeviceLabel (ConvertFrom-ImDevicePath $imUsbKeyboardPath) 'KUKEY42')
    Assert-Equal 'ZMK (USB)' (Get-ImDeviceLabel (ConvertFrom-ImDevicePath $imUsbKeyboardPath) '')
    Assert-Equal 'Keyball39 (USB)' (Get-ImDeviceLabel (ConvertFrom-ImDevicePath '\\?\HID#VID_5957&PID_0200&MI_01#7&1&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}') 'Keyball39')
    Assert-Equal 'KQ-mini + Keyball39 (USB)' (Get-ImDeviceLabel (ConvertFrom-ImDevicePath '\\?\HID#VID_FEED&PID_999C&MI_00#7&1&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}') 'Keyboard Quantizer Mini')
    Assert-Equal 'その他 (USB VID 046D / PID C52B)' (Get-ImDeviceLabel (ConvertFrom-ImDevicePath '\\?\HID#VID_046D&PID_C52B&MI_01&Col01#7&1&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}') '')
    Assert-Equal 'USB Receiver (USB VID 046D / PID C52B)' (Get-ImDeviceLabel (ConvertFrom-ImDevicePath '\\?\HID#VID_046D&PID_C52B&MI_01&Col01#7&1&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}') 'USB Receiver')
    Assert-Equal '001122334455 (BLE)' (Get-ImDeviceLabel (ConvertFrom-ImDevicePath ('\\?\HID#{00001812-0000-1000-8000-00805f9b34fb}_DEV_VID&01004C_PID&0267_001122334455&Col01#9&1&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}')) '')
    Assert-True ((Get-ImDeviceLabel (ConvertFrom-ImDevicePath '\\?\Root#RDP_KBD#0000#{884b96c3-56ef-11d1-bc8c-00a0c91405dd}') '') -like 'その他 (*RDP_KBD*')
}

Test-Case 'デバイス: 同じ物理デバイスをまとめ、一覧の行を作る。HID インターフェイスのパスに変換できる' {
    $devices = New-ImTestDevices
    $groups = Group-ImDevice $devices
    Assert-Equal 2 @($groups.Keys).Count
    Assert-Equal 2 @($groups[[string]$devices[0].GroupKey]).Count
    $lines = Format-ImConnectedLines $devices
    Assert-Equal 2 @($lines).Count
    Assert-True ($lines[0] -like 'LisM (BLE)*キーボード / マウス*[C3F2A1B0D9E8]*') $lines[0]
    Assert-True ($lines[1] -like 'その他 (USB VID 046D / PID C52B)*マウス*') $lines[1]
    Assert-Equal '#2 LisM (BLE) マウス' (Format-ImDeviceLine $devices[1])
    Assert-Equal ('\\?\HID#VID_1D50&PID_615E&MI_00&Col01#8&2f3a1b2c&0&0000#' + $script:KcHidInterfaceGuid) (Get-ImHidInterfacePath $imUsbKeyboardPath)
    $none = Format-ImConnectedLines @()
    Assert-Equal 1 @($none).Count '無いときは案内の 1 行'
    Assert-True ($none[0] -like '(キーボード・マウスが見つかりません)') $none[0]
    # JSON の形との往復
    $back = ConvertFrom-ImDeviceJson ([pscustomobject](ConvertTo-ImDeviceJson $devices[1]))
    Assert-Equal $devices[1].Label $back.Label
    Assert-Equal $devices[1].GroupKey $back.GroupKey
    Assert-Equal 'mouse' $back.Kind
}

# ---------------------------------------------------------------------------
# 間隔と停滞
# ---------------------------------------------------------------------------

Test-Case '間隔の統計: 一定 15 ms' {
    $times = [double[]]@(0..199 | ForEach-Object { $_ * 15.0 })
    $s = Get-ImIntervalStats $times 300
    Assert-Equal 200 $s.Count
    Assert-Equal 199 $s.ActiveCount
    Assert-Near 15 $s.Median 0.001
    Assert-Near 15 $s.P95 0.001
    Assert-Near 15 $s.Max 0.001
    Assert-Equal 0 $s.Pauses
    Assert-Near (199 * 15) $s.ActiveSpanMs 0.001
    $bin = @($s.Bins | Where-Object { $_.From -eq 12 })[0]
    Assert-Equal 20 $bin.To
    Assert-Near 100 $bin.Percent 0.001 '12-20 ms に集中する'
    Assert-Equal 300 @($s.Bins)[-1].To '最後の区切りは IdleMs'
    $one = Get-ImIntervalStats ([double[]]@(5.0)) 300
    Assert-Equal 1 $one.Count
    Assert-Equal 0 $one.ActiveCount
}

Test-Case '停滞の検出: 200 ms 止まって 10 件が 1 ms 間隔で届く' {
    $rows = @()
    $rows += (New-ImMotionRows 0 15 100)          # 〜1485 ms
    $rows += (New-ImMotionRows 1685 1 10)         # 200 ms の停滞のあとのバースト
    $rows += (New-ImMotionRows 1709 15 50)
    $r = Find-ImStalls $rows 50 300 9
    Assert-Equal 1 @($r.Stalls).Count
    $st = @($r.Stalls)[0]
    Assert-Near 1485 $st.Start 0.001
    Assert-Near 200 $st.GapMs 0.001
    Assert-Equal 10 $st.BurstCount
    Assert-Near 9 $st.BurstSpanMs 0.001
    Assert-Equal 30 $st.Dx
    Assert-True (-not $st.Overflow) '300 ms 未満は Overflow ではない'
    Assert-Equal 0 $r.Hiccups
    Assert-Equal 0 $r.Pauses
    # 400 ms なら Overflow
    $rows2 = @()
    $rows2 += (New-ImMotionRows 0 15 100)
    $rows2 += (New-ImMotionRows 1885 1 10)
    $r2 = Find-ImStalls $rows2 50 300 9
    Assert-Equal 1 @($r2.Stalls).Count
    Assert-True @($r2.Stalls)[0].Overflow
}

Test-Case '停止 (手を止めた) と途切れは停滞にしない' {
    $rows = @()
    $rows += (New-ImMotionRows 0 15 100)          # 〜1485
    $rows += (New-ImMotionRows 1985 15 50)        # 500 ms の停止のあと、普通に 15 ms
    $r = Find-ImStalls $rows 50 300 9
    Assert-Equal 0 @($r.Stalls).Count
    Assert-Equal 1 $r.Pauses
    Assert-Equal 0 $r.Hiccups
    $rows2 = @()
    $rows2 += (New-ImMotionRows 0 15 50)          # 〜735
    $rows2 += (New-ImMotionRows 815 15 50)        # 80 ms の途切れ (まとめて届かない)
    $r2 = Find-ImStalls $rows2 50 300 9
    Assert-Equal 0 @($r2.Stalls).Count
    Assert-Equal 1 $r2.Hiccups
    Assert-Equal 1 (Get-ImIntervalStats (Get-ImMotionTimes $rows) 300).Pauses
}

Test-Case '見立て: 停滞が多い BLE / USB、安定、移動が少ない' {
    $devices = New-ImTestDevices
    $stable = [pscustomobject]@{ Count = 1000; Median = 15.0; P95 = 16.0; ActiveSpanMs = 15000.0 }
    $noStall = @{ Stalls = @(); Hiccups = 0; Pauses = 0 }
    Assert-True ((Get-ImVerdict $devices[1] $stable $noStall) -like '問題は見当たりません*')
    $jitter = [pscustomobject]@{ Count = 1000; Median = 15.0; P95 = 40.0; ActiveSpanMs = 15000.0 }
    Assert-True ((Get-ImVerdict $devices[1] $jitter $noStall) -like 'BLE の送信が詰まっている*')
    $many = @{ Stalls = @(1, 2, 3); Hiccups = 0; Pauses = 0 }
    Assert-True ((Get-ImVerdict $devices[2] $stable $many) -like 'USB 接続なので*')
    $few = [pscustomobject]@{ Count = 10; Median = 15.0; P95 = 40.0; ActiveSpanMs = 150.0 }
    Assert-True ((Get-ImVerdict $devices[1] $few $many) -like '移動が少ない*')
}

# ---------------------------------------------------------------------------
# キーの時系列と AML ビュー
# ---------------------------------------------------------------------------

Test-Case 'キーの時系列: 押下時間・同時に押していたキー・備考 (mod-tap)' {
    $devices = New-ImTestDevices
    $rows = @(
        (New-ImKeyRowByUsage 1000 0xE0 $false), (New-ImKeyRowByUsage 1000 0x04 $false),
        (New-ImKeyRowByUsage 1030 0x04 $false),                                      # オートリピート
        (New-ImKeyRowByUsage 1155 0x04 $true), (New-ImKeyRowByUsage 1200 0xE0 $true),
        (New-ImKeyRowByUsage 2000 0x05 $false), (New-ImKeyRowByUsage 2050 0x05 $true)
    )
    $tl = Get-ImKeyTimeline @{ 1 = $rows } $devices $imScan 150
    Assert-Equal 6 @($tl).Count 'リピートはまとめる'
    Assert-Equal 'Ctrl' $tl[0].Label
    Assert-True $tl[0].Down
    Assert-Equal '-' (Format-ImDelta $tl[0].DeltaPrevMs)
    Assert-Equal '他キーと同時に出力 (ホールド判定)' $tl[0].Note
    Assert-Equal 'A' $tl[1].Label
    Assert-Equal 'Ctrl (0)' (@($tl[1].HeldKeys) -join ',')
    Assert-True (-not $tl[2].Down)
    Assert-Near 155 $tl[2].HoldMs 0.001
    Assert-Equal '長押し (150 ms 以上)' $tl[2].Note
    Assert-Near 155 $tl[2].DeltaPrevMs 0.001
    Assert-Near 200 $tl[3].HoldMs 0.001
    Assert-True ($tl[3].Note -like '*修飾として使用*') $tl[3].Note
    Assert-Equal 'B' $tl[4].Label
    Assert-Equal '' $tl[4].Note
    Assert-Near 50 $tl[5].HoldMs 0.001
    Assert-Equal '' $tl[5].Note '短いタップには備考なし'
}

Test-Case 'キーの時系列: マウスボタンも並ぶ' {
    $devices = New-ImTestDevices
    $by = @{
        1 = @((New-ImKeyRowByUsage 100 0xE1 $false), (New-ImKeyRowByUsage 400 0xE1 $true))
        2 = @((New-ImMouseRow 101 0 0 0x0001 0 0 2), (New-ImMouseRow 180 0 0 0x0002 0 0 2))
    }
    $tl = Get-ImKeyTimeline $by $devices $imScan 150
    Assert-Equal 4 @($tl).Count
    Assert-Equal 'Shift,ボタン 1,ボタン 1,Shift' (@($tl | ForEach-Object { $_.Label }) -join ',')
    Assert-Equal 2 $tl[1].Device
    Assert-Equal 1 $tl[1].Button
    Assert-Equal '他キーと同時に出力 (ホールド判定)' $tl[0].Note 'Shift がクリックと同時に出た'
    Assert-Near 79 $tl[2].HoldMs 0.001
    Assert-Equal 'Shift (1)' (@($tl[1].HeldKeys) -join ',')
}

Test-Case 'AML ビュー: 移動直後のクリック / 10 秒後のキー / 修飾キーによる解除' {
    $devices = New-ImTestDevices
    $motion = New-ImMotionRows 0 15 20            # 〜285 ms
    $by = @{
        1 = @(
            (New-ImKeyRowByUsage 1000 0x09 $false), (New-ImKeyRowByUsage 1050 0x09 $true),    # F: 移動から 715 ms
            (New-ImKeyRowByUsage 2000 0xE1 $false), (New-ImKeyRowByUsage 2100 0xE1 $true),    # Shift
            (New-ImKeyRowByUsage 2200 0x09 $false), (New-ImKeyRowByUsage 2250 0x09 $true),    # F (修飾キーのあと)
            (New-ImKeyRowByUsage 12000 0x09 $false), (New-ImKeyRowByUsage 12050 0x09 $true)   # F: 10 秒超
        )
        2 = @($motion + @((New-ImMouseRow 400 0 0 0x0001 0 0 2), (New-ImMouseRow 450 0 0 0x0002 0 0 2)))
        3 = @((New-ImMouseRow 100 5 5 0 0 0 3), (New-ImMouseRow 20000 0 0 0x0001 0 0 3))
    }
    $tl = Get-ImKeyTimeline $by $devices $imScan 150
    $aml = Get-ImAmlView $by $devices $tl 10000
    $mine = @($aml | Where-Object { $_.Device -ne 3 })
    Assert-Equal 5 $mine.Count
    Assert-Equal 'ボタン 1 押す' $mine[0].Input
    Assert-Near 115 $mine[0].SinceMotionMs 0.001
    Assert-Equal 'AML 中 (クリック)' $mine[0].State
    Assert-Equal 'F 押す' $mine[1].Input
    Assert-Near 715 $mine[1].SinceMotionMs 0.001
    Assert-Equal '移動から 0.7 秒以内に文字' $mine[1].State
    Assert-Equal '修飾キー (AML が切れる契機)' $mine[2].State
    Assert-Equal '移動から 1.9 秒以内に文字 (直前に修飾キー → AML 解除後)' $mine[3].State
    Assert-Equal 'AML 終了後 (10 秒超)' $mine[4].State
    # 別の機種 (同じ GroupKey も FamilyKey も無い) のクリックは、自分のボールで判定する
    $other = @($aml | Where-Object { $_.Device -eq 3 })
    Assert-Equal 1 $other.Count
    Assert-True ($other[0].State -like 'クリック (移動から 10 秒超)') $other[0].State
    $noMotion = Get-ImAmlView @{ 1 = $by[1] } $devices $tl 10000
    Assert-Equal 0 @($noMotion).Count '移動が無ければ空'
}

# ---------------------------------------------------------------------------
# 記録ファイルとライブログ
# ---------------------------------------------------------------------------

Test-Case 'CSV / JSON の往復 (BOM、引用符、dt_ms、デバイスの一覧、マーク)' {
    $dir = New-ImTempDir
    try {
        $sample = New-ImSampleRecording $dir
        $bytes = [System.IO.File]::ReadAllBytes($sample.Csv)
        Assert-True ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'CSV は BOM 付き'
        $text = [System.IO.File]::ReadAllText($sample.Csv, [System.Text.Encoding]::UTF8)
        Assert-True ($text.StartsWith('t_ms,device,label,kind,event,key,')) 'ヘッダ'
        Assert-True ($text -like '*,1,LisM (BLE),key,down,",",*') ', のラベルは引用符で囲む'
        Assert-True ($text -like '*15.000,2,LisM (BLE),mouse,motion,,0,0,3,-1,0,0,0,15.000*') '2 件目の移動の dt_ms は 15'
        Assert-True ($text -like '*mouse,button,MB1 down,*') 'ボタンの key 列'
        Assert-True ($text -like '*mouse,wheel,wheel -120,*') 'ホイールの key 列'
        $rec = Read-ImRecording $sample.Json
        Assert-Equal @($sample.Rows).Count @($rec.Rows).Count
        Assert-Equal '2026-10-02 12:34:56' $rec.Started
        Assert-Near 21500 $rec.DurationMs 0.001
        Assert-Equal 3 @($rec.Devices).Count
        Assert-Equal 'LisM (BLE)' $rec.Devices[1].Label
        Assert-Equal 'mouse' $rec.Devices[1].Kind
        Assert-Equal $sample.Devices[1].GroupKey $rec.Devices[1].GroupKey
        Assert-Equal 1 @($rec.Marks).Count
        Assert-Near 15000 $rec.Marks[0].T 0.001
        Assert-Equal $sample.Csv $rec.Paths.Csv '.json を渡しても .csv を見つける'
        # 行の中身
        $r0 = $rec.Rows[0]
        Assert-Equal 'mouse' $r0.Kind
        Assert-Equal 3 $r0.Dx
        Assert-Equal -1 $r0.Dy
        $burst = $rec.Rows[200]
        Assert-Near 3185 $burst.Time 0.0005
        $comma = @($rec.Rows | Where-Object { $_.Kind -eq 'key' -and $_.Scan -eq [int]$imScan.ByUsage[0x36].scan })
        Assert-Equal 2 $comma.Count
        Assert-True $comma[1].Break
        $wheel = @($rec.Rows | Where-Object { $_.Wheel -ne 0 -or $_.HWheel -ne 0 })
        Assert-Equal 3 $wheel.Count
        Assert-Equal 120 $wheel[2].HWheel
        $btn = @($rec.Rows | Where-Object { $_.Buttons -ne 0 })
        Assert-Equal 2 $btn.Count
        # CSV だけでも読める (デバイスは番号だけ)
        Remove-Item -LiteralPath $sample.Json
        $only = Read-ImRecording $sample.Csv
        Assert-Equal 0 @($only.Devices).Count
        Assert-Equal @($sample.Rows).Count @($only.Rows).Count
        Assert-Throws { Read-ImRecording (Join-Path $dir 'nothing.csv') } '*記録のファイルがありません*'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force
    }
}

Test-Case 'CSV の 1 行の分割: 引用符の中の , と ""' {
    Assert-Equal 'a|b||c' ((Split-ImCsvLine 'a,b,,c') -join '|')
    Assert-Equal 'a|b,c|d""e|' ((Split-ImCsvLine 'a,"b,c","d""""e",') -join '|')
    Assert-Equal '","' (ConvertTo-ImCsvField ',')
    Assert-Equal '"a""b"' (ConvertTo-ImCsvField 'a"b')
    Assert-Equal 'plain' (ConvertTo-ImCsvField 'plain')
}

Test-Case '分析と報告: サンプルの記録で停滞 1 回、キーの時系列、AML、ホイール、マーク' {
    $devices = New-ImTestDevices
    $rec = @{ Started = '2026-10-02 12:34:56'; DurationMs = 21500; Devices = $devices; Connected = $devices; Rows = (New-ImSampleRows); Marks = @([pscustomobject]@{ N = 1; T = 15000.0 }); Paths = @{ Csv = 'sample.csv'; Json = 'sample.json' } }
    $a = Invoke-ImAnalysis $rec @{ GapMs = 50; IdleMs = 300; ScanTable = $imScan }
    Assert-Equal 3 @($a.Devices).Count
    Assert-True $a.Intervals.ContainsKey(2)
    Assert-True (-not $a.Intervals.ContainsKey(1)) 'キーボードには間隔の統計が無い'
    Assert-Equal 290 $a.Intervals[2].Count
    Assert-Near 15 $a.Intervals[2].Median 0.001
    Assert-Equal 1 @($a.Stalls[2].Stalls).Count
    Assert-Near 200 @($a.Stalls[2].Stalls)[0].GapMs 0.001
    Assert-Equal 1 $a.Wheel.Count
    Assert-Equal 2 $a.Wheel[2].Down
    Assert-Equal 1 $a.Wheel[2].Right
    Assert-Equal 1 @($a.Marks).Count
    $lines = Format-ImReport $a $rec 10
    $text = $lines -join "`n"
    Assert-True ($text -like '*==== 接続中のデバイス (起動時) ====*') '接続中の節'
    Assert-True ($text -like '*#2 LisM (BLE) マウス*移動 290 件 / ボタン 2 件 / ホイール 3 件*') '記録したデバイス'
    Assert-True ($text -like '*停滞 → まとめて到着: 1 回 (最長 200 ms、300 ms 超 0 回)*') $text
    Assert-True ($text -like '*2.985 秒  200 ms 止まったあと 10 件が 9.0 ms に集中 (X +30 / Y -10)*') '停滞の行'
    Assert-True ($text -like '*見立て: 問題は見当たりません*') '停滞 1 回では判定しない'
    Assert-True ($text -like '*==== キーの時系列 (タップホールドの手がかり) ====*') 'キーの節'
    Assert-True ($text -like '*A *離す*155*長押し (150 ms 以上)*') 'A の押下時間'
    Assert-True ($text -like '*Ctrl*押す*他キーと同時に出力 (ホールド判定)*') 'Ctrl の備考'
    Assert-True ($text -like '*==== AML (オートマウスレイヤー) ====*') 'AML の節'
    Assert-True ($text -like '*ボタン 1 押す*AML 中 (クリック)*') 'AML のクリック'
    Assert-True ($text -like '*==== ホイール ====*上 0 / 下 2 / 右 1 / 左 0*') 'ホイール'
    Assert-True ($text -like '*==== マーク ====*1: 15.000 秒*') 'マーク'
    Assert-True ($text -like '*記録: sample.csv*') '記録のパス'
    $short = Format-ImReport $a $rec 10 2
    Assert-True (($short -join "`n") -like '*ほか * 件 (.txt に全件)*') '行数の上限'
    # デバイスの一覧が無い記録 (CSV だけ) でも分析できる
    $bare = @{ Started = ''; DurationMs = 0; Devices = @(); Connected = @(); Rows = $rec.Rows; Marks = @(); Paths = @{ Csv = ''; Json = '' } }
    $b = Invoke-ImAnalysis $bare @{ ScanTable = $imScan }
    Assert-Equal 2 @($b.Devices).Count
    Assert-True ((Format-ImReport $b $bare 10) -join "`n" -like '*(日時不明)*')
}

Test-Case 'ライブログ: 移動はまとめ、キー・ボタン・ホイールはそのまま。-ShowMotion では 1 件ずつ' {
    $devices = New-ImTestDevices
    $byId = @{}
    foreach ($d in $devices) { $byId[[int]$d.Id] = $d }
    $state = New-ImLiveLog $false 300 $imScan
    $lines = @()
    foreach ($r in (New-ImMotionRows 0 15 20)) { $lines += (Add-ImLiveEvent $state $r $byId) }
    Assert-Equal 0 $lines.Count '移動は区間が閉じるまで出ない'
    $lines += (Add-ImLiveEvent $state (New-ImKeyRowByUsage 290 0x04 $false) $byId)
    Assert-Equal 1 $lines.Count
    Assert-True ($lines[0] -like '*0.290  #1 LisM (BLE)*A 押す') $lines[0]
    $lines += (Add-ImLiveEvent $state (New-ImKeyRowByUsage 290 0x04 $false) $byId)
    Assert-Equal 1 $lines.Count 'オートリピートは出さない'
    $lines += (Add-ImLiveEvent $state (New-ImKeyRowByUsage 400 0x04 $true) $byId)
    Assert-True ($lines[1] -like '*A 離す (押下 110 ms)') $lines[1]
    $lines += (Add-ImLiveEvent $state (New-ImMouseRow 450 0 0 0x0001 0 0 2) $byId)
    Assert-True ($lines[2] -like '*#2 LisM (BLE)*ボタン 1 押す (+50 ms)') $lines[2]
    $lines += (Add-ImLiveEvent $state (New-ImMouseRow 460 0 0 0 -120 0 2) $byId)
    Assert-True ($lines[3] -like '*ホイール -120') $lines[3]
    $early = Complete-ImLiveLog $state 500 $byId $false
    Assert-Equal 0 @($early).Count 'まだ 300 ms たっていない'
    $done = Complete-ImLiveLog $state 700 $byId $false
    $done = @($done)
    Assert-Equal 1 $done.Count
    Assert-True ($done[0] -like '*0.000  #2 LisM (BLE)*ボール 0.3 秒  20 件  X +60 / Y -20  間隔 中央 15.0 ms / 最大 15.0 ms') $done[0]
    # 間が空いたら区間を分ける
    [void](Add-ImLiveEvent $state (New-ImMouseRow 1000 1 1 0 0 0 2) $byId)
    $split = Add-ImLiveEvent $state (New-ImMouseRow 1400 1 1 0 0 0 2) $byId
    Assert-Equal 1 @($split).Count
    Assert-True ($split[0] -like '*ボール 0.0 秒  1 件*')
    $forced = Complete-ImLiveLog $state 1400 $byId $true
    Assert-Equal 1 @($forced).Count '強制的に閉じる'
    # 1 件ずつ
    $each = New-ImLiveLog $true 300 $imScan
    $lines = @()
    foreach ($r in (New-ImMotionRows 0 15 20)) { $lines += (Add-ImLiveEvent $each $r $byId) }
    Assert-Equal 20 $lines.Count
    Assert-True ($lines[1] -like '*X +3 / Y -1 (Δ 15.0 ms)') $lines[1]
    $nothing = Complete-ImLiveLog $each 9999 $byId $true
    Assert-Equal 0 @($nothing).Count '1 件ずつのときはまとめの行は無い'
}

# ---------------------------------------------------------------------------
# 入口のスクリプト (別のプロセスで実行)
# ---------------------------------------------------------------------------

function Invoke-ImEntry([string[]]$Arguments) {
    $out = & $script:ImHostExe -NoProfile -ExecutionPolicy Bypass -File $script:ImEntry @Arguments 2>&1
    return @{ Code = $LASTEXITCODE; Output = ($out | Out-String) }
}

Test-Case '入口: -Analyze で記録ファイルを分析して報告を保存する (終了コード 0)' {
    $dir = New-ImTempDir
    try {
        $sample = New-ImSampleRecording $dir
        $report = Join-Path $dir 'report.txt'
        $r = Invoke-ImEntry @('-Analyze', $sample.Csv, '-Report', $report)
        Assert-Equal 0 $r.Code ('終了コード。出力: ' + $r.Output)
        Assert-True (Test-Path -LiteralPath $report) '報告が保存される'
        $text = [System.IO.File]::ReadAllText($report, [System.Text.Encoding]::UTF8)
        Assert-True ($text -like '*input-monitor 2026-10-02 12:34:56*記録 21.5 秒*') $text
        Assert-True ($text -like '*LisM (BLE)*') 'デバイスのラベル'
        Assert-True ($text -like '*停滞 → まとめて到着: 1 回*') '停滞'
        Assert-True ($r.Output -like '*報告を保存しました*') $r.Output
        # 報告の既定の保存先は記録と同じ名前の .txt
        $r2 = Invoke-ImEntry @('-Analyze', $sample.Json)
        Assert-Equal 0 $r2.Code $r2.Output
        Assert-True (Test-Path -LiteralPath (Join-Path $dir 'sample.txt'))
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force
    }
}

Test-Case '入口: 無い記録ファイルは失敗 (終了コード 1)、イベントの無い記録は 2' {
    $dir = New-ImTempDir
    try {
        $r = Invoke-ImEntry @('-Analyze', (Join-Path $dir 'nothing.csv'))
        Assert-Equal 1 $r.Code $r.Output
        Assert-True ($r.Output -like '*失敗: 記録のファイルがありません*') $r.Output
        $empty = Join-Path $dir 'empty.csv'
        Export-ImCsv @() @() $empty $imScan
        $r2 = Invoke-ImEntry @('-Analyze', $empty)
        Assert-Equal 2 $r2.Code $r2.Output
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force
    }
}

if (-not $script:IsWindowsHost) {
    Test-Case '入口: Windows 以外では記録できない (終了コード 1)' {
        $r = Invoke-ImEntry @('-Seconds', '1')
        Assert-Equal 1 $r.Code $r.Output
        Assert-True ($r.Output -like '*失敗: 記録は Windows でのみできます*') $r.Output
    }
}
