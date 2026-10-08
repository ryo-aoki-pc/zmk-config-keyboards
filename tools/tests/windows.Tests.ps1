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
. (Join-Path $script:KcLib 'hold-tap-sim.ps1')
. (Join-Path $script:KcLib 'hold-tap.ps1')
. (Join-Path $script:KcLib 'hold-tap-ui.ps1')
. (Join-Path $script:KcLib 'keyboard-sim.ps1')
. (Join-Path $script:KcLib 'keyboard-sim-ui.ps1')
. (Join-Path $script:ToolsDir 'lib\firmware-release.ps1')
. (Join-Path $script:ToolsDir 'lib\flash-plan.ps1')
. (Join-Path $script:ToolsDir 'lib\flash-ui.ps1')
. (Join-Path $script:TestsDir 'flash-fixtures.ps1')

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

Test-Case 'ログのフォント: HackGen Console NF を先頭に、無ければ BIZ UDGothic に落ちる' -WindowsOnly {
    Import-KcInputForm
    $root = $null
    $window = [KcUi]::CreateWindow('InputMonitorWindow.xaml', [ref]$root)
    try {
        $source = $window.FindResource('KcMonoFont').Source
        Assert-True ($source -like '*HackGen Console NF, BIZ UDGothic, MS Gothic') $source
    } finally {
        $window.Close()
    }
    Assert-True (-not [KcUi]::IsSystemFont('No Such Font Family')) 'IsSystemFont'
    Assert-Equal $null ([KcUi]::FindUserFontFile('No Such Font Family'))
    Assert-Equal 'file:///C:/Users/Taro%20Yamada%2Cx/Fonts/a.ttf#HackGen Console NF, MS Gothic' `
        ([KcUi]::FontFileSource('C:\Users\Taro Yamada,x\Fonts\a.ttf', 'HackGen Console NF', 'MS Gothic'))
    # ファイルの URI で指定したフォント (等幅の Courier New) が使われる。次の候補の Segoe UI に落ちると i と M の幅が違う
    $family = New-Object System.Windows.Media.FontFamily ([KcUi]::FontFileSource((Join-Path $env:windir 'Fonts\cour.ttf'), 'Courier New', 'Segoe UI'))
    $typeface = New-Object System.Windows.Media.Typeface($family, [System.Windows.FontStyles]::Normal,
        [System.Windows.FontWeights]::Normal, [System.Windows.FontStretches]::Normal)
    $width = {
        param([string]$Text)
        (New-Object System.Windows.Media.FormattedText($Text, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Windows.FlowDirection]::LeftToRight, $typeface, 20.0, [System.Windows.Media.Brushes]::Black)).Width
    }
    Assert-Near (& $width 'iiii') (& $width 'MMMM') 0.01 'Courier New の i と M の幅'
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

# 要素の中の TextBlock (ContentPresenter が文字列から作るものも含む)
function Get-UiTextBlocks($Element) {
    $found = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push($Element)
    while ($stack.Count -gt 0) {
        $e = $stack.Pop()
        if ($e -is [System.Windows.Controls.TextBlock]) { [void]$found.Add($e) }
        $n = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($e)
        for ($i = 0; $i -lt $n; $i++) { $stack.Push([System.Windows.Media.VisualTreeHelper]::GetChild($e, $i)) }
    }
    return $found.ToArray()
}

# 折り返さない TextBlock の文字が、親から割り当てられた幅に収まる (WPF は収まらない文字を切って描く。
# そのとき ActualWidth は文字の幅のままなので、同じ書式の TextBlock を測って、割り当ての幅と比べる)
function Assert-UiTextNotClipped($Element) {
    foreach ($tb in (Get-UiTextBlocks $Element)) {
        if (-not $tb.IsVisible -or -not $tb.Text) { continue }
        if ($tb.TextWrapping -ne [System.Windows.TextWrapping]::NoWrap -or $tb.TextTrimming -ne [System.Windows.TextTrimming]::None) { continue }
        $probe = New-Object System.Windows.Controls.TextBlock
        $probe.Text = $tb.Text
        $probe.FontFamily = $tb.FontFamily
        $probe.FontSize = $tb.FontSize
        $probe.FontWeight = $tb.FontWeight
        $probe.FontStyle = $tb.FontStyle
        $probe.FontStretch = $tb.FontStretch
        $probe.Language = $tb.Language
        [System.Windows.Media.TextOptions]::SetTextFormattingMode($probe, [System.Windows.Media.TextOptions]::GetTextFormattingMode($tb))
        $probe.Measure((New-Object System.Windows.Size ([double]::PositiveInfinity), ([double]::PositiveInfinity)))
        $slot = [System.Windows.Controls.Primitives.LayoutInformation]::GetLayoutSlot($tb)
        $room = $slot.Width - $tb.Margin.Left - $tb.Margin.Right
        Assert-True ($probe.DesiredSize.Width -le $room + 1) ('「{0}」が切れない ({1:N1} > {2:N1})' -f $tb.Text, $probe.DesiredSize.Width, $room)
    }
}

# 書き込みツールの選ぶ画面: 3 つの欄がウィンドウに収まり、オプションの文字が切れない
function Assert-UiFlashSelectFits($Root) {
    $width = $Root.ActualWidth
    foreach ($name in @('KeyboardsCard', 'BuildsCard', 'OptionsCard')) {
        $span = Get-UiSpan $Root.FindName($name) $Root
        Assert-True ($span.Right -le $width + 0.5) ('{0} がウィンドウに収まる ({1:N1} > {2:N1})' -f $name, $span.Right, $width)
    }
    Assert-UiTextNotClipped $Root.FindName('OptionsPanel')
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
        # 96 DPI でちょうど 100 前後。拡大率が 175% などの画面では、レイアウトの丸めで 1 物理ピクセル (0.57) 低くなる
        Assert-True ($root.FindName('KeyboardCard').ActualHeight -ge 99) ('キーボード図の高さ: {0}' -f $root.FindName('KeyboardCard').ActualHeight)
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

# 書き込みツールの子プロセスの偽物 (HasExited / ExitCode はテストで変える)
function New-WfChild([string[]]$Lines = @(), [int]$ExitCode = 0, [bool]$Exited = $true) {
    $lineObjects = @(foreach ($l in $Lines) { [pscustomobject]@{ Text = $l; IsError = $false; Partial = $false } })
    $child = [pscustomobject]@{ Pending = $lineObjects; HasExited = $Exited; ExitCode = $ExitCode; Killed = $false }
    $child | Add-Member -MemberType ScriptMethod -Name TakeLines -Value { $a = $this.Pending; $this.Pending = @(); return , $a }
    $child | Add-Member -MemberType ScriptMethod -Name Kill -Value { $this.Killed = $true; $this.HasExited = $true; $this.ExitCode = 1 }
    $child | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
    return $child
}

# 本物の KcFlashForm と画面の流れ (flash-ui.ps1)。一覧の取得・ダウンロード・子プロセスは偽物
function New-WfContext($Form) {
    $script:WfChildren = New-Object System.Collections.Queue
    return (New-FlashUiContext -Form $Form -ToolsDir 'C:\tools' -WaitSeconds 600 `
            -GetBuilds {
                param($Repo)
                $builds = @(ConvertFrom-FirmwareListPages @(New-FlashFixtureLismJson) (New-FlashFixtureIssuesJson))
                if ($Repo -notlike '*LisM') { foreach ($b in $builds) { $b.Assets = $null } }
                return @{ Builds = $builds; Source = 'api'; Message = ''; Level = 0; FetchedAt = [DateTime]::UtcNow }
            } `
            -Download {
                param($Repo, $Tag, $Assets, $OnFile)
                $paths = @{}
                for ($i = 0; $i -lt $Assets.Count; $i++) {
                    & $OnFile $i $Assets.Count $Assets[$i]
                    $paths[$Assets[$i]] = 'C:\fw\' + $Assets[$i]
                }
                return @{ Paths = $paths; Info = @{ commit = 'aaaaaaa1234'; built = '2026-10-02T03:00:00Z' } }
            } `
            -NewChild { param($Command) $script:WfChildren.Dequeue() })
}

