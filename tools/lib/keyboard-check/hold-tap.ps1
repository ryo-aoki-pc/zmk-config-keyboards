# タップホールドのタイミングを見る (keyboard-check.ps1 -Mode HoldTap) の計算。Windows の API を使わない純粋関数。
# expected.ps1 / hold-tap-sim.ps1 が先に読み込まれている前提。
#
# ZMK のログ版ファームで、選んだキーの組み合わせ (hold-tap のキーと、一緒に押すキー 1 つ) を押した 1 回分
# (hold-tap のキーを押してから、選んだキーを全部離すまで。長くても tapping-term + 100 ms で打ち切る。押している最中も含む) を、
# シミュレータ (HoldTapSim.cs) で計算し、グラフ (横軸が時刻) の中身を作る。
#   - キーマップ: 期待値 (tools/expected/*.json) の interactive.hold_tap (generate.py が submodule のキーマップから作る)
#   - 設定: キーマップの値のうち、flavor と tapping-term だけをウィンドウで変えられる
#   - 「離す時刻ごとの結果」: 対象のキーを離す時刻を 1ms ずつ動かした結果を、同じ結果の区間にまとめたもの
#     (押している最中は、仮の「離す」を足して動かす)
#
# グラフのモデル (Get-KcHoldTapChart) は、ウィンドウ (InputTestForm.cs の KcHoldTapForm / KcTimelineView) にそのまま渡す。
# 下の定数は KcTimelineView の定数と揃える (tests/windows.Tests.ps1 が確かめる)。

$script:KcHtLaneCaption = 0
$script:KcHtLaneKey = 1
$script:KcHtLaneOutput = 2
$script:KcHtLaneStrip = 3

$script:KcHtBarPlain = 0       # ほかのキーの押下
$script:KcHtBarUndecided = 1   # hold-tap の判定待ち
$script:KcHtBarTap = 2         # タップに決まったあと
$script:KcHtBarHold = 3        # ホールドに決まったあと
$script:KcHtBarMod = 4         # 届いた修飾キー
$script:KcHtBarLayer = 5       # 有効になったレイヤー
$script:KcHtBarKey = 6         # 届いたキー
$script:KcHtBarOther = 7       # そのほかのビヘイビア
$script:KcHtBarStripTap = 8    # 帯: タップ
$script:KcHtBarStripHold = 9   # 帯: ホールド
$script:KcHtBarStripNone = 10  # 帯: 判定なし

$script:KcHtMarkDecision = 0   # 判定した時刻
$script:KcHtMarkTerm = 1       # tapping-term
$script:KcHtMarkFirmware = 2   # ファームが判定した時刻 (計算と違うときだけ)
$script:KcHtMarkCursor = 3     # 帯の上の、実際に離した時刻

$script:KcHtArrowCapture = 0   # 判定まで保留されたキー (押した時刻 → 送られた時刻)

$script:KcHtOpenEnd = 10000000  # 離していないキー・届いたままの出力の終わり (ウィンドウが「今」か右端で切る)
$script:KcHtLimitExtraMs = 100   # 1 回分は、対象を押してから tapping-term + この長さで打ち切る (横軸の右端も)

$script:KcHtFlavors = @('hold-preferred', 'balanced', 'tap-preferred', 'tap-unless-interrupted')
$script:KcHtFlavorText = @{
    'hold-preferred'         = 'ほかのキーを押したらホールド'
    'balanced'               = 'ほかのキーを押して離したらホールド'
    'tap-preferred'          = 'tapping-term が過ぎたときだけホールド'
    'tap-unless-interrupted' = 'ほかのキーを押したらホールド (tapping-term が過ぎるとタップ)'
}

# ---------------------------------------------------------------------------
# キーマップと設定
# ---------------------------------------------------------------------------

function ConvertTo-KcHtZmkConfigFromJson($Json) {
    Import-KcHoldTapSim
    $c = New-Object KcHtZmkConfig
    $c.Flavor = [string](Get-KcProp $Json 'flavor' 'hold-preferred')
    $c.Term = [int](Get-KcProp $Json 'tapping_term_ms' 200)
    $c.QuickTap = [int](Get-KcProp $Json 'quick_tap_ms' -1)
    $c.PriorIdle = [int](Get-KcProp $Json 'require_prior_idle_ms' -1)
    $c.RetroTap = [bool](Get-KcProp $Json 'retro_tap' $false)
    $c.Hwu = [bool](Get-KcProp $Json 'hold_while_undecided' $false)
    $c.HwuLinger = [bool](Get-KcProp $Json 'hold_while_undecided_linger' $false)
    $c.TriggerOnRelease = [bool](Get-KcProp $Json 'hold_trigger_on_release' $false)
    $c.TriggerPositions = [int[]]@(Get-KcProp $Json 'hold_trigger_key_positions' @())
    return $c
}

# 期待値 → モデル。ZMK の機種だけ (KQ-mini・Keyball39 は $null)
function New-KcHtModel($Expected) {
    Import-KcHoldTapSim
    $ht = Get-KcProp (Get-KcProp $Expected 'interactive') 'hold_tap' $null
    if ($null -eq $ht -or [string]$ht.engine -ne 'zmk') { return $null }
    $km = New-Object KcHtKeymap
    $keys = @{}
    foreach ($k in @(Get-KcProp (Get-KcProp $Expected 'physical') 'keys' @())) {
        if (-not [bool](Get-KcProp $k 'present' $true)) { continue }
        $keys[[int]$k.pos] = @{ Pos = [int]$k.pos; Legend = [string](Get-KcProp $k 'legend' ''); Base = $null }
    }
    foreach ($k in @($ht.keys)) {
        $pos = [int]$k.pos
        foreach ($p in $k.on.PSObject.Properties) {
            $b = ConvertTo-KcHtBinding $p.Value
            $km.Set($pos, [int]$p.Name, $b)
            if ($p.Name -eq '0' -and $keys.ContainsKey($pos)) { $keys[$pos].Base = $b }
        }
    }
    $behaviors = @{}
    foreach ($p in $ht.behaviors.PSObject.Properties) {
        $cfg = ConvertTo-KcHtZmkConfigFromJson $p.Value
        $km.SetBehavior($p.Name, $cfg)
        $behaviors[$p.Name] = $cfg
    }
    return @{ Name = [string]$Expected.name; Keymap = $km; Keys = $keys; Behaviors = $behaviors }
}

