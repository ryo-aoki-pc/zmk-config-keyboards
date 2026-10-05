# 自動テスト用シミュレータ。実機への入力・通信は行わない。

$script:KcSimRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:KcSimModels = @{}
. (Join-Path $PSScriptRoot 'hold-tap-sim.ps1')

function Get-KcSimProperty($Object, [string]$Name, $Default = $null) {
    if ($null -ne $Object) {
        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($Name)) { return ,($Object[$Name]) }
        } else {
            $property = $Object.PSObject.Properties[$Name]
            if ($null -ne $property) { return ,($property.Value) }
        }
    }
    return ,$Default
}

function Test-KcSimProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-KcSimInteger($Value, [string]$Name, [long]$Minimum = 0) {
    if ($null -eq $Value -or ($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Minimum) {
        throw ('{0} は {1} 以上の整数で指定してください' -f $Name, $Minimum)
    }
}

function ConvertTo-KcSimObject($Value, [type]$Type) {
    if ($Type -eq [KcHtBinding] -and -not (Test-KcSimProperty $Value 'kind')) { throw 'バインディングの kind が必要です' }
    $result = [System.Activator]::CreateInstance($Type)
    foreach ($field in $Type.GetFields()) {
        $valueName = $field.Name
        if (-not (Test-KcSimProperty $Value $valueName)) {
            $snake = [regex]::Replace($field.Name, '([a-z0-9])([A-Z])', '$1_$2').ToLowerInvariant()
            $valueName = $snake
            if ($Type -eq [KcHtZmkConfig]) {
                $aliases = @{ Term = 'tapping_term_ms'; QuickTap = 'quick_tap_ms'; PriorIdle = 'require_prior_idle_ms'; Hwu = 'hold_while_undecided'; HwuLinger = 'hold_while_undecided_linger'; TriggerOnRelease = 'hold_trigger_on_release'; TriggerPositions = 'hold_trigger_key_positions' }
                if ($aliases.ContainsKey($field.Name)) { $valueName = $aliases[$field.Name] }
            }
            if (-not (Test-KcSimProperty $Value $valueName)) { continue }
        }
        $v = Get-KcSimProperty $Value $valueName
        if ($null -eq $v) { continue }
        $ft = $field.FieldType
        if ($ft.IsArray) {
            $et = $ft.GetElementType()
            $values = @($v)
            $array = [System.Array]::CreateInstance($et, $values.Count)
            for ($j = 0; $j -lt $values.Count; $j++) {
                if ($et.IsPrimitive -or $et -eq [string]) {
                    $item = [System.Convert]::ChangeType($values[$j], $et, [System.Globalization.CultureInfo]::InvariantCulture)
                } else { $item = ConvertTo-KcSimObject $values[$j] $et }
                $array.SetValue($item, $j)
            }
            $field.SetValue($result, $array)
        } elseif ($ft.IsPrimitive -or $ft -eq [string]) {
            $field.SetValue($result, [System.Convert]::ChangeType($v, $ft, [System.Globalization.CultureInfo]::InvariantCulture))
        } else {
            $field.SetValue($result, (ConvertTo-KcSimObject $v $ft))
        }
    }
    return $result
}

function Get-KcSimModel([string]$Board, [string]$Python = 'python') {
    if ($Board -notin @('lism', 'kukey42', 'aroundfortyrb', 'pyuron', 'roba', 'torabo-tsuki-lp', 'keyball39', 'kq-mini')) {
        throw ('未対応の機種: {0}' -f $Board)
    }
    if (-not $script:KcSimModels.ContainsKey($Board)) {
        $exporter = Join-Path $script:KcSimRoot 'tools/simulator/export_model.py'
        $lines = & $Python $exporter --keyboard $Board
        if ($LASTEXITCODE -ne 0) { throw ('機種設定の読み込みに失敗しました: {0}' -f $Board) }
        $script:KcSimModels[$Board] = ($lines -join "`n") | ConvertFrom-Json
    }
    return $script:KcSimModels[$Board]
}

function ConvertTo-KcSimKeymap($Model) {
    Import-KcHoldTapSim
    Assert-KcSimInteger (Get-KcSimProperty $Model 'schema_version') 'schema_version'
    if ((Get-KcSimProperty $Model 'schema_version') -ne 1) { throw '機種設定の schema_version は 1 が必要です' }
    $map = New-Object KcHtKeymap
    $required = Get-KcSimProperty $Model 'requires' @()
    foreach ($feature in $required) {
        if ($feature -ne 'qmk_key_override' -or $null -eq $map.PSObject.Properties['Overrides']) { throw ('未対応の必須機能: {0}' -f $feature) }
    }
    $zmkSettings = Get-KcSimProperty $Model 'zmk_settings'
    if ($null -ne $zmkSettings) { $map.SeparateModRelease = [bool](Get-KcSimProperty $zmkSettings 'separate_mod_release_report' $false) }
    $overrides = Get-KcSimProperty $Model 'qmk_overrides' @()
    if ($overrides.Count -gt 0) {
        $overrideField = $map.GetType().GetField('Overrides')
        if ($null -eq $overrideField) { throw 'QMK キーオーバーライドの実行エンジンがありません' }
        $elementType = $overrideField.FieldType.GetElementType()
        $rules = [System.Array]::CreateInstance($elementType, $overrides.Count)
        for ($i = 0; $i -lt $overrides.Count; $i++) { $rules.SetValue((ConvertTo-KcSimObject $overrides[$i] $elementType), $i) }
        $overrideField.SetValue($map, $rules)
    }
    foreach ($key in @($Model.keys)) {
        if (-not (Get-KcSimProperty $key 'present' $true)) { continue }
        Assert-KcSimInteger $key.pos 'keys.pos'
        foreach ($layer in $key.on.PSObject.Properties) {
            $map.Set([int]$key.pos, [int]$layer.Name, (ConvertTo-KcSimObject $layer.Value ([KcHtBinding])))
        }
        $hand = [string](Get-KcSimProperty $key 'qmk_hand' (Get-KcSimProperty $key 'hand' '*'))
        if (-not $hand) { $hand = '*' }
        $map.SetHand([int]$key.pos, [char]$hand.Substring(0, 1).ToUpperInvariant())
        if (Test-KcSimProperty $key 'usage') { $map.SetCell([int]$key.pos, [int]$key.usage) }
    }
    $behaviors = Get-KcSimProperty $Model 'behaviors'
    if ($null -ne $behaviors) {
        foreach ($behavior in $behaviors.PSObject.Properties) {
            $map.SetBehavior($behavior.Name, (ConvertTo-KcSimObject $behavior.Value ([KcHtZmkConfig])))
        }
    }
    $settings = Get-KcSimProperty $Model 'settings'
    if ($null -ne $settings) { $map.Qmk = ConvertTo-KcSimObject $settings ([KcHtQmkSettings]) }
    return $map
}

function ConvertTo-KcSimActual($Result) {
    $keys = New-Object 'System.Collections.Generic.List[object]'
    $layers = New-Object 'System.Collections.Generic.List[object]'
    $mouse = New-Object 'System.Collections.Generic.List[object]'
    $down = @{}
    $active = @{ 0 = $true }
    $buttons = 0
    foreach ($o in $Result.Hid) {
        if ($o.Kind -eq 'key') {
            $keys.Add([ordered]@{ t = $o.T; usage = $o.Usage; down = $o.Down; mods = $o.Mods })
            if ($o.Down) { $down[$o.Usage] = $true } else { $down.Remove($o.Usage) }
        } elseif ($o.Kind -eq 'layer') {
            $layers.Add([ordered]@{ t = $o.T; layer = $o.Layer; down = $o.Down })
            if ($o.Down) { $active[$o.Layer] = $true } else { $active.Remove($o.Layer) }
        } elseif ($o.Kind -eq 'mouse') {
            $mouse.Add([ordered]@{ t = $o.T; x = $o.X; y = $o.Y; wheel = $o.Wheel; hwheel = $o.HWheel; buttons = $o.Buttons })
            $buttons = $o.Buttons
        } else { throw ('未対応の出力を検出しました: {0}' -f $o.Kind) }
    }
    if ($Result.Approx) { throw '近似処理を含むため自動テストに合格できません' }
    return [ordered]@{
        keys = $keys.ToArray(); layers = $layers.ToArray(); mouse = $mouse.ToArray()
        state = [ordered]@{ layers = @($active.Keys | Sort-Object); keys = @($down.Keys | Sort-Object); buttons = $buttons }
    }
}

function Assert-KcSimExpected($Expected, $Actual, [string]$Path = 'expect') {
    if ($null -eq $Expected) { throw ('{0} がありません' -f $Path) }
    $properties = @($Expected.PSObject.Properties)
    if ($Expected -is [System.Collections.IDictionary]) {
        $properties = @($Expected.get_Keys() | ForEach-Object { [pscustomobject]@{ Name = $_; Value = $Expected[$_] } })
    }
    if ($properties.Count -eq 0) { throw ('{0} は空にできません' -f $Path) }
    foreach ($prop in $properties) {
        $name = [string]$prop.Name
        $actualNames = @($Actual.PSObject.Properties.Name)
        if ($Actual -is [System.Collections.IDictionary]) { $actualNames = @($Actual.get_Keys()) }
        if ($actualNames -cnotcontains $name) { throw ('未知の検証項目: {0}.{1}' -f $Path, $name) }
        $expectedValue = $prop.Value
        $actualValue = Get-KcSimProperty $Actual $name
        if ($actualValue -is [array] -and $expectedValue -isnot [array]) { throw ('{0}.{1} は配列で指定してください' -f $Path, $name) }
        if ($expectedValue -is [array] -and $actualValue -isnot [array]) { throw ('{0}.{1} は配列ではありません' -f $Path, $name) }
        if ($expectedValue -is [array]) {
            $a = @($actualValue)
            if ($expectedValue.Count -ne $a.Count) { throw ('{0}.{1}: 期待 {2} 件、実際 {3} 件' -f $Path, $name, $expectedValue.Count, $a.Count) }
            for ($i = 0; $i -lt $a.Count; $i++) {
                $p = '{0}.{1}[{2}]' -f $Path, $name, $i
                if ($expectedValue[$i] -is [pscustomobject] -or $expectedValue[$i] -is [System.Collections.IDictionary]) {
                    Assert-KcSimExpected $expectedValue[$i] $a[$i] $p
                } else { Assert-KcSimScalar $expectedValue[$i] $a[$i] $p }
            }
        } elseif ($expectedValue -is [pscustomobject] -or $expectedValue -is [System.Collections.IDictionary]) {
            Assert-KcSimExpected $expectedValue $actualValue ($Path + '.' + $name)
        } else { Assert-KcSimScalar $expectedValue $actualValue ($Path + '.' + $name) }
    }
}

function Invoke-KcSimScenario {
    param([Parameter(Mandatory = $true)] $Scenario, [string]$Python = 'python')
    $name = [string](Get-KcSimProperty $Scenario 'name' '')
    $board = [string](Get-KcSimProperty $Scenario 'board' 'inline')
    $entry = [ordered]@{ name = $name; board = $board; status = 'failed'; error = ''; sources = @(); decisions = @(); actual = $null }
    try {
        if (-not $name.Trim()) { throw 'シナリオ名が必要です' }
        $model = Get-KcSimProperty $Scenario 'model'
        if ($null -eq $model) {
            $sourceBoard = $board
            if ($board -eq 'keyball-kq-mini') { $sourceBoard = 'keyball39' }
            $model = Get-KcSimModel $sourceBoard $Python
        } elseif ($board -eq 'keyball-kq-mini') { throw '連携テストに inline model は指定できません' }
        $entry.sources = (Get-KcSimProperty $model 'sources' @())
        $map = ConvertTo-KcSimKeymap $model
        $engine = [string]$model.engine
        if ($engine -notin @('zmk', 'qmk')) { throw ('未対応のエンジン: {0}' -f $engine) }
        $events = Get-KcSimProperty $Scenario 'events'
        if ($events -isnot [array] -or $events.Count -eq 0) { throw 'events に 1 件以上の入力が必要です' }
        Assert-KcSimInteger $Scenario.end_ms 'end_ms'
        $pressed = @{}
        $keys = New-Object 'System.Collections.Generic.List[KcHtInput]'
        $auxiliary = New-Object 'System.Collections.Generic.List[KcSimEvent]'
        $last = -1L
        foreach ($event in $events) {
            Assert-KcSimInteger $event.t 'events.t'
            if ($event.t -lt $last -or $event.t -gt $Scenario.end_ms) { throw '入力時刻は昇順で end_ms 以下にしてください' }
            $last = [long]$event.t
            $kind = [string](Get-KcSimProperty $event 'type' '')
            if ($kind -in @('press', 'release')) {
                Assert-KcSimInteger $event.pos 'events.pos'
                $pos = [int]$event.pos
                if (-not $map.Keys.ContainsKey($pos)) { throw ('存在しないキー位置: {0}' -f $pos) }
                $isDown = $kind -eq 'press'
                if ($isDown -eq $pressed.ContainsKey($pos)) { throw ('キー位置 {0} の押下・解放が対応していません' -f $pos) }
                if ($isDown) { $pressed[$pos] = $true } else { $pressed.Remove($pos) }
                $keys.Add([KcHtInput]::Make($pos, $isDown, [long]$event.t))
            } elseif ($kind -eq 'move') {
                Assert-KcSimInteger $event.x 'events.x' ([int]::MinValue)
                Assert-KcSimInteger $event.y 'events.y' ([int]::MinValue)
                $aux = New-Object KcSimEvent
                $aux.T = $event.t; $aux.Kind = 'move'; $aux.X = $event.x; $aux.Y = $event.y
                $aux.Side = [string](Get-KcSimProperty $event 'side' 'right')
                $auxiliary.Add($aux)
            } elseif ($kind -ne 'advance') { throw ('未知の入力: {0}' -f $kind) }
        }
        $peripheral = New-KcSimPeripheral $model
        $result = [KcKeyboardSim]::Run($engine, $map, $keys.ToArray(), $auxiliary.ToArray(), [long]$Scenario.end_ms, $true, $peripheral)
        if ($board -eq 'keyball-kq-mini') {
            $upstream = ConvertTo-KcSimActual $result
            $downstreamModel = Get-KcSimModel 'kq-mini' $Python
            $downstreamMap = ConvertTo-KcSimKeymap $downstreamModel
            if ($upstream.mouse.Count -gt 0 -and -not (Get-KcSimProperty $downstreamModel 'mouse_passthrough_verified' $false)) {
                throw 'KQ-mini のマウス割り当て変更・ジェスチャーには対応していません'
            }
            $entry.sources += (Get-KcSimProperty $downstreamModel 'sources' @())
            $forwarded = New-Object 'System.Collections.Generic.List[KcHtInput]'
            $lastButtons = 0
            $hasKeyboard = $false
            $hasWheel = $false
            foreach ($o in $result.Hid) {
                if ($o.Kind -eq 'key' -and $o.Usage -gt 0) {
                    $hasKeyboard = $true
                    $forwarded.Add([KcHtInput]::Make($o.Usage, $o.Down, $o.T))
                } elseif ($o.Kind -eq 'mouse') {
                    if ($o.Wheel -ne 0 -or $o.HWheel -ne 0) { $hasWheel = $true }
                    # quantizer_mouse.c はボタンを 0xD1..0xD8 の行列に入れる。
                    # これを省くと、クリックでの permissive hold の確定を見落とす。
                    for ($bit = 0; $bit -lt 8; $bit++) {
                        $mask = 1 -shl $bit
                        if (($lastButtons -band $mask) -ne ($o.Buttons -band $mask)) {
                            $forwarded.Add([KcHtInput]::Make(209 + $bit, (($o.Buttons -band $mask) -ne 0), $o.T))
                        }
                    }
                    $lastButtons = $o.Buttons
                }
            }
            if ($hasKeyboard -and $hasWheel) { throw 'KQ-mini 連携のホイールとキーの混在には対応していません' }
            $downstream = [KcKeyboardSim]::Run('qmk', $downstreamMap, $forwarded.ToArray(), [KcSimEvent[]]@(), [long]$Scenario.end_ms, $true)
            $entry.actual = ConvertTo-KcSimActual $downstream
            $entry.actual.mouse = Merge-KcSimChainMouse $upstream.mouse $entry.actual.mouse
            # 最終ボタン状態は KQ の処理結果 (保留中の hold-tap も含む) を使う。
            $entry.actual['upstream'] = $upstream
            $entry.decisions = @($downstream.Decisions.ToArray())
        } else {
            $entry.actual = ConvertTo-KcSimActual $result
            $entry.decisions = @($result.Decisions.ToArray())
        }
        Assert-KcSimExpected $Scenario.expect $entry.actual
        $entry.status = 'passed'
    } catch { $entry.error = $_.Exception.Message }
    return [pscustomobject]$entry
}

function New-KcSimPeripheral($Model) {
    $pointer = Get-KcSimProperty $Model 'pointer'
    if ($null -eq $pointer) { return $null }
    if ((Get-KcSimProperty $pointer 'transport' 'usb') -ne 'usb') { throw 'USB の論理出力だけに対応しています' }
    $listeners = @($pointer.listeners)
    if ($listeners.Count -eq 0) { throw 'ポインターのリスナーがありません' }
    $peripheral = $null
    foreach ($listener in $listeners) {
        $cfg = ConvertTo-KcSimObject $pointer ([KcPointerConfig])
        $cfg = Set-KcSimPointerListener $cfg $listener
        if ($null -eq $peripheral) { $peripheral = New-Object KcPointerPeripheral($cfg, [int]$pointer.aml_layer, [int]$pointer.scroll_layer) }
        $peripheral.AddSide([string]$listener.side, $cfg)
    }
    return $peripheral
}

function Set-KcSimPointerListener($Config, $Listener) {
    $xy = (Get-KcSimProperty $Listener 'xy_scaler' @(1, 1))
    if ($xy[0] -ne 1 -or $xy[1] -ne 1) { throw '追加の XY 一括倍率には対応していません' }
    $Config.Transform = [int](Get-KcSimProperty $Listener 'transform' 0)
    $Config.ScrollTransform = [int](Get-KcSimProperty $Listener 'scroll_transform' 0)
    $Config.XNumerator = $Listener.x_scaler[0]; $Config.XDenominator = $Listener.x_scaler[1]
    $Config.YNumerator = $Listener.y_scaler[0]; $Config.YDenominator = $Listener.y_scaler[1]
    $Config.ScrollNumerator = $Listener.scroll_scaler[0]; $Config.ScrollDenominator = $Listener.scroll_scaler[1]
    $Config.ScrollXSign = [int](Get-KcSimProperty $Listener 'scroll_x_sign' 1)
    $Config.ScrollYSign = [int](Get-KcSimProperty $Listener 'scroll_y_sign' 1)
    $Config.ScrollSupported = [bool](Get-KcSimProperty $Listener 'scroll_supported' $true)
    $Config.ReportIntervalMs = [int](Get-KcSimProperty $Listener 'report_interval_ms' 8)
    $accel = Get-KcSimProperty $Listener 'accel'
    if ($null -ne $accel) {
        $Config.MinFactor = $accel.min_factor; $Config.MaxFactor = $accel.max_factor
        $Config.SpeedThreshold = $accel.speed_threshold; $Config.SpeedMax = $accel.speed_max
    } else { $Config.MinFactor = 1000; $Config.MaxFactor = 1000 }
    return $Config
}

function Assert-KcSimScalar($Expected, $Actual, [string]$Path) {
    $typeOK = $false
    if ($Actual -is [bool]) { $typeOK = $Expected -is [bool] }
    elseif ($Actual -is [int] -or $Actual -is [long]) { $typeOK = $Expected -is [int] -or $Expected -is [long] }
    elseif ($Actual -is [string]) { $typeOK = $Expected -is [string] }
    if (-not $typeOK -or $Expected -cne $Actual) { throw ('{0}: 期待 {1}、実際 {2} (値と型を比較)' -f $Path, $Expected, $Actual) }
}

function Merge-KcSimChainMouse($Upstream, $Downstream) {
    $merged = New-Object 'System.Collections.Generic.List[object]'
    $index = 0
    $buttons = 0
    $down = @($Downstream)
    foreach ($report in @($Upstream)) {
        while ($index -lt $down.Count -and $down[$index].t -lt $report.t) {
            $buttons = $down[$index].buttons
            $merged.Add($down[$index]); $index++
        }
        if ($report.x -ne 0 -or $report.y -ne 0 -or $report.wheel -ne 0 -or $report.hwheel -ne 0) {
            $merged.Add([ordered]@{ t = $report.t; x = $report.x; y = $report.y; wheel = $report.wheel; hwheel = $report.hwheel; buttons = $buttons })
        }
        while ($index -lt $down.Count -and $down[$index].t -eq $report.t) {
            $buttons = $down[$index].buttons
            $merged.Add($down[$index]); $index++
        }
    }
    while ($index -lt $down.Count) { $merged.Add($down[$index]); $index++ }
    return ,$merged.ToArray()
}
