# 実動作テスト (GUI)。テスト用のウィンドウ (InputTestForm.cs) で、キーのタップ・レイヤー・ビヘイビア
# (behavior-test.ps1)・AML・スクロール・トラックボールの正規化 (楕円・速さ) を順に行う。Windows のみ。
# keyboard-check.ps1 から dot-source して使う。expected.ps1 / results.ps1 / rawhid.ps1 / input-eval.ps1 /
# trackball-calib.ps1 が先に読み込まれている前提。
#
# ウィンドウを開いている間はコンソールに書かない (クリックがコンソールに当たると、
# 簡易編集モードで処理が止まるため)。結果は $Results に入れ、最後にまとめて表示する。

$script:KcBallNames = @{ right = '右'; left = '左' }
$script:KcStateNormal = 0
$script:KcStateCurrent = 1
$script:KcStatePass = 2
$script:KcStateFail = 3
$script:KcStateSkip = 4

# ウィンドウ (WPF) の C# をコンパイルして読み込む。見た目は Theme.xaml と *Window.xaml にある。
# input-monitor.ps1 もここを通る
function Import-KcInputForm {
    $wpf = @('PresentationFramework', 'PresentationCore', 'WindowsBase', 'System.Xaml')
    foreach ($name in $wpf) {
        Add-Type -AssemblyName $name
    }
    Import-KcCSharp 'InputTestForm.cs' 'KcInputTestForm' $wpf
    [KcUi]::XamlDir = $script:KcLibDir
    # 高 DPI の画面でぼやけないように、ウィンドウを作る前に DPI 対応にする
    [KcUi]::EnsureDpiAware()
}

# ボタンの文字・凡例・機種名・キーボードの図を入れる
function Initialize-KcInputForm($Form, $Expected) {
    $Form.SetButtonTexts('次へ', 'やり直し', 'スキップ', '中止')
    $Form.SetButtons($false, $false, $true)
    $Form.SetKeyLegendTexts('いまのキー', '合格', '違うキー', 'スキップ')
    $Form.SetSubtitle([string]$Expected.name)
    $keys = @($Expected.physical.keys | Where-Object { [bool](Get-KcProp $_ 'present' $true) })
    $Form.SetKeys(
        [int[]]@($keys | ForEach-Object { [int]$_.pos }),
        [double[]]@($keys | ForEach-Object { [double]$_.x }),
        [double[]]@($keys | ForEach-Object { [double]$_.y }),
        [double[]]@($keys | ForEach-Object { [double]$_.w }),
        [double[]]@($keys | ForEach-Object { [double]$_.h }),
        [string[]]@($keys | ForEach-Object { [string]$_.legend }))
}

function New-KcInputForm($Expected) {
    Import-KcInputForm
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
        throw 'テスト用のウィンドウは STA で動かす必要があります。powershell.exe (Windows PowerShell) で実行してください'
    }
    $form = New-Object KcInputTestForm
    try {
        Initialize-KcInputForm $form $Expected
        $form.Show()
    } catch {
        $form.Dispose()
        throw
    }
    $form.Activate()
    [KcUi]::DoEvents()
    return $form
}

# メッセージを処理して少し待つ (ウィンドウとキーボードのフックを動かし続ける)
function Invoke-KcPump {
    [KcUi]::DoEvents()
    Start-Sleep -Milliseconds 15
}

# $Done (param($events, $now)) が $true を返すか、ボタンが押されるか、時間切れになるまで入力を集める。
# 戻り値: @{ Outcome = done / timeout / next / retry / skip / abort; Events }
# (scriptblock は呼び出し元の変数を参照するので、ここの変数名は ws で始めて重ならないようにする)
function Wait-KcStep {
    param(
        [Parameter(Mandatory = $true)] $Ctx,
        [scriptblock]$Done = $null,
        [int]$TimeoutMs = 30000,
        [scriptblock]$OnTick = $null,
        [switch]$AnyDevice,
        [switch]$ButtonsOnly,
        # $Done / $OnTick を呼ぶ間隔 (入力が多い計測で、毎回すべての記録を調べないように)
        [int]$CheckIntervalMs = 100
    )
    $wsForm = $Ctx.Form
    $wsEvents = New-Object 'System.Collections.Generic.List[object]'
    $wsStart = $wsForm.NowMs
    $wsLastCheck = [long]0
    while ($true) {
        Invoke-KcPump
        $wsAction = $wsForm.TakeAction()
        if ($wsAction) {
            return @{ Outcome = $wsAction; Events = $wsEvents.ToArray() }
        }
        foreach ($wsE in $wsForm.TakeEvents()) {
            if ($AnyDevice -or $Ctx.Devices -contains $wsE.Device) {
                $wsEvents.Add($wsE)
            }
        }
        $wsNow = $wsForm.NowMs
        if (($wsNow - $wsLastCheck) -ge $CheckIntervalMs) {
            $wsLastCheck = $wsNow
            $wsArray = $wsEvents.ToArray()
            if ($null -ne $OnTick) {
                & $OnTick $wsArray $wsNow
            }
            if (-not $ButtonsOnly -and $null -ne $Done -and (& $Done $wsArray $wsNow)) {
                return @{ Outcome = 'done'; Events = $wsArray }
            }
        }
        if ($TimeoutMs -gt 0 -and ($wsNow - $wsStart) -gt $TimeoutMs) {
            return @{ Outcome = 'timeout'; Events = $wsEvents.ToArray() }
        }
    }
}

# 最初にボールが動いた時刻 (動いていなければ -1)
function Get-KcFirstMoveTime($Events) {
    foreach ($e in $Events) {
        if ($e.Kind -eq 'mouse' -and ($e.Dx -ne 0 -or $e.Dy -ne 0)) {
            return [long]$e.Time
        }
    }
    return [long]-1
}

# 入力が止まってから $IdleMs たったか (マウスの移動量が $MinMove 以上のときだけ)
function Test-KcMotionSettled($Events, [long]$Now, [int]$MinMove, [int]$IdleMs) {
    $m = Measure-KcMotion $Events
    if ([math]::Sqrt([double]$m.Dx * $m.Dx + [double]$m.Dy * $m.Dy) -lt $MinMove) {
        return $false
    }
    $last = @($Events)[@($Events).Count - 1].Time
    return (($Now - $last) -ge $IdleMs)
}

