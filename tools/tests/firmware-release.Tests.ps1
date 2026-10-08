# 書き込みツールのビルドの一覧とダウンロード (lib/firmware-release.ps1) のテスト。
# GitHub API の応答は偽物 (flash-fixtures.ps1) を使い、ネットワークには出ない。

. (Join-Path $script:ToolsDir 'lib\firmware-release.ps1')
. (Join-Path $script:TestsDir 'flash-fixtures.ps1')

$script:FrUtc = [TimeZoneInfo]::Utc

function Get-FrLismBuilds([switch]$WithStates) {
    $issues = ''
    if ($WithStates) {
        $issues = New-FlashFixtureIssuesJson
    }
    return @(ConvertFrom-FirmwareListPages @(New-FlashFixtureLismJson) $issues)
}

Test-Case 'タグ: 既定は firmware-latest、-Pr は firmware-pr-<番号>、不正な名前と併用は例外' {
    Assert-Equal 'firmware-latest' (Get-FirmwareTag)
    Assert-Equal 'firmware-pr-12' (Get-FirmwareTag -Pr 12)
    Assert-Equal 'firmware-custom-abc1234' (Get-FirmwareTag 'firmware-custom-abc1234')
    Assert-Throws { Get-FirmwareTag 'a b' } '*正しくありません*'
    Assert-Throws { Get-FirmwareTag 'firmware-latest' 3 } '*一緒に使えません*'
    Assert-Equal 'latest' (Get-FirmwareTagKind 'firmware-latest')
    Assert-Equal 'custom' (Get-FirmwareTagKind 'firmware-custom-0a1b2c3')
    Assert-Equal 'pr' (Get-FirmwareTagKind 'firmware-pr-7')
    Assert-Equal '' (Get-FirmwareTagKind 'v1.0.0')
    Assert-Equal '' (Get-FirmwareTagKind 'firmware-pr-x')
}

Test-Case 'BUILD_INFO: 知っているキーだけを、最初の行から読む (CRLF も)' {
    $info = ConvertFrom-FirmwareInfoText "説明: 無視`r`nkind: pr`r`ncommit: abc`r`ncommit: def`r`nother: x`r`ntitle: タイトル: コロン入り"
    Assert-Equal 'pr' $info['kind']
    Assert-Equal 'abc' $info['commit']
    Assert-Equal 'タイトル: コロン入り' $info['title']
    Assert-True (-not $info.ContainsKey('other')) '知らないキー'
    Assert-Equal 0 (ConvertFrom-FirmwareInfoText '').Count
}

Test-Case 'JSON の配列: 空・1 件・複数を同じように読む (5.1 と 7 の違いを吸収)' {
    Assert-Equal 0 @(ConvertFrom-FirmwareJsonArray '[]').Count
    Assert-Equal 0 @(ConvertFrom-FirmwareJsonArray '').Count
    $one = @(ConvertFrom-FirmwareJsonArray '[{"a":1}]')
    Assert-Equal 1 $one.Count
    Assert-Equal 1 $one[0].a
    Assert-Equal 3 @(ConvertFrom-FirmwareJsonArray '[{"a":1},{"a":2},{"a":3}]').Count
}

Test-Case '日時: 文字列も DateTime も UTC にする' {
    $d = ConvertTo-FirmwareUtc '2026-10-03T05:40:49Z'
    Assert-Equal ([DateTimeKind]::Utc) $d.Kind
    Assert-Equal '2026-10-03T05:40:49' $d.ToString('s')
    $local = (New-Object DateTime 2026, 1, 2, 3, 4, 5, ([DateTimeKind]::Utc)).ToLocalTime()
    Assert-Equal '2026-01-02T03:04:05' (ConvertTo-FirmwareUtc $local).ToString('s')
    Assert-Equal $null (ConvertTo-FirmwareUtc 'not a date')
    Assert-Equal $null (ConvertTo-FirmwareUtc $null)
}

Test-Case 'Link ヘッダー: 次のページの URL' {
    $link = '<https://api.github.com/repositories/1/releases?per_page=50&page=2>; rel="next", <https://api.github.com/repositories/1/releases?per_page=50&page=3>; rel="last"'
    Assert-Equal 'https://api.github.com/repositories/1/releases?per_page=50&page=2' (Get-FirmwareLinkNext $link)
    Assert-Equal '' (Get-FirmwareLinkNext '<https://x>; rel="prev"')
    Assert-Equal '' (Get-FirmwareLinkNext '')
}

