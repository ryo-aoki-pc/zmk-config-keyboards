# 実動作テストの「レイヤー・ビヘイビア」(GUI)。レイヤーの移動 (押したまま)、長押し (mod-tap)、モッドモーフ、
# タップダンス、&to の切り替え、コンボを、期待値 (interactive.behaviors.scenarios) の手順どおりに押してもらい、
# PC に届いた入力を behavior-eval.ps1 で判定する。Windows のみ。
# input-test.ps1 (Invoke-KcInputTest) から呼ぶ。expected.ps1 / results.ps1 / input-eval.ps1 / behavior-eval.ps1 /
# input-test.ps1 が先に読み込まれている前提。
#
# 画面: 上にレイヤーの帯 (この手順で通るレイヤー → と、全レイヤーの結果)、手順のチップ (押したまま + タップ → …)、
# キーボードの図 (その手順のレイヤーの表示。押したままのキーは紫 / 修飾キーは橙、タップするキーは青く光り、押す順の
# バッジが付く。押さないキーは赤の斜線)、期待する入力と実際の入力のキーキャップ (一致は緑、違いは赤)。

# 手順のチップの見出し
$script:KcBehaviorChip = @{
    layer = '押したまま'; mod = '押したまま (修飾)'; tap = 'タップ'; combo = '同時に押す'; release = ''; check = '確認'
}

# 期待値のレイヤー → 表示 (位置ごと) と押さない位置
function Get-KcBehaviorLayer($Ctx, [int]$Index) {
    foreach ($l in @($Ctx.Behaviors.layers)) {
        if ([int]$l.index -eq $Index) {
            return $l
        }
    }
    return $null
}

# レイヤーの番号 → 名前
function Get-KcBehaviorLayerName($Ctx, [int]$Index) {
    $l = Get-KcBehaviorLayer $Ctx $Index
    if ($null -ne $l) {
        return [string]$l.name
    }
    return ('L{0}' -f $Index)
}

# 全レイヤーの結果のチップ
function Update-KcBehaviorOverview($Ctx, [int]$Current) {
    $names = @()
    $states = @()
    foreach ($l in @($Ctx.Behaviors.layers)) {
        $i = [int]$l.index
        $names += [string]$l.name
        $t = $Ctx.LayerTally[$i]
        $st = [KcInputTestForm]::LayerSkip
        if ($Ctx.TestedLayers -contains $i) {
            $st = [KcInputTestForm]::LayerIdle
        }
        if ($null -ne $t) {
            if ($t.Fail -gt 0) {
                $st = [KcInputTestForm]::LayerFail
            } elseif ($t.Pass -gt 0 -and $t.Pass + $t.Skip -ge $t.Total) {
                $st = [KcInputTestForm]::LayerPass
            } else {
                $st = [KcInputTestForm]::LayerIdle
            }
        }
        if ($i -eq $Current) {
            $st = [KcInputTestForm]::LayerTesting
        }
        $states += $st
    }
    $Ctx.Form.SetLayerOverview('レイヤー', [string[]]$names, [int[]]$states)
}

