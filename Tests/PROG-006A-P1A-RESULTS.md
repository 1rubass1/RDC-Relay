# PROG-006A-P1A — fake-only IPC corrective pass

**2026-10-23 · STARMER · Windows PowerShell 5.1 · PR #18 · Programmer.** This document supersedes the **P1-only 21 PASS / 3 NOT CHECKED** classification for the corrected P1A state. The original `Tests/ARCH-016-P1-RESULTS.md` remains historical evidence, not current security acceptance.

## Boundary

Changes are confined to `Tests/Prototypes/ARCH-016-P1/`, `Tests/Test-Arch016P1Matrix.ps1` and development documentation. No `Source/remote-window.ps1`, Desktop Commander Remote, installed RDC Relay, system policy, production branches, app update/Exit or release. The prototype keeps a **fake** Remote identity, never real process state or credentials.

## M1 — bounded monotonic replay epochs, not nonce rotation

The former global 8192-item `HashSet` permanently locked out Host and `TEST_END`. P1A introduces two **OS-identity/nonce-bound monotonic request streams**, one from the tracked GUI child, one from the verified test controller. Every authenticated request carries `requestSequence` plus a 32-hex `requestId` whose first 16 hex digits encode the sequence. Server rejects a non-increasing sequence or a reused/mismatched ID before dispatch. Each stream maintains a **per-epoch bounded requestId ledger**; on progressing past the epoch boundary it is cleared **only after** the strictly increasing sequence has rendered **all old epoch messages unusable**. It does not blindly clear a generation-global replay set. The Host generation, PID, application Host ID, fake Remote UUID and per-launch nonce are unchanged across these sequence epochs.

- Default epoch size **8192**. Test fixture supplies `-ReplayLimit 8` (no global setting) and forces many rotations by sending >270 synthetic events while GUI polling continues.
- Tests assert `controllerEpoch >= 10`, `guiEpoch >= 1`, preserved fake session/Host PID, acceptance of current requests, rejection of **a request captured before rollover** and an old requestId with a forged new sequence, a functional GUI A→B and the final authenticated cooperative `TEST_END`.
- Old replay **remains rejected even after the old per-epoch ledger was recycled**, since `lastSequence` is never reset within that verified process session. GUI sequences reset only after the *actual registered GUI process has exited*, with a new child/nonce; controller sequence lives until Host exits.
- The large finite sequence and epoch counters are not infinite. When nonrepresentable/invalid, the code fails closed; product-grade renewal beyond the typed counter limit remains separate. This is an **equivalent bounded monotonic anti-replay mechanism, not cryptographic key rotation**. Fully compromised same-user processes remain a residual threat.

## M2 — secure-at-creation fixture secrets

`PrivateFile` first builds the protected `FileSecurity` with real Windows **TokenLogonSid Allow / NETWORK Deny**, then calls .NET Framework `FileStream(FileMode.CreateNew, FileSystemRights.Write, FileShare.None, ..., FileSecurity)`. The file has the protected DACL **at creation**, before writing any nonce/Host identity JSON byte; it is flushed before rename. Subsequent updates create an already-protected random temporary file and use atomic `File.Replace` to replace the existing protected destination; initial creation uses `File.Move`. Neither public `File.WriteAllText` followed by delayed `SetAccessControl` nor a broad system permission change is used for auth files.

Additional **PASS EXTRA P1A-ACL-AT-CREATION** negative control:
1. Inspect a normally created `controller-auth.json` for protected, explicit logon SID Allow and NETWORK Deny.
2. Start a distinct **disposable test-only** Host from a fresh unique fixture root with `-FailAclBeforeWrite`. The intentionally simulated ACL failure occurs before creating the first secret file.
3. Assert a nonzero child exit within 6 s, **no controller secret JSON**, **no *.secured** temporary secret, then delete only that confirmed disposable fixture folder.

This validates the injected failure path, not a real cross-session Windows security denial.

## M3 — revised ARCH-016-P1 24-row evidence

