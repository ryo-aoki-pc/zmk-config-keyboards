# タップホールドのシミュレータ (hold-tap-sim.ps1 / hold-tap-qmk.ps1) と、タイミングのグラフの計算 (hold-tap.ps1) のテスト

. (Join-Path $script:KcLib 'hold-tap-sim.ps1')
. (Join-Path $script:TestsDir 'hold-tap-vectors-zmk.ps1')
. (Join-Path $script:TestsDir 'hold-tap-vectors-qmk.ps1')

# 'p0@0 r0@10' → @(@{ Pos = 0; Down = $true; T = 0 }, ...)
function ConvertTo-HtEvents([string]$Text) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($tok in ($Text -split '\s+')) {
        if (-not $tok) { continue }
        if ($tok -notmatch '^([pr])(\d+)@(-?\d+)$') { throw "入力の書き方が違います: $tok" }
        $out.Add(@{ Pos = [int]$Matches[2]; Down = ($Matches[1] -eq 'p'); T = [long]$Matches[3] })
    }
    return , $out.ToArray()
}

# 位置ごとのバインディングの並び (レイヤー 0 だけ) → シミュレータのキーマップ
function New-HtTestKeymap($Keys, $Behaviors) {
    $map = @{}
    for ($i = 0; $i -lt @($Keys).Count; $i++) {
        $map[$i] = @{ 0 = @($Keys)[$i] }
    }
    return @{ Keys = $map; Behaviors = $Behaviors }
}

Test-Case 'ZMK: app/tests/hold-tap の全件で、ZMK と同じログの行を出す' {
    $prefixes = @('kp_', 'mo_', 'ht_binding_', 'ht_decide')
    $bad = New-Object 'System.Collections.Generic.List[string]'
    foreach ($v in $script:KcHtZmkVectors) {
        $km = New-HtTestKeymap $v.Keys $v.Behaviors
        $r = Invoke-KcZmkHoldTap -Keymap $km -Events (ConvertTo-HtEvents $v.Events) -TickMs 10 -Trace
        $allow = $prefixes
        if ($v.Retro) { $allow = $prefixes + @('decide_retro_tap', 'update_hold_status_for_retro_tap') }
        $got = @($r.Lines | Where-Object {
                $line = $_
                @($allow | Where-Object { $line.StartsWith($_) }).Count -gt 0
            })
        $want = @($v.Expect)
        if (($got -join "`n") -ne ($want -join "`n")) {
            $bad.Add(('{0}:{1}  期待:{1}    {2}{1}  実際:{1}    {3}' -f $v.Name, "`n", ($want -join "`n    "), ($got -join "`n    ")))
        }
    }
    if ($bad.Count -gt 0) {
        throw ('{0} / {1} 件が違います{2}{3}' -f $bad.Count, @($script:KcHtZmkVectors).Count, "`n", (($bad | Select-Object -First 3) -join "`n"))
    }
}

Test-Case 'QMK: tests/tap_hold_configurations で、QMK と同じ HID のレポートを出す' {
    $bad = New-Object 'System.Collections.Generic.List[string]'
    foreach ($v in $script:KcHtQmkVectors) {
        $keys = @{}
        foreach ($k in $v.Keys) {
            if (-not $keys.ContainsKey($k.Pos)) { $keys[$k.Pos] = @{} }
            $keys[$k.Pos][$k.Layer] = $k.Binding
        }
        $km = @{ Keys = $keys; Qmk = $v.Settings; Hands = $v.Hands }
        $r = Invoke-KcQmkTapHold -Keymap $km -Events (ConvertTo-HtEvents $v.Events) -Trace
        $got = @($r.Lines | Where-Object { $_.StartsWith('report: ') })
        $want = @($v.Expect)
        if (($got -join "`n") -ne ($want -join "`n")) {
            $bad.Add(('{0}:{1}  入力: {4}{1}  期待:{1}    {2}{1}  実際:{1}    {3}' -f $v.Name, "`n", ($want -join "`n    "), ((@($r.Lines)) -join "`n    "), $v.Events))
        }
    }
    if ($bad.Count -gt 0) {
        throw ('{0} / {1} 件が違います{2}{3}' -f $bad.Count, @($script:KcHtQmkVectors).Count, "`n", (($bad | Select-Object -First 4) -join "`n"))
    }
}
