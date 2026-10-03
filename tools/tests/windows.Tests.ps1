# C# ヘルパーのコンパイル (Windows PowerShell 5.1 では C# 5 でコンパイルされる) と、ウィンドウ (WPF) の描画のテスト

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'rawhid.ps1')
. (Join-Path $script:KcLib 'input-eval.ps1')
. (Join-Path $script:KcLib 'behavior-eval.ps1')
. (Join-Path $script:KcLib 'zmk-studio.ps1')
. (Join-Path $script:KcLib 'zmk-log.ps1')
. (Join-Path $script:KcLib 'input-test.ps1')
. (Join-Path $script:KcLib 'behavior-test.ps1')
. (Join-Path $script:KcLib 'layer-trace.ps1')

Test-Case 'RawHid.cs をコンパイルできる' {
    Import-KcCSharp 'RawHid.cs' 'KcRawHid'
    Assert-True ('KcRawHid' -as [type]) 'KcRawHid 型'
}

Test-Case 'RawHid: 開けないパスは例外になる' -WindowsOnly {
    Import-KcCSharp 'RawHid.cs' 'KcRawHid'
    Assert-Throws { [KcRawHid]::Query('\\?\HID#VID_0000&PID_0000#nothing', [byte[]](0x01), 100, 1) } '*cannot open*'
    Assert-Equal '' ([KcRawHid]::GetProductString('\\?\HID#VID_0000&PID_0000#nothing'))
}

Test-Case 'InputTestForm.cs をコンパイルして、ウィンドウを作れる' -WindowsOnly {
    Import-KcInputForm
    $form = New-Object KcInputTestForm
    try {
        $form.SetButtonTexts('次へ', 'やり直し', 'スキップ', '中止')
        $form.SetKeys([int[]]@(0, 1), [double[]]@(0, 1), [double[]]@(0, 0), [double[]]@(1, 1), [double[]]@(1, 1), [string[]]@('Q', 'W'))
        $form.SetKeyState(1, 2)
        $form.SetTexts('t', 'i', 'd')
        $form.SetSubtitle('LisM')
        $form.SetProgress(1, 2)
        $form.SetKeyLegendTexts('いまのキー', '合格', '違うキー', 'スキップ')
        $form.SetStatus('s', 3)
        Assert-Equal '' $form.TakeAction()
        Assert-Equal 0 @($form.TakeEvents()).Count
    } finally {
        $form.Dispose()
    }
}

# RAWINPUT のバイト列 (64 ビット: ヘッダー 24 バイト)
function New-RawInputBytes([int]$Type, [long]$Device, [byte[]]$Body, [int]$PtrSize = 8) {
    $header = 8 + 2 * $PtrSize
    $b = New-Object byte[] ($header + $Body.Length)
    [BitConverter]::GetBytes([int]$Type).CopyTo($b, 0)
    if ($PtrSize -eq 8) { [BitConverter]::GetBytes([long]$Device).CopyTo($b, 8) } else { [BitConverter]::GetBytes([int]$Device).CopyTo($b, 8) }
    $Body.CopyTo($b, $header)
    return , $b
}

