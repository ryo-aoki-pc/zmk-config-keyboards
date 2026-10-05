# シミュレータの画面の流れ。WPF の型に触れず、ウィンドウと子プロセスを差し替えてテストできる。
# keyboard-sim.ps1 が先に読み込まれている前提。合否は既存の CLI のレポートだけから取得する。

function New-KcSimUiContext($Form, [string]$ScenarioPath, [string]$Python, [string]$ToolsDir,
    [string]$CacheDir, [scriptblock]$NewChild,
    [scriptblock]$GetModel = { param($Board, $Python) Get-KcSimModel $Board $Python },
    [scriptblock]$OpenReport = { param($Folder) }) {
    return @{
        Form = $Form; ScenarioPath = $ScenarioPath; Python = $Python; ToolsDir = $ToolsDir
        CacheDir = $CacheDir; NewChild = $NewChild; GetModel = $GetModel; OpenReport = $OpenReport
        State = @{
            Entries = @(); Board = ''; Selected = ''; Results = @{}; Child = $null; Run = $null
            Exit = $false; Phase = 'ready'; ReportFolder = ''; AtMs = 0L; ModelError = ''
        }
    }
}

# 引数は PowerShell の単一引用文字列に閉じ込める。EncodedCommand にするのは入口の役割。
function New-KcSimUiChildCommand([string]$ScriptPath, [string]$InputFile, [string]$ReportFile,
    [string]$JUnitFile, [string]$Python) {
    $quoted = @($ScriptPath, $InputFile, $ReportFile, $JUnitFile, $Python | ForEach-Object { "'" + $_.Replace("'", "''") + "'" })
    return ('[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); & {0} -Scenario {1} -ReportJson {2} -ReportJUnit {3} -Python {4}; exit $LASTEXITCODE' -f $quoted)
}

function Read-KcSimUiScenarios([string]$Path) {
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) { $files = @(Get-ChildItem -LiteralPath $item.FullName -Filter '*.json' -File | Sort-Object Name) }
    else { $files = @($item) }
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $names = @{}
    foreach ($file in $files) {
        $suite = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
        Assert-KcSimInteger (Get-KcSimProperty $suite 'schema') 'schema'
        $cases = Get-KcSimProperty $suite 'scenarios'
        if ((Get-KcSimProperty $suite 'schema') -ne 1 -or $cases -isnot [array] -or $cases.Count -eq 0) {
            throw ('空または未対応のシナリオファイル: {0}' -f $file.Name)
        }
        foreach ($case in $cases) {
            $board = [string](Get-KcSimProperty $case 'board' 'inline')
            $name = [string](Get-KcSimProperty $case 'name' '')
            $identity = '{0}/{1}' -f $board, $name
            if ($names.ContainsKey($identity)) { throw ('シナリオ名が重複しています: {0}' -f $identity) }
            $names[$identity] = $true
            $entries.Add([pscustomobject]@{ Id = [string]$entries.Count; Board = $board; Name = $name; Source = $file.FullName; Scenario = $case })
        }
    }
    if ($entries.Count -eq 0) { throw '実行対象のシナリオが 0 件です' }
    return ,$entries.ToArray()
}

function Get-KcSimUiBindingLabel($Binding) {
    $label = [string](Get-KcSimProperty $Binding 'label' '')
    if ($label) { return $label }
    $kind = Get-KcSimProperty $Binding 'kind' ''
    if ($kind -eq 'ht') {
        $tap = [string](Get-KcSimProperty (Get-KcSimProperty $Binding 'tap') 'label' '')
        $hold = [string](Get-KcSimProperty (Get-KcSimProperty $Binding 'hold') 'label' '')
        if ($tap) {
            if ($hold -and ($tap.Length + $hold.Length) -le 10) { return $tap + '/' + $hold }
            return $tap
        }
    }
    if ($kind -eq 'kp') {
        $usage = [int](Get-KcSimProperty $Binding 'usage' 0)
        return 'HID {0:X2}' -f $usage
    }
    $src = [string](Get-KcSimProperty $Binding 'src' '')
    if ($src) { return $src }
    return $kind
}

