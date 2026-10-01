# 検査結果の記録・表示・保存。keyboard-check.ps1 から dot-source して使う。
#
# 結果は 1 項目ずつ New-KcResult で作り、List に入れていく。
#   Status: PASS (意図どおり) / FAIL (意図と違う) / WARN (確認が必要) / SKIP (検査できなかった) / INFO (参考)

$script:KcStatusColors = @{
    PASS = 'Green'; FAIL = 'Red'; WARN = 'Yellow'; SKIP = 'DarkGray'; INFO = 'Gray'
}
$script:KcMaxDetails = 20

function New-KcResultList {
    return , (New-Object 'System.Collections.Generic.List[object]')
}

function Add-KcResult {
    param(
        [Parameter(Mandatory = $true)] $Results,
        [Parameter(Mandatory = $true)] [string]$Category,
        [Parameter(Mandatory = $true)] [string]$Item,
        [Parameter(Mandatory = $true)] [ValidateSet('PASS', 'FAIL', 'WARN', 'SKIP', 'INFO')] [string]$Status,
        [string]$Expected = '',
        [string]$Actual = '',
        [string]$Hint = '',
        [string[]]$Details = @(),
        # 参考の項目 (設定ファイルどうしの整合など)。「何も検査できなかった」の判定に数えない
        [switch]$Reference
    )
    $r = [pscustomobject]@{
        Category = $Category
        Item     = $Item
        Status   = $Status
        Expected = $Expected
        Actual   = $Actual
        Hint     = $Hint
        Details  = @($Details)
        Reference = [bool]$Reference
    }
    $Results.Add($r)
    return $r
}

# 一覧の 1 行目 (状態・項目・期待値と実際の値) と、続く詳細の行
function Format-KcResultLines($Result) {
    $lines = @()
    $line = '[{0}] {1}: {2}' -f $Result.Status, $Result.Category, $Result.Item
    if ($Result.Actual -and $Result.Expected -and $Result.Actual -ne $Result.Expected) {
        $line += ' (期待: {0} / 実際: {1})' -f $Result.Expected, $Result.Actual
    } elseif ($Result.Actual) {
        $line += ' ({0})' -f $Result.Actual
    } elseif ($Result.Expected) {
        $line += ' ({0})' -f $Result.Expected
    }
    $lines += $line
    $details = @($Result.Details)
    $shown = $details
    if ($details.Count -gt $script:KcMaxDetails) {
        $shown = $details[0..($script:KcMaxDetails - 1)]
    }
    foreach ($d in $shown) {
        $lines += ('    - ' + $d)
    }
    if ($details.Count -gt $script:KcMaxDetails) {
        $lines += ('    - ほか {0} 件 (-Report で全件を書き出せます)' -f ($details.Count - $script:KcMaxDetails))
    }
    if ($Result.Hint) {
        foreach ($h in ($Result.Hint -split "`n")) {
            $lines += ('    → ' + $h)
        }
    }
    return , $lines
}

function Write-KcResult($Result) {
    $color = $script:KcStatusColors[$Result.Status]
    $lines = Format-KcResultLines $Result
    Write-Host $lines[0] -ForegroundColor $color
    for ($i = 1; $i -lt $lines.Count; $i++) {
        Write-Host $lines[$i]
    }
}

function Get-KcStatusCounts($Results) {
    $counts = [ordered]@{ PASS = 0; FAIL = 0; WARN = 0; SKIP = 0; INFO = 0 }
    foreach ($r in $Results) {
        $counts[$r.Status]++
    }
    return $counts
}

# 結果の一覧と集計を表示する
function Write-KcSummary($Results, [string]$Title = '検査結果') {
    Write-Host ''
    Write-Host ('==== {0} ====' -f $Title)
    foreach ($r in $Results) {
        Write-KcResult $r
    }
    $c = Get-KcStatusCounts $Results
    Write-Host ''
    $text = 'PASS {0} / FAIL {1} / WARN {2} / SKIP {3}' -f $c.PASS, $c.FAIL, $c.WARN, $c.SKIP
    $code = Get-KcExitCode $Results
    if ($code -eq 1) {
        Write-Host ('判定: 意図と違う設定があります。' + $text) -ForegroundColor Red
    } elseif ($code -eq 2) {
        Write-Host ('判定: 検査できた項目がありません (SKIP の案内を見てください)。' + $text) -ForegroundColor Yellow
    } elseif ($c.WARN -gt 0) {
        Write-Host ('判定: 意図と違う設定は見つかりませんでした (確認が必要な項目があります)。' + $text) -ForegroundColor Yellow
    } else {
        Write-Host ('判定: 意図どおりです。' + $text) -ForegroundColor Green
    }
}

# 終了コード: 0 = FAIL なし、1 = FAIL あり、2 = 何も検査できなかった (参考の項目は数えない)
function Get-KcExitCode($Results) {
    $c = Get-KcStatusCounts $Results
    if ($c.FAIL -gt 0) {
        return 1
    }
    $checked = @($Results | Where-Object { -not $_.Reference -and ($_.Status -eq 'PASS' -or $_.Status -eq 'WARN') })
    if ($checked.Count -eq 0) {
        return 2
    }
    return 0
}

# 結果をテキストに書き出す (詳細は省略しない)。UTF-8 (BOM 付き) で保存する
function Export-KcReport($Results, [string]$Path, [string[]]$Header = @()) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Force -Path $dir)
    }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($h in $Header) {
        $lines.Add($h)
    }
    $lines.Add('')
    $saved = $script:KcMaxDetails
    $script:KcMaxDetails = [int]::MaxValue
    try {
        foreach ($r in $Results) {
            foreach ($l in (Format-KcResultLines $r)) {
                $lines.Add($l)
            }
        }
    } finally {
        $script:KcMaxDetails = $saved
    }
    $c = Get-KcStatusCounts $Results
    $lines.Add('')
    $lines.Add(('PASS {0} / FAIL {1} / WARN {2} / SKIP {3} / INFO {4}' -f $c.PASS, $c.FAIL, $c.WARN, $c.SKIP, $c.INFO))
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($Path, $lines.ToArray(), $encoding)
}