# 図・レイヤーの帯・手順のチップ・期待する入力を、手順に合わせて出す
function Show-KcBehaviorStep($Ctx, $Scenario, $Step, [string]$Title) {
    $form = $Ctx.Form
    $layer = [int]$Step.layer
    $form.ClearKeyStates()
    $form.ClearKeyBadges()
    $form.ResetKeyLegends()
    $pos = @($Ctx.KeyPositions)
    $info = Get-KcBehaviorLayer $Ctx $layer
    if ($null -ne $info) {
        $legends = @($info.legends)
        $form.SetKeyLegends([int[]]$pos, [string[]]@($pos | ForEach-Object { if ($_ -lt $legends.Count) { [string]$legends[$_] } else { '' } }))
        foreach ($d in @($info.danger)) {
            $form.SetKeyState([int]$d, [KcInputTestForm]::StateDanger)
        }
    }
    # 押すキーは、押すときのレイヤーの表示にする (&to で入る前の「V」など)
    $badges = @{}
    $n = 0
    $captions = @(); $texts = @(); $kinds = @(); $joiners = @()
    $prevHold = $false
    foreach ($a in @($Step.actions)) {
        $op = [string]$a.op
        $role = [string](Get-KcProp $a 'role' '')
        $alayer = [int](Get-KcProp $a 'layer' $layer)
        $ainfo = Get-KcBehaviorLayer $Ctx $alayer
        $positions = @(Get-KcProp $a 'positions' @(Get-KcProp $a 'pos' @()))
        if ($op -ne 'release') {
            $n++
        }
        foreach ($p in $positions) {
            $p = [int]$p
            if ($null -ne $ainfo -and $p -lt @($ainfo.legends).Count) {
                $form.SetKeyLegends([int[]]@($p), [string[]]@([string]$ainfo.legends[$p]))
            }
            $state = [KcInputTestForm]::StateCurrent
            if ($op -eq 'hold' -and $role -eq 'layer') { $state = [KcInputTestForm]::StateHold }
            elseif ($op -eq 'hold') { $state = [KcInputTestForm]::StateMod }
            elseif ($op -eq 'combo') { $state = [KcInputTestForm]::StateCombo }
            $form.SetKeyState($p, $state)
            $b = [string]$n
            $count = [int](Get-KcProp $a 'count' 1)
            if ($count -gt 1) { $b += ('×{0}' -f $count) }
            if ($badges.ContainsKey($p)) { $badges[$p] += ',' + $b } else { $badges[$p] = $b }
        }
        # チップ
        $kind = [KcInputTestForm]::ChipTap
        $caption = $script:KcBehaviorChip.tap
        $text = [string](Get-KcProp $a 'key' '')
        switch ($op) {
            'hold' {
                if ($role -eq 'layer') {
                    $kind = [KcInputTestForm]::ChipLayer; $caption = $script:KcBehaviorChip.layer
                    $label = [string](Get-KcProp $a 'label' '')
                    if ($label -and $label -ne $text) { $text = '{0} ({1})' -f $text, $label }
                } else {
                    $kind = [KcInputTestForm]::ChipMod; $caption = $script:KcBehaviorChip.mod
                    $text = '{0} ({1})' -f $text, [string](Get-KcProp $a 'label' '')
                }
            }
            'tap' {
                $count = [int](Get-KcProp $a 'count' 1)
                if ($count -gt 1) { $caption = '素早く {0} 回タップ' -f $count }
                if ($role -eq 'check') { $kind = [KcInputTestForm]::ChipCheck; $caption = $script:KcBehaviorChip.check }
            }
            'combo' {
                $kind = [KcInputTestForm]::ChipCombo; $caption = $script:KcBehaviorChip.combo
                $text = (@(Get-KcProp $a 'keys' @()) -join ' + ')
            }
            'release' {
                $kind = [KcInputTestForm]::ChipRelease; $caption = $script:KcBehaviorChip.release; $text = '全部離す'
            }
        }
        $isHold = $op -eq 'hold'
        $joiner = ''
        if ($texts.Count -gt 0 -and $isHold -and $prevHold) { $joiner = '+' }
        $captions += $caption; $texts += $text; $kinds += $kind; $joiners += $joiner
        $prevHold = $isHold
    }
    foreach ($p in $badges.Keys) {
        $form.SetKeyBadge([int]$p, [string]$badges[$p])
    }
    $form.SetSequence([string[]]$captions, [string[]]$texts, [int[]]$kinds, [string[]]$joiners)

    # レイヤーの帯: この手順で通るレイヤー
    $path = @($Step.path)
    $held = @(@($Step.actions) | Where-Object { $_.op -eq 'hold' -and (Get-KcProp $_ 'role' '') -eq 'layer' } |
            ForEach-Object { [string](Get-KcProp $_ 'label' '') })
    $pn = @(); $pk = @()
    for ($i = 0; $i -lt $path.Count; $i++) {
        $name = Get-KcBehaviorLayerName $Ctx ([int]$path[$i])
        $pn += $name
        if ($i -eq $path.Count - 1) {
            $pk += [KcInputTestForm]::PathTarget
        } elseif ($i -eq 0) {
            $pk += [KcInputTestForm]::PathStart
        } elseif ($held -contains $name) {
            $pk += [KcInputTestForm]::PathHeld
        } else {
            $pk += [KcInputTestForm]::PathSwitched
        }
    }
    $form.SetLayerPath([string[]]$pn, [int[]]$pk)
    Update-KcBehaviorOverview $Ctx $layer

    $detail = [string](Get-KcProp $Step 'note' '')
    $tips = @()
    if (@(@($Step.actions) | Where-Object { $_.op -eq 'hold' }).Count -gt 0) {
        $tips += '押したままのキーは、タップしたキーを離してから離してください。'
    }
    if ([int](Get-KcProp $Step 'td_ms' 0) -gt 0) {
        $tips += ('2 回目は {0} ms 以内に (素早く) タップします。' -f [int]$Step.td_ms)
    }
    if ($tips.Count -gt 0) {
        $detail += "`n" + ($tips -join ' ')
    }
    $instruction = [string]$Step.text + 'してください'
    $form.SetTexts($Title, $instruction, $detail.Trim())
    [void](Update-KcBehaviorOutputs $Ctx $Step @())
}

