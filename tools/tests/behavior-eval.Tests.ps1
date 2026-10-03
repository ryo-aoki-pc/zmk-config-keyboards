# レイヤー・ビヘイビアのテストの判定 (behavior-eval.ps1) のテスト

. (Join-Path $script:KcLib 'expected.ps1')
. (Join-Path $script:KcLib 'input-eval.ps1')
. (Join-Path $script:KcLib 'behavior-eval.ps1')

$common = Get-KcExpected 'common' $script:ExpectedDir
$scan = New-KcScanTable $common

function New-BeKey([long]$Time, [int]$Usage, [bool]$Break) {
    $k = $scan.ByUsage[$Usage]
    return (New-KcKeyEvent $Time ([int]$k.scan) ([int]$k.prefix) $Break)
}

# 左右をまとめた修飾 → 押す修飾キーの usage ($Right なら右の修飾)
function Get-BeModUsages([int]$Mods, [bool]$Right = $false) {
    $f = Get-KcFoldedMods $Mods
    $out = @()
    for ($i = 0; $i -lt 4; $i++) {
        if ($f -band (1 -shl $i)) {
            $u = 0xE0 + $i
            if ($Right) { $u += 4 }
            $out += $u
        }
    }
    return , $out
}

# 期待のストローク → Raw Input のキーの記録。$Variant で、実機で起きる揺れを混ぜる:
#   repeat: 押したままのリピート / opt: 付いても可の修飾を付ける / right: 右の修飾キーで送る /
#   noise: ストロークの間に修飾キーだけの出入り (QMK の修飾の出し直し、マスク) / overlap: 次のキーを押してから前のキーを離す
function New-BeEvents($Expect, [string]$Variant = '') {
    $events = New-Object 'System.Collections.Generic.List[object]'
    $t = [long]0
    $prev = -1
    foreach ($s in @($Expect)) {
        $mods = [int]$s.mods
        if ($Variant -eq 'opt') {
            $mods = $mods -bor [int](Get-KcProp $s 'opt' 0)
        }
        $mu = Get-BeModUsages $mods ($Variant -eq 'right')
        if ($Variant -eq 'noise') {
            $events.Add((New-BeKey $t 0xE0 $false)); $t += 3
            $events.Add((New-BeKey $t 0xE0 $true)); $t += 3
        }
        foreach ($u in $mu) { $events.Add((New-BeKey $t $u $false)); $t += 2 }
        $events.Add((New-BeKey $t ([int]$s.usage) $false)); $t += 5
        if ($Variant -eq 'repeat') {
            $events.Add((New-BeKey $t ([int]$s.usage) $false)); $t += 30
            $events.Add((New-BeKey $t ([int]$s.usage) $false)); $t += 30
        }
        if ($Variant -eq 'overlap' -and $prev -ge 0) {
            $events.Add((New-BeKey $t $prev $true)); $t += 2
        }
        if ($Variant -ne 'overlap') {
            $events.Add((New-BeKey $t ([int]$s.usage) $true)); $t += 2
        }
        foreach ($u in $mu) { $events.Add((New-BeKey $t $u $true)); $t += 2 }
        $prev = [int]$s.usage
        $t += 20
    }
    if ($Variant -eq 'overlap' -and $prev -ge 0) {
        $events.Add((New-BeKey $t $prev $true))
    }
    return , $events.ToArray()
}

Test-Case 'ストローク: 修飾キーの押下状態を付け、修飾キーだけの出入りは数えない' {
    $events = @(
        (New-BeKey 0 0xE0 $false), (New-BeKey 5 0xE0 $true),      # Ctrl を押したまま → マスクで離れる
        (New-BeKey 6 0x4B $false), (New-BeKey 20 0x4B $true),     # PgUp
        (New-BeKey 30 0xE1 $false), (New-BeKey 31 0x4D $false), (New-BeKey 40 0x4D $true), (New-BeKey 41 0xE1 $true)
    )
    $s = ConvertTo-KcStrokes $events $scan
    Assert-Equal 2 $s.Count
    Assert-Equal 0x4B $s[0].Usage
    Assert-Equal 0 $s[0].Mods
    Assert-Equal 0x02 $s[1].Mods
    Assert-Equal 'PgUp、Shift+End' (Format-KcStrokeList $s $scan)
}

