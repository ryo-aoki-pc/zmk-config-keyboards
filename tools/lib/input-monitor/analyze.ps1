# 入力イベントの記録 (CSV / JSON) の読み書きと分析: マウスレポートの間隔と停滞、キーの時系列、AML ビュー、
# ウィンドウに出すライブログ、日本語の報告。Windows の API を使わないので、どの OS でもテストできる。
# input-monitor.ps1 から dot-source して使う。lib/keyboard-check/expected.ps1 (Get-KcProp / Read-KcJson /
# Get-KcUsageLabel)・input-eval.ps1 (ConvertTo-KcKeyActions / $script:KcMouseButtonFlags)・devices.ps1 が
# 先に読み込まれている前提。
#
# 行 (row) は KcInputEvent と同じ列の PSCustomObject で、Time だけが記録開始からの ms (小数あり) になっている:
#   Time、Device (デバイスの番号 #n)、Kind ('key' / 'mouse')、Scan、Prefix、Break、Dx、Dy、Buttons、Wheel、HWheel
# 記録 (recording) は @{ Started; DurationMs; Devices; Connected; Rows; Marks; Paths = @{ Csv; Json } }。
# 配列を返す関数 (return , $x) の結果は、いったん変数に入れてからパイプに通す。

$script:ImCulture = [System.Globalization.CultureInfo]::InvariantCulture
$script:ImCsvHeader = 't_ms,device,label,kind,event,key,scan,prefix,dx,dy,buttons,wheel,hwheel,dt_ms'
$script:ImSchema = 1
# 間隔のヒストグラムの区切り (ms)。最後の区切りは IdleMs
$script:ImBinEdges = @(0, 4, 8, 12, 20, 32, 64)

# ---------------------------------------------------------------------------
# 行
# ---------------------------------------------------------------------------

function New-ImKeyRow([double]$Time, [int]$Scan, [int]$Prefix = 0, [bool]$Break = $false, [int]$Device = 1) {
    return [pscustomobject]@{ Time = $Time; Device = $Device; Kind = 'key'; Scan = $Scan; Prefix = $Prefix; Break = $Break; Dx = 0; Dy = 0; Buttons = 0; Wheel = 0; HWheel = 0 }
}

function New-ImMouseRow([double]$Time, [int]$Dx = 0, [int]$Dy = 0, [int]$Buttons = 0, [int]$Wheel = 0, [int]$HWheel = 0, [int]$Device = 2) {
    return [pscustomobject]@{ Time = $Time; Device = $Device; Kind = 'mouse'; Scan = 0; Prefix = 0; Break = $false; Dx = $Dx; Dy = $Dy; Buttons = $Buttons; Wheel = $Wheel; HWheel = $HWheel }
}

# KcInputEvent (TimeUs 付き) → 行。$OriginMs は記録開始の時刻 (ms)
function ConvertTo-ImRow($Event, [int]$DeviceId, [double]$OriginMs) {
    $t = [math]::Round(([double]$Event.TimeUs) / 1000.0 - $OriginMs, 3)
    return [pscustomobject]@{
        Time = $t; Device = $DeviceId; Kind = [string]$Event.Kind; Scan = [int]$Event.Scan; Prefix = [int]$Event.Prefix; Break = [bool]$Event.Break
        Dx = [int]$Event.Dx; Dy = [int]$Event.Dy; Buttons = [int]$Event.Buttons; Wheel = [int]$Event.Wheel; HWheel = [int]$Event.HWheel
    }
}

# 行の種類: down / up (キー)、button / wheel / motion (マウス。1 行に複数あるときはこの順で優先)
function Get-ImRowEvent($Row) {
    if ($Row.Kind -eq 'key') {
        if ($Row.Break) {
            return 'up'
        }
        return 'down'
    }
    if ($Row.Buttons -ne 0) {
        return 'button'
    }
    if ($Row.Wheel -ne 0 -or $Row.HWheel -ne 0) {
        return 'wheel'
    }
    return 'motion'
}

function Test-ImMotion($Row) {
    return ($Row.Kind -eq 'mouse' -and ($Row.Dx -ne 0 -or $Row.Dy -ne 0))
}

function Test-ImModifier([int]$Usage) {
    return ($Usage -ge 0xE0 -and $Usage -le 0xE7)
}

# スキャンコード → キーの表示名 (表に無ければ 16 進)
function Get-ImKeyLabel([int]$Prefix, [int]$Scan, $ScanTable) {
    $key = '{0}:{1}' -f $Prefix, $Scan
    if ($null -ne $ScanTable -and $ScanTable.ByScan.ContainsKey($key)) {
        return (Get-KcUsageLabel ([int]$ScanTable.ByScan[$key]) $ScanTable)
    }
    if ($Prefix -ne 0) {
        return ('0x{0:X2}:0x{1:X2}' -f $Prefix, $Scan)
    }
    return ('0x{0:X2}' -f $Scan)
}

# ボタンのフラグ → 'ボタン 1 押す' / 'MB1 down' (CSV 用)
function Get-ImButtonText([int]$Buttons, [bool]$Japanese = $true) {
    $parts = @()
    foreach ($b in $script:KcMouseButtonFlags) {
        if ($Buttons -band $b[1]) {
            if ($Japanese) { $parts += ('ボタン {0} 押す' -f $b[0]) } else { $parts += ('MB{0} down' -f $b[0]) }
        }
        if ($Buttons -band $b[2]) {
            if ($Japanese) { $parts += ('ボタン {0} 離す' -f $b[0]) } else { $parts += ('MB{0} up' -f $b[0]) }
        }
    }
    return ($parts -join ' + ')
}

function Get-ImWheelText($Row, [bool]$Japanese = $true) {
    $parts = @()
    if ($Row.Wheel -ne 0) {
        if ($Japanese) { $parts += ('ホイール {0:+#;-#;0}' -f $Row.Wheel) } else { $parts += ('wheel {0:+#;-#;0}' -f $Row.Wheel) }
    }
    if ($Row.HWheel -ne 0) {
        if ($Japanese) { $parts += ('横ホイール {0:+#;-#;0}' -f $Row.HWheel) } else { $parts += ('hwheel {0:+#;-#;0}' -f $Row.HWheel) }
    }
    return ($parts -join ' + ')
}

