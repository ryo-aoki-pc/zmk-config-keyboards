# 上流の処理順に基づく、仮想時計とビヘイビアの独立した期待値。
. (Join-Path $script:KcLib 'keyboard-sim.ps1')
Import-KcHoldTapSim

function New-KseKey([int]$Usage, [int]$Mods = 0) {
    $b = New-Object KcHtBinding
    $b.Kind = 'kp'; $b.Usage = $Usage; $b.Mods = $Mods
    return $b
}

function Invoke-Kse($Map, [string]$Events, [long]$End, [string]$Engine = 'zmk') {
    $inputs = New-Object 'System.Collections.Generic.List[KcHtInput]'
    foreach ($token in ($Events -split ' ')) {
        if (-not $token) { continue }
        if ($token -notmatch '^([pr])(\d+)@(\d+)$') { throw $token }
        $inputs.Add([KcHtInput]::Make([int]$Matches[2], ($Matches[1] -eq 'p'), [long]$Matches[3]))
    }
    return [KcKeyboardSim]::Run($Engine, $Map, $inputs.ToArray(), [KcSimEvent[]]@(), $End, $false)
}

function Get-KseKeys($Result) {
    return (($Result.Hid | Where-Object { $_.Kind -eq 'key' } | ForEach-Object {
        '{0}/{1}/{2}/{3}' -f $_.T, $_.Usage, [int]$_.Down, $_.Mods
    }) -join ' ')
}

Test-Case '終了時刻: 未確定のhold-tapを勝手に最後まで実行しない' {
    $map = New-Object KcHtKeymap
    $ht = New-Object KcHtBinding; $ht.Kind = 'ht'; $ht.Behavior = 'test'
    $ht.Hold = New-KseKey 224; $ht.Tap = New-KseKey 4
    $cfg = New-Object KcHtZmkConfig; $cfg.Term = 150
    $map.Set(0, 0, $ht); $map.SetBehavior('test', $cfg)
    foreach ($engine in @('zmk', 'qmk')) {
        $map.Qmk.TappingTerm = 150
        $before = Invoke-Kse $map 'p0@0' 149 $engine
        Assert-Equal 149 $before.EndT
        Assert-Equal 0 $before.Hid.Count
        Assert-Equal 0 $before.Decisions.Count
        $at = Invoke-Kse $map 'p0@0' 150 $engine
        Assert-Equal '150/224/1/1' (Get-KseKeys $at)
        Assert-Equal 1 $at.Decisions.Count
    }
}

Test-Case 'ZMK: 既定のマクロ待ち15msとタップ30msを共有キューで処理する' {
    $map = New-Object KcHtKeymap
    $macro = ConvertTo-KcSimObject (@{ kind = 'macro'; steps = @(
        @{ kind = 'tap'; binding = @{ kind = 'kp'; usage = 4 } },
        @{ kind = 'tap'; binding = @{ kind = 'kp'; usage = 5 } }
    ) }) ([KcHtBinding])
    $map.Set(0, 0, $macro); $map.Set(1, 0, (New-KseKey 6))
    $r = Invoke-Kse $map 'p0@0 r0@1 p1@10 r1@11' 100
    Assert-Equal '0/4/1/0 10/6/1/0 11/6/0/0 30/4/0/0 45/5/1/0 75/5/0/0' (Get-KseKeys $r)
    $short = Invoke-Kse $map 'p0@0' 29
    Assert-Equal '0/4/1/0' (Get-KseKeys $short)
}

Test-Case 'ZMK: pause後のタップ時間は明示した制御だけを引き継ぐ' {
    $map = New-Object KcHtKeymap
    $macro = ConvertTo-KcSimObject (@{ kind = 'macro'; wait_ms = 3; tap_ms = 2; steps = @(
        @{ kind = 'tap'; binding = @{ kind = 'kp'; usage = 4 } },
        @{ kind = 'wait_time'; ms = 10 },
        @{ kind = 'tap'; binding = @{ kind = 'kp'; usage = 5 } },
        @{ kind = 'pause' },
        @{ kind = 'tap'; binding = @{ kind = 'kp'; usage = 6 } }
    ) }) ([KcHtBinding])
    $map.Set(0, 0, $macro)
    Assert-Equal '0/4/1/0 2/4/0/0 5/5/1/0 7/5/0/0 25/6/1/0 25/6/0/0' (Get-KseKeys (Invoke-Kse $map 'p0@0 r0@25' 50))
}