function Get-KcSimUiGeometry($Model, $Scenario) {
    $keys = Get-KcSimProperty $Model 'keys' @()
    $keys = @($keys | Where-Object { Get-KcSimProperty $_ 'present' $true })
    $physical = $keys.Count -gt 0
    foreach ($key in $keys) {
        if (-not (Test-KcSimProperty $key 'x') -or -not (Test-KcSimProperty $key 'y')) { $physical = $false }
    }
    if ((Get-KcSimProperty $Model 'id') -eq 'kq-mini' -or (Get-KcSimProperty $Scenario 'board') -eq 'kq-mini') { $physical = $false }
    $used = @{}
    foreach ($event in (Get-KcSimProperty $Scenario 'events' @())) {
        $pos = Get-KcSimProperty $event 'pos'
        if ((Get-KcSimProperty $event 'type' '') -in @('press', 'release') -and
            ($pos -is [int] -or $pos -is [long]) -and $pos -ge 0 -and $pos -le [int]::MaxValue) {
            $used[[int]$pos] = $true
        }
    }
    if (-not $physical) { $keys = @($keys | Where-Object { $used.ContainsKey([int]$_.pos) }) }
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($key in $keys) {
        Assert-KcSimInteger (Get-KcSimProperty $key 'pos') 'keys.pos'
        $pos = [int]$key.pos
        $binding = Get-KcSimProperty (Get-KcSimProperty $key 'on') '0'
        $legend = Get-KcSimUiBindingLabel $binding
        if ($legend.Length -gt 14) { $legend = $legend.Substring(0, 11) + '...' }
        $legend += "`n#" + $pos
        if ($physical) {
            $x = [double]$key.x; $y = [double]$key.y
            $w = [double](Get-KcSimProperty $key 'w' 1); $h = [double](Get-KcSimProperty $key 'h' 1)
        } else {
            $x = ($out.Count % 8) * 1.6; $y = [Math]::Floor($out.Count / 8) * 1.2; $w = 1.5; $h = 1
        }
        foreach ($coordinate in @($x, $y, $w, $h)) {
            if ([double]::IsNaN($coordinate) -or [double]::IsInfinity($coordinate)) { throw 'キーの座標には有限の数値が必要です' }
        }
        if ($w -le 0 -or $h -le 0) { throw 'キーの幅と高さは 0 より大きい数値が必要です' }
        $out.Add([pscustomobject]@{ Pos = $pos; X = $x; Y = $y; W = $w; H = $h; Legend = $legend })
    }
    $caption = 'キーの位置（BASE）'
    if (-not $physical) { $caption = '論理キー一覧（BASE・入力に含まれる位置）' }
    if ((Get-KcSimProperty $Model 'id') -eq 'kq-mini' -or (Get-KcSimProperty $Scenario 'board') -eq 'kq-mini') {
        $caption = 'HIDキー一覧（入力に含まれる番号）'
    }
    return [pscustomobject]@{ Keys = $out.ToArray(); Caption = $caption }
}