# CSV の key 列
function Get-ImRowKeyText($Row, $ScanTable) {
    switch (Get-ImRowEvent $Row) {
        'down' { return (Get-ImKeyLabel $Row.Prefix $Row.Scan $ScanTable) }
        'up' { return (Get-ImKeyLabel $Row.Prefix $Row.Scan $ScanTable) }
        'button' { return (Get-ImButtonText $Row.Buttons $false) }
        'wheel' { return (Get-ImWheelText $Row $false) }
    }
    return ''
}

# ---------------------------------------------------------------------------
# 記録ファイル (CSV: イベント、JSON: デバイスの一覧など)
# ---------------------------------------------------------------------------

function Resolve-ImPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return (Join-Path (Get-Location).Path $Path)
}

# UTF-8 (BOM 付き) で保存する (日本語版 Windows の Excel やメモ帳が UTF-8 と認識するため)
function Export-ImTextFile([string]$Path, [string[]]$Lines) {
    $full = Resolve-ImPath $Path
    $dir = Split-Path -Parent $full
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Force -Path $dir)
    }
    [System.IO.File]::WriteAllLines($full, [string[]]@($Lines), (New-Object System.Text.UTF8Encoding($true)))
}

function ConvertTo-ImCsvField([string]$Value) {
    if ($Value -match '[,"\r\n]') {
        return ('"' + $Value.Replace('"', '""') + '"')
    }
    return $Value
}

function Export-ImCsv($Rows, $Devices, [string]$Path, $ScanTable) {
    $labels = @{}
    foreach ($d in @($Devices)) {
        $labels[[int]$d.Id] = ConvertTo-ImCsvField ([string]$d.Label)
    }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add($script:ImCsvHeader)
    $last = @{}
    foreach ($r in @($Rows)) {
        $id = [int]$r.Device
        $t = [double]$r.Time
        $dt = ''
        if ($last.ContainsKey($id)) {
            $dt = ($t - [double]$last[$id]).ToString('F3', $script:ImCulture)
        }
        $last[$id] = $t
        $label = ''
        if ($labels.ContainsKey($id)) {
            $label = $labels[$id]
        }
        $lines.Add(('{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13}' -f $t.ToString('F3', $script:ImCulture), $id, $label, $r.Kind, (Get-ImRowEvent $r),
                (ConvertTo-ImCsvField (Get-ImRowKeyText $r $ScanTable)), $r.Scan, $r.Prefix, $r.Dx, $r.Dy, $r.Buttons, $r.Wheel, $r.HWheel, $dt))
    }
    Export-ImTextFile $Path $lines.ToArray()
}

# CSV の 1 行 → 列 (引用符の中の , と "" を扱う。引用符が無ければ単純に分ける)
function Split-ImCsvLine([string]$Line) {
    if ($Line.IndexOf('"') -lt 0) {
        return , $Line.Split(',')
    }
    $fields = New-Object 'System.Collections.Generic.List[string]'
    $sb = New-Object System.Text.StringBuilder
    $quoted = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($quoted) {
            if ($c -eq '"') {
                if ($i + 1 -lt $Line.Length -and $Line[$i + 1] -eq '"') {
                    [void]$sb.Append('"')
                    $i++
                } else {
                    $quoted = $false
                }
            } else {
                [void]$sb.Append($c)
            }
        } elseif ($c -eq '"') {
            $quoted = $true
        } elseif ($c -eq ',') {
            $fields.Add($sb.ToString())
            [void]$sb.Clear()
        } else {
            [void]$sb.Append($c)
        }
    }
    $fields.Add($sb.ToString())
    return , $fields.ToArray()
}

function Import-ImCsv([string]$Path) {
    $lines = [System.IO.File]::ReadAllLines((Resolve-ImPath $Path), [System.Text.Encoding]::UTF8)
    if ($lines.Length -eq 0 -or -not $lines[0].StartsWith('t_ms,device,')) {
        throw ('入力イベントの CSV ではありません: {0}' -f $Path)
    }
    $rows = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 1; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if (-not $line) {
            continue
        }
        $f = Split-ImCsvLine $line
        if ($f.Count -lt 13) {
            continue
        }
        $rows.Add([pscustomobject]@{
                Time = [double]::Parse($f[0], $script:ImCulture); Device = [int]$f[1]; Kind = [string]$f[3]
                Scan = [int]$f[6]; Prefix = [int]$f[7]; Break = ($f[4] -eq 'up')
                Dx = [int]$f[8]; Dy = [int]$f[9]; Buttons = [int]$f[10]; Wheel = [int]$f[11]; HWheel = [int]$f[12]
            })
    }
    return , $rows.ToArray()
}

# JSON に書くメタ情報。$Fields: @{ Started; DurationMs; Os; Ps; GapMs; IdleMs; Seconds; ShowMotion; EventsFile }
function New-ImMeta([hashtable]$Fields, $Devices, $Connected, $Marks) {
    $devs = @()
    foreach ($d in @($Devices)) { $devs += (ConvertTo-ImDeviceJson $d) }
    $conn = @()
    foreach ($d in @($Connected)) { $conn += (ConvertTo-ImDeviceJson $d) }
    $mk = @()
    foreach ($m in @($Marks)) { $mk += [ordered]@{ n = [int]$m.N; t = [double]$m.T } }
    return [ordered]@{
        schema = $script:ImSchema
        tool = 'input-monitor'
        started = [string](Get-KcProp $Fields 'Started' '')
        duration_ms = [double](Get-KcProp $Fields 'DurationMs' 0)
        host = [ordered]@{ os = [string](Get-KcProp $Fields 'Os' ''); ps = [string](Get-KcProp $Fields 'Ps' '') }
        options = [ordered]@{
            gap_ms = [int](Get-KcProp $Fields 'GapMs' 0); idle_ms = [int](Get-KcProp $Fields 'IdleMs' 0)
            seconds = [int](Get-KcProp $Fields 'Seconds' 0); show_motion = [bool](Get-KcProp $Fields 'ShowMotion' $false)
        }
        events_file = [string](Get-KcProp $Fields 'EventsFile' '')
        devices = $devs
        connected = $conn
        marks = $mk
    }
}

