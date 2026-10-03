# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## このリポジトリについて

各キーボードのファームウェアのリポジトリ (ZMK と QMK/Vial) を git submodule として集約し、Windows 用の書き込み・診断スクリプトを `tools/` に置いたリポジトリ。このリポジトリではファームウェアをビルドしない (各 submodule の GitHub Actions がビルドする)。テストがあるのは、設定の検査ツール `tools/keyboard-check` だけ (下の「設定の検査ツール」)。`README.md` は利用者向けの日本語の説明書で、書き込みツールの使い方と、各キーボードで共通のキーマップ設定を説明している。

README、スクリプトの表示メッセージとコメント、コミットメッセージと PR のタイトル・本文など、利用者の目に触れるものは日本語で書く。ただし `*.cmd` は ASCII 文字だけで書くので、コメントと表示メッセージは英語にする。

## submodule

クローンしたばかりの状態では submodule はチェックアウトされていない。ソースを読むときは `git submodule update --init [--depth 1] <path>` を実行する。各 submodule は `custom` ブランチを追跡する (`zmk-keymap-docgen`・`zmk-input-processor-xy-accel`・`zmk-input-processor-aml-threshold` は `main`)。

- `zmk-config-{LisM,AroundFortyRB,KUKEY42,Pyuron,roBa}` と `zmk-keyboard-torabo-tsuki-lp`: ZMK の設定。6 台とも分割キーボードで、ZMK は `config/west.yml` で v0.3.0 に固定している。右手側がセントラル、左手側がペリフェラル。マイコンは、torabo-tsuki-lp だけが BLE Micro Pro Boost (`bmp_boost`。乾電池 1 本と電源スイッチ付き) で、他の 5 台は Seeed XIAO nRF52840。roBa は KUKEY42 と同じ 43 キー配列で、キーマップも同じ。ローカルビルド用の `Makefile` (`make` / `make single`) と `build.yaml` がある。`build.yaml` は、CI でビルドするエントリの一覧 (matrix) と、各エントリの `artifact-name` を定める。ログ版 (`*_logging`) のエントリの `cmake-args` (ログのバッファ、スレッドのスタック、thread analyzer) は 6 リポジトリで揃える (デバッグログでスタックの使用量が増え、ZMK の既定のサイズでは溢れる。KUKEY42 では入力スレッドが 576 バイト使い、セントラルの既定の 512 バイトを超えて、起動から数秒で止まった)。6 リポジトリとも、リポジトリ自身を Zephyr モジュールとして `src/usb_bootmagic.c` (`zmk,usb-bootmagic`) を持ち、左手側は Q、右手側は P を押したまま USB を挿すとその側がブートローダになる (キーは左右の overlay の `row` / `column` で指定)。このファイルと binding は 6 リポジトリで同じ内容なので、直すときはすべてに入れる。LisM だけは、充電中の LED 表示 `src/charge_indicator.c` (`CONFIG_CHARGE_INDICATOR`。4mplelab/zmk-feature-charge-indicator を取り込んで直したもの) も持つ。GPIO のコールバックは割り込みの中で呼ばれるので、そこでは `k_sleep` などの眠る API を呼ばず、ワークアイテムに回す (割り込みの中で眠ると、カーネルのタイムアウトの一覧が壊れてファームウェア全体が止まる。元のモジュールではこれで、USB を挿すと LisM が操作できなくなっていた)。
- `vial-qmk-kq-mini`: Keyboard Quantizer Mini (RP2040) 用の Vial/QMK。
- `keyball`: Keyball39 (Pro Micro / ATmega32U4、`keyball39` の `via` キーマップ) 用の QMK。CI は qmk_firmware 0.34.6 でビルドする (0.34.6 に移植したのは keyball39 だけで、他の機種は CI の対象から外している)。
- `zmk-input-processor-xy-accel`: ZMK の入力プロセッサのモジュール。トラックボールを転がす速さに応じてカーソルの移動量に倍率を掛ける (カーソルの加速)。ZMK の 6 リポジトリは submodule ではなく、`config/west.yml` でこのリポジトリのコミットを固定して取り込む。変えたときは `main` に入れ、6 リポジトリの `west.yml` の固定コミットを揃えて上げる。
- `zmk-input-processor-aml-threshold`: ZMK の入力プロセッサのモジュール。トラックボールのリスナーで `zip_temp_layer` の代わりに使い、キー入力の振動などでボールがわずかに動いても AML を発動させない (キーの押下・解放の直後と、止まっていた状態からの動きがしきい値に満たないときは `zip_temp_layer` に渡さない)。取り込み方と更新のしかたは `zmk-input-processor-xy-accel` と同じ。
- `zmk-keymap-docgen`: Python のツール。ZMK の `.keymap` から KEYMAP.html と KEYMAP.xlsx を生成する。`zmk_to_vial.py` は LisM のキーマップを KQ-mini の EEPROM デフォルトに変換する。ZMK の 6 リポジトリに加えて `keyball` と `vial-qmk-kq-mini` も、これを自身の `tools/keymap-docgen` submodule として取り込んでいる。QMK 側の 2 つは `vial_keymap_docgen.py` で KEYMAP.html を生成している。

