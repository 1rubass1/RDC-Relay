# PROG-006A-G7 follow-up — R1/R2 corrections and owner-authorized OS trial

**Date:** 2026-10-25 · **Role:** Programmer · **Machine:** STARMER / Windows PowerShell 5.1
**Scope:** existing `feature/v1.6-host-gui-owner-pilot` / Draft PR #23.
**Origin:** [REV-006A-G7](https://github.com/1rubass1/RDC-Relay/pull/23#issuecomment-6395651980) requested changes on `d218e8e`. All previous historical G6/G7 measured evidence remains intact; this document is an additional follow-up, not a retroactive rewrite.

## Reviewer R1 — false full Exit with unrecorded Host child

**Source:** `Source/RdcOwnerProcess.cs`, `RemoteTreeCooperativeExit.ExecuteInjected`.

When `includeHostExit=true`, preflight now requires Host direct OS child inventory to be **exactly the recorded Remote root**, without an additional Adopted/Unknown/other direct child. After the verified descendants/Remote have cooperatively exited, the contract makes a fresh Host children query **immediately before** its cooperative request and refuses if any child remains or appeared late. A final direct-child recheck is required before `Complete`. No force kill or claimed adoption.

`Tests/Test-V16OwnerTreeStop.ps1` adds:
- an unrecorded Adopted direct Host child before any stop → `RefuseUnexpectedChild`, **0** requests, child alive;
- an Adopted direct Host child that appears after the Remote step → `RefuseUnexpectedChild`, only child/Remote requests, Host alive, foreign child alive.

**Measured:** **18 PASS / 0 FAIL / exit 0**. This is an injected contract test; OS hostile race and real Remote stop remain unproven.

## Reviewer R2 — unsafe PID-only cleanup refusal and interrupted exact deletion

**Source:** `Tests/Rc1OsFixtureProof.ps1` and `Tests/Test-Rc1OsFixtureProvenance.ps1`.

- Formerly recorded Host/GUI PID is no longer treated as permanently reserved. If CIM returns an overlapping PID, a **fresh OS** `Process.StartTime.ToUniversalTime().Ticks` read distinguishes the exact recorded process (refuse) from a later unrelated reused PID (leave it untouched). If the PID disappeared between observations, fresh CIM corroboration is required; unreadable identity fails closed. Any command line referencing the trial root still refuses.
- An exact private CreateNew progress journal binds each of sixteen source files by the **original creation SHA256**: `intent-NN.json` is flushed **before** exact file delete; `done-NN.json` is flushed **after**. Each record binds run GUID, original epoch, file/index/hash, previous receipt or intent digest. No progress guessed from absent files.
- On a later invocation, only a complete consecutive hash-validated chain or one unfinished next intent is accepted. A missing file with its **previously written exact intent** can finish its done record; extra/missing/tampered entries refuse with nonzero `NOT CLEAN`. Validation re-checks sentinel, every remaining SHA256, reparse paths and OS survivors before each exact deletion. No recursive removal or force stop.
- **No retroactive salvage**: any formerly retained incomplete directory without this original write-ahead journal still fails closed. Specifically the old G7 partial cleanup root `RDC-RC1-OS-510e5b127c2e44efbd8c6f96f5f8f6d5` (9/16 original files) and earlier G7 root `RDC-RC1-OS-329977f0e2c244d4bfb6458cef151d90` (missing exit proof) remain **NOT CLEAN / untouched**.

**Measured:** `Test-Rc1OsFixtureProvenance.ps1`: **28 PASS / 0 FAIL / exit 0**, including:
- observed reused PID with different verified birth allowed but never signalled;
- exact alive PID/birth, missing birth or root-reference denied;
- deliberate interruption after deleting the **7th own file**, with 9 source entries remaining and intact independent proof/sentinel;
- read-only validation recognizes precisely the interrupted journal;
- a tampered intent prevents resume and any additional deletion;
- restoring original intent permits exact resumed cleanup; test-owned source/proof/sentinel disappear only after all identity/hash checks.

The remaining final post-root metadata removal is not a transactional filesystem commit, and hostile same-logon proof rewriting or adversarial TOCTOU is not proved impossible. Unknown or partially failed evidence remains NOT CLEAN; no attempts to repair retained older roots.

## Measured Windows OS execution (owner-authorized)

| Test | Result | Exit | Remarks |
| --- | --- | --- | --- |
| `Invoke-Rc1OwnerOsSmoke.ps1 -Execute -Cycles 10` | **43 PASS / 0 FAIL** | **0** | Host PID **30496**, UTC birth **639285207055756957**, session **1**, eleven distinct GUI identities/11 authenticated IPC, 10 native WM_CLOSE, zero survivors, original source and new attested-progress cleanup `OS_DISPOSABLE_CLEAN=TRUE`, run ID `3e1fe63a163e41888be5d122754ca90f` |
| `Test-V16OwnerTreeStop.ps1` | **18 PASS / 0 FAIL** | **0** | pure injected, includes preexisting and late Adopted direct Host child refusal |
| `Test-Rc1OsFixtureProvenance.ps1` | **28 PASS / 0 FAIL** | **0** | file-only fault injection and verified resume |
| `Invoke-V16Rc1SafeRegression.ps1` | **19 suites PASS / 0 FAIL** | **0** | prior 17 suites + updated two G7 suites |
| `Invoke-Rc1DummyRemoteTreeTrial.ps1 -Execute -OwnerApprovedDummyTree` | **6 PASS / 0 FAIL** | **0** | New actual disposable PowerShell actor parent+child, verified PID/birth/session/parent, cooperative child then parent exit, independent zero survivors and untouched external sentinel; trial root and sentinel cleaned |
| Separate post-trial inventory | **0 dummy TEMP roots, 0 non-observer dummy processes** | — | No real Remote processes used or stopped |

**User authorization:** On 2026-10-25 Владислав explicitly granted all test permissions in this conversation. Only two new ephemeral test PowerShell actors were started for the dummy tree. The independent **new dummy-tree pre-gate review is still NOT CHECKED**; the trial runner labels this truthfully and the test is **not** a production IPC/Remote approval. This is an owner-approved pre-review engineering trial, not a Reviewer PASS.

## Remaining real product gates

- `Source/RdcOwnerRemoteState.RequireSafeStop` still always refuses actual Remote stop. The above two-actor dummy harness is **standalone**, not a verified end-to-end adapter from production Host to pinned `@wonderwhy-er/desktop-commander@0.2.52`. Exact process spawning, real account/log/reconnection and safe full Exit remain **NOT IMPLEMENTED / NOT CHECKED**.
- OS-04 can be considered **PARTIAL** for actual owned stand-in root/child cooperative OS exit, **not PASS of integrated Host**. OS-05…OS-10 remained unrun for their distinct hostile branches. OS-16 remains **PARTIAL**, no real Host + Remote full Exit. Existing reviewed aggregate OS-01…OS-24 G6 matrix **5 PASS / 5 PARTIAL / 14 NOT CHECKED** remains the accepted reference; new partial trial awaits independent classification.
- Candidate still `installable=false / publishable=false`, compile-guarded installer; installed v1.5.18, current live Desktop Commander Remote, main/stable/public update feed and three historical TEMP roots untouched.
- **Next technical priority:** attach a real source-verified, OS-observing pinned Remote-owner adapter to Host with explicit OS ancestry and proof-bound cooperative stop, then isolated side-by-side installable RC1 Setup/Portable and STARMER owner pilot. Avoid another F1/F2-only microcycle.

**Requested Reviewer follow-up:** validate exact R1/R2 fixes and interrupted file journal, confirm the new owner-authorized dummy OS trial claims **without** equating them to product Remote acceptance, identify any remaining blocking exploitable defect. PR #23 Draft; no merge or release.
