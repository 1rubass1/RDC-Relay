# G121 — Native title Help icon, direct About and visible Journal dialog

**Date: 2026-11-11.** Private RC1 Owner UI candidate. Public release and live installed app unchanged.

## Owner request and root cause

- Replace the purple/stylized question button with a **standard blue Windows question-mark icon**, move it to a logically related location, remove the Help context menu, and open **Справка / О программе** immediately.
- Add a **Показать журнал** action on the LEFT of the About dialog footer, retaining **Закрыть** on the right. Remove the extraneous version suffix from the journal window title.
- Previously the context-menu Open Journal handler only called `Render-CompactLog` and focused `$log` in the MAIN GUI. This was invisible when the Help modal was already open. It also only displayed the viewport-size subset of the Owner journal, rather than the retained history.

## Targeted implementation

- In `Source/remote-window.ps1` the old `RdcCircleButton` is no longer instantiated for Help: the action is a 32×32 native `System.Windows.Forms.Button` with the standard Win32 `SystemIcons.Question` bitmap, full keyboard and accessible name **Справка / О программе**. Its position is directly to the right of the **RDC Relay** title within a non-wrapping header `FlowLayoutPanel`. Stop and Account remain in the right actions group. The original custom button class is retained for unrelated historical/test uses; no tray files changed.
- Help button dispatches exactly once to `Show-RdcAbout`, which maintains the existing mode-specific text and Owner `Show-RdcOwnerHelp` modal; no Help context menu or dead `openLogItem` remains. The non-Owner About message remains available directly.
- About dialog footer is now a 2-column `TableLayoutPanel`, **Показать журнал** (160×34) on the LEFT, **Закрыть** (96×34, Enter/Escape default) on the RIGHT. The rest of the user-approved G113–G115 dark Help style, scrollable text, native question icon and adaptive height are unchanged.
- The new journal button calls `Show-RdcOwnerJournal` with the real Help dialog as modal parent. It **opens** a separate resizable, dark, scrollable and read-only WinForms dialog with a versionless caption `RDC Relay — журнал`, header `Журнал`, and explicit Close. This fixes the previously invisible main-pane focus behavior.
- `Get-RdcOwnerJournalText` creates a fresh snapshot of the already bounded and filtered Owner Host event history (`$script:eventBlocks`, last 64 events, plus any active event). **It does not** open original Remote log files or raw credentials, access the network, launch Notepad, or modify the live Host. If no events have arrived, the window displays `Журнал пока пуст.`.
- No change to actual running Host/Remote, Account menu, Stop/Reconnect buttons, tray, installed GUI, stable 1.5.18, registry, user shortcut, stored credentials, or release feed. Concurrent Designer/Tray changes in `COORDINATION/BOARD.md` and `docs/dev/design/icon-concepts-2026-11-11/` were left out of the G121 scope.

## Verification

- Existing real AST-derived WinForms Stop/Reconnect/Help modal tests updated for the left/right footer: **38/38 PASS**.
- New `Tests/Test-V16OwnerHelpJournalRoute.ps1`: AST-direct Help click, no intermediate menu, question glyph/title placement, Owner journal snapshot with more than six lines, empty placeholder, real Journal dialog child controls/scrolling/theme/versionless title, and real Help footer button click with correct modal parent: **16/16 PASS**.
- Full safe RC1 suite `Tests/Invoke-V16Rc1SafeRegression.ps1`: **52/52 PASS**, exit 0 (includes the new Help/Journal route test). Standalone Setup `Tests/Test-V16StandaloneSetup.ps1`: **19/19 PASS**. Setup/Launcher icon verification **10/10 PASS** in the full builder.
- Private standalone RC1 contains 21 SHA-checked payload members. Current STARMER Desktop **`RDC-Relay-1.6.0-RC1-NativeHelpJournal-Setup.exe`**, SHA256 `58B4ECB4DB48448BB3C75F2E3295352A67E44646040D65425030E1EA56852667`; **`RDC-Relay-1.6.0-RC1-NativeHelpJournal-Portable.zip`**, SHA256 `4DE79F0619057A84B560D8CBD78F45375516FA41FD0B507C89ECAB2701FA0101`. The old G120 Setup/Portable were independently hash-checked and archived in `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G121_Superseded_AccountGroup`; stable v1.5.18 rollback installer SHA verified unchanged.

## Remaining gates

Owner physical screen + DPI acceptance, independent Reviewer and any full runtime Host/Remote journal with real devices remain pending. NO public release, no installer executed, no modification to installed running app.
