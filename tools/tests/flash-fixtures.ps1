# 書き込みツールのテスト (firmware-release / flash-ui) で使う、GitHub の releases API の応答の偽物。
# 各リポジトリの .github/scripts/firmware-release.sh が書く本文と同じ形にする。

# リリースの本文 (説明の 1 行と、BUILD_INFO.txt と同じ「キー: 値」の行の ```text ブロック)
function New-FlashFixtureBody([string]$Kind, [string]$Branch, [int]$Pr, [string]$Title, [string]$Head, [string]$Commit,
    [string]$Subject, [string]$Built, [string]$Run = 'https://github.com/o/r/actions/runs/100') {
    $lines = @('ビルドの説明の行です。', '', '```text', 'repository: o/r', "kind: $Kind", "branch: $Branch")
    if ($Kind -eq 'pr') {
        $lines += "pr: $Pr"
        $lines += "title: $Title"
    }
    $lines += "head: $Head"
    $lines += "commit: $Commit"
    $lines += "subject: $Subject"
    $lines += "built: $Built"
    $lines += "run: $Run"
    $lines += '```'
    return ($lines -join "`n")
}

function New-FlashFixtureRelease([string]$Tag, [string]$Name, [string]$Body, [string[]]$Assets, [string]$Created,
    [bool]$Draft = $false) {
    $assetList = @(foreach ($a in $Assets) {
            [ordered]@{ name = $a; size = 1234; uploader = [ordered]@{ login = 'github-actions[bot]'; id = 41898282 } }
        })
    return [ordered]@{
        id           = 1
        tag_name     = $Tag
        name         = $Name
        body         = $Body
        draft        = $Draft
        prerelease   = $true
        created_at   = $Created
        published_at = $Created
        html_url     = "https://github.com/o/r/releases/tag/$Tag"
        assets       = $assetList
    }
}

$script:FlashFixtureLismAssets = @(
    'lism_left_peripheral_non_trackball.uf2', 'lism_left_peripheral_trackball.uf2',
    'lism_right_central_non_trackball.uf2', 'lism_right_central_trackball.uf2',
    'lism_right_central_non_trackball_studio.uf2', 'lism_right_central_trackball_studio.uf2',
    'lism_right_central_non_trackball_logging.uf2', 'lism_right_central_trackball_logging.uf2',
    'settings_reset-seeeduino_xiao_ble-zmk.uf2', 'BUILD_INFO.txt')

# LisM のリリース一覧 (API の 1 ページの JSON):
#   firmware-latest と firmware-custom-aaaaaaa (同じコミット、2026-10-02)、firmware-custom-bbbbbbb (2026-09-20、ログ版なし)、
#   firmware-pr-27 (2026-10-03)、firmware-pr-12 (2026-09-25)、下書きの firmware-pr-30、v1.0.0
function New-FlashFixtureLismJson {
    $all = $script:FlashFixtureLismAssets
    $noLogging = @($all | Where-Object { $_ -notlike '*_logging.uf2' })
    $releases = @(
        (New-FlashFixtureRelease 'firmware-pr-30' 'PR #30 @ ccccccc: 下書き' (New-FlashFixtureBody 'pr' 'x' 30 '下書き' 'ccccccc0' 'ddddddd0' 'x' '2026-10-03T09:00:00Z') $all '2026-10-03T09:00:00Z' $true),
        (New-FlashFixtureRelease 'firmware-pr-27' 'PR #27 @ 1111111: スクロールを速くする' (New-FlashFixtureBody 'pr' 'claude/scroll' 27 'スクロールを速くする' '1111111aaaa' '2222222bbbb' 'WIP' '2026-10-03T05:40:49Z') $all '2026-10-03T05:34:35Z'),
        (New-FlashFixtureRelease 'firmware-latest' 'Latest firmware (custom @ aaaaaaa)' (New-FlashFixtureBody 'custom' 'custom' 0 '' 'aaaaaaa1234' 'aaaaaaa1234' 'AML を直す (#26)' '2026-10-02T03:00:00Z') $all '2026-10-02T03:00:30Z'),
        (New-FlashFixtureRelease 'firmware-custom-aaaaaaa' 'custom @ aaaaaaa: AML を直す (#26)' (New-FlashFixtureBody 'custom' 'custom' 0 '' 'aaaaaaa1234' 'aaaaaaa1234' 'AML を直す (#26)' '2026-10-02T03:00:00Z') $all '2026-10-02T03:00:20Z'),
        (New-FlashFixtureRelease 'firmware-pr-12' 'PR #12 @ 3333333: 古い PR' (New-FlashFixtureBody 'pr' 'claude/old' 12 '古い PR' '3333333cccc' '4444444dddd' 'x' '2026-09-25T00:00:00Z') $all '2026-09-25T00:00:10Z'),
        (New-FlashFixtureRelease 'firmware-custom-bbbbbbb' 'custom @ bbbbbbb: 前のビルド' (New-FlashFixtureBody 'custom' 'custom' 0 '' 'bbbbbbb5678' 'bbbbbbb5678' '前のビルド' '2026-09-20T00:00:00Z') $noLogging '2026-09-20T00:00:10Z'),
        (New-FlashFixtureRelease 'v1.0.0' 'v1.0.0' 'release' @('firmware.zip') '2025-01-01T00:00:00Z')
    )
    return (ConvertTo-Json -InputObject $releases -Depth 6)
}

# /issues の一覧 (PR #27 はオープン、#12 はマージ済み、#5 はクローズ、#3 は issue)
function New-FlashFixtureIssuesJson {
    $issues = @(
        [ordered]@{ number = 27; state = 'open'; pull_request = [ordered]@{ merged_at = $null } },
        [ordered]@{ number = 12; state = 'closed'; pull_request = [ordered]@{ merged_at = '2026-09-26T00:00:00Z' } },
        [ordered]@{ number = 5; state = 'closed'; pull_request = [ordered]@{ merged_at = $null } },
        [ordered]@{ number = 3; state = 'open' }
    )
    return (ConvertTo-Json -InputObject $issues -Depth 4)
}
