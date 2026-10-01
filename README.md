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
| AML | `&zip_temp_layer 8 10000`、`require-prior-idle-ms 200`、除外位置 D / K と修飾キーの位置 (A / - / Z / / / Win / Alt)、マウスクリックでタイマー延長 |
| マウスレイヤーの修飾キー | MOUSE_MOVE / MOUSE_SCROLL の A / - / Z / / は Ctrl / Shift、Win / Alt の位置は Win / Alt。AML に入ってから Shift + クリック・Ctrl + ホイールなどを押せる |
| スクロール | `zip_scroll_scaler 1 16` (1/16) |

### Keyboard Quantizer Mini + Keyball39 の役割分担

keyball39 (via) は LisM BASE 配列の素の HID コードだけを送り、レイヤー・MT/LT・タップホールド設定
(`&mt` / `&lt` の tapping-term / quick-tap / flavor) は vial-qmk-kq-mini 側の EEPROM デフォルト
(`zmk_to_vial.py` で `lism.keymap` + `lism.vialmap.json` から生成) が担当します。
Quantizer に無いマウスレイヤー (MOUSE_MOVE / MOUSE_SCROLL) と AML の除外キー・タイムアウト・
require-prior-idle は keyball39 本体側で LisM の `trackball.overlay` / `&zip_temp_layer` 設定を再現しています。

- マウスレイヤーの修飾キー: keyball39 は AML / スクロールレイヤーで、KQ-mini が mod-tap にする位置
  (A / - / Z / /) とベースの Win / Alt の位置から素の修飾キー (`KC_LCTL` / `KC_RCTL` / `KC_LSFT` /
  `KC_RSFT` / `KC_LGUI` / `KC_LALT`) を送ります。KQ-mini はそれをそのまま素通しします
- マウスボタン: KQ-mini はマウスボタンを自身のキーマップ経由で送ります。ボタンを押したままキーを押したり
  離したりしても、ボタンは押されたままです (ドラッグ中に Ctrl / Shift を押してもドロップされない)

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

`tools/` の書き込みスクリプトを使います。ファイルの検証から成否の判定まで、スクリプトが行います。

| キーボード | マイコン / ブートローダ | ファイル | スクリプト |
| --- | --- | --- | --- |
| LisM / AroundFortyRB / KUKEY42 / Pyuron | Seeed XIAO nRF52840 / Adafruit nRF52 UF2 | `.uf2` | `tools/flash-zmk.cmd` (ダブルクリック)、または `tools/flash-uf2.cmd` (ファイルをドロップ) |
| Keyboard Quantizer Mini | RP2040 / ROM ブートローダ (`RPI-RP2` ドライブ) | `.uf2` | `tools/flash-kq-mini.cmd` (ダブルクリック) |
| Keyball39 | Pro Micro (ATmega32U4) / caterina | `.hex` | `tools/flash-keyball.cmd` (ダブルクリック) |

### Keyboard Quantizer Mini (`tools/flash-kq-mini.cmd`)

