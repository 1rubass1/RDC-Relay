# G6 — executable Windows OS harness coverage, actual source, and strict gaps

> **Post-G7 Programmer execution update (2026-10-25):** Independent G6 coverage table below remains the original **5 PASS / 5 PARTIAL / 14 NOT CHECKED**, and its older text describing a never-run dummy is historical. Under new explicit owner test authorization, Programmer executed a **standalone disposable owned dummy parent+child PowerShell OS cooperative stop** with OS identity/sentinel/survivor checks: **6 PASS / 0 FAIL / exit 0**; this adds **PARTIAL** evidence toward OS-04 and OS-16, without closing integrated product full Exit or unrun hostile OS-05…OS-10. Repaired G7 fixture cleanup (write-ahead original-SHA256 journal and OS PID birth handling) passed **28 negatives**, owner-tree refusal **18 injected**, 10-cycle Host/GUI/IPC **43 OS**, safe regressions **19/19**, all exit 0. New dummy independent Reviewer pre-gate **NOT CHECKED** and R1/R2 recheck pending. [Measured follow-up](V1-6-0-RC1-G7-R1-R2-OS-FOLLOWUP.md).

> **G7 update (2026-10-25):** Reviewed G6 coverage tally is still **5 PASS / 5 PARTIAL / 14 NOT CHECKED**. [G7 report](V1-6-0-RC1-G7-SAFETY-AND-TREE-REPORT.md) adds source-provenance cleanup F1/F2 negative controls (17/0), fake-injected owner-tree stop contract (16/0), successful attested cleanup on new FAKE_ONLY Windows Host/GUI runs (10 cycles 43/0; one cycle 15/0), and a NOT CLEAN diagnostic root lacking complete run proof. The new dummy-Remote child-tree OS mode was **only written/parsed, not executed**; OS-04…10/16/24 cannot become PASS from synthetic checks. Historical G6 evidence below is unchanged.

**2026-10-25 · Programmer · STARMER · branch `feature/v1.6-host-gui-owner-pilot` · Draft PR #23.**
**Disposition:** **PARTIAL PASS; actual disposable fake-only OS execution, not full OS-01…OS-24 certification and NOT INSTALLABLE.** Supersedes the older OS plan's global `NOT AUTHORIZED / NOT EXECUTED` label only for the exact test cases below. Direct owner GO on 2026-10-25 covered new disposable fake-only Windows test trees. No real Desktop Commander Remote 0.2.52, installed 1.5.18, stable channel or protected historical TEMP was controlled.

## Tested product-source harness

`Tests/Invoke-Rc1OwnerOsSmoke.ps1` is **inert without `-Execute`**, checks current branch and `installable=false / liveRemoteEnabled=false / publishable=false` candidate marker, and copies a fixed list of 16 actual Source product GUI/Host/IPC files into one new ACL-private `%TEMP%\RDC-RC1-OS-<32hex>` root. `-Cycles` accepts only **1…10** GUI replacements; separate `-InjectStartFailure`, `-InjectConstructorFailure`, `-ProbeDuplicateHost` opt-in. A new GUID, ticket, epoch and external sentinel are used per invocation. Trial Host requires explicit `-FakeOnly`; its source path and state root are private and identity-checked; 35s or 120s cooperative self-exit is bounded. No force-kill, logout, real Remote or installer route.

Checks rely on OS-observed exact PowerShell executable, parent PID, process UTC birth ticks and session; native HWND owner revalidated **immediately before** WM_CLOSE; GUI generation PIDs are unique; the same Host PID/birth remains across replacements. Kernel-verified Named Pipe peer identity is probed from the *foreign harness PID* while holding a correct private test ticket; Host returns `GUI_OS_IDENTITY`, not a WELCOME. Raw oversized and incomplete frames exercise server reject/timeout/worker cap; both GUI generations (or all 11) must poll authenticated snapshots and events. Fake-only Host sends a close generation to its GUI and self-exits; a post-run independent CIM command-line inventory must find **0 test-root process survivors** before any cleanup. File SHA256, approved exact entries, no reparse and unchanged outside sentinel are required before nonrecursive verified-only deletion. A failed/unknown identity keeps the exact root `NOT CLEAN`; `Remove-Rc1OsSmokeFixture.ps1` can clean *only* separately attested own failed fixtures.

## Observed Windows execution receipts

