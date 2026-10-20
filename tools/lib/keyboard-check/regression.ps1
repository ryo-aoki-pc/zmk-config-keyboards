# 実機の回帰テスト (keyboard-check.ps1 -Mode Regression)。チェックリスト (tools/regression/checks.json) の
# 読み込み・検証・選択、手順の判定、前回の結果、PR 本文の検査。Windows の API を使わないので、どの OS でもテストできる。
# 手順の流れ (ウィンドウ) は regression-test.ps1。
# expected.ps1 / input-eval.ps1 / zmk-log.ps1 が先に読み込まれている前提。
#
# 配列を返す関数 (return , $x) の結果は、いったん変数に入れてからパイプに通す。

$script:KcRegressionSchema = 1
$script:KcRegressionBoards = @('KqMini', 'Keyball39', 'LisM', 'AroundFortyRB', 'KUKEY42', 'Pyuron', 'roBa', 'torabo-tsuki-lp')
$script:KcRegressionZmkBoards = @('LisM', 'AroundFortyRB', 'KUKEY42', 'Pyuron', 'roBa', 'torabo-tsuki-lp')
$script:KcRegressionFirmwares = @('any', 'studio', 'logging')
$script:KcRegressionKeys = @('id', 'title', 'symptom', 'prs', 'boards', 'handler', 'firmware', 'minutes', 'default', 'params', 'fail_hint')

# handler: Fn = regression-test.ps1 の関数、Params = 必須の params、Kind = auto (自動) / semi (半自動) / manual (手動)。
# Values = params の値の候補
$script:KcRegressionHandlers = [ordered]@{
    'manual'        = @{ Fn = 'Invoke-KcRgManual'; Params = @('question'); Kind = 'manual' }
    'readout'       = @{ Fn = 'Invoke-KcRgReadout'; Params = @(); Kind = 'auto' }
    'input-test'    = @{ Fn = 'Invoke-KcRgInputTest'; Params = @('test'); Kind = 'semi'; Values = @{ test = @('shift-click', 'release', 'threshold', 'scroll') } }
    'behaviors'     = @{ Fn = 'Invoke-KcRgBehaviors'; Params = @('kinds'); Kind = 'semi' }
    'ball-alive'    = @{ Fn = 'Invoke-KcRgBallAlive'; Params = @('duration_ms'); Kind = 'semi' }
    'typing-no-aml' = @{ Fn = 'Invoke-KcRgTypingNoAml'; Params = @('repeat'); Kind = 'semi' }
    'aml-extend'    = @{ Fn = 'Invoke-KcRgAmlExtend'; Params = @('extra_ms', 'check_within_ms'); Kind = 'semi' }
    'replug'        = @{ Fn = 'Invoke-KcRgReplug'; Params = @('targets', 'repeat'); Kind = 'semi' }
    'bootmagic'     = @{ Fn = 'Invoke-KcRgBootmagic'; Params = @('sides'); Kind = 'semi' }
    'logging-soak'  = @{ Fn = 'Invoke-KcRgLoggingSoak'; Params = @('dumps', 'max_ms'); Kind = 'semi' }
    'idle-wake'     = @{ Fn = 'Invoke-KcRgIdleWake'; Params = @('keys'); Kind = 'semi' }
    'drag-hold'     = @{ Fn = 'Invoke-KcRgDragHold'; Params = @(); Kind = 'semi' }
}
$script:KcRegressionKindNames = @{ auto = '自動'; semi = '半自動'; manual = '手動' }
$script:KcRegressionFirmwareNames = @{ any = ''; studio = 'Studio 版'; logging = 'ログ版'; normal = '通常版' }
$script:KcRegressionStatusOrder = @{ PASS = 0; SKIP = 1; WARN = 2; FAIL = 3 }

# ---------------------------------------------------------------------------
# チェックリストの読み込みと検証
# ---------------------------------------------------------------------------

function Read-KcRegressionDocument([string]$Path) {
    return (Read-KcJson $Path)
}

# .gitmodules の submodule の名前 (path) と、このリポジトリ (zmk-config-keyboards)。prs に書ける repo
function Get-KcRegressionRepos([string]$GitmodulesText) {
    $repos = New-Object 'System.Collections.Generic.List[string]'
    $repos.Add('zmk-config-keyboards')
    foreach ($m in [regex]::Matches($GitmodulesText, '(?m)^\s*path\s*=\s*(\S+)\s*$')) {
        $repos.Add($m.Groups[1].Value)
    }
    return , $repos.ToArray()
}

# 1 件の check (JSON のオブジェクト) → 既定を補ったもの
function ConvertTo-KcRegressionCheck($Raw) {
    $params = Get-KcProp $Raw 'params' $null
    if ($null -eq $params) {
        $params = [pscustomobject]@{}
    }
    $minutes = Get-KcProp $Raw 'minutes' 1
    $default = Get-KcProp $Raw 'default' $true
    return [pscustomobject]@{
        Id = [string](Get-KcProp $Raw 'id' ''); Title = [string](Get-KcProp $Raw 'title' ''); Symptom = [string](Get-KcProp $Raw 'symptom' '')
        Prs = @(Get-KcProp $Raw 'prs' @()); Boards = @(Get-KcProp $Raw 'boards' @()); Handler = [string](Get-KcProp $Raw 'handler' '')
        Firmware = [string](Get-KcProp $Raw 'firmware' 'any'); Minutes = $minutes; Default = $default
        Params = $params; FailHint = [string](Get-KcProp $Raw 'fail_hint' ''); Raw = $Raw
    }
}

function Get-KcRegressionChecks($Document) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($c in @(Get-KcProp $Document 'checks' @())) {
        $out.Add((ConvertTo-KcRegressionCheck $c))
    }
    return , $out.ToArray()
}

