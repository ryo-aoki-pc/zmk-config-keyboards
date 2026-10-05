# 実機なしのシミュレータ。期待値はシナリオに固定し、実行結果から生成しない。
. (Join-Path $script:KcLib 'keyboard-sim.ps1')

$script:KsFixtureJson = @'
{
  "schema": 1,
  "scenarios": [{
    "name": "Q < & > の押下と解放",
    "model": {
      "schema_version": 1, "id": "test", "engine": "zmk", "sources": [],
      "layers": [{"index": 0, "name": "BASE"}],
      "keys": [{"pos": 0, "hand": "L", "present": true, "on": {"0": {"kind": "kp", "usage": 20, "mods": 0}}}],
      "behaviors": {}, "settings": {}, "pointer": null
    },
    "events": [{"t": 0, "type": "press", "pos": 0}, {"t": 20, "type": "release", "pos": 0}],
    "end_ms": 30,
    "expect": {
      "keys": [{"t": 0, "usage": 20, "down": true, "mods": 0}, {"t": 20, "usage": 20, "down": false, "mods": 0}],
      "layers": [], "mouse": [], "state": {"layers": [0], "keys": [], "buttons": 0}
    }
  }]
}
'@

function New-KsFixture {
    return ($script:KsFixtureJson | ConvertFrom-Json).scenarios[0]
}

# CLI は別プロセスで実行し、exit と JSON/JUnit の両方を確認する。
function Invoke-KsFixtureCli([string]$Json, [switch]$OverwriteInput, [string]$Board = '') {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('keyboard-sim-test-' + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($dir)
    try {
        $inputFile = Join-Path $dir 'scenario.json'
        $reportFile = Join-Path $dir 'report.json'
        $xmlFile = Join-Path $dir 'report.xml'
        [System.IO.File]::WriteAllText($inputFile, $Json, (New-Object System.Text.UTF8Encoding($false)))
        if ($OverwriteInput) { $reportFile = $inputFile }
        $exe = (Get-Process -Id $PID).Path
        $argsList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
            (Join-Path $script:ToolsDir 'scripts/keyboard-sim.ps1'), '-Scenario', $inputFile,
            '-ReportJson', $reportFile, '-ReportJUnit', $xmlFile)
        if ($Board) { $argsList += @('-Board', $Board) }
        $output = @(& $exe @argsList 2>&1)
        $code = $LASTEXITCODE
        $reportText = ''
        $report = $null
        $xml = $null
        if ([System.IO.File]::Exists($reportFile)) {
            $reportText = [System.IO.File]::ReadAllText($reportFile)
            $report = $reportText | ConvertFrom-Json
        }
        if ([System.IO.File]::Exists($xmlFile)) { $xml = [xml][System.IO.File]::ReadAllText($xmlFile) }
        return [pscustomobject]@{ Code = $code; Report = $report; Json = $reportText; Xml = $xml
            Input = [System.IO.File]::ReadAllText($inputFile); Output = ($output -join "`n") }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force
    }
}

Test-Case '固定シナリオ: 全8機種のキーとLisMの複合操作を検証する' {
    $files = @(Get-ChildItem (Join-Path $script:ToolsDir 'simulator/scenarios') -Filter '*.json' -File | Sort-Object Name)
    $count = 0
    $boards = @{}
    $failures = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in $files) {
        $suite = [System.IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
        Assert-Equal 1 $suite.schema
        foreach ($scenario in $suite.scenarios) {
            $result = Invoke-KcSimScenario $scenario
            if ($result.status -ne 'passed') { $failures.Add($scenario.name + ': ' + $result.error) }
            $boards[$scenario.board] = $true
            $count++
        }
    }
    Assert-Equal 0 $failures.Count ($failures.ToArray() -join "`n")
    Assert-True ($count -ge 50) ('検証したシナリオ: ' + $count)
    foreach ($board in @('lism', 'aroundfortyrb', 'kukey42', 'roba', 'pyuron', 'torabo-tsuki-lp', 'keyball39', 'kq-mini')) {
        Assert-True $boards.ContainsKey($board) ('未検証の機種: ' + $board)
    }
}

Test-Case '期待値: キーを1つ変えると失敗し実際の出力を残す' {
    $scenario = New-KsFixture
    $scenario.expect.keys[0].usage = 21
    $result = Invoke-KcSimScenario $scenario
    Assert-Equal 'failed' $result.status
    Assert-True ($result.error.Contains('expect.keys[0].usage')) $result.error
    Assert-Equal 20 $result.actual.keys[0].usage
}

