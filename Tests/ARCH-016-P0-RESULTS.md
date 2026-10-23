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

## ARCH-016-P0A — bounded fixture cleanup and runner validation (2026-10-23)

P0A modifies **only prototype test utilities and evidence** in the same draft PR #15. No changes to `Source/`, shipped launcher, installed RDC Relay or live Remote. Target remains STARMER Windows PowerShell **5.1.26100.9711**.

- `Tests/Test-Arch016P0Lifecycle.ps1` now requires **at least 15 executed test cases** (`$expectedMinimumCases=15`). The final exit code is nonzero for *any failed assertion*, early harness exception, incomplete case count, failed host cleanup, remaining fixture process, unverifiable ownership or unreleased IPC.
- Failure-path cleanup validates the **specific child Host handle returned by the test's `Start-Process`** against PID, creation-time and read-only `Win32_Process` command line (unique disposable `TrayHost.ps1`, `Gui.ps1`, `-PipeName` and `-TestMode`). Only the verified fixture Host receives its existing cooperative `CLOSE_GUI` and `END_TEST_HOST` test commands. **No `Stop-Process`, `taskkill`, forced termination or operations on unrelated processes.**
- The host is given **7000 ms** to exit after a bounded cooperative request; GUI close is polled for **4500 ms**. An independent read-only WMI scan waits up to **3500 ms** for all processes executing the **unique test TEMP scripts** to disappear, including GUI children if Host crashed. Exit without residuals is recorded as `CLEANUP_REMAINING_PROCESS_COUNT=0`; any remaining PID and parent PID is reported. The test additionally probes local Named Pipe connection availability without waiting for a response and checks that the Host has exited. Unverifiable ownership/cleanup → FAIL, **retain diagnostics**, escalate; never kill.
- Prototype client in `Ipc.ps1` now also applies a deadline to `ReadLineAsync().Wait(TimeoutMs)`, so a missing response cannot block the harness indefinitely. **Server-side synchronous unbounded `ReadLine`, post-read frame-size guard and weak production IPC identity remain unchanged and unsafe for product use**; this is **not** an IPC security fix.

### Reproduced controls on STARMER

| Route | Measured outcome | Status |
| --- | --- | --- |
| Full positive lifecycle | **15 PASS, 0 FAIL, exit 0**; `CLEANUP_HOST_IDENTITY=VERIFIED`, `CLEANUP_REMAINING_PROCESS_COUNT=0`, `CLEANUP_PIPE_RELEASED=PASS`, `CLEANUP_RESULT=PASS` | PASS |
| Disposable runner copy with one skipped check | **14 PASS, 1 FAIL, process exit 1**; explicit `FAIL: coverage minimum 15 but only 14 cases executed`; host/pipe/children cleaned | PASS (negative control) |
| Disposable runner copy with injected failing assertion **while GUI A is running** | Expected runner FAIL/exit 1, cooperative GUI close requested for its owned PID, host/pipe/children cleaned | PASS (negative control, independently rerunnable) |
| `Test-Arch016P0ANegative.ps1` control harness | Validates both nonzero exit codes, exact runner failure signatures and zero fixture-owned processes/pipe before deleting **only its own** temporary negative scripts and evidence folders | PASS |
| Old negative-harness implementation flaw (diagnostic history) | Initial negative runner used PowerShell 5.1 `Start-Process -RedirectStandardOutput -PassThru`, which returned a blank `ExitCode` despite the subprocess printing FAIL; changed **test driver only** to .NET `Diagnostics.Process`, async stdout/stderr draining and `WaitForExit(65000)`. The unsuccessful early run's uniquely tagged artifacts were independently checked for no live process and removed by exact path. | Fixed in test driver |

To repeat:

    powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File Tests/Test-Arch016P0Lifecycle.ps1
    powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File Tests/Test-Arch016P0ANegative.ps1

**NOT CHECKED / still blocked:** active user Remote or production process cleanup, real cross-session or remote named pipe misuse, malicious client hanging server-side `ReadLine`, real Explorer icon / user X, installed GUI, release and actual production ownership semantics. The prototype never force-stops even a verified test-owned PID if graceful exit fails. This is a **deliberate explicit FAIL/escalation boundary**, not silent cleanup. Await **REV-016-P0A** and an Architect merge decision; PR #15 stays draft.
