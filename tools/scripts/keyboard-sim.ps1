<#
.SYNOPSIS
    実機なしで時刻付きのキーボード操作をシミュレーションし、期待値と比較します。
.DESCRIPTION
    親リポジトリのシミュレータと submodule の設定を読みます。設定や実機は変更しません。
    JSON/JUnit レポートを出力でき、失敗・未対応・シナリオ 0 件は終了コード 1 です。
.EXAMPLE
    pwsh -NoProfile -File tools/scripts/keyboard-sim.ps1
.EXAMPLE
    pwsh -NoProfile -File tools/scripts/keyboard-sim.ps1 -Scenario tools/simulator/scenarios -ReportJson tools/.cache/simulator/results.json
#>
[CmdletBinding()]
param(
    [string]$Scenario = (Join-Path $PSScriptRoot '../simulator/scenarios'),
    [string]$Board = '',
    [string]$Python = 'python',
    [string]$ReportJson = '',
    [string]$ReportJUnit = ''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/keyboard-check/keyboard-sim.ps1')

function Save-KcSimReport([string]$Path, [string]$Text) {
    $full = [System.IO.Path]::GetFullPath($Path)
    $ancestor = $full
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $attributes = [System.IO.File]::GetAttributes($ancestor)
            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'リンク経由のレポート出力には対応していません' }
        }
        $ancestor = [System.IO.Path]::GetDirectoryName($ancestor)
    }
    $root = $script:KcSimRoot + [System.IO.Path]::DirectorySeparatorChar
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $full.Substring($root.Length)
        $tracked = @(& git -C $script:KcSimRoot ls-files -- $relative)
        if ($LASTEXITCODE -ne 0) { throw 'レポート出力先の追跡状態を確認できません' }
        $first = ($relative -split '[\\/]')[0]
        if (Test-Path -LiteralPath (Join-Path $script:KcSimRoot ($first + '/.git'))) { throw 'submodule 内にレポートを書き込めません' }
        if ($tracked.Count -gt 0) { throw ('追跡ファイルにレポートを書き込めません: {0}' -f $Path) }
    }
    if ($script:KcSimInputFiles -contains $full) { throw 'シナリオをレポートで上書きできません' }
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($full))
    [System.IO.File]::WriteAllText($full, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

$report = [ordered]@{ schema = 1; passed = 0; failed = 0; scenarios = @() }
$script:KcSimInputFiles = @()
try {
    $item = Get-Item -LiteralPath $Scenario
    if ($item.PSIsContainer) { $files = @(Get-ChildItem -LiteralPath $item.FullName -Filter '*.json' -File | Sort-Object Name) }
    else { $files = @($item) }
    $script:KcSimInputFiles = @($files | ForEach-Object { $_.FullName })
    $results = New-Object 'System.Collections.Generic.List[object]'
    $names = @{}
    foreach ($file in $files) {
        $suite = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        Assert-KcSimInteger $suite.schema 'schema'
        if ($suite.schema -ne 1 -or $suite.scenarios -isnot [array] -or $suite.scenarios.Count -eq 0) { throw ('空または未対応のシナリオファイル: {0}' -f $file.Name) }
        foreach ($case in $suite.scenarios) {
            if ($Board -and (Get-KcSimProperty $case 'board') -ne $Board) { continue }
            $identity = '{0}/{1}' -f (Get-KcSimProperty $case 'board' 'inline'), (Get-KcSimProperty $case 'name' '')
            if ($names.ContainsKey($identity)) { throw ('シナリオ名が重複しています: {0}' -f $identity) }
            $names[$identity] = $true
            $result = Invoke-KcSimScenario $case -Python $Python
            $results.Add($result)
            $report.scenarios = $results.ToArray()
            if ($result.status -eq 'passed') {
                $report.passed++
                Write-Host ('PASS {0}' -f $identity)
            } else {
                $report.failed++
                Write-Host ('FAIL {0}: {1}' -f $identity, $result.error)
            }
        }
    }
    $report.scenarios = $results.ToArray()
    if ($results.Count -eq 0) { throw '実行対象のシナリオが 0 件です' }
} catch {
    $report.failed++
    $report['error'] = $_.Exception.Message
    Write-Host ('失敗: ' + $_.Exception.Message)
}

try {
    if ($ReportJson -and $ReportJUnit -and [System.IO.Path]::GetFullPath($ReportJson) -eq [System.IO.Path]::GetFullPath($ReportJUnit)) { throw 'JSON と JUnit の出力先は別にしてください' }
    if ($ReportJson) { Save-KcSimReport $ReportJson ($report | ConvertTo-Json -Depth 100) }
    if ($ReportJUnit) {
        $doc = New-Object System.Xml.XmlDocument
        $suiteNode = $doc.CreateElement('testsuite')
        $suiteNode.SetAttribute('name', 'keyboard-simulator')
        $suiteNode.SetAttribute('tests', [string]($report.passed + $report.failed))
        $suiteNode.SetAttribute('failures', [string]$report.failed)
        [void]$doc.AppendChild($suiteNode)
        foreach ($result in $report.scenarios) {
            $node = $doc.CreateElement('testcase')
            $node.SetAttribute('name', $result.name); $node.SetAttribute('classname', $result.board)
            if ($result.status -ne 'passed') {
                $failure = $doc.CreateElement('failure'); $failure.InnerText = $result.error
                [void]$node.AppendChild($failure)
            }
            [void]$suiteNode.AppendChild($node)
        }
        if ($report.Contains('error')) {
            $node = $doc.CreateElement('testcase'); $node.SetAttribute('name', 'configuration')
            $failure = $doc.CreateElement('failure'); $failure.InnerText = $report.error
            [void]$node.AppendChild($failure); [void]$suiteNode.AppendChild($node)
        }
        Save-KcSimReport $ReportJUnit $doc.OuterXml
    }
} catch {
    Write-Host ('失敗: レポートを保存できません: ' + $_.Exception.Message)
    exit 1
}
Write-Host ('シミュレーション: 成功 {0} / 失敗 {1}' -f $report.passed, $report.failed)
if ($report.failed -gt 0) { exit 1 }
exit 0
