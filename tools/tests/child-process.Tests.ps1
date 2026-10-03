# 書き込みツールの子プロセス (lib/keyboard-check/ChildProcess.cs) のテスト。書き込みツールと同じく、
# PowerShell を -EncodedCommand で起動し、出力を UTF-8 の行で受け取る。Linux の pwsh でも動く
# (Job Object は Windows だけなので、孫のプロセスまで止めるテストは Windows のみ)。

. (Join-Path $script:KcLib 'rawhid.ps1')
. (Join-Path $script:ToolsDir 'lib\flash-plan.ps1')

$script:CpHost = (Get-Process -Id $PID).Path

# 書き込みツール (flash.ps1) と同じ引数で子プロセスを起動する
function Start-CpChild([string]$Command) {
    Import-KcCSharp 'ChildProcess.cs' 'KcChildProcess'
    $arguments = '-NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -EncodedCommand ' + (ConvertTo-FlashEncodedCommand $Command)
    return [KcChildProcess]::Start($script:CpHost, $arguments, $script:ToolsDir, 65001)
}

# 終わるまで待って、すべての行を返す
function Wait-CpChild($Child, [int]$TimeoutMs = 60000) {
    $lines = New-Object System.Collections.ArrayList
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ($true) {
        foreach ($l in $Child.TakeLines()) { [void]$lines.Add($l) }
        if ($Child.HasExited) { break }
        if ([DateTime]::UtcNow -gt $deadline) { throw '子プロセスが終わりません' }
        Start-Sleep -Milliseconds 50
    }
    foreach ($l in $Child.TakeLines()) { [void]$lines.Add($l) }
    return , ($lines.ToArray())
}

