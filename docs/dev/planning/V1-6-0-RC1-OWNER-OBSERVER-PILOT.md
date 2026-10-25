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


## PROG-006A-G8 — product replacement, safe RC1 recovery (2026-10-25; independent review pending)

This section supersedes the older installed-package hashes **for source/build artifacts only**. The previously installed private observer RC1 stays as-is; the new G8 build has **not** been installed or launched.

### Actual product UI route matrix

| Complete original GUI surface | G8 route | State / boundary |
| --- | --- | --- |
| Status, connection evidence, tool health, bounded activity log | Persistent RdcOwnerRuntime Host snapshot/events via authenticated IPC to `rc1-owner-gui.ps1` and the original `remote-window.ps1` | Implemented and fake-OS validated; health comes from actual existing Remote log evidence, **not** network health proof |
| X, tray reopen | OwnerGui FormClosing returns without legacy Stop; GUI process terminates; tray Host opens a new process from current source and state/log replay | Native ten-cycle FAKE_ONLY OS smoke **43/0/exit0**, 11 GUI generations, one Host; newly built G8 staged GUI still NOT CHECKED interactively |
| Account → Devices | Host `OPEN_EXTERNAL/DEVICE_MANAGEMENT` accepts only exact official `https://mcp.desktopcommander.app/`; GUI independently verifies reply URL on explicit click | Source integrated, but real browser navigation NOT CHECKED |
| Account → Verify device | Same IPC route for `DEVICE_VERIFICATION` and exact `https://mcp.desktopcommander.app/device/verify` | Source integrated, browser NOT CHECKED |
| Help → Show RC1 journal, About | Focus the original bounded sanitised log control; About explains X and Adopted permissions | Source integrated, GUI physical click NOT CHECKED |
| Start/Stop, Reconnect, Change account, Updates, full Remote Exit | Typed `REMOTE_ACTION` is authenticated but **rejects** all mutations for Adopted/Unknown; corresponding GUI controls remain disabled, no fake success | **BLOCKED**, not counted as functional parity: no verified RC1-Owned real Remote supervisor/approval. Stable updater off |

Device links open a browser for owner-directed account management; they **do not mutate the Remote process or change its local credentials**. Browser/login actions are outside tested Host/GUI state. GUI cannot grant itself remote-control capabilities: Host snapshot is the authority; direct legacy Start/Stop/Restart/Change account call sites cannot execute in OwnerGui.

### U1 controlled backup, post-Setup failure and fail-closed recovery

- `Scripts/upgrade-rc1-observer-pilot.ps1 -Execute` requires exact branch-independent candidate Setup SHA-256 supplied separately (`-ExpectedSetupSha256`), 19 exact manifest payload SHA-256 hashes, the attested current private RC1 `app`, and verified old Host and pinned existing Remote PID/birth. It cooperatively exits only that private Host **after** user GUI is safely gone. **This helper was not run against the live install in G8.**
- Previous attested `app` moves to a *new unique* `app-backup-<GUID>`. If Setup fails before app publication, its unchanged backup is copied to a private `.restore-<GUID>`, verified and published as `app`. If a verified G8 candidate was published by this run but Launcher or Host failed, candidate is renamed to `app-failed-<GUID>`, older attested app is independently staged/restored, and both archives are retained. No unknown path is overwritten/deleted.
- If Setup reports failure **after** it might have published an app, or the new app is foreign, hashed incorrectly, a reparse path, active or ownership is ambiguous, **do not move or overwrite it**: retain candidate and backup for manual reviewed recovery. The original private RC1 can be relaunched only after the same existing Remote identity is verified. Never use `taskkill /T /F`, `remote --logout`, or a speculative Remote restart to recover.
- Isolated one-time `Tests/Test-V16UpgradeRollback.ps1` used fresh `%TEMP%\RDC-RC1-U1-<GUID>` fixture, not live app or historical backups. Cases: Setup never publishes app; Launcher failure; Host missing; tampered/foreign candidate; active candidate. **11 PASS/0 FAIL/exit0**, exact synthetic root cleaned. This is **not** proof of a real installer failure or full live in-place upgrade.

