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
| 6 | FUNC | FUNCTION | ファンクションキー (F1〜F12)・Insert・PrintScreen など |
| 7 | BT | BLUETOOTH | Bluetooth／出力切替 |
| 8 | MOUS | MOUSE_MOVE | マウス移動 (AML・最上位) |
| 9 | SCRL | MOUSE_SCROLL | スクロール／クリック |

- 対象: LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa / torabo-tsuki-lp
- キー数が LisM と違う機種は、次のルールで移植している (各リポジトリのキーマップ冒頭にも書いてある)
  - LisM の `&mo BT` (I 列の下) の位置にキーが無い機種 (AroundFortyRB / KUKEY42 / roBa / Pyuron) は、3 段目中央の 2 キーに置く。torabo-tsuki-lp は両方に置く
  - LisM の左親指の空き (`&none`) に当たるキーがある機種 (AroundFortyRB / KUKEY42 / roBa / torabo-tsuki-lp / Keyball39) は、そこを SPACE の複製 (`&lt VIM_BASE SPACE`) にする
  - LisM に無い位置のキー (KUKEY42 / roBa / torabo-tsuki-lp のホーム段中央など) は `&none`。KUKEY42 / roBa は右親指が少ないので `&mo FUNC` が 1 つ、Pyuron は左親指が少ないので `&mo FUNC` は右だけ

### 共通基盤

