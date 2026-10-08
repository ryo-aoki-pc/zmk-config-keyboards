# Keyball の診断 (tools/scripts/keyball-check.ps1) を別のプロセスで実行するテスト (Keyball は PC に直結していない前提)

$script:KbcEntry = Join-Path $script:ToolsDir 'scripts\keyball-check.ps1'
$script:KbcHostExe = (Get-Process -Id $PID).Path

# 見つからないときの案内の途中で、KQ-mini の有無を調べる .Count が StrictMode の例外になっていた
Test-Case 'Keyball が見つからなければ、案内して終了コード 2' -WindowsOnly {
    $out = & $script:KbcHostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:KbcEntry 2>&1
    $code = $LASTEXITCODE
    $text = $out | Out-String
    Assert-Equal 2 $code ('終了コード。出力: ' + $text)
    Assert-True ($text -like '*VIA インターフェイスが見つかりません*') $text
    Assert-True ($text -like '*Keyball を PC に直接つな*') ('直結の案内: ' + $text)
}