Test-Case '期待値: 空・未知の項目・入力なしを成功にしない' {
    $scenario = New-KsFixture
    $scenario.expect = [pscustomobject]@{}
    Assert-Equal 'failed' (Invoke-KcSimScenario $scenario).status
    $scenario = New-KsFixture
    $scenario.expect = [pscustomobject]@{ keyz = @() }
    Assert-Equal 'failed' (Invoke-KcSimScenario $scenario).status
    $scenario = New-KsFixture
    $scenario.events = @()
    Assert-Equal 'failed' (Invoke-KcSimScenario $scenario).status
    $scenario = New-KsFixture
    $scenario.expect = [pscustomobject]@{ Keys = @() }
    Assert-Equal 'failed' (Invoke-KcSimScenario $scenario).status
    $scenario = New-KsFixture
    $scenario.expect.keys[0].down = 'true'
    Assert-Equal 'failed' (Invoke-KcSimScenario $scenario).status
    $scenario = New-KsFixture
    $scenario.expect.state.buttons = @(0)
    $result = Invoke-KcSimScenario $scenario
    Assert-Equal 'failed' $result.status
    Assert-True ($result.error.Contains('expect.state.buttons')) $result.error
    $scenario = New-KsFixture
    $scenario.expect = [pscustomobject]@{ state = [pscustomobject]@{ layers = @(0) } }
    Assert-Equal 'passed' (Invoke-KcSimScenario $scenario).status
}

Test-Case '入力検査: 未対応のビヘイビア・時刻逆順・二重押下・存在しない位置は失敗' {
    $scenario = New-KsFixture
    $scenario.model.keys[0].on.'0'.kind = 'other'
    Assert-Equal 'failed' (Invoke-KcSimScenario $scenario).status
    $scenario = New-KsFixture
    $scenario.events[1].t = -1
    Assert-Equal 'failed' (Invoke-KcSimScenario $scenario).status
    $scenario = New-KsFixture
    $scenario.events[1].type = 'press'
    Assert-Equal 'failed' (Invoke-KcSimScenario $scenario).status
    $scenario = New-KsFixture
    $scenario.events[0].pos = 999
    Assert-Equal 'failed' (Invoke-KcSimScenario $scenario).status
    $scenario = New-KsFixture
    $scenario.events[0].t = 0.5
    Assert-Equal 'failed' (Invoke-KcSimScenario $scenario).status
}

Test-Case 'CLI: 成功は終了0、JSONは決定的、JUnitはXML文字をエスケープする' {
    $first = Invoke-KsFixtureCli $script:KsFixtureJson
    $second = Invoke-KsFixtureCli $script:KsFixtureJson
    Assert-Equal 0 $first.Code $first.Output
    Assert-Equal 0 $second.Code $second.Output
    Assert-Equal 1 $first.Report.passed
    Assert-Equal 0 $first.Report.failed
    Assert-Equal $first.Json $second.Json '同じ入力のレポート'
    Assert-Equal '1' $first.Xml.testsuite.tests
    Assert-Equal '0' $first.Xml.testsuite.failures
    Assert-Equal 'Q < & > の押下と解放' $first.Xml.testsuite.testcase.name
}

Test-Case 'CLI: 比較失敗は終了1とJUnit failureになる' {
    $suite = $script:KsFixtureJson | ConvertFrom-Json
    $suite.scenarios[0].expect.keys[0].usage = 21
    $result = Invoke-KsFixtureCli ($suite | ConvertTo-Json -Depth 100)
    Assert-Equal 1 $result.Code $result.Output
    Assert-Equal 0 $result.Report.passed
    Assert-Equal 1 $result.Report.failed
    Assert-Equal 'failed' $result.Report.scenarios[0].status
    Assert-True ($null -ne $result.Xml.testsuite.testcase.failure)
}

Test-Case 'CLI: 壊れたJSON・シナリオ0件・抽出後0件は終了1' {
    foreach ($json in @('{broken', '{"schema":1,"scenarios":[]}')) {
        $result = Invoke-KsFixtureCli $json
        Assert-Equal 1 $result.Code $result.Output
        Assert-Equal 0 $result.Report.passed
        Assert-Equal 1 $result.Report.failed
        Assert-True (-not [string]::IsNullOrWhiteSpace($result.Report.error))
        Assert-Equal '1' $result.Xml.testsuite.failures
    }
    $result = Invoke-KsFixtureCli $script:KsFixtureJson -Board 'nonexistent'
    Assert-Equal 1 $result.Code $result.Output
    Assert-Equal 0 $result.Report.passed
    Assert-Equal 1 $result.Report.failed
}

Test-Case 'CLI: 入力JSONをレポートで上書きしない' {
    $result = Invoke-KsFixtureCli $script:KsFixtureJson -OverwriteInput
    Assert-Equal 1 $result.Code $result.Output
    Assert-Equal $script:KsFixtureJson $result.Input
}

