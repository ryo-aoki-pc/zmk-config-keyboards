# C# ヘルパーのコンパイル (Windows PowerShell 5.1 では C# 5 でコンパイルされる) のテスト

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'rawhid.ps1')
. (Join-Path $script:KcLib 'input-test.ps1')

Test-Case 'RawHid.cs をコンパイルできる' {
    Import-KcCSharp 'RawHid.cs' 'KcRawHid'
    Assert-True ('KcRawHid' -as [type]) 'KcRawHid 型'
}

Test-Case 'RawHid: 開けないパスは例外になる' -WindowsOnly {
    Import-KcCSharp 'RawHid.cs' 'KcRawHid'
    Assert-Throws { [KcRawHid]::Query('\\?\HID#VID_0000&PID_0000#nothing', [byte[]](0x01), 100, 1) } '*cannot open*'
    Assert-Equal '' ([KcRawHid]::GetProductString('\\?\HID#VID_0000&PID_0000#nothing'))
}

Test-Case 'InputTestForm.cs をコンパイルして、ウィンドウを作れる' -WindowsOnly {
    Import-KcInputForm
    $form = New-Object KcInputTestForm
    try {
        $form.SetButtonTexts('次へ', 'やり直し', 'スキップ', '中止')
        $form.SetKeys([int[]]@(0, 1), [double[]]@(0, 1), [double[]]@(0, 0), [double[]]@(1, 1), [double[]]@(1, 1), [string[]]@('Q', 'W'))
        $form.SetKeyState(1, 2)
        $form.SetTexts('t', 'i', 'd')
        Assert-Equal '' $form.TakeAction()
        Assert-Equal 0 @($form.TakeEvents()).Count
    } finally {
        $form.Dispose()
    }
}

# RAWINPUT のバイト列 (64 ビット: ヘッダー 24 バイト)
function New-RawInputBytes([int]$Type, [long]$Device, [byte[]]$Body, [int]$PtrSize = 8) {
    $header = 8 + 2 * $PtrSize
    $b = New-Object byte[] ($header + $Body.Length)
    [BitConverter]::GetBytes([int]$Type).CopyTo($b, 0)
    if ($PtrSize -eq 8) { [BitConverter]::GetBytes([long]$Device).CopyTo($b, 8) } else { [BitConverter]::GetBytes([int]$Device).CopyTo($b, 8) }
    $Body.CopyTo($b, $header)
    return , $b
}

Test-Case 'Raw Input の解析: キー (E0 付き) とマウス (移動・ボタン・ホイール)' -WindowsOnly {
    Import-KcInputForm
    $kb = New-Object byte[] 16
    [BitConverter]::GetBytes([uint16]0x5B).CopyTo($kb, 0)
    [BitConverter]::GetBytes([uint16]0x03).CopyTo($kb, 2)       # BREAK | E0
    [BitConverter]::GetBytes([uint16]0x5B).CopyTo($kb, 6)
    $e = [KcRawInputParser]::Parse((New-RawInputBytes 1 0x1234 $kb), 8, 5)
    Assert-Equal 'key' $e.Kind
    Assert-Equal 0x5B $e.Scan
    Assert-Equal 0xE0 $e.Prefix
    Assert-True $e.Break
    Assert-Equal 0x1234 $e.Device

    $ms = New-Object byte[] 24
    [BitConverter]::GetBytes([uint16]0x0401).CopyTo($ms, 4)     # WHEEL | BUTTON_1_DOWN
    [BitConverter]::GetBytes([int16]-120).CopyTo($ms, 6)
    [BitConverter]::GetBytes([int]5).CopyTo($ms, 12)
    [BitConverter]::GetBytes([int]-7).CopyTo($ms, 16)
    $m = [KcRawInputParser]::Parse((New-RawInputBytes 0 0x99 $ms), 8, 6)
    Assert-Equal 'mouse' $m.Kind
    Assert-Equal 5 $m.Dx
    Assert-Equal -7 $m.Dy
    Assert-Equal -120 $m.Wheel
    Assert-Equal 1 $m.Buttons

    $fake = New-Object byte[] 16
    [BitConverter]::GetBytes([uint16]0x2A).CopyTo($fake, 0)
    [BitConverter]::GetBytes([uint16]0x02).CopyTo($fake, 2)     # E0 の左 Shift (偽の Shift) は捨てる
    Assert-Equal $null ([KcRawInputParser]::Parse((New-RawInputBytes 1 1 $fake 4), 4, 7))
    Assert-Equal $null ([KcRawInputParser]::Parse((New-RawInputBytes 1 0 $kb), 8, 7)) '注入された入力 (デバイス 0) は捨てる'
    Assert-Equal 0 $e.TimeUs 'TimeUs はモニター用のウィンドウだけが埋める'
}

Test-Case 'InputTestForm.cs: モニター用のウィンドウ (KcInputMonitorForm) を作れる' -WindowsOnly {
    Import-KcInputForm
    $form = New-Object KcInputMonitorForm('t', '停止', 'マーク', 'クリア', 'hint')
    try {
        $form.AppendLog('x')
        $form.SetStatus('s', 1)
        Assert-Equal '' $form.TakeAction()
        Assert-Equal 0 @($form.TakeEvents()).Count
        Assert-True ($form.NowUs -ge 0) 'NowUs'
        Assert-True (-not $form.IsClosed)
        $form.RequestClose()
    } finally {
        $form.Dispose()
    }
    $list = @([KcInputMonitorForm]::ListDevices())
    foreach ($d in $list) {
        Assert-True ($d.Type -eq 0 -or $d.Type -eq 1) 'キーボードとマウスだけ'
    }
}
