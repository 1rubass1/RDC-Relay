# PROG-006A-P2 — interactive Tray Host and replaceable GUI results

**2026-10-24 · Programmer · STARMER Windows PowerShell 5.1 · B1 · fake-only.**
[Draft PR #20](https://github.com/1rubass1/RDC-Relay/pull/20). Branch: prototype/prog-006a-p2-interactive-tray-gui, based on development 27c3a98e93ff2014bc3e09c39b83034244e87a0f.

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
| P1-20 | Outside-root and root-junction refusal verified by P2A; file-symlink and true TOCTOU race remain NOT CHECKED | PARTIAL |
| P1-22/23 | Deliberate failing assertion with live test GUI exits nonzero and cooperative cleanup; prior P0/P0A/process/window/Remote/classifier/parity/UI/Npx mock regression suites exit zero | PASS |
| P1-11 | Different Windows logon session / remote SMB client | NOT CHECKED |
| P1-21 | Physical human tray double click / X mouse click, DPI, Explorer restart | NOT CHECKED |
| P1-24 | True release ZIP/Setup/Portable contents | NOT CHECKED |
| Extra: P1A-ACL-at-creation | Protected DACL prior to nonce writing, controlled ACL fault leaves no secret file | PASS |
| Extra: P2 tray dispatch | Synthetic test verb exercises the exact real NotifyIcon/menu TrayOpen function and detects duplicate GUI denial | PASS |
| Extra: P2 10+ GUI cycles | Real child starts/exits counted in Host, Host PID and mock UUID unchanged | PASS |
| Extra: P2 GUI version denial | Modified TEMP GUI genuinely sends protocol version 2; Host refuses HELLO, Host survives, no duplicate | PASS |

**Original P2-only full-suite totals before P2A (24 inherited rows): 20 PASS, 0 FAIL, 1 PARTIAL, 3 NOT CHECKED, exit 0.** **4 original extra PASS** (ACL-at-creation fault, shared tray Open handler, 10+ completed GUI processes, real child GUI protocol-version denial). Additional P2-specific positive checks are independent EXTRA cases and not counted as extra 24-row results. A debugging -Fast run intentionally downgrades P1-23 to PARTIAL and is **not** accepted as full inherited regression evidence.

## Baseline visible WinForms test before P2A (STARMER interactive session 8)

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

## PROG-006A-P2A — narrow boundary and ticket-failure corrections (2026-10-24)

**Branch/commit:** `prototype/prog-006a-p2-interactive-tray-gui` / `92125f16624e739897dcb13326ac580272dc487d`; [Draft PR #20](https://github.com/1rubass1/RDC-Relay/pull/20). [Independent review handoff](https://github.com/1rubass1/RDC-Relay/pull/20#issuecomment-6376207083).

**Scope:** only `Tests/Prototypes/ARCH-016-P2/P1Core.cs`, `Host.ps1`, `Gui.ps1`, `Tests/Set-P2DemoBuild.ps1`, the P2 lifecycle harness, a new `Tests/Test-P2BoundaryGuards.ps1`, and this evidence/governance update. No product `Source/`, installed app, real Remote, production branches, ACL settings, Explorer, or release files changed.

### Implemented

- `P1Core.cs` canonicalizes the fixture root without a trailing separator; enforces the exact direct-child `TEMP\RDC-P2-<GUID>` boundary with separator-aware comparisons; checks the root itself and all existing path components for `FileAttributes.ReparsePoint`; requires `Gui.ps1` to be the exact direct child and non-reparse. The same checks run at Host construction and on every GUI launch, including immediately before `Process.Start`.
- `PrivateFile` accepts only direct fixture children `controller-auth.json` and `gui-ticket.json`, revalidates the root/destination/temp path before creation and replacement, creates the protected temp file with its DACL before writing bytes, and cleans a temp file only when its path is still validated.
- `Set-P2DemoBuild.ps1` rejects non-direct/nested roots, root or path-component reparse points, a reparse `Gui.ps1`, any nested directory, unexpected direct-child files, and reparse entries before reading the source. It revalidates immediately before source read/write and verifies the written build marker.
- `Gui.ps1` validates the exact P2 root and `gui-pulse.txt` path on each test pulse. It refuses reparse paths and uses delete-then-`FileMode.CreateNew` for the normal pulse file instead of opening/following an existing file link. This reduces file-link redirection risk but does **not** prove race-free directory-handle semantics.
- `-FailGuiTicketBeforeWrite` is a P2 test-only Host switch. It throws inside the controlled `Open()` failure path **before JSON serialization, temp-file creation, ACL/file creation or ticket bytes**. Failure clears GUI state to `NONE`, increments the failure counter, records only `gui / launch-failed`, returns a normal IPC snapshot, and does not leak the exception or nonce. `TEST_LAST_EVENT` is a test-only authenticated assertion route.

### Actual STARMER verification

**Full `Test-Arch016P2Lifecycle.ps1` (Windows PowerShell 5.1):**

- Matrix: **20 PASS / 0 FAIL / 1 PARTIAL / 3 NOT CHECKED**, `EXTRA_PASS=5`, **exit 0**.
- P2A sub-suite included in that run: **4 PASS / 0 FAIL / 2 NOT CHECKED**, **exit 0**.
- Root-junction negative: actual test-owned NTFS junction. Host startup exited `10` before writing `controller-auth.json` or `gui-ticket.json`; `Set-P2DemoBuild.ps1` refused the junction before source access. The target `Gui.ps1` hash and the separate outside sentinel hash were unchanged.
- GUI-ticket failure: injected before serialization/write. The authenticated `TEST_OPEN` returned a snapshot; `guiState=NONE`, `guiPid=0`, `guiFailures=1`, `guiStarts=0`; latest event was the generic `gui / launch-failed`; no `gui-ticket.json`, no `*.secured`, no GUI child; Host PID remained the same and its tick advanced. Cooperative Host exit and fixture cleanup succeeded.
- **NOT CHECKED — `Gui.ps1` file reparse:** Both `New-Item -ItemType SymbolicLink` and native `CreateSymbolicLinkW` with `ALLOW_UNPRIVILEGED_CREATE` were refused; native error **1314 / ERROR_PRIVILEGE_NOT_HELD**. The test did not fake a PASS; the helper and constructor guards are in place, but that negative case needs a supported link-creation environment.
- **NOT CHECKED — redirected pulse file link:** the same `ERROR_PRIVILEGE_NOT_HELD` result prevented a file symbolic link for `gui-pulse.txt`; the sentinel-through-file-link scenario was not executed. The root-junction outside sentinel test did pass.
- P1-20 remains **PARTIAL**: the root junction is now tested, but a true concurrent TOCTOU swap was not reproduced. Physical mouse X/tray double-click, DPI/accessibility, cross-logon/SMB and packaging remain **NOT CHECKED**.

**Final `Test-P2VisibleWindow.ps1`: exit 0.** Actual visible native HWNDs in interactive Session 8:

| Observation | Value |
| --- | --- |
| Test Host PID | **15728** |
| Fake Remote UUID | **8e4dfa2bf4bc4b38b609f210e70c00d0** |
| GUI A PID / HWND | **24916 / 35783940** |
| GUI B PID / HWND | **17220 / 4850662** |
| Shared tray handler activations | **2** |
| Host/mock identity unchanged; GUI PID/HWND changed | **PASS** |
| Test-owned surviving Host/GUI processes | **0** |

The visible test used the documented build helper and native `WM_CLOSE` to the verified owned GUI HWND. It did not physically click X or double-click the tray icon.

### Final boundary and cleanup status

- The full lifecycle output reported `REMAINING_FIXTURE_PIDS=` (empty); visible-window output reported `VISIBLE_FIXTURE_SURVIVORS=` (empty). P2A boundary tests cleaned their own GUID-scoped fixtures on successful completion.
- Historical `RDC-P1-1840a5107e624387a3e007ea92d2bef4`, `RDC-P1-2e61d74ad79c41488491cfa10ee44b6c`, and the separate unknown-provenance `RDC-P2-aace757df1eb4f7cb3e2e17dbeec7a5d` remain **NOT CLEAN and untouched**.
- `Source/remote-window.ps1` remains unchanged; real Remote, installed RDC Relay, `main`, `stable`, and release packaging were not touched. PR #20 remains Draft / unmerged pending independent **REV-006A-P2A**.

See PROG-006A-P2-DEMO.md for the original interactive demo steps and safe disposal. **No merge/release authorization.**
