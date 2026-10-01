# ZMK Studio の読み出し検査 (zmk-studio.ps1) のテスト。偽の Studio (fake-devices.ps1) を使う

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'results.ps1')
. (Join-Path $script:KcLib 'qmk.ps1')
. (Join-Path $script:KcLib 'zmk-studio.ps1')
. (Join-Path $script:TestsDir 'fake-devices.ps1')

$common = Get-KcExpected 'common' $script:ExpectedDir
$zmkExpected = @{}
foreach ($id in @('lism', 'kukey42', 'aroundfortyrb', 'pyuron')) {
    $e = Get-KcExpected $id $script:ExpectedDir
    $zmkExpected[[string]$e.device.product] = $e
}

function Invoke-FakeZmkReadout($Fake, $Preferred = $null) {
    $session = New-KcStudioSession $Fake.Transport
    $r = New-KcResultList
    $chosen = Invoke-KcZmkReadout -Session $session -ExpectedByName $zmkExpected -Common $common -Results $r -Preferred $Preferred
    return @{ Results = $r; Expected = $chosen }
}

function Get-ZmkResult($Results, [string]$Item) {
    $r = @($Results | Where-Object { $_.Item -eq $Item })
    if ($r.Count -eq 0) {
        throw "結果に $Item がありません"
    }
    return $r[0]
}

Test-Case 'varint と zigzag' {
    foreach ($v in @(0, 1, 127, 128, 300, 16383, 16384, 0x7FFFFFFF, 0x0307004F)) {
        $bytes = ConvertTo-KcVarint ([uint64]$v)
        $f = ConvertFrom-KcProtobuf ([byte[]]((New-KcPbVarint 2 $v)))
        Assert-Equal ([uint64]$v) (Get-KcPbUInt $f 2) "varint $v"
        Assert-True ($bytes.Length -ge 1)
    }
    foreach ($v in @(0, 1, -1, 2, -2, 12345, -12345)) {
        Assert-Equal $v (ConvertFrom-KcZigZag (ConvertTo-KcZigZag $v)) "zigzag $v"
    }
    Assert-Equal 1 (ConvertTo-KcZigZag -1)
    Assert-Equal 4 (ConvertTo-KcZigZag 2)
}

Test-Case 'protobuf: 入れ子・packed / unpacked の repeated' {
    $inner = Join-KcBytes @((New-KcPbVarint 1 7), (New-KcPbBytes 2 ([System.Text.Encoding]::UTF8.GetBytes('名前'))))
    $msg = Join-KcBytes @((New-KcPbBytes 3 $inner), (New-KcPbVarint 4 5), (New-KcPbVarint 4 6))
    $f = ConvertFrom-KcProtobuf $msg
    $g = ConvertFrom-KcProtobuf (Get-KcPbMessage $f 3)
    Assert-Equal 7 (Get-KcPbUInt $g 1)
    Assert-Equal '名前' (Get-KcPbString $g 2)
    Assert-Equal '5,6' ((Get-KcPbRepeatedUInt $f 4) -join ',')
    $packed = New-KcPbBytes 4 (Join-KcBytes @((ConvertTo-KcVarint 300), (ConvertTo-KcVarint 1)))
    Assert-Equal '300,1' ((Get-KcPbRepeatedUInt (ConvertFrom-KcProtobuf $packed) 4) -join ',')
    Assert-Equal 0 (Get-KcPbUInt $g 9) '無いフィールドは 0'
    Assert-Throws { ConvertFrom-KcProtobuf ([byte[]](0x0A, 0x05, 0x01)) } '*途中で切れています*'
}