# JSON は BOM 無しで保存する (Read-KcJson で読む)
function Export-ImMeta($Meta, [string]$Path) {
    $full = Resolve-ImPath $Path
    $dir = Split-Path -Parent $full
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Force -Path $dir)
    }
    $json = ConvertTo-Json -InputObject $Meta -Depth 6
    [System.IO.File]::WriteAllText($full, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# 記録ファイル (.csv または .json) を読む。同じ名前の相方 (.json / .csv) も読む
function Read-ImRecording([string]$Path) {
    $full = Resolve-ImPath $Path
    if (-not (Test-Path -LiteralPath $full)) {
        throw ('記録のファイルがありません: {0}' -f $Path)
    }
    $base = Join-Path (Split-Path -Parent $full) ([System.IO.Path]::GetFileNameWithoutExtension($full))
    $csv = $base + '.csv'
    $json = $base + '.json'
    if (-not (Test-Path -LiteralPath $csv)) {
        throw ('イベントの CSV がありません: {0}' -f $csv)
    }
    $rec = @{ Started = ''; DurationMs = 0.0; Devices = @(); Connected = @(); Rows = @(); Marks = @(); Paths = @{ Csv = $csv; Json = $json } }
    if (Test-Path -LiteralPath $json) {
        $meta = Read-KcJson $json
        if ([int](Get-KcProp $meta 'schema' 0) -ne $script:ImSchema) {
            throw ('記録ファイルの形式 (schema) が違います: {0}' -f $json)
        }
        $rec.Started = [string](Get-KcProp $meta 'started' '')
        $rec.DurationMs = [double](Get-KcProp $meta 'duration_ms' 0)
        $devs = @()
        foreach ($d in @(Get-KcProp $meta 'devices' @())) { $devs += (ConvertFrom-ImDeviceJson $d) }
        $rec.Devices = $devs
        $conn = @()
        foreach ($d in @(Get-KcProp $meta 'connected' @())) { $conn += (ConvertFrom-ImDeviceJson $d) }
        $rec.Connected = $conn
        $marks = @()
        foreach ($m in @(Get-KcProp $meta 'marks' @())) { $marks += [pscustomobject]@{ N = [int](Get-KcProp $m 'n' 0); T = [double](Get-KcProp $m 't' 0) } }
        $rec.Marks = $marks
    }
    $rec.Rows = Import-ImCsv $csv
    return $rec
}

# ---------------------------------------------------------------------------
# マウスレポートの間隔と停滞
# ---------------------------------------------------------------------------

function Get-ImMotionTimes($Rows) {
    $t = New-Object 'System.Collections.Generic.List[double]'
    foreach ($r in @($Rows)) {
        if (Test-ImMotion $r) {
            $t.Add([double]$r.Time)
        }
    }
    return , $t.ToArray()
}

# 昇順に並んだ値の百分位 (0〜1)
function Get-ImPercentile([double[]]$Sorted, [double]$P) {
    $n = $Sorted.Length
    if ($n -eq 0) {
        return 0.0
    }
    $idx = [int][math]::Ceiling($P * $n) - 1
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $n) { $idx = $n - 1 }
    return $Sorted[$idx]
}

# 間隔のヒストグラム: [{From; To; Count; Percent}] (From 以上 To 未満。最後だけ IdleMs 以下)
function New-ImBins([double[]]$Deltas, [double]$IdleMs) {
    $edges = @($script:ImBinEdges | Where-Object { $_ -lt $IdleMs }) + @($IdleMs)
    $counts = New-Object int[] ($edges.Count - 1)
    foreach ($d in @($Deltas)) {
        for ($b = $edges.Count - 2; $b -ge 0; $b--) {
            if ($d -ge $edges[$b]) {
                $counts[$b]++
                break
            }
        }
    }
    $total = @($Deltas).Count
    $bins = @()
    for ($b = 0; $b -lt $counts.Length; $b++) {
        $pct = 0.0
        if ($total -gt 0) {
            $pct = 100.0 * $counts[$b] / $total
        }
        $bins += [pscustomobject]@{ From = [double]$edges[$b]; To = [double]$edges[$b + 1]; Count = $counts[$b]; Percent = $pct }
    }
    return , $bins
}

# 移動の時刻の列 → 間隔の統計。IdleMs より長い間隔は「停止 (手を止めた)」として統計から除く
function Get-ImIntervalStats([double[]]$Times, [double]$IdleMs) {
    $n = @($Times).Count
    $stats = [pscustomobject]@{ Count = $n; ActiveCount = 0; Pauses = 0; Median = 0.0; P95 = 0.0; Max = 0.0; ActiveSpanMs = 0.0; Bins = @() }
    $active = New-Object 'System.Collections.Generic.List[double]'
    $span = 0.0
    $pauses = 0
    for ($i = 1; $i -lt $n; $i++) {
        $d = $Times[$i] - $Times[$i - 1]
        if ($d -gt $IdleMs) {
            $pauses++
        } else {
            $active.Add($d)
            $span += $d
        }
    }
    $stats.Pauses = $pauses
    $stats.ActiveCount = $active.Count
    $stats.ActiveSpanMs = $span
    if ($active.Count -gt 0) {
        $sorted = $active.ToArray()
        [Array]::Sort($sorted)
        $stats.Median = Get-ImPercentile $sorted 0.5
        $stats.P95 = Get-ImPercentile $sorted 0.95
        $stats.Max = $sorted[$sorted.Length - 1]
    }
    $stats.Bins = New-ImBins $active.ToArray() $IdleMs
    return $stats
}