Test-Case 'Raw Input の解析: キー (E0 付き) とマウス (移動・ボタン・ホイール)' -WindowsOnly {
    Import-KcInputForm
    $kb = New-Object byte[] 16
    [BitConverter]::GetBytes([uint16]0x5B).CopyTo($kb, 0)
    [BitConverter]::GetBytes([uint16]0x03).CopyTo($kb, 2)       # BREAK | E0
    [BitConverter]::GetBytes([uint16]0x5B).CopyTo($kb, 6)
    $e = [KcRawInputParser]::Parse((New-RawInputBytes 1 0x1234 $kb), 8, 5)
    Assert-Equal 'key' $e.Kind
    Assert-Equal 0x5B $e.Scan
    Assert-Equal 0xE0 $e.Prefix
    Assert-True $e.Break
    Assert-Equal 0x1234 $e.Device

    $ms = New-Object byte[] 24
    [BitConverter]::GetBytes([uint16]0x0401).CopyTo($ms, 4)     # WHEEL | BUTTON_1_DOWN
    [BitConverter]::GetBytes([int16]-120).CopyTo($ms, 6)
    [BitConverter]::GetBytes([int]5).CopyTo($ms, 12)
    [BitConverter]::GetBytes([int]-7).CopyTo($ms, 16)
    $m = [KcRawInputParser]::Parse((New-RawInputBytes 0 0x99 $ms), 8, 6)
    Assert-Equal 'mouse' $m.Kind
    Assert-Equal 5 $m.Dx
    Assert-Equal -7 $m.Dy
    Assert-Equal -120 $m.Wheel
    Assert-Equal 1 $m.Buttons

    $fake = New-Object byte[] 16
    [BitConverter]::GetBytes([uint16]0x2A).CopyTo($fake, 0)
    [BitConverter]::GetBytes([uint16]0x02).CopyTo($fake, 2)     # E0 の左 Shift (偽の Shift) は捨てる
    Assert-Equal $null ([KcRawInputParser]::Parse((New-RawInputBytes 1 1 $fake 4), 4, 7))
    Assert-Equal $null ([KcRawInputParser]::Parse((New-RawInputBytes 1 0 $kb), 8, 7)) '注入された入力 (デバイス 0) は捨てる'
    Assert-Equal 0 $e.TimeUs 'TimeUs はモニター用のウィンドウだけが埋める'
}

Test-Case 'InputTestForm.cs: モニター用のウィンドウ (KcInputMonitorForm) を作れる' -WindowsOnly {
    Import-KcInputForm
    $form = New-Object KcInputMonitorForm('t', '停止', 'マーク', 'クリア', 'hint')
    try {
        $form.AppendLog('x')
        $form.SetStatus('s', 1)
        Assert-Equal '' $form.TakeAction()
        Assert-Equal 0 @($form.TakeEvents()).Count
        Assert-True ($form.NowUs -ge 0) 'NowUs'
        Assert-True (-not $form.IsClosed)
        $form.RequestClose()
    } finally {
        $form.Dispose()
    }
    $list = @([KcInputMonitorForm]::ListDevices())
    foreach ($d in $list) {
        Assert-True ($d.Type -eq 0 -or $d.Type -eq 1) 'キーボードとマウスだけ'
    }
}

# ウィンドウの中身を PNG にする (描画で例外が出ないことを確かめる)。$env:KC_SCREENSHOT_DIR があれば
# そこに残す (CI は artifact に上げる)
function Save-UiSnapshot($Form, [string]$Name) {
    $dir = $env:KC_SCREENSHOT_DIR
    $keep = [bool]$dir
    if (-not $keep) {
        $dir = [System.IO.Path]::GetTempPath()
    }
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Force -Path $dir)
    }
    $path = Join-Path $dir ($Name + '.png')
    $Form.SaveSnapshot($path)
    Assert-True ((Get-Item -LiteralPath $path).Length -gt 1000) ('{0} の PNG' -f $Name)
    if (-not $keep) {
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
    }
}

# 画面外に、前面にせずに表示する
function Show-UiOffscreen($Window) {
    $Window.Topmost = $false
    $Window.ShowActivated = $false
    $Window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $Window.Left = -20000
    $Window.Top = -20000
    $Window.Show()
    [KcUi]::DoEvents()
}

# 要素の左端と右端 (ウィンドウの中身の座標)
function Get-UiSpan($Element, $Root) {
    $p = $Element.TranslatePoint((New-Object System.Windows.Point 0, 0), $Root)
    return [pscustomobject]@{ Left = $p.X; Right = $p.X + $Element.ActualWidth }
}