Test-Case 'PR の状態: オープン / マージ済み / クローズ (issue は除く)' {
    $states = ConvertTo-FirmwarePullStates @(ConvertFrom-FirmwareJsonArray (New-FlashFixtureIssuesJson))
    Assert-Equal 'open' $states[27]
    Assert-Equal 'merged' $states[12]
    Assert-Equal 'closed' $states[5]
    Assert-True (-not $states.ContainsKey(3)) 'issue'
}

Test-Case 'ビルドの一覧: firmware-* だけ (下書きと v* は除く)、最新を先頭に新しい順' {
    $builds = Get-FrLismBuilds
    Assert-Equal 'firmware-latest,firmware-pr-27,firmware-custom-aaaaaaa,firmware-pr-12,firmware-custom-bbbbbbb' (@($builds | ForEach-Object { $_.Tag }) -join ',')
    $pr = $builds[1]
    Assert-Equal 'pr' $pr.Kind
    Assert-Equal 27 $pr.Pr
    Assert-Equal 'スクロールを速くする' $pr.Title
    Assert-Equal 'claude/scroll' $pr.Branch
    Assert-Equal '1111111aaaa' $pr.Head
    Assert-Equal '2222222bbbb' $pr.Commit
    Assert-Equal '2026-10-03T05:40:49' $pr.Built.ToString('s')
    Assert-Equal 10 @($pr.Assets).Count
    Assert-True (@($builds[4].Assets) -notcontains 'lism_right_central_trackball_logging.uf2') '古いビルドにはログ版が無い'
}

Test-Case 'ビルドの一覧: 最新と同じコミットの custom は双子 (最新はそのタグからダウンロードする)' {
    $builds = Get-FrLismBuilds
    $latest = $builds[0]
    $twin = @($builds | Where-Object { $_.Tag -eq 'firmware-custom-aaaaaaa' })[0]
    Assert-True $twin.IsLatestTwin '双子の印'
    Assert-Equal 'firmware-custom-aaaaaaa' $latest.DownloadTag
    Assert-Equal 'AML を直す (#26)' $latest.Title
    Assert-Equal 'firmware-custom-bbbbbbb' @($builds | Where-Object { $_.Tag -eq 'firmware-custom-bbbbbbb' })[0].DownloadTag
}

Test-Case 'ビルドの一覧: CI を変える前の firmware-latest (本文に BUILD_INFO が無い) も読める' {
    $legacy = New-FlashFixtureRelease 'firmware-latest' 'Latest firmware (custom @ aaaaaaa)' 'custom ブランチの最新ビルド。' @('a.uf2') '2026-10-02T03:00:30Z'
    $custom = New-FlashFixtureRelease 'firmware-custom-aaaaaaa' 'custom @ aaaaaaa: x' (New-FlashFixtureBody 'custom' 'custom' 0 '' 'aaaaaaa1234' 'aaaaaaa1234' '件名' '2026-10-02T03:00:00Z') @('a.uf2') '2026-10-02T03:00:20Z'
    $builds = @(ConvertTo-FirmwareBuild @(ConvertFrom-FirmwareJsonArray (ConvertTo-Json -InputObject @($legacy, $custom) -Depth 6)))
    Assert-Equal 'latest' $builds[0].Kind
    Assert-True $builds[0].Legacy '古い形式'
    Assert-Equal 'aaaaaaa1234' $builds[0].Commit
    Assert-Equal 'custom' $builds[0].Branch
    Assert-Equal 'firmware-custom-aaaaaaa' $builds[0].DownloadTag
    Assert-Equal '件名' $builds[0].Title
    Assert-Equal '2026-10-02T03:00:30' $builds[0].Built.ToString('s')

    $alone = @(ConvertTo-FirmwareBuild @(ConvertFrom-FirmwareJsonArray (ConvertTo-Json -InputObject @($legacy) -Depth 6)))
    $label = Format-FirmwareBuildLabel $alone[0] $script:FrUtc
    Assert-Equal 'custom ブランチの最新ビルド' $label.Title
    Assert-Equal 'aaaaaaa · 2026/10/02 03:00' $label.Detail
}

