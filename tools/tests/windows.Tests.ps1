# C# ヘルパーのコンパイル (Windows PowerShell 5.1 では C# 5 でコンパイルされる) のテスト

. (Join-Path $script:KcLib 'rawhid.ps1')

Test-Case 'RawHid.cs をコンパイルできる' {
    Import-KcCSharp 'RawHid.cs' 'KcRawHid'
    Assert-True ('KcRawHid' -as [type]) 'KcRawHid 型'
}

Test-Case 'RawHid: 開けないパスは例外になる' -WindowsOnly {
    Import-KcCSharp 'RawHid.cs' 'KcRawHid'
    Assert-Throws { [KcRawHid]::Query('\\?\HID#VID_0000&PID_0000#nothing', [byte[]](0x01), 100, 1) } '*cannot open*'
    Assert-Equal '' ([KcRawHid]::GetProductString('\\?\HID#VID_0000&PID_0000#nothing'))
}
