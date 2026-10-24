# PROG-006A-P3 — runnable owner GUI demonstration (research-only)

**PR:** [Draft #22](https://github.com/1rubass1/RDC-Relay/pull/22), [Reviewer handoff](https://github.com/1rubass1/RDC-Relay/pull/22#issuecomment-6381708244).

**Date:** 2026-10-24. **Machine:** STARMER. **Runtime:** Windows PowerShell 5.1, real Windows interactive WinForms HWND. **Branch:** prototype/prog-006a-p3-user-demo from development b2a51e5612dd6856f3f490d41cfd6544a156c574.

## Deliverable

- Portable folder Tests/UserDemo/P3/, containing three double-clickable Russian-named .cmd launch/change/cleanup helpers, matching .ps1 scripts, the isolated fake IPC Host/GUI source under Fixture/, the public project design banner PNG and README-RU.md.
- Portable test-only archive Tests/UserDemo/RDCRelay-P3-UserDemo.zip (no installation, updates or production artifacts).
- The standalone Host uses the accepted P2/P2A fake-only Windows logon-bound secure IPC and unique per-run RDC-P3-<GUID> paths/rdc-p3-* pipes. It never reads credentials, actual account, real logs, provider files or remote-window.ps1; does not start/stop or attach to real Desktop Commander Remote.
- Distinct Windows SystemIcons.Information icon and RDC Relay DEMO tooltip. Tray menu uses the exact requested Russian names: «Открыть RDC Relay», «Статус: демонстрация» (disabled), «Завершить тестовую сборку…». The last action requests user confirmation, signals only the verified own GUI via closeGeneration, and waits for its actual exit before ending Host. It uses **no Stop-Process/taskkill**. If GUI refuses to close, Host remains rather than killing any process.
- Full GUI is a **real** separately running WinForms process. Its GUI source is intentionally replacable: Gui.ps1 loads an independent DemoGui.ps1 in visible user mode; TestMode retains the P2 compatible fixture GUI. The changed DemoGui.ps1 runs in a **new process** after an actual GUI exit. Account menu accurately reflects the production account item names decoded from the original OEM-866 source, but all account/Remote operations are disabled.
- Main dimensions and colors follow native original Source/remote-window.ps1 (read-only) and NATIVE_UI_GEOMETRY.md: outer window 1074×900, header 78px, footer 38px, log 125px, divider 7px; dark #1D2024/#121417, #7B5FA2, #BF7643, #EBB857, Segoe UI and Consolas. User-mode window title and banner identify a **demonstration**, never actual connected state. DPI AutoScale is enabled, but exact visual fidelity at other DPIs is not claimed.
- The actual source app screenshot, installed files, production icon, live remote credentials and user journals were not copied into the demo kit.

## Reproducible STARMER results

| Test / criterion | Actual observation | Status |
| --- | --- | --- |
| New standalone Host and GUI A | Host PID **41492**, GUI A PID **17900**, GUI A HWND **47974272** | PASS |
| Fake Remote identity | **66de1f31b22a408ab58fc84914f0bf9f** (unchanged during GUI replacements) | PASS |
| GUI X-equivalent process exit | Native WM_CLOSE sent only to the test-owned verified GUI A HWND; GUI exited, Host PID remained 41492 | PASS |
| Updated source GUI B | Temp-only DemoGui.ps1 A→B via owner-facing helper; GUI B PID **5604**, HWND **3476190** | PASS |
| Tray shared open handler / duplicate prevention | Test-only TEST_TRAY_DOUBLE_CLICK dispatches exact TrayOpen handler; duplicate GUI denied | PASS |
| Ten complete close/reopen cycles | **10** complete native owned GUI WM_CLOSE/reopen iterations, **11 distinct GUI PIDs** including initial GUI A | PASS |
| Shared menu/Host graceful exit path | Test-only TEST_USER_FINISH calls same RequestDemoExit code route as confirmed tray menu; GUI exited, Host exited on its own | PASS |
| Remaining test-owned Host/GUI processes | **0** | PASS |
| Automated visible-window test exit code | **0**, Test-P3VisibleWindow.ps1 | PASS |
| Standalone starter selftest | **Host PID 26140 / GUI A PID 21744**; same test-owned exit route, exact-path temporary fixture cleanup, no process survivors; Start-Demo.ps1 -SelfTest exit **0** | PASS |
| Standalone starter desktop mouse clicks / menu appearance | Owner has not physically clicked tray icon or window X through this test | NOT CHECKED |
| Pixel-perfect visual similarity, 100/125/150% DPI, high contrast, Narrator and keyboard focus sweep | Layout and control properties implemented; not independently visually accepted | NOT CHECKED |
| Another Windows logon, SMB transport, Windows Explorer restart, real product ZIP/installer | Not authorized in this test | NOT CHECKED |
| True concurrent TOCTOU path-swap resistance | Not reproduced, inherited P2/P2A limitation | PARTIAL |

The automated Windows tests use native owned HWND WM_CLOSE and verified fixture IPC. They do not represent a physical mouse action and do not certify visual acceptance.

## Safety and cleanup

- Source/remote-window.ps1, installed RDC Relay, real Desktop Commander Remote, production branches main/stable, actual account/log data, system configuration and release packages remain untouched.
- Only ephemeral RDC-P3-<GUID> paths are created under user TEMP; launcher stores only the latest GUID path and test Host PID in its ignored local RunState/ directory (no nonce/secret in that marker). The cleanup helper refuses a live Host/GUI, unexpected/reparse path, unexpected child file or non-P3 root.
- Three registered historical TEMP directories, **two RDC-P1-* and unknown-provenance RDC-P2-aace757df1eb4f7cb3e2e17dbeec7a5d**, remain NOT CLEAN and were not modified or deleted.
- A transient first selftest revealed an unrelated automatic PowerShell variable naming collision in the cleanup helper; this was fixed and the exact owned temporary fixture was removed after verifying its processes had exited. The subsequent end-to-end launcher selftest passed and cleaned its own fixture.
- Production integration PROG-006A/006B/005B/005 and release remain blocked; Draft PR requires independent Reviewer and Architect disposition.

**Owner instructions:** Tests/UserDemo/P3/README-RU.md, or the same README after extracting the separate portable demo ZIP.
