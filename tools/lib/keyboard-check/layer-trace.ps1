# レイヤーの動きを見る (keyboard-check.ps1 -Mode Trace)。ZMK のログ版ファーム (右手側に *_logging.uf2) が USB の
# COM ポートに出すログを読み、自由に押したキーごとに、有効なレイヤー・&trans のフォールスルー・決まったレイヤーと
# バインディング・ビヘイビアの中 (ホールドタップの判定、タップダンスの回数、モッドモーフの分岐)・送ったキーを表示する。
# Windows のみ。ログの解析は zmk-log.ps1 (純粋関数)。COM ポートには何も送らない (読むだけ)。
# expected.ps1 / input-eval.ps1 / behavior-eval.ps1 / zmk-studio.ps1 / zmk-log.ps1 / input-test.ps1 が先に読み込まれている前提。

# ZMK (VID 1D50 / PID 615E) の COM ポートを開く (115200 bps、DTR オン。何も送らない)
function Open-KcLogPort([string]$Port) {
    $sp = New-Object System.IO.Ports.SerialPort($Port, 115200)
    $sp.DtrEnable = $true
    $sp.ReadTimeout = 50
    $sp.Encoding = [System.Text.Encoding]::UTF8
    $sp.Open()
    return $sp
}

function Close-KcLogPort($Port) {
    if ($null -ne $Port) {
        try { $Port.Close() } catch { }
        try { $Port.Dispose() } catch { }
    }
}

function Read-KcLogPort($Port) {
    try {
        if ($Port.IsOpen -and $Port.BytesToRead -gt 0) {
            return $Port.ReadExisting()
        }
    } catch {
        return $null
    }
    return ''
}

# ログ版のキーボードの COM ポートを探して読む (-Mode Trace と -Mode HoldTap で使う)。ログの行が届くまで ZMK の
# COM ポートをすべて開いて読み、ログの行が届いたポートだけを残す ($Port を指定したらそのポートだけ)
function New-KcLogPortReader([string]$Port = '') {
    return @{ Port = $Port; Ports = @{}; Buffers = @{}; Active = $null; ActiveName = ''; NextScan = [DateTime]::MinValue }
}

# 読めた行 (Lines) と、ポートの状態の表示 (変わったときだけ Status と Level。Status が $null なら変わらない)
function Read-KcLogPortLines($Reader) {
    $out = New-Object 'System.Collections.Generic.List[string]'
    $status = $null
    $level = 0
    if ($null -eq $Reader.Active -and [DateTime]::Now -ge $Reader.NextScan) {
        $Reader.NextScan = [DateTime]::Now.AddSeconds(2)
        $cands = @()
        # Find-KcStudioPort は配列をそのまま返す (return , $x)。パイプラインにつなぐと配列が 1 つの値として届き、
        # ポートが 0 件のとき $_.Port が StrictMode の例外になるので、foreach で回す
        if ($Reader.Port) { $cands = @($Reader.Port) } else { $cands = @(foreach ($p in (Find-KcStudioPort)) { $p.Port }) }
        foreach ($c in $cands) {
            if (-not $Reader.Ports.ContainsKey($c)) {
                try { $Reader.Ports[$c] = Open-KcLogPort $c; $Reader.Buffers[$c] = '' } catch { }
            }
        }
        if ($Reader.Ports.Count -eq 0) {
            $status = 'ログ版のキーボードが見つかりません'
            $level = 2
        } else {
            $status = '{0} を待っています (キーを押してください)' -f (@($Reader.Ports.Keys) -join ', ')
            $level = 3
        }
    }
    foreach ($name in @($Reader.Ports.Keys)) {
        if ($null -ne $Reader.Active -and $name -ne $Reader.ActiveName) { continue }
        $chunk = Read-KcLogPort $Reader.Ports[$name]
        if ($null -eq $chunk) {
            # 抜かれた
            Close-KcLogPort $Reader.Ports[$name]
            $Reader.Ports.Remove($name)
            if ($name -eq $Reader.ActiveName) {
                $Reader.Active = $null
                $Reader.ActiveName = ''
                $status = '{0} が切れました。つなぎ直してください' -f $name
                $level = 2
            }
            continue
        }
        if (-not $chunk) { continue }
        $buf = $Reader.Buffers[$name]
        $lines = Split-KcLogChunk ([ref]$buf) $chunk
        $Reader.Buffers[$name] = $buf
        foreach ($line in $lines) {
            if ($null -eq $Reader.Active) {
                $rec = ConvertFrom-KcZmkLogLine $line
                if ($null -eq $rec -or ($rec.Type -eq 'other' -and $rec.Time -lt 0)) { continue }
                # ログの行が届いたポートを使い、ほかのポートは閉じる
                $Reader.Active = $Reader.Ports[$name]
                $Reader.ActiveName = $name
                foreach ($o in @($Reader.Ports.Keys)) {
                    if ($o -ne $name) { Close-KcLogPort $Reader.Ports[$o]; $Reader.Ports.Remove($o) }
                }
                $status = '{0} ログ受信中' -f $name
                $level = 1
            }
            $out.Add($line)
        }
    }
    return @{ Lines = $out.ToArray(); Status = $status; Level = $level }
}

