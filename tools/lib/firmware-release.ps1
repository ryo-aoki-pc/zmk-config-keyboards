# 各ファームウェアリポジトリの CI が置くリリースから、ビルドの一覧を取得し、ファームウェアをダウンロードする関数。
# flash.ps1 / flash-zmk.ps1 / flash-keyball.ps1 / flash-kq-mini.ps1 から dot-source して使う。
#
#   タグ firmware-latest         custom ブランチの最新ビルド
#   タグ firmware-custom-<sha7>  custom ブランチのビルドの履歴 (新しいものから 30 件)
#   タグ firmware-pr-<番号>      PR のビルド (PR に push するたびに置き換わる。新しいものから 30 件)
#
#   https://github.com/<Repo>/releases/download/<タグ>/<Asset>
#   https://github.com/<Repo>/releases/download/<タグ>/BUILD_INFO.txt
#   https://api.github.com/repos/<Repo>/releases  (一覧。認証なしでは 1 時間に 60 回まで)
#
# 公開リポジトリのリリースなので認証は不要。Actions の Artifacts と違って期限切れにならない。
# リリースの本文の ```text ブロックと BUILD_INFO.txt の「キー: 値」の行は、各リポジトリの
# .github/scripts/firmware-release.sh が書く (キーの名前は $script:FirmwareInfoKeys)。

$script:FirmwareLatestTag = 'firmware-latest'
$script:FirmwareInfoKeys = @('repository', 'kind', 'branch', 'pr', 'title', 'head', 'commit', 'subject', 'built', 'run')
$script:FirmwareApiBase = 'https://api.github.com'
$script:FirmwareStateTexts = @{ open = 'オープン'; merged = 'マージ済み'; closed = 'クローズ' }
# ダウンロードが HTTP の応答なしで失敗したとき、やり直すまでの待ち時間 (テストでは 0 にする)
$script:FirmwareRetryDelayMs = 500

# ---------------------------------------------------------------------------
# 純粋関数 (Windows 以外でもテストできる)
# ---------------------------------------------------------------------------

# -Tag / -Pr からリリースのタグを決める (どちらも無ければ firmware-latest)
function Get-FirmwareTag([string]$Tag = '', [int]$Pr = 0) {
    if ($Pr -gt 0) {
        if ($Tag) {
            throw '-Tag と -Pr は一緒に使えません。'
        }
        return "firmware-pr-$Pr"
    }
    if (-not $Tag) {
        return $script:FirmwareLatestTag
    }
    if ($Tag -notmatch '^[A-Za-z0-9._-]+$') {
        throw "タグの名前が正しくありません: $Tag"
    }
    return $Tag
}

# タグの種類: latest / custom / pr (書き込みツールが扱わないタグは '')
function Get-FirmwareTagKind([string]$Tag) {
    if ($Tag -eq $script:FirmwareLatestTag) { return 'latest' }
    if ($Tag -match '^firmware-custom-[0-9a-f]+$') { return 'custom' }
    if ($Tag -match '^firmware-pr-\d+$') { return 'pr' }
    return ''
}

# BUILD_INFO.txt / リリースの本文から「キー: 値」の行を読む (知っているキーだけ。同じキーは最初の行)
function ConvertFrom-FirmwareInfoText([string]$Text) {
    $info = @{}
    if (-not $Text) {
        return $info
    }
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^([a-z]+): ?(.*)$') {
            $key = $Matches[1]
            if ($script:FirmwareInfoKeys -contains $key -and -not $info.ContainsKey($key)) {
                $info[$key] = $Matches[2].Trim()
            }
        }
    }
    return $info
}

# JSON の配列の要素を出力する (呼ぶ側は @() で受ける)。Windows PowerShell 5.1 は配列を 1 つのオブジェクトとして返し、
# PowerShell 7 は空の配列を $null にするので、どちらでも同じになるように foreach で取り出す
function ConvertFrom-FirmwareJsonArray([string]$Json) {
    $items = New-Object System.Collections.ArrayList
    if ($Json -and $Json.Trim()) {
        $parsed = ConvertFrom-Json $Json
        foreach ($item in $parsed) {
            if ($null -ne $item) {
                [void]$items.Add($item)
            }
        }
    }
    return $items.ToArray()
}