Test-Case 'ビルドの一覧: PR の状態を付ける' {
    $builds = Get-FrLismBuilds -WithStates
    Assert-Equal 'open' $builds[1].State
    Assert-Equal 'merged' $builds[3].State
    Assert-Equal '' $builds[0].State
}

Test-Case '絞り込み: すべて / PR / custom (双子は出さない)' {
    $builds = Get-FrLismBuilds
    Assert-Equal 'firmware-latest,firmware-pr-27,firmware-pr-12,firmware-custom-bbbbbbb' (@(Select-FirmwareBuilds $builds 'all' | ForEach-Object { $_.Tag }) -join ',')
    Assert-Equal 'firmware-pr-27,firmware-pr-12' (@(Select-FirmwareBuilds $builds 'pr' | ForEach-Object { $_.Tag }) -join ',')
    Assert-Equal 'firmware-latest,firmware-custom-bbbbbbb' (@(Select-FirmwareBuilds $builds 'custom' | ForEach-Object { $_.Tag }) -join ',')
    Assert-Equal 0 @(Select-FirmwareBuilds @() 'all').Count
}

Test-Case '表示: バッジ・タイトル・詳細 (PR は head のコミットとブランチ)・PR の状態' {
    $builds = Get-FrLismBuilds -WithStates
    $l = Format-FirmwareBuildLabel $builds[1] $script:FrUtc
    Assert-Equal 'PR #27' $l.Badge
    Assert-Equal 'スクロールを速くする' $l.Title
    Assert-Equal '1111111 · 2026/10/03 05:40 · claude/scroll' $l.Detail
    Assert-Equal 'オープン' $l.StateText
    Assert-True ($l.Tooltip -like '*firmware-pr-27*') 'ツールチップにタグ'
    $latest = Format-FirmwareBuildLabel $builds[0] $script:FrUtc
    Assert-Equal '最新' $latest.Badge
    Assert-Equal 'aaaaaaa · 2026/10/02 03:00' $latest.Detail
    Assert-Equal '' $latest.StateText
    $tokyo = $null
    foreach ($id in @('Tokyo Standard Time', 'Asia/Tokyo')) {
        try { $tokyo = [TimeZoneInfo]::FindSystemTimeZoneById($id); break } catch { }
    }
    if ($null -ne $tokyo) {
        Assert-Equal '1111111 · 2026/10/03 14:40 · claude/scroll' (Format-FirmwareBuildLabel $builds[1] $tokyo).Detail
    }
}

Test-Case 'レート制限の案内: リセットの時刻' {
    $text = Get-FirmwareRateLimitText (New-Object DateTime 2026, 10, 3, 6, 5, 0, ([DateTimeKind]::Utc)) $script:FrUtc
    Assert-True ($text -like '*60 回*') $text
    Assert-True ($text -like '*06:05 以降*') $text
}