function Get-KcHtKeyName($Model, [int]$Pos) {
    if ($Model.Keys.ContainsKey($Pos)) {
        $k = $Model.Keys[$Pos]
        $b = $k.Base
        if ($null -ne $b -and $b.Kind -eq 'ht') { return ('{0} ({1})' -f $b.Tap.Label, $b.Hold.Label) }
        if ($k.Legend) { return $k.Legend }
        if ($null -ne $b -and $b.Label) { return $b.Label }
    }
    return ('位置 {0}' -f $Pos)
}

# BASE で hold-tap のキーなら、その behavior の名前 (mt / lt など)。違えば ''
function Get-KcHtBehavior($Model, [int]$Pos) {
    if (-not $Model.Keys.ContainsKey($Pos)) { return '' }
    $b = $Model.Keys[$Pos].Base
    if ($null -eq $b -or $b.Kind -ne 'ht' -or -not $Model.Behaviors.ContainsKey($b.Behavior)) { return '' }
    return [string]$b.Behavior
}

# 設定 (ウィンドウで変えた値): behavior の名前 → @{ Flavor; Term }。キーマップの値と同じなら持たない
function New-KcHtConfig {
    return @{}
}

function Copy-KcHtConfig($Config) {
    $c = @{}
    foreach ($k in @($Config.Keys)) { $c[$k] = @{ Flavor = $Config[$k].Flavor; Term = $Config[$k].Term } }
    return $c
}

# 今の設定: @{ Flavor; Term; Changed (キーマップの値と違うか) }
function Get-KcHtSetting($Model, $Config, [string]$Behavior) {
    $base = $Model.Behaviors[$Behavior]
    $s = @{ Flavor = [string]$base.Flavor; Term = [int]$base.Term; Changed = $false }
    if ($Config.ContainsKey($Behavior)) {
        $o = $Config[$Behavior]
        if ($null -ne $o.Flavor) { $s.Flavor = [string]$o.Flavor }
        if ($null -ne $o.Term) { $s.Term = [int]$o.Term }
    }
    $s.Changed = ($s.Flavor -ne $base.Flavor -or $s.Term -ne $base.Term)
    return $s
}

# flavor / term を変える
function Set-KcHtSetting($Model, $Config, [string]$Behavior, [string]$Name, $Value) {
    if (-not $Config.ContainsKey($Behavior)) { $Config[$Behavior] = @{ Flavor = $null; Term = $null } }
    switch ($Name) {
        'flavor' { $Config[$Behavior].Flavor = [string]$Value }
        'term' { $Config[$Behavior].Term = [int]$Value }
    }
    if (-not (Get-KcHtSetting $Model $Config $Behavior).Changed) { $Config.Remove($Behavior) }
}

function Get-KcHtKeymapWith($Model, $Config) {
    $km = $Model.Keymap
    foreach ($name in @($Config.Keys)) {
        $s = Get-KcHtSetting $Model $Config $name
        $c = $Model.Behaviors[$name].Clone()
        $c.Flavor = $s.Flavor
        $c.Term = $s.Term
        $km = $km.WithBehavior($name, $c)
    }
    return $km
}

# ---------------------------------------------------------------------------
# ログ版ファームのログから、選んだキーの組み合わせを押した 1 回分 (エピソード) を切り出す
# ---------------------------------------------------------------------------

# 1 回分の長さ (対象のキーを押してから。この先は打ち切る)
function Get-KcHtLimitMs([int]$Term) {
    return $Term + $script:KcHtLimitExtraMs
}

# $Rec は zmk-log.ps1 の ConvertFrom-KcZmkLogLine のレコード。
# Combo: 調べるキーの組み合わせ @{ Target (hold-tap のキー); Partner (一緒に押すキー) }。$null のあいだは回を作らない
# LimitMs: 1 回分の長さ (Get-KcHtLimitMs)。Pressed: 最後に処理した行で押したキーの位置 (無ければ -1。組み合わせを選ぶのに使う)
function New-KcHtCapture($Model, $Combo = $null, [int]$LimitMs = 250) {
    return @{
        Model = $Model; Combo = $Combo; LimitMs = $LimitMs
        Held = @{}; Recent = (New-Object 'System.Collections.Generic.List[object]'); Ep = $null; Seq = 0
        LastTime = [double]0; Pressed = -1
    }
}

# 選んだキーか
function Test-KcHtComboKey($State, [int]$Pos) {
    $c = $State.Combo
    return ($null -ne $c -and ($Pos -eq [int]$c.Target -or $Pos -eq [int]$c.Partner))
}

# 選んだキーを全部離しているか
function Test-KcHtCaptureIdle($State) {
    $c = $State.Combo
    if ($null -eq $c) { return $true }
    return (-not $State.Held.ContainsKey([int]$c.Target) -and -not $State.Held.ContainsKey([int]$c.Partner))
}