Test-Case 'ZMK: 暗黙の修飾はキーごとに保持せず最新の押下で置き換わる' {
    $map = New-Object KcHtKeymap
    $map.Set(0, 0, (New-KseKey 4 1)); $map.Set(1, 0, (New-KseKey 5 2)); $map.Set(2, 0, (New-KseKey 6))
    Assert-Equal '0/224/1/1 0/4/1/1 10/224/0/0 10/225/1/2 10/5/1/2 20/225/0/0 20/6/1/0 30/4/0/0 40/5/0/0 50/6/0/0' (Get-KseKeys (Invoke-Kse $map 'p0@0 p1@10 p2@20 r0@30 r1@40 r2@50' 60))
    $r = Invoke-Kse $map 'p0@0 r0@10' 20
    Assert-Equal '0/224/1/1 0/4/1/1 10/224/0/0 10/4/0/0' (Get-KseKeys $r)
}

Test-Case 'Vial: tap danceの4分岐とtapping-termを過ぎた時点の判定' {
    $map = New-Object KcHtKeymap
    $dance = New-Object KcHtBinding; $dance.Kind = 'qdance'; $dance.Term = 50
    $dance.Bindings = [KcHtBinding[]]@((New-KseKey 4), (New-KseKey 5), (New-KseKey 6), (New-KseKey 7))
    $map.Set(0, 0, $dance); $map.Set(1, 0, (New-KseKey 8))
    Assert-Equal '' (Get-KseKeys (Invoke-Kse $map 'p0@0 r0@10' 50 'qmk'))
    Assert-Equal '51/4/1/0 51/4/0/0' (Get-KseKeys (Invoke-Kse $map 'p0@0 r0@10' 51 'qmk'))
    Assert-Equal '51/5/1/0' (Get-KseKeys (Invoke-Kse $map 'p0@0' 51 'qmk'))
    Assert-Equal '71/6/1/0 71/6/0/0' (Get-KseKeys (Invoke-Kse $map 'p0@0 r0@10 p0@20 r0@30' 71 'qmk'))
    Assert-Equal '71/7/1/0' (Get-KseKeys (Invoke-Kse $map 'p0@0 r0@10 p0@20' 71 'qmk'))
    Assert-Equal '35/4/1/0 35/4/0/0 35/4/1/0 35/4/0/0 35/8/1/0' (Get-KseKeys (Invoke-Kse $map 'p0@0 r0@10 p0@20 r0@30 p1@35' 40 'qmk'))
}

Test-Case 'Vial: マクロdelayはZMKの非同期待ちとは異なり入力処理を止める' {
    $map = New-Object KcHtKeymap
    $macro = ConvertTo-KcSimObject (@{ kind = 'qmacro'; steps = @(
        @{ kind = 'tap'; binding = @{ kind = 'kp'; usage = 4 } },
        @{ kind = 'wait'; ms = 40 },
        @{ kind = 'tap'; binding = @{ kind = 'kp'; usage = 5 } }
    ) }) ([KcHtBinding])
    $map.Set(0, 0, $macro); $map.Set(1, 0, (New-KseKey 6))
    Assert-Equal '0/4/1/0 0/4/0/0 40/5/1/0 40/5/0/0 40/6/1/0 40/6/0/0' (Get-KseKeys (Invoke-Kse $map 'p0@0 r0@1 p1@10 r1@20' 50 'qmk'))
}

Test-Case 'エンジン: ZMKのビヘイビアをQMKの同名機能に見立てない' {
    $map = New-Object KcHtKeymap
    $binding = New-Object KcHtBinding; $binding.Kind = 'macro'
    $map.Set(0, 0, $binding)
    Assert-Throws { Invoke-Kse $map 'p0@0 r0@10' 20 'qmk' } '*zmk behavior*'
}

Test-Case 'Vial: tap danceは押下時の修飾を覚え判定時にweak modsで戻す' {
    $map = New-Object KcHtKeymap
    $dance = New-Object KcHtBinding; $dance.Kind = 'qdance'; $dance.Term = 50
    $dance.Bindings = [KcHtBinding[]]@((New-KseKey 4), (New-KseKey 5), (New-KseKey 6), (New-KseKey 7))
    $map.Set(0, 0, $dance); $map.Set(1, 0, (New-KseKey 225))
    Assert-Equal '0/225/1/2 30/225/0/0 61/225/1/2 61/4/1/2 61/4/0/2 61/225/0/0' (Get-KseKeys (Invoke-Kse $map 'p1@0 p0@10 r0@20 r1@30' 70 'qmk'))
}
