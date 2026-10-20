# 実機の回帰テスト (keyboard-check.ps1 -Mode Regression) の流れ。チェックリスト (tools/regression/checks.json) の
# 項目を 1 つずつ行う。読み出し (readout) と、答えるだけの項目 (manual) はコンソールで、ほかはテスト用の
# ウィンドウ (KcInputTestForm) で行う。判定は regression.ps1 (純粋関数)。手順の一部は input-test.ps1 /
# behavior-test.ps1 の関数をそのまま使う。
# Windows の API (Raw Input のデバイス一覧・ドライブ・COM ポート・スリープの抑止) には $Ctx.Probe から触る
# (テストでは偽物にする)。WMI / CIM は UI のループの中で呼ばない (呼ぶと、その間ウィンドウが止まる)。
# expected.ps1 / results.ps1 / input-eval.ps1 / zmk-log.ps1 / regression.ps1 / input-test.ps1 / behavior-test.ps1 /
# layer-trace.ps1 / lib/input-monitor/devices.ps1 が先に読み込まれている前提。
#
# ウィンドウを開いている間はコンソールに書かない (input-test.ps1 と同じ)。

# readout と manual はコンソールで行う (manual は、ほかのアプリ (input-monitor・Windows の設定) を見ながら答えるので、
# 手前に出たままのテスト用のウィンドウを閉じてから尋ねる)
$script:KcRgConsoleHandlers = @('readout', 'manual')

# ---------------------------------------------------------------------------
# Windows に触る処理 (Probe)
# ---------------------------------------------------------------------------

# UF2 のブートローダのドライブ (INFO_UF2.TXT があるドライブ)。開いた直後は読めないことがあるので、少しやり直す
function Find-KcUf2Drives {
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -eq [System.IO.DriveType]::Network -or $d.DriveType -eq [System.IO.DriveType]::CDRom) {
            continue
        }
        try {
            if (-not $d.IsReady) {
                continue
            }
            $root = $d.RootDirectory.FullName
            $infoPath = [System.IO.Path]::Combine($root, 'INFO_UF2.TXT')
            if (-not [System.IO.File]::Exists($infoPath)) {
                continue
            }
            $info = $null
            for ($i = 0; $i -lt 4 -and $null -eq $info; $i++) {
                try {
                    $info = [System.IO.File]::ReadAllText($infoPath)
                } catch {
                    Start-Sleep -Milliseconds 250
                }
            }
            $out.Add([pscustomobject]@{ Root = $root; Label = [string]$d.VolumeLabel; Info = [string]$info })
        } catch {
            # 準備できていないドライブ (カードリーダーなど) や、取り外し中のドライブは無視する
        }
    }
    return , $out.ToArray()
}

# Windows で使う Probe。テストでは同じ名前の scriptblock を持つ偽物にする
function New-KcRegressionProbe {
    return @{
        # Raw Input のキーボード・マウス (ハンドル・経路 USB / BLE・VID / PID)。軽い呼び出し (WMI を使わない)
        ListInputDevices = {
            $list = New-Object 'System.Collections.Generic.List[object]'
            foreach ($d in [KcInputMonitorForm]::ListDevices()) {
                $path = [KcInputTestForm]::GetDeviceName($d.Handle)
                $info = ConvertFrom-ImDevicePath $path
                $list.Add([pscustomobject]@{ Handle = [long]$d.Handle; Type = [int]$d.Type; Transport = [string]$info.Transport; Vid = [string]$info.Vid; Pid = [string]$info.Pid })
            }
            return , $list.ToArray()
        }
        DeviceName       = { param($Handle) [KcInputTestForm]::GetDeviceName([long]$Handle) }
        FindUf2Drives    = { Find-KcUf2Drives }
        # COM ポートは、ここで 1 回だけ探す (Read-KcLogPortLines が UI のループの中で CIM を呼ばないように)
        NewLogReader     = {
            param($Port)
            $r = New-KcLogPortReader $Port
            if (-not $Port) { $r.Candidates = @(foreach ($x in (Find-KcStudioPort)) { $x.Port }) }
            $r
        }
        ReadLog          = { param($Reader) Read-KcLogPortLines $Reader }
        CloseLog         = { param($Reader) Close-KcLogPortReader $Reader }
        KeepAwake        = { param($On) [KcUi]::KeepAwake([bool]$On) }
        ReadHost         = { param($Prompt) Read-Host $Prompt }
        WriteHost        = { param($Text, $Color) if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text } }
    }
}

# ---------------------------------------------------------------------------
# 共通の部品
# ---------------------------------------------------------------------------

function Add-KcRgRow($Ctx, [string]$Item, [string]$Status, [string]$Actual = '', [string]$Message = '', [string[]]$Details = @()) {
    if ($Status -eq 'NONE') {
        $Status = 'SKIP'
    }
    $hint = $Message
    if ($Status -eq 'FAIL' -and $Ctx.Check.FailHint) {
        $hint = (@($Message, $Ctx.Check.FailHint) | Where-Object { $_ }) -join "`n"
    }
    [void](Add-KcResult -Results $Ctx.Results -Category $Ctx.Category -Item $Item -Status $Status -Actual $Actual -Hint $hint -Details $Details)
}

function Restore-KcRgButtons($Ctx) {
    $Ctx.Form.SetButtonTexts('次へ', 'やり直し', 'スキップ', '中止')
    $Ctx.Form.SetButtons($false, $false, $true)
}

# ボタンを待つ。$Until (param($events, $now)) が $true を返したら 'done' (デバイスやドライブの出入りを待つとき)。
# 戻り値: done / next / retry / skip / abort / timeout
function Wait-KcRgButton($Ctx, [string]$Title, [string]$Instruction, [string]$Detail, [string]$Next = '次へ', [string]$Retry = '',
    [scriptblock]$Until = $null, [int]$TimeoutMs = 0, [int]$CheckMs = 500) {
    $Ctx.Form.SetTexts($Title, $Instruction, $Detail)
    $retryText = 'やり直し'
    if ($Retry) { $retryText = $Retry }
    $Ctx.Form.SetButtonTexts($Next, $retryText, 'スキップ', '中止')
    $Ctx.Form.SetButtons($true, [bool]$Retry, $true)
    try {
        if ($null -eq $Until) {
            $wbR = Wait-KcStep -Ctx $Ctx -TimeoutMs $TimeoutMs -ButtonsOnly
        } else {
            $wbR = Wait-KcStep -Ctx $Ctx -TimeoutMs $TimeoutMs -CheckIntervalMs $CheckMs -Done $Until
        }
    } finally {
        Restore-KcRgButtons $Ctx
    }
    # 待つ間に届いた入力 (ブートローダの手順が、キーが離されたかを見る)
    $Ctx.LastEvents = @($wbR.Events)
    return $wbR.Outcome
}

# はい / いいえで答えてもらう (ウィンドウ)。戻り値: yes / no / skip / abort
function Wait-KcRgYesNo($Ctx, [string]$Title, [string]$Question, [string]$Detail) {
    $o = Wait-KcRgButton $Ctx $Title $Question $Detail 'はい' 'いいえ'
    switch ($o) {
        'next' { return 'yes' }
        'retry' { return 'no' }
        'abort' { return 'abort' }
    }
    return 'skip'
}

# カウントダウン。$TouchDevices (ハンドルの配列) の入力があったら、やり直す ($null なら触っても続ける)。
# 戻り値: done / skip / abort
function Wait-KcRgCountdown($Ctx, [int]$Ms, [string]$Title, [string]$Instruction, [string]$Detail, $TouchDevices = $null) {
    $Ctx.Form.SetTexts($Title, $Instruction, $Detail)
    $Ctx.Form.SetButtons($false, $false, $true)
    $end = $Ctx.Form.NowMs + $Ms
    while ($Ctx.Form.NowMs -lt $end) {
        Invoke-KcPump
        $a = $Ctx.Form.TakeAction()
        if ($a -eq 'abort' -or $a -eq 'skip') {
            $Ctx.Form.SetProgress(0, 0)
            return $a
        }
        $events = @($Ctx.Form.TakeEvents())
        if ($null -ne $TouchDevices -and @($events | Where-Object { @($TouchDevices) -contains $_.Device }).Count -gt 0) {
            $end = $Ctx.Form.NowMs + $Ms
            $Ctx.Form.SetStatus('触ったので、カウントダウンをやり直します', 3)
        } else {
            $left = [math]::Ceiling(($end - $Ctx.Form.NowMs) / 1000.0)
            $text = if ($left -ge 120) { '残り {0} 分' -f [math]::Ceiling($left / 60.0) } else { '残り {0} 秒' -f $left }
            $Ctx.Form.SetStatus($text, 0)
        }
        $Ctx.Form.SetProgress([int][math]::Max(0, $Ms - ($end - $Ctx.Form.NowMs)), $Ms)
    }
    $Ctx.Form.SetProgress(0, 0)
    return 'done'
}

