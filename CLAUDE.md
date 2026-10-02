# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## このリポジトリについて

各キーボードのファームウェアのリポジトリ (ZMK と QMK/Vial) を git submodule として集約し、Windows 用の書き込み・診断スクリプトを `tools/` に置いたリポジトリ。このリポジトリではファームウェアをビルドしない (各 submodule の GitHub Actions がビルドする)。テストがあるのは、設定の検査ツール `tools/keyboard-check` だけ (下の「設定の検査ツール」)。`README.md` は利用者向けの日本語の説明書で、書き込みツールの使い方と、各キーボードで共通のキーマップ設定を説明している。

README、スクリプトの表示メッセージとコメント、コミットメッセージと PR のタイトル・本文など、利用者の目に触れるものは日本語で書く。ただし `*.cmd` は ASCII 文字だけで書くので、コメントと表示メッセージは英語にする。

## submodule

クローンしたばかりの状態では submodule はチェックアウトされていない。ソースを読むときは `git submodule update --init [--depth 1] <path>` を実行する。各 submodule は `custom` ブランチを追跡する (`zmk-keymap-docgen`・`zmk-input-processor-xy-accel`・`zmk-input-processor-aml-threshold` は `main`)。

- `zmk-config-{LisM,AroundFortyRB,KUKEY42,Pyuron,roBa}` と `zmk-keyboard-torabo-tsuki-lp`: ZMK の設定。6 台とも分割キーボードで、ZMK は `config/west.yml` で v0.3.0 に固定している。右手側がセントラル、左手側がペリフェラル。マイコンは、torabo-tsuki-lp だけが BLE Micro Pro Boost (`bmp_boost`。乾電池 1 本と電源スイッチ付き) で、他の 5 台は Seeed XIAO nRF52840。roBa は KUKEY42 と同じ 43 キー配列で、キーマップも同じ。ローカルビルド用の `Makefile` (`make` / `make single`) と `build.yaml` がある。`build.yaml` は、CI でビルドするエントリの一覧 (matrix) と、各エントリの `artifact-name` を定める。6 リポジトリとも、リポジトリ自身を Zephyr モジュールとして `src/usb_bootmagic.c` (`zmk,usb-bootmagic`) を持ち、左手側は Q、右手側は P を押したまま USB を挿すとその側がブートローダになる (キーは左右の overlay の `row` / `column` で指定)。このファイルと binding は 6 リポジトリで同じ内容なので、直すときはすべてに入れる。
- `vial-qmk-kq-mini`: Keyboard Quantizer Mini (RP2040) 用の Vial/QMK。
- `keyball`: Keyball39 (Pro Micro / ATmega32U4、`keyball39` の `via` キーマップ) 用の QMK。CI は qmk_firmware 0.34.6 でビルドする (0.34.6 に移植したのは keyball39 だけで、他の機種は CI の対象から外している)。
- `zmk-input-processor-xy-accel`: ZMK の入力プロセッサのモジュール。トラックボールを転がす速さに応じてカーソルの移動量に倍率を掛ける (カーソルの加速)。ZMK の 6 リポジトリは submodule ではなく、`config/west.yml` でこのリポジトリのコミットを固定して取り込む。変えたときは `main` に入れ、6 リポジトリの `west.yml` の固定コミットを揃えて上げる。
- `zmk-input-processor-aml-threshold`: ZMK の入力プロセッサのモジュール。トラックボールのリスナーで `zip_temp_layer` の代わりに使い、キー入力の振動などでボールがわずかに動いても AML を発動させない (キーの押下・解放の直後と、止まっていた状態からの動きがしきい値に満たないときは `zip_temp_layer` に渡さない)。取り込み方と更新のしかたは `zmk-input-processor-xy-accel` と同じ。
- `zmk-keymap-docgen`: Python のツール。ZMK の `.keymap` から KEYMAP.html と KEYMAP.xlsx を生成する。`zmk_to_vial.py` は LisM のキーマップを KQ-mini の EEPROM デフォルトに変換する。ZMK の 6 リポジトリに加えて `keyball` と `vial-qmk-kq-mini` も、これを自身の `tools/keymap-docgen` submodule として取り込んでいる。QMK 側の 2 つは `vial_keymap_docgen.py` で KEYMAP.html を生成している。

