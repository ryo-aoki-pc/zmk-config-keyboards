# zmk-config-keyboards

各キーボードのファームウェア関連リポジトリ (ZMK / QMK) を git submodule として集約したリポジトリです。

## キーマップ・設定の統一 (LisM 基準)

[zmk-config-LisM](https://github.com/ryo-aoki-pc/zmk-config-LisM) を基準として、各キーボードのキーマップ・west.yml・conf・CI を統一しています。

### 統一済みのレイヤー構成 (10 レイヤー)

| 番号 | 別名 | レイヤーノード | 役割 |
| --- | --- | --- | --- |
| 0 | BASE | BASE_QWERTY | 通常入力 (QWERTY) |
| 1 | SYM | NUM_SYMBOL | 数字・記号 |
| 2 | VIM_BASE | VIM_NORMAL_BASE | BASE 層に対応する Vim ノーマル |
| 3 | VIM_SYM | VIM_NORMAL_SYM | SYM 層に対応する Vim ノーマル |
| 4 | VIM_VISUAL | VIM_VISUAL_BASE | BASE 層に対応する Vim ビジュアル |
| 5 | VIM_VIS_SYM | VIM_VISUAL_SYM | SYM 層に対応する Vim ビジュアル |
| 6 | FUNC | FUNCTION | ファンクションキー |
| 7 | BT | BLUETOOTH | Bluetooth／出力切替 |
| 8 | MOUS | MOUSE_MOVE | マウス移動 (AML・最上位) |
| 9 | SCRL | MOUSE_SCROLL | スクロール／クリック |

- 対象: LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa / torabo-tsuki-lp
- 共通基盤: zmk = zmkfirmware **v0.3.0**、`tools/keymap-docgen` submodule による KEYMAP.html / KEYMAP.xlsx 自動生成、build.yml / keymap-docs.yml / release.yml の共通ワークフロー

### Keyboard Quantizer Mini + Keyball39 の役割分担

keyball39 (via) は LisM BASE 配列の素の HID コードだけを送り、レイヤー・MT/LT・タップホールド設定
(`&mt` / `&lt` の tapping-term / quick-tap / flavor) は vial-qmk-kq-mini 側の EEPROM デフォルト
(`zmk_to_vial.py` で `lism.keymap` + `lism.vialmap.json` から生成) が担当します。
Quantizer に無いマウスレイヤー (MOUSE_MOVE / MOUSE_SCROLL) と AML の除外キー・タイムアウト・
require-prior-idle は keyball39 本体側で LisM の `trackball.overlay` / `&zip_temp_layer` 設定を再現しています。

## Submodules

### キーボード設定 (zmk-config)

| リポジトリ | 追跡ブランチ |
| --- | --- |
| [zmk-config-Pyuron](https://github.com/ryo-aoki-pc/zmk-config-Pyuron) | `custom` |
| [zmk-config-LisM](https://github.com/ryo-aoki-pc/zmk-config-LisM) | `custom` |
| [zmk-config-KUKEY42](https://github.com/ryo-aoki-pc/zmk-config-KUKEY42) | `custom` |
| [zmk-config-AroundFortyRB](https://github.com/ryo-aoki-pc/zmk-config-AroundFortyRB) | `custom` |
| [zmk-config-roBa](https://github.com/ryo-aoki-pc/zmk-config-roBa) | `custom` |

### その他 ZMK 関連

| リポジトリ | 追跡ブランチ | 用途 |
| --- | --- | --- |
| [zmk-keyboard-torabo-tsuki-lp](https://github.com/ryo-aoki-pc/zmk-keyboard-torabo-tsuki-lp) | `custom` | キーボード定義 |
| [zmk-keymap-docgen](https://github.com/ryo-aoki-pc/zmk-keymap-docgen) | `main` | キーマップドキュメント生成ツール |

### QMK/Vial 関連

| リポジトリ | 追跡ブランチ | 用途 |
| --- | --- | --- |
| [vial-qmk-kq-mini](https://github.com/ryo-aoki-pc/vial-qmk-kq-mini) | `custom` | KQ Mini 用 Vial (QMK) ファームウェア。LisM 基準のキーマップ (zmk_to_vial.py で変換) とタップホールド設定 (tapping term 150 / balanced / quick-tap 0) を EEPROM デフォルトとして同梱 |
| [keyball](https://github.com/ryo-aoki-pc/keyball) | `custom` | Keyball 用 QMK ファームウェア。KQ Mini 併用前提の LisM 基準ベース配列 (keyball39 via)。AML の発動条件・タイムアウト・スクロール速度も LisM のトラックボール設定に合わせる |

## 使い方

### クローン

```bash
git clone --recurse-submodules https://github.com/ryo-aoki-pc/zmk-config-keyboards.git
```

すでにクローン済みの場合:

```bash
git submodule update --init --recursive
```

### submodule を最新に更新

各 submodule を追跡ブランチの最新コミットに更新します:

```bash
git submodule update --remote
git add .
git commit -m "Update submodules"
```