### New isolated G8 build (not installed)

- Package: `dist\RDCRelay-1.6.0-RC1-ObserverPilot-0dc6d52c52c84cb09d9d97d35fa655db\package`
- Setup: `RC1 Pilot Setup.exe`; SHA-256 `E5CFDBF8C2D506FD6D58DA2BAB304FE6F999C0B35BD21A0CDB7D4CBAF0AD29C6`.
- Portable ZIP: `..\RDCRelay-1.6.0-RC1-Observer-Portable.zip`; SHA-256 `BCE83DCE757C3106B3013204118E98F52A64B2620C221502711ED505442C11A5`.
- Build `Scripts/build-rc1-observer-pilot.ps1 -Build` **exit0**; source marker stays noninstallable, isolated stage marker is private installable and nonpublishable; 19 pinned runtime items, manifest and Setup exactly verified, archive entry bytes independently hashed. Public/stable updater and `main`/`stable` untouched. Existing prior installed private RC1 and 1.5.18 are not changed by build.
- `Tests/Invoke-V16Rc1SafeRegression.ps1`: **21/21 suites PASS, exit0** (includes U1 negative fixture). `Tests/Invoke-Rc1OwnerOsSmoke.ps1 -Execute -Cycles 10`: **43 PASS/0 FAIL/0 NOT CHECKED, exit0**, 11 GUI Windows processes with ten real WM_CLOSE operations, Host retained, authenticated IPC, independent no-survivor proof, `OS_DISPOSABLE_CLEAN=TRUE`.
- A further attempt to run the G8 **staged** `Source/rc1-tray-host.ps1 -ObserveExisting -ObserveAutoExitSeconds 15` was explicitly rejected by the execution environment as a new live-Remote-observing Host/GUI tree without exact fresh approval. **NOT EXECUTED; no workaround attempted**. Consequently staged candidate actual read-only UI, clicks, X and tray, link opening, human DPI/a11y, and production-path Setup/U1 recovery are **NOT CHECKED**.

### Safe user-facing shell transition (OWNER GO required)

1. **Before any switch**, obtain the one independent REV-006A-G8 for U1, Host IPC navigation policy and this switch path, plus owner approval identifying the new observer-only Host/GUI executable and bounded OS test window. Independently recheck installed RC1 manifest, current Host PID/birth and **existing Remote identity**; verify default original shortcut, installed v1.5.18 and RC1 backup roots without modifying them.
2. Do **not** press X on the old 1.5.18 GUI to make room; its historical event handler can initiate Remote stop. **Leave it running/minimised** or use a separately independently verified harmless hide-only route. Do not use force-termination or replace the primary shortcut. For user testing, open the explicitly named separate **RDC Relay 1.6.0 RC1 (Pilot)** only after staged source is reviewed and installed through owner-confirmed U1 protocol.
3. After approved new staged OS smoke and any separately approved private U1 upgrade, verify exactly one *new private Host* identity, one GUI generation at a time, one unchanged actual Remote PID/birth, and no extra Remote spawn. Physically test X, tray reopen, status/journal, account web links, help, and visible denied actions with screenshots/user feedback. An Adopted Remote must remain read-only.
4. On failure, **only** close the verified RC1 Pilot GUI with X and terminate its own Host using its cooperative RC1 tray action; do not signal actual Remote or legacy GUI. Run manifest-pinned U1 recovery only after confirming no private Host/GUI is active, no file/reparse ambiguity and exact old/new SHA identities. Preserve old backup and failed candidate; if uncertain, freeze both and request manual review. Old 1.5.18 install/shortcut remains available without substitution.
5. Treat RC1 as a *parallel observer shell*, not a full replacement for actions that still need legacy-owned Remote. Full takeover, legacy shell retirement, true Remote lifecycle and stable 1.6.0 promotion need a separate ownership contract and owner authorization.

**G8 handoff:** product code + U1 negative/replay evidence ready for **one independent REV-006A-G8**, not a GO for live Remote mutation, automatic default-shell replacement, in-place RC1 upgrade, stable publication or PR merge.