Test-Case 'テスト用のウィンドウを描画できる (各状態、最小の大きさ)' -WindowsOnly {
    Import-KcInputForm
    $expected = Get-KcExpected 'lism' $script:ExpectedDir
    $form = New-Object KcInputTestForm
    try {
        Initialize-KcInputForm $form $expected
        $w = $form.Window
        Show-UiOffscreen $w
        $root = $w.Content
        $form.SetTexts('準備: キーボードの特定', 'テストするキーボードのキーを 1 つ押してください',
            "Shift など、押しても何も起きないキーがおすすめです。`nPC 本体のキーボードやマウスには触らないでください。")
        Save-UiSnapshot $form 'keyboard-check-1-start'

        $pos = @($expected.physical.keys | ForEach-Object { [int]$_.pos })
        $form.SetKeyState($pos[0], 2)
        $form.SetKeyState($pos[1], 3)
        $form.SetKeyState($pos[2], 4)
        $form.SetKeyState($pos[3], 1)
        $form.SetTexts('キーのタップ (4 / 43)', '「R」をタップしてください', 'キーを押してすぐ離してください。')
        $form.SetProgress(3, 43)
        $form.SetStatus('違うキー: e', 2)
        Save-UiSnapshot $form 'keyboard-check-2-tap'

        $w.Width = $w.MinWidth
        $w.Height = $w.MinHeight
        $form.SetTexts('AML (自動マウスレイヤー): クリック',
            'カーソルが 1 cm ほど動くまでボールを転がしてから、「D」を押したまま、右のボールを手前 (自分の方) へゆっくり大きく転がしてください',
            "ボールを転がすと AML になり、「F」でクリック、「D」はスクロールのキーになります (文字は入力されません)。`nクリックはこのウィンドウの中だけで起きます。")
        $form.SetStatus("縦横比 1.15 (傾き 3.2°) → 補正後の予想 1.01`nやり直すときは「やり直し」、よければ「次へ」を押してください。", 3)
        $form.SetButtons($true, $true, $false)
        $form.SetLog('入力 123 件')
        [KcUi]::DoEvents()
        Save-UiSnapshot $form 'keyboard-check-3-min'
        Assert-True ($root.FindName('KeyboardCard').ActualHeight -ge 120) ('キーボード図の高さ: {0}' -f $root.FindName('KeyboardCard').ActualHeight)
        $footerTop = $root.FindName('Footer').TranslatePoint((New-Object System.Windows.Point 0, 0), $root).Y
        foreach ($name in @('StatusBanner', 'LogText')) {
            $e = $root.FindName($name)
            $bottom = $e.TranslatePoint((New-Object System.Windows.Point 0, 0), $root).Y + $e.ActualHeight
            Assert-True ($bottom -le $footerTop + 0.5) ('{0} がボタンの帯に重ならない ({1} > {2})' -f $name, $bottom, $footerTop)
        }
        $spans = @(@('AbortButton', 'RetryButton', 'NextButton') | ForEach-Object { Get-UiSpan $root.FindName($_) $root } | Sort-Object Left)
        for ($i = 1; $i -lt $spans.Count; $i++) {
            Assert-True ($spans[$i - 1].Right -le $spans[$i].Left) 'ボタンが重ならない'
        }
        Assert-True ($spans[$spans.Count - 1].Right -le $root.ActualWidth) 'ボタンがウィンドウに収まる'

        $form.SetStatus('残り 3 秒', 0)
        $form.SetProgress(7000, 10000)
        $form.SetStatus('OK: q', 1)
        $form.ClearKeyStates()
        Save-UiSnapshot $form 'keyboard-check-4-ok'
    } finally {
        $form.Dispose()
    }
    Assert-True $form.IsClosed '閉じた'
    Assert-Equal 'abort' $form.TakeAction() '閉じたら中止'
}