# 値が空か (null / 空の文字列 / 空の配列)
function Test-KcRegressionEmpty($Value) {
    if ($null -eq $Value) {
        return $true
    }
    if ($Value -is [string]) {
        return (-not $Value.Trim())
    }
    if ($Value -is [System.Array]) {
        return ($Value.Count -eq 0)
    }
    return $false
}

# チェックリストの誤り (文字列の配列。空なら正しい)。$Repos: prs に書ける repo の名前
function Test-KcRegressionDocument($Document, [string[]]$Repos) {
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $schema = Get-KcProp $Document 'schema' $null
    if ($schema -ne $script:KcRegressionSchema) {
        $errors.Add(('schema は {0} にしてください (今: {1})' -f $script:KcRegressionSchema, $schema))
    }
    $raws = @(Get-KcProp $Document 'checks' @())
    if ($raws.Count -eq 0) {
        $errors.Add('checks が空です')
    }
    $seen = @{}
    $n = 0
    foreach ($raw in $raws) {
        $n++
        $c = ConvertTo-KcRegressionCheck $raw
        $where = if ($c.Id) { $c.Id } else { '{0} 件目' -f $n }
        foreach ($p in @($raw.PSObject.Properties)) {
            if ($script:KcRegressionKeys -notcontains $p.Name) {
                $errors.Add(('{0}: 知らない項目 {1} があります' -f $where, $p.Name))
            }
        }
        if ($c.Id -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
            $errors.Add(('{0}: id は英小文字・数字とハイフン (kebab-case) にしてください' -f $where))
        } elseif ($seen.ContainsKey($c.Id)) {
            $errors.Add(('{0}: id が重なっています' -f $where))
        }
        $seen[$c.Id] = $true
        if (Test-KcRegressionEmpty $c.Title) { $errors.Add(('{0}: title が空です' -f $where)) }
        if (Test-KcRegressionEmpty $c.Symptom) { $errors.Add(('{0}: symptom (過去に起きたこと) が空です' -f $where)) }
        if ($c.Prs.Count -eq 0) {
            $errors.Add(('{0}: prs (直した PR) が空です' -f $where))
        }
        foreach ($pr in $c.Prs) {
            $m = [regex]::Match([string]$pr, '^([A-Za-z0-9._-]+)#([1-9]\d*)$')
            if (-not $m.Success) {
                $errors.Add(('{0}: prs の {1} は <repo>#<番号> の形にしてください' -f $where, $pr))
            } elseif ($null -ne $Repos -and $Repos -notcontains $m.Groups[1].Value) {
                $errors.Add(('{0}: prs の repo {1} は、submodule の名前でも zmk-config-keyboards でもありません' -f $where, $m.Groups[1].Value))
            }
        }
        if ($c.Boards.Count -eq 0) {
            $errors.Add(('{0}: boards が空です' -f $where))
        }
        foreach ($b in $c.Boards) {
            if (@('all', 'zmk') -notcontains [string]$b -and $script:KcRegressionBoards -notcontains [string]$b) {
                $errors.Add(('{0}: boards の {1} は機種のキーか zmk / all にしてください' -f $where, $b))
            }
        }
        if ($script:KcRegressionFirmwares -notcontains $c.Firmware) {
            $errors.Add(('{0}: firmware は {1} のどれかにしてください' -f $where, ($script:KcRegressionFirmwares -join ' / ')))
        }
        $min = 0.0
        if (-not [double]::TryParse([string]$c.Minutes, [ref]$min) -or $min -le 0) {
            $errors.Add(('{0}: minutes は正の数にしてください' -f $where))
        }
        if ($c.Default -isnot [bool]) {
            $errors.Add(('{0}: default は true / false にしてください' -f $where))
        }
        if (-not $script:KcRegressionHandlers.Contains($c.Handler)) {
            $errors.Add(('{0}: handler の {1} はありません ({2})' -f $where, $c.Handler, (@($script:KcRegressionHandlers.Keys) -join ' / ')))
            continue
        }
        $spec = $script:KcRegressionHandlers[$c.Handler]
        foreach ($k in @($spec.Params)) {
            if (Test-KcRegressionEmpty (Get-KcProp $c.Params $k $null)) {
                $errors.Add(('{0}: handler {1} には params.{2} が要ります' -f $where, $c.Handler, $k))
            }
        }
        # 中の項目の必須 (replug の targets、bootmagic の sides)
        $inner = @{ replug = @('targets', @('label', 'plug', 'unplug', 'keys')); bootmagic = @('sides', @('label', 'key')) }
        if ($inner.ContainsKey($c.Handler)) {
            $list = $inner[$c.Handler][0]
            $i = 0
            foreach ($t in @(Get-KcProp $c.Params $list @())) {
                $i++
                foreach ($k in @($inner[$c.Handler][1])) {
                    if (Test-KcRegressionEmpty (Get-KcProp $t $k $null)) {
                        $errors.Add(('{0}: params.{1} の {2} 件目に {3} が要ります' -f $where, $list, $i, $k))
                    }
                }
                if ($c.Handler -eq 'replug') {
                    $start = [string](Get-KcProp $t 'start' 'unplugged')
                    if (@('unplugged', 'plugged') -notcontains $start) {
                        $errors.Add(('{0}: params.targets の {1} 件目の start は unplugged / plugged にしてください' -f $where, $i))
                    }
                }
            }
        }
        if ($spec.ContainsKey('Values')) {
            foreach ($k in @($spec.Values.Keys)) {
                $v = Get-KcProp $c.Params $k $null
                if ($null -ne $v -and @($spec.Values[$k]) -notcontains [string]$v) {
                    $errors.Add(('{0}: params.{1} は {2} のどれかにしてください' -f $where, $k, (@($spec.Values[$k]) -join ' / ')))
                }
            }
        }
    }
    return , $errors.ToArray()
}

