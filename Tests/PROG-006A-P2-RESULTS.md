# PROG-006A-P2 — interactive Tray Host and replaceable GUI results

**2026-10-24 · Programmer · STARMER Windows PowerShell 5.1 · B1 · fake-only.**
Branch: prototype/prog-006a-p2-interactive-tray-gui, based on development 27c3a98e93ff2014bc3e09c39b83034244e87a0f.

## Scope and architecture

P2 copies the accepted P1A fake Host/GUI/secure Named Pipe implementation into an **independent** Tests/Prototypes/ARCH-016-P2 folder. Pipe names now start with rdc-p2-* and every disposable test root must be exactly RDC-P2-<GUID> within TEMP. This avoids collisions with both installed RDC Relay and P1A experiments.

P2 Host is its own **Windows PowerShell STA process** running WinForms ApplicationContext, a **real NotifyIcon** and a right-click ContextMenuStrip. In interactive mode the icon is visible and named **RDC Relay P2 SANDBOX - fake Remote**; default automated test mode leaves it invisible. Both NotifyIcon.DoubleClick and the menu **Open demo GUI** call the same TrayOpen function; test-only TEST_TRAY_DOUBLE_CLICK invokes that same function without claiming to physically click the icon. Reopening while the GUI is running reuses the existing child and displays brief user feedback instead of creating another. A test-only Stop P2 Host menu option acts **only when no GUI is running** and exits the disposable Host, not any Remote.

GUI is a **separate WinForms process** with no Remote handle, no user logfile reader and **no actual process control**. Normal X/native WM_CLOSE terminates the GUI process; Host PID/mock Remote UUID and heartbeat continue. Opening again starts a fresh GUI script from the disposable file. Build A has an orange status accent and Build B gold, with the build in the Window title/header. The test UI references existing RDC Relay dark palette and geometry, has a real header, textual fake connection status, read-only synthetic journal, synthetic event stream and disabled Start/Stop/Reconnect/Account buttons. A single About fixture button is keyboard focusable. This **does not replace or redesign the production icon**; DES-002 remains separate.

The P1A transport is preserved: bounded async JSON frames, OS-observed Windows client/server PID/session, process birthtime and per-launch credentials, TokenLogonSid ACL created before secrets, requestSequence and per-epoch replay protection, revisioned bounded event stream with snapshot-resync. No actual Remote command or caller-provided PID is trusted.

## Automated lifecycle and inherited security matrix

Run: powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File Tests\Test-Arch016P2Lifecycle.ps1

The 24 inherited P1/P1A fake-only test rows are executed **against the new P2 copy**, not the installed product. Full original accepted P1 matrix evidence remains valid for P1 itself; the P2 run is a new regression execution.

| Route | Actual evidence | Classification |
| --- | --- | --- |
| P1-01/02/03/04 | Genuine child GUI launches/closes, A -> edited B from disposable source, 8 further complete cycles; Host/mock identity stable; pre/post-HELLO fault recovery | PASS |
| P1-05/06/07/08/09 | Request/response ID equality, sized/partial frames, held open timeout, GUI Timer pulses under blocked P2 GUI IPC, two simultaneous silent peers, bounded worker peak, malformed burst | PASS |
| P1-10/12/13/14/15 | Actual pipe-peer PID/session checks, unrelated fake rogue server, allowlist, replay/epochs, incompatible protocol/generation | PASS |
| P1-16/17/18/19 | Host event revisions and snapshot recovery after gap, duplicate Host mutex denial, stale expected Host identity refusal | PASS |
| P1-20 | Outside-root GUI launch refused; real reparse and TOCTOU swap not injected | PARTIAL |
| P1-22/23 | Deliberate failing assertion with live test GUI exits nonzero and cooperative cleanup; prior P0/P0A/process/window/Remote/classifier/parity/UI/Npx mock regression suites exit zero | PASS |
| P1-11 | Different Windows logon session / remote SMB client | NOT CHECKED |
| P1-21 | Physical human tray double click / X mouse click, DPI, Explorer restart | NOT CHECKED |
| P1-24 | True release ZIP/Setup/Portable contents | NOT CHECKED |
| Extra: P1A-ACL-at-creation | Protected DACL prior to nonce writing, controlled ACL fault leaves no secret file | PASS |
| Extra: P2 tray dispatch | Synthetic test verb exercises the exact real NotifyIcon/menu TrayOpen function and detects duplicate GUI denial | PASS |
| Extra: P2 10+ GUI cycles | Real child starts/exits counted in Host, Host PID and mock UUID unchanged | PASS |
| Extra: P2 GUI version denial | Modified TEMP GUI genuinely sends protocol version 2; Host refuses HELLO, Host survives, no duplicate | PASS |