# この機種の Raw Input のデバイス (期待値の device.usb_vid / usb_pid と同じ VID / PID)。ほかの ZMK の機種も
# 同じ VID / PID なので、判定はキーとボールの動きで行う
function Get-KcRgTargetDevices($Ctx) {
    $list = & $Ctx.Probe.ListInputDevices
    return , @(@($list) | Where-Object { Test-KcRgDeviceMatch $Ctx.Expected ([string]$_.Vid) ([string]$_.Pid) })
}

function Test-KcRgUsbPresent($Ctx) {
    $t = Get-KcRgTargetDevices $Ctx
    return (@($t | Where-Object { $_.Transport -eq 'USB' }).Count -gt 0)
}

# 抜き挿し・スリープの後: 次の項目で、キーボード・ボールを特定し直す
function Reset-KcRgDevices($Ctx) {
    $Ctx.Keyboard = [long]0
    $Ctx.Mouse = [long]0
    $Ctx.Devices = @()
}

# キーボード (とボール) を特定する。特定したデバイスが消えていたら (抜き挿しの後)、もう一度特定する
function Initialize-KcRgDevices($Ctx, [bool]$Mouse) {
    if ($Ctx.Keyboard -ne 0 -and -not [string](& $Ctx.Probe.DeviceName $Ctx.Keyboard)) {
        Reset-KcRgDevices $Ctx
    }
    if ($Ctx.Mouse -ne 0 -and -not [string](& $Ctx.Probe.DeviceName $Ctx.Mouse)) {
        $Ctx.Mouse = [long]0
        $Ctx.Devices = @($Ctx.Keyboard)
    }
    if ($Ctx.Keyboard -eq 0) {
        $o = Select-KcKeyboardDevice $Ctx
        if ($o -ne 'done') { return $o }
    }
    if ($Mouse -and $Ctx.Mouse -eq 0) {
        $o = Select-KcMouseDevice $Ctx
        if ($o -ne 'done') { return $o }
    }
    return 'done'
}

# 決めたキー ($Usages) とボールの動きが、この機種のデバイスから届くまで待つ。デバイスの一覧は 1 秒ごとに見直す
# (抜き挿しで、ハンドルが変わるため)。この機種のデバイスが見つからなければ、どのデバイスの入力も受け付ける。
# 戻り値: @{ Outcome = done / timeout / skip / abort / next; Missing = 届かなかったもの; Transport; AnyDevice }
function Wait-KcRgInput($Ctx, [int[]]$Usages, [bool]$Ball, [int]$TimeoutMs, [string]$Title, [string]$Instruction, [string]$Detail, [scriptblock]$OnTick = $null) {
    # scriptblock は呼び出し元の変数を (動的に) 参照するので、ここの変数名は wi で始めて重ならないようにする
    $Ctx.Form.SetTexts($Title, $Instruction, $Detail)
    $Ctx.Form.SetButtons($false, $false, $true)
    $Ctx.Form.ClearEvents()
    $wiState = @{ Refresh = [long]-100000; Handles = @{}; Progress = $null }
    $wiUsages = $Usages
    $wiBall = $Ball
    $wiExtra = $OnTick
    $wiUpdate = {
        param($ev, $now)
        if (($now - $wiState.Refresh) -ge 1000) {
            $wiState.Refresh = $now
            foreach ($d in (Get-KcRgTargetDevices $Ctx)) {
                $wiState.Handles[[long]$d.Handle] = [string]$d.Transport
            }
        }
        $wiState.Progress = Get-KcRgInputProgress $ev ([long[]]@($wiState.Handles.Keys)) $wiUsages $wiBall $Ctx.ScanTable
    }
    $wiR = Wait-KcStep -Ctx $Ctx -AnyDevice -TimeoutMs $TimeoutMs -CheckIntervalMs 250 -OnTick {
        param($ev, $now)
        & $wiUpdate $ev $now
        if ($null -ne $wiExtra) { & $wiExtra $ev $now }
        if ($wiState.Progress.Missing.Count -gt 0) {
            $Ctx.Form.SetStatus(('まだ届いていないもの: {0}' -f ($wiState.Progress.Missing -join '、')), 0)
        }
    } -Done {
        param($ev, $now)
        & $wiUpdate $ev $now
        $wiState.Progress.Done -and (($now - $wiState.Progress.LastTime) -ge 300)
    }
    if ($null -eq $wiState.Progress) {
        & $wiUpdate @($wiR.Events) $Ctx.Form.NowMs
    }
    $wiP = $wiState.Progress
    $wiTransport = ''
    if ($wiP.Handle -ne 0 -and $wiState.Handles.ContainsKey([long]$wiP.Handle)) {
        $wiTransport = $wiState.Handles[[long]$wiP.Handle]
    }
    if ($wiTransport) {
        $Ctx.Transport = $wiTransport
    }
    return @{ Outcome = $wiR.Outcome; Missing = @($wiP.Missing); Transport = $wiTransport; AnyDevice = [bool]$wiP.AnyDevice; Events = $wiR.Events }
}

# Wait-KcRgInput の判定 (純粋)。この機種のデバイス ($Handles) の入力だけを数える。$Handles が空 (この機種の
# デバイスが見つからない) なら、何も数えない (PC 本体のキーボードやマウスの入力で合格にしない)
function Get-KcRgInputProgress($Events, [long[]]$Handles, [int[]]$Usages, [bool]$Ball, $ScanTable) {
    $any = (@($Handles).Count -eq 0)
    $mine = @($Events | Where-Object { -not $any -and @($Handles) -contains [long]$_.Device })
    $actions = ConvertTo-KcKeyActions $mine $ScanTable
    $missing = New-Object 'System.Collections.Generic.List[string]'
    if ($any) {
        $missing.Add('この機種のデバイス (VID / PID)')
    }
    $handle = [long]0
    $last = [long]0
    foreach ($u in @($Usages)) {
        $hit = @($actions | Where-Object { $_.Usage -eq $u })
        if (@($hit | Where-Object { $_.Down }).Count -eq 0) {
            $missing.Add(('「{0}」' -f (Get-KcUsageLabel $u $ScanTable)))
        } else {
            # 待っているキーの最後の押す / 離す (ほかのキーでは待ちを延ばさない)
            $last = [math]::Max($last, [long]$hit[$hit.Count - 1].Time)
        }
    }
    $keyEvents = @($mine | Where-Object { $_.Kind -eq 'key' })
    if ($keyEvents.Count -gt 0) {
        $handle = [long]$keyEvents[$keyEvents.Count - 1].Device
    }
    if ($Ball) {
        $moves = @($mine | Where-Object { $_.Kind -eq 'mouse' -and ($_.Dx -ne 0 -or $_.Dy -ne 0) })
        if ($moves.Count -lt 3) {
            $missing.Add('ボールの動き')
        } else {
            $last = [math]::Max($last, [long]$moves[$moves.Count - 1].Time)
            if ($handle -eq 0) { $handle = [long]$moves[$moves.Count - 1].Device }
        }
    }
    return [pscustomobject]@{ Done = ($missing.Count -eq 0); Missing = $missing.ToArray(); Handle = $handle; LastTime = $last; AnyDevice = $any }
}

function Get-KcRgUsages($Ctx, [string[]]$Legends) {
    $out = @()
    foreach ($l in @($Legends)) {
        $u = Get-KcUsageByLegend $l $Ctx.ScanTable
        if ($u -ge 0) { $out += $u }
    }
    return , [int[]]$out
}

# ---------------------------------------------------------------------------
# handler (コンソール)
# ---------------------------------------------------------------------------

# 手順を見せて、はい / いいえで答えてもらう (コンソール)
function Invoke-KcRgManual($Ctx, $Check) {
    $p = $Check.Params
    $say = $Ctx.Probe.WriteHost
    & $say ''
    & $say ('■ {0}' -f $Check.Title) 'Cyan'
    & $say ('  過去に起きたこと: {0}' -f $Check.Symptom)
    & $say ('  PR: {0}' -f (Format-KcRegressionPrs $Check)) 'DarkGray'
    $i = 0
    foreach ($s in @(Get-KcProp $p 'steps' @())) {
        $i++
        & $say ('  {0}. {1}' -f $i, $s)
    }
    & $say ('  {0}' -f $p.question) 'Yellow'
    while ($true) {
        $a = [string](& $Ctx.Probe.ReadHost '  1. はい  2. いいえ  3. スキップ')
        switch ($a.Trim()) {
            '1' { Add-KcRgRow $Ctx '確認' 'PASS' 'はい'; return 'done' }
            '2' { Add-KcRgRow $Ctx '確認' 'FAIL' 'いいえ'; return 'done' }
            '3' { Add-KcRgRow $Ctx '確認' 'SKIP' 'スキップしました'; return 'done' }
        }
        & $say '  1〜3 の番号を入れてください。' 'Yellow'
    }
}

