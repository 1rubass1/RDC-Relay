# RDC Relay 1.6.0 RC1 — G5 controlled Windows OS Host/GUI smoke

**Date:** 2026-10-25 (Europe/Moscow) · **Task:** PROG-006A-INTEGRATION · **Branch:** `feature/v1.6-host-gui-owner-pilot` · **Draft PR:** #23.
**Verdict:** **PARTIAL PASS for narrowly scoped FAKE_ONLY product-source Windows Host/GUI/IPC trials**. Not a full OS-01…OS-24 acceptance, Remote lifecycle acceptance, installable RC1, or G1 pilot GO.

## Authorization and hard boundaries

Owner explicitly directed the Programmer to start tests on STARMER on 2026-10-25, after the independent Reviewer had recorded that no harness or GO existed. The direct owner instruction superseded the earlier scheduling/preflight pause **only for newly created disposable fake-only trial processes**. Reviewer has not independently audited G5 yet.

Harness `Tests/Invoke-Rc1OwnerOsSmoke.ps1 -Execute` creates a new private direct child of `%TEMP%\RDC-RC1-OS-<32hex>` and copies exactly 16 real `Source/` product files. Marker must contain `candidate=1.6.0 RC1`, `liveRemoteEnabled=false`, `installable=false`, `publishable=false`. It starts **one** bounded 35s fake-only Host and its own PowerShell GUI children, validates PID, UTC process birth, exact executable, parent and Windows session, verifies HWND PID, sends native WM_CLOSE only to the proven child, waits for its exit, waits for a distinct replacement GUI, and waits for Host's own IPC closeGeneration and cooperative exit. No forced stop. No real Remote, npx, login, logout, account, updater, setup, installed file or known historical P1/P2 TEMP directory is accessed for control.

The trial instrumentation is rejected without an existing exact-named private root and is unavailable without explicit `-FakeOnly`. Stable source routes remain unchanged. Trial Host and GUI state are confined to this newly created root. Tests fail closed on uncertain identity/reparse/survivor and leave their exact fixture for manual review; successful fixtures are deleted only after allowed-entry/hash/empty-state/sentinel checks.

## Defects discovered by actual OS trials and fixes

1. A GUI launched by Host's `ProcessStartInfo` lacked PowerShell execution-policy arguments. GUI exited before showing a window on this STARMER configuration. Added **process-scoped** `-ExecutionPolicy Bypass` to child arguments; no machine/user registry policy was modified.
2. A real GUI process then reached its initial authenticated `HELLO`, but the synchronous WinForms-thread call timed out with `CLIENT_WRITE`. The asynchronous `RdcOwnerWire` read/write/serve continuation inherited a UI synchronization context while the caller was blocking on `Task.Wait`. All I/O continuation awaits now use `ConfigureAwait(false)`, keeping protocol continuations off the GUI context. Compiled and exercised in actual Windows GUI/pipe exchanges.
3. The first attempted event-rehydration assertion closed GUI A too soon after its HWND appeared; one diagnostic run had **11 PASS / 1 FAIL / exit 1** because GUI A had not yet issued `GET_EVENTS`. Added a bounded 1800ms settling interval **before** the identity-revalidated WM_CLOSE. Latest run confirms both distinct GUI PIDs issue snapshot and event requests.
4. Trial-only async stderr capture exposes actual GUI startup errors without changing normal launch diagnostics. The F2 `CreateThen` path still cleans only its verifiably owned ticket after a deliberately injected first start exception; retry succeeds.

## Measured Windows process tests on STARMER

