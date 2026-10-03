<#
.SYNOPSIS
    Keyball39 (Pro Micro / caterina ブートローダ) に .hex ファームウェアを書き込みます。

.DESCRIPTION
    次の手順で、左右 2 台に同じファームウェアを書き込みます。
      1. .hex を指定しなければ、keyball のリリース (既定は firmware-latest = custom ブランチの最新ビルド。
         -Tag / -Pr で PR や過去のビルド) をダウンロードする
      2. .hex (Intel HEX) を検証する (チェックサム / 書き込み先がブートローダより前に収まるか)
      3. avrdude が無ければ、公式の Windows 版 (バージョン固定・SHA256 確認済み) を tools\.cache に
         ダウンロードする
      4. caterina ブートローダ (COM ポート) が現れるのを待ち、avrdude で書き込む。これを台数分くり返す

    caterina ブートローダは起動から約 8 秒で終了するので、COM ポートが現れたらすぐに書き込みます。
    Keyball は KQ-mini 経由では書き込めないので、PC に直接つないでください。

    tools\scripts\flash-keyball.cmd をダブルクリックすると、Keyball39 を選んだ状態で書き込みツールのウィンドウ (flash.ps1) が開きます。

.PARAMETER Path
    書き込む .hex ファイル。省略すると最新のファームウェアをダウンロードします。

.PARAMETER Avrdude
    使用する avrdude.exe のパス。省略すると tools\.cache にダウンロードした avrdude を使います。

.PARAMETER Count
    書き込む台数。既定は 2 (左右)。片側だけ書き直すときは 1。

.PARAMETER WaitSeconds
    1 台ごとに、ブートローダが現れるまで待つ秒数。

.PARAMETER Tag
    ダウンロードするリリースのタグ (例: firmware-custom-1a2b3c4)。既定は firmware-latest (custom の最新)。
    選べるタグは flash.ps1 -Keyboard Keyball39 -List で表示できます。

.PARAMETER Pr
    PR のビルド (firmware-pr-<番号>) を書き込みます。-Tag とは一緒に使えません。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash-keyball.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash-keyball.ps1 keyball_keyball39_via.hex -Count 1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\scripts\flash-keyball.ps1 -Pr 19
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [string]$Avrdude,

    [ValidateRange(1, 10)]
    [int]$Count = 2,

    [int]$WaitSeconds = 120,

    [string]$Tag,

    [int]$Pr = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# このスクリプトは tools\scripts にある。lib・expected・.cache は tools の下
$TOOLS_DIR = Split-Path -Parent $PSScriptRoot
. (Join-Path $TOOLS_DIR 'lib\firmware-release.ps1')
. (Join-Path $TOOLS_DIR 'lib\flash-plan.ps1')

$CACHE_DIR = Join-Path $TOOLS_DIR '.cache'

# ATmega32U4 (32 KB) の先頭 28 KB がアプリケーション領域。0x7000 以降は caterina ブートローダ。
$APP_END = 0x7000

# avrdude の公式 Windows 版 (https://github.com/avrdudes/avrdude/releases)
$AVRDUDE_VERSION = 'v8.3'
$AVRDUDE_URL = "https://github.com/avrdudes/avrdude/releases/download/$AVRDUDE_VERSION/avrdude-$AVRDUDE_VERSION-windows-x64.zip"
$AVRDUDE_SHA256 = '8630C7D8BB9682A1685AAA9AD42550AE1131C9D13528F0D20975368BA615E9B0'

# caterina ブートローダの USB VID:PID (QMK の util/udev/50-qmk.rules の Caterina 欄と同じ)
$CATERINA_IDS = @(
    '1209:2302',                            # Keyboardio Atreus 2 Bootloader
    '1B4F:9203', '1B4F:9205', '1B4F:9207',  # SparkFun Pro Micro / LilyPad
    '1FFB:0101',                            # Pololu A-Star 32U4
    '2341:0036', '2341:0037',               # Arduino Leonardo / Micro
    '239A:000C', '239A:000D', '239A:000E',  # Adafruit Feather / ItsyBitsy 32U4
    '2A03:0036', '2A03:0037'                # dog hunter Leonardo / Micro
)