Test-Case '記録用のウィンドウを描画できる' -WindowsOnly {
    Import-KcInputForm
    $form = New-Object KcInputMonitorForm('input-monitor', '停止', 'マーク', 'クリア',
        ("別のアプリ (メモ帳など) にキーを入力したり、ボールを転がしたりしてください。`r`n" + '停止: 記録を終えて分析する / マーク: ログに区切りを入れる / クリア: ここまでの記録を捨てる'))
    try {
        Show-UiOffscreen $form.Window
        $form.AppendLog(("接続中のキーボード・マウス:`r`n  #1 キーボード  LisM (BLE)`r`n  #2 マウス      LisM (BLE)`r`n"))
        foreach ($n in 1..80) {
            $form.AppendLog(('{0,9:F3}  #1  キー   A  押す' -f ($n * 0.137)))
        }
        $form.SetStatus('経過 12.3 秒   イベント 456 件   #1 120  #2 336', 0)
        [KcUi]::DoEvents()
        Save-UiSnapshot $form 'input-monitor'
        Assert-True (-not $form.IsClosed)
        $form.RequestClose()
        [KcUi]::DoEvents()
        Assert-True $form.IsClosed '閉じた'
        Assert-Equal 'stop' $form.TakeAction() '閉じたら停止'
    } finally {
        $form.Dispose()
    }
}

# 要素の下端がボタンの帯より上にあるか
function Assert-UiAboveFooter($Root, [string[]]$Names) {
    $footerTop = $Root.FindName('Footer').TranslatePoint((New-Object System.Windows.Point 0, 0), $Root).Y
    foreach ($name in $Names) {
        $e = $Root.FindName($name)
        if ($e.Visibility -ne [System.Windows.Visibility]::Visible) { continue }
        $bottom = $e.TranslatePoint((New-Object System.Windows.Point 0, 0), $Root).Y + $e.ActualHeight
        Assert-True ($bottom -le $footerTop + 0.5) ('{0} がボタンの帯に重ならない ({1} > {2})' -f $name, $bottom, $footerTop)
    }
}