**ファームウェアやキーマップの変更は、このリポジトリではなく submodule のリポジトリで行う。** そのリポジトリの `custom` ブランチに PR を出して変更し、その後このリポジトリで submodule の参照を更新する。参照を更新するのは、変えたい submodule だけにする。パスを付けずに `git submodule update --remote` を実行すると、すべての submodule が追跡ブランチの最新に進んでしまう。参照更新のコミットメッセージには、各 submodule を `<submodule>: <旧 SHA> → <新 SHA> (ryo-aoki-pc/<repo>#N)` の形で並べる。submodule の参照を更新するコミットは、タイトルの末尾に `(submodule 参照更新)` を付ける。ZMK の 6 リポジトリ・`keyball`・`zmk-keymap-docgen` の参照を更新したら、`python tools/expected/generate.py` で検査ツールの期待値を作り直して同じコミットに入れる (キーマップやトラックボールの設定が変わったのに作り直していないと、CI の `generate.py --check` が失敗する。元にしたコミットの違いだけなら失敗しない)。

### LisM 基準

`zmk-config-LisM` が、レイヤー構成 (BASE … SCRL の 10 レイヤー)、タップホールド設定、AML (オートマウスレイヤー。発動条件の `aml_threshold` の値を含む)、スクロール速度、カーソルの加速 (`trackball_accel` の値)、スリープの基準になっている。ZMK の 6 リポジトリはすべてこれに揃えている (例外は README の「共通基盤」の表に書く。例: torabo-tsuki-lp のスクロール速度)。動作の変更は、たいてい ZMK の 6 リポジトリすべてに入れる必要があり、`keyball` と `vial-qmk-kq-mini` にも入れることが多い。そうした変更では README の「共通基盤」の表も更新する。

KQ-mini と Keyball39 は組み合わせて使い、役割を分担している:
- Keyball39 は LisM BASE 配列の素の HID コードだけを送る。マウスレイヤーと AML (発動のしきい値を含む)、カーソルの加速も Keyball39 側で実装している。
- レイヤー、mod-tap / layer-tap、タップホールドのタイミングは KQ-mini が担当する。これらは `lism.keymap` + `lism.vialmap.json` から生成した EEPROM デフォルトで決まる。

どちらかを変える前に、README の「Keyboard Quantizer Mini + Keyball39 の役割分担」を読むこと。

## リリースから書き込みまでの流れ

`keyball`、`vial-qmk-kq-mini`、ZMK の 6 リポジトリの CI は、`custom` ブランチをビルドするたびに (push 時など) 次の 2 つを行う:
- 固定タグ `firmware-latest` のプレリリースを削除して作り直す
- ファームウェアと `BUILD_INFO.txt` をそこにアップロードする

`tools/` のスクリプトは `https://github.com/<repo>/releases/download/firmware-latest/<asset>` からダウンロードする。そのため書き込まれるのは `custom` の最新ビルドで、このリポジトリが参照しているコミットとは限らない。

アセット名はリポジトリをまたいだ取り決めになっている:
- `tools/flash-zmk.ps1` の `$KEYBOARDS` 表には、ZMK の各リポジトリの `build.yaml` の `artifact-name` が直接書かれている。`{v}` は LisM の `trackball` / `non_trackball` の版を表すプレースホルダで、ZMK Studio 版では、スクリプトが右手側 (セントラル) の名前の末尾に `_studio` を付ける (Studio 版があるのはセントラルだけ)。設定リセットのアセット名 (XIAO は `settings_reset-seeeduino_xiao_ble-zmk`、BMP は `settings_reset-bmp_boost-zmk`) は、`$KEYBOARDS` の各機種の `Mcu` が指す `$MCUS` の `SettingsReset` に直接書かれている。
- Keyball と KQ-mini のアセット名は、それぞれのスクリプトに直接書かれている。

submodule 側でアセット名 (ZMK では `build.yaml` の `artifact-name`) を変えるときは、スクリプトと README の URL の表も更新する。

## tools/ の構成

