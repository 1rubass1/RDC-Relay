# G113 — Owner-only Stop Remote and Help dialogs, same theme as Account Switch

**2026-11-11 · Programmer implementation candidate, owner visual acceptance and independent Reviewer pending.** **Not a public release.**

## Owner request

The button **«Остановить»** opens an overlong system confirmation. Replace its Owner-GUI confirmation with one text sentence only, **«Остановить Remote?»**. Align the visual style and title with the already accepted Owner Account Switch dialog. Restyle **«Справка / О программе»** to match the same dark modal design. No underlying Host/Remote action or account behavior changes.

## Implemented

- `Source/remote-window.ps1` adds `New-RdcOwnerStopDialog` / `Show-RdcOwnerStopConfirmation`. Owner Stop is now a native **WinForms FixedDialog** centered on parent, title `Остановка Remote`, Segoe UI 10pt, background RGB(29,32,36), Gainsboro text, 24px horizontal padding, standard Windows Warning triangle and one bold message **exactly** `Остановить Remote?`. Same rectangular 96×34px Yes/No buttons and 34px height as Owner Account Switch. Cancel/Enter/Escape **No**, only explicit Yes queues the existing `STOP` action after unchanged `ownerManagedMode` and `ownerCanStop` capability guards; Start action unchanged.
- `Source/remote-window.ps1` adds `New-RdcOwnerHelpDialog` / `Show-RdcOwnerHelp`: same dark fixed, centered modal; title `RDC Relay — справка`; heading `Справка / О программе`; scrollable, readable, noneditable `RichTextBox` preserving the existing Owner mode-specific content and safe Remote PID diagnostic; single `Закрыть` rectangular 96×34px, Enter/Escape close. No browser, Host, Remote, account mutation or file operations.
- Both form replacements are **Owner GUI only**. Legacy 1.5.18 Stop path / legacy Help MessageBox and full product behavior remain untouched.
- Structure follows Windows App Design Guidelines and Fluent 2 dialog guidance: safe default for a risky action, concise question, stable footer, consistent typography/color and keyboard cancellation.

## Verification

- New `Tests/Test-V16OwnerStopHelpDialogs.ps1`: AST-extracted **real** dialog constructors instantiate actual WinForms controls in isolation and check exact wording, native warning icon, titles, dark theme, measured bounding box, button layout, safe No/Yes routing, Host gate and preserved Help content; **20/20 PASS**. No active Host or Remote is invoked.
- Complete bounded `Tests/Invoke-V16Rc1SafeRegression.ps1` includes test above: **48/48 PASS**, exit code 0.
- Standalone `Tests/Test-V16StandaloneSetup.ps1` against the actual built G113 embedded Setup: **19/19 PASS**.
- `Scripts/build-rc1-full.ps1 -Build`: **21** SHA-checked embedded payload members, Setup/Portable compiled and verified.
- STARMER Desktop:
  - `RDC-Relay-1.6.0-RC1-StopHelpDialogs-Setup.exe`, SHA256 `7F4055DF0D050F01884AE0F5510EBA1CF26F50CB31B5B1CAD04EF0CC2820F2CA`.
  - `RDC-Relay-1.6.0-RC1-StopHelpDialogs-Portable.zip`, SHA256 `DD652BD0CF58E028694B0528DEE037F2A8436E010B347338C61D7971CDCA1827`.
- G112 old pair validated by hash then archived under `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G113_Superseded_InstallPrompt`; stable 1.5.18 rollback EXE verified and preserved.

## Pending and preservation

Owner-installed visual test of both dialogs, DPI/scaling/accessibility and independent Reviewer remain **NOT CHECKED**. **The installer was never run on the installed system;** no running GUI, Host/Remote, Windows uninstall registration, tray, OAuth, shortcuts, stable rollback or public release/feed was changed.
