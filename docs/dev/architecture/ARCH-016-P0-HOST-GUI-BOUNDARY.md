# ARCH-016-P0 — technical host / GUI boundary proposal

Programmer feasibility report (not an approved architecture or Source refactor), 2026-10-23.

## Existing monolith dependencies examined

Source/remote-window.ps1 on development integrates all of the following in one Windows PowerShell 5.1 process and script scope:

| Current route | Responsibilities coupled today | Extraction constraint |
| --- | --- | --- |
| GUI mutex block (~307–373) | PowerShell GUI singleton, Win32 foreground, no-HWND age-based forced Stop-Process | Must NOT migrate destructive heuristic; durable Host singleton and GUI registration are distinct |
| UI object construction, rendering and WinForms handlers | RdcLogBox, header scroll, Form, accessibility/layout, state/animation, menu commands | GUI-only code; no Remote ownership or file readers |
| Find-ExistingRemote / Start-Remote (~5056,5163) | WMI launcher discovery, adoption of existing Remote, npx launcher, start timeout, synthetic/real runtime status | Host only, after separately reviewed PROG-005 ownership policy; no real adoption in P0 |
| Stop-Remote / Begin/Update/Complete-RemoteOperation (~5227–5387) | taskkill /PID /T /F, stop/restart/reconnect/logout/close state and deadlines | Host only after identity verification and separate permission; explicit full Exit remains PROG-006B |
| Open-Reader / Read-LiveLog (~4944,5048) | Log IO, startup/runtime parsing, history ring and UI rendering side effects | Host owns log read/cursor + observation state; GUI receives sanitized bounded snapshots/events |
| Get-RemoteLineClassification / Process-RemoteLine | Already-decoded marker classification, fault/activity/reconnect signals, compact-log effects | Pure classification stays shared or host-side; state mutations move to host; UI gets model not control |
| Refresh-Window (~5574–5693) and WinForms Timer tick | Poll process HasExited, auth/ready/fault, pending reconnect, updater tick, log read, format display | SPLIT: host monitor/watchdog timer and GUI presentation/interaction timer; GUI X cannot affect host |
| Start/Complete-RuntimeInitialization (~5422–5490), FormClosing/FormClosed (~5765–5789) | Startup/updater gating, global flags, X→Begin close→Stop Remote, reader/process disposal | Host starts independently; GUI can be closed/disposed without touching Remote handle; distinct controlled Exit/update paths |
| Application.Run($form) + updater/shortcut helpers | Form-owned message loop, updater check and relay lifecycle | Host ApplicationContext loop remains while zero GUI exists; GUI own independent Application.Run loop |

PROG-005A proved the existing X→remote-stop and no-window forced-kill behavior only under AST mocks. A one-process Hide/Show or Form re-creation does NOT prove fresh PowerShell source/C# type loading. P0 demonstrates why two real processes are a viable alternative but does NOT migrate these actual product functions.

## P0 executable ownership scheme

                           restricted local Named Pipe
   Persistent Tray Host  <-----------------------------> Disposable GUI
   - NotifyIcon/menu        STATE / OPEN / HELLO / BYE     - WinForms Form
   - ApplicationContext     protocol 1                     - build A/B source
   - fake session UUID                                     - local timer/view
   - fake heartbeat                                       - no process control
   - GUI-child reference                                  - closes on normal X
               |
               +-- mock state only: NO Desktop Commander Remote access

Tray Host starts once per test, keeps fake Remote session UUID and monitor counter. GUI is started with Windows PowerShell -STA -File using an absolute script path. After GUI Form.Close completes, the process terminates; editing the file and starting again loads a new script/runtime instance. A test records the **same Host PID and fake session UUID**, while GUI PID and source build change A→B. Windows messages for the actual icon/menu are installed, but automated tests invoke the shared Open function through a test-only route and suppress notification visibility.

## Minimum safe integration sequence after Architect decision

1. Specify a durable Host IPC identity and versioned snapshot contract. A transport-ready boolean is not process ownership; separate process alive, auth in progress, transport ready, last tool activity, latched fault and updated-at revision. Include bounded tail/events with sequence numbers and reconnection/resync after missed events.
2. Before moving any code, preserve Source behavioral regressions (PROG-003/003A/004 and PROG-005A) plus fresh isolated host/UI acceptance. Treat old X→Stop behavior as characterized danger, NOT a contract to preserve in new UI.
3. Introduce a new development-only Host runner with explicit mutex and a same-user/same-session IPC handshake; remove any stale no-window forced kill from the *new* entrypoint. Fail closed when another host exists: never kill based on HWND absence. Do not change the production launcher before Reviewer safety gate.
4. Move only logically independent supervisor responsibilities into Host: monitoring heartbeat/log reader/event ingestion and state snapshot; process ownership Start/Stop/Restart must remain BLOCKED until PROG-005B + PROG-005 safety evidence and owner policy. During staged extraction, use mocked process dependencies.
5. Create replaceable GUI entrypoint: rendering/layout/accessibility/event handlers only; X closes GUI process; new launch always opens current version of UI script. Use host state snapshot for initial paint; no second runtime initializers, log file handles, updater polling or Remote launcher in GUI.
6. Host owns updater flow and GUI version selection after explicit compatibility verification; preserve code 42 controlled-update behavior and no duplicate timer/Remote launch. Version mismatch/failure must not terminate Host or Remote.
7. Add negative tests: broken/slow IPC, same-user unrelated process, cross-session access, duplicate host + GUI, startup and process-exit races, rapid open/close ≥10 times, Explorer restart, GUI crash, shutdown/logoff and separate controlled full Exit. Tests requiring actual Remote/process tree/force termination demand separate authority; no production launch before gates.
8. Run independent Reviewer and Architect acceptance, real interactive WinForms/icon accessibility and DPI tests in an approved isolated UI environment; package allowlist and installed artifact gate. Then separately approve actual integration into Source/product, only after full safe Exit lifecycle is designed.

## IPC P0 reviewed safety vs unmet production requirements

**Present:** local-only "." named pipe, protected PipeSecurity DACL for current SID, random unguessable test-run pipe identifier, fixed request verbs, GUI PID check against child created by host, protocol-number gating, no arbitrary tool/shell execution, no user Remote identity/credentials/real log exposure.

**Still missing for production:** per-user/per-session app rendezvous; authenticating same Windows Session ID and creation-time process identity; bounded asynchronous pipe read (current P0 synchronous ReadLine on WinForms timer can be stalled by a same-user client); frame limits before allocation; robust cancellation/timeouts/disconnect; sequence/generation and reply correlation; explicit request authorization per command, replay protection and nonce rotation; integrity/signed update process and version rollback; real tray Explorer restart; UI interactivity tests; real owned/adopted process shutdown. No P0 test claims these are implemented.

## Gates

- **P0 only** permits disposable Windows PowerShell Tray Host and GUI processes with a fake Remote. A test-only END_TEST_HOST stops only the process started by the fixture after the GUI closes; not a user-facing full Exit.
- **PROG-006A remains separately authorized work**, dependent on Architect acceptance of boundary and Reviewer findings. P0 is not permission to edit existing Source or installed RDC Relay.
- **PROG-006B / PROG-005B / PROG-005 remain blocked.** Never wire full Exit to old taskkill, never stop the user's live Desktop Commander Remote.
- User-visible design and real interactive tray/GUI are NOT CHECKED; no release, no main/stable, no updater/installation changes.
