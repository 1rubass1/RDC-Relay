# PROG-006A-P1 — fake Host/GUI protected IPC, Windows PowerShell 5.1

**Programmer evidence, STARMER, 2026-10-23.** Branch `prototype/prog-006a-p1-secure-ipc-fake-host`, forked from `development@256532abc61df4666fadc26d418664d5b35fbb51`. Scope: **`Tests/Prototypes/ARCH-016-P1/` and test/documentation only**. No `Source/` modification, installed RDC Relay, Desktop Commander Remote, npx, network settings, `main`, `stable`, release or real Remote ownership.

## Implementation boundary

- `P1Wire.cs`: async 4-byte little-endian length-prefixed UTF-8 JSON frames. Maximum request **8192 bytes**, response **65536 bytes** enforced before payload allocation/decoding, zero/overflow rejected. Timeout for each frame operation (1–1.2 s), connects bounded; timeout disposes pipe. Two listener instances with SemaphoreSlim 2 and Task-based workers; **no synchronous pipe reads/waits in Host WinForms Timer**. GUI Timer only checks completed background IPC tasks.
- `P1Core.cs`: separate STA WinForms `ApplicationContext` and test-only `NotifyIcon`, host mutex, mock Remote UUID + increasing heartbeat, authoritative `revision`/`eventSeq` with 256-event ring, GUI process registry and validated creation-time/session. Normal GUI Form close ends GUI, not Host. GUI source A→B is edited **only in disposable TEMP**.
- Windows Named Pipe DACL uses actual Windows **TokenLogonSid** (`GetTokenInformation(TokenLogonSid)`, not the unrelated TokenStatistics token ID), explicitly denies NETWORK SID, and compares OS-observed pipe-client/server process ID and session (`GetNamedPipeClient/ServerProcessId`, `GetNamedPipeClient/ServerSessionId`) with tracked Windows `Process.StartTime`. GUI verifies the Host process PID/start time/session against a protected per-launch ticket. Host validates the actual spawned GUI PID/start time/session, **not any claimed client PID**. Random per-launch nonce is stored in logon-SID ACL-protected test files, never passed as CLI argument. Protocol version 1, host generation, GUID request ID and bounded fail-closed replay ledger (limit 8192, then `REKEY_REQUIRED`). GUI `HELLO` requires build stamp.
- **No product Remote commands:** GUI allowlist `HELLO`, `GET_SNAPSHOT`, `GET_EVENTS`, `DETACH`; separate test-only pipe `rdc-p1-ctl-<GUID>` exposes synthetic `TEST_*` verbs solely to OS-validated original test controller. Product-style `STOP`, `LOGOUT`, `END_TEST_HOST`, arbitrary execution and restart requests are denied. No true Remote state is read. Snapshot returns `fake:true` and `unknown` values for real Remote dimensions.
- GUI consumes bounded `EVENT_BATCH` frames with monotonic sequence and `moreAvailable`; when ring overflow makes a gap, it requests a fresh Host snapshot and updates its state without restarting Host. Host records gap and resnapshot counters.
- New `Tests/Test-Arch016P1Matrix.ps1` launches only disposable Host/GUI scripts in unique `RDC-P1-<GUID>` TEMP directories. Cleanup verifies Host PID + start time + exact command line before test-only `TEST_CLOSE` and `TEST_END`, waits <=4.5s GUI / <=7.5s Host and scans real process records for 3.5s. **No Stop-Process/taskkill** in normal fixture. When cleanup cannot be established, output includes residual PIDs and diagnostics and exits nonzero. Test-only source is not deployed.

## ARCH-016-P1 24-row acceptance matrix (isolated STARMER)

