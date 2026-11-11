# G115 — Adaptive vertical sizing of Owner Help dialog

**2026-11-11 · Programmer implementation candidate; visual owner approval and independent Reviewer pending. NOT RELEASED.**

## Owner request and baseline

The Owner GUI dark `Справка / О программе` modal looked disproportionately tall relative to the text. Compare with the accepted `Смена аккаунта Desktop Commander` modal. The latter has **600×325 px** client size; the old Help used **660×480 px**. Preserve the help width, icon, dark seamless text panel and footer, but reduce excessive vertical whitespace.

## Implementation

- `Source/remote-window.ps1` / `New-RdcOwnerHelpDialog` now uses the existing `Segoe UI 10` text font and WinForms `TextRenderer.MeasureText` with `WordBreak|TextBoxControl|NoPrefix` and conservative wrapping width (`dialog.ClientWidth - 80`).
- Computes the vertical need including existing **20px top, 44px heading row, 20px text breathing space, 52px footer, 16px bottom** and constrains the Help **client height to 220…325px**, where 325 equals the actual Account Switch modal. The width remains **660px** for the same line lengths and icon/title/header composition.
- For short content, the dialog becomes shorter. Long content scrolls inside the existing read-only, seamless dark `RichTextBox`; footer and Close button remain visible. Fixed centered modal, labels, keyboard close and Host/Remote behavior unchanged. No version/installer/upgrade changes.

## Verification

- `Tests/Test-V16OwnerStopHelpDialogs.ps1`: real AST-extracted WinForms constructors, actual Account Switch height comparison, short Help (smaller), real managed-Host text (no more than 325px), long Help (caps at 325px and stays scrollable), all Stop/Reconnect/Help labels/buttons and permission route regression: **37/37 PASS**.
- `Tests/Invoke-V16Rc1SafeRegression.ps1`: **48/48 PASS**, exit 0.
- `Tests/Test-V16StandaloneSetup.ps1` against rebuilt EXE: **19/19 PASS**.
- `Scripts/build-rc1-full.ps1 -Build`: 21 hash-checked payload members. STARMER Desktop current test package:
  - `RDC-Relay-1.6.0-RC1-CompactHelp-Setup.exe` SHA256 `05F173B85F942BBEB749C195AEBB4A6E0DE55EC0FA5AFE591E1AE583BD10A62F`
  - `RDC-Relay-1.6.0-RC1-CompactHelp-Portable.zip` SHA256 `62AC27BDF87E35F0FC060B5446BE6BFBD7F085F3A1F62EE62385418CF0B476B3`
- Previous G114 Setup and Portable independently SHA-checked and archived under `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G115_Superseded_ReconnectHelp`; the separate 1.5.18 rollback installer SHA was rechecked and preserved.

## Safety and remaining checks

**NOT CHECKED:** Owner visual perception on physical monitor, actual installed OS DPI scaling, independent Reviewer. Built candidate **not launched on installed STARMER system**. No installed GUI, working Host or Remote, Windows registration, shortcuts, credentials, user data, public release feed or stable release branch changed. Do not merge to public release.
