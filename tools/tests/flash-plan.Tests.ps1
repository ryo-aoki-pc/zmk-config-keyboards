# 書き込みツールの機種の表と手順 (lib/flash-plan.ps1) のテスト。

. (Join-Path $script:ToolsDir 'lib\flash-plan.ps1')

# 以前の flash-zmk.ps1 の Get-FlashPlan と同じ組み立て (アセット名と順番が変わっていないことを確かめる)
function Get-FpLegacyPlan([string]$Keyboard, [string]$Mode, [string]$Central, [string]$Right, [string]$Left) {
    $k = $script:FlashKeyboards[$Keyboard]
    $centralName = $k.Right.Replace('{v}', $Right)
    if ($Central) { $centralName += '_' + $Central }
    $peripheralName = $k.Left.Replace('{v}', $Left)
    $reset = $script:FlashMcus[$k.Mcu].SettingsReset + '.uf2'
    $rr = "右手側/設定リセット/$reset"
    $rm = "右手側/セントラル/$centralName.uf2"
    $lr = "左手側/設定リセット/$reset"
    $lm = "左手側/ペリフェラル/$peripheralName.uf2"
    switch ($Mode) {
        'Both' { return @($rm, $lm) }
        'ResetBoth' { return @($rr, $rm, $lr, $lm) }
        'Right' { return @($rm) }
        'Left' { return @($lm) }
        'ResetOnly' { return @($rr, $lr) }
    }
}

Test-Case '機種の表: ZMK 6 台・Keyball39・KQ-mini' {
    Assert-Equal 'LisM,AroundFortyRB,KUKEY42,Pyuron,roBa,torabo-tsuki-lp,Keyball39,KQ-mini' (@($script:FlashKeyboards.Keys) -join ',')
    foreach ($key in @($script:FlashKeyboards.Keys)) {
        $k = $script:FlashKeyboards[$key]
        Assert-True ($k.Repo -like 'ryo-aoki-pc/*') $key
        Assert-True $script:FlashMcus.ContainsKey($k.Mcu) ('{0}: Mcu' -f $key)
    }
    Assert-Equal 'keyball_keyball39_via.hex' $script:FlashKeyboards['Keyball39'].Asset
    Assert-Equal 'sekigon_keyboard_quantizer_mini_vial.uf2' $script:FlashKeyboards['KQ-mini'].Asset
}

Test-Case '手順: ZMK の全機種 × 書き込む内容 × セントラルの版 × LisM の版で、以前と同じファイルと順番' {
    foreach ($key in @($script:FlashKeyboards.Keys | Where-Object { $script:FlashKeyboards[$_].Kind -eq 'zmk' })) {
        $variants = @('trackball')
        if (Test-FlashHasVariants $key) { $variants = @('trackball', 'non_trackball') }
        foreach ($mode in @($script:FlashModes.Keys)) {
            foreach ($central in @('', 'studio', 'logging')) {
                foreach ($r in $variants) {
                    foreach ($l in $variants) {
                        $steps = @(Get-FlashPlan -Keyboard $key -Mode $mode -Central $central -Right $r -Left $l)
                        $actual = @($steps | ForEach-Object { '{0}/{1}/{2}' -f $_.Side, $_.What, $_.Asset }) -join ' | '
                        $expected = (Get-FpLegacyPlan $key $mode $central $r $l) -join ' | '
                        Assert-Equal $expected $actual ('{0} {1} {2} {3} {4}' -f $key, $mode, $central, $r, $l)
                        $target = $script:FlashMcus[$script:FlashKeyboards[$key].Mcu].Target
                        Assert-Equal 0 @($steps | Where-Object { $_.Target -ne $target -or $_.Runner -ne 'uf2' }).Count ('{0} の Target' -f $key)
                    }
                }
            }
        }
    }
}