function Invoke-WfActions($Ctx) {
    foreach ($a in (Get-FlashUiCoalescedActions $Ctx.Form.TakeActions())) {
        Invoke-FlashUiAction $Ctx $a
    }
    [KcUi]::DoEvents()
}

Test-Case '書き込みツールのウィンドウ: 定数が画面の流れ (flash-ui.ps1) と同じ' -WindowsOnly {
    Import-KcInputForm
    Assert-Equal ([KcFlashForm]::PageSelect) $script:FlashUiPageSelect
    Assert-Equal ([KcFlashForm]::PageRun) $script:FlashUiPageRun
    Assert-Equal ([KcFlashForm]::LevelOk) $script:FlashUiLevelOk
    Assert-Equal ([KcFlashForm]::LevelNg) $script:FlashUiLevelNg
    Assert-Equal ([KcFlashForm]::LevelWarn) $script:FlashUiLevelWarn
    Assert-Equal ([KcFlashForm]::LevelFaint) $script:FlashUiLevelFaint
    Assert-Equal ([KcFlashForm]::StepActive) $script:FlashUiStepActive
    Assert-Equal ([KcFlashForm]::StepDone) $script:FlashUiStepDone
    Assert-Equal ([KcFlashForm]::StepFailed) $script:FlashUiStepFailed
    Assert-Equal ([KcFlashForm]::KindPr) $script:FlashUiKinds['pr']
    Assert-Equal ([KcFlashForm]::KindCustom) $script:FlashUiKinds['custom']
    Assert-Equal ([KcFlashForm]::PrMerged) $script:FlashUiPrStates['merged']
    Assert-Equal ([KcFlashForm]::PrClosed) $script:FlashUiPrStates['closed']
    Assert-Equal ([KcFlashForm]::StyleSegments) $script:FlashUiStyleSegments
}