- 各 `*.cmd` は、ダブルクリックやファイルのドラッグ＆ドロップで起動するための薄いラッパーで、ASCII 文字だけで書く。`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0<name>.ps1"` を実行し、`pause` してから、スクリプトの終了コードで終了する。
- `flash-uf2.ps1` は UF2 を書き込む本体。対応するボード (XIAO の `nRF52840` / BLE Micro Pro Boost の `BMP` / KQ-mini の `RP2040`) と、ボードごとの書き込み範囲・ドライブの見分け方・案内の文言は `$BOARDS` にまとめている。`flash-zmk.ps1` は機種のマイコンに応じて `-Target nRF52840` か `-Target BMP` を、`flash-kq-mini.ps1` は `-Target RP2040` を付けてこれを呼ぶ (`-Target` は複数指定できる)。処理は 4 段階:
  1. `.uf2` を検証する: マジックナンバー、ファミリ ID、アドレス範囲、ブロックの欠けが無いこと。XIAO と BMP はファミリ ID (0xADA52840) が同じなので、先頭ブロックの書き込み先 (XIAO は 0x27000、BMP は 0x26000) でボードを決める。
  2. ブートローダのドライブのうち、`INFO_UF2.TXT` の内容が対象のボードと合うものを選ぶ。BMP はボリュームラベル `BLEMICROPRO` で選び、XIAO の書き込み先からは外す。KQ-mini の場合は、先に CDC シリアルポートへ `dfu` を送ってブートローダに切り替える。
  3. ファイルサイズを先に確保してからデータを書き込む。
  4. ドライブが消えたら成功と判定する。ブートローダが再起動した後、ファイルを閉じるときに出る例外は想定どおりのもの。BMP は電源スイッチが OFF のまま USB 給電で再起動するとブートローダに戻るので、ドライブが再び現れても成功とする (XIAO では失敗)。

  `dfu` コマンドは NUL で 16 バイトに埋めて送る。古い KQ-mini のファームウェアは 16 バイト (CDC のエンドポイントサイズ) に満たないパケットを捨てるので、埋めないと届かない。16 バイトに埋める処理は残すこと。
- `flash-zmk.ps1` は、書き込みを始める前に、必要なアセットをすべてダウンロードする。その後、右 (セントラル) → 左 (ペリフェラル) の順に書き込む (設定リセットを挟むこともできる)。書き込み前の案内と、BMP の設定リセット後に電源スイッチ ON で一度起動させる案内 (Enter 待ち) は `$MCUS` にある。`-Keyboard` と `-Mode` を指定するとメニューを出さずに実行する。`.uf2` のパスを渡すと、そのファイルを `flash-uf2.ps1` で書き込むだけになる。
- `flash-keyball.ps1` は Intel HEX を検証する:
  - チェックサム
  - イメージが caterina ブートローダの始まる 0x7000 より前に収まること

  `-Avrdude` で avrdude.exe を指定しなければ、公式の Windows 版 v8.3 を初回に `tools/.cache/` へダウンロードし、SHA256 で確認して使う (PATH 上の avrdude は使わない)。その後、caterina の COM ポートが現れるたびに片側ずつ書き込む。
- `keyball-check.ps1` は読み取り専用の診断スクリプト。`Add-Type` で読み込む C# のヘルパーを使い、raw HID で VIA の get 系コマンドを送る。VIA の set / 書き込み系のコマンドは決して送らないこと。
- `input-monitor.ps1` は入力イベントモニタ (ファームのデバッグ用)。Raw Input で、つないでいるすべてのキーボード・マウスの入力をデバイスごとに µs のタイムスタンプ付きで記録し、停止後に分析する (キーの時系列と押下時間、AML ビュー、マウスレポートの間隔と「停滞 → まとめて到着」の検出)。ウィンドウは `lib/keyboard-check/InputTestForm.cs` の `KcInputMonitorForm` で、専用の STA スレッドでメッセージループを回す (`KcInputTestForm` のように PowerShell 側の `DoEvents` + sleep で回すと、WM_INPUT の処理が 15 ms 単位に固まって間隔を測れない)。`KcInputEvent` / `KcRawInputParser` を共有するため、別の `.cs` にはしない (`Add-Type` は 1 回ごとに別アセンブリになり、同名の型が衝突する)。`lib/input-monitor/devices.ps1` (Raw Input のパス → USB / BLE・VID / PID・製品名・同じ物理デバイスのまとめ) と `analyze.ps1` (記録の CSV / JSON の読み書き、統計、報告、ライブログ。純粋関数) に分けてあり、記録は `tools/.cache/input-monitor/<日時>.{csv,json,txt}`。`-Analyze` は Linux の `pwsh` でも動き、`tests/input-monitor.Tests.ps1` がその場で作った記録で入口のスクリプトまで通す。
- `lib/firmware-latest.ps1` は dot-source で読み込む。`Get-FirmwareLatest` (複数のアセットを続けて取得するための `-Quiet` がある) と `Show-FirmwareBuildInfo` を提供する。TLS 1.2・`-UseBasicParsing`・進捗バーの抑止をまとめた `Invoke-FirmwareDownload` もここにあり、`flash-keyball.ps1` は avrdude のダウンロードにこれを直接使う。
- ダウンロードしたファイルは `tools/.cache/` に保存する (git の管理外)。

