# タップホールドのタイミングを見る (keyboard-check.ps1 -Mode HoldTap) の計算。Windows の API を使わない純粋関数。
# expected.ps1 / hold-tap-sim.ps1 が先に読み込まれている前提。
#
# 押す・離す時刻 (入力) を、ZMK / QMK のシミュレータ (HoldTapSim.cs) で計算し、グラフ (横軸が時刻) の中身を作る。
#   - キーマップ: 期待値 (tools/expected/*.json) の interactive.hold_tap (generate.py が submodule のキーマップから作る)
#   - 設定: キーマップの値をもとに、ウィンドウで変えた値 (flavor、tapping-term など)
#   - 入力: プリセット (ロール・包むなど) か、ログ版ファームで実際に押したもの (1 回分 = エピソード)
#   - 「離す時刻を変えると」: 選んだ入力の時刻を 1ms ずつ動かした結果を、同じ結果の区間にまとめたもの
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
$script:KcHtBarBaseline = 8    # キーマップの値で計算した出力 (枠だけ)
$script:KcHtBarFirmware = 9    # ファームが実際に送った出力 (枠だけ)
$script:KcHtBarStripTap = 10   # 帯: タップ
$script:KcHtBarStripHold = 11  # 帯: ホールド
$script:KcHtBarStripNone = 12  # 帯: 判定なし

$script:KcHtSpanWindow = 0     # quick-tap / require-prior-idle / FLOW_TAP_TERM が効く区間

$script:KcHtMarkDecision = 0   # 判定した時刻
$script:KcHtMarkTerm = 1       # tapping-term (ドラッグできる)
$script:KcHtMarkFirmware = 2   # ファームが判定した時刻
$script:KcHtMarkCursor = 3     # 帯の上の、今の時刻
$script:KcHtMarkBaseline = 4   # キーマップの値で判定した時刻

$script:KcHtArrowCapture = 0   # 判定まで保留されたキー (押した時刻 → 送られた時刻)

$script:KcHtHandleTerm = 1000
$script:KcHtHandleNone = -1

$script:KcHtFlavors = @('hold-preferred', 'balanced', 'tap-preferred', 'tap-unless-interrupted')
$script:KcHtFlavorText = @{
    'hold-preferred'         = 'ほかのキーを押したらホールド'
    'balanced'               = 'ほかのキーを押して離したらホールド'
    'tap-preferred'          = 'tapping-term が過ぎたときだけホールド'
    'tap-unless-interrupted' = 'ほかのキーを押したらホールド (tapping-term が過ぎるとタップ)'
}
$script:KcHtQmkModes = @('default', 'permissive-hold', 'hold-on-other-key-press')
$script:KcHtQmkModeLabel = @{ 'default' = '既定'; 'permissive-hold' = 'PERMISSIVE_HOLD'; 'hold-on-other-key-press' = 'HOLD_ON_OTHER_KEY_PRESS' }
$script:KcHtQmkModeText = @{
    'default'                 = 'TAPPING_TERM が過ぎたらホールド'
    'permissive-hold'         = 'ほかのキーを押して離したら (包んだら) ホールド'
    'hold-on-other-key-press' = 'ほかのキーを押したらホールド'
}

# ---------------------------------------------------------------------------
# キーマップ
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

function ConvertTo-KcHtQmkSettingsFromJson($Json) {
    Import-KcHoldTapSim
    $q = New-Object KcHtQmkSettings
    $q.TappingTerm = [int](Get-KcProp $Json 'tapping_term' 200)
    $q.PermissiveHold = [int](Get-KcProp $Json 'permissive_hold' 0) -ne 0
    $q.HoldOnOtherKeyPress = [int](Get-KcProp $Json 'hold_on_other_key_press' 0) -ne 0
    $q.RetroTapping = [int](Get-KcProp $Json 'retro_tapping' 0) -ne 0
    $q.QuickTapTerm = [int](Get-KcProp $Json 'quick_tap_term' 200)
    $q.ChordalHold = [int](Get-KcProp $Json 'chordal_hold' 0) -ne 0
    $q.FlowTapTerm = [int](Get-KcProp $Json 'flow_tap_term' 0)
    $q.TapCodeDelay = [int](Get-KcProp $Json 'tap_code_delay' 0)
    return $q
}

# 期待値 → モデル。タップホールドが無い機種 (Keyball39) は $null
function New-KcHtModel($Expected) {
    Import-KcHoldTapSim
    $ht = Get-KcProp (Get-KcProp $Expected 'interactive') 'hold_tap' $null
    if ($null -eq $ht) { return $null }
    $engine = [string]$ht.engine
    $km = New-Object KcHtKeymap
    $keys = @{}
    foreach ($k in @(Get-KcProp (Get-KcProp $Expected 'physical') 'keys' @())) {
        if (-not [bool](Get-KcProp $k 'present' $true)) { continue }
        $keys[[int]$k.pos] = @{
            Pos = [int]$k.pos; Legend = [string](Get-KcProp $k 'legend' ''); Hand = [string](Get-KcProp $k 'hand' '')
            X = [double]$k.x; Y = [double]$k.y; Base = $null; QmkHand = ''
        }
    }
    foreach ($k in @($ht.keys)) {
        $pos = [int]$k.pos
        foreach ($p in $k.on.PSObject.Properties) {
            $b = ConvertTo-KcHtBinding $p.Value
            $km.Set($pos, [int]$p.Name, $b)
            if ($p.Name -eq '0' -and $keys.ContainsKey($pos)) { $keys[$pos].Base = $b }
        }
        if ($engine -eq 'qmk') {
            $km.SetCell($pos, [int]$k.usage)
            $h = [string](Get-KcProp $k 'qmk_hand' '*')
            $km.SetHand($pos, [char]$h[0])
            if ($keys.ContainsKey($pos)) { $keys[$pos].QmkHand = $h }
        }
    }
    $baseZmk = @{}
    if ($engine -eq 'zmk') {
        foreach ($p in $ht.behaviors.PSObject.Properties) {
            $cfg = ConvertTo-KcHtZmkConfigFromJson $p.Value
            $km.SetBehavior($p.Name, $cfg)
            $baseZmk[$p.Name] = $cfg
        }
    } else {
        $km.Qmk = ConvertTo-KcHtQmkSettingsFromJson $ht.settings
    }
    # 対象にできるキー: BASE で hold-tap のキー (位置の順)
    $targets = New-Object 'System.Collections.Generic.List[object]'
    foreach ($pos in @($keys.Keys | Sort-Object)) {
        $b = $keys[$pos].Base
        if ($null -eq $b -or $b.Kind -ne 'ht') { continue }
        $targets.Add(@{
                Pos = [int]$pos; Legend = $keys[$pos].Legend; Behavior = $b.Behavior
                TapLabel = $b.Tap.Label; HoldLabel = $b.Hold.Label; HoldIsLayer = ($b.Hold.Kind -eq 'mo'); Hand = $keys[$pos].Hand
            })
    }
    return @{
        Engine = $engine; Name = [string]$Expected.name; Keymap = $km; Keys = $keys; Targets = $targets
        BaseZmk = $baseZmk; BaseQmk = $km.Qmk
    }
}

# 変えられる設定 (ウィンドウの値)。ZMK は behavior ごと、QMK は全体
function New-KcHtConfig($Model) {
    $zmk = @{}
    foreach ($name in @($Model.BaseZmk.Keys)) { $zmk[$name] = $Model.BaseZmk[$name].Clone() }
    $qmk = $null
    if ($null -ne $Model.BaseQmk) { $qmk = $Model.BaseQmk.Clone() }
    return @{ Zmk = $zmk; Qmk = $qmk }
}

function Get-KcHtKeymapWith($Model, $Config) {
    $km = $Model.Keymap
    if ($Model.Engine -eq 'qmk') {
        return $km.WithQmk($Config.Qmk)
    }
    foreach ($name in @($Config.Zmk.Keys)) { $km = $km.WithBehavior($name, $Config.Zmk[$name]) }
    return $km
}

