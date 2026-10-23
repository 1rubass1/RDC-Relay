# PROG-004 — decoded Remote line classification extraction and equivalence

2026-10-23 · STARMER · Windows PowerShell 5.1.26100.9711

**Basis:** `tests/prog-003a-characterization-edge-cases` with Architect restricted GO after REV-003, reviewed PR #6. **Implementation branch:** `refactor/prog-004-remote-line-classifier`. The original **33** characterization scenarios were retained verbatim as cases; **13** additional grouped branch-matrix scenarios were added **before** changing `Source/remote-window.ps1` (first test-only commit `3126407`; expanded fixture 46 PASS/0 FAIL/exit 0, snapshot SHA-256 `8FC870DD6D4D080BE6D50DACBACD57E48E84E4728A3C15D4E2664D102AAC8C30`). The baseline source remained unchanged then.

## Scope and mechanism

`Get-RemoteLineClassification([string]$line,[string]$faultKind)` was added to `Source/remote-window.ps1`. It has no side effects and returns `ToolKind` (`received`, `completed`, `failed` or empty), `HealthKind` (`ready`, `auth`, `session-lost`, `startup-failed`, `local-mcp`, `transport-offline`, `remote-unreachable` or empty), and `IsSerializedToolPayload`. It only inspects **already-decoded complete text lines** and explicit fault-kind context.

`Update-RemoteHealthFromLine` retains all state/fault/retry/ready/logging mutations in original branch priority; `Process-RemoteLine` retains marker-driven activity, log event lifecycle, JSON/bracket payload guarding, event ordering and visual mutations in their original call sites. No new or changed file reader, byte decoder, process handling, network, UI controls, update mechanism, process tree or external API. Classification intentionally preserves substring false positives, unmatched tool IDs, orphan completions and other PROG-003A quirks.

## Changed-branch coverage (pre-change, 46 fixtures / 0 fail)

| Branch family | Covered variants and effects |
| --- | --- |
| Ready | Remote-connected, Presence, *conditional* verified local MCP restart; readiness, fault clearing, flash, log, retry cancellation |
| Authentication wait | Both auth markers; interactive flag, deadline removal, no false fault, later Presence |
| Session-lost | All three alternative signatures; red fault, one log + retry log, auto-reconnect scheduling |
| Startup-failed | Device startup failure; latched fault and retry schedule |
| Local executor fault | Both loss/restart-failure strings; fault kind, deadline cleanup, **no** automatic restart schedule |
| Transport-offline | Channel error, channel closed, marked offline; latched red without queued restart |
| Remote-unreachable | All five legacy messages; fault kind, logging, deadline, no restart |
| No match / guards | Empty, whitespace, unknown, online-only, subscribed-only, manual-stop/stopping |
| Order / precedence | Ready before auth before fatal session before startup before local before transport before unreachable; separate-line opposite-order outcomes |
| Tool markers | Exact Unicode received/completed/failed and near misses, serial/bracketed payload vs non-JSON text, repeated, overlapping, out-of-order, orphan events; counts, fault state, hold, flashes, events |
| Log / UI sinks | Startup/live boundary, last-six ordering, max 8000/30000, CRLF/Unicode chunks, intentional existing internal overflow; fake logging and visual sinks |

## Measured validation (all isolated, not live Remote)

| Test | Result |
| --- | --- |
| `Tests/Test-RemoteCharacterization.ps1` (original 33 + 13 matrix) | **46 PASS / 0 FAIL, exit 0**, on both *pre* and *post* source |
| Full normalized deterministic state/log/event/visual-effect trace (after adding ordered sink captures) | **byte-identical SHA-256 before/after:** `49F346B69241EA36CE7CC1AA71180E550F36C2A7F403211658C9035730CB1D5F` |
| `Tests/Test-RemoteLineClassifier.ps1` | **32 direct pure-classifier input cases PASS / 0 FAIL, exit 0**; no state mutation |
| `Tests/Test-RemoteClassifierParity.ps1` | **PASS, exit 0**; runs the same 46 fixtures against both immutable original source and refactored source, compares normalized trace hashes |
| Existing `Tests/Test-UiLifecycle.ps1` | **PASS, exit 0**, mocks only |
| Existing `Tests/Test-NpxRecovery.ps1` | **PASS, exit 0** (seven synthetic safety scenarios) |
| `git diff --check` | **PASS, exit 0**; no uncommitted changes in isolated worktree |

The original baseline source used in this comparison has SHA-256 `7D0BC5531A51514F12248EEB70C2D3FC5072772C48414BB45A42730A0BD6D19C`; the refactored source SHA-256 is `641EDFDD46AC89B8ED9BB3FE79E2ABFC24BE2178AAC63EE4AB89C93075EE631F`. The trace normalizes clock prefixes and the *presence* of timestamp-based deadlines, not exact times. It includes every test's final health/active/event/header/log state and **ordered** synthetic log, render, divider work/fault and recovery-flash effects.

Repeat on STARMER from the isolated PROG-004 worktree:

```powershell
$root = 'E:\Projects\GitSync\RDC\RDC-Relay PROG-004'
$base = 'E:\Projects\GitSync\RDC\RDC-Relay PROG-003A\Source\remote-window.ps1'
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$root\Tests\Test-RemoteCharacterization.ps1"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$root\Tests\Test-RemoteLineClassifier.ps1"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$root\Tests\Test-RemoteClassifierParity.ps1" -BaselineSourcePath $base
```

The parity runner refuses a baseline source whose SHA-256 does not match the recorded original, refuses comparison with identical source, and creates/deletes only its own bounded temporary traces.

## Safety, NOT CHECKED and review gate

**NOT CHECKED:** actual `Open-Reader` / UTF-8 byte-boundary decoding / log file rotation/sharing/catch-up; physical/real Remote stream delivery and network/auth; owned/adopted/external processes, `taskkill` or stale PID; WinForms event loop and shader visuals; installed app, Setup/Portable and update/release artifacts. Fake effects do **not** prove those routes.

**No modifications:** `main`, `stable`, installed RDC Relay, operating Desktop Commander Remote, network, global Codex settings, any `Source/` file except the narrow `remote-window.ps1` classifier addition and integration.

**Gate:** PROG-004 is submitted to **REV-004** for independent review of all changed classification branches, trace parity and scope. This is not authorization to merge or begin PROG-005. Architect must decide integration GO/NO-GO separately.
