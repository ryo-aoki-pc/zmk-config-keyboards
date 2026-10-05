# Key override vectors from the pinned process_key_override.c, vial.c and quantum.c.
# Expected events are fixed from those branches, not recorded simulator output.
. (Join-Path $script:KcLib 'hold-tap-sim.ps1')
Import-KcHoldTapSim

function New-KoBinding([int]$Usage) {
    $b = New-Object KcHtBinding
    $b.Kind = 'kp'; $b.Usage = $Usage; $b.Src = '0x{0:X4}' -f $Usage
    return $b
}
function New-KoRule {
    $r = New-Object KcSimOverrideRule
    $r.Trigger = '0x002A'; $r.Replacement = New-KoBinding 76
    $r.TriggerMods = 34; $r.SuppressedMods = 34; $r.Layers = 1
    return $r
}
function New-KoMap {
    $m = New-Object KcHtKeymap
    $m.Qmk.ChordalCompiled = $false; $m.Qmk.FlowCompiled = $false
    $m.Set(0, 0, (New-KoBinding 42)); $m.Set(1, 0, (New-KoBinding 225))
    $m.Set(2, 0, (New-KoBinding 5)); $m.Set(3, 0, (New-KoBinding 224))
    $m.Overrides = [KcSimOverrideRule[]]@((New-KoRule))
    return $m
}
function Invoke-Ko([KcHtKeymap]$Map, [object[]]$Rows, [long]$End = 1000) {
    $events = New-Object 'System.Collections.Generic.List[KcHtInput]'
    foreach ($row in $Rows) {
        $e = New-Object KcHtInput; $e.T = $row[0]; $e.Pos = $row[1]; $e.Down = [bool]$row[2]
        $events.Add($e)
    }
    return [KcKeyboardSim]::Run('qmk', $Map, $events.ToArray(), [KcSimEvent[]]@(), $End, $false)
}
function Get-KoKeys($Result) {
    return @($Result.Hid | Where-Object { $_.Kind -eq 'key' -and $_.Usage -lt 224 } | ForEach-Object {
        '{0}:{1}:{2}:{3}' -f $_.T, $_.Usage, ([int]$_.Down), $_.Mods
    })
}

Test-Case 'QMK override: either side satisfies an AND modifier family; one_mod switches to OR' {
    $r = New-KoRule; $r.TriggerMods = 51
    Assert-True ([KcQmkOverrideSim]::MatchesModifiers($r, 33))
    Assert-True (-not [KcQmkOverrideSim]::MatchesModifiers($r, 1))
    $r.Options = 143
    Assert-True ([KcQmkOverrideSim]::MatchesModifiers($r, 1))
    $r.NegativeModMask = 4
    Assert-True (-not [KcQmkOverrideSim]::MatchesModifiers($r, 5))
}

Test-Case 'QMK override: suppression and trigger release restore the held modifier' {
    $m = New-KoMap
    $r = Invoke-Ko $m @(@(0,1,1), @(10,0,1), @(20,0,0), @(30,1,0))
    Assert-Equal @('10:76:1:0', '20:76:0:2') (Get-KoKeys $r)
    Assert-Equal @('0:1', '10:0', '20:1', '30:0') @($r.Hid | Where-Object Usage -eq 225 | ForEach-Object { '{0}:{1}' -f $_.T, ([int]$_.Down) })
}

Test-Case 'QMK override: disabled and inactive-layer rules do not consume the trigger' {
    foreach ($mode in @('disabled', 'layer')) {
        $m = New-KoMap
        if ($mode -eq 'disabled') { $m.Overrides[0].Options = 7 } else { $m.Overrides[0].Layers = 4 }
        $r = Invoke-Ko $m @(@(0,1,1), @(10,0,1), @(20,0,0), @(30,1,0))
        Assert-Equal @('10:42:1:2', '20:42:0:2') (Get-KoKeys $r)
    }
}

Test-Case 'QMK override: a negative modifier prevents activation' {
    $m = New-KoMap; $m.Overrides[0].NegativeModMask = 17
    $r = Invoke-Ko $m @(@(0,3,1), @(10,1,1), @(20,0,1), @(30,0,0), @(40,1,0), @(50,3,0))
    Assert-Equal @('20:42:1:3', '30:42:0:3') (Get-KoKeys $r)
}

Test-Case 'QMK override: modifier activation waits until 500ms from original press' {
    $r = Invoke-Ko (New-KoMap) @(@(0,0,1), @(100,1,1), @(600,0,0), @(650,1,0))
    Assert-Equal @('0:42:1:0', '100:42:0:0', '500:76:1:0', '600:76:0:2') (Get-KoKeys $r)
}

Test-Case 'QMK override: a modifier after repeat delay defers for another 50ms' {
    $r = Invoke-Ko (New-KoMap) @(@(0,0,1), @(600,1,1), @(700,0,0), @(750,1,0))
    Assert-Equal @('0:42:1:0', '600:42:0:0', '650:76:1:0', '700:76:0:2') (Get-KoKeys $r)
}

Test-Case 'QMK override: trigger release before deadline cancels deferred registration' {
    $r = Invoke-Ko (New-KoMap) @(@(0,0,1), @(100,1,1), @(499,0,0), @(600,1,0))
    Assert-Equal @('0:42:1:0', '100:42:0:0') (Get-KoKeys $r)
}