Test-Case '書き込みツールのウィンドウを描画できる (選ぶ画面・最小の大きさ・書き込み中・失敗・完了)' -WindowsOnly {
    Import-KcInputForm
    $form = New-Object KcFlashForm('ファームウェアの書き込み')
    try {
        $w = $form.Window
        Show-UiOffscreen $w
        $root = $w.Content
        $ctx = New-WfContext $form
        Initialize-FlashUi $ctx 'LisM'
        [KcUi]::DoEvents()
        Assert-Equal 4 $root.FindName('BuildList').Children.Count 'ビルドの一覧'
        Assert-Equal 10 $root.FindName('KeyboardList').Children.Count '機種 8 台とグループの見出し 2 つ'
        Assert-Equal 0 @($form.TakeActions()).Count '選び直しただけでは操作にならない'
        Save-UiSnapshot $form 'flash-1-select'
        Assert-UiFlashSelectFits $root

        # PR のビルドをクリック → 操作 build:firmware-pr-27
        $pr = @($root.FindName('BuildList').Children | Where-Object { $_.Content -ne $null })[1]
        $pr.IsChecked = $true
        Assert-Equal 'build:firmware-pr-27' (@($form.TakeActions()) -join ',')
        Invoke-FlashUiAction $ctx 'build:firmware-pr-27'
        Invoke-FlashUiAction $ctx 'option:mode:ResetBoth'
        Invoke-FlashUiAction $ctx 'option:central:studio'
        [KcUi]::DoEvents()
        Assert-Equal 4 $root.FindName('PlanSteps').Children.Count '手順'
        Save-UiSnapshot $form 'flash-2-select-options'
        Assert-UiFlashSelectFits $root
        Invoke-FlashUiAction $ctx 'option:central:logging'
        [KcUi]::DoEvents()
        Assert-UiFlashSelectFits $root

        $w.Width = $w.MinWidth
        $w.Height = $w.MinHeight
        [KcUi]::DoEvents()
        Save-UiSnapshot $form 'flash-3-select-min'
        Assert-UiAboveFooter $root @('SelectPage')
        Assert-UiFlashSelectFits $root
        Invoke-FlashUiAction $ctx 'option:central:studio'
        $spans = @(@('CloseButton', 'StartButton') | ForEach-Object { Get-UiSpan $root.FindName($_) $root } | Sort-Object Left)
        Assert-True ($spans[0].Right -le $spans[1].Left) 'ボタンが重ならない'
        Assert-True ($spans[1].Right -le $root.ActualWidth) 'ボタンがウィンドウに収まる'
        $w.Width = 1220
        $w.Height = 800

        # 書き込み: 1 手順目は書き込み中、ログに成功・失敗・薄い行
        $script:WfChildren.Enqueue((New-WfChild @('ファームウェア: settings_reset-seeeduino_xiao_ble-zmk.uf2', '  nRF52840 / 196 ブロック', '', 'ブートローダのドライブを待っています...', '  (ドライブ切断によるエラー「...」は想定どおり)') 0 $false))
        $root.FindName('StartButton').RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        Assert-Equal 'start' (@($form.TakeActions()) -join ',')
        Invoke-FlashUiAction $ctx 'start'
        Update-FlashUiTick $ctx
        [KcUi]::DoEvents()
        Assert-Equal 'run' $ctx.State.Phase
        Assert-True ($root.FindName('RunPage').Visibility -eq [System.Windows.Visibility]::Visible) '書き込む画面'
        Save-UiSnapshot $form 'flash-4-run'
        Assert-UiAboveFooter $root @('RunPage')

        $ctx.State.Child.Pending = @([pscustomobject]@{ Text = '失敗: 600 秒待ってもブートローダのドライブが見つかりませんでした。'; IsError = $false; Partial = $false },
            [pscustomobject]@{ Text = '  リセットボタンを素早く 2 回押してください。'; IsError = $false; Partial = $false })
        $ctx.State.Child.ExitCode = 1
        $ctx.State.Child.HasExited = $true
        Update-FlashUiTick $ctx
        [KcUi]::DoEvents()
        Assert-Equal 'failed' $ctx.State.Phase
        Save-UiSnapshot $form 'flash-5-failed'
        $spans = @(@('CloseButton', 'BackButton', 'RetryButton') | ForEach-Object { Get-UiSpan $root.FindName($_) $root } | Sort-Object Left)
        for ($i = 1; $i -lt $spans.Count; $i++) {
            Assert-True ($spans[$i - 1].Right -le $spans[$i].Left) 'ボタンが重ならない'
        }

        for ($i = 0; $i -lt 4; $i++) { $script:WfChildren.Enqueue((New-WfChild @('成功: ブートローダが全ブロックを受け取り、ボードが再起動しました。') 0 $true)) }
        Invoke-FlashUiAction $ctx 'retry'
        for ($i = 0; $i -lt 4; $i++) { Update-FlashUiTick $ctx }
        [KcUi]::DoEvents()
        Assert-Equal 'done' $ctx.State.Phase
        Save-UiSnapshot $form 'flash-6-done'
    } finally {
        $form.Dispose()
    }
    Assert-True $form.IsClosed '閉じた'
    Assert-Equal 'close' (@($form.TakeActions()) -join ',') '閉じたら close'
}

