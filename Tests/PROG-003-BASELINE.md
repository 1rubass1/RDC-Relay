# PROG-003 — Remote lifecycle characterization baseline

2026-10-23 · Branch `tests/prog-003-remote-lifecycle-baseline` from `development@5e728ef`.

## Method and execution

`Tests/Test-RemoteCharacterization.ps1` uses the PowerShell AST to load only named functions from `Source/remote-window.ps1`; substitutes all process starts/stops, WinForms controls, logs and rendering with in-memory fakes. No full app launch, Remote client attach, npm cache edit or network calls. Windows PowerShell 5.1 requires this test fixture encoded UTF-8 with BOM for Unicode marker literals.

Run on STARMER from the dedicated checkout:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'E:\Projects\GitSync\RDC\RDC-Relay PROG-003\Tests\Test-RemoteCharacterization.ps1'
```

Observed 2026-10-23: **12 PASS, 0 FAIL** (PowerShell 5.1 on STARMER; commit `1bb1697`). The initial UTF-8-without-BOM variant produced a parser FAIL and was corrected; final rerun passed. The script exits nonzero on assertion failures.

## Captured behavior (fixture PASS, not real-system proof)

| Route / scenario | Observed result |
| --- | --- |
| Cold ready + duplicate Presence | Ready set and single recovery flash |
| Channel error → subscription → Presence | Transport fault latched; subscription alone insufficient; Presence restores |
| Expired session + repeat marker | One queued retry, duplicate suppressed; exhaustion at third attempt |
| Tool failure → Presence → completed tool | Failure remains latched across Presence, success clears |
| Tool-envelope and JSON marker-like strings | Not treated as transport fault |
| Manual stop guard | No new fault or scheduled reconnect |
| Split log chunk and bounded events | Incomplete line deferred; max six completed events; active count nonnegative |
| ANSI and carriage returns, large UI event | Sanitized line and bounded UI text |
| Silent in-progress tool >60 s | Activity retires without fault |
| Asynchronous manual stop | Pending operation retained, controls disabled, neutral finish |
| Failed stop action | No restart; operation failure latched |
| SelfTest reconnect due | No process action or attempt increment |

## Existing contracts discovered in source

- Remote readiness is separate from process-alive; `Desktop Commander Remote is connected` and Presence can mark readiness; a completed tool call can validate adopted-session reachability.
- Local executor, transport, session, startup, tool and process failures use distinct fault kinds. Tool failure stays latched despite presence; a successful tool completion clears it.
- Auto-reconnect delays are `2/5/10 s`. Intentional stop suppresses fault changes. `stop`, `restart`, `logout`, `reconnect`, and `close` use an asynchronous operation state with a 10-second stop deadline; logout has a 30-second deadline then asynchronous termination.
- Log classification uses `🔧 Received tool call`, `✅ Tool call … completed:`, `❌ Tool call … failed:`. Event preview is limited to six entries and 8000 characters each. The reader initializes from a bounded tail and can skip backlog. Long tool silence (60 s) retires *activity*, not connection health.
- `Find-ExistingRemote` selects a `cmd.exe` launcher whose command line includes `desktop-commander remote` **and this instance's log path**; existing process is adopted without starting another. `Stop-Remote` uses `taskkill /PID … /T /F` on the current process handle. This ownership boundary is inferred from source, **not** verified against real processes.

## NOT CHECKED / decision risks

1. Live-owned, adopted, external and child-process identity/termination race paths: require explicit approval and an isolated disposable Remote/process tree; **never test on owner's running Remote**.
2. Actual realtime Presence publication, channel loss/recovery, duplicate markers and late/out-of-order tool completions: source fixture cannot prove remote-event delivery or true upstream semantics.
3. Complete WinForms start/close/update UI event routing, observed rendering, native process failure, and setup/portable packages: test does not launch distributed app.
4. Real logfile sharing/rotation/large-log catch-up and encoding boundary at split UTF-8 bytes: fixture tests in-memory line parsing only. Reader catches IO exceptions silently; assess separately with bounded synthetic files.
5. Stale taskkill PID or adopted process ownership contract is not strong enough to prove noninterference; this is a **risk**, not a refactor request. Seek Architect contract decision before PROG-005.
6. Auto reconnect under real CLI boot/auth failures and physical network faults, including retries under concurrent events, remains unverified.
7. `Process-RemoteLine` counts tool start/end markers, not tool IDs; extra/late completions and overlapping calls may alter inference. Current tests preserve that existing counter contract, not correctness of every interleaving.

**Source changes:** none. `main`, `stable`, installed RDC Relay, live Remote, Codex settings, network and existing production logs untouched. Results apply to isolated AST-loaded functions only; independent Reviewer still needed before refactor/release.

## PROG-003A — REV-002 edge-case expansion (2026-10-23)

**Branch:** `tests/prog-003a-characterization-edge-cases` (forked from `tests/prog-003-remote-lifecycle-baseline`; no merge to production branches). **No `Source/` changes.**

The **original 12 `Case` scenarios remain**. Added **21** targeted scenarios in the same AST-isolated test file. The final runner asserts `$expectedMinimumCases=33`: deleting cases below that count fails even when every remaining assertion passes. These are characterization expectations of existing implementation, **not intended or approved behavior**. Run from the new isolated worktree:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'E:\Projects\GitSync\RDC\RDC-Relay PROG-003A\Tests\Test-RemoteCharacterization.ps1'
```