function Get-KcHtTarget($Model, [int]$Pos) {
    foreach ($t in $Model.Targets) {
        if ($t.Pos -eq $Pos) { return $t }
    }
    return $null
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

function Get-KcHtTerm($Model, $Config, [int]$Target) {
    if ($Model.Engine -eq 'qmk') { return [int]$Config.Qmk.TappingTerm }
    $t = Get-KcHtTarget $Model $Target
    if ($null -ne $t -and $Config.Zmk.ContainsKey($t.Behavior)) { return [int]$Config.Zmk[$t.Behavior].Term }
    return 200
}

# ---------------------------------------------------------------------------
# 設定の項目 (ウィンドウの左の欄)
# ---------------------------------------------------------------------------

# 項目の定義: Type = choice (Keys / Labels / Details) か slider (Min / Max / OffText = 0 のときの表示)
function Get-KcHtParamDefs($Model) {
    if ($Model.Engine -eq 'qmk') {
        return @(
            @{ Name = 'term'; Caption = 'TAPPING_TERM (ms)'; Type = 'slider'; Min = 50; Max = 500; OffText = '' },
            @{ Name = 'permissive'; Caption = 'PERMISSIVE_HOLD'; Type = 'choice'; Keys = @('0', '1'); Labels = @('オフ', 'オン')
                Details = @('', 'ほかのキーを押して離したら (包んだら)、TAPPING_TERM の前でもホールド') },
            @{ Name = 'hoop'; Caption = 'HOLD_ON_OTHER_KEY_PRESS'; Type = 'choice'; Keys = @('0', '1'); Labels = @('オフ', 'オン')
                Details = @('', 'ほかのキーを押したらホールド') },
            @{ Name = 'quick'; Caption = 'QUICK_TAP_TERM (ms)'; Type = 'slider'; Min = 0; Max = 500; OffText = 'なし' },
            @{ Name = 'retro'; Caption = 'RETRO_TAPPING'; Type = 'choice'; Keys = @('0', '1'); Labels = @('オフ', 'オン')
                Details = @('', '長押しのあと、ほかのキーを押さずに離したらタップを送る') },
            @{ Name = 'chordal'; Caption = 'CHORDAL_HOLD'; Type = 'choice'; Keys = @('0', '1'); Labels = @('オフ', 'オン')
                Details = @('', '同じ手のキーと押したらタップ (KQ-mini の左右はキーのコードで決まる)') },
            @{ Name = 'flow'; Caption = 'FLOW_TAP_TERM (ms)'; Type = 'slider'; Min = 0; Max = 300; OffText = 'なし' }
        )
    }
    return @(
        @{ Name = 'flavor'; Caption = 'flavor'; Type = 'choice'; Keys = $script:KcHtFlavors; Labels = $script:KcHtFlavors
            Details = @($script:KcHtFlavors | ForEach-Object { $script:KcHtFlavorText[$_] }) },
        @{ Name = 'term'; Caption = 'tapping-term-ms'; Type = 'slider'; Min = 50; Max = 500; OffText = '' },
        @{ Name = 'quick'; Caption = 'quick-tap-ms'; Type = 'slider'; Min = 0; Max = 500; OffText = 'なし' },
        @{ Name = 'idle'; Caption = 'require-prior-idle-ms'; Type = 'slider'; Min = 0; Max = 500; OffText = 'なし' },
        @{ Name = 'positional'; Caption = 'hold-trigger-key-positions'; Type = 'choice'; Keys = @('off', 'opposite', 'keymap')
            Labels = @('なし', '反対の手', 'キーマップ'); Details = @('', '反対の手のキーを押したときだけホールド (同じ手ならタップ)', 'キーマップに書いた位置') },
        @{ Name = 'onrelease'; Caption = 'hold-trigger-on-release'; Type = 'choice'; Keys = @('0', '1'); Labels = @('オフ', 'オン')
            Details = @('', 'hold-trigger-key-positions を、押したときではなく離したときに見る') },
        @{ Name = 'retro'; Caption = 'retro-tap'; Type = 'choice'; Keys = @('0', '1'); Labels = @('オフ', 'オン')
            Details = @('', '時間切れでホールドになっても、ほかのキーを押さずに離したらタップ') },
        @{ Name = 'hwu'; Caption = 'hold-while-undecided'; Type = 'choice'; Keys = @('0', '1', 'linger'); Labels = @('オフ', 'オン', 'linger')
            Details = @('', '判定を待つ間もホールドを押しておく', '判定を待つ間もホールドを押し、タップのあとも離すまで押しておく') }
    )
}

function Get-KcHtOppositePositions($Model, [int]$Target) {
    $hand = ''
    if ($Model.Keys.ContainsKey($Target)) { $hand = $Model.Keys[$Target].Hand }
    $out = New-Object 'System.Collections.Generic.List[int]'
    foreach ($pos in @($Model.Keys.Keys | Sort-Object)) {
        if ($Model.Keys[$pos].Hand -and $Model.Keys[$pos].Hand -ne $hand) { $out.Add([int]$pos) }
    }
    return , $out.ToArray()
}

# 設定の値 (ウィンドウに出す文字列 / 数)
function Get-KcHtParamValue($Model, $Config, [int]$Target, [string]$Name) {
    if ($Model.Engine -eq 'qmk') {
        $q = $Config.Qmk
        switch ($Name) {
            'term' { return [int]$q.TappingTerm }
            'permissive' { return ([string][int]$q.PermissiveHold) }
            'hoop' { return ([string][int]$q.HoldOnOtherKeyPress) }
            'quick' { return [int]$q.QuickTapTerm }
            'retro' { return ([string][int]$q.RetroTapping) }
            'chordal' { return ([string][int]$q.ChordalHold) }
            'flow' { return [int]$q.FlowTapTerm }
        }
        return $null
    }
    $t = Get-KcHtTarget $Model $Target
    if ($null -eq $t) { return $null }
    $c = $Config.Zmk[$t.Behavior]
    switch ($Name) {
        'flavor' { return $c.Flavor }
        'term' { return [int]$c.Term }
        'quick' { return [int][Math]::Max(0, $c.QuickTap) }
        'idle' { return [int][Math]::Max(0, $c.PriorIdle) }
        'positional' {
            $p = @($c.TriggerPositions)
            if ($p.Count -eq 0) { return 'off' }
            $opp = @(Get-KcHtOppositePositions $Model $Target)
            if (($p -join ',') -eq ($opp -join ',')) { return 'opposite' }
            return 'keymap'
        }
        'onrelease' { return ([string][int]$c.TriggerOnRelease) }
        'retro' { return ([string][int]$c.RetroTap) }
        'hwu' {
            if (-not $c.Hwu) { return '0' }
            if ($c.HwuLinger) { return 'linger' }
            return '1'
        }
    }
    return $null
}

# 値を変える。$Value はウィンドウからの文字列
function Set-KcHtParamValue($Model, $Config, [int]$Target, [string]$Name, [string]$Value) {
    if ($Model.Engine -eq 'qmk') {
        $q = $Config.Qmk.Clone()
        switch ($Name) {
            'term' { $q.TappingTerm = [int]$Value }
            'permissive' { $q.PermissiveHold = ($Value -eq '1') }
            'hoop' { $q.HoldOnOtherKeyPress = ($Value -eq '1') }
            'quick' { $q.QuickTapTerm = [int]$Value }
            'retro' { $q.RetroTapping = ($Value -eq '1') }
            'chordal' { $q.ChordalHold = ($Value -eq '1') }
            'flow' { $q.FlowTapTerm = [int]$Value }
            'mode' {
                $q.PermissiveHold = ($Value -eq 'permissive-hold')
                $q.HoldOnOtherKeyPress = ($Value -eq 'hold-on-other-key-press')
            }
        }
        $Config.Qmk = $q
        return
    }
    $t = Get-KcHtTarget $Model $Target
    if ($null -eq $t) { return }
    $c = $Config.Zmk[$t.Behavior].Clone()
    switch ($Name) {
        'flavor' { $c.Flavor = $Value }
        'term' { $c.Term = [int]$Value }
        'quick' {
            $c.QuickTap = [int]$Value
            if ($c.QuickTap -le 0) { $c.QuickTap = -1 }
        }
        'idle' {
            $c.PriorIdle = [int]$Value
            if ($c.PriorIdle -le 0) { $c.PriorIdle = -1 }
        }
        'positional' {
            switch ($Value) {
                'opposite' { $c.TriggerPositions = Get-KcHtOppositePositions $Model $Target }
                'keymap' { $c.TriggerPositions = [int[]]@($Model.BaseZmk[$t.Behavior].TriggerPositions) }
                default { $c.TriggerPositions = [int[]]@() }
            }
        }
        'onrelease' { $c.TriggerOnRelease = ($Value -eq '1') }
        'retro' { $c.RetroTap = ($Value -eq '1') }
        'hwu' {
            $c.Hwu = ($Value -ne '0')
            $c.HwuLinger = ($Value -eq 'linger')
        }
    }
    $Config.Zmk[$t.Behavior] = $c
}

# キーマップの値と違う設定の名前
function Get-KcHtChangedParams($Model, $Config, [int]$Target) {
    $base = New-KcHtConfig $Model
    $out = New-Object 'System.Collections.Generic.List[string]'
    foreach ($d in (Get-KcHtParamDefs $Model)) {
        $a = [string](Get-KcHtParamValue $Model $Config $Target $d.Name)
        $b = [string](Get-KcHtParamValue $Model $base $Target $d.Name)
        if ($a -ne $b) { $out.Add($d.Name) }
    }
    return , $out.ToArray()
}

# 設定を 1 行の文字列に (比べる・表示する)
function Format-KcHtConfig($Model, $Config, [int]$Target) {
    if ($Model.Engine -eq 'qmk') {
        $q = $Config.Qmk
        $parts = @('TAPPING_TERM {0}' -f $q.TappingTerm)
        if ($q.PermissiveHold) { $parts += 'PERMISSIVE_HOLD' }
        if ($q.HoldOnOtherKeyPress) { $parts += 'HOLD_ON_OTHER_KEY_PRESS' }
        if ($q.QuickTapTerm -gt 0) { $parts += ('QUICK_TAP_TERM {0}' -f $q.QuickTapTerm) }
        if ($q.RetroTapping) { $parts += 'RETRO_TAPPING' }
        if ($q.ChordalHold) { $parts += 'CHORDAL_HOLD' }
        if ($q.FlowTapTerm -gt 0) { $parts += ('FLOW_TAP_TERM {0}' -f $q.FlowTapTerm) }
        return ($parts -join ' / ')
    }
    $t = Get-KcHtTarget $Model $Target
    if ($null -eq $t) { return '' }
    $c = $Config.Zmk[$t.Behavior]
    $parts = @($c.Flavor, ('tapping-term {0}' -f $c.Term))
    if ($c.QuickTap -gt 0) { $parts += ('quick-tap {0}' -f $c.QuickTap) }
    if ($c.PriorIdle -gt 0) { $parts += ('require-prior-idle {0}' -f $c.PriorIdle) }
    if (@($c.TriggerPositions).Count -gt 0) { $parts += 'hold-trigger-key-positions' }
    if ($c.TriggerOnRelease) { $parts += 'hold-trigger-on-release' }
    if ($c.RetroTap) { $parts += 'retro-tap' }
    if ($c.Hwu) { $parts += 'hold-while-undecided' }
    return ('&{0}: {1}' -f $t.Behavior, ($parts -join ' / '))
}

# ---------------------------------------------------------------------------
# 入力 (プリセット)
# ---------------------------------------------------------------------------

$script:KcHtLetters = @(0x04..0x1D)

# 相手のキー: 対象の反対の手 (-Same なら同じ手) の、素の文字キー。対象の段に近いもの
function Get-KcHtPartner($Model, [int]$Target, [switch]$Same, [int[]]$Exclude = @()) {
    $tk = $Model.Keys[$Target]
    $best = $null
    $bestScore = [double]::MaxValue
    foreach ($pos in @($Model.Keys.Keys | Sort-Object)) {
        if ($pos -eq $Target -or $Exclude -contains $pos) { continue }
        $k = $Model.Keys[$pos]
        $b = $k.Base
        if ($null -eq $b -or $b.Kind -ne 'kp' -or $b.Mods -ne 0 -or $script:KcHtLetters -notcontains $b.Usage) { continue }
        $sameHand = ($k.Hand -eq $tk.Hand)
        if ([bool]$Same -ne $sameHand) { continue }
        $score = [Math]::Abs($k.Y - $tk.Y) * 10 + [Math]::Abs($k.X - $tk.X)
        if ($score -lt $bestScore) {
            $bestScore = $score
            $best = [int]$pos
        }
    }
    return $best
}

# もう 1 つの hold-tap (2 つの hold-tap のプリセット): 対象と同じ手の、修飾キーの mod-tap
function Get-KcHtSecondTarget($Model, [int]$Target) {
    $tk = $Model.Keys[$Target]
    foreach ($t in $Model.Targets) {
        if ($t.Pos -eq $Target -or $t.HoldIsLayer) { continue }
        if ($t.Hand -eq $tk.Hand) { return $t.Pos }
    }
    foreach ($t in $Model.Targets) {
        if ($t.Pos -ne $Target -and -not $t.HoldIsLayer) { return $t.Pos }
    }
    return $null
}

function Get-KcHtPresetDefs($Model, [int]$Target) {
    $list = @(
        @{ Id = 'single'; Label = '単独'; Detail = '対象のキーだけを押して離す' },
        @{ Id = 'roll'; Label = 'ロール'; Detail = '対象 → 相手を押し、対象を先に離す (速く打つときの重なり)' },
        @{ Id = 'nest'; Label = '包む'; Detail = '対象を押したまま、相手を押して離す (修飾キーとして使うとき)' },
        @{ Id = 'pre'; Label = '先に押す'; Detail = '相手を先に押し、そのまま対象を押す' },
        @{ Id = 'double'; Label = '連打'; Detail = '対象をタップしてすぐ押し直す (quick-tap)' },
        @{ Id = 'prior'; Label = '直前に別のキー'; Detail = '別のキーを打った直後に対象を押す (require-prior-idle / FLOW_TAP_TERM)' }
    )
    if ($null -ne (Get-KcHtSecondTarget $Model $Target)) {
        $list += @{ Id = 'two'; Label = '2 つの hold-tap'; Detail = 'hold-tap を 2 つ押したまま、相手を押して離す' }
    }
    return $list
}

function New-KcHtEvent([int]$Pos, [bool]$Down, [long]$T, [string]$Role) {
    return @{ Pos = $Pos; Down = $Down; T = $T; Role = $Role }
}

# プリセット → @{ Id; Events; TargetIndex (判定を見る押下); Handle (最初に選ぶ入力) }
function New-KcHtPreset($Model, $Config, [int]$Target, [string]$Id, [switch]$Same) {
    $term = Get-KcHtTerm $Model $Config $Target
    $p = Get-KcHtPartner $Model $Target -Same:$Same
    if ($null -eq $p) { $p = Get-KcHtPartner $Model $Target -Same:(-not $Same) }
    if ($null -eq $p) { $p = -1 }
    $ev = New-Object 'System.Collections.Generic.List[object]'
    $targetIndex = 0
    $handle = 0
    switch ($Id) {
        'single' {
            $ev.Add((New-KcHtEvent $Target $true 0 'target'))
            $ev.Add((New-KcHtEvent $Target $false ([Math]::Max(40, $term - 40)) 'target'))
            $handle = 1
        }
        'roll' {
            $ev.Add((New-KcHtEvent $Target $true 0 'target'))
            $ev.Add((New-KcHtEvent $p $true 50 'partner'))
            $ev.Add((New-KcHtEvent $Target $false 90 'target'))
            $ev.Add((New-KcHtEvent $p $false 130 'partner'))
            $handle = 2
        }
        'nest' {
            $ev.Add((New-KcHtEvent $Target $true 0 'target'))
            $ev.Add((New-KcHtEvent $p $true 50 'partner'))
            $ev.Add((New-KcHtEvent $p $false 100 'partner'))
            $ev.Add((New-KcHtEvent $Target $false 140 'target'))
            $handle = 2
        }
        'pre' {
            $ev.Add((New-KcHtEvent $p $true -40 'partner'))
            $ev.Add((New-KcHtEvent $Target $true 0 'target'))
            $ev.Add((New-KcHtEvent $p $false 40 'partner'))
            $ev.Add((New-KcHtEvent $Target $false 100 'target'))
            $targetIndex = 1
            $handle = 3
        }
        'double' {
            $ev.Add((New-KcHtEvent $Target $true 0 'target'))
            $ev.Add((New-KcHtEvent $Target $false 60 'target'))
            $ev.Add((New-KcHtEvent $Target $true 120 'target'))
            $ev.Add((New-KcHtEvent $Target $false ([long](120 + $term + 80)) 'target'))
            $targetIndex = 2
            $handle = 2
        }
        'prior' {
            $k = Get-KcHtPartner $Model $Target -Same:$Same -Exclude @($p)
            if ($null -eq $k) { $k = $p }
            $ev.Add((New-KcHtEvent $k $true -120 'prior'))
            $ev.Add((New-KcHtEvent $k $false -80 'prior'))
            $ev.Add((New-KcHtEvent $Target $true 0 'target'))
            $ev.Add((New-KcHtEvent $p $true 50 'partner'))
            $ev.Add((New-KcHtEvent $p $false 100 'partner'))
            $ev.Add((New-KcHtEvent $Target $false 140 'target'))
            $targetIndex = 2
            $handle = 1
        }
        'two' {
            $s = Get-KcHtSecondTarget $Model $Target
            $ev.Add((New-KcHtEvent $Target $true 0 'target'))
            $ev.Add((New-KcHtEvent $s $true 40 'second'))
            $ev.Add((New-KcHtEvent $p $true 80 'partner'))
            $ev.Add((New-KcHtEvent $p $false 120 'partner'))
            $ev.Add((New-KcHtEvent $s $false 160 'second'))
            $ev.Add((New-KcHtEvent $Target $false 200 'target'))
            $handle = 5
        }
        default { throw "知らないプリセットです: $Id" }
    }
    return @{ Id = $Id; Events = $ev.ToArray(); TargetIndex = $targetIndex; Handle = $handle }
}

# 入力 $Index を動かせる範囲 (同じキーの前後の押す / 離すを越えない)
function Get-KcHtHandleLimits($Events, [int]$Index) {
    $e = $Events[$Index]
    $min = [long]-2000
    $max = [long]5000
    for ($i = $Index - 1; $i -ge 0; $i--) {
        if ($Events[$i].Pos -eq $e.Pos) { $min = [long]$Events[$i].T + 1; break }
    }
    for ($i = $Index + 1; $i -lt $Events.Count; $i++) {
        if ($Events[$i].Pos -eq $e.Pos) { $max = [long]$Events[$i].T - 1; break }
    }
    return @{ Min = $min; Max = $max }
}

# 入力の時刻を変えた新しい並び (時刻順に並べ直さない。シミュレータが時刻順に処理する)
function Set-KcHtEventTime($Events, [int]$Index, [long]$T) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt $Events.Count; $i++) {
        $e = $Events[$i]
        if ($i -eq $Index) {
            $lim = Get-KcHtHandleLimits $Events $Index
            $t = [Math]::Min([Math]::Max($T, $lim.Min), $lim.Max)
            $out.Add(@{ Pos = $e.Pos; Down = $e.Down; T = [long]$t; Role = $e.Role })
        } else {
            $out.Add($e)
        }
    }
    return , $out.ToArray()
}

