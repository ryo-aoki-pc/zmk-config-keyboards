# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## このリポジトリについて

各キーボードのファームウェアのリポジトリ (ZMK と QMK/Vial) を git submodule として集約し、Windows 用の書き込み・診断スクリプトを `tools/` に置いたリポジトリ。このリポジトリでは何もビルドせず、ビルド・lint・テストのコマンドも無い。ファームウェアは各 submodule の GitHub Actions がビルドする。`README.md` は、書き込みツールと共通のキーマップ設定についての利用者向けの説明書 (日本語)。

README、スクリプトの表示メッセージとコメント、コミットメッセージと PR のタイトル・本文は、すべて日本語で書く。

## submodule

クローンしたばかりの状態では submodule はチェックアウトされていない。ソースを読むときは `git submodule update --init [--depth 1] <path>` を実行する。各 submodule は `custom` ブランチを追跡する (`zmk-keymap-docgen` だけは `main`)。

- `zmk-config-{LisM,AroundFortyRB,KUKEY42,Pyuron}`: ZMK の設定。4 台とも Seeed XIAO nRF52840 の分割キーボードで、ZMK は `config/west.yml` で v0.3.0 に固定している。右手側がセントラル、左手側がペリフェラル。ローカルビルド用の `Makefile` (`make` / `make single`) と、CI のビルド行列と各ビルドの `artifact-name` を決める `build.yaml` がある。
- `vial-qmk-kq-mini`: Keyboard Quantizer Mini (RP2040) 用の Vial/QMK。
- `keyball`: Keyball39 (Pro Micro / ATmega32U4、`keyball39` の `via` キーマップ) 用の QMK。
- `zmk-keymap-docgen`: Python のツール。ZMK の `.keymap` から KEYMAP.html と KEYMAP.xlsx を生成する。`zmk_to_vial.py` は LisM のキーマップを KQ-mini の EEPROM デフォルトに変換する。ZMK の各リポジトリも、これを自身の `tools/keymap-docgen` submodule として取り込んでいる。

**ファームウェアやキーマップの変更は、このリポジトリではなく submodule のリポジトリで行う。** そのリポジトリの `custom` ブランチに PR を出して変更し、その後このリポジトリで submodule の参照を更新する。参照を更新するのは、変えたい submodule だけにする。パスを付けずに `git submodule update --remote` を実行すると、すべての submodule が追跡ブランチの最新に進んでしまう。参照更新のコミットメッセージには、各 submodule を `<submodule>: <旧 SHA> → <新 SHA> (ryo-aoki-pc/<repo>#N)` の形で並べる。submodule の参照を更新するコミットは、タイトルの末尾に `(submodule 参照更新)` を付ける。

### LisM 基準

`zmk-config-LisM` が、レイヤー構成 (BASE … SCRL の 10 レイヤー)、タップホールド設定、AML (オートマウスレイヤー)、スクロール速度、スリープの基準になっている。ZMK の 4 リポジトリはすべてこれに揃えている。動作を変えるときは、たいてい ZMK の 4 リポジトリすべてに入れる必要があり、`keyball` と `vial-qmk-kq-mini` にも入れることが多い。そうした変更では README の「共通基盤」の表も更新する。

KQ-mini と Keyball39 は組み合わせて使い、役割を分担している:
- Keyball39 は LisM BASE 配列の素の HID コードだけを送る。マウスレイヤーと AML も Keyball39 側で実装している。
- レイヤー、mod-tap / layer-tap、タップホールドのタイミングは KQ-mini が担当する。これらは `lism.keymap` + `lism.vialmap.json` から生成した EEPROM デフォルトで決まる。

どちらかを変える前に、README の「Keyboard Quantizer Mini + Keyball39 の役割分担」を読むこと。

## リリースから書き込みまでの流れ

`keyball`、`vial-qmk-kq-mini`、ZMK の 4 リポジトリの CI は、`custom` ブランチをビルドするたびに (push 時など) 次の 2 つを行う:
- 固定タグ `firmware-latest` のプレリリースを削除して作り直す
- ファームウェアと `BUILD_INFO.txt` をそこにアップロードする

`tools/` のスクリプトは `https://github.com/<repo>/releases/download/firmware-latest/<asset>` からダウンロードする。そのため書き込まれるのは `custom` の最新ビルドで、このリポジトリが参照しているコミットとは限らない。

アセット名はリポジトリをまたいだ取り決めになっている:
- `tools/flash-zmk.ps1` の `$KEYBOARDS` 表には、ZMK の各リポジトリの `build.yaml` の `artifact-name` が直接書かれている。`{v}` は LisM の `trackball` / `non_trackball` の版を表すプレースホルダで、ZMK Studio 版ではスクリプトが末尾に `_studio` を付ける。`settings_reset-seeeduino_xiao_ble-zmk` も直接書かれている。
- Keyball と KQ-mini のアセット名は、それぞれのスクリプトに直接書かれている。

