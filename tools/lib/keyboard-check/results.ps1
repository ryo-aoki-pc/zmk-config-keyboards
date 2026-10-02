# 検査結果の記録・表示・保存。keyboard-check.ps1 から dot-source して使う。
#
# 結果は 1 項目ずつ New-KcResult で作り、List に入れていく。
#   Status: PASS (意図どおり) / FAIL (意図と違う) / WARN (確認が必要) / SKIP (検査できなかった) / INFO (参考)

# コンソールの表示: 判定のバッジの色 (Write-Host に渡す)。PS 5.1 のコンソールで別の色に置き換えられる
# DarkYellow / DarkMagenta は使わない
$script:KcBadgeColors = @{
    PASS = @{ ForegroundColor = 'Black'; BackgroundColor = 'Green' }
    FAIL = @{ ForegroundColor = 'White'; BackgroundColor = 'DarkRed' }
    WARN = @{ ForegroundColor = 'Black'; BackgroundColor = 'Yellow' }
    SKIP = @{ ForegroundColor = 'Black'; BackgroundColor = 'DarkGray' }
    INFO = @{ ForegroundColor = 'Black'; BackgroundColor = 'Gray' }
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

# 1 行目の末尾に付ける、期待値と実際の値
function Format-KcResultValue($Result) {
    if ($Result.Actual -and $Result.Expected -and $Result.Actual -ne $Result.Expected) {
        return (' (期待: {0} / 実際: {1})' -f $Result.Expected, $Result.Actual)
    } elseif ($Result.Actual) {
        return (' ({0})' -f $Result.Actual)
    } elseif ($Result.Expected) {
        return (' ({0})' -f $Result.Expected)
    }
    return ''
}

# 詳細の行 (多いときは $script:KcMaxDetails 件まで)。字下げは付けない
function Get-KcResultDetailLines($Result) {
    $lines = @()
    $details = @($Result.Details)
    $shown = $details
    if ($details.Count -gt $script:KcMaxDetails) {
        $shown = $details[0..($script:KcMaxDetails - 1)]
    }
    foreach ($d in $shown) {
        $lines += ('- ' + $d)
    }
    if ($details.Count -gt $script:KcMaxDetails) {
        $lines += ('- ほか {0} 件 (-Report で全件を書き出せます)' -f ($details.Count - $script:KcMaxDetails))
    }
    return , $lines
}

# ヒントの行。字下げは付けない
function Get-KcResultHintLines($Result) {
    $lines = @()
    if ($Result.Hint) {
        foreach ($h in ($Result.Hint -split "`n")) {
            $lines += ('→ ' + $h)
        }
    }
    return , $lines
}

# 一覧の 1 行目 (状態・項目・期待値と実際の値) と、続く詳細の行 (レポートの書式)
function Format-KcResultLines($Result) {
    $lines = @()
    $lines += ('[{0}] {1}: {2}' -f $Result.Status, $Result.Category, $Result.Item) + (Format-KcResultValue $Result)
    foreach ($d in (Get-KcResultDetailLines $Result)) {
        $lines += ('    ' + $d)
    }
    foreach ($h in (Get-KcResultHintLines $Result)) {
        $lines += ('    ' + $h)
    }
    return , $lines
}

# 判定のバッジ (Status 名で色を選ぶ) を、前後に余白を付けて書く。続けて書く文字は既定の色になる
function Write-KcBadge([string]$Text, [string]$Status) {
    $colors = $script:KcBadgeColors[$Status]
    Write-Host (' {0} ' -f $Text) -NoNewline @colors
}

# 区切りの線。─ は日本語のコンソール (conhost) では 2 桁、Windows Terminal では 1 桁で表示される
function Get-KcRuleText {
    $width = 0
    try {
        $width = [int]$Host.UI.RawUI.WindowSize.Width
    } catch {
        $width = 0
    }
    if ($width -le 0) {
        $width = 80
    }
    $width = [math]::Max(60, [math]::Min(100, $width - 1))
    $cell = 2
    if ($env:WT_SESSION) {
        $cell = 1
    }
    return ('─' * [math]::Floor($width / $cell))
}

# コンソールに 1 項目を表示する: 判定のバッジ、項目、詳細 (- )、ヒント (→)
function Write-KcResult($Result) {
    $indent = ' ' * 11
    Write-Host '   ' -NoNewline
    Write-KcBadge $Result.Status $Result.Status
    Write-Host ('  ' + $Result.Item + (Format-KcResultValue $Result))
    foreach ($d in (Get-KcResultDetailLines $Result)) {
        Write-Host ($indent + '- ') -NoNewline -ForegroundColor DarkGray
        Write-Host $d.Substring(2)
    }
    foreach ($h in (Get-KcResultHintLines $Result)) {
        Write-Host ($indent + $h) -ForegroundColor Cyan
    }
}

function Get-KcStatusCounts($Results) {
    $counts = [ordered]@{ PASS = 0; FAIL = 0; WARN = 0; SKIP = 0; INFO = 0 }
    foreach ($r in $Results) {
        $counts[$r.Status]++
    }
    return $counts
}

# 全体の判定。Status: 色を選ぶための判定 (PASS / FAIL / WARN)、Text: 表示する文
function Get-KcVerdict($Results) {
    $c = Get-KcStatusCounts $Results
    $code = Get-KcExitCode $Results
    if ($code -eq 1) {
        return [pscustomobject]@{ Status = 'FAIL'; Text = '意図と違う設定があります。' }
    } elseif ($code -eq 2) {
        return [pscustomobject]@{ Status = 'WARN'; Text = '検査できた項目がありません (SKIP の案内を見てください)。' }
    } elseif ($c.WARN -gt 0) {
        return [pscustomobject]@{ Status = 'WARN'; Text = '意図と違う設定は見つかりませんでした (確認が必要な項目があります)。' }
    }
    return [pscustomobject]@{ Status = 'PASS'; Text = '意図どおりです。' }
}

# 結果の一覧と集計を表示する。続けて並んだ同じ Category の項目は、見出しの下にまとめる
function Write-KcSummary($Results, [string]$Title = '検査結果') {
    $rule = Get-KcRuleText
    Write-Host ''
    Write-Host (' ' + $Title)
    Write-Host $rule -ForegroundColor DarkGray
    $category = $null
    foreach ($r in $Results) {
        if ($r.Category -ne $category) {
            if ($null -ne $category) {
                Write-Host ''
            }
            $category = $r.Category
            Write-Host ('■ ' + $category) -ForegroundColor Cyan
        }
        Write-KcResult $r
    }
    Write-Host $rule -ForegroundColor DarkGray
    $c = Get-KcStatusCounts $Results
    Write-Host ' ' -NoNewline
    foreach ($s in @('PASS', 'FAIL', 'WARN', 'SKIP')) {
        $text = ' {0} {1} ' -f $s, $c[$s]
        if ($c[$s] -gt 0) {
            Write-KcBadge $text.Trim() $s
        } else {
            Write-Host $text -NoNewline -ForegroundColor DarkGray
        }
        Write-Host '  ' -NoNewline
    }
    Write-Host ''
    $v = Get-KcVerdict $Results
    Write-Host ' ' -NoNewline
    Write-KcBadge '判定' $v.Status
    Write-Host (' ' + $v.Text)
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