**ファームウェアやキーマップの変更は、このリポジトリではなく submodule のリポジトリで行う。** そのリポジトリの `custom` ブランチに PR を出して変更し、その後このリポジトリで submodule の参照を更新する。参照を更新するのは、変えたい submodule だけにする。パスを付けずに `git submodule update --remote` を実行すると、すべての submodule が追跡ブランチの最新に進んでしまう。参照更新のコミットメッセージには、各 submodule を `<submodule>: <旧 SHA> → <新 SHA> (ryo-aoki-pc/<repo>#N)` の形で並べる。submodule の参照を更新するコミットは、タイトルの末尾に `(submodule 参照更新)` を付ける。ZMK の 6 リポジトリ・`keyball`・`zmk-keymap-docgen` の参照を更新したら、`python tools/expected/generate.py` で検査ツールの期待値を作り直して同じコミットに入れる (キーマップやトラックボールの設定が変わったのに作り直していないと、CI の `generate.py --check` が失敗する。元にしたコミットの違いだけなら失敗しない)。

### LisM 基準

`zmk-config-LisM` が、レイヤー構成 (BASE … SCRL の 10 レイヤー)、タップホールド設定、AML (オートマウスレイヤー。発動条件の `aml_threshold` の値と、スクロール中も延ばす `zip_temp_layer` を含む)、スクロールの速度と向き、カーソルの加速 (`trackball_accel` の値)、スリープ、BLE (ZMK の既定値のまま、機種ごとの調整を入れない) の基準になっている。ZMK の 6 リポジトリはすべてこれに揃えている (例外は README の「共通基盤」の表に書く。例: torabo-tsuki-lp のスクロール速度)。動作の変更は、たいてい ZMK の 6 リポジトリすべてに入れる必要があり、`keyball` と `vial-qmk-kq-mini` にも入れることが多い。そうした変更では README の「共通基盤」の表も更新する。

KQ-mini と Keyball39 は組み合わせて使い、役割を分担している:
- Keyball39 は LisM BASE 配列の素の HID コードだけを送る。マウスレイヤーと AML (発動のしきい値を含む)、カーソルの加速も Keyball39 側で実装している。
- レイヤー、mod-tap / layer-tap、タップホールドのタイミングは KQ-mini が担当する。これらは `lism.keymap` + `lism.vialmap.json` から生成した EEPROM デフォルトで決まる。

どちらかを変える前に、README の「Keyboard Quantizer Mini + Keyball39 の役割分担」を読むこと。

`lism.keymap` を変えたら、vial-qmk-kq-mini の生成物も作り直して PR にする (手では編集しない。作り直しても変わらないなら不要):
- `keyboards/sekigon/keyboard_quantizer/mini/keymaps/vial/zmk_keymap_defaults.inc` と `KEYMAP.vil`: zmk-config-LisM の README の「再生成方法」のコマンド (`zmk_to_vial.py`)。`--strict` を付けると、変換の警告で止まる
- ルートの `KEYMAP.html`: `KEYMAP.vil` の push を受けて、vial-qmk-kq-mini の CI (`keymap-vial-docs.yml`) が bot のコミットで作り直す (ZMK のリポジトリの KEYMAP.html と同じ)。手元で作るなら、vial-qmk-kq-mini で `python3 ../zmk-keymap-docgen/vial_keymap_docgen.py keyboards/sekigon/keyboard_quantizer/mini/keymaps/vial/KEYMAP.vil --format vil -l keyboards/sekigon/keyboard_quantizer/mini/keymaps/vial/vial.json --title "Keyboard Quantizer Mini (Vial / LisM) キーマップ" -o KEYMAP.html` (CI と同じ結果になる)

ZMK のリポジトリの `KEYMAP.html` / `KEYMAP.xlsx` も、キーマップの push を受けて CI (`keymap-docs.yml`) が bot のコミットで作り直す。bot のコミット (GITHUB_TOKEN) ではワークフローが動かず、PR の最後のコミットにビルドが付かないので、キーマップを変えるときは、CI と同じ docgen (`tools/keymap-docgen`) と openpyxl 3.1.5 で手元で作り直して同じコミットに入れる (docgen は xlsx の時刻を固定するので、同じ結果になる)。