# 1 行ぶん進める。戻り値: $null、@{ Kind = 'done'; Episode } (1 回分が終わった)、@{ Kind = 'discarded'; Pos; Seq }
# (選んだキーを押している途中で、選んでいないキー Pos を押したので、その回を捨てた)
function Update-KcHtCapture($State, $Rec) {
    $State.Pressed = -1
    if ($null -eq $Rec) { return $null }
    $out = $null
    if ($Rec.Type -eq 'dropped') {
        if ($null -ne $State.Ep) { $State.Ep.Dropped = $true }
        return $null
    }
    if ($Rec.Time -ge 0) { $State.LastTime = [double]$Rec.Time }
    $ep = $State.Ep
    # 打ち切り: 対象を押してから LimitMs を過ぎた行は、その回に入れない
    if ($null -ne $ep -and $Rec.Time -ge 0 -and $Rec.Time -gt $ep.CutAt) {
        $out = @{ Kind = 'done'; Episode = (Complete-KcHtCapture $State -Cut) }
        $ep = $null
    }
    switch ($Rec.Type) {
        'position' {
            $pos = [int]$Rec.Pos
            $down = $Rec.Pressed
            $uncertain = $false
            if ($null -eq $down) {
                # ペリフェラル (左手側) のキーは押す / 離すが出ないので、交互に数える
                $down = -not $State.Held.ContainsKey($pos)
                $uncertain = $true
            }
            $selected = Test-KcHtComboKey $State $pos
            if ($null -ne $ep -and $down) {
                $idle = Test-KcHtCaptureIdle $State
                if (-not $selected) {
                    if ($idle) {
                        $out = @{ Kind = 'done'; Episode = (Complete-KcHtCapture $State) }
                    } else {
                        $State.Ep = $null
                        $out = @{ Kind = 'discarded'; Pos = $pos; Seq = $ep.Seq }
                    }
                    $ep = $null
                } elseif ($idle -and $Rec.Time - $ep.LastT -gt 50) {
                    $out = @{ Kind = 'done'; Episode = (Complete-KcHtCapture $State) }
                    $ep = $null
                }
            }
            if ($down) {
                $State.Held[$pos] = $true
                $State.Pressed = $pos
            } else {
                $State.Held.Remove($pos)
            }
            $e = @{ Pos = $pos; Down = [bool]$down; T = [double]$Rec.Time; Uncertain = $uncertain }
            $State.Recent.Add($e)
            while ($State.Recent.Count -gt 40) { $State.Recent.RemoveAt(0) }
            if ($null -ne $ep -and $selected) {
                $ep.Events.Add($e)
                $ep.LastT = [double]$Rec.Time
                if ($uncertain) { $ep.Uncertain = $true }
            }
        }
        'ht_new' {
            $pos = [int]$Rec.Pos
            # 押したことの確かめ (ペリフェラルを交互に数えてずれていたら直す)
            $last = Find-KcHtRecent $State $pos
            if ($null -ne $last -and -not $last.Down) {
                $last.Down = $true
                $State.Held[$pos] = $true
                $State.Pressed = $pos
            }
            $c = $State.Combo
            if ($null -eq $ep -and $null -ne $last -and $null -ne $c -and $pos -eq [int]$c.Target) {
                $State.Seq++
                $ep = @{
                    Seq = $State.Seq; Target = $pos; Partner = [int]$c.Partner; Start = [double]$last.T; LastT = [double]$Rec.Time
                    Limit = [int]$State.LimitMs; CutAt = [double]$last.T + $State.LimitMs
                    Events = (New-Object 'System.Collections.Generic.List[object]')
                    Decisions = (New-Object 'System.Collections.Generic.List[object]')
                    Hid = (New-Object 'System.Collections.Generic.List[object]')
                    Dropped = $false; Uncertain = $false; Cut = $false
                }
                # 一緒に押すキーを先に押していたら、その「押す」から入れる
                # (6 台とも quick-tap・require-prior-idle を使わないので、それより前の入力は判定に関わらない)
                $partner = [int]$c.Partner
                if ($State.Held.ContainsKey($partner)) {
                    $p = Find-KcHtRecent $State $partner
                    if ($null -ne $p -and $p.Down -and $p.T -le $last.T) {
                        $ep.Events.Add($p)
                        if ($p.Uncertain) { $ep.Uncertain = $true }
                    }
                }
                $ep.Events.Add($last)
                if ($last.Uncertain) { $ep.Uncertain = $true }
                $State.Ep = $ep
            }
        }
        'ht_decided' {
            if ($null -ne $ep -and (Test-KcHtComboKey $State ([int]$Rec.Pos))) {
                $ep.Decisions.Add(@{ Pos = [int]$Rec.Pos; Status = [string]$Rec.Decision; Moment = [string]$Rec.Moment; Flavor = [string]$Rec.Flavor; T = [double]$Rec.Time })
                $ep.LastT = [double]$Rec.Time
            }
        }
        'hid' {
            if ($null -ne $ep -and $Rec.Page -eq 7) {
                $ep.Hid.Add(@{ T = [double]$Rec.Time; Usage = [int]$Rec.Usage; Pressed = [bool]$Rec.Pressed })
                $ep.LastT = [double]$Rec.Time
            }
        }
        { $_ -eq 'ht_capture' -or $_ -eq 'ht_bubble' } {
            # 押す / 離すの確かめ (ペリフェラル)
            $other = [int]$Rec.Other
            if ($Rec.Pressed) { $State.Held[$other] = $true } else { $State.Held.Remove($other) }
        }
        'ht_cleanup' {
            $State.Held.Remove([int]$Rec.Pos)
        }
    }
    return $out
}

# そのキーの直近の押す / 離す ($null = 無い)
function Find-KcHtRecent($State, [int]$Pos) {
    for ($i = $State.Recent.Count - 1; $i -ge 0; $i--) {
        if ($State.Recent[$i].Pos -eq $Pos) { return $State.Recent[$i] }
    }
    return $null
}

