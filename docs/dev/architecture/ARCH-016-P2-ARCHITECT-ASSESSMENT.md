# ARCH-016-P2 — Architect decision on REV-006A-P2

**Date:** 2026-10-24  
**Project:** RDC Relay · B1 core stabilization  
**PR:** [#20 — interactive fake-only Tray Host / replaceable GUI](https://github.com/1rubass1/RDC-Relay/pull/20)  
**Reviewer evidence:** [REV-006A-P2 conclusion](https://github.com/1rubass1/RDC-Relay/pull/20#issuecomment-6375321316)

## Decision

**CONDITIONAL PASS for the isolated fake-only lifecycle demonstration. PR #20 remains DRAFT and must NOT be merged yet.** Assign the narrow correction **PROG-006A-P2A**, followed by independent **REV-006A-P2A**. No new product implementation stage is authorized.

This is not a request to repeat the full design/research cycle. Reviewer established a working real-window GUI A→WM_CLOSE→B path with a persistent fake Host and synthetic Remote identity. Two concrete safety defects remain in the disposable demo's path boundary and failure handling; both are actionable and should be corrected before preserving the user-facing demo in `development`.

## Evidence accepted

Reviewer ran on **STARMER / Windows PowerShell 5.1**, reviewed implementation commit `89928c089c5af5a61cbb8f049cad5a4ca3fea0f5`:

- Inherited 24-row fake-only matrix: **20 PASS / 0 FAIL / 1 PARTIAL / 3 NOT CHECKED**, exit 0; plus **4 EXTRA PASS**.
- Visible WinForms GUI A closed with native `WM_CLOSE`; GUI B started with a new PID/HWND while the fake Host PID and mock Remote UUID stayed the same. Duplicate open was refused; test-owned P2 process survivors: zero.
- P0/P0A, process/window, classifier/parity/UI and Npx mock regressions passed.
- PR #20 currently points to `0155de283e83ca39f09339174d458b9d20fb9238`; comparison shows the two commits after the reviewed code commit only update `COORDINATION/BOARD.md` and `PROJECT_CONTEXT.md`. No P2 implementation code changed after the reviewed HEAD.
- Production `Source/remote-window.ps1`, installed RDC Relay, real Desktop Commander Remote, `main`, `stable` and release artifacts were not touched.

## Mandatory narrow P2A corrections

### P2A-1 — enforce the disposable path boundary at every write/launch boundary

In `P1Core.cs`, `root` includes a trailing directory separator while `ContainsReparsePoint` ascends to a root path without that separator. The loop can stop before checking the root itself. In `Set-P2DemoBuild.ps1`, textual TEMP prefix and directory name checks are not sufficient: the helper must reject a reparse-point root and a reparse-point `Gui.ps1` **before reading or writing the GUI source**.

Required:
1. Canonicalize and validate the root using separator-boundary-safe comparisons; explicitly check the root directory itself and every relevant component, including the GUI file, for `FileAttributes.ReparsePoint`. Do not rely on a `StartsWith` loop that omits the root.
2. Apply the same validation before every GUI launch in Host and before every owner-facing source write in `Set-P2DemoBuild.ps1`; reject unexpected/nested roots rather than trusting a textual prefix.
3. Ensure the GUI does not write its pulse/log fixture outside the validated disposable root if the script/root becomes a reparse point.
4. Add isolated negative tests for a reparse-point fixture root and reparse-point `Gui.ps1` before the build helper writes anything. Use only unique test-owned paths; a sentinel outside the fixture must remain byte-identical. If the OS cannot create a particular reparse fixture, report that case as NOT CHECKED rather than PASS. Do not attempt a real TOCTOU race or modify unrelated paths.

### P2A-2 — make GUI-ticket creation failure a controlled launch failure

`P1Core.Open()` calls `PrivateFile(gui-ticket.json,...)` before the existing `Process.Start` try/catch. A ticket ACL/filesystem failure can therefore escape the normal tray launch-failure path.

Required:
1. Bring ticket creation and launch into one explicit, bounded error-handling path.
2. On ticket-creation failure, keep the Host and tray responsive, record a non-secret `launch-failed` event/counter, leave GUI state `NONE`, and do not report a GUI PID.
3. Add a test-only fault injection for failure before GUI-ticket creation. Assert no ticket/secret temp file is exposed, no GUI process starts, Host remains responsive, and no unhandled exception escapes the open handler.
4. Keep cleanup limited to exact files created by this test invocation; never delete an unknown pre-existing file, and do not use force-kill/process-wide cleanup.

## Required regression evidence

Run the existing full `Test-Arch016P2Lifecycle.ps1` suite and `Test-P2VisibleWindow.ps1` on STARMER in the fake-only environment after the correction. Preserve accurate PASS / FAIL / PARTIAL / NOT CHECKED counts and exit codes. Demonstrate that the new negative tests fail closed, and that the normal A→WM_CLOSE→B path still retains the same fake Host PID/mock Remote UUID with zero test-owned survivors.

No requirement to upgrade the existing path-race result: **P1-20 remains PARTIAL** until a separately safe true TOCTOU test exists. Physical human X/tray double-click, DPI/accessibility/Explorer behavior, cross-logon/SMB and actual package contents remain **NOT CHECKED**. These known limitations alone do not prevent a future research-only merge once P2A's two actionable defects are corrected and independently reviewed.

## Explicitly prohibited

- No real Desktop Commander Remote, installed RDC Relay, product IPC, `Source/remote-window.ps1`, `main`, `stable` or release changes.
- No PROG-006A product migration, PROG-006B Exit, PROG-005B or PROG-005.
- No Windows Explorer restart, cross-logon/SMB experiment, system security/ACL change or unapproved OS configuration.
- Do not inspectively repair, change ACL/owner, or delete historical TEMP artifacts.

**Historical residue stays NOT CLEAN and untouched:** both prior `RDC-P1-*` directories and the separate `RDC-P2-aace757df1eb4f7cb3e2e17dbeec7a5d` directory with unknown provenance. No cleanup is authorized by this decision.

## Gate after P2A

Programmer makes only the two corrections above on the existing PR #20 branch and hands off **REV-006A-P2A**. Reviewer independently checks the path/reparse negative cases, ticket-creation failure, full lifecycle regression and residual inventory. Architect will then decide on **research-only** merge. Until then, PR #20 stays Draft / unmerged.