function Close-KcLogPortReader($Reader) {
    foreach ($p in @($Reader.Ports.Values)) { Close-KcLogPort $p }
    $Reader.Ports.Clear()
    $Reader.Active = $null
    $Reader.ActiveName = ''
}

# 図・レイヤーのチップ・解決の欄・時系列を、いまの状態に合わせる
function Update-KcTraceView($View) {
    $state = $View.State
    $form = $View.Form
    $beh = $View.Expected.interactive.behaviors
    $top = 0
    foreach ($l in $state.Active) { if ($l -gt $top) { $top = $l } }

    # レイヤーのチップ
    $names = @(); $states = @()
    foreach ($l in @($beh.layers)) {
        $i = [int]$l.index
        $names += [string]$l.name
        if ($i -eq $top) { $states += [KcLayerTraceForm]::LayerTop }
        elseif ($state.Active.Contains($i) -or $i -eq 0) { $states += [KcLayerTraceForm]::LayerOn }
        else { $states += [KcLayerTraceForm]::LayerOff }
    }
    $form.SetLayers([string[]]$names, [int[]]$states)

    # 図: 有効な最上位のレイヤーの表示 (押しているキーは、押したときに決まったレイヤーの表示) と、押しているキー
    $lg = Get-KcTraceLegends $state ([int[]]@($View.KeyPositions))
    if ($View.ShownLegends -ne $lg.Signature -and $lg.Legends.Count -gt 0) {
        $form.SetKeyLegends([int[]]@($View.KeyPositions), [string[]]$lg.Legends)
        $View.ShownLegends = $lg.Signature
    }
    if ($View.ShownLayer -ne $top -and $state.Layers.ContainsKey($top)) {
        $View.ShownLayer = $top
        $form.SetPictureCaption(('表示: {0} (いま有効な最上位のレイヤー)' -f (Get-KcTraceLayerName $state $top)))
    }
    $form.ClearKeyStates()
    if ($state.Layers.ContainsKey($top)) {
        foreach ($d in @($state.Layers[$top].danger)) {
            $form.SetKeyState([int]$d, [KcInputTestForm]::StateDanger)
        }
    }
    foreach ($p in @($state.Held.Keys)) {
        $e = Find-KcTracePress $state ([int]$p)
        $st = [KcInputTestForm]::StateCurrent
        if ($null -ne $e -and @($e.Steps | Where-Object { $_ -like '押している間*' -or $_ -like 'ホールドタップ: ホールド*' }).Count -gt 0) {
            $st = [KcInputTestForm]::StateHold
        } elseif ($null -ne $e -and $null -ne $e.Resolved -and $e.Resolved.Src -match '^&kp (L|R)(CTRL|SHIFT|ALT|GUI|EFT_|IGHT_)') {
            $st = [KcInputTestForm]::StateMod
        }
        $form.SetKeyState([int]$p, $st)
    }

    # 時系列 (新しいものを上に。最後の 20 件は、あとから届いたログで書き直す)
    foreach ($e in $state.Events) {
        if ($e.Seq -gt $View.LastSeq) {
            $form.AddTimeline((Format-KcTraceEvent $state $e $View.ScanTable))
            $View.Seqs.Add($e.Seq)
            $View.LastSeq = $e.Seq
        }
    }
    $recent = @($state.Events | Select-Object -Last 20)
    foreach ($e in $recent) {
        $i = $View.Seqs.IndexOf($e.Seq)
        if ($i -ge 0) {
            $form.SetTimelineLine($View.Seqs.Count - 1 - $i, (Format-KcTraceEvent $state $e $View.ScanTable))
        }
    }

    # 解決の欄: 選んだ行、無ければ最後の押下
    $target = $null
    $sel = $form.SelectedIndex
    if ($sel -ge 0 -and $sel -lt $View.Seqs.Count) {
        $seq = $View.Seqs[$View.Seqs.Count - 1 - $sel]
        $target = @($state.Events | Where-Object { $_.Seq -eq $seq }) | Select-Object -First 1
    }
    if ($null -eq $target) {
        for ($i = $state.Events.Count - 1; $i -ge 0; $i--) {
            if ($state.Events[$i].Pressed -and $state.Events[$i].Pos -ge 0) { $target = $state.Events[$i]; break }
        }
    }
    if ($null -eq $target) {
        $form.SetResolve('キーを押すと、ここにレイヤーの解決が出ます', [string[]]@(), [string[]]@(), [int[]]@(), [string[]]@(), [string[]]@(), '')
    } else {
        $verb = '離した'
        if ($target.Pressed) { $verb = '押した' }
        $title = '位置 {0}「{1}」を{2} ({3:F3} 秒)' -f $target.Pos, $target.Key, $verb, ($target.Time / 1000.0)
        $rows = Get-KcTraceCascade $state $target
        $rl = @(); $rt = @(); $rs = @()
        foreach ($r in $rows) {
            $rl += ('{0} ({1})' -f $r.Name, $r.Layer)
            $rt += $r.Text
            switch ($r.State) {
                'on' {
                    if ($r.Text -like '*期待値と違う*') { $rs += [KcLayerTraceForm]::RowMismatch } else { $rs += [KcLayerTraceForm]::RowResolved }
                }
                'trans' { $rs += [KcLayerTraceForm]::RowTrans }
                default { $rs += [KcLayerTraceForm]::RowSkipped }
            }
        }
        $steps = @($target.Steps | ForEach-Object { '・' + $_ })
        $steps += @($target.LayerChanges | ForEach-Object { '・レイヤー: ' + $_ })
        $outs = @($target.Outputs | ForEach-Object { Format-KcStroke $_ $View.ScanTable })
        $form.SetResolve($title, [string[]]$rl, [string[]]$rt, [int[]]$rs, [string[]]$steps, [string[]]$outs, '(送ったキーなし)')
    }

    $level = 0
    $msg = 'ログ {0} 行 / 押下と解放 {1} 件' -f $state.Lines, $View.LastSeq
    if ($state.Dropped -gt 0) {
        $level = 3
        $msg += (' / 欠けたログ {0} 件 (ボールを動かすとログが増えて欠けやすくなります)' -f $state.Dropped)
    }
    if ($View.Paused) {
        $msg = '一時停止中 (' + $msg + ')'
        $level = 3
    }
    $form.SetStatus($msg, $level)
    $state.Changed = $false
}