# 期待する入力と実際の入力のキーキャップ
function Update-KcBehaviorOutputs($Ctx, $Step, $Events) {
    $t = Test-KcBehaviorStep $Events $Step $Ctx.ScanTable
    $exp = @(@($Step.expect) | ForEach-Object { Format-KcStroke $_ $Ctx.ScanTable })
    $es = @($t.ExpectedStates | ForEach-Object {
            switch ([int]$_) { 1 { [KcInputTestForm]::CapOk } 2 { [KcInputTestForm]::CapNg } default { [KcInputTestForm]::CapNeutral } } })
    $act = @($t.Strokes | ForEach-Object { Format-KcStroke $_ $Ctx.ScanTable })
    $as = @($t.ActualStates | ForEach-Object { if ([int]$_ -eq 1) { [KcInputTestForm]::CapOk } else { [KcInputTestForm]::CapNg } })
    $Ctx.Form.SetOutputs('期待する入力', [string[]]$exp, [int[]]$es, '実際の入力', [string[]]$act, [int[]]$as, '(まだ入力がありません)')
    return $t
}

# 手順を 1 回やってもらう。戻り値: @{ Outcome = PASS / FAIL / NONE / MOVED / SKIP / ABORT; Result }
function Invoke-KcBehaviorAttempt($Ctx, $Step) {
    $fg = Wait-KcForeground $Ctx
    if ($fg -eq 'abort') {
        return @{ Outcome = 'ABORT'; Result = $null }
    }
    if ($fg -eq 'resumed') {
        return @{ Outcome = 'REDRAW'; Result = $null }
    }
    if (-not [KcInputTestForm]::GetDeviceName($Ctx.Keyboard)) {
        return @{ Outcome = 'GONE'; Result = $null }
    }
    $settle = [int]$Ctx.Common.thresholds.behavior_settle_ms
    $kb = $Ctx.Keyboard
    $Ctx.Form.ClearEvents()
    $Ctx.Form.SetStatus('', 0)
    $r = Wait-KcStep -Ctx $Ctx -AnyDevice -TimeoutMs 30000 -OnTick {
        param($ev, $now)
        $keysOnly = @($ev | Where-Object { $_.Kind -eq 'key' -and $_.Device -eq $kb })
        [void](Update-KcBehaviorOutputs $Ctx $Step $keysOnly)
    } -Done {
        param($ev, $now)
        $keysOnly = @($ev | Where-Object { $_.Kind -eq 'key' -and $_.Device -eq $kb })
        Test-KcBehaviorStepDone $keysOnly $Step $Ctx.ScanTable $now $settle
    }
    if ($r.Outcome -eq 'abort') {
        return @{ Outcome = 'ABORT'; Result = $null }
    }
    $keys = @($r.Events | Where-Object { $_.Kind -eq 'key' -and $_.Device -eq $kb })
    $t = Update-KcBehaviorOutputs $Ctx $Step $keys
    if ($r.Outcome -eq 'skip' -or ($r.Outcome -eq 'timeout' -and $keys.Count -eq 0)) {
        return @{ Outcome = 'SKIP'; Result = $t }
    }
    $outcome = $t.Status
    if ($outcome -ne 'PASS' -and (Test-KcBehaviorMouseMoved $r.Events)) {
        $outcome = 'MOVED'
    }
    return @{ Outcome = $outcome; Result = $t }
}

