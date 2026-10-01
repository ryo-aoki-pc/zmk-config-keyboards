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

- 対象: LisM / AroundFortyRB / KUKEY42 / Pyuron

### 共通基盤

| 項目 | 内容 |
| --- | --- |
| ZMK | zmkfirmware **v0.3.0** を `config/west.yml` で固定 |
| ドキュメント生成 | `tools/keymap-docgen` submodule (全リポジトリ同一コミット) による KEYMAP.html / KEYMAP.xlsx 自動生成 |
| ワークフロー | build.yml / keymap-docs.yml / release.yml を共通化 (keymap-docs.yml はキーマップのパス以外同一) |
| ファイル構成 | `.conf` は `boards/shields/<NAME>/`、ハード・役割は `Kconfig.defconfig`、Studio とセントラル役割は `build.yaml` の `cmake-args` |
| アーティファクト | 全エントリに `artifact-name` を付与し、Studio 版 / 非 Studio 版の両方を生成 |
| ローカルビルド | `Makefile` + `scripts/` + `.devcontainer/` (`make` / `make single` など) |
| タップホールド | `&mt` / `&lt` = tapping-term 150 / quick-tap 0 / flavor balanced |
| AML | `&zip_temp_layer 8 10000`、`require-prior-idle-ms 200`、除外位置 D / K、マウスクリックでタイマー延長 |
| スクロール | `zip_scroll_scaler 1 16` (1/16) |

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

### その他 ZMK 関連

| リポジトリ | 追跡ブランチ | 用途 |
| --- | --- | --- |
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

## ファームウェアの書き込み (Windows)

対象: LisM / AroundFortyRB / KUKEY42 / Pyuron (いずれも Seeed XIAO nRF52840 + Adafruit nRF52 UF2 ブートローダ)

### エクスプローラでのコピー時に「予期しないエラー」が出る場合

`.uf2` をブートローダのドライブへエクスプローラでコピーすると、次のエラーが出ることがあります。

> 予期しないエラーが発生したため、ファイルをコピーできません。
> エラー 0x800701B1: 存在しないデバイスを指定しました。

