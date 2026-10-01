# 入口のスクリプト (tools/keyboard-check.ps1) を別のプロセスで実行するテスト (キーボードはつながっていない前提)

$script:KcEntry = Join-Path $script:ToolsDir 'keyboard-check.ps1'
$script:KcHostExe = (Get-Process -Id $PID).Path

function Invoke-KcEntry([string[]]$Arguments) {
    $report = Join-Path ([System.IO.Path]::GetTempPath()) ('kc-entry-{0}.txt' -f [guid]::NewGuid())
    $out = & $script:KcHostExe -NoProfile -ExecutionPolicy Bypass -File $script:KcEntry @Arguments -Report $report 2>&1
    $code = $LASTEXITCODE
    $text = ''
    if (Test-Path -LiteralPath $report) {
        $text = [System.IO.File]::ReadAllText($report)
        Remove-Item -LiteralPath $report
    }
    return @{ Code = $code; Output = ($out | Out-String); Report = $text }
}

Test-Case 'ZMK: Studio 版が見つからなければ SKIP と案内 (終了コード 2)' {
    $r = Invoke-KcEntry @('-Keyboard', 'LisM', '-Mode', 'Readout')
    Assert-Equal 2 $r.Code ('終了コード。出力: ' + $r.Output)
    Assert-True ($r.Report -like '*ZMK Studio 版が USB で見つかりません*') $r.Report
    Assert-True ($r.Report -like '*lism_right_central_trackball_studio*') 'Studio 版のファイル名を案内する'
    Assert-True ($r.Report -like '*設定ファイル (参考)*') '設定ファイルの整合も表示する'
}

Test-Case 'KQ-mini: 見つからなければ SKIP、Keyball は直結の案内' {
    $r = Invoke-KcEntry @('-Keyboard', 'KqMini', '-Mode', 'Readout')
    Assert-Equal 2 $r.Code ('終了コード。出力: ' + $r.Output)
    Assert-True ($r.Report -like '*KQ-mini 経由では読めません*') $r.Report
}