Test-Case '未対応の実設定: Bluetooth切替とKUKEY42のドライバ内スクロールを成功にしない' {
    $scenarios = @'
[
  {"name":"Bluetooth切替", "board":"lism", "end_ms":100,
   "events":[{"t":0,"type":"press","pos":39},{"t":10,"type":"press","pos":0},{"t":20,"type":"release","pos":0},{"t":30,"type":"release","pos":39}],
   "expect":{"keys":[]}},
  {"name":"ドライバ内スクロール", "board":"kukey42", "end_ms":600,
   "events":[{"t":300,"type":"move","side":"right","x":40,"y":0},{"t":320,"type":"press","pos":12},{"t":520,"type":"move","side":"right","x":0,"y":32},{"t":550,"type":"release","pos":12}],
   "expect":{"keys":[]}},
  {"name":"キーとホイールの混在", "board":"keyball-kq-mini", "end_ms":700,
   "events":[{"t":300,"type":"move","side":"right","x":0,"y":40},{"t":320,"type":"press","pos":12},{"t":330,"type":"press","pos":10},{"t":600,"type":"move","side":"right","x":0,"y":32},{"t":610,"type":"release","pos":10},{"t":620,"type":"release","pos":12}],
   "expect":{"keys":[]}}
]
'@ | ConvertFrom-Json
    foreach ($scenario in $scenarios) {
        $result = Invoke-KcSimScenario $scenario
        Assert-Equal 'failed' $result.status $scenario.name
        if ($scenario.board -eq 'lism') {
            Assert-True ($result.error.Contains('Unsupported zmk behavior at position 0: other &bt BT_SEL 0')) $result.error
        } elseif ($scenario.board -eq 'kukey42') {
            Assert-True ($result.error.Contains("This driver's raw scroll conversion is not modeled")) $result.error
        } else {
            Assert-Equal 'KQ-mini 連携のホイールとキーの混在には対応していません' $result.error
        }
    }
}

Test-Case 'CLI: 追跡ファイルとsubmodule内へのレポート出力を拒否する' {
    # 保護が壊れていても実際のソースを上書きしないよう、最小の一時チェックアウトで実行する。
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('keyboard-sim-path-' + [guid]::NewGuid().ToString('N'))
    $scriptDir = Join-Path $dir 'tools/scripts'
    $libDir = Join-Path $dir 'tools/lib/keyboard-check'
    [void][System.IO.Directory]::CreateDirectory($scriptDir)
    [void][System.IO.Directory]::CreateDirectory($libDir)
    try {
        $cli = Join-Path $scriptDir 'keyboard-sim.ps1'
        Copy-Item -LiteralPath (Join-Path $script:ToolsDir 'scripts/keyboard-sim.ps1') -Destination $cli
        foreach ($name in @('keyboard-sim.ps1', 'hold-tap-sim.ps1', 'HoldTapSim.cs', 'KeyboardSim.cs', 'QmkOverrideSim.cs', 'PointerSim.cs', 'PointerPeripheral.cs')) {
            Copy-Item -LiteralPath (Join-Path $script:KcLib $name) -Destination (Join-Path $libDir $name)
        }
        $inputFile = Join-Path $dir 'scenario.json'
        [System.IO.File]::WriteAllText($inputFile, $script:KsFixtureJson, (New-Object System.Text.UTF8Encoding($false)))
        $source = Join-Path $dir 'README.md'
        [System.IO.File]::WriteAllText($source, 'preserve parent source')
        & git -C $dir init --quiet
        Assert-Equal 0 $LASTEXITCODE '一時リポジトリの初期化'
        & git -C $dir add -- README.md
        Assert-Equal 0 $LASTEXITCODE '保護対象を追跡する'
        $submodule = Join-Path $dir 'firmware'
        [void][System.IO.Directory]::CreateDirectory($submodule)
        # 現在のガードはgitlink名だけでなく .git のある下位チェックアウトも保護する。
        & git -C $submodule init --quiet
        Assert-Equal 0 $LASTEXITCODE '下位チェックアウトの初期化'
        $nestedSource = Join-Path $submodule 'keymap.keymap'
        [System.IO.File]::WriteAllText($nestedSource, 'preserve firmware source')
        $exe = (Get-Process -Id $PID).Path
        foreach ($target in @($source, $nestedSource)) {
            $before = [System.IO.File]::ReadAllText($target)
            $output = @(& $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli -Scenario $inputFile -ReportJson $target 2>&1)
            Assert-Equal 1 $LASTEXITCODE ($output -join "`n")
            Assert-Equal $before ([System.IO.File]::ReadAllText($target)) '元の内容を維持する'
            if ($target -eq $source) {
                Assert-True (($output -join "`n").Contains('追跡ファイルにレポートを書き込めません')) ($output -join "`n")
            } else {
                Assert-True (($output -join "`n").Contains('submodule 内にレポートを書き込めません')) ($output -join "`n")
            }
        }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force
    }
}
