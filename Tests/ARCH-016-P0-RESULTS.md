# ARCH-016-P0 — replaceable GUI / persistent fake Tray Host

Programmer P0 technical prototype · 2026-10-23 · B1 · STARMER.

## Boundary and files

Tests/Prototypes/ARCH-016-P0 is entirely isolated from shipped RDC Relay.

- TrayHost.ps1: long-lived prototype-only STA PowerShell process, WinForms ApplicationContext, NotifyIcon and Open menu; fake Remote identity generated once on host startup, fake monitor heartbeat every 75 ms. Never queries, starts, stops or reads the real Remote; no npx, taskkill or TCP listener.
- Gui.ps1: a separate short-lived STA PowerShell WinForms Form. Form.Close destroys this GUI process, not its parent tray host. No actual Remote handles in GUI.
- Ipc.ps1: local Windows Named Pipe helper. A fresh random 128-bit run name must match rdcrelay-arch016p0-<32 lowercase hex chars>. Server explicitly grants FullControl to the current Windows user SID via PipeSecurity protected DACL, not Everyone/Anonymous. All clients connect to "." (local computer).
- Tests/Test-Arch016P0Lifecycle.ps1: copies only these scripts into a uniquely named temporary folder, starts only these prototype processes, tests IPC and new GUI code on disk. Calls test-only END_TEST_HOST only after GUI closed, never Stop-Process/taskkill. Removes its own temp copy after clean shutdown; on failure retains temp-only fake diagnostics.

## P0 IPC and process contract

Finite commands: STATE, OPEN, HELLO|PID|build|1, BYE|PID. Commands TRAY_DOUBLE_CLICK, CLOSE_GUI, DROP_NEXT_STATE, END_TEST_HOST work only in TestMode. HELLO verifies that the connecting PID equals the child launched by this test host and the protocol version equals 1. Duplicate GUI handshake is rejected; OPEN while GUI alive reuses the existing instance. No generic execution command or real Remote actions. STATE returns only a fake session UUID, monitor tick and test process counters.

NotifyIcon.Add_DoubleClick and Open context-menu item both call Open-ProbeGui. TestMode constructs NotifyIcon but leaves it invisible to avoid user desktop changes; the test-only TRAY_DOUBLE_CLICK dispatches that same function. For a supervised manual demonstration, -TestMode -DisplayTray shows a real disposable icon; END_TEST_HOST is strictly a test teardown facility, NOT full product Exit/PROG-006B.

## Actual execution

Machine: STARMER, Windows PowerShell 5.1.26100.9711. Command:

    powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File Tests\Test-Arch016P0Lifecycle.ps1

| Test route | Evidence | Result |
| --- | --- | --- |
| Host startup and fake kernel | Stable host PID + random fake session ID, heartbeat rises without GUI | PASS |
| Tray-event path opens GUI A | New actual STA WinForms GUI child, build A handshake | PASS |
| Repeated OPEN and second tray event | GUI launch count stays 1 | PASS |
| Competing direct GUI | Handshake rejected, disposable duplicate exits 5 | PASS |
| Temporary IPC response loss | GUI and monitor survive dropped STATE reply | PASS |
| X-equivalent Form.Close | GUI A exits, host and fake kernel stay alive | PASS |
| Source A → B rewrite | Test overwrites a TEMP copy of GUI PROGRAM SOURCE; reopened new child reports build B; host PID/session stay identical | PASS |
| Invalid GUI code | Test-only launch fails without stopping host | PASS |
| Repair and relaunch | Corrected B GUI reconnects to original host | PASS |
| 10 open/close sessions | Ten separate successful GUI children, never two simultaneously, kernel heartbeat continuous | PASS |
| IPC protocol version mismatch | GUI changes protocol 1 → 2, handshake rejected | PASS |
| Absent host | GUI exits 5, no substitute supervisor or Remote starts | PASS |
| Cleanup | All test GUI children close, fake host exits through test-only IPC and named pipe disappears | PASS |

Automated result: **15 PASS, 0 FAIL, exit 0**. GUI source build B SHA-256 and prototype-only host PID/session ID recorded in the runtime output. Test logs are disposable and not committed.

## Risks / NOT CHECKED

- Real GUI mouse X click: the automated test calls the same WinForms Form.Close path, not a physical click.
- Real notification-area rendering/double click/Explorer restart: only a synthetic dispatch to the same registered Open function was exercised.
- Same-user ACL is present; same-Windows-session identity is NOT independently authenticated. Pipe frame-size guard applies only AFTER synchronous ReadLine on UI timer: a stalled or malicious same-user client may block the host message loop. Need asynchronous bounded-frame worker, deadlines and session/instance authentication for production.
- Windows update/relaunch, controlled shutdown, installed RDC Relay, actual Remote, live logs/connection, PID ownership/children and real process termination are NOT CHECKED. Fake Remote ID is a UUID sentinel, NOT a Remote PID.
- Host instance uniqueness holds only per test-specific pipe name; installed-app rendezvous, single-host mutex, protected same-user launch handshake and recovery design are separate.
- No physical UI visibility, accessibility or DPI acceptance in headless automation; test mode leaves icon hidden.

This is **technical feasibility**, not authorization for PROG-006A integration or release. The separate PROG-006B full Exit and PROG-005 process-ownership scopes remain BLOCKED. Reviewer and Architect must evaluate the limits above.