# どの項目にも使われていない handler (使わない handler を残さない)
function Get-KcRegressionUnusedHandlers($Checks) {
    $used = @{}
    foreach ($c in @($Checks)) {
        $used[$c.Handler] = $true
    }
    return , @(@($script:KcRegressionHandlers.Keys) | Where-Object { -not $used.ContainsKey($_) })
}

# ---------------------------------------------------------------------------
# 機種・ファームでの絞り込みと選択
# ---------------------------------------------------------------------------

function Test-KcRegressionZmkBoard([string]$Board) {
    return ($script:KcRegressionZmkBoards -contains $Board)
}

function Test-KcRegressionApplies($Check, [string]$Board) {
    foreach ($b in @($Check.Boards)) {
        if ($b -eq 'all' -or $b -eq $Board) {
            return $true
        }
        if ($b -eq 'zmk' -and (Test-KcRegressionZmkBoard $Board)) {
            return $true
        }
    }
    return $false
}

# 機種に当てはまる項目。$Firmware: ZMK の右手側のファーム (normal / studio / logging。QMK の機種は空)。
# Ready = 今のファームで行える、Default = Enter で行う、Need = 行えないときに要るもの
function Select-KcRegressionChecks($Checks, [string]$Board, [string]$Firmware) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    $i = 0
    foreach ($c in @($Checks)) {
        if (-not (Test-KcRegressionApplies $c $Board)) {
            continue
        }
        $i++
        $ready = $true
        $need = ''
        if ($c.Firmware -ne 'any' -and (Test-KcRegressionZmkBoard $Board) -and $c.Firmware -ne $Firmware) {
            $ready = $false
            $need = '右手側が「{0}」のとき' -f $script:KcRegressionFirmwareNames[$c.Firmware]
        }
        $out.Add([pscustomobject]@{ Index = $i; Check = $c; Ready = $ready; Default = ($ready -and [bool]$c.Default); Need = $need })
    }
    return , $out.ToArray()
}

# 選択の文字列 → 番号の配列 (1 から)。空 = 既定、all = すべて、"2,4-6" = 番号。正しくなければ $null
function ConvertFrom-KcRegressionSelection([string]$Text, [int]$Count, [int[]]$Defaults) {
    $t = ([string]$Text).Trim()
    if (-not $t) {
        return , @($Defaults)
    }
    if ($t -eq 'all') {
        if ($Count -le 0) {
            return , @()
        }
        return , @(1..$Count)
    }
    $picked = New-Object 'System.Collections.Generic.List[int]'
    foreach ($part in ($t -split '[,、\s]+')) {
        if (-not $part) {
            continue
        }
        $m = [regex]::Match($part, '^(\d+)(?:-(\d+))?$')
        if (-not $m.Success) {
            return $null
        }
        $a = [int]$m.Groups[1].Value
        $b = $a
        if ($m.Groups[2].Success) {
            $b = [int]$m.Groups[2].Value
        }
        if ($a -lt 1 -or $b -gt $Count -or $a -gt $b) {
            return $null
        }
        for ($k = $a; $k -le $b; $k++) {
            if (-not $picked.Contains($k)) {
                $picked.Add($k)
            }
        }
    }
    if ($picked.Count -eq 0) {
        return $null
    }
    return , $picked.ToArray()
}

# -Check の id → 項目 (Selected の並び)。知らない id は Unknown に入れる
function Resolve-KcRegressionIds($Entries, [string[]]$Ids) {
    $byId = @{}
    foreach ($e in @($Entries)) {
        $byId[$e.Check.Id] = $e
    }
    $picked = New-Object 'System.Collections.Generic.List[object]'
    $unknown = New-Object 'System.Collections.Generic.List[string]'
    foreach ($raw in @($Ids)) {
        foreach ($id in ([string]$raw -split ',')) {
            $id = $id.Trim()
            if (-not $id) {
                continue
            }
            if ($id -eq 'all') {
                foreach ($e in @($Entries)) {
                    if (-not $picked.Contains($e)) { $picked.Add($e) }
                }
            } elseif ($byId.ContainsKey($id)) {
                if (-not $picked.Contains($byId[$id])) { $picked.Add($byId[$id]) }
            } else {
                $unknown.Add($id)
            }
        }
    }
    return [pscustomobject]@{ Selected = $picked.ToArray(); Unknown = $unknown.ToArray() }
}

function Format-KcRegressionPrs($Check) {
    return (@($Check.Prs) -join ', ')
}

# 一覧の行 (コンソールに出す)。$History: Read-KcRegressionHistory の結果
function Format-KcRegressionList($Entries, $History, [string]$Board) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($e in @($Entries)) {
        $c = $e.Check
        $mark = if ($e.Default) { '*' } else { ' ' }
        $kind = $script:KcRegressionKindNames[$script:KcRegressionHandlers[$c.Handler].Kind]
        $line = '  {0} {1,2}. {2}  [{3}・{4} 分]' -f $mark, $e.Index, $c.Title, $kind, $c.Minutes
        $last = Get-KcRegressionLast $History $Board $c.Id
        if ($null -ne $last) {
            $time = Format-KcRegressionTime (Get-KcProp $last 'time' '')
            $line += ('  前回: {0} ({1})' -f [string](Get-KcProp $last 'status' ''), $time.Substring(0, [math]::Min(10, $time.Length)))
        }
        $lines.Add($line)
        $notes = @(('id: {0}' -f $c.Id))
        if (-not $e.Ready) {
            $notes += $e.Need
        } elseif (-not [bool]$c.Default) {
            $notes += '既定では行わない (時間がかかる・ブートローダに入れるなど)'
        }
        $notes += ('PR: {0}' -f (Format-KcRegressionPrs $c))
        $lines.Add(('         {0}' -f ($notes -join ' / ')))
    }
    return , $lines.ToArray()
}