# 結果を保存する (生のログと時系列)
function Save-KcTrace($View) {
    $dir = Join-Path $View.CacheDir 'trace'
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Force -Path $dir)
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $log = Join-Path $dir ('{0}-{1}.log' -f $stamp, $View.Expected.id)
    $txt = Join-Path $dir ('{0}-{1}.txt' -f $stamp, $View.Expected.id)
    [System.IO.File]::WriteAllText($log, $View.Raw.ToString(), (New-Object System.Text.UTF8Encoding($true)))
    $lines = @($View.State.Events | ForEach-Object {
            $l = Format-KcTraceEvent $View.State $_ $View.ScanTable
            if ($_.Steps.Count -gt 0) { $l += "`r`n" + (@($_.Steps | ForEach-Object { '              ・' + $_ }) -join "`r`n") }
            $l })
    [System.IO.File]::WriteAllText($txt, ($lines -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($true)))
    return $txt
}

# 全体。戻り値: 保存したファイル ($null = 保存なし)
function Invoke-KcLayerTrace {
    param(
        [Parameter(Mandatory = $true)] $Expected,
        [Parameter(Mandatory = $true)] $Common,
        [Parameter(Mandatory = $true)] [string]$CacheDir,
        [string]$Port = ''
    )
    Import-KcInputForm
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
        throw 'ウィンドウは STA で動かす必要があります。powershell.exe (Windows PowerShell) で実行してください'
    }
    $form = New-Object KcLayerTraceForm
    $keys = @($Expected.physical.keys | Where-Object { [bool](Get-KcProp $_ 'present' $true) })
    $form.SetButtonTexts('終了', '一時停止', 'クリア', 'ログを保存')
    $form.SetKeyboardName([string]$Expected.name)
    $form.SetCaptions('レイヤー', '表示: BASE', '送ったキー', '押したキー (新しい順。行を選ぶと上に詳しく出ます)')
    $form.SetKeys([int[]]@($keys | ForEach-Object { [int]$_.pos }), [double[]]@($keys | ForEach-Object { [double]$_.x }),
        [double[]]@($keys | ForEach-Object { [double]$_.y }), [double[]]@($keys | ForEach-Object { [double]$_.w }),
        [double[]]@($keys | ForEach-Object { [double]$_.h }), [string[]]@($keys | ForEach-Object { [string]$_.legend }))
    $artifacts = @(Get-KcProp $Expected.device 'logging_artifacts' @()) -join ' / '
    if (-not $artifacts) { $artifacts = '*_logging.uf2' }
    $form.SetTexts('レイヤーの動きを見る',
        ("キーボードのキーを自由に押すと、そのキーがどのレイヤーで、どう解決されたかが出ます。右手側にログ版のファーム ($artifacts) を書き込み、" +
            'USB でつないでください (tools/flash.cmd で書き込む内容を「右手側 (セントラル) だけ」、右手側の版を「ログ版」にする)。このウィンドウを前面にしておくと、押したキーはどこにも入力されません。' +
            '調べ終わったら通常版に戻してください。'))
    $form.SetPort('COM ポートを探しています', 0)
    $form.Show()
    $form.Activate()
    $form.MaskWinKey($true)
    $consoleMode = [KcConsoleMode]::DisableQuickEdit()
    $view = @{
        Form = $form; Expected = $Expected; ScanTable = (New-KcScanTable $Common); State = (New-KcLayerTrace $Expected)
        KeyPositions = @($keys | ForEach-Object { [int]$_.pos }); ShownLayer = -1; ShownLegends = ''; LastSeq = 0
        Seqs = (New-Object 'System.Collections.Generic.List[int]'); Paused = $false; CacheDir = $CacheDir
        Raw = (New-Object System.Text.StringBuilder)
    }
    $reader = New-KcLogPortReader $Port
    $lastRefresh = [DateTime]::MinValue
    $saved = $null
    try {
        Update-KcTraceView $view
        while ($true) {
            [KcUi]::DoEvents()
            Start-Sleep -Milliseconds 15
            $a = $form.TakeAction()
            if ($a -eq 'stop') { break }
            if ($a -eq 'pause') {
                $view.Paused = -not $view.Paused
                if ($view.Paused) { $form.SetButtonTexts('終了', '再開', 'クリア', 'ログを保存') } else { $form.SetButtonTexts('終了', '一時停止', 'クリア', 'ログを保存') }
                $view.State.Changed = $true
            }
            if ($a -eq 'clear') {
                $view.State = New-KcLayerTrace $Expected
                $view.Seqs.Clear(); $view.LastSeq = 0; $view.ShownLayer = -1; $view.ShownLegends = ''
                [void]$view.Raw.Clear()
                $form.ClearTimeline()
                $form.ClearSelection()
            }
            if ($a -eq 'save') {
                $saved = Save-KcTrace $view
                $form.SetStatus(('保存しました: {0}' -f $saved), 1)
                $lastRefresh = [DateTime]::Now.AddSeconds(2)
            }
            $read = Read-KcLogPortLines $reader
            if ($null -ne $read.Status) { $form.SetPort($read.Status, $read.Level) }
            foreach ($line in $read.Lines) {
                $rec = ConvertFrom-KcZmkLogLine $line
                if ($null -eq $rec) { continue }
                [void]$view.Raw.AppendLine((Remove-KcAnsi $line))
                if (-not $view.Paused) {
                    Update-KcLayerTrace $view.State $rec
                }
            }
            $sel = $form.TakeSelectionChanged()
            if (($view.State.Changed -or $sel) -and [DateTime]::Now -ge $lastRefresh) {
                Update-KcTraceView $view
                $lastRefresh = [DateTime]::Now.AddMilliseconds(80)
            }
        }
    } finally {
        Close-KcLogPortReader $reader
        $form.MaskWinKey($false)
        $form.Close()
        $form.Dispose()
        [KcConsoleMode]::Restore($consoleMode)
        try { $Host.UI.RawUI.FlushInputBuffer() } catch { }
    }
    return $saved
}