submodule 側でアーティファクト名を変えるときは、スクリプトと README の URL の表も更新する。

## tools/ の構成

- 各 `*.cmd` は、ダブルクリックやファイルのドラッグ＆ドロップで起動するための薄いラッパーで、ASCII 文字だけで書く。`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0<name>.ps1"` を実行し、`pause` してから、スクリプトの終了コードで終了する。
- `flash-uf2.ps1` は UF2 書き込みの中心。`flash-zmk.ps1` (`-Target nRF52840` を付けて) と `flash-kq-mini.ps1` (`-Target RP2040` を付けて) は、どちらもこれを呼ぶ。処理は 4 段階:
  1. `.uf2` を検証する: マジックナンバー、ファミリ ID、アドレス範囲、ブロックの欠けが無いこと。
  2. `INFO_UF2.TXT` が対象のボードと合うブートローダのドライブを選ぶ。KQ-mini の場合は、先に CDC シリアルポートへ `dfu` を送ってブートローダに切り替える。
  3. ファイルサイズを先に確保してからデータを書き込む。
  4. ドライブが消えたら成功と判定する。ブートローダがリセットした後のクローズ時の例外は想定どおりの動作。

  `dfu` コマンドは NUL で 16 バイトに埋めて送る。古い KQ-mini のファームウェアは 16 バイト (CDC のエンドポイントサイズ) に満たないパケットを捨てるので、埋めないと届かない。この埋め込みは残すこと。
- `flash-zmk.ps1` は、書き込みを始める前にすべてのアセットをダウンロードする。その後、右 (セントラル) → 左 (ペリフェラル) の順に書き込む (設定リセットを挟むこともできる)。`-Keyboard` と `-Mode` を指定するとメニューを出さずに実行する。`.uf2` のパスを渡すと、そのファイルを `flash-uf2.ps1` で書き込むだけになる。
- `flash-keyball.ps1` は Intel HEX を検証する:
  - チェックサム
  - イメージが caterina ブートローダの始まる 0x7000 より前に収まること

  avrdude が無ければ v8.3 (SHA256 で固定) をダウンロードし、caterina の COM ポートが現れるたびに片側ずつ書き込む。
- `keyball-check.ps1` は読み取り専用の診断スクリプト。`Add-Type` で読み込む C# のヘルパーを使い、raw HID で VIA の get 系コマンドを送る。VIA の set / 書き込み系のコマンドは決して送らないこと。
- `lib/firmware-latest.ps1` は dot-source で読み込む。`Get-FirmwareLatest` (複数のアセットを続けて取得するための `-Quiet` がある) と `Show-FirmwareBuildInfo` を提供する。
- ダウンロードしたファイルは `tools/.cache/` に保存する (git の管理外)。

### PowerShell の約束事 (必須)

- 対象は **Windows PowerShell 5.1** (`powershell.exe`) で、PowerShell 7 ではない。例えば、TLS 1.2 を明示的に有効にし、`Invoke-WebRequest` に `-UseBasicParsing` を付け、進捗バーを抑止している。
- `.ps1` は **UTF-8 (BOM 付き)** のままにする。BOM が無いと、日本語版 Windows の PS 5.1 は日本語の文字列を CP932 として読んでしまう。新しく作る `.ps1` にも BOM を付ける。
- `.gitattributes` で、`.ps1`・`.cmd`・`.bat` の改行は **CRLF** に固定されている。
- `lib/` 以外のスクリプトは、日本語のコメントベースのヘルプで始まり、`param` の直後で `Set-StrictMode -Version 2.0` と `$ErrorActionPreference = 'Stop'` を設定する。
- 書き込みスクリプトでは、失敗は `Stop-WithError` を通す (赤字で `失敗: …` と表示し、終了コード 1 で終了する)。成功時は `成功` または `完了` と表示し、終了コード 0 で終了する。呼び出し側は `$LASTEXITCODE` を確認する。
- これらのスクリプトは、ドライブの列挙・シリアルポート・HID・PnP といった Windows のデバイス API を使うため、Linux のコンテナでは動作を確認できない。

## README の保守

スクリプトの動作、オプション、メニューの項目、既定値を変えたときは、同じ PR で README の該当する節も更新する。README の各節は、`#xiao-をブートローダにする方法` や `#最新ファームウェアの取得元-firmware-latest-リリース` のような見出しのアンカーで互いにリンクしているので、見出しを変えるとリンクが切れる。