| Run | Explicit command arguments | Actual result |
| --- | --- | --- |
| G5 latest normal | `Invoke-Rc1OwnerOsSmoke.ps1 -Execute` | **9 PASS / 0 FAIL / exit 0**; Host PID **43744**, GUI A **53744**, GUI B **52720**, Windows session 8; exact parent/birth/HWND checks PASS. |
| G5 latest F2 negative | `Invoke-Rc1OwnerOsSmoke.ps1 -Execute -InjectStartFailure` | **12 PASS / 0 FAIL / exit 0**; Host PID **28568**, GUI A **2948**, GUI B **23556**, session 8. First Process.Start throws `IOException: RC1_TRIAL_INJECTED_GUI_START_FAILURE`; owned ticket revoked; GUI A and B subsequently launch. |
| Early diagnostic attempts | Same bounded fresh-root harness during code repair | **FAIL / exit 1** (missing window, rapid GUI exit, then `CLIENT_WRITE`). Real failures; not counted as accepted PASS. |
| G5 timed-close first attempt | F2 negative with immediate WM_CLOSE | **11 PASS / 1 FAIL / exit 1** due to unobserved GUI-A `GET_EVENTS`; no Remote touched. Fixed timing and repeated above. |
| Repeat full isolated regression | `Invoke-V16Rc1SafeRegression.ps1` | **17 PASS / 0 FAIL / exit 0**, each suite separately returns exit 0: 9 V16 F2/state/IPC/source/package/fake suites + 8 legacy AST/fake regressions. |
| .NET WinPS 5.1 product-source compilation | `Test-V16OwnerAddType.ps1` | **PASS / exit 0**. `Test-V16ProductHostGuiSource.ps1` **19 PASS / 0 FAIL / exit 0** within regression. |

In the two final G5 OS runs, both GUI generations completed authenticated Host snapshot and event-queue calls: `RC1_TRIAL_IPC_SNAPSHOT_GUI_COUNT=2 EVENT_GUI_COUNT=2`. OS-01 GUI A `WM_CLOSE` exited only its process; Host PID survived. OS-02 opened GUI B with a different OS identity under the same Host. Host later signalled GUI B to close via the existing IPC generation, and both exited cooperatively. Outside sentinel unchanged. Successful trial roots reported `OS_DISPOSABLE_CLEAN=TRUE`.

Five **known G5 failed-run fixture roots** were inspected as exact source-only 16-file directories with empty `owner-state`, verified against candidate marker and matching external sentinel, checked for reparse points and active command lines, then removed individually by `Remove-Rc1OsSmokeFixture.ps1 -Execute`: **5 verified / 5 cleaned / exit 0**. No recursive/broad removal and no forced process stop. The **three historically protected TEMP roots remain NOT CLEAN and untouched**.

## Remaining NOT CHECKED / BLOCKED

- Full physical tray-click UX, DPI/accessibility, crashed GUI recovery, version-skew/malformed/foreign or cross-logon IPC, PID-reuse spoofing, hostile reparse races, OS-03…OS-24 matrix and multi-cycle stress: **NOT CHECKED**. The tested auth snapshot/event path is real IPC; this is not a complete independent security/UX verdict.
- Real pinned Desktop Commander Remote **0.2.52** start/adoption/Owned-vs-Adopted-vs-Unknown handling, connection/reconnection, genuine file logs and full verified process-tree Exit: **NOT IMPLEMENTED / NOT CHECKED**. New Host still enforces **FAKE_ONLY** and never calls `taskkill /T /F`, unverified `Stop-Process`, or `remote --logout`.
- Genuine installable side-by-side `1.6.0 RC1` Setup/Portable transaction and rollback: **BLOCKED**. Candidate marker `installable=false`, compile-blocked Setup/Launcher, and known G4 manifest-vs-installer input mismatch remain. Installed v1.5.18, stable updater/feed, `main`, `stable` and real Remote were not modified.
- No RC1 installation, activation, publication or PR merge authorized or attempted. A separate gate/plan is required before touching the real Remote or installing RC1.

## Independent handoff

Review the exact G5 commit and `Tests/Invoke-Rc1OwnerOsSmoke.ps1` safety gates, `Source/RdcOwnerWire.cs` synchronization fix, trial-only state/identity cleanup and log evidence; then independently repeat safe static suites and, with owner-approved scope, selected isolated OS test cases. Keep **Draft PR #23**, no merge. Architect should determine the separate scope for remaining fake OS negative controls and real Remote/installer gates before any STARMER RC1 switch.
