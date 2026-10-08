<#
.SYNOPSIS
    接続したキーボードの設定 (キーマップ・トラックボール) が、意図した通り (LisM 基準) になっているかを検査します。

.DESCRIPTION
    tools/expected/*.json (submodule のキーマップ・overlay・keymap.c から生成した期待値) と、次の 2 つの方法で比べます。

    読み出し検査 (キーボードの設定を読み出して比べる。設定は書き換えない)
      - Keyboard Quantizer Mini: Vial でキーマップ・タップホールド設定・タップダンス・キーオーバーライド・マクロ
      - Keyball39 (PC に直結): VIA でキーマップ・Ball availability・CPI / スクロール / AML (しきい値を含む) の設定
      - ZMK (LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa / torabo-tsuki-lp): ZMK Studio 版の右手側を USB で
        つなぐと、キーマップ

    実動作テスト (テスト用のウィンドウで、キーを押す・ボールを転がす)
      - BASE レイヤーのキーのタップ
      - レイヤー・ビヘイビア: レイヤーの移動 (押したまま)、長押し (mod-tap)、モッドモーフ、タップダンス、
        &to での切り替え、コンボ。手順と期待する入力を、キーボードの図・レイヤーの帯・キーキャップで表示する
      - AML のクリック、Shift + クリック、AML の Ctrl / Shift での解除、スクロールの向き、AML のタイムアウト、
        AML のしきい値 (わずかな動きでは発動しない)
      - トラックボールの正規化: X/Y の比率 (楕円補正。傾きは補正しない)、キーボード間の速さ (LisM 基準)。
        overlay / config.h に入れる値 (今の値に補正を掛けた値) を出す

    結果は PASS / FAIL / WARN / SKIP で表示し、tools/.cache/keyboard-check/reports/ にも保存します。

    レイヤーの動きを見る (-Mode Trace。ZMK のみ。合否は出さない)
      - 右手側にログ版のファーム (*_logging.uf2) を書き込んで USB でつなぐと、自由に押したキーごとに、有効なレイヤー・
        &trans のフォールスルー・決まったレイヤーとバインディング・ホールドタップの判定・タップダンスの回数・
        モッドモーフの分岐・送ったキーを、キーボードの図と時系列で表示する。ログは tools/.cache/keyboard-check/trace/ に保存できる

    タップホールドのタイミングを見る (-Mode HoldTap。ZMK のみ。合否は出さない)
      - 右手側にログ版のファーム (*_logging.uf2) を書き込んで USB でつなぐと、hold-tap のキー (&mt / &lt) を押した
        瞬間から、押したキー・PC に届く入力・tapping-term と判定の時刻を、時刻を横軸にしたグラフにリアルタイムに出す。
        離す時刻ごとの結果と flavor ごとの比較の帯も出し、flavor と tapping-term を変えると計算し直す

.PARAMETER Keyboard
    機種 (KqMini / Keyball39 / LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa / torabo-tsuki-lp)。省略するとメニューで選びます。
    KqMini は、Keyboard Quantizer Mini に Keyball39 をつないだ状態です。

.PARAMETER Mode
    All (読み出し検査と実動作テスト) / Readout (読み出し検査だけ) / Interactive (実動作テストだけ) /
    Trace (レイヤーの動きを見る。ZMK のログ版ファームのログから、押したキーのレイヤーの遷移と解決を表示する。合否は出さない) /
    HoldTap (タップホールドのタイミングを見る。ZMK のログ版ファームで、選んだキーの組み合わせ (&mt / &lt のキーと、一緒に押すキー) を押したときの判定を、時刻のグラフにリアルタイムに出す。合否は出さない)。

.PARAMETER Section
    実動作テストの範囲。All / Keys (キーのタップ) / Behaviors (レイヤー・タップダンス・モッドモーフ・コンボ) /
    Trackball (AML・スクロール) / Calibrate (トラックボールの正規化)。

.PARAMETER Ball
    LisM のトラックボールの位置 (right / left / both)。省略すると尋ねます。

.PARAMETER Port
    ZMK Studio (-Mode Trace / HoldTap ではログ版ファーム) の COM ポート (例: COM5)。省略すると自動で探します。

.PARAMETER Report
    結果を保存するファイル。省略すると tools/.cache/keyboard-check/reports/ に保存します。

.PARAMETER Speed
    トラックボールの正規化で、速さも計測します。省略すると、メニューで選んで始めたとき (-Keyboard か -Mode を
    省略したとき) は尋ねます。両方を指定したときは計測しません。

.PARAMETER Diameter
    ボールの直径 (mm)。速さを実効 CPI (指の移動量あたりの速さ) で比べるのに使います。

.PARAMETER SpeedReference
    速さの基準 (実効 CPI)。省略すると、前に LisM で計測した値を使います。

.PARAMETER CalibStrength
    楕円補正の強さ (0〜100、既定 100)。50 なら、測ったずれの半分 (対数で) だけ直す値を出します。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\keyboard-check.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\keyboard-check.ps1 -Keyboard KUKEY42 -Mode Interactive -Section Calibrate

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\keyboard-check.ps1 -Keyboard LisM -Mode Interactive -Section Behaviors

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\keyboard-check.ps1 -Keyboard LisM -Mode Trace

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\keyboard-check.ps1 -Keyboard LisM -Mode HoldTap
#>
[CmdletBinding()]
param(
    [ValidateSet('KqMini', 'Keyball39', 'LisM', 'AroundFortyRB', 'KUKEY42', 'Pyuron', 'roBa', 'torabo-tsuki-lp')]
    [string]$Keyboard,

    [ValidateSet('All', 'Readout', 'Interactive', 'Trace', 'HoldTap')]
    [string]$Mode,

    [ValidateSet('All', 'Keys', 'Behaviors', 'Trackball', 'Calibrate')]
    [string]$Section = 'All',

    [ValidateSet('right', 'left', 'both')]
    [string]$Ball,

    [string]$Port,

    [string]$Report,

    [switch]$Speed,

    [double]$Diameter = 0,

    [double]$SpeedReference = 0,

    [ValidateRange(0, 100)]
    [int]$CalibStrength = 100,

    # テスト用: 期待値のディレクトリ
    [string]$ExpectedDir
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# このスクリプトは tools\scripts にある。lib・expected・.cache は tools の下
$toolsDir = Split-Path -Parent $PSScriptRoot
$lib = Join-Path $toolsDir 'lib\keyboard-check'
. (Join-Path $lib 'expected.ps1')
. (Join-Path $lib 'results.ps1')
. (Join-Path $lib 'rawhid.ps1')
. (Join-Path $lib 'qmk.ps1')
. (Join-Path $lib 'zmk-studio.ps1')
. (Join-Path $lib 'input-eval.ps1')
. (Join-Path $lib 'behavior-eval.ps1')
. (Join-Path $lib 'trackball-calib.ps1')
. (Join-Path $lib 'input-test.ps1')
. (Join-Path $lib 'behavior-test.ps1')
. (Join-Path $lib 'zmk-log.ps1')
. (Join-Path $lib 'layer-trace.ps1')
. (Join-Path $lib 'hold-tap-sim.ps1')
. (Join-Path $lib 'hold-tap.ps1')
. (Join-Path $lib 'hold-tap-ui.ps1')

if (-not $ExpectedDir) {
    $ExpectedDir = Join-Path $toolsDir 'expected'
}
$cacheDir = Join-Path $toolsDir '.cache\keyboard-check'
$calibCache = Join-Path $cacheDir 'trackball.json'
$isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

$common = Get-KcExpected 'common' $ExpectedDir
$boards = @(
    @{ Key = 'KqMini'; Id = 'kq-mini'; Label = 'Keyboard Quantizer Mini + Keyball39' },
    @{ Key = 'Keyball39'; Id = 'keyball39'; Label = 'Keyball39 (PC に直結)' },
    # Product: ZMK Studio のデバイス名 (期待値の device.product = CONFIG_ZMK_KEYBOARD_NAME)
    @{ Key = 'LisM'; Id = 'lism'; Label = 'LisM'; Product = 'LisM' },
    @{ Key = 'AroundFortyRB'; Id = 'aroundfortyrb'; Label = 'AroundFortyRB'; Product = 'AroundFortyRB' },
    @{ Key = 'KUKEY42'; Id = 'kukey42'; Label = 'KUKEY42'; Product = 'KUKEY42' },
    @{ Key = 'Pyuron'; Id = 'pyuron'; Label = 'Pyuron'; Product = 'Pyuron' },
    @{ Key = 'roBa'; Id = 'roba'; Label = 'roBa'; Product = 'roBa' },
    @{ Key = 'torabo-tsuki-lp'; Id = 'torabo-tsuki-lp'; Label = 'torabo-tsuki-lp'; Product = 'torabo-tsuki' }
)

function Read-KcChoice([string]$Prompt, [int]$Count, [int]$Default) {
    while ($true) {
        $answer = Read-Host ('{0} [{1}]' -f $Prompt, $Default)
        if (-not $answer) {
            return $Default
        }
        $n = 0
        if ([int]::TryParse($answer.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Count) {
            return $n
        }
        Write-Host ('1〜{0} の番号を入れてください。' -f $Count) -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# 接続中のデバイス
# ---------------------------------------------------------------------------

$found = @{ KqMini = @(); Keyball = @(); StudioPorts = @(); StudioNames = @{}; ZmkUsb = @() }
if ($isWindowsHost -and $Mode -ne 'Trace' -and $Mode -ne 'HoldTap') {
    Write-Host '接続中のキーボードを探しています...'
    # Find-* は配列をそのまま返す (return , $x) ので、@() で包まずに受け取る
    $found.KqMini = Find-KcRawHidInterface -Vid 'FEED' -ProductId '999C'
    $found.Keyball = Find-KcRawHidInterface -Vid '5957' -ProductHighByte 2
    $found.ZmkUsb = Find-KcZmkUsbDevice
    $ports = Find-KcStudioPort
    if ($Port) {
        $ports = @([pscustomobject]@{ Port = $Port; Name = $Port; DeviceId = '' })
    }
    $found.StudioPorts = $ports
    foreach ($p in $ports) {
        $t = $null
        try {
            $t = Open-KcStudioPort $p.Port
            $info = Read-KcStudioDeviceInfo (New-KcStudioSession $t) 1500
            $found.StudioNames[$p.Port] = $info.Name
        } catch {
            $found.StudioNames[$p.Port] = ''
        } finally {
            Close-KcStudioPort $t
        }
    }
}

function Get-KcDetection($Board) {
    switch ($Board.Key) {
        'KqMini' { if ($found.KqMini.Count -gt 0) { return '検出: KQ-mini' } }
        'Keyball39' { if ($found.Keyball.Count -gt 0) { return '検出: Keyball39 (VIA)' } }
        default {
            foreach ($p in $found.StudioPorts) {
                if ([string]::Equals($found.StudioNames[$p.Port], $Board.Product, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return ('検出: Studio 版 {0}' -f $p.Port)
                }
            }
        }
    }
    return ''
}

# ---------------------------------------------------------------------------
# 機種と内容の選択
# ---------------------------------------------------------------------------

# メニューで選んだときは、トラックボールの正規化で速さも測るかを尋ねる (-Keyboard と -Mode を両方指定したときは -Speed で決める)。
# メニューで $Keyboard と $Mode が埋まる前に決めておく
$askSpeed = -not ($Keyboard -and $Mode)

if (-not $Keyboard) {
    Write-Host ''
    Write-Host '検査するキーボード:'
    $default = 0
    for ($i = 0; $i -lt $boards.Count; $i++) {
        $d = Get-KcDetection $boards[$i]
        if ($d -and $default -eq 0) {
            $default = $i + 1
        }
        $line = '  {0}. {1}' -f ($i + 1), $boards[$i].Label
        if ($d) {
            $line += ' (' + $d + ')'
        }
        Write-Host $line
    }
    if ($found.ZmkUsb.Count -gt 0 -and $found.StudioPorts.Count -eq 0) {
        Write-Host '  (USB でつながった ZMK キーボードがあります。Studio 版ではないため、キーマップの読み出しはできません)' -ForegroundColor DarkGray
    }
    if ($default -eq 0) {
        $default = 1
    }
    $Keyboard = $boards[(Read-KcChoice '番号' $boards.Count $default) - 1].Key
}
$board = @($boards | Where-Object { $_.Key -eq $Keyboard })[0]
$expected = Get-KcExpected $board.Id $ExpectedDir

$sections = @()
if (-not $Mode) {
    Write-Host ''
    Write-Host '検査の内容:'
    Write-Host '  1. 読み出し検査 + 実動作テスト'
    Write-Host '  2. 読み出し検査だけ'
    Write-Host '  3. 実動作テストだけ (キー・レイヤー・トラックボール・正規化)'
    Write-Host '  4. トラックボールの正規化だけ (楕円・速さ)'
    Write-Host '  5. レイヤー・タップダンス・モッドモーフ・コンボだけ'
    Write-Host '  6. レイヤーの動きを見る (ZMK のログ版ファームで、自由に押したキーのレイヤーの遷移と解決を表示)'
    Write-Host '  7. タップホールドのタイミングを見る (ZMK のログ版ファームで、選んだキーの組み合わせの判定をリアルタイムに表示)'
    switch (Read-KcChoice '番号' 7 1) {
        1 { $Mode = 'All' }
        2 { $Mode = 'Readout' }
        3 { $Mode = 'Interactive' }
        4 { $Mode = 'Interactive'; $Section = 'Calibrate' }
        5 { $Mode = 'Interactive'; $Section = 'Behaviors' }
        6 { $Mode = 'Trace' }
        7 { $Mode = 'HoldTap' }
    }
}
if ($Mode -ne 'Readout' -and $Mode -ne 'Trace' -and $Mode -ne 'HoldTap') {
    if ($Section -eq 'All') {
        $sections = @('Keys', 'Behaviors', 'Trackball', 'Calibrate')
    } else {
        $sections = @($Section)
    }
}

# レイヤーの動きを見る (ログ版ファーム)。合否は出さない
if ($Mode -eq 'Trace') {
    if ($expected.kind -ne 'zmk') {
        Write-Host ''
        Write-Host ('「レイヤーの動きを見る」は ZMK のキーボードだけです ({0} は対象外)。' -f $board.Label) -ForegroundColor Yellow
        Write-Host 'KQ-mini のレイヤーやタップダンスは、「5. レイヤー・タップダンス・モッドモーフ・コンボだけ」で確かめてください。'
        exit 0
    }
    if (-not $isWindowsHost) {
        Write-Host 'Windows でのみ動きます。' -ForegroundColor Yellow
        exit 0
    }
    Write-Host ''
    Write-Host ('{0} のログ版ファームのログから、押したキーのレイヤーの遷移と解決を表示します。' -f $expected.name)
    Write-Host 'ウィンドウを閉じるか「終了」を押すと終わります。'
    try {
        $saved = Invoke-KcLayerTrace -Expected $expected -Common $common -CacheDir $cacheDir -Port $Port
        if ($saved) {
            Write-Host ('保存しました: {0}' -f $saved)
        }
    } catch {
        Write-Host ('失敗: {0}' -f $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
    exit 0
}

# タップホールドのタイミングを見る (ログ版ファーム)。合否は出さない
if ($Mode -eq 'HoldTap') {
    if ($expected.kind -ne 'zmk') {
        Write-Host ''
        Write-Host ('「タップホールドのタイミングを見る」は ZMK のキーボードだけです ({0} は対象外)。' -f $board.Label) -ForegroundColor Yellow
        exit 0
    }
    if (-not $isWindowsHost) {
        Write-Host 'Windows でのみ動きます。' -ForegroundColor Yellow
        exit 0
    }
    Write-Host ''
    Write-Host ('{0} のログ版ファームのログから、押した hold-tap の判定をリアルタイムに表示します。' -f $expected.name)
    Write-Host 'ウィンドウを閉じるか「閉じる」を押すと終わります。'
    try {
        Invoke-KcHoldTap -Expected $expected -Port $Port
    } catch {
        Write-Host ('失敗: {0}' -f $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
    exit 0
}

$results = New-KcResultList
$sourceText = (@($expected.sources) | ForEach-Object { '{0} @ {1}' -f $_.submodule, $_.commit.Substring(0, 7) }) -join ', '
Write-Host ''
Write-Host ('機種: {0}   期待値: tools/expected/{1}.json ({2})' -f $board.Label, $board.Id, $sourceText)


# ---------------------------------------------------------------------------
# 読み出し検査
# ---------------------------------------------------------------------------

function Invoke-KcQmkReadoutSafe([string]$Category, $Iface, [scriptblock]$Body) {
    try {
        if (Test-KcRawHidBusy $Iface.Path) {
            [void](Add-KcResult -Results $results -Category $Category -Item '読み出し' -Status SKIP -Actual 'ほかのアプリが通信中' `
                    -Hint 'Vial / VIA / Remap などを閉じてから再実行してください')
            return
        }
        $query = New-KcRawHidQuery $Iface.Path
        & $Body $query
    } catch {
        [void](Add-KcResult -Results $results -Category $Category -Item '読み出し' -Status SKIP -Actual ('失敗: ' + $_.Exception.Message) `
                -Hint 'USB を挿し直して、Vial / VIA を閉じてから再実行してください')
    }
}

if ($Mode -ne 'Interactive' -and $Mode -ne 'Trace' -and $Mode -ne 'HoldTap') {
    Write-Host '読み出し検査をしています...'
    switch ($board.Key) {
        'KqMini' {
            if ($found.KqMini.Count -eq 0) {
                [void](Add-KcResult -Results $results -Category 'KQ-mini' -Item '読み出し' -Status SKIP -Actual '見つかりません' `
                        -Hint 'KQ-mini を PC に USB でつないでから再実行してください')
            } else {
                Invoke-KcQmkReadoutSafe 'KQ-mini' $found.KqMini[0] {
                    param($q)
                    Invoke-KcKqMiniReadout -Query $q -Expected $expected -Common $common -Results $results
                }
            }
            if ($found.Keyball.Count -gt 0) {
                $kbExp = Get-KcExpected 'keyball39' $ExpectedDir
                Invoke-KcQmkReadoutSafe 'Keyball39' $found.Keyball[0] {
                    param($q)
                    Invoke-KcKeyballReadout -Query $q -Expected $kbExp -Common $common -Results $results
                }
            } else {
                [void](Add-KcResult -Results $results -Category 'Keyball39' -Item '読み出し' -Status SKIP -Actual 'KQ-mini 経由では読めません' `
                        -Hint 'Keyball の設定 (キーマップ・CPI など) は、Keyball を PC に直結して「Keyball39 (PC に直結)」で検査してください')
            }
        }
        'Keyball39' {
            if ($found.Keyball.Count -eq 0) {
                $hint = 'Keyball を PC に直結してから再実行してください'
                if ($found.KqMini.Count -gt 0) {
                    $hint = 'KQ-mini 経由では Keyball の VIA に届きません。Keyball を PC に直結してから再実行してください'
                }
                [void](Add-KcResult -Results $results -Category 'Keyball39' -Item '読み出し' -Status SKIP -Actual '見つかりません' -Hint $hint)
            } else {
                Invoke-KcQmkReadoutSafe 'Keyball39' $found.Keyball[0] {
                    param($q)
                    Invoke-KcKeyballReadout -Query $q -Expected $expected -Common $common -Results $results
                }
            }
        }
        default {
            $zmkExpected = @{}
            foreach ($b in @($boards | Where-Object { $_.ContainsKey('Product') })) {
                $e = Get-KcExpected $b.Id $ExpectedDir
                $zmkExpected[[string]$e.device.product] = $e
            }
            $ports = @($found.StudioPorts)
            $match = @($ports | Where-Object { [string]::Equals($found.StudioNames[$_.Port], $board.Product, [System.StringComparison]::OrdinalIgnoreCase) })
            if ($match.Count -gt 0) {
                $ports = $match
            }
            if ($ports.Count -eq 0) {
                $artifacts = (@($expected.device.studio_artifacts) -join ' / ')
                [void](Add-KcResult -Results $results -Category ('{0} (Studio)' -f $expected.name) -Item 'キーマップの読み出し' -Status SKIP `
                        -Actual 'ZMK Studio 版が USB で見つかりません' -Hint (
                        "キーマップを読み出すには、右手側に ZMK Studio 版 ($artifacts) を書き込み、USB でつないでください。`n" +
                        'tools/flash.cmd で機種を選び、書き込む内容を「右手側 (セントラル) だけ」、右手側の版を「Studio 版」にして書き込んでください。実動作テストは Studio 版でなくてもできます'))
            } else {
                $t = $null
                try {
                    $t = Open-KcStudioPort $ports[0].Port
                    $chosen = Invoke-KcZmkReadout -Session (New-KcStudioSession $t) -ExpectedByName $zmkExpected -Common $common -Results $results -Preferred $expected
                    if ($null -ne $chosen -and $chosen.id -ne $expected.id) {
                        $expected = $chosen
                    }
                } catch {
                    [void](Add-KcResult -Results $results -Category ('{0} (Studio)' -f $expected.name) -Item 'キーマップの読み出し' -Status SKIP `
                            -Actual ('失敗: ' + $_.Exception.Message) -Hint 'ブラウザの ZMK Studio を閉じ、USB を挿し直してから再実行してください')
                } finally {
                    Close-KcStudioPort $t
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 実動作テスト
# ---------------------------------------------------------------------------

if ($sections.Count -gt 0) {
    if (-not $isWindowsHost) {
        [void](Add-KcResult -Results $results -Category ('{0}: 実動作' -f $expected.name) -Item '実動作テスト' -Status SKIP -Actual 'Windows でのみ動きます')
    } else {
        $tb = $expected.interactive.trackball
        $balls = @($tb.balls)
        if ([bool]$tb.ask_balls -and ($sections -contains 'Trackball' -or $sections -contains 'Calibrate')) {
            if ($Ball) {
                $balls = @('right', 'left')
                if ($Ball -ne 'both') { $balls = @($Ball) }
            } else {
                Write-Host ''
                Write-Host ('{0} のトラックボールの位置:' -f $expected.name)
                Write-Host '  1. 右手側'
                Write-Host '  2. 左手側'
                Write-Host '  3. 両方'
                switch (Read-KcChoice '番号' 3 1) {
                    1 { $balls = @('right') }
                    2 { $balls = @('left') }
                    3 { $balls = @('right', 'left') }
                }
            }
        }
        $doSpeed = [bool]$Speed
        $dia = $null
        if ($sections -contains 'Calibrate') {
            if (-not $Speed -and $askSpeed) {
                Write-Host ''
                Write-Host 'トラックボールの速さも計測しますか? (ボールに印を付けて、決まった回数だけ回します。LisM を基準に、ほかの機種の倍率の推奨値を出します)'
                $doSpeed = (Read-KcChoice '1. しない  2. する' 2 1) -eq 2
            }
            if ($doSpeed) {
                if ($Diameter -gt 0) {
                    $dia = $Diameter
                } else {
                    $cached = Read-KcCalibCache $calibCache
                    $prev = @($cached | Where-Object { $_.keyboard -eq $expected.id -and $null -ne (Get-KcProp $_ 'diameter_mm' $null) })
                    $defDia = ''
                    if ($prev.Count -gt 0) {
                        $defDia = [string]$prev[$prev.Count - 1].diameter_mm
                    } elseif ($expected.id -eq 'keyball39' -or $expected.id -eq 'kq-mini') {
                        $defDia = '34'
                    }
                    $answer = Read-Host ('ボールの直径 (mm、分からなければ空のまま Enter) [{0}]' -f $defDia)
                    if (-not $answer) {
                        $answer = $defDia
                    }
                    $v = 0.0
                    if ($answer -and [double]::TryParse($answer, [ref]$v) -and $v -gt 0) {
                        $dia = $v
                    }
                }
            }
        }
        $options = @{
            Sections = $sections; Balls = $balls; Speed = $doSpeed; Diameter = $dia; Strength = ($CalibStrength / 100.0)
            SpeedReference = $null; CachePath = $calibCache; ReadoutMismatch = $script:KcZmkMismatch
        }
        if ($SpeedReference -gt 0) {
            $options.SpeedReference = $SpeedReference
        }
        Write-Host ''
        Write-Host 'テスト用のウィンドウを開きます。ウィンドウの指示に従って、キーを押したりボールを転がしたりしてください。'
        Write-Host '(ウィンドウを閉じるか「中止」を押すと、そこまでの結果を表示します)'
        try {
            [void](Invoke-KcInputTest -Expected $expected -Common $common -Results $results -Options $options)
        } catch {
            [void](Add-KcResult -Results $results -Category ('{0}: 実動作' -f $expected.name) -Item '実動作テスト' -Status SKIP `
                    -Actual ('失敗: ' + $_.Exception.Message))
        }
    }
}

# ---------------------------------------------------------------------------
# 結果
# ---------------------------------------------------------------------------

# 設定ファイルどうしの整合 (参考)
foreach ($c in @($expected.consistency)) {
    $st = 'INFO'
    if ($c.level -eq 'warn') {
        $st = 'WARN'
    }
    [void](Add-KcResult -Results $results -Category ('{0}: 設定ファイル (参考)' -f $expected.name) -Item $c.message -Status $st -Reference)
}

Write-KcSummary $results ('{0} の検査結果' -f $expected.name)
if (-not $Report) {
    $Report = Join-Path $cacheDir ('reports\{0}-{1}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $expected.id)
}
try {
    Export-KcReport $results $Report @(
        ('keyboard-check {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
        ('機種: {0}' -f $expected.name),
        ('期待値: tools/expected/{0}.json ({1})' -f $expected.id, $sourceText))
    Write-Host ('結果を保存しました: {0}' -f $Report)
} catch {
    Write-Host ('結果を保存できませんでした: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
}
exit (Get-KcExitCode $results)