# 停滞の検出。GapMs 以上空いた直後に、間隔 BurstMaxMs 以下の移動が BurstMin 件以上続く → 停滞 (溜まったレポートがまとめて届いた)
#   @{ Stalls = [{Start; Resume; GapMs; BurstCount; BurstSpanMs; Dx; Dy; Overflow}]; Hiccups (空きだけで、まとめて届いていない); Pauses (IdleMs 以上の停止) }
#   Overflow: 空きが IdleMs 以上 (ZMK が BLE で溜められる 20 件を超えて、移動量が捨てられた疑い)
function Find-ImStalls($Rows, [double]$GapMs, [double]$IdleMs, [double]$BurstMaxMs, [int]$BurstMin = 3) {
    $motion = @(@($Rows) | Where-Object { Test-ImMotion $_ })
    $stalls = New-Object 'System.Collections.Generic.List[object]'
    $hiccups = 0
    $pauses = 0
    $n = $motion.Count
    $i = 1
    while ($i -lt $n) {
        $gap = [double]$motion[$i].Time - [double]$motion[$i - 1].Time
        if ($gap -lt $GapMs) {
            $i++
            continue
        }
        $j = $i + 1
        while ($j -lt $n -and ([double]$motion[$j].Time - [double]$motion[$j - 1].Time) -le $BurstMaxMs) {
            $j++
        }
        $count = $j - $i
        if ($count -ge $BurstMin) {
            $dx = 0
            $dy = 0
            for ($k = $i; $k -lt $j; $k++) {
                $dx += [int]$motion[$k].Dx
                $dy += [int]$motion[$k].Dy
            }
            $stalls.Add([pscustomobject]@{
                    Start = [double]$motion[$i - 1].Time; Resume = [double]$motion[$i].Time; GapMs = $gap; BurstCount = $count
                    BurstSpanMs = ([double]$motion[$j - 1].Time - [double]$motion[$i].Time); Dx = $dx; Dy = $dy; Overflow = ($gap -ge $IdleMs)
                })
            $i = $j
        } else {
            if ($gap -ge $IdleMs) { $pauses++ } else { $hiccups++ }
            $i++
        }
    }
    return @{ Stalls = $stalls.ToArray(); Hiccups = $hiccups; Pauses = $pauses }
}

# 見立て (PASS / FAIL ではなく目安)
function Get-ImVerdict($Device, $Stats, $StallInfo) {
    if ($Stats.Count -lt 50) {
        return '移動が少ないので判定しません (50 件未満)'
    }
    $stalls = @($StallInfo.Stalls).Count
    $perMin = 0.0
    if ($Stats.ActiveSpanMs -gt 0) {
        $perMin = $stalls * 60000.0 / $Stats.ActiveSpanMs
    }
    $jitter = ($Stats.Median -ge 4 -and $Stats.P95 -gt 2 * $Stats.Median)
    # 停滞が 3 回以上あり、動いていた 1 分あたりでも 3 回以上 (短い記録の 1 回で決めつけない)、または p95 が中央値の 2 倍超
    if (($stalls -ge 3 -and $perMin -ge 3) -or $jitter) {
        if ($Device.Transport -eq 'BLE') {
            return 'BLE の送信が詰まっている可能性があります。README「ZMK キーボードを複数台 BLE で同時接続するとカーソルがカクつく場合」を参照'
        }
        if ($Device.Transport -eq 'USB') {
            return 'USB 接続なので BLE の問題ではありません (PC 側の負荷か、ファームの rate limit の設定)'
        }
        return '間隔が乱れています'
    }
    return '問題は見当たりません (間隔は安定しています)'
}

# ---------------------------------------------------------------------------
# キーの時系列と AML ビュー
# ---------------------------------------------------------------------------

# マウスボタンの押す / 離す → [{Button; Down; Time}]
function Get-ImButtonActions($Rows) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($r in @($Rows)) {
        if ($r.Kind -ne 'mouse' -or $r.Buttons -eq 0) {
            continue
        }
        foreach ($b in $script:KcMouseButtonFlags) {
            if ($r.Buttons -band $b[1]) { $out.Add([pscustomobject]@{ Button = $b[0]; Down = $true; Time = [double]$r.Time }) }
            if ($r.Buttons -band $b[2]) { $out.Add([pscustomobject]@{ Button = $b[0]; Down = $false; Time = [double]$r.Time }) }
        }
    }
    return , $out.ToArray()
}

# キーとボタンの押す / 離すを時刻順に並べ、押下時間・同時に押していたキー・備考 (タップホールドの手がかり) を付ける。
# $ByDevice: @{ デバイス番号 = 行の配列 }。キーの時刻は ConvertTo-KcKeyActions で ms に丸められる (オートリピートもまとめる)
#   [{Time; Device; Label; Usage; Button; Down; DeltaPrevMs; HoldMs; HeldKeys; Note}]
function Get-ImKeyTimeline($ByDevice, $Devices, $ScanTable, [int]$HoldMs = 150) {
    $items = New-Object 'System.Collections.Generic.List[object]'
    $seq = 0
    foreach ($d in @($Devices)) {
        $id = [int]$d.Id
        if (-not $ByDevice.ContainsKey($id)) {
            continue
        }
        $rows = $ByDevice[$id]
        $actions = ConvertTo-KcKeyActions $rows $ScanTable
        foreach ($a in @($actions)) {
            $label = 'スキャンコード ' + $a.Code
            if ($a.Usage -ge 0) {
                $label = Get-KcUsageLabel $a.Usage $ScanTable
            }
            $items.Add([pscustomobject]@{ Time = [double]$a.Time; Seq = $seq; Device = $id; Code = [string]$a.Code; Usage = [int]$a.Usage; Label = $label; Down = [bool]$a.Down; Button = 0 })
            $seq++
        }
        $buttons = Get-ImButtonActions $rows
        foreach ($b in @($buttons)) {
            $items.Add([pscustomobject]@{ Time = [double]$b.Time; Seq = $seq; Device = $id; Code = ('btn:' + $b.Button); Usage = -1; Label = ('ボタン ' + $b.Button); Down = [bool]$b.Down; Button = [int]$b.Button })
            $seq++
        }
    }
    $sorted = @($items | Sort-Object Time, Seq)
    $out = New-Object 'System.Collections.Generic.List[object]'
    $held = @{}
    $prev = $null
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $it = $sorted[$i]
        $delta = $null
        if ($null -ne $prev) {
            $delta = $it.Time - $prev
        }
        $prev = $it.Time
        $key = '{0}|{1}' -f $it.Device, $it.Code
        $note = @()
        $heldText = @()
        $hold = $null
        $isMod = Test-ImModifier $it.Usage
        if ($it.Down) {
            foreach ($k in @($held.Keys)) {
                if ($k -ne $key) {
                    $heldText += ('{0} ({1:F0})' -f $held[$k].Label, ($it.Time - $held[$k].Time))
                    $held[$k].Other = $true
                }
            }
            if ($isMod) {
                # 直前・直後の別のキー (ボタン) の押下と同時 (2 ms 以内) → ホールドの判定で修飾キーが出た (balanced)
                $near = $false
                if ($i -gt 0 -and $sorted[$i - 1].Down -and -not (Test-ImModifier $sorted[$i - 1].Usage) -and ($it.Time - $sorted[$i - 1].Time) -le 2) {
                    $near = $true
                }
                if ($i + 1 -lt $sorted.Count -and $sorted[$i + 1].Down -and -not (Test-ImModifier $sorted[$i + 1].Usage) -and ($sorted[$i + 1].Time - $it.Time) -le 2) {
                    $near = $true
                }
                if ($near) {
                    $note += '他キーと同時に出力 (ホールド判定)'
                }
            }
            $held[$key] = @{ Time = $it.Time; Label = $it.Label; Other = $false }
        } elseif ($held.ContainsKey($key)) {
            $hold = $it.Time - $held[$key].Time
            if ($hold -ge $HoldMs) {
                $note += ('長押し ({0} ms 以上)' -f $HoldMs)
            }
            if ($isMod -and $held[$key].Other) {
                $note += '修飾として使用'
            }
            $held.Remove($key)
        }
        $out.Add([pscustomobject]@{
                Time = $it.Time; Device = $it.Device; Label = $it.Label; Usage = $it.Usage; Button = $it.Button; Down = $it.Down
                DeltaPrevMs = $delta; HoldMs = $hold; HeldKeys = $heldText; Note = ($note -join '、')
            })
    }
    return , $out.ToArray()
}

