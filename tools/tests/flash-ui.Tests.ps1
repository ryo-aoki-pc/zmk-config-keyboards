# 書き込みツールの画面の流れ (lib/flash-ui.ps1) のテスト。ウィンドウ・子プロセス・ダウンロード・一覧の取得は偽物を使う
# (Windows 以外でも、選択 → ダウンロード → 手順ごとの書き込み → 完了 / 失敗 / 中止 の流れを確かめる)。

. (Join-Path $script:ToolsDir 'lib\firmware-release.ps1')
. (Join-Path $script:ToolsDir 'lib\flash-plan.ps1')
. (Join-Path $script:ToolsDir 'lib\flash-ui.ps1')
. (Join-Path $script:TestsDir 'flash-fixtures.ps1')

$script:FuFormMethods = @('SetTexts', 'SetCaptions', 'SetButtonTexts', 'SetButtons', 'SetStartEnabled', 'SetSource', 'SetStatus',
    'SetProgress', 'ShowPage', 'SetKeyboards', 'SelectKeyboard', 'SetBuildFilters', 'SetBuilds', 'SetBuildsMessage',
    'ClearOptionGroups', 'AddOptionGroup', 'SetPlanNote', 'SetSteps', 'SetStepState', 'SetBanner', 'AppendLog', 'ClearLog',
    'SetCloseGuard', 'RequestClose')

# KcFlashForm の偽物: 呼ばれたメソッドと引数を Calls に記録する。Queue に入れた操作を TakeActions で返す
function New-FuForm {
    $form = [pscustomobject]@{ Calls = (New-Object System.Collections.ArrayList); Queue = (New-Object System.Collections.ArrayList) }
    foreach ($m in $script:FuFormMethods) {
        $form | Add-Member -MemberType ScriptMethod -Name $m -Value ([scriptblock]::Create("[void]`$this.Calls.Add((@('$m') + `$args))"))
    }
    $form | Add-Member -MemberType ScriptMethod -Name TakeActions -Value {
        $a = $this.Queue.ToArray()
        $this.Queue.Clear()
        return , $a
    }
    return $form
}

# 名前が $Name の呼び出し (引数の配列) を 1 つずつ出力する (呼ぶ側は @() で受ける)
function Get-FuCalls($Form, [string]$Name) {
    foreach ($c in $Form.Calls) {
        if ($c[0] -eq $Name) {
            , $c
        }
    }
}

function Get-FuLast($Form, [string]$Name) {
    $calls = @(Get-FuCalls $Form $Name)
    if ($calls.Count -eq 0) {
        throw "$Name が呼ばれていません"
    }
    return , $calls[$calls.Count - 1]
}

# 子プロセスの偽物。HasExited / ExitCode はテストで変える
function New-FuChild([string[]]$Lines = @(), [int]$ExitCode = 0, [bool]$Exited = $true) {
    $lineObjects = @(foreach ($l in $Lines) { [pscustomobject]@{ Text = $l; IsError = $false; Partial = $false } })
    $child = [pscustomobject]@{ Pending = $lineObjects; HasExited = $Exited; ExitCode = $ExitCode; Killed = $false; Disposed = $false }
    $child | Add-Member -MemberType ScriptMethod -Name TakeLines -Value {
        $a = $this.Pending
        $this.Pending = @()
        return , $a
    }
    $child | Add-Member -MemberType ScriptMethod -Name Kill -Value {
        $this.Killed = $true
        $this.HasExited = $true
        $this.ExitCode = 1
    }
    $child | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed = $true }
    return $child
}

