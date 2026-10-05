# ファームウェアの整数演算と AML の境界を、手計算の値で確かめる。
# PointerSim は単独でも読み込める。ほかのテストでまとめてコンパイル済みなら再利用する。
if (-not ('KcPointerSim' -as [type])) {
    Add-Type -Path (Join-Path $script:KcLib 'PointerSim.cs')
}

function New-PointerTestConfig([string]$Engine = 'zmk') {
    $c = New-Object KcPointerConfig
    $c.Engine = $Engine
    $c.ExcludedPositions = [int[]]@(12, 17)
    if ($Engine -eq 'keyball') { $c.Transform = 4; $c.ScrollTransform = 6 }
    return $c
}

Test-Case 'ZMK 加速: 次の報告に倍率を掛け、Y=8 の4回は 4,4,6,7' {
    $s = New-Object KcPointerSim (New-PointerTestConfig)
    foreach ($t in @(300, 308, 316, 324)) { $s.Move($t, 0, 8, $false) }
    # speed=80,540,770,885 / 次の factor=540,770,885,942。端数も次へ渡す。
    Assert-Equal @(4, 4, 6, 7) @($s.Reports | ForEach-Object { $_.Y })
}

Test-Case 'ZMK 加速: 初回 X/Y(sync) のリセットは固定ソースのイベント順を守る' {
    $s = New-Object KcPointerSim (New-PointerTestConfig)
    foreach ($t in @(300, 308, 316)) { $s.Move($t, 8, 0, $false) }
    # 初回は sync 前の Y イベントでもリセットされ、速度計算に X が残らない。
    Assert-Equal @(4, 4, 6) @($s.Reports | ForEach-Object { $_.X })
}

Test-Case 'ZMK 補正: 1/2 の補正と 1/2 の加速で4カウントが1になる' {
    $c = New-PointerTestConfig
    $c.XNumerator = 1; $c.XDenominator = 2
    $c.SpeedThreshold = 1000000; $c.SpeedMax = 2000000
    $s = New-Object KcPointerSim $c
    foreach ($t in @(300, 308, 316, 324)) { $s.Move($t, 1, 0, $false) }
    Assert-Equal 1 $s.Reports.Count
    Assert-Equal 1 $s.Reports[0].X
    Assert-Equal 324 $s.Reports[0].Time
}

Test-Case 'ZMK 加速: 負の端数はゼロ方向へ丸め、次に持ち越す' {
    $c = New-PointerTestConfig
    $c.SpeedThreshold = 1000000; $c.SpeedMax = 2000000
    $s = New-Object KcPointerSim $c
    $s.Move(300, -1, 0, $false)
    Assert-Equal 0 $s.Reports.Count
    $s.Move(308, -1, 0, $false)
    Assert-Equal -1 $s.Reports[0].X
}

Test-Case 'ZMK 加速: 51ms途切れると最小倍率に戻る' {
    $s = New-Object KcPointerSim (New-PointerTestConfig)
    $s.Move(300, 0, 100, $false)
    $s.Move(308, 0, 100, $false)
    $s.Move(359, 0, 2, $false)
    Assert-Equal 1 $s.Reports[2].Y
}

Test-Case 'AML: 符号付き累積の9は抑制し10で発動する' {
    $s = New-Object KcPointerSim (New-PointerTestConfig)
    $s.Move(300, 18, 0, $false)
    Assert-Equal $false $s.AmlActive
    $s.Move(308, 2, 0, $false)
    Assert-Equal $true $s.AmlActive
    Assert-Equal 308 $s.Transitions[0].Time
}

Test-Case 'AML: 逆向きの振動は打ち消し、100msを超える間隔は累積を消す' {
    $s = New-Object KcPointerSim (New-PointerTestConfig)
    $s.Move(300, 18, 0, $false)
    $s.Move(308, -18, 0, $false)
    Assert-Equal $false $s.AmlActive
    $s.Move(409, 18, 0, $false)
    Assert-Equal $false $s.AmlActive
}