# 日時 (ISO 8601 の文字列、または PowerShell 7 の ConvertFrom-Json が作る DateTime) を UTC の DateTime にする
function ConvertTo-FirmwareUtc($Value) {
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [DateTime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) {
            return [DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc)
        }
        return $Value.ToUniversalTime()
    }
    $text = [string]$Value
    if (-not $text) {
        return $null
    }
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $result = [DateTime]::MinValue
    if ([DateTime]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$result)) {
        return $result
    }
    return $null
}

# オブジェクトのプロパティ (無ければ $Default)。Set-StrictMode でも無いプロパティを読めるように
function Get-FirmwareProp($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) {
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) {
        return $Default
    }
    return $prop.Value
}

# Link ヘッダーの次のページの URL ('' なら最後のページ)
function Get-FirmwareLinkNext([string]$Link) {
    if (-not $Link) {
        return ''
    }
    foreach ($part in $Link.Split(',')) {
        if ($part -match '<([^>]+)>\s*;\s*rel="next"') {
            return $Matches[1]
        }
    }
    return ''
}

# /issues の一覧から、PR の番号 → open / merged / closed
function ConvertTo-FirmwarePullStates($Issues) {
    $states = @{}
    foreach ($issue in @($Issues)) {
        $pull = Get-FirmwareProp $issue 'pull_request'
        if ($null -eq $pull) {
            continue
        }
        $number = [int](Get-FirmwareProp $issue 'number' 0)
        if ($number -le 0) {
            continue
        }
        $state = [string](Get-FirmwareProp $issue 'state' '')
        if ($state -eq 'closed') {
            if ($null -ne (Get-FirmwareProp $pull 'merged_at')) {
                $state = 'merged'
            }
        } elseif ($state -ne 'open') {
            continue
        }
        $states[$number] = $state
    }
    return $states
}

