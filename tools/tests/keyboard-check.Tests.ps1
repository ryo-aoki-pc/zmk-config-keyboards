# 入口のスクリプト (tools/scripts/keyboard-check.ps1) を別のプロセスで実行するテスト (キーボードはつながっていない前提)

. (Join-Path $script:KcLib 'expected.ps1')

$script:KcEntry = Join-Path $script:ToolsDir 'scripts\keyboard-check.ps1'
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

Test-Case 'HoldTap: ZMK のキーボードだけ。KQ-mini では案内して終了コード 0' {
    $r = Invoke-KcEntry @('-Keyboard', 'KqMini', '-Mode', 'HoldTap')
    Assert-Equal 0 $r.Code ('終了コード。出力: ' + $r.Output)
    Assert-True ($r.Output -like '*ZMK のキーボードだけです*') $r.Output
}

Test-Case 'HoldTap: Windows 以外では、ウィンドウを開かずに終了コード 0' {
    if ($script:IsWindowsHost) { return }
    $r = Invoke-KcEntry @('-Keyboard', 'LisM', '-Mode', 'HoldTap')
    Assert-Equal 0 $r.Code ('終了コード。出力: ' + $r.Output)
    Assert-True ($r.Output -like '*Windows でのみ*') $r.Output
}

Test-Case '機種の一覧: ZMK Studio のデバイス名が期待値と合う' {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:KcEntry, [ref]$null, [ref]$null)
    $tables = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)
    $seen = 0
    foreach ($t in $tables) {
        $kv = @{}
        foreach ($pair in $t.KeyValuePairs) {
            $kv[[string]$pair.Item1.Value] = $pair.Item2.Extent.Text.Trim("'")
        }
        if (-not $kv.ContainsKey('Id') -or -not $kv.ContainsKey('Key')) {
            continue
        }
        $e = Get-KcExpected $kv['Id'] $script:ExpectedDir
        if ($e.kind -eq 'zmk') {
            Assert-Equal ([string]$e.device.product) $kv['Product'] $kv['Id']
            $seen++
        }
    }
    Assert-Equal 6 $seen 'ZMK の機種の数'
}