| 項目 | 内容 |
| --- | --- |
| ZMK | zmkfirmware **v0.3.0** を `config/west.yml` で固定 |
| ドキュメント生成 | `tools/keymap-docgen` submodule (ZMK の 6 リポジトリ・keyball・vial-qmk-kq-mini で同一コミット) による KEYMAP.html / KEYMAP.xlsx 自動生成。KEYMAP.html はブラウザで開くと、レイヤーをタブ (← / → ・数字キー) で切り替えて 1 画面で見るビューアになる (Tap Dance / Mod Morph の図と経路はボタンで切り替え、マウスを重ねたキーの全操作を下の欄に出す。JavaScript が動かなければ全レイヤーを縦に並べる)。レイアウトの JSON の `row` / `col` は `y` / `x` と同じにする (KEYMAP.xlsx の配置に使う) |
| ワークフロー | build.yml / keymap-docs.yml / release.yml を共通化 (keymap-docs.yml はキーマップとレイアウトの JSON のパス以外同一。torabo-tsuki-lp だけレイアウトを `-l config/info.json` で渡す)。firmware-latest はタグを消さずに付け替えてリリースを作り直し、ダウンロードできることを確かめる。PR のビルド (firmware-pr-<番号>) と custom のビルドの履歴 (firmware-custom-<sha7>) もリリースに置き、それぞれ新しいものから 30 件を残す (`.github/scripts/firmware-release.sh`。keyball / vial-qmk-kq-mini の build ワークフローも同じ処理) |
| ファイル構成 | `.conf` は `boards/shields/<NAME>/`、ハード・役割は `Kconfig.defconfig`、Studio とセントラル役割は `build.yaml` の `cmake-args` |
| アーティファクト | 全エントリに `artifact-name` を付与し、Studio 版 / 非 Studio 版の両方を生成 |
| ローカルビルド | `Makefile` + `scripts/` + `.devcontainer/` (`make` / `make single` など) |
| タップホールド | `&mt` / `&lt` = tapping-term 150 / quick-tap 0 / flavor balanced |
| FUNC レイヤー | `Q`〜`P` で F1〜F10、F10 の下の `-` / `/` で F11 / F12。`D` / `F` / `G` で PrintScreen / ScrollLock / Pause (標準のキーボードと同じ並び)、`C` (PrintScreen の下) で Insert、`Z` でアプリケーションキー (メニュー)。キー数の違う機種も BASE と同じ文字の位置。KQ-mini + Keyball39 も同じ (FUNC は Keyball39 の `` ` `` を押したまま) |
| AML | `&zip_temp_layer 8 10000`、`require-prior-idle-ms 200`、除外位置は D / K (`&mo SCRL`) だけ、マウスクリックでタイマー延長。D / K を押したままスクロールしている間も延長する (スクロールのチェーンの先頭に `&zip_temp_layer 8 10000`。KUKEY42 はドライバのスクロールが通る `trackball_listener`、Keyball39 は `auto_mouse_activation` でホイールも数える)。修飾キーの位置 (A / - / Z / / / Win / Alt) を押しても AML が切れる。MOUSE_MOVE ではそこを `&trans` にしてあり、BASE と同じキーになる (A / - / Z / / はタップで文字、長押しで Ctrl / Shift)。マウスを使った直後に `a` や `z` を入力できる |
| AML の発動条件 | キー入力の振動などでボールがわずかに動いても AML にならない。キーを押した・離したあと `require-prior-idle-ms` (200ms) は発動せず (すべてのキーの押下と解放を数える)、止まっていた状態から動いた量 (X と Y それぞれ向き付きで足すので、行ったり来たりする振動は打ち消し合う) が 10 (加速の後の値 = カーソルの移動量) に達したら発動する。トラックボールのリスナーで `zip_temp_layer` の代わりに [zmk-input-processor-aml-threshold](https://github.com/ryo-aoki-pc/zmk-input-processor-aml-threshold) の `aml_threshold` (`threshold 10`) を使う。カーソルの動き、AML 中のタイムアウトの延長、クリックでの延長は変わらない。Keyball39 も同じ (`keymaps/via/config.h` の `KEYBALL_AML_THRESHOLD`、待ちは `AUTO_MOUSE_DELAY`)。調整は [AML の発動条件の調整](#aml-の発動条件の調整) |
| 楕円の補正 | ボールを円を描くように回したときに、カーソルが楕円ではなく円を描くよう、ボールごとに画面の X と Y に別々の倍率を掛ける (傾きは補正しない)。ZMK は listener の `input-processors` の `zip_xy_transform` の後・`trackball_accel` の前の `<&zip_x_scaler n d>, <&zip_y_scaler n d>` (分母 16 以下の分数)、Keyball39 は `config.h` の `KEYBALL_SCALE_X` / `KEYBALL_SCALE_Y` (1000 = 等倍)。値は機体ごとに [トラックボールの正規化](#トラックボールの正規化-楕円補正速さ) で測って入れる (LisM 基準ではない)。今は KUKEY42 だけ X 1/2・Y 13/12 (前の 2x2 行列の対角に近い値) |
| マウスレイヤーの修飾キー | MOUSE_SCROLL の A / - / Z / / は Ctrl / Shift、Win / Alt の位置は Win / Alt。修飾キーとクリック・ホイールを組み合わせるときは、`D` / `K` を押してから修飾キーを押す (例: `D` → `Z` → `F` で Shift + クリック、`D` → `A` → ボールで Ctrl + ホイール)。修飾キーを先に押すと AML が切れ、`D` が文字になる。修飾キーを押したままボールを転がすと、押してから 200ms たったあとにカーソルが 10 以上動いたところで AML に戻る |
| トラックボールの細かさ | センサーの値を引き伸ばさず、1 カウントでカーソルが 1 動く (2 倍などにすると 2 ずつ飛ぶ)。AroundFortyRB / roBa は CPI 800、KUKEY42 は CPI 2000。LisM / Pyuron / torabo-tsuki-lp (PAW3222) は CPI を設定せず等倍 |
| カーソルの加速 | 転がす速さに応じて移動量に倍率を掛ける ([zmk-input-processor-xy-accel](https://github.com/ryo-aoki-pc/zmk-input-processor-xy-accel) の `trackball_accel`)。速さ 0 で 0.5 倍 → 1000 カウント/秒で等倍 → 4000 カウント/秒以上で 1.3 倍 (`min-factor 500` / `speed-threshold 1000` / `max-factor 1300` / `speed-max 4000`)。カーソル移動だけに掛け、スクロールには掛けない。Keyball39 も同じ値 (`keymaps/via/config.h` の `KEYBALL_ACCEL_*`)。調整は [カーソルの加速の調整](#カーソルの加速の調整) |
| スクロール | 右へ転がすと右へ、手前へ転がすと下へスクロールする (全機種・左右のボールで同じ向き)。速さは `zip_scroll_scaler 1 16` (1/16)。例外: AroundFortyRB / roBa は CPI 800 なので `zip_scroll_scaler 1 32` (CPI 400 のときの 1/16 と同じ速さ)、KUKEY42 はドライバの `CONFIG_PMW3610_SCROLL_TICK=32`、torabo-tsuki-lp は実機で調整した `zip_scroll_scaler 1 1` + スムーズスクロール (`CONFIG_ZMK_POINTING_SMOOTH_SCROLLING`) |
| スリープ | 5 分で idle、30 分で deep sleep (`CONFIG_ZMK_SLEEP`)。kscan に `wakeup-source` を付けて、キーを押せば復帰する (無いとリセットボタンでしか復帰しない)。USB 給電中は deep sleep しない |
| BLE | ZMK の既定値のまま (送信出力・PHY・接続間隔・スタックなどを機種ごとに変えない)。例外: torabo-tsuki-lp は BMP の上流に合わせて送信出力 +8dBm (`CONFIG_BT_CTLR_TX_PWR_PLUS_8`) |
| LED | XIAO の 5 台は RGB LED ウィジェット ([zmk-rgbled-widget](https://github.com/caksoylar/zmk-rgbled-widget) の `rgbled_adapter`、`CONFIG_RGBLED_WIDGET_BATTERY_LEVEL_HIGH=30` / `CRITICAL=10`) でバッテリー残量と接続状態を表示する。充電中の表示 (`CONFIG_CHARGE_INDICATOR`) は LisM だけ (LisM の `src/charge_indicator.c`。[4mplelab/zmk-feature-charge-indicator](https://github.com/4mplelab/zmk-feature-charge-indicator) を取り込んで、[USB を挿すと止まる不具合](#lism-を-usb-でつなぐと操作できなくなる場合) を直したもの)。torabo-tsuki-lp は BMP のステータス LED (`CONFIG_ZMK_STATUS_LED`) |
| ブートローダ | 左手側は `Q`、右手側は `P` を押したまま USB ケーブルを挿すと、その側がブートローダになる (Keyball の Bootmagic と同じ操作)。各リポジトリの `src/usb_bootmagic.c` (`zmk,usb-bootmagic`) で、キーは左右の overlay の `row` / `column` で指定する。キーマップには、リセット (`&sys_reset`)・ブートローダ (`&bootloader`) のキーを置かない (押し間違えると、キーボードが再起動したりブートローダで止まったりするため。KQ-mini にも `QK_BOOT` / `QK_RBT` は無い)。[XIAO をブートローダにする方法](#xiao-をブートローダにする方法) を参照 |

### カーソルの加速の調整

ゆっくり転がしたときはカーソルを細かく動かし (狙った位置に止めやすくする)、速く転がしたときは遠くまで動かします。
倍率は速さ (カウント/秒) で次のように変わり、その間は直線で補間します。

| 速さ (カウント/秒) | 0 | 500 | 1000 | 2500 | 4000 以上 |
| --- | --- | --- | --- | --- | --- |
| 倍率 | 0.5 | 0.75 | 1.0 | 1.15 | 1.3 |

- 速さは X と Y を合わせた移動量から求めるので、斜めに動かしても縦横と同じ倍率になる
- 1 に満たない端数は次へ持ち越すので、0.5 倍でも移動量は失われない (2 カウントで 1 動く)
- 50ms 以上止まっていたら 0.5 倍から始める (速く転がした直後に止めて細かく合わせるとき、前の速さを引き継がない)。Keyball39 は 8ms ごとの移動平均で速さを求めるので、止めると約 50ms で 0.5 倍に戻る
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

### AML の発動条件の調整

キー入力の振動などでボールがわずかに動いても AML (マウスレイヤー) にならないよう、AML の発動に条件を付けています。

- キーを押した・離したあと 200ms (keymap の `zip_temp_layer` の `require-prior-idle-ms`) は発動しない
- 止まっていた状態から動いた量が 10 (`threshold`) に達したら発動する。動いた量は X と Y それぞれ向き付きで足すので、行ったり来たりする振動は打ち消し合う。大きさは「大きいほう + 小さいほうの半分」(√(X² + Y²) の近似)
- 値は加速の後 (カーソルの移動量) で数える。ゆっくり転がすと加速が 0.5 倍なので、ボールのカウントでは約 2 倍になる
- 100ms 以上動きが途切れたら、0 から数え直す
- AML が有効な間は、これまでどおり少しでも動けばタイムアウトが延びる

| 症状 | 変える値 |
| --- | --- |
| まだキー入力の振動で AML になる | `threshold` を上げる (例: 20) |
| キーを離した直後に AML になる | keymap の `zip_temp_layer` の `require-prior-idle-ms` を上げる (例: 300) |
| ボールを少し動かしただけでは AML にならない | `threshold` を下げる (例: 5)。0 にすると、キー入力の直後でなければ動いたらすぐ発動する |

`aml_threshold` ノードは、各キーボードの `trackball_accel` と同じファイルにあります ([カーソルの加速の調整](#カーソルの加速の調整) の表)。
Keyball39 は `qmk_firmware/keyboards/keyball/keyball39/keymaps/via/config.h` の `KEYBALL_AML_THRESHOLD` (待ちは `AUTO_MOUSE_DELAY`) です。

### Keyboard Quantizer Mini + Keyball39 の役割分担

keyball39 (via) は LisM BASE 配列の素の HID コードだけを送り、レイヤー・MT/LT・タップホールド設定
(`&mt` / `&lt` の tapping-term / quick-tap / flavor) は vial-qmk-kq-mini 側の EEPROM デフォルト
(`zmk_to_vial.py` で `lism.keymap` + `lism.vialmap.json` から生成) が担当します。
Quantizer に無いマウスレイヤー (MOUSE_MOVE / MOUSE_SCROLL) と AML の除外キー・タイムアウト・
require-prior-idle・発動のしきい値は keyball39 本体側で LisM の `trackball.overlay` / `&zip_temp_layer` 設定を再現しています。

- マウスレイヤーの修飾キー:
  - AML レイヤーでは、KQ-mini が mod-tap にする位置 (A / - / Z / /) とベースの Win / Alt の位置は `KC_TRNS` です。押すと AML が切れ、ベースと同じ素のキーを送ります。A / - / Z / / は KQ-mini の mod-tap になります (タップで文字、長押しで Ctrl / Shift)
  - スクロールレイヤーでは、同じ位置から素の修飾キー (`KC_LCTL` / `KC_RCTL` / `KC_LSFT` / `KC_RSFT` / `KC_LGUI` / `KC_LALT`) を送ります。KQ-mini はそれをそのまま素通しします
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
| [zmk-input-processor-aml-threshold](https://github.com/ryo-aoki-pc/zmk-input-processor-aml-threshold) | `main` | AML の発動条件の入力プロセッサ (振動などのわずかな動きでは AML にしない)。ZMK の 6 リポジトリが `config/west.yml` でコミットを固定して取り込む |

### QMK/Vial 関連

| リポジトリ | 追跡ブランチ | 用途 |
| --- | --- | --- |
| [vial-qmk-kq-mini](https://github.com/ryo-aoki-pc/vial-qmk-kq-mini) | `custom` | KQ Mini 用 Vial (QMK) ファームウェア。LisM 基準のキーマップ (zmk_to_vial.py で変換) とタップホールド設定 (tapping term 150 / balanced / quick-tap 0) を EEPROM デフォルトとして同梱 |
| [keyball](https://github.com/ryo-aoki-pc/keyball) | `custom` | Keyball 用 QMK ファームウェア (qmk_firmware 0.34.6 でビルド。移植したのは keyball39 だけ)。KQ Mini 併用前提の LisM 基準ベース配列 (keyball39 via)。AML の発動条件・タイムアウト・スクロール速度も LisM のトラックボール設定に合わせる |

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

期待値が submodule の内容と合っていないと、CI (`.github/workflows/keyboard-check.yml`) の `generate.py --check` が失敗します
(submodule のコミットだけが進み、キーマップやトラックボールの設定が変わらないときは失敗しません)。

### ツール (`tools/`)

`tools/` の直下にあるのは、利用者が実行する `.cmd` だけです。

| `.cmd` | 用途 |
| --- | --- |
| `tools/flash.cmd` | [書き込みツール](#書き込みツール-toolsflashcmd) |
| `tools/keyboard-check.cmd` | [キーボードの設定の検査](#キーボードの設定を検査する-toolskeyboard-checkcmd) |
| `tools/keyboard-sim.cmd` | [実機なしのシミュレータ (Windows GUI)](#シミュレータの画面-windows) |
| `tools/input-monitor.cmd` | [入力イベントの記録](#入力イベントを記録して調べる-toolsinput-monitorcmd) |
| `tools/keyball-check.cmd` | [Keyball39 のトラックボールの診断](#keyball39-のトラックボールが動かない場合) |

スクリプトの本体 (`.ps1`) は `tools/scripts/` にあります。`tools/scripts/` には、機種を絞った書き込み用の `.cmd` もあります。
実機なしの自動テストは、[`tools/keyboard-sim.cmd` の画面](#シミュレータの画面-windows) または
[`tools/scripts/keyboard-sim.ps1` のコマンドライン](#実機なしで自動テストする) から実行します。

| `.cmd` | ダブルクリック | ファイルのドロップ |
| --- | --- | --- |
| `tools/scripts/flash-zmk.cmd` | `tools/flash.cmd` と同じウィンドウが開く | ZMK キーボード (XIAO / BMP) の `.uf2` だけを書き込む |
| `tools/scripts/flash-kq-mini.cmd` | KQ-mini を選んだ状態でウィンドウが開く | KQ-mini の `.uf2` だけを書き込む |
| `tools/scripts/flash-keyball.cmd` | Keyball39 を選んだ状態でウィンドウが開く | `.hex` を Keyball39 に書き込む |
| `tools/scripts/flash-uf2.cmd` | (使い方を表示する) | `.uf2` を書き込む ([書き込みスクリプト](#書き込みスクリプト-toolsscriptsflash-uf2cmd)) |

ツールのウィンドウのログ (等幅の文字) は、[HackGen Console NF](https://github.com/yuru7/HackGen) がインストールされていれば、それで表示します
(自分のユーザだけにインストールしたものでも使えます)。無ければ BIZ UDゴシック、それも無ければ MS ゴシックです。

## ファームウェアの書き込み (Windows)

`tools/flash.cmd` (書き込みツール) をダブルクリックするとウィンドウが開きます。機種とビルドを選び、画面の案内に従って書き込みます。ファイルの検証から成否の判定まで、ツールが行います。
選べるビルドは、最新 (custom ブランチの最新ビルド) のほか、PR のビルドと custom の過去のビルドです ([過去のビルドと PR のビルド](#過去のビルドと-pr-のビルド))。

| キーボード | マイコン / ブートローダ | ファイル |
| --- | --- | --- |
| LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa | Seeed XIAO nRF52840 / Adafruit nRF52 UF2 | `.uf2` |
| torabo-tsuki-lp | BLE Micro Pro Boost (nRF52840) / BLE Micro Pro の UF2 (`BLEMICROPRO` ドライブ) | `.uf2` |
| Keyboard Quantizer Mini | RP2040 / ROM ブートローダ (`RPI-RP2` ドライブ) | `.uf2` |
| Keyball39 | Pro Micro (ATmega32U4) / caterina | `.hex` |

手元のファイル (`.uf2` / `.hex`) を書き込むときは、そのファイルを `tools/flash.cmd` にドラッグ＆ドロップします。
`.uf2` はファイルの中身から書き込み先 (XIAO / BMP / KQ-mini) を決め、`.hex` は Keyball39 に書き込みます。

### 書き込みツール (`tools/flash.cmd`)

1. `tools/flash.cmd` をダブルクリックする。コンソールの画面と、書き込みツールのウィンドウが開く。コンソールは、書き込みが終わるまで閉じない (閉じると書き込みも止まる)
2. 左の一覧で機種を選ぶ (前回選んだ機種が選ばれている)
3. 中央の一覧でビルドを選ぶ。最新が先頭で、あとはビルドした日時の新しい順に並ぶ

   | バッジ | ビルド | タグ |
   | --- | --- | --- |
   | 最新 | custom ブランチの最新ビルド (既定) | `firmware-latest` |
   | PR #番号 | PR のビルド。PR を custom にマージした状態のコミットをビルドしたもの。右に PR の状態 (オープン / マージ済み / クローズ) が出る | `firmware-pr-<番号>` |
   | custom | custom ブランチの過去のビルド | `firmware-custom-<sha7>` |

   - 各ビルドには、タイトル (PR のタイトル、またはコミットの件名)、コミット (PR は PR の先頭のコミット)、ビルドした日時、PR のブランチが出る
   - 上の「すべて / PR / custom」で絞り込める。「更新」で一覧を GitHub から取り直す
4. 右の欄で、書き込む内容を選ぶ
   - ZMK: 書き込む内容 (下の表)、右手側 (セントラル) の版 (通常版 / Studio 版 / ログ版)、LisM は左右のトラックボールの有無
   - Keyball39: 台数 (左右 2 台 / 片側 1 台)
   - その下に、書き込む手順とファイルが出る。選んだビルドに無いファイル (後から足したログ版など) があると、理由が出て書き込めない
5. 「書き込む」を押す。必要なファイルを先にすべてダウンロードしてから、手順ごとに書き込む
   - 上の案内に従って、表示された側をブートローダにする ([XIAO をブートローダにする方法](#xiao-をブートローダにする方法)、[torabo-tsuki-lp (BLE Micro Pro Boost) をブートローダにする方法](#torabo-tsuki-lp-ble-micro-pro-boost-をブートローダにする方法))
   - ログに書き込みスクリプトの出力が出る (成功は緑、失敗は赤)。成否の判定は、各スクリプト (`tools/scripts/` の `flash-uf2.ps1` / `flash-keyball.ps1`) が行う
   - 「中止」でいつでも止められる。失敗や中止の後は「再試行」で、その手順からやり直せる (ダウンロードはやり直さない)
   - torabo-tsuki-lp の設定リセットは、書き込んだ後に一度起動させる必要がある。案内に従ってから「続ける」を押す
6. 「完了」と出たら終わり。「戻る」で、別の機種やビルドを書き込める

書き込む内容 (ZMK):

| 書き込む内容 | 書き込む順番 |
| --- | --- |
| 左右に書き込む (既定) | 右 → 左 |
| 設定リセットしてから左右に書き込む | 右 (設定リセット → セントラル) → 左 (設定リセット → ペリフェラル) |
| 右手側 (セントラル) だけ | 右 |
| 左手側 (ペリフェラル) だけ | 左 |
| 設定リセットだけ | 右 → 左 |

補足:

- **既定値**: 書き込む内容と右手側の版は、機種を選ぶたびに「左右に書き込む」「通常版」に戻る (ログ版などを誤って書き込まないため)。機種、LisM のトラックボールの有無、Keyball の台数は前回のものを覚える (`tools/.cache/flash-settings.json`)
- **書き込むキーボードから入力したキー** (ブートローダにするときの `Q` / `P` など) は、ウィンドウが受け取って捨てる。ウィンドウの選択は変わらない
- **ビルドの一覧**は GitHub API から取る。認証なしでは 1 時間に 60 回まで (1 機種で 2〜3 回使う。同じ機種は 10 分間取り直さない)
  - 上限に達したときや、オフラインのときは、前回取得した一覧を出す。それも無ければ最新だけを出す (理由は一覧の上に出る)
  - 環境変数 `GITHUB_TOKEN` (または `GH_TOKEN`) に GitHub のトークンを入れておくと、上限が 1 時間に 5000 回になる (公開リポジトリを読むだけなので、権限を付けないトークンでよい)
- ダウンロードしたファイルは `tools/.cache/firmware/` に保存される (git の管理外)

コマンドラインから実行する場合 (`-List` はウィンドウを出さずに、その機種のビルドとタグの一覧を表示する。ファイルを指定すると、ウィンドウを出さずにそのファイルだけを書き込む):

```powershell
powershell -ExecutionPolicy Bypass -File tools\scripts\flash.ps1 [-Keyboard LisM|AroundFortyRB|KUKEY42|Pyuron|roBa|torabo-tsuki-lp|Keyball39|KQ-mini] [-List] [<ファイル.uf2 / .hex>]
```

### Keyboard Quantizer Mini

1. KQ-mini を PC につないだまま、`tools/flash.cmd` をダブルクリックし、KQ-mini とビルドを選んで「書き込む」を押す
2. ツールが自動で次の処理を行う
   - 選んだビルド (既定は [最新のファームウェア](#最新ファームウェアの取得元-firmware-latest-リリース)) をダウンロードする
   - KQ-mini をブートローダに切り替える (KQ-mini のシリアルポートに `dfu` コマンドを送る)
   - ファームウェアを書き込む
3. 「完了」と表示されれば終わり。KQ-mini の LED が点灯して入力できるようになるまで、数十秒かかることがある

- 自動で切り替わらないとき: KQ-mini を PC につなぎ直してから、もう一度書き込む (KQ-mini のキーマップにはブートローダのキーが無い)
- キーマップ: LisM 基準のキーマップとタップホールド設定は、書き込み後の初回起動時に EEPROM へ自動で適用される (Vial での読み込みは不要)
- 手元の `.uf2` を書き込むとき: そのファイルを `tools/flash.cmd` (または `tools/scripts/flash-kq-mini.cmd`) にドラッグ＆ドロップする

コマンドラインから実行する場合 (ウィンドウを出さずに書き込む。`-Pr` で PR のビルド、`-Tag` で過去のビルド):

```powershell
powershell -ExecutionPolicy Bypass -File tools\scripts\flash-kq-mini.ps1 [<ファイル.uf2>] [-Pr <番号> | -Tag <タグ>]
```

### Keyball39

Keyball は KQ-mini 経由では書き込めません (KQ-mini はキー入力だけを中継するため)。書き込むときは PC に直接つなぎます。

1. `tools/flash.cmd` をダブルクリックし、Keyball39 とビルド、台数 (既定は左右 2 台) を選んで「書き込む」を押す。次の 2 つを自動でダウンロードする
   - 選んだビルド (既定は [最新のファームウェア](#最新ファームウェアの取得元-firmware-latest-リリース))
   - avrdude (初回のみ)。公式の Windows 版 v8.3 を SHA256 で確認してから使う
2. 「1 台目」と表示されたら、片側を KQ-mini から外して USB ケーブルで PC に直接つなぎ、ブートローダを起動する。方法は次のどちらか
   - リセットスイッチを押す。認識されなければ素早く 2 回押す
   - 左手側は `Q`、右手側は `P` を押したまま USB ケーブルを挿す (Bootmagic)
3. COM ポートが現れるとすぐに書き込まれる。成功したら、「2 台目」でもう片側も同じように書き込む
4. 「完了」と表示されたら、Keyball を KQ-mini に接続し直す

補足:

- **Bootmagic**
  - EEPROM も初期化されるため、CPI などの Keyball の設定は既定値に戻る
  - 右手側の `P` が使えるのは、[ryo-aoki-pc/keyball#10](https://github.com/ryo-aoki-pc/keyball/pull/10) 以降のファームウェアから
- **QMK 0.34.6 のファームウェアを初めて書き込んだとき** ([ryo-aoki-pc/keyball#17](https://github.com/ryo-aoki-pc/keyball/pull/17) で QMK を 0.22.14 から上げた)
  - 初回の起動で EEPROM が 1 回だけ初期化され、CPI などの Keyball の設定は既定値に戻る (QMK の EEPROM の形式の番号が変わったため)
  - 左右の通信の形式も QMK のバージョンで変わるので、左右とも書き込む
- **書き込みに失敗したとき**: caterina ブートローダは約 8 秒で終了する。失敗したらもう一度リセットスイッチを押す (1 台につき 3 回まで再試行する)。それでも失敗したら「再試行」を押す
- **手元の `.hex` を書き込むとき**: そのファイルを `tools/flash.cmd` (または `tools/scripts/flash-keyball.cmd`) にドラッグ＆ドロップする

コマンドラインから実行する場合 (ウィンドウを出さずに書き込む。`-Count 1` で片側だけ書き込む、`-Avrdude` で手元の avrdude を使う、`-Pr` で PR のビルド、`-Tag` で過去のビルド):

```powershell
powershell -ExecutionPolicy Bypass -File tools\scripts\flash-keyball.ps1 [<ファイル.hex>] [-Count 1] [-Avrdude <avrdude.exe>] [-Pr <番号> | -Tag <タグ>]
```

### 最新ファームウェアの取得元 (`firmware-latest` リリース)

[keyball](https://github.com/ryo-aoki-pc/keyball)、[vial-qmk-kq-mini](https://github.com/ryo-aoki-pc/vial-qmk-kq-mini)、ZMK の 6 リポジトリの CI は、custom ブランチをビルドするたびに次のことを行います。

- 固定タグ `firmware-latest` のプレリリースを作り直す
- ファームウェアと `BUILD_INFO.txt` (コミット・ビルド日時) を置く

書き込みツールは、既定でここからダウンロードします。

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

ZMK の `<artifact-name>` は各リポジトリの `build.yaml` のもので、全エントリ (左右・Studio 版・ログ版・設定リセット) が置かれます。
ログ版 (`<セントラル>_logging`) は、USB の COM ポートにデバッグログを出す右手側のファームで、
[レイヤーの動きを見る](#レイヤーの動きを見る-ログ版ファーム) と [タップホールドのタイミングを見る](#タップホールドのタイミングを見る) で使います。

- 公開リポジトリのリリースなので、ログインや gh CLI は不要
- Actions の Artifacts と違い、90 日で期限切れにならない
- 最新として書き込まれるのは custom ブランチの最新ビルド。このリポジトリが submodule で参照しているコミットとは限らない
- ダウンロードしたファイルと avrdude は `tools/.cache/` に保存される (git の管理外)

#### 過去のビルドと PR のビルド

同じ CI は、`firmware-latest` のほかに次のプレリリースも作ります (各リポジトリの `.github/scripts/firmware-release.sh`)。
書き込みツールは、GitHub API でリリースの一覧を取り、ビルドを選べるようにしています。ダウンロード URL は、上の表の `firmware-latest` をタグに置き換えたものです。

| タグ | 中身 | 置き換え・削除 |
| --- | --- | --- |
| `firmware-custom-<sha7>` | custom ブランチの各ビルド (`<sha7>` はコミットの先頭 7 桁) | 新しいものから 30 件を残し、古いものは CI が削除する |
| `firmware-pr-<番号>` | PR のビルド。PR を custom にマージした状態のコミット (`refs/pull/<番号>/merge`) をビルドしたもの | PR に push するたびに置き換わる。新しいものから 30 件を残す |

- 選べるのは、この仕組みを入れた後 (2026 年 10 月) のビルドから。それより前のビルドは Actions の Artifacts にしか無い
- PR のビルドを作るのは、同じリポジトリのブランチからの PR だけ (fork や Dependabot の PR は書き込み権限が無いので作らない)。keyball は、keyball39 のコードやワークフローを変える PR だけ
- PR がマージ・クローズされても、PR のビルドは 30 件の枠から外れるまで残る (一覧にはマージ済み / クローズと出る)
- リリースの本文の ```` ```text ```` ブロックと `BUILD_INFO.txt` には、`kind` (custom / pr)、`branch`、`pr`、`title` (PR のタイトル)、`head` (PR の先頭のコミット)、`commit` (ビルドしたコミット)、`subject` (コミットの件名)、`built`、`run` が書かれる。書き込みツールはこれを読んで一覧に出す
- 最新と同じコミットの `firmware-custom-<sha7>` は一覧に出さない。最新を選ぶと、置き換わらないこちらのタグからダウンロードする (ダウンロードの途中で `firmware-latest` が置き換わっても混ざらないように)

### ZMK キーボード

対象:

- LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa (Seeed XIAO nRF52840 + Adafruit nRF52 UF2 ブートローダ)
- torabo-tsuki-lp (BLE Micro Pro Boost + BLE Micro Pro の UF2 ブートローダ。乾電池と電源スイッチ付き)

#### XIAO をブートローダにする方法

次のどれかで切り替える。

- **左手側は `Q`、右手側は `P` を押したまま USB ケーブルを挿す**: Keyball の Bootmagic と同じ操作。押したキーがある側が切り替わる
  - もう片側の電源や接続は要らない (その側だけで判定する)。電源スイッチは ON / OFF のどちらでもよい
  - ドライブが現れるまで押し続け、現れたら離す。電源スイッチが OFF のときは、挿してから起動するまで 1 秒ほどかかる。
    書き込みが終わってもまだ押していると、書き込んだファームウェアがまたブートローダを起動する
  - 押したキーは、ふだんの入力と同じく PC にも送られる。その側が動いていて PC とつながっていると (左手側は右手側を経由)、
    挿すまでの間 `q` / `p` が入力される。気になるときは、電源スイッチを OFF にしてから挿す
  - この機能が入ったファームウェアを一度書き込むまでは使えない (初回はリセットボタンを使う)
- **リセットボタンを素早く 2 回押す**: どの状態でも使える
- 設定リセット用のファームウェアにはキーの処理が無いので、それが動いている側はリセットボタンでしか切り替えられない。
  書き込みツールの「設定リセットしてから左右に書き込む」では、2 番目 (右手側のセントラル) と
  4 番目 (左手側のペリフェラル) を書き込むときがこれにあたる (ツールの案内にも出る)。設定リセット後は左右のペアリングも切れるので、
  3 番目 (左手側の設定リセット) は `Q` + USB で切り替える

#### torabo-tsuki-lp (BLE Micro Pro Boost) をブートローダにする方法

- **電源スイッチを OFF にしてから USB ケーブルでつなぐ**: `BLEMICROPRO` という名前のドライブが現れる。どの状態でも使える
- **電源スイッチを ON のまま、`Q` (左手側) / `P` (右手側) を押しながら USB ケーブルでつなぐ**: XIAO と同じ
  ([XIAO をブートローダにする方法](#xiao-をブートローダにする方法) を参照)。この方法なら、書き込んだファームウェアはそのまま起動する
- 電源スイッチが OFF の状態でブートローダにしたときは、書き込んだファームウェアは、USB ケーブルを抜いて電源スイッチを ON にし、
  USB ケーブルを差し直すと起動する。電源スイッチが OFF のままだと、再起動してもブートローダに戻る

#### ZMK キーボードに書き込む (`tools/flash.cmd`)

[書き込みツール](#書き込みツール-toolsflashcmd) で機種、ビルド、書き込む内容を選んで「書き込む」を押します。

1. 「[1/2] 右手側: セントラル を書き込みます」のように表示されたら、**表示された側の** XIAO をブートローダにする
   (左手側は `Q`、右手側は `P` を押したまま USB ケーブルを挿す、リセットボタンを素早く 2 回押す、など。[XIAO をブートローダにする方法](#xiao-をブートローダにする方法) を参照)。
   書き込みと成否の判定は [書き込みスクリプト](#書き込みスクリプト-toolsscriptsflash-uf2cmd) と同じ
   - torabo-tsuki-lp は、表示された側の電源スイッチを OFF にしてから USB ケーブルでつなぐ (もう片側の USB ケーブルは抜く)。
     書き込んだファームウェアは、USB ケーブルを抜いて電源スイッチを ON にし、USB ケーブルを差し直したときに起動する
   - torabo-tsuki-lp の設定リセットは、書き込んだあとに一度起動させないと動かない。ツールの案内に従って
     スイッチ ON で USB ケーブルを差し直し、数秒待ってから USB ケーブルを抜いてスイッチを OFF に戻し、「続ける」を押す
2. すべて終わると「完了」と表示される。設定リセットを含んだ場合は、PC の Bluetooth 設定から古い登録を削除して再ペアリングする

- **右手側 (セントラル) の版**: 通常版のほか、Studio 版 (ZMK Studio 対応。`_studio`) と、ログ版 (`_logging`。[レイヤーの動きを見る](#レイヤーの動きを見る-ログ版ファーム) と [タップホールドのタイミングを見る](#タップホールドのタイミングを見る) 用) を選べる。
  Studio 版とログ版は、どちらか一方だけ。調べ終わったら通常版に戻す
- **左右を間違えないこと**: 左右の XIAO (torabo-tsuki-lp は BMP) はブートローダの情報が同じなので、ツールからは見分けられない。表示された側だけをブートローダにする
- **途中で失敗したとき**: そこで止まる。「再試行」でその手順から続けるか、「戻る」で選び直す
- **手元の `.uf2` を書き込むとき**: そのファイルを `tools/flash.cmd` (または `tools/scripts/flash-zmk.cmd`) にドラッグ＆ドロップする

コマンドラインから実行する場合 (`-Keyboard` と `-Mode` を両方指定すると、ウィンドウを出さずにコンソールで書き込む。どちらかを省くとウィンドウが開く。`-Pr` で PR のビルド、`-Tag` で過去のビルド):

```powershell
powershell -ExecutionPolicy Bypass -File tools\scripts\flash-zmk.ps1 [-Keyboard LisM|AroundFortyRB|KUKEY42|Pyuron|roBa|torabo-tsuki-lp] [-Mode Both|ResetBoth|Right|Left|ResetOnly] [-Studio | -Logging] [-RightVariant trackball|non_trackball] [-LeftVariant trackball|non_trackball] [-Pr <番号> | -Tag <タグ>]
```

コンソールで書き込むときは、必要なファイルを先にすべてダウンロードしてから、右 → 左の順に書き込みます。途中で失敗すると、残りのファイルの場所を表示します
(もう一度実行するか、表示されたファイルを `tools/flash.cmd` にドロップする)。torabo-tsuki-lp の設定リセットの後は、案内に従ってから Enter を押します。

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

#### 書き込みスクリプト (`tools/scripts/flash-uf2.cmd`)

エラーダイアログを出さずに書き込み、成否をはっきり表示するスクリプトです。

1. `.uf2` ファイルを `tools/scripts/flash-uf2.cmd` にドラッグ＆ドロップする (`tools/flash.cmd` にドロップしても、このスクリプトで書き込む)
2. 「ブートローダのドライブを待っています...」と表示されたら、リセットボタンを素早く 2 回押す
   (または、左手側は `Q`、右手側は `P` を押したまま USB ケーブルを挿す。[XIAO をブートローダにする方法](#xiao-をブートローダにする方法) を参照)。
   既にドライブが出ていればすぐに書き込みが始まります
   - torabo-tsuki-lp (BMP) は、電源スイッチを OFF にしてから USB ケーブルでつなぐ
3. 「成功」と表示されれば完了
   - torabo-tsuki-lp (BMP) は、USB ケーブルを抜いて電源スイッチを ON にし、USB ケーブルを差し直すと起動する

コマンドラインから実行する場合 (ドライブは省略すると自動検出):

```powershell
powershell -ExecutionPolicy Bypass -File tools\scripts\flash-uf2.ps1 <ファイル.uf2> [E:]
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
書き込みツール (`tools/flash.cmd`) で「設定リセットしてから左右に書き込む」を選ぶと、この手順をまとめて行えます。

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
- レイヤーの移動・長押し・モッドモーフ・タップダンス・`&to` の切り替えが、押したときに意図どおりに動かない
  (ビヘイビアの中身はファームに焼き込まれていて、読み出し検査では確かめられない)

ZMK のキーボードでは、自由に押したキーのレイヤーの遷移と解決を見ることもできます ([レイヤーの動きを見る](#レイヤーの動きを見る-ログ版ファーム))。
`&mt` / `&lt` のキーと、一緒に押すキーの組み合わせを押したときの判定のタイミングも、ログ版のファームで、時刻を横軸にしたグラフにリアルタイムに出せます ([タップホールドのタイミングを見る](#タップホールドのタイミングを見る))。

### 使い方

1. `tools/keyboard-check.cmd` をダブルクリックし、機種と検査の内容を番号で選ぶ。接続中の機種には「検出」と表示される

   | 番号 | 検査の内容 |
   | --- | --- |
   | 1 (Enter) | 読み出し検査 + 実動作テスト (キーのタップ → レイヤー・ビヘイビア → トラックボール → 正規化) |
   | 2 | 読み出し検査だけ |
   | 3 | 実動作テストだけ |
   | 4 | トラックボールの正規化だけ (楕円・速さ) |
   | 5 | レイヤー・タップダンス・モッドモーフ・コンボだけ |
   | 6 | [レイヤーの動きを見る](#レイヤーの動きを見る-ログ版ファーム) (ZMK のログ版ファーム。合否は出さない) |
   | 7 | [タップホールドのタイミングを見る](#タップホールドのタイミングを見る) (ZMK のログ版ファーム。選んだキーの組み合わせの判定をリアルタイムに表示。合否は出さない) |

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
| Keyball39 (PC に直結) | キーマップ (全 4 レイヤー)、Ball availability、CPI・スクロールの倍率・AML (しきい値を含む)・カーソルの加速・楕円の補正 (`KEYBALL_SCALE_X` / `_Y`) の設定 | Keyball を PC に直結する (KQ-mini 経由では読めない)。CPI などは [ryo-aoki-pc/keyball#12](https://github.com/ryo-aoki-pc/keyball/pull/12)、AML のしきい値は [ryo-aoki-pc/keyball#16](https://github.com/ryo-aoki-pc/keyball/pull/16) 以降のファームで読める |
| LisM / AroundFortyRB / KUKEY42 / Pyuron / roBa / torabo-tsuki-lp | キーマップ (全 10 レイヤー)、物理レイアウト、ZMK Studio の未保存の変更 | 右手側に ZMK Studio 版を書き込み (`tools/flash.cmd` で右手側の版を「Studio 版」にする)、USB でつなぐ。キーボードの出力を USB にする (BT レイヤー + `U`)。ブラウザの ZMK Studio は閉じる |

ZMK のトラックボールの設定 (スクロールの向き・倍率・AML) は ZMK Studio では読めないので、実動作テストで確かめます。

### 実動作テスト

テスト用のウィンドウで、キーを押したりボールを転がしたりして、PC に届いた入力を期待値と比べます。
どの機種でも、ファームを変えずに USB / BLE のどちらでもできます (リモートデスクトップ越しではできません)。

| 項目 | 合格の条件 |
| --- | --- |
| キーのタップ | BASE レイヤーのキーを 1 つずつタップして、意図したキーが入力される (KQ-mini は、Keyball のキーを KQ-mini が変換した結果で確かめる) |
| AML のクリック | ボールを転がしたあと、`D` を押しながら `F` でクリックになる (文字は入力されない) |
| Shift + クリック | ボールを転がしたあと、`D` → `Z` → `F` で Shift + クリックになる |
| AML の Ctrl / Shift での解除 | ボールを転がしたあと `A` (長押しで Ctrl) をタップすると、AML が切れて `a` が入力される。`Z` (長押しで Shift) も同じ |
| スクロールの向き | `D` を押しながら手前へ転がすと下へ、右へ転がすと右へスクロールする (マウスのホイールと同じ向き) |
| AML のタイムアウト | 10 秒触らないと AML が切れ、`D` を押したまま `F` で文字 (`d` と `f`) が入力される (AML のままだとクリックになる) |
| AML のしきい値 | ボールにそっと触れてカーソルを数ドット (しきい値 10 未満) だけ動かしたあと、`D` を押したまま `F` で文字が入力される (わずかな動きでは AML にならない)。AML のタイムアウトが合格したときだけ行う |

- 右手側のボールは左手のキー (`D` / `F` / `Z` / `A`)、左手側のボールは右手のキー (`K` / `J` / `/` / `-`) で試す
- AML はカーソルがしきい値 (10) 以上動いたときに発動するので、AML のテストでボールの動きが小さすぎたときはやり直しになる
- AML 中の `F` は ZMK では文字になる (`zip_temp_layer` が keymap より先に AML を切る) ので、AML が切れたかは `D` (AML 中はスクロールのキー) を押したまま `F` で確かめる
- Win / Alt でも AML が切れるが、AML 中でも BASE でも同じキーが出るため、実動作テストでは確かめない (設定ファイルの整合と、Keyball のキーマップの読み出しで確かめる)
- テスト中は、Win キーでスタートメニューが開かず、キーボードから送られたクリックはウィンドウの中だけで起きるようにしてある

### レイヤー・ビヘイビアのテスト

キーのタップの次に、レイヤーやビヘイビアを手順どおりに押して、PC に届いた入力を確かめます (メニューの 5 だけでもできる)。
手順と「期待する入力」は、submodule のキーマップから ZMK の動きを真似て作ったもの (`tools/expected/behaviors.py`) です。

| 種類 | 押すもの | LisM の例 |
| --- | --- | --- |
| レイヤーの移動 (押したまま) | `&mo` / `&lt` のキーを押したまま、そのレイヤーのキー。入り方 (どのレイヤーキーか) ごとに 1〜2 キー | `SYM` + `Q` → `1`、`Space` 長押し + `H` → `←`、`VIM_BASE` + `SYM` + `P` → `Home`、`FUNC` + `Q` → `F1` |
| 長押し (mod-tap) | `&mt` のキーを押したまま、反対の手のキー | `A` 長押し + `H` → `Ctrl+H` |
| モッドモーフ | 修飾キーなし / あり (レイヤーの中の Ctrl / Shift のキーを押したまま) | `VIM_BASE` + `U` → `Ctrl+Z`、`VIM_BASE` + `A` (Ctrl) + `U` → `PgUp` (Ctrl は付かない) |
| タップダンス | 決まった回数だけ素早くタップ | `VIM_BASE` + `D` を 2 回 → `Home`、`Shift+End`、`Ctrl+X` |
| レイヤーの切り替え (`&to`) | 切り替わるキー → 全部離す → そのレイヤーのキー → … → BASE に戻るキー → BASE の文字 | `VIM_BASE` + `V` → 離して `N` → `F3`、`SYM` + `P` → `Shift+Home` (VIM_VIS_SYM)、`V` → `→` (BASE に戻る)、`Q` → `Q` |
| コンボ | 同時に押す | (今はどの機種にもコンボが無いので「コンボは定義されていません」と INFO。キーマップに足せば自動でテストに入る) |

テスト用のウィンドウには、手順をグラフィカルに表示します。

- **レイヤーの帯**: この手順で通るレイヤー (`BASE → VIM_BASE → VIM_VISUAL`) と、全レイヤーの結果 (合格は緑、違いは赤)
- **手順のチップ**: 押したまま (レイヤーは紫、修飾キーは橙) + タップ (青) → …
- **キーボードの図**: その手順のレイヤーの表示に切り替わる。押すキーには押す順のバッジ (`1` `2` `×2`) が付き、押さないキー (Bluetooth / 出力切り替え) は赤の斜線
- **期待する入力と実際の入力**: キーキャップで並べ、押すたびに更新する (一致は緑、違いは赤)

判定と安全:

- 順番だけで比べる (時刻は見ない)。修飾キーは左右を区別せず、修飾キーだけの出入り (モッドモーフのマスクなど) は数えない。
  マクロの途中でモーフのキーを先に離したときに付く修飾キー (`Ctrl+X` に付く Shift など) は、付いていても合格
- 違ったら 1 回だけやり直す。ボールやマウスが動いた (AML になった) ときは、失敗にせずやり直す
- `&to` の手順で失敗・スキップ・中止したときは、BASE に戻す手順 (`V` → `Q` など) を案内し、戻ったことを確かめてから続ける
- 押すとキーボードの状態が変わるキー (Bluetooth / 出力切り替え。どれも BT レイヤーにある) とその隣のキーは、手順に入れない。
  FUNC レイヤーは F1 / F6 などで確かめ、PrintScreen などシステムが反応するキーは押さずに読み出し検査で確かめる。
  BT レイヤーと AML のレイヤー (MOUS / SCRL) はこのテストの対象外。
  Win / Alt を押したままにする手順や、`Ctrl+Esc` などシステムが反応する組み合わせも作らない
- マクロは `Ctrl+X` / `Ctrl+V` などを送るので、手順の前に毎回、テスト用のウィンドウが前面かを確かめる (前面でなければクリックを促す)
- 読み出し検査でキーの割り当てが違っていた位置を使う手順は飛ばす
- **KQ-mini**: LisM の手順を Keyball39 の位置に置き換えて、KQ-mini + Keyball39 が LisM と同じに動くかを確かめる。
  キーオーバーライド (モッドモーフ) は、修飾キーより先にタップしたキーを離す。Keyball39 (PC に直結) は BASE を送るだけなので対象外

### レイヤーの動きを見る (ログ版ファーム)

ZMK のキーボードで、**自由に押したキー**がどのレイヤーで、どう解決されたかを表示します (メニューの 6、または `-Mode Trace`)。
PC に届く入力だけでは、レイヤーキーを押した瞬間や `&trans` のフォールスルーは見えないので、キーボードが USB の COM ポートに出す
デバッグログ (ZMK の `zmk-usb-logging`) を読みます。合否は出しません。

準備:

1. 右手側 (セントラル) にログ版を書き込む: `tools/flash.cmd` で機種を選び、書き込む内容を「右手側 (セントラル) だけ」、右手側の版を「ログ版」にする
   (コマンドラインでは `flash-zmk.ps1 -Mode Right -Logging`)。ログ版は ZMK Studio が入っていない
2. 右手側を USB でつなぐ (BLE ではログが出ない)
3. 調べ終わったら、通常版 (または Studio 版) に戻す (ログ版はログを出す分だけ処理が増える。ログでスタックが溢れないよう、
   ログ版だけスレッドのスタックを大きくしてある)

ウィンドウの見方:

- **レイヤー**: 有効なレイヤーが点灯し、有効な最上位のレイヤーを強調する
- **キーボードの図**: 有効な最上位のレイヤーの表示に切り替わり、押しているキーが光る (レイヤーキーは紫)。
  押しているキーは、押したときに決まったレイヤーの表示のまま (VIM_BASE を押したままなら、そのキーは「VIM_BASE」)
- **最後に押したキーの解決** (時系列の行を選ぶと、その行の解決): 上のレイヤーから順に、`&trans` で下へ行ったレイヤー・
  バインディングが決まったレイヤー・見なかったレイヤーを並べる。続けて、ビヘイビアの中
  (ホールドタップがタップかホールドか・何で決まったか、タップダンスの回数と決まり方、モッドモーフでどちらになったか、
  `&mo` / `&to` とレイヤーのオン・オフ) と、送ったキーのキーキャップ
- **時系列**: 押す / 離すごとに 1 行 (新しい順)。ボールで AML になったときなど、キーと関係なくレイヤーが変わったときも 1 行
- 「ログを保存」で、生のログと時系列を `tools/.cache/keyboard-check/trace/` に保存する。生のログには、スレッドごとの
  スタックの最大使用量 (`<inf> thread_analyzer:` の行。30 秒ごと) も入る

- このウィンドウを前面にしておくと、押したキーはどこにも入力されない (Win キーでスタートメニューも開かない)
- モッドモーフの分岐はログに出ないので、押したときの修飾キーと期待値の定義から決める。
  ログのビヘイビアの名前が期待値と違うときは、赤で「期待値と違う」と出る (古いファームや、キーマップが違うファーム)
- ボールを動かすとログが増えて欠けることがある。欠けたら下の行に件数が出るので、ボールに触れずに押し直す
- 左手側 (ペリフェラル) のキーは、ログに押す / 離すの区別が出ないので、交互に数える。ログが欠けて押す / 離すが逆になったら、キーを全部離して「クリア」を押す

### タップホールドのタイミングを見る

ZMK のキーボードで、hold-tap のキー (`&mt` / `&lt`) と一緒に押すキーの組み合わせを決めておき、そのキーを押した瞬間からの判定を、
時刻を横軸にしたグラフにリアルタイムに出します (メニューの 7、または `-Mode HoldTap`)。合否は出しません。

準備は [レイヤーの動きを見る](#レイヤーの動きを見る-ログ版ファーム) と同じです (右手側にログ版のファームを書き込み、USB でつなぐ)。
KQ-mini と Keyball39 は対象外です (KQ-mini は判定のログを出さないため)。

キーの組み合わせの選び方:

1. ウィンドウを開くと、「① hold-tap のキー (A や Space など) を押してください」と出ます。調べる hold-tap のキー (例: `A (Ctrl)`) を押します
   - hold-tap でないキーを押したときは、下にそのことが出て、待ち続けます
2. 「② A (Ctrl) と一緒に押すキーを押してください」と出たら、一緒に押すキー (例: `H`) を押します
3. 左の欄に `A (Ctrl) + H` と出たら、選び終わりです。その hold-tap (`&mt` / `&lt`) の設定が下に出ます

- 選んでいるあいだに押したキーは、グラフに出しません
- 別の組み合わせにするときは「押して選び直す」を押します。選んでいる途中の「やめる」で、前の組み合わせに戻ります

ウィンドウの見方:

- **押している間**: hold-tap のキーを押した瞬間を 0 ms にして、「今」の線 (`今 87 ms`) が右へ進みます
  - 押しているキーの帯も伸び、判定や PC に届くキーは、その時刻が来たところで現れます
  - 上の結果には、今離したときの結果が出ます (例: 「今離すと: タップ → A。150 ms を過ぎると ホールド (時間切れ) → Ctrl」)
- **1 回分の終わり**: 選んだキーを全部離すと、その回をそのまま残します。次に hold-tap のキーを押すと、その回に切り替わります
  - 押したままでも、tapping-term + 100 ms (150 ms なら 250 ms) で打ち切ります。押していたキーは右端まで伸ばし、上の結果に「250 ms (tapping-term + 100 ms) で打ち切った」と出ます
  - 横軸の右端は、押している最中から tapping-term + 100 ms です
- **選んでいないキー**: 選んだキーを押している途中に、ほかのキーを押した回は出しません。下に「J を押したので、この回は出しません」と出て、前の回のグラフに戻ります
  - 選んだキーを全部離したあとに押したときは、その回をそこで終えて残します
- **押したキー**: 選んだ 2 つのキーの帯 (押す → 離す)。一緒に押すキーは、押さなかった回でも行を出します。hold-tap のキーは、判定までを「判定待ち」、そのあとをタップ / ホールドの色で塗ります
- **PC に届く入力**: 届いたキー・修飾キー・レイヤーの帯。判定まで保留されたキーには、押した時刻から送られた時刻へ矢印を引きます
  - 行は、組み合わせで届きうるもの (例: `A (Ctrl) + H` なら A・Ctrl・H) を前もって並べます。押している最中に行が増えて、下の帯がずれることはありません
- **線**: 縦線の上端には番号だけを付け、何の線かはグラフのすぐ下に、番号・線の見本と合わせて並べます (例: `① tapping-term (150 ms)`、`② 判定: タップ (140 ms)`)
  - tapping-term (橙の破線)、判定 (青)、ファームの判定 (赤の破線。計算と違うときだけ)、離した時刻 (白。全部離したあと、下の帯の上)
  - 「今」の線 (緑) には、線の上に `今 87 ms` と出します
- **(キー) を離す時刻ごとの結果**: 対象のキーを離す時刻を 1 ms ずつ動かしたときの結果を、同じ結果の区間ごとに色分けした帯です
  - 例: `〜130 ms: タップ → A H / 131 ms〜: ホールド (ほかのキー) → Ctrl+H`
  - 全部離したあとは、実際に離した時刻に線を引きます
- **flavor ごとの比較**: 同じ帯を 4 つの flavor で並べます。行を押すと、その flavor に切り替わります

設定 (左の欄):

- 今の回の hold-tap (`&mt` / `&lt`) の flavor と tapping-term を変えると、同じ入力をその設定で計算し直します。キーボードには書き込みません
- 「キーマップの値に戻す」で、キーマップの値 (LisM は balanced / 150 ms) に戻ります
- 設定を変えて、ファームの判定 (キーマップの値) と違う結果になったときは、上の結果に「ファームの判定は … 設定を変えたので違う」と出ます

| flavor | ホールドになるとき |
| --- | --- |
| `hold-preferred` | ほかのキーを押したとき、または tapping-term が過ぎたとき |
| `balanced` (LisM 基準) | ほかのキーを押して離したとき (包んだとき)、または tapping-term が過ぎたとき |
| `tap-preferred` | tapping-term が過ぎたときだけ |
| `tap-unless-interrupted` | ほかのキーを押したときだけ (tapping-term が過ぎるとタップ) |

注意:

- 計算には、ZMK v0.3.0 の `behavior_hold_tap.c` を移植したシミュレータを使います
  - ZMK の `app/tests/hold-tap` のテストと同じ結果になることを確かめています
  - flavor と tapping-term 以外の設定 (quick-tap など) は、キーマップの値のままです
- ちょうど tapping-term の時刻に離すとホールドになります (タイマーが同じ時刻の入力より先に処理されるため)。帯の境目の前後 1 ms は、実機ではどちらにもなり得ます
- 時刻は、右手側 (セントラル) がキーの入力を受け取った時刻です。左手側 (ペリフェラル) のキーは BLE で届くまでの分だけ遅れますが、hold-tap の判定もこの時刻で行われます
- ログは、キーボードの中で最大 0.1 秒ほどまとめてから送られます
  - そのため、押したキーや判定が少し遅れて現れることがあります
  - 時刻はログに書かれた時刻を使うので、グラフの上の位置はずれません
- 設定を変えていないのにファームの判定が計算と違うときは、次のどちらかです。キーを全部離して押し直してください
  - 左手側のキーの押す / 離すを数え違えた
  - ファームのキーマップが期待値と違う
- ログが欠けた回は、上の結果にそう出ます
- このウィンドウを前面にしておくと、押したキーはどこにも入力されません

### トラックボールの正規化 (楕円補正・速さ)

検査の内容で「4. トラックボールの正規化だけ」(または 1 / 3) を選ぶと、次の 2 つを測って、補正の推奨値を出します。
ファームや overlay は書き換えないので、推奨値を反映して書き込んだあと、もう一度測って確かめます。

**楕円 (X / Y の比率)**: ボールを円を描くように、右回りで 10 秒、左回りで 10 秒回します。
カーソルが楕円ではなく円を描くよう、画面の X と Y に別々に掛ける倍率を求めます。傾きは補正しません
(傾いた楕円は、軸ごとの倍率で直せる分だけ直し、残る縦横比を「補正後の予想」に出します)。
X と Y の比 (√(X の分散 / Y の分散)) が 1.10 を超えると WARN になり、設定に入れる行を出します。1.10 以下なら PASS (変更不要) です。

| 機種 | 入れる場所 | 出す行の例 |
| --- | --- | --- |
| LisM | 右のボール: `snippets/trackball-central/trackball.overlay` の `central_listener`。左のボール: `snippets/trackball-central/trackball.overlay` と `snippets/non-trackball-central/non_trackball.overlay` の `peripheral_listener` (両方に同じ値) | `<&zip_x_scaler 17 12>, <&zip_y_scaler 7 10>` |
| Pyuron | `boards/shields/Pyuron/Pyuron.dtsi` の `trackball_listener_L` / `trackball_listener_R` | 同上 |
| AroundFortyRB / roBa | `AroundForty-RB_R.overlay` / `roBa_R.overlay` の `trackball_listener` | 同上 |
| KUKEY42 | `KUKEY42_R.overlay` の `trackball_listener` (今の値 `<&zip_x_scaler 1 2>, <&zip_y_scaler 13 12>` を置き換える) | 同上 |
| torabo-tsuki-lp | `torabo_tsuki_lp_right.overlay` の `pointing_listener` | 同上 |
| Keyball39 / KQ-mini | `keyball/qmk_firmware/keyboards/keyball/keyball39/keymaps/via/config.h` (KQ-mini はマウスを等倍で中継するので Keyball39 の値) | `#define KEYBALL_SCALE_X 1414` と `#define KEYBALL_SCALE_Y 707` |

- ZMK は、listener の `input-processors` の `zip_xy_transform` (向き) の後・`<&trackball_accel>` の前に入れる (加速は補正後の値で速さを測るため)。
  値は分母 16 以下の分数で、それで表せる範囲で直す (例: 1.03 倍のようなわずかなずれは 1/1 のまま)
- Keyball39 は 1000 = 等倍 (500〜2000)。`KEYBALL_SCALE_*` の無い古い keyball では、測った値を表示するだけ
- すでに倍率が入っていれば、今の値に補正を掛けた値を出す (測り直すたびに円に近づく)。全体の速さ (X と Y の倍率の積) は変えない
- 手順: 測る → 出た行を submodule のリポジトリの `custom` ブランチに PR で入れる → CI のビルドを `tools/flash.cmd` で書き込む →
  もう一度測って PASS を確かめる → このリポジトリの submodule の参照を更新する (期待値の今の値も更新される)
- 推奨値は期待値 (このリポジトリが参照している submodule) の今の値に掛けて出すので、書き込んだファームと submodule の参照をそろえてから測る

楕円の当てはめは「KUKEY42 真円計測」ページと同じです (移動量の共分散)。
このスクリプトは Raw Input で、そのボールの値だけを OS の加速の前に測るので、補正の強さは 100% のまま使えます (`-CalibStrength` で変えられる)。

キーボードのファームの[カーソルの加速](#カーソルの加速の調整) (ZMK の `trackball_accel`、Keyball39 の `KEYBALL_ACCEL_*`) は、
測った移動量から取り除いてから計算します。加速の後の値のままだと、速く動く長軸の向きほど大きく出て楕円が実際より細長くなり、
速さも転がす速さで変わってしまうためです。取り除く計算はファームの処理と完全には同じではありませんが、
ファームの処理を真似た計算での確認では、縦横比と 1 回転あたりのカウントの誤差は 3% 以内です。

**速さ (キーボード間)**: ボールに印を付け、右へちょうど 2 回転を 2 回、手前へちょうど 2 回転を 2 回転がします。
ボールの直径を入れると、指の移動量あたりの速さ (実効 CPI) で比べます。
速さも測るかは、メニューで選んで始めたとき (`-Keyboard` か `-Mode` を省略したとき) に尋ねます。
両方を指定したときは、`-Speed` を付けると測ります ([コマンドライン](#コマンドライン))。

- 最初に LisM で測ると、基準として `tools/.cache/keyboard-check/trackball.json` に保存される (`-SpeedReference` でも指定できる)
- ほかの機種で、基準との差が ±10% を超えると WARN になり、推奨値を出す: PMW3610 の機種 (KUKEY42 / AroundFortyRB / roBa) は CPI、
  ZMK は `<&zip_xy_scaler n d>` (`<&trackball_accel>` より前)、Keyball39 は `KEYBALL_CPI_DEFAULT`。
  CPI を変えられる機種は CPI を先に出す (倍率を 1 より大きくすると、1 カウントでカーソルが 2 以上動き、細かさが落ちるため)
- Keyball39 は 1 回の報告が ±127 で頭打ちになるので、速く回しすぎたときはやり直しを促す

### 判定と対処

| 結果 | 原因と対処 |
| --- | --- |
| KQ-mini のキーマップなどが FAIL | Vial で変えた内容が残っている。Vial の「File → Load saved layout」で `vial-qmk-kq-mini/keyboards/sekigon/keyboard_quantizer/mini/keymaps/vial/KEYMAP.vil` を読み込む。新しいビルドを `tools/flash.cmd` で書き込んでも戻る (同じビルドの書き直しでは戻らない) |
| Keyball39 の CPI / スクロールの倍率が FAIL | EEPROM に古い値が残っている。Bootmagic (左手側は `Q`、右手側は `P` を押しながら USB を挿す) で初期化する |
| Keyball39 のカーソルの加速が FAIL | `config.h` の `KEYBALL_ACCEL_*` が違うファームが書き込まれている。`tools/flash.cmd` で最新のファームを書き込む |
| Keyball39 の楕円の補正が FAIL | `config.h` の `KEYBALL_SCALE_X` / `_Y` が期待値と違うファームが書き込まれている。`tools/flash.cmd` で最新のファームを書き込むか、[submodule を最新に更新](#submodule-を最新に更新) する |
| 楕円が WARN | 出た行 (Details) を [入れる場所](#トラックボールの正規化-楕円補正速さ) に入れてビルドし、書き込んでからもう一度測る。ZMK の倍率はキーボードから読み出せないので、測り直して確かめる |
| ZMK のキーマップが FAIL | ZMK Studio で保存した変更が残っている。Studio の「Restore Stock Settings」か、`tools/flash.cmd` の「設定リセットしてから左右に書き込む」 |
| ZMK の読み出しが SKIP (応答がない) | キーボードの出力が BLE になっている。BT レイヤーのキーを押しながら `U` (`&out OUT_USB`) で USB に切り替える |
| スクロールの向きが FAIL | overlay の `zip_xy_transform` (`X_INVERT` / `Y_INVERT` / `XY_SWAP`) を確かめる |
| AML のクリックが FAIL (文字が入力された) | AML (ZMK の `zip_temp_layer` / `aml_threshold`、Keyball の `AUTO_MOUSE_*`) が動いていない。ボールの動きが小さすぎたときは FAIL ではなくやり直しになる |
| AML のしきい値が FAIL (わずかな動きでクリックになった) | しきい値の無い古いファームが書き込まれている。`tools/flash.cmd` で最新のファームを書き込む |
| Keyball39 の AML のしきい値が SKIP / FAIL | SKIP はしきい値の無い古いファーム、FAIL は `config.h` の `KEYBALL_AML_THRESHOLD` が違うファーム。`tools/flash.cmd` で最新のファームを書き込む |
| レイヤー・ビヘイビアのテストが FAIL (ZMK) | ファームが古いか、キーマップのビヘイビア (mod-morph の mods、tap-dance、マクロ) が意図と違う。`tools/flash.cmd` で最新のファームを書き込む。どこで違うかは [レイヤーの動きを見る](#レイヤーの動きを見る-ログ版ファーム) で確かめられる |
| レイヤー・ビヘイビアのテストが FAIL (KQ-mini) | Vial で変えたタップダンス・キーオーバーライド・マクロが残っている。Vial の「File → Load saved layout」で `KEYMAP.vil` を読み込む。モッドモーフの手順は、修飾キーより先にタップしたキーを離してやり直す |
| AML の Ctrl / Shift での解除が FAIL (修飾キーだけが入力された) | Ctrl / Shift で AML を解除しない古いファームが書き込まれている。`tools/flash.cmd` で最新のファームを書き込む。長押しになった場合 (Ctrl / Shift になる) は、短く押してやり直す |
| 読み出し検査は PASS なのに、タップホールドや AML の動作が意図と違う | [入力イベントを記録して調べる](#入力イベントを記録して調べる-toolsinput-monitorcmd) で、PC に届いたキーとタイミング (押下時間、修飾キーが出た時刻、ボールの移動からの経過) を見る。ZMK では、タップホールドがどの時刻に何で決まるか (離す時刻や flavor を変えるとどうなるか) を、[タップホールドのタイミングを見る](#タップホールドのタイミングを見る) で確かめられる |

- 一覧の最後の「設定ファイル (参考)」は、submodule の設定ファイルどうしの整合です (キーボードは見ていない)。
  例: LisM は、左ボールのスクロールの処理が右手側の版 (trackball / non_trackball) で違うため、WARN になります
- 期待値は、このリポジトリが参照している submodule のコミットから作ります。書き込みツールは既定で custom ブランチの最新を書くため、
  submodule の参照が古いと、意図どおりでも FAIL になることがあります。そのときは
  [submodule を最新に更新](#submodule-を最新に更新) してから検査します

### コマンドライン

`-Keyboard` と `-Mode` を両方指定すると、メニューを出さずに検査します。

```powershell
powershell -ExecutionPolicy Bypass -File tools\scripts\keyboard-check.ps1 [-Keyboard KqMini|Keyball39|LisM|AroundFortyRB|KUKEY42|Pyuron|roBa|torabo-tsuki-lp] [-Mode All|Readout|Interactive|Trace|HoldTap] [-Section All|Keys|Behaviors|Trackball|Calibrate] [-Ball right|left|both] [-Port COM5] [-Speed] [-Diameter <mm>] [-SpeedReference <実効CPI>] [-CalibStrength <0-100>] [-Report <ファイル>]
```

終了コードは、0 = FAIL なし、1 = FAIL あり、2 = 検査できた項目がない、です (`-Mode Trace` / `-Mode HoldTap` は合否を出さないので 0)。

## 実機なしで自動テストする

`tools/scripts/keyboard-sim.ps1` は、キーの押下・解放とボールの移動を仮想時計で処理し、
HID キー出力・レイヤー・マウス出力を JSON の期待値と比較します。実時間の待機や画面操作は不要です。
シミュレータ本体、シナリオ、テスト、CI はすべてこの親リポジトリにあります。
submodule は設定の読み取り元であり、ファイルや参照コミットを書き換えません。

### シミュレータの準備と実行

Python 3.10 以上を用意します。Windows の GUI は標準の Windows PowerShell 5.1 で動作します。
以下のコマンドラインの例は PowerShell 7 を使い、親リポジトリのルートで実行します。
Python の追加パッケージやファームウェア用ツールチェーンは不要です。
必要な submodule だけを、親が固定したコミットで取得できます (孫 submodule の取得は不要)。

```bash
git submodule update --init --depth 1 \
  zmk-keymap-docgen zmk-config-LisM zmk-config-KUKEY42 zmk-config-AroundFortyRB \
  zmk-config-Pyuron zmk-config-roBa zmk-keyboard-torabo-tsuki-lp keyball \
  vial-qmk-kq-mini zmk-input-processor-xy-accel zmk-input-processor-aml-threshold
```

```powershell
pwsh -NoProfile -File tools/scripts/keyboard-sim.ps1 -ReportJson tools/.cache/simulator/results.json -ReportJUnit tools/.cache/simulator/results.xml
```

既定では `tools/simulator/scenarios/` 内の JSON を名前順に実行します。
`-Scenario <ファイルまたはフォルダ>` で入力を変更し、`-Board lism` などで機種を絞れます。
Python のコマンド名が `python3` の環境では `-Python python3` を指定します。
終了コードは、全件成功で `0`、期待値の不一致・設定不備・未対応処理・対象 0 件で `1` です。
JSON レポートには実際の出力と参照した設定のコミット、JUnit レポートには各シナリオの成否が入ります。

機種 ID は `lism` / `kukey42` / `aroundfortyrb` / `pyuron` / `roba` / `torabo-tsuki-lp` / `keyball39` / `kq-mini` です。
`-Board keyball-kq-mini` は Keyball39 の HID キー出力を KQ-mini に渡す連携を検査します。
この場合の `pos` は Keyball39 の物理位置で、`expect` は KQ-mini を通したキー・レイヤーとマウス出力を比較します。
マウスボタンも KQ-mini の入力として処理するため、クリックによるタップホールドの確定を検査できます。
Keyball39 側の出力も JSON レポートの `actual.upstream` に記録します。
実行時にチェックアウト中のキーマップ・設定を読み込みます。`tools/expected/*.json` をシミュレーションの入力には使いません。
キー位置や各レイヤーの割り当ては、次のコマンドの `keys[].pos` / `keys[].on` で確認できます。

```bash
python tools/simulator/export_model.py --keyboard lism
```

### シミュレータの画面 (Windows)

上の準備後、`tools/keyboard-sim.cmd` をダブルクリックすると、機種とシナリオを選ぶ画面が開きます。
USB / BLE のキーボードを接続する必要はありません。

1. 機種とシナリオを選び、「選択を実行」または「この機種を全件実行」を押す。
   実行中は「中止」で止められます。中止した回は合格になりません。
2. 結果一覧でシナリオを選び、入力・期待値・実際の出力を確認する。失敗した場合はエラーの詳細も表示されます。
3. 時刻スライダーや「再生 / 一時停止」で、キーボード図の押下位置、出力キー、有効レイヤー、マウスの状態を確認する。
   再生は記録を画面上で確認する機能です。KQ-mini 単体は入力の HID キー一覧、Keyball39 → KQ-mini は Keyball39 の配列を表示します。

独自のシナリオは「JSON を開く」から読み込むか、JSON ファイルを `tools/keyboard-sim.cmd` にドラッグ＆ドロップします。
「標準に戻す」で、同梱の `tools/simulator/scenarios/` を読み直します。
期待値は JSON で管理し、GUI から自動生成・書き換えは行いません。

実行ごとに `tools/.cache/simulator/gui/<実行ごとのフォルダ>/` に入力のコピー `scenario.json` を保存し、
完了時に結果の `results.json` / `results.xml` を保存します。「レポート」から保存先を開けます。
実行と合否判定はコマンドラインと同じシミュレータを使います。

起動時の機種・シナリオ・Python を指定する場合:

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File tools/scripts/keyboard-sim-gui.ps1 -Scenario tools/simulator/scenarios -Board lism -Python python
```

### シナリオを書く

次は LisM の位置 `0` (Q) を 50ms 押す例です。JSON を親リポジトリの `tools/simulator/scenarios/` に追加します。
期待値は仕様から定め、実際の出力をそのままコピーして正解にはしません。

```json
{
  "schema": 1,
  "scenarios": [{
    "name": "q-tap",
    "board": "lism",
    "events": [
      {"t": 0, "type": "press", "pos": 0},
      {"t": 50, "type": "release", "pos": 0}
    ],
    "end_ms": 100,
    "expect": {
      "keys": [
        {"t": 0, "usage": 20, "down": true, "mods": 0},
        {"t": 50, "usage": 20, "down": false, "mods": 0}
      ],
      "layers": [],
      "mouse": [],
      "state": {"layers": [0], "keys": [], "buttons": 0}
    }
  }]
}
```

| 項目 | 意味 |
| --- | --- |
| `t` / `end_ms` | 開始からの整数ミリ秒。入力は時刻順で `end_ms` 以下に並べ、最後までタイマーを処理する |
| `press` / `release` | `pos` のキーを押す・離す。押下と解放は対応させる |
| `move` | `{"t": 250, "type": "move", "side": "right", "x": 20, "y": 0}` のように左右のボールの移動を指定する。`x` / `y` は listener の軸変換前のドライバ出力 (整数、−32767〜32767)、`side` の既定は `right` |
| `advance` | `{"t": 10000, "type": "advance"}` のように、入力せず時間を進める |
| `expect.keys` | `t`、HID `usage`、押下 `down`、修飾ビット `mods` の配列 |
| `expect.layers` | `t`、レイヤー番号 `layer`、有効化 `down` の配列 |
| `expect.mouse` | `t`、`x`、`y`、`wheel`、`hwheel`、ボタンのビットマスク `buttons` の配列 |
| `expect.state` | 終了時の有効レイヤー `layers`、押下中の HID usage `keys`、`buttons` |

`expect` は 1 項目以上必要です。指定した出力の配列は**件数と順序も含めてすべて**比較します。
各出力のフィールドは省略できるため、時刻を検査しない場合は `t` を省けます。
`"keys": []` はキー出力がないことを検査し、`keys` 自体を省略するとキー出力を検査しません。
`"expect": {"state": {"layers": [0]}}` のように、終了時の状態だけを検査することもできます。
存在しないキー、未知の検証項目、未対応・近似の処理は成功扱いにしません。

同時刻のボール入力・予約された処理はキー入力より先に実行し、同種の入力は記述順を保ちます。
ZMK のタップホールドは同時刻のキー入力よりタイムアウトを先に判定します。
QMK は物理キー入力を処理してから、アイドル時のタッピング判定を進めます。
境界を検査するときは、この順序も期待値に含めてください。

### 検証範囲と CI

ZMK / QMK のタップホールド、レイヤー切替、ZMK の mod-morph・tap-dance・マクロ、
Vial のタップダンス・マクロ・キーオーバーライドをシナリオから検証します。
Bluetooth プロファイル切替など、再現していない処理を実行すると失敗します。
ボールは軸変換・加速・スクロール・AML の発動、延長、解除を検証します。
1 件の `move` は X → Y (同期) の順で揃ったドライバ入力フレームとして、USB 接続時の論理処理を再現します。
ZMK は入力フレームを即時処理し、Keyball39 は 8ms ごとのポーリングで処理するため、入力時刻と出力時刻が異なることがあります。
KUKEY42 のドライバ内スクロールは未対応で、その操作を含むシナリオは失敗します (カーソル移動は対応)。

Keyball39 → KQ-mini のマウス連携は、固定された実装と `KEYMAP.vil` の設定を確認し、
マウス入力が既定の割り当てで、ジェスチャーが無効の場合に検証します。
マウスの割り当てやジェスチャーなどを変更した設定では、連携のマウス操作を含むシナリオは失敗します。
また、同じ連携シナリオでホイール出力とキーボードのキー出力が混在する場合は未対応として失敗します。
キー出力を伴わないカーソル移動・ホイール、マウスボタンの連携は検証できます。

これは設定から動作を計算するモデルであり、ファームウェアそのものを動かすエミュレータではありません。
USB / BLE の通信や BLE 送信のまとめ処理、スムーズスクロールの通信、実機のセンサー・割り込み・EEPROM、Windows の画面は別途実機で検証します。

シミュレータの単体テストと、既存の検査ツールの回帰テストは次のコマンドで実行できます。

```powershell
python -m unittest discover -s tools/simulator -v
python -m unittest discover -s tools/expected -v
pwsh -NoProfile -File tools/tests/run.ps1
```

ウィンドウの描画など Windows 専用のテストは、ツールと同じ Windows PowerShell 5.1 で実行したときだけ動きます (pwsh では SKIP になります)。
Windows ではそれらも含めて、次のコマンドで実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\tests\run.ps1
```

`.github/workflows/keyboard-check.yml` は Linux で設定の整合性、単体テスト、同梱シナリオを実行します。
JSON / JUnit レポートは失敗時も `simulator-results` artifact に保存します。
Windows PowerShell 5.1 のジョブでも同じ固定コミットの submodule と Python を用意し、
実機なしでライブラリと各機種の設定を使うテストを実行します。

## 入力イベントを記録して調べる (`tools/input-monitor.cmd`)

ファームウェアの動作を PC 側から観察するためのツールです。つないでいるすべてのキーボード・マウスから届いた入力 (キー、ボールの移動、クリック、ホイール) を、
デバイスごとに µs 精度のタイムスタンプ付きで記録し、停止したあとに次の 3 つを分析して報告します。
キーボードの設定は読まず、書き換えもしません。ファームを変える必要はなく、USB / BLE のどちらでも使えます。

| 分析 | 分かること |
| --- | --- |
| キーの時系列 | 押した・離した時刻、押下時間、同時に押していたキー。タップホールド (`&mt` / `&lt`、KQ-mini の mod-tap) でどのキーがいつ出たかの手がかり。修飾キーが別のキーと同時に (2ms 以内に) 出ていれば、ファームがホールドと判定した証拠 |
| AML (オートマウスレイヤー) | キーやクリックが、同じキーボードのボールの直前の移動から何 ms 後だったか。10 秒のタイムアウトのあとか、修飾キーで解除したあとかが分かる |
| マウスレポートの間隔 | 移動のレポートの到着間隔の中央値・p95・分布と、「停滞 → まとめて到着」の回数。[複数台 BLE のカクつき](#zmk-キーボードを複数台-ble-で同時接続するとカーソルがカクつく場合) の表の間隔 (15〜16ms) と比べる |

### 記録の手順

1. `tools/input-monitor.cmd` をダブルクリックする。接続中のキーボード・マウスの一覧 (機種名と USB / BLE) が表示され、記録用のウィンドウが開く
2. 別のアプリ (メモ帳など) にキーを入力したり、ボールを転がしたりする。ウィンドウが前面でなくても記録される。
   ウィンドウには、キーの押す・離す (押下時間付き)、クリック、ホイールが 1 行ずつ、ボールの移動は連続した区間ごとにまとめて表示される
3. 「停止」を押す (またはウィンドウを閉じる) と、分析の結果がコンソールに表示される

- 「マーク」はログに区切りを入れる (報告の最後に時刻が載る)。「クリア」はそこまでの記録を捨てる
- ウィンドウが前面のときは、記録中のキーボードの Alt や Win でメニューが開かないよう、キーを飲み込む (Ctrl+C / Ctrl+A でログのコピーはできる)
- 記録は `tools/.cache/input-monitor/<日時>.csv` (イベント。Excel で開ける) と `.json` (デバイスの一覧など)、報告は `.txt` に保存される
- リモートデスクトップ越しでは記録できない (Raw Input が届かない)

### 報告の読み方

**マウスレポートの間隔**: デバイスごとに、移動のレポートの間隔の中央値・p95・最大と分布を出します。
USB なら 1ms か 8ms 付近、BLE の ZMK なら 15〜16ms 付近に集中していれば正常です。

| 用語 | 意味 |
| --- | --- |
| 停滞 → まとめて到着 | `-GapMs` (既定 50ms) 以上空いた直後に、中央値の 6 割以下の間隔で 3 件以上が続けて届いた。キーボード側に溜まったレポートが一気に届いた状態で、カーソルが止まってから飛ぶ原因。空きが `-IdleMs` (既定 300ms) 以上なら、ZMK が溜められる 20 件を超えて移動量が捨てられた疑い |
| 途切れ | `-GapMs` 以上空いたが、まとめては届いていない (レポートが抜けたか、一瞬止めた) |
| 停止 | `-IdleMs` 以上空いた。手を止めたとみなし、統計から除く |

「見立て」は目安です。停滞が 3 回以上あり動いていた 1 分あたりでも 3 回以上か、p95 が中央値の 2 倍を超えると「BLE の送信が詰まっている可能性」と表示します (USB のデバイスなら BLE の問題ではない)。

**キーの時系列**: キーとマウスボタンの押す・離すを時刻順に並べ、直前の操作からの経過、押下時間 (150ms 以上は「長押し」)、押した時点で押されていた他のキーを載せます。
ZMK の `&mt` / `&lt` は balanced なので、ホールドと判定された修飾キーは別のキーの押下と同時に出ます (「他キーと同時に出力 (ホールド判定)」)。
タップのつもりが修飾キーになったときは、この行と押下時間を見ると、tapping-term (150ms) との関係が分かります。

**AML**: ボールを転がしたあとのキー・クリックごとに、直前の移動からの経過を載せます。「AML 中 (クリック)」「移動から n 秒以内に文字」「AML 終了後 (10 秒超)」「修飾キー (AML が切れる契機)」で、
[共通基盤](#共通基盤) の AML のとおりに動いているかを確かめます。Keyball39 + KQ-mini のように、キーボードとマウスが別の USB インターフェイスになっている場合は、同じ VID / PID のマウスと組にします。

### input-monitor のコマンドライン

```powershell
powershell -ExecutionPolicy Bypass -File tools\scripts\input-monitor.ps1 [-Seconds <秒>] [-ShowMotion] [-GapMs 50] [-IdleMs 300] [-Top 10] [-OutDir <フォルダ>] [-Report <ファイル>]
powershell -ExecutionPolicy Bypass -File tools\scripts\input-monitor.ps1 -Analyze <記録の .csv または .json> [-Report <ファイル>]
```

- `-Seconds` を指定すると、その秒数で自動的に停止する
- `-ShowMotion` は、ウィンドウにボールの移動を 1 件ずつ (前の移動からの間隔付きで) 表示する
- `-Analyze` は、保存した記録を分析し直す (Windows 以外の PowerShell でも動く)
- 終了コードは、0 = 記録して分析した、1 = 失敗、2 = イベントが無かった、です

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

- まず [入力イベントを記録して調べる](#入力イベントを記録して調べる-toolsinput-monitorcmd) で記録し、「停滞 → まとめて到着」の回数と間隔の分布を見る (上の表の間隔と比べる)
- 使っていないキーボードの電源を切る
- KUKEY42 / roBa / AroundFortyRB は、右手側の overlay の `<&trackball_rate_limit 15>` を `30` (32ms ごと) に上げる。
  カーソルの動きは粗くなるが、送る量が半分になる

## LisM を USB でつなぐと操作できなくなる場合

動いている LisM に USB ケーブルを挿したとき、次のようになるなら、ファームウェアが止まっています。

- キーもトラックボールも入力できなくなる
- USB を抜いても戻らない (USB を抜いて電源を入れ直すと、Bluetooth で使えるようになる)

原因は、充電中の LED 表示 ([4mplelab/zmk-feature-charge-indicator](https://github.com/4mplelab/zmk-feature-charge-indicator)) です。
充電状態のピン (STAT) の割り込みの中で `k_sleep` していました。USB を挿す・抜くときは充電状態が続けて変わるので、
カーネルのタイムアウトの一覧が壊れ、ファームウェア全体が止まります (USB を抜いたときに止まることもあります)。

- [ryo-aoki-pc/zmk-config-LisM#26](https://github.com/ryo-aoki-pc/zmk-config-LisM/pull/26) で直した
  (充電中の LED 表示は、LisM の `src/charge_indicator.c` に取り込んだ)
- それより前のビルドには、この不具合がある (書き込みツールで選べる過去の custom のビルドも含む)。
  [書き込みツール](#書き込みツール-toolsflashcmd) で、左右とも最新を書き込む
- 書き込みの直後のように、USB をつないだまま起動したときは、起動の時点では充電状態が変わらないので止まらない
  (古いファームウェアでは、書き込み直後は USB で使えても、挿し直すと止まる)

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
   `powershell -ExecutionPolicy Bypass -File tools\scripts\keyball-check.ps1 -Watch` で実行すると、1 秒ごとの変化を表示し続ける

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
   先に [`tools/flash.cmd`](#keyboard-quantizer-mini) で最新のファームウェアに書き換える。
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
  左右それぞれに保存するので、[`tools/flash.cmd`](#keyball39) で左右に同じファームを書けば揃う)

点検後、ボール側に USB を挿して `tools/keyball-check.cmd` を実行し、Ball availability がボールの側
(`Right` など) になれば復旧です。それでも `None` のままなら、ボール基板 (センサーのはんだ付けやセンサー本体) の不良が考えられます。