# エピソードの中身を、対象のキーを押した時刻を 0 にした形にする:
# @{ Seq; Target; Partner; T0 (0 にしたファームの時刻); Events (@{ Pos; Down; T; Role }); TargetIndex; Decisions; Hid;
#    Dropped; Uncertain; Cut (打ち切った); Limit (1 回分の長さ); Live }
function ConvertTo-KcHtEpisodeData($Ep, [bool]$Live) {
    $t0 = [Math]::Floor($Ep.Start)
    $events = New-Object 'System.Collections.Generic.List[object]'
    $targetIndex = -1
    foreach ($e in $Ep.Events) {
        $t = [long]([Math]::Floor($e.T) - $t0)
        if ($targetIndex -lt 0 -and $e.Pos -eq $Ep.Target -and $e.Down -and $t -eq 0) { $targetIndex = $events.Count }
        $role = 'partner'
        if ($e.Pos -eq $Ep.Target) { $role = 'target' } elseif ($t -lt 0) { $role = 'prior' }
        $events.Add(@{ Pos = [int]$e.Pos; Down = [bool]$e.Down; T = $t; Role = $role })
    }
    if ($targetIndex -lt 0) { $targetIndex = 0 }
    $decisions = New-Object 'System.Collections.Generic.List[object]'
    foreach ($d in $Ep.Decisions) {
        $decisions.Add(@{ Pos = $d.Pos; Status = $d.Status; Moment = $d.Moment; Flavor = $d.Flavor; T = [double]([Math]::Floor($d.T) - $t0) })
    }
    $hid = New-Object 'System.Collections.Generic.List[object]'
    foreach ($h in $Ep.Hid) {
        $hid.Add(@{ T = [double]([Math]::Floor($h.T) - $t0); Usage = $h.Usage; Pressed = $h.Pressed })
    }
    return @{
        Seq = $Ep.Seq; Target = $Ep.Target; Partner = $Ep.Partner; T0 = [double]$t0; Events = $events.ToArray(); TargetIndex = $targetIndex
        Decisions = $decisions.ToArray(); Hid = $hid.ToArray(); Dropped = $Ep.Dropped; Uncertain = $Ep.Uncertain
        Cut = $Ep.Cut; Limit = $Ep.Limit; Live = $Live
    }
}

# 今のエピソードを終える。選んだキーを全部離していなければ $null。
# -Cut: 1 回分の長さを過ぎたので、押していても終える (押していたら Cut = $true)
function Complete-KcHtCapture($State, [switch]$Cut) {
    $ep = $State.Ep
    if ($null -eq $ep) { return $null }
    $idle = Test-KcHtCaptureIdle $State
    if (-not $Cut -and -not $idle) { return $null }
    $State.Ep = $null
    if (-not $idle) { $ep.Cut = $true }
    return ConvertTo-KcHtEpisodeData $ep $false
}

# 押している最中のエピソード (Live = $true)。$State は変えない。無ければ $null
function Get-KcHtCaptureSnapshot($State) {
    if ($null -eq $State.Ep) { return $null }
    return ConvertTo-KcHtEpisodeData $State.Ep $true
}

# ---------------------------------------------------------------------------
# 「今」の時計: ログの行の時刻 (ファームの起動からの ms) と、届いた PC の時刻の差から、ファームの「今」を推定する。
# 行はまとめて遅れて届く (ZMK のログは deferred) ので、直近 5 秒でいちばん遅れの少ない行に合わせる
# ---------------------------------------------------------------------------

function New-KcHtClock {
    return @{ Samples = (New-Object 'System.Collections.Generic.List[object]'); Offset = $null; LastFw = [double]::NaN }
}

function Update-KcHtClock($Clock, [double]$FwMs, [double]$PcMs) {
    if (-not [double]::IsNaN($Clock.LastFw) -and $FwMs -lt $Clock.LastFw - 1000) {
        # ファームの時刻が戻った (再起動など)
        $Clock.Samples.Clear()
    }
    $Clock.LastFw = $FwMs
    $Clock.Samples.Add(@{ Pc = $PcMs; D = $FwMs - $PcMs })
    while ($Clock.Samples.Count -gt 1 -and $Clock.Samples[0].Pc -lt $PcMs - 5000) { $Clock.Samples.RemoveAt(0) }
    $best = [double]::NegativeInfinity
    foreach ($s in $Clock.Samples) {
        if ($s.D -gt $best) { $best = $s.D }
    }
    $Clock.Offset = $best
}

# ファームの「今」(ms)。まだ行が届いていなければ $null
function Get-KcHtClockNow($Clock, [double]$PcMs) {
    if ($null -eq $Clock.Offset) { return $null }
    return $PcMs + $Clock.Offset
}

# ---------------------------------------------------------------------------
# 計算と、結果の文
# ---------------------------------------------------------------------------

function New-KcHtEvent([int]$Pos, [bool]$Down, [long]$T, [string]$Role) {
    return @{ Pos = $Pos; Down = $Down; T = $T; Role = $Role }
}

function Invoke-KcHtRun($Keymap, $Events) {
    Import-KcHoldTapSim
    return [KcHtSweep]::Run('zmk', $Keymap, (ConvertTo-KcHtInputs $Events))
}

function Format-KcHtStatus([string]$Status) {
    switch ($Status) {
        'tap' { return 'タップ' }
        'hold' { return 'ホールド' }
        'hold-timer' { return 'ホールド (時間切れ)' }
        'hold-interrupt' { return 'ホールド (ほかのキー)' }
        '' { return '判定なし' }
    }
    return $Status
}

# 「タップに決定」「ホールド (時間切れ) に決定」
function Format-KcHtDecided([string]$Status) {
    $text = Format-KcHtStatus $Status
    if ($text.EndsWith(')')) { return $text + ' に決定' }
    return $text + 'に決定'
}

function Get-KcHtStatusClass([string]$Status) {
    if ($Status -eq 'tap') { return 'tap' }
    if ($Status -like 'hold*') { return 'hold' }
    return 'none'
}

# 判定の理由の文
function Format-KcHtMoment($Model, $Decision, [int]$Term) {
    $t = $Decision.DecideT
    $other = ''
    if ($Decision.Other -ge 0) { $other = Get-KcHtKeyName $Model $Decision.Other }
    switch ($Decision.Moment) {
        'key-up' { return ('{0} ms に {1} を離した' -f $t, (Get-KcHtKeyName $Model $Decision.Pos)) }
        'other-key-down' { return ('{0} ms に {1} を押した' -f $t, $other) }
        'other-key-up' { return ('{0} ms に {1} を離した (押している間に、ほかのキーを押して離した)' -f $t, $other) }
        'timer' { return ('tapping-term ({0} ms) が過ぎた' -f $Term) }
        'quick-tap' { return ('直前のキーから require-prior-idle 以内か、前のタップから quick-tap 以内に押した ({0} ms)' -f $t) }
    }
    return ('{0} ({1} ms)' -f $Decision.Moment, $t)
}