Test-Case 'キャッシュ: 保存した応答から同じ一覧を作れる' {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('fr-cache-' + [guid]::NewGuid().ToString('N'))
    try {
        $fetched = New-Object DateTime 2026, 10, 3, 1, 2, 3, ([DateTimeKind]::Utc)
        Save-FirmwareListCache 'o/r' $dir @(New-FlashFixtureLismJson) (New-FlashFixtureIssuesJson) $fetched
        $cache = Read-FirmwareListCache 'o/r' $dir
        Assert-True ($null -ne $cache) 'キャッシュ'
        Assert-Equal '2026-10-03T01:02:03' $cache.FetchedAt.ToString('s')
        $builds = @(ConvertFrom-FirmwareListPages $cache.Pages $cache.Issues)
        Assert-Equal 5 $builds.Count
        Assert-Equal 'open' $builds[1].State
        Assert-Equal $null (Read-FirmwareListCache 'o/none' $dir)
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case '一覧の取得: API から (ページをたどり、PR の状態も取る)' {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('fr-api-' + [guid]::NewGuid().ToString('N'))
    $script:FrCalls = New-Object System.Collections.ArrayList
    function Invoke-FirmwareApi([string]$Uri, [int]$TimeoutSec = 20) {
        [void]$script:FrCalls.Add($Uri)
        if ($Uri -like '*/issues?*') {
            return @{ Ok = $true; Text = (New-FlashFixtureIssuesJson); Next = ''; Remaining = 50; ResetAt = $null; Kind = ''; Status = 200; Message = '' }
        }
        if ($Uri -like '*page=2*') {
            return @{ Ok = $true; Text = '[]'; Next = ''; Remaining = 51; ResetAt = $null; Kind = ''; Status = 200; Message = '' }
        }
        return @{ Ok = $true; Text = (New-FlashFixtureLismJson); Next = 'https://api.github.com/x?page=2'; Remaining = 52; ResetAt = $null; Kind = ''; Status = 200; Message = '' }
    }
    try {
        $result = Get-FirmwareBuildList -Repo 'o/r' -CacheDir $dir
        Assert-Equal 'api' $result.Source
        Assert-Equal 5 $result.Builds.Count
        Assert-Equal 'open' $result.Builds[1].State
        Assert-Equal 3 $script:FrCalls.Count
        Assert-True ($script:FrCalls[0] -like 'https://api.github.com/repos/o/r/releases?per_page=50') $script:FrCalls[0]
        Assert-True ($null -ne (Read-FirmwareListCache 'o/r' $dir)) 'キャッシュに保存'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case '一覧の取得: レート制限なら前回の一覧、それも無ければ最新だけ' {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('fr-limit-' + [guid]::NewGuid().ToString('N'))
    function Invoke-FirmwareApi([string]$Uri, [int]$TimeoutSec = 20) {
        return @{ Ok = $false; Text = ''; Next = ''; Remaining = 0; ResetAt = $null; Kind = 'ratelimit'; Status = 403; Message = 'GitHub API の利用回数の上限に達しました。' }
    }
    function Get-FirmwareBuildInfo([string]$Repo, [string]$Tag, [string]$OutDir) {
        return @{ commit = 'abcdef1234'; built = '2026-10-01T00:00:00Z' }
    }
    try {
        $fallback = Get-FirmwareBuildList -Repo 'o/r' -CacheDir $dir
        Assert-Equal 'fallback' $fallback.Source
        Assert-Equal 3 $fallback.Level
        Assert-True ($fallback.Message -like '*上限*最新のビルドだけ*') $fallback.Message
        Assert-Equal 1 $fallback.Builds.Count
        Assert-Equal 'firmware-latest' $fallback.Builds[0].Tag
        Assert-Equal 'abcdef1234' $fallback.Builds[0].Commit
        Assert-Equal $null $fallback.Builds[0].Assets

        Save-FirmwareListCache 'o/r' $dir @(New-FlashFixtureLismJson) '' ([DateTime]::UtcNow)
        $cached = Get-FirmwareBuildList -Repo 'o/r' -CacheDir $dir
        Assert-Equal 'cache' $cached.Source
        Assert-Equal 5 $cached.Builds.Count
        Assert-True ($cached.Message -like '*前回*') $cached.Message
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'ダウンロード: 途中でビルドが置き換わったら 1 回だけやり直す' {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('fr-dl-' + [guid]::NewGuid().ToString('N'))
    $script:FrInfoCommits = New-Object System.Collections.Queue
    foreach ($c in @('a', 'b', 'b', 'b')) { $script:FrInfoCommits.Enqueue($c) }
    $script:FrFiles = New-Object System.Collections.ArrayList
    function Get-FirmwareBuildInfo([string]$Repo, [string]$Tag, [string]$OutDir) {
        return @{ commit = $script:FrInfoCommits.Dequeue() }
    }
    function Save-FirmwareFile([string]$Repo, [string]$Tag, [string]$Asset, [string]$Dir) {
        [void]$script:FrFiles.Add($Asset)
        return (Join-Path $Dir $Asset)
    }
    try {
        $progress = New-Object System.Collections.ArrayList
        $saved = Save-FirmwareBuild -Repo 'o/r' -Tag 'firmware-pr-1' -Assets @('x.uf2', 'y.uf2', 'x.uf2') -OutDir $dir -Quiet `
            -OnFile { param($Index, $Count, $Asset) [void]$progress.Add(('{0}/{1}:{2}' -f $Index, $Count, $Asset)) }
        Assert-Equal 'x.uf2,y.uf2,x.uf2,y.uf2' ($script:FrFiles -join ',')
        Assert-Equal 'b' $saved.Info['commit']
        Assert-True ($saved.Paths['y.uf2'] -like '*firmware-pr-1*y.uf2') $saved.Paths['y.uf2']
        Assert-Equal '0/2:x.uf2,1/2:y.uf2,0/2:x.uf2,1/2:y.uf2' ($progress -join ',')

        foreach ($c in @('a', 'b', 'c', 'd')) { $script:FrInfoCommits.Enqueue($c) }
        Assert-Throws { Save-FirmwareBuild -Repo 'o/r' -Tag 'firmware-pr-1' -Assets @('x.uf2') -OutDir $dir -Quiet } '*置き換わりました*'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'ダウンロード: 応答の無い失敗 (接続が切れたなど) は 1 回だけやり直す' {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('fr-retry-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Force -Path $dir)
    $oldDelay = $script:FirmwareRetryDelayMs
    $script:FirmwareRetryDelayMs = 0
    $script:FrResults = New-Object System.Collections.Queue
    $script:FrDownloads = 0
    # 'ok' は保存する。'closed' は HTTP の応答が無い失敗、数字はその HTTP の状態コード
    function Invoke-FirmwareDownload([string]$Uri, [string]$OutFile, [int]$TimeoutSec = 0) {
        $script:FrDownloads++
        $next = [string]$script:FrResults.Dequeue()
        if ($next -eq 'ok') {
            [System.IO.File]::WriteAllText($OutFile, 'data')
            return
        }
        throw $next
    }
    function Get-HttpStatusCode($ErrorRecord) {
        $text = $ErrorRecord.Exception.Message
        if ($text -eq 'closed') { return $null }
        return [int]$text
    }
    try {
        foreach ($r in @('closed', 'ok')) { $script:FrResults.Enqueue($r) }
        $path = Save-FirmwareFile 'o/r' 'firmware-pr-1' 'x.uf2' $dir
        Assert-Equal 2 $script:FrDownloads 'やり直して取れた'
        Assert-Equal 'data' ([System.IO.File]::ReadAllText($path))

        $script:FrDownloads = 0
        foreach ($r in @('closed', '404')) { $script:FrResults.Enqueue($r) }
        Assert-Throws { Save-FirmwareFile 'o/r' 'firmware-pr-1' 'x.uf2' $dir } '*firmware-pr-1 リリース*自動で削除*' '切断のあとの 404 は案内'
        Assert-Equal 2 $script:FrDownloads

        $script:FrDownloads = 0
        foreach ($r in @('closed', 'closed')) { $script:FrResults.Enqueue($r) }
        Assert-Throws { Save-FirmwareFile 'o/r' 'firmware-pr-1' 'x.uf2' $dir } '*ダウンロードに失敗しました*' '2 回続けば失敗'
        Assert-Equal 2 $script:FrDownloads

        $script:FrDownloads = 0
        $script:FrResults.Enqueue('500')
        Assert-Throws { Save-FirmwareFile 'o/r' 'firmware-pr-1' 'x.uf2' $dir } '*ダウンロードに失敗しました*' 'HTTP のエラーはやり直さない'
        Assert-Equal 1 $script:FrDownloads
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $dir 'x.uf2.download'))) '途中のファイルを残さない'
    } finally {
        $script:FirmwareRetryDelayMs = $oldDelay
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case '404 の案内: PR / custom のビルドは「自動で削除される」、最新は「ビルドを実行して」' {
    Assert-True ((Get-FirmwareNotFoundText 'o/r' 'firmware-pr-3' 'a.uf2') -like '*自動で削除*') 'pr'
    Assert-True ((Get-FirmwareNotFoundText 'o/r' 'firmware-latest' 'a.uf2') -like '*custom ブランチのビルドを実行*') 'latest'
}

Test-Case 'JSON: 50 件のページより大きい 1.9 MB の配列も読める (5.1 の ConvertFrom-Json の上限 2 MB 未満)' {
    $item = '{"name":"' + ('x' * 1900) + '","assets":[{"name":"a.uf2"}]}'
    $json = '[' + ((1..1000 | ForEach-Object { $item }) -join ',') + ']'
    Assert-True ($json.Length -gt 1900000 -and $json.Length -lt 2000000) ('{0} 文字' -f $json.Length)
    Assert-Equal 1000 @(ConvertFrom-FirmwareJsonArray $json).Count
}