**Verified on STARMER, Windows PowerShell 5.1.26100.9711:**

| Check | Observed | Status |
| --- | --- | --- |
| Baseline scenarios preserved | 12 existing case names and bodies retained | PASS |
| New scenarios | 21 added to same AST-fixture test runner | PASS |
| Full current characterization | `TOTAL: PASS=33 FAIL=0`, process exit **0** | PASS |
| Synthetic failing assertion, disposable copy beside original | `FAIL: intentional runner probe : deliberate synthetic failure`, `TOTAL: PASS=33 FAIL=1`, process exit **1** | PASS (negative control) |
| Synthetic guard violation, disposable copy with expected minimum changed from 33 to 34 | `FAIL: only 33 cases; minimum 34`, exit **1** | PASS (negative control) |
| Worktree and source boundary | Only fixture changed before doc updates; `git diff --check` clean; `Source/remote-window.ps1` SHA-256 `7D0BC5531A51514F12248EEB70C2D3FC5072772C48414BB45A42730A0BD6D19C` | PASS (static) |

Negative checks used **separate disposable copies** in the PROG-003A `Tests/` directory, with UTF-8 BOM retained for PowerShell 5.1, and removed their temporary files in `finally`. The first expanded run recorded 32 PASS / 1 FAIL because the new fixture incorrectly expected a trailing newline in completed-event previews; corrected the **test assertion only** to match the original `Limit-UiEvent().TrimEnd()` behavior. The final rerun was 33 PASS / 0 FAIL.

### New behavior captured (all fixture PASS)

| Reviewer requirement | Actual current observation |
| --- | --- |
| Duplicate start, duplicate success, orphan success | Each start increments **one global counter**, each completion decrements to zero minimum; a completion **without any start** marks Remote ready and triggers a recovery flash. Duplicated completions do not flash repeatedly while already ready. |
| Overlapping, mismatched ID, failure after success | IDs are **not correlated**. The last completion may clear an earlier unrelated tool fault; a late failure after success re-latches red. Duplicate failure consumes another in-flight count while suppressing duplicate identical fault logs. |
| Exact/near markers | Only exact leading, case-sensitive Unicode `🔧 `/`✅ `/`❌ ` plus expected marker text alter the activity counter. Embedded, misspaced and missing-colon variants do not. |
| Serialized vs non-JSON tool payload | Lines whose trimmed prefix is `{` or `[` are excluded from health inspection; **non-JSON** tool output containing `Channel error:` causes an apparent transport fault and embedded Presence can clear it. Bracket-prefixed non-JSON text is suppressed too. |
| Conflicting health messages | On a **single line**, Presence readiness dominates Channel error regardless of substring order. On **separate lines**, whichever signal occurs last determines ready vs transport fault. Session expiry schedules a retry, subsequently canceled by ready; the reverse order stays failed. Local executor restart only clears a matching `local-mcp` fault. |
| Unicode, line/chunk delivery | Synthetic UTF-8 encode/decode roundtrip followed by *decoded string* delivery, including a surrogate-pair split in memory and CRLF, preserves Unicode marker recognition and event order. **Not** a test of actual `Open-Reader` byte decoding. |
| CRLF split between calls | A trailing standalone CR is normalized early to CRLF; delivery of its LF in the next chunk adds an **extra blank line** to the current event (existing quirk). |
| Startup/live switch | Commands footer freezes startup text; a marker can end startup before the footer. Marker-free channel loss/recovery appears in a completed activity episode. Startup probe also treats embedded `Received tool call ` text as a boundary. |
| Ordering, bounded history, overflow | Completed-event ring retains the **latest six events in order**; header limited to 30,000 characters; visible events to 8,000. Near-full incremental appends can temporarily exceed 8,000 **internally** before `Commit-CurrentEvent` clamps preview (existing quirk). |

**Scope / NOT CHECKED:** none of these calls use the real Remote process or event delivery. `Open-Reader` file sharing, UTF-8 byte splits, rotation/tail; real WinForms rendering/timer routes; process ownership/PID/`taskkill`; process-level concurrency/network/auth retries; installed Setup/Portable/updater and releases remain **NOT CHECKED**. Only **already-decoded complete-line classification** may be evaluated by Architect after independent REV-003; no permission for PROG-004/PROG-005 is implied.

**Review handoff:** Reviewer REV-003 should verify assertions against `Source/remote-window.ps1`, repeat the 33-case suite and both negative probes, assess whether the observed anomalies are faithfully captured, and report independent GO/NO-GO to Architect. Do not modify source or treat fixture PASS as integration proof.