function Format-KcHtEventName($Model, $Event) {
    $what = '離す'
    if ($Event.Down) { $what = '押す' }
    return ('{0} を{1}' -f (Get-KcHtKeyName $Model $Event.Pos), $what)
}

# ---------------------------------------------------------------------------
# 計算と、結果の文
# ---------------------------------------------------------------------------

function Invoke-KcHtRun($Model, $Keymap, $Events) {
    Import-KcHoldTapSim
    return [KcHtSweep]::Run($Model.Engine, $Keymap, (ConvertTo-KcHtInputs $Events))
}

function Format-KcHtStatus([string]$Engine, [string]$Status) {
    switch ($Status) {
        'tap' { return 'タップ' }
        'hold' { return 'ホールド' }
        'hold-timer' { return 'ホールド (時間切れ)' }
        'hold-interrupt' { return 'ホールド (ほかのキー)' }
        '' { return '判定なし' }
    }
    return $Status
}

function Get-KcHtStatusClass([string]$Status) {
    if ($Status -eq 'tap') { return 'tap' }
    if ($Status -like 'hold*') { return 'hold' }
    return 'none'
}

# 判定の理由の文
function Format-KcHtMoment($Model, $Config, [int]$Target, $Decision, $Events) {
    $t = $Decision.DecideT
    $name = Get-KcHtKeyName $Model $Decision.Pos
    $other = ''
    if ($Decision.Other -ge 0) { $other = Get-KcHtKeyName $Model $Decision.Other }
    $term = Get-KcHtTerm $Model $Config $Target
    switch ($Decision.Moment) {
        # ZMK
        'key-up' { return ('{0} ms に {1} を離した' -f $t, $name) }
        'other-key-down' { return ('{0} ms に {1} を押した' -f $t, $other) }
        'other-key-up' { return ('{0} ms に {1} を離した (押している間に、ほかのキーを押して離した)' -f $t, $other) }
        'timer' { return ('tapping-term ({0} ms) が過ぎた ({1} ms)' -f $term, $t) }
        'quick-tap' {
            if ($Model.Engine -eq 'qmk') { return ('前のタップから QUICK_TAP_TERM 以内に押し直した ({0} ms)' -f $t) }
            return ('押したとき、直前のキーから require-prior-idle 以内か、前のタップから quick-tap 以内だった ({0} ms)' -f $t)
        }
        # QMK
        'release' { return ('{0} ms に {1} を離した (TAPPING_TERM {2} ms より前)' -f $t, $name, $term) }
        'timeout' { return ('TAPPING_TERM ({0} ms) が過ぎた ({1} ms)' -f $term, $t) }
        'permissive' { return ('{0} ms に {1} を離した (押している間に押して離した: PERMISSIVE_HOLD)' -f $t, $other) }
        'other-press' { return ('{0} ms に {1} を押した (HOLD_ON_OTHER_KEY_PRESS)' -f $t, $other) }
        'chordal' {
            if ($other) { return ('{0} は同じ手のキー (CHORDAL_HOLD) なのでタップ ({1} ms)' -f $other, $t) }
            return ('同じ手のキーと押した (CHORDAL_HOLD) のでタップ ({0} ms)' -f $t)
        }
        'flow-tap' { return ('直前のキーから FLOW_TAP_TERM 以内に押した ({0} ms)' -f $t) }
    }
    return ('{0} ({1} ms)' -f $Decision.Moment, $t)
}

