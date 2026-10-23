# PROG-005A — existing process / window lifecycle characterization (mock-only)

**2026-10-23 · Stage B1 · Programmer evidence for REV-005A**

- **Branch:** `tests/prog-005a-process-tray-lifecycle-baseline`, directly from `development@324a5bb499c0a01dc35de3dbb5e95c87bc648c58` (confirmed merge-base).
- **Implementation changes:** two **new tests only**. `Source/` and runtime behavior are untouched.
- **Source examined:** `Source/remote-window.ps1` SHA-256 `641EDFDD46AC89B8ED9BB3FE79E2ABFC24BE2178AAC63EE4AB89C93075EE631F`. Project policies: `docs/dev/architecture/PROG-005-PROCESS-OWNERSHIP-PLAN.md`, `TRAY-LIFECYCLE-DESIGN.md`.
- **Runner:** Windows PowerShell **5.1.26100.9711**, STARMER, isolated worktree `E:\Projects\GitSync\RDC\RDC-Relay PROG-005A`.

## Test execution (actual)

| Test | Observed | Status |
| --- | --- | --- |
| `Tests/Test-ProcessOwnershipCharacterization.ps1` | **27 PASS, 0 FAIL, exit 0** | PASS |
| `Tests/Test-WindowLifecycleCharacterization.ps1` | **21 PASS, 0 FAIL, exit 0** | PASS |
| Deliberately failing assertion inserted into a disposable copy of **each** new script | Each: one deliberate FAIL, **exit 1** | PASS (negative control) |
| `Tests/Test-RemoteCharacterization.ps1` | **46 PASS, 0 FAIL, exit 0** | PASS |
| `Tests/Test-RemoteLineClassifier.ps1` | **32 PASS, 0 FAIL, exit 0** | PASS |
| `Tests/Test-RemoteClassifierParity.ps1` | **PASS, exit 0**; normalized before/after SHA-256 `49F346B69241EA36CE7CC1AA71180E550F36C2A7F403211658C9035730CB1D5F` | PASS |
| Existing `Tests/Test-UiLifecycle.ps1` | PASS, exit 0 | PASS |
| Existing `Tests/Test-NpxRecovery.ps1` | PASS, exit 0; 7 synthetic scenarios | PASS |
| `git diff --check`, worktree state | Exit 0, clean; temp negative-test copies **0** left | PASS |

Run the two new suites without invoking the app, a real process/WMI query or any real taskkill:

```powershell
$root = 'E:\Projects\GitSync\RDC\RDC-Relay PROG-005A'
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$root\Tests\Test-ProcessOwnershipCharacterization.ps1"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$root\Tests\Test-WindowLifecycleCharacterization.ps1"
```

**Isolation details:** The tests parse production source into a PowerShell AST and load only selected definitions / WinForms registration-scriptblock contents. `Get-CimInstance`, `Get-Process`, `Start-NoWindowCmd`, `Stop-Process`, `Get-Date`, `Start-Sleep`, shell activation and resource management are controlled **in-memory** fakes. The original singleton AST branch is executed without creating a mutex: two `exit 0` sites become test-only sentinel exceptions, `$PSScriptRoot` resolves to fixture source root, and the top-level `$ownsWindow` variable is bound to fixture script scope. The simulated `RdcShellIdentity` has no Win32 P/Invoke and only increments counters. `taskkill` and `remote --logout` occur **only as captured command-line strings**, never spawned. No actual Remote, Windows process tree, process enumeration, user logs or GUI window was used. The disposable negative copies were deleted in `finally`.

## Actual old contract vs safety gap vs future policy (not implemented)