1. KQ-mini を PC につないだまま、`tools/flash-kq-mini.cmd` をダブルクリックする
2. スクリプトが自動で次の処理を行う
   - [最新のファームウェア](#最新ファームウェアの取得元-firmware-latest-リリース) をダウンロードする
   - KQ-mini をブートローダに切り替える (KQ-mini のシリアルポートに `dfu` コマンドを送る)
   - ファームウェアを書き込む
3. 「成功」と表示されれば完了。KQ-mini の LED が点灯して入力できるようになるまで、数十秒かかることがある

- 自動で切り替わらないとき: KQ-mini の FUNC レイヤーの `QK_BOOT` キーを押す。スクリプトはそのまま `RPI-RP2` ドライブが現れるのを待つ
- キーマップ: LisM 基準のキーマップとタップホールド設定は、書き込み後の初回起動時に EEPROM へ自動で適用される (Vial での読み込みは不要)
- 手元の `.uf2` を書き込むとき: そのファイルを `tools/flash-kq-mini.cmd` にドラッグ＆ドロップする

### Keyball39 (`tools/flash-keyball.cmd`)

Keyball は KQ-mini 経由では書き込めません (KQ-mini はキー入力だけを中継するため)。書き込むときは PC に直接つなぎます。

1. `tools/flash-keyball.cmd` をダブルクリックする。次の 2 つを自動でダウンロードする
   - [最新のファームウェア](#最新ファームウェアの取得元-firmware-latest-リリース)
   - avrdude (初回のみ)。公式の Windows 版 v8.3 を SHA256 で確認してから使う
2. 「1 / 2 台目」と表示されたら、片側を KQ-mini から外して USB ケーブルで PC に直接つなぎ、ブートローダを起動する。方法は次のどちらか
   - リセットスイッチを押す。認識されなければ素早く 2 回押す
   - 左手側は `Q`、右手側は `P` を押したまま USB ケーブルを挿す (Bootmagic)
3. COM ポートが現れるとすぐに書き込まれる。「成功」と表示されたら、もう片側も同じように書き込む
4. 「完了」と表示されたら、Keyball を KQ-mini に接続し直す

補足:

- **Bootmagic**
  - EEPROM も初期化されるため、CPI などの Keyball の設定は既定値に戻る
  - 右手側の `P` が使えるのは、[ryo-aoki-pc/keyball#10](https://github.com/ryo-aoki-pc/keyball/pull/10) 以降のファームウェアから
- **書き込みに失敗したとき**: caterina ブートローダは約 8 秒で終了する。失敗したらもう一度リセットスイッチを押す (1 台につき 3 回まで再試行する)
- **手元の `.hex` を書き込むとき**: そのファイルを `tools/flash-keyball.cmd` にドラッグ＆ドロップする

コマンドラインから実行する場合 (`-Count 1` で片側だけ書き込む、`-Avrdude` で手元の avrdude を使う):

```powershell
powershell -ExecutionPolicy Bypass -File tools\flash-keyball.ps1 [<ファイル.hex>] [-Count 1] [-Avrdude <avrdude.exe>]
```

### 最新ファームウェアの取得元 (`firmware-latest` リリース)

[keyball](https://github.com/ryo-aoki-pc/keyball)、[vial-qmk-kq-mini](https://github.com/ryo-aoki-pc/vial-qmk-kq-mini)、ZMK の 4 リポジトリの CI は、custom ブランチをビルドするたびに次のことを行います。

- 固定タグ `firmware-latest` のプレリリースを作り直す
- ファームウェアと `BUILD_INFO.txt` (コミット・ビルド日時) を置く

スクリプトはここからダウンロードします。

| キーボード | ダウンロード URL |
| --- | --- |
| Keyball39 | `https://github.com/ryo-aoki-pc/keyball/releases/download/firmware-latest/keyball_keyball39_via.hex` |
| Keyboard Quantizer Mini | `https://github.com/ryo-aoki-pc/vial-qmk-kq-mini/releases/download/firmware-latest/sekigon_keyboard_quantizer_mini_vial.uf2` |
| LisM | `https://github.com/ryo-aoki-pc/zmk-config-LisM/releases/download/firmware-latest/<artifact-name>.uf2` |
| AroundFortyRB | `https://github.com/ryo-aoki-pc/zmk-config-AroundFortyRB/releases/download/firmware-latest/<artifact-name>.uf2` |
| KUKEY42 | `https://github.com/ryo-aoki-pc/zmk-config-KUKEY42/releases/download/firmware-latest/<artifact-name>.uf2` |
| Pyuron | `https://github.com/ryo-aoki-pc/zmk-config-Pyuron/releases/download/firmware-latest/<artifact-name>.uf2` |

ZMK の `<artifact-name>` は各リポジトリの `build.yaml` のもので、全エントリ (左右・Studio 版・設定リセット) が置かれます。

- 公開リポジトリのリリースなので、ログインや gh CLI は不要
- Actions の Artifacts と違い、90 日で期限切れにならない
- 書き込まれるのは custom ブランチの最新ビルド。このリポジトリが submodule で参照しているコミットとは限らない
- ダウンロードしたファイルと avrdude は `tools/.cache/` に保存される (git の管理外)

### ZMK キーボード (`tools/flash-zmk.cmd` / `tools/flash-uf2.cmd`)

対象: LisM / AroundFortyRB / KUKEY42 / Pyuron (いずれも Seeed XIAO nRF52840 + Adafruit nRF52 UF2 ブートローダ)

#### 最新版を書き込む (`tools/flash-zmk.cmd`)

1. `tools/flash-zmk.cmd` をダブルクリックし、機種と書き込む内容を番号で選ぶ

   | 番号 | 書き込む内容 | 書き込む順番 |
   | --- | --- | --- |
   | 1 (Enter) | 左右に書き込む | 右 → 左 |
   | 2 | 設定リセットしてから左右に書き込む | 右 (設定リセット → セントラル) → 左 (設定リセット → ペリフェラル) |
   | 3 | 右手側 (セントラル) だけ | 右 |
   | 4 | 左手側 (ペリフェラル) だけ | 左 |
   | 5 | 設定リセットだけ | 右 → 左 |

2. 書き込むファイルの一覧が出るので、確認して Enter を押す。ここで次の切り替えもできる
   - `s`: 右手側を ZMK Studio 対応版にするか (既定は通常版)
   - `r` / `l` (LisM のみ): 右 / 左のトラックボール有無 (既定は左右ともトラックボールあり)
3. スクリプトが必要なファイルを [`firmware-latest`](#最新ファームウェアの取得元-firmware-latest-リリース) からまとめてダウンロードする
4. 「[1/2] 右手側にセントラルを書き込みます」のように表示されたら、**表示された側の** XIAO をブートローダにする
   (リセットボタンを素早く 2 回、または BT レイヤーの `&bootloader` キー)。書き込みと成否の判定は `flash-uf2.cmd` と同じ
5. すべて終わると「完了」と表示される。設定リセットを含んだ場合は、PC の Bluetooth 設定から古い登録を削除して再ペアリングする

- **左右を間違えないこと**: 左右の XIAO はブートローダの情報が同じなので、スクリプトからは見分けられない。表示された側だけをブートローダにする
- **途中で失敗したとき**: そこで止まり、残りのファイルの場所を表示する。もう一度実行するか、表示されたファイルを `tools/flash-uf2.cmd` にドロップする
- **手元の `.uf2` を書き込むとき**: そのファイルを `tools/flash-zmk.cmd` (または `tools/flash-uf2.cmd`) にドラッグ＆ドロップする
- **既定値を変えるとき**: `tools/flash-zmk.ps1` 冒頭の `$DEFAULT_STUDIO` / `$DEFAULT_LISM_RIGHT` / `$DEFAULT_LISM_LEFT` を書き換える

コマンドラインから実行する場合 (`-Keyboard` と `-Mode` を両方指定すると、メニューを出さずに書き込む):

```powershell
powershell -ExecutionPolicy Bypass -File tools\flash-zmk.ps1 [-Keyboard LisM|AroundFortyRB|KUKEY42|Pyuron] [-Mode Both|ResetBoth|Right|Left|ResetOnly] [-Studio] [-RightVariant trackball|non_trackball] [-LeftVariant trackball|non_trackball]
```

#### エクスプローラでのコピー時に「予期しないエラー」が出る場合

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

#### 書き込みスクリプト (`tools/flash-uf2.cmd`)

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

- 書き込む前に `.uf2` を検証し、別ボード用のファイルや壊れたダウンロードはここで弾く
  - UF2 形式か
  - どのボード用か (ファミリ ID で nRF52840 / RP2040 を判定)
  - 書き込み先が書き込み可能な領域に収まるか (nRF52840 は `0x27000`-`0xF4000`、RP2040 は `0x10000000`-`0x11000000`)
  - ブロックの欠けが無いか
- `INFO_UF2.TXT` の内容がそのボードと合うドライブを自動で探し、ブートローダの情報 (Model / Board-ID など) を表示する
  - 例: XIAO と KQ-mini の両方がブートローダになっていても、別のボードには書き込まない
- ファイルサイズを先に確保してからデータだけを書き込み、書き込み完了直後の切断は想定どおりの動作として扱う
- ドライブが消えたこと (= ブートローダが全ブロックを受け取って再起動したこと) を確認して成功と判定する

#### 左右の役割や BLE 設定を変えた後の書き込み順

セントラル役割や Studio の指定方法を変えたとき
([ryo-aoki-pc/zmk-config-keyboards#10](https://github.com/ryo-aoki-pc/zmk-config-keyboards/pull/10) の統一後など) は、
古い設定が残らないように次の順で書き込みます。
`tools/flash-zmk.cmd` の「2. 設定リセットしてから左右に書き込む」を選ぶと、この手順をまとめて行えます。

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
   [vial-qmk-kq-mini#13](https://github.com/ryo-aoki-pc/vial-qmk-kq-mini/pull/13) より前のファームウェアは
   16 バイトに満たない受信データを捨てるため、ターミナルで打った文字が届かない。入力しても何も表示されないときは、
   先に [`tools/flash-kq-mini.cmd`](#keyboard-quantizer-mini-toolsflash-kq-minicmd) で最新のファームウェアに書き換える。
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
  左右それぞれに保存するので、[`tools/flash-keyball.cmd`](#keyball39-toolsflash-keyballcmd) で左右に同じファームを書けば揃う)

点検後、ボール側に USB を挿して `tools/keyball-check.cmd` を実行し、Ball availability がボールの側
(`Right` など) になれば復旧です。それでも `None` のままなら、ボール基板 (センサーのはんだ付けやセンサー本体) の不良が考えられます。
