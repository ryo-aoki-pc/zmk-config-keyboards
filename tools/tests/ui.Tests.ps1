# テスト用・記録用・書き込みツールのウィンドウ (WPF) の XAML のテスト。WPF の無い環境 (Linux) でも、XAML と
# InputTestForm.cs の食い違い (要素の名前、テーマのキー) を見つける

$script:UiDir = $script:KcLib
$script:UiCs = [System.IO.File]::ReadAllText((Join-Path $script:UiDir 'InputTestForm.cs'))
$script:UiTheme = [System.IO.File]::ReadAllText((Join-Path $script:UiDir 'Theme.xaml'))

function Get-UiMatches([string]$Text, [string]$Pattern) {
    return , @([regex]::Matches($Text, $Pattern) | ForEach-Object { $_.Groups[1].Value })
}

function Get-UiThemeKeys {
    return , (Get-UiMatches $script:UiTheme 'x:Key="([^"{]+)"')
}

# InputTestForm.cs のウィンドウ: KcUi.CreateWindow("<XAML>") を呼ぶクラスと、その XAML
function Get-UiWindows {
    $windows = @()
    foreach ($m in [regex]::Matches($script:UiCs, 'KcUi\.CreateWindow\("(\w+\.xaml)"')) {
        $classes = [regex]::Matches($script:UiCs.Substring(0, $m.Index), 'public sealed class (\w+)')
        $windows += @{ Class = $classes[$classes.Count - 1].Groups[1].Value; Xaml = $m.Groups[1].Value }
    }
    return , $windows
}

# InputTestForm.cs のうち、ウィンドウのクラスの部分 (次の public なクラスの前まで)
function Get-UiClassText([string]$ClassName) {
    $start = $script:UiCs.IndexOf('public sealed class ' + $ClassName)
    Assert-True ($start -ge 0) $ClassName
    $next = $script:UiCs.IndexOf("`npublic ", $start + 10)
    if ($next -lt 0) {
        $next = $script:UiCs.Length
    }
    return $script:UiCs.Substring($start, $next - $start)
}

Test-Case 'ウィンドウ: どの XAML も、いずれかのクラスが読み込む' {
    $windows = Get-UiWindows
    Assert-Equal 'KcInputTestForm,KcInputMonitorForm,KcLayerTraceForm,KcFlashForm,KcHoldTapForm' (@($windows | ForEach-Object { $_.Class }) -join ',')
    $files = @(Get-ChildItem -LiteralPath $script:UiDir -Filter '*.xaml' -File | Where-Object { $_.Name -ne 'Theme.xaml' } | ForEach-Object { $_.Name } | Sort-Object)
    Assert-Equal ($files -join ',') (@($windows | ForEach-Object { $_.Xaml } | Sort-Object) -join ',')
}

Test-Case 'XAML は XML として読める' {
    foreach ($f in @(Get-ChildItem -LiteralPath $script:UiDir -Filter '*.xaml' -File | ForEach-Object { $_.Name })) {
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load((Join-Path $script:UiDir $f))
        Assert-True ($null -ne $doc.DocumentElement) $f
    }
}

Test-Case 'Theme.xaml: キーが重複せず、StaticResource は定義の後で参照する' {
    $keys = Get-UiThemeKeys
    $dup = @($keys | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    Assert-Equal '' ($dup -join ', ') '重複したキー:'
    $bad = @()
    foreach ($m in [regex]::Matches($script:UiTheme, '\{StaticResource (\w+)\}')) {
        $def = $script:UiTheme.IndexOf(('x:Key="{0}"' -f $m.Groups[1].Value))
        if ($def -lt 0 -or $def -gt $m.Index) {
            $bad += $m.Groups[1].Value
        }
    }
    Assert-Equal '' ($bad -join ', ') '定義より前 (または定義の無い) StaticResource:'
}

Test-Case 'C# が探す要素が、ウィンドウの XAML にある' {
    foreach ($w in (Get-UiWindows)) {
        $code = Get-UiClassText $w.Class
        Assert-True ($code.Contains(('KcUi.CreateWindow("{0}"' -f $w.Xaml))) ('{0} は {1} を読み込む' -f $w.Class, $w.Xaml)
        $xaml = [System.IO.File]::ReadAllText((Join-Path $script:UiDir $w.Xaml))
        $names = Get-UiMatches $xaml 'x:Name="(\w+)"'
        $wanted = Get-UiMatches $code 'KcUi\.Find<\w+>\(root, "(\w+)"\)'
        Assert-True ($wanted.Count -ge 5) ('{0} の要素' -f $w.Class)
        $missing = @($wanted | Where-Object { $names -notcontains $_ })
        Assert-Equal '' ($missing -join ', ') ('{0} に無い要素:' -f $w.Xaml)
    }
}

Test-Case 'XAML と C# が使うテーマのキーが、Theme.xaml にある' {
    $keys = Get-UiThemeKeys
    $missing = @()
    foreach ($f in @(Get-UiWindows | ForEach-Object { $_.Xaml })) {
        $xaml = [System.IO.File]::ReadAllText((Join-Path $script:UiDir $f))
        foreach ($k in (Get-UiMatches $xaml '\{(?:Dynamic|Static)Resource (\w+)\}')) {
            if ($keys -notcontains $k) {
                $missing += ('{0}: {1}' -f $f, $k)
            }
        }
    }
    # C# の "Kc..." の文字列は、すべてテーマのキー (FindResource で引く)
    foreach ($k in (Get-UiMatches $script:UiCs '"(Kc\w+)"')) {
        if ($keys -notcontains $k) {
            $missing += ('InputTestForm.cs: ' + $k)
        }
    }
    Assert-Equal '' ($missing -join ', ') 'Theme.xaml に無いキー:'
}