Test-Case '判定: 順に比べ、修飾は左右を区別せず、opt は付いても可' {
    $step = [pscustomobject]@{ expect = @(
            [pscustomobject]@{ usage = 0x4D; mods = 0x02 },
            [pscustomobject]@{ usage = 0x1B; mods = 0x01; opt = 0x02 }) }
    Assert-Equal 'PASS' (Test-KcBehaviorStep (New-BeEvents $step.expect) $step $scan).Status
    Assert-Equal 'PASS' (Test-KcBehaviorStep (New-BeEvents $step.expect 'opt') $step $scan).Status 'Shift 付きの Ctrl+X も可'
    Assert-Equal 'PASS' (Test-KcBehaviorStep (New-BeEvents $step.expect 'right') $step $scan).Status '右の修飾キー'
    $wrong = @([pscustomobject]@{ usage = 0x4D; mods = 0 }, [pscustomobject]@{ usage = 0x1B; mods = 0x01 })
    $r = Test-KcBehaviorStep (New-BeEvents $wrong) $step $scan
    Assert-Equal 'FAIL' $r.Status
    Assert-True ($r.Message -like '1 番目の修飾キーが違います*') $r.Message
    Assert-Equal '2,1' ($r.ExpectedStates -join ',')
    $short = Test-KcBehaviorStep (New-BeEvents @($step.expect[0])) $step $scan
    Assert-Equal 'FAIL' $short.Status
    Assert-True ($short.Message -like '入力が足りません*') $short.Message
    Assert-Equal '1,0' ($short.ExpectedStates -join ',')
    Assert-Equal 'NONE' (Test-KcBehaviorStep @() $step $scan).Status
    $extra = Test-KcBehaviorStep (New-BeEvents ($step.expect + @([pscustomobject]@{ usage = 0x04; mods = 0 }))) $step $scan
    Assert-Equal 'FAIL' $extra.Status
    Assert-Equal '余分な入力があります' $extra.Message
    Assert-Equal '1,1,2' ($extra.ActualStates -join ',')
}

Test-Case '判定してよいか: 期待の数が出て、待ってから。タップダンスは長めに待つ' {
    $step = [pscustomobject]@{ expect = @([pscustomobject]@{ usage = 0x4A; mods = 0 }, [pscustomobject]@{ usage = 0x4D; mods = 0x02 }) }
    $ev = New-BeEvents $step.expect
    $last = [long]$ev[$ev.Count - 1].Time
    Assert-True (-not (Test-KcBehaviorStepDone @() $step $scan 5000 700)) '入力なし'
    Assert-True (-not (Test-KcBehaviorStepDone $ev $step $scan ($last + 100) 700)) 'まだ待つ'
    Assert-True (Test-KcBehaviorStepDone $ev $step $scan ($last + 700) 700) '判定できる'
    $one = New-BeEvents @($step.expect[0])
    $l1 = [long]$one[$one.Count - 1].Time
    Assert-True (-not (Test-KcBehaviorStepDone $one $step $scan ($l1 + 5000) 700)) '足りないうちは待つ (マクロの途中)'
    $bad = New-BeEvents @([pscustomobject]@{ usage = 0x04; mods = 0 })
    Assert-True (Test-KcBehaviorStepDone $bad $step $scan ([long]$bad[$bad.Count - 1].Time + 700) 700) '違うと分かったら判定'
    $td = [pscustomobject]@{ expect = $step.expect; td_ms = 200 }
    Assert-True (-not (Test-KcBehaviorStepDone $ev $td $scan ($last + 400) 300)) 'タップダンスは td_ms + 300'
    Assert-True (Test-KcBehaviorStepDone $ev $td $scan ($last + 500) 300)
}

Test-Case 'ボールが動いたか、BASE に戻せたか' {
    Assert-True (-not (Test-KcBehaviorMouseMoved @((New-KcMouseEvent 0 1 1))))
    Assert-True (Test-KcBehaviorMouseMoved @((New-KcMouseEvent 0 5 5)))
    Assert-True (Test-KcBehaviorMouseMoved @((New-KcMouseEvent 0 0 0 0x0001)))
    $rec = [pscustomobject]@{ check = [pscustomobject]@{ usage = 0x14; mods = 0 } }
    $ok = New-BeEvents @([pscustomobject]@{ usage = 0x4F; mods = 0 }, [pscustomobject]@{ usage = 0x14; mods = 0 })
    Assert-True (Test-KcBehaviorRecovered $ok $rec $scan)
    $vis = New-BeEvents @([pscustomobject]@{ usage = 0x19; mods = 0 }, [pscustomobject]@{ usage = 0x14; mods = 0 })
    Assert-True (Test-KcBehaviorRecovered $vis $rec $scan) 'もともと BASE (v が出た) でも、最後が q なら戻っている'
    $no = New-BeEvents @([pscustomobject]@{ usage = 0x4F; mods = 0x02 })
    Assert-True (-not (Test-KcBehaviorRecovered $no $rec $scan))
}

