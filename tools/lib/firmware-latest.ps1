# 各ファームウェアリポジトリの CI が置く firmware-latest リリース (custom ブランチの最新ビルド) から
# ファームウェアをダウンロードする関数。flash-keyball.ps1 / flash-kq-mini.ps1 から dot-source して使う。
#
#   https://github.com/<Repo>/releases/download/firmware-latest/<Asset>
#   https://github.com/<Repo>/releases/download/firmware-latest/BUILD_INFO.txt
#
# 公開リポジトリのリリースなので認証は不要。Actions の Artifacts と違って期限切れにならない。

function Invoke-FirmwareDownload([string]$Uri, [string]$OutFile) {
    # Windows PowerShell 5.1 は既定で TLS 1.2 を使わないことがあるので明示する
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    # 進捗バーを出すと Invoke-WebRequest が極端に遅くなる
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile
    } finally {
        $ProgressPreference = $oldProgress
    }
}

function Get-HttpStatusCode($ErrorRecord) {
    $ex = $ErrorRecord.Exception
    while ($ex) {
        $prop = $ex.PSObject.Properties['Response']
        if ($prop -and $prop.Value) {
            $codeProp = $prop.Value.PSObject.Properties['StatusCode']
            if ($codeProp) { return [int]$codeProp.Value }
        }
        $ex = $ex.InnerException
    }
    return $null
}

function Get-FirmwareLatest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repo,

        [Parameter(Mandatory = $true)]
        [string]$Asset,

        [Parameter(Mandatory = $true)]
        [string]$OutDir,

        [string]$Tag = 'firmware-latest'
    )

    $base = "https://github.com/$Repo/releases/download/$Tag"
    $dir = Join-Path $OutDir ($Repo -replace '[\\/]', '_')
    [void](New-Item -ItemType Directory -Force -Path $dir)
    $dest = Join-Path $dir $Asset
    $tmp = "$dest.download"

    Write-Host "最新のファームウェアをダウンロードしています: $Repo ($Tag)"
    try {
        Invoke-FirmwareDownload "$base/$Asset" $tmp
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        if ((Get-HttpStatusCode $_) -eq 404) {
            throw ("$Repo に $Tag リリース (または $Asset) がまだありません。`n" +
                "  https://github.com/$Repo/actions で custom ブランチのビルドを実行してから、もう一度試してください。`n" +
                "  手元の .uf2 / .hex を書き込む場合は、ファイルをこのスクリプトにドラッグ＆ドロップしてください。")
        }
        throw "ダウンロードに失敗しました: $base/$Asset`n  $($_.Exception.Message)"
    }
    Move-Item -LiteralPath $tmp -Destination $dest -Force
    Write-Host ("  {0} ({1:N0} バイト)" -f $Asset, (Get-Item -LiteralPath $dest).Length)

    # BUILD_INFO.txt (コミット / ビルド日時) は表示するだけなので、取れなくても続行する
    $info = Join-Path $dir 'BUILD_INFO.txt'
    try {
        Invoke-FirmwareDownload "$base/BUILD_INFO.txt" $info
        foreach ($line in [System.IO.File]::ReadAllLines($info)) {
            if ($line -match '^(commit|built):') { Write-Host "  $line" }
        }
    } catch {
        Write-Host '  (BUILD_INFO.txt は取得できませんでした)' -ForegroundColor DarkGray
    }

    return $dest
}