# 昇順の配列から、$T 以下の最後の値 (無ければ $null)
function Get-ImLastBefore([double[]]$Sorted, [double]$T) {
    $lo = 0
    $hi = $Sorted.Length - 1
    $found = -1
    while ($lo -le $hi) {
        $mid = [int](($lo + $hi) / 2)
        if ($Sorted[$mid] -le $T) {
            $found = $mid
            $lo = $mid + 1
        } else {
            $hi = $mid - 1
        }
    }
    if ($found -lt 0) {
        return $null
    }
    return $Sorted[$found]
}

# AML ビュー: キー / ボタンを押すたびに、同じキーボードのボールの直前の移動から何 ms 後かを出す
#   [{Time; Device; Input; SinceMotionMs; State}]
function Get-ImAmlView($ByDevice, $Devices, $Timeline, [int]$TimeoutMs = 10000) {
    $motionTimes = @{}
    foreach ($d in @($Devices)) {
        $id = [int]$d.Id
        if ($ByDevice.ContainsKey($id)) {
            $t = Get-ImMotionTimes $ByDevice[$id]
            if (@($t).Count -gt 0) {
                $motionTimes[$id] = $t
            }
        }
    }
    if ($motionTimes.Count -eq 0) {
        return , @()
    }
    # デバイス → 組になるマウス (同じ GroupKey → 同じ FamilyKey)
    $pair = @{}
    foreach ($d in @($Devices)) {
        $mouse = $null
        foreach ($m in @($Devices)) {
            if ($motionTimes.ContainsKey([int]$m.Id) -and $m.GroupKey -eq $d.GroupKey) { $mouse = $m; break }
        }
        if ($null -eq $mouse) {
            foreach ($m in @($Devices)) {
                if ($motionTimes.ContainsKey([int]$m.Id) -and $m.FamilyKey -eq $d.FamilyKey) { $mouse = $m; break }
            }
        }
        if ($null -ne $mouse) {
            $pair[[int]$d.Id] = [int]$mouse.Id
        }
    }
    $out = New-Object 'System.Collections.Generic.List[object]'
    $lastMod = @{}
    foreach ($it in @($Timeline)) {
        if (-not $it.Down) {
            continue
        }
        $id = [int]$it.Device
        if (-not $pair.ContainsKey($id)) {
            continue
        }
        $last = Get-ImLastBefore $motionTimes[$pair[$id]] $it.Time
        $since = $null
        if ($null -ne $last) {
            $since = $it.Time - $last
        }
        $isMod = Test-ImModifier $it.Usage
        $state = '-'
        if ($it.Button -gt 0) {
            $state = 'クリック (移動なし)'
            if ($null -ne $since -and $since -lt $TimeoutMs) {
                $state = 'AML 中 (クリック)'
            } elseif ($null -ne $since) {
                $state = 'クリック (移動から {0:F0} 秒超)' -f ($TimeoutMs / 1000.0)
            }
        } elseif ($isMod) {
            $state = '修飾キー (AML が切れる契機)'
        } elseif ($null -ne $since) {
            if ($since -lt $TimeoutMs) {
                $state = '移動から {0:F1} 秒以内に文字' -f ($since / 1000.0)
                if ($lastMod.ContainsKey($id) -and $lastMod[$id] -ge $last) {
                    $state += ' (直前に修飾キー → AML 解除後)'
                }
            } else {
                $state = 'AML 終了後 ({0:F0} 秒超)' -f ($TimeoutMs / 1000.0)
            }
        }
        if ($isMod) {
            $lastMod[$id] = $it.Time
        }
        if ($null -eq $since -and $it.Button -eq 0) {
            continue  # 最初の移動より前のキーは載せない
        }
        $out.Add([pscustomobject]@{ Time = $it.Time; Device = $id; Input = ($it.Label + ' 押す'); SinceMotionMs = $since; State = $state })
    }
    return , $out.ToArray()
}

# ---------------------------------------------------------------------------
# 分析
# ---------------------------------------------------------------------------

function Get-ImCounts($Rows) {
    $c = [pscustomobject]@{ Keys = 0; Motion = 0; Buttons = 0; Wheel = 0; First = $null; Last = $null; Total = @($Rows).Count }
    foreach ($r in @($Rows)) {
        if ($null -eq $c.First) { $c.First = [double]$r.Time }
        $c.Last = [double]$r.Time
        if ($r.Kind -eq 'key') {
            if (-not $r.Break) { $c.Keys++ }
            continue
        }
        if ($r.Dx -ne 0 -or $r.Dy -ne 0) { $c.Motion++ }
        if ($r.Buttons -ne 0) { $c.Buttons++ }
        if ($r.Wheel -ne 0 -or $r.HWheel -ne 0) { $c.Wheel++ }
    }
    return $c
}