Test-Case '手順: XIAO の設定リセットの後は、リセットボタンで切り替える案内' {
    $steps = @(Get-FlashPlan -Keyboard 'LisM' -Mode 'ResetBoth')
    Assert-True ($steps[0].Prepare -like '右手側の XIAO*Q*P*') $steps[0].Prepare
    Assert-True ($steps[1].Prepare -like '*設定リセットのファームウェアが動いている*リセットボタン*') $steps[1].Prepare
    Assert-True ($steps[2].Prepare -like '左手側の XIAO*Q*P*') $steps[2].Prepare
    Assert-True ($steps[3].Prepare -like '左手側*リセットボタン*') $steps[3].Prepare
    Assert-Equal 0 @($steps | Where-Object { $_.Pause -or $_.AfterReset }).Count 'XIAO は一度起動させる必要がない'
}

Test-Case '手順: BMP の設定リセットは、最後でなければ一度起動させてから次へ (Pause)' {
    $both = @(Get-FlashPlan -Keyboard 'torabo-tsuki-lp' -Mode 'ResetBoth')
    Assert-Equal 'True,False,True,False' (@($both | ForEach-Object { $_.Pause }) -join ',')
    Assert-True ($both[0].AfterReset -like '右手側の USB ケーブルを抜き*電源スイッチを ON*') $both[0].AfterReset
    Assert-True ($both[1].Prepare -like '右手側の電源スイッチを OFF*') $both[1].Prepare
    $only = @(Get-FlashPlan -Keyboard 'torabo-tsuki-lp' -Mode 'ResetOnly')
    Assert-Equal 'True,False' (@($only | ForEach-Object { $_.Pause }) -join ',')
    Assert-True ($only[1].AfterReset -like '左手側*') '最後の設定リセットの後の案内は完了のときに出す'
    Assert-Equal 'BMP' $only[0].Target
}

Test-Case '手順: Keyball39 は台数ぶん (1 台ずつ flash-keyball.ps1)、KQ-mini は 1 回' {
    $two = @(Get-FlashPlan -Keyboard 'Keyball39' -Count 2)
    Assert-Equal '1 台目,2 台目' (@($two | ForEach-Object { $_.Side }) -join ',')
    Assert-Equal 'keyball,keyball' (@($two | ForEach-Object { $_.Runner }) -join ',')
    Assert-Equal 'keyball_keyball39_via.hex' $two[0].Asset
    $one = @(Get-FlashPlan -Keyboard 'Keyball39' -Count 1)
    Assert-Equal 1 $one.Count
    Assert-Equal 'Keyball' $one[0].Side
    $kq = @(Get-FlashPlan -Keyboard 'KQ-mini')
    Assert-Equal 1 $kq.Count
    Assert-Equal 'RP2040' $kq[0].Target
    Assert-Equal 'uf2' $kq[0].Runner
}

Test-Case '手順: 不正な機種・書き込む内容・版は例外' {
    Assert-Throws { Get-FlashPlan -Keyboard 'Nope' } '*機種*'
    Assert-Throws { Get-FlashPlan -Keyboard 'LisM' -Mode 'All' } '*書き込む内容*'
    Assert-Throws { Get-FlashPlan -Keyboard 'LisM' -Mode 'Both' -Central 'debug' } '*セントラルの版*'
}

Test-Case 'ビルドに無いファイル: 一覧が不明 ($null) なら確かめない' {
    $steps = @(Get-FlashPlan -Keyboard 'LisM' -Mode 'Right' -Central 'logging')
    Assert-Equal 0 @(Get-FlashMissingAssets $steps $null).Count
    Assert-Equal 'lism_right_central_trackball_logging.uf2' ((Get-FlashMissingAssets $steps @('lism_right_central_trackball.uf2')) -join ',')
    Assert-Equal 0 @(Get-FlashMissingAssets $steps @('lism_right_central_trackball_logging.uf2')).Count
    $reset = @(Get-FlashPlan -Keyboard 'LisM' -Mode 'ResetOnly')
    Assert-Equal 1 @(Get-FlashMissingAssets $reset @()).Count '同じファイルは 1 回だけ'
}