# 同じ時刻の入力は配列の順に処理する。出力された HID usage から物理位置は逆算しない。
function Get-KcSimUiReplay($Scenario, $Actual, [long]$AtMs) {
    $pressed = @{}; $down = @{}; $layers = @{ 0 = $true }; $mods = 0
    $mouse = [ordered]@{ X = 0L; Y = 0L; Wheel = 0L; HWheel = 0L; Buttons = 0 }
    foreach ($event in (Get-KcSimProperty $Scenario 'events' @())) {
        # 不正な入力の理由は CLI に任せる。プレビューから実行操作までを壊さない。
        $time = Get-KcSimProperty $event 't'
        if (($time -isnot [int] -and $time -isnot [long]) -or $time -lt 0 -or $time -gt $AtMs) { continue }
        $kind = Get-KcSimProperty $event 'type' ''
        $position = Get-KcSimProperty $event 'pos'
        if ($kind -notin @('press', 'release') -or ($position -isnot [int] -and $position -isnot [long]) -or
            $position -lt 0 -or $position -gt [int]::MaxValue) { continue }
        $pos = [int]$position
        if ($kind -eq 'press') { $pressed[$pos] = $true } else { $pressed.Remove($pos) }
    }
    foreach ($event in (Get-KcSimProperty $Actual 'keys' @())) {
        if ($event.t -gt $AtMs) { continue }
        $usage = [int]$event.usage
        if ($event.down) { $down[$usage] = $true } else { $down.Remove($usage) }
        $mods = [int](Get-KcSimProperty $event 'mods' 0)
    }
    foreach ($event in (Get-KcSimProperty $Actual 'layers' @())) {
        if ($event.t -gt $AtMs) { continue }
        $layer = [int]$event.layer
        if ($event.down) { $layers[$layer] = $true } else { $layers.Remove($layer) }
    }
    foreach ($event in (Get-KcSimProperty $Actual 'mouse' @())) {
        if ($event.t -gt $AtMs) { continue }
        $mouse.X += [long](Get-KcSimProperty $event 'x' 0); $mouse.Y += [long](Get-KcSimProperty $event 'y' 0)
        $mouse.Wheel += [long](Get-KcSimProperty $event 'wheel' 0); $mouse.HWheel += [long](Get-KcSimProperty $event 'hwheel' 0)
        $mouse.Buttons = [int](Get-KcSimProperty $event 'buttons' 0)
    }
    $positions = [int[]]@($pressed.Keys | Sort-Object)
    $usages = [int[]]@($down.Keys | Sort-Object)
    $active = [int[]]@($layers.Keys | Sort-Object)
    $text = '{0} ms  |  押下位置: {1}' -f $AtMs, ($positions -join ', ')
    if ($null -eq $Actual) { $text += '  |  出力: 未実行・結果なし' }
    else {
        $text += "`n" + ('レイヤー: {0}  |  HIDキー: {1}  |  修飾キー: 0x{2:X2}' -f ($active -join ', '), ($usages -join ', '), $mods)
        $text += "`n" + ('マウス累計: X {0}, Y {1}  |  スクロール: 縦 {2}, 横 {3}  |  ボタン: 0x{4:X2}' -f $mouse.X, $mouse.Y, $mouse.Wheel, $mouse.HWheel, $mouse.Buttons)
    }
    return [pscustomobject]@{ Pressed = $positions; Keys = $usages; Layers = $active; Mods = $mods; Mouse = $mouse; HasActual = ($null -ne $Actual); Text = $text }
}

function Get-KcSimUiSelected($Ctx) {
    foreach ($entry in $Ctx.State.Entries) { if ($entry.Id -ceq $Ctx.State.Selected) { return $entry } }
    return $null
}

function Show-KcSimUiLists($Ctx) {
    $s = $Ctx.State
    $boards = @($s.Entries | ForEach-Object { $_.Board } | Select-Object -Unique)
    $labels = @{ lism = 'LisM'; kukey42 = 'KUKEY42'; aroundfortyrb = 'AroundForty-RB'; pyuron = 'Pyuron'; roba = 'roBa'; 'torabo-tsuki-lp' = 'torabo-tsuki-lp'; keyball39 = 'Keyball39'; 'kq-mini' = 'KQ-mini'; 'keyball-kq-mini' = 'Keyball39 → KQ-mini'; inline = '埋め込みモデル' }
    $boardLabels = @($boards | ForEach-Object { if ($labels.ContainsKey($_)) { $labels[$_] } else { $_ } })
    $Ctx.Form.SetBoards([string[]]$boards, [string[]]$boardLabels, [string]$s.Board)
    $entries = @($s.Entries | Where-Object { $_.Board -ceq $s.Board })
    $statuses = @($entries | ForEach-Object {
        if ($s.Results.ContainsKey($_.Id)) { [string]$s.Results[$_.Id].status }
        elseif ($null -ne $s.Run -and @($s.Run.Entries | ForEach-Object { $_.Id }) -contains $_.Id) { 'running' }
        else { 'pending' }
    })
    $statusNames = @{ passed = '合格'; failed = '失敗'; running = '実行中'; cancelled = '中止' }
    $caseLabels = @(for ($i = 0; $i -lt $entries.Count; $i++) {
        if ($statusNames.ContainsKey($statuses[$i])) { '{0}  {1}' -f $statusNames[$statuses[$i]], $entries[$i].Name }
        else { $entries[$i].Name }
    })
    $Ctx.Form.SetScenarios([string[]]@($entries | ForEach-Object { $_.Id }), [string[]]$caseLabels, [string[]]$statuses, [string]$s.Selected)
    $Ctx.Form.SetBusy(($null -ne $s.Child), ($null -ne (Get-KcSimUiSelected $Ctx)))
}

