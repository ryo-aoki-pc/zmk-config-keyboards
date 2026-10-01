# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

An umbrella repo that pins the owner's keyboard firmware repos (ZMK and QMK/Vial) as git submodules, plus Windows flashing and diagnostic scripts in `tools/`. Nothing is built here, and there is no build, lint, or test command for this repo. Firmware is built by each submodule's own GitHub Actions. `README.md` is the Japanese user manual for the flashing tools and the shared keymap settings.

Everything user-facing is written in Japanese: README, script messages, script comments, and commit/PR titles and bodies. Follow that.

## Submodules

Submodules are not checked out in a fresh clone. To read their source, run `git submodule update --init [--depth 1] <path>`. Each one tracks its `custom` branch; `zmk-keymap-docgen` tracks `main`.

- `zmk-config-{LisM,AroundFortyRB,KUKEY42,Pyuron}`: ZMK configs. All four are split boards on Seeed XIAO nRF52840, pinned to ZMK v0.3.0 in `config/west.yml`. The right half is the central and the left half is the peripheral. Each one has a `Makefile` for local builds (`make`, `make single`) and a `build.yaml` that defines the CI matrix and the `artifact-name` of every build.
- `vial-qmk-kq-mini`: Vial/QMK for the Keyboard Quantizer Mini (RP2040).
- `keyball`: QMK for the Keyball39 (Pro Micro / ATmega32U4, `keyball39` `via` keymap).
- `zmk-keymap-docgen`: Python tooling. It generates KEYMAP.html and KEYMAP.xlsx from a ZMK `.keymap`. Its `zmk_to_vial.py` converts the LisM keymap into the KQ-mini's EEPROM defaults. The ZMK repos also vendor it as their own `tools/keymap-docgen` submodule.

**Changing firmware or keymaps happens in the submodule's repo, not here.** Make the change on that repo's `custom` branch through a PR there. Then bump the gitlink in this repo. Bump only the submodules you mean to change: `git submodule update --remote` with no path moves every submodule to its branch tip. The commit message for a bump lists each submodule as `name: oldsha → newsha (ryo-aoki-pc/<repo>#N)`. When a submodule is bumped, the title ends with `(submodule 参照更新)`.

### LisM is the reference ("LisM 基準")

`zmk-config-LisM` is the reference for the layer layout (10 layers: BASE … SCRL), tap-hold settings, AML (auto mouse layer), scroll scaling, and sleep. All four ZMK repos are kept in sync with it. A behavior change usually has to land in all four ZMK repos, and often in `keyball` and `vial-qmk-kq-mini` too. Each such change also updates the "共通基盤" table in README.

The KQ-mini and the Keyball39 are used together and split the work:
- The Keyball39 sends only plain HID codes for the LisM BASE layout. It also implements the mouse layers and AML.
- The KQ-mini applies the layers, mod-tap/layer-tap, and tap-hold timing. These come from EEPROM defaults generated from `lism.keymap` + `lism.vialmap.json`.

Read README's "Keyboard Quantizer Mini + Keyball39 の役割分担" section before changing either one.

## Release → flashing pipeline

On every push to `custom`, the CI of `keyball`, `vial-qmk-kq-mini`, and the four ZMK repos does two things:
- deletes and recreates a prerelease with the fixed tag `firmware-latest`
- uploads the firmware and `BUILD_INFO.txt` to it

The scripts in `tools/` download from `https://github.com/<repo>/releases/download/firmware-latest/<asset>`. They therefore flash the latest `custom` build, which is not necessarily the commit pinned here.

The asset names are a cross-repo contract:
- The `$KEYBOARDS` table in `tools/flash-zmk.ps1` hardcodes each ZMK repo's `build.yaml` `artifact-name`s. The `{v}` placeholder stands for LisM's `trackball` / `non_trackball` variants, and the script appends `_studio` for ZMK Studio builds. It also hardcodes `settings_reset-seeeduino_xiao_ble-zmk`.
- The Keyball and KQ-mini asset names are hardcoded in their own scripts.

If you rename an artifact in a submodule, update the script and the URL table in README.

## tools/ architecture

- Each `*.cmd` is a thin, ASCII-only wrapper that lets the user double-click it or drag and drop a file onto it. It runs `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0<name>.ps1"`, then `pause`, then exits with the script's exit code.
- `flash-uf2.ps1` is the core UF2 writer. `flash-zmk.ps1` (with `-Target nRF52840`) and `flash-kq-mini.ps1` (with `-Target RP2040`) both call it. It works in four steps:
  1. Validates the `.uf2`: magic numbers, family ID, address range, and that no blocks are missing.
  2. Picks the bootloader drive whose `INFO_UF2.TXT` matches the target board. For the KQ-mini, it first sends `dfu` over the CDC serial port to switch the board into the bootloader.
  3. Preallocates the file size and writes the data.
  4. Reports success when the drive disappears. Exceptions on close, after the bootloader resets, are expected.

  The `dfu` command is NUL-padded to 16 bytes so that older KQ-mini firmware, which drops CDC packets shorter than a full packet, still receives it. Keep the padding.
- `flash-zmk.ps1` downloads every asset before it flashes anything. It then flashes right (central) before left (peripheral), with optional settings_reset steps. With `-Keyboard` and `-Mode` it runs without the menu. With a `.uf2` path, it just calls `flash-uf2.ps1` on that file.
- `flash-keyball.ps1` validates the Intel HEX:
  - the checksums
  - that the image ends before 0x7000, where the caterina bootloader starts

  It downloads avrdude v8.3 pinned by SHA256 and flashes each half when its caterina COM port appears.
- `keyball-check.ps1` is a read-only diagnostic. It sends VIA "get" commands over raw HID, using a C# helper loaded with `Add-Type`. It must never send VIA set/write commands.
- `lib/firmware-latest.ps1` is dot-sourced. It provides `Get-FirmwareLatest`, which has `-Quiet` for downloading several assets in a row, and `Show-FirmwareBuildInfo`.
- Downloads are cached in `tools/.cache/`, which is gitignored.

### PowerShell conventions (required)

- Target **Windows PowerShell 5.1** (`powershell.exe`), not PowerShell 7. For example, TLS 1.2 is enabled explicitly, `Invoke-WebRequest` uses `-UseBasicParsing`, and the progress bar is suppressed.
- `.ps1` files must stay **UTF-8 with BOM**. Without the BOM, PS 5.1 on a Japanese Windows reads the Japanese text as CP932. New `.ps1` files need a BOM too.
- `.gitattributes` forces **CRLF** for `.ps1`, `.cmd`, and `.bat`.
- Every script starts with `Set-StrictMode -Version 2.0` and `$ErrorActionPreference = 'Stop'`, and has a comment-based help block in Japanese.
- In the flashing scripts, failures go through `Stop-WithError`, which prints `失敗: …` in red and exits with code 1. Success prints `成功` or `完了` and exits with code 0. Callers check `$LASTEXITCODE`.
- These scripts need Windows device APIs: drive enumeration, serial ports, HID, and PnP. They cannot be exercised in a Linux container.

## README maintenance

When a script's behavior, options, menu entries, or defaults change, update the matching README section in the same PR. README sections link to each other through heading anchors, such as `#xiao-をブートローダにする方法` and `#最新ファームウェアの取得元-firmware-latest-リリース`, so renaming a heading breaks those links.