Test-Case 'オプションの欄: 書き込む内容に合わせて出す欄を変える' {
    $right = @(Get-FlashOptionGroups 'LisM' 'Right')
    Assert-Equal 'mode,central,right,left' (@($right | ForEach-Object { $_.Key }) -join ',')
    Assert-Equal 'True,True,True,False' (@($right | ForEach-Object { $_.Visible }) -join ',')
    $left = @(Get-FlashOptionGroups 'LisM' 'Left')
    Assert-Equal 'True,False,False,True' (@($left | ForEach-Object { $_.Visible }) -join ',')
    Assert-Equal 'mode,central' (@(Get-FlashOptionGroups 'Pyuron' 'Both' | ForEach-Object { $_.Key }) -join ',')
    $mode = @(Get-FlashOptionGroups 'Pyuron' 'Both')[0]
    Assert-Equal 'choices' $mode.Style
    Assert-Equal 5 @($mode.Keys).Count
    Assert-Equal 5 @($mode.Details).Count
    Assert-Equal 'count' (@(Get-FlashOptionGroups 'Keyball39' '')[0].Key)
    Assert-Equal '2,1' ((@(Get-FlashOptionGroups 'Keyball39' '')[0].Keys) -join ',')
    Assert-Equal 0 @(Get-FlashOptionGroups 'KQ-mini' '').Count
}

Test-Case '子プロセスのコマンド: 引用符を含むパスと配列を、そのまま渡せる (構文として正しい)' {
    $cmd = Format-FlashCommand "C:\a b\it's\flash-uf2.ps1" ([ordered]@{ Path = "C:\x\o'k.uf2"; Target = @('nRF52840', 'BMP'); WaitSeconds = 600 })
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$tokens, [ref]$errors)
    Assert-Equal 0 @($errors).Count '構文エラー'
    $call = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq 'Ampersand' }, $true)
    Assert-Equal "C:\a b\it's\flash-uf2.ps1" $call.CommandElements[0].Value
    Assert-True ($cmd -like "*-Path 'C:\x\o''k.uf2'*") $cmd
    Assert-True ($cmd -like "*-Target 'nRF52840','BMP'*") $cmd
    Assert-True ($cmd -like '*exit $LASTEXITCODE*') $cmd
    Assert-True ($cmd -like '*UTF8Encoding*') $cmd
}

Test-Case '子プロセスのコマンド: 手順ごとのスクリプトと引数' {
    $uf2 = @(Get-FlashPlan -Keyboard 'torabo-tsuki-lp' -Mode 'Right')[0]
    $cmd = Get-FlashStepCommand $uf2 'C:\fw\a.uf2' 'C:\tools' 600
    Assert-True ($cmd -like "*& 'C:\tools*flash-uf2.ps1' -Path 'C:\fw\a.uf2' -Target 'BMP' -WaitSeconds '600'*") $cmd
    $hex = @(Get-FlashPlan -Keyboard 'Keyball39' -Count 2)[1]
    $cmd = Get-FlashStepCommand $hex 'C:\fw\k.hex' 'C:\tools' 300
    Assert-True ($cmd -like "*flash-keyball.ps1' -Path 'C:\fw\k.hex' -Count '1' -WaitSeconds '300'*") $cmd
}

