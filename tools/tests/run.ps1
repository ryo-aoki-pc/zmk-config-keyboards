<#
.SYNOPSIS
    tools/ の PowerShell スクリプトのテストを実行します (Pester は使いません)。

.DESCRIPTION
    - tools/**/*.ps1 が UTF-8 (BOM 付き) で、構文エラーが無いこと
    - Windows PowerShell 5.1 で使えない構文 (??、?.、三項演算子、&&、文字列の `e など) を使っていないこと
    - .cmd / .cs / .xaml が ASCII だけで書かれていること
    - .cmd が呼ぶ .ps1 があり、tools 直下には利用者が実行する .cmd だけがあること
    - tools/tests/*.Tests.ps1 の各テスト (偽のデバイスを使った読み出し検査、判定の計算など)

    Windows 専用のテスト (C# のコンパイル、フォームの生成) は Windows 以外では飛ばします。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\tests\run.ps1

.EXAMPLE
    pwsh -NoProfile -File tools/tests/run.ps1 -Filter qmk
#>
[CmdletBinding()]
param(
    # テスト名 (またはファイル名) にこの文字列を含むものだけ実行する
    [string]$Filter = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:TestsDir = $PSScriptRoot
$script:ToolsDir = Split-Path -Parent $PSScriptRoot
$script:KcLib = Join-Path $script:ToolsDir 'lib\keyboard-check'
$script:ExpectedDir = Join-Path $script:ToolsDir 'expected'
$script:IsWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0
$script:Failures = New-Object 'System.Collections.Generic.List[string]'
$script:CurrentFile = ''

function Test-Case([string]$Name, [scriptblock]$Body, [switch]$WindowsOnly) {
    $full = '{0} / {1}' -f $script:CurrentFile, $Name
    if ($Filter -and $full -notlike "*$Filter*") {
        return
    }
    if ($WindowsOnly -and -not $script:IsWindowsHost) {
        $script:Skipped++
        Write-Host ('  SKIP  {0} (Windows のみ)' -f $Name) -ForegroundColor DarkGray
        return
    }
    try {
        & $Body
        $script:Passed++
        Write-Host ('  ok    {0}' -f $Name) -ForegroundColor Green
    } catch {
        $script:Failed++
        $msg = '{0}: {1}' -f $full, $_.Exception.Message
        $script:Failures.Add($msg)
        Write-Host ('  FAIL  {0}' -f $Name) -ForegroundColor Red
        Write-Host ('        {0}' -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ('        {0}' -f $_.InvocationInfo.PositionMessage.Split("`n")[0]) -ForegroundColor DarkGray
    }
}

function Assert-Equal($Expected, $Actual, [string]$Message = '') {
    $e = $Expected
    $a = $Actual
    if ($e -is [array] -or $a -is [array]) {
        $e = (@($e) | ForEach-Object { [string]$_ }) -join ','
        $a = (@($a) | ForEach-Object { [string]$_ }) -join ','
    }
    if ($e -ne $a -or ($null -eq $e) -ne ($null -eq $a)) {
        throw ('{0} 期待: <{1}> 実際: <{2}>' -f $Message, $e, $a)
    }
}

function Assert-True($Condition, [string]$Message = '') {
    if (-not $Condition) {
        throw ('{0} (条件が成り立っていません)' -f $Message)
    }
}

function Assert-Near([double]$Expected, [double]$Actual, [double]$Tolerance, [string]$Message = '') {
    if ([math]::Abs($Expected - $Actual) -gt $Tolerance) {
        throw ('{0} 期待: {1} ± {2} 実際: {3}' -f $Message, $Expected, $Tolerance, $Actual)
    }
}

function Assert-Throws([scriptblock]$Body, [string]$Like = '*', [string]$Message = '') {
    $thrown = $null
    try {
        & $Body
    } catch {
        $thrown = $_.Exception.Message
    }
    if ($null -eq $thrown) {
        throw ('{0} (例外が出ませんでした)' -f $Message)
    }
    if ($thrown -notlike $Like) {
        throw ('{0} 例外のメッセージが違います: {1}' -f $Message, $thrown)
    }
}

# ---------------------------------------------------------------------------
# ファイルの体裁
# ---------------------------------------------------------------------------

$script:CurrentFile = 'hygiene'
Write-Host '[hygiene]'

$psFiles = @(Get-ChildItem -Path $script:ToolsDir -Recurse -Include '*.ps1' -File | Where-Object { $_.FullName -notmatch '[\\/]\.cache[\\/]' })
$cmdFiles = @(Get-ChildItem -Path $script:ToolsDir -Recurse -Include '*.cmd', '*.cs', '*.xaml' -File | Where-Object { $_.FullName -notmatch '[\\/]\.cache[\\/]' })

Test-Case '.ps1 は UTF-8 (BOM 付き)' {
    $bad = @()
    foreach ($f in $psFiles) {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
            $bad += $f.Name
        }
    }
    Assert-Equal '' ($bad -join ', ') 'BOM が無いファイル:'
}