### 設定の検査ツール (`keyboard-check.ps1`)

接続したキーボードの設定 (キーマップ・トラックボール) が LisM 基準の意図どおりかを検査する。キーボードの設定は書き換えない。
- 期待値: `tools/expected/generate.py` (Python 3.10 以上、標準ライブラリだけ) が submodule の `.keymap` / overlay / `.conf` / `keymap.c` と `zmk-keymap-docgen` の `zmk_to_vial.py` から `tools/expected/*.json` を生成し、コミットしておく。機種を足すときは `ZMK_BOARDS` と `keyboard-check.ps1` の `$boards`、CI の submodule の一覧を揃える。
- 読み出し検査: KQ-mini は Vial、Keyball39 は VIA (ryo-aoki-pc/keyball#12 で足した読み取り専用のコマンド `08 00 01`〜`03` を含む)、ZMK は ZMK Studio の RPC。送るのは読み取りのコマンドだけで、`lib/keyboard-check/qmk.ps1` の許可リストで縛っている。Vial の unlock (`FE 06`) や VIA / Studio の set 系は送らないこと。
- 実動作テストとトラックボールの正規化: `lib/keyboard-check/InputTestForm.cs` (Raw Input) のウィンドウで入力を記録し、`input-eval.ps1` / `trackball-calib.ps1` の純粋関数で判定する。ファームのカーソルの加速は `Remove-KcAccel` で取り除いてから計算する (加速の処理を変えたら、`tests/trackball-calib.Tests.ps1` のファームを真似た計算も合わせる)。
- テスト: `python tools/expected/generate.py --check`、`python -m unittest discover -s tools/expected`、`tools/tests/run.ps1` (Pester は使わない。Linux の `pwsh` でも Windows 専用のテスト以外は動く。`input-monitor` のテストもここで走る)。CI は `.github/workflows/keyboard-check.yml` (Linux と Windows PowerShell 5.1)。
- `.cs` は ASCII だけで書き、Windows PowerShell 5.1 の `Add-Type` がコンパイルできる C# 5 の構文にする。

### PowerShell の約束事 (必須)

- 対象は **Windows PowerShell 5.1** (`powershell.exe`) で、PowerShell 7 ではない。例えば、TLS 1.2 を明示的に有効にし、`Invoke-WebRequest` に `-UseBasicParsing` を付け、進捗バーを抑止している。
- `.ps1` は **UTF-8 (BOM 付き)** のままにする。BOM が無いと、日本語版 Windows の PS 5.1 は日本語の文字列を CP932 として読んでしまう。新しく作る `.ps1` にも BOM を付ける。
- `.gitattributes` で、`.ps1`・`.cmd`・`.bat` の改行は **CRLF** に固定されている。
- `lib/` 以外のスクリプトは、日本語のコメントベースのヘルプで始まり、`param` の直後で `Set-StrictMode -Version 2.0` と `$ErrorActionPreference = 'Stop'` を設定する。
- 書き込みスクリプトは、失敗したら赤字で `失敗: …` と表示し、終了コード 1 で終了する。`flash-uf2.ps1`・`flash-zmk.ps1`・`flash-keyball.ps1` は、それぞれのスクリプト内で定義した `Stop-WithError` でこれを行う (`lib/` には無く、`flash-kq-mini.ps1` には定義されていない)。成功時は `成功` または `完了` と表示し、終了コード 0 で終了する。呼び出し側は `$LASTEXITCODE` を確認する。
- これらのスクリプトは、ドライブの列挙・シリアルポート・HID・PnP といった Windows のデバイス API を使うため、Linux のコンテナでは動作を確認できない。

## README の保守

スクリプトの動作、オプション、メニューの項目、既定値を変えたときは、同じ PR で README の該当する節も更新する。README の各節は、`#xiao-をブートローダにする方法` や `#最新ファームウェアの取得元-firmware-latest-リリース` のような見出しのアンカーで互いにリンクしているので、見出しを変えるとリンクが切れる。