Test-Case 'テスト用のウィンドウ: レイヤー・ビヘイビアの手順を描画できる (レイヤーの帯・チップ・キーキャップ、最小の大きさ)' -WindowsOnly {
    Import-KcInputForm
    $expected = Get-KcExpected 'lism' $script:ExpectedDir
    $common = Get-KcExpected 'common' $script:ExpectedDir
    $scan = New-KcScanTable $common
    $form = New-Object KcInputTestForm
    try {
        Initialize-KcInputForm $form $expected
        $w = $form.Window
        Show-UiOffscreen $w
        $root = $w.Content
        $beh = $expected.interactive.behaviors
        $ctx = @{
            Form = $form; Expected = $expected; Common = $common; ScanTable = $scan; Behaviors = $beh
            KeyPositions = @($expected.physical.keys | ForEach-Object { [int]$_.pos }); LayerTally = @{ 1 = @{ Pass = 2; Fail = 0; Skip = 0; Total = 2 }; 6 = @{ Pass = 0; Fail = 1; Skip = 0; Total = 1 } }
            TestedLayers = @(0, 1, 2, 3, 4, 5, 6)
        }
        $form.SetExtraLegendTexts('押したまま (レイヤー)', '押したまま (修飾)', '押さない')
        $sc = @($beh.scenarios | Where-Object { $_.id -eq 'morph-mm_vim_u' })[0]
        $step = @($sc.steps)[1]
        Show-KcBehaviorStep $ctx $sc $step 'モッドモーフ (4 / 13): モッドモーフ mm_vim_u — 手順 2 / 2'
        $form.SetProgress(20, 56)
        # Ctrl を押したまま、マスクされて PgUp だけ (合格)
        $ok = @((New-KcKeyEvent 0 0x1D 0 $false), (New-KcKeyEvent 5 0x1D 0 $true), (New-KcKeyEvent 6 0x49 0xE0 $false), (New-KcKeyEvent 30 0x49 0xE0 $true))
        $t = Update-KcBehaviorOutputs $ctx $step $ok
        Assert-Equal 'PASS' $t.Status
        Show-KcStepResult $ctx 'PASS' ('OK: ' + $t.Actual)
        [KcUi]::DoEvents()
        Save-UiSnapshot $form 'keyboard-check-5-behavior'
        Assert-True ($root.FindName('LayerStrip').Visibility -eq [System.Windows.Visibility]::Visible) 'レイヤーの帯'
        Assert-True ($root.FindName('SequencePanel').Children.Count -ge 3) '手順のチップ'

        # &to の手順 (入る → 全部離す → タップ)、違う入力、最小の大きさ
        $to = @($beh.scenarios | Where-Object { $_.kind -eq 'to_layer' })[0]
        Show-KcBehaviorStep $ctx $to @($to.steps)[0] 'レイヤーの切り替え (&to) (1 / 4): VIM_VISUAL への切り替え (1) — 手順 1 / 4'
        $bad = @((New-KcKeyEvent 0 0x2F 0 $false), (New-KcKeyEvent 9 0x2F 0 $true))
        $t2 = Update-KcBehaviorOutputs $ctx @($to.steps)[0] $bad
        Assert-Equal 'FAIL' $t2.Status
        Show-KcStepResult $ctx 'FAIL' ($t2.Message + ' もう一度お願いします')
        $w.Width = $w.MinWidth
        $w.Height = $w.MinHeight
        [KcUi]::DoEvents()
        Save-UiSnapshot $form 'keyboard-check-6-behavior-min'
        Assert-True ($root.FindName('KeyboardCard').ActualHeight -ge 100) ('キーボード図の高さ: {0}' -f $root.FindName('KeyboardCard').ActualHeight)
        # カードが低いときは色の凡例を隠し、図に場所を回す
        $card = $root.FindName('KeyboardCard').ActualHeight
        Assert-Equal ($card -ge 140) ($root.FindName('Legend').Visibility -eq [System.Windows.Visibility]::Visible) ('凡例 (カードの高さ {0})' -f $card)
        Assert-True ($root.FindName('KeyboardView').ActualHeight -ge 56) ('図の高さ: {0}' -f $root.FindName('KeyboardView').ActualHeight)
        Assert-UiAboveFooter $root @('OutputPanel', 'StatusBanner')

        # グループの区切りと後片付け
        $form.ClearKeyBadges()
        $form.ResetKeyLegends()
        $form.SetSequence([string[]]@(), [string[]]@(), [int[]]@(), [string[]]@())
        $form.ClearOutputs()
        $form.SetLayerPath([string[]]@(), [int[]]@())
        $form.SetLayerOverview('', [string[]]@(), [int[]]@())
        [KcUi]::DoEvents()
        Assert-True ($root.FindName('LayerStrip').Visibility -ne [System.Windows.Visibility]::Visible) 'レイヤーの帯を隠す'
    } finally {
        $form.Dispose()
    }
}

