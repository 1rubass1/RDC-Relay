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