Test-Case '.cmd / .cs / .xaml は ASCII だけ' {
    $bad = @()
    foreach ($f in $cmdFiles) {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        foreach ($b in $bytes) {
            if ($b -gt 0x7E -or ($b -lt 0x20 -and $b -ne 0x0D -and $b -ne 0x0A -and $b -ne 0x09)) {
                $bad += $f.Name
                break
            }
        }
    }
    Assert-Equal '' ($bad -join ', ') 'ASCII 以外を含むファイル:'
}

Test-Case '.cmd が呼ぶ .ps1 がある' {
    $bad = @()
    foreach ($f in $cmdFiles) {
        if ($f.Extension -ne '.cmd') {
            continue
        }
        $found = [regex]::Matches([System.IO.File]::ReadAllText($f.FullName), '%~dp0([^"\s]+\.ps1)')
        if ($found.Count -eq 0) {
            $bad += ('{0} (.ps1 を呼んでいない)' -f $f.Name)
        }
        foreach ($m in $found) {
            $target = Join-Path $f.DirectoryName ($m.Groups[1].Value.Replace('\', [string][System.IO.Path]::DirectorySeparatorChar))
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                $bad += ('{0} → {1}' -f $f.Name, $m.Groups[1].Value)
            }
        }
    }
    Assert-Equal '' ($bad -join ', ') '.ps1 が見つからない .cmd:'
}

Test-Case 'tools 直下は利用者が実行する .cmd だけ (.ps1 と他の .cmd は scripts)' {
    $top = @(Get-ChildItem -Path $script:ToolsDir -File | Where-Object { $_.Extension -eq '.cmd' -or $_.Extension -eq '.ps1' } |
            ForEach-Object { $_.Name } | Sort-Object)
    Assert-Equal 'flash.cmd, input-monitor.cmd, keyball-check.cmd, keyboard-check.cmd' ($top -join ', ') 'tools 直下:'
}

Test-Case '.ps1 に構文エラーが無い' {
    $bad = @()
    foreach ($f in $psFiles) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) {
            $bad += ('{0}: {1}' -f $f.Name, $errors[0].Message)
        }
    }
    Assert-Equal '' ($bad -join ' / ') '構文エラー:'
}

Test-Case 'Windows PowerShell 5.1 で使えない構文を使っていない' {
    $bad = @()
    $ps7Params = @('AsHashtable', 'AsByteStream', 'Parallel', 'SkipHttpErrorCheck', 'NoEnumerate', 'Stable')
    $ps7Vars = @('IsWindows', 'IsLinux', 'IsMacOS', 'IsCoreCLR')
    foreach ($f in $psFiles) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        $found = $ast.FindAll({
                param($n)
                $t = $n.GetType().Name
                if ($t -eq 'TernaryExpressionAst' -or $t -eq 'PipelineChainAst') {
                    return $true
                }
                if ($n -is [System.Management.Automation.Language.BinaryExpressionAst]) {
                    if ([string]$n.Operator -eq 'QuestionQuestion') {
                        return $true
                    }
                }
                if ($n -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    if ([string]$n.Operator -eq 'QuestionQuestionEquals') {
                        return $true
                    }
                }
                $nc = $n.PSObject.Properties['NullConditional']
                if ($null -ne $nc -and $nc.Value) {
                    return $true
                }
                if ($n -is [System.Management.Automation.Language.CommandParameterAst]) {
                    if ($ps7Params -contains $n.ParameterName) {
                        return $true
                    }
                }
                if ($n -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    if ($ps7Vars -contains $n.VariablePath.UserPath) {
                        return $true
                    }
                }
                return $false
            }, $true)
        foreach ($n in $found) {
            $bad += ('{0}:{1} {2}' -f $f.Name, $n.Extent.StartLineNumber, $n.Extent.Text)
        }
        # 文字列のエスケープ `e (ESC) と `u{...} は PowerShell 6 から。5.1 では e や u{...} のままになる
        foreach ($t in $tokens) {
            if ($t.Kind -ne 'StringExpandable' -and $t.Kind -ne 'HereStringExpandable') { continue }
            if ($t.Text -match '(?<!`)(?:``)*`(?:e|u\{)') {
                $bad += ('{0}:{1} {2}' -f $f.Name, $t.Extent.StartLineNumber, $t.Text)
            }
        }
    }
    Assert-Equal '' ($bad -join ' / ') 'PS7 専用の構文:'
}

# ---------------------------------------------------------------------------
# 各テストファイル
# ---------------------------------------------------------------------------

foreach ($file in @(Get-ChildItem -Path $script:TestsDir -Filter '*.Tests.ps1' -File | Sort-Object Name)) {
    $script:CurrentFile = $file.BaseName -replace '\.Tests$', ''
    Write-Host ('[{0}]' -f $script:CurrentFile)
    . $file.FullName
}

Write-Host ''
$summary = 'テスト: 成功 {0} / 失敗 {1} / スキップ {2}' -f $script:Passed, $script:Failed, $script:Skipped
if ($script:Failed -gt 0) {
    Write-Host $summary -ForegroundColor Red
    foreach ($f in $script:Failures) {
        Write-Host ('  - ' + $f) -ForegroundColor Red
    }
    exit 1
}
Write-Host $summary -ForegroundColor Green
exit 0
