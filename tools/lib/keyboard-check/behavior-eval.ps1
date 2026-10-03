# 実動作テストの「レイヤー・ビヘイビア」の判定 (キーの記録 → 合否)。Windows の API を使わないので、どの OS でもテストできる。
# keyboard-check.ps1 から dot-source して使う。expected.ps1 / input-eval.ps1 が先に読み込まれている前提。
#
# 期待値 (tools/expected/*.json の interactive.behaviors.scenarios[].steps[]) の expect は、PC に届くはずの
# 「ストローク」の並び: 修飾以外のキーを押した瞬間の {usage, mods (HID の修飾のバイト), opt (付いていても可の修飾)}。
# tools/expected/behaviors.py が ZMK の動きを真似て求めたもの。
#
# 比べ方:
#   - 順番だけで比べ、時刻は見ない (テスト用のウィンドウの時刻は 15 ms 単位にまとまるため)
#   - 修飾は左右を区別しない (Ctrl / Shift / Alt / Win)。opt の修飾は付いていてもいなくてもよい
#   - 修飾キーだけの出入りは数えない (モッドモーフのマスクや、押したままにする修飾キーで出入りするため)

# HID の修飾のバイト → 左右をまとめた Ctrl (1) / Shift (2) / Alt (4) / Win (8)
function Get-KcFoldedMods([int]$Mods) {
    return (($Mods -bor ($Mods -shr 4)) -band 0x0F)
}

function Format-KcModsText([int]$Mods) {
    $f = Get-KcFoldedMods $Mods
    $names = @()
    if ($f -band 1) { $names += 'Ctrl' }
    if ($f -band 2) { $names += 'Shift' }
    if ($f -band 4) { $names += 'Alt' }
    if ($f -band 8) { $names += 'Win' }
    return ($names -join '+')
}

# ストローク (期待値の {usage, mods} か ConvertTo-KcStrokes の {Usage, Mods}) → 'Ctrl+X'
function Format-KcStroke($Stroke, $ScanTable) {
    $usage = [int](Get-KcProp $Stroke 'Usage' (Get-KcProp $Stroke 'usage' -1))
    $mods = [int](Get-KcProp $Stroke 'Mods' (Get-KcProp $Stroke 'mods' 0))
    $label = ''
    if ($usage -ge 0) {
        $label = Get-KcUsageLabel $usage $ScanTable
    } else {
        $label = 'スキャンコード ' + [string](Get-KcProp $Stroke 'Code' '?')
    }
    $m = Format-KcModsText $mods
    if ($m) {
        return ($m + '+' + $label)
    }
    return $label
}

function Format-KcStrokeList($Strokes, $ScanTable) {
    # foreach で回す (New-Object で作った List を @() で包むと、PowerShell 7 で例外になるため)
    $parts = @()
    foreach ($s in $Strokes) {
        $parts += (Format-KcStroke $s $ScanTable)
    }
    if ($parts.Count -eq 0) {
        return '(入力なし)'
    }
    return ($parts -join '、')
}

# キーの記録 → ストロークの並び [{Usage; Mods; Code; Time}]。修飾キーの押下状態を追い、修飾以外のキーを押した瞬間の
# 修飾を付ける (リピートはまとめる)。修飾キーだけのタップは数えない
function ConvertTo-KcStrokes($Events, $ScanTable) {
    $actions = ConvertTo-KcKeyActions $Events $ScanTable
    $mods = 0
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($a in $actions) {
        if ($a.Usage -ge 0xE0 -and $a.Usage -le 0xE7) {
            $bit = 1 -shl ($a.Usage - 0xE0)
            if ($a.Down) {
                $mods = $mods -bor $bit
            } else {
                $mods = $mods -band (-bnot $bit)
            }
            continue
        }
        if ($a.Down) {
            $out.Add([pscustomobject]@{ Usage = $a.Usage; Mods = $mods; Code = $a.Code; Time = $a.Time })
        }
    }
    return , $out.ToArray()
}

# 実際のストロークが、期待の 1 つと合うか (修飾は左右をまとめ、opt は無視)
function Test-KcStrokeMatch($Actual, $Expected) {
    if ([int]$Actual.Usage -ne [int]$Expected.usage) {
        return $false
    }
    $opt = Get-KcFoldedMods ([int](Get-KcProp $Expected 'opt' 0))
    $fa = Get-KcFoldedMods ([int]$Actual.Mods)
    $fe = Get-KcFoldedMods ([int]$Expected.mods)
    return ((($fa -bxor $fe) -band (-bnot $opt) -band 0x0F) -eq 0)
}