Test-Case '次にすること: やり直しは 1 回、&to のシナリオは BASE に戻してから最初から' {
    $d = Get-KcBehaviorDecision 'PASS' 1 $false $false
    Assert-Equal 'step' $d.Next
    Assert-Equal 'PASS' $d.Record
    Assert-Equal 'end' (Get-KcBehaviorDecision 'PASS' 1 $true $true).Next
    $d = Get-KcBehaviorDecision 'FAIL' 1 $false $false
    Assert-Equal 'retry' $d.Next
    Assert-Equal '' $d.Record
    $d = Get-KcBehaviorDecision 'FAIL' 2 $false $false
    Assert-Equal 'step' $d.Next
    Assert-Equal 'FAIL' $d.Record
    $d = Get-KcBehaviorDecision 'FAIL' 1 $true $false
    Assert-Equal 'restart' $d.Next
    Assert-True $d.Recover
    $d = Get-KcBehaviorDecision 'FAIL' 2 $true $false
    Assert-Equal 'end' $d.Next
    Assert-True $d.Recover
    Assert-Equal 'FAIL' $d.Record
    Assert-Equal 'retry' (Get-KcBehaviorDecision 'MOVED' 3 $false $false).Next 'ボールが動いたのは、やり直しに数えない'
    Assert-Equal 'SKIP' (Get-KcBehaviorDecision 'NONE' 2 $false $true).Record
    $d = Get-KcBehaviorDecision 'SKIP' 1 $true $false
    Assert-Equal 'end' $d.Next
    Assert-True $d.Recover
    $d = Get-KcBehaviorDecision 'ABORT' 1 $true $false
    Assert-Equal 'abort' $d.Next
    Assert-True $d.Recover
}

Test-Case '読み出し検査で違っていた位置を使う手順' {
    $step = [pscustomobject]@{ actions = @(
            [pscustomobject]@{ op = 'hold'; pos = 35; layer = 0 }, [pscustomobject]@{ op = 'tap'; pos = 0; layer = 1 }) }
    Assert-True (-not (Test-KcBehaviorStepUsesMismatch $step @{}))
    Assert-True (Test-KcBehaviorStepUsesMismatch $step @{ '1:0' = $true })
    Assert-True (-not (Test-KcBehaviorStepUsesMismatch $step @{ '0:0' = $true }))
}

Test-Case '全機種の全シナリオ: 期待から作った入力は PASS、1 か所変えると FAIL' {
    $n = 0
    foreach ($id in @('lism', 'kukey42', 'aroundfortyrb', 'pyuron', 'roba', 'torabo-tsuki-lp', 'kq-mini')) {
        $e = Get-KcExpected $id $script:ExpectedDir
        foreach ($sc in @($e.interactive.behaviors.scenarios)) {
            foreach ($st in @($sc.steps)) {
                $where = '{0}: {1}: {2}' -f $id, $sc.title, $st.text
                foreach ($v in @('', 'repeat', 'opt', 'right', 'noise', 'overlap')) {
                    $r = Test-KcBehaviorStep (New-BeEvents $st.expect $v) $st $scan
                    Assert-Equal 'PASS' $r.Status ('{0} ({1}) {2}' -f $where, $v, $r.Message)
                }
                $first = $st.expect[0]
                $other = 0x04
                if ([int]$first.usage -eq 0x04) { $other = 0x05 }
                $bad = @([pscustomobject]@{ usage = $other; mods = [int]$first.mods }) + @($st.expect | Select-Object -Skip 1)
                Assert-Equal 'FAIL' (Test-KcBehaviorStep (New-BeEvents $bad) $st $scan).Status ($where + ' (キーを変える)')
                $flip = @([pscustomobject]@{ usage = [int]$first.usage; mods = ([int]$first.mods -bxor 0x04) }) + @($st.expect | Select-Object -Skip 1)
                Assert-Equal 'FAIL' (Test-KcBehaviorStep (New-BeEvents $flip) $st $scan).Status ($where + ' (Alt を足す)')
                $n++
            }
        }
    }
    Assert-True ($n -gt 200) ('手順の数 {0}' -f $n)
}

Test-Case 'Keyball39 (直結) はレイヤー・ビヘイビアのテストが無い' {
    $e = Get-KcExpected 'keyball39' $script:ExpectedDir
    Assert-Equal 0 @($e.interactive.behaviors.scenarios).Count
    Assert-True (@($e.interactive.behaviors.not_tested).Count -gt 0)
}