function Show-KcBehaviorOutcome($Ctx, [string]$Outcome, $Result, [bool]$WillRetry) {
    $again = ''
    if ($WillRetry) { $again = ' もう一度お願いします' }
    switch ($Outcome) {
        'PASS' { Show-KcStepResult $Ctx 'PASS' ('OK: ' + $Result.Actual) }
        'FAIL' { Show-KcStepResult $Ctx 'FAIL' ($Result.Message + $again) }
        'NONE' { Show-KcStepResult $Ctx 'WARN' ('入力がありませんでした。' + $again) }
        'MOVED' { Show-KcStepResult $Ctx 'WARN' ('ボールやマウスが動きました (AML になるとキーの意味が変わります)。ボールに触れないでください。' + $again) }
        'SKIP' { Show-KcStepResult $Ctx 'WARN' 'スキップしました' }
    }
    $ms = 700
    if ($Outcome -ne 'PASS') { $ms = 1600 }
    Wait-KcPause $Ctx $ms
}

# &to のレイヤーから BASE に戻す (失敗・スキップ・中止のあと)。戻り値: done / abort / failed
function Invoke-KcBehaviorRecover($Ctx, $Scenario) {
    $rec = Get-KcProp $Scenario 'recover' $null
    if ($null -eq $rec) {
        return 'done'
    }
    $step = [pscustomobject]@{
        actions = $rec.actions; expect = @($rec.expect); text = $rec.text; layer = [int]$Scenario.to_layer
        path = @([int]$Scenario.to_layer, 0)
        note = ('キーボードが {0} のままかもしれないので、BASE に戻します。最後の「{1}」で文字が入力されれば戻っています。' -f
            (Get-KcBehaviorLayerName $Ctx ([int]$Scenario.to_layer)), [string]@($rec.actions)[@($rec.actions).Count - 1].key)
    }
    for ($i = 1; $i -le 2; $i++) {
        Show-KcBehaviorStep $Ctx $Scenario $step 'BASE に戻す'
        $Ctx.Form.SetButtons($false, $false, $false)
        $fg = Wait-KcForeground $Ctx
        if ($fg -eq 'abort') { return 'abort' }
        $Ctx.Form.ClearEvents()
        $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 60000 -OnTick {
            param($ev, $now)
            [void](Update-KcBehaviorOutputs $Ctx $step $ev)
        } -Done {
            param($ev, $now)
            ((Test-KcBehaviorRecovered $ev $rec $Ctx.ScanTable) -and (Test-KcKeysSettled $ev $Ctx.ScanTable $now 300)) -or
            (Test-KcKeysSettled $ev $Ctx.ScanTable $now 3000)
        }
        $Ctx.Form.SetButtons($false, $false, $true)
        if ($r.Outcome -eq 'abort') { return 'abort' }
        if (Test-KcBehaviorRecovered $r.Events $rec $Ctx.ScanTable) {
            Show-KcStepResult $Ctx 'PASS' 'BASE に戻りました'
            Wait-KcPause $Ctx 700
            return 'done'
        }
        Show-KcStepResult $Ctx 'WARN' ('BASE に戻っていないようです ({0})。もう一度お願いします' -f (Format-KcStrokeList (ConvertTo-KcStrokes $r.Events $Ctx.ScanTable) $Ctx.ScanTable))
        Wait-KcPause $Ctx 1600
    }
    return 'failed'
}

# 結果の集計 (種類ごと・レイヤーごと)
function Add-KcBehaviorTally($Ctx, $Scenario, $Step, [string]$Record, [string]$Line) {
    $kind = [string]$Scenario.kind
    if (-not $Ctx.Tally.Contains($kind)) {
        $Ctx.Tally[$kind] = @{ Pass = 0; Fail = New-Object 'System.Collections.Generic.List[string]'; Skip = New-Object 'System.Collections.Generic.List[string]'; Total = 0 }
    }
    $t = $Ctx.Tally[$kind]
    $t.Total++
    $layer = [int]$Step.layer
    if (-not $Ctx.LayerTally.ContainsKey($layer)) {
        $Ctx.LayerTally[$layer] = @{ Pass = 0; Fail = 0; Skip = 0; Total = 0 }
    }
    $lt = $Ctx.LayerTally[$layer]
    $lt.Total++
    switch ($Record) {
        'PASS' { $t.Pass++; $lt.Pass++ }
        'FAIL' { $t.Fail.Add($Line); $lt.Fail++ }
        default { $t.Skip.Add($Line); $lt.Skip++ }
    }
}