# 対象のキーを離した入力の番号 (まだ離していなければ -1)
function Get-KcHtReleaseIndex($Episode) {
    $events = $Episode.Events
    $ti = $Episode.TargetIndex
    for ($i = $ti + 1; $i -lt $events.Count; $i++) {
        if ($events[$i].Pos -eq $events[$ti].Pos) {
            if (-not $events[$i].Down) { return $i }
            return -1
        }
    }
    return -1
}

# 対象のキーを離す時刻ごとの結果 (今の設定と、flavor ごと):
# @{ Release (動かした「離す」の時刻。押している最中は $null); To (計算した右端); Segments; Flavors = @(@{ Flavor; Segments; Current }) }
function Get-KcHtReleaseSweeps($Model, $Config, $Episode, $Range) {
    Import-KcHoldTapSim
    $events = $Episode.Events
    $ti = $Episode.TargetIndex
    $target = [int]$events[$ti].Pos
    $pressT = [long]$events[$ti].T
    $behavior = Get-KcHtBehavior $Model $target
    $setting = Get-KcHtSetting $Model $Config $behavior
    $rel = Get-KcHtReleaseIndex $Episode
    $releaseT = $null
    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($e in $events) { $list.Add($e) }
    if ($rel -lt 0) {
        # 押している最中: 仮の「離す」を足す
        $list.Add((New-KcHtEvent $target $false ($pressT + 1) 'phantom'))
        $rel = $list.Count - 1
    } else {
        $releaseT = [long]$events[$rel].T
    }
    $from = $pressT + 1
    # 横軸の右端 (tapping-term + 100 ms) まで。押している最中も同じ
    $to = [long]$Range.To
    for ($i = $rel + 1; $i -lt $list.Count; $i++) {
        if ($list[$i].Pos -eq $target) { $to = [long][Math]::Min($to, $list[$i].T - 1); break }
    }
    $inputs = ConvertTo-KcHtInputs $list.ToArray()
    $current = @([KcHtSweep]::VaryInput('zmk', (Get-KcHtKeymapWith $Model $Config), $inputs, $rel, $from, $to, $ti))
    $flavors = New-Object 'System.Collections.Generic.List[object]'
    foreach ($f in $script:KcHtFlavors) {
        $c = Copy-KcHtConfig $Config
        Set-KcHtSetting $Model $c $behavior 'flavor' $f
        $segs = @([KcHtSweep]::VaryInput('zmk', (Get-KcHtKeymapWith $Model $c), $inputs, $rel, $from, $to, $ti))
        $flavors.Add(@{ Flavor = $f; Segments = $segs; Current = ($f -eq $setting.Flavor) })
    }
    return @{ Release = $releaseT; To = $to; Segments = $current; Flavors = $flavors.ToArray() }
}

# 帯 (区間) の境目の文: 「〜140 ms: タップ → A H / 141 ms〜: ホールド (ほかのキー) → Ctrl+H」
function Format-KcHtSegments($Segments) {
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $n = @($Segments).Count
    for ($i = 0; $i -lt $n; $i++) {
        $s = @($Segments)[$i]
        $range = '{0}〜{1} ms' -f $s.From, $s.To
        if ($n -gt 1 -and $i -eq 0) { $range = '〜{0} ms' -f $s.To }
        if ($n -gt 1 -and $i -eq $n - 1) { $range = '{0} ms〜' -f $s.From }
        $parts.Add(('{0}: {1} → {2}' -f $range, (Format-KcHtStatus $s.Status), (Format-KcHtStrokes $s.Text)))
    }
    return ($parts -join ' / ')
}

function Format-KcHtStrokes([string]$Text) {
    if ($Text) { return $Text }
    return 'なし'
}

# 「今」を含む区間の番号 (無ければ -1)。押した直後 (最初の区間より前) は最初の区間、最後の区間より後は最後の区間
function Find-KcHtSegment($Segments, [double]$Now) {
    $segs = @($Segments)
    if ($segs.Count -eq 0) { return -1 }
    $t = [Math]::Min([Math]::Max($Now, [double]$segs[0].From), [double]$segs[$segs.Count - 1].To)
    for ($i = 0; $i -lt $segs.Count; $i++) {
        if ($t -ge $segs[$i].From - 0.5 -and $t -lt $segs[$i].To + 0.5) { return $i }
    }
    return -1
}