# リリースの一覧 (GitHub API の releases の要素) をビルドの一覧にする。
# firmware-* 以外のタグと下書きは除く。並びは、最新を先頭に、残りはビルドした日時の新しい順。
# custom のビルドのうち最新と同じコミットのもの (双子) には IsLatestTwin を付け、最新のダウンロードはそのタグから行う
# (firmware-latest は push のたびに置き換わるが、firmware-custom-<sha7> は置き換わらないため)。
function ConvertTo-FirmwareBuild($Releases, [hashtable]$PullStates = @{}) {
    $builds = New-Object System.Collections.ArrayList
    foreach ($r in @($Releases)) {
        if ($null -eq $r) {
            continue
        }
        $tag = [string](Get-FirmwareProp $r 'tag_name' '')
        $kind = Get-FirmwareTagKind $tag
        if (-not $kind -or [bool](Get-FirmwareProp $r 'draft' $false)) {
            continue
        }
        $name = [string](Get-FirmwareProp $r 'name' '')
        $info = ConvertFrom-FirmwareInfoText ([string](Get-FirmwareProp $r 'body' ''))
        $legacy = -not $info.ContainsKey('commit')
        $commit = ''
        $branch = ''
        if ($legacy) {
            # CI を変える前の firmware-latest: 名前が「Latest firmware (custom @ abc1234)」
            if ($name -match '\((\S+) @ ([0-9a-f]{7,40})\)') {
                $branch = $Matches[1]
                $commit = $Matches[2]
            }
        } else {
            $commit = [string]$info['commit']
            $branch = [string]$info['branch']
        }
        $created = ConvertTo-FirmwareUtc (Get-FirmwareProp $r 'created_at')
        $built = $null
        if ($info.ContainsKey('built')) {
            $built = ConvertTo-FirmwareUtc $info['built']
        }
        if ($null -eq $built) {
            $built = ConvertTo-FirmwareUtc (Get-FirmwareProp $r 'published_at')
        }
        if ($null -eq $built) {
            $built = $created
        }
        $pr = 0
        if ($kind -eq 'pr') {
            $pr = [int]($tag -replace '^firmware-pr-', '')
        }
        $title = ''
        if ($kind -eq 'pr') {
            if ($info.ContainsKey('title')) { $title = [string]$info['title'] }
        } elseif ($info.ContainsKey('subject')) {
            $title = [string]$info['subject']
        }
        $headSha = $commit
        if ($info.ContainsKey('head') -and $info['head']) {
            $headSha = [string]$info['head']
        }
        $state = ''
        if ($pr -gt 0 -and $PullStates.ContainsKey($pr)) {
            $state = [string]$PullStates[$pr]
        }
        $assets = @(foreach ($a in @(Get-FirmwareProp $r 'assets' @())) {
                $n = [string](Get-FirmwareProp $a 'name' '')
                if ($n) { $n }
            })
        [void]$builds.Add([pscustomobject]@{
                Tag          = $tag
                DownloadTag  = $tag
                Kind         = $kind
                Pr           = $pr
                Title        = $title
                Branch       = $branch
                Head         = $headSha
                Commit       = $commit
                Built        = $built
                Created      = $created
                Run          = [string]$info['run']
                Assets       = $assets
                State        = $state
                IsLatestTwin = $false
                Legacy       = $legacy
                Name         = $name
                Url          = [string](Get-FirmwareProp $r 'html_url' '')
            })
    }

    $latest = @($builds | Where-Object { $_.Kind -eq 'latest' } | Select-Object -First 1)
    if ($latest.Count -eq 1 -and $latest[0].Commit) {
        $l = $latest[0]
        foreach ($b in $builds) {
            if ($b.Kind -eq 'custom' -and $b.Commit -and ($b.Commit.StartsWith($l.Commit) -or $l.Commit.StartsWith($b.Commit))) {
                $b.IsLatestTwin = $true
                $l.DownloadTag = $b.Tag
                if (-not $l.Title) { $l.Title = $b.Title }
                if ($l.Legacy) { $l.Commit = $b.Commit; $l.Head = $b.Head }
                break
            }
        }
    }

    $rest = @($builds | Where-Object { $_.Kind -ne 'latest' } | Sort-Object -Property @(
            @{ Expression = { if ($null -ne $_.Built) { $_.Built } else { [DateTime]::MinValue } }; Descending = $true },
            @{ Expression = { $_.Tag }; Descending = $false }))
    $sorted = New-Object System.Collections.ArrayList
    foreach ($b in $builds) {
        if ($b.Kind -eq 'latest') { [void]$sorted.Add($b) }
    }
    foreach ($b in $rest) {
        [void]$sorted.Add($b)
    }
    return $sorted.ToArray()
}

# 絞り込み: all (すべて) / pr (PR) / custom (最新と custom の履歴)。最新と同じコミットの custom (双子) は出さない
function Select-FirmwareBuilds($Builds, [string]$Filter = 'all') {
    $list = New-Object System.Collections.ArrayList
    foreach ($b in @($Builds)) {
        if ($null -eq $b -or $b.IsLatestTwin) {
            continue
        }
        if ($Filter -eq 'pr' -and $b.Kind -ne 'pr') { continue }
        if ($Filter -eq 'custom' -and $b.Kind -eq 'pr') { continue }
        [void]$list.Add($b)
    }
    return $list.ToArray()
}