function Show-KcStepResult($Ctx, [string]$Status, [string]$Text) {
    $level = 0
    switch ($Status) {
        'PASS' { $level = 1 }
        'FAIL' { $level = 2 }
        'WARN' { $level = 3 }
        'NONE' { $level = 3 }
    }
    $Ctx.Form.SetStatus($Text, $level)
}

# 結果を見せて少し待つ (次の手順の入力と混ざらないように)
function Wait-KcPause($Ctx, [int]$Ms) {
    $end = $Ctx.Form.NowMs + $Ms
    while ($Ctx.Form.NowMs -lt $end) {
        Invoke-KcPump
        [void]$Ctx.Form.TakeEvents()
    }
}

# 「次へ」か「やり直し」を待つ
function Wait-KcNextOrRetry($Ctx) {
    $Ctx.Form.SetButtons($true, $true, $false)
    $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 0 -ButtonsOnly
    $Ctx.Form.SetButtons($false, $false, $true)
    return $r.Outcome
}

function Add-KcInputResult($Ctx, [string]$Category, [string]$Item, [string]$Status, [string]$Actual = '', [string]$Hint = '', [string[]]$Details = @(), [string]$Expected = '') {
    if ($Status -eq 'NONE') {
        $Status = 'SKIP'
    }
    [void](Add-KcResult -Results $Ctx.Results -Category $Category -Item $Item -Status $Status -Actual $Actual -Hint $Hint -Details $Details -Expected $Expected)
}

# ---------------------------------------------------------------------------
# デバイスの特定
# ---------------------------------------------------------------------------

# このウィンドウが前面になるまで待つ (前面でないと、マクロの Ctrl+X などがほかのアプリに届く)
function Wait-KcForeground($Ctx, [string]$Why = 'キーの入力をこのウィンドウで受け取るためです (ほかのアプリにキーが入力されないようにします)。') {
    if ($Ctx.Form.IsForeground) {
        return 'done'
    }
    $Ctx.Form.SetTexts('準備', 'このウィンドウを一度クリックしてください', $Why)
    $Ctx.Form.Activate()
    while (-not $Ctx.Form.IsForeground) {
        Invoke-KcPump
        $a = $Ctx.Form.TakeAction()
        if ($a -eq 'abort') {
            return 'abort'
        }
    }
    return 'resumed'
}

function Select-KcKeyboardDevice($Ctx) {
    # キーの入力をこのウィンドウで受け取る (Alt / Win を押してもメニューが開かない) ため、前面にする
    if ((Wait-KcForeground $Ctx 'キーの入力をこのウィンドウで受け取るためです (コンソールにキーが入力されないようにします)。') -eq 'abort') {
        return 'abort'
    }
    $Ctx.Form.SetTexts('準備: キーボードの特定', 'テストするキーボードのキーを 1 つ押してください',
        "Shift など、押しても何も起きないキーがおすすめです。`nPC 本体のキーボードやマウスには触らないでください。")
    $r = Wait-KcStep -Ctx $Ctx -AnyDevice -TimeoutMs 60000 -Done {
        param($ev, $now)
        @($ev | Where-Object { $_.Kind -eq 'key' }).Count -gt 0
    }
    if ($r.Outcome -ne 'done') {
        return $r.Outcome
    }
    $Ctx.Keyboard = [long](@($r.Events | Where-Object { $_.Kind -eq 'key' })[0].Device)
    $Ctx.Devices = @($Ctx.Keyboard)
    $name = [KcInputTestForm]::GetDeviceName($Ctx.Keyboard)
    $Ctx.KeyboardName = $name
    $Ctx.Form.SetStatus('キーボード: ' + $name, 1)
    Wait-KcPause $Ctx 800
    return 'done'
}

function Select-KcMouseDevice($Ctx) {
    $Ctx.Form.SetTexts('準備: トラックボールの特定', 'キーから手を離して、ボールを少し転がしてください',
        'PC のマウスには触らないでください。')
    $r = Wait-KcStep -Ctx $Ctx -AnyDevice -TimeoutMs 60000 -Done {
        param($ev, $now)
        $mv = @($ev | Where-Object { $_.Kind -eq 'mouse' -and ($_.Dx -ne 0 -or $_.Dy -ne 0) })
        if ($mv.Count -lt 5) {
            return $false
        }
        $dev = $mv[0].Device
        $sum = 0
        foreach ($e in $mv) {
            if ($e.Device -eq $dev) { $sum += [math]::Abs($e.Dx) + [math]::Abs($e.Dy) }
        }
        $sum -ge 40
    }
    if ($r.Outcome -ne 'done') {
        return $r.Outcome
    }
    $Ctx.Mouse = [long](@($r.Events | Where-Object { $_.Kind -eq 'mouse' -and ($_.Dx -ne 0 -or $_.Dy -ne 0) })[0].Device)
    $Ctx.Devices = @($Ctx.Keyboard, $Ctx.Mouse)
    $name = [KcInputTestForm]::GetDeviceName($Ctx.Mouse)
    $Ctx.MouseName = $name
    $Ctx.Form.SetStatus('トラックボール: ' + $name, 1)
    Wait-KcPause $Ctx 1500
    return 'done'
}

# ---------------------------------------------------------------------------
# キーのタップ (BASE レイヤー)
# ---------------------------------------------------------------------------