# 手順 1 つの判定。$Step: 期待値の steps[] の 1 つ (expect)
#   Status: PASS / FAIL / NONE (何も出ない)
#   ActualStates: 実際のストロークごとに 1 = 合う / 2 = 違う、ExpectedStates: 期待ごとに 0 = まだ / 1 = 合う / 2 = 違う
function Test-KcBehaviorStep($Events, $Step, $ScanTable) {
    $actual = ConvertTo-KcStrokes $Events $ScanTable
    $expected = @($Step.expect)
    $aStates = New-Object 'System.Collections.Generic.List[int]'
    $eStates = New-Object 'System.Collections.Generic.List[int]'
    $firstBad = -1
    for ($i = 0; $i -lt $expected.Count; $i++) {
        if ($i -ge $actual.Count) {
            $eStates.Add(0)
            continue
        }
        if (Test-KcStrokeMatch $actual[$i] $expected[$i]) {
            $eStates.Add(1)
        } else {
            $eStates.Add(2)
            if ($firstBad -lt 0) { $firstBad = $i }
        }
    }
    for ($i = 0; $i -lt $actual.Count; $i++) {
        if ($i -lt $expected.Count -and $eStates[$i] -eq 1) {
            $aStates.Add(1)
        } else {
            $aStates.Add(2)
            if ($firstBad -lt 0) { $firstBad = $i }
        }
    }
    $actualText = Format-KcStrokeList $actual $ScanTable
    $expectedText = Format-KcStrokeList $expected $ScanTable
    $r = [pscustomobject]@{
        Status = 'PASS'; Actual = $actualText; Expected = $expectedText; Message = ''
        Strokes = $actual; ActualStates = $aStates.ToArray(); ExpectedStates = $eStates.ToArray()
    }
    if ($actual.Count -eq 0) {
        $r.Status = 'NONE'
        $r.Actual = '(入力なし)'
        return $r
    }
    if ($firstBad -lt 0 -and $actual.Count -eq $expected.Count) {
        return $r
    }
    $r.Status = 'FAIL'
    if ($firstBad -lt 0) {
        $r.Message = ('入力が足りません ({0} / {1})' -f $actual.Count, $expected.Count)
    } elseif ($firstBad -ge $expected.Count) {
        $r.Message = '余分な入力があります'
    } elseif ([int]$actual[$firstBad].Usage -eq [int]$expected[$firstBad].usage) {
        $r.Message = ('{0} 番目の修飾キーが違います (期待 {1} / 実際 {2})' -f ($firstBad + 1),
            (Format-KcStroke $expected[$firstBad] $ScanTable), (Format-KcStroke $actual[$firstBad] $ScanTable))
    } else {
        $r.Message = ('{0} 番目が違います (期待 {1} / 実際 {2})' -f ($firstBad + 1),
            (Format-KcStroke $expected[$firstBad] $ScanTable), (Format-KcStroke $actual[$firstBad] $ScanTable))
    }
    return $r
}

# 判定してよいか: 期待の数だけ出た (か、もう違うと分かった) あと、$SettleMs 何も来なかった。
# 押したままのレイヤーキーは PC に何も送らないので、「全部離した」は条件にしない。
# タップダンスの手順は、タップダンスの時間 (td_ms) + 300 ms は待つ
function Test-KcBehaviorStepDone($Events, $Step, $ScanTable, [long]$NowMs, [int]$SettleMs) {
    $keys = @(@($Events) | Where-Object { $_.Kind -eq 'key' })
    if ($keys.Count -eq 0) {
        return $false
    }
    $settle = $SettleMs
    $td = [int](Get-KcProp $Step 'td_ms' 0)
    if ($td -gt 0) {
        $settle = [math]::Max($settle, $td + 300)
    }
    if (($NowMs - [long]$keys[$keys.Count - 1].Time) -lt $settle) {
        return $false
    }
    $t = Test-KcBehaviorStep $Events $Step $ScanTable
    if ($t.Status -eq 'NONE') {
        return $false
    }
    return ($t.Status -eq 'PASS' -or $t.Strokes.Count -ge @($Step.expect).Count -or @($t.ExpectedStates | Where-Object { $_ -eq 2 }).Count -gt 0)
}

