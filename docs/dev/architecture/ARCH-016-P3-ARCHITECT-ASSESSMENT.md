# ARCH-016-P3 — Architect decision after REV-006A-P3

**Date:** 2026-10-24 · **Stage:** B1 · **PR:** [#22](https://github.com/1rubass1/RDC-Relay/pull/22) · **Status:** CONDITIONAL ACCEPT of fake-only P3 feasibility; **NO-GO owner-kit handoff and PR merge** pending narrowly scoped P3A corrections.

**Primary evidence:** [REV-006A-P3 independent Reviewer conclusion](https://github.com/1rubass1/RDC-Relay/pull/22#issuecomment-6381840407). Reviewer checked implementation commit `983c5190dac9faba512127a5ee8507a5bf466286`. Current PR head before this assessment `ff5b857837de36379c03bbeded08894d2b9cac93` added coordination-only documentation after reviewed code. These facts are independent Reviewer evidence, not an Architect STARMER test.

## Architect decision

**Assign PROG-006A-P3A, followed by independent REV-006A-P3A, on the same P3 branch and PR #22.** The review's F1/F2 findings concern reliability and safety of an owner-operated cleanup tool. Do not waive either finding for an owner-facing kit. Keep the work limited to cleanup/marker ownership and self-test integrity; do not repeat the Host/GUI architecture or visual redesign.

Existing valid fake-only functionality is accepted as feasibility evidence: a real WinForms GUI A (PID/HWND) closes via owned native WM_CLOSE and new Build B launches with a distinct GUI process while fake Host PID/mock Remote identity remain unchanged, at least 10 further GUI cycles, no duplicate GUI, and fixture-owned graceful exit. ZIP members 17/17 matched checked-out source hashes, with no embedded runtime secrets. Independently executing the extracted ZIP was blocked and remains **NOT CHECKED**; physical human tray/X/menu use and subjective visual resemblance remain **NOT CHECKED**, not accepted by HWND tests.

## F1 — fail-closed exit/selftest result (required)

- In `Tests/UserDemo/P3/Check-And-Cleanup.ps1`, discovering any exact owned Host/GUI still alive, undecidable ownership, failed deletion or a retained own-run marker must yield **nonzero**; print clear Russian diagnostics, **do not force terminate processes or delete while running**. Distinguish `NOT CLEAN` from success.
- In `Start-Demo.ps1 -SelfTest`, verify the child's return status/exit explicitly (do not rely on a stale `$?`), exact-run process inventory zero, verified owned fixture directory absent and `RunState/active-demo.json` absent before printing `P3_SELFTEST_EXIT=0`. Errors/nonzero must propagate to the caller and the GUI/Host exit must be cooperative.
- Isolated **negative control**: keep an explicitly test-owned survivor alive, invoke cleanup, assert **nonzero, unchanged files and marker**, and that no process was killed. Then cooperatively end only that owned test process and separately confirm that clean teardown succeeds.

## F2 — exact owner-run binding and narrow file removal (required)

- Existing marker `HostPID` and `HostStartTicks` must be validated and incorporated into a per-run identity record rather than read and ignored. Bind the record to the exact freshly created `TEMP\\RDC-P3-<GUID>` root and a run-specific GUID/nonce placed in independently matching fixture metadata. This is a consistency/ownership check for the disposable run, **not authentication against malicious code with the same Windows logon**.
- Before using any marker-derived root or deletion argument, require **exact direct child** of the actual TEMP directory, canonical separator-safe equality/containment, rejection of reparse points in the root, parents and any entry, no nesting and explicit allowlist. Reject symlinks/junctions and unknown/modified files. Prevent a stale/corrupt/forged marker naming an unrelated stopped GUID-shaped directory from authorizing deletion.
- Make `Remove-Fixture.ps1` fail closed when independently invoked with a nested, redirected, unrelated or provenance-unknown directory. A GUID-shaped folder name and absence of matching processes are **not sufficient authorization**.
- Handle the case of an already-exited Host using verified per-run evidence rather than guessing process identity from a reused PID. Unverifiable marker, unknown history or changed path = **NOT CLEAN and no deletion**, with owner-facing explanation. Tests must use newly created fixtures/sentinels, never the three historic TEMP directories.
- Negative tests for nested `RDC-P3-<GUID>` folders, wrong marker/root binding, altered/old PID or creation ticks, and external sentinel preserved byte-for-byte. If a Windows symlink cannot be created, record NOT CHECKED rather than falsely PASS. No broad cleanup.

## Complete owner kit, not only Git scripts

After code changes, **rebuild** `Tests/UserDemo/RDCRelay-P3-UserDemo.zip`; check exact member allowlist, hash equality to new source, absence of auth/ticket/RunState secrets and stale scripts, and document SHA-256. Test direct `Start-Demo.ps1 -SelfTest`, cleanup negative control, and extracted ZIP `Start-Demo.ps1 -SelfTest` on STARMER **only in a safely authorized disposable path**. A blocked execution is NOT CHECKED; do not bypass security policy or elevate merely to force PASS. Rerun `Tests/UserDemo/P3/Test-P3VisibleWindow.ps1` and assert zero verified own-run survivors.

Independent Reviewer **REV-006A-P3A** reruns the focused negative checks, visible GUI A→B regression, selftest and portable archive verification (including extracted ZIP when safe), and returns PASS / CONDITIONAL PASS / FAIL with explicitly untested cases.

## Owner acceptance and remaining boundaries

Even after a clean P3A review, **physical X, notification icon double-click and right-click menu, appearance compared with installed RDC Relay, text/layout/disabled controls and normal Windows DPI** require owner-observed demonstration before claiming user acceptance. The owner should have a safe start/close/cleanup procedure and no requirement to touch the real installation. Internal research merge can be decided separately after P3A; do not silently treat it as physical UX sign-off.

Three historical/unverified directories (two `RDC-P1-*`, one `RDC-P2-aace757df1eb4f7cb3e2e17dbeec7a5d`) remain **NOT CLEAN, untouched**. No ACL edit, owner takeover, delete, elevation, force-stop or historical diagnostic cleanup. No real Desktop Commander Remote, installed RDC Relay, `Source/remote-window.ps1`, `main`, `stable`, release, PROG-006A/006B/005B/005 or product IPC work is authorized by this decision.