**Latest full-suite totals (24 inherited rows): 20 PASS, 0 FAIL, 1 PARTIAL, 3 NOT CHECKED, exit 0.** **4 extra PASS** (ACL-at-creation fault, shared tray Open handler, 10+ completed GUI processes, real child GUI protocol-version denial). Additional P2-specific positive checks are independent EXTRA cases and not counted as extra 24-row results. A debugging -Fast run intentionally downgrades P1-23 to PARTIAL and is **not** accepted as full inherited regression evidence.

## Independent visible WinForms test in STARMER interactive session 8

Command: powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File Tests\Test-P2VisibleWindow.ps1

This is a **real GUI window/HWND and actual OS process** test, not a screenshot or physical mouse simulation:

| Observation | Actual value |
| --- | --- |
| Owned test Tray Host PID | **15016** |
| Mock Remote UUID | **ed1aa1aaf9ed4d0bb082fbd653e76b21** |
| GUI A PID / HWND | **18464 / 13044456** |
| Native WM_CLOSE delivered only to owned GUI A | **PASS**, child terminated; Host remained |
| Source edit | Temp-only GUI Build A -> Build B |
| GUI B PID / HWND | **42276 / 2099764** |
| Tray shared open-handler activations | **2** |
| Duplicate open prevented | **PASS** |
| Host PID/mock session unchanged, GUI B newly loaded | **PASS** |
| Graceful teardown, matching surviving test Host/GUI PIDs | **None** |
| Exit code | **0** |

The final repeat used the reproducible Set-P2DemoBuild.ps1 helper to perform the A -> B edit only after GUI A exited. The test queries Win32_Process for **exact copied Gui.ps1 path, actual parent Host PID and MainWindowHandle**, then posts native WM_CLOSE to **only that owned HWND**. It does not send mouse clicks or keystrokes, force-kill processes, or restart Explorer. It verifies the visible window was actually created in session 8. It **does not prove the owner's physical tray double-click or physical X click**. Those remain **NOT CHECKED** until the owner follows the interactive demonstration instructions in PROG-006A-P2-DEMO.md and confirms observations.

## Cleanup, limitations and deliberate non-goals

- The fixtures issue test-only cooperative CLOSE_GUI / TEST_END to verified own Host/GUI and wait with deadlines. No Stop-Process/taskkill, no live Remote/installed app process calls. Native WM_CLOSE is sent only after verifying the child's unique fixture script path and parent Host PID.
- An early P2-only test run had 2 FAIL due a stale P1 pipe prefix in the **test harness**, not a production process defect. The harness was corrected; final P2 tests pass. The failed test-owned directory was removed **only after verifying no matching P2 Host/GUI was running**.
- **Two historical P1 TEMP directories remain NOT CLEAN and were NOT touched**: RDC-P1-1840a5107e624387a3e007ea92d2bef4 (bad ACL), RDC-P1-2e61d74ad79c41488491cfa10ee44b6c. Cleanup/owner or ACL changes require separate authorization.
- Actual physical mouse/notification overflow/Explorer restart, different Windows logon/SMB, updater crash/rollback, UI accessibility at high contrast/DPI/keyboard/AT, package allowlist and actual Remote remain **NOT CHECKED**. P1 path TOCTOU remains PARTIAL. Neither WinForms appearance nor secure IPC is production certification. No new general local executor, login, TCP server, real journal input or system-level configuration was introduced.
- The manual interactive launcher intentionally leaves the **user-requested fake-only Host** running until the owner selects **Stop P2 test Host**. The fixture cleanup helper refuses deletion while that Host/GUI exists. Avoid leaving demo processes running without the owner being aware.

See PROG-006A-P2-DEMO.md for exact Windows PowerShell 5.1 steps and safe disposal. Independent REV-006A-P2 and Architect research-only integration decision remain required. **No merge/release authorization.**