Test-Case 'AML: キー解放から199msは抑制し200msで許可する' {
    foreach ($elapsed in @(199, 200)) {
        $s = New-Object KcPointerSim (New-PointerTestConfig)
        $s.Key(100, $true, $false, $false)
        $s.Key(110, $false, $false, $false)
        $s.Move((110 + $elapsed), 20, 0, $false)
        Assert-Equal ($elapsed -eq 200) $s.AmlActive
    }
}

Test-Case 'AML: 修飾キーでも押下で解除し除外位置では保持する' {
    $s = New-Object KcPointerSim (New-PointerTestConfig)
    $s.Move(300, 20, 0, $false)
    $s.Key(350, $true, $false, $true)
    Assert-Equal $true $s.AmlActive
    $s.Key(400, $true, $true, $false)
    Assert-Equal $false $s.AmlActive
}

Test-Case 'ZMK AML: ゼロの入力も期限を延ばしちょうど10000msで解除する' {
    $s = New-Object KcPointerSim (New-PointerTestConfig)
    $s.Move(300, 20, 0, $false)
    $s.Move(10000, 0, 0, $false)
    $s.AdvanceTo(19999)
    Assert-Equal $true $s.AmlActive
    $s.AdvanceTo(20000)
    Assert-Equal $false $s.AmlActive
    Assert-Equal 20000 $s.Transitions[1].Time
}

Test-Case 'ZMK AML: クリックの押下と解放が期限を延ばす' {
    $s = New-Object KcPointerSim (New-PointerTestConfig)
    $s.Move(300, 20, 0, $false)
    $s.Button(9000, 1, $true)
    $s.Button(9050, 1, $false)
    Assert-Equal @(0, 1, 0) @($s.Reports | ForEach-Object { $_.Buttons })
    $s.AdvanceTo(19049)
    Assert-Equal $true $s.AmlActive
    $s.AdvanceTo(19050)
    Assert-Equal $false $s.AmlActive
}

Test-Case 'ZMK AML: レイヤーを外から解除すると保留中の期限も消える' {
    $s = New-Object KcPointerSim (New-PointerTestConfig)
    $s.Move(300, 20, 0, $false)
    $s.ObserveLayer(400, $false)
    Assert-Equal -1 $s.NextDeadline
    $s.Move(600, 2, 0, $false)
    Assert-Equal $false $s.AmlActive
    $s.AdvanceTo(20000)
    Assert-Equal 1 $s.Transitions.Count
}

Test-Case 'ZMK スクロール: 加速を通さず1/16の端数と向きを守る' {
    $c = New-PointerTestConfig
    $c.ScrollTransform = 1
    $s = New-Object KcPointerSim $c
    $s.Move(300, 8, 8, $true)
    Assert-Equal 0 $s.Reports.Count
    $s.Move(308, 8, 8, $true)
    Assert-Equal -1 $s.Reports[0].HWheel
    Assert-Equal 1 $s.Reports[0].Wheel
    Assert-Equal 0 $s.Reports[0].X
    Assert-Equal 10308 $s.NextDeadline
}

Test-Case 'ZMK スクロール: 直前のキーコードの時刻による抑制を使う' {
    $s = New-Object KcPointerSim (New-PointerTestConfig)
    $s.Keycode(100, 100)
    $s.Move(299, 0, 16, $true)
    Assert-Equal $false $s.AmlActive
    $s.Move(300, 0, 16, $true)
    Assert-Equal $true $s.AmlActive
}

Test-Case 'ZMK 左右: 端数としきい値の累積はリスナーごとに独立する' {
    $c = New-PointerTestConfig
    $s = New-Object KcPointerSim $c
    $s.AddSide('left', $c)
    $s.MoveSide(300, 'left', 18, 0, $false)
    $s.MoveSide(308, 'right', 18, 0, $false)
    Assert-Equal $false $s.AmlActive
    $s.MoveSide(316, 'left', 2, 0, $false)
    Assert-Equal $true $s.AmlActive
}

