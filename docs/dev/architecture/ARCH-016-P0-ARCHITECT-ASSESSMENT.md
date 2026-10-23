# ARCH-016-P0 — Architect feasibility assessment and Reviewer gate

**2026-10-23 · Architect · Stage B1 · PR #15 · PRELIMINARY, awaiting REV-016-P0.**

## Decision at this checkpoint

**Architecture choice: CONDITIONAL TECHNICAL GO for further design** of a **durable WinForms Tray Host process + independently replaceable GUI process**. The alternative of hiding and showing an old `Form` inside the existing PowerShell process does **not** meet the owner's central requirement to load modified GUI source while Remote remains live.

**Implementation decision: NO-GO for PROG-006A, PROG-006B, PROG-005B, PROG-005** until a separate independent Reviewer report and Architect decision. In particular, **do not attach the P0 host to the real Desktop Commander Remote**. This evaluation concerns a disposable synthetic Remote UUID/heartbeat, NOT proof of continued real Remote service.

The P0 architecture demonstrates *feasibility*, not a production-quality secure IPC implementation. Preserve [PR #15](https://github.com/1rubass1/RDC-Relay/pull/15) in draft until Reviewer gate; do not merge or release on this assessment alone.

## Evidence independently checked by Architect

- Statically inspected `Tests/Prototypes/ARCH-016-P0/TrayHost.ps1`, `Gui.ps1`, `Ipc.ps1`, the actual `Tests/Test-Arch016P0Lifecycle.ps1`, PR #15 diff, and [Programmer results](../../../Tests/ARCH-016-P0-RESULTS.md).
- **Fresh direct execution on STARMER**, Windows PowerShell 5.1, worktree `E:\Projects\GitSync\RDC\RDC-Relay ARCH-016-P0` at `4edcc7439ca86daede16c0c6213c0e0d0ad93771`: `Test-Arch016P0Lifecycle.ps1` **15 PASS / 0 FAIL / exit 0**. Branch worktree clean afterward. Temporary fixture source changed A→B, while fake Host PID and fake Remote UUID stayed the same. Test-mode GUI/tray are not visually shown to the user.
- GitHub PR comparison against `development` changes **8 paths**: two development coordination docs, two test/evidence documents and four prototype/test scripts; **`Source/` unchanged**. No tests against user Remote or installed app.
- Existing PROG-003/003A/004/005A regression PASS is **Programmer-reported** at this checkpoint, not separately repeated by Architect in this assessment. Intentional negative-exit guard for the new P0 runner is not independently shown.

## Security and correctness risks — MUST resolve before real product IPC

| Priority | P0 observation | Production requirement |
| --- | --- | --- |
| **P0 BLOCKER** | `TrayHost.ps1` calls blocking `$reader.ReadLine()` in a **75 ms WinForms Timer tick**, and checks request size only **after** receiving the entire line. A connected client can withhold newline/data or send an unbounded prefix, freezing host message loop, heartbeat and tray. | Read in **non-UI worker** using strictly bounded **byte-framed protocol**, hard max size before decode/allocate, per-stage read/write deadlines, cancellation and broken-client cleanup. GUI also synchronously `ReadLine`s on its timer: no freeze of user UI if host stalls. Prove bounded recovery with disposable adversarial clients. |
| **P0 BLOCKER** | `PipeSecurity` DACL grants current user **SID**; this by itself does not prove same interactive logon session or forbid remote pipe clients. `NamedPipeClientStream('.')` restricts the provided test client, **not the host's listener**. | Authenticate same logon session using **logon SID**/session-specific policy; explicitly **deny NETWORK** access (or a verified reject-remote mechanism); verify current Windows user and session on actual accepted connection. Keep an unauthenticated client from invoking sensitive actions. |
| **P0 BLOCKER** | `HELLO|PID|build|1` is validated against a PID in the **client-supplied message**, not verified OS pipe-client process identity; other same-SID clients can spoof it. No GUI verification of connected server. | Use Windows-reported pipe-client PID/session (e.g. `GetNamedPipeClientProcessId` / session ID as platform permits) with creation time and an unpredictable per-launch challenge tied to host generation, and GUI-side server verification. Do not trust arbitrary PID/version strings, pipe names or command-line arguments as credentials. |
| **HIGH** | `STATE`/`OPEN` and `TestMode` control verbs are not per-command authenticated. Anyone who connects under the allowed SID and knows the random pipe name could query state, spawn GUI, or request `END_TEST_HOST` in prototype test mode. | Separate **test-only IPC** irreversibly from product commands; explicit authorization for each verb and failure-safe defaults. No product remote `Stop`/`Restart`/`Logout` through P0 methods. Expose only bounded/sanitized read-only snapshots until approved operation ACL/UX. |
| **HIGH** | A new random pipe name per run solves P0 fixture isolation but not installed single-host uniqueness, updater/shortcut discovery, restart recovery, host replacement or stale IPC identity. | Persistent per-user/session rendezvous + independently verified host identity, single-host mutex/lock, deterministic secure client discovery, no-old-GUI-kill fallback and zero duplicate Remote starts. |
| **HIGH** | Fake state contains stable UUID and counter, not real reader cursor, Remote child handles, event ordering, parser/fault state or auth. | Versioned bounded snapshot with `hostId`, `hostGeneration`, monotonically increasing `revision`/`eventSeq`, independent `processAlive`, `transportReady`, `auth`, `fault`, `toolActivity`, bounded/redacted log tail and resync after gaps. Backpressure/rate limits; GUI is presentation, not owner of the live Remote. |
| **GATE** | GUI A→B refresh, 10 process sessions, mock heartbeat and a synthetic tray dispatch passed. No physical click, Explorer taskbar restart, DPI/a11y, update exit 42, installed launcher or real process-tree retention test. | Independent GUI/host acceptance and release-boundary checks in a separate authorized sandbox; explicit NOT CHECKED for real Remote and `main`/`stable` until independent real-system approval. |

**Sources for IPC risk contract (Microsoft Learn):**
- [Named pipe access/security](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights) (logon SID for session isolation, access-control details).
- [Named pipes overview](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipes) (can also be remotely accessible unless explicitly restricted).
- [GetNamedPipeClientProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid) (actual OS client identity).
- [NamedPipeServerStream](https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.namedpipeserverstream) (async APIs).

## Minimum migration / responsibility boundaries (future plans, NOT approved code)

1. **Retain existing shipped `Source/remote-window.ps1` and legacy characterization as an oracle.** Keep all 48 PROG-005A, 46 PROG-004 and 32 pure classifier fixtures. Never silently change old stop/adopt semantics as a side effect of tray work.
2. **Host shell first, with fake Remote only:** own `NotifyIcon`, `ApplicationContext`, host singleton/rendezvous, GUI process launch/exit, authenticated versioned IPC and state contract. `X` kills only GUI; GUI A→B source reload repeats successfully; host still alive with mock state. No old forced no-HWND `Stop-Process`.
3. **Presentation/view-model seam:** create a narrow host-owned snapshot/Event DTO and a GUI-only adapter preserving existing WinForms layout, `RdcLogBox`, visual feedback/animations and keyboard/accessibility. GUI does NOT run `Start-RuntimeInitialization`, `Start-Remote`, `Stop-Remote`, `Open-Reader`, `Read-LiveLog`, `Invoke-AutoReconnect` or update checks. Initial GUI render is from host snapshot; reconnect uses sequence/generation guard.
4. **Move observation and supervision to Host in separately reviewed increments:** already-pure `Get-RemoteLineClassification`, state/fault/counters, log reader byte ownership/cursor, monitoring and reconnect scheduling; sever present circular UI side-effect calls (`Set-State`, `Add-Log`, `Render-CompactLog`, `Set-RuntimeDisplay`) via explicit events/state mutation vs view rendering. Use fake OS dependencies throughout the split until real ownership approval.
5. **Remote start/adoption/stop ownership LAST:** `Find-ExistingRemote`, `Start-Remote`, `Stop-Remote`, `taskkill`, launcher hierarchy, `remote --logout` and real disconnect remain separate **PROG-005B → REV-005B → PROG-005** gated work. Initial real-host adoption or interaction is NOT authorized by P0. No real Remote PID kill or process experiments.
6. **Full tray Exit LAST (PROG-006B):** owner-approved semantics stop *verified managed* Remote+launcher+children, then Host/GUI/icon; no credentials deletion, no orphan session and no killing unknown processes. No fake working Exit exposed as completed feature. Respect controlled updater/relaunch, shutdown/logoff and rollback/release boundaries.

### Independent Reviewer: REV-016-P0

Review independent source/harness correctness and precise scope (no `Source/` modifications), reproduce 15 tests on STARMER without launching actual Remote, verify test-rig cleanup and working-tree invariants, assess 15-case runner negative FAIL nonzero, `PipeSecurity` actual current-user DACL, WinForms `ReadLine` hang and client identity spoofability, observe A→B reload/fake host PID continuity, and explicitly separate synthetic event from physical tray click. Report **PASS / CONDITIONAL PASS / FAIL**, blocking findings, whether P0 needs changes before draft PR merge, and future PROG-006A minimum gates. Do **not** implement PROG-006A or any actual shutdown. Submit findings to Architect. PROG-006A remains **BLOCKED** pending Reviewer and a separate Architect decision.