# 読み出し検査 (keyboard-check.ps1 の Invoke-KcReadoutAll) を行い、その行をこの項目の区分に入れる
function Invoke-KcRgReadout($Ctx, $Check) {
    if ((Test-KcRegressionZmkBoard ([string]$Ctx.Options.Board)) -and [string](Get-KcProp $Ctx.Options 'Firmware' '') -eq 'logging') {
        # ログ版の COM ポートには何も送らない (Studio の RPC も送らない)
        Add-KcRgRow $Ctx '読み出し' 'SKIP' '右手側がログ版のため読み出しません' '読み出しは、右手側を Studio 版にして行ってください'
        return 'done'
    }
    $tmp = New-KcResultList
    & $Ctx.Options.Readout $tmp
    if ($tmp.Count -eq 0) {
        Add-KcRgRow $Ctx '読み出し' 'SKIP' '読み出した項目がありません'
        return 'done'
    }
    foreach ($r in $tmp) {
        $hint = $r.Hint
        if ($r.Status -eq 'FAIL' -and $Check.FailHint) {
            $hint = (@($r.Hint, $Check.FailHint) | Where-Object { $_ }) -join "`n"
        }
        [void](Add-KcResult -Results $Ctx.Results -Category $Ctx.Category -Item ('{0}: {1}' -f $r.Category, $r.Item) -Status $r.Status `
                -Expected $r.Expected -Actual $r.Actual -Hint $hint -Details @($r.Details) -Reference:([bool]$r.Reference))
    }
    return 'done'
}

# ---------------------------------------------------------------------------
# handler (ウィンドウ)
# ---------------------------------------------------------------------------

# 今の実動作テストの手順 (input-test.ps1) を、ボールごとに行う
function Invoke-KcRgInputTest($Ctx, $Check) {
    $o = Initialize-KcRgDevices $Ctx $true
    if ($o -ne 'done') { return $o }
    $tb = $Ctx.Expected.interactive.trackball
    $test = [string]$Check.Params.test
    $keys = $null
    foreach ($ball in @($Ctx.Balls)) {
        $keys = Get-KcHandKeys $tb $ball
        $o = 'done'
        switch ($test) {
            'shift-click' { $o = Invoke-KcShiftClickTest $Ctx $ball $keys }
            'release' {
                foreach ($rk in @($keys.release_ctrl, $keys.release_shift)) {
                    if ($o -eq 'done') { $o = Invoke-KcAmlReleaseTest $Ctx $ball $rk }
                }
            }
            'scroll' { $o = Invoke-KcScrollTest $Ctx $ball $keys }
        }
        if ($o -ne 'done') { return $o }
    }
    if ($test -eq 'threshold' -and $null -ne $keys) {
        if ((Get-KcAmlThreshold $Ctx) -le 0) {
            Add-KcRgRow $Ctx 'AML のしきい値' 'SKIP' 'この機種の期待値に AML のしきい値がありません'
            return 'done'
        }
        $o = Invoke-KcTimeoutTest $Ctx $keys
        if ($o -eq 'done') { $o = Invoke-KcAmlThresholdTest $Ctx $keys }
        return $o
    }
    return 'done'
}

# レイヤー・ビヘイビアのテスト (behavior-test.ps1) を、決めた種類だけ行う
function Invoke-KcRgBehaviors($Ctx, $Check) {
    $o = Initialize-KcRgDevices $Ctx $false
    if ($o -ne 'done') { return $o }
    $Ctx.BehaviorKinds = @($Check.Params.kinds)
    $Ctx.BehaviorCategory = $Ctx.Category
    try {
        return (Invoke-KcBehaviorTest $Ctx)
    } finally {
        $Ctx.BehaviorKinds = @()
        $Ctx.BehaviorCategory = ''
    }
}

# ボールを転がし続ける間に、ボールの動きが途中で止まらない (#52: キーは効くのにボールだけ止まる)
function Invoke-KcRgBallAlive($Ctx, $Check) {
    $o = Initialize-KcRgDevices $Ctx $true
    if ($o -ne 'done') { return $o }
    $p = $Check.Params
    $dur = [int]$p.duration_ms
    $endMs = [int](Get-KcProp $p 'end_ms' 3000)
    $tb = $Ctx.Expected.interactive.trackball
    foreach ($ball in @($Ctx.Balls)) {
        $bn = $script:KcBallNames[$ball]
        $key = (Get-KcHandKeys $tb $ball).release_ctrl
        $item = 'ボールが止まらない ({0}のボール)' -f $bn
        $res = $null
        for ($n = 1; $n -le 2; $n++) {
            $Ctx.Form.SetTexts($item, ('カウントダウンが終わるまで{0}のボールを転がし続け、途中と最後に「{1}」を押してください' -f $bn, $key.legend),
                ("キーは効くのに、ボールだけが止まる不具合を確かめます (転がし続けて、カーソルが止まらなければ合格)。`n「{0}」は短く押してください。カーソルはこのウィンドウの中だけで動きます。" -f $key.legend))
            $Ctx.Form.ClearEvents()
            $Ctx.Form.Confine($true)
            $start = $Ctx.Form.NowMs
            $r = Wait-KcStep -Ctx $Ctx -TimeoutMs $dur -OnTick {
                param($ev, $now)
                $left = [math]::Max(0, $dur - ($now - $start))
                $Ctx.Form.SetProgress([int]($dur - $left), $dur)
                $msg = '転がし続けてください (残り {0} 秒)' -f [math]::Ceiling($left / 1000.0)
                if ($left -le ($dur / 2) -and $left -gt ($dur / 2 - 2500)) { $msg = '「{0}」を押してください' -f $key.legend }
                if ($left -le 3000) { $msg = '最後に「{0}」を押してください' -f $key.legend }
                $Ctx.Form.SetStatus($msg, 0)
            }
            $Ctx.Form.Confine($false)
            $Ctx.Form.SetProgress(0, 0)
            if ($r.Outcome -eq 'abort') { return 'abort' }
            if ($r.Outcome -eq 'skip') { $res = New-KcRgResult 'NONE' '(スキップ)'; break }
            $res = Test-KcBallAlive $r.Events $start ($start + $dur) $endMs $Ctx.ScanTable
            if ($res.Status -eq 'STOPPED') {
                $a = Wait-KcRgYesNo $Ctx $item ('{0} 最後までボールを転がし続けていましたか?' -f $res.Actual) 'はいなら不合格 (ボールが止まった) とします。いいえなら、やり直します。'
                if ($a -eq 'abort') { return 'abort' }
                if ($a -eq 'yes') { $res.Status = 'FAIL'; break }
                if ($a -eq 'skip') { $res.Status = 'NONE'; break }
                continue
            }
            if ($res.Status -eq 'PASS') { break }
            if ($n -lt 2) {
                Show-KcStepResult $Ctx 'NONE' ($res.Actual + ' ' + $res.Message + ' もう一度お願いします')
                Wait-KcPause $Ctx 1800
            }
        }
        if ($res.Status -eq 'STOPPED') {
            # 2 回とも「転がし続けていなかった」と答えた
            $res.Status = 'NONE'
            $res.Message = 'ボールを最後まで転がし続けられなかったため、確かめられませんでした'
        }
        Add-KcRgRow $Ctx $item $res.Status $res.Actual $res.Message $res.Details
    }
    return 'done'
}