Test-Case 'レイヤーの動きを見るウィンドウを描画できる (ログから、レイヤーの解決・時系列)' -WindowsOnly {
    Import-KcInputForm
    $expected = Get-KcExpected 'lism' $script:ExpectedDir
    $common = Get-KcExpected 'common' $script:ExpectedDir
    $form = New-Object KcLayerTraceForm
    try {
        $keys = @($expected.physical.keys)
        $form.SetButtonTexts('終了', '一時停止', 'クリア', 'ログを保存')
        $form.SetKeyboardName('LisM')
        $form.SetCaptions('レイヤー', '表示: BASE', '送ったキー', '押したキー (新しい順)')
        $form.SetTexts('レイヤーの動きを見る', 'キーボードのキーを自由に押すと、そのキーがどのレイヤーで、どう解決されたかが出ます。')
        $form.SetKeys([int[]]@($keys | ForEach-Object { [int]$_.pos }), [double[]]@($keys | ForEach-Object { [double]$_.x }),
            [double[]]@($keys | ForEach-Object { [double]$_.y }), [double[]]@($keys | ForEach-Object { [double]$_.w }),
            [double[]]@($keys | ForEach-Object { [double]$_.h }), [string[]]@($keys | ForEach-Object { [string]$_.legend }))
        $form.SetPort('COM7 ログ受信中', 1)
        Show-UiOffscreen $form.Window
        $view = @{
            Form = $form; Expected = $expected; ScanTable = (New-KcScanTable $common); State = (New-KcLayerTrace $expected)
            KeyPositions = @($keys | ForEach-Object { [int]$_.pos }); ShownLayer = -1; ShownLegends = ''; LastSeq = 0
            Seqs = (New-Object 'System.Collections.Generic.List[int]'); Paused = $false; CacheDir = ''
        }
        $log = @(
            '[00:00:01.000,000] <dbg> zmk: zmk_physical_layouts_kscan_process_msgq: Row: 3, col: 0, position: 36, pressed: true',
            '[00:00:01.000,100] <dbg> zmk: zmk_keymap_apply_position_state: layer_id: 0 position: 36, binding name: momentary_layer',
            '[00:00:01.000,200] <dbg> zmk: mo_keymap_binding_pressed: position 36 layer 2',
            '[00:00:01.000,300] <dbg> zmk: set_layer_state: layer_changed: layer 2 state 1',
            '[00:00:01.100,000] <dbg> zmk: peripheral_event_work_callback: Trigger key position state change for 10',
            '[00:00:01.100,100] <dbg> zmk: zmk_keymap_apply_position_state: layer_id: 2 position: 10, binding name: key_press',
            '[00:00:01.100,200] <dbg> zmk: on_keymap_binding_pressed: position 10 keycode 0x700E0',
            '[00:00:01.100,300] <dbg> zmk: hid_listener_keycode_pressed: usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00',
            '[00:00:01.200,000] <dbg> zmk: zmk_physical_layouts_kscan_process_msgq: Row: 0, col: 1, position: 6, pressed: true',
            '[00:00:01.200,100] <dbg> zmk: zmk_keymap_apply_position_state: layer_id: 2 position: 6, binding name: MM_VIM_U',
            '[00:00:01.200,200] <dbg> zmk: on_keymap_binding_pressed: position 6 keycode 0x7004B',
            '[00:00:01.200,300] <dbg> zmk: hid_listener_keycode_pressed: usage_page 0x07 keycode 0x4B implicit_mods 0x00 explicit_mods 0x01'
        )
        foreach ($l in $log) {
            Update-KcLayerTrace $view.State (ConvertFrom-KcZmkLogLine $l)
        }
        Update-KcTraceView $view
        [KcUi]::DoEvents()
        Save-UiSnapshot $form 'keyboard-check-7-trace'
        $root = $form.Window.Content
        Assert-Equal 3 $root.FindName('Timeline').Items.Count '時系列'
        Assert-True ($root.FindName('CascadePanel').Children.Count -ge 2) 'レイヤーの段'
        Assert-Equal '' $form.TakeAction()
        $form.Window.Width = $form.Window.MinWidth
        $form.Window.Height = $form.Window.MinHeight
        [KcUi]::DoEvents()
        Save-UiSnapshot $form 'keyboard-check-8-trace-min'
        # 最小の大きさでも、レイヤーのチップは折り返して窓に収まり、解決の欄はスクロールしなくても全部見える
        $right = $root.ActualWidth
        foreach ($chip in $root.FindName('LayerChips').Children) {
            $x = $chip.TranslatePoint((New-Object System.Windows.Point 0, 0), $root).X + $chip.ActualWidth
            Assert-True ($x -le $right + 0.5) ('レイヤーのチップが窓に収まる ({0} > {1})' -f $x, $right)
        }
        $scroll = $root.FindName('ResolveScroll')
        Assert-True ($scroll.ScrollableHeight -le 0.5) ('解決の欄がスクロールなしで見える (はみ出し {0})' -f $scroll.ScrollableHeight)
    } finally {
        $form.Dispose()
    }
    Assert-True $form.IsClosed '閉じた'
    Assert-Equal 'stop' $form.TakeAction() '閉じたら終了'
}