# 要約 (ウィンドウの上の欄): @{ Title; Lines; Level (1 = タップ、2 = ホールド、0 = なし) }
function Get-KcHtSummary($Model, $Config, [int]$Target, $Events, [int]$TargetIndex, $Result) {
    Import-KcHoldTapSim
    $d = [KcHtText]::DecisionFor($Result, $TargetIndex)
    $strokes = [KcHtText]::Strokes($Result)
    if (-not $strokes) { $strokes = '(なし)' }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $d) {
        return @{ Title = ('判定なし: {0}' -f $strokes); Lines = @('対象のキーの判定がありません'); Level = 0 }
    }
    $status = Format-KcHtStatus $Model.Engine $d.Status
    $title = '{0}: PC に届くのは {1}' -f $status, $strokes
    $lines.Add(('決め手: {0}' -f (Format-KcHtMoment $Model $Config $Target $d $Events)))
    if ($d.Positional) {
        $lines.Add(('最初に押したほかのキー ({0}) が hold-trigger-key-positions に無いので、タップにした' -f (Get-KcHtKeyName $Model $d.FirstOther)))
    }
    if ($d.Retro) {
        $lines.Add(('時間切れでホールドになったが、ほかのキーを押さずに離したので、{0} でタップを送った ({1} ms)' -f @('retro-tap', 'RETRO_TAPPING')[[int]($Model.Engine -eq 'qmk')], $d.RetroT))
    }
    for ($i = 0; $i -lt $Result.Inputs.Count; $i++) {
        $in = $Result.Inputs[$i]
        if (-not $in.Captured -or -not $in.Down) { continue }
        if ($in.ReplayAt -gt $in.At) {
            $lines.Add(('{0} を押したのは {1} ms、PC に送られたのは判定のあとの {2} ms ({3} ms 遅れ)' -f (Get-KcHtKeyName $Model $in.Pos), $in.At, $in.ReplayAt, ($in.ReplayAt - $in.At)))
        }
    }
    if ($Model.Engine -eq 'qmk') {
        $mode = [KcQmkTapHoldSim]::QmkFlavor($Config.Qmk)
        $lines.Add(('{0}: {1}' -f $script:KcHtQmkModeLabel[$mode], $script:KcHtQmkModeText[$mode]))
    } else {
        $flavor = Get-KcHtParamValue $Model $Config $Target 'flavor'
        $lines.Add(('{0}: {1}' -f $flavor, $script:KcHtFlavorText[$flavor]))
    }
    if ($Result.Approx) {
        $lines.Add('モッドモーフなどのキーは、押すと文字のキーを押したものとして計算しています (目安)')
    }
    $level = 2
    if ($d.Status -eq 'tap') { $level = 1 }
    return @{ Title = $title; Lines = $lines.ToArray(); Level = $level }
}