# ---------------------------------------------------------------------------
# 結果
# ---------------------------------------------------------------------------

# 項目の判定 = 中の行のいちばん悪いもの (FAIL > WARN > SKIP > PASS)。INFO と参考の行は数えない。行が無ければ SKIP
function Get-KcRegressionStatus($Rows) {
    $worst = $null
    # List を @() で包むと、Linux の pwsh 7.4 で「Argument types do not match」になるので、そのまま回す
    foreach ($r in $Rows) {
        if ($r.Status -eq 'INFO' -or [bool](Get-KcProp $r 'Reference' $false)) {
            continue
        }
        if ($null -eq $worst -or $script:KcRegressionStatusOrder[$r.Status] -gt $script:KcRegressionStatusOrder[$worst]) {
            $worst = $r.Status
        }
    }
    if ($null -eq $worst) {
        return 'SKIP'
    }
    return $worst
}

# 項目の内容のハッシュ (前回の結果が、今の項目と同じ内容で行ったものかを見分ける)
function Get-KcRegressionCheckHash($Check) {
    $json = $Check.Raw | ConvertTo-Json -Depth 20 -Compress
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))
    } finally {
        $sha.Dispose()
    }
    return (-join ($bytes[0..3] | ForEach-Object { $_.ToString('x2') }))
}

function Read-KcRegressionHistory([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return , @()
    }
    try {
        $doc = Read-KcJson $Path
        return , @(Get-KcProp $doc 'runs' @())
    } catch {
        return , @()
    }
}

# $Entries: @{ time; board; check; status; hash; firmware; expected; transport }。新しいものから 500 件を残す
function Add-KcRegressionHistory([string]$Path, $Entries) {
    $all = New-Object 'System.Collections.Generic.List[object]'
    foreach ($e in (Read-KcRegressionHistory $Path)) {
        $all.Add($e)
    }
    foreach ($e in @($Entries)) {
        $all.Add([pscustomobject]$e)
    }
    $keep = $all.ToArray()
    if ($keep.Count -gt 500) {
        $keep = $keep[($keep.Count - 500)..($keep.Count - 1)]
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Force -Path $dir)
    }
    $json = ([pscustomobject]@{ schema = 1; runs = @($keep) }) | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# 前回の結果の時刻 (pwsh 7 の ConvertFrom-Json は、日時の形の文字列を DateTime にすることがある)
function Format-KcRegressionTime($Value) {
    if ($Value -is [datetime]) {
        return $Value.ToString('yyyy-MM-dd HH:mm')
    }
    return [string]$Value
}

function Get-KcRegressionLast($History, [string]$Board, [string]$CheckId) {
    $last = $null
    foreach ($h in @($History)) {
        if ([string](Get-KcProp $h 'board' '') -eq $Board -and [string](Get-KcProp $h 'check' '') -eq $CheckId) {
            $last = $h
        }
    }
    return $last
}

# ---------------------------------------------------------------------------
# 手順の判定
# ---------------------------------------------------------------------------