function Stop-WithError([string]$Message) {
    Write-Host ''
    Write-Host "失敗: $Message" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Intel HEX の検証
# ---------------------------------------------------------------------------
# 問題があれば例外を投げる。問題なければ書き込むデータのバイト数と範囲を返す。
function Test-IntelHex([string]$File) {
    $lines = [System.IO.File]::ReadAllLines($File)
    $base = 0
    $dataBytes = 0
    $minAddr = [long]::MaxValue
    $maxEnd = [long]0
    $eof = $false
    for ($n = 0; $n -lt $lines.Length; $n++) {
        $line = $lines[$n].Trim()
        $lineNo = $n + 1
        if ($line.Length -eq 0) { continue }
        if ($eof) { throw "$lineNo 行目: EOF レコードの後にデータがあります。" }
        if ($line -notmatch '^:([0-9A-Fa-f]{2})+$' -or $line.Length -lt 11) {
            throw "$lineNo 行目: Intel HEX の行ではありません。"
        }
        $count = ($line.Length - 1) / 2
        $rec = New-Object byte[] $count
        $sum = 0
        for ($k = 0; $k -lt $count; $k++) {
            $rec[$k] = [Convert]::ToByte($line.Substring(1 + 2 * $k, 2), 16)
            $sum += $rec[$k]
        }
        $len = $rec[0]
        if ($count -ne $len + 5) { throw "$lineNo 行目: レコード長 ($len) と行の長さが合いません。" }
        if (($sum -band 0xFF) -ne 0) { throw "$lineNo 行目: チェックサムが合いません。ファイルが壊れている可能性があります。" }
        $offset = ([int]$rec[1] -shl 8) -bor $rec[2]
        $type = $rec[3]
        switch ($type) {
            0 {
                if ($len -gt 0) {
                    $start = [long]$base + $offset
                    $end = $start + $len
                    if ($end -gt $APP_END) {
                        throw ("$lineNo 行目: 書き込み先 0x{0:X4}-0x{1:X4} がアプリケーション領域 (0x0000-0x{2:X4}) を超えています。" -f $start, ($end - 1), ($APP_END - 1))
                    }
                    $dataBytes += $len
                    if ($start -lt $minAddr) { $minAddr = $start }
                    if ($end -gt $maxEnd) { $maxEnd = $end }
                }
            }
            1 { $eof = $true }
            2 { $base = (([int]$rec[4] -shl 8) -bor $rec[5]) * 16 }
            3 { }
            4 { $base = ([long](([int]$rec[4] -shl 8) -bor $rec[5])) * 65536 }
            5 { }
            default { throw ("$lineNo 行目: 未知のレコード種別 (0x{0:X2}) です。" -f $type) }
        }
    }
    if (-not $eof) { throw 'EOF レコードがありません。ファイルが途中で切れている可能性があります。' }
    if ($dataBytes -eq 0) { throw '書き込むデータがありません。' }
    return [pscustomobject]@{ Bytes = $dataBytes; Start = $minAddr; End = $maxEnd }
}

# ---------------------------------------------------------------------------
# avrdude の用意
# ---------------------------------------------------------------------------
function Get-AvrdudePath {
    if ($Avrdude) {
        if (-not (Test-Path -LiteralPath $Avrdude -PathType Leaf)) {
            throw "avrdude が見つかりません: $Avrdude"
        }
        return (Resolve-Path -LiteralPath $Avrdude).ProviderPath
    }

    $dir = Join-Path $CACHE_DIR "avrdude\$AVRDUDE_VERSION"
    $exe = Join-Path $dir 'avrdude.exe'
    if ((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath (Join-Path $dir 'avrdude.conf'))) {
        return $exe
    }

    Write-Host "avrdude $AVRDUDE_VERSION をダウンロードしています (初回のみ)..."
    $zip = Join-Path $CACHE_DIR "avrdude-$AVRDUDE_VERSION-windows-x64.zip"
    $tmpDir = "$dir.extract"
    [void](New-Item -ItemType Directory -Force -Path $CACHE_DIR)
    try {
        Invoke-FirmwareDownload $AVRDUDE_URL $zip
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        if ($hash -ne $AVRDUDE_SHA256) {
            throw "ダウンロードした avrdude の SHA256 が一致しません (期待値 $AVRDUDE_SHA256 / 実際 $hash)。"
        }
        if (Test-Path -LiteralPath $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $tmpDir
        foreach ($name in 'avrdude.exe', 'avrdude.conf') {
            if (-not (Test-Path -LiteralPath (Join-Path $tmpDir $name))) {
                throw "avrdude の zip に $name がありません。"
            }
        }
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        Move-Item -LiteralPath $tmpDir -Destination $dir
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "  $dir に展開しました。"
    return $exe
}

# ---------------------------------------------------------------------------
# caterina ブートローダの COM ポート
# ---------------------------------------------------------------------------
function Find-CaterinaPort {
    try {
        $entities = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass = 'Ports'")
    } catch {
        return
    }
    foreach ($e in $entities) {
        if ($e.PNPDeviceID -match '^USB\\VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') {
            $id = "$($Matches[1]):$($Matches[2])".ToUpperInvariant()
            if ($CATERINA_IDS -contains $id -and $e.Name -match '\((COM\d+)\)') {
                [pscustomobject]@{ Port = $Matches[1]; Id = $id }
            }
        }
    }
}

function Wait-CaterinaPort([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $ports = @(Find-CaterinaPort)
        if ($ports.Count -gt 1) {
            throw "caterina ブートローダが複数あります ($(($ports | ForEach-Object { $_.Port }) -join ', '))。1 台ずつつないでください。"
        }
        if ($ports.Count -eq 1) { return $ports[0] }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

function Wait-CaterinaGone([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (@(Find-CaterinaPort).Count -eq 0) { return }
        Start-Sleep -Milliseconds 250
    }
}

function Invoke-Avrdude([string]$Exe, [string]$WorkDir, [string]$Port) {
    $avrArgs = @()
    $conf = Join-Path (Split-Path -Parent $Exe) 'avrdude.conf'
    if (Test-Path -LiteralPath $conf) { $avrArgs += @('-C', $conf) }
    # -U のファイル名にドライブレターの ":" を含めないよう、作業ディレクトリからの相対名で渡す
    $avrArgs += @('-p', 'atmega32u4', '-c', 'avr109', '-P', $Port, '-U', 'flash:w:firmware.hex:i')

    Push-Location -LiteralPath $WorkDir
    # avrdude は進捗を標準エラーに出すので、エラー扱いにしない
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # 標準出力を戻り値に混ぜないよう画面へ流す
        & $Exe @avrArgs | Out-Host
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# 1. ファームウェアの用意と検証
# ---------------------------------------------------------------------------
if (-not $Path) {
    try {
        $keyball = $script:FlashKeyboards['Keyball39']
        $Path = Get-FirmwareAsset -Repo $keyball.Repo -Asset $keyball.Asset -OutDir (Join-Path $CACHE_DIR 'firmware') `
            -Tag (Get-FirmwareTag $Tag $Pr)
    } catch {
        Stop-WithError $_.Exception.Message
    }
    Write-Host ''
}
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Stop-WithError "ファイルが見つかりません: $Path"
}
$hexFile = (Resolve-Path -LiteralPath $Path).ProviderPath
try {
    $hex = Test-IntelHex $hexFile
} catch {
    Stop-WithError "Intel HEX として正しくありません: $hexFile`n  $($_.Exception.Message)"
}
Write-Host "ファームウェア: $([System.IO.Path]::GetFileName($hexFile))"
Write-Host ("  ATmega32U4 / 0x{0:X4}-0x{1:X4} / {2:N0} バイト (上限 {3:N0} バイト)" -f $hex.Start, ($hex.End - 1), $hex.Bytes, $APP_END)

# ---------------------------------------------------------------------------
# 2. avrdude の用意
# ---------------------------------------------------------------------------
try {
    $avrdudeExe = Get-AvrdudePath
} catch {
    Stop-WithError ("avrdude を用意できませんでした: $($_.Exception.Message)`n" +
        '  インストール済みの avrdude を使う場合は -Avrdude <avrdude.exe のパス> を指定してください。')
}

# avrdude に渡す .hex は、パスに ":" や空白を含まない作業ディレクトリへコピーしておく
$workDir = Join-Path $CACHE_DIR 'keyball'
[void](New-Item -ItemType Directory -Force -Path $workDir)
Copy-Item -LiteralPath $hexFile -Destination (Join-Path $workDir 'firmware.hex') -Force

# ---------------------------------------------------------------------------
# 3. 1 台ずつ書き込む
# ---------------------------------------------------------------------------
$maxAttempts = 3
for ($unit = 1; $unit -le $Count; $unit++) {
    Write-Host ''
    if ($Count -gt 1) {
        Write-Host "[$unit / $Count 台目]" -ForegroundColor Cyan
    }
    Write-Host '  Keyball の片側を KQ-mini から外し、USB ケーブルで PC に直接つないでください。'
    Write-Host '  つないだら、次のどちらかでブートローダを起動してください:'
    Write-Host '    - リセットスイッチを押す (認識されなければ素早く 2 回)'
    Write-Host '    - 左手側は Q、右手側は P を押したまま USB ケーブルを挿す (EEPROM の設定も初期化されます)'

    $done = $false
    for ($attempt = 1; $attempt -le $maxAttempts -and -not $done; $attempt++) {
        Write-Host ''
        Write-Host 'ブートローダ (COM ポート) を待っています...'
        try {
            $port = Wait-CaterinaPort $WaitSeconds
        } catch {
            Stop-WithError $_.Exception.Message
        }
        if ($null -eq $port) {
            $message = "$WaitSeconds 秒待っても caterina ブートローダの COM ポートが見つかりませんでした。"
            if ($unit -gt 1) {
                $message += "`n  $($unit - 1) 台目までは書き込み済みです。残りは、もう一度実行して書き込んでください (-Count $($Count - $unit + 1) で台数を指定できます)。"
            }
            Stop-WithError $message
        }
        Write-Host "  $($port.Port) (USB $($port.Id)) を見つけました。書き込みます..."
        # QMK と同じく、ポートが使えるようになるまで少し待つ
        Start-Sleep -Seconds 1
        Write-Host ''
        $rc = Invoke-Avrdude $avrdudeExe $workDir $port.Port
        Write-Host ''
        if ($rc -eq 0) {
            Write-Host "成功: $unit 台目に書き込みました (avrdude のベリファイ済み)。" -ForegroundColor Green
            $done = $true
        } else {
            Write-Host "avrdude が失敗しました (終了コード $rc)。" -ForegroundColor Yellow
            if ($attempt -lt $maxAttempts) {
                Write-Host '  ブートローダが 8 秒で終了した可能性があります。もう一度リセットスイッチを押してください。'
            }
        }
        # ブートローダが終了して COM ポートが消えるのを待ってから次へ進む
        Wait-CaterinaGone 10
    }
    if (-not $done) {
        Stop-WithError "$maxAttempts 回試しましたが書き込めませんでした。USB ケーブルや USB ポートを変えて、もう一度試してください。"
    }
}

Write-Host ''
$summary = if ($Count -gt 1) { "$Count 台すべてに書き込みました" } else { '書き込みました' }
Write-Host "完了: $summary。Keyball を KQ-mini に接続し直してください。" -ForegroundColor Green
exit 0