# $Options: @{ GapMs; IdleMs; AmlTimeoutMs; HoldMs; ScanTable }
function Invoke-ImAnalysis($Recording, [hashtable]$Options) {
    $gapMs = [double](Get-KcProp $Options 'GapMs' 50)
    $idleMs = [double](Get-KcProp $Options 'IdleMs' 300)
    $amlTimeout = [int](Get-KcProp $Options 'AmlTimeoutMs' 10000)
    $holdMs = [int](Get-KcProp $Options 'HoldMs' 150)
    $scanTable = Get-KcProp $Options 'ScanTable' $null
    $rows = @($Recording.Rows)
    $lists = @{}
    foreach ($r in $rows) {
        $id = [int]$r.Device
        if (-not $lists.ContainsKey($id)) {
            $lists[$id] = New-Object 'System.Collections.Generic.List[object]'
        }
        $lists[$id].Add($r)
    }
    $byDevice = @{}
    foreach ($k in @($lists.Keys)) {
        $byDevice[$k] = $lists[$k].ToArray()
    }
    $devices = @()
    $known = @{}
    foreach ($d in @($Recording.Devices)) {
        $known[[int]$d.Id] = $d
        $devices += $d
    }
    foreach ($k in @($byDevice.Keys | Sort-Object)) {
        if (-not $known.ContainsKey([int]$k)) {
            $devices += (New-ImDevice -Id ([int]$k) -Handle 0 -Kind 'unknown' -Info (ConvertFrom-ImDevicePath '') -Name '')
        }
    }
    $summary = @()
    $intervals = @{}
    $stalls = @{}
    $verdicts = @{}
    $wheel = @{}
    foreach ($d in $devices) {
        $id = [int]$d.Id
        $dr = @()
        if ($byDevice.ContainsKey($id)) {
            $dr = $byDevice[$id]
        }
        $c = Get-ImCounts $dr
        $summary += [pscustomobject]@{ Device = $d; Keys = $c.Keys; Motion = $c.Motion; Buttons = $c.Buttons; Wheel = $c.Wheel; First = $c.First; Last = $c.Last; Total = $c.Total }
        if ($c.Motion -gt 1) {
            $times = Get-ImMotionTimes $dr
            $st = Get-ImIntervalStats $times $idleMs
            # まとめて届いた判定: 中央値の 6 割以下の間隔 (公称 15 ms なら 9 ms 以下。BLE の接続間隔 7.5 ms で続けて届く分を含む)
            $burstMax = [math]::Max(1.0, $st.Median * 0.6)
            $si = Find-ImStalls $dr $gapMs $idleMs $burstMax
            $intervals[$id] = $st
            $stalls[$id] = $si
            $verdicts[$id] = Get-ImVerdict $d $st $si
        }
        if ($c.Wheel -gt 0) {
            $up = 0; $down = 0; $right = 0; $left = 0
            foreach ($r in $dr) {
                if ($r.Wheel -gt 0) { $up++ } elseif ($r.Wheel -lt 0) { $down++ }
                if ($r.HWheel -gt 0) { $right++ } elseif ($r.HWheel -lt 0) { $left++ }
            }
            $wheel[$id] = [pscustomobject]@{ Up = $up; Down = $down; Right = $right; Left = $left }
        }
    }
    $timeline = Get-ImKeyTimeline $byDevice $devices $scanTable $holdMs
    $aml = Get-ImAmlView $byDevice $devices $timeline $amlTimeout
    return @{
        Devices = $devices; Summary = $summary; Intervals = $intervals; Stalls = $stalls; Verdicts = $verdicts
        Timeline = $timeline; Aml = $aml; Wheel = $wheel; Marks = @($Recording.Marks); EventCount = $rows.Count
        Options = @{ GapMs = $gapMs; IdleMs = $idleMs; AmlTimeoutMs = $amlTimeout; HoldMs = $holdMs }
    }
}

# ---------------------------------------------------------------------------
# 報告
# ---------------------------------------------------------------------------

function Format-ImSeconds([double]$Ms) {
    return ('{0:F3}' -f ($Ms / 1000.0))
}

function Format-ImDelta($Value) {
    if ($null -eq $Value) {
        return '-'
    }
    return ('{0:F0}' -f [double]$Value)
}

