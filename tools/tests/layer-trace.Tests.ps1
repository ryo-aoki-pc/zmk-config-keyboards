# ログ版のキーボードの COM ポートを探して読む処理 (layer-trace.ps1 の Read-KcLogPortLines) のテスト。
# -Mode Trace と -Mode HoldTap が使う。COM ポートは偽物にする (Find-KcStudioPort と Open-KcLogPort を置き換える)

. (Join-Path $script:KcLib 'zmk-log.ps1')
. (Join-Path $script:KcLib 'layer-trace.ps1')

# Find-KcStudioPort は配列をそのまま返す (return , $x)。0 件のとき、パイプラインで .Port を読むと StrictMode の例外になっていた
Test-Case 'ログのポート: 見つからなければ「見つかりません」を出す (0 件でも例外にしない)' {
    function Find-KcStudioPort { $found = @(); return , $found }
    $reader = New-KcLogPortReader
    $r = Read-KcLogPortLines $reader
    Assert-Equal 'ログ版のキーボードが見つかりません' $r.Status
    Assert-Equal 2 $r.Level
    Assert-Equal 0 @($r.Lines).Count
    Assert-Equal 0 $reader.Ports.Count
}

Test-Case 'ログのポート: 見つかったポートを開き、ログの行が届くのを待つ' {
    function Find-KcStudioPort {
        $found = @()
        $found += [pscustomobject]@{ Port = 'COM91'; Name = 'USB シリアル デバイス (COM91)'; DeviceId = '' }
        return , $found
    }
    function Open-KcLogPort([string]$Port) { return [pscustomobject]@{ IsOpen = $true; BytesToRead = 0 } }
    $reader = New-KcLogPortReader
    $r = Read-KcLogPortLines $reader
    Assert-Equal 'COM91 を待っています (キーを押してください)' $r.Status
    Assert-Equal 3 $r.Level
    Assert-True $reader.Ports.ContainsKey('COM91') 'ポートを開いた'
    Assert-Equal 0 @($r.Lines).Count
}
