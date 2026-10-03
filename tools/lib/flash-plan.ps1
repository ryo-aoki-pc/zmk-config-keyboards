# 書き込みツールの機種の表と、書き込む手順 (どのファイルを、どの側に、どの順で書くか) を決める関数。
# 純粋関数だけなので、Windows 以外でもテストできる。
# flash.ps1 (GUI) / flash-zmk.ps1 / flash-keyball.ps1 / flash-kq-mini.ps1 から dot-source して使う。

# 機種。Kind は zmk / keyball / kqmini、Mcu は下の $FlashMcus のキー。
# ZMK の Right / Left は各リポジトリの build.yaml の artifact-name。{v} は LisM のトラックボール有無
# (trackball / non_trackball)。セントラルの ZMK Studio 対応版は Right の後ろに _studio、ログ版は _logging が付く。
# Keyball39 / KQ-mini の Asset は、それぞれの CI がリリースに置くファイルの名前。
$script:FlashKeyboards = [ordered]@{
    LisM              = @{ Kind = 'zmk'; Repo = 'ryo-aoki-pc/zmk-config-LisM'; Right = 'lism_right_central_{v}'; Left = 'lism_left_peripheral_{v}'; Mcu = 'XIAO' }
    AroundFortyRB     = @{ Kind = 'zmk'; Repo = 'ryo-aoki-pc/zmk-config-AroundFortyRB'; Right = 'AroundForty-RB_right_central'; Left = 'AroundForty-RB_left_peripheral'; Mcu = 'XIAO' }
    KUKEY42           = @{ Kind = 'zmk'; Repo = 'ryo-aoki-pc/zmk-config-KUKEY42'; Right = 'KUKEY42_right_central'; Left = 'KUKEY42_left_peripheral'; Mcu = 'XIAO' }
    Pyuron            = @{ Kind = 'zmk'; Repo = 'ryo-aoki-pc/zmk-config-Pyuron'; Right = 'Pyuron_right_central'; Left = 'Pyuron_left_peripheral'; Mcu = 'XIAO' }
    roBa              = @{ Kind = 'zmk'; Repo = 'ryo-aoki-pc/zmk-config-roBa'; Right = 'roBa_right_central'; Left = 'roBa_left_peripheral'; Mcu = 'XIAO' }
    'torabo-tsuki-lp' = @{ Kind = 'zmk'; Repo = 'ryo-aoki-pc/zmk-keyboard-torabo-tsuki-lp'; Right = 'torabo_tsuki_lp_right_central'; Left = 'torabo_tsuki_lp_left_peripheral'; Mcu = 'BMP' }
    Keyball39         = @{ Kind = 'keyball'; Repo = 'ryo-aoki-pc/keyball'; Asset = 'keyball_keyball39_via.hex'; Mcu = 'ProMicro' }
    'KQ-mini'         = @{ Kind = 'kqmini'; Repo = 'ryo-aoki-pc/vial-qmk-kq-mini'; Asset = 'sekigon_keyboard_quantizer_mini_vial.uf2'; Mcu = 'RP2040' }
}

# マイコンごとの設定。Target は flash-uf2.ps1 の -Target、SettingsReset は設定リセットの artifact-name。
# Prepare は 1 回の書き込みの前、AfterReset は設定リセットを書き込んだ後の案内 ({0} は「右手側」など)。
$script:FlashMcus = @{
    XIAO     = @{
        Label         = 'Seeed XIAO nRF52840'
        Target        = 'nRF52840'
        SettingsReset = 'settings_reset-seeeduino_xiao_ble-zmk'
        Prepare       = '{0}の XIAO をブートローダにしてください (もう片側には触れないでください)。左手側は Q、右手側は P を押したまま USB ケーブルを挿すか、リセットボタンを素早く 2 回押します。'
        AfterReset    = ''
    }
    # BLE Micro Pro Boost は電源スイッチを OFF にして USB をつなぐとブートローダが起動する。
    # 書き込んだファームウェアは、USB を抜いてスイッチを ON にし、USB を差し直したときに動く。
    BMP      = @{
        Label         = 'BLE Micro Pro Boost'
        Target        = 'BMP'
        SettingsReset = 'settings_reset-bmp_boost-zmk'
        Prepare       = '{0}の電源スイッチを OFF にしてから USB ケーブルでつないでください (もう片側の USB ケーブルは抜いてください)。'
        AfterReset    = '{0}の USB ケーブルを抜き、電源スイッチを ON にしてから USB ケーブルを差し直してください。設定リセットが動きます。数秒待ったら USB ケーブルを抜き、電源スイッチを OFF に戻してください。'
    }
    ProMicro = @{
        Label   = 'Pro Micro (ATmega32U4)'
        Prepare = 'Keyball の片側を KQ-mini から外し、USB ケーブルで PC に直接つないでください。つないだら、リセットスイッチを押してブートローダを起動します (認識されなければ素早く 2 回。左手側は Q、右手側は P を押したまま USB ケーブルを挿してもよい)。ブートローダは約 8 秒で終わります。'
    }
    RP2040   = @{
        Label   = 'RP2040'
        Target  = 'RP2040'
        Prepare = 'KQ-mini を PC につないだままにしてください。自動でブートローダに切り替えます (切り替わらないときは、FUNC レイヤーの QK_BOOT キーを押してください)。'
    }
}