# 画面の流れの $Ctx。$Children に入れた子プロセスを順に返す
function New-FuContext([string]$Keyboard = 'LisM', [hashtable]$Settings = @{}) {
    $world = @{
        Form       = (New-FuForm)
        BuildCalls = (New-Object System.Collections.ArrayList)
        Downloads  = (New-Object System.Collections.ArrayList)
        Commands   = (New-Object System.Collections.ArrayList)
        Children   = (New-Object System.Collections.Queue)
        Saved      = (New-Object System.Collections.ArrayList)
        DownloadError = ''
        Now        = (New-Object DateTime 2026, 10, 3, 6, 0, 0, ([DateTimeKind]::Utc))
    }
    $script:FuWorld = $world
    $world.Ctx = New-FlashUiContext -Form $world.Form -ToolsDir 'C:\tools' -WaitSeconds 600 -Settings $Settings `
        -GetBuilds {
            param($Repo)
            [void]$script:FuWorld.BuildCalls.Add($Repo)
            $issues = New-FlashFixtureIssuesJson
            $builds = @(ConvertFrom-FirmwareListPages @(New-FlashFixtureLismJson) $issues)
            if ($Repo -notlike '*LisM') {
                # LisM 以外は、ビルドにあるファイルを「不明」にする (偽物のファイル名は LisM のもの)
                foreach ($b in $builds) { $b.Assets = $null }
            }
            return @{ Builds = $builds; Source = 'api'; Message = ''; Level = 0; FetchedAt = $script:FuWorld.Now }
        } `
        -Download {
            param($Repo, $Tag, $Assets, $OnFile)
            [void]$script:FuWorld.Downloads.Add(('{0} {1} {2}' -f $Repo, $Tag, ($Assets -join ',')))
            $paths = @{}
            for ($i = 0; $i -lt $Assets.Count; $i++) {
                & $OnFile $i $Assets.Count $Assets[$i]
                $paths[$Assets[$i]] = 'C:\fw\' + $Assets[$i]
            }
            if ($script:FuWorld.DownloadError) {
                throw $script:FuWorld.DownloadError
            }
            return @{ Paths = $paths; Info = @{ commit = 'aaaaaaa1234'; built = '2026-10-02T03:00:00Z' } }
        } `
        -NewChild {
            param($Command)
            [void]$script:FuWorld.Commands.Add($Command)
            return $script:FuWorld.Children.Dequeue()
        } `
        -SaveSettings { param($Settings) [void]$script:FuWorld.Saved.Add($Settings) } `
        -Now { $script:FuWorld.Now }
    Initialize-FlashUi $world.Ctx $Keyboard
    return $world
}

Test-Case '起動: 機種の一覧・前回の機種・ビルドの一覧・手順を出し、書き込めるようにする' {
    $w = New-FuContext '' @{ Keyboard = 'Pyuron' }
    $f = $w.Form
    $s = $w.Ctx.State
    Assert-Equal 'Pyuron' $s.Keyboard
    $kb = Get-FuLast $f 'SetKeyboards'
    Assert-Equal 8 $kb[1].Count
    Assert-Equal 'ZMK' $kb[4][0]
    Assert-Equal 'QMK / Vial' $kb[4][7]
    Assert-Equal 'Pyuron' (Get-FuLast $f 'SelectKeyboard')[1]
    Assert-Equal 'ryo-aoki-pc/zmk-config-Pyuron' ($w.BuildCalls -join ',')
    Assert-Equal 'firmware-latest' $s.Tag
    $builds = Get-FuLast $f 'SetBuilds'
    Assert-Equal 'firmware-latest,firmware-pr-27,firmware-pr-12,firmware-custom-bbbbbbb' ($builds[1] -join ',')
    Assert-Equal '0,1,1,2' ($builds[2] -join ',')
    Assert-Equal '0,1,2,0' ($builds[6] -join ',') 'PR の状態 (オープン / マージ済み)'
    Assert-Equal 'firmware-latest' $builds[9]
    $steps = Get-FuLast $f 'SetSteps'
    Assert-Equal '[1/2] 右手側: セントラル,[2/2] 左手側: ペリフェラル' ($steps[1] -join ',')
    Assert-Equal $true (Get-FuLast $f 'SetStartEnabled')[1]
    Assert-Equal 'mode,central' (@(Get-FuCalls $f 'AddOptionGroup' | ForEach-Object { $_[1] }) -join ',')
    Assert-True ((Get-FuLast $f 'SetSource')[1] -like 'GitHub から取得 (??:??)') (Get-FuLast $f 'SetSource')[1]
}

Test-Case '機種の切り替え: 一覧は 10 分間取り直さない (「更新」で取り直す)、書き込む内容は既定に戻す' {
    $w = New-FuContext 'LisM'
    $ctx = $w.Ctx
    Invoke-FlashUiAction $ctx 'option:mode:Right'
    Invoke-FlashUiAction $ctx 'option:central:logging'
    Assert-Equal 'Right' $ctx.State.Mode
    Invoke-FlashUiAction $ctx 'keyboard:roBa'
    Assert-Equal 'Both' $ctx.State.Mode
    Assert-Equal '' $ctx.State.Central
    Invoke-FlashUiAction $ctx 'keyboard:LisM'
    Assert-Equal 2 $w.BuildCalls.Count '同じリポジトリは取り直さない'
    $w.Now = $w.Now.AddMinutes(11)
    Invoke-FlashUiAction $ctx 'keyboard:roBa'
    Assert-Equal 3 $w.BuildCalls.Count '10 分たったら取り直す'
    Invoke-FlashUiAction $ctx 'refresh'
    Assert-Equal 4 $w.BuildCalls.Count '更新'
    Assert-Equal 'roBa' $w.Saved[$w.Saved.Count - 1].Keyboard
}

Test-Case 'オプション: 書き込む内容で欄が変わり、LisM の版・セントラルの版がファイル名に入る' {
    $w = New-FuContext 'LisM'
    $f = $w.Form
    Invoke-FlashUiAction $w.Ctx 'option:mode:Left'
    $groups = @(Get-FuCalls $f 'AddOptionGroup' | Select-Object -Last 4)
    Assert-Equal 'mode,central,right,left' (@($groups | ForEach-Object { $_[1] }) -join ',')
    Assert-Equal 'True,False,False,True' (@($groups | ForEach-Object { $_[8] }) -join ',')
    Invoke-FlashUiAction $w.Ctx 'option:left:non_trackball'
    Assert-Equal 'lism_left_peripheral_non_trackball.uf2' ((Get-FuLast $f 'SetSteps')[2] -join ',')
    Invoke-FlashUiAction $w.Ctx 'option:mode:Right'
    Invoke-FlashUiAction $w.Ctx 'option:central:studio'
    Assert-Equal 'lism_right_central_trackball_studio.uf2' ((Get-FuLast $f 'SetSteps')[2] -join ',')
    Assert-Equal 'non_trackball' $w.Saved[$w.Saved.Count - 1].LismLeft '版は覚える'
}

Test-Case 'ビルドに無いファイル (古いビルドのログ版) は、書き込めないようにして理由を出す' {
    $w = New-FuContext 'LisM'
    $f = $w.Form
    Invoke-FlashUiAction $w.Ctx 'option:mode:Right'
    Invoke-FlashUiAction $w.Ctx 'option:central:logging'
    Assert-Equal $true (Get-FuLast $f 'SetStartEnabled')[1]
    Assert-True ((Get-FuLast $f 'SetPlanNote')[1] -like '*通常版に戻して*') 'ログ版の注意'
    Invoke-FlashUiAction $w.Ctx 'build:firmware-custom-bbbbbbb'
    Assert-Equal $false (Get-FuLast $f 'SetStartEnabled')[1]
    $note = Get-FuLast $f 'SetPlanNote'
    Assert-True ($note[1] -like '*lism_right_central_trackball_logging.uf2*') $note[1]
    Assert-Equal 2 $note[2]
    Invoke-FlashUiAction $w.Ctx 'start'
    Assert-Equal 'select' $w.Ctx.State.Phase '書き込みは始まらない'
    Assert-Equal 0 $w.Downloads.Count
}

Test-Case '絞り込み: PR だけ (選んでいたビルドが隠れたら先頭を選ぶ)。無いビルドは選べない' {
    $w = New-FuContext 'LisM'
    $f = $w.Form
    Invoke-FlashUiAction $w.Ctx 'filter:pr'
    Assert-Equal 'firmware-pr-27,firmware-pr-12' ((Get-FuLast $f 'SetBuilds')[1] -join ',')
    Assert-Equal 'firmware-pr-27' $w.Ctx.State.Tag
    Assert-True ((Get-FuLast $f 'SetPlanNote')[1] -like 'PR #27 *') 'PR の説明'
    Invoke-FlashUiAction $w.Ctx 'build:firmware-nope'
    Assert-Equal 'firmware-pr-27' $w.Ctx.State.Tag
}

Test-Case '書き込み: ダウンロード → 1 手順ずつ子プロセス → 完了' {
    $w = New-FuContext 'LisM'
    $f = $w.Form
    $ctx = $w.Ctx
    $w.Children.Enqueue((New-FuChild @('ブートローダのドライブを待っています...', '成功: ブートローダが全ブロックを受け取り、ボードが再起動しました。') 0 $false))
    $w.Children.Enqueue((New-FuChild @('成功: ok') 0 $true))
    Invoke-FlashUiAction $ctx 'build:firmware-pr-27'
    Invoke-FlashUiAction $ctx 'start'
    Assert-Equal 'ryo-aoki-pc/zmk-config-LisM firmware-pr-27 lism_right_central_trackball.uf2,lism_left_peripheral_trackball.uf2' ($w.Downloads -join '|')
    Assert-Equal 'run' $ctx.State.Phase
    Assert-Equal 1 $w.Commands.Count
    Assert-True ($w.Commands[0] -like "*flash-uf2.ps1' -Path 'C:\fw\lism_right_central_trackball.uf2' -Target 'nRF52840' -WaitSeconds '600'*") $w.Commands[0]
    Assert-Equal $script:FlashUiPageRun (Get-FuLast $f 'ShowPage')[1]
    Assert-True ((Get-FuLast $f 'SetBanner')[1] -like '`[1/2`] 右手側: セントラル*') (Get-FuLast $f 'SetBanner')[1]
    Assert-Equal $true (Get-FuLast $f 'SetCloseGuard')[1]

    Update-FlashUiTick $ctx
    Assert-Equal 'run' $ctx.State.Phase 'まだ終わっていない'
    Assert-True ((Get-FuLast $f 'SetStatus')[1] -like '成功: *(0:00)') (Get-FuLast $f 'SetStatus')[1]
    $ok = @(Get-FuCalls $f 'AppendLog' | Where-Object { $_[1] -like '成功:*' })
    Assert-Equal 1 $ok.Count
    Assert-Equal $script:FlashUiLevelOk $ok[0][2]

    $ctx.State.Child.HasExited = $true
    Update-FlashUiTick $ctx
    Assert-Equal 2 $w.Commands.Count '2 手順目'
    Assert-True ($w.Commands[1] -like '*lism_left_peripheral_trackball.uf2*') $w.Commands[1]
    Update-FlashUiTick $ctx
    Assert-Equal 'done' $ctx.State.Phase
    Assert-Equal 'done' $ctx.State.Result
    Assert-Equal 2 $ctx.State.Flashed
    $banner = Get-FuLast $f 'SetBanner'
    Assert-True ($banner[1] -like '完了: LisM に 2 個*') $banner[1]
    Assert-Equal $script:FlashUiLevelOk $banner[3]
    Assert-Equal '0:1,0:2,1:1,1:2' (@(Get-FuCalls $f 'SetStepState' | ForEach-Object { '{0}:{1}' -f $_[1], $_[2] }) -join ',')
    Assert-Equal $false (Get-FuLast $f 'SetCloseGuard')[1]

    Invoke-FlashUiAction $ctx 'back'
    Assert-Equal 'select' $ctx.State.Phase
    Assert-Equal $script:FlashUiPageSelect (Get-FuLast $f 'ShowPage')[1]
}

Test-Case '書き込み: 下の欄には字下げしていない行 (いま何をしているか) を出し、字下げした案内と薄い行は出さない' {
    $w = New-FuContext 'LisM'
    $f = $w.Form
    $ctx = $w.Ctx
    $w.Children.Enqueue((New-FuChild @('ファームウェア: lism_right_central_trackball.uf2', '  nRF52840 / 196 ブロック', '',
                'ブートローダのドライブを待っています...', '  左手側は Q、右手側は P を押したまま USB ケーブルを挿す', '  (想定どおりの行)') 0 $false))
    Invoke-FlashUiAction $ctx 'start'
    Update-FlashUiTick $ctx
    Assert-Equal 'ブートローダのドライブを待っています...  (0:00)' (Get-FuLast $f 'SetStatus')[1]
    $texts = @(Get-FuCalls $f 'AppendLog' | ForEach-Object { $_[1] })
    Assert-True ($texts -contains '  左手側は Q、右手側は P を押したまま USB ケーブルを挿す') 'ログには案内も出す'
}

Test-Case '書き込み: 最新は同じコミットの custom のタグからダウンロードする' {
    $w = New-FuContext 'LisM'
    $w.Children.Enqueue((New-FuChild @() 0 $true))
    $w.Children.Enqueue((New-FuChild @() 0 $true))
    Invoke-FlashUiAction $w.Ctx 'start'
    Assert-True ($w.Downloads[0] -like '* firmware-custom-aaaaaaa *') $w.Downloads[0]
}

Test-Case '書き込み: 失敗したら理由を出し、「再試行」で同じ手順からやり直す' {
    $w = New-FuContext 'LisM'
    $f = $w.Form
    $ctx = $w.Ctx
    $w.Children.Enqueue((New-FuChild @('失敗: 120 秒待ってもブートローダのドライブが見つかりませんでした。', '  リセットボタンを素早く 2 回押してください。') 1 $true))
    $w.Children.Enqueue((New-FuChild @('成功: ok') 0 $true))
    $w.Children.Enqueue((New-FuChild @('成功: ok') 0 $true))
    Invoke-FlashUiAction $ctx 'start'
    Update-FlashUiTick $ctx
    Assert-Equal 'failed' $ctx.State.Phase
    $banner = Get-FuLast $f 'SetBanner'
    Assert-True ($banner[2] -like '120 秒待っても*リセットボタンを素早く 2 回*再試行*') $banner[2]
    Assert-Equal $script:FlashUiLevelNg $banner[3]
    Assert-Equal 'True,True,False,True,False,False' ((Get-FuLast $f 'SetButtons')[1..6] -join ',')
    Invoke-FlashUiAction $ctx 'retry'
    Assert-Equal 2 $w.Commands.Count
    Assert-Equal $w.Commands[0] $w.Commands[1] '同じ手順'
    Update-FlashUiTick $ctx
    Update-FlashUiTick $ctx
    Assert-Equal 'done' $ctx.State.Phase
    Assert-Equal 1 $w.Downloads.Count 'ダウンロードはやり直さない'
}

Test-Case '書き込み: 待っている間に中止 → 子プロセスを止め、「再試行」でやり直せる' {
    $w = New-FuContext 'LisM'
    $ctx = $w.Ctx
    $child = New-FuChild @() 0 $false
    $w.Children.Enqueue($child)
    Invoke-FlashUiAction $ctx 'start'
    Invoke-FlashUiAction $ctx 'cancel'
    Assert-True $child.Killed '止めた'
    Update-FlashUiTick $ctx
    Assert-Equal 'cancelled' $ctx.State.Phase
    Assert-True $child.Disposed '片付けた'
    Assert-Equal $script:FlashUiStepFailed (Get-FuLast $w.Form 'SetStepState')[2]
    Assert-Equal 'cancelled' $ctx.State.Result
}

Test-Case '書き込み: BMP の設定リセットの後は「続ける」を待つ' {
    $w = New-FuContext 'torabo-tsuki-lp'
    $f = $w.Form
    $ctx = $w.Ctx
    Invoke-FlashUiAction $ctx 'option:mode:ResetBoth'
    for ($i = 0; $i -lt 4; $i++) { $w.Children.Enqueue((New-FuChild @('成功: ok') 0 $true)) }
    Invoke-FlashUiAction $ctx 'start'
    Update-FlashUiTick $ctx
    Assert-Equal 'pause' $ctx.State.Phase
    $banner = Get-FuLast $f 'SetBanner'
    Assert-True ($banner[2] -like '右手側の USB ケーブルを抜き*「続ける」*') $banner[2]
    Assert-Equal 'False,False,True,False,True,False' ((Get-FuLast $f 'SetButtons')[1..6] -join ',')
    Update-FlashUiTick $ctx
    Assert-Equal 1 $w.Commands.Count '「続ける」までは次へ進まない'
    Invoke-FlashUiAction $ctx 'continue'
    Assert-Equal 2 $w.Commands.Count
    Assert-True ($w.Commands[1] -like "*torabo_tsuki_lp_right_central.uf2' -Target 'BMP'*") $w.Commands[1]
    Update-FlashUiTick $ctx
    Assert-Equal 'run' $ctx.State.Phase '3 手順目 (左の設定リセット)'
    Update-FlashUiTick $ctx
    Assert-Equal 'pause' $ctx.State.Phase
    Invoke-FlashUiAction $ctx 'cancel'
    Assert-Equal 'cancelled' $ctx.State.Phase
    Invoke-FlashUiAction $ctx 'retry'
    Assert-True ($w.Commands[3] -like '*torabo_tsuki_lp_left_peripheral.uf2*') '中止の後の再試行は次の手順から'
    Update-FlashUiTick $ctx
    Assert-Equal 'done' $ctx.State.Phase
    Assert-True ((Get-FuLast $f 'SetBanner')[2] -like '*再ペアリング*') '設定リセットの後の案内'
}

Test-Case 'ダウンロード: 中止できる。失敗したら「再試行」でダウンロードからやり直す' {
    $w = New-FuContext 'LisM'
    $ctx = $w.Ctx
    $w.Form.Queue.Add('cancel') | Out-Null
    Invoke-FlashUiAction $ctx 'start'
    Assert-Equal 'cancelled' $ctx.State.Phase
    Assert-Equal 0 $w.Commands.Count

    $w.DownloadError = 'ダウンロードに失敗しました: https://example'
    Invoke-FlashUiAction $ctx 'retry'
    Assert-Equal 'failed' $ctx.State.Phase
    Assert-True ((Get-FuLast $w.Form 'SetBanner')[2] -like 'ダウンロードに失敗しました*') 'バナー'
    $w.DownloadError = ''
    $w.Children.Enqueue((New-FuChild @() 0 $true))
    Invoke-FlashUiAction $ctx 'retry'
    Assert-Equal 3 $w.Downloads.Count
    Assert-Equal 'run' $ctx.State.Phase
}

Test-Case '閉じる: 書き込み中なら子プロセスを止めて終わる。ダウンロード中に閉じても終わる' {
    $w = New-FuContext 'LisM'
    $child = New-FuChild @() 0 $false
    $w.Children.Enqueue($child)
    Invoke-FlashUiAction $w.Ctx 'start'
    Invoke-FlashUiAction $w.Ctx 'close'
    Assert-True $child.Killed '止めた'
    Assert-True $w.Ctx.State.Exit '終わる'

    $w2 = New-FuContext 'LisM'
    $w2.Form.Queue.Add('close') | Out-Null
    Invoke-FlashUiAction $w2.Ctx 'start'
    Assert-True $w2.Ctx.State.Exit '終わる'
}

Test-Case 'Keyball39: 台数ぶん flash-keyball.ps1 -Count 1、完了で KQ-mini へのつなぎ直しを案内' {
    $w = New-FuContext 'Keyball39'
    $ctx = $w.Ctx
    Assert-Equal 'count' ((Get-FuLast $w.Form 'AddOptionGroup')[1])
    Invoke-FlashUiAction $ctx 'option:count:1'
    Assert-Equal 1 $ctx.State.Count
    $w.Children.Enqueue((New-FuChild @('完了: 書き込みました。') 0 $true))
    Invoke-FlashUiAction $ctx 'start'
    Assert-True ($w.Commands[0] -like "*flash-keyball.ps1' -Path 'C:\fw\keyball_keyball39_via.hex' -Count '1'*") $w.Commands[0]
    Update-FlashUiTick $ctx
    Assert-Equal 'done' $ctx.State.Phase
    Assert-True ((Get-FuLast $w.Form 'SetBanner')[2] -like '*KQ-mini に接続し直して*') '案内'
    Assert-Equal 1 $w.Saved[$w.Saved.Count - 1].KeyballCount
}

Test-Case '続けて届いた操作: 機種・ビルド・絞り込みは最後のものだけ' {
    $a = @(Get-FlashUiCoalescedActions @('keyboard:LisM', 'option:mode:Right', 'keyboard:roBa', 'build:a', 'build:b', '', 'start'))
    Assert-Equal 'option:mode:Right,keyboard:roBa,build:b,start' ($a -join ',')
    Assert-Equal 0 @(Get-FlashUiCoalescedActions @()).Count
}

Test-Case '一覧が取れないとき: 前回の一覧・最新だけを、理由と一緒に出す' {
    $w = New-FuContext 'LisM'
    $ctx = $w.Ctx
    $ctx.GetBuilds = { param($Repo) @{ Builds = @(); Source = 'fallback'; Message = 'GitHub に接続できませんでした。 最新のビルドだけ選べます。'; Level = 3; FetchedAt = $null } }
    Invoke-FlashUiAction $ctx 'refresh'
    $message = Get-FuLast $w.Form 'SetBuildsMessage'
    Assert-True ($message[1] -like 'GitHub に接続できませんでした*ビルドがありません*') $message[1]
    Assert-Equal 3 $message[2]
    Assert-Equal '最新だけ' (Get-FuLast $w.Form 'SetSource')[1]
    Assert-Equal $false (Get-FuLast $w.Form 'SetStartEnabled')[1]
}