# ボールやマウスが動いた (AML になって、キーの意味が変わったかもしれない)
function Test-KcBehaviorMouseMoved($Events, [int]$MinMove = 8) {
    $sum = 0
    foreach ($e in @($Events)) {
        if ($e.Kind -eq 'mouse') {
            $sum += [math]::Abs([int]$e.Dx) + [math]::Abs([int]$e.Dy)
            if ([int]$e.Buttons -ne 0) {
                return $true
            }
        }
    }
    return ($sum -ge $MinMove)
}

# BASE に戻す手順 (recover) の後、最後の入力が BASE の確かめのキー (recover.check) か
function Test-KcBehaviorRecovered($Events, $Recover, $ScanTable) {
    $actual = ConvertTo-KcStrokes $Events $ScanTable
    if ($actual.Count -eq 0) {
        return $false
    }
    return (Test-KcStrokeMatch $actual[$actual.Count - 1] $Recover.check)
}

# 手順の結果から、次にすることを決める (純粋関数)。
#   $Outcome: PASS / FAIL / NONE (入力が無い・足りない) / MOVED (ボールが動いた) / SKIP (スキップ・時間切れ) / ABORT
#   $Attempt: 何回目か (1 から)、$Stateful: &to のレイヤーを使うシナリオ (失敗したら BASE に戻してからやり直す)
# 戻り値: Next = step (次の手順) / retry (同じ手順をもう一度) / restart (BASE に戻してからシナリオの最初から) /
#               end (このシナリオは終わり) / abort (テストを中止)
#         Record = この手順の結果として残すもの (PASS / FAIL / SKIP / '' = まだ残さない)、Recover = BASE に戻す手順をするか
function Get-KcBehaviorDecision([string]$Outcome, [int]$Attempt, [bool]$Stateful, [bool]$LastStep) {
    $d = @{ Next = 'step'; Record = ''; Recover = $false }
    switch ($Outcome) {
        'PASS' {
            $d.Record = 'PASS'
            if ($LastStep) { $d.Next = 'end' }
        }
        'ABORT' {
            $d.Next = 'abort'
            $d.Recover = $Stateful
        }
        'SKIP' {
            $d.Record = 'SKIP'
            if ($Stateful) {
                $d.Next = 'end'
                $d.Recover = $true
            } elseif ($LastStep) {
                $d.Next = 'end'
            }
        }
        default {
            # FAIL / NONE / MOVED: 1 回だけやり直す (MOVED はやり直しを数えない)
            $retryable = ($Attempt -lt 2) -or ($Outcome -eq 'MOVED' -and $Attempt -lt 4)
            if ($retryable) {
                if ($Stateful) {
                    $d.Next = 'restart'
                    $d.Recover = $true
                } else {
                    $d.Next = 'retry'
                }
            } else {
                $d.Record = 'FAIL'
                if ($Outcome -ne 'FAIL') { $d.Record = 'SKIP' }
                if ($Stateful) {
                    $d.Next = 'end'
                    $d.Recover = $true
                } elseif ($LastStep) {
                    $d.Next = 'end'
                }
            }
        }
    }
    return $d
}

# 読み出し検査で違っていた位置 ("レイヤー:位置") を使う手順か
function Test-KcBehaviorStepUsesMismatch($Step, $Mismatch) {
    if ($null -eq $Mismatch -or $Mismatch.Count -eq 0) {
        return $false
    }
    foreach ($a in @($Step.actions)) {
        $layer = [int](Get-KcProp $a 'layer' 0)
        foreach ($p in @(Get-KcProp $a 'positions' @(Get-KcProp $a 'pos' @()))) {
            if ($Mismatch.ContainsKey(('{0}:{1}' -f $layer, [int]$p))) {
                return $true
            }
        }
    }
    return $false
}

# 種類 (期待値の scenarios[].kind) → 結果の項目名
$script:KcBehaviorKindNames = [ordered]@{
    layer     = 'レイヤーの移動 (押したまま)'
    hold_tap  = '長押し (mod-tap)'
    mod_morph = 'モッドモーフ'
    tap_dance = 'タップダンス'
    to_layer  = 'レイヤーの切り替え (&to)'
    combo     = 'コンボ'
}