# ボールの近くのキーを速く打っても、AML にならない (#30 の振動の簡易な確認)
function Invoke-KcRgTypingNoAml($Ctx, $Check) {
    $o = Initialize-KcRgDevices $Ctx $true
    if ($o -ne 'done') { return $o }
    $tb = $Ctx.Expected.interactive.trackball
    $repeat = [int]$Check.Params.repeat
    $legends = @()
    $usages = @()
    foreach ($side in @('left', 'right')) {
        $k = Get-KcProp $tb.keys $side $null
        if ($null -eq $k) { continue }
        foreach ($x in @($k.scroll, $k.after_timeout)) {
            if ($usages -notcontains [int]$x.usage) { $legends += [string]$x.legend; $usages += [int]$x.usage }
        }
    }
    $waitMs = [int]$tb.aml.timeout_ms + 2000
    $item = 'キーを速く打っても AML にならない'
    $res = Invoke-KcRetryStep $Ctx {
        $c = Wait-KcRgCountdown $Ctx $waitMs $item 'ボールから手を離して、カウントダウンが終わるまで待ってください' 'AML が切れた状態から始めます。' $Ctx.Devices
        if ($c -eq 'abort') { return 'abort' }
        if ($c -eq 'skip') { return (New-KcRgResult 'NONE' '(スキップ)') }
        $Ctx.Form.SetTexts($item, ('「{0}」を、それぞれ {1} 回以上、速く打ってください (順番は問いません)' -f ($legends -join '」「'), $repeat),
            "ボールには触らないでください。キーを打つ振動でボールがわずかに動いても、AML にならず文字がすべて入れば合格です。`n(ボールが動かなければ古いファームでも合格になる、簡易な確認です)")
        $Ctx.Form.ClearEvents()
        $Ctx.Form.Confine($true)
        $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 30000 -Done {
            param($ev, $now)
            $downs = @((ConvertTo-KcKeyActions $ev $Ctx.ScanTable) | Where-Object { $_.Down })
            ($downs.Count -ge ($usages.Count * $repeat)) -and (Test-KcKeysSettled $ev $Ctx.ScanTable $now 800)
        }
        $Ctx.Form.Confine($false)
        if ($r.Outcome -eq 'abort') { return 'abort' }
        if ($r.Outcome -eq 'skip') { return (New-KcRgResult 'NONE' '(スキップ)') }
        $t = Test-KcTypingNoAml $r.Events ([int[]]$usages) $repeat $Ctx.ScanTable
        Show-KcStepResult $Ctx $t.Status ($t.Actual + ' ' + $t.Message)
        Wait-KcPause $Ctx 800
        return $t
    }
    if ($res -is [string]) { return $res }
    Add-KcRgRow $Ctx $item $res.Status $res.Actual $res.Message (@($res.Details) + (Get-KcFirstAttemptDetails $res))
    return 'done'
}

# AML のタイムアウトより長くスクロールしても AML が切れない。D を離してから D → F で確かめる
# (D を押したままでは、AML が切れても D のレイヤー (SCRL) が残り、クリックになってしまう)
function Invoke-KcRgAmlExtend($Ctx, $Check) {
    $o = Initialize-KcRgDevices $Ctx $true
    if ($o -ne 'done') { return $o }
    $p = $Check.Params
    $tb = $Ctx.Expected.interactive.trackball
    $timeout = [int]$tb.aml.timeout_ms
    $hold = $timeout + [int]$p.extra_ms
    $within = [int]$p.check_within_ms
    foreach ($ball in @($Ctx.Balls)) {
        $bn = $script:KcBallNames[$ball]
        $keys = Get-KcHandKeys $tb $ball
        $item = 'スクロールの後も AML が残る ({0}のボール)' -f $bn
        $res = Invoke-KcRetryStep $Ctx {
            $Ctx.Form.SetTexts($item, ('カーソルが 1 cm ほど動くまで{0}のボールを転がしてから、「{1}」を押したまま、ボールを転がしてスクロールを始めてください' -f $bn, $keys.scroll.legend),
                ('スクロールが始まったら、カウントダウン ({0} 秒) が終わるまで、「{1}」を押したままスクロールを続けます。AML のタイムアウト ({2} 秒) より長くスクロールしても、AML が切れないことを確かめます。' -f ($hold / 1000), $keys.scroll.legend, ($timeout / 1000)))
            $Ctx.Form.ClearEvents()
            $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 40000 -Done {
                param($ev, $now)
                @($ev | Where-Object { $_.Kind -eq 'mouse' -and ($_.Wheel -ne 0 -or $_.HWheel -ne 0) }).Count -ge 2
            }
            if ($r.Outcome -eq 'abort') { return 'abort' }
            if ($r.Outcome -ne 'done') { return (New-KcRgResult 'NONE' '(スクロールが始まらない)') }
            $start = $Ctx.Form.NowMs
            $st = @{ LastWheel = $start }
            $r2 = Wait-KcStep -Ctx $Ctx -TimeoutMs $hold -OnTick {
                param($ev, $now)
                $w = @($ev | Where-Object { $_.Kind -eq 'mouse' -and ($_.Wheel -ne 0 -or $_.HWheel -ne 0) })
                if ($w.Count -gt 0) { $st.LastWheel = [long]$w[$w.Count - 1].Time }
                $Ctx.Form.SetProgress([int]($now - $start), $hold)
                if (($now - $st.LastWheel) -gt 1500) {
                    $Ctx.Form.SetStatus(('「{0}」を押したまま、スクロールを続けてください' -f $keys.scroll.legend), 3)
                } else {
                    $Ctx.Form.SetStatus(('スクロールを続けてください (残り {0} 秒)' -f [math]::Ceiling(($hold - ($now - $start)) / 1000.0)), 0)
                }
            }
            $Ctx.Form.SetProgress(0, 0)
            if ($r2.Outcome -eq 'abort') { return 'abort' }
            if ($r2.Outcome -eq 'skip') { return (New-KcRgResult 'NONE' '(スキップ)') }
            $wheels = @($r2.Events | Where-Object { $_.Kind -eq 'mouse' -and ($_.Wheel -ne 0 -or $_.HWheel -ne 0) })
            if ($wheels.Count -eq 0 -or ($Ctx.Form.NowMs - [long]$wheels[$wheels.Count - 1].Time) -gt 2000) {
                return (New-KcRgResult 'NONE' '(スクロールが途中で止まった)' 'カウントダウンが終わるまで、スクロールを続けてください')
            }
            $lastScroll = [long]$wheels[$wheels.Count - 1].Time
            $Ctx.Form.SetTexts($item, ('ボールから手を離し、「{0}」を離してから、すぐに「{0}」を押したまま「{1}」を押してください' -f $keys.scroll.legend, $keys.click.legend),
                ("AML が残っていれば「{0}」でクリックになり、文字は入力されません。{1} 秒以内に押してください。`nクリックはこのウィンドウの中だけで起きます。" -f $keys.click.legend, ($within / 1000)))
            $Ctx.Form.ClearEvents()
            $Ctx.Form.Confine($true)
            $btn = [int]$keys.click.button
            $r3 = Wait-KcStep -Ctx $Ctx -TimeoutMs ($within + 5000) -Done {
                param($ev, $now)
                $m = Measure-KcMotion $ev
                if (Test-KcButtonClicked $m $btn) { return ($now - @($ev)[@($ev).Count - 1].Time) -ge 300 }
                Test-KcKeysSettled $ev $Ctx.ScanTable $now 400
            }
            $Ctx.Form.Confine($false)
            if ($r3.Outcome -eq 'abort') { return 'abort' }
            if ($r3.Outcome -ne 'done') { return (New-KcRgResult 'NONE' '(入力なし)') }
            $t = Test-KcAmlStillOn $r3.Events ([int]$keys.click.button) ([int]$keys.scroll.usage) ([int]$keys.after_timeout.usage) (Get-KcAmlThreshold $Ctx) $Ctx.ScanTable $lastScroll $timeout
            Show-KcStepResult $Ctx $t.Status ($t.Actual + ' ' + $t.Message)
            Wait-KcPause $Ctx 800
            return $t
        }
        if ($res -is [string]) { return $res }
        Add-KcRgRow $Ctx $item $res.Status $res.Actual $res.Message (@($res.Details) + (Get-KcFirstAttemptDetails $res))
    }
    return 'done'
}