# 帯 (区間) の境目の文: 「〜140 ms: タップ → A H / 141 ms〜: ホールド (ほかのキー) → Ctrl+H」
function Format-KcHtSegments($Model, $Segments, [string]$Unit = 'ms') {
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $n = @($Segments).Count
    for ($i = 0; $i -lt $n; $i++) {
        $s = @($Segments)[$i]
        $range = '{0}〜{1} {2}' -f $s.From, $s.To, $Unit
        if ($n -gt 1 -and $i -eq 0) { $range = '〜{0} {1}' -f $s.To, $Unit }
        if ($n -gt 1 -and $i -eq $n - 1) { $range = '{0} {1}〜' -f $s.From, $Unit }
        $text = $s.Text
        if (-not $text) { $text = 'なし' }
        $parts.Add(('{0}: {1} → {2}' -f $range, (Format-KcHtStatus $Model.Engine $s.Status), $text))
    }
    return ($parts -join ' / ')
}

# ---------------------------------------------------------------------------
# 帯 (離す時刻・tapping-term を変えると、設定ごとの比較)
# ---------------------------------------------------------------------------

# 選んだ入力 (またはtapping-term) を動かした区間。$Range: @{ From; To } (グラフの横軸)
function Get-KcHtSweep($Model, $Keymap, $Events, [int]$TargetIndex, [int]$Handle, $Range, [string]$Behavior) {
    Import-KcHoldTapSim
    $inputs = ConvertTo-KcHtInputs $Events
    if ($Handle -eq $script:KcHtHandleTerm) {
        $press = [long]$Events[$TargetIndex].T
        $hi = [int][Math]::Min(500, [Math]::Max(50, $Range.To - $press))
        return @([KcHtSweep]::VaryTerm($Model.Engine, $Keymap, $Behavior, $inputs, 50, $hi, $TargetIndex))
    }
    if ($Handle -lt 0 -or $Handle -ge $Events.Count) { return @() }
    $lim = Get-KcHtHandleLimits $Events $Handle
    $from = [long][Math]::Max($lim.Min, $Range.From)
    $to = [long][Math]::Min($lim.Max, $Range.To)
    if ($to -lt $from) { return @() }
    return @([KcHtSweep]::VaryInput($Model.Engine, $Keymap, $inputs, $Handle, $from, $to, $TargetIndex))
}

# 比べる設定 (ZMK: flavor ごと、QMK: 既定 / PERMISSIVE_HOLD / HOLD_ON_OTHER_KEY_PRESS) → @(@{ Key; Label; Keymap; Current })
function Get-KcHtCompareConfigs($Model, $Config, [int]$Target) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    if ($Model.Engine -eq 'qmk') {
        $cur = [KcQmkTapHoldSim]::QmkFlavor($Config.Qmk)
        foreach ($m in $script:KcHtQmkModes) {
            $c = @{ Zmk = $Config.Zmk; Qmk = $Config.Qmk }
            Set-KcHtParamValue $Model $c $Target 'mode' $m
            $out.Add(@{ Key = $m; Label = $script:KcHtQmkModeLabel[$m]; Keymap = (Get-KcHtKeymapWith $Model $c); Current = ($m -eq $cur); Action = ('param:mode:{0}' -f $m) })
        }
        return , $out.ToArray()
    }
    $cur = Get-KcHtParamValue $Model $Config $Target 'flavor'
    foreach ($f in $script:KcHtFlavors) {
        $zmk = @{}
        foreach ($k in @($Config.Zmk.Keys)) { $zmk[$k] = $Config.Zmk[$k] }
        $c = @{ Zmk = $zmk; Qmk = $Config.Qmk }
        Set-KcHtParamValue $Model $c $Target 'flavor' $f
        $out.Add(@{ Key = $f; Label = $f; Keymap = (Get-KcHtKeymapWith $Model $c); Current = ($f -eq $cur); Action = ('param:flavor:{0}' -f $f) })
    }
    return , $out.ToArray()
}

# ---------------------------------------------------------------------------
# グラフのモデル
# ---------------------------------------------------------------------------

# 横軸の範囲 (50ms 単位)。$Prev があれば、はみ出さない限りそれを使う (ドラッグ中に縮尺を変えない)
function Get-KcHtRange($Events, $Result, [long]$PressT, [int]$Term, $Prev = $null) {
    $min = [long]0
    $max = [long]($PressT + $Term + 60)
    foreach ($e in $Events) {
        if ($e.T -lt $min) { $min = [long]$e.T }
        if ($e.T -gt $max) { $max = [long]$e.T }
    }
    if ($null -ne $Result) {
        if ($Result.EndT -gt $max) { $max = [long]$Result.EndT }
    }
    $from = [long]([Math]::Floor(($min - 60) / 50.0) * 50)
    $to = [long]([Math]::Ceiling(($max + 80) / 50.0) * 50)
    if ($to - $from -lt 400) { $to = $from + 400 }
    if ($null -ne $Prev -and $Prev.From -le $from -and $Prev.To -ge $to) { return $Prev }
    return @{ From = $from; To = $to }
}

function New-KcHtChart {
    return @{
        From = 0; To = 400
        Lanes = (New-Object 'System.Collections.Generic.List[object]')
        Bars = (New-Object 'System.Collections.Generic.List[object]')
        Spans = (New-Object 'System.Collections.Generic.List[object]')
        Marks = (New-Object 'System.Collections.Generic.List[object]')
        Arrows = (New-Object 'System.Collections.Generic.List[object]')
        Handles = (New-Object 'System.Collections.Generic.List[object]')
        Selected = $script:KcHtHandleNone
    }
}

function Add-KcHtLane($Chart, [string]$Title, [string]$Note, [int]$Kind, [string]$Action = '') {
    $Chart.Lanes.Add(@{ Title = $Title; Note = $Note; Kind = $Kind; Action = $Action })
    return $Chart.Lanes.Count - 1
}

function Add-KcHtBar($Chart, [int]$Lane, [double]$From, [double]$To, [int]$Style, [string]$Text = '', [int]$Start = -1, [int]$End = -1) {
    $Chart.Bars.Add(@{ Lane = $Lane; From = $From; To = $To; Style = $Style; Text = $Text; Start = $Start; End = $End })
}

function Add-KcHtMark($Chart, [int]$LaneFrom, [int]$LaneTo, [double]$At, [int]$Style, [string]$Text = '', [int]$Handle = -1) {
    $Chart.Marks.Add(@{ LaneFrom = $LaneFrom; LaneTo = $LaneTo; At = $At; Style = $Style; Text = $Text; Handle = $Handle })
}