Test-Case '書き込みツールのウィンドウ: BMP の設定リセットの後の「続ける」を描画できる' -WindowsOnly {
    Import-KcInputForm
    $form = New-Object KcFlashForm('ファームウェアの書き込み')
    try {
        Show-UiOffscreen $form.Window
        $ctx = New-WfContext $form
        Initialize-FlashUi $ctx 'torabo-tsuki-lp'
        Invoke-FlashUiAction $ctx 'option:mode:ResetBoth'
        $script:WfChildren.Enqueue((New-WfChild @('成功: ok') 0 $true))
        Invoke-FlashUiAction $ctx 'start'
        Update-FlashUiTick $ctx
        [KcUi]::DoEvents()
        Assert-Equal 'pause' $ctx.State.Phase
        Assert-True ($form.Window.Content.FindName('ContinueButton').Visibility -eq [System.Windows.Visibility]::Visible) '続ける'
        Save-UiSnapshot $form 'flash-7-bmp-continue'

        # 書き込み中は、タイトルバーで閉じても close の操作になるだけ (PowerShell が子プロセスを止めてから閉じる)
        $form.Window.Close()
        [KcUi]::DoEvents()
        Assert-True (-not $form.IsClosed) 'まだ閉じない'
        Assert-Equal 'close' (@($form.TakeActions()) -join ',')
    } finally {
        $form.Dispose()
    }
    Assert-True $form.IsClosed '閉じた'
}

Test-Case '書き込みツールのウィンドウ: 専用のスレッドで開き、別のスレッドから操作して閉じられる' -WindowsOnly {
    Import-KcInputForm
    $form = [KcFlashForm]::Launch('ファームウェアの書き込み (テスト)')
    try {
        $form.SetTexts('FLASH', 't', 's')
        $form.SetKeyboards([string[]]@('LisM'), [string[]]@('LisM'), [string[]]@('XIAO'), [string[]]@('ZMK'))
        $form.SelectKeyboard('LisM')
        $form.AppendLog('line', 1, $false)
        $form.SetStatus('s', 0)
        Start-Sleep -Milliseconds 200
        Assert-Equal 0 @($form.TakeActions()).Count
        Assert-True (-not $form.IsClosed) '開いている'
        $form.RequestClose()
        Assert-True ($form.WaitClosed(5000)) '閉じた'
    } finally {
        $form.Dispose()
    }
}

Test-Case 'タップホールドのウィンドウ: 定数がグラフのモデル (hold-tap.ps1) と同じ' -WindowsOnly {
    Import-KcInputForm
    Assert-Equal ([KcTimelineView]::LaneCaption) $script:KcHtLaneCaption
    Assert-Equal ([KcTimelineView]::LaneKey) $script:KcHtLaneKey
    Assert-Equal ([KcTimelineView]::LaneOutput) $script:KcHtLaneOutput
    Assert-Equal ([KcTimelineView]::LaneStrip) $script:KcHtLaneStrip
    Assert-Equal ([KcTimelineView]::BarPlain) $script:KcHtBarPlain
    Assert-Equal ([KcTimelineView]::BarUndecided) $script:KcHtBarUndecided
    Assert-Equal ([KcTimelineView]::BarTap) $script:KcHtBarTap
    Assert-Equal ([KcTimelineView]::BarHold) $script:KcHtBarHold
    Assert-Equal ([KcTimelineView]::BarMod) $script:KcHtBarMod
    Assert-Equal ([KcTimelineView]::BarLayer) $script:KcHtBarLayer
    Assert-Equal ([KcTimelineView]::BarKey) $script:KcHtBarKey
    Assert-Equal ([KcTimelineView]::BarOther) $script:KcHtBarOther
    Assert-Equal ([KcTimelineView]::BarStripTap) $script:KcHtBarStripTap
    Assert-Equal ([KcTimelineView]::BarStripHold) $script:KcHtBarStripHold
    Assert-Equal ([KcTimelineView]::BarStripNone) $script:KcHtBarStripNone
    Assert-Equal ([KcTimelineView]::MarkDecision) $script:KcHtMarkDecision
    Assert-Equal ([KcTimelineView]::MarkTerm) $script:KcHtMarkTerm
    Assert-Equal ([KcTimelineView]::MarkFirmware) $script:KcHtMarkFirmware
    Assert-Equal ([KcTimelineView]::MarkCursor) $script:KcHtMarkCursor
    Assert-Equal ([KcTimelineView]::ArrowCapture) $script:KcHtArrowCapture
    Assert-Equal ([KcHoldTapForm]::SummaryTap) 1
    Assert-Equal ([KcHoldTapForm]::SummaryHold) 2
}

