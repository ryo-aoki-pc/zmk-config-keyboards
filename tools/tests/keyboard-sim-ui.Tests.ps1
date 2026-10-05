# シミュレータの画面の流れ。小さい入力ファイルと偽物のウィンドウ・子プロセスで検査する。
. (Join-Path $script:KcLib 'keyboard-sim.ps1')
. (Join-Path $script:KcLib 'keyboard-sim-ui.ps1')
. (Join-Path $script:KcLib 'rawhid.ps1')

$script:SuiFormMethods = @('SetLabels', 'SetBoards', 'SetScenarios', 'SetDetails', 'SetSummary', 'SetBusy',
    'SetKeys', 'SetKeyStates', 'SetReplay', 'SetReplayState', 'SetReportEnabled', 'AppendLog', 'RequestClose')

function New-SuiForm {
    $form = [pscustomobject]@{ Calls = (New-Object System.Collections.ArrayList) }
    foreach ($m in $script:SuiFormMethods) {
        $form | Add-Member -MemberType ScriptMethod -Name $m -Value ([scriptblock]::Create("[void]`$this.Calls.Add((@('$m') + `$args))"))
    }
    return $form
}

function Get-SuiLast($Form, [string]$Name) {
    $found = $null
    foreach ($call in $Form.Calls) { if ($call[0] -eq $Name) { $found = $call } }
    if ($null -eq $found) { throw "$Name が呼ばれていません" }
    return ,$found
}

function New-SuiScenario([string]$Name = 'Q のタップ', [string]$Board = 'lism') {
    $case = @'
{
  "name":"Q のタップ", "board":"lism", "end_ms":30,
  "model":{"schema_version":1,"id":"test","name":"テスト","engine":"zmk","sources":[],
    "layers":[{"index":0,"name":"BASE"}],"behaviors":{},"settings":{},"pointer":null,
    "keys":[
      {"pos":0,"x":0,"y":0,"w":1,"h":1,"present":true,"on":{"0":{"kind":"kp","usage":20,"src":"&kp Q"}}},
      {"pos":1,"x":1,"y":0,"w":1,"h":1,"present":false,"on":{"0":{"kind":"none"}}},
      {"pos":2,"x":2,"y":0.25,"w":1.5,"h":1,"present":true,"on":{"0":{"kind":"kp","usage":26,"src":"&kp W"}}}
    ]},
  "events":[{"t":0,"type":"press","pos":0},{"t":20,"type":"release","pos":0}],
  "expect":{"keys":[{"t":0,"usage":20,"down":true,"mods":0},{"t":20,"usage":20,"down":false,"mods":0}],
    "layers":[],"mouse":[],"state":{"layers":[0],"keys":[],"buttons":0}}
}
'@ | ConvertFrom-Json
    $case.name = $Name
    $case.board = $Board
    return $case
}

function New-SuiChild([bool]$Exited = $false) {
    $child = [pscustomobject]@{ Pending = @(); HasExited = $Exited; ExitCode = 0; Killed = $false; Disposed = $false }
    $child | Add-Member -MemberType ScriptMethod -Name TakeLines -Value {
        $out = $this.Pending
        $this.Pending = @()
        return ,$out
    }
    $child | Add-Member -MemberType ScriptMethod -Name Kill -Value { $this.Killed = $true; $this.HasExited = $true; $this.ExitCode = 1 }
    $child | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed = $true }
    return $child
}

