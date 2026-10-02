<#
.SYNOPSIS
    キーボード・マウスから PC に届いた入力 (キー、ボールの移動、クリック、ホイール) をデバイスごとにタイムスタンプ付きで記録し、タイミングを調べます。

.DESCRIPTION
    ファームウェアの動作をホスト側から観察するためのツールです。Raw Input で、つないでいるすべてのキーボード・マウスの
    イベントを µs 精度の時刻付きで記録し (ウィンドウを開いている間は、別のアプリに入力していても記録されます)、
    停止したあとに次の 3 つを分析して報告します。キーボードの設定は読まず、書き換えもしません。

      - キーの時系列: 押した・離した時刻、押下時間、同時に押していたキー (タップホールドでどのキーがいつ出たかの手がかり)
      - AML (オートマウスレイヤー): キーやクリックが、直前のボールの移動から何 ms 後だったか (10 秒のタイムアウト、修飾キーでの解除)
      - マウスレポートの間隔: 中央値・p95・分布と、「停滞 → まとめて到着」の検出 (BLE で複数台をつないだときのカクつき)

    記録は tools/.cache/input-monitor/<日時>.csv (イベント) と .json (デバイスの一覧など)、報告は .txt に保存します。
    記録は Windows でのみできます。-Analyze での分析は Windows 以外でもできます。

.PARAMETER Seconds
    記録する秒数。省略 (0) すると、ウィンドウの「停止」を押すか閉じるまで記録します。

.PARAMETER Analyze
    記録ファイル (.csv または .json) を指定すると、記録せずにその分析だけを行います。

.PARAMETER OutDir
    記録と報告の保存先。省略すると tools/.cache/input-monitor/ です。

.PARAMETER Report
    報告 (.txt) の保存先。省略すると、記録と同じ場所に同じ名前で保存します。

.PARAMETER ShowMotion
    ウィンドウのログに、ボールの移動を 1 件ずつ表示します (省略すると、連続した移動をまとめて 1 行にします)。

.PARAMETER GapMs
    マウスレポートの間隔がこれ以上空いたら「停滞」の候補にします (既定 50 ms。各機種の公称 15〜16 ms の 3 倍強)。

.PARAMETER IdleMs
    これ以上空いたら「手を止めた」とみなします (既定 300 ms。ZMK が BLE で溜められる 20 件 × 15 ms)。