# 抜き挿しの後も、キーとボールが効く。target ごとに、挿す → 確認 → 抜く → 確認 を repeat 回。
# start が plugged の target (つないだ状態から始める) は、抜く → (確認) → 挿す → 確認 の順
function Invoke-KcRgReplug($Ctx, $Check) {
    $p = $Check.Params
    $repeat = [int]$p.repeat
    $settle = [int](Get-KcProp $p 'settle_ms' 3000)
    $note = [string](Get-KcProp $p 'start_note' '')
    $o = Wait-KcRgButton $Ctx $Check.Title '準備ができたら「次へ」を押してください' $note
    if ($o -eq 'abort') { return 'abort' }
    if ($o -eq 'skip') { Add-KcRgRow $Ctx '抜き挿し' 'SKIP' 'スキップしました'; return 'done' }
    foreach ($tg in @($p.targets)) {
        $label = [string]$tg.label
        $usages = Get-KcRgUsages $Ctx @($tg.keys)
        $ball = [bool](Get-KcProp $tg 'ball' $false)
        $usb = [bool](Get-KcProp $tg 'usb' $false)
        $respond = [int](Get-KcProp $tg 'respond_ms' 15000)
        $afterUnplug = [bool](Get-KcProp $tg 'check_after_unplug' $true)
        $phases = @('plug', 'unplug')
        if ([string](Get-KcProp $tg 'start' 'unplugged') -eq 'plugged') { $phases = @('unplug', 'plug') }
        $keyText = ((@($tg.keys) | ForEach-Object { '「{0}」' -f $_ }) -join '')
        $want = $keyText + 'を押し' + $(if ($ball) { '、ボールを少し転がして' } else { 'て' }) + 'ください'
        $fails = New-Object 'System.Collections.Generic.List[string]'
        $infos = New-Object 'System.Collections.Generic.List[string]'
        $checks = 0
        $passed = 0
        $skipped = $false
        for ($n = 1; $n -le $repeat -and -not $skipped; $n++) {
            foreach ($phase in $phases) {
                $text = [string]$tg.$phase
                $title = '{0}: {1} / {2} 回目' -f $label, $(if ($phase -eq 'plug') { '挿す' } else { '抜く' }), $n
                $until = $null
                if ($usb) {
                    $wantUsb = ($phase -eq 'plug')
                    $until = { param($ev, $now) (Test-KcRgUsbPresent $Ctx) -eq $wantUsb }
                }
                $detail = if ($usb) { 'USB の認識・切断を見て、自動で次へ進みます (進まなければ「次へ」)。' } else { '終わったら「次へ」を押してください。' }
                $o = Wait-KcRgButton $Ctx $title $text $detail '次へ' '' $until
                if ($o -eq 'abort') { return 'abort' }
                if ($o -eq 'skip') { $skipped = $true; break }
                if ($usb) {
                    $infos.Add(('{0} 回目・{1}: USB {2}' -f $n, $(if ($phase -eq 'plug') { '挿した' } else { '抜いた' }), $(if ($o -eq 'done') { $(if ($phase -eq 'plug') { 'を認識した' } else { 'が切れた' }) } else { 'の変化は見えなかった (「次へ」で進んだ)' })))
                }
                if ($phase -eq 'unplug' -and -not $afterUnplug) {
                    continue
                }
                $c = Wait-KcRgCountdown $Ctx $settle $title '少し待ってください' '起動や接続の切り替えを待っています。'
                if ($c -eq 'abort') { return 'abort' }
                if ($c -eq 'skip') { $skipped = $true; break }
                $w = Wait-KcRgInput $Ctx $usages $ball $respond $title $want ('{0} 秒以内に届けば合格です。PC 本体のキーボードやマウスには触らないでください。' -f ($respond / 1000))
                if ($w.Outcome -eq 'abort') { return 'abort' }
                if ($w.Outcome -eq 'skip') { $skipped = $true; break }
                $checks++
                $when = '{0} 回目・{1}' -f $n, $(if ($phase -eq 'plug') { '挿した後' } else { '抜いた後' })
                if ($w.Missing.Count -eq 0) {
                    $passed++
                    if ($w.Transport) { $infos.Add(('{0}: 入力の経路 {1}' -f $when, $w.Transport)) }
                    Show-KcStepResult $Ctx 'PASS' ('{0}: 届きました' -f $when)
                } else {
                    $fails.Add(('{0}: {1} 秒たっても {2} が届かない' -f $when, ($respond / 1000), ($w.Missing -join '、')))
                    Show-KcStepResult $Ctx 'FAIL' ('{0}: 届きませんでした ({1})' -f $when, ($w.Missing -join '、'))
                }
                if ($w.AnyDevice) { $infos.Add(('{0}: この機種のデバイス (VID / PID) が Raw Input に見つからなかった' -f $when)) }
                Wait-KcPause $Ctx 800
            }
        }
        Reset-KcRgDevices $Ctx
        $details = @($fails.ToArray()) + @($infos.ToArray())
        if ($fails.Count -gt 0) {
            Add-KcRgRow $Ctx $label 'FAIL' ('{0} / {1} 回で効かなくなった' -f $fails.Count, $checks) 'キーやボールが効かなくなったら、電源を入れ直してください' $details
        } elseif ($skipped -or $checks -eq 0) {
            Add-KcRgRow $Ctx $label 'SKIP' ('{0} 回まで確かめてスキップ' -f $passed) '' $details
        } else {
            Add-KcRgRow $Ctx $label 'PASS' ('{0} / {0} 回、キーとボールが効いた' -f $checks) '' $details
        }
    }
    $ask = [string](Get-KcProp $p 'ask' '')
    if ($ask) {
        $a = Wait-KcRgYesNo $Ctx $Check.Title $ask ''
        if ($a -eq 'abort') { return 'abort' }
        $st = switch ($a) { 'yes' { 'PASS' } 'no' { 'FAIL' } default { 'SKIP' } }
        Add-KcRgRow $Ctx '目で確かめる' $st $ask
    }
    return 'done'
}

# この機種のマイコン (flash-plan.ps1 の $FlashKeyboards。無ければ XIAO)
function Get-KcRgMcu($Ctx) {
    $fk = Get-Variable -Name 'FlashKeyboards' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $fk -and $fk.Contains([string]$Ctx.Options.Board)) {
        return [string]$fk[[string]$Ctx.Options.Board].Mcu
    }
    return 'XIAO'
}

# 配列を返す (return , $x)。呼び出し側は変数に受けてから使う (@() で包むと、配列が 1 つの値になる)
function Get-KcRgUf2Drives($Ctx, [string]$Mcu) {
    $all = & $Ctx.Probe.FindUf2Drives
    return , @(@($all) | Where-Object { Test-KcUf2DriveBoard $Mcu ([string]$_.Label) ([string]$_.Info) })
}

function Test-KcRgUf2Present($Ctx, [string]$Mcu) {
    $d = Get-KcRgUf2Drives $Ctx $Mcu
    return ($d.Count -gt 0)
}

# この機種のデバイスのハンドル
function Get-KcRgTargetHandles($Ctx) {
    $t = Get-KcRgTargetDevices $Ctx
    return , [long[]]@(@($t) | ForEach-Object { [long]$_.Handle })
}

# ブートローダのドライブが無くなるまで待つ。戻り値: done (無い) / skip / abort / next (残ったまま「次へ」)
function Wait-KcRgNoUf2($Ctx, [string]$Mcu, [string]$Title, [string]$Back) {
    $present = Get-KcRgUf2Drives $Ctx $Mcu
    if ($present.Count -eq 0) { return 'done' }
    $o = Wait-KcRgButton $Ctx $Title ('ブートローダのドライブ ({0}) があります。{1}' -f $present[0].Root, $Back) 'ドライブが消えると、自動で次へ進みます。' '次へ' '' {
        param($ev, $now) -not (Test-KcRgUf2Present $Ctx $Mcu)
    }
    if ($o -eq 'next' -and -not (Test-KcRgUf2Present $Ctx $Mcu)) { return 'done' }
    return $o
}