# 一覧に出す文字 (バッジ・タイトル・詳細・PR の状態・ツールチップ)。$Zone は表示するタイムゾーン
function Format-FirmwareBuildLabel($Build, [TimeZoneInfo]$Zone = [TimeZoneInfo]::Local) {
    $badge = 'custom'
    if ($Build.Kind -eq 'latest') { $badge = '最新' }
    elseif ($Build.Kind -eq 'pr') { $badge = 'PR #{0}' -f $Build.Pr }

    $title = [string]$Build.Title
    if (-not $title) {
        if ($Build.Kind -eq 'latest') { $title = 'custom ブランチの最新ビルド' }
        elseif ($Build.Kind -eq 'pr') { $title = '(タイトルなし)' }
        else { $title = 'custom ブランチのビルド' }
    }

    $parts = @()
    $sha = [string]$Build.Commit
    if ($Build.Kind -eq 'pr' -and $Build.Head) {
        $sha = [string]$Build.Head
    }
    if ($sha) {
        $parts += $sha.Substring(0, [Math]::Min(7, $sha.Length))
    }
    if ($null -ne $Build.Built) {
        $local = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::SpecifyKind($Build.Built, [DateTimeKind]::Utc), $Zone)
        $parts += $local.ToString('yyyy/MM/dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Build.Branch -and $Build.Kind -eq 'pr') {
        $parts += [string]$Build.Branch
    }
    $stateText = ''
    if ($Build.State -and $script:FirmwareStateTexts.ContainsKey([string]$Build.State)) {
        $stateText = $script:FirmwareStateTexts[[string]$Build.State]
    }
    $tip = @($title, ('タグ: {0}' -f $Build.Tag))
    if ($Build.Commit) { $tip += ('コミット: {0}' -f $Build.Commit) }
    if ($Build.Kind -eq 'pr') { $tip += 'PR をマージした状態のコミットをビルドしたもの' }
    return [pscustomobject]@{
        Badge     = $badge
        Title     = $title
        Detail    = ($parts -join ' · ')
        StateText = $stateText
        Tooltip   = ($tip -join "`n")
    }
}

# レート制限の案内 (リセットの時刻を表示のタイムゾーンで)
function Get-FirmwareRateLimitText($ResetAt, [TimeZoneInfo]$Zone = [TimeZoneInfo]::Local) {
    $text = 'GitHub API の利用回数の上限 (認証なしでは 1 時間に 60 回) に達しました。'
    if ($null -ne $ResetAt) {
        $local = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::SpecifyKind($ResetAt, [DateTimeKind]::Utc), $Zone)
        $text += ' {0} 以降に「更新」してください。' -f $local.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    }
    return $text
}

# ---------------------------------------------------------------------------
# ネットワーク
# ---------------------------------------------------------------------------

function Invoke-FirmwareDownload([string]$Uri, [string]$OutFile, [int]$TimeoutSec = 0) {
    # Windows PowerShell 5.1 は既定で TLS 1.2 を使わないことがあるので明示する
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    # 進捗バーを出すと Invoke-WebRequest が極端に遅くなる
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        if ($TimeoutSec -gt 0) {
            Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile -TimeoutSec $TimeoutSec
        } else {
            Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile
        }
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

# 応答のヘッダー (5.1 は Dictionary<string,string>、7 は Dictionary<string,IEnumerable<string>>)
function Get-FirmwareHeaderValue($Headers, [string]$Name) {
    if ($null -eq $Headers) {
        return ''
    }
    foreach ($key in @($Headers.Keys)) {
        if ([string]::Equals([string]$key, $Name, [StringComparison]::OrdinalIgnoreCase)) {
            $value = $Headers[$key]
            if ($value -is [string]) {
                return $value
            }
            return (@($value) -join ',')
        }
    }
    return ''
}

# エラーの応答のヘッダー (5.1 は WebHeaderCollection、7 は HttpResponseHeaders。どちらも GetValues がある)
function Get-FirmwareErrorHeader($ErrorRecord, [string]$Name) {
    $ex = $ErrorRecord.Exception
    while ($ex) {
        $prop = $ex.PSObject.Properties['Response']
        if ($prop -and $prop.Value) {
            try {
                $values = $prop.Value.Headers.GetValues($Name)
                if ($values) {
                    return (@($values) -join ',')
                }
            } catch {
            }
            return ''
        }
        $ex = $ex.InnerException
    }
    return ''
}

function ConvertFrom-FirmwareEpoch([string]$Text) {
    $seconds = 0L
    if ([long]::TryParse($Text, [ref]$seconds) -and $seconds -gt 0) {
        return (New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)).AddSeconds($seconds)
    }
    return $null
}