| ID | Test evidence, narrowed to what was actually measured | Result |
| --- | --- | --- |
| P1-01 | Fake Host heartbeat before GUI | PASS |
| P1-02 | GUI A → X-equivalent close → source B; stable Host PID/fake UUID | PASS |
| P1-03 | Repeated opens and 10+ separate GUI launches; one active GUI | PASS |
| P1-04 | GUI fault before/after HELLO, repaired GUI reconnects | PASS |
| P1-05 | Correlated request/response `requestId` **equality asserted**; bounded JSON | PASS |
| P1-06 | Zero, oversized and UINT32_MAX declared frame lengths rejected | PASS |
| P1-07 | **Held-open** incomplete 2-byte header and incomplete body through 1.2 s server deadlines; timeout counter and Host heartbeat progress verified | PASS |
| P1-08 | **Two held GUI-pipe peers** prevent timely GUI responses; GUI WinForms Timer test-pulse file continues advancing, Host heartbeat unchanged. Actual visible paint not observed | PASS (headless render-timer liveness) |
| P1-09 | **Two simultaneously connected silent peers**, measured `guiWorkerPeak=2` and maximum 2; separate rapid 15 malformed frames and Host heartbeat check. Long-duration memory soak not measured | PASS (bounded fixture concurrency) |
| P1-10 | Forged client PID text versus kernel peer ID rejected | PASS |
| P1-11 | Real second Windows logon or SMB attempt | NOT CHECKED |
| P1-12 | **Live rogue Named Pipe server** in unrelated test process, wrong OS server PID rejected by client verifier shared with GUI; no real malicious installed Host trial | PASS (fake-only peer check) |
| P1-13 | GUI pipe forbidden product operations not authorized | PASS |
| P1-14 | Immediate duplicate; old pre-rollover request; reused requestId with forged new sequence; wrong nonce rejected | PASS |
| P1-15 | Wrong protocol version / Host generation refused | PASS |
| P1-16 | Host revision/sequence monotonic; GUI returns to authoritative snapshot | PASS |
| P1-17 | 256-event ring bound, >270 events induce gap/snapshot recovery, **200000-character synthetic event truncates to <=100 chars** | PASS |
| P1-18 | Second Host process denied without killing first | PASS |
| P1-19 | Stale / false Host rendezvous PID refused | PASS |
| P1-20 | Outside-root GUI path refused; **real reparse/TOCTOU race not performed** | **PARTIAL** |
| P1-21 | Physical tray double-click, X, Explorer, DPI, keyboard/visual feedback | NOT CHECKED |
| P1-22 | Injected failing assertion with live GUI; runner nonzero, verified fixture-only cooperative cleanup, no matching live Host/GUI PIDs | PASS |
| P1-23 | Prior P0/P0A, ownership/window, Remote characterization, classifier/parity, mock UI and Npx regression fixtures | PASS |
| P1-24 | Actual Setup/ZIP contents and release boundary | NOT CHECKED |

**Full P1A matrix:** **20 PASS / 0 FAIL / 1 PARTIAL / 3 NOT CHECKED**, normal process **exit 0**. **Additional ACL negative:** 1 separate extra PASS. The fixture's `-InjectFailureAtGui` run intentionally exits **nonzero** and the parent normal runner verifies its diagnostic signature and that test-owned child processes are absent. All tests use fake states only.

## M4 — fixture cleanup and historical NOT CLEAN

The harness validates its own Host PID, creation time and exact disposable script command before a test-only cooperative `TEST_CLOSE` / `TEST_END`; waits are bounded (GUI 4.5 s, Host 7.5 s, read-only WMI process inventory 3.5 s). It never calls `Stop-Process` or `taskkill` on real user processes. If verified fixture cleanup cannot complete, it reports FAIL and exact remaining PIDs/diagnostics, never unconditional success.

**The two historical residual TEMP directories were not modified, ACL-taken-over, or deleted by P1A:**
- `%TEMP%\RDC-P1-1840a5107e624387a3e007ea92d2bef4` — wrong-logon-SID protected `controller-auth.json`, Access denied.
- `%TEMP%\RDC-P1-2e61d74ad79c41488491cfa10ee44b6c` — older fixture diagnostic.

**Historical workstation cleanup status remains NOT CLEAN**, even when all new fixture processes and directories clean up successfully. Any remediation requires separate owner authorization and Architect process/path verification. Prototype is still a research fixture; real Remote integration, production IPC, Windows cross-session/SMB proof, signed/path-pinned binaries and physical desktop acceptance remain NO-GO.

## Reproduce

Run in the P1 worktree using Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File Tests\Test-Arch016P1Matrix.ps1
```

Expected: 24-row matrix statuses above; separate `PASS EXTRA P1A-ACL-AT-CREATION`; `REMAINING_FIXTURE_PIDS=` empty; positive exit 0. Do **not** merge PR #18 before independent **REV-006A-P1A** and separate Architect disposition.