| Command / scope | Evidence | Result |
| --- | --- | --- |
| `-Execute -Cycles 10` | **Host 33448**, UTC birth `639285079591748713`, session 8; **11 GUI PIDs** 28624, 1848, 42200, 12924, 51352, 22208, 52440, 43416, 5888, 12224, 15640. Ten verified WM_CLOSE operations; one Host birth; GUI snapshot/event counts **11/11**; malformed pipe rejected=1, timeout=1, peak active=2; independent survivor count 0, cooperative exit and own-root deletion. | **43 PASS / 0 FAIL / exit 0**; OS-02 ten-cycle requirement genuinely executed. |
| `-Execute -Cycles 1 -InjectStartFailure` | Host 21840, GUI 22960→50404, exact ticket recovery, foreign-ticket peer denied; event/snapshot 2/2, clean exit. | **15 PASS / 0 FAIL / exit 0** |
| `-Execute -Cycles 1 -InjectConstructorFailure` | Host 7128, GUI 52684→21076, injection after pipe start; original run root removed, mutex and IPC released, fresh Host constructed and exited. | **13 PASS / 0 FAIL / exit 0** |
| `-Execute -Cycles 1 -InjectConstructorFailure -InjectStartFailure` | Host 12188, GUI 52708→8328; both injected failures recovered; private pipe oversized frame rejected **1**, partial frame timed out **1**, peak active **2**. | **18 PASS / 0 FAIL / exit 0** |
| `-Execute -Cycles 1 -ProbeDuplicateHost` | Host **24528**; duplicate launcher PID **32372** returned **exit 1 / RC1_HOST_ALREADY_RUNNING_NO_KILL**; original Host survives; GUI 37044→50900; outside sentinel unchanged; `OS_TRIAL_SURVIVOR_COUNT=0`. | **18 PASS / 0 FAIL / exit 0** |
| 17 inherited V16 + legacy fake/AST/compile suites | Current full source compiled in WinPS 5.1, full original GUI contract, ticket, package, parser, state regressions. | PASS (separate individual exit codes recorded by `Invoke-V16Rc1SafeRegression.ps1`) |

The 35s/120s trial timings are process **bounds**, not claims of UI latency or user experience. Early G5 failures and fixes remain documented in [G5 report](V1-6-0-RC1-G5-OS-SMOKE-REPORT.md) and are not rewritten as PASS.

## Honest OS-01…OS-24 coverage

| ID | Status | Measured boundary / missing proof |
| --- | --- | --- |
| OS-01 | **PASS (programmatic native WM_CLOSE)** | Only verified GUI exits; same Host stays. Physical mouse X not checked. |
| OS-02 | **PASS** | Ten genuine GUI process replacements / eleven unique GUI identities, same Host, fake events/snapshot 11/11. |
| OS-03 | **PARTIAL** | Second same-root Host refused by OS singleton, no forced kill. Actual tray double-click/rapid launcher interaction not checked. |
| OS-04 | **NOT CHECKED** | No disposable owned dummy Remote child-chain stop controller exists yet. |
| OS-05 | **NOT CHECKED** | No adopted stand-in OS stop attempt. |
| OS-06 | **NOT CHECKED** | No orphan/foreign stand-in stop attempt. |
| OS-07 | **NOT CHECKED** | No controlled stale-PID/birth reuse negative. |
| OS-08 | **NOT CHECKED** | No wrong-session/image/epoch process stop attempt. |
| OS-09 | **NOT CHECKED** | No verified parent-exited child survivor test. |
| OS-10 | **NOT CHECKED** | No non-cooperating dummy Remote child stop timeout. |
| OS-11 | **NOT CHECKED** | No executable no-HWND child test; source guard only. |
| OS-12 | **PARTIAL** | Actual outside PID with valid ticket denied, oversized frame refused; version/replay/wrong nonce from authenticated GUI not exercised. |
| OS-13 | **NOT CHECKED** | Boundary functions reject reparse statically; no deliberate junction/symlink OS fixture. |
| OS-14 | **PASS** | External sentinel exact bytes intact after each run. |
| OS-15 | **PARTIAL** | GUI A/B (and all eleven) reobtained Host snapshot/events; forced missed-sequence/gap and crashed GUI untested. |
| OS-16 | **PARTIAL** | Verified own GUI fake-only Exit is cooperative; owned dummy Remote process tree full Exit not implemented. |
| OS-17 | **NOT CHECKED** | Real incompatible-version GUI process not tested. |
| OS-18 | **NOT CHECKED** | No concurrent foreign installed app process trial. |
| OS-19 | **PASS** | Real GUI first Process.Start deliberately fails after ticket, verified own revoke, retry and normal GUI/Host process continuation. |
| OS-20 | **NOT CHECKED** | Replaced/foreign/reparse private ticket OS race untested; synthetic F2 negatives exist. |
| OS-21 | **PASS (specific injection point)** | Actual trial constructor fails after pipe creation, cleans own mutex/run root/IPC workers; subsequent Host construction works. Additional partial-init points untested. |
| OS-22 | **NOT CHECKED** | Ten GUI launches used same copied source; on-disk source A→B modification/reload not tested. |
| OS-23 | **PARTIAL** | Real pipe oversize/partial timeout, worker cap and responsive GUI verified; event gap/long-lived arbitrary hung peer not fully exercised. |
| OS-24 | **NOT CHECKED** | Host still FAKE_ONLY and cannot attempt full Exit with a simulated Unknown child. |

**Reviewer handoff / Architect boundary:** inspect exact G6 commit, test-root trust, execution/cleanup paths, negative frame and duplicate-Host behavior and false-PASS risks. Missing 04–10/16/24 require a real *disposable stand-in process ownership supervisor and cooperative stop contract*, **not** a fabricated Remote. A genuine Remote and installable RC1 remain blocked until separately reviewed and approved. PR #23 stays Draft / NO MERGE.
