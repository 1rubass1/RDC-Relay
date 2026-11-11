# ARCH-017 — Architect decision after REV-006A-G6; G7 assignment

**Date:** 2026-10-25  
**Project:** RDC Relay 1.6.0 RC1 / B1  
**PR:** [#23](https://github.com/1rubass1/RDC-Relay/pull/23), `feature/v1.6-host-gui-owner-pilot`, **Draft / NO MERGE / NOT INSTALLABLE**  
**Independent Reviewer:** [REV-006A-G6](https://github.com/1rubass1/RDC-Relay/pull/23#issuecomment-6394761060), review of Programmer code `c203d52f25b91a597e29ea4142ee4155c8747637`  
**Decision:** **CONDITIONAL ACCEPT** of measured disposable FAKE_ONLY Windows Host/GUI/IPC results; **REQUEST CHANGES** on harness cleanup integrity. Assign **PROG-006A-G7** in the **same PR #23**, then **REV-006A-G7** once focused safety and substantial product-source deliverables are available. No separate F1/F2-only standalone PR.

## Verified evidence; do not overstate

Independent STARMER Windows PowerShell 5.1 runs:
- OS-02 ten GUI replacements: **43 PASS / 0 FAIL / exit 0**, one unchanged Host PID/birth, eleven unique original GUI PID/HWND, eleven authenticated snapshot/event polls, no trial survivors.
- Combined constructor/start failure: **19 PASS / 0 FAIL / exit 0**, exact ticket recoverable and Host/GUI IPC alive.
- Duplicate Host: **18 PASS / 0 FAIL / exit 0**, second executable refused without killing existing Host.
- Legacy/new safe regressions: **17 PASS / 0 FAIL / exit 0**.
- OS-01…OS-24 current audited matrix **5 PASS / 5 PARTIAL / 14 NOT CHECKED**. Reviewer confirmed three new trial roots absent and three unrelated historical P1/P2 TEMP roots remain **NOT CLEAN and untouched**.

The Reviewer identified **two source-proven defects**, not failures reproduced in the above successful test runs. Existing evidence remains valid **within its tested scope**, but harness cleanup gate is not unconditionally accepted.

## Task PROG-006A-G7 — permanent harness safety + useful forward progress

### G7-A: F1 — sentinel check must fail closed

`Tests/Invoke-Rc1OwnerOsSmoke.ps1` lines ~300–307 skip sentinel comparison if the sentinel is missing. Make existence, readable exact original bytes/hash, correct run association and no-reparse check **mandatory** before `safeToClean`, before deleting any fixture and before recording `OS_DISPOSABLE_CLEAN=TRUE` or overall success. Missing/changed/unreadable sentinel means nonzero FAIL and `NOT CLEAN`, with **no delete or force stop**.

Add a fixture-only *negative* test removing/altering only its newly generated own sentinel before cleanup and verify no false PASS, no test-root deletion, no foreign file access, clear run ID/path and retained NOT CLEAN evidence. After the test, clean only explicitly verified own fixtures through an approved route; do not use F2-vulnerable cleanup to conceal a failure.

### G7-B: F2 — deletion requires independently bound run provenance

`Tests/Remove-Rc1OsSmokeFixture.ps1` currently accepts an arbitrary `-RunIds` value with matching direct-TEMP folder shape, 16 filenames and deterministic sentinel, but no launch-recorded file hashes or immutable-at-run creation evidence. **GUID shape, source filename list, user-editable candidate JSON and deterministic sentinel are not authority to delete.**

1. At fixture creation, write a **fresh, protected per-run attestation** using CreateNew and ACL-before-secret-data, with run GUID/epoch, canonical root, approved source SHA-256 for all 16 files, original source commit/manifest identity, creation/birth metadata and available captured exact test-owned Host/GUI process IDs/UTC birth/OS session/parent identity. Bind to the independent harness run record rather than trusting a directory that merely looks correct. Describe and enforce the threat model: this prevents accidental/foreign/stale fixture selection, not malicious same-logon impersonation.
2. Give cleanup an explicit trusted evidence source and exact run identity; require original per-run attestation/provenance **before** selecting a root. Existing older/unattested fixtures must be **NOT CLEAN / refuse**, not silently migrated or guessed from a GUID. Prevent replay and duplicate selection.
3. Revalidate canonical exact direct-child TEMP path, no reparse roots/components/files, exact file set, **byte hashes against the original attestation**, non-symlink sources, expected sentinel identity, and OS read-only no-survivor inventory immediately before each deletion boundary. A changed hash, unknown entry, missing independent record, anomalous process identity, ownership ambiguity or inaccessible data means **fail closed, nonzero, no additional deletion**. Use exact-file nonrecursive deletion only; report any partial failure honestly and preserve diagnostics.
4. Add isolated negatives: lookalike GUID root with no matching attestation; edited-but-same-name source file; inconsistent owner birth or run binding; missing/changed sentinel; and unexpected/reparse entry only if safely constructible. Verify all unauthorized inputs are rejected **without deleting them or modifying an external sentinel**. Keep evidence of refusal and unchanged sentinel.
5. Retain measured 10 GUI replacements, explicit `-Execute`, `-FakeOnly`, existing bounded runtimes, no force stop, distinct per-logon identity and zero survivor checks. Re-run the 17 quick suites and approved FAKE_ONLY OS smoke tests only if the safety changes themselves warrant it and only inside previously owner-approved Host/GUI fixture scope.

Do **not** authorize broad cleanup of unrelated folders; the two old P1 and unknown-provenance P2 directories stay untouched and NOT CLEAN. Existing arbitrary historical G5/G6 failed fixture roots without securely established provenance must likewise remain NOT CLEAN rather than be force-cleaned.

### G7-C: advance product RC1, rather than creating another standalone safety-check cycle

Within existing `PROG-006A-INTEGRATION`, begin the genuine **Owned/Adopted/Unknown Remote child ownership + cooperative shutdown** module using an injectable stand-in interface and in-memory/fake process observations **without running any new dummy-Remote OS process tree**. Extend the existing `Source/RdcOwnerProcess.cs`, `Source/RdcOwnerRemoteState.cs` and Host boundary as appropriate; do not re-introduce `taskkill /T /F`, no-HWND force stop, `Stop-Process -Force` or `remote --logout`.

Required source outcomes:
- Pin owner process and descendant chain to OS-observable PID, UTC birth, session, executable/path, parent and run epoch. Stop authorization uses fresh OS observations immediately before a cooperative request.
- **Owned** requires direct recorded creation/verified ancestry and explicit allowed stop; **Adopted** and **Unknown** categorically refuse ownership-based stop even if executable name matches.
- Design cooperative bounded child → parent → Host full Exit with truthful failure/NOT CLEAN and no fallback force kill; default production Remote stop remains **blocked** until reviewed disposable owned-child trial and separate authorization.
- Add pure fake/injected tests for Owned success eligibility, mismatched PID/birth/session/path, adopted/unknown, child survivor, stop refusal/timeout and no false-clean status. Mark OS-04…OS-10/OS-16/OS-24 **NOT CHECKED** until their actual new *dummy Remote* process-tree trials are independently scoped and separately authorized.
- Prepare (do not execute) a bounded runnable dummy-Remote test mode and a precise **owner permission request** specifying executable, fresh GUID roots, operations, limits, cooperative stop, outside sentinels, independent process inventory and rollback. It must not contact `@wonderwhy-er/desktop-commander@0.2.52` or installed v1.5.18.

Maintain candidate packaging work toward a *side-by-side* 1.6.0 RC1, but retain `RDC_RC1_BLOCKED` and `installable=false / publishable=false` until an actual safe install transaction, rollback and separate owner G1 are accepted. Do not call a blocked ZIP an installer. Don't perform real Remote log/credential/account operations or publish stable v1.6.0.

## Next handoff

Programmer commits all changes to the **existing PR #23** and updates `COORDINATION/BOARD.md`, `PROJECT_CONTEXT.md`, G6/G7 evidence and OS matrix preserving exact PASS / PARTIAL / NOT CHECKED. Independent **REV-006A-G7** must inspect F1/F2 negative controls and provenance/TOCTOU limits and verify new fake-only owned-stop source contract, with a separate **explicit owner gate** before any new OS-tree dummy Remote trial. No PR merge or owner install claim.

The user has approved previously run **disposable FAKE_ONLY Host/GUI** Windows trials, **not** the genuine Remote, RC1 installation, historical TEMP cleanup or new managed **dummy Remote stop/tree** trials. No implicit expansion of permissions. Stable v1.5.18, live Remote, `main`, `stable`, update channel and user credentials remain untouched.