これはファームウェアの不具合ではありません。ブートローダは `.uf2` の最後のブロックを受け取った時点で
書き込みを確定し、すぐに再起動して USB ドライブを切り離します。エクスプローラはデータをコピーした後に
コピー先ファイルの属性やタイムスタンプを更新しようとするため、既に消えたドライブへの操作となってエラーになります。
書き込み自体は完了しています。エラーになるかどうかは Windows 側の書き込み順に依存するため、
Windows のバージョンや環境によって出たり出なかったりします
(参考: [adafruit/Adafruit_nRF52_Bootloader#120](https://github.com/adafruit/Adafruit_nRF52_Bootloader/issues/120)、
[zephyrproject-rtos/zephyr#107165](https://github.com/zephyrproject-rtos/zephyr/issues/107165))。

| 結果 | 見分け方 |
| --- | --- |
| 成功 | エラーの後にドライブが消え、キーボードが新しいファームウェアで起動する (ダイアログは閉じてよい) |
| 失敗 | ドライブが消えずに残る、またはブートローダのドライブが再び現れる |

### 書き込みスクリプト (`tools/flash-uf2.cmd`)

エラーダイアログを出さずに書き込み、成否をはっきり表示するスクリプトです。

1. `.uf2` ファイルを `tools/flash-uf2.cmd` にドラッグ＆ドロップする
2. 「ブートローダのドライブを待っています...」と表示されたら、リセットボタンを素早く 2 回押す
   (または BT レイヤーの `&bootloader` キーを押す)。既にドライブが出ていればすぐに書き込みが始まります
3. 「成功」と表示されれば完了

コマンドラインから実行する場合 (ドライブは省略すると自動検出):

```powershell
powershell -ExecutionPolicy Bypass -File tools\flash-uf2.ps1 <ファイル.uf2> [E:]
```

スクリプトが行うこと:

- 書き込む前に `.uf2` を検証する (UF2 形式か / nRF52840 用か / 書き込み先がアプリケーション領域
  `0x27000`-`0xF4000` に収まるか / ブロックの欠けが無いか)。別ボード用のファイルや壊れたダウンロードはここで弾く
- `INFO_UF2.TXT` があるドライブを自動で探し、ブートローダの情報 (Model / Board-ID など) を表示する
- ファイルサイズを先に確保してからデータだけを書き込み、書き込み完了直後の切断は想定どおりの動作として扱う
- ドライブが消えたこと (= ブートローダが全ブロックを受け取って再起動したこと) を確認して成功と判定する

### 左右の役割や BLE 設定を変えた後の書き込み順

セントラル役割や Studio の指定方法を変えたとき
([ryo-aoki-pc/zmk-config-keyboards#10](https://github.com/ryo-aoki-pc/zmk-config-keyboards/pull/10) の統一後など) は、
古い設定が残らないように次の順で書き込みます。

1. `settings_reset-seeeduino_xiao_ble-zmk.uf2` を左右両方に書き込む
2. 左 (`*_left_peripheral*.uf2`) と右 (`*_right_central*.uf2`) のファームウェアをそれぞれ書き込む
3. 設定リセットでペアリング情報も消えるため、PC の Bluetooth 設定から古いキーボードを削除して再ペアリングする

## Keyball39 のトラックボールが動かない場合

キーは入力できるのにトラックボールだけ動かないときの切り分け手順です。

Keyball のファームウェアは、起動時に左右それぞれがトラックボールのセンサー (PMW3360) を検出し、
USB を挿した側が反対側に問い合わせて、どちらにボールがあるかを確定します
(結果は VIA の layout options「Ball availability」に保存されます)。
センサーが応答しないとボールが無いものとして扱われ、マウスの動きを送りません。
[keyball](https://github.com/ryo-aoki-pc/keyball) の `lib/keyball` は、起動後もボールが見つかるまで
2 秒ごとに検出と問い合わせをやり直します。接触が回復したときや、KQ Mini 経由で反対側の起動が遅れたときも、
挿し直さずに使えるようになります。

### 切り分け

1. OLED の `Ball:` 行を見る。ボールを転がしても数値が 0 のままなら、Keyball 本体がボールの動きを受け取れていない
   (KQ Mini や PC 側の問題ではない)
2. Keyball を KQ Mini を通さずに PC に直接つなぎ、`tools/keyball-check.cmd` を実行する。
   VIA の読み取りコマンドだけを使い (設定は書き換えない)、Ball availability・起動からの経過時間・RGB の状態を表示する。
   `powershell -ExecutionPolicy Bypass -File tools\keyball-check.ps1 -Watch` で実行すると、1 秒ごとの変化を表示し続ける

   | Ball availability | 意味 |
   | --- | --- |
   | `Right` / `Left` / `Dual` | その側のボールを認識している |
   | `None` | どちらのボールも認識していない |

3. `None` のときは、USB をボールがある側の半分に挿し替えてもう一度実行する
   (TRRS ケーブルは通電中に抜き差ししない)
   - ボール側に挿しても `None`: その半分のセンサーが応答していない → 下の「ハードの点検」へ
   - ボール側に挿すと認識する: センサーは正常。左右の通信 (TRRS ケーブル) や起動タイミングを確認する
4. PC 直結では動くのに KQ Mini 経由でだけ動かない場合は、ボールを転がしたときに KQ Mini の LED が点滅するか
   (KQ Mini が Keyball からレポートを受け取っているか) を見る。
   さらに詳しく見るときは、KQ Mini の仮想 COM ポートを開いて `debug` と入力し、
   ボールを転がして `Mouse report` の行が出るかを確認する (もう一度 `debug` と入力すると止まる)。
   入力補完により `df` だけで `dfu` (ブートローダの起動) が実行されるため、コマンド名は最後まで入力する。
   また、Vial で KQ Mini の `KC_MS_LEFT` / `KC_MS_UP` の位置の割り当てを変えると、
   X / Y 方向の移動はスクロールに変換される (ホイールキーを割り当てた場合) か、転送されなくなる

### ハードの点検 (ボールがある側)

ボール基板は 7 ピンの L 字コンスルーに、Pro Micro は 12 ピンのコンスルーに差し込んであるだけなので、
取り扱いの拍子に接触不良になることがあります。USB を抜いてから点検します
(写真付きの手順は [Keyball39 ビルドガイド](https://github.com/ryo-aoki-pc/keyball/blob/custom/keyball39/doc/rev1/buildguide_jp.md) の 4-2 / 8-1 / 8-3 章)。

- ボールを外し、本体裏の頭が平らな M1.7 ネジ 2 本を外してボールケースを外す。
  ボール基板を L 字コンスルーから抜いてピンの曲がり・折れを確認し、垂直に差し直す。
  メイン基板とボール基板の間に隙間が無いことを確認して組み戻す
- Pro Micro がコンスルーに傾かず奥まで刺さっているか
- L 字コンスルー近くの信号線ジャンパ 4 箇所 (裏面のはんだブリッジ) に割れが無いか
- LED を実装している場合は、VIA で消灯・保存してから挿し直すと、電源 (ハブ経由の給電など) の不足が原因かを切り分けられる。
  LED の設定は左右の Pro Micro に別々に保存され、USB を挿した側の設定が左右両方の LED に使われる
  (keyball39 via のファームは、新しいビルドの初回起動時に `keymaps/via/config.h` の `RGBLIGHT_DEFAULT_*` を
  左右それぞれに保存するので、左右に同じファームを書けば揃う)

点検後、ボール側に USB を挿して `tools/keyball-check.cmd` を実行し、Ball availability がボールの側
(`Right` など) になれば復旧です。それでも `None` のままなら、ボール基板 (センサーのはんだ付けやセンサー本体) の不良が考えられます。