# 出力 (Hid) をレーンごとの区間に: @(@{ Key; Title; Note; Style; Items = @(@{ From; To }) })
function Get-KcHtOutputRuns($Hid, [double]$End) {
    $runs = New-Object 'System.Collections.Generic.List[object]'
    $byKey = @{}
    $open = @{}
    foreach ($o in $Hid) {
        if ($o.Kind -eq 'layer') {
            $key = 'layer:{0}' -f $o.Layer
            $style = $script:KcHtBarLayer
            $note = 'レイヤー'
        } elseif ($o.Kind -eq 'other') {
            $key = 'other:{0}' -f $o.Label
            $style = $script:KcHtBarOther
            $note = 'ビヘイビア'
        } else {
            $key = 'key:{0}' -f $o.Usage
            if ($o.Usage -ge 0xE0 -and $o.Usage -le 0xE7) {
                $style = $script:KcHtBarMod
                $note = '修飾キー'
            } else {
                $style = $script:KcHtBarKey
                $note = 'キー'
            }
        }
        if (-not $byKey.ContainsKey($key)) {
            $run = @{ Key = $key; Title = [string]$o.Label; Note = $note; Style = $style; Items = (New-Object 'System.Collections.Generic.List[object]') }
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

# ファームのログの HID (@{ T; Usage; Pressed; Mods }) → Hid と同じ形
function ConvertTo-KcHtHidFromLog($Records) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($r in @($Records)) {
        $label = ''
        if ($null -ne $r.Label) { $label = [string]$r.Label }
        $out.Add(@{ T = [double]$r.T; Down = [bool]$r.Pressed; Kind = 'key'; Usage = [int]$r.Usage; Mods = 0; Layer = -1; Label = $label })
    }
    return , $out.ToArray()
}

# $View: @{ Model; Config; Target; Events; TargetIndex; Selected; Result; Base (キーマップの値の結果か $null);
#           Firmware (@{ Decisions; Hid } か $null); Range; Sweeps = @{ Handle; Compare; Term } (無ければ $null) }
function Get-KcHoldTapChart($View) {
    Import-KcHoldTapSim
    $model = $View.Model
    $events = $View.Events
    $result = $View.Result
    $chart = New-KcHtChart
    $chart.From = $View.Range.From
    $chart.To = $View.Range.To
    $end = [double]$chart.To
    $term = Get-KcHtTerm $model $View.Config $View.Target
    $pressT = [long]$events[$View.TargetIndex].T
    $isQmk = ($model.Engine -eq 'qmk')

    # ---- 押したキー
    [void](Add-KcHtLane $chart '押したキー' '' $script:KcHtLaneCaption)
    $keyLane = @{}
    $order = New-Object 'System.Collections.Generic.List[int]'
    foreach ($role in @('target', 'second', 'partner', 'prior', '')) {
        foreach ($e in $events) {
            $r = ''
            if ($null -ne $e.Role) { $r = [string]$e.Role }
            if (($role -eq '' -or $r -eq $role) -and -not $order.Contains([int]$e.Pos)) { $order.Add([int]$e.Pos) }
        }
    }
    foreach ($pos in $order) {
        $note = ''
        if ($model.Keys.ContainsKey($pos) -and $null -ne $model.Keys[$pos].Base) {
            $b = $model.Keys[$pos].Base
            if ($b.Kind -eq 'ht') {
                if ($isQmk) { $note = $b.Src } else { $note = '&{0}' -f $b.Behavior }
            }
        }
        $keyLane[$pos] = Add-KcHtLane $chart (Get-KcHtKeyName $model $pos) $note $script:KcHtLaneKey
    }
    $firstKeyLane = 1
    $lastKeyLane = $chart.Lanes.Count - 1
    # 押下の帯 (押す → 離す)。hold-tap は判定までを判定待ち、そのあとをタップ / ホールドで塗る
    for ($i = 0; $i -lt $events.Count; $i++) {
        $e = $events[$i]
        if (-not $e.Down) { continue }
        $j = -1
        for ($k = $i + 1; $k -lt $events.Count; $k++) {
            if ($events[$k].Pos -eq $e.Pos) { $j = $k; break }
        }
        $upT = $end
        if ($j -ge 0 -and -not $events[$j].Down) { $upT = [double]$events[$j].T }
        $lane = $keyLane[[int]$e.Pos]
        $d = [KcHtText]::DecisionFor($result, $i)
        $at = [double]$e.T
        if ($i -lt $result.Inputs.Count -and $result.Inputs[$i].At -ge 0) { $at = [double]$result.Inputs[$i].At }
        if ($null -ne $d) {
            $decT = [Math]::Min([double]$d.DecideT, $upT)
            $style = $script:KcHtBarHold
            if ($d.Status -eq 'tap') { $style = $script:KcHtBarTap }
            if ($decT -gt $at) {
                Add-KcHtBar $chart $lane $at $decT $script:KcHtBarUndecided '判定待ち' $i -1
                Add-KcHtBar $chart $lane $decT $upT $style (Format-KcHtStatus $model.Engine $d.Status) -1 $j
            } else {
                Add-KcHtBar $chart $lane $at $upT $style (Format-KcHtStatus $model.Engine $d.Status) $i $j
            }
        } else {
            Add-KcHtBar $chart $lane $at $upT $script:KcHtBarPlain '' $i $j
        }
    }
    # quick-tap / require-prior-idle / FLOW_TAP_TERM が効く区間 (対象の押下の前)
    $targetLane = $keyLane[[int]$events[$View.TargetIndex].Pos]
    if ($isQmk) {
        $q = $View.Config.Qmk
        if ($q.FlowTapTerm -gt 0) {
            $prev = $null
            for ($i = 0; $i -lt $events.Count; $i++) {
                if ($i -ne $View.TargetIndex -and $events[$i].T -lt $pressT) { $prev = $events[$i] }
            }
            if ($null -ne $prev) {
                $chart.Spans.Add(@{ LaneFrom = $targetLane; LaneTo = $targetLane; From = [double]$prev.T; To = [double]($prev.T + $q.FlowTapTerm); Style = $script:KcHtSpanWindow; Text = 'FLOW_TAP_TERM' })
            }
        }
        if ($q.QuickTapTerm -gt 0) {
            for ($i = 0; $i -lt $View.TargetIndex; $i++) {
                if ($events[$i].Pos -eq $events[$View.TargetIndex].Pos -and $events[$i].Down) {
                    $chart.Spans.Add(@{ LaneFrom = $targetLane; LaneTo = $targetLane; From = [double]$events[$i].T; To = [double]($events[$i].T + $q.QuickTapTerm); Style = $script:KcHtSpanWindow; Text = 'QUICK_TAP_TERM' })
                }
            }
        }
    } else {
        $t = Get-KcHtTarget $model $View.Target
        $c = $View.Config.Zmk[$t.Behavior]
        if ($c.PriorIdle -gt 0) {
            $prev = $null
            for ($i = 0; $i -lt $events.Count; $i++) {
                if ($events[$i].Down -and $i -ne $View.TargetIndex -and $events[$i].T -lt $pressT) { $prev = $events[$i] }
            }
            if ($null -ne $prev) {
                $chart.Spans.Add(@{ LaneFrom = $targetLane; LaneTo = $targetLane; From = [double]$prev.T; To = [double]($prev.T + $c.PriorIdle); Style = $script:KcHtSpanWindow; Text = 'require-prior-idle' })
            }
        }
        if ($c.QuickTap -gt 0) {
            for ($i = 0; $i -lt $View.TargetIndex; $i++) {
                if ($events[$i].Pos -eq $events[$View.TargetIndex].Pos -and $events[$i].Down) {
                    $chart.Spans.Add(@{ LaneFrom = $targetLane; LaneTo = $targetLane; From = [double]$events[$i].T; To = [double]($events[$i].T + $c.QuickTap); Style = $script:KcHtSpanWindow; Text = 'quick-tap' })
                }
            }
        }
    }

    # ---- PC に届く入力
    [void](Add-KcHtLane $chart 'PC に届く入力' '' $script:KcHtLaneCaption)
    $outLane = @{}
    $runs = Get-KcHtOutputRuns $result.Hid $end
    foreach ($run in $runs) {
        $outLane[$run.Key] = Add-KcHtLane $chart $run.Title $run.Note $script:KcHtLaneOutput
        foreach ($it in $run.Items) { Add-KcHtBar $chart $outLane[$run.Key] $it.From $it.To $run.Style $run.Title }
    }
    $extra = @()
    if ($null -ne $View.Base) { $extra += @{ Hid = $View.Base.Hid; Style = $script:KcHtBarBaseline; Note = 'キーマップの値' } }
    if ($null -ne $View.Firmware) { $extra += @{ Hid = (ConvertTo-KcHtHidFromLog $View.Firmware.Hid); Style = $script:KcHtBarFirmware; Note = 'ファーム' } }
    foreach ($x in $extra) {
        foreach ($run in (Get-KcHtOutputRuns $x.Hid $end)) {
            if (-not $outLane.ContainsKey($run.Key)) {
                $outLane[$run.Key] = Add-KcHtLane $chart $run.Title ('{0}だけ' -f $x.Note) $script:KcHtLaneOutput
            }
            foreach ($it in $run.Items) { Add-KcHtBar $chart $outLane[$run.Key] $it.From $it.To $x.Style $x.Note }
        }
    }
    $lastOutLane = $chart.Lanes.Count - 1
    # 判定まで保留されたキー: 押した時刻 → 送られた時刻
    for ($i = 0; $i -lt $result.Inputs.Count; $i++) {
        $in = $result.Inputs[$i]
        if (-not $in.Captured -or -not $in.Down -or $in.ReplayAt -le $in.At) { continue }
        $toLane = $keyLane[[int]$in.Pos]
        foreach ($o in $result.Hid) {
            if ($o.Pos -eq $in.Pos -and $o.Down -and $o.T -eq $in.ReplayAt) {
                $k = 'key:{0}' -f $o.Usage
                if ($o.Kind -eq 'layer') { $k = 'layer:{0}' -f $o.Layer }
                if ($outLane.ContainsKey($k)) { $toLane = $outLane[$k] }
                break
            }
        }
        $chart.Arrows.Add(@{ FromLane = $keyLane[[int]$in.Pos]; FromAt = [double]$in.At; ToLane = $toLane; ToAt = [double]$in.ReplayAt; Style = $script:KcHtArrowCapture })
    }
    # 判定の時刻、tapping-term、ファーム / キーマップの値の判定
    $d = [KcHtText]::DecisionFor($result, $View.TargetIndex)
    $termName = 'tapping-term'
    if ($isQmk) { $termName = 'TAPPING_TERM' }
    Add-KcHtMark $chart $firstKeyLane $lastOutLane ([double]($pressT + $term)) $script:KcHtMarkTerm ('{0} {1} ms' -f $termName, $term) $script:KcHtHandleTerm
    if ($null -ne $d) {
        Add-KcHtMark $chart $firstKeyLane $lastOutLane ([double]$d.DecideT) $script:KcHtMarkDecision ('{0}に決定' -f (Format-KcHtStatus $model.Engine $d.Status))
    }
    if ($null -ne $View.Base) {
        $bd = [KcHtText]::DecisionFor($View.Base, $View.TargetIndex)
        if ($null -ne $bd -and ($null -eq $d -or $bd.DecideT -ne $d.DecideT -or $bd.Status -ne $d.Status)) {
            Add-KcHtMark $chart $firstKeyLane $lastOutLane ([double]$bd.DecideT) $script:KcHtMarkBaseline ('キーマップの値: {0}' -f (Format-KcHtStatus $model.Engine $bd.Status))
        }
    }
    if ($null -ne $View.Firmware) {
        foreach ($fd in @($View.Firmware.Decisions)) {
            if ($fd.Pos -ne $events[$View.TargetIndex].Pos) { continue }
            Add-KcHtMark $chart $firstKeyLane $lastOutLane ([double]$fd.T) $script:KcHtMarkFirmware ('ファーム: {0}' -f (Format-KcHtStatus 'zmk' $fd.Status))
            break
        }
    }

    # ---- 帯
    $sw = $View.Sweeps
    if ($null -ne $sw) {
        $sel = $View.Selected
        $selName = $termName
        if ($sel -ge 0 -and $sel -lt $events.Count) { $selName = Format-KcHtEventName $model $events[$sel] }
        $toBars = {
            param($Lane, $Segs, [bool]$IsTerm)
            foreach ($s in @($Segs)) {
                $style = $script:KcHtBarStripNone
                $cls = Get-KcHtStatusClass $s.Status
                if ($cls -eq 'tap') { $style = $script:KcHtBarStripTap } elseif ($cls -eq 'hold') { $style = $script:KcHtBarStripHold }
                $text = $s.Text
                if (-not $text) { $text = '-' }
                $from = [double]$s.From
                $to = [double]$s.To + 1
                if ($IsTerm) {
                    $from += $pressT
                    $to += $pressT
                }
                Add-KcHtBar $chart $Lane $from $to $style $text
            }
        }
        $isTerm = ($sel -eq $script:KcHtHandleTerm)
        $cursor = [double]($pressT + $term)
        if (-not $isTerm -and $sel -ge 0 -and $sel -lt $events.Count) { $cursor = [double]$events[$sel].T }
        if ($null -ne $sw.Handle) {
            [void](Add-KcHtLane $chart ('「{0}」の時刻を変えると' -f $selName) '' $script:KcHtLaneCaption)
            $lane = Add-KcHtLane $chart '今の設定' (Format-KcHtSegments $model $sw.Handle) $script:KcHtLaneStrip
            & $toBars $lane $sw.Handle $isTerm
            Add-KcHtMark $chart $lane $lane $cursor $script:KcHtMarkCursor ''
        }
        if ($null -ne $sw.Compare -and @($sw.Compare).Count -gt 0) {
            $cap = 'flavor ごとの比較 (行を押すとその flavor にする)'
            if ($isQmk) { $cap = '設定ごとの比較 (行を押すとその設定にする)' }
            $first = Add-KcHtLane $chart $cap '' $script:KcHtLaneCaption
            foreach ($c in @($sw.Compare)) {
                $note = ''
                if ($c.Current) { $note = '今の設定' }
                $lane = Add-KcHtLane $chart $c.Label $note $script:KcHtLaneStrip $c.Action
                & $toBars $lane $c.Segments $isTerm
            }
            Add-KcHtMark $chart ($first + 1) ($chart.Lanes.Count - 1) $cursor $script:KcHtMarkCursor ''
        }
        if ($null -ne $sw.Term -and -not $isTerm) {
            [void](Add-KcHtLane $chart ('{0} を変えると (線の位置 = 押した時刻 + {0})' -f $termName) '' $script:KcHtLaneCaption)
            $lane = Add-KcHtLane $chart '今の設定' (Format-KcHtSegments $model $sw.Term) $script:KcHtLaneStrip
            & $toBars $lane $sw.Term $true
            Add-KcHtMark $chart $lane $lane ([double]($pressT + $term)) $script:KcHtMarkCursor ''
        }
    }

    # ---- 動かせるもの
    for ($i = 0; $i -lt $events.Count; $i++) {
        $lim = Get-KcHtHandleLimits $events $i
        $chart.Handles.Add(@{ Id = $i; Min = [double][Math]::Max($lim.Min, $chart.From); Max = [double][Math]::Min($lim.Max, $chart.To); Tip = (Format-KcHtEventName $model $events[$i]) })
    }
    $chart.Handles.Add(@{ Id = $script:KcHtHandleTerm; Min = [double]($pressT + 50); Max = [double]([Math]::Min($pressT + 500, $chart.To)); Tip = $termName })
    $chart.Selected = $View.Selected
    return $chart
}

# ---------------------------------------------------------------------------
# ログ版ファームのログから、実際に押したもの (エピソード) を切り出す
# ---------------------------------------------------------------------------

# $Rec は zmk-log.ps1 の ConvertFrom-KcZmkLogLine のレコード
function New-KcHtCapture($Model) {
    return @{
        Model = $Model; Held = @{}; Recent = (New-Object 'System.Collections.Generic.List[object]'); Ep = $null; Seq = 0
        Undecided = 0; LastTime = [double]0
    }
}

function Test-KcHtCaptureIdle($State) {
    return ($State.Held.Count -eq 0 -and $State.Undecided -le 0)
}

# 1 行ぶん進める。終わったエピソードがあれば返す ($null = なし)
function Update-KcHtCapture($State, $Rec) {
    if ($null -eq $Rec) { return $null }
    $done = $null
    if ($Rec.Type -eq 'dropped') {
        if ($null -ne $State.Ep) { $State.Ep.Dropped = $true }
        return $null
    }
    if ($Rec.Time -ge 0) { $State.LastTime = [double]$Rec.Time }
    $ep = $State.Ep
    switch ($Rec.Type) {
        'position' {
            $pos = [int]$Rec.Pos
            if ($null -ne $ep -and (Test-KcHtCaptureIdle $State) -and $Rec.Time - $ep.LastT -gt 50) {
                $done = Complete-KcHtCapture $State
                $ep = $null
            }
            $down = $Rec.Pressed
            $uncertain = $false
            if ($null -eq $down) {
                # ペリフェラル (左手側) のキーは押す / 離すが出ないので、交互に数える
                $down = -not $State.Held.ContainsKey($pos)
                $uncertain = $true
            }
            if ($down) { $State.Held[$pos] = $true } else { $State.Held.Remove($pos) }
            $e = @{ Pos = $pos; Down = [bool]$down; T = [double]$Rec.Time; Uncertain = $uncertain }
            $State.Recent.Add($e)
            while ($State.Recent.Count -gt 40) { $State.Recent.RemoveAt(0) }
            if ($null -ne $ep) {
                $ep.Events.Add($e)
                $ep.LastT = [double]$Rec.Time
                if ($uncertain) { $ep.Uncertain = $true }
            }
        }
        'ht_new' {
            $pos = [int]$Rec.Pos
            $State.Undecided++
            # 押したことの確かめ (ペリフェラルを交互に数えてずれていたら直す)
            $last = $null
            for ($i = $State.Recent.Count - 1; $i -ge 0; $i--) {
                if ($State.Recent[$i].Pos -eq $pos) { $last = $State.Recent[$i]; break }
            }
            if ($null -ne $last -and -not $last.Down) {
                $last.Down = $true
                $State.Held[$pos] = $true
            }
            if ($null -eq $ep -and $null -ne $last) {
                $State.Seq++
                $ep = @{
                    Seq = $State.Seq; Target = $pos; Start = [double]$last.T; LastT = [double]$Rec.Time
                    Events = (New-Object 'System.Collections.Generic.List[object]')
                    Decisions = (New-Object 'System.Collections.Generic.List[object]')
                    Hid = (New-Object 'System.Collections.Generic.List[object]')
                    Dropped = $false; Uncertain = $false
                }
                # 直前の入力 (require-prior-idle / quick-tap のため) と、押したままのキー
                foreach ($r in $State.Recent) {
                    if ($r.T -ge $last.T - 1000) {
                        $ep.Events.Add($r)
                        if ($r.Uncertain) { $ep.Uncertain = $true }
                    }
                }
                $State.Ep = $ep
            }
        }
        'ht_decided' {
            $State.Undecided--
            if ($null -ne $ep) {
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
    return $done
}

# 今のエピソードを終える (判定待ちが無く、すべて離したとき)。終えたエピソード、無ければ $null
function Complete-KcHtCapture($State, [switch]$Force) {
    $ep = $State.Ep
    if ($null -eq $ep) { return $null }
    if (-not $Force -and -not (Test-KcHtCaptureIdle $State)) { return $null }
    $State.Ep = $null
    $State.Undecided = [Math]::Max(0, $State.Undecided)
    $t0 = [Math]::Floor($ep.Start)
    $events = New-Object 'System.Collections.Generic.List[object]'
    $targetIndex = -1
    foreach ($e in $ep.Events) {
        $t = [long]([Math]::Floor($e.T) - $t0)
        if ($targetIndex -lt 0 -and $e.Pos -eq $ep.Target -and $e.Down -and $t -eq 0) { $targetIndex = $events.Count }
        $role = 'partner'
        if ($e.Pos -eq $ep.Target) { $role = 'target' } elseif ($t -lt 0) { $role = 'prior' }
        $events.Add(@{ Pos = [int]$e.Pos; Down = [bool]$e.Down; T = $t; Role = $role })
    }
    if ($targetIndex -lt 0) { $targetIndex = 0 }
    $decisions = @($ep.Decisions | ForEach-Object { @{ Pos = $_.Pos; Status = $_.Status; Moment = $_.Moment; Flavor = $_.Flavor; T = [double]([Math]::Floor($_.T) - $t0) } })
    $hid = @($ep.Hid | ForEach-Object { @{ T = [double]([Math]::Floor($_.T) - $t0); Usage = $_.Usage; Pressed = $_.Pressed } })
    return @{
        Seq = $ep.Seq; Target = $ep.Target; Start = $ep.Start; Events = $events.ToArray(); TargetIndex = $targetIndex
        Decisions = $decisions; Hid = $hid; Dropped = $ep.Dropped; Uncertain = $ep.Uncertain
    }
}

# エピソードの一覧の 1 行: 「12:34:56  A (Ctrl) + J → ホールド (ほかのキー)」
function Format-KcHtEpisode($Model, $Episode) {
    $ts = [TimeSpan]::FromMilliseconds([Math]::Max(0, $Episode.Start))
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($e in $Episode.Events) {
        if ($e.Down -and $e.T -ge 0) {
            $n = Get-KcHtKeyName $Model $e.Pos
            if (-not $keys.Contains($n)) { $keys.Add($n) }
        }
    }
    $status = '判定なし'
    foreach ($d in @($Episode.Decisions)) {
        if ($d.Pos -eq $Episode.Target) { $status = Format-KcHtStatus 'zmk' $d.Status; break }
    }
    $flags = ''
    if ($Episode.Dropped) { $flags += ' (ログ欠け)' }
    return ('{0:00}:{1:00}:{2:00}  {3} → {4}{5}' -f [int][Math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds, ($keys -join ' + '), $status, $flags)
}

# ファームの判定と、キーマップの値での計算を比べる → @{ Level (1 一致 / 3 境目 / 2 違う / 0 比べない); Text }
function Compare-KcHtFirmware($Model, $Episode) {
    if ($Episode.Dropped) { return @{ Level = 0; Text = 'ログが欠けたので比べません' } }
    $fd = $null
    foreach ($d in @($Episode.Decisions)) {
        if ($d.Pos -eq $Episode.Target) { $fd = $d; break }
    }
    if ($null -eq $fd) { return @{ Level = 0; Text = 'ファームの判定がログにありません' } }
    $km = Get-KcHtKeymapWith $Model (New-KcHtConfig $Model)
    $r = Invoke-KcHtRun $Model $km $Episode.Events
    $sd = [KcHtText]::DecisionFor($r, $Episode.TargetIndex)
    if ($null -ne $sd -and $sd.Status -eq $fd.Status) {
        return @{ Level = 1; Text = ('ファームの判定 ({0}) と、キーマップの値での計算が同じ' -f (Format-KcHtStatus 'zmk' $fd.Status)) }
    }
    $simText = '判定なし'
    if ($null -ne $sd) { $simText = Format-KcHtStatus 'zmk' $sd.Status }
    # 境目 (どれかの入力を ±2ms 動かすと、ファームと同じになる) なら、実機のずれの範囲
    $inputs = ConvertTo-KcHtInputs $Episode.Events
    for ($i = 0; $i -lt $Episode.Events.Count; $i++) {
        $t = [long]$Episode.Events[$i].T
        $segs = @([KcHtSweep]::VaryInput($Model.Engine, $km, $inputs, $i, $t - 2, $t + 2, $Episode.TargetIndex))
        foreach ($s in $segs) {
            if ($s.Status -eq $fd.Status) {
                return @{ Level = 3; Text = ('ファームは {0}、計算は {1} (境目の ±2ms 以内なので、実機のずれの範囲)' -f (Format-KcHtStatus 'zmk' $fd.Status), $simText) }
            }
        }
    }
    return @{ Level = 2; Text = ('ファームは {0}、計算は {1} (違う)。ファームのキーマップが期待値と違うか、左手側のキーの押す / 離すを数え違えた可能性' -f (Format-KcHtStatus 'zmk' $fd.Status), $simText) }
}