# シナリオ 1 つ。戻り値: done / abort
# 手順の結果はシナリオの終わりにまとめて数える (&to のシナリオを最初からやり直したとき、前の結果を捨てるため)
function Invoke-KcBehaviorScenario($Ctx, $Scenario, [int]$Index, [int]$Count) {
    $steps = @($Scenario.steps)
    $stateful = $null -ne (Get-KcProp $Scenario 'recover' $null)
    $kindName = [string]$script:KcBehaviorKindNames[[string]$Scenario.kind]
    $records = @{}
    $outcome = 'done'
    $i = 0
    $attempt = 1
    while ($i -lt $steps.Count) {
        $step = $steps[$i]
        $title = '{0} ({1} / {2}): {3}' -f $kindName, $Index, $Count, $Scenario.title
        if ($steps.Count -gt 1) {
            $title += (' — 手順 {0} / {1}' -f ($i + 1), $steps.Count)
        }
        $where = '{0} [{1}]' -f $step.text, [string](Get-KcProp $step 'src' $Scenario.title)
        if (Test-KcBehaviorStepUsesMismatch $step $Ctx.Mismatch) {
            $records[$i] = @('SKIP', ($where + ': 読み出し検査でキーの割り当てが違っていたため飛ばした'))
            if ($stateful) { break }
            $i++
            continue
        }
        Show-KcBehaviorStep $Ctx $Scenario $step $title
        $Ctx.Form.SetProgress($Ctx.StepDone + $records.Count, $Ctx.StepTotal)
        $a = Invoke-KcBehaviorAttempt $Ctx $step
        if ($a.Outcome -eq 'REDRAW') {
            continue
        }
        if ($a.Outcome -eq 'GONE') {
            $Ctx.Form.SetTexts('キーボードが見つかりません', 'キーボードが外れたか、リセットされました',
                'テストをやめます。キーボードをつなぎ直してから、もう一度実行してください。')
            Wait-KcPause $Ctx 2500
            $Ctx.BehaviorGone = $true
            $outcome = 'abort'
            break
        }
        $last = $i -eq $steps.Count - 1
        $d = Get-KcBehaviorDecision $a.Outcome $attempt $stateful $last
        $willRetry = $d.Next -eq 'retry' -or $d.Next -eq 'restart'
        if ($a.Outcome -ne 'ABORT') {
            Show-KcBehaviorOutcome $Ctx $a.Outcome $a.Result $willRetry
        }
        if ($d.Record) {
            $line = $where
            if ($d.Record -eq 'SKIP') {
                $line = $where + ': スキップ'
            } elseif ($d.Record -eq 'FAIL' -and $null -ne $a.Result) {
                $line = '{0}: 期待 {1} / 実際 {2}' -f $where, $a.Result.Expected, $a.Result.Actual
            }
            $records[$i] = @($d.Record, $line)
        }
        if ($d.Recover) {
            $rc = Invoke-KcBehaviorRecover $Ctx $Scenario
            if ($rc -eq 'abort') { $outcome = 'abort'; break }
            if ($rc -eq 'failed') {
                $Ctx.BehaviorStuck = $true
                $outcome = 'abort'
                break
            }
        }
        if ($d.Next -eq 'abort') { $outcome = 'abort'; break }
        if ($d.Next -eq 'end') { break }
        if ($d.Next -eq 'retry') {
            $attempt++
            continue
        }
        if ($d.Next -eq 'restart') {
            # BASE に戻したので、シナリオの最初からやり直す
            $records = @{}
            $attempt = 2
            $i = 0
            continue
        }
        $i++
        $attempt = 1
    }
    for ($j = 0; $j -lt $steps.Count; $j++) {
        if ($records.ContainsKey($j)) {
            Add-KcBehaviorTally $Ctx $Scenario $steps[$j] $records[$j][0] $records[$j][1]
        } else {
            Add-KcBehaviorTally $Ctx $Scenario $steps[$j] 'SKIP' ('{0}: 前の手順が合わなかったか、中止したため飛ばした' -f $steps[$j].text)
        }
        $Ctx.StepDone++
    }
    return $outcome
}

