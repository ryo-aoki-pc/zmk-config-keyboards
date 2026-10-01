# VIA / Vial (QMK) の読み出し検査: KQ-mini (Vial) と Keyball39 (VIA)。
# keyboard-check.ps1 から dot-source して使う。expected.ps1 と results.ps1 が先に読み込まれている前提。
#
# 問い合わせは $Query (scriptblock: & $Query <コマンド byte[]> <エコーの長さ> → 32 バイトの応答) で行う。
# 実機は rawhid.ps1 の New-KcRawHidQuery、テストは偽のデバイスを渡す。
#
# 送るのは読み取りコマンドだけ。Test-KcQmkCommandAllowed の許可リストにないコマンドは送らない
# (キーマップや設定を書き換えるコマンド、Vial の unlock 開始 (FE 06) は、ここからは送れない)。

# ---------------------------------------------------------------------------
# 許可リストと問い合わせ
# ---------------------------------------------------------------------------

function Test-KcQmkCommandAllowed([byte[]]$Command) {
    if ($null -eq $Command -or $Command.Length -eq 0) {
        return $false
    }
    $c0 = [int]$Command[0]
    $c1 = -1
    $c2 = -1
    if ($Command.Length -gt 1) { $c1 = [int]$Command[1] }
    if ($Command.Length -gt 2) { $c2 = [int]$Command[2] }
    switch ($c0) {
        0x01 { return $true }                                  # id_get_protocol_version
        0x02 { return ($c1 -eq 0x01 -or $c1 -eq 0x02) }        # id_get_keyboard_value (uptime / layout options)
        0x08 {                                                 # id_custom_get_value
            if ($c1 -eq 0x02) { return ($c2 -ge 1 -and $c2 -le 4) }   # RGB ライティング
            if ($c1 -eq 0x00) { return ($c2 -eq 1 -or $c2 -eq 2) }    # Keyball の状態 / ビルド日付
            return $false
        }
        0x0C { return $true }                                  # id_dynamic_keymap_macro_get_count
        0x0D { return $true }                                  # id_dynamic_keymap_macro_get_buffer_size
        0x0E { return $true }                                  # id_dynamic_keymap_macro_get_buffer
        0x11 { return $true }                                  # id_dynamic_keymap_get_layer_count
        0x12 { return $true }                                  # id_dynamic_keymap_get_buffer
        0xFE {                                                 # Vial
            if ($c1 -eq 0x00 -or $c1 -eq 0x05 -or $c1 -eq 0x09 -or $c1 -eq 0x0A) { return $true }
            if ($c1 -eq 0x0D) { return ($c2 -eq 0x00 -or $c2 -eq 0x01 -or $c2 -eq 0x03 -or $c2 -eq 0x05 -or $c2 -eq 0x07) }
            return $false
        }
    }
    return $false
}