# GitHub API を呼ぶ。例外は投げず、結果を返す:
#   Ok, Text (応答の本文), Next (次のページの URL), Remaining (残りの回数。不明なら -1), ResetAt (UTC),
#   Kind (失敗の種類: ratelimit / http / network), Status, Message
# $env:GITHUB_TOKEN か $env:GH_TOKEN があれば使う (上限が 1 時間に 5000 回になる)。トークンは表示しない
function Invoke-FirmwareApi([string]$Uri, [int]$TimeoutSec = 20) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'X-GitHub-Api-Version' = '2022-11-28' }
    $token = $env:GITHUB_TOKEN
    if (-not $token) { $token = $env:GH_TOKEN }
    if ($token) {
        $headers['Authorization'] = 'Bearer ' + $token
    }
    $result = @{ Ok = $false; Text = ''; Next = ''; Remaining = -1; ResetAt = $null; Kind = ''; Status = 0; Message = '' }
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $Uri -Headers $headers -TimeoutSec $TimeoutSec
        $result.Ok = $true
        $result.Status = [int]$resp.StatusCode
        $result.Text = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        $result.Next = Get-FirmwareLinkNext (Get-FirmwareHeaderValue $resp.Headers 'Link')
        $remaining = 0
        if ([int]::TryParse((Get-FirmwareHeaderValue $resp.Headers 'X-RateLimit-Remaining'), [ref]$remaining)) {
            $result.Remaining = $remaining
        }
        $result.ResetAt = ConvertFrom-FirmwareEpoch (Get-FirmwareHeaderValue $resp.Headers 'X-RateLimit-Reset')
    } catch {
        $code = Get-HttpStatusCode $_
        $remainingText = Get-FirmwareErrorHeader $_ 'X-RateLimit-Remaining'
        $retryAfter = Get-FirmwareErrorHeader $_ 'Retry-After'
        $result.ResetAt = ConvertFrom-FirmwareEpoch (Get-FirmwareErrorHeader $_ 'X-RateLimit-Reset')
        if ($null -ne $code) {
            $result.Status = [int]$code
            if (($code -eq 403 -or $code -eq 429) -and ($remainingText -eq '0' -or $retryAfter)) {
                $result.Kind = 'ratelimit'
                $result.Remaining = 0
                $result.Message = Get-FirmwareRateLimitText $result.ResetAt
            } else {
                $result.Kind = 'http'
                $result.Message = 'GitHub API がエラーを返しました (HTTP {0})。' -f $code
            }
        } else {
            $result.Kind = 'network'
            $result.Message = 'GitHub に接続できませんでした: {0}' -f $_.Exception.Message
        }
    } finally {
        $ProgressPreference = $oldProgress
    }
    return $result
}

# リリースの一覧のページ (JSON の文字列の配列)。5.1 の ConvertFrom-Json は約 2 MB までしか読めないので、
# 1 ページを 50 件にして、次のページを順にたどる
function Get-FirmwareReleasePages([string]$Repo, [int]$PerPage = 50, [int]$MaxPages = 4) {
    $pages = New-Object System.Collections.ArrayList
    $uri = '{0}/repos/{1}/releases?per_page={2}' -f $script:FirmwareApiBase, $Repo, $PerPage
    $last = $null
    for ($i = 0; $i -lt $MaxPages -and $uri; $i++) {
        $last = Invoke-FirmwareApi $uri
        if (-not $last.Ok) {
            return @{ Ok = $false; Pages = @(); Api = $last }
        }
        [void]$pages.Add($last.Text)
        $uri = $last.Next
    }
    return @{ Ok = $true; Pages = $pages.ToArray(); Api = $last }
}

# キャッシュのファイル: <CacheDir>/<owner_repo>/builds/ に、API の応答をそのまま置く
function Get-FirmwareListCacheDir([string]$Repo, [string]$CacheDir) {
    return (Join-Path (Join-Path $CacheDir ($Repo -replace '[\\/]', '_')) 'builds')
}

