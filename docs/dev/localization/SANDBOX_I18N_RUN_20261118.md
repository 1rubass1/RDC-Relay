# RDC Relay 1.6.0 — Windows Sandbox RU/EN visual smoke result

**Date:** 2026-11-18. **Result: PASS for offline Owner-dialog smoke at 96 DPI; NOT full application or release GO.**

## Exact isolated snapshot

- Tested commit: `742a0a8e63b25e30d753cb549cbcae4fb9ef325a` (clean private worktree branch `fix/rc1-tray-exit-prompt`).
- Source ZIP SHA-256: `6d350460c91b90199b017df6d6932ddcb09252ac008d649903b3f600b43aa6b2`. Archive created by `git archive HEAD Source Tests Scripts Installer` and mounted **read-only**.
- Offline Windows Sandbox `.wsb`: `[local project root]\_archive\RDC_I18n_Sandbox_742a0a8_20261118\RDC-I18n-Smoke.wsb`.
- Guest networking, vGPU, camera/microphone, clipboard and printer redirection disabled; separate writable Output mapping only for reports/images.
- First attempt using Expand-Archive was blocked by unavailable PowerShell Archive module before tests; corrected to built-in .NET ZipFile in commit `742a0a8` and reran successfully. The failed preliminary run is not counted as a test pass.

## Guest results (not simulated host results)

| Test | PASS | FAIL |
| --- | ---: | ---: |
| Test-V16OwnerHeaderStatusRu.ps1 | 97 | 0 |
| Test-V16OwnerDialogLanguage.ps1 | 26 | 0 |
| Test-V16OwnerAccountSwitchDialog.ps1 | 24 | 0 |
| Test-V16OwnerStopHelpDialogs.ps1 | 41 | 0 |
| Test-V16OwnerLanguage.ps1 | 25 | 0 |
| Test-V16OwnerJournalLanguage.ps1 | 24 | 0 |
| Test-V16OwnerRealUpdateNotice.ps1 | 23 | 0 |
| Test-V16OwnerTrayMenu.ps1 | 50 | 0 |
| **Eight functional suites** | **310** | **0** |
| Test-V16OwnerSandboxVisual.ps1 | **6 PNG captures** | **0** |

Guest sentinel: `Output\done.txt = PASS`; machine-readable test summary in `Output\smoke-report.txt`; six screenshots and visual size/DPI report in `Output\screens`.

## Visual inspection at Sandbox's actual DPI

- Guest DPI: **96 x 96 (100%)**. Stop and Reconnect: **496 × 207 px** on both locales. Account Switch: **616 × 364 px** on both locales.
- Six inspected PNGs: `ru-RU-stop.png`, `en-US-stop.png`, `ru-RU-reconnect.png`, `en-US-reconnect.png`, `ru-RU-accountswitch.png`, `en-US-accountswitch.png`.
- Both languages show readable uncut dialog titles, warning icons, questions, body paragraphs and button labels; English Account Switch intro wraps naturally across two lines. Dark styling and button placements are preserved. Default safe action remains **No/Нет** (also asserted by WinForms tests).
- Image assets are outside Git at `[local project root]\_archive\RDC_I18n_Sandbox_742a0a8_20261118\Output\screens\`, not shipped in the RDC Relay build.

## What this does NOT prove

- Full Host and GUI running together in the disposable guest, tray-click propagation across processes, any real Desktop Commander session, authentication, reconnect or credentials.
- WinForms rendering at 125%, 150% or 200%, high-contrast system themes, multiple monitors, screen readers or keyboard accessibility beyond the scripted default-No contract.
- Startup vendor banner compatibility inside a live Remote session, true installer/upgrade/repair/uninstall/rollback, or the production update button path.
- Complete localization coverage: several transient IPC/test-mode strings, full Help body and release installer paths remain pending.

**Next gate:** complete transient GUI strings and test source-level fallback; then repeat visual smoke at nondefault DPI and run a separate credential-free Host/GUI integration fixture. Keep release GO closed.
