# 回帰シナリオの期待値

このフォルダの JSON は人が確認する固定の期待値です。シミュレータの出力や `tools/expected/*.json` から期待値を生成しません。入力を変えずに期待値だけを更新して成功にする運用は避け、元の設定・上流仕様と照合します。

`boards.json` はチェックアウトされた各 `.keymap` の BASE の位置と、150ms のタップホールド設定に基づきます。キー位置は 0 始まりです。KQ-mini 単体の入力だけは HID usage を位置として使います。

| 機種 | Q | A | Enter の layer-tap | SYM の momentary |
| --- | ---: | ---: | ---: | ---: |
| LisM | 0 | 10 | 37 | 35 |
| AroundFortyRB | 0 | 10 | 37 | 36 |
| KUKEY42 / roBa | 0 | 10 | 41 | 39 |
| Pyuron | 0 | 10 | 37 | 35 |
| torabo-tsuki-lp | 13 | 25 | 60 | 58 |
| KQ-mini (HID usage) | 20 | 4 | 40 | 230 |

ZMK の `balanced` と KQ-mini の `permissive_hold` により、149ms の解放は A、151ms の解放は Ctrl です。SYM では Q の位置が `1` (usage 30) です。SYM を先に解放しても、押した時点の `1` の解放を送ります。

Keyball39 は `keyball/qmk_firmware/keyboards/keyball/keyball39/keymaps/via/keymap.c` の素の HID 出力を検証します。`keyball-kq-mini` は同じ物理操作を KQ-mini へ中継し、上流の A と下流の Ctrl が別々に検証できるようにしています。

`lism-behaviors.json` は `zmk-config-LisM/config/lism.keymap` の実際のビヘイビアに基づきます。

- Vim `o`: End → Enter。
- Vim `g`: 単押しは無出力、2回押しは Ctrl+Home。
- Vim `dd`: Home → Shift+End → Ctrl+X。
- Ctrl+`u`: Ctrl をマスクして PageUp。
- Vim `v`: visual に移動し、もう一度 `v` で Right を送って BASE に戻る。

`lism-pointer.json` は LisM の右センサーの値を入力し、`boards/shields/lism/lism.dtsi` の変換・入力プロセッサに基づきます。初回の移動は XY 反転後に 0.5 倍になるため、X=-18 は出力+9、X=-20 は出力+10です。AML のしきい値は10、キー解放後の抑制は200ms、累積のリセットは停止が100msを超えたとき、期限は10000msです。SCRL は加速せず1/16で、横軸だけを反転します。

キーの `mods` はその出力時点の HID 修飾ビットです。Ctrl / Shift の単独の出入りも検証対象に含めます。ZMK v0.3.0 の `CONFIG_ZMK_HID_SEPARATE_MOD_RELEASE_REPORT` は既定で無効なので、暗黙の修飾とキーの解放は同じレポートです。その差分は修飾の解放、キーの解放の順に正規化し、キー解放時の `mods` は0になります。時刻を省いた期待レコードは出力順序と値を検証し、タイマー境界のシナリオでは必要な時刻を明示します。

これらは設定の回帰テストです。ファームウェア全体をエミュレーションした結果や、USB / BLE・実際のセンサーで測定した結果ではありません。既存の `hold-tap-vectors-zmk.ps1` と `hold-tap-vectors-qmk.ps1` で上流のタップホールドのテストベクトルも別途検証します。

`boards-pointer.json` では各ボードの listener / overlay の軸変換・楕円補正を確認します。KUKEY42 の X=40 は1/2の補正後に初回0.5倍で10です。Keyball39 の右センサー Y=8 を4回送るケースは、8ms間隔の報告、Q8の速度64/96/112/120と倍率192/224/240/248により、出力が6/7/7/8になります。3回目の端数128を持ち越さないと、4回目が7に変わります。

LisM のクリックは SCRL 内で行います。キーの物理押下で一度 AML を解除し、ボタンの入力で同時刻に再発動します。ボタン解放も期限を延ばすため、期限は最後のボタン解放から10000msです。KUKEY42 のドライバ内スクロールと Bluetooth の接続操作は、PowerShell のテストで未対応として失敗することを別途確かめます。

`kq-overrides.json` は KQ-mini の実際の `KEYMAP.vil` と Vial/QMK の key override・マクロ処理に基づきます。CapsLock の HID usage 57 でVimレイヤーを押したまま、Ctrl+U は Ctrl を抑制した PageUp、Shift+O は M5 の Home → 100ms → Enter → 100ms → Up、Shift+Y は tap-dance を M3 の Shift+End → 100ms → Ctrl+C に置換することを検証します。Vial マクロは実際の修飾状態を消すため、最後に物理 Shift を離しても余分な解放レポートを送りません。

`kq-mouse.json` は、マウスボタン1を HID usage 209 の入力として KQ-mini のタップホールド判定に含めることを確認します。Aを保持してクリックを完了すると `permissive_hold` が確定し、保留したボタンの押下・解放も再生します。Keyball39 の SCRL で A の位置を押す場合は、元のキーマップが既に `KC_LCTL` なので、押下時点から Ctrl です。連携時にホイールとキーを混在させる操作は現在未対応として失敗し、その診断を PowerShell テストで確認します。