Test-Case '子プロセスのコマンド: 実際に実行すると引数と終了コードが届く (-EncodedCommand)' {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('fp-cmd-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $dir)
    try {
        $script = Join-Path $dir "it's a script.ps1"
        $body = 'param([string]$Path, [string[]]$Target, [int]$WaitSeconds) ' +
            'Write-Host ("path=" + $Path); Write-Host ("target=" + ($Target -join "+")); Write-Host ("wait=" + $WaitSeconds); Write-Host "成功: µ"; exit 3'
        [System.IO.File]::WriteAllText($script, $body, (New-Object System.Text.UTF8Encoding $true))
        $cmd = Format-FlashCommand $script ([ordered]@{ Path = "C:\x\o'k a.uf2"; Target = @('nRF52840', 'BMP'); WaitSeconds = 42 })
        $exe = (Get-Process -Id $PID).Path
        $out = & $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand (ConvertTo-FlashEncodedCommand $cmd) 2>&1
        $code = $LASTEXITCODE
        $text = @($out | ForEach-Object { [string]$_ }) -join "`n"
        Assert-Equal 3 $code '終了コード'
        Assert-True ($text -like "*path=C:\x\o'k a.uf2*") $text
        Assert-True ($text -like '*target=nRF52840+BMP*') $text
        Assert-True ($text -like '*wait=42*') $text

        $bad = Format-FlashCommand (Join-Path $dir 'missing.ps1') ([ordered]@{ Path = 'x' })
        $out = & $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand (ConvertTo-FlashEncodedCommand $bad) 2>&1
        Assert-Equal 1 $LASTEXITCODE 'スクリプトが無ければ 1'
        # (親の PowerShell は子の出力をコンソールのコードページで読むので、ASCII の部分で確かめる)
        Assert-True ((@($out | ForEach-Object { [string]$_ }) -join "`n") -like '*missing.ps1*') 'エラーの行'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'ログの行: 失敗 / 成功・完了 / 注意 / 薄く / 隠す' {
    Assert-Equal 2 (ConvertTo-FlashLogLevel '失敗: 見つかりません')
    Assert-Equal 2 (ConvertTo-FlashLogLevel '  失敗: x')
    Assert-Equal 1 (ConvertTo-FlashLogLevel '成功: ブートローダが全ブロックを受け取り')
    Assert-Equal 1 (ConvertTo-FlashLogLevel '完了: 2 台すべてに書き込みました。')
    Assert-Equal 3 (ConvertTo-FlashLogLevel 'avrdude が失敗しました (終了コード 1)。')
    Assert-Equal 3 (ConvertTo-FlashLogLevel 'avrdude error: programmer is not responding' $true)
    Assert-Equal 3 (ConvertTo-FlashLogLevel 'WARNING: X:\ は ...')
    Assert-Equal 4 (ConvertTo-FlashLogLevel '  (ドライブ切断によるエラー「...」は、')
    Assert-Equal -1 (ConvertTo-FlashLogLevel '#< CLIXML')
    Assert-Equal -1 (ConvertTo-FlashLogLevel '<Objs Version="1.1.0.1" xmlns="...">')
    Assert-Equal 0 (ConvertTo-FlashLogLevel 'ブートローダのドライブを待っています...')
    Assert-Equal 0 (ConvertTo-FlashLogLevel 'avrdude: writing flash (12345 bytes):' $true)
}

Test-Case '手順の後: 中止 / 失敗 / 一時停止 / 次 / 完了' {
    $steps = @(Get-FlashPlan -Keyboard 'torabo-tsuki-lp' -Mode 'ResetBoth')
    Assert-Equal 'cancelled' (Get-FlashNextPhase $steps 0 1 $true)
    Assert-Equal 'failed' (Get-FlashNextPhase $steps 0 1 $false)
    Assert-Equal 'pause' (Get-FlashNextPhase $steps 0 0 $false)
    Assert-Equal 'next' (Get-FlashNextPhase $steps 1 0 $false)
    Assert-Equal 'done' (Get-FlashNextPhase $steps 3 0 $false)
}

Test-Case 'スクリプトの -Keyboard の候補が機種の表と同じ (flash.ps1 は全機種、flash-zmk.ps1 は ZMK)' {
    foreach ($case in @(@{ File = 'flash.ps1'; Keys = @($script:FlashKeyboards.Keys) },
            @{ File = 'flash-zmk.ps1'; Keys = @($script:FlashKeyboards.Keys | Where-Object { $script:FlashKeyboards[$_].Kind -eq 'zmk' }) })) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:ToolsDir $case.File), [ref]$tokens, [ref]$errors)
        $param = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Keyboard' })[0]
        $set = @($param.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' })[0]
        $values = @($set.PositionalArguments | ForEach-Object { $_.Value })
        Assert-Equal ($case.Keys -join ',') ($values -join ',') $case.File
    }
}