# Q (左) / P (右) を押したまま USB を挿すと、その側がブートローダ (UF2) になる
function Invoke-KcRgBootmagic($Ctx, $Check) {
    $p = $Check.Params
    $mcu = Get-KcRgMcu $Ctx
    $appear = [int](Get-KcProp $p 'appear_ms' 20000)
    $leave = [int](Get-KcProp $p 'leave_ms' 90000)
    $negative = [int](Get-KcProp $p 'negative_ms' 6000)
    $respond = [int](Get-KcProp $p 'respond_ms' 20000)
    $back = if ($mcu -eq 'BMP') { 'USB を抜き、電源スイッチを OFF → ON にして、ふだんの起動に戻してください' } else { 'リセットボタンを 1 回押して、ふだんの起動に戻してください' }
    $switchNote = if ($mcu -eq 'BMP') { ' (電源スイッチは ON のまま。OFF で挿すと、キーを押さなくてもブートローダになります)' } else { '' }
    foreach ($side in @($p.sides)) {
        $label = [string]$side.label
        $key = [string]$side.key
        $usage = Get-KcUsageByLegend $key $Ctx.ScanTable
        # 始める前に、ブートローダのドライブが無いこと (スキップしたら、この側だけ飛ばす)
        $skipSide = $false
        while (Test-KcRgUf2Present $Ctx $mcu) {
            $present = Get-KcRgUf2Drives $Ctx $mcu
            if ($present.Count -eq 0) { break }
            $o = Wait-KcRgButton $Ctx $Check.Title ('ブートローダのドライブ ({0}) があります。{1}' -f $present[0].Root, $back) 'ドライブが消えると、自動で次へ進みます。' '次へ' '' {
                param($ev, $now) -not (Test-KcRgUf2Present $Ctx $mcu)
            }
            if ($o -eq 'abort') { return 'abort' }
            if ($o -eq 'skip') { $skipSide = $true; break }
            if ($o -eq 'next') { break }
        }
        if ($skipSide) {
            Add-KcRgRow $Ctx $label 'SKIP' 'スキップしました'
            continue
        }
        $cases = @(
            @{ Item = ('{0}: 動作中に「{1}」を押したまま挿す' -f $label, $key); KeyCheck = $true
                Text = ('{0}の USB を抜き、電池で動いている状態で、「{1}」を押したまま USB を挿してください{2}' -f $label, $key, $switchNote)
                Detail = ("UF2 のドライブが現れるまで「{0}」を押したままにします (現れたら離す)。`nもう片方が PC につながっていれば、ブートローダに入る前にファームがキーを離したことにするので、PC でキーが押されたままにならないことも確かめます。" -f $key) }
        )
        if ($mcu -ne 'BMP') {
            $cases += @{ Item = ('{0}: 電源 OFF から「{1}」を押したまま挿して起動' -f $label, $key); KeyCheck = $false
                Text = ('{0}の USB を抜いて電源スイッチを OFF にし、「{1}」を押したまま USB を挿してください (電源スイッチが無ければ「スキップ」)' -f $label, $key)
                Detail = ('USB からの電源で起動した直後に「{0}」が押されていても、ブートローダになることを確かめます。ドライブが現れるまで押したままにします。' -f $key)
            }
        }
        foreach ($case in $cases) {
            # 前の手順のドライブが残っていると、操作しなくても合格になってしまうので、消えるまで待つ
            $o = Wait-KcRgNoUf2 $Ctx $mcu $case.Item $back
            if ($o -eq 'abort') { return 'abort' }
            if ($o -ne 'done') { Add-KcRgRow $Ctx $case.Item 'SKIP' 'ブートローダのドライブが残っているため、確かめられません'; continue }
            # もう片方を通して PC に届くキーを受け取るため、この機種のデバイスを入れておく
            $handles = Get-KcRgTargetHandles $Ctx
            $Ctx.Devices = @(@($Ctx.Devices) + @($handles) | Select-Object -Unique)
            $Ctx.Form.ClearEvents()
            $st = @{ Found = $null; FoundAt = [long]0 }
            # ドライブが現れた時刻を、キーが離された時刻と比べるので、短い間隔で見る
            $o = Wait-KcRgButton $Ctx $case.Item $case.Text $case.Detail '次へ' '' {
                param($ev, $now)
                $d = Get-KcRgUf2Drives $Ctx $mcu
                if ($d.Count -gt 0) { $st.Found = $d[0]; $st.FoundAt = $now; return $true }
                $false
            } ($appear + 60000) 200
            if ($o -eq 'abort') { return 'abort' }
            if ($o -eq 'skip') { Add-KcRgRow $Ctx $case.Item 'SKIP' 'スキップしました'; continue }
            if ($null -eq $st.Found) {
                Add-KcRgRow $Ctx $case.Item 'FAIL' 'UF2 のドライブが現れない' ('「{0}」を押したまま挿してもブートローダになりませんでした' -f $key)
                continue
            }
            $events = @(Get-KcProp $Ctx 'LastEvents' @())
            $details = @(('ドライブ {0} (Board-ID: {1})' -f $st.Found.Root, (Get-KcUf2BoardId $st.Found.Info)))
            $status = 'PASS'
            $msg = ''
            if ($case.KeyCheck -and $usage -ge 0) {
                $rel = Test-KcBootmagicRelease $events $usage $st.FoundAt $Ctx.ScanTable
                $details += $rel.Actual
                if ($rel.Status -eq 'FAIL' -or $rel.Status -eq 'WARN') {
                    $status = $rel.Status
                    $msg = $rel.Message
                }
            }
            $Ctx.Form.SetStatus(('ドライブ {0} が現れました。「{1}」を離してください' -f $st.Found.Root, $key), 1)
            Wait-KcPause $Ctx 1500
            $o = Wait-KcRgButton $Ctx $case.Item $back 'ドライブが消えると、自動で次へ進みます。' '次へ' '' {
                param($ev, $now) -not (Test-KcRgUf2Present $Ctx $mcu)
            } $leave
            if ($o -eq 'abort') { return 'abort' }
            if ($o -eq 'timeout') { $details += 'ブートローダのドライブが消えませんでした (リセットしてください)' }
            Add-KcRgRow $Ctx $case.Item $status ('UF2 のドライブが現れた ({0})' -f $st.Found.Root) $msg $details
        }
        # 何も押さずに挿したときは、ブートローダにならず、ふだんどおり入力できる。待つ間もドライブを見続ける
        $item = '{0}: 何も押さずに挿すと、ふだんどおり起動する' -f $label
        $o = Wait-KcRgNoUf2 $Ctx $mcu $item $back
        if ($o -eq 'abort') { return 'abort' }
        if ($o -ne 'done') { Add-KcRgRow $Ctx $item 'SKIP' 'ブートローダのドライブが残っているため、確かめられません'; continue }
        $st = @{ Found = $null }
        $watch = {
            param($ev, $now)
            $d = Get-KcRgUf2Drives $Ctx $mcu
            if ($d.Count -gt 0) { $st.Found = $d[0] }
            $false
        }
        $o = Wait-KcRgButton $Ctx $item ('何も押さずに、{0}の USB を抜いて挿し直し、挿したら「次へ」を押してください{1}' -f $label, $switchNote) 'UF2 のドライブが現れないことを確かめます。' '次へ' '' $watch
        if ($o -eq 'abort') { return 'abort' }
        if ($o -eq 'skip') { Add-KcRgRow $Ctx $item 'SKIP' 'スキップしました'; continue }
        $Ctx.Form.SetTexts($item, 'そのまま待ってください', 'UF2 のドライブが現れないことを確かめています。')
        $c = Wait-KcStep -Ctx $Ctx -TimeoutMs $negative -CheckIntervalMs 300 -Done $watch
        if ($c.Outcome -eq 'abort') { return 'abort' }
        if ($c.Outcome -eq 'skip') { Add-KcRgRow $Ctx $item 'SKIP' 'スキップしました'; continue }
        if ($null -ne $st.Found) {
            Add-KcRgRow $Ctx $item 'FAIL' ('UF2 のドライブが現れた ({0})' -f $st.Found.Root) 'キーを押していないのにブートローダになりました'
            continue
        }
        Reset-KcRgDevices $Ctx
        $w = Wait-KcRgInput $Ctx (Get-KcRgUsages $Ctx @($key)) $false $respond $item ('「{0}」を押してください' -f $key) 'ふだんどおり起動して、キーが届けば合格です。'
        if ($w.Outcome -eq 'abort') { return 'abort' }
        if ($w.Outcome -eq 'skip') {
            Add-KcRgRow $Ctx $item 'SKIP' 'ブートローダにはならなかった (キーの確認はスキップ)'
        } elseif ($w.Missing.Count -eq 0) {
            Add-KcRgRow $Ctx $item 'PASS' 'ブートローダにならず、キーが届いた'
        } else {
            Add-KcRgRow $Ctx $item 'FAIL' ('{0} が届かない' -f ($w.Missing -join '、')) 'ブートローダにはなりませんでしたが、キーが届きませんでした'
        }
    }
    Reset-KcRgDevices $Ctx
    return 'done'
}