function Invoke-KcTapTest($Ctx) {
    $it = $Ctx.Expected.interactive
    $taps = @($it.taps)
    $cat = $Ctx.Category
    if ($taps.Count -eq 0) {
        return 'done'
    }
    foreach ($s in @($it.skipped)) {
        $Ctx.Form.SetKeyState([int]$s.pos, $script:KcStateSkip)
    }
    $fails = @()
    $skips = @()
    $passed = 0
    $settle = [int]$Ctx.Common.thresholds.tap_settle_ms
    for ($i = 0; $i -lt $taps.Count; $i++) {
        $tap = $taps[$i]
        $pos = [int]$tap.pos
        $Ctx.Form.SetKeyState($pos, $script:KcStateCurrent)
        $detail = 'キーを押してすぐ離してください。'
        if ($null -ne (Get-KcProp $tap 'hold_usage' $null) -or $null -ne (Get-KcProp $tap 'hold_layer' $null)) {
            $detail = '長押しすると別の動作になるキーです。押してすぐ離してください (150 ms 以内)。'
        }
        if ((Get-KcProp $tap 'special' '') -eq 'gui') {
            $detail += "`nWin キーでスタートメニューが開かないようにしてあります。開いてしまったら Esc で閉じてください。"
        }
        $Ctx.Form.SetTexts(('キーのタップ ({0} / {1})' -f ($i + 1), $taps.Count), ('「{0}」をタップしてください' -f $tap.legend), $detail)
        $Ctx.Form.SetProgress($i, $taps.Count)
        $Ctx.Form.SetStatus('', 0)
        $attempt = 0
        $result = $null
        while ($true) {
            $attempt++
            $Ctx.Form.ClearEvents()
            $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 20000 -Done {
                param($ev, $now)
                Test-KcKeysSettled $ev $Ctx.ScanTable $now $settle
            }
            if ($r.Outcome -eq 'abort') {
                return 'abort'
            }
            if ($r.Outcome -eq 'skip' -or $r.Outcome -eq 'timeout') {
                $result = [pscustomobject]@{ Status = 'SKIP'; Actual = '(スキップ)' }
                break
            }
            $result = Test-KcTap $r.Events $tap $Ctx.ScanTable
            if ($result.Status -eq 'HOLD' -and $attempt -lt 2) {
                Show-KcStepResult $Ctx 'WARN' ('長押しと判定されました ({0})。もう一度、素早くタップしてください' -f $result.Actual)
                continue
            }
            if ($result.Status -eq 'FAIL' -and $attempt -lt 2) {
                Show-KcStepResult $Ctx 'FAIL' ('「{0}」が入力されました。もう一度「{1}」をタップしてください' -f $result.Actual, $tap.legend)
                continue
            }
            break
        }
        $expText = Get-KcUsageLabel ([int]$tap.usage) $Ctx.ScanTable
        switch ($result.Status) {
            'PASS' {
                $passed++
                $Ctx.Form.SetKeyState($pos, $script:KcStatePass)
                Show-KcStepResult $Ctx 'PASS' ('OK: ' + $result.Actual)
            }
            'SKIP' {
                $skips += ('位置 {0} ({1})' -f $pos, $tap.legend)
                $Ctx.Form.SetKeyState($pos, $script:KcStateSkip)
            }
            default {
                $what = $result.Actual
                if ($result.Status -eq 'HOLD') { $what += ' (長押しの動作)' }
                $fails += ('位置 {0} ({1}): 期待 {2} / 実際 {3} [{4}]' -f $pos, $tap.legend, $expText, $what, $tap.src)
                $Ctx.Form.SetKeyState($pos, $script:KcStateFail)
                Show-KcStepResult $Ctx 'FAIL' ('違うキー: ' + $what)
            }
        }
        Wait-KcPause $Ctx 250
    }
    $total = $taps.Count
    if ($fails.Count -gt 0) {
        Add-KcInputResult $Ctx $cat 'キーのタップ (BASE レイヤー)' 'FAIL' ('{0} / {1} キーが違う' -f $fails.Count, $total) `
            'キーマップか、KQ-mini / Keyball の変換が意図と違います。読み出し検査の結果も確かめてください' $fails
    } elseif ($passed -eq 0) {
        Add-KcInputResult $Ctx $cat 'キーのタップ (BASE レイヤー)' 'SKIP' 'すべてスキップ'
    } else {
        $status = 'PASS'
        if ($skips.Count -gt 0) { $status = 'WARN' }
        Add-KcInputResult $Ctx $cat 'キーのタップ (BASE レイヤー)' $status ('{0} / {1} キーが一致' -f $passed, $total) '' $skips
    }
    return 'done'
}

# ---------------------------------------------------------------------------
# トラックボール
# ---------------------------------------------------------------------------

# 1 つの手順を最大 2 回 (間違えたときに 1 回だけやり直す)。$Body は結果 (Status / Actual / Message) を返す
function Invoke-KcRetryStep($Ctx, [scriptblock]$Body) {
    for ($n = 1; $n -le 2; $n++) {
        $res = & $Body
        if ($res -is [string]) {
            return $res
        }
        if ($res.Status -eq 'PASS' -or $n -eq 2) {
            return $res
        }
        $msg = [string](Get-KcProp $res 'Message' '')
        if (-not $msg) { $msg = [string]$res.Actual }
        Show-KcStepResult $Ctx $res.Status ($msg + ' もう一度お願いします')
        Wait-KcPause $Ctx 1800
    }
}

# AML の発動に要るボールの動きの量 (期待値の aml.threshold。無ければ 0 = しきい値なし)
function Get-KcAmlThreshold($Ctx) {
    return [int](Get-KcProp $Ctx.Expected.interactive.trackball.aml 'threshold' 0)
}

function Invoke-KcAmlClickTest($Ctx, [string]$Ball, $Keys) {
    $bn = $script:KcBallNames[$Ball]
    $res = Invoke-KcRetryStep $Ctx {
        $Ctx.Form.SetTexts(('AML (自動マウスレイヤー): クリック ({0}のボール)' -f $bn), ('カーソルが 1 cm ほど動くまで{0}のボールを転がしてから、「{1}」を押したまま「{2}」を押してください' -f $bn, $Keys.scroll.legend, $Keys.click.legend),
            ("ボールを転がすと AML になり、「{0}」でクリック、「{1}」はスクロールのキーになります (文字は入力されません)。`nクリックはこのウィンドウの中だけで起きます。" -f $Keys.click.legend, $Keys.scroll.legend))
        $Ctx.Form.ClearEvents()
        $Ctx.Form.Confine($true)
        $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 40000 -Done {
            param($ev, $now)
            $m = Measure-KcMotion $ev
            if (Test-KcButtonClicked $m 1) { return ($now - @($ev)[@($ev).Count - 1].Time) -ge 300 }
            Test-KcKeysSettled $ev $Ctx.ScanTable $now 400
        }
        $Ctx.Form.Confine($false)
        if ($r.Outcome -eq 'abort') { return 'abort' }
        if ($r.Outcome -ne 'done') { return [pscustomobject]@{ Status = 'NONE'; Actual = '(スキップ)' } }
        $t = Test-KcAmlClick $r.Events ([int]$Keys.click.button) $Ctx.ScanTable -Threshold (Get-KcAmlThreshold $Ctx)
        Show-KcStepResult $Ctx $t.Status ($t.Actual + ' ' + [string](Get-KcProp $t 'Message' ''))
        Wait-KcPause $Ctx 800
        return $t
    }
    if ($res -is [string]) { return $res }
    Add-KcInputResult $Ctx $Ctx.Category ('AML のクリック ({0}のボール)' -f $bn) $res.Status $res.Actual ([string](Get-KcProp $res 'Message' ''))
    return 'done'
}