| ID | Scope / specific outcome | Result |
| --- | --- | --- |
| P1-01 | Host heartbeat with zero GUI, fake Remote only | PASS |
| P1-02 | A→close→edit GUI source→B; stable Host PID/mock UUID | PASS |
| P1-03 | Repeated OPEN, GUI singleton and 10-plus GUI launches | PASS |
| P1-04 | GUI fails before and after HELLO; repaired GUI attaches | PASS |
| P1-05 | Valid framed JSON, typed request/response correlation | PASS |
| P1-06 | Zero, >8192, UINT32_MAX length headers rejected before body | PASS |
| P1-07 | Partial header/body, missing newline; heartbeat continues | PASS |
| P1-08 | Held idle client, dropped GUI response, no Host UI timer stall | PASS |
| P1-09 | Fast malformed clients; worker concurrency <=2 | PASS |
| P1-10 | Forged GUI PID in caller-provided HELLO rejected by kernel-observed peer PID | PASS |
| P1-11 | Different real Windows logon SID / remote SMB peer actual connection denial | **NOT CHECKED** — isolated cross-session or SMB sandbox requires separate authorization |
| P1-12 | False Host PID/start-time from rendezvous rejected by GUI/IPC client | PASS |
| P1-13 | STOP, LOGOUT, END_TEST_HOST, SCRIPT_EXEC, RESTART rejected | PASS |
| P1-14 | Reused request ID and expired nonce rejected | PASS |
| P1-15 | Protocol mismatch and stale Host generation refused | PASS |
| P1-16 | Monotonic Host revisions/sequence and GUI snapshot-based resync | PASS |
| P1-17 | Host event ring <=256, GUI detects gap after >270 synthetic events, requests fresh snapshot | PASS |
| P1-18 | Duplicate Host mutex refused without killing existing Host | PASS |
| P1-19 | Incorrect/stale Host PID rendezvous refuses connection | PASS |
| P1-20 | Outside-root GUI launch refused; normalized path/reparse guard checked in code | PASS (ordinary outside-root; TOCTOU/reparse race **NOT CHECKED**) |
| P1-21 | Physical tray double click/X/keyboard/DPI/Explorer restart | **NOT CHECKED** — visible UI sandbox not approved |
| P1-22 | Independent runner intentionally fails while GUI alive; nonzero exit, cooperative cleanup and zero owned PIDs | PASS |
| P1-23 | Existing P0 15, P0 negative 2, PROG-005A 27+21, Remote 46, classifier 32/parity, UI and Npx mock regression suites | PASS |
| P1-24 | Actual Setup/Portable/ZIP artifact content and release | **NOT CHECKED** — no package created or opened; `Source/` unchanged by static scope |

**Automated totals:** **21 PASS / 0 FAIL / 3 NOT CHECKED**, **exit 0** for the completed positive 24-row matrix. The `-InjectFailureAtGui` run exits **nonzero** by design, and its fixture-owned Host/GUI process list is empty after verified cooperative cleanup. P1-23 executes prior regression scripts, checking each exit code (including original classifier differential parity).

Reproduce on STARMER from the P1 worktree:

```powershell
powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File 'E:\Projects\GitSync\RDC\RDC-Relay PROG-006A-P1\Tests\Test-Arch016P1Matrix.ps1'
```

## Safety qualification and open risks

1. **Production IPC remains NO-GO.** Although the Windows logon SID DACL and NETWORK deny are set, independent cross-session/SMB rejection and Windows `PIPE_REJECT_REMOTE_CLIENTS` are **NOT CHECKED**. Pipe path and per-launch nonce file are not a security boundary against malicious equal-privilege code in the same logon session. The trusted Host executable/install signature is not verified; source is a disposable test file.
2. Actual OS pipe peer process PID and session are verified in the test, but high-privilege spoofing, PID reuse between validation and use, process-handle identity pinning, nonce leakage from same-SID compromised code and request-ledger exhaustion are residual risks. Replay ledger intentionally fails closed after 8192 requests rather than silently clearing; rekey/recovery is not implemented for an installed product.
3. Path reparse rejection occurs before spawn. Atomic no-swap-after-validation and installer signature verification are **NOT CHECKED**.
4. The Host's in-memory snapshots/events are fake. Actual Remote PID/process inheritance, log cursor, credentials, network reconnect and full Exit remain excluded.
5. GUI and tray are headless under test (`NotifyIcon` allocated but invisible), so physical mouse, keyboard, Windows Explorer restart and visual/accessibility acceptance are **NOT CHECKED**.
6. **Initial development diagnostic — orphan file `NOT CLEAN`:** the *first* failed P1 fixture used an **incorrect** logon-SID derivation from TokenStatistics and wrote `%TEMP%\RDC-P1-1840a5107e624387a3e007ea92d2bef4\controller-auth.json` with a SID not present in the session. After verifying that this was only a fixture Host PID 23608 (unique script path, creation time, command line, no GUI children), the test-only orphan was terminated; **no live Remote or user process was terminated**. A subsequent attempt to restore permissions/remove its own temporary file received **Access denied**. The folder/file remains as a **diagnostic artifact requiring Architect-guided local cleanup or separately granted file permission correction**. No system-wide ACL/security settings were changed. All later corrected fixtures use `TokenLogonSid` and report zero active test-owned PIDs with their own TEMP directories removed. **This earlier run does not qualify as leak-free file cleanup.**
7. All P0/P1 tests are isolated fake-only proof. **Reviewer REV-006A-P1 must independently verify** C# framing, same-session OS identity, nonce failure, GUI event resync, hostile stalled peer and negative failure-path teardown before Architect GO; P1 is **not** automatic authorization for PROG-006A, PROG-006B, PROG-005B, PROG-005 or release.