Test-Case 'QMK override: modifier release defers restoration of a still-held trigger' {
    $r = Invoke-Ko (New-KoMap) @(@(0,1,1), @(10,0,1), @(100,1,0), @(600,0,0))
    Assert-Equal @('10:76:1:0', '100:76:0:2', '510:42:1:0', '600:42:0:0') (Get-KoKeys $r)
}

Test-Case 'QMK override: no_reregister_trigger leaves the trigger suppressed' {
    $m = New-KoMap; $m.Overrides[0].Options = 151
    $r = Invoke-Ko $m @(@(0,1,1), @(10,0,1), @(100,1,0), @(600,0,0))
    Assert-Equal @('10:76:1:0', '100:76:0:2') (Get-KoKeys $r)
}

Test-Case 'QMK override: list order chooses the first matching replacement' {
    $m = New-KoMap; $second = New-KoRule; $second.Replacement = New-KoBinding 75
    $m.Overrides = [KcSimOverrideRule[]]@($m.Overrides[0], $second)
    $r = Invoke-Ko $m @(@(0,1,1), @(10,0,1), @(20,0,0), @(30,1,0))
    Assert-Equal @('10:76:1:0', '20:76:0:2') (Get-KoKeys $r)
}

Test-Case 'QMK override: replacement implicit modifiers survive trigger suppression' {
    $m = New-KoMap; $m.Overrides[0].Replacement.Mods = 1
    $r = Invoke-Ko $m @(@(0,1,1), @(10,0,1), @(20,0,0), @(30,1,0))
    Assert-Equal @('10:76:1:1', '20:76:0:2') (Get-KoKeys $r)
}

Test-Case 'QMK override: macro replacement clears real trigger mods before running its own shift' {
    $m = New-KoMap
    $macro = New-Object KcHtBinding; $macro.Kind = 'qmacro'; $macro.Src = '0x7703'; $macro.TapMs = 0; $macro.WaitMs = 0
    $steps = @()
    foreach ($row in @(@('press',225), @('tap',77), @('release',225))) {
        $step = New-Object KcSimMacroStep; $step.Kind = $row[0]; $step.Binding = New-KoBinding $row[1]; $steps += $step
    }
    $macro.Steps = [KcSimMacroStep[]]$steps; $m.Overrides[0].Replacement = $macro
    $r = Invoke-Ko $m @(@(0,1,1), @(10,0,1), @(20,0,0), @(30,1,0))
    Assert-Equal @('10:77:1:2', '10:77:0:2') (Get-KoKeys $r)
    Assert-Equal @('0:1', '10:0', '10:1', '10:0') @($r.Hid | Where-Object Usage -eq 225 | ForEach-Object { '{0}:{1}' -f $_.T, ([int]$_.Down) })
}

Test-Case 'QMK override: configured tap code delay is a blocking firmware wait' {
    $m = New-KoMap; $m.Qmk.TapCodeDelay = 7
    $r = Invoke-Ko $m @(@(0,1,1), @(10,0,1), @(30,0,0), @(40,1,0))
    Assert-Equal @('17:76:1:0', '30:76:0:2') (Get-KoKeys $r)
}

Test-Case 'QMK override: trigger-only activation does not react to a later modifier' {
    $m = New-KoMap; $m.Overrides[0].Options = 129
    $r = Invoke-Ko $m @(@(0,0,1), @(100,1,1), @(600,0,0), @(650,1,0))
    Assert-Equal @('0:42:1:0', '600:42:0:2') (Get-KoKeys $r)
}

Test-Case 'QMK override: another key clears replacement unless keep-active option is set' {
    $m = New-KoMap
    $r = Invoke-Ko $m @(@(0,1,1), @(10,0,1), @(20,2,1), @(30,2,0), @(40,0,0), @(50,1,0))
    Assert-Equal @('10:76:1:0', '20:76:0:2', '20:5:1:2', '30:5:0:2') (Get-KoKeys $r)
    $m.Overrides[0].Options = 167
    $r = Invoke-Ko $m @(@(0,1,1), @(10,0,1), @(20,2,1), @(30,2,0), @(40,0,0), @(50,1,0))
    Assert-Equal @('10:76:1:0', '20:5:1:0', '30:5:0:0', '40:76:0:2') (Get-KoKeys $r)
}

Test-Case 'QMK override: deferred register_code16 also waits tap_code_delay' {
    $m = New-KoMap; $m.Qmk.TapCodeDelay = 7
    $r = Invoke-Ko $m @(@(0,0,1), @(100,1,1), @(600,0,0), @(650,1,0))
    Assert-Equal @('0:42:1:0', '100:42:0:0', '507:76:1:0', '600:76:0:2') (Get-KoKeys $r)
}

Test-Case 'QMK override: register_code16 narrows a custom trigger to uint8, as pinned QMK does' {
    $m = New-KoMap; $carrier = New-Object KcHtBinding; $carrier.Src = '0x7E05'
    $m.Set(0,0,$carrier); $m.Overrides[0].Trigger = '0x7E05'
    $r = Invoke-Ko $m @(@(0,1,1), @(10,0,1), @(100,1,0), @(600,0,0))
    # SAFE_RANGE=0x7e40 allows restoring QK_KB_5, but register_code(uint8_t)
    # receives only 0x05 (KC_B). A later custom-key release does not release B.
    Assert-Equal @('10:76:1:0', '100:76:0:2', '510:5:1:0') (Get-KoKeys $r)
}