function Invoke-KcShiftClickTest($Ctx, [string]$Ball, $Keys) {
    $bn = $script:KcBallNames[$Ball]
    $item = 'AML: Shift + クリック ({0}のボール)' -f $bn
    $res = Invoke-KcRetryStep $Ctx {
        $Ctx.Form.SetTexts($item, ('カーソルが 1 cm ほど動くまで{0}のボールを転がしてから、「{1}」→「{2}」→「{3}」の順に押してください' -f $bn, $Keys.scroll.legend, $Keys.shift.legend, $Keys.click.legend),
            ("「{0}」と「{1}」は押したまま、「{2}」でクリックします。Shift を押したままクリックできれば合格です。`n「{1}」を先に押すと AML が切れるので、「{0}」から押します。" -f $Keys.scroll.legend, $Keys.shift.legend, $Keys.click.legend))
        $Ctx.Form.ClearEvents()
        $Ctx.Form.Confine($true)
        $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 40000 -Done {
            param($ev, $now)
            $m = Measure-KcMotion $ev
            if (-not (Test-KcButtonClicked $m 1)) {
                $acts = ConvertTo-KcKeyActions $ev $Ctx.ScanTable
                return (@($acts | Where-Object { $_.Down -and $_.Usage -ne [int]$Keys.shift.usage }).Count -gt 0 -and (Test-KcKeysSettled $ev $Ctx.ScanTable $now 400))
            }
            Test-KcKeysSettled $ev $Ctx.ScanTable $now 300
        }
        $Ctx.Form.Confine($false)
        if ($r.Outcome -eq 'abort') { return 'abort' }
        if ($r.Outcome -ne 'done') { return [pscustomobject]@{ Status = 'NONE'; Actual = '(スキップ)' } }
        $t = Test-KcShiftClick $r.Events ([int]$Keys.shift.usage) ([int]$Keys.click.button) $Ctx.ScanTable -Threshold (Get-KcAmlThreshold $Ctx)
        Show-KcStepResult $Ctx $t.Status ($t.Actual + ' ' + [string](Get-KcProp $t 'Message' ''))
        Wait-KcPause $Ctx 800
        return $t
    }
    if ($res -is [string]) { return $res }
    Add-KcInputResult $Ctx $Ctx.Category $item $res.Status $res.Actual ([string](Get-KcProp $res 'Message' ''))
    return 'done'
}

# AML 中に Ctrl / Shift の位置をタップすると、AML が切れて文字が入力される
function Invoke-KcAmlReleaseTest($Ctx, [string]$Ball, $Key) {
    $bn = $script:KcBallNames[$Ball]
    $item = 'AML: {0} で解除 ({1}のボール)' -f $Key.mod, $bn
    $res = Invoke-KcRetryStep $Ctx {
        $Ctx.Form.SetTexts($item, ('カーソルが 1 cm ほど動くまで{0}のボールを転がしてから、「{1}」をタップしてください' -f $bn, $Key.legend),
            ("「{0}」は長押しで {1} になるキーです。AML 中に押すと AML が切れ、文字が入力されれば合格です。`n長押しにならないよう、短く押してください。" -f $Key.legend, $Key.mod))
        $Ctx.Form.ClearEvents()
        $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 40000 -Done {
            param($ev, $now)
            Test-KcKeysSettled $ev $Ctx.ScanTable $now 400
        }
        if ($r.Outcome -eq 'abort') { return 'abort' }
        if ($r.Outcome -ne 'done') { return [pscustomobject]@{ Status = 'NONE'; Actual = '(スキップ)' } }
        $t = Test-KcAmlRelease $r.Events ([int]$Key.usage) $Ctx.ScanTable -Threshold (Get-KcAmlThreshold $Ctx)
        Show-KcStepResult $Ctx $t.Status ($t.Actual + ' ' + [string](Get-KcProp $t 'Message' ''))
        Wait-KcPause $Ctx 800
        return $t
    }
    if ($res -is [string]) { return $res }
    Add-KcInputResult $Ctx $Ctx.Category $item $res.Status $res.Actual ([string](Get-KcProp $res 'Message' ''))
    return 'done'
}