# グラフの線のラベル (Canvas の Border) が重ならない
function Assert-UiChartLabelsApart($Root) {
    $chips = @($Root.FindName('ChartCanvas').Children | Where-Object { $_ -is [System.Windows.Controls.Border] } | ForEach-Object {
            $x = [System.Windows.Controls.Canvas]::GetLeft($_)
            $y = [System.Windows.Controls.Canvas]::GetTop($_)
            [pscustomobject]@{ Text = $_.Child.Text; L = $x; T = $y; R = $x + $_.DesiredSize.Width; B = $y + $_.DesiredSize.Height }
        })
    Assert-True ($chips.Count -ge 2) 'ラベルがある'
    for ($i = 0; $i -lt $chips.Count; $i++) {
        for ($j = $i + 1; $j -lt $chips.Count; $j++) {
            $a = $chips[$i]
            $b = $chips[$j]
            $apart = $a.R -le $b.L + 0.5 -or $b.R -le $a.L + 0.5 -or $a.B -le $b.T + 0.5 -or $b.B -le $a.T + 0.5
            Assert-True $apart ('「{0}」と「{1}」が重ならない' -f $a.Text, $b.Text)
        }
    }
}

# ログ版ファームの行 (zmk-log.Tests.ps1 と同じ書式)
function New-WhtLog([double]$Ms, [string]$Func, [string]$Msg) {
    $ts = [TimeSpan]::FromMilliseconds([math]::Floor($Ms))
    $us = [int](($Ms - [math]::Floor($Ms)) * 1000)
    return ('[{0:00}:{1:00}:{2:00}.{3:000},{4:000}] <dbg> zmk: {5}: {6}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds, $us, $Func, $Msg)
}

# 本物の KcHoldTapForm と画面の流れ (hold-tap-ui.ps1)。PC の時刻 $Pc にログの行が届き、ループが 1 回まわる (ファームの時刻 = $Pc + 4000)
function Step-Wht($Ctx, [double]$Pc, [string[]]$Lines = @()) {
    if ($Lines.Count -gt 0) { Add-KcHoldTapLogLines $Ctx $Lines $Pc }
    Update-KcHoldTapLive $Ctx $Pc
    [KcUi]::DoEvents()
}

Test-Case 'タップホールドのウィンドウを描画できる (組み合わせを選ぶ前・押している最中・終わった回・最小の大きさ)' -WindowsOnly {
    Import-KcInputForm
    $form = New-Object KcHoldTapForm('タップホールドのタイミング')
    try {
        $w = $form.Window
        Show-UiOffscreen $w
        $root = $w.Content
        $ctx = New-KcHoldTapContext -Form $form -Model (New-KcHtModel (Get-KcExpected 'lism' $script:ExpectedDir))
        Initialize-KcHoldTapUi $ctx
        [KcUi]::DoEvents()
        Assert-True $root.FindName('ChartMessage').IsVisible '組み合わせを選ぶ前は ① の案内'
        Assert-True ($root.FindName('ChartMessage').Text -like '① *') $root.FindName('ChartMessage').Text
        Assert-Equal '? + ?' $root.FindName('ComboText').Text
        Assert-True $root.FindName('ComboHint').IsVisible '選んでいる途中の案内'
        Assert-True (-not $root.FindName('PickButton').IsVisible) 'はじめは「やめる」が無い'
        Assert-Equal 4 $root.FindName('FlavorPanel').Children[0].Child.Children.Count 'flavor の 4 つ'
        Assert-Equal 0 @($form.TakeActions()).Count '表示しただけでは操作にならない'
        Save-UiSnapshot $form 'keyboard-check-9-holdtap-wait'
        Assert-UiTextNotClipped $root.FindName('SideCard')

        # 組み合わせを選ぶ: A を押して離し、H を押して離す
        Step-Wht $ctx 100 @((New-WhtLog 4100.2 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
            (New-WhtLog 4100.4 'on_hold_tap_binding_pressed' '10 new undecided hold_tap'))
        Assert-Equal 'A (Ctrl) + ?' $root.FindName('ComboText').Text
        Step-Wht $ctx 150 @((New-WhtLog 4150.0 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
            (New-WhtLog 4150.2 'on_hold_tap_binding_released' '10 cleaning up hold-tap'))
        Step-Wht $ctx 200 @((New-WhtLog 4200.3 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: true'))
        Step-Wht $ctx 250 @((New-WhtLog 4250.3 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: false'))
        Assert-Equal 'A (Ctrl) + H' $root.FindName('ComboText').Text
        Assert-True (-not $root.FindName('ComboHint').IsVisible) '決まったら案内を消す'
        Assert-True $root.FindName('PickButton').IsVisible '押して選び直す'
        $root.FindName('PickButton').RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        Assert-Equal 'pick' (@($form.TakeActions()) -join ',')

        # A を押したまま H を押した (押している最中)
        Step-Wht $ctx 1000 @((New-WhtLog 5000.2 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
            (New-WhtLog 5000.4 'on_hold_tap_binding_pressed' '10 new undecided hold_tap'))
        Step-Wht $ctx 1060 @((New-WhtLog 5060.3 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: true'),
            (New-WhtLog 5060.4 'position_state_changed_listener' '10 capturing 15 down event'))
        Assert-True $form.Timeline.IsLive '押している最中'
        # 描画・PNG 保存の所要時間で150msの判定境界を越えないよう、表示時刻を固定する。
        $form.Timeline.SetLive($true, 87, $false)
        $form.Timeline.Render()
        [KcUi]::DoEvents()
        Assert-Equal 87 $form.Timeline.Now '固定した表示時刻'
        Save-UiSnapshot $form 'keyboard-check-10-holdtap-live'
        Assert-Equal 'tapping-term (150 ms)' ($form.Timeline.LegendTexts -join '|') '押している最中: 判定はまだ出ない'
        Assert-Equal 1 $root.FindName('MarkLegendPanel').Children.Count
        Assert-UiChartLabelsApart $root
        $nowX = $form.Timeline.XOf($form.Timeline.Now)
        foreach ($r in @($root.FindName('ChartCanvas').Children | Where-Object { $_ -is [System.Windows.Shapes.Rectangle] -and [string]$_.ToolTip -eq '判定待ち' })) {
            $right = [System.Windows.Controls.Canvas]::GetLeft($r) + $r.Width
            Assert-True ($right -le $nowX + 5) ('判定待ちの帯は「今」で切る ({0:N1} > {1:N1})' -f $right, $nowX)
        }
        # 通常の呼び出しでは時計が進むことも別に確かめる。
        $form.SetLive($true, 87)
        Start-Sleep -Milliseconds 150
        [KcUi]::DoEvents()
        Assert-True ($form.Timeline.Now -ge 200) ('「今」はひとりでに進む ({0})' -f $form.Timeline.Now)
        # flavor の比較の行を押すと、その flavor にする操作
        $chart = Get-KcHoldTapChart $ctx.Model $ctx.Config $ctx.Episode $ctx.Result $ctx.Sweeps $ctx.Range
        $lane = -1
        for ($i = 0; $i -lt $chart.Lanes.Count; $i++) { if ($chart.Lanes[$i].Action -eq 'flavor:hold-preferred') { $lane = $i } }
        $form.Timeline.SimulateLaneClick($lane)
        Assert-Equal 'flavor:hold-preferred' (@($form.TakeActions()) -join ',')

        # H を離してホールドに決まり、A を離して 300 ms たつと、その回が残る
        Step-Wht $ctx 1100 @((New-WhtLog 5100.1 'zmk_physical_layouts_kscan_process_msgq' 'Row: 1, col: 5, position: 15, pressed: false'),
            (New-WhtLog 5100.2 'position_state_changed_listener' '10 capturing 15 up event'),
            (New-WhtLog 5100.3 'decide_hold_tap' '10 decided hold-interrupt (balanced decision moment other-key-up)'),
            (New-WhtLog 5100.4 'hid_listener_keycode_pressed' 'usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00'),
            (New-WhtLog 5100.5 'hid_listener_keycode_pressed' 'usage_page 0x07 keycode 0x0B implicit_mods 0x00 explicit_mods 0x00'),
            (New-WhtLog 5100.6 'hid_listener_keycode_released' 'usage_page 0x07 keycode 0x0B implicit_mods 0x00 explicit_mods 0x00'))
        Step-Wht $ctx 1140 @((New-WhtLog 5140.0 'peripheral_event_work_callback' 'Trigger key position state change for 10'),
            (New-WhtLog 5140.1 'hid_listener_keycode_released' 'usage_page 0x07 keycode 0xE0 implicit_mods 0x00 explicit_mods 0x00'),
            (New-WhtLog 5140.2 'on_hold_tap_binding_released' '10 cleaning up hold-tap'))
        Step-Wht $ctx 1600
        Assert-True (-not $form.Timeline.IsLive) '終わった回'
        Assert-True ($root.FindName('SummaryTitle').Text -like 'ホールド (ほかのキー):*') $root.FindName('SummaryTitle').Text
        Save-UiSnapshot $form 'keyboard-check-11-holdtap-done'
        Assert-Equal 'tapping-term (150 ms)|判定: ホールド (ほかのキー) (100 ms)|離した時刻 (140 ms)' ($form.Timeline.LegendTexts -join '|')
        Assert-Equal 3 $root.FindName('MarkLegendPanel').Children.Count
        Assert-UiChartLabelsApart $root

        # 設定を変えると、ファームの判定と違う線が出る。最小の大きさ
        [void](Invoke-KcHoldTapAction $ctx 'flavor:tap-preferred' 1700)
        [KcUi]::DoEvents()
        Assert-True $root.FindName('ChangedTag').IsVisible '変更あり'
        $w.Width = $w.MinWidth
        $w.Height = $w.MinHeight
        [KcUi]::DoEvents()
        Save-UiSnapshot $form 'keyboard-check-12-holdtap-min'
        Assert-True (@($form.Timeline.LegendTexts) -contains 'ファームの判定: ホールド (ほかのキー) (100 ms)') ($form.Timeline.LegendTexts -join ' / ')
        Assert-UiAboveFooter $root @('ChartCard', 'SummaryBanner', 'SideCard')
        Assert-UiTextNotClipped $root.FindName('SideCard')
        Assert-UiChartLabelsApart $root
    } finally {
        $form.Dispose()
    }
    Assert-True $form.IsClosed '閉じた'
    Assert-Equal 'close' (@($form.TakeActions()) -join ',') '閉じたら close'
}

Test-Case 'タップホールドのウィンドウ: 専用のスレッドで開き、別のスレッドから操作して閉じられる' -WindowsOnly {
    Import-KcInputForm
    $form = [KcHoldTapForm]::Launch('タップホールドのタイミング (テスト)')
    try {
        $form.SetTexts('HOLD-TAP', 't')
        $form.SetLabels('flavor', 'tapping-term', 'reset', 'changed', 'close', 'now {0} ms')
        $form.SetSettings('&mt', [string[]]@('balanced', 'tap-preferred'), [string[]]@('a', 'b'), 'balanced', 150, 50, 500, 'keymap', $false)
        $form.SetLive($true, 10)
        $form.MaskWinKey($true)
        Start-Sleep -Milliseconds 200
        Assert-Equal 0 @($form.TakeActions()).Count 'PowerShell からの値は操作にならない'
        Assert-True ($form.Timeline.Now -ge 150) ('「今」が進む ({0})' -f $form.Timeline.Now)
        Assert-True (-not $form.IsClosed) '開いている'
        $form.MaskWinKey($false)
        $form.RequestClose()
        Assert-True ($form.WaitClosed(5000)) '閉じた'
        Assert-Equal 'close' (@($form.TakeActions()) -join ',')
    } finally {
        $form.Dispose()
    }
}

# シミュレータの画面。実機は使わず、選択・表示と最小サイズでの描画を確かめる。
function Set-WindowsSimBoards($Form) {
    $Form.SetBoards([string[]]@('lism', 'keyball-kq-mini', 'kukey42', 'aroundfortyrb', 'pyuron', 'roba', 'torabo-tsuki-lp', 'keyball39', 'kq-mini'),
        [string[]]@('LisM', 'Keyball39 → KQ-mini', 'KUKEY42', 'AroundForty-RB', 'Pyuron', 'roBa', 'torabo-tsuki-lp', 'Keyball39', 'KQ-mini'), 'lism')
}

function Initialize-WindowsSimForm($Form) {
    $labels = [ordered]@{
        TitleText = 'キーボードシミュレータ'; SubtitleText = '機種とシナリオを選び、キー・レイヤー・マウスの出力を確認します。'
        BoardsCaption = '機種'; ScenariosCaption = 'シナリオ'; PictureCaption = '入力したキーの位置'; ReplayCaption = '入力と出力を時刻で確認'
        InputsCaption = '入力'; ExpectedCaption = '期待値'; ActualCaption = '実際の出力'; LogCaption = '実行ログ'
        OpenButton = 'JSON を開く'; StandardButton = '標準に戻す'; ReportButton = 'レポート'
        RunButton = '選択を実行'; RunAllButton = 'この機種を全件実行'; CancelButton = '中止'
        CloseButton = '閉じる'; PlayButton = '再生 / 一時停止'
    }
    $Form.SetLabels([string[]]@($labels.Keys), [string[]]@($labels.Values))
    Set-WindowsSimBoards $Form
    $suitePath = Join-Path $script:ToolsDir 'simulator/scenarios/lism-behaviors.json'
    $script:WindowsSimCases = ([System.IO.File]::ReadAllText($suitePath) | ConvertFrom-Json).scenarios
    $case = $script:WindowsSimCases[0]
    $Form.SetScenarios([string[]]@('0', '1'), [string[]]@($case.name, $script:WindowsSimCases[1].name), [string[]]@('', ''), '0')
    $geometry = Get-KcSimUiGeometry -Model (Get-KcSimModel 'lism') -Scenario $case
    $keys = $geometry.Keys
    $Form.SetKeys([int[]]@($keys | ForEach-Object { $_.Pos }), [double[]]@($keys | ForEach-Object { $_.X }),
        [double[]]@($keys | ForEach-Object { $_.Y }), [double[]]@($keys | ForEach-Object { $_.W }),
        [double[]]@($keys | ForEach-Object { $_.H }), [string[]]@($keys | ForEach-Object { $_.Legend }))
    $inputs = @{ events = $case.events; end_ms = $case.end_ms } | ConvertTo-Json -Depth 100
    $Form.SetDetails($case.name, 'lism-behaviors.json / lism', $inputs, ($case.expect | ConvertTo-Json -Depth 100), '未実行')
    $Form.SetSummary('実行できます', '入力と期待値を確認して「選択を実行」を押してください', 0)
    $Form.SetBusy($false, $true)
    $Form.SetReplay([long]$case.end_ms, $true)
    $replay = Get-KcSimUiReplay -Scenario $case -Actual $null -AtMs 0
    $Form.SetReplayState($replay.Text)
    $Form.SetKeyStates([int[]]$replay.Pressed)
    $Form.SetReportEnabled($false)
}

Test-Case 'シミュレータのウィンドウ: 選択・実行・結果・最小サイズを描画できる' -WindowsOnly {
    Import-KcInputForm
    $form = New-Object KcSimulatorForm('キーボードシミュレータ')
    try {
        $window = $form.Window
        Show-UiOffscreen $window
        $root = $window.Content
        Initialize-WindowsSimForm $form
        [KcUi]::DoEvents()
        Assert-Equal 9 $root.FindName('BoardPanel').Children.Count
        Assert-Equal 2 $root.FindName('ScenarioPanel').Children.Count
        Assert-Equal 0 @($form.TakeActions()).Count '表示の更新で入力操作が発生しない'
        Assert-True $root.FindName('InputsBox').IsReadOnly '入力は閲覧専用'
        Assert-True $root.FindName('ExpectedBox').IsReadOnly '期待値は閲覧専用'
        Assert-True $root.FindName('ActualBox').IsReadOnly '結果は閲覧専用'
        Save-UiSnapshot $form 'simulator-1-ready'

        $root.FindName('BoardPanel').Children[1].IsChecked = $true
        Assert-Equal 'board:keyball-kq-mini' (@($form.TakeActions()) -join ',')
        Set-WindowsSimBoards $form
        $root.FindName('ScenarioPanel').Children[1].IsChecked = $true
        Assert-Equal 'scenario:1' (@($form.TakeActions()) -join ',')
        $root.FindName('RunButton').RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        Assert-Equal 'run' (@($form.TakeActions()) -join ',')
        $root.FindName('ReplaySlider').Value = 50
        Assert-Equal 'seek:50' (@($form.TakeActions()) -join ',')

        $form.SetBusy($true, $true)
        Assert-True (-not $root.FindName('RunButton').IsEnabled) '二重実行を防ぐ'
        Assert-True $root.FindName('CancelButton').IsEnabled '中止できる'
        $form.SetSummary('実行中', '2 件のシナリオを検証しています。', 0)
        $form.AppendLog('PASS lism/' + $script:WindowsSimCases[0].name)
        Save-UiSnapshot $form 'simulator-2-running'

        $form.SetBusy($false, $true)
        $form.SetScenarios([string[]]@('0', '1'), [string[]]@(('合格  ' + $script:WindowsSimCases[0].name), ('失敗  ' + $script:WindowsSimCases[1].name)),
            [string[]]@('passed', 'failed'), '1')
        $case = $script:WindowsSimCases[1]
        $inputs = @{ events = $case.events; end_ms = $case.end_ms } | ConvertTo-Json -Depth 100
        $form.SetDetails($case.name, 'lism-behaviors.json / lism', $inputs, ($case.expect | ConvertTo-Json -Depth 100),
            '{ "status": "failed", "error": "期待したキー入力と実際の出力が一致しません" }')
        $form.SetSummary('1 件の検証に失敗しました', 'expect.keys: 期待したキー入力と実際の出力が一致しません。シナリオを選択して詳細を確認してください。', 2)
        $form.SetReportEnabled($true)
        $form.SetKeyStates([int[]]@(10, 15))
        $form.SetReplayState('100 ms / レイヤー: BASE, MOUSE / 押しているキー: 10, 15')
        [KcUi]::DoEvents()
        Assert-Equal 0 @($form.TakeActions()).Count '結果を反映しても操作が発生しない'
        Assert-True $root.FindName('ReportButton').IsEnabled
        Save-UiSnapshot $form 'simulator-3-result'

        $window.Width = $window.MinWidth
        $window.Height = $window.MinHeight
        [KcUi]::DoEvents()
        Save-UiSnapshot $form 'simulator-4-min'
        Assert-True ($root.FindName('KeyboardCanvas').ActualWidth -gt 100) 'キーボード図が描画される'
        Assert-True ($root.FindName('ScenarioScroll').ActualHeight -gt 100) 'シナリオを選べる高さ'
        $spans = @(@('RunButton', 'RunAllButton', 'CancelButton', 'CloseButton') | ForEach-Object { Get-UiSpan $root.FindName($_) $root } | Sort-Object Left)
        for ($i = 1; $i -lt $spans.Count; $i++) {
            Assert-True ($spans[$i - 1].Right -le $spans[$i].Left + 0.5) '操作ボタンが重ならない'
        }
        Assert-True ($spans[$spans.Count - 1].Right -le $root.ActualWidth + 0.5) '操作ボタンがウィンドウに収まる'
        Assert-UiTextNotClipped $root.FindName('RunButton')
        Assert-UiTextNotClipped $root.FindName('RunAllButton')
    } finally { $form.Dispose() }
    Assert-True $form.IsClosed
    Assert-Equal 'close' (@($form.TakeActions()) -join ',')
}

Test-Case 'シミュレータのウィンドウ: 専用スレッドからの更新と終了を処理する' -WindowsOnly {
    Import-KcInputForm
    $form = [KcSimulatorForm]::Launch('キーボードシミュレータ (テスト)')
    try {
        Initialize-WindowsSimForm $form
        $form.SetDetails('完了', 'test.json', 'input', 'expected', 'actual')
        $form.SetSummary('検証が完了しました', '成功 1 / 失敗 0', 1)
        $form.SetKeyStates([int[]]@())
        $form.AppendLog('完了: 成功 1 / 失敗 0')
        Save-UiSnapshot $form 'simulator-5-thread'
        Assert-Equal 0 @($form.TakeActions()).Count 'PowerShell からの更新は操作にならない'
        Assert-True (-not $form.IsClosed)
        $form.RequestClose()
        Assert-True ($form.WaitClosed(5000)) '閉じた'
        Assert-Equal 'close' (@($form.TakeActions()) -join ',')
    } finally { $form.Dispose() }
}