# ログ版で使い続けても止まらず、スタックに余裕がある (thread analyzer)。COM ポートは読むだけで、何も送らない
function Invoke-KcRgLoggingSoak($Ctx, $Check) {
    $p = $Check.Params
    $dumps = [int]$p.dumps
    $maxMs = [int]$p.max_ms
    $startMs = [int](Get-KcProp $p 'start_ms' 30000)
    $respond = [int](Get-KcProp $p 'respond_ms' 15000)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $ls = @{ First = [long]-1; LastLine = [long]-1; Headers = 0; LastHeader = [long]-1; Port = '' }
    $reader = & $Ctx.Probe.NewLogReader ([string](Get-KcProp $Ctx.Options 'Port' ''))
    $cands = @(Get-KcProp $reader 'Candidates' @('?'))
    $read = {
        param($now)
        $got = & $Ctx.Probe.ReadLog $reader
        if ($null -ne $got.Status) { $Ctx.Form.SetStatus([string]$got.Status, [int]$got.Level) }
        foreach ($l in @($got.Lines)) {
            $lines.Add([string]$l)
            $rec = ConvertFrom-KcZmkLogLine $l
            if ($null -ne $rec -and $rec.Time -ge 0) {
                if ($ls.First -lt 0) { $ls.First = $now }
                $ls.LastLine = $now
            }
            $ta = ConvertFrom-KcThreadAnalyzerLine $l
            if ($null -ne $ta -and $ta.Kind -eq 'header') { $ls.Headers++; $ls.LastHeader = $now }
        }
        $name = [string](Get-KcProp $reader 'ActiveName' '')
        if ($name) { $ls.Port = $name }
    }
    try {
        $item = 'ログ版が止まらない'
        if ($cands.Count -eq 0) {
            Add-KcRgRow $Ctx $item 'SKIP' 'ログ版の COM ポートが見つかりません' 'ログ版のファームを右手側に書き込み、USB でつないでから行ってください (tools/flash.cmd で右手側の版を「ログ版」にする)'
            return 'done'
        }
        if ($cands.Count -gt 1) {
            # ほかの ZMK キーボードのログと取り違えないように
            Add-KcRgRow $Ctx 'COM ポート' 'WARN' ('ZMK の COM ポートが {0} 個 ({1})' -f $cands.Count, ($cands -join ', ')) 'ほかの ZMK キーボードを USB から外すか、-Port で COM ポートを指定してください'
        }
        $o = Initialize-KcRgDevices $Ctx $true
        if ($o -ne 'done') { return $o }
        $Ctx.Form.SetTexts($item, 'キーを 1 つ押してください (ログの受信を始めます)',
            "右手側にログ版のファーム (*_logging.uf2) を書き込み、USB でつないでおきます。`nCOM ポートは読むだけで、何も送りません。")
        $r = Wait-KcStep -Ctx $Ctx -TimeoutMs $startMs -CheckIntervalMs 100 -OnTick { param($ev, $now) & $read $now } -Done { param($ev, $now) $ls.First -ge 0 }
        if ($r.Outcome -eq 'abort') { return 'abort' }
        if ($r.Outcome -eq 'skip') {
            Add-KcRgRow $Ctx $item 'SKIP' 'スキップしました'
            return 'done'
        }
        if ($ls.First -lt 0) {
            Add-KcRgRow $Ctx $item 'SKIP' 'ログが届きません' 'ログ版のファームを右手側に書き込み、USB でつないでください (tools/flash.cmd で右手側の版を「ログ版」にする)'
            return 'done'
        }
        $Ctx.Form.SetTexts($item, 'キーを打ったり、ボールを転がしたりし続けてください',
            ('thread analyzer (スレッドごとのスタックの最大使用量。30 秒ごとに出る) が {0} 回出るまで続けます (長くても {1} 秒)。' -f $dumps, ($maxMs / 1000)))
        $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 0 -CheckIntervalMs 100 -OnTick {
            param($ev, $now)
            & $read $now
            $Ctx.Form.SetProgress([int][math]::Min($maxMs, $now - $ls.First), $maxMs)
            $Ctx.Form.SetStatus(('thread analyzer {0} / {1} 回 ({2} 秒)' -f $ls.Headers, $dumps, [math]::Floor(($now - $ls.First) / 1000)), 0)
        } -Done {
            param($ev, $now)
            (($ls.Headers -ge $dumps) -and (($now - $ls.LastHeader) -ge 2000)) -or (($now - $ls.First) -ge $maxMs)
        }
        $Ctx.Form.SetProgress(0, 0)
        if ($r.Outcome -eq 'abort') { return 'abort' }
        if ($r.Outcome -eq 'skip') {
            Add-KcRgRow $Ctx $item 'SKIP' 'スキップしました'
            return 'done'
        }
        $p2 = Get-KcRgUsages $Ctx @('P')
        $w = Wait-KcRgInput $Ctx $p2 $true $respond $item '最後に「P」を押して、ボールを転がしてください' 'キーとボールの入力が届き、そのキーのログも届けば、止まっていません。' { param($ev, $now) & $read $now }
        if ($w.Outcome -eq 'abort') { return 'abort' }
        if ($w.Outcome -eq 'skip') {
            Add-KcRgRow $Ctx $item 'SKIP' '最後の確認をスキップしました'
            return 'done'
        }
        # 最後に押したキーの後に、ログが届いたか (ログは deferred でまとめて届くので、少し待つ)
        $keys = @($w.Events | Where-Object { $_.Kind -eq 'key' })
        $keyTime = [long]$Ctx.Form.NowMs
        if ($keys.Count -gt 0) { $keyTime = [long]$keys[$keys.Count - 1].Time }
        if ($ls.LastLine -lt $keyTime) {
            [void](Wait-KcStep -Ctx $Ctx -TimeoutMs 3000 -CheckIntervalMs 100 -OnTick { param($ev, $now) & $read $now } -Done { param($ev, $now) $ls.LastLine -ge $keyTime })
        }
        $logAfter = ($ls.LastLine -ge $keyTime)
        $details = @(('ポート {0}、ログ {1} 行' -f $ls.Port, $lines.Count))
        if ($w.Missing.Count -eq 0 -and $logAfter) {
            Add-KcRgRow $Ctx $item 'PASS' ('最後までキー・ボール・ログが届いた (約 {0} 秒)' -f [math]::Round(($Ctx.Form.NowMs - $ls.First) / 1000)) '' $details
        } else {
            $what = @()
            if ($w.Missing.Count -gt 0) { $what += ('{0} が届かない' -f ($w.Missing -join '、')) }
            if (-not $logAfter) { $what += '最後のキーのあとにログが届かない' }
            Add-KcRgRow $Ctx $item 'FAIL' ($what -join '、') 'ファームが止まったかもしれません。電源を入れ直してください' $details
        }
        $soak = Measure-KcLoggingSoak $lines.ToArray()
        $normal = [int](Get-KcProp (Get-KcProp $Ctx.Expected.device 'stacks' $null) 'input' 0)
        foreach ($row in (Get-KcLoggingSoakRows $soak $dumps ([int](Get-KcProp $p 'warn_pct' 75)) ([int](Get-KcProp $p 'fail_pct' 90)) $normal ([int](Get-KcProp $p 'normal_warn_pct' 75)))) {
            Add-KcRgRow $Ctx $row.Item $row.Status $row.Actual $row.Message @($row.Details)
        }
        if ($Ctx.Options.CacheDir -and $lines.Count -gt 0) {
            try {
                $dir = Join-Path $Ctx.Options.CacheDir 'regression'
                if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
                $path = Join-Path $dir ('{0}-{1}-logging.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Ctx.Expected.id)
                [System.IO.File]::WriteAllLines($path, $lines.ToArray(), (New-Object System.Text.UTF8Encoding($false)))
                [void](Add-KcResult -Results $Ctx.Results -Category $Ctx.Category -Item 'ログ' -Status INFO -Actual $path -Reference)
            } catch {
                # 保存できなくても、判定には使わない
            }
        }
        return 'done'
    } finally {
        & $Ctx.Probe.CloseLog $reader
    }
}

# スリープ (deep sleep) からキーを押して戻れる。電池で、スリープの時間 + margin_ms の間触らずに置く
function Invoke-KcRgIdleWake($Ctx, $Check) {
    $p = $Check.Params
    $item = 'スリープから戻る'
    $sleep = Get-KcProp $Ctx.Expected.device 'sleep_timeout_ms' $null
    $details = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $sleep) {
        $sleep = [int](Get-KcProp $p 'default_idle_ms' 1800000)
        $details.Add(('期待値にスリープの時間が無いので、{0} 分として待った' -f ($sleep / 60000)))
    }
    $total = [int]$sleep + [int](Get-KcProp $p 'margin_ms' 60000)
    $o = Initialize-KcRgDevices $Ctx $true
    if ($o -ne 'done') { return $o }
    if (Test-KcRgUsbPresent $Ctx) {
        $o = Wait-KcRgButton $Ctx $item '両手の USB を抜いてください' 'USB から電源をとっている間はスリープしません。USB が抜けると、自動で次へ進みます。' '次へ' '' {
            param($ev, $now) -not (Test-KcRgUsbPresent $Ctx)
        }
        if ($o -eq 'abort') { return 'abort' }
        if ($o -eq 'skip') { Add-KcRgRow $Ctx $item 'SKIP' 'スキップしました'; return 'done' }
        if ($o -eq 'next') { $details.Add('USB でつながったまま (この機種でないかもしれない) で始めた') }
    }
    $mins = [math]::Ceiling($total / 60000.0)
    $o = Wait-KcRgButton $Ctx $item ('{0} 分触らずに置いて、スリープさせます' -f $mins) `
        ("「始める」でカウントダウンを始めます。この間、PC がスリープ・画面オフにならないようにします。`nすでに {0} 分以上触らずに置いてあるなら「もう置いてある」を押してください。" -f $mins) '始める' 'もう置いてある'
    if ($o -eq 'abort') { return 'abort' }
    if ($o -eq 'skip') { Add-KcRgRow $Ctx $item 'SKIP' 'スキップしました'; return 'done' }
    if ($o -eq 'next') {
        $handles = Get-KcRgTargetHandles $Ctx
        $touch = @($Ctx.Devices) + @($handles)
        & $Ctx.Probe.KeepAwake $true
        try {
            $c = Wait-KcRgCountdown $Ctx $total $item 'キーボードとボールに触らずに待ってください' ('スリープの時間 ({0} 分) + 1 分。触ると、カウントダウンをやり直します。PC 本体のキーボードやマウスは使って構いません。' -f ($sleep / 60000)) $touch
        } finally {
            & $Ctx.Probe.KeepAwake $false
        }
        if ($c -eq 'abort') { return 'abort' }
        if ($c -eq 'skip') { Add-KcRgRow $Ctx $item 'SKIP' 'スキップしました'; return 'done' }
    } else {
        $details.Add('カウントダウンを飛ばした (すでに置いてあった)')
    }
    Reset-KcRgDevices $Ctx
    $keys = @($p.keys)
    $respond = [int](Get-KcProp $p 'respond_ms' 90000)
    $w = Wait-KcRgInput $Ctx (Get-KcRgUsages $Ctx $keys) $true $respond $item `
        ('右手側のキーを 1 回押して起こし、3 秒ほど待ってから左手側のキーを 1 回押して起こしてください。そのあと {0} を押し、ボールを転がしてください' -f ((@($keys) | ForEach-Object { '「{0}」' -f $_ }) -join '')) `
        '起こすために押したキーは PC に届きません。BLE につながり直すまで数秒かかります。'
    if ($w.Outcome -eq 'abort') { return 'abort' }
    if ($w.Outcome -eq 'skip') {
        Add-KcRgRow $Ctx $item 'SKIP' '最後の確認をスキップしました' '' $details.ToArray()
        return 'done'
    }
    $details.Add('スリープに入ったこと自体は確かめていません (LED などで確かめてください)')
    if ($w.Transport) { $details.Add(('入力の経路 {0}' -f $w.Transport)) }
    if ($w.Missing.Count -eq 0) {
        Add-KcRgRow $Ctx $item 'PASS' 'キーを押して戻り、両手のキーとボールが効いた' '' $details.ToArray()
    } else {
        Add-KcRgRow $Ctx $item 'FAIL' ('{0} 秒たっても {1} が届かない' -f ($respond / 1000), ($w.Missing -join '、')) 'リセットボタンでしか戻らないときは、kscan に wakeup-source が無いかもしれません' $details.ToArray()
    }
    return 'done'
}