function Invoke-KcScrollTest($Ctx, [string]$Ball, $Keys) {
    $bn = $script:KcBallNames[$Ball]
    $expect = $Ctx.Common.expect
    $dirs = @(
        @{ Expect = [string]$expect.scroll_toward; Text = '手前 (自分の方) へ'; Item = '手前へ転がす → 下へスクロール' },
        @{ Expect = [string]$expect.scroll_right; Text = '右へ'; Item = '右へ転がす → 右へスクロール' }
    )
    foreach ($d in $dirs) {
        $res = Invoke-KcRetryStep $Ctx {
            $Ctx.Form.SetTexts(('スクロール ({0}のボール)' -f $bn), ('カーソルが 1 cm ほど動くまでボールを転がしてから、「{0}」を押したまま、{1}のボールを{2}ゆっくり大きく転がしてください' -f $Keys.scroll.legend, $bn, $d.Text),
                'スクロールは 16 カウントで 1 段なので、大きめに転がしてください。止まると次へ進みます。')
            $Ctx.Form.ClearEvents()
            $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 40000 -Done {
                param($ev, $now)
                $m = Measure-KcMotion $ev
                (($m.WheelPos + $m.WheelNeg + $m.HWheelPos + $m.HWheelNeg) -ge 3) -and (($now - @($ev)[@($ev).Count - 1].Time) -ge 700)
            }
            if ($r.Outcome -eq 'abort') { return 'abort' }
            if ($r.Outcome -ne 'done') {
                if ($r.Outcome -eq 'timeout' -and @($r.Events).Count -gt 0) {
                    return (Test-KcScroll (Measure-KcMotion $r.Events) $d.Expect)
                }
                return [pscustomobject]@{ Status = 'NONE'; Actual = '(スキップ)' }
            }
            $t = Test-KcScroll (Measure-KcMotion $r.Events) $d.Expect
            if ($t.Status -ne 'PASS') {
                # スクロールにならなかったのが、最初の動きが小さくて AML にならなかったせいなら、やり直す
                $small = Test-KcAmlMotion $r.Events (Get-KcAmlThreshold $Ctx)
                if ($null -ne $small) { $t = $small }
            }
            Show-KcStepResult $Ctx $t.Status ($t.Actual + ' ' + [string](Get-KcProp $t 'Message' ''))
            Wait-KcPause $Ctx 800
            return $t
        }
        if ($res -is [string]) { return $res }
        Add-KcInputResult $Ctx $Ctx.Category ('スクロールの向き: {0} ({1}のボール)' -f $d.Item, $bn) $res.Status $res.Actual `
            ([string](Get-KcProp $res 'Message' ''))
    }
    return 'done'
}

function Invoke-KcTimeoutTest($Ctx, $Keys) {
    $aml = $Ctx.Expected.interactive.trackball.aml
    $waitMs = [int]$aml.timeout_ms + [int]$Ctx.Common.thresholds.aml_timeout_margin_ms
    # AML が発動するだけ動かしてから数える
    $minMove = [math]::Max(40, (Get-KcAmlThreshold $Ctx))
    $Ctx.AmlTimeoutPassed = $false
    $res = Invoke-KcRetryStep $Ctx {
        $Ctx.Form.SetTexts('AML のタイムアウト', 'カーソルが 1 cm ほど動くまでボールを転がしてから手を離し、カウントダウンが終わるまで何も触らないでください',
            ('AML は {0} 秒で切れるはずです。切れたあと、「{1}」で文字が入力されれば合格です。' -f ([int]$aml.timeout_ms / 1000), $Keys.click.legend))
        $Ctx.Form.ClearEvents()
        $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 60000 -Done {
            param($ev, $now)
            Test-KcMotionSettled $ev $now $minMove 300
        }
        if ($r.Outcome -eq 'abort') { return 'abort' }
        if ($r.Outcome -ne 'done') { return [pscustomobject]@{ Status = 'NONE'; Actual = '(スキップ)' } }
        $end = $Ctx.Form.NowMs + $waitMs
        while ($Ctx.Form.NowMs -lt $end) {
            Invoke-KcPump
            $a = $Ctx.Form.TakeAction()
            if ($a -eq 'abort') { return 'abort' }
            if ($a -eq 'skip') { return [pscustomobject]@{ Status = 'NONE'; Actual = '(スキップ)' } }
            $touched = @($Ctx.Form.TakeEvents() | Where-Object { $Ctx.Devices -contains $_.Device })
            $Ctx.Form.SetProgress([int][math]::Max(0, $waitMs - ($end - $Ctx.Form.NowMs)), $waitMs)
            if ($touched.Count -gt 0) {
                $end = $Ctx.Form.NowMs + $waitMs
                $Ctx.Form.SetStatus('触ったので、カウントダウンをやり直します', 3)
            } else {
                $Ctx.Form.SetStatus(('残り {0} 秒' -f [math]::Ceiling(($end - $Ctx.Form.NowMs) / 1000.0)), 0)
            }
        }
        $Ctx.Form.SetTexts('AML のタイムアウト', ('「{0}」を押したまま「{1}」を押してください' -f $Keys.scroll.legend, $Keys.click.legend),
            ("AML が切れていれば、「{0}」「{1}」が文字として入力されます (AML のままだとクリックになります)。`nクリックはこのウィンドウの中だけで起きます。" -f $Keys.scroll.legend, $Keys.click.legend))
        $Ctx.Form.ClearEvents()
        $Ctx.Form.Confine($true)
        $r2 = Wait-KcStep -Ctx $Ctx -TimeoutMs 30000 -Done {
            param($ev, $now)
            $m = Measure-KcMotion $ev
            if (Test-KcButtonClicked $m 1) { return $true }
            Test-KcKeysSettled $ev $Ctx.ScanTable $now 300
        }
        $Ctx.Form.Confine($false)
        if ($r2.Outcome -eq 'abort') { return 'abort' }
        if ($r2.Outcome -ne 'done') { return [pscustomobject]@{ Status = 'NONE'; Actual = '(スキップ)' } }
        $t = Test-KcAmlOff $r2.Events ([int]$Keys.scroll.usage) ([int]$Keys.after_timeout.usage) $Ctx.ScanTable 'AML が時間がたっても切れていません'
        Show-KcStepResult $Ctx $t.Status ($t.Actual + ' ' + [string](Get-KcProp $t 'Message' ''))
        Wait-KcPause $Ctx 800
        return $t
    }
    if ($res -is [string]) { return $res }
    $Ctx.AmlTimeoutPassed = ($res.Status -eq 'PASS')
    Add-KcInputResult $Ctx $Ctx.Category ('AML のタイムアウト ({0} 秒)' -f ([int]$aml.timeout_ms / 1000)) $res.Status $res.Actual ([string](Get-KcProp $res 'Message' ''))
    return 'done'
}