function Save-FirmwareListCache([string]$Repo, [string]$CacheDir, [string[]]$Pages, [string]$Issues, [DateTime]$FetchedAt) {
    $dir = Get-FirmwareListCacheDir $Repo $CacheDir
    try {
        [void](New-Item -ItemType Directory -Force -Path $dir)
        Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        $utf8 = New-Object System.Text.UTF8Encoding $false
        for ($i = 0; $i -lt $Pages.Count; $i++) {
            [System.IO.File]::WriteAllText((Join-Path $dir ('releases-{0}.json' -f ($i + 1))), $Pages[$i], $utf8)
        }
        if ($Issues) {
            [System.IO.File]::WriteAllText((Join-Path $dir 'issues.json'), $Issues, $utf8)
        }
        [System.IO.File]::WriteAllText((Join-Path $dir 'fetched.txt'), $FetchedAt.ToUniversalTime().ToString('o'), $utf8)
    } catch {
        # キャッシュは無くても動くので、書けなくても続ける
    }
}

function Read-FirmwareListCache([string]$Repo, [string]$CacheDir) {
    $dir = Get-FirmwareListCacheDir $Repo $CacheDir
    $fetchedFile = Join-Path $dir 'fetched.txt'
    if (-not (Test-Path -LiteralPath $fetchedFile)) {
        return $null
    }
    try {
        $pages = @(Get-ChildItem -LiteralPath $dir -Filter 'releases-*.json' -File | Sort-Object Name |
                ForEach-Object { [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8) })
        $issuesFile = Join-Path $dir 'issues.json'
        $issues = ''
        if (Test-Path -LiteralPath $issuesFile) {
            $issues = [System.IO.File]::ReadAllText($issuesFile, [System.Text.Encoding]::UTF8)
        }
        $fetched = ConvertTo-FirmwareUtc ([System.IO.File]::ReadAllText($fetchedFile).Trim())
        return @{ Pages = $pages; Issues = $issues; FetchedAt = $fetched }
    } catch {
        return $null
    }
}

# API の応答 (ページの JSON と issues の JSON) からビルドの一覧を作る
function ConvertFrom-FirmwareListPages([string[]]$Pages, [string]$Issues) {
    $releases = New-Object System.Collections.ArrayList
    foreach ($page in $Pages) {
        foreach ($r in (ConvertFrom-FirmwareJsonArray $page)) {
            [void]$releases.Add($r)
        }
    }
    $states = @{}
    if ($Issues) {
        $states = ConvertTo-FirmwarePullStates (ConvertFrom-FirmwareJsonArray $Issues)
    }
    return (ConvertTo-FirmwareBuild $releases.ToArray() $states)
}

# API が使えないときの、最新だけの一覧 (BUILD_INFO.txt はダウンロード URL から取るので、API の回数に数えない)
function New-FirmwareLatestOnlyList([string]$Repo, [string]$CacheDir) {
    $info = $null
    try {
        $info = Get-FirmwareBuildInfo -Repo $Repo -Tag $script:FirmwareLatestTag -OutDir $CacheDir
    } catch {
        $info = $null
    }
    $commit = ''
    $built = $null
    if ($null -ne $info) {
        $commit = [string]$info['commit']
        $built = ConvertTo-FirmwareUtc $info['built']
    }
    $build = [pscustomobject]@{
        Tag = $script:FirmwareLatestTag; DownloadTag = $script:FirmwareLatestTag; Kind = 'latest'; Pr = 0
        Title = ''; Branch = 'custom'; Head = $commit; Commit = $commit; Built = $built; Created = $built; Run = ''
        Assets = $null; State = ''; IsLatestTwin = $false; Legacy = $true; Name = ''; Url = ''
    }
    return $build
}