# 書き込む内容 (ZMK)
$script:FlashModes = [ordered]@{
    Both      = '左右に書き込む (右 → 左)'
    ResetBoth = '設定リセットしてから左右に書き込む (ペアリング情報も消えます)'
    Right     = '右手側 (セントラル) だけ'
    Left      = '左手側 (ペリフェラル) だけ'
    ResetOnly = '設定リセットだけ (右 → 左)'
}

# セントラル (右手側) の版。キーは artifact-name に付ける接尾辞
$script:FlashCentrals = [ordered]@{
    ''      = '通常版'
    studio  = 'Studio 版'
    logging = 'ログ版'
}

# LisM の左右のトラックボールの有無 (欄の見出しが「右手側のトラックボール」なので、選択肢は「あり / なし」)
$script:FlashVariants = [ordered]@{
    trackball     = 'あり'
    non_trackball = 'なし'
}

function Get-FlashKeyboard([string]$Keyboard) {
    if (-not $script:FlashKeyboards.Contains($Keyboard)) {
        throw "機種が正しくありません: $Keyboard"
    }
    return $script:FlashKeyboards[$Keyboard]
}

# LisM のようにトラックボールの有無で版が分かれる機種か
function Test-FlashHasVariants([string]$Keyboard) {
    $k = Get-FlashKeyboard $Keyboard
    return ($k.Kind -eq 'zmk' -and $k.Right.Contains('{v}'))
}

function Test-FlashModeHasCentral([string]$Mode) {
    return ($Mode -in @('Both', 'ResetBoth', 'Right'))
}

function Test-FlashModeHasPeripheral([string]$Mode) {
    return ($Mode -in @('Both', 'ResetBoth', 'Left'))
}

# 1 つの手順
function New-FlashStep([string]$Side, [string]$What, [string]$Asset, [string]$Runner, [string]$Target, [string]$Prepare,
    [string]$AfterReset = '', [bool]$IsReset = $false) {
    return [pscustomobject]@{
        Side       = $Side
        What       = $What
        Asset      = $Asset
        Runner     = $Runner
        Target     = $Target
        Prepare    = $Prepare
        AfterReset = $AfterReset
        IsReset    = $IsReset
        Pause      = $false
    }
}