# 要約 (ウィンドウの上の欄): @{ Title; Lines; Level (1 = タップ、2 = ホールド、0 = 判定待ち・なし); Key (変わったかを見る文字列) }
# $Now: 押している最中の「今」(対象を押した時刻からの ms)。終わった回は $null
function Get-KcHtSummary($Model, $Config, $Episode, $Result, $Sweeps, $Now) {
    Import-KcHoldTapSim
    $ti = $Episode.TargetIndex
    $target = [int]$Episode.Events[$ti].Pos
    $setting = Get-KcHtSetting $Model $Config (Get-KcHtBehavior $Model $target)
    $live = ($null -ne $Now)
    $d = [KcHtText]::DecisionFor($Result, $ti)
    $decided = ($null -ne $d -and (-not $live -or $d.DecideT -le $Now))
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $level = 0
    $segIndex = -1
    if ($decided) {
        $status = Format-KcHtStatus $d.Status
        if ($live) {
            $title = '{0} ({1} ms)' -f (Format-KcHtDecided $d.Status), $d.DecideT
        } else {
            $title = '{0}: PC に届くのは {1}' -f $status, (Format-KcHtStrokes ([KcHtText]::Strokes($Result)))
        }
        $lines.Add(('決め手: {0} ({1})' -f (Format-KcHtMoment $Model $d $setting.Term), $setting.Flavor))
        $level = 2
        if ($d.Status -eq 'tap') { $level = 1 }
    } elseif ($live) {
        $title = '判定待ち'
    } else {
        $title = '判定なし: PC に届くのは {0}' -f (Format-KcHtStrokes ([KcHtText]::Strokes($Result)))
    }
    # 押している最中で判定の前: 今離すと
    if ($live -and -not $decided -and $null -ne $Sweeps -and $null -eq $Sweeps.Release -and @($Sweeps.Segments).Count -gt 0) {
        $segs = @($Sweeps.Segments)
        $segIndex = Find-KcHtSegment $segs $Now
        if ($segIndex -ge 0) {
            $s = $segs[$segIndex]
            $text = '今離すと: {0} → {1}' -f (Format-KcHtStatus $s.Status), (Format-KcHtStrokes $s.Text)
            if ($segIndex + 1 -lt $segs.Count) {
                $n = $segs[$segIndex + 1]
                $text += '。{0} ms を過ぎると {1} → {2}' -f $n.From, (Format-KcHtStatus $n.Status), (Format-KcHtStrokes $n.Text)
            }
            $lines.Add($text)
        }
    }
    # 判定まで保留されたキー (最初の 1 つ)
    for ($i = 0; $i -lt $Result.Inputs.Count; $i++) {
        $in = $Result.Inputs[$i]
        if (-not $in.Captured -or -not $in.Down -or $in.ReplayAt -le $in.At) { continue }
        if ($live -and $in.ReplayAt -gt $Now) { continue }
        $lines.Add(('{0} は判定まで保留され、{1} ms 遅れて送られた' -f (Get-KcHtKeyName $Model $in.Pos), ($in.ReplayAt - $in.At)))
        break
    }
    # ファームの判定と違うとき
    $fd = $null
    foreach ($x in @($Episode.Decisions)) {
        if ($x.Pos -eq $target) { $fd = $x; break }
    }
    if ($null -ne $fd -and $null -ne $d -and $decided -and ($fd.Status -ne $d.Status -or [Math]::Abs($fd.T - $d.DecideT) -gt 1)) {
        $why = '計算と違う (左手側のキーの押す / 離すを数え違えたか、ファームのキーマップが期待値と違う)'
        if ($setting.Changed) { $why = '設定を変えたので違う' }
        $lines.Add(('ファームの判定は {0} ({1} ms)。{2}' -f (Format-KcHtStatus $fd.Status), $fd.T, $why))
    }
    if (-not $live -and $Episode.ContainsKey('Cut') -and $Episode.Cut -and (Get-KcHtReleaseIndex $Episode) -lt 0) {
        $lines.Add(('{0} ms (tapping-term + {1} ms) で打ち切った。{2} はまだ押していた' -f $Episode.Limit, $script:KcHtLimitExtraMs, (Get-KcHtKeyName $Model $target)))
    }
    if ($Episode.Dropped) { $lines.Add('ログが欠けたので、実際の押し方と違うことがある') }
    return @{ Title = $title; Lines = $lines.ToArray(); Level = $level; Key = ('{0}|{1}|{2}' -f $decided, $segIndex, $lines.Count) }
}

# ---------------------------------------------------------------------------
# グラフのモデル
# ---------------------------------------------------------------------------

# 横軸の範囲 (50ms 単位)。右端は 1 回分の長さ (tapping-term + 100 ms) で、押している最中も同じ。
# 左端は押した時刻の少し前 (一緒に押すキーを先に押していたら、その時刻から。-500 ms まで)
function Get-KcHtRange($Episode, [int]$Term) {
    $min = [long]0
    foreach ($e in $Episode.Events) {
        if ($e.T -lt $min) { $min = [long]$e.T }
    }
    $from = [long][Math]::Max(-500, [Math]::Floor(($min - 60) / 50.0) * 50)
    $to = [long]([Math]::Ceiling((Get-KcHtLimitMs $Term) / 50.0) * 50)
    return @{ From = $from; To = $to }
}

function New-KcHtChart {
    return @{
        From = 0; To = 400
        Lanes = (New-Object 'System.Collections.Generic.List[object]')
        Bars = (New-Object 'System.Collections.Generic.List[object]')
        Marks = (New-Object 'System.Collections.Generic.List[object]')
        Arrows = (New-Object 'System.Collections.Generic.List[object]')
    }
}

function Add-KcHtLane($Chart, [string]$Title, [string]$Note, [int]$Kind, [string]$Action = '') {
    $Chart.Lanes.Add(@{ Title = $Title; Note = $Note; Kind = $Kind; Action = $Action })
    return $Chart.Lanes.Count - 1
}

function Add-KcHtBar($Chart, [int]$Lane, [double]$From, [double]$To, [int]$Style, [string]$Text = '') {
    $Chart.Bars.Add(@{ Lane = $Lane; From = $From; To = $To; Style = $Style; Text = $Text })
}

function Add-KcHtMark($Chart, [int]$LaneFrom, [int]$LaneTo, [double]$At, [int]$Style, [string]$Text = '') {
    $Chart.Marks.Add(@{ LaneFrom = $LaneFrom; LaneTo = $LaneTo; At = $At; Style = $Style; Text = $Text })
}

# 出力 (シミュレータの Hid の 1 つ) のレーン: @{ Key; Title; Note; Style }
function Get-KcHtOutputLane($Output) {
    if ($Output.Kind -eq 'layer') {
        return @{ Key = ('layer:{0}' -f $Output.Layer); Title = [string]$Output.Label; Note = 'レイヤー'; Style = $script:KcHtBarLayer }
    }
    if ($Output.Kind -eq 'other') {
        return @{ Key = ('other:{0}' -f $Output.Label); Title = [string]$Output.Label; Note = 'ビヘイビア'; Style = $script:KcHtBarOther }
    }
    if ($Output.Usage -ge 0xE0 -and $Output.Usage -le 0xE7) {
        return @{ Key = ('key:{0}' -f $Output.Usage); Title = [string]$Output.Label; Note = '修飾キー'; Style = $script:KcHtBarMod }
    }
    return @{ Key = ('key:{0}' -f $Output.Usage); Title = [string]$Output.Label; Note = 'キー'; Style = $script:KcHtBarKey }
}