# わずかな動き (キー入力の振動くらい) では AML にならない。AML が切れている (タイムアウトが PASS) ところから始める
function Invoke-KcAmlThresholdTest($Ctx, $Keys) {
    $threshold = Get-KcAmlThreshold $Ctx
    $item = 'AML のしきい値 (わずかな動きでは発動しない)'
    if (-not $Ctx.AmlTimeoutPassed) {
        Add-KcInputResult $Ctx $Ctx.Category $item 'SKIP' 'AML のタイムアウトが合格しなかったため確かめられません'
        return 'done'
    }
    $res = Invoke-KcRetryStep $Ctx {
        $Ctx.Form.SetTexts($item, ('ボールにそっと触れてカーソルを数ドットだけ動かしてから、「{0}」を押したまま「{1}」を押してください' -f $Keys.scroll.legend, $Keys.click.legend),
            ("AML は、止まっていた状態からカーソルが {0} 以上動いたときに発動します (キー入力の振動などで発動しないため)。`nわずかな動きなら AML にならず、「{1}」「{2}」が文字として入力されれば合格です。クリックはこのウィンドウの中だけで起きます。" -f $threshold, $Keys.scroll.legend, $Keys.click.legend))
        $Ctx.Form.ClearEvents()
        $Ctx.Form.Confine($true)
        $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 40000 -Done {
            param($ev, $now)
            $m = Measure-KcMotion $ev
            if (Test-KcButtonClicked $m 1) { return ($now - @($ev)[@($ev).Count - 1].Time) -ge 300 }
            Test-KcKeysSettled $ev $Ctx.ScanTable $now 400
        }
        $Ctx.Form.Confine($false)
        if ($r.Outcome -eq 'abort') { return 'abort' }
        if ($r.Outcome -ne 'done') { return [pscustomobject]@{ Status = 'NONE'; Actual = '(スキップ)' } }
        $t = Test-KcAmlThreshold $r.Events ([int]$Keys.scroll.usage) ([int]$Keys.after_timeout.usage) $threshold $Ctx.ScanTable
        Show-KcStepResult $Ctx $t.Status ($t.Actual + ' ' + [string](Get-KcProp $t 'Message' ''))
        Wait-KcPause $Ctx 800
        return $t
    }
    if ($res -is [string]) { return $res }
    Add-KcInputResult $Ctx $Ctx.Category $item $res.Status $res.Actual ([string](Get-KcProp $res 'Message' ''))
    return 'done'
}

# ---------------------------------------------------------------------------
# トラックボールの正規化
# ---------------------------------------------------------------------------

function Get-KcBallFirmware($Expected, [string]$Ball) {
    $fw = @($Expected.interactive.trackball.firmware)
    $match = @($fw | Where-Object { $_.side -eq $Ball })
    if ($match.Count -gt 0) {
        return $match[0]
    }
    return $fw[0]
}