Test-Case 'Keyball 加速: 8msごとのQ8計算は8カウントから6,7,7,8を出す' {
    $s = New-Object KcPointerSim (New-PointerTestConfig 'keyball')
    foreach ($t in @(300, 308, 316, 324)) { $s.Move($t, 0, 8, $false) }
    $s.AdvanceTo(328)
    Assert-Equal @(304, 312, 320, 328) @($s.Reports | ForEach-Object { $_.Time })
    Assert-Equal @(6, 7, 7, 8) @($s.Reports | ForEach-Object { $_.X })
    Assert-Equal 312 $s.Transitions[0].Time
}

Test-Case 'Keyball 加速: Q8の負数は下方向へ丸め、空の8ms区間で速度を減衰する' {
    $s = New-Object KcPointerSim (New-PointerTestConfig 'keyball')
    $s.Move(300, 0, -1, $false)
    $s.AdvanceTo(304)
    Assert-Equal -1 $s.Reports[0].X
    $s.Move(500, 0, 1, $false)
    $s.AdvanceTo(504)
    Assert-Equal 1 $s.Reports[1].X
}

Test-Case 'Keyball 加速: レポートは符号付き127に飽和する' {
    $s = New-Object KcPointerSim (New-PointerTestConfig 'keyball')
    $s.Move(300, 0, 1000, $false)
    $s.Move(308, 0, -1000, $false)
    $s.AdvanceTo(312)
    Assert-Equal @(127, -127) @($s.Reports | ForEach-Object { $_.X })
}

Test-Case 'Keyball スクロール: 切替直後50msは捨て、その後は1/16で変換する' {
    $s = New-Object KcPointerSim (New-PointerTestConfig 'keyball')
    $s.SetScroll(300, $true)
    $s.Move(300, 16, 16, $true)
    $s.AdvanceTo(344)
    Assert-Equal 0 $s.Reports.Count
    $s.Move(350, 16, 16, $true)
    $s.AdvanceTo(352)
    Assert-Equal 1 $s.Reports[0].HWheel
    Assert-Equal -1 $s.Reports[0].Wheel
}

Test-Case 'Keyball AML: 空の報告では延長せず期限を超えた8ms区間で解除する' {
    $s = New-Object KcPointerSim (New-PointerTestConfig 'keyball')
    $s.Move(300, 0, 16, $false)
    $s.AdvanceTo(10304)
    Assert-Equal $true $s.AmlActive
    $s.AdvanceTo(10312)
    Assert-Equal $false $s.AmlActive
    Assert-Equal 10312 $s.Transitions[1].Time
}

Test-Case 'Keyball AML: マウスキーを押したままなら保持し修飾キーで解除する' {
    $s = New-Object KcPointerSim (New-PointerTestConfig 'keyball')
    $s.Move(300, 0, 16, $false)
    $s.Key(400, $true, $false, $true)
    $s.AdvanceTo(11000)
    Assert-Equal $true $s.AmlActive
    $s.Key(11001, $true, $true, $false)
    Assert-Equal $false $s.AmlActive
}

Test-Case '入力の検証: 不明なエンジン、ゼロの除数、未対応スクロールを拒否する' {
    $c = New-PointerTestConfig
    $c.Engine = 'unknown'
    Assert-Throws { New-Object KcPointerSim $c }
    $c = New-PointerTestConfig
    $c.XDenominator = 0
    Assert-Throws { New-Object KcPointerSim $c }
    $c = New-PointerTestConfig
    $c.ScrollSupported = $false
    $s = New-Object KcPointerSim $c
    Assert-Throws { $s.Move(300, 1, 1, $true) }
    Assert-Throws { $s.MoveSide(301, 'unknown', 1, 1, $false) }
    Assert-Throws { $s.Move(299, 1, 1, $false) }
}