# ビルドの一覧を取得する。戻り値:
#   Builds, Source (api / cache / fallback), Message (Source が api 以外のときの説明), Level (0 情報 / 3 注意), FetchedAt
# 取れなければ、前回取得した一覧 (キャッシュ)、それも無ければ最新だけを返す
function Get-FirmwareBuildList([string]$Repo, [string]$CacheDir, [switch]$NoPullStates) {
    $list = Get-FirmwareReleasePages $Repo
    if ($list.Ok) {
        $issues = ''
        if (-not $NoPullStates -and ($list.Api.Remaining -lt 0 -or $list.Api.Remaining -ge 5)) {
            $api = Invoke-FirmwareApi ('{0}/repos/{1}/issues?state=all&sort=updated&direction=desc&per_page=50' -f $script:FirmwareApiBase, $Repo)
            if ($api.Ok) {
                $issues = $api.Text
            }
        }
        $now = [DateTime]::UtcNow
        Save-FirmwareListCache $Repo $CacheDir $list.Pages $issues $now
        return @{
            Builds = @(ConvertFrom-FirmwareListPages $list.Pages $issues); Source = 'api'; Message = ''; Level = 0; FetchedAt = $now
        }
    }

    $reason = $list.Api.Message
    $cache = Read-FirmwareListCache $Repo $CacheDir
    if ($null -ne $cache) {
        $when = ''
        if ($null -ne $cache.FetchedAt) {
            $when = ' (' + $cache.FetchedAt.ToLocalTime().ToString('MM/dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) + ') '
        }
        return @{
            Builds    = @(ConvertFrom-FirmwareListPages $cache.Pages $cache.Issues); Source = 'cache'; Level = 3; FetchedAt = $cache.FetchedAt
            Message   = '{0} 前回{1}取得した一覧を表示しています。' -f $reason, $when
        }
    }
    return @{
        Builds  = @(New-FirmwareLatestOnlyList $Repo $CacheDir); Source = 'fallback'; Level = 3; FetchedAt = $null
        Message = '{0} 最新のビルドだけ選べます。' -f $reason
    }
}

function Get-FirmwareCacheDir([string]$Repo, [string]$OutDir, [string]$Tag = '') {
    $dir = Join-Path $OutDir ($Repo -replace '[\\/]', '_')
    if ($Tag) {
        $dir = Join-Path $dir $Tag
    }
    [void](New-Item -ItemType Directory -Force -Path $dir)
    return $dir
}

# 404 のときの案内
function Get-FirmwareNotFoundText([string]$Repo, [string]$Tag, [string]$Asset) {
    $kind = Get-FirmwareTagKind $Tag
    if ($kind -eq 'pr' -or $kind -eq 'custom') {
        return ("$Repo に $Tag リリース (または $Asset) がありません。`n" +
            "  古いビルドは自動で削除されます。PR に push し直したばかりなら、ビルドが終わるまで待ってください。`n" +
            "  このビルドに $Asset が無い場合もあります (後から足したファームウェアなど)。`n" +
            "  https://github.com/$Repo/releases で確かめてください。")
    }
    return ("$Repo に $Tag リリース (または $Asset) がまだありません。`n" +
        "  https://github.com/$Repo/actions で custom ブランチのビルドを実行してから、もう一度試してください。`n" +
        "  https://github.com/$Repo/releases で $Tag が下書き (Draft) になっている場合も、ダウンロードできません。`n" +
        "  手元の .uf2 / .hex を書き込む場合は、ファイルをこのスクリプトにドラッグ＆ドロップしてください。")
}

# 1 つのファイルをダウンロードして、保存したパスを返す。HTTP の応答が無い失敗 (接続が切れたなど) は 1 回だけやり直す
# (5.1 では、404 の応答のあとのダウンロードが「接続が予期せずに閉じられました」になることがあり、404 の案内を出せない)
function Save-FirmwareFile([string]$Repo, [string]$Tag, [string]$Asset, [string]$Dir) {
    $dest = Join-Path $Dir $Asset
    $tmp = "$dest.download"
    $url = "https://github.com/$Repo/releases/download/$Tag/$Asset"
    for ($attempt = 1; $true; $attempt++) {
        try {
            Invoke-FirmwareDownload $url $tmp
            break
        } catch {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            $code = Get-HttpStatusCode $_
            if ($code -eq 404) {
                throw (Get-FirmwareNotFoundText $Repo $Tag $Asset)
            }
            if ($null -ne $code -or $attempt -ge 2) {
                throw "ダウンロードに失敗しました: $url`n  $($_.Exception.Message)"
            }
            Start-Sleep -Milliseconds $script:FirmwareRetryDelayMs
        }
    }
    Move-Item -LiteralPath $tmp -Destination $dest -Force
    return $dest
}