function Invoke-KcEllipseCalib($Ctx, [string]$Ball) {
    $bn = $script:KcBallNames[$Ball]
    $cat = $Ctx.CalibCategory
    $fw = Get-KcBallFirmware $Ctx.Expected $Ball
    while ($true) {
        $Ctx.Form.SetTexts(('トラックボールの正規化: 楕円の計測 ({0}のボール)' -f $bn), 'ボールを、円を描くように一定の速さで回してください',
            "右回りで 10 秒、続けて左回りで 10 秒回します。回し始めると残り時間が出ます。`nなるべく同じ速さで、大きめの円を描いてください。")
        $Ctx.Form.SetStatus('', 0)
        $Ctx.Form.ClearEvents()
        $started = $null
        $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 90000 -CheckIntervalMs 250 -OnTick {
            param($ev, $now)
            $t0 = Get-KcFirstMoveTime $ev
            if ($t0 -ge 0) {
                $left = 20 - [math]::Floor(($now - $t0) / 1000.0)
                $dir = '右回り'
                if ($now - $t0 -ge 10000) { $dir = '左回り' }
                $Ctx.Form.SetStatus(('{0} で回してください: 残り {1} 秒 (入力 {2})' -f $dir, [math]::Max($left, 0), @($ev).Count), 0)
                $Ctx.Form.SetProgress([int][math]::Min($now - $t0, 20000), 20000)
            }
        } -Done {
            param($ev, $now)
            $t0 = Get-KcFirstMoveTime $ev
            ($t0 -ge 0) -and (($now - $t0) -ge 20000)
        }
        if ($r.Outcome -eq 'abort') { return 'abort' }
        if ($r.Outcome -ne 'done') {
            Add-KcInputResult $Ctx $cat ('楕円 ({0}のボール)' -f $bn) 'SKIP' '(スキップ)'
            return 'done'
        }
        $m = Measure-KcMotion $r.Events
        $rec = New-KcEllipseRecommendation -Samples $m.Samples -Firmware $fw -Thresholds $Ctx.Common.thresholds -Strength $Ctx.Options.Strength
        if ($rec.Status -eq 'SKIP') {
            Show-KcStepResult $Ctx 'WARN' $rec.Message
        } else {
            $text = '{0} → 補正後の予想 {1}' -f $rec.Summary, $rec.PredictedRatio
            if (@($rec.Notes).Count -gt 0) {
                $text += "`n" + $rec.Notes[0]
            }
            Show-KcStepResult $Ctx $rec.Status $text
        }
        $Ctx.Form.SetDetail("やり直すときは「やり直し」、よければ「次へ」を押してください。`n" + ((@($rec.Lines) | Select-Object -First 1) -join ''))
        $o = Wait-KcNextOrRetry $Ctx
        if ($o -eq 'abort') { return 'abort' }
        if ($o -eq 'retry') { continue }
        if ($rec.Status -eq 'SKIP') {
            Add-KcInputResult $Ctx $cat ('楕円 ({0}のボール)' -f $bn) 'SKIP' $rec.Message
            return 'done'
        }
        $hint = ''
        if ($rec.Status -ne 'PASS') {
            $hint = '推奨値 (Details) を overlay / 設定に反映してください。ツールはファームを書き換えません'
        }
        $details = @($rec.Lines) + @($rec.Notes)
        Add-KcInputResult $Ctx $cat ('楕円 ({0}のボール)' -f $bn) $rec.Status ('{0}、補正後の予想 {1}' -f $rec.Summary, $rec.PredictedRatio) $hint $details `
            ('縦横比 {0:F2} 以下' -f [double]$Ctx.Common.thresholds.ellipse_ratio_pass)
        $Ctx.CalibEntries.Add([pscustomobject]@{
                time = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'); keyboard = $Ctx.Expected.id; name = $Ctx.Expected.name; ball = $Ball; kind = 'ellipse'
                ratio = [math]::Round($rec.Fit.Ratio, 4); tilt = [math]::Round($rec.Tilt, 2); points = $rec.Fit.N
                matrix = @([math]::Round($rec.Matrix[0][0], 5), [math]::Round($rec.Matrix[0][1], 5), [math]::Round($rec.Matrix[1][0], 5), [math]::Round($rec.Matrix[1][1], 5))
                device = $Ctx.MouseName
            })
        return 'done'
    }
}

function Invoke-KcSpeedCalib($Ctx, [string]$Ball) {
    $bn = $script:KcBallNames[$Ball]
    $cat = $Ctx.CalibCategory
    $fw = Get-KcBallFirmware $Ctx.Expected $Ball
    $accel = Get-KcProp $fw 'accel' $null
    $th = $Ctx.Common.thresholds
    $revs = 2
    $plan = @(
        @{ Axis = 'x'; Text = '右へ' }, @{ Axis = 'x'; Text = '右へ' },
        @{ Axis = 'y'; Text = '手前 (自分の方) へ' }, @{ Axis = 'y'; Text = '手前 (自分の方) へ' }
    )
    while ($true) {
        $strokes = @()
        $saturated = 0
        $n = 0
        foreach ($p in $plan) {
            $n++
            $Ctx.Form.SetTexts(('トラックボールの正規化: 速さ ({0}のボール、{1} / {2})' -f $bn, $n, $plan.Count),
                ('ボールの印を真上に合わせてから、{0}ちょうど {1} 回転させてください' -f $p.Text, $revs),
                "回し終わったら手を離してください (2.5 秒止まると次へ進みます)。`nボールに印が無いときは、テープやペンで小さな印を付けてください。持ち替えても大丈夫です。")
            $Ctx.Form.SetProgress($n - 1, $plan.Count)
            $Ctx.Form.SetStatus('', 0)
            $Ctx.Form.ClearEvents()
            $r = Wait-KcStep -Ctx $Ctx -TimeoutMs 90000 -Done {
                param($ev, $now)
                Test-KcMotionSettled $ev $now 200 2500
            }
            if ($r.Outcome -eq 'abort') { return 'abort' }
            if ($r.Outcome -ne 'done') {
                Add-KcInputResult $Ctx $cat ('速さ ({0}のボール)' -f $bn) 'SKIP' '(スキップ)'
                return 'done'
            }
            $m = Measure-KcMotion $r.Events
            if ($null -ne $accel) {
                # ファームのカーソルの加速を取り除く (転がす速さで倍率が変わるため)
                $pre = Remove-KcAccel $m.Samples $accel ([int]$th.accel_window_ms) ([int]$th.accel_idle_ms)
                $saturated += $pre.Saturated
                $strokes += @{ Axis = $p.Axis; Dx = $pre.Dx; Dy = $pre.Dy; Revolutions = $revs }
                Show-KcStepResult $Ctx 'PASS' ('X {0:F0} / Y {1:F0} カウント (加速を除く。加速の後は X {2} / Y {3})' -f $pre.Dx, $pre.Dy, $m.Dx, $m.Dy)
            } else {
                $strokes += @{ Axis = $p.Axis; Dx = $m.Dx; Dy = $m.Dy; Revolutions = $revs }
                Show-KcStepResult $Ctx 'PASS' ('X {0} / Y {1} カウント' -f $m.Dx, $m.Dy)
            }
            Wait-KcPause $Ctx 600
        }
        $meas = Get-KcSpeedMeasurement $strokes $Ctx.Options.Diameter
        $tol = [double]$Ctx.Common.thresholds.speed_repeat_tolerance
        $ref = $Ctx.SpeedReference
        $rec = New-KcSpeedRecommendation -Measurement $meas -Reference $ref -Firmware $fw -Thresholds $Ctx.Common.thresholds
        $text = $rec.Summary
        $redo = ''
        if ($saturated -gt 0) {
            $redo = ('速く回しすぎて、1 回の報告の上限 ({0}) に達しました ({1} 回)。もう少しゆっくり回して、やり直してください。' -f [int]$accel.clamp, $saturated)
        } elseif ($meas.Spread -gt $tol) {
            $redo = ('2 回の計測の差が {0:P0} あります。回転数がずれていないか確かめて、やり直してください。' -f $meas.Spread)
        }
        if ($redo) {
            $text = $redo + "`n" + $text
            Show-KcStepResult $Ctx 'WARN' $text
        } else {
            Show-KcStepResult $Ctx $rec.Status $text
        }
        $Ctx.Form.SetDetail("やり直すときは「やり直し」、よければ「次へ」を押してください。`n" + ((@($rec.Lines) | Select-Object -First 1) -join ''))
        $o = Wait-KcNextOrRetry $Ctx
        if ($o -eq 'abort') { return 'abort' }
        if ($o -eq 'retry') { continue }
        $status = $rec.Status
        if ($redo -and $status -eq 'PASS') {
            $status = 'WARN'
        }
        $hint = ''
        if ($redo) {
            $hint = $redo
        } elseif ($status -eq 'WARN') {
            $hint = '推奨値 (Details) を overlay / 設定に反映してください。ツールはファームを書き換えません'
        }
        Add-KcInputResult $Ctx $cat ('速さ ({0}のボール)' -f $bn) $status $rec.Summary $hint (@($rec.Lines) + @($rec.Notes))
        $entry = [pscustomobject]@{
            time = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'); keyboard = $Ctx.Expected.id; name = $Ctx.Expected.name; ball = $Ball; kind = 'speed'
            per_rev_x = [math]::Round($meas.PerRevX, 1); per_rev_y = [math]::Round($meas.PerRevY, 1); per_rev = [math]::Round($meas.PerRev, 1)
            diameter_mm = $Ctx.Options.Diameter; cpi = $null; device = $Ctx.MouseName
        }
        if ($null -ne $meas.Cpi) {
            $entry.cpi = [math]::Round($meas.Cpi, 1)
        }
        $Ctx.CalibEntries.Add($entry)
        if ($Ctx.Expected.id -eq 'lism' -and $null -eq $Ctx.Options.SpeedReference) {
            # LisM は基準になる (次からほかの機種と比べるのに使う)
            $Ctx.SpeedReference = [pscustomobject]@{ Cpi = $entry.cpi; PerRev = $entry.per_rev; Source = ('LisM {0} {1}' -f $Ball, $entry.time) }
        }
        return 'done'
    }
}