リセット (`&sys_reset`)・ブートローダ (`&bootloader`) のキーは、どのレイヤーにも置かない (押し間違えると、キーボードが再起動したりブートローダで止まったりするため。KQ-mini にも `QK_BOOT` / `QK_RBT` は無い)。ブートローダには、左手側は Q、右手側は P を押したまま USB を挿すか、リセットボタンを素早く 2 回押して切り替える (KQ-mini は書き込みツールが送る `dfu` コマンド)。

キーマップに使えるキーコードは、docgen の `zmk_to_vial.py` の `ZMK_KEYCODES` にあるもの (キーボードのページ 0x07) だけ。メディアキー (`C_*`)・F13 以降・テンキー (`KP_*`) は、docgen と `tools/expected/generate.py` が対応していない (`generate.py` が「知らない ZMK キーコード」や変換の警告で止まる)。

## リリースから書き込みまでの流れ

`keyball`、`vial-qmk-kq-mini`、ZMK の 6 リポジトリの CI は、ビルドしたファームウェアと `BUILD_INFO.txt` をプレリリースに置く (`.github/scripts/firmware-release.sh`):
- `custom` ブランチをビルドするたびに (push 時など)、固定タグ `firmware-latest` のプレリリースを作り直し、`firmware-custom-<sha7>` (履歴) も作る
- 同じリポジトリのブランチからの PR をビルドするたびに、`firmware-pr-<番号>` を作り直す (PR をマージした状態のコミットのビルド)
- `firmware-custom-*` と `firmware-pr-*` は、それぞれ新しいものから 30 件を残し、古いリリースとタグを消す。`firmware-latest` と `v*` には触れない
- タグは消さずに付け替える (消すと、GitHub が後から同じタグ名のリリースを下書きに戻す)。後から始まった run のビルドが公開済みなら置き換えない
- 公開のジョブは `publish-latest` / `publish-custom` / `publish-pr` に分け、concurrency のグループも分ける (1 つのグループにすると、待機中のジョブが取り消されて履歴が欠ける)

`firmware-release.sh` は 8 リポジトリで同じ内容なので、直すときはすべてに入れる。リリースの本文の ```text ブロックと `BUILD_INFO.txt` の「キー: 値」の行 (`repository kind branch pr title head commit subject built run`) は、書き込みツールが一覧を作るために読む取り決めなので、キーの名前と形を変えない (`tools/lib/firmware-release.ps1` の `$FirmwareInfoKeys` と `ConvertTo-FirmwareBuild`)。

`tools/` のスクリプトは `https://github.com/<repo>/releases/download/<タグ>/<asset>` からダウンロードする。既定のタグは `firmware-latest` なので、既定で書き込まれるのは `custom` の最新ビルドで、このリポジトリが参照しているコミットとは限らない。書き込みツール (`flash.cmd`) は GitHub API (`/repos/<repo>/releases`。認証なしでは 1 時間に 60 回) でリリースの一覧を取り、PR や過去のビルドも選べる。

アセット名はリポジトリをまたいだ取り決めになっている:
- `tools/lib/flash-plan.ps1` の `$FlashKeyboards` 表には、ZMK の各リポジトリの `build.yaml` の `artifact-name` が直接書かれている。`{v}` は LisM の `trackball` / `non_trackball` の版を表すプレースホルダで、ZMK Studio 版では、スクリプトが右手側 (セントラル) の名前の末尾に `_studio` を付け、ログ版 (`zmk-usb-logging`。`keyboard-check` の `-Mode Trace` 用) では `_logging` を付ける (Studio 版とログ版があるのはセントラルだけ。両方を入れた版は無い)。設定リセットのアセット名 (XIAO は `settings_reset-seeeduino_xiao_ble-zmk`、BMP は `settings_reset-bmp_boost-zmk`) は、`$FlashKeyboards` の各機種の `Mcu` が指す `$FlashMcus` の `SettingsReset` に直接書かれている。
- Keyball と KQ-mini のアセット名も、`$FlashKeyboards` の `Asset` に直接書かれている (`flash-keyball.ps1` / `flash-kq-mini.ps1` もここから取る)。

submodule 側でアセット名 (ZMK では `build.yaml` の `artifact-name`) を変えるときは、スクリプトと README の URL の表も更新する。

## tools/ の構成