function Clear-KcSimUiDetails($Ctx) {
    $Ctx.Form.SetDetails('', '', '', '', '')
    $Ctx.Form.SetKeys([int[]]@(), [double[]]@(), [double[]]@(), [double[]]@(), [double[]]@(), [string[]]@())
    $Ctx.Form.SetKeyStates([int[]]@())
    $Ctx.Form.SetReplay(0L, $false)
    $Ctx.Form.SetReplayState('シナリオを選択してください')
}

function Show-KcSimUiReplay($Ctx) {
    $entry = Get-KcSimUiSelected $Ctx
    if ($null -eq $entry) { return }
    $actual = $null
    if ($Ctx.State.Results.ContainsKey($entry.Id)) { $actual = Get-KcSimProperty $Ctx.State.Results[$entry.Id] 'actual' }
    $replay = Get-KcSimUiReplay $entry.Scenario $actual $Ctx.State.AtMs
    $Ctx.Form.SetKeyStates([int[]]$replay.Pressed)
    $Ctx.Form.SetReplayState([string]$replay.Text)
}

function Show-KcSimUiSelection($Ctx) {
    $s = $Ctx.State
    $s.AtMs = 0L
    Clear-KcSimUiDetails $Ctx
    $entry = Get-KcSimUiSelected $Ctx
    if ($null -eq $entry) { return }
    $scenario = $entry.Scenario
    $s.ModelError = ''
    try {
        $model = Get-KcSimProperty $scenario 'model'
        if ($null -eq $model) {
            $board = $entry.Board
            if ($board -eq 'keyball-kq-mini') { $board = 'keyball39' }
            $model = & $Ctx.GetModel $board $Ctx.Python
        }
        $geometry = Get-KcSimUiGeometry $model $scenario
        $keys = $geometry.Keys
        $Ctx.Form.SetLabels([string[]]@('PictureCaption'), [string[]]@($geometry.Caption))
        $Ctx.Form.SetKeys([int[]]@($keys | ForEach-Object { $_.Pos }), [double[]]@($keys | ForEach-Object { $_.X }),
            [double[]]@($keys | ForEach-Object { $_.Y }), [double[]]@($keys | ForEach-Object { $_.W }),
            [double[]]@($keys | ForEach-Object { $_.H }), [string[]]@($keys | ForEach-Object { $_.Legend }))
    } catch { $s.ModelError = 'キー図を取得できません: ' + $_.Exception.Message }
    $inputs = [ordered]@{ events = (Get-KcSimProperty $scenario 'events'); end_ms = (Get-KcSimProperty $scenario 'end_ms') } | ConvertTo-Json -Depth 100
    $expected = ConvertTo-Json -InputObject (Get-KcSimProperty $scenario 'expect') -Depth 100
    $actual = '未実行'
    if ($s.Results.ContainsKey($entry.Id)) { $actual = $s.Results[$entry.Id] | ConvertTo-Json -Depth 100 }
    $source = $entry.Source + "`n" + $entry.Board
    if ($s.ModelError) { $source += "`n" + $s.ModelError }
    $Ctx.Form.SetDetails([string]$entry.Name, [string]$source, [string]$inputs, [string]$expected, [string]$actual)
    $end = Get-KcSimProperty $scenario 'end_ms' 0
    $validEnd = ($end -is [int] -or $end -is [long]) -and $end -ge 0
    if (-not $validEnd) { $end = 0L }
    $Ctx.Form.SetReplay([long]$end, [bool]$validEnd)
    Show-KcSimUiReplay $Ctx
    if ($null -ne $s.Child) { $Ctx.Form.SetSummary('実行中', 'シミュレータの完了を待っています', 0) }
    elseif ($s.Results.ContainsKey($entry.Id)) {
        $result = $s.Results[$entry.Id]
        if ($result.status -eq 'passed') { $Ctx.Form.SetSummary('成功', 'すべての期待値に一致しました', 1) }
        elseif ($result.status -eq 'cancelled') { $Ctx.Form.SetSummary('中止', [string]$result.error, 3) }
        else { $Ctx.Form.SetSummary('失敗', [string]$result.error, 2) }
    } elseif ($s.ModelError) { $Ctx.Form.SetSummary('キー図の読み込みに失敗', [string]$s.ModelError, 2) }
    else { $Ctx.Form.SetSummary('実行できます', '入力と期待値を確認して「選択を実行」を押してください', 0) }
}