function New-SuiContext {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('keyboard-sim-ui-test-' + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($dir)
    $path = Join-Path $dir 'scenarios.json'
    $cases = @((New-SuiScenario), (New-SuiScenario '別の Q' 'lism'), (New-SuiScenario 'KQ の Q' 'kq-mini'))
    $json = @{ schema = 1; scenarios = $cases } | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
    $world = @{
        Dir = $dir; Path = $path; Form = (New-SuiForm); Child = (New-SuiChild)
        Calls = (New-Object System.Collections.ArrayList); Opened = (New-Object System.Collections.ArrayList)
        FailName = ''; InvalidReport = $false; MissingReport = $false
    }
    $script:SuiWorld = $world
    $world.Ctx = New-KcSimUiContext -Form $world.Form -ScenarioPath $path -Python 'test-python' -ToolsDir $script:ToolsDir `
        -CacheDir (Join-Path $dir 'cache') -NewChild {
            param($InputFile, $ReportFile, $JUnitFile, $Python)
            [void]$script:SuiWorld.Calls.Add(@($InputFile, $ReportFile, $JUnitFile, $Python))
            $suite = [System.IO.File]::ReadAllText($InputFile) | ConvertFrom-Json
            $entries = @(foreach ($case in $suite.scenarios) {
                $failed = $case.name -eq $script:SuiWorld.FailName
                [pscustomobject]@{ name = $case.name; board = $case.board; status = $(if ($failed) { 'failed' } else { 'passed' })
                    error = $(if ($failed) { 'expect.keys: 期待と実際が違います' } else { '' }); actual = $case.expect; sources = @(); decisions = @() }
            })
            $failedCount = @($entries | Where-Object { $_.status -eq 'failed' }).Count
            $report = @{ schema = 1; passed = $entries.Count - $failedCount; failed = $failedCount; scenarios = $entries } | ConvertTo-Json -Depth 100
            if ($script:SuiWorld.InvalidReport) { $report = '{ broken' }
            if (-not $script:SuiWorld.MissingReport) { [System.IO.File]::WriteAllText($ReportFile, $report, (New-Object System.Text.UTF8Encoding($false))) }
            if ($failedCount -gt 0) { $script:SuiWorld.Child.ExitCode = 1 }
            return $script:SuiWorld.Child
        } -GetModel { param($Board, $Python) return (New-SuiScenario).model } `
        -OpenReport { param($Folder) [void]$script:SuiWorld.Opened.Add($Folder) }
    Initialize-KcSimUi $world.Ctx
    return $world
}

function Remove-SuiContext($World) {
    try { Stop-KcSimUi $World.Ctx } finally { Remove-Item -LiteralPath $World.Dir -Recurse -Force }
}

Test-Case 'シナリオ読込: 空・壊れた JSON・重複する機種と名前を拒否する' {
    $w = New-SuiContext
    try {
        $entries = Read-KcSimUiScenarios -Path $w.Path
        Assert-Equal 3 $entries.Count
        Assert-Equal 3 @($entries | Select-Object -ExpandProperty Id -Unique).Count
        foreach ($text in @('{ broken', '{"schema":1,"scenarios":[]}')) {
            [System.IO.File]::WriteAllText($w.Path, $text)
            Assert-Throws { Read-KcSimUiScenarios -Path $w.Path }
        }
        $same = New-SuiScenario
        [System.IO.File]::WriteAllText($w.Path, (@{ schema = 1; scenarios = @($same, $same) } | ConvertTo-Json -Depth 100))
        Assert-Throws { Read-KcSimUiScenarios -Path $w.Path } '*重複*'
    } finally { Remove-SuiContext $w }
}

Test-Case '単件の実行: 選択した入力だけを子に渡し、完了時に結果とレポートを開ける' {
    $w = New-SuiContext
    try {
        Invoke-KcSimUiAction $w.Ctx 'board:lism'
        Invoke-KcSimUiAction $w.Ctx 'scenario:1'
        Invoke-KcSimUiAction $w.Ctx 'run'
        Assert-Equal 'running' $w.Ctx.State.Phase
        Assert-Equal 1 $w.Calls.Count
        $suite = [System.IO.File]::ReadAllText($w.Calls[0][0]) | ConvertFrom-Json
        Assert-Equal 1 $suite.scenarios.Count
        Assert-Equal '別の Q' $suite.scenarios[0].name
        Assert-Equal 'test-python' $w.Calls[0][3]
        Assert-Equal $false (Get-SuiLast $w.Form 'SetReportEnabled')[1]
        Update-KcSimUi $w.Ctx
        Assert-Equal 'running' $w.Ctx.State.Phase '子プロセスの終了を待つ'
        $w.Child.HasExited = $true
        Update-KcSimUi $w.Ctx
        Assert-Equal 'done' $w.Ctx.State.Phase
        Assert-Equal 'passed' $w.Ctx.State.Results['1'].status
        Assert-True $w.Child.Disposed '子プロセスを閉じる'
        Assert-Equal $true (Get-SuiLast $w.Form 'SetReportEnabled')[1]
        Invoke-KcSimUiAction $w.Ctx 'report'
        Assert-Equal 1 $w.Opened.Count
    } finally { Remove-SuiContext $w }
}

Test-Case '機種の全件実行: 期待値に違反した結果と成功した結果を両方残す' {
    $w = New-SuiContext
    try {
        $w.FailName = '別の Q'
        Invoke-KcSimUiAction $w.Ctx 'board:lism'
        Invoke-KcSimUiAction $w.Ctx 'runall'
        $suite = [System.IO.File]::ReadAllText($w.Calls[0][0]) | ConvertFrom-Json
        Assert-Equal 2 $suite.scenarios.Count
        Assert-Equal 'lism,lism' (@($suite.scenarios | ForEach-Object { $_.board }) -join ',')
        $w.Child.HasExited = $true
        Update-KcSimUi $w.Ctx
        Assert-Equal 'passed' $w.Ctx.State.Results['0'].status
        Assert-Equal 'failed' $w.Ctx.State.Results['1'].status
        Assert-True ($w.Ctx.State.Results['1'].error -like '*期待と実際*') '不一致の詳細'
        Assert-Equal 2 $w.Ctx.State.Results.Count
    } finally { Remove-SuiContext $w }
}

Test-Case '実行中は選択・二重実行を受け付けず、中止すると子プロセスを止める' {
    $w = New-SuiContext
    try {
        Invoke-KcSimUiAction $w.Ctx 'board:lism'
        $selected = $w.Ctx.State.Selected
        Invoke-KcSimUiAction $w.Ctx 'run'
        foreach ($action in @('board:kq-mini', 'scenario:2', 'run', 'runall', 'standard')) { Invoke-KcSimUiAction $w.Ctx $action }
        Assert-Equal 'lism' $w.Ctx.State.Board
        Assert-Equal $selected $w.Ctx.State.Selected
        Assert-Equal 1 $w.Calls.Count
        Invoke-KcSimUiAction $w.Ctx 'cancel'
        Assert-Equal 'cancelled' $w.Ctx.State.Phase
        Assert-True $w.Child.Killed '子プロセスを中止'
        Assert-True $w.Child.Disposed '子プロセスを閉じる'
        Assert-Equal 'cancelled' $w.Ctx.State.Results[$selected].status '中止を成功として扱わない'
        Assert-Equal $null $w.Ctx.State.Results[$selected].actual
        Invoke-KcSimUiAction $w.Ctx 'board:kq-mini'
        Assert-Equal 'kq-mini' $w.Ctx.State.Board '中止後は機種を選べる'
    } finally { Remove-SuiContext $w }
}

Test-Case '壊れたレポートと欠落したレポートは成功扱いせず、再実行できる' {
    foreach ($kind in @('InvalidReport', 'MissingReport')) {
        $w = New-SuiContext
        try {
            $w[$kind] = $true
            Invoke-KcSimUiAction $w.Ctx 'run'
            $w.Child.HasExited = $true
            Update-KcSimUi $w.Ctx
            Assert-Equal 'failed' $w.Ctx.State.Phase $kind
            Assert-Equal 'failed' $w.Ctx.State.Results[$w.Ctx.State.Selected].status
            Assert-Equal $null $w.Ctx.State.Results[$w.Ctx.State.Selected].actual
            $w[$kind] = $false
            $w.Child = New-SuiChild $true
            Invoke-KcSimUiAction $w.Ctx 'run'
            Update-KcSimUi $w.Ctx
            Assert-Equal 'done' $w.Ctx.State.Phase 'エラーから復帰'
            Assert-Equal 2 $w.Calls.Count
        } finally { Remove-SuiContext $w }
    }
}

Test-Case 'ファイルを開く: 解析失敗で古い結果を消し、別のファイルで復旧する' {
    $w = New-SuiContext
    try {
        $bad = Join-Path $w.Dir 'bad.json'
        [System.IO.File]::WriteAllText($bad, '{ broken')
        Invoke-KcSimUiAction $w.Ctx ('open:' + $bad)
        Assert-Equal 'failed' $w.Ctx.State.Phase
        Assert-Equal 0 $w.Ctx.State.Entries.Count
        Assert-Equal '' $w.Ctx.State.Selected
        Assert-Equal $false (Get-SuiLast $w.Form 'SetReportEnabled')[1]
        Invoke-KcSimUiAction $w.Ctx ('open:' + $w.Path)
        Assert-Equal 'ready' $w.Ctx.State.Phase
        Assert-Equal 3 $w.Ctx.State.Entries.Count
        Assert-Equal '0' $w.Ctx.State.Selected
    } finally { Remove-SuiContext $w }
}

Test-Case '終了すると実行中の子プロセスも閉じる' {
    $w = New-SuiContext
    try {
        Invoke-KcSimUiAction $w.Ctx 'run'
        Invoke-KcSimUiAction $w.Ctx 'close'
        Assert-True $w.Ctx.State.Exit
        Assert-True $w.Child.Killed
        Assert-True $w.Child.Disposed
    } finally { Remove-SuiContext $w }
}

Test-Case 'キーボード図: 実際の座標と幅を保ち、存在しないキーを除く' {
    $case = New-SuiScenario
    $geometry = Get-KcSimUiGeometry -Model $case.model -Scenario $case
    Assert-Equal '0,2' (@($geometry.Keys | ForEach-Object { $_.Pos }) -join ',')
    Assert-Near 2 $geometry.Keys[1].X 0.001
    Assert-Near 0.25 $geometry.Keys[1].Y 0.001
    Assert-Near 1.5 $geometry.Keys[1].W 0.001
    # KQ の HID 番号には物理配置が無い。入力に使う位置だけを論理キーとして並べる。
    $case.board = 'kq-mini'
    $case.model.id = 'kq-mini'
    foreach ($key in $case.model.keys) {
        $key.PSObject.Properties.Remove('x')
        $key.PSObject.Properties.Remove('y')
    }
    $logical = Get-KcSimUiGeometry -Model $case.model -Scenario $case
    Assert-Equal '0' (@($logical.Keys | ForEach-Object { $_.Pos }) -join ',')
    Assert-True ($logical.Caption -like '*HID*') 'HID の一覧と分かる表示'
}

Test-Case '時刻の再生: 物理キーと HID を区別し、レイヤーとマウスの状態を復元する' {
    $case = New-SuiScenario
    $case.events = @(
        [pscustomobject]@{ t = 0; type = 'press'; pos = 0 },
        [pscustomobject]@{ t = 10; type = 'press'; pos = 2 },
        [pscustomobject]@{ t = 20; type = 'release'; pos = 0 },
        [pscustomobject]@{ t = 20; type = 'release'; pos = 2 })
    $actual = @'
{"keys":[{"t":12,"usage":224,"down":true,"mods":1},{"t":12,"usage":26,"down":true,"mods":1},
{"t":20,"usage":26,"down":false,"mods":1},{"t":20,"usage":224,"down":false,"mods":0}],
"layers":[{"t":12,"layer":3,"down":true},{"t":20,"layer":3,"down":false}],
"mouse":[{"t":5,"x":3,"y":-2,"wheel":0,"hwheel":0,"buttons":1},
{"t":15,"x":4,"y":1,"wheel":-1,"hwheel":2,"buttons":0}],
"state":{"layers":[0],"keys":[],"buttons":0}}
'@ | ConvertFrom-Json
    $before = Get-KcSimUiReplay -Scenario $case -Actual $actual -AtMs 10
    Assert-Equal '0,2' ($before.Pressed -join ',')
    Assert-Equal '' ($before.Keys -join ',') 'hold-tap の確定前は HID が無い'
    $during = Get-KcSimUiReplay -Scenario $case -Actual $actual -AtMs 15
    Assert-Equal '0,2' ($during.Pressed -join ',')
    Assert-Equal '26,224' (@($during.Keys | Sort-Object) -join ',')
    Assert-Equal '0,3' (@($during.Layers | Sort-Object) -join ',')
    Assert-Equal 1 $during.Mods
    Assert-Equal 7 $during.Mouse.X
    Assert-Equal -1 $during.Mouse.Y
    Assert-Equal -1 $during.Mouse.Wheel
    Assert-Equal 2 $during.Mouse.HWheel
    Assert-Equal 0 $during.Mouse.Buttons
    $after = Get-KcSimUiReplay -Scenario $case -Actual $actual -AtMs 20
    Assert-Equal '' ($after.Pressed -join ',')
    Assert-Equal '' ($after.Keys -join ',')
    Assert-Equal '0' ($after.Layers -join ',')
    Assert-Equal 0 $after.Mods
    $preview = Get-KcSimUiReplay -Scenario $case -Actual $null -AtMs 10
    Assert-Equal $false $preview.HasActual
    Assert-Equal '0,2' ($preview.Pressed -join ',')
}

Test-Case '子プロセスのコマンド: 空白と引用符を含むパスをコードにしない' {
    $scriptPath = "C:\it's a folder\keyboard-sim.ps1"
    $inputPath = "C:\inputs\it's a test.json"
    $command = New-KcSimUiChildCommand -ScriptPath $scriptPath -InputFile $inputPath -ReportFile 'C:\cache\out.json' `
        -JUnitFile 'C:\cache\out.xml' -Python "C:\Program Files\Python\python.exe"
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($command, [ref]$tokens, [ref]$errors)
    Assert-Equal 0 $errors.Count
    $calls = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
    $target = @($calls | Where-Object { $_.CommandElements[0].Value -eq $scriptPath })
    Assert-Equal 1 $target.Count
    $values = @($target[0].CommandElements | ForEach-Object { $_.Extent.Text }) -join ' '
    Assert-True ($values.Contains("'C:\inputs\it''s a test.json'")) '入力パスは 1 つのリテラル'
}

Test-Case '画面の実行経路: 実際の CLI 子プロセスが日本語の合格・不合格レポートを返す' {
    Import-KcCSharp 'ChildProcess.cs' 'KcChildProcess'
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("keyboard sim's test " + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($dir)
    $ctx = $null
    try {
        $inputFile = Join-Path $dir '日本語の入力.json'
        $case = New-SuiScenario '日本語のタップを検証' 'inline'
        [System.IO.File]::WriteAllText($inputFile, (@{ schema = 1; scenarios = @($case) } | ConvertTo-Json -Depth 100),
            (New-Object System.Text.UTF8Encoding($false)))
        $script:SuiRealHost = (Get-Process -Id $PID).Path
        $script:SuiRealCli = Join-Path $script:ToolsDir 'scripts/keyboard-sim.ps1'
        $ctx = New-KcSimUiContext -Form (New-SuiForm) -ScenarioPath $inputFile -Python 'python' -ToolsDir $script:ToolsDir `
            -CacheDir (Join-Path $dir "実行結果's cache") -NewChild {
                param($InputFile, $ReportFile, $JUnitFile, $Python)
                $command = New-KcSimUiChildCommand -ScriptPath $script:SuiRealCli -InputFile $InputFile `
                    -ReportFile $ReportFile -JUnitFile $JUnitFile -Python $Python
                $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
                $arguments = '-NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
                return [KcChildProcess]::Start($script:SuiRealHost, $arguments, $script:ToolsDir, 65001)
            }
        Initialize-KcSimUi $ctx
        foreach ($shouldPass in @($true, $false)) {
            if (-not $shouldPass) {
                # 入力は同じまま、固定された期待値だけを間違える。
                $case.expect.keys[0].usage = 26
                [System.IO.File]::WriteAllText($inputFile, (@{ schema = 1; scenarios = @($case) } | ConvertTo-Json -Depth 100),
                    (New-Object System.Text.UTF8Encoding($false)))
                Invoke-KcSimUiAction $ctx ('open:' + $inputFile)
            }
            Invoke-KcSimUiAction $ctx 'run'
            Assert-Equal 'running' $ctx.State.Phase
            $reportPath = $ctx.State.Run.ReportFile
            $junitPath = $ctx.State.Run.JUnitFile
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            while ($null -ne $ctx.State.Child) {
                Update-KcSimUi $ctx
                if ([DateTime]::UtcNow -gt $deadline) { throw 'シミュレータの子プロセスが 30 秒以内に終了しませんでした' }
                if ($null -ne $ctx.State.Child) { Start-Sleep -Milliseconds 50 }
            }
            Assert-Equal 'done' $ctx.State.Phase '終了コードと JSON レポートを受け取る'
            $result = $ctx.State.Results['0']
            Assert-Equal $case.name $result.name '日本語のシナリオ名'
            Assert-Equal 20 $result.actual.keys[0].usage '既存のエンジンが実際に Q を出力'
            $display = (Get-SuiLast $ctx.Form 'SetDetails')[5] | ConvertFrom-Json
            Assert-Equal 20 $display.keys[0].usage '画面の実際の出力は期待値でなくエンジンの結果を表示'
            Assert-Equal @() $display.state.keys '終了時の状態も画面に表示'
            $report = [System.IO.File]::ReadAllText($reportPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            $xml = [xml][System.IO.File]::ReadAllText($junitPath, [System.Text.Encoding]::UTF8)
            Assert-Equal $case.name $xml.testsuite.testcase.name 'JUnit の日本語名'
            if ($shouldPass) {
                Assert-Equal 'passed' $result.status
                Assert-Equal 1 $report.passed
                Assert-Equal 0 $report.failed
            } else {
                Assert-Equal 'failed' $result.status
                Assert-Equal 0 $report.passed
                Assert-Equal 1 $report.failed
                Assert-True ($result.error -like '*expect.keys*') '期待値の不一致を表示'
            }
            $messages = @($ctx.Form.Calls | Where-Object { $_[0] -eq 'AppendLog' } | ForEach-Object { $_[1] }) -join "`n"
            Assert-True ($messages.Contains($case.name)) '子プロセスからの日本語ログ'
        }
    } finally {
        if ($null -ne $ctx) { Stop-KcSimUi $ctx }
        Remove-Item -LiteralPath $dir -Recurse -Force
    }
}