# 出力 (Hid) をレーンごとの区間に: @(@{ Key; Title; Note; Style; Items = @(@{ From; To }) })
function Get-KcHtOutputRuns($Hid, [double]$End) {
    $runs = New-Object 'System.Collections.Generic.List[object]'
    $byKey = @{}
    $open = @{}
    foreach ($o in $Hid) {
        $lane = Get-KcHtOutputLane $o
        $key = $lane.Key
        if (-not $byKey.ContainsKey($key)) {
            $run = @{ Key = $key; Title = $lane.Title; Note = $lane.Note; Style = $lane.Style; Items = (New-Object 'System.Collections.Generic.List[object]') }
            $byKey[$key] = $run
            $runs.Add($run)
        }
        if ($o.Down) {
            if (-not $open.ContainsKey($key)) { $open[$key] = [double]$o.T }
        } elseif ($open.ContainsKey($key)) {
            $byKey[$key].Items.Add(@{ From = $open[$key]; To = [double]$o.T })
            $open.Remove($key)
        }
    }
    foreach ($key in @($open.Keys)) {
        $byKey[$key].Items.Add(@{ From = $open[$key]; To = $End })
    }
    return , $runs.ToArray()
}

# 組み合わせで PC に届きうる入力のレーン (グラフに前もって並べる): @(@{ Key; Title; Note; Style })。
# 短い入力をシミュレータで計算し、届いた順に集める (ラベルとキーは実際の計算と同じになる):
#   タップ / 一緒に押すキーで包んだホールド (hold-preferred で計算する) / タップのあとに一緒に押すキー /
#   一緒に押すキーが hold-tap なら、そのホールド
function Get-KcHtComboOutputs($Model, $Config, [int]$Target, [int]$Partner) {
    Import-KcHoldTapSim
    $behavior = Get-KcHtBehavior $Model $Target
    if (-not $behavior) { return , @() }
    $c = Copy-KcHtConfig $Config
    Set-KcHtSetting $Model $c $behavior 'flavor' 'hold-preferred'
    $km = Get-KcHtKeymapWith $Model $c
    $runs = New-Object 'System.Collections.Generic.List[object]'
    $runs.Add(@((New-KcHtEvent $Target $true 0 'target'), (New-KcHtEvent $Target $false 10 'target')))
    if ($Partner -ge 0) {
        $runs.Add(@((New-KcHtEvent $Target $true 0 'target'), (New-KcHtEvent $Partner $true 10 'partner'),
                (New-KcHtEvent $Partner $false 20 'partner'), (New-KcHtEvent $Target $false 30 'target')))
        $runs.Add(@((New-KcHtEvent $Target $true 0 'target'), (New-KcHtEvent $Target $false 10 'target'),
                (New-KcHtEvent $Partner $true 20 'partner'), (New-KcHtEvent $Partner $false 30 'partner')))
        $pb = Get-KcHtBehavior $Model $Partner
        if ($pb) {
            $pt = [long](Get-KcHtSetting $Model $c $pb).Term
            $runs.Add(@((New-KcHtEvent $Target $true 0 'target'), (New-KcHtEvent $Target $false 10 'target'),
                    (New-KcHtEvent $Partner $true 20 'partner'), (New-KcHtEvent $Partner $false (20 + $pt + 10) 'partner')))
        }
    }
    $lanes = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($events in $runs) {
        foreach ($o in (Invoke-KcHtRun $km $events).Hid) {
            $lane = Get-KcHtOutputLane $o
            if ($seen.ContainsKey($lane.Key)) { continue }
            $seen[$lane.Key] = $true
            $lanes.Add($lane)
        }
    }
    return , $lanes.ToArray()
}

# 帯の区間 → 帯のバー
function Add-KcHtStripBars($Chart, [int]$Lane, $Segments) {
    foreach ($s in @($Segments)) {
        $style = $script:KcHtBarStripNone
        $cls = Get-KcHtStatusClass $s.Status
        if ($cls -eq 'tap') { $style = $script:KcHtBarStripTap } elseif ($cls -eq 'hold') { $style = $script:KcHtBarStripHold }
        $text = $s.Text
        if (-not $text) { $text = '-' }
        Add-KcHtBar $Chart $Lane ([double]$s.From) ([double]$s.To + 1) $style $text
    }
}