function New-CpScript([string]$Body) {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('cp-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $dir)
    $path = Join-Path $dir 'child.ps1'
    [System.IO.File]::WriteAllText($path, $Body, (New-Object System.Text.UTF8Encoding $true))
    return $path
}

Test-Case 'ChildProcess.cs をコンパイルできる' {
    Import-KcCSharp 'ChildProcess.cs' 'KcChildProcess'
    Assert-True ('KcChildProcess' -as [type]) 'KcChildProcess 型'
}

Test-Case '子プロセス: 出力を UTF-8 の行で受け取り、CR だけの行は Partial、終了コードも届く' {
    $script = New-CpScript ('Write-Host "日本語の行 ✓ µ"' + "`n" +
        '[Console]::Out.Write("進捗 50%`r"); [Console]::Out.Write("進捗 100%`r`n"); [Console]::Out.Flush()' + "`n" +
        '[Console]::Error.WriteLine("エラーの行"); exit 3')
    try {
        $child = Start-CpChild (Format-FlashCommand $script ([ordered]@{}))
        try {
            $lines = Wait-CpChild $child
            $texts = @($lines | ForEach-Object { $_.Text })
            Assert-True ($texts -contains '日本語の行 ✓ µ') ($texts -join ' | ')
            $partial = @($lines | Where-Object { $_.Text -eq '進捗 50%' })
            Assert-Equal 1 $partial.Count ($texts -join ' | ')
            Assert-True $partial[0].Partial 'CR だけで終わる行'
            Assert-True (-not @($lines | Where-Object { $_.Text -eq '進捗 100%' })[0].Partial) 'CRLF で終わる行'
            $err = @($lines | Where-Object { $_.Text -eq 'エラーの行' })
            Assert-Equal 1 $err.Count ($texts -join ' | ')
            Assert-True $err[0].IsError '標準エラー'
            Assert-Equal 3 $child.ExitCode
            Assert-True (-not $child.Killed) '止めていない'
        } finally {
            $child.Dispose()
        }
    } finally {
        Remove-Item -LiteralPath (Split-Path -Parent $script) -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case '子プロセス: flash-uf2.ps1 / flash-keyball.ps1 の失敗は「失敗:」の行と終了コード 1' {
    $uf2 = [pscustomobject]@{ Runner = 'uf2'; Target = 'nRF52840'; Asset = 'x.uf2' }
    $missing = Join-Path ([System.IO.Path]::GetTempPath()) ('cp-none-' + [guid]::NewGuid().ToString('N') + '.uf2')
    $child = Start-CpChild (Get-FlashStepCommand $uf2 $missing $script:ToolsDir 5)
    try {
        $texts = @(Wait-CpChild $child | ForEach-Object { $_.Text })
        Assert-Equal 1 $child.ExitCode
        Assert-True (@($texts | Where-Object { $_ -like '失敗: ファイルが見つかりません*' }).Count -eq 1) ($texts -join ' | ')
    } finally {
        $child.Dispose()
    }

    $hex = New-CpScript ''
    [System.IO.File]::WriteAllText($hex, ":00000001FF`n:XX`n")
    try {
        $kb = [pscustomobject]@{ Runner = 'keyball'; Target = ''; Asset = 'k.hex' }
        $child = Start-CpChild (Get-FlashStepCommand $kb $hex $script:ToolsDir 5)
        try {
            $lines = Wait-CpChild $child
            $texts = @($lines | ForEach-Object { $_.Text })
            Assert-Equal 1 $child.ExitCode
            Assert-True (@($texts | Where-Object { $_ -like '失敗: Intel HEX として正しくありません*' }).Count -eq 1) ($texts -join ' | ')
            Assert-Equal 2 (ConvertTo-FlashLogLevel @($texts | Where-Object { $_ -like '失敗:*' })[0])
        } finally {
            $child.Dispose()
        }
    } finally {
        Remove-Item -LiteralPath (Split-Path -Parent $hex) -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case '子プロセス: Kill で止められる (止めたことがわかる)' {
    $child = Start-CpChild 'Write-Host "waiting"; Start-Sleep -Seconds 60; exit 0'
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        $seen = $false
        while (-not $seen -and [DateTime]::UtcNow -lt $deadline) {
            foreach ($l in $child.TakeLines()) { if ($l.Text -eq 'waiting') { $seen = $true } }
            Start-Sleep -Milliseconds 50
        }
        Assert-True $seen '起動した'
        Assert-True (-not $child.HasExited) 'まだ動いている'
        $child.Kill()
        Assert-True ($child.WaitExit(10000)) '止まった'
        Assert-True $child.Killed '止めた印'
        $child.Kill()
    } finally {
        $child.Dispose()
    }
}

Test-Case '子プロセス: 孫のプロセス (avrdude など) も一緒に止まる (Job Object)' -WindowsOnly {
    $child = Start-CpChild ('$p = Start-Process -FilePath ping.exe -ArgumentList "-n","60","127.0.0.1" -PassThru -WindowStyle Hidden; ' +
        'Write-Host ("pid=" + $p.Id); Start-Sleep -Seconds 60; exit 0')
    try {
        Assert-True $child.InJob 'Job Object に入っている'
        $grandchild = 0
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        while ($grandchild -eq 0 -and [DateTime]::UtcNow -lt $deadline) {
            foreach ($l in $child.TakeLines()) {
                if ($l.Text -match '^pid=(\d+)$') { $grandchild = [int]$Matches[1] }
            }
            Start-Sleep -Milliseconds 50
        }
        Assert-True ($grandchild -gt 0) '孫のプロセスが起動した'
        Assert-True ($null -ne (Get-Process -Id $grandchild -ErrorAction SilentlyContinue)) '孫のプロセスが動いている'
        $child.Kill()
        Assert-True ($child.WaitExit(10000)) '子プロセスが止まった'
        $gone = $false
        for ($i = 0; $i -lt 50 -and -not $gone; $i++) {
            $gone = $null -eq (Get-Process -Id $grandchild -ErrorAction SilentlyContinue)
            Start-Sleep -Milliseconds 100
        }
        Assert-True $gone '孫のプロセスも止まった'
    } finally {
        $child.Dispose()
    }
}