# BUILD_INFO.txt を取得して「キー: 値」を返す (無ければ $null)
function Get-FirmwareBuildInfo([string]$Repo, [string]$Tag, [string]$OutDir) {
    $dir = Get-FirmwareCacheDir $Repo $OutDir $Tag
    try {
        $path = Save-FirmwareFile $Repo $Tag 'BUILD_INFO.txt' $dir
    } catch {
        return $null
    }
    return (ConvertFrom-FirmwareInfoText ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)))
}

# ビルドの情報 (コミット / ビルド日時 / PR) を表示する
function Show-FirmwareBuildInfo($Info) {
    if ($null -eq $Info) {
        Write-Host '  (BUILD_INFO.txt は取得できませんでした)' -ForegroundColor DarkGray
        return
    }
    if ($Info.ContainsKey('pr') -and $Info['pr']) {
        Write-Host ('  pr: #{0} {1}' -f $Info['pr'], $Info['title'])
    }
    foreach ($key in @('commit', 'built')) {
        if ($Info.ContainsKey($key)) {
            Write-Host ('  {0}: {1}' -f $key, $Info[$key])
        }
    }
}

# 1 つのビルドから、必要なファイルをすべてダウンロードする。戻り値: @{ Paths = @{ アセット名 = パス }; Info = BUILD_INFO }
# firmware-latest と firmware-pr-<番号> は置き換わることがあるので、前後で BUILD_INFO.txt の commit を比べ、
# 違えば (途中で置き換わったら) 1 回だけやり直す。$OnFile は 1 ファイルごとに呼ぶ ({ param($Index, $Count, $Asset) })
function Save-FirmwareBuild([string]$Repo, [string]$Tag, [string[]]$Assets, [string]$OutDir, [scriptblock]$OnFile = $null, [switch]$Quiet) {
    $unique = @($Assets | Select-Object -Unique)
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $dir = Get-FirmwareCacheDir $Repo $OutDir $Tag
        Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        $before = Get-FirmwareBuildInfo $Repo $Tag $OutDir
        $paths = @{}
        for ($i = 0; $i -lt $unique.Count; $i++) {
            if ($null -ne $OnFile) {
                & $OnFile $i $unique.Count $unique[$i]
            }
            $paths[$unique[$i]] = Save-FirmwareFile $Repo $Tag $unique[$i] $dir
            if (-not $Quiet) {
                Write-Host ('  {0} ({1:N0} バイト)' -f $unique[$i], (Get-Item -LiteralPath $paths[$unique[$i]]).Length)
            }
        }
        $after = Get-FirmwareBuildInfo $Repo $Tag $OutDir
        if ($null -eq $before -or $null -eq $after -or [string]$before['commit'] -eq [string]$after['commit']) {
            return @{ Paths = $paths; Info = $after }
        }
        if (-not $Quiet) {
            Write-Host '  ダウンロードの途中でビルドが置き換わったので、やり直します。' -ForegroundColor Yellow
        }
    }
    throw "ダウンロードの途中で $Tag のビルドが置き換わりました。もう一度試してください。"
}

# 1 つのファイルをダウンロードする (flash-keyball.ps1 / flash-kq-mini.ps1 用)。ビルドの情報も表示する
function Get-FirmwareAsset([string]$Repo, [string]$Asset, [string]$OutDir, [string]$Tag = 'firmware-latest') {
    Write-Host "ファームウェアをダウンロードしています: $Repo ($Tag)"
    $result = Save-FirmwareBuild -Repo $Repo -Tag $Tag -Assets @($Asset) -OutDir $OutDir
    Show-FirmwareBuildInfo $result.Info
    return $result.Paths[$Asset]
}