# 書き込む手順の一覧。
#   ZMK: $Mode (Both / ResetBoth / Right / Left / ResetOnly)、$Central ('' / studio / logging)、$Right / $Left (LisM の版)
#   Keyball39: $Count 台 (1 台につき 1 手順。flash-keyball.ps1 -Count 1 を 1 回ずつ)
#   KQ-mini: 1 手順
# BMP の設定リセットのうち最後でないものは Pause (書き込んだ後、一度起動させてから次へ進む)
function Get-FlashPlan([string]$Keyboard, [string]$Mode = 'Both', [string]$Central = '', [string]$Right = 'trackball',
    [string]$Left = 'trackball', [int]$Count = 2) {
    $k = Get-FlashKeyboard $Keyboard
    $mcu = $script:FlashMcus[$k.Mcu]
    $steps = New-Object System.Collections.ArrayList

    if ($k.Kind -eq 'keyball') {
        if ($Count -lt 1) { $Count = 1 }
        for ($i = 1; $i -le $Count; $i++) {
            $side = if ($Count -gt 1) { '{0} 台目' -f $i } else { 'Keyball' }
            [void]$steps.Add((New-FlashStep $side 'ファームウェア' $k.Asset 'keyball' '' $mcu.Prepare))
        }
        return $steps.ToArray()
    }
    if ($k.Kind -eq 'kqmini') {
        [void]$steps.Add((New-FlashStep 'KQ-mini' 'ファームウェア' $k.Asset 'uf2' $mcu.Target $mcu.Prepare))
        return $steps.ToArray()
    }

    if (-not $script:FlashModes.Contains($Mode)) {
        throw "書き込む内容が正しくありません: $Mode"
    }
    if (-not $script:FlashCentrals.Contains($Central)) {
        throw "セントラルの版が正しくありません: $Central"
    }
    $centralName = $k.Right.Replace('{v}', $Right)
    if ($Central) {
        $centralName += '_' + $Central
    }
    $peripheralName = $k.Left.Replace('{v}', $Left)
    $reset = $mcu.SettingsReset + '.uf2'

    $rightReset = New-FlashStep '右手側' '設定リセット' $reset 'uf2' $mcu.Target ($mcu.Prepare -f '右手側') ($mcu.AfterReset -f '右手側') $true
    $rightMain = New-FlashStep '右手側' 'セントラル' "$centralName.uf2" 'uf2' $mcu.Target ($mcu.Prepare -f '右手側')
    $leftReset = New-FlashStep '左手側' '設定リセット' $reset 'uf2' $mcu.Target ($mcu.Prepare -f '左手側') ($mcu.AfterReset -f '左手側') $true
    $leftMain = New-FlashStep '左手側' 'ペリフェラル' "$peripheralName.uf2" 'uf2' $mcu.Target ($mcu.Prepare -f '左手側')

    switch ($Mode) {
        'Both' { $list = @($rightMain, $leftMain) }
        'ResetBoth' { $list = @($rightReset, $rightMain, $leftReset, $leftMain) }
        'Right' { $list = @($rightMain) }
        'Left' { $list = @($leftMain) }
        'ResetOnly' { $list = @($rightReset, $leftReset) }
    }
    for ($i = 0; $i -lt $list.Count; $i++) {
        $s = $list[$i]
        # 設定リセットのファームウェアにはキーの処理が無いので、それが動いている側は Q / P では切り替えられない
        if ($k.Mcu -eq 'XIAO' -and $i -gt 0 -and $list[$i - 1].IsReset -and $list[$i - 1].Side -eq $s.Side) {
            $s.Prepare = '{0}の XIAO をブートローダにしてください。設定リセットのファームウェアが動いているので、リセットボタンを素早く 2 回押します。' -f $s.Side
        }
        if ($s.IsReset -and $s.AfterReset -and $i -lt $list.Count - 1) {
            $s.Pause = $true
        }
        [void]$steps.Add($s)
    }
    return $steps.ToArray()
}

# 手順で使うファイルのうち、ビルドに無いもの ($AssetNames が $null なら、わからないので空)
function Get-FlashMissingAssets($Steps, $AssetNames) {
    if ($null -eq $AssetNames) {
        return @()
    }
    $names = @($AssetNames)
    $missing = New-Object System.Collections.ArrayList
    foreach ($s in @($Steps)) {
        if ($names -notcontains $s.Asset -and -not $missing.Contains($s.Asset)) {
            [void]$missing.Add($s.Asset)
        }
    }
    return $missing.ToArray()
}