# ---------------------------------------------------------------------------
# 全体
# ---------------------------------------------------------------------------

# $Options: @{ Sections = @('Keys','Behaviors','Trackball','Calibrate'); Balls = @('right'); Speed = $bool; Diameter = mm または $null;
#             Strength = 0〜1; SpeedReference = 基準の実効 CPI または $null; CachePath; ReadoutMismatch = @{ "レイヤー:位置" = $true } }
function Invoke-KcInputTest {
    param(
        [Parameter(Mandatory = $true)] $Expected,
        [Parameter(Mandatory = $true)] $Common,
        [Parameter(Mandatory = $true)] $Results,
        [Parameter(Mandatory = $true)] [hashtable]$Options
    )
    $ctx = @{
        Expected = $Expected; Common = $Common; Results = $Results; Options = $Options
        ScanTable = (New-KcScanTable $Common); Keyboard = [long]0; Mouse = [long]0; Devices = @(); KeyboardName = ''; MouseName = ''
        Category = ('{0}: 実動作' -f $Expected.name); CalibCategory = ('{0}: トラックボールの正規化' -f $Expected.name)
        CalibEntries = (New-Object 'System.Collections.Generic.List[object]'); SpeedReference = $null; Form = $null
        AmlTimeoutPassed = $false
        # レイヤー・ビヘイビアのテスト (behavior-test.ps1)。Mismatch: 読み出し検査で違っていた "レイヤー:位置"
        Mismatch = (Get-KcProp $Options 'ReadoutMismatch' @{})
    }
    if ($null -ne $Options.SpeedReference) {
        $ctx.SpeedReference = [pscustomobject]@{ Cpi = [double]$Options.SpeedReference; PerRev = $null; Source = '-SpeedReference' }
    } else {
        $ctx.SpeedReference = Get-KcSpeedReference (Read-KcCalibCache $Options.CachePath)
    }
    $sections = @($Options.Sections)
    $doKeys = $sections -contains 'Keys'
    $doBehaviors = $sections -contains 'Behaviors'
    $doBall = $sections -contains 'Trackball'
    $doCalib = $sections -contains 'Calibrate'
    $tb = $Expected.interactive.trackball
    $outcome = 'done'
    $form = New-KcInputForm $Expected
    $ctx.Form = $form
    $consoleMode = [KcConsoleMode]::DisableQuickEdit()
    try {
        $form.MaskWinKey($true)
        if ($doKeys -or $doBall -or $doBehaviors) {
            # トラックボールの正規化だけのときは、キーを押さないので特定しない
            $outcome = Select-KcKeyboardDevice $ctx
            if ($outcome -eq 'done') {
                [void](Add-KcResult -Results $Results -Category $ctx.Category -Item 'キーボード' -Status INFO -Actual $ctx.KeyboardName)
            }
        }
        if ($outcome -eq 'done' -and $doKeys -and @($Expected.interactive.taps).Count -gt 0) {
            $outcome = Invoke-KcTapTest $ctx
        }
        if ($outcome -eq 'done' -and $doBehaviors) {
            $outcome = Invoke-KcBehaviorTest $ctx
        }
        if ($outcome -eq 'done' -and ($doBall -or $doCalib)) {
            $outcome = Select-KcMouseDevice $ctx
            if ($outcome -eq 'done') {
                [void](Add-KcResult -Results $Results -Category $ctx.Category -Item 'トラックボール' -Status INFO -Actual $ctx.MouseName)
            }
        }
        $lastKeys = $null
        foreach ($ball in @($Options.Balls)) {
            if ($outcome -ne 'done') { break }
            $keys = Get-KcHandKeys $tb $ball
            $lastKeys = $keys
            if ($doCalib) {
                $outcome = Invoke-KcEllipseCalib $ctx $ball
            }
            if ($outcome -eq 'done' -and $doBall) {
                $outcome = Invoke-KcAmlClickTest $ctx $ball $keys
            }
            if ($outcome -eq 'done' -and $doBall) {
                $outcome = Invoke-KcShiftClickTest $ctx $ball $keys
            }
            foreach ($rk in @($keys.release_ctrl, $keys.release_shift)) {
                if ($outcome -eq 'done' -and $doBall) {
                    $outcome = Invoke-KcAmlReleaseTest $ctx $ball $rk
                }
            }
            if ($outcome -eq 'done' -and $doBall) {
                $outcome = Invoke-KcScrollTest $ctx $ball $keys
            }
            if ($outcome -eq 'done' -and $doCalib -and $Options.Speed) {
                $outcome = Invoke-KcSpeedCalib $ctx $ball
            }
        }
        if ($outcome -eq 'done' -and $doBall -and $null -ne $lastKeys) {
            $outcome = Invoke-KcTimeoutTest $ctx $lastKeys
        }
        if ($outcome -eq 'done' -and $doBall -and $null -ne $lastKeys -and (Get-KcAmlThreshold $ctx) -gt 0) {
            $outcome = Invoke-KcAmlThresholdTest $ctx $lastKeys
        }
        if ($outcome -eq 'done') {
            $form.SetTexts('完了', '実動作テストが終わりました', '結果はコンソールに表示されます。')
            Wait-KcPause $ctx 800
        }
    } finally {
        $form.Confine($false)
        $form.MaskWinKey($false)
        $form.Close()
        $form.Dispose()
        [KcConsoleMode]::Restore($consoleMode)
        try {
            $Host.UI.RawUI.FlushInputBuffer()
        } catch {
            # コンソールが無いときは何もしない
        }
    }
    if ($outcome -eq 'abort') {
        [void](Add-KcResult -Results $Results -Category $ctx.Category -Item '実動作テスト' -Status SKIP -Actual '途中で中止しました')
    }
    if ($ctx.CalibEntries.Count -gt 0 -and $Options.CachePath) {
        foreach ($e in $ctx.CalibEntries) {
            Save-KcCalibEntry $Options.CachePath $e
        }
    }
    return $outcome
}