function Open-KcSimUiScenarios($Ctx, [string]$Path) {
    # 読み直したシナリオの図も、現在のチェックアウトから作り直す。
    $script:KcSimModels = @{}
    $s = $Ctx.State
    $s.Entries = @(); $s.Board = ''; $s.Selected = ''; $s.Results = @{}; $s.AtMs = 0L; $s.ReportFolder = ''
    $Ctx.Form.SetReportEnabled($false)
    Clear-KcSimUiDetails $Ctx
    try {
        $s.Entries = Read-KcSimUiScenarios $Path
        $Ctx.ScenarioPath = $Path
        $s.Board = $s.Entries[0].Board; $s.Selected = $s.Entries[0].Id; $s.Phase = 'ready'
        Show-KcSimUiLists $Ctx
        Show-KcSimUiSelection $Ctx
    } catch {
        $s.Phase = 'failed'
        Show-KcSimUiLists $Ctx
        $Ctx.Form.SetSummary('シナリオを読み込めません', $_.Exception.Message, 2)
        $Ctx.Form.AppendLog('失敗: ' + $_.Exception.Message)
    }
}

function Initialize-KcSimUi($Ctx) { Open-KcSimUiScenarios $Ctx $Ctx.ScenarioPath }

function Start-KcSimUiRun($Ctx, [bool]$All) {
    $s = $Ctx.State
    if ($null -ne $s.Child -or $s.Exit) { return }
    $entries = @($s.Entries | Where-Object { $_.Board -ceq $s.Board -and ($All -or $_.Id -ceq $s.Selected) })
    if ($entries.Count -eq 0) { $Ctx.Form.SetSummary('実行できません', '実行対象のシナリオが 0 件です', 2); return }
    foreach ($entry in $entries) { $s.Results.Remove($entry.Id) }
    $s.ReportFolder = ''; $Ctx.Form.SetReportEnabled($false)
    try {
        $folder = Join-Path $Ctx.CacheDir ([Guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($folder)
        $inputFile = Join-Path $folder 'scenario.json'; $reportFile = Join-Path $folder 'results.json'; $junitFile = Join-Path $folder 'results.xml'
        $suite = [ordered]@{ schema = 1; scenarios = @($entries | ForEach-Object { $_.Scenario }) }
        [System.IO.File]::WriteAllText($inputFile, ($suite | ConvertTo-Json -Depth 100), (New-Object System.Text.UTF8Encoding($false)))
        $s.Run = @{ Entries = $entries; Folder = $folder; ReportFile = $reportFile; JUnitFile = $junitFile }
        $s.Child = & $Ctx.NewChild $inputFile $reportFile $junitFile $Ctx.Python
        if ($null -eq $s.Child) { throw 'シミュレータを起動できません' }
        # CLI と同じく、実行ごとに現在のキーマップから図を読み直す。
        $script:KcSimModels = @{}
        $s.Phase = 'running'; $s.AtMs = 0L
        $Ctx.Form.AppendLog(('実行: {0} 件 / {1}' -f $entries.Count, $s.Board))
        Show-KcSimUiLists $Ctx
        Show-KcSimUiSelection $Ctx
    } catch {
        if ($null -ne $s.Child) { Stop-KcSimUi $Ctx }
        $s.Run = $null; $s.Phase = 'failed'
        Show-KcSimUiLists $Ctx
        Show-KcSimUiSelection $Ctx
        $Ctx.Form.SetSummary('実行を開始できません', $_.Exception.Message, 2)
        $Ctx.Form.AppendLog('失敗: ' + $_.Exception.Message)
    }
}

function Receive-KcSimUiLines($Ctx, $Child) {
    foreach ($line in $Child.TakeLines()) {
        if ($line -is [string]) { $text = $line } else { $text = [string](Get-KcSimProperty $line 'Text' '') }
        # Windows PowerShell の情報ストリームは EncodedCommand で CLIXML を重ねて出す。
        if ($text -and $text -notmatch '^#< CLIXML' -and $text -notmatch '^<Objs') { $Ctx.Form.AppendLog($text) }
    }
}

# 欠けた・別の実行のレポートを成功にしない。名前・機種・順序・件数と終了コードを確認する。
function Read-KcSimUiReport($Run, [int]$ExitCode) {
    if (-not (Test-Path -LiteralPath $Run.ReportFile -PathType Leaf)) { throw 'シミュレータの JSON レポートがありません' }
    $report = [System.IO.File]::ReadAllText($Run.ReportFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    Assert-KcSimInteger (Get-KcSimProperty $report 'schema') 'report.schema'
    if ((Get-KcSimProperty $report 'schema') -ne 1) { throw '未対応のレポート形式です' }
    if (Test-KcSimProperty $report 'error') { throw ('シミュレータの実行エラー: ' + [string]$report.error) }
    Assert-KcSimInteger (Get-KcSimProperty $report 'passed') 'report.passed'
    Assert-KcSimInteger (Get-KcSimProperty $report 'failed') 'report.failed'
    $results = Get-KcSimProperty $report 'scenarios'
    if ($results -isnot [array] -or $results.Count -ne $Run.Entries.Count) { throw 'レポートのシナリオ件数が実行対象と一致しません' }
    $passed = 0; $failed = 0
    for ($i = 0; $i -lt $results.Count; $i++) {
        $result = $results[$i]; $entry = $Run.Entries[$i]
        if ((Get-KcSimProperty $result 'name') -cne $entry.Name -or (Get-KcSimProperty $result 'board') -cne $entry.Board) { throw 'レポートのシナリオ名・機種・順序が実行対象と一致しません' }
        $status = Get-KcSimProperty $result 'status'
        if ((Get-KcSimProperty $result 'error') -isnot [string]) { throw 'レポートのエラー欄が不正です' }
        $actual = Get-KcSimProperty $result 'actual'
        if ($null -ne $actual) {
            foreach ($kind in @('keys', 'layers', 'mouse')) {
                $events = Get-KcSimProperty $actual $kind
                if ($events -isnot [array]) { throw ('レポートの actual.{0} は配列が必要です' -f $kind) }
                foreach ($event in $events) {
                    Assert-KcSimInteger (Get-KcSimProperty $event 't') ('actual.' + $kind + '.t')
                    if ($kind -eq 'mouse') {
                        foreach ($field in @('x', 'y', 'wheel', 'hwheel')) { Assert-KcSimInteger (Get-KcSimProperty $event $field) ('actual.mouse.' + $field) ([int]::MinValue) }
                        Assert-KcSimInteger (Get-KcSimProperty $event 'buttons') 'actual.mouse.buttons'
                    } else {
                        if ((Get-KcSimProperty $event 'down') -isnot [bool]) { throw 'レポートの down は真偽値が必要です' }
                        if ($kind -eq 'keys') {
                            Assert-KcSimInteger (Get-KcSimProperty $event 'usage') 'actual.keys.usage'
                            Assert-KcSimInteger (Get-KcSimProperty $event 'mods') 'actual.keys.mods'
                        } else { Assert-KcSimInteger (Get-KcSimProperty $event 'layer') 'actual.layers.layer' }
                    }
                }
            }
        }
        if ($status -ceq 'passed') {
            if ($null -eq $actual) { throw '成功したシナリオに実際の出力がありません' }
            if ($result.error) { throw '成功したシナリオにエラーが記録されています' }
            $passed++
        } elseif ($status -ceq 'failed') { $failed++ }
        else { throw 'レポートの合否が不正です' }
    }
    if ($passed -ne $report.passed -or $failed -ne $report.failed -or ($failed -eq 0 -and $ExitCode -ne 0) -or ($failed -gt 0 -and $ExitCode -ne 1)) {
        throw ('レポートの集計と終了コードが一致しません（終了コード {0}）' -f $ExitCode)
    }
    return $report
}

function Update-KcSimUi($Ctx) {
    $s = $Ctx.State; $child = $s.Child
    if ($null -eq $child -or $s.Exit) { return }
    try {
        Receive-KcSimUiLines $Ctx $child
        if (-not $child.HasExited) { return }
        # HasExited は標準出力と標準エラーの読み取り完了も待つ。
        Receive-KcSimUiLines $Ctx $child
        $code = [int]$child.ExitCode
        $child.Dispose(); $s.Child = $null
        $run = $s.Run; $s.Run = $null
        $s.ReportFolder = $run.Folder; $Ctx.Form.SetReportEnabled($true)
        try {
            $report = Read-KcSimUiReport $run $code
            for ($i = 0; $i -lt $run.Entries.Count; $i++) { $s.Results[$run.Entries[$i].Id] = $report.scenarios[$i] }
            $s.Phase = 'done'
            Show-KcSimUiLists $Ctx; Show-KcSimUiSelection $Ctx
            $level = 1
            if ($report.failed -gt 0) { $level = 2 }
            $Ctx.Form.SetSummary(('成功 {0} / 失敗 {1}' -f $report.passed, $report.failed), '詳細はシナリオを選択して確認できます', $level)
        } catch {
            $message = $_.Exception.Message
            foreach ($entry in $run.Entries) { $s.Results[$entry.Id] = [pscustomobject]@{ status = 'failed'; error = $message; actual = $null } }
            $s.Phase = 'failed'
            Show-KcSimUiLists $Ctx; Show-KcSimUiSelection $Ctx
            $Ctx.Form.SetSummary('実行結果を確認できません', $message, 2)
            $Ctx.Form.AppendLog('失敗: ' + $message)
        }
    } catch {
        $message = $_.Exception.Message
        Stop-KcSimUi $Ctx
        $s.Phase = 'failed'
        Show-KcSimUiLists $Ctx
        $Ctx.Form.SetSummary('シミュレータの実行に失敗', $message, 2)
        $Ctx.Form.AppendLog('失敗: ' + $message)
    }
}

function Stop-KcSimUi($Ctx) {
    $s = $Ctx.State; $child = $s.Child; $run = $s.Run
    $s.Child = $null; $s.Run = $null
    if ($null -eq $child) { return }
    try { $child.Kill() } finally {
        try { Receive-KcSimUiLines $Ctx $child } finally { $child.Dispose() }
    }
    if ($null -ne $run) {
        foreach ($entry in $run.Entries) { $s.Results[$entry.Id] = [pscustomobject]@{ status = 'cancelled'; error = '実行を中止しました。合否は未確定です'; actual = $null } }
        $s.ReportFolder = $run.Folder
        $Ctx.Form.SetReportEnabled($true)
    }
    $s.Phase = 'cancelled'
}

function Invoke-KcSimUiAction($Ctx, [string]$Action) {
    $s = $Ctx.State
    if ($s.Exit) { return }
    if ($Action -eq 'close') { try { Stop-KcSimUi $Ctx } finally { $s.Exit = $true }; return }
    if ($Action -eq 'cancel') {
        if ($null -ne $s.Child) { Stop-KcSimUi $Ctx; Show-KcSimUiLists $Ctx; Show-KcSimUiSelection $Ctx }
        return
    }
    if ($Action.StartsWith('seek:')) {
        $at = 0L
        if ([long]::TryParse($Action.Substring(5), [ref]$at) -and $at -ge 0) { $s.AtMs = $at; Show-KcSimUiReplay $Ctx }
        return
    }
    if ($null -ne $s.Child) { return }
    try {
        if ($Action -eq 'run') { Start-KcSimUiRun $Ctx $false }
        elseif ($Action -eq 'runall') { Start-KcSimUiRun $Ctx $true }
        elseif ($Action -eq 'standard') { Open-KcSimUiScenarios $Ctx (Join-Path $Ctx.ToolsDir 'simulator/scenarios') }
        elseif ($Action.StartsWith('open:')) { Open-KcSimUiScenarios $Ctx $Action.Substring(5) }
        elseif ($Action -eq 'report') { if ($s.ReportFolder) { & $Ctx.OpenReport $s.ReportFolder } }
        elseif ($Action.StartsWith('board:')) {
            $board = $Action.Substring(6)
            $entries = @($s.Entries | Where-Object { $_.Board -ceq $board })
            $s.Board = $board; $s.Selected = ''; $s.AtMs = 0L
            if ($entries.Count -gt 0) { $s.Selected = $entries[0].Id }
            Show-KcSimUiLists $Ctx; Show-KcSimUiSelection $Ctx
            if ($entries.Count -eq 0) { $Ctx.Form.SetSummary('シナリオがありません', ('機種 {0} のシナリオは 0 件です' -f $board), 2) }
        } elseif ($Action.StartsWith('scenario:')) {
            $id = $Action.Substring(9)
            $found = @($s.Entries | Where-Object { $_.Id -ceq $id -and $_.Board -ceq $s.Board })
            if ($found.Count -eq 1) { $s.Selected = $id; $s.AtMs = 0L; Show-KcSimUiLists $Ctx; Show-KcSimUiSelection $Ctx }
        }
    } catch {
        $Ctx.Form.SetSummary('操作に失敗', $_.Exception.Message, 2)
        $Ctx.Form.AppendLog('失敗: ' + $_.Exception.Message)
    }
}