# 種類ごとの区切り。戻り値: next / skip / abort
function Wait-KcBehaviorGroup($Ctx, [string]$Kind, [int]$Scenarios, [int]$Steps) {
    $about = @{
        layer     = 'レイヤーキー (&mo / &lt) を押したまま、ほかのキーを押して、そのレイヤーのキーが入力されるかを確かめます。'
        hold_tap  = '長押しで修飾キーになるキー (&mt) を押したまま、反対の手のキーを押します。'
        mod_morph = '修飾キーの有無で動作が変わるキー (mod-morph) を、修飾キーなし・ありで押します。修飾キーは、レイヤーの中の Ctrl / Shift のキーを押したままにします。'
        tap_dance = '素早く続けて押すと動作が変わるキー (tap-dance) を、決まった回数だけ素早くタップします。'
        to_layer  = '押すとレイヤーが切り替わったままになるキー (&to) で入り、そのレイヤーのキーを確かめてから BASE に戻ります。'
        combo     = '同時に押すと別のキーになる組み合わせ (コンボ) を押します。'
    }
    $form = $Ctx.Form
    $form.ClearKeyStates()
    $form.ClearKeyBadges()
    $form.ResetKeyLegends()
    $form.SetSequence([string[]]@(), [string[]]@(), [int[]]@(), [string[]]@())
    $form.ClearOutputs()
    $form.SetLayerPath([string[]]@(), [int[]]@())
    Update-KcBehaviorOverview $Ctx -1
    $form.SetTexts(('{0}' -f $script:KcBehaviorKindNames[$Kind]), ('{0} 件 ({1} 手順) を確かめます' -f $Scenarios, $Steps),
        ($about[$Kind] + "`n「次へ」で始めます。「スキップ」でこの種類を飛ばします。"))
    $form.SetProgress($Ctx.StepDone, $Ctx.StepTotal)
    $form.SetStatus('', 0)
    $form.SetButtons($true, $false, $true)
    $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 0 -ButtonsOnly
    $form.SetButtons($false, $false, $true)
    return $r.Outcome
}