Test-Case 'フレーム: エスケープと、分かれて届いたフレーム' {
    $payload = [byte[]](0x01, 0xAB, 0x02, 0xAC, 0xAD, 0x03)
    $frame = ConvertTo-KcStudioFrame $payload
    Assert-Equal 'AB 01 AC AB 02 AC AC AC AD 03 AD' ((@($frame) | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
    $d = New-KcStudioFrameDecoder
    Add-KcStudioFrameBytes $d ([byte[]](0x55, 0x66))            # SOF の前のごみは捨てる
    for ($i = 0; $i -lt $frame.Length; $i += 3) {
        Add-KcStudioFrameBytes $d ([byte[]]$frame[$i..([math]::Min($i + 2, $frame.Length - 1))])
    }
    Add-KcStudioFrameBytes $d (ConvertTo-KcStudioFrame ([byte[]](0x09)))
    Assert-Equal 2 $d.Frames.Count
    Assert-Equal '1,171,2,172,173,3' (([byte[]]$d.Frames.Dequeue()) -join ',')
    Assert-Equal '9' (([byte[]]$d.Frames.Dequeue()) -join ',')
}

Test-Case '要求のバイト列 (zmk-studio-messages の定義どおり)' {
    $r = $script:KcStudioRequests.GetKeymap
    $bytes = New-KcStudioRequest 5 $r.Subsystem (& $r.Inner)
    Assert-Equal '08 05 2A 02 08 01' ((@($bytes) | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
    $r = $script:KcStudioRequests.GetDeviceInfo
    Assert-Equal '08 01 1A 02 08 01' ((@(New-KcStudioRequest 1 $r.Subsystem (& $r.Inner)) | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
    $details = New-KcStudioRequest 4 4 (New-KcPbBytes 2 (New-KcPbVarint 1 300))
    Assert-Equal '08 04 22 05 12 03 08 AC 02' ((@($details) | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
}

Test-Case 'LisM: 期待値どおりなら PASS (通知が挟まり、少しずつ届いても読める)' {
    $fake = New-FakeStudio $zmkExpected['LisM'] $common
    $out = Invoke-FakeZmkReadout $fake
    $r = $out.Results
    Assert-Equal 'lism' $out.Expected.id
    Assert-Equal '' ((@($r | Where-Object { $_.Status -eq 'FAIL' -or $_.Status -eq 'WARN' -or $_.Status -eq 'SKIP' }) | ForEach-Object { $_.Item }) -join ', ')
    Assert-Equal 'PASS' (Get-ZmkResult $r 'キーマップ').Status
    Assert-Equal '全 420 セルが一致' (Get-ZmkResult $r 'キーマップ').Actual
    Assert-Equal '42-Key Layout' (Get-ZmkResult $r '物理レイアウト').Actual
    foreach ($req in $fake.Requests) {
        Assert-True (@('3.1', '3.2', '4.1', '4.2', '5.1', '5.3', '5.6') -contains $req) "読み取り以外の RPC: $req"
    }
}

Test-Case 'キーを 1 つ変えると、その位置だけ FAIL' {
    $fake = New-FakeStudio $zmkExpected['LisM'] $common
    $fake.Keymap[0][10] = @{ b = 'Key Press'; p1 = 0x00070004; p2 = 0 }
    $fake.Keymap[2][1] = @{ b = 'None'; p1 = 0; p2 = 0 }
    $r = (Invoke-FakeZmkReadout $fake).Results
    $km = Get-ZmkResult $r 'キーマップ'
    Assert-Equal 'FAIL' $km.Status
    Assert-Equal 2 @($km.Details).Count
    Assert-Equal 'L0 BASE_QWERTY / 位置 10 (A): 期待 &mt LEFT_CONTROL A / 実際 &kp A' $km.Details[0]
    Assert-Equal 'L2 VIM_NORMAL_BASE / 位置 1 (W): 期待 &mm_vim_w / 実際 &none' $km.Details[1]
}

Test-Case '物理レイアウトの切り替え・レイヤーの並べ替え・未保存の変更' {
    $fake = New-FakeStudio $zmkExpected['LisM'] $common
    $fake.Active = 1
    $fake.Unsaved = $true
    $fake.LayerIds = @(0, 1, 2, 3, 4, 5, 6, 7, 9, 8)
    $r = (Invoke-FakeZmkReadout $fake).Results
    Assert-Equal 'FAIL' (Get-ZmkResult $r '物理レイアウト').Status
    Assert-Equal 'WARN' (Get-ZmkResult $r 'レイヤーの順番').Status
    Assert-Equal 'WARN' (Get-ZmkResult $r '未保存の変更').Status
}

Test-Case '応答が無いときは USB 出力への切り替えを案内する' {
    $fake = New-FakeStudio $zmkExpected['LisM'] $common
    $fake.Silent = $true
    $r = (Invoke-FakeZmkReadout $fake).Results
    $c = Get-ZmkResult $r '接続'
    Assert-Equal 'SKIP' $c.Status
    Assert-True ($c.Hint -like '*OUT_USB*') $c.Hint
}

Test-Case 'つないだ機種がメニューで選んだ機種と違うときは、つないだ機種で検査する' {
    $fake = New-FakeStudio $zmkExpected['KUKEY42'] $common
    $out = Invoke-FakeZmkReadout $fake $zmkExpected['LisM']
    Assert-Equal 'kukey42' $out.Expected.id
    Assert-Equal 'WARN' (Get-ZmkResult $out.Results '機種').Status
    Assert-Equal 'PASS' (Get-ZmkResult $out.Results 'キーマップ').Status
}

Test-Case '全機種: 期待値どおりなら キーマップが PASS' {
    foreach ($name in @('KUKEY42', 'AroundFortyRB', 'Pyuron')) {
        $fake = New-FakeStudio $zmkExpected[$name] $common
        $fake.Notify = $false
        $fake.Chunk = 64
        $r = (Invoke-FakeZmkReadout $fake).Results
        Assert-Equal 'PASS' (Get-ZmkResult $r 'キーマップ').Status $name
    }
}