# グラフ: 押したキー (選んだ 2 つ)、PC に届く入力 (組み合わせで届きうるものを前もって並べる)、判定と tapping-term の線、
# 離す時刻ごとの結果、flavor ごとの比較。
# 押している最中も同じ形で、ウィンドウが「今」より後を描かない。離していないキーと届いたままの出力は $KcHtOpenEnd まで
function Get-KcHoldTapChart($Model, $Config, $Episode, $Result, $Sweeps, $Range) {
    Import-KcHoldTapSim
    $events = $Episode.Events
    $ti = $Episode.TargetIndex
    $target = [int]$events[$ti].Pos
    $setting = Get-KcHtSetting $Model $Config (Get-KcHtBehavior $Model $target)
    $pressT = [long]$events[$ti].T
    $end = [double]$script:KcHtOpenEnd
    $chart = New-KcHtChart
    $chart.From = $Range.From
    $chart.To = $Range.To

    $partner = -1
    if ($Episode.ContainsKey('Partner') -and $null -ne $Episode.Partner) { $partner = [int]$Episode.Partner }

    # ---- 押したキー (対象、一緒に押すキーの順。一緒に押すキーは押さなかった回でも出す)
    [void](Add-KcHtLane $chart '押したキー' '' $script:KcHtLaneCaption)
    $keyLane = @{}
    $order = New-Object 'System.Collections.Generic.List[int]'
    $order.Add($target)
    if ($partner -ge 0 -and $partner -ne $target) { $order.Add($partner) }
    foreach ($e in $events) {
        if (-not $order.Contains([int]$e.Pos)) { $order.Add([int]$e.Pos) }
    }
    foreach ($pos in $order) {
        $note = ''
        $behavior = Get-KcHtBehavior $Model $pos
        if ($behavior) { $note = '&{0}' -f $behavior }
        $keyLane[$pos] = Add-KcHtLane $chart (Get-KcHtKeyName $Model $pos) $note $script:KcHtLaneKey
    }
    $firstKeyLane = 1
    # 押下の帯 (押す → 離す)。hold-tap は判定までを判定待ち、そのあとをタップ / ホールドで塗る
    for ($i = 0; $i -lt $events.Count; $i++) {
        $e = $events[$i]
        if (-not $e.Down) { continue }
        $upT = $end
        for ($k = $i + 1; $k -lt $events.Count; $k++) {
            if ($events[$k].Pos -eq $e.Pos) {
                if (-not $events[$k].Down) { $upT = [double]$events[$k].T }
                break
            }
        }
        $lane = $keyLane[[int]$e.Pos]
        $at = [double]$e.T
        if ($i -lt $Result.Inputs.Count -and $Result.Inputs[$i].At -ge 0) { $at = [double]$Result.Inputs[$i].At }
        $d = [KcHtText]::DecisionFor($Result, $i)
        if ($null -ne $d) {
            $decT = [Math]::Min([double]$d.DecideT, $upT)
            $style = $script:KcHtBarHold
            if ($d.Status -eq 'tap') { $style = $script:KcHtBarTap }
            if ($decT -gt $at) { Add-KcHtBar $chart $lane $at $decT $script:KcHtBarUndecided '判定待ち' }
            Add-KcHtBar $chart $lane ([Math]::Max($at, $decT)) $upT $style (Format-KcHtStatus $d.Status)
        } else {
            Add-KcHtBar $chart $lane $at $upT $script:KcHtBarPlain ''
        }
    }

    # ---- PC に届く入力 (組み合わせで届きうるものを先に並べ、ほかに届いたものは後ろに足す)
    [void](Add-KcHtLane $chart 'PC に届く入力' '' $script:KcHtLaneCaption)
    $outLane = @{}
    foreach ($lane in (Get-KcHtComboOutputs $Model $Config $target $partner)) {
        $outLane[$lane.Key] = Add-KcHtLane $chart $lane.Title $lane.Note $script:KcHtLaneOutput
    }
    foreach ($run in (Get-KcHtOutputRuns $Result.Hid $end)) {
        if (-not $outLane.ContainsKey($run.Key)) { $outLane[$run.Key] = Add-KcHtLane $chart $run.Title $run.Note $script:KcHtLaneOutput }
        foreach ($it in $run.Items) { Add-KcHtBar $chart $outLane[$run.Key] $it.From $it.To $run.Style $run.Title }
    }
    $lastLane = $chart.Lanes.Count - 1
    # 判定まで保留されたキー: 押した時刻 → 送られた時刻
    for ($i = 0; $i -lt $Result.Inputs.Count; $i++) {
        $in = $Result.Inputs[$i]
        if (-not $in.Captured -or -not $in.Down -or $in.ReplayAt -le $in.At -or -not $keyLane.ContainsKey([int]$in.Pos)) { continue }
        $toLane = $keyLane[[int]$in.Pos]
        foreach ($o in $Result.Hid) {
            if ($o.Pos -eq $in.Pos -and $o.Down -and $o.T -eq $in.ReplayAt) {
                $k = 'key:{0}' -f $o.Usage
                if ($o.Kind -eq 'layer') { $k = 'layer:{0}' -f $o.Layer }
                if ($outLane.ContainsKey($k)) { $toLane = $outLane[$k] }
                break
            }
        }
        $chart.Arrows.Add(@{ FromLane = $keyLane[[int]$in.Pos]; FromAt = [double]$in.At; ToLane = $toLane; ToAt = [double]$in.ReplayAt; Style = $script:KcHtArrowCapture })
    }
    # tapping-term、判定、ファームの判定 (計算と違うときだけ)。ウィンドウはこの順に番号を振り、文はグラフの下に並べる
    Add-KcHtMark $chart $firstKeyLane $lastLane ([double]($pressT + $setting.Term)) $script:KcHtMarkTerm ('tapping-term ({0} ms)' -f $setting.Term)
    $d = [KcHtText]::DecisionFor($Result, $ti)
    if ($null -ne $d) {
        Add-KcHtMark $chart $firstKeyLane $lastLane ([double]$d.DecideT) $script:KcHtMarkDecision ('判定: {0} ({1} ms)' -f (Format-KcHtStatus $d.Status), $d.DecideT)
    }
    foreach ($fd in @($Episode.Decisions)) {
        if ($fd.Pos -ne $target) { continue }
        if ($null -eq $d -or $fd.Status -ne $d.Status -or [Math]::Abs($fd.T - $d.DecideT) -gt 1) {
            Add-KcHtMark $chart $firstKeyLane $lastLane ([double]$fd.T) $script:KcHtMarkFirmware ('ファームの判定: {0} ({1} ms)' -f (Format-KcHtStatus $fd.Status), $fd.T)
        }
        break
    }

    # ---- 離す時刻ごとの結果、flavor ごとの比較
    if ($null -ne $Sweeps) {
        $name = Get-KcHtKeyName $Model $target
        [void](Add-KcHtLane $chart ('{0} を離す時刻ごとの結果' -f $name) '' $script:KcHtLaneCaption)
        $first = Add-KcHtLane $chart '今の設定' (Format-KcHtSegments $Sweeps.Segments) $script:KcHtLaneStrip
        Add-KcHtStripBars $chart $first $Sweeps.Segments
        [void](Add-KcHtLane $chart 'flavor ごとの比較 (行を押すとその flavor にする)' '' $script:KcHtLaneCaption)
        foreach ($f in $Sweeps.Flavors) {
            $note = ''
            if ($f.Current) { $note = '今の設定' }
            $lane = Add-KcHtLane $chart $f.Flavor $note $script:KcHtLaneStrip ('flavor:{0}' -f $f.Flavor)
            Add-KcHtStripBars $chart $lane $f.Segments
        }
        if ($null -ne $Sweeps.Release) {
            Add-KcHtMark $chart $first ($chart.Lanes.Count - 1) ([double]$Sweeps.Release) $script:KcHtMarkCursor ('離した時刻 ({0} ms)' -f $Sweeps.Release)
        }
    }
    return $chart
}