function Invoke-KcQmk($Query, [byte[]]$Command, [int]$EchoLen) {
    if (-not (Test-KcQmkCommandAllowed $Command)) {
        throw ('読み取り専用でないコマンドは送りません: {0}' -f (($Command | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))
    }
    $r = & $Query $Command $EchoLen
    if ($null -eq $r -or @($r).Count -lt 32) {
        throw '応答が 32 バイトありません'
    }
    return , ([byte[]]$r)
}

function ConvertFrom-KcBigEndian([byte[]]$Bytes, [int]$Offset, [int]$Length) {
    [long]$v = 0
    for ($i = 0; $i -lt $Length; $i++) {
        $v = ($v -shl 8) -bor [long]$Bytes[$Offset + $i]
    }
    return $v
}

function ConvertFrom-KcLittleEndian([byte[]]$Bytes, [int]$Offset, [int]$Length) {
    [long]$v = 0
    for ($i = $Length - 1; $i -ge 0; $i--) {
        $v = ($v -shl 8) -bor [long]$Bytes[$Offset + $i]
    }
    return $v
}

# ---------------------------------------------------------------------------
# VIA
# ---------------------------------------------------------------------------

function Read-KcViaProtocol($Query) {
    $r = Invoke-KcQmk $Query ([byte[]](0x01)) 1
    return [int](ConvertFrom-KcBigEndian $r 1 2)
}

function Read-KcViaUptime($Query) {
    $r = Invoke-KcQmk $Query ([byte[]](0x02, 0x01)) 2
    return [long](ConvertFrom-KcBigEndian $r 2 4)
}

function Read-KcViaLayoutOptions($Query) {
    $r = Invoke-KcQmk $Query ([byte[]](0x02, 0x02)) 2
    return [long](ConvertFrom-KcBigEndian $r 2 4)
}

function Read-KcViaLayerCount($Query) {
    $r = Invoke-KcQmk $Query ([byte[]](0x11)) 1
    return [int]$r[1]
}

# 0x12 (dynamic_keymap_get_buffer) で $Size バイト読む。1 回に 28 バイトまで
function Read-KcViaKeymapBuffer($Query, [int]$Size) {
    $buf = New-Object byte[] $Size
    for ($offset = 0; $offset -lt $Size; $offset += 28) {
        $n = [math]::Min(28, $Size - $offset)
        $cmd = [byte[]](0x12, (($offset -shr 8) -band 0xFF), ($offset -band 0xFF), $n)
        $r = Invoke-KcQmk $Query $cmd 4
        [Array]::Copy($r, 4, $buf, $offset, $n)
    }
    return , $buf
}

# キーマップのバッファ (キーコードは 2 バイトのビッグエンディアン) → [レイヤー][行][列]
function ConvertFrom-KcViaKeymapBuffer([byte[]]$Bytes, [int]$Layers, [int]$Rows, [int]$Cols) {
    $out = New-Object 'object[]' $Layers
    for ($l = 0; $l -lt $Layers; $l++) {
        $grid = New-Object 'object[]' $Rows
        for ($r = 0; $r -lt $Rows; $r++) {
            $row = New-Object 'int[]' $Cols
            for ($c = 0; $c -lt $Cols; $c++) {
                $i = ((($l * $Rows) + $r) * $Cols + $c) * 2
                $row[$c] = ([int]$Bytes[$i] -shl 8) -bor [int]$Bytes[$i + 1]
            }
            $grid[$r] = $row
        }
        $out[$l] = $grid
    }
    return , $out
}

function Read-KcViaKeymap($Query, [int]$Layers, [int]$Rows, [int]$Cols) {
    $bytes = Read-KcViaKeymapBuffer $Query ($Layers * $Rows * $Cols * 2)
    return , (ConvertFrom-KcViaKeymapBuffer $bytes $Layers $Rows $Cols)
}

# マクロ: 個数・バッファの大きさ・中身 (16 個目の NUL まで読んだら止める)
function Read-KcViaMacros($Query) {
    $count = [int](Invoke-KcQmk $Query ([byte[]](0x0C)) 1)[1]
    $size = [int](ConvertFrom-KcBigEndian (Invoke-KcQmk $Query ([byte[]](0x0D)) 1) 1 2)
    $bytes = New-Object 'System.Collections.Generic.List[byte]'
    $nuls = 0
    for ($offset = 0; $offset -lt $size -and $nuls -lt $count; $offset += 28) {
        $n = [math]::Min(28, $size - $offset)
        $cmd = [byte[]](0x0E, (($offset -shr 8) -band 0xFF), ($offset -band 0xFF), $n)
        $r = Invoke-KcQmk $Query $cmd 4
        for ($i = 0; $i -lt $n; $i++) {
            $b = $r[4 + $i]
            $bytes.Add($b)
            if ($b -eq 0) {
                $nuls++
                if ($nuls -ge $count) {
                    break
                }
            }
        }
    }
    return [pscustomobject]@{ Count = $count; Size = $size; Bytes = $bytes.ToArray() }
}

# マクロのバッファ → 16 個のマクロ (それぞれ NUL の前までのバイト列)
function Split-KcMacroBuffer([byte[]]$Bytes, [int]$Count) {
    $macros = New-Object 'object[]' $Count
    $cur = New-Object 'System.Collections.Generic.List[byte]'
    $idx = 0
    foreach ($b in $Bytes) {
        if ($idx -ge $Count) {
            break
        }
        if ($b -eq 0) {
            $macros[$idx] = $cur.ToArray()
            $cur = New-Object 'System.Collections.Generic.List[byte]'
            $idx++
        } else {
            $cur.Add($b)
        }
    }
    for (; $idx -lt $Count; $idx++) {
        $macros[$idx] = [byte[]]@()
    }
    return , $macros
}

# マクロのバイト列 → 動作の並び (表記の違い (拡張キーコード) をそろえて比べるため)
function ConvertFrom-KcMacroBytes([byte[]]$Bytes) {
    $out = @()
    $i = 0
    while ($i -lt $Bytes.Length) {
        $b = $Bytes[$i]
        if ($b -eq 1 -and ($i + 1) -lt $Bytes.Length) {
            $code = $Bytes[$i + 1]
            switch ($code) {
                { $_ -ge 1 -and $_ -le 3 } {
                    $names = @('', 'tap', 'down', 'up')
                    $out += ('{0}:{1:X4}' -f $names[$code], [int]$Bytes[$i + 2])
                    $i += 3
                    continue
                }
                4 {
                    $ms = ([int]$Bytes[$i + 2] - 1) + ([int]$Bytes[$i + 3] - 1) * 255
                    $out += ('delay:{0}' -f $ms)
                    $i += 4
                    continue
                }
                { $_ -ge 5 -and $_ -le 7 } {
                    $names = @('', '', '', '', '', 'tap', 'down', 'up')
                    $lo = [int]$Bytes[$i + 2]
                    $hi = [int]$Bytes[$i + 3]
                    $kc = ($hi -shl 8) -bor $lo
                    if ($hi -eq 0xFF) {
                        $kc = $lo -shl 8
                    }
                    $out += ('{0}:{1:X4}' -f $names[$code], $kc)
                    $i += 4
                    continue
                }
                default {
                    $out += ('raw:{0:X2}' -f $b)
                    $i += 1
                    continue
                }
            }
        } else {
            $out += ('text:{0:X2}' -f $b)
            $i += 1
        }
    }
    return , $out
}

function ConvertTo-KcHexString([byte[]]$Bytes) {
    return ((@($Bytes) | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
}

# RGB ライティング (VIA プロトコル 12 以降は rgblight チャンネル 2)
function Read-KcViaRgb($Query, [int]$Protocol) {
    if ($Protocol -lt 12) {
        return $null
    }
    $b = Invoke-KcQmk $Query ([byte[]](0x08, 0x02, 0x01)) 3
    $e = Invoke-KcQmk $Query ([byte[]](0x08, 0x02, 0x02)) 3
    $c = Invoke-KcQmk $Query ([byte[]](0x08, 0x02, 0x04)) 3
    if ($b[0] -eq 0xFF -or $e[0] -eq 0xFF -or $c[0] -eq 0xFF) {
        return $null
    }
    return [pscustomobject]@{ Effect = [int]$e[3]; Brightness = [int]$b[3]; Hue = [int]$c[3]; Saturation = [int]$c[4] }
}

# ---------------------------------------------------------------------------
# Keyball39 の状態 (keymaps/via/keymap.c の via_custom_value_command_kb、08 00 01)
# ---------------------------------------------------------------------------

function ConvertFrom-KcKeyballStatus([byte[]]$R) {
    $flags = [int]$R[5]
    return [pscustomobject]@{
        Format           = [int]$R[3]
        Model            = [int]$R[4]
        ThisHaveBall     = [bool]($flags -band 0x01)
        ThatEnable       = [bool]($flags -band 0x02)
        ThatHaveBall     = [bool]($flags -band 0x04)
        IsLeft           = [bool]($flags -band 0x08)
        IsMaster         = [bool]($flags -band 0x10)
        ScrollMode       = [bool]($flags -band 0x20)
        AmlEnabled       = [bool]($flags -band 0x40)
        AmlToggled       = [bool]($flags -band 0x80)
        Cpi              = [int]$R[6]
        CpiRaw           = [int]$R[7]
        ScrollDiv        = [int]$R[8]
        ScrollDivRaw     = [int]$R[9]
        ScrollSnap       = [int]$R[10]
        AmlLayer         = [int]$R[11]
        AmlTimeout       = [int](ConvertFrom-KcBigEndian $R 12 2)
        AmlDelay         = [int](ConvertFrom-KcBigEndian $R 14 2)
        AmlDebounce      = [int]$R[16]
        ScrollLayer      = [int]$R[17]
        LayerState       = [int]$R[18]
        EeconfigKb       = [long](ConvertFrom-KcBigEndian $R 19 4)
        EeconfigUser     = [long](ConvertFrom-KcBigEndian $R 23 4)
        CpiDefault       = [int]$R[27]
        ScrollDivDefault = [int]$R[28]
    }
}

# 0xFF (id_unhandled) なら $null (このコマンドの無い古いファーム)
function Read-KcKeyballStatus($Query) {
    $r = Invoke-KcQmk $Query ([byte[]](0x08, 0x00, 0x01)) 3
    if ($r[0] -eq 0xFF) {
        return $null
    }
    return (ConvertFrom-KcKeyballStatus $r)
}

function Read-KcKeyballBuildDate($Query) {
    $r = Invoke-KcQmk $Query ([byte[]](0x08, 0x00, 0x02)) 3
    if ($r[0] -eq 0xFF) {
        return $null
    }
    $chars = @()
    for ($i = 3; $i -lt 32 -and $r[$i] -ne 0; $i++) {
        $chars += [char]$r[$i]
    }
    return (-join $chars)
}

# ---------------------------------------------------------------------------
# Vial (応答は要求をエコーしない。構造体はリトルエンディアン)
# ---------------------------------------------------------------------------

function Read-KcVialKeyboardId($Query) {
    $r = Invoke-KcQmk $Query ([byte[]](0xFE, 0x00)) 0
    return [pscustomobject]@{
        Protocol = [long](ConvertFrom-KcLittleEndian $r 0 4)
        Uid      = [int[]]@($r[4..11])
    }
}

function Read-KcVialUnlockStatus($Query) {
    $r = Invoke-KcQmk $Query ([byte[]](0xFE, 0x05)) 0
    return [pscustomobject]@{ Unlocked = [int]$r[0]; InProgress = [int]$r[1] }
}

# 設定 (QMK settings) の QSID の一覧
function Read-KcVialSettingIds($Query) {
    $ids = New-Object 'System.Collections.Generic.List[int]'
    $gt = 0
    for ($page = 0; $page -lt 16; $page++) {
        $r = Invoke-KcQmk $Query ([byte[]](0xFE, 0x09, ($gt -band 0xFF), (($gt -shr 8) -band 0xFF))) 0
        $done = $false
        for ($i = 0; $i -lt 32; $i += 2) {
            $q = [int](ConvertFrom-KcLittleEndian $r $i 2)
            if ($q -eq 0xFFFF) {
                $done = $true
                break
            }
            $ids.Add($q)
            $gt = $q
        }
        if ($done) {
            break
        }
    }
    return , $ids.ToArray()
}

$script:KcSettingWidths = @{ 'uint8_t' = 1; 'uint16_t' = 2; 'uint32_t' = 4 }

# 設定の値 (読めなければ $null)
function Read-KcVialSetting($Query, [int]$Qsid, [string]$Type) {
    $r = Invoke-KcQmk $Query ([byte[]](0xFE, 0x0A, ($Qsid -band 0xFF), (($Qsid -shr 8) -band 0xFF))) 0
    if ($r[0] -ne 0) {
        return $null
    }
    $width = 1
    if ($script:KcSettingWidths.ContainsKey($Type)) {
        $width = $script:KcSettingWidths[$Type]
    }
    return [long](ConvertFrom-KcLittleEndian $r 1 $width)
}

function Read-KcVialEntryCounts($Query) {
    $r = Invoke-KcQmk $Query ([byte[]](0xFE, 0x0D, 0x00)) 0
    return [pscustomobject]@{
        TapDance    = [int]$r[0]
        Combo       = [int]$r[1]
        KeyOverride = [int]$r[2]
        AltRepeat   = [int]$r[3]
        Features    = [int]$r[31]
    }
}

# タップダンス / コンボ / キーオーバーライド / 代替リピートの 1 件 (応答の [1..] が構造体)
function Read-KcVialEntry($Query, [int]$Op, [int]$Index) {
    $r = Invoke-KcQmk $Query ([byte[]](0xFE, 0x0D, $Op, $Index)) 0
    if ($r[0] -ne 0) {
        throw ('Vial のエントリ (種類 {0}、番号 {1}) を読めません (状態 {2})' -f $Op, $Index, $r[0])
    }
    return , $r
}

function ConvertFrom-KcVialTapDance([byte[]]$R) {
    return [pscustomobject]@{
        on_tap        = [int](ConvertFrom-KcLittleEndian $R 1 2)
        on_hold       = [int](ConvertFrom-KcLittleEndian $R 3 2)
        on_double_tap = [int](ConvertFrom-KcLittleEndian $R 5 2)
        on_tap_hold   = [int](ConvertFrom-KcLittleEndian $R 7 2)
        term          = [int](ConvertFrom-KcLittleEndian $R 9 2)
    }
}

function ConvertFrom-KcVialKeyOverride([byte[]]$R) {
    return [pscustomobject]@{
        trigger           = [int](ConvertFrom-KcLittleEndian $R 1 2)
        replacement       = [int](ConvertFrom-KcLittleEndian $R 3 2)
        layers            = [int](ConvertFrom-KcLittleEndian $R 5 2)
        trigger_mods      = [int]$R[7]
        negative_mod_mask = [int]$R[8]
        suppressed_mods   = [int]$R[9]
        options           = [int]$R[10]
    }
}

function ConvertFrom-KcVialCombo([byte[]]$R) {
    return [pscustomobject]@{
        input  = [int[]]@((ConvertFrom-KcLittleEndian $R 1 2), (ConvertFrom-KcLittleEndian $R 3 2),
            (ConvertFrom-KcLittleEndian $R 5 2), (ConvertFrom-KcLittleEndian $R 7 2))
        output = [int](ConvertFrom-KcLittleEndian $R 9 2)
    }
}

function ConvertFrom-KcVialAltRepeat([byte[]]$R) {
    return [pscustomobject]@{
        keycode      = [int](ConvertFrom-KcLittleEndian $R 1 2)
        alt_keycode  = [int](ConvertFrom-KcLittleEndian $R 3 2)
        allowed_mods = [int]$R[5]
        options      = [int]$R[6]
    }
}

# ---------------------------------------------------------------------------
# 比較
# ---------------------------------------------------------------------------

# 2 つの [レイヤー][行][列] を比べ、違うセルの説明の一覧を返す。
#   $Describe: { param($layer, $row, $col) "どこか" }、$Format: { param($value) "名前" }
#   (scriptblock は呼び出し元の変数を参照する。GetNewClosure() を使うとスクリプトの関数が見えなくなるので使わない)
function Compare-KcKeymapGrid($Expected, $Actual, [int]$Layers, [int]$Rows, [int]$Cols, [scriptblock]$Describe, [scriptblock]$Format) {
    $diffs = New-Object 'System.Collections.Generic.List[string]'
    for ($l = 0; $l -lt $Layers; $l++) {
        for ($r = 0; $r -lt $Rows; $r++) {
            for ($c = 0; $c -lt $Cols; $c++) {
                $e = [int]$Expected[$l][$r][$c]
                $a = [int]$Actual[$l][$r][$c]
                if ($e -ne $a) {
                    $diffs.Add(('{0}: 期待 {1} / 実際 {2}' -f (& $Describe $l $r $c), (& $Format $e), (& $Format $a)))
                }
            }
        }
    }
    return , $diffs.ToArray()
}

# キーマップの比較結果を記録する
function Add-KcKeymapResult($Results, [string]$Category, [string[]]$Diffs, [int]$Cells, [string]$Hint) {
    if ($Diffs.Count -eq 0) {
        [void](Add-KcResult -Results $Results -Category $Category -Item 'キーマップ' -Status PASS -Actual ('全 {0} セルが一致' -f $Cells))
    } else {
        [void](Add-KcResult -Results $Results -Category $Category -Item 'キーマップ' -Status FAIL `
                -Expected ('全 {0} セルが一致' -f $Cells) -Actual ('{0} セルが違う' -f $Diffs.Count) -Details $Diffs -Hint $Hint)
    }
}

# ---------------------------------------------------------------------------
# KQ-mini (Vial)
# ---------------------------------------------------------------------------

# KQ-mini の行列 (行, 列) → 「キー D (行 1 列 7)」のような説明 (行列は HID usage の並び)
function Get-KcKqCellName([int]$Row, [int]$Col, $Names) {
    $usage = -1
    if ($Row -eq 0) {
        $usage = 0xE0 + $Col
    } elseif ($Row -ge 1 -and $Row -le 28) {
        $usage = ($Row - 1) * 8 + $Col
    } elseif ($Row -eq 30) {
        $usage = 0xE8 + $Col
    }
    if ($usage -ge 0) {
        return ('{0} (行 {1} 列 {2})' -f (Format-KcQmkBasic $usage $Names), $Row, $Col)
    }
    return ('行 {0} 列 {1}' -f $Row, $Col)
}

function Invoke-KcKqMiniReadout {
    param(
        [Parameter(Mandatory = $true)] $Query,
        [Parameter(Mandatory = $true)] $Expected,
        [Parameter(Mandatory = $true)] $Common,
        [Parameter(Mandatory = $true)] $Results
    )
    $cat = 'KQ-mini'
    $v = $Expected.readout.vial
    $names = New-KcQmkNames $Common $Expected
    $layerNames = @{}
    foreach ($l in @($Expected.layers)) {
        $layerNames[[int]$l.index] = [string]$l.name
    }

    # Vial の ID (これを送ると、再起動するまで Vial モードになる)
    $id = Read-KcVialKeyboardId $Query
    $uidHex = (@($id.Uid) | ForEach-Object { '{0:X2}' -f $_ }) -join ''
    $expUid = (@($Expected.device.vial_uid) | ForEach-Object { '{0:X2}' -f $_ }) -join ''
    if ($uidHex -ne $expUid) {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'Vial の ID' -Status FAIL -Expected $expUid -Actual $uidHex `
                -Hint 'vial-qmk-kq-mini のファームではないようです。tools/flash-kq-mini.cmd で書き込み直してください')
        return
    }
    [void](Add-KcResult -Results $Results -Category $cat -Item 'Vial の ID' -Status PASS -Actual ('{0} (Vial プロトコル {1})' -f $uidHex, $id.Protocol))

    $lock = Read-KcVialUnlockStatus $Query
    if ($lock.InProgress -ne 0) {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'Vial のロック' -Status SKIP -Actual 'アンロックの途中' `
                -Hint 'Vial の操作中は読み出せません。KQ-mini を挿し直して (Vial を閉じて) から再実行してください')
        return
    }

    # キーマップ
    $layers = Read-KcViaLayerCount $Query
    $expLayers = [int]$v.layer_count
    if ($layers -ne $expLayers) {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'レイヤー数' -Status FAIL -Expected $expLayers -Actual $layers)
        return
    }
    $rows = [int]$v.rows
    $cols = [int]$v.cols
    $actual = Read-KcViaKeymap $Query $layers $rows $cols
    $describe = {
        param($l, $r, $c)
        $ln = ''
        if ($layerNames.ContainsKey($l)) { $ln = ' ' + $layerNames[$l] }
        'L{0}{1} / {2}' -f $l, $ln, (Get-KcKqCellName $r $c $names)
    }
    $format = { param($x) Format-KcQmkKeycode $x $names }
    $diffs = Compare-KcKeymapGrid $v.keymap $actual $layers $rows $cols $describe $format
    $hint = 'Vial で変更した内容が KQ-mini の EEPROM に残っています。Vial の「File → Load saved layout」で vial-qmk-kq-mini の KEYMAP.vil を読み込むか、tools/flash-kq-mini.cmd で書き込み直すと戻ります (同じファームの書き直しでは戻りません)'
    $mouseDiffs = @()
    foreach ($m in @($v.mouse_cells)) {
        for ($l = 0; $l -lt $layers; $l++) {
            if ([int]$v.keymap[$l][[int]$m.row][[int]$m.col] -ne [int]$actual[$l][[int]$m.row][[int]$m.col]) {
                $mouseDiffs += ('L{0} {1}' -f $l, $m.what)
            }
        }
    }
    if ($mouseDiffs.Count -gt 0) {
        $hint += "`nマウスの中継に使うセルが違います: " + ($mouseDiffs -join '、')
    }
    Add-KcKeymapResult $Results $cat $diffs ($layers * $rows * $cols) $hint

    # タップホールドなどの設定 (QMK settings)
    $types = @{}
    foreach ($s in @($Common.qmk_settings)) {
        $types[[int]$s.qsid] = [string]$s.type
    }
    $sdiffs = @()
    $sok = @()
    foreach ($s in @($v.settings)) {
        $val = Read-KcVialSetting $Query ([int]$s.qsid) ([string]$s.type)
        $label = '{0} (QSID {1})' -f $s.name, $s.qsid
        if ($null -eq $val) {
            $sdiffs += ('{0}: 読めません' -f $label)
        } elseif ([long]$val -ne [long]$s.value) {
            $sdiffs += ('{0}: 期待 {1} / 実際 {2}' -f $label, $s.value, $val)
        } else {
            $sok += ('{0}={1}' -f $s.name, $val)
        }
    }
    if ($sdiffs.Count -eq 0) {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'タップホールドの設定' -Status PASS -Actual ($sok -join ', '))
    } else {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'タップホールドの設定' -Status FAIL -Details $sdiffs `
                -Hint 'Vial の「QMK Settings」で変更した値が残っています。tapping term などを lism.vialmap.json の値に戻してください')
    }

    # タップダンス / キーオーバーライド / コンボ / 代替リピート
    $counts = Read-KcVialEntryCounts $Query
    $tdDiffs = @()
    $expTd = @{}
    foreach ($t in @($v.tap_dance.entries)) {
        $expTd[[int]$t.index] = $t
    }
    for ($i = 0; $i -lt $counts.TapDance; $i++) {
        $a = ConvertFrom-KcVialTapDance (Read-KcVialEntry $Query 0x01 $i)
        if ($expTd.ContainsKey($i)) {
            $e = $expTd[$i]
            foreach ($f in @('on_tap', 'on_hold', 'on_double_tap', 'on_tap_hold', 'term')) {
                if ([int]$e.$f -ne [int]$a.$f) {
                    $ev = [int]$e.$f
                    $av = [int]$a.$f
                    if ($f -ne 'term') {
                        $ev = Format-KcQmkKeycode $ev $names
                        $av = Format-KcQmkKeycode $av $names
                    }
                    $tdDiffs += ('TD({0}) {1} の {2}: 期待 {3} / 実際 {4}' -f $i, $e.name, $f, $ev, $av)
                }
            }
        } elseif (($a.on_tap -bor $a.on_hold -bor $a.on_double_tap -bor $a.on_tap_hold) -ne 0) {
            $tdDiffs += ('TD({0}): 期待 なし / 実際 {1}' -f $i, (Format-KcQmkKeycode $a.on_tap $names))
        }
    }
    Add-KcEntryResult $Results $cat 'タップダンス' $tdDiffs ('{0} 件' -f @($v.tap_dance.entries).Count)

    $koDiffs = @()
    $expKo = @{}
    foreach ($k in @($v.key_override.entries)) {
        $expKo[[int]$k.index] = $k
    }
    for ($i = 0; $i -lt $counts.KeyOverride; $i++) {
        $a = ConvertFrom-KcVialKeyOverride (Read-KcVialEntry $Query 0x05 $i)
        if ($expKo.ContainsKey($i)) {
            $e = $expKo[$i]
            foreach ($f in @('trigger', 'replacement', 'layers', 'trigger_mods', 'negative_mod_mask', 'suppressed_mods', 'options')) {
                if ([int]$e.$f -ne [int]$a.$f) {
                    $ev = '0x{0:X2}' -f [int]$e.$f
                    $av = '0x{0:X2}' -f [int]$a.$f
                    if ($f -eq 'trigger' -or $f -eq 'replacement') {
                        $ev = Format-KcQmkKeycode $e.$f $names
                        $av = Format-KcQmkKeycode $a.$f $names
                    }
                    $koDiffs += ('{0} ({1}) の {2}: 期待 {3} / 実際 {4}' -f $i, $e.name, $f, $ev, $av)
                }
            }
        } elseif ($a.trigger -ne 0 -or ($a.options -band 0x80) -ne 0) {
            $koDiffs += ('{0}: 期待 なし / 実際 {1} → {2}' -f $i, (Format-KcQmkKeycode $a.trigger $names), (Format-KcQmkKeycode $a.replacement $names))
        }
    }
    Add-KcEntryResult $Results $cat 'キーオーバーライド' $koDiffs ('{0} 件' -f @($v.key_override.entries).Count)

    $comboDiffs = @()
    for ($i = 0; $i -lt $counts.Combo; $i++) {
        $a = ConvertFrom-KcVialCombo (Read-KcVialEntry $Query 0x03 $i)
        $used = $a.output -ne 0
        foreach ($x in $a.input) {
            if ($x -ne 0) { $used = $true }
        }
        if ($used) {
            $comboDiffs += ('{0}: 期待 なし / 実際 {1} → {2}' -f $i, ((@($a.input) | Where-Object { $_ -ne 0 } | ForEach-Object { Format-KcQmkKeycode $_ $names }) -join ' + '), (Format-KcQmkKeycode $a.output $names))
        }
    }
    Add-KcEntryResult $Results $cat 'コンボ' $comboDiffs 'なし'

    $arDiffs = @()
    for ($i = 0; $i -lt $counts.AltRepeat; $i++) {
        $a = ConvertFrom-KcVialAltRepeat (Read-KcVialEntry $Query 0x07 $i)
        if ($a.keycode -ne 0 -or $a.alt_keycode -ne 0) {
            $arDiffs += ('{0}: 期待 なし / 実際 {1} → {2}' -f $i, (Format-KcQmkKeycode $a.keycode $names), (Format-KcQmkKeycode $a.alt_keycode $names))
        }
    }
    Add-KcEntryResult $Results $cat '代替リピート' $arDiffs 'なし'

    # マクロ
    $m = Read-KcViaMacros $Query
    $actualMacros = Split-KcMacroBuffer $m.Bytes $m.Count
    $mDiffs = @()
    foreach ($e in @($v.macro.entries)) {
        $i = [int]$e.index
        $expBytes = [byte[]]@()
        if ($e.hex) {
            $expBytes = [byte[]]@($e.hex -split ' ' | ForEach-Object { [Convert]::ToByte($_, 16) })
        }
        $act = [byte[]]@()
        if ($i -lt $actualMacros.Count) {
            $act = [byte[]]$actualMacros[$i]
        }
        $ea = (ConvertFrom-KcMacroBytes $expBytes) -join ' '
        $aa = (ConvertFrom-KcMacroBytes $act) -join ' '
        if ($ea -ne $aa) {
            $mDiffs += ('M{0} {1}: 期待 [{2}] / 実際 [{3}]' -f $i, $e.name, $ea, $aa)
        }
    }
    Add-KcEntryResult $Results $cat 'マクロ' $mDiffs ('{0} 件' -f @($v.macro.entries | Where-Object { $_.hex }).Count)
}

function Add-KcEntryResult($Results, [string]$Category, [string]$Item, [string[]]$Diffs, [string]$Summary) {
    if ($Diffs.Count -eq 0) {
        [void](Add-KcResult -Results $Results -Category $Category -Item $Item -Status PASS -Actual ('{0} (一致)' -f $Summary))
    } else {
        [void](Add-KcResult -Results $Results -Category $Category -Item $Item -Status FAIL -Expected $Summary -Actual ('{0} 件が違う' -f $Diffs.Count) `
                -Details $Diffs -Hint 'Vial で変更した内容が残っています。KEYMAP.vil を読み込み直すか、tools/flash-kq-mini.cmd で書き込み直してください')
    }
}

# ---------------------------------------------------------------------------
# Keyball39 (VIA、PC に直結したときだけ)
# ---------------------------------------------------------------------------

function Invoke-KcKeyballReadout {
    param(
        [Parameter(Mandatory = $true)] $Query,
        [Parameter(Mandatory = $true)] $Expected,
        [Parameter(Mandatory = $true)] $Common,
        [Parameter(Mandatory = $true)] $Results
    )
    $cat = 'Keyball39'
    $v = $Expected.readout.via
    $names = New-KcQmkNames $Common $Expected

    $protocol = Read-KcViaProtocol $Query
    $uptime = Read-KcViaUptime $Query
    $status = 'PASS'
    if ($protocol -lt [int]$v.protocol_min) {
        $status = 'WARN'
    }
    [void](Add-KcResult -Results $Results -Category $cat -Item 'VIA' -Status $status -Actual ('プロトコル 0x{0:X4}、起動から {1:F1} 秒' -f $protocol, ($uptime / 1000.0)))

    # キーマップ
    $layers = Read-KcViaLayerCount $Query
    if ($layers -ne [int]$v.layer_count) {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'レイヤー数' -Status FAIL -Expected $v.layer_count -Actual $layers)
    } else {
        $rows = [int]$v.rows
        $cols = [int]$v.cols
        $actual = Read-KcViaKeymap $Query $layers $rows $cols
        $where = @{}
        foreach ($k in @($Expected.physical.keys)) {
            $where['{0},{1}' -f $k.matrix[0], $k.matrix[1]] = $k
        }
        $layerNames = @{}
        foreach ($l in @($Expected.layers)) {
            $layerNames[[int]$l.index] = [string]$l.name
        }
        $describe = {
            param($l, $r, $c)
            $key = '{0},{1}' -f $r, $c
            $pos = '行 {0} 列 {1}' -f $r, $c
            if ($where.ContainsKey($key)) {
                $k = $where[$key]
                $pos = '{0} {1} ({2})' -f $k.label, $k.legend, $pos
            }
            'L{0} {1} / {2}' -f $l, $layerNames[$l], $pos
        }
        $format = { param($x) Format-KcQmkKeycode $x $names }
        $diffs = Compare-KcKeymapGrid $v.keymap $actual $layers $rows $cols $describe $format
        Add-KcKeymapResult $Results $cat $diffs ($layers * $rows * $cols) `
            'VIA で変更した内容が EEPROM に残っています。VIA でキーを戻すか、tools/flash-keyball.cmd で書き込み直してください (同じ日にビルドしたファームでは戻らないことがあります)'
    }

    # ボールの検出 (layout options の Ball availability)
    $layout = Read-KcViaLayoutOptions $Query
    $ballNames = @('None', 'Right', 'Left', 'Dual')
    $ball = $ballNames[[int]($layout -band 3)]
    $expBall = [string]$v.layout_options.ball
    if ($ball -eq $expBall) {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'Ball availability' -Status PASS -Actual $ball)
    } elseif ($ball -eq 'None' -and $uptime -lt 6000) {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'Ball availability' -Status WARN -Expected $expBall -Actual $ball `
                -Hint '起動直後のため、左右の問い合わせが終わっていない可能性があります。数秒後に再実行してください')
    } elseif ($ball -eq 'None') {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'Ball availability' -Status FAIL -Expected $expBall -Actual $ball `
                -Hint 'トラックボールを認識していません。README.md の「Keyball39 のトラックボールが動かない場合」と tools/keyball-check.cmd で切り分けてください')
    } else {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'Ball availability' -Status WARN -Expected $expBall -Actual $ball)
    }

    # Keyball のトラックボール設定 (新しいファームのコマンド 08 00 01)
    $st = Read-KcKeyballStatus $Query
    if ($null -eq $st) {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'トラックボールの設定 (CPI / スクロール / AML)' -Status SKIP `
                -Actual 'このファームでは読めません' -Hint 'tools/flash-keyball.cmd で最新のファームを書き込むと読めるようになります')
    } else {
        Add-KcKeyballStatusResults $Results $cat $st $v.status
        $date = Read-KcKeyballBuildDate $Query
        if ($date) {
            [void](Add-KcResult -Results $Results -Category $cat -Item 'ファームのビルド日時' -Status INFO -Actual $date)
        }
    }

    # マクロ (via キーマップでは使わない)
    $m = Read-KcViaMacros $Query
    $used = @(Split-KcMacroBuffer $m.Bytes $m.Count | Where-Object { @($_).Count -gt 0 })
    if ($used.Count -eq 0) {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'マクロ' -Status PASS -Actual 'なし (一致)')
    } else {
        [void](Add-KcResult -Results $Results -Category $cat -Item 'マクロ' -Status WARN -Expected 'なし' -Actual ('{0} 件' -f $used.Count) `
                -Hint 'VIA でマクロが登録されています (キーマップから呼ばれていなければ動作には影響しません)')
    }

    $rgb = Read-KcViaRgb $Query $protocol
    if ($null -ne $rgb) {
        $text = '消灯'
        if ($rgb.Effect -ne 0) {
            $text = '点灯 (エフェクト {0}、明るさ {1}/255、色相 {2}、彩度 {3})' -f $rgb.Effect, $rgb.Brightness, $rgb.Hue, $rgb.Saturation
        }
        [void](Add-KcResult -Results $Results -Category $cat -Item 'RGB ライティング' -Status INFO -Actual $text)
    }
}

function Add-KcKeyballStatusResults($Results, [string]$Category, $Status, $Exp) {
    $sides = @()
    if ($Status.IsLeft) { $sides += 'USB 側: 左' } else { $sides += 'USB 側: 右' }
    if ($Status.ThisHaveBall) { $sides += 'USB 側にボールあり' }
    if ($Status.ThatHaveBall) { $sides += '反対側にボールあり' }
    if (-not $Status.ThatEnable) { $sides += '反対側と通信できていない' }
    [void](Add-KcResult -Results $Results -Category $Category -Item 'ボールと左右' -Status INFO -Actual ($sides -join '、'))

    $checks = @(
        @('CPI', ('{0} ({1} CPI)' -f $Exp.cpi, ([int]$Exp.cpi * 100)), $Status.Cpi, ('{0} ({1} CPI)' -f $Status.Cpi, ($Status.Cpi * 100)), ([int]$Exp.cpi -eq $Status.Cpi),
            'EEPROM に保存された古い CPI が残っています (ファームを書き直しても戻りません)。Bootmagic (左手側は Q、右手側は P を押しながら USB を挿す) で初期化してください'),
        @('スクロールの倍率', ('1/{0}' -f [math]::Pow(2, [int]$Exp.scroll_div - 1)), $Status.ScrollDiv, ('1/{0}' -f [math]::Pow(2, $Status.ScrollDiv - 1)), ([int]$Exp.scroll_div -eq $Status.ScrollDiv),
            'EEPROM に保存された古いスクロールの倍率が残っています。Bootmagic (左手側は Q、右手側は P を押しながら USB を挿す) で初期化してください'),
        @('スクロールの方向の固定', 'なし (FREE)', $Status.ScrollSnap, ('{0}' -f @('縦のみ', '横のみ', 'なし (FREE)')[[math]::Min($Status.ScrollSnap, 2)]), ([int]$Exp.scroll_snap -eq $Status.ScrollSnap),
            'keymap.c の keyboard_post_init_user が効いていません。最新のファームを書き込んでください'),
        @('AML (自動マウスレイヤー)', '有効', $Status.AmlEnabled, $(if ($Status.AmlEnabled) { '有効' } else { '無効' }), ([bool]$Exp.aml_enabled -eq $Status.AmlEnabled),
            'AML が無効になっています。最新のファームを書き込んでください'),
        @('AML のレイヤー', [string]$Exp.aml_layer, $Status.AmlLayer, [string]$Status.AmlLayer, ([int]$Exp.aml_layer -eq $Status.AmlLayer), ''),
        @('AML のタイムアウト', ('{0} ms' -f $Exp.aml_timeout), $Status.AmlTimeout, ('{0} ms' -f $Status.AmlTimeout), ([int]$Exp.aml_timeout -eq $Status.AmlTimeout),
            'AML のタイムアウトが LisM (10 秒) と違います'),
        @('AML の発動条件 (キー入力からの待ち)', ('{0} ms' -f $Exp.aml_delay), $Status.AmlDelay, ('{0} ms' -f $Status.AmlDelay), ([int]$Exp.aml_delay -eq $Status.AmlDelay), ''),
        @('スクロールレイヤー', [string]$Exp.scroll_layer, $Status.ScrollLayer, [string]$Status.ScrollLayer, ([int]$Exp.scroll_layer -eq $Status.ScrollLayer), '')
    )
    foreach ($c in $checks) {
        if ($c[4]) {
            [void](Add-KcResult -Results $Results -Category $Category -Item $c[0] -Status PASS -Actual $c[3])
        } else {
            [void](Add-KcResult -Results $Results -Category $Category -Item $c[0] -Status FAIL -Expected $c[1] -Actual $c[3] -Hint $c[5])
        }
    }
}