# 報告の行。$MaxRows: 時系列と AML ビューに載せる最大の行数 (コンソール用。ファイルには全件)
function Format-ImReport($Analysis, $Recording, [int]$Top = 10, [int]$MaxRows = [int]::MaxValue) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $started = [string]$Recording.Started
    if (-not $started) {
        $started = '(日時不明)'
    }
    $lines.Add(('input-monitor {0}   記録 {1:F1} 秒   イベント {2} 件' -f $started, ([double]$Recording.DurationMs / 1000.0), $Analysis.EventCount))
    $csv = [string](Get-KcProp $Recording.Paths 'Csv' '')
    if ($csv) {
        $lines.Add(('記録: {0}' -f $csv))
    }
    $o = $Analysis.Options

    $connected = @($Recording.Connected)
    if ($connected.Count -gt 0) {
        $lines.Add('')
        $lines.Add('==== 接続中のデバイス (起動時) ====')
        foreach ($l in (Format-ImConnectedLines $connected)) {
            $lines.Add('  ' + $l)
        }
    }

    $lines.Add('')
    $lines.Add('==== 記録したデバイス ====')
    $recorded = @($Analysis.Summary | Where-Object { $_.Total -gt 0 })
    if ($recorded.Count -eq 0) {
        $lines.Add('  (記録したイベントがありません)')
    }
    foreach ($s in $recorded) {
        $parts = @()
        if ($s.Keys -gt 0) { $parts += ('キー {0} 件' -f $s.Keys) }
        if ($s.Motion -gt 0) { $parts += ('移動 {0} 件' -f $s.Motion) }
        if ($s.Buttons -gt 0) { $parts += ('ボタン {0} 件' -f $s.Buttons) }
        if ($s.Wheel -gt 0) { $parts += ('ホイール {0} 件' -f $s.Wheel) }
        $lines.Add(('  {0,-44} {1}' -f (Format-ImDeviceLine $s.Device), ($parts -join ' / ')))
    }

    $lines.Add('')
    $lines.Add('==== マウスレポートの間隔 ====')
    $anyMotion = $false
    foreach ($s in $recorded) {
        $id = [int]$s.Device.Id
        if (-not $Analysis.Intervals.ContainsKey($id)) {
            continue
        }
        $anyMotion = $true
        $st = $Analysis.Intervals[$id]
        $si = $Analysis.Stalls[$id]
        $lines.Add(('  #{0} {1}: 移動 {2} 件、動いていた時間 {3:F1} 秒、停止 ({4:F0} ms 超) {5} 回' -f $id, $s.Device.Label, $st.Count, ($st.ActiveSpanMs / 1000.0), $o.IdleMs, $st.Pauses))
        $lines.Add(('     間隔: 中央値 {0:F1} ms / p95 {1:F1} ms / 最大 {2:F1} ms (停止を除く)' -f $st.Median, $st.P95, $st.Max))
        $bins = @()
        foreach ($b in @($st.Bins)) {
            $bins += ('{0:F0}-{1:F0} ms {2:F0}%' -f $b.From, $b.To, $b.Percent)
        }
        $lines.Add('     分布: ' + ($bins -join ' | '))
        $stallList = @($si.Stalls)
        $longest = 0.0
        $overflow = 0
        foreach ($x in $stallList) {
            if ($x.GapMs -gt $longest) { $longest = $x.GapMs }
            if ($x.Overflow) { $overflow++ }
        }
        $lines.Add(('     停滞 → まとめて到着: {0} 回 (最長 {1:F0} ms、{2:F0} ms 超 {3} 回)、途切れ ({4:F0} ms 以上空いたが、まとめて届いていない) {5} 回' -f $stallList.Count, $longest, $o.IdleMs, $overflow, $o.GapMs, $si.Hiccups))
        $shown = @($stallList | Sort-Object -Property @{ Expression = 'GapMs'; Descending = $true } | Select-Object -First $Top)
        foreach ($x in @($shown | Sort-Object Start)) {
            $lines.Add(('        {0,9} 秒  {1:F0} ms 止まったあと {2} 件が {3:F1} ms に集中 (X {4:+#;-#;0} / Y {5:+#;-#;0})' -f (Format-ImSeconds $x.Start), $x.GapMs, $x.BurstCount, $x.BurstSpanMs, $x.Dx, $x.Dy))
        }
        if ($stallList.Count -gt $shown.Count) {
            $lines.Add(('        ほか {0} 回' -f ($stallList.Count - $shown.Count)))
        }
        $lines.Add('     見立て: ' + $Analysis.Verdicts[$id])
    }
    if (-not $anyMotion) {
        $lines.Add('  (移動の記録がありません)')
    }

    $lines.Add('')
    $lines.Add('==== キーの時系列 (タップホールドの手がかり) ====')
    $timeline = @($Analysis.Timeline)
    if ($timeline.Count -eq 0) {
        $lines.Add('  (キー・ボタンの記録がありません)')
    } else {
        $lines.Add(('  (tapping-term 150 ms / quick-tap 0 / balanced。修飾キーが別のキーと同時に出ていれば、ファームがホールドと判定した証拠。押下 {0} ms 以上を長押しと表示)' -f $o.HoldMs))
        $lines.Add('  時刻(秒)    Δ前(ms)  デバイス  キー                 状態  押下(ms)  同時に押していたキー / 備考')
        $count = 0
        foreach ($t in $timeline) {
            if ($count -ge $MaxRows) {
                $lines.Add(('  ほか {0} 件 (.txt に全件)' -f ($timeline.Count - $count)))
                break
            }
            $count++
            $state = '離す'
            if ($t.Down) { $state = '押す' }
            $extra = @()
            if (@($t.HeldKeys).Count -gt 0) { $extra += (@($t.HeldKeys) -join ', ') }
            if ($t.Note) { $extra += $t.Note }
            $lines.Add(('  {0,9}  {1,8}  #{2,-7} {3,-20} {4}  {5,8}  {6}' -f (Format-ImSeconds $t.Time), (Format-ImDelta $t.DeltaPrevMs), $t.Device, $t.Label, $state, (Format-ImDelta $t.HoldMs), ($extra -join ' / ')))
        }
    }

    $lines.Add('')
    $lines.Add('==== AML (オートマウスレイヤー) ====')
    $aml = @($Analysis.Aml)
    if ($aml.Count -eq 0) {
        $lines.Add('  (ボールの移動のあとのキー・ボタンの記録がありません)')
    } else {
        $lines.Add(('  (ボールを転がすと AML になり、{0:F0} 秒触らないと切れる。修飾キーの位置を押しても切れる)' -f ($o.AmlTimeoutMs / 1000.0)))
        $lines.Add('  時刻(秒)    デバイス  入力                   直前の移動からの経過(ms)  見立て')
        $count = 0
        foreach ($a in $aml) {
            if ($count -ge $MaxRows) {
                $lines.Add(('  ほか {0} 件 (.txt に全件)' -f ($aml.Count - $count)))
                break
            }
            $count++
            $lines.Add(('  {0,9}  #{1,-7} {2,-22} {3,24}  {4}' -f (Format-ImSeconds $a.Time), $a.Device, $a.Input, (Format-ImDelta $a.SinceMotionMs), $a.State))
        }
    }

    if ($Analysis.Wheel.Count -gt 0) {
        $lines.Add('')
        $lines.Add('==== ホイール ====')
        foreach ($s in $recorded) {
            $id = [int]$s.Device.Id
            if ($Analysis.Wheel.ContainsKey($id)) {
                $w = $Analysis.Wheel[$id]
                $lines.Add(('  #{0} {1}: 上 {2} / 下 {3} / 右 {4} / 左 {5}' -f $id, $s.Device.Label, $w.Up, $w.Down, $w.Right, $w.Left))
            }
        }
    }

    $marks = @($Analysis.Marks)
    if ($marks.Count -gt 0) {
        $lines.Add('')
        $lines.Add('==== マーク ====')
        foreach ($m in $marks) {
            $lines.Add(('  {0}: {1} 秒' -f $m.N, (Format-ImSeconds $m.T)))
        }
    }
    return , $lines.ToArray()
}