# 画面のオプションの欄。Style は choices (縦に並べる) / segments (横に並べる)。
# Visible が $false の欄は隠す (その書き込む内容では使わないもの)
function Get-FlashOptionGroups([string]$Keyboard, [string]$Mode) {
    $k = Get-FlashKeyboard $Keyboard
    $groups = New-Object System.Collections.ArrayList
    if ($k.Kind -eq 'zmk') {
        $details = [ordered]@{
            Both      = '右手側 (セントラル) → 左手側 (ペリフェラル) の順'
            ResetBoth = '右 (設定リセット → セントラル) → 左 (設定リセット → ペリフェラル)'
            Right     = 'セントラルだけを書き直す'
            Left      = 'ペリフェラルだけを書き直す'
            ResetOnly = '左右の設定 (ペアリング情報も) を消す'
        }
        [void]$groups.Add([pscustomobject]@{
                Key = 'mode'; Caption = '書き込む内容'; Style = 'choices'; Visible = $true
                Keys = @($script:FlashModes.Keys); Labels = @($script:FlashModes.Values); Details = @($details.Values)
            })
        $hasCentral = Test-FlashModeHasCentral $Mode
        [void]$groups.Add([pscustomobject]@{
                Key = 'central'; Caption = '右手側 (セントラル) の版'; Style = 'segments'; Visible = $hasCentral
                Keys = @($script:FlashCentrals.Keys); Labels = @($script:FlashCentrals.Values)
                Details = @('ふだん使う版', 'ZMK Studio でキーマップを読み書きできる版', 'USB の COM ポートにデバッグログを出す版 (レイヤーの動きを見る用)')
            })
        if (Test-FlashHasVariants $Keyboard) {
            [void]$groups.Add([pscustomobject]@{
                    Key = 'right'; Caption = '右手側のトラックボール'; Style = 'segments'; Visible = $hasCentral
                    Keys = @($script:FlashVariants.Keys); Labels = @($script:FlashVariants.Values); Details = @('', '')
                })
            [void]$groups.Add([pscustomobject]@{
                    Key = 'left'; Caption = '左手側のトラックボール'; Style = 'segments'; Visible = (Test-FlashModeHasPeripheral $Mode)
                    Keys = @($script:FlashVariants.Keys); Labels = @($script:FlashVariants.Values); Details = @('', '')
                })
        }
    } elseif ($k.Kind -eq 'keyball') {
        [void]$groups.Add([pscustomobject]@{
                Key = 'count'; Caption = '書き込む台数'; Style = 'segments'; Visible = $true
                Keys = @('2', '1'); Labels = @('左右 (2 台)', '片側 (1 台)'); Details = @('左右に同じファームウェアを書く', '片側だけ書き直す')
            })
    }
    return $groups.ToArray()
}

# 子プロセス (powershell.exe -EncodedCommand) に渡すコマンド。出力を UTF-8 にしてからスクリプトを実行し、
# 終了コードをそのまま返す。$Arguments は名前 → 値 (文字列・数値・文字列の配列) の順序付きの表
function Format-FlashCommand([string]$Script, $Arguments) {
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add("& '" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Script) + "'")
    foreach ($name in @($Arguments.Keys)) {
        $value = $Arguments[$name]
        $quoted = @(foreach ($v in @($value)) {
                "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string]$v) + "'"
            })
        [void]$parts.Add('-' + $name + ' ' + ($quoted -join ','))
    }
    return ('$ProgressPreference = ''SilentlyContinue''; ' +
        'try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }; ' +
        'try { ' + ($parts -join ' ') + '; exit $LASTEXITCODE } ' +
        'catch { Write-Host (''失敗: '' + $_.Exception.Message); exit 1 }')
}

function ConvertTo-FlashEncodedCommand([string]$Command) {
    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
}

# 1 つの手順を実行するスクリプトと引数
function Get-FlashStepCommand($Step, [string]$Path, [string]$ToolsDir, [int]$WaitSeconds) {
    $arguments = [ordered]@{ Path = $Path }
    if ($Step.Runner -eq 'keyball') {
        $script = [System.IO.Path]::Combine($ToolsDir, 'flash-keyball.ps1')
        $arguments['Count'] = 1
    } else {
        $script = [System.IO.Path]::Combine($ToolsDir, 'flash-uf2.ps1')
        $arguments['Target'] = $Step.Target
    }
    $arguments['WaitSeconds'] = $WaitSeconds
    return (Format-FlashCommand $script $arguments)
}

# 子プロセスの 1 行の表示: -1 隠す / 0 ふつう / 1 成功 / 2 失敗 / 3 注意 / 4 薄く
function ConvertTo-FlashLogLevel([string]$Text, [bool]$IsError = $false) {
    if ($Text -match '^\s*#< CLIXML' -or $Text -match '^\s*<Objs ') { return -1 }
    if ($Text -match '^\s*失敗:') { return 2 }
    if ($Text -match '^\s*(成功|完了):') { return 1 }
    if ($Text -match '^\s*(警告|WARNING):' -or $Text -match 'avrdude が失敗' -or $Text -match '(?i)avrdude.*\berror\b') { return 3 }
    if ($Text -match '^\s+\(') { return 4 }
    return 0
}

# 手順が終わった後の次の状態: cancelled (中止) / failed / pause (BMP の設定リセット後) / next / done
function Get-FlashNextPhase($Steps, [int]$Index, [int]$ExitCode, [bool]$Killed) {
    if ($Killed) { return 'cancelled' }
    if ($ExitCode -ne 0) { return 'failed' }
    $list = @($Steps)
    if ($list[$Index].Pause) { return 'pause' }
    if ($Index -lt $list.Count - 1) { return 'next' }
    return 'done'
}
