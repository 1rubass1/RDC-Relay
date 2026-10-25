# RDC Relay 1.6.0 RC1 — private STARMER observer pilot (2026-10-25)

**Role / task:** Programmer, PROG-006A-INTEGRATION continuation. Existing Draft [PR #23](https://github.com/1rubass1/RDC-Relay/pull/23), branch `feature/v1.6-host-gui-owner-pilot`.

**Disposition:** A real, installed, side-by-side Windows **observer** pilot is running on STARMER with the original full WinForms GUI, persistent tray Host and protected IPC. **PARTIAL product acceptance, NO-GO for stable release, Remote lifecycle ownership, reconnect/start/stop, full Exit or updater publication.** The owner explicitly authorized Windows tests and private RC1 installation, not public release. The existing installed v1.5.18, its shortcut and actual Desktop Commander Remote were not intentionally modified or controlled by RC1.

## Installed private candidate

- Installed: `%LOCALAPPDATA%\RDCRelayOwnerPilot\1.6.0-RC1\app`.
- User desktop shortcut: **RDC Relay 1.6.0 RC1 (Pilot)**, targets `app\RC1 Pilot Launcher.exe --observe-existing`.
- Product GUI: original `Source/remote-window.ps1` executed in an independent Windows PowerShell GUI process; X really ends only that GUI; tray Host survives. GUI re-open from tray loads current installed code and receives authenticated snapshot/events.
- Host uses separate per-source/logon mutex, protected ticket and versioned/identity-checked Named Pipe, source-root pinned. No fake-only synthetic banner is carried into actual observed journal.
- Real Remote pinned `@wonderwhy-er/desktop-commander@0.2.52` is discovered only by exact executable, command line, session, private log, PID and UTC process birth. Its ownership is **Adopted**, never Owned. Host can read log evidence and categorised tool-health markers but cannot launch, stop, reconnect, logout, update credentials or send commands to real Remote.
- Host historical log bootstrap scans **at most the last 8 MiB / 100,000 lines / 3 seconds**; if incomplete, it explicitly refuses to claim current health. Raw log lines, credentials and tool parameters are never exposed through IPC. New events are read in bounded chunks; latest health is explicitly **log evidence**, not an active network probe.
- A separately verified replacement launcher PID/birth can be passively reacquired after a legacy Remote crash/restart; observer journal epoch rotates, ownership remains Adopted and mutating permissions remain false. Missing/ambiguous identities stay Disconnected.
- Candidate Setup and Portable are built as isolated GUID stages by `Scripts/build-rc1-observer-pilot.ps1 -Build`. Only the staged candidate marker is installable, while `Source/rc1-candidate.json` in git stays blocked. Setup verifies exact 19-record SHA-256 payload and explicit process-local owner gate, refuses overwriting an existing app; upgrade script backs up the old payload first.
- No `main`/`stable` change, public updater/release/tag, auto-start or update feed publication.

### Current package and Windows outcome

- Built package: `dist\RDCRelay-1.6.0-RC1-ObserverPilot-aa060aea695d4a45899a2a90cfc3da05\package`.
- Setup SHA-256: `A8833D08A668E1642D771DCE62A0AFE5B52A22AA500954CEBB9A0F2322AAF50E`.
- Portable ZIP SHA-256: `95F2217F66B360C840128FD6FA8FF82F1E3B4D98D8B44484D0189045682DFF55`.
- Setup **exit 0**, 19 manifest payloads verified; separate shortcut target unchanged. Previous candidate preserved at `%LOCALAPPDATA%\RDCRelayOwnerPilot\1.6.0-RC1\app-backup-f753286aadd44a14a1c799f5d335cfc6`; an earlier known pilot backup `app-backup-adcd1299e3e143dbb9633571f738667d` also remains. **No backup removed.**
- Pre-upgrade Host PID **21208** stopped cooperatively by four successful `WM_QUIT` messages to exact checked owner process after user GUI had exited. No `taskkill`, recursive tree kill or Remote signal. New installed Host **33428** and original-GUI process **15556**, WinForms HWND **264626**, observed after installation.
- During this trial the **legacy Remote itself changed identity** from PID **29208** to **30984** (new birth ticks **639285254966193048**). Cause of legacy Remote crash/restart was **not established**; no RC1 control command was issued. New installed Host reattaches to the verified existing PID **30984**, remaining Adopted.
- Read-only UIAutomation inspected **33** GUI elements; window title identifies RC1 observed Remote, visible Remote PID is **30984**, ownership label includes **Adopted**, health detail displays **Remote MCP connected (log evidence)**. This is **not proof of active application-level connectivity** and not a substitute for owner interactive operation.
- First upgrade-helper execution reached new Setup exit 0 and launched the new processes, but PowerShell's `Start-Process -Wait` then waited for the persistent **descendant Host** instead of returning. The script is corrected to use `Launcher.WaitForExit(15000)` (launcher only). Verified helper child **31896** had no children and was individually ended to release the wait; Host **33428** and actual Remote **30984** remained alive. Treat that initial helper's final exit as **PARTIAL**, not a false full PASS.
- Installed v1.5.18 and three historic NOT CLEAN P1/P2 TEMP roots, plus two G7 NOT CLEAN roots, were not altered.

## Actual tests and limitations

| Scope | Result | Exit / qualification |
| --- | --- | --- |
| `Test-V16ObservedRemote.ps1 -InspectLive` | **22 PASS / 0 FAIL** | **0**; includes private-log bootstrap and simulated stale PID/birth reacquisition with no Remote mutation |
| `Test-V16OwnerRemoteState.ps1` | **23 PASS / 0 FAIL** | **0**; Adopted retarget remains no-stop, resets journal |
| `Tests/Invoke-V16Rc1SafeRegression.ps1` | **20/20 suites PASS** | **0**; static/compile/fake/injected regression, latest after retarget |
| Real source Host/GUI observation smoke (15 s) | **PASS** | **0**; one GUI start, one snapshot and event IPC client, observer-only graceful detach |
| Prior fake Host/GUI OS smoke, one cycle | **15 PASS / 0 FAIL** | **0**, own test processes cleaned; before latest retarget-only changes |
| Private Setup / manifest + installed Launcher | **PASS / PARTIAL** | Setup exit **0**; Host/GUI real processes and inspected WinForms confirmed, but human interaction not verified |
| Upgrade helper first attempt | **PARTIAL** | Setup exit **0**, final helper blocked on `Start-Process -Wait`; corrected source not yet independently executed end-to-end |
| User's physical X → tray reopen / accounts / DPI / accessibility | **NOT CHECKED** | Owner acceptance pending |
| Active Remote health, Owned Remote start/stop/reconnect/full Exit, updater | **NOT CHECKED / BLOCKED** | Existing Remote only observed; actual mutating commands intentionally absent |

The test counts are per named suite, not interchangeable with live Windows evidence. Live OS observations prove GUI/Host/IPC and read-only journal rendering, not a complete v1.6.0 feature set. Previous version of the bootstrap fixture gave **21 PASS / 1 FAIL** due to a PowerShell reserved `$PID` test parameter; corrected to `$newProcessId`, repeated **22/0**. No real Remote was stopped during the negative test.

## Owner smoke and rollback

1. Double-click **RDC Relay 1.6.0 RC1 (Pilot)**; confirm exact RC1 title and **Adopted**. Opening again should reuse the single Host/GUI, not start another Remote.
2. Press **X**. It must terminate the GUI process; tray icon and Desktop Commander Remote must remain. Tray double-click should start a **new GUI PID** and replay latest Host status and event journal.
3. Use existing Desktop Commander Remote normally via its old app/client; RC1 should show categorised changes without revealing raw tool parameters or credentials.
4. In this observer pilot the tray entry **«Закрыть RC1 (Remote останется)»** deliberately closes **only** the verified RC1 GUI/Host. This does **not** satisfy the final ADR-005 full Exit semantics, because a preexisting Adopted Remote cannot legally be terminated by RC1.
5. If RC1 misbehaves, close its GUI using X and its **RC1-specific** tray action. Do not stop Desktop Commander Remote. The complete previous RC1 `app-backup-f753...` folder is available for a reviewed same-root rollback; ordinary 1.5.18 remains installed and usable. Do not perform a blind recursive cleanup or replace unknown files.

**Next engineering gate:** owner physical UI feedback plus independent Reviewer audit of actual observer setup/backup/IPC and passive PID-reacquire safety; later implement and safely test **newly RC1-owned** Remote lifecycle before enabling account, reconnect, stop or genuine full Exit. PR #23 stays Draft and unmerged.