# Raw Input のデバイスが、この機種のものか (VID / PID)。Keyball39 は PID の上位バイト (02) だけで見分ける
# (keyboard-check.ps1 の Find-KcRawHidInterface -ProductHighByte 2 と同じ)
function Test-KcRgDeviceMatch($Expected, [string]$Vid, [string]$ProductId) {
    $wantVid = [string]$Expected.device.usb_vid
    $wantPid = [string]$Expected.device.usb_pid
    if (-not [string]::Equals($Vid, $wantVid, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if ([string]$Expected.id -eq 'keyball39') {
        return ($ProductId.Length -eq 4 -and [string]::Equals($ProductId.Substring(0, 2), $wantPid.Substring(0, 2), [System.StringComparison]::OrdinalIgnoreCase))
    }
    return [string]::Equals($ProductId, $wantPid, [System.StringComparison]::OrdinalIgnoreCase)
}

# キーの表示 (Q / P / D など) → HID usage (common.json の hid_keys の label)。無ければ -1
function Get-KcUsageByLegend([string]$Legend, $ScanTable) {
    foreach ($u in @($ScanTable.ByUsage.Keys)) {
        if ([string]::Equals([string]$ScanTable.ByUsage[$u].label, $Legend, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [int]$u
        }
    }
    return -1
}

function New-KcRgResult([string]$Status, [string]$Actual, [string]$Message = '', [string[]]$Details = @()) {
    return [pscustomobject]@{ Status = $Status; Actual = $Actual; Message = $Message; Details = @($Details) }
}

# ボールを転がし続けたか。$StartTime / $EndTime: 手順の始まりと終わり (Form.NowMs)。
#   PASS: 最後の $EndMs にもボールの動きがあり、キーが $MinKeys 回以上届いた
#   STOPPED: ボールの動きが途中で止まり (または初めから無く)、その後もキーは届いた (キーは効くのにボールが止まる = #52 の症状。
#            人が転がすのをやめただけのこともあるので、呼び出し側が尋ねる)
#   NONE: 操作が足りない (キーが届かない、何も届かない)
function Test-KcBallAlive($Events, [long]$StartTime, [long]$EndTime, [int]$EndMs, $ScanTable, [int]$MinKeys = 2) {
    $moves = @($Events | Where-Object { $_.Kind -eq 'mouse' -and ($_.Dx -ne 0 -or $_.Dy -ne 0) -and $_.Time -ge $StartTime -and $_.Time -le $EndTime })
    $actions = ConvertTo-KcKeyActions $Events $ScanTable
    $downs = @($actions | Where-Object { $_.Down -and $_.Time -ge $StartTime -and $_.Time -le $EndTime })
    $details = New-Object 'System.Collections.Generic.List[string]'
    $details.Add(('ボールの入力 {0} 回、キーの押下 {1} 回' -f $moves.Count, $downs.Count))
    if ($moves.Count -gt 0) {
        $gap = 0
        for ($i = 1; $i -lt $moves.Count; $i++) {
            $gap = [math]::Max($gap, [long]$moves[$i].Time - [long]$moves[$i - 1].Time)
        }
        $details.Add(('動き始め {0:N1} 秒、最後の動き {1:N1} 秒 (手順は {2:N1} 秒)、いちばん長い途切れ {3:N1} 秒' -f `
                    (([long]$moves[0].Time - $StartTime) / 1000.0), (([long]$moves[$moves.Count - 1].Time - $StartTime) / 1000.0),
                (($EndTime - $StartTime) / 1000.0), ($gap / 1000.0)))
    }
    $lastMove = if ($moves.Count -gt 0) { [long]$moves[$moves.Count - 1].Time } else { [long]::MinValue }
    if ($moves.Count -gt 0 -and $lastMove -ge ($EndTime - $EndMs)) {
        if ($downs.Count -ge $MinKeys) {
            return (New-KcRgResult 'PASS' ('最後までボールが動き、キーも {0} 回届いた' -f $downs.Count) '' $details.ToArray())
        }
        return (New-KcRgResult 'NONE' ('キーが {0} 回しか届いていない' -f $downs.Count) '途中と最後に、決めたキーを押してください' $details.ToArray())
    }
    $keysAfter = @($downs | Where-Object { $_.Time -gt $lastMove })
    if ($keysAfter.Count -gt 0) {
        $what = if ($moves.Count -eq 0) { 'ボールの動きが届かない' } else { 'ボールの動きが途中で止まった' }
        return (New-KcRgResult 'STOPPED' ('{0} (その後もキーは届いた)' -f $what) 'キーは効くのに、ボールの動きが届いていません' $details.ToArray())
    }
    return (New-KcRgResult 'NONE' '入力が足りない' 'カウントダウンが終わるまでボールを転がし続け、途中と最後にキーを押してください' $details.ToArray())
}

# 速く打ったキー: クリック・ホイールが出ず、$Usages のキーがそれぞれ $Repeat 回以上届いた
function Test-KcTypingNoAml($Events, [int[]]$Usages, [int]$Repeat, $ScanTable) {
    $motion = Measure-KcMotion $Events
    $actions = ConvertTo-KcKeyActions $Events $ScanTable
    $downs = @($actions | Where-Object { $_.Down })
    $clicks = @($motion.Buttons | Where-Object { $_.Down })
    $wheels = $motion.WheelPos + $motion.WheelNeg + $motion.HWheelPos + $motion.HWheelNeg
    $counts = @()
    foreach ($u in $Usages) {
        $counts += @($downs | Where-Object { $_.Usage -eq $u }).Count
    }
    $text = (@(for ($i = 0; $i -lt $Usages.Count; $i++) { '{0} {1} 回' -f (Get-KcUsageLabel $Usages[$i] $ScanTable), $counts[$i] }) -join '、')
    $details = @($text, ('ボールの動き {0}、クリック {1}、ホイール {2}' -f ($motion.AbsX + $motion.AbsY), $clicks.Count, $wheels))
    if ($clicks.Count -gt 0 -or $wheels -gt 0) {
        return (New-KcRgResult 'FAIL' ('クリック {0} 回・ホイール {1} 回が出た' -f $clicks.Count, $wheels) 'キーを打っただけで AML (マウスレイヤー) になりました' $details)
    }
    if ($downs.Count -lt ($Usages.Count * $Repeat)) {
        return (New-KcRgResult 'NONE' ('キーが {0} 回しか届いていない' -f $downs.Count) ('表示したキーを {0} 回ずつ、速く打ってください' -f $Repeat) $details)
    }
    for ($i = 0; $i -lt $Usages.Count; $i++) {
        if ($counts[$i] -lt $Repeat) {
            return (New-KcRgResult 'FAIL' $text ('「{0}」が {1} 回しか届いていません (AML になってスクロールのキーなどになった?)' -f (Get-KcUsageLabel $Usages[$i] $ScanTable), $counts[$i]) $details)
        }
    }
    return (New-KcRgResult 'PASS' $text '' $details)
}

# AML がまだ有効か: ボールを動かさずに、スクロールのキーを押したままクリックのキー → クリックになり、文字は出ない。
# $SinceScrollMs: 最後のスクロールからクリックまでの時間 (AML のタイムアウトに近いと、正しく切れたのか分からない)
function Test-KcAmlStillOn($Events, [int]$Button, [int]$ScrollUsage, [int]$ClickUsage, [int]$Threshold, $ScanTable, [long]$LastScroll, [int]$TimeoutMs) {
    $motion = Measure-KcMotion $Events
    $actions = ConvertTo-KcKeyActions $Events $ScanTable
    $letters = @($actions | Where-Object { $_.Down -and ($_.Usage -eq $ScrollUsage -or $_.Usage -eq $ClickUsage) })
    $clicks = @($motion.Buttons | Where-Object { $_.Down -and $_.Button -eq $Button })
    $path = $motion.AbsX + $motion.AbsY
    if ($Threshold -gt 0 -and $path -ge $Threshold) {
        return (New-KcRgResult 'NONE' ('ボールの動き {0}' -f $path) 'D を離したあとは、ボールに触らずにキーだけを押してください (転がすと AML がまた発動します)')
    }
    # 押した最初の時刻 (キーの押下か、ボタンの押下。離したときの入力は数えない)
    $downs = @(@($actions | Where-Object { $_.Down } | ForEach-Object { [long]$_.Time }) + @($motion.Buttons | Where-Object { $_.Down } | ForEach-Object { [long]$_.Time }) | Sort-Object)
    if ($downs.Count -gt 0 -and $LastScroll -gt 0 -and ($downs[0] - $LastScroll) -ge ($TimeoutMs - 1000)) {
        return (New-KcRgResult 'NONE' ('最後のスクロールから {0:N1} 秒' -f (($downs[0] - $LastScroll) / 1000.0)) 'D を離したら、すぐに押してください (AML のタイムアウトが来てしまいます)')
    }
    # 先に起きたほうで決める (クリックのあとに、AML が切れて文字が出ても、AML は残っていた)
    $firstClick = if ($clicks.Count -gt 0) { [long]$clicks[0].Time } else { [long]::MaxValue }
    $firstLetter = if ($letters.Count -gt 0) { [long]$letters[0].Time } else { [long]::MaxValue }
    if ($letters.Count -gt 0 -and $firstLetter -lt $firstClick) {
        $t = (@($letters | ForEach-Object { Get-KcKeyLabel $_ $ScanTable }) -join ' + ')
        return (New-KcRgResult 'FAIL' ('キー入力: ' + $t) 'スクロールの間に AML が切れていました (文字が入力されました)')
    }
    if ($clicks.Count -gt 0) {
        return (New-KcRgResult 'PASS' ('ボタン {0} のクリック (AML が残っていた)' -f $Button))
    }
    return (New-KcRgResult 'NONE' '(入力なし)')
}

# ドラッグ中のキー (KQ-mini#14): ボタンの押下 → Ctrl の押下 → Ctrl の解放 → ボタンの解放、の間にボタンが離されず、
# その間にボールが動いた
function Test-KcDragHold($Events, [int]$Button, [int[]]$CtrlUsages, $ScanTable) {
    $motion = Measure-KcMotion $Events
    $btn = @($motion.Buttons | Where-Object { $_.Button -eq $Button })
    $downs = @($btn | Where-Object { $_.Down })
    $ups = @($btn | Where-Object { -not $_.Down })
    if ($downs.Count -eq 0) {
        return (New-KcRgResult 'NONE' '(ボタンの押下なし)' 'ボールを転がしてから、D を押したまま F を押してください')
    }
    $actions = ConvertTo-KcKeyActions $Events $ScanTable
    $ctrl = @($actions | Where-Object { $CtrlUsages -contains $_.Usage })
    $down = [long]$downs[0].Time
    $ctrlDown = @($ctrl | Where-Object { $_.Down -and $_.Time -ge $down })
    if ($ups.Count -eq 0) {
        return (New-KcRgResult 'NONE' '(ボタンを離していない)' '最後に F を離してください')
    }
    $up = [long]$ups[$ups.Count - 1].Time
    if ($downs.Count -gt 1 -or $ups.Count -gt 1) {
        return (New-KcRgResult 'FAIL' ('ボタンの押下 {0} 回・解放 {1} 回' -f $downs.Count, $ups.Count) 'ドラッグの途中でボタンが離されました')
    }
    if ($ctrlDown.Count -eq 0) {
        if (@($ctrl | Where-Object { $_.Down }).Count -gt 0) {
            return (New-KcRgResult 'NONE' '(Ctrl がボタンより先)' 'F でボタンを押してから、A を長押ししてください')
        }
        return (New-KcRgResult 'NONE' '(Ctrl なし)' 'ドラッグの途中で A を長押し (Ctrl) してください')
    }
    $ctrlUp = @($ctrl | Where-Object { -not $_.Down -and $_.Time -ge [long]$ctrlDown[0].Time })
    if ($ctrlUp.Count -eq 0) {
        if ($up -gt [long]$ctrlDown[0].Time) {
            return (New-KcRgResult 'FAIL' 'Ctrl を押している間にボタンが離された' 'キーを押したときに、KQ-mini がマウスボタンを離しました')
        }
        return (New-KcRgResult 'NONE' '(Ctrl を離していない)' 'A を離してから F を離してください')
    }
    # ドラッグ中の Ctrl の押す / 離すが (何回でも) 全部終わってから、ボタンが離されたか
    $lastCtrl = [long]@($ctrl | Where-Object { $_.Time -ge $down } | ForEach-Object { [long]$_.Time } | Sort-Object)[-1]
    $ctrlHeldAtUp = $false
    foreach ($a in @($ctrl | Where-Object { $_.Time -le $up } | Sort-Object -Property Time)) {
        $ctrlHeldAtUp = [bool]$a.Down
    }
    if ($up -lt $lastCtrl -or $ctrlHeldAtUp) {
        return (New-KcRgResult 'FAIL' 'Ctrl を押している間にボタンが離された' 'キーを押したときに、KQ-mini がマウスボタンを離しました')
    }
    $moved = @($Events | Where-Object { $_.Kind -eq 'mouse' -and ($_.Dx -ne 0 -or $_.Dy -ne 0) -and $_.Time -gt $down -and $_.Time -lt $up })
    if ($moved.Count -eq 0) {
        return (New-KcRgResult 'NONE' '(ドラッグ中の動きなし)' 'F を押したまま、ボールを転がしてください')
    }
    return (New-KcRgResult 'PASS' ('ボタンを押したまま Ctrl を押して離し、ボールも動いた (動き {0} 回)' -f $moved.Count))
}

# ---------------------------------------------------------------------------
# ログ版のログ (logging-soak)
# ---------------------------------------------------------------------------

# ログの行 → ダンプの数、スレッドごとの最大使用量、取得失敗、fatal、時刻の巻き戻り (再起動)
function Measure-KcLoggingSoak([string[]]$Lines) {
    $threads = [ordered]@{}
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $fatal = New-Object 'System.Collections.Generic.List[string]'
    $dumps = 0
    $logLines = 0
    $lastTime = -1.0
    $rewinds = 0
    foreach ($line in @($Lines)) {
        if (Test-KcZmkLogFatal $line) {
            $fatal.Add((Remove-KcAnsi $line))
        }
        $rec = ConvertFrom-KcZmkLogLine $line
        if ($null -ne $rec -and $rec.Time -ge 0) {
            $logLines++
            if ($lastTime -ge 0 -and $rec.Time -lt ($lastTime - 1000)) {
                $rewinds++
            }
            $lastTime = [double]$rec.Time
        }
        $ta = ConvertFrom-KcThreadAnalyzerLine $line
        if ($null -eq $ta) {
            continue
        }
        switch ($ta.Kind) {
            'header' { $dumps++ }
            'thread' {
                if (-not $threads.Contains($ta.Name) -or $ta.Usage -gt $threads[$ta.Name].Usage) {
                    $threads[$ta.Name] = [pscustomobject]@{ Name = $ta.Name; Usage = $ta.Usage; Size = $ta.Size; Pct = $ta.Pct }
                }
            }
            'error' {
                if (-not $errors.Contains($ta.Name)) { $errors.Add($ta.Name) }
            }
        }
    }
    return [pscustomobject]@{
        Dumps = $dumps; Threads = @($threads.Values); Errors = $errors.ToArray(); Fatal = $fatal.ToArray()
        Rewinds = $rewinds; LogLines = $logLines
    }
}

# スレッドの使用率の判定。$NormalInput: 通常版の入力スレッドのスタック (期待値の device.stacks.input。無ければ 0)
# 戻り値: 行の配列 (@{ Item; Status; Actual; Message; Details })
function Get-KcLoggingSoakRows($Soak, [int]$Dumps, [int]$WarnPct, [int]$FailPct, [int]$NormalInput, [int]$NormalWarnPct) {
    $rows = New-Object 'System.Collections.Generic.List[object]'
    if ($Soak.Fatal.Count -gt 0 -or $Soak.Rewinds -gt 0) {
        $what = @()
        if ($Soak.Fatal.Count -gt 0) { $what += ('fatal error の行 {0} 件' -f $Soak.Fatal.Count) }
        if ($Soak.Rewinds -gt 0) { $what += ('ファームの時刻の巻き戻り {0} 回 (再起動した)' -f $Soak.Rewinds) }
        $rows.Add([pscustomobject]@{ Item = '再起動・異常が無い'; Status = 'FAIL'; Actual = ($what -join '、'); Message = 'ファームが落ちたか、再起動しました'; Details = @($Soak.Fatal | Select-Object -First 10) })
    } else {
        $rows.Add([pscustomobject]@{ Item = '再起動・異常が無い'; Status = 'PASS'; Actual = ('ログ {0} 行' -f $Soak.LogLines); Message = ''; Details = @() })
    }
    if ($Soak.Dumps -lt $Dumps -or $Soak.Threads.Count -eq 0) {
        $rows.Add([pscustomobject]@{ Item = 'thread analyzer'; Status = 'WARN'; Actual = ('{0} 回 (期待 {1} 回以上)' -f $Soak.Dumps, $Dumps)
                Message = 'thread analyzer の行が足りません。ログ版のファームが古いか、時間が足りません'; Details = @() })
    }
    if ($Soak.Threads.Count -gt 0) {
        $status = 'PASS'
        $details = New-Object 'System.Collections.Generic.List[string]'
        foreach ($t in @($Soak.Threads | Sort-Object -Property Pct -Descending)) {
            $mark = ''
            if ($t.Pct -ge $FailPct) { $status = 'FAIL'; $mark = ' ← 足りない' }
            elseif ($t.Pct -ge $WarnPct) { if ($status -ne 'FAIL') { $status = 'WARN' }; $mark = ' ← 余裕が少ない' }
            $details.Add(('{0}: {1} / {2} バイト ({3} %){4}' -f $t.Name, $t.Usage, $t.Size, $t.Pct, $mark))
        }
        foreach ($e in $Soak.Errors) {
            if ($status -eq 'PASS') { $status = 'WARN' }
            $details.Add(('{0}: 使用量を取れなかった' -f $e))
        }
        $top = @($Soak.Threads | Sort-Object -Property Pct -Descending)[0]
        $rows.Add([pscustomobject]@{ Item = ('スタックの余裕 ({0} % 未満)' -f $WarnPct); Status = $status
                Actual = ('いちばん高い {0}: {1} %' -f $top.Name, $top.Pct); Message = ''; Details = $details.ToArray() })
        $inputThread = @($Soak.Threads | Where-Object { $_.Name -eq 'input' })
        if ($inputThread.Count -gt 0 -and $NormalInput -gt 0) {
            $pct = [math]::Round(100.0 * $inputThread[0].Usage / $NormalInput)
            $st = 'INFO'
            $msg = ''
            if ($pct -ge $NormalWarnPct) {
                $st = 'WARN'
                $msg = '通常版の入力スレッドのスタックでは足りなくなるかもしれません (ログ版はログの分だけ多く使うので、目安です)'
            }
            $rows.Add([pscustomobject]@{ Item = ('入力スレッド (通常版の {0} バイトと比べた目安)' -f $NormalInput); Status = $st
                    Actual = ('{0} / {1} バイト ({2} %)' -f $inputThread[0].Usage, $NormalInput, $pct); Message = $msg; Details = @() })
        }
    }
    return , $rows.ToArray()
}

# ---------------------------------------------------------------------------
# UF2 のドライブ (bootmagic)
# ---------------------------------------------------------------------------

# ドライブがそのマイコンのブートローダか (flash-uf2.ps1 の $BOARDS と同じ見分け方)。
# BMP はボリュームラベル BLEMICROPRO、XIAO は INFO_UF2.TXT に nRF52840 があり、ラベルが BLEMICROPRO でない
function Test-KcUf2DriveBoard([string]$Mcu, [string]$Label, [string]$Info) {
    if ($Mcu -eq 'BMP') {
        return ($Label -eq 'BLEMICROPRO')
    }
    if ($Label -eq 'BLEMICROPRO') {
        return $false
    }
    return ($null -ne $Info -and $Info.Contains('nRF52840'))
}

# bootmagic: もう片方を通して PC に届いたキー ($Usage) が、ブートローダに入る前に、ファームによって離されたか。
# $FoundAt はドライブを見つけた時刻。ドライブが現れてから人が指を離した入力と見分けるため、
# 見つける $MarginMs より前に離されていれば PASS、後なら WARN (確かめられない)、離されていなければ FAIL
function Test-KcBootmagicRelease($Events, [int]$Usage, [long]$FoundAt, $ScanTable, [int]$MarginMs = 300) {
    $acts = ConvertTo-KcKeyActions $Events $ScanTable
    $mine = @($acts | Where-Object { $_.Usage -eq $Usage } | Sort-Object -Property Time)
    $label = Get-KcUsageLabel $Usage $ScanTable
    if (@($mine | Where-Object { $_.Down }).Count -eq 0) {
        return (New-KcRgResult 'NONE' ('「{0}」の入力は PC に届いていません (もう片方が PC につながっていないときは、押されたままにならないことは確かめられません)' -f $label))
    }
    $before = @($mine | Where-Object { $_.Time -le ($FoundAt - $MarginMs) })
    if ($before.Count -gt 0 -and -not $before[$before.Count - 1].Down) {
        return (New-KcRgResult 'PASS' ('「{0}」は、ブートローダに入る前に離された' -f $label))
    }
    $later = @($mine | Where-Object { -not $_.Down -and $_.Time -gt ($FoundAt - $MarginMs) })
    if ($later.Count -gt 0) {
        return (New-KcRgResult 'WARN' ('「{0}」が離されたのは、ドライブが現れた後' -f $label) ('ドライブが現れる前に指を離したか、ファームがキーを離さなかったかを見分けられません。ドライブが現れるまで押したまま、もう一度確かめてください'))
    }
    return (New-KcRgResult 'FAIL' ('「{0}」が離されなかった' -f $label) ('ブートローダに入る前に「{0}」が離されず、PC でキーが押されたままになりました' -f $label))
}

# INFO_UF2.TXT の Board-ID の行
function Get-KcUf2BoardId([string]$Info) {
    if (-not $Info) {
        return ''
    }
    $m = [regex]::Match($Info, '(?m)^Board-ID:\s*(.+?)\s*$')
    if ($m.Success) {
        return $m.Groups[1].Value
    }
    return ''
}

# ---------------------------------------------------------------------------
# PR 本文の「実機の回帰テスト」の節 (CI が確かめる)
# ---------------------------------------------------------------------------

# 誤りの一覧 (空なら正しい)。$Ids: checks.json の id
#   - 追加・更新: `<id>` (id は checks.json にあること)
#   - 既存のテスト: <パスなど>
#   - 不要: <理由>
function Test-KcRegressionPrBody([string]$Body, [string[]]$Ids) {
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $text = [regex]::Replace([string]$Body, '(?s)<!--.*?-->', '')
    $m = [regex]::Match($text, '(?ms)^#{1,6}\s*実機の回帰テスト\s*$(.*?)(?=^#{1,6}\s|\z)')
    if (-not $m.Success) {
        $errors.Add('PR 本文に「## 実機の回帰テスト」の節がありません (.github/pull_request_template.md を見てください)')
        return , $errors.ToArray()
    }
    $valid = 0
    foreach ($line in ($m.Groups[1].Value -split "`r?`n")) {
        $lm = [regex]::Match($line, '^\s*[-*]\s*(追加・更新|既存のテスト|不要)\s*[:：]\s*(.*?)\s*$')
        if (-not $lm.Success) {
            continue
        }
        $kind = $lm.Groups[1].Value
        $value = $lm.Groups[2].Value
        if (-not $value -or $value -match '^<[^>]*>$') {
            $errors.Add(('「{0}」の行が空のままです' -f $kind))
            continue
        }
        if ($kind -eq '追加・更新') {
            $found = @([regex]::Matches($value, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
            if ($found.Count -eq 0) {
                $errors.Add('「追加・更新」には、checks.json の id を `id` の形で書いてください')
                continue
            }
            $bad = @($found | Where-Object { $Ids -notcontains $_ })
            if ($bad.Count -gt 0) {
                $errors.Add(('checks.json に無い id: {0}' -f ($bad -join ', ')))
                continue
            }
        }
        $valid++
    }
    if ($valid -eq 0 -and $errors.Count -eq 0) {
        $errors.Add('「実機の回帰テスト」の節に、「- 追加・更新: `id`」「- 既存のテスト: パス」「- 不要: 理由」のどれかを書いてください')
    }
    return , $errors.ToArray()
}