function Write-ImReport([string[]]$Lines) {
    foreach ($l in @($Lines)) {
        if ($l -like '*見立て:*') {
            Write-Host $l -ForegroundColor Yellow
        } elseif ($l.StartsWith('====')) {
            Write-Host $l -ForegroundColor Cyan
        } else {
            Write-Host $l
        }
    }
}

# ---------------------------------------------------------------------------
# ライブログ (記録中にウィンドウへ出す行)
# ---------------------------------------------------------------------------

function New-ImLiveLog([bool]$ShowMotion, [double]$IdleMs, $ScanTable) {
    return @{ ShowMotion = $ShowMotion; IdleMs = $IdleMs; ScanTable = $ScanTable; Open = @{}; LastKeyTime = $null; Held = @{} }
}

function Format-ImLogLine([double]$Time, $Device, [string]$Text) {
    $name = '#?'
    if ($null -ne $Device) {
        $name = '#{0} {1}' -f $Device.Id, $Device.Label
    }
    return ('{0,9:F3}  {1,-26}  {2}' -f ($Time / 1000.0), $name, $Text)
}

function Format-ImMotionSummary($Seg, $Device) {
    $median = 0.0
    if ($Seg.Deltas.Count -gt 0) {
        $s = $Seg.Deltas.ToArray()
        [Array]::Sort($s)
        $median = Get-ImPercentile $s 0.5
    }
    return (Format-ImLogLine $Seg.Start $Device ('ボール {0:F1} 秒  {1} 件  X {2:+#;-#;0} / Y {3:+#;-#;0}  間隔 中央 {4:F1} ms / 最大 {5:F1} ms' -f (($Seg.Last - $Seg.Start) / 1000.0), $Seg.Count, $Seg.Dx, $Seg.Dy, $median, $Seg.MaxGap))
}

# 1 行の記録 → ウィンドウに出す行 (0 行以上)。$Devices: @{ 番号 = デバイス }
function Add-ImLiveEvent($State, $Row, $Devices) {
    $lines = @()
    $id = [int]$Row.Device
    $dev = $null
    if ($Devices.ContainsKey($id)) {
        $dev = $Devices[$id]
    }
    $t = [double]$Row.Time
    if (Test-ImMotion $Row) {
        if ($State.ShowMotion) {
            $dt = ''
            if ($State.Open.ContainsKey($id)) {
                $dt = ' (Δ {0:F1} ms)' -f ($t - $State.Open[$id].Last)
            }
            $lines += (Format-ImLogLine $t $dev ('X {0:+#;-#;0} / Y {1:+#;-#;0}{2}' -f $Row.Dx, $Row.Dy, $dt))
            $State.Open[$id] = @{ Last = $t }
        } else {
            if ($State.Open.ContainsKey($id) -and ($t - $State.Open[$id].Last) -gt $State.IdleMs) {
                $lines += (Format-ImMotionSummary $State.Open[$id] $dev)
                $State.Open.Remove($id)
            }
            if (-not $State.Open.ContainsKey($id)) {
                $State.Open[$id] = @{ Start = $t; Last = $t; Count = 0; Dx = 0; Dy = 0; MaxGap = 0.0; Deltas = (New-Object 'System.Collections.Generic.List[double]') }
            } else {
                $gap = $t - $State.Open[$id].Last
                $State.Open[$id].Deltas.Add($gap)
                if ($gap -gt $State.Open[$id].MaxGap) {
                    $State.Open[$id].MaxGap = $gap
                }
            }
            $seg = $State.Open[$id]
            $seg.Last = $t
            $seg.Count++
            $seg.Dx += [int]$Row.Dx
            $seg.Dy += [int]$Row.Dy
        }
    }
    $event = Get-ImRowEvent $Row
    if ($event -eq 'down' -or $event -eq 'up') {
        $label = Get-ImKeyLabel $Row.Prefix $Row.Scan $State.ScanTable
        $code = '{0}|{1}:{2}' -f $id, $Row.Prefix, $Row.Scan
        if ($event -eq 'down') {
            if ($State.Held.ContainsKey($code)) {
                return , $lines  # オートリピート
            }
            $dt = ''
            if ($null -ne $State.LastKeyTime) {
                $dt = ' (+{0:F0} ms)' -f ($t - $State.LastKeyTime)
            }
            $State.Held[$code] = $t
            $lines += (Format-ImLogLine $t $dev ('{0} 押す{1}' -f $label, $dt))
        } else {
            $hold = ''
            if ($State.Held.ContainsKey($code)) {
                $hold = ' (押下 {0:F0} ms)' -f ($t - $State.Held[$code])
                $State.Held.Remove($code)
            }
            $lines += (Format-ImLogLine $t $dev ('{0} 離す{1}' -f $label, $hold))
        }
        $State.LastKeyTime = $t
    } elseif ($event -eq 'button') {
        $dt = ''
        if ($null -ne $State.LastKeyTime) {
            $dt = ' (+{0:F0} ms)' -f ($t - $State.LastKeyTime)
        }
        $lines += (Format-ImLogLine $t $dev ((Get-ImButtonText $Row.Buttons $true) + $dt))
        $State.LastKeyTime = $t
    } elseif ($event -eq 'wheel') {
        $lines += (Format-ImLogLine $t $dev (Get-ImWheelText $Row $true))
    }
    return , $lines
}

# IdleMs 以上更新の無い移動の区間を閉じて、まとめの行を返す ($Force ならすべて閉じる)
function Complete-ImLiveLog($State, [double]$NowMs, $Devices, [bool]$Force) {
    $lines = @()
    if ($State.ShowMotion) {
        return , $lines
    }
    foreach ($id in @($State.Open.Keys)) {
        $seg = $State.Open[$id]
        if ($Force -or ($NowMs - $seg.Last) -gt $State.IdleMs) {
            $dev = $null
            if ($Devices.ContainsKey($id)) {
                $dev = $Devices[$id]
            }
            $lines += (Format-ImMotionSummary $seg $dev)
            $State.Open.Remove($id)
        }
    }
    return , $lines
}
