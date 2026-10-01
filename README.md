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
| トラックボールの細かさ | センサーの値を引き伸ばさず、1 カウントでカーソルが 1 動く (2 倍などにすると 2 ずつ飛ぶ)。AroundFortyRB / roBa は CPI 800、KUKEY42 は CPI 2000 + 楕円の補正 (`trackball_matrix` の divisor 2000)。LisM / Pyuron / torabo-tsuki-lp (PAW3222) は CPI を設定せず等倍 |
| カーソルの加速 | 転がす速さに応じて移動量に倍率を掛ける ([zmk-input-processor-xy-accel](https://github.com/ryo-aoki-pc/zmk-input-processor-xy-accel) の `trackball_accel`)。速さ 0 で 0.5 倍 → 1000 カウント/秒で等倍 → 4000 カウント/秒以上で 1.3 倍 (`min-factor 500` / `speed-threshold 1000` / `max-factor 1300` / `speed-max 4000`)。カーソル移動だけに掛け、スクロールには掛けない。Keyball39 も同じ値 (`keymaps/via/config.h` の `KEYBALL_ACCEL_*`)。調整は [カーソルの加速の調整](#カーソルの加速の調整) |
| スクロール | `zip_scroll_scaler 1 16` (1/16)。例外: AroundFortyRB / roBa は CPI 800 なので `zip_scroll_scaler 1 32` (CPI 400 のときの 1/16 と同じ速さ)、KUKEY42 はドライバの `CONFIG_PMW3610_SCROLL_TICK=32`、torabo-tsuki-lp は実機で調整した `zip_scroll_scaler 1 1` + スムーズスクロール (`CONFIG_ZMK_POINTING_SMOOTH_SCROLLING`) |
| スリープ | 5 分で idle、30 分で deep sleep (`CONFIG_ZMK_SLEEP`)。kscan に `wakeup-source` を付けて、キーを押せば復帰する (無いとリセットボタンでしか復帰しない)。USB 給電中は deep sleep しない |

### カーソルの加速の調整

ゆっくり転がしたときはカーソルを細かく動かし (狙った位置に止めやすくする)、速く転がしたときは遠くまで動かします。
倍率は速さ (カウント/秒) で次のように変わり、その間は直線で補間します。

| 速さ (カウント/秒) | 0 | 500 | 1000 | 2500 | 4000 以上 |
| --- | --- | --- | --- | --- | --- |
| 倍率 | 0.5 | 0.75 | 1.0 | 1.15 | 1.3 |

- 速さは X と Y を合わせた移動量から求めるので、斜めに動かしても縦横と同じ倍率になる
- 1 に満たない端数は次へ持ち越すので、0.5 倍でも移動量は失われない (2 カウントで 1 動く)
- 50ms 以上止まっていたら 0.5 倍から始める (速く転がした直後に止めて細かく合わせるとき、前の速さを引き継がない)
- Windows の「ポインターの精度を高める」(マウスのプロパティ) が ON のときは、OS 側でも加速がかかる

値は各キーボードの `trackball_accel` ノード (Keyball39 は `config.h` の `KEYBALL_ACCEL_*`) で変えます。

| 症状 | 変える値 |
| --- | --- |
| ゆっくり動かしたときに遅すぎる | `min-factor` を上げる (例: 700) |
| ゆっくり動かしても細かく止められない | `min-factor` を下げる、または `speed-threshold` を上げる |
| 速く動かすと飛びすぎる (OS の加速と重なる) | `max-factor` を下げる (1000 で加速なし) |
| 速く動かしても遠くまで届かない | `max-factor` を上げる、または `speed-max` を下げる |

| キーボード | `trackball_accel` の場所 |
| --- | --- |
| LisM | `boards/shields/lism/lism.dtsi` (左右のトラックボールで共有) |
| Pyuron | `boards/shields/Pyuron/Pyuron.dtsi` (左右のトラックボールで共有) |
| torabo-tsuki-lp | `boards/shields/torabo_tsuki_lp/torabo_tsuki_lp.dtsi` |
| AroundFortyRB | `boards/shields/AroundForty-RB/AroundForty-RB_R.overlay` |
| roBa | `boards/shields/roBa/roBa_R.overlay` |
| KUKEY42 | `boards/shields/KUKEY42/KUKEY42_R.overlay` |
| Keyball39 | `qmk_firmware/keyboards/keyball/keyball39/keymaps/via/config.h` |

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
- カーソルの加速: keyball39 本体側で掛けます (`keymaps/via/config.h` の `KEYBALL_ACCEL_*`。ZMK のキーボードと同じ値)。
  KQ-mini 側では倍率を掛けません

## Submodules

### キーボード設定 (zmk-config / zmk-keyboard)

| リポジトリ | 追跡ブランチ |
| --- | --- |
| [zmk-config-Pyuron](https://github.com/ryo-aoki-pc/zmk-config-Pyuron) | `custom` |
| [zmk-config-LisM](https://github.com/ryo-aoki-pc/zmk-config-LisM) | `custom` |
| [zmk-config-KUKEY42](https://github.com/ryo-aoki-pc/zmk-config-KUKEY42) | `custom` |
| [zmk-config-AroundFortyRB](https://github.com/ryo-aoki-pc/zmk-config-AroundFortyRB) | `custom` |
| [zmk-config-roBa](https://github.com/ryo-aoki-pc/zmk-config-roBa) | `custom` |
| [zmk-keyboard-torabo-tsuki-lp](https://github.com/ryo-aoki-pc/zmk-keyboard-torabo-tsuki-lp) | `custom` |

### その他 ZMK 関連

| リポジトリ | 追跡ブランチ | 用途 |
| --- | --- | --- |
| [zmk-keymap-docgen](https://github.com/ryo-aoki-pc/zmk-keymap-docgen) | `main` | キーマップドキュメント生成ツール |
| [zmk-input-processor-xy-accel](https://github.com/ryo-aoki-pc/zmk-input-processor-xy-accel) | `main` | カーソルの加速の入力プロセッサ。ZMK の 6 リポジトリが `config/west.yml` でコミットを固定して取り込む |

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

各 submodule を追跡ブランチの最新コミットに更新します。
検査ツールの期待値 (`tools/expected/*.json`) も submodule から作り直します (Python 3.10 以上):

```bash
git submodule update --remote
python tools/expected/generate.py
git add .
git commit -m "Update submodules"
```

期待値が submodule の内容と合っていないと、CI (`.github/workflows/keyboard-check.yml`) の `generate.py --check` が失敗します。

## ファームウェアの書き込み (Windows)

`tools/` の書き込みスクリプトを使います。ファイルの検証から成否の判定まで、スクリプトが行います。

| キーボード | マイコン / ブートローダ | ファイル | スクリプト |
| --- | --- | --- | --- |
| LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa | Seeed XIAO nRF52840 / Adafruit nRF52 UF2 | `.uf2` | `tools/flash-zmk.cmd` (ダブルクリック)、または `tools/flash-uf2.cmd` (ファイルをドロップ) |
| torabo-tsuki-lp | BLE Micro Pro Boost (nRF52840) / BLE Micro Pro の UF2 (`BLEMICROPRO` ドライブ) | `.uf2` | `tools/flash-zmk.cmd` (ダブルクリック)、または `tools/flash-uf2.cmd` (ファイルをドロップ) |
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

[keyball](https://github.com/ryo-aoki-pc/keyball)、[vial-qmk-kq-mini](https://github.com/ryo-aoki-pc/vial-qmk-kq-mini)、ZMK の 6 リポジトリの CI は、custom ブランチをビルドするたびに次のことを行います。

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
| roBa | `https://github.com/ryo-aoki-pc/zmk-config-roBa/releases/download/firmware-latest/<artifact-name>.uf2` |
| torabo-tsuki-lp | `https://github.com/ryo-aoki-pc/zmk-keyboard-torabo-tsuki-lp/releases/download/firmware-latest/<artifact-name>.uf2` |

ZMK の `<artifact-name>` は各リポジトリの `build.yaml` のもので、全エントリ (左右・Studio 版・設定リセット) が置かれます。

- 公開リポジトリのリリースなので、ログインや gh CLI は不要
- Actions の Artifacts と違い、90 日で期限切れにならない
- 書き込まれるのは custom ブランチの最新ビルド。このリポジトリが submodule で参照しているコミットとは限らない
- ダウンロードしたファイルと avrdude は `tools/.cache/` に保存される (git の管理外)

### ZMK キーボード (`tools/flash-zmk.cmd` / `tools/flash-uf2.cmd`)

対象:

- LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa (Seeed XIAO nRF52840 + Adafruit nRF52 UF2 ブートローダ)
- torabo-tsuki-lp (BLE Micro Pro Boost + BLE Micro Pro の UF2 ブートローダ。乾電池と電源スイッチ付き)

#### XIAO をブートローダにする方法

次のどちらかで切り替える。

- **リセットボタンを素早く 2 回押す**: どの状態でも使える
- **FUNC レイヤーの `&bootloader` キー**: 押したキーがある側が切り替わる
  - 右手側: FUNC を押しながら `N`
  - 左手側: FUNC を押しながら `B`。**右手側の電源が入っていて、左右がつながっているときだけ**使える
    (左のキー入力は右手側 (セントラル) がキーマップで解釈し、BLE で左手側に切り替えを指示するため。
    右の電源が切れていると何も起きない)
  - `tools/flash-zmk.cmd` の設定リセットを含むモード (2 / 5) では、最初の右手側以外はキーで切り替えられない。
    設定リセット用のファームウェアが動いている側にはキーマップが無く、設定リセット後は左右のペアリングも切れているため。
    リセットボタンを使う

#### torabo-tsuki-lp (BLE Micro Pro Boost) をブートローダにする方法

- **電源スイッチを OFF にしてから USB ケーブルでつなぐ**: `BLEMICROPRO` という名前のドライブが現れる。どの状態でも使える
- **FUNC レイヤーの `&bootloader` キー**: XIAO と同じく右手側は FUNC + `N`、左手側は FUNC + `B`
  (左手側は右手側の電源が入っていて、左右がつながっているときだけ)
- 書き込んだファームウェアは、USB ケーブルを抜いて電源スイッチを ON にし、USB ケーブルを差し直すと起動する。
  電源スイッチが OFF のままだと、再起動してもブートローダに戻る

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
   (リセットボタンを素早く 2 回、または FUNC レイヤーの `&bootloader` キー。[XIAO をブートローダにする方法](#xiao-をブートローダにする方法) を参照)。
   書き込みと成否の判定は `flash-uf2.cmd` と同じ
   - torabo-tsuki-lp は、表示された側の電源スイッチを OFF にしてから USB ケーブルでつなぐ (もう片側の USB ケーブルは抜く)。
     書き込んだファームウェアは、USB ケーブルを抜いて電源スイッチを ON にし、USB ケーブルを差し直したときに起動する
   - torabo-tsuki-lp の設定リセットは、書き込んだあとに一度起動させないと動かない。スクリプトの案内に従って
     スイッチ ON で USB ケーブルを差し直し、数秒待ってから USB ケーブルを抜いてスイッチを OFF に戻し、Enter を押す
5. すべて終わると「完了」と表示される。設定リセットを含んだ場合は、PC の Bluetooth 設定から古い登録を削除して再ペアリングする

- **左右を間違えないこと**: 左右の XIAO (torabo-tsuki-lp は BMP) はブートローダの情報が同じなので、スクリプトからは見分けられない。表示された側だけをブートローダにする
- **途中で失敗したとき**: そこで止まり、残りのファイルの場所を表示する。もう一度実行するか、表示されたファイルを `tools/flash-uf2.cmd` にドロップする
- **手元の `.uf2` を書き込むとき**: そのファイルを `tools/flash-zmk.cmd` (または `tools/flash-uf2.cmd`) にドラッグ＆ドロップする
- **既定値を変えるとき**: `tools/flash-zmk.ps1` 冒頭の `$DEFAULT_STUDIO` / `$DEFAULT_LISM_RIGHT` / `$DEFAULT_LISM_LEFT` を書き換える

コマンドラインから実行する場合 (`-Keyboard` と `-Mode` を両方指定すると、メニューを出さずに書き込む):

```powershell
powershell -ExecutionPolicy Bypass -File tools\flash-zmk.ps1 [-Keyboard LisM|AroundFortyRB|KUKEY42|Pyuron|roBa|torabo-tsuki-lp] [-Mode Both|ResetBoth|Right|Left|ResetOnly] [-Studio] [-RightVariant trackball|non_trackball] [-LeftVariant trackball|non_trackball]
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
   (または FUNC レイヤーの `&bootloader` キーを押す。[XIAO をブートローダにする方法](#xiao-をブートローダにする方法) を参照)。
   既にドライブが出ていればすぐに書き込みが始まります
   - torabo-tsuki-lp (BMP) は、電源スイッチを OFF にしてから USB ケーブルでつなぐ
3. 「成功」と表示されれば完了
   - torabo-tsuki-lp (BMP) は、USB ケーブルを抜いて電源スイッチを ON にし、USB ケーブルを差し直すと起動する

コマンドラインから実行する場合 (ドライブは省略すると自動検出):

```powershell
powershell -ExecutionPolicy Bypass -File tools\flash-uf2.ps1 <ファイル.uf2> [E:]
```

スクリプトが行うこと:

- 書き込む前に `.uf2` を検証し、別ボード用のファイルや壊れたダウンロードはここで弾く
  - UF2 形式か
  - どのボード用か (ファミリ ID で nRF52840 / RP2040 を判定。XIAO と BMP はファミリ ID が同じなので、
    書き込み先の先頭アドレス (XIAO は `0x27000`、BMP は `0x26000`) で判定)
  - 書き込み先が書き込み可能な領域に収まるか (XIAO は `0x27000`-`0xF4000`、BMP は `0x26000`-`0xE0000`、RP2040 は `0x10000000`-`0x11000000`)
  - ブロックの欠けが無いか
- `INFO_UF2.TXT` の内容 (BMP はボリュームラベル `BLEMICROPRO`) がそのボードと合うドライブを自動で探し、ブートローダの情報 (Model / Board-ID など) を表示する
  - 例: XIAO と KQ-mini の両方がブートローダになっていても、別のボードには書き込まない
- ファイルサイズを先に確保してからデータだけを書き込み、書き込み完了直後の切断は想定どおりの動作として扱う
- ドライブが消えたこと (= ブートローダが全ブロックを受け取って再起動したこと) を確認して成功と判定する。
  BMP は電源スイッチが OFF のまま再起動するとブートローダに戻るので、ドライブが再び現れても成功とする

#### 左右の役割や BLE 設定を変えた後の書き込み順

セントラル役割や Studio の指定方法を変えたとき
([ryo-aoki-pc/zmk-config-keyboards#10](https://github.com/ryo-aoki-pc/zmk-config-keyboards/pull/10) の統一後など) は、
古い設定が残らないように次の順で書き込みます。
`tools/flash-zmk.cmd` の「2. 設定リセットしてから左右に書き込む」を選ぶと、この手順をまとめて行えます。

1. `settings_reset-seeeduino_xiao_ble-zmk.uf2` を左右両方に書き込む
   (torabo-tsuki-lp は `settings_reset-bmp_boost-zmk.uf2`。書き込んだあと、スイッチ ON で USB ケーブルを差し直して一度起動させる)
2. 左 (`*_left_peripheral*.uf2`) と右 (`*_right_central*.uf2`) のファームウェアをそれぞれ書き込む
3. 設定リセットでペアリング情報も消えるため、PC の Bluetooth 設定から古いキーボードを削除して再ペアリングする

## キーボードの設定を検査する (`tools/keyboard-check.cmd`)

接続したキーボードの設定 (キーマップ・トラックボール) が、意図した設定 (LisM 基準) になっているかを確かめるスクリプトです。
次のようなずれを見つけます。キーボードの設定は書き換えません。

- Vial / ZMK Studio で変えた内容が、キーボードに残っている
- Keyball の CPI やスクロールの倍率が、EEPROM に古い値のまま残っている (ファームを書き直しても戻らない)
- overlay の XY / スクロールの反転、AML の設定が意図と違う

### 使い方

1. `tools/keyboard-check.cmd` をダブルクリックし、機種と検査の内容を番号で選ぶ。接続中の機種には「検出」と表示される
2. 読み出し検査のあと、テスト用のウィンドウが開く。ウィンドウの指示に従って、キーを押したりボールを転がしたりする
3. 最後に PASS / FAIL / WARN / SKIP の一覧が出る。結果は `tools/.cache/keyboard-check/reports/` にも保存される

| 判定 | 意味 |
| --- | --- |
| PASS | 意図どおり |
| FAIL | 意図と違う (下の「判定と対処」を参照) |
| WARN | 確認が必要 (トラックボールの補正の推奨値など) |
| SKIP | 検査できなかった (案内に従って準備すると検査できる) |

### 読み出し検査

キーボードから設定を読み出して、期待値 (`tools/expected/*.json`) とすべてのキーを比べます。読み取りのコマンドだけを送ります。

| 機種 | 検査する内容 | 準備 |
| --- | --- | --- |
| Keyboard Quantizer Mini + Keyball39 | KQ-mini のキーマップ (全 8 レイヤー)、タップホールド設定 (tapping term など)、タップダンス、キーオーバーライド、コンボ、マクロ | KQ-mini を PC につなぐ。Vial は閉じる |
| Keyball39 (PC に直結) | キーマップ (全 4 レイヤー)、Ball availability、CPI・スクロールの倍率・AML・カーソルの加速の設定 | Keyball を PC に直結する (KQ-mini 経由では読めない)。CPI などは [ryo-aoki-pc/keyball#12](https://github.com/ryo-aoki-pc/keyball/pull/12) 以降のファームで読める |
| LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa / torabo-tsuki-lp | キーマップ (全 10 レイヤー)、物理レイアウト、ZMK Studio の未保存の変更 | 右手側に ZMK Studio 版を書き込み (`tools/flash-zmk.cmd` のファイルの一覧で `s`)、USB でつなぐ。キーボードの出力を USB にする (BT レイヤー + `U`)。ブラウザの ZMK Studio は閉じる |

ZMK のトラックボールの設定 (反転・倍率・AML) は ZMK Studio では読めないので、実動作テストで確かめます。

### 実動作テスト

テスト用のウィンドウで、キーを押したりボールを転がしたりして、PC に届いた入力を期待値と比べます。
どの機種でも、ファームを変えずに USB / BLE のどちらでもできます (リモートデスクトップ越しではできません)。

| 項目 | 合格の条件 |
| --- | --- |
| キーのタップ | BASE レイヤーのキーを 1 つずつタップして、意図したキーが入力される (KQ-mini は、Keyball のキーを KQ-mini が変換した結果で確かめる) |
| ボールの向き | 右へ転がすと右、手前へ転がすと下へカーソルが動く |
| AML のクリック | ボールを転がしたあと、`D` を押しながら `F` でクリックになる (文字は入力されない) |
| Shift + クリック | ボールを転がしたあと、`Z` → `D` → `F` で Shift + クリックになる |
| スクロールの向き | `D` を押しながら手前へ転がすと下へ、右へ転がすと右へスクロールする (マウスのホイールと同じ向き) |
| AML のタイムアウト | 10 秒触らないと AML が切れ、`F` で文字が入力される |

- 右手側のボールは左手のキー (`D` / `F` / `Z`)、左手側のボールは右手のキー (`K` / `J` / `/`) で試す
- テスト中は、Win キーでスタートメニューが開かず、キーボードから送られたクリックはウィンドウの中だけで起きるようにしてある

### トラックボールの正規化 (楕円補正・速さ)

検査の内容で「4. トラックボールの正規化だけ」(または 1 / 3) を選ぶと、次の 2 つを測って、補正の推奨値を出します。
ファームや overlay は書き換えないので、推奨値を反映して書き込んだあと、もう一度測って確かめます。

**楕円 (X / Y の比率と傾き)**: ボールを円を描くように、右回りで 10 秒、左回りで 10 秒回します。縦横比が 1.10 を超えると WARN になり、推奨値を出します。

| 機種 | 推奨値 |
| --- | --- |
| KUKEY42 | `KUKEY42_R.overlay` の `trackball_matrix` の `matrix` / `divisor` の行 (今の行列に補正を掛けた値) |
| LisM / AroundFortyRB / Pyuron / roBa / torabo-tsuki-lp | listener の `input-processors` で `<&trackball_accel>` より前に足す `<&zip_x_scaler n d>, <&zip_y_scaler n d>`。傾きがあって軸ごとの倍率で直せないときは、KUKEY42 の 2x2 行列の入力プロセッサ (`src/input_processor_xy_matrix.c`) の移植が必要 |
| Keyball39 / KQ-mini | X と Y を別々に補正する設定が無いので、測った値だけを表示する |

計算は「KUKEY42 真円計測」ページと同じです (移動量の共分散から、楕円を同じ面積の円に戻す行列を求める)。
ページはブラウザで OS のポインタの加速が入った値を測るため、補正の強さを下げる必要がありました。
このスクリプトは Raw Input で、そのボールの値だけを OS の加速の前に測るので、補正の強さは 100% のまま使えます (`-CalibStrength` で変えられる)。
直線のテスト (右へ / 手前へ) で 5° 以上ずれていれば、回転も補正に入れます。

キーボードのファームの[カーソルの加速](#カーソルの加速の調整) (ZMK の `trackball_accel`、Keyball39 の `KEYBALL_ACCEL_*`) は、
測った移動量から取り除いてから計算します。加速の後の値のままだと、速く動く長軸の向きほど大きく出て楕円が実際より細長くなり、
速さも転がす速さで変わってしまうためです。取り除く計算はファームの処理と完全には同じではありませんが、
ファームの処理を真似た計算での確認では、縦横比と 1 回転あたりのカウントの誤差は 3% 以内です。
推奨値の補正は、加速より前 (ZMK は `<&trackball_accel>` より前) に入れます。

**速さ (キーボード間)**: ボールに印を付け、右へちょうど 2 回転を 2 回、手前へちょうど 2 回転を 2 回転がします。
ボールの直径を入れると、指の移動量あたりの速さ (実効 CPI) で比べます。

- 最初に LisM で測ると、基準として `tools/.cache/keyboard-check/trackball.json` に保存される (`-SpeedReference` でも指定できる)
- ほかの機種で、基準との差が ±10% を超えると WARN になり、推奨値を出す: PMW3610 の機種 (KUKEY42 / AroundFortyRB / roBa) は CPI、
  ZMK は `<&zip_xy_scaler n d>` (`<&trackball_accel>` より前)、Keyball39 は `KEYBALL_CPI_DEFAULT`。
  CPI を変えられる機種は CPI を先に出す (倍率を 1 より大きくすると、1 カウントでカーソルが 2 以上動き、細かさが落ちるため)
- Keyball39 は 1 回の報告が ±127 で頭打ちになるので、速く回しすぎたときはやり直しを促す

### 判定と対処

| 結果 | 原因と対処 |
| --- | --- |
| KQ-mini のキーマップなどが FAIL | Vial で変えた内容が残っている。Vial の「File → Load saved layout」で `vial-qmk-kq-mini/keyboards/sekigon/keyboard_quantizer/mini/keymaps/vial/KEYMAP.vil` を読み込む。新しいビルドを `tools/flash-kq-mini.cmd` で書き込んでも戻る (同じビルドの書き直しでは戻らない) |
| Keyball39 の CPI / スクロールの倍率が FAIL | EEPROM に古い値が残っている。Bootmagic (左手側は `Q`、右手側は `P` を押しながら USB を挿す) で初期化する |
| Keyball39 のカーソルの加速が FAIL | `config.h` の `KEYBALL_ACCEL_*` が違うファームが書き込まれている。`tools/flash-keyball.cmd` で最新のファームを書き込む |
| ZMK のキーマップが FAIL | ZMK Studio で保存した変更が残っている。Studio の「Restore Stock Settings」か、`tools/flash-zmk.cmd` の「2. 設定リセットしてから左右に書き込む」 |
| ZMK の読み出しが SKIP (応答がない) | キーボードの出力が BLE になっている。BT レイヤーのキーを押しながら `U` (`&out OUT_USB`) で USB に切り替える |
| ボールの向き・スクロールの向きが FAIL | overlay の `zip_xy_transform` (`X_INVERT` / `Y_INVERT` / `XY_SWAP`) を確かめる |
| AML のクリックが FAIL (文字が入力された) | AML (ZMK の `zip_temp_layer`、Keyball の `AUTO_MOUSE_*`) が動いていない |

- 一覧の最後の「設定ファイル (参考)」は、submodule の設定ファイルどうしの整合です (キーボードは見ていない)。
  例: LisM は、左ボールのスクロールの処理が右手側の版 (trackball / non_trackball) で違うため、WARN になります
- 期待値は、このリポジトリが参照している submodule のコミットから作ります。書き込みスクリプトは custom ブランチの最新を書くため、
  submodule の参照が古いと、意図どおりでも FAIL になることがあります。そのときは
  [submodule を最新に更新](#submodule-を最新に更新) してから検査します

### コマンドライン

`-Keyboard` と `-Mode` を両方指定すると、メニューを出さずに検査します。

```powershell
powershell -ExecutionPolicy Bypass -File tools\keyboard-check.ps1 [-Keyboard KqMini|Keyball39|LisM|AroundFortyRB|KUKEY42|Pyuron|roBa|torabo-tsuki-lp] [-Mode All|Readout|Interactive] [-Section All|Keys|Trackball|Calibrate] [-Ball right|left|both] [-Port COM5] [-Speed] [-Diameter <mm>] [-SpeedReference <実効CPI>] [-CalibStrength <0-100>] [-Report <ファイル>]
```

終了コードは、0 = FAIL なし、1 = FAIL あり、2 = 検査できた項目がない、です。

## ZMK キーボードを複数台 BLE で同時接続するとカーソルがカクつく場合

ZMK は、トラックボールのセンサーが報告するたびに、マウスレポートを 1 つ送ります。BLE では送り切れないレポートを
最大 20 個まで溜めて順に送るため、送る量が送信の機会より多いと、カーソルが遅れてまとめて動きます。
満杯になると古いレポートが捨てられ、移動量も抜けます。PC 側の送信の機会は接続しているキーボード全台で分け合うので
(使っていないキーボードも、接続しているだけで分け合う相手になる)、台数が増えるほど起きやすくなります。

各キーボードが BLE でレポートを送る間隔は次のとおりです。

| キーボード | 間隔 | 決めている設定 |
| --- | --- | --- |
| KUKEY42 / roBa | 16ms ごと (ドライバは 8ms ごとに報告し、15ms に 1 回までにまとめる) | `KUKEY42_R.overlay` / `roBa_R.overlay` の `trackball_rate_limit` ([zmk-input-processor-report-rate-limit](https://github.com/badjeff/zmk-input-processor-report-rate-limit)) |
| AroundFortyRB | 15ms 以上 (ドライバの報告を 15ms に 1 回までにまとめる) | `AroundForty-RB_R.overlay` の `trackball_rate_limit` (同上) |
| LisM / Pyuron / torabo-tsuki-lp | 約 15ms ごと | PAW3222 のドライバ (15ms ごとに読み取る。設定は無い) |

- KUKEY42 は以前、8ms ごとに送っていたため、複数台を同時に接続するとカクついていた
  ([ryo-aoki-pc/zmk-config-KUKEY42#25](https://github.com/ryo-aoki-pc/zmk-config-KUKEY42/pull/25) で修正)。
  roBa も同じく 8ms ごとに送っていたため、同じ方法でまとめた
  ([ryo-aoki-pc/zmk-config-roBa#4](https://github.com/ryo-aoki-pc/zmk-config-roBa/pull/4))
- AroundFortyRB は以前、ドライバの `CONFIG_PMW3610_REPORT_INTERVAL_MIN=15` でまとめていた。ドライバは報告の間隔が
  15ms 以上空くと、まだ送っていない移動量を捨てるため、ゆっくり動かしたときに動きが抜けていた
  ([ryo-aoki-pc/zmk-config-AroundFortyRB#36](https://github.com/ryo-aoki-pc/zmk-config-AroundFortyRB/pull/36) で `trackball_rate_limit` に変更)
- まとめるときは、間隔に満たない分の移動量を次のレポートに足す。ただし、前に送ってから 30ms 以上次の動きが
  無かったときは、足さずに捨てる (ボールを止める直前の 15ms ぶんの動きが抜けることがある)
- USB 接続中は、KUKEY42 / roBa / AroundFortyRB もまとめずに送る

それでもカクつくとき:

- 使っていないキーボードの電源を切る
- KUKEY42 / roBa / AroundFortyRB は、右手側の overlay の `<&trackball_rate_limit 15>` を `30` (32ms ごと) に上げる。
  カーソルの動きは粗くなるが、送る量が半分になる

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