- `tools/` の直下には、利用者が実行する `.cmd` (`flash.cmd` / `keyboard-check.cmd` / `input-monitor.cmd` / `keyball-check.cmd`) だけを置く。入口の `.ps1` と、機種を絞った書き込み用の `.cmd` (`flash-zmk.cmd` / `flash-keyball.cmd` / `flash-kq-mini.cmd` / `flash-uf2.cmd`) は `tools/scripts/` に置く (`tests/run.ps1` が確かめる)。`scripts/` のスクリプトは、`Split-Path -Parent $PSScriptRoot` (`$TOOLS_DIR` / `$toolsDir`) から `lib/`・`expected/`・`.cache/` を指し、同じフォルダのスクリプトは `$PSScriptRoot` から呼ぶ (`$PSScriptRoot` から `.cache` を作ると `tools/scripts/.cache` にずれ、`.gitignore` から外れる)。
- 各 `*.cmd` は、ダブルクリックやファイルのドラッグ＆ドロップで起動するための薄いラッパーで、ASCII 文字だけで書く。`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\<name>.ps1"` (`scripts/` の `.cmd` は `"%~dp0<name>.ps1"`) を実行し、`pause` してから、スクリプトの終了コードで終了する。ウィンドウを開くものは `-STA` を付ける。`flash.cmd` と `scripts/` の `flash-zmk.cmd` / `flash-keyball.cmd` / `flash-kq-mini.cmd` は、引数が無ければ書き込みツールのウィンドウ (`flash.ps1`) を開き、ファイルがドロップされたらそのファイルを書き込む (`flash.cmd` は `.hex` を `flash-keyball.ps1`、それ以外を `flash-uf2.ps1 -Target nRF52840, BMP, RP2040` で書き込むので、利用者向けの案内は `tools/flash.cmd` にする)。
- `flash.ps1` (`flash.cmd`) は書き込みツール (GUI)。全機種 (ZMK 6 台・Keyball39・KQ-mini) の機種・ビルド (最新 / PR / 過去の custom)・書き込む内容を選び、手順ごとに書き込む。
  - ウィンドウは `KcFlashForm` (`InputTestForm.cs`、`FlashWindow.xaml`) で、`KcFlashForm.Launch` が専用の STA スレッドで回す。PowerShell のスレッドは、ボタンや選択の操作 (`TakeActions()` のキュー。`keyboard:<機種>` / `build:<タグ>` / `option:<欄>:<値>` / `start` など) を 80 ms ごとに取り、一覧の取得・ダウンロード・子プロセスの中継を行う (止まる処理をしてもウィンドウは固まらない)。
  - 画面の流れ (選ぶ → ダウンロード → 手順ごとの書き込み → 完了 / 失敗 / 中止、BMP の「続ける」、再試行) は `lib/flash-ui.ps1` にあり、ウィンドウ・一覧の取得・ダウンロード・子プロセスを `$Ctx` 経由で使う (WPF の型に触れないので、`tests/flash-ui.Tests.ps1` が偽物で確かめる)。`lib/flash-ui.ps1` の `$FlashUi*` の定数は `KcFlashForm` の定数と揃える (`tests/windows.Tests.ps1` が確かめる)。
  - 各手順は、`flash-uf2.ps1` / `flash-keyball.ps1 -Count 1` を子プロセス (`powershell.exe -NonInteractive -EncodedCommand`。作業フォルダは tools) で実行する。スクリプトは `Get-FlashStepCommand` が `$Ctx.ToolsDir` (tools フォルダ) の `scripts\` から探す。コマンドは `Format-FlashCommand` が作り、先頭で `[Console]::OutputEncoding` を BOM 無しの UTF-8 にしてから、スクリプトの終了コードを返す。子プロセスは `lib/keyboard-check/ChildProcess.cs` の `KcChildProcess` (他の C# と型を共有しないので別ファイル) で、出力を UTF-8 の行で受け取り (CR だけで終わる行は `Partial`)、Job Object (KILL_ON_JOB_CLOSE) に入れる。中止やツールの終了で、孫 (avrdude) まで止まる。ログの色は行の先頭 (`失敗:` / `成功:` / `完了:` など) で決める (`ConvertTo-FlashLogLevel`)。
  - 前回の選択 (機種・LisM の版・Keyball の台数) は `tools/.cache/flash-settings.json`。書き込む内容と右手側の版は、機種を選ぶたびに既定 (左右・通常版) に戻す。
  - `-List` は、ウィンドウを出さずにビルドの一覧を表示する (Linux の `pwsh` でも動く)。
- `flash-uf2.ps1` は UF2 を書き込む本体。対応するボード (XIAO の `nRF52840` / BLE Micro Pro Boost の `BMP` / KQ-mini の `RP2040`) と、ボードごとの書き込み範囲・ドライブの見分け方・案内の文言は `$BOARDS` にまとめている。書き込みツールと `flash-zmk.ps1` は機種のマイコンに応じて `-Target nRF52840` か `-Target BMP` を、KQ-mini では `-Target RP2040` を付けてこれを呼ぶ (`-Target` は複数指定できる)。処理は 4 段階:
  1. `.uf2` を検証する: マジックナンバー、ファミリ ID、アドレス範囲、ブロックの欠けが無いこと。XIAO と BMP はファミリ ID (0xADA52840) が同じなので、先頭ブロックの書き込み先 (XIAO は 0x27000、BMP は 0x26000) でボードを決める。
  2. ブートローダのドライブのうち、`INFO_UF2.TXT` の内容が対象のボードと合うものを選ぶ。BMP はボリュームラベル `BLEMICROPRO` で選び、XIAO の書き込み先からは外す。KQ-mini の場合は、先に CDC シリアルポートへ `dfu` を送ってブートローダに切り替える。
  3. ファイルサイズを先に確保してからデータを書き込む。
  4. ドライブが消えたら成功と判定する。ブートローダが再起動した後、ファイルを閉じるときに出る例外は想定どおりのもの。BMP は電源スイッチが OFF のまま USB 給電で再起動するとブートローダに戻るので、ドライブが再び現れても成功とする (XIAO では失敗)。

  `dfu` コマンドは NUL で 16 バイトに埋めて送る。古い KQ-mini のファームウェアは 16 バイト (CDC のエンドポイントサイズ) に満たないパケットを捨てるので、埋めないと届かない。16 バイトに埋める処理は残すこと。
- `lib/flash-plan.ps1` は機種の表 (`$FlashKeyboards` / `$FlashMcus` / `$FlashModes`) と、書き込む手順を決める純粋関数 (`Get-FlashPlan` など)。ZMK は右 (セントラル) → 左 (ペリフェラル) の順に書き込む (設定リセットを挟むこともできる)。書き込み前の案内と、BMP の設定リセット後に電源スイッチ ON で一度起動させる案内 (`Pause`。最後の手順でなければ「続ける」/ Enter を待つ) は `$FlashMcus` にある。
- `flash-zmk.ps1` は、`-Keyboard` と `-Mode` を指定するとコンソールで書き込み (書き込みを始める前に、必要なアセットをすべてダウンロードする)、どちらかが無ければ書き込みツールのウィンドウを開く。`.uf2` のパスを渡すと、そのファイルを `flash-uf2.ps1` で書き込むだけになる。`flash-zmk.ps1` / `flash-keyball.ps1` / `flash-kq-mini.ps1` は `-Tag` / `-Pr` で PR や過去のビルドを書き込める。
- `flash-keyball.ps1` は Intel HEX を検証する:
  - チェックサム
  - イメージが caterina ブートローダの始まる 0x7000 より前に収まること

  `-Avrdude` で avrdude.exe を指定しなければ、公式の Windows 版 v8.3 を初回に `tools/.cache/` へダウンロードし、SHA256 で確認して使う (PATH 上の avrdude は使わない)。その後、caterina の COM ポートが現れるたびに片側ずつ書き込む。
- `keyball-check.ps1` は読み取り専用の診断スクリプト。`Add-Type` で読み込む C# のヘルパーを使い、raw HID で VIA の get 系コマンドを送る。VIA の set / 書き込み系のコマンドは決して送らないこと。
- `input-monitor.ps1` は入力イベントモニタ (ファームのデバッグ用)。Raw Input で、つないでいるすべてのキーボード・マウスの入力をデバイスごとに µs のタイムスタンプ付きで記録し、停止後に分析する (キーの時系列と押下時間、AML ビュー、マウスレポートの間隔と「停滞 → まとめて到着」の検出)。ウィンドウは `lib/keyboard-check/InputTestForm.cs` の `KcInputMonitorForm` で、専用の STA スレッドでメッセージループを回す (`KcInputTestForm` のように PowerShell 側の `DoEvents` + sleep で回すと、WM_INPUT の処理が 15 ms 単位に固まって間隔を測れない)。`KcInputEvent` / `KcRawInputParser` / `KcUi` を共有するため、別の `.cs` にはしない (`Add-Type` は 1 回ごとに別アセンブリになり、同名の型が衝突する)。`lib/input-monitor/devices.ps1` (Raw Input のパス → USB / BLE・VID / PID・製品名・同じ物理デバイスのまとめ) と `analyze.ps1` (記録の CSV / JSON の読み書き、統計、報告、ライブログ。純粋関数) に分けてあり、記録は `tools/.cache/input-monitor/<日時>.{csv,json,txt}`。`-Analyze` は Linux の `pwsh` でも動き、`tests/input-monitor.Tests.ps1` がその場で作った記録で入口のスクリプトまで通す。
- `lib/firmware-release.ps1` は dot-source で読み込む。リリースの一覧の取得 (`Get-FirmwareBuildList`。API を 1 ページ 50 件でたどる (5.1 の `ConvertFrom-Json` は約 2 MB まで)、PR の状態は `/issues` を 1 回。取れなければ前回の一覧 (`tools/.cache/firmware/<repo>/builds/`)、それも無ければ最新だけ)、一覧の解析と表示 (`ConvertTo-FirmwareBuild` / `Select-FirmwareBuilds` / `Format-FirmwareBuildLabel`。純粋関数)、ダウンロード (`Save-FirmwareBuild` は前後で `BUILD_INFO.txt` の commit を比べ、途中で置き換わったら 1 回やり直す。`Get-FirmwareAsset` は 1 ファイル用) を提供する。ダウンロードはタグごとのフォルダ (`tools/.cache/firmware/<repo>/<タグ>/`) に置く。TLS 1.2・`-UseBasicParsing`・進捗バーの抑止をまとめた `Invoke-FirmwareDownload` もここにあり、`flash-keyball.ps1` は avrdude のダウンロードにこれを直接使う。`$env:GITHUB_TOKEN` / `$env:GH_TOKEN` があれば API に付ける (表示しない)。
- ダウンロードしたファイルは `tools/.cache/` に保存する (git の管理外)。

### 設定の検査ツール (`keyboard-check.ps1`)

接続したキーボードの設定 (キーマップ・トラックボール) が LisM 基準の意図どおりかを検査する。キーボードの設定は書き換えない。
- 期待値: `tools/expected/generate.py` (Python 3.10 以上、標準ライブラリだけ) が submodule の `.keymap` / overlay / `.conf` / `keymap.c` と `zmk-keymap-docgen` の `zmk_to_vial.py` から `tools/expected/*.json` を生成し、コミットしておく。機種を足すときは `ZMK_BOARDS` と `keyboard-check.ps1` の `$boards`、CI の submodule の一覧を揃える。
- 読み出し検査: KQ-mini は Vial、Keyball39 は VIA (ryo-aoki-pc/keyball#12 で足した読み取り専用のコマンド `08 00 01`〜`03` を含む)、ZMK は ZMK Studio の RPC。送るのは読み取りのコマンドだけで、`lib/keyboard-check/qmk.ps1` の許可リストで縛っている。Vial の unlock (`FE 06`) や VIA / Studio の set 系は送らないこと。
- 実動作テストとトラックボールの正規化: `lib/keyboard-check/InputTestForm.cs` (Raw Input) のウィンドウで入力を記録し、`input-eval.ps1` / `trackball-calib.ps1` の純粋関数で判定する。ファームのカーソルの加速は `Remove-KcAccel` で取り除いてから計算する (加速の処理を変えたら、`tests/trackball-calib.Tests.ps1` のファームを真似た計算も合わせる)。
- レイヤー・ビヘイビアのテスト: `tools/expected/behaviors.py` が ZMK v0.3.0 の動き (レイヤー、`&mo` / `&lt` / `&to`、hold-tap、mod-morph のマスクと keep-mods、tap-dance、マクロ) を真似て、手順と「PC に届く入力 (ストローク)」の期待値を作る (`interactive.behaviors`)。KQ-mini は LisM の手順を Keyball39 の位置に置き換える。押すと状態が変わるキー (`&bt` `&out` `&sys_reset` `&bootloader` `&studio_unlock`) とその隣、Win / Alt の押したまま、システムが反応する組み合わせ (Ctrl+Esc、Alt+Tab など) は手順に入れず、入ったら生成をエラーにする (`test_behaviors.py` が全機種で確かめる)。判定は `lib/keyboard-check/behavior-eval.ps1` (純粋関数)、流れと表示は `behavior-test.ps1`。ZMK の動きの真似を変えたら、`tests/behavior-eval.Tests.ps1` の全シナリオの合成 (PASS と 1 文字変えた FAIL) が通ることを確かめる。
- レイヤーの動きを見る (`-Mode Trace`): ZMK のログ版ファーム (`*_logging`) が USB の COM ポートに出すログを `lib/keyboard-check/zmk-log.ps1` (純粋関数。`tests/zmk-log.Tests.ps1` が ZMK v0.3.0 の書式のログで確かめる) で解析し、`layer-trace.ps1` が `KcLayerTraceForm` (`LayerTraceWindow.xaml`) に出す。COM ポートは読むだけで、何も送らない。ログの書式は ZMK のバージョンで変わるので、ZMK を上げたら正規表現を確かめる。
- タップホールドのタイミングを見る (`-Mode HoldTap`、メニュー 7。ZMK のみ): ログ版ファームで押した hold-tap の 1 回分 (hold-tap のキーを押してから全部離すまで) を、押した瞬間からリアルタイムに、時刻を横軸にしたグラフで出す。設定は flavor と tapping-term だけを変えられ、離す時刻ごとの結果の帯と flavor ごとの比較の帯を出す。
  - シミュレータは `lib/keyboard-check/HoldTapSim.cs` にある。ZMK v0.3.0 の `behavior_hold_tap.c` を移植した `KcZmkHoldTapSim` (作業の列とタイマーの真似。保留したキーの再送を含む) と、vial-qmk の `action_tapping.c` と `action.c` の retro tapping を移植した `KcQmkTapHoldSim` がある。QMK のほうは画面では使わず、テストだけが使う (KQ-mini はログを出さないので、ウィンドウの対象外)
  - WPF を使わず型も共有しないので、`InputTestForm.cs` とは別ファイルにしてあり、Linux の `pwsh` でもコンパイルしてテストする。`hold-tap-sim.ps1` が読み込みと変換を行う
  - `tests/hold-tap.Tests.ps1` が、ZMK の `app/tests/hold-tap` (`tests/hold-tap-vectors-zmk.ps1`) と QMK の `tests/tap_hold_configurations` (`hold-tap-vectors-qmk.ps1`) のベクトルと同じ結果になることを確かめる。シミュレータを変えたら全件が通ることを確かめる
  - 期待値は `generate.py` が出す `interactive.hold_tap`。ZMK は `&mt` / `&lt` などの設定とキーごとのバインディング (KQ-mini の分も出すが、ウィンドウでは使わない)
  - `hold-tap.ps1` (純粋関数) にあるもの:
    - ログからの 1 回分の切り出し (`Update-KcHtCapture`) と、押している最中の回 (`Get-KcHtCaptureSnapshot`)
    - 「今」の時計 (`Update-KcHtClock`)。ログは deferred で最大 0.1 秒ほどまとめて届くので、直近 5 秒でいちばん遅れの少ない行に合わせる
    - 離す時刻ごとの結果 (`Get-KcHtReleaseSweeps`。押している最中は仮の「離す」を足して動かす)、要約、グラフのモデル
  - ウィンドウの流れは `hold-tap-ui.ps1` で、`$Ctx.Form` 経由でウィンドウに触る (`tests/hold-tap-ui.Tests.ps1` が偽物にログの行を時刻つきで流して確かめる)
    - 押している最中の回は、中身が変わったら 50 ms 以上あけて計算し直す
    - その間は、「今」を含む区間が変わったときだけ結果の文を送る
    - 全部離して 400 ms ログが来なければ、回を終える
  - ウィンドウは `KcHoldTapForm` (`HoldTapWindow.xaml`。グラフは `KcTimelineView`) で、`KcFlashForm` と同じく専用の STA スレッドで回す
    - `KcTimelineView.SetLive` で、押している最中は「今」より後を描かず、`DispatcherTimer` で「今」の線を自分で進める
    - PowerShell は 250 ms ごとに時計を合わせ直すだけ
    - `hold-tap.ps1` の `$script:KcHt*` の定数は、`KcTimelineView` の定数と揃える (`tests/windows.Tests.ps1` が確かめる)
  - ログ版ファームの COM ポートを探して読む処理は、`layer-trace.ps1` の `New-KcLogPortReader` / `Read-KcLogPortLines` を `-Mode Trace` と共有する
- テスト: `python tools/expected/generate.py --check`、`python -m unittest discover -s tools/expected`、`tools/tests/run.ps1` (Pester は使わない。Linux の `pwsh` でも Windows 専用のテスト以外は動く。`input-monitor`、タップホールド (`hold-tap` / `hold-tap-ui`)、書き込みツール (`firmware-release` / `flash-plan` / `flash-ui` / `child-process`。GitHub API の応答の偽物は `tests/flash-fixtures.ps1`) のテストもここで走る)。CI は `.github/workflows/keyboard-check.yml` (Linux と Windows PowerShell 5.1)。
- `.cs` は ASCII だけで書き、Windows PowerShell 5.1 の `Add-Type` がコンパイルできる C# 5 の構文にする (警告もエラーになる)。
- テスト用・記録用・書き込みツールのウィンドウは WPF (ダークテーマ)。見た目は `lib/keyboard-check/` の `Theme.xaml` (色・ボタンなどのスタイル) と `InputTestWindow.xaml` / `InputMonitorWindow.xaml` / `LayerTraceWindow.xaml` / `FlashWindow.xaml` / `HoldTapWindow.xaml` (中身) にあり、`InputTestForm.cs` が `XamlReader` で読み込む (`x:Class` は使わず、名前の付いた要素を `KcUi.Find` で探す)。ウィンドウの XAML からテーマのキーは `DynamicResource` で参照する。ログなどの等幅の文字は `KcMonoFont` (`HackGen Console NF, BIZ UDGothic, MS Gothic`)。現在のユーザだけにインストールしたフォント (Windows 10 1809 以降の既定) は WPF のシステムフォントの一覧に無いことがあるので、`KcUi.CreateWindow` (`ApplyMonoFont`) が、名前で見つからない HackGen Console NF を HKCU のフォントの登録から探し、ファイルの URI で先頭に足す。そのため、テーマの中のスタイルからも `KcMonoFont` は `DynamicResource` で参照する。XAML も ASCII だけで書き、表示する文字列は PowerShell から渡す。`Import-KcInputForm` (`input-test.ps1`) が `[KcUi]::XamlDir` を設定し、ウィンドウを作る前に `[KcUi]::EnsureDpiAware()` を呼ぶ。テスト用のウィンドウは PowerShell のスレッドで `[KcUi]::DoEvents()` で回す。キーボードの図は `KcKeyboardView`、チップ・キーキャップ・矢印は `KcDraw`、Win キーのフックは `KcWinKeyMask` にあり、`KcInputTestForm` と `KcLayerTraceForm` と `KcHoldTapForm` が共有する。書き込みツールとタップホールドのウィンドウの一覧や選択肢は、フォーカスを取らないラジオボタン (`KcNavItem` / `KcBuildItem` / `KcSegment` / `KcChoice`) とスライダー (`KcSlider`) で作り、つないだキーボードから入力したキーで選択が変わらないようにしている。`tests/ui.Tests.ps1` が XAML と C# の名前・キーの食い違いを (Linux でも。ウィンドウは `KcUi.CreateWindow("<XAML>")` から自動で見つける) 調べ、`tests/windows.Tests.ps1` が画面外に描画する。`$env:KC_SCREENSHOT_DIR` を設定すると、描いた PNG が残る (CI は artifact `window-screenshots` に上げる)。

### PowerShell の約束事 (必須)

- 対象は **Windows PowerShell 5.1** (`powershell.exe`) で、PowerShell 7 ではない。例えば、TLS 1.2 を明示的に有効にし、`Invoke-WebRequest` に `-UseBasicParsing` を付け、進捗バーを抑止している。
- `.ps1` は **UTF-8 (BOM 付き)** のままにする。BOM が無いと、日本語版 Windows の PS 5.1 は日本語の文字列を CP932 として読んでしまう。新しく作る `.ps1` にも BOM を付ける。
- `.gitattributes` で、`.ps1`・`.cmd`・`.bat` の改行は **CRLF** に固定されている。
- `scripts/` のスクリプト (と `tests/run.ps1`) は、日本語のコメントベースのヘルプで始まり、`param` の直後で `Set-StrictMode -Version 2.0` と `$ErrorActionPreference = 'Stop'` を設定する。
- 書き込みスクリプトは、失敗したら赤字で `失敗: …` と表示し、終了コード 1 で終了する。`flash-uf2.ps1`・`flash-zmk.ps1`・`flash-keyball.ps1`・`flash.ps1` は、それぞれのスクリプト内で定義した `Stop-WithError` でこれを行う (`lib/` には無く、`flash-kq-mini.ps1` には定義されていない)。成功時は `成功` または `完了` と表示し、終了コード 0 で終了する。呼び出し側は `$LASTEXITCODE` を確認する。書き込みツールは子プロセスの出力のこの行の先頭で色を決め、`失敗:` の行を失敗の理由として出すので、文言の先頭は変えない。
- これらのスクリプトは、ドライブの列挙・シリアルポート・HID・PnP といった Windows のデバイス API を使うため、Linux のコンテナでは動作を確認できない。
- Linux の `pwsh` (7.4) では、`New-Object` で作った `List` を `@()` で包むと「Argument types do not match」で失敗することがある。`foreach` で回すか `.ToArray()` を使う (5.1 では起きないので、Linux のテストでだけ落ちる)。

## README の保守

スクリプトの動作、オプション、メニューの項目、既定値を変えたときは、同じ PR で README の該当する節も更新する。README の各節は、`#xiao-をブートローダにする方法` や `#最新ファームウェアの取得元-firmware-latest-リリース` のような見出しのアンカーで互いにリンクしているので、見出しを変えるとリンクが切れる。