| Source route / scenario | Existing behavior established under mocks | Risk | Proposed change / decision gate |
| --- | --- | --- | --- |
| `Find-ExistingRemote` match | First matching `cmd.exe` containing case-insensitive `desktop-commander`, substring ` remote`, and current `logPath`. Two matches → **first wins**; WMI failure, disappeared PID → `$null`. | Ambiguous identity; substring `remotely` **also matches** and may be adopted if PID resolves. | Distinguish Owned / Adopted / Unknown and robust identity proof; PROG-005 **blocked**. |
| `Find-ExistingRemote` time | `StartTime` / creation time mismatch is ignored in discovery; no PID-reuse check. | Stale/reused identity can lead to wrong handle. | Require evidence and verification before destructive action; separate PROG-005 decision. |
| `Start-Remote` | Existing match adopted without new launch or ownership metadata. If WMI fails, creates a **new** hidden `cmd → npx … remote` launcher; if handle already alive, returns without query. | Can create duplicate Remote after discovery failure; owned and adopted indistinguishable later. | Fail-closed identity/ownership contract requires Architect/owner GO. |
| `Stop-Remote` | For **any** live `$script:proc`, including adopted, issues fake-captured `taskkill.exe /PID <PID> /T /F`; ignores creation-time mismatch and active tool count. | Could force-stop unrelated/adopted tree or active MCP tool; *not* proof it happens on a real system. | No-kill by default for Unknown/Adopted proposed, policy still **needs owner decision**. |
| Async stop/restart | Operation guards duplicates, waits for fake child/Remote exit; stop failure and stop timeout yield `operation-failed`, no immediate restart. | Real deadline/taskkill races and PID reuse untested. | Separate disposable Windows process-tree tests need new permission (PROG-005B). |
| Logout | After successful fake stop, constructs `remote --logout` command (fake-only); closeRequested prevents logout step. | Real logout deletes local credentials; must never be run in mock tests. | Explicit credential policy before PROG-005; real route NOT CHECKED. |
| Current normal X | Active Remote → `FormClosing.Cancel=true`, `closeRequested=true`, `Begin-RemoteOperation 'close'` → old stop path before actual Form closes. Does **not** Hide form. | Conflicts with owner-approved **future** X→tray keep-Remote-alive behavior. | PROG-006 **blocked** until REV-005A and separate narrow UI/Exit scope; do **not** change X in PROG-005A. |
| X during initializing/operation | Sets deferred close flag; a second X does not initiate a second operation. `allowClose`, `SelfTest`, `Preview` bypass interception. | Hidden Form is not a real tested mode; controlled shutdown/update reason handling is not characterized end-to-end. | Explicit Exit/updater/shutdown policy + future isolated UI acceptance. |
| `FormClosed` | Stops timer, disposes reader and process handle, optional shortcut timer/update notice. | Disposal of process handle does not prove child Remote has ended; actual message pump NOT CHECKED. | Preserve state if future X only hides; implement/verify only in PROG-006. |
| Duplicate GUI mutex | A visible matching GUI peer is foregrounded. A matching **no-window** PowerShell peer older than ~5 s is passed to fake `Stop-Process -Force` after ~1.5 s wait. Multiple peers can all receive kill requests; even if mutex cannot be reacquired, kill was already requested. | Deliberately hidden healthy tray supervisor may be **destroyed**; no HWND is not proof of hang. | Owner-approved direction: **non-destructive singleton fallback**, no kill on missing window; implement in PROG-006 after GO. |
| Duplicate GUI young/missing | Young hidden GUI is not killed, second launcher exits; vanished PID and no matching peers result in exit when mutex remains locked. | No IPC to open intentionally hidden Form; may appear unresponsive. | Separate secure same-user reactivation design/verification. |
| `Refresh-Window` alive but no HWND | `HasExited=false` is enough to render running/connecting, even when no visible HWND; readiness deadline expiry only clears deadline and **does not** set fault/kill. | Frozen-but-alive process and hidden healthy process are not distinguished; no robust heartbeat. | Process identity/liveness policy and independently verified future UI/monitoring tests. |
| `Refresh-Window` exited | One `process-exit` fault with retry flag for synthetic unexpected exit (when cache repair fakes return false); repeat refresh does not re-log. | Real OS process exit/restart/network not proven. | Keep NOT CHECKED until separate integration tests. |

## Scope boundaries / NOT CHECKED

- Real WMI `Win32_Process`, `Get-Process`, PID creation-time identity, OS mutex ownership and abandonment, real `user32` window activation, Windows session ACL, and lifetime of hidden Form/WinForms message pump: **NOT CHECKED**.
- Actual `cmd.exe`/`npx` process tree, Remote, in-flight tools, `taskkill`, `Stop-Process`, race between WMI and PID, no-window hang detection and credentials/logout: **NOT CHECKED**.
- Real tray `NotifyIcon`, X→Hide, tray click restore, explorer restart, multiple launches, updater exit code 42, Windows shutdown/logoff, Setup/Portable: **NOT CHECKED**; not implemented.
- The tests capture legacy behavior that may be **unsafe**. PASS is evidence of fake-route fidelity only, not approval to retain destructive behavior in future Source changes.
- **PROG-006, PROG-005B and PROG-005 remain blocked**; no implementation authorization inferred from this report.

**Reviewer handoff:** Independently inspect the two AST extraction methods, mock isolation, expected old dangerous behavior, 48 positive fixture cases, negative runner controls, and absence of `Source/` changes. Run suites in Windows PowerShell 5.1, assess risks and report REV-005A verdict to Architect before any PROG-006/PROG-005B or ownership refactor.