# 全体。$Ctx は Invoke-KcInputTest のもの (Keyboard は特定済み)。戻り値: done / abort
function Invoke-KcBehaviorTest($Ctx) {
    $beh = Get-KcProp $Ctx.Expected.interactive 'behaviors' $null
    $cat = '{0}: レイヤー・ビヘイビア' -f $Ctx.Expected.name
    if ($null -eq $beh -or @($beh.scenarios).Count -eq 0) {
        $why = 'この機種の期待値にテストがありません'
        if ($null -ne $beh -and @($beh.not_tested).Count -gt 0) {
            $why = [string]@($beh.not_tested)[0].reason
        }
        Add-KcInputResult $Ctx $cat 'レイヤー・ビヘイビア' 'SKIP' $why
        return 'done'
    }
    $Ctx.Behaviors = $beh
    $Ctx.KeyPositions = @($Ctx.Expected.physical.keys | Where-Object { [bool](Get-KcProp $_ 'present' $true) } | ForEach-Object { [int]$_.pos })
    $Ctx.Tally = [ordered]@{}
    $Ctx.LayerTally = @{}
    $Ctx.TestedLayers = @($beh.scenarios | ForEach-Object { @($_.steps) } | ForEach-Object { [int]$_.layer } | Sort-Object -Unique)
    $Ctx.StepDone = 0
    $Ctx.StepTotal = @($beh.scenarios | ForEach-Object { @($_.steps).Count } | Measure-Object -Sum).Sum
    $Ctx.BehaviorStuck = $false
    $Ctx.BehaviorGone = $false
    $Ctx.Form.SetExtraLegendTexts('押したまま (レイヤー)', '押したまま (修飾)', '押さない')
    $Ctx.Form.SetKeyLegendTexts('タップ', '合格', '違う', 'スキップ')
    $outcome = 'done'
    try {
        foreach ($kind in @($script:KcBehaviorKindNames.Keys)) {
            $list = @($beh.scenarios | Where-Object { $_.kind -eq $kind })
            if ($list.Count -eq 0) {
                continue
            }
            $nSteps = @($list | ForEach-Object { @($_.steps).Count } | Measure-Object -Sum).Sum
            $g = Wait-KcBehaviorGroup $Ctx $kind $list.Count $nSteps
            if ($g -eq 'abort') { $outcome = 'abort'; break }
            if ($g -eq 'skip') {
                foreach ($sc in $list) {
                    foreach ($st in @($sc.steps)) {
                        Add-KcBehaviorTally $Ctx $sc $st 'SKIP' ('{0}: スキップ' -f $st.text)
                        $Ctx.StepDone++
                    }
                }
                continue
            }
            for ($i = 0; $i -lt $list.Count; $i++) {
                $o = Invoke-KcBehaviorScenario $Ctx $list[$i] ($i + 1) $list.Count
                if ($o -eq 'abort') { $outcome = 'abort'; break }
            }
            if ($outcome -eq 'abort') { break }
        }
    } finally {
        $Ctx.Form.ClearKeyStates()
        $Ctx.Form.ClearKeyBadges()
        $Ctx.Form.ResetKeyLegends()
        $Ctx.Form.SetSequence([string[]]@(), [string[]]@(), [int[]]@(), [string[]]@())
        $Ctx.Form.ClearOutputs()
        $Ctx.Form.SetLayerPath([string[]]@(), [int[]]@())
        $Ctx.Form.SetLayerOverview('', [string[]]@(), [int[]]@())
        $Ctx.Form.SetExtraLegendTexts('', '', '')
        $Ctx.Form.SetKeyLegendTexts('いまのキー', '合格', '違うキー', 'スキップ')
    }
    Add-KcBehaviorResults $Ctx $cat
    if ($Ctx.BehaviorStuck) {
        Add-KcInputResult $Ctx $cat 'BASE に戻せなかった' 'WARN' '&to のレイヤーのままかもしれません' `
            'キーボードの USB を挿し直すか、電源を入れ直してから使ってください'
    }
    if ($Ctx.BehaviorGone) {
        Add-KcInputResult $Ctx $cat 'キーボード' 'SKIP' 'テストの途中でキーボードが見つからなくなりました (リセット・ブートローダ・ケーブル)'
    }
    if ($outcome -eq 'abort' -and ($Ctx.BehaviorStuck -or $Ctx.BehaviorGone)) {
        # キーボードの状態が分からないので、この先のテスト (AML など) もしない
        return 'abort'
    }
    return $outcome
}

# 種類ごとの結果の項目
function Add-KcBehaviorResults($Ctx, [string]$Category) {
    $beh = $Ctx.Behaviors
    $hint = 'ファームが古いか、キーマップのビヘイビア (mod-morph の mods、tap-dance、マクロ) が意図と違います。tools/flash.cmd で最新のファームを書き込んでください'
    if ($Ctx.Expected.kind -eq 'vial') {
        $hint = 'Vial で変えたタップダンス・キーオーバーライド・マクロが残っているかもしれません。Vial の「File → Load saved layout」で KEYMAP.vil を読み込んでください。' +
        'キーオーバーライドは、修飾キーより先にタップしたキーを離したか確かめてください'
    }
    foreach ($kind in @($script:KcBehaviorKindNames.Keys)) {
        $item = [string]$script:KcBehaviorKindNames[$kind]
        if (-not $Ctx.Tally.Contains($kind)) {
            if ($kind -eq 'combo' -and [int]$beh.combos -eq 0) {
                Add-KcInputResult $Ctx $Category $item 'INFO' 'コンボは定義されていません'
            }
            continue
        }
        $t = $Ctx.Tally[$kind]
        if ($t.Fail.Count -gt 0) {
            Add-KcInputResult $Ctx $Category $item 'FAIL' ('{0} / {1} 件が違う' -f $t.Fail.Count, $t.Total) $hint ($t.Fail.ToArray() + $t.Skip.ToArray())
        } elseif ($t.Pass -eq 0) {
            Add-KcInputResult $Ctx $Category $item 'SKIP' 'すべてスキップ' '' $t.Skip.ToArray()
        } elseif ($t.Skip.Count -gt 0) {
            Add-KcInputResult $Ctx $Category $item 'WARN' ('{0} / {1} 件が一致 ({2} 件スキップ)' -f $t.Pass, $t.Total, $t.Skip.Count) '' $t.Skip.ToArray()
        } else {
            Add-KcInputResult $Ctx $Category $item 'PASS' ('{0} / {1} 件が一致' -f $t.Pass, $t.Total)
        }
    }
    $nt = @($beh.not_tested | ForEach-Object { '{0}: {1}' -f $_.what, $_.reason })
    if ($nt.Count -gt 0) {
        [void](Add-KcResult -Results $Ctx.Results -Category $Category -Item 'テストしないもの' -Status INFO -Details $nt -Reference)
    }
}