# ドラッグ中に A (長押しで Ctrl) を押しても、ボタンが離されない (KQ-mini#14)
function Invoke-KcRgDragHold($Ctx, $Check) {
    $o = Initialize-KcRgDevices $Ctx $true
    if ($o -ne 'done') { return $o }
    $tb = $Ctx.Expected.interactive.trackball
    $ball = @($Ctx.Balls)[0]
    $keys = Get-KcHandKeys $tb $ball
    $item = 'ドラッグ中にキーを押しても切れない'
    $res = Invoke-KcRetryStep $Ctx {
        $Ctx.Form.SetTexts($item,
            ('ボールを転がしてから、「{0}」を押したまま「{1}」を押します。「{1}」は押したまま「{0}」を離し、ボールを転がして (ドラッグ)、「{2}」を長押ししてから離し、最後に「{1}」を離してください' -f $keys.scroll.legend, $keys.click.legend, $keys.release_ctrl.legend),
            ("ドラッグの途中で「{0}」(長押しで Ctrl) を押しても、マウスのボタンが離されなければ合格です。`nドラッグはこのウィンドウの中だけで起きます。" -f $keys.release_ctrl.legend))
        $Ctx.Form.ClearEvents()
        $Ctx.Form.Confine($true)
        $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 60000 -Done {
            param($ev, $now)
            $m = Measure-KcMotion $ev
            $ups = @($m.Buttons | Where-Object { -not $_.Down })
            ($ups.Count -gt 0) -and ((Test-KcKeysSettled $ev $Ctx.ScanTable $now 600) -or (($now - [long]$ups[$ups.Count - 1].Time) -ge 1500))
        }
        $Ctx.Form.Confine($false)
        if ($r.Outcome -eq 'abort') { return 'abort' }
        if ($r.Outcome -eq 'skip') { return (New-KcRgResult 'NONE' '(スキップ)') }
        $t = Test-KcDragHold $r.Events ([int]$keys.click.button) @(224, 228) $Ctx.ScanTable
        Show-KcStepResult $Ctx $t.Status ($t.Actual + ' ' + $t.Message)
        Wait-KcPause $Ctx 800
        return $t
    }
    if ($res -is [string]) { return $res }
    Add-KcRgRow $Ctx $item $res.Status $res.Actual $res.Message (@($res.Details) + (Get-KcFirstAttemptDetails $res))
    return 'done'
}

# ---------------------------------------------------------------------------
# 全体
# ---------------------------------------------------------------------------

# $Entries: Select-KcRegressionChecks の項目のうち、行うもの。$Options:
#   Board; Firmware (ZMK の右手側の答え。QMK は空); Port; Balls (ボール); CacheDir; HistoryPath;
#   Readout (scriptblock: param($Results)。読み出し検査); Probe (省略すると Windows のもの); Form (テスト用。省略するとウィンドウを開く)
function Invoke-KcRegressionTest {
    param(
        [Parameter(Mandatory = $true)] $Expected,
        [Parameter(Mandatory = $true)] $Common,
        [Parameter(Mandatory = $true)] $Results,
        [Parameter(Mandatory = $true)] $Entries,
        [Parameter(Mandatory = $true)] [hashtable]$Options
    )
    $ctx = New-KcInputContext $Expected $Common $Results @{}
    $ctx.Options = $Options
    $ctx.Probe = Get-KcProp $Options 'Probe' $null
    if ($null -eq $ctx.Probe) { $ctx.Probe = New-KcRegressionProbe }
    $ctx.Balls = @(Get-KcProp $Options 'Balls' @($Expected.interactive.trackball.balls))
    $ctx.Check = $null
    $ctx.Transport = ''
    $console = @($Entries | Where-Object { $script:KcRgConsoleHandlers -contains $_.Check.Handler })
    $window = @($Entries | Where-Object { $script:KcRgConsoleHandlers -notcontains $_.Check.Handler })
    $history = New-Object 'System.Collections.Generic.List[object]'
    $sources = (@($Expected.sources) | ForEach-Object { '{0}@{1}' -f $_.submodule, ([string]$_.commit).Substring(0, [math]::Min(7, ([string]$_.commit).Length)) }) -join ' '
    $state = @{ Aborted = $false }
    $run = {
        param($e)
        $c = $e.Check
        $ctx.Check = $c
        $ctx.Category = '回帰: {0}' -f $c.Title
        $ctx.Transport = ''
        $start = $Results.Count
        [void](Add-KcResult -Results $Results -Category $ctx.Category -Item '過去の不具合' -Status INFO -Actual (Format-KcRegressionPrs $c) -Details @($c.Symptom) -Reference)
        if ($state.Aborted) {
            Add-KcRgRow $ctx '回帰テスト' 'SKIP' '途中で中止したため、行いませんでした'
        } else {
            $fn = $script:KcRegressionHandlers[$c.Handler].Fn
            $o = & $fn $ctx $c
            if ($o -eq 'abort') {
                $state.Aborted = $true
                Add-KcRgRow $ctx '回帰テスト' 'SKIP' '途中で中止しました'
            }
        }
        $rows = @(for ($i = $start; $i -lt $Results.Count; $i++) { $Results[$i] })
        $history.Add(@{
                time = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); board = [string]$Options.Board; check = $c.Id; status = (Get-KcRegressionStatus $rows)
                hash = (Get-KcRegressionCheckHash $c); firmware = [string](Get-KcProp $Options 'Firmware' ''); expected = $sources
                transport = [string]$ctx.Transport; build = '不明'
            })
    }
    # 読み出し → ウィンドウ → 答えるだけの項目、の順
    foreach ($e in @($console | Where-Object { $_.Check.Handler -eq 'readout' })) { & $run $e }
    if ($window.Count -gt 0 -and -not $state.Aborted) {
        $form = Get-KcProp $Options 'Form' $null
        $own = ($null -eq $form)
        if ($own) { $form = New-KcInputForm $Expected }
        $ctx.Form = $form
        $consoleMode = $null
        if ($own) { $consoleMode = [KcConsoleMode]::DisableQuickEdit() }
        try {
            if ($own) { $form.MaskWinKey($true) }
            foreach ($e in $window) {
                if ($own -and (Wait-KcForeground $ctx) -eq 'abort') { $state.Aborted = $true }
                & $run $e
            }
            if (-not $state.Aborted) {
                $form.SetTexts('完了', '回帰テストが終わりました', '結果はコンソールに表示されます。')
                Wait-KcPause $ctx 800
            }
        } finally {
            if ($own) {
                $form.Confine($false)
                $form.MaskWinKey($false)
                $form.Close()
                $form.Dispose()
                [KcConsoleMode]::Restore($consoleMode)
                try { $Host.UI.RawUI.FlushInputBuffer() } catch { }
            }
        }
    } elseif ($window.Count -gt 0) {
        foreach ($e in $window) { & $run $e }
    }
    foreach ($e in @($console | Where-Object { $_.Check.Handler -ne 'readout' })) { & $run $e }
    if ($Options.HistoryPath) {
        try {
            Add-KcRegressionHistory $Options.HistoryPath $history.ToArray()
        } catch {
            # 前回の結果を残せなくても、今回の結果は表示する
        }
    }
    return $(if ($state.Aborted) { 'abort' } else { 'done' })
}