.PARAMETER Top
    報告に載せる停滞の件数 (既定 10)。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\input-monitor.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\input-monitor.ps1 -Seconds 60 -ShowMotion

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\input-monitor.ps1 -Analyze tools\.cache\input-monitor\20261002-123456.csv
#>
[CmdletBinding()]
param(
    [ValidateRange(0, 86400)]
    [int]$Seconds = 0,

    [string]$Analyze,

    [string]$OutDir,

    [string]$Report,

    [switch]$ShowMotion,

    [ValidateRange(1, 100000)]
    [int]$GapMs = 50,

    [ValidateRange(1, 100000)]
    [int]$IdleMs = 300,

    [ValidateRange(0, 1000)]
    [int]$Top = 10
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$kcLib = Join-Path $PSScriptRoot 'lib\keyboard-check'
$imLib = Join-Path $PSScriptRoot 'lib\input-monitor'
. (Join-Path $kcLib 'expected.ps1')
. (Join-Path $kcLib 'rawhid.ps1')
. (Join-Path $kcLib 'input-eval.ps1')
. (Join-Path $kcLib 'input-test.ps1')
. (Join-Path $imLib 'devices.ps1')
. (Join-Path $imLib 'analyze.ps1')

$isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
if (-not $OutDir) {
    $OutDir = Join-Path $PSScriptRoot '.cache\input-monitor'
}
$scanTable = New-KcScanTable (Get-KcExpected 'common' (Join-Path $PSScriptRoot 'expected'))
$options = @{ GapMs = $GapMs; IdleMs = $IdleMs; AmlTimeoutMs = 10000; HoldMs = 150; ScanTable = $scanTable }
$consoleRows = 60

function Stop-WithError([string]$Message) {
    Write-Host ''
    Write-Host "失敗: $Message" -ForegroundColor Red
    exit 1
}

# 分析して、コンソールに表示し、.txt に保存する。終了コードを返す
function Invoke-ImReport($Recording, [string]$ReportPath) {
    if (@($Recording.Rows).Count -eq 0) {
        Write-Host '記録にイベントがありません。' -ForegroundColor Yellow
        return 2
    }
    $analysis = Invoke-ImAnalysis $Recording $options
    Write-Host ''
    Write-ImReport (Format-ImReport $analysis $Recording $Top $consoleRows)
    Write-Host ''
    try {
        Export-ImTextFile $ReportPath (Format-ImReport $analysis $Recording $Top)
        Write-Host ('報告を保存しました: {0}' -f $ReportPath)
    } catch {
        Write-Host ('報告を保存できませんでした: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
    }
    return 0
}

# ---------------------------------------------------------------------------
# 記録ファイルの分析だけ
# ---------------------------------------------------------------------------

if ($Analyze) {
    $recording = $null
    try {
        $recording = Read-ImRecording $Analyze
    } catch {
        Stop-WithError $_.Exception.Message
    }
    Write-Host ('記録を読みました: {0} ({1} 件)' -f $recording.Paths.Csv, @($recording.Rows).Count)
    if (-not $Report) {
        $Report = [System.IO.Path]::ChangeExtension($recording.Paths.Csv, '.txt')
    }
    exit (Invoke-ImReport $recording $Report)
}

# ---------------------------------------------------------------------------
# 記録
# ---------------------------------------------------------------------------

if (-not $isWindowsHost) {
    Stop-WithError '記録は Windows でのみできます (-Analyze で記録ファイルの分析はできます)'
}
try {
    Import-KcInputForm
    Import-KcCSharp 'RawHid.cs' 'KcRawHid'
} catch {
    Stop-WithError ('C# のヘルパーを読み込めません: ' + $_.Exception.Message)
}

# 接続中のデバイス (番号 1〜)。記録中に初めて見るデバイスは、その続きの番号にする
$byHandle = @{}
$byId = @{}
# (配列を返す関数の結果は、いったん変数に受けてから @() で包む。直接 @(関数) と書くと 1 要素になる)
$connected = @()
try {
    $connected = Get-ImConnectedDevices
    $connected = @($connected)
} catch {
    Write-Host ('接続中のデバイスを列挙できませんでした: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
}
foreach ($d in $connected) {
    $byHandle[[long]$d.Handle] = $d
    $byId[[int]$d.Id] = $d
}
$nextId = $connected.Count + 1
$connectedLines = Format-ImConnectedLines $connected
$connectedLines = @($connectedLines)

Write-Host '接続中のキーボード・マウス:'
foreach ($l in $connectedLines) {
    Write-Host ('  ' + $l)
}
Write-Host ''
Write-Host '記録用のウィンドウを開きます。ウィンドウを開いている間はコンソールに触らないでください。'
if ($Seconds -gt 0) {
    Write-Host ('{0} 秒たつか、「停止」を押すか、ウィンドウを閉じると記録を終えて分析します。' -f $Seconds)
} else {
    Write-Host '「停止」を押すか、ウィンドウを閉じると記録を終えて分析します。'
}

$hint = '別のアプリ (メモ帳など) にキーを入力したり、ボールを転がしたりしてください。このウィンドウが前面のときはキーを飲み込みます (Ctrl+C でログをコピーできます)。' +
    "`r`n" + '停止: 記録を終えて分析する / マーク: ログに区切りを入れる / クリア: ここまでの記録を捨てる'
$rows = New-Object 'System.Collections.Generic.List[object]'
$marks = New-Object 'System.Collections.Generic.List[object]'
$counts = @{}
$live = New-ImLiveLog ([bool]$ShowMotion) $IdleMs $scanTable
$started = Get-Date
$origin = 0.0
$duration = 0.0
$failure = ''
$consoleMode = [KcConsoleMode]::DisableQuickEdit()
$form = $null
try {
    $form = [KcInputMonitorForm]::Launch('input-monitor', '停止', 'マーク', 'クリア', $hint)
    $form.AppendLog(('接続中のキーボード・マウス:' + "`r`n  " + ($connectedLines -join "`r`n  ") + "`r`n"))
    $origin = $form.NowUs / 1000.0
    $lastStatus = -1000.0
    while (-not $form.IsClosed) {
        Start-Sleep -Milliseconds 100
        $lines = New-Object 'System.Collections.Generic.List[string]'
        foreach ($e in $form.TakeEvents()) {
            $h = [long]$e.Device
            if (-not $byHandle.ContainsKey($h)) {
                $d = $null
                try {
                    $d = Resolve-ImDevice $h ([string]$e.Kind) $nextId
                } catch {
                    $d = New-ImDevice -Id $nextId -Handle $h -Kind ([string]$e.Kind) -Info (ConvertFrom-ImDevicePath '') -Name ''
                }
                $nextId++
                $byHandle[$h] = $d
                $byId[[int]$d.Id] = $d
                $lines.Add('---- 新しいデバイス: ' + (Format-ImDeviceLine $d))
            }
            $dev = $byHandle[$h]
            $row = ConvertTo-ImRow $e ([int]$dev.Id) $origin
            $rows.Add($row)
            if (-not $counts.ContainsKey([int]$dev.Id)) {
                $counts[[int]$dev.Id] = 0
            }
            $counts[[int]$dev.Id]++
            foreach ($l in (Add-ImLiveEvent $live $row $byId)) {
                $lines.Add($l)
            }
        }
        $now = $form.NowUs / 1000.0 - $origin
        foreach ($l in (Complete-ImLiveLog $live $now $byId $false)) {
            $lines.Add($l)
        }
        if ($lines.Count -gt 0) {
            $form.AppendLog(($lines.ToArray() -join "`r`n"))
        }
        $action = $form.TakeAction()
        if ($action -eq 'stop') {
            break
        } elseif ($action -eq 'mark') {
            $marks.Add([pscustomobject]@{ N = $marks.Count + 1; T = $now })
            $form.AppendLog(('---- マーク {0} ({1} 秒) ----' -f $marks.Count, (Format-ImSeconds $now)))
        } elseif ($action -eq 'clear') {
            $rows.Clear()
            $marks.Clear()
            $counts = @{}
            $live = New-ImLiveLog ([bool]$ShowMotion) $IdleMs $scanTable
            $origin = $form.NowUs / 1000.0
            $started = Get-Date
            $now = 0.0
            $form.ClearLog()
        }
        if (($now - $lastStatus) -ge 500) {
            $lastStatus = $now
            $parts = @()
            foreach ($id in @($counts.Keys | Sort-Object)) {
                $parts += ('#{0} {1}' -f $id, $counts[$id])
            }
            $form.SetStatus(('経過 {0:F1} 秒   イベント {1} 件   {2}' -f ($now / 1000.0), $rows.Count, ($parts -join '  ')), 0)
        }
        if ($Seconds -gt 0 -and $now -ge $Seconds * 1000.0) {
            break
        }
    }
    $duration = $form.NowUs / 1000.0 - $origin
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($null -ne $form) {
        $form.RequestClose()
        [void]$form.WaitClosed(2000)
    }
    [KcConsoleMode]::Restore($consoleMode)
    try {
        $Host.UI.RawUI.FlushInputBuffer()
    } catch {
        # コンソールが無いときは何もしない
    }
}
if ($failure) {
    Stop-WithError $failure
}
if ($rows.Count -eq 0) {
    Write-Host '記録したイベントがありません。' -ForegroundColor Yellow
    exit 2
}

# ---------------------------------------------------------------------------
# 保存と分析
# ---------------------------------------------------------------------------

$stamp = $started.ToString('yyyyMMdd-HHmmss')
$csvPath = Join-Path $OutDir ($stamp + '.csv')
$jsonPath = Join-Path $OutDir ($stamp + '.json')
if (-not $Report) {
    $Report = Join-Path $OutDir ($stamp + '.txt')
}
$allDevices = @($byId.Values | Sort-Object Id)
try {
    Export-ImCsv $rows.ToArray() $allDevices $csvPath $scanTable
    $meta = New-ImMeta @{
        Started = $started.ToString('yyyy-MM-dd HH:mm:ss'); DurationMs = $duration
        Os = [System.Environment]::OSVersion.VersionString; Ps = $PSVersionTable.PSVersion.ToString()
        GapMs = $GapMs; IdleMs = $IdleMs; Seconds = $Seconds; ShowMotion = [bool]$ShowMotion; EventsFile = (Split-Path -Leaf $csvPath)
    } $allDevices $connected $marks.ToArray()
    Export-ImMeta $meta $jsonPath
    Write-Host ('記録を保存しました: {0} ({1} 件)' -f $csvPath, $rows.Count)
} catch {
    Write-Host ('記録を保存できませんでした: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
}
$recording = @{
    Started = $started.ToString('yyyy-MM-dd HH:mm:ss'); DurationMs = $duration; Devices = $allDevices; Connected = $connected
    Rows = $rows.ToArray(); Marks = $marks.ToArray(); Paths = @{ Csv = $csvPath; Json = $jsonPath }
}
exit (Invoke-ImReport $recording $Report)
