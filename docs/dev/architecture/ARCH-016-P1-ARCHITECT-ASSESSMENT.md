## Architect final research-only integration decision — 2026-10-23

**ACCEPTED as a research-only fake Host/GUI IPC prototype, not product-safe IPC.** Following [REV-006A-P1A independent PASS](https://github.com/1rubass1/RDC-Relay/pull/18#issuecomment-6374530402), Architect merged [PR #18](https://github.com/1rubass1/RDC-Relay/pull/18) to `development` at **`0a44593b8442ead9c467509072bb1bb103fb0158`**. The NO-MERGE and P1A-pending text below records the earlier state and is superseded for **research merge only**, not product safety.

**Independent reviewer evidence:** STARMER Windows PowerShell 5.1, 24 matrix rows **20 PASS / 0 FAIL / 1 PARTIAL / 3 NOT CHECKED**, runner exit 0, additional ACL-at-creation fault-injection PASS; mock GUI build A→B with stable fake Host PID and fake Remote identity, request replay epochs functioning across multiple rollover cycles, no permanent 8192-request lockout, private ACL present at file creation, hostile incomplete/flood/rogue-server fixture checks, bounded fake event logs, negative GUI-active failure and fixture-owned cooperative teardown. Reviewed source code commit **`b16c354e0152e89ad4bbc9799e0c88e3dba8c0b3`**; subsequent PR changes through merge modified only `COORDINATION/BOARD.md` and `PROJECT_CONTEXT.md`.

**Architect integration verification:** GitHub comparison against `development` before merge: exactly 10 paths under `Tests/`, `docs/dev/` and coordination documentation; `Source/remote-window.ps1` Git blob **`e056e591afa0f2d49ffe4ee307bb167494b3f61f`** identical to base `development`; no `main`/`stable` or installed app update. All 37 relative internal links across review/board/context resolved; no trailing whitespace in these docs. Architect did not rerun P1 on STARMER (independent Reviewer execution was accepted). Do not claim a full distributable ZIP check.

**Still explicitly NOT CHECKED / BLOCKED:** P1-20 reparse/TOCTOU path-race PARTIAL; P1-11 real cross-session and remote SMB denial NOT CHECKED; P1-21 physical tray X/double-click, DPI/Explorer restart/accessibility NOT CHECKED; P1-24 actual Setup/Portable ZIP NOT CHECKED. Runtime/installer path signing/atomic pin, full same-privileged-user malicious code threat, Windows OS hang, real Remote continuity and owned/adopted shutdown are not established. This P1 research merge **DOES NOT authorize** product `PROG-006A`, `PROG-006B`, `PROG-005B`, `PROG-005`, remote-process launch/stop, real Remote test, or release.

**Historical workstation residue: NOT CLEAN.** Two old fixture directories (`%TEMP%\RDC-P1-1840a5107e624387a3e007ea92d2bef4` and `%TEMP%\RDC-P1-2e61d74ad79c41488491cfa10ee44b6c`) are left untouched. No owner approval to change ACL, take ownership, elevate, delete, run generic cleanup or touch live user processes. Separately authorize exact-path verification and narrowly-scoped cleanup later if desired. DESIGNER `DES-002` stays queued pending owner brief.

---

# ARCH-016-P1 — Architect decision after REV-006A-P1

**2026-10-23 · RDC Relay / B1 · PR #18 · status: CONDITIONAL ACCEPTANCE of fake-only feasibility evidence; PR MERGE NO-GO until limited P1A corrections.**

Source of independent verdict: [REV-006A-P1 GitHub comment](https://github.com/1rubass1/RDC-Relay/pull/18#issuecomment-6372166227). Original contract: [ARCH-016-P1-HOST-GUI-IPC-CONTRACT.md](ARCH-016-P1-HOST-GUI-IPC-CONTRACT.md). This assessment approves neither product IPC nor any operation against the installed RDC Relay / real Desktop Commander Remote.

## 1. What is accepted

Independent Reviewer ran the 24-row fake-only suite on **STARMER, Windows PowerShell 5.1**, reviewed code HEAD `b3961005c2a80b4b90aedc39145dc44386e54b27`: **21 PASS, 0 FAIL, 3 NOT CHECKED, exit 0**, including the deliberately failed GUI-active run with nonzero exit and fixture-only cooperative cleanup. This is Reviewer evidence; Architect has **statically reviewed** `P1Core.cs`, `P1Wire.cs`, `Gui.ps1`, the test runner and PR diff, but has **not independently rerun P1** after the review.

Credible research results: independently replaceable GUI A→B, the same fake Host PID/fake session UUID; non-UI-worker async 4-byte length-prefixed messages with pre-allocation size guard; OS-observed named-pipe peer PID and session compared with expected spawn process and creation time; TokenLogonSid DACL/NETWORK deny as implemented; GUI vs test-only controller verb allowlists; fake Host event ring, gap detection/resync, no real Remote call; previous fixture regressions pass. Production `Source/` is unchanged.

**Do not interpret 21/24 as 21 fully proven production controls.** Reviewer judged P1-05, 07, 08, 09, 12, 17, 20 materially **PARTIAL** relative to the named security requirement. P1-11 (real different logon/network SMB), P1-21 (physical tray/UI/DPI), P1-24 (actual Setup/ZIP) remain explicitly **NOT CHECKED**.

## 2. Must resolve in PROG-006A-P1A before research-only PR #18 merge

**M1 — Durable replay defense (blocking):** `P1Core.cs` maintains a generation-global `HashSet<string> seen`; at `seen.Count >= 8192` all later requests yield `REKEY_REQUIRED`, with no rekey mechanism. This eventually breaks normal GUI polling **and the test controller's cooperative `TEST_END`**, causing a persistently running Host and failed fixture teardown. Replace with a bounded **verified epoch/rekey/replay design** or an alternative safe bounded ledger that preserves no-replay guarantees without permanent lockout. Never silently clear a ledger inside the old epoch. A deterministic **small test limit** should force rollover for multiple epochs without reusing the Host PID, fake Remote UUID or losing GUI A→B. Old-epoch and duplicate IDs must be rejected; current-epoch valid request and cooperative `TEST_END` must remain possible. Do not add product stop/logout commands.

**M2 — Auth material must be private at creation (blocking):** `P1Core.PrivateFile` currently calls `File.WriteAllText()` and only **then** applies `File.SetAccessControl()`. The nonce/ticket file temporarily inherits surrounding directory ACL before protection; this is not a secure-at-creation guarantee. Construct the protected parent TEMP ACL and create each fixture secret file with appropriate DACL **atomically before first secret byte is written**, or use an equivalent demonstrably safe Windows implementation. Keep explicit logon SID / NETWORK policy. Verify a failing simulated ACL-creation path writes **no** secret file, does not broaden system permissions, and cleans fixture processes. Document any Windows PowerShell 5.1/.NET Framework constraints.

**M3 — Evidence integrity:** Update test assertions and the 24-row results so PASS means the row's stated criterion was actually exercised. At minimum independently test or downgrade:
- P1-05: response `requestId` actually equals the triggering request ID.
- P1-07: a **held open** incomplete header/body reaches server's **deadline** while Host heartbeat continues; closing early is not this case.
- P1-08: nonresponding/stalled server does not indefinitely block **GUI rendering**, not just a silent client/Host heartbeat.
- P1-09: **concurrent** adversarial clients and observed bounded active workers, rather than sequential clients alone.
- P1-12: competing/spoof Host pipe rather than only deliberately wrong expected PID (otherwise explicitly PARTIAL/NOT CHECKED).
- P1-17: very large synthetic event/payload behavior, not just 256-event ring overflow (otherwise mark PARTIAL).
- P1-20: an actual reparse/TOCTOU injection if safely achievable inside fixture; otherwise mark **NOT CHECKED** for atomic path swap, never claim it proven.

It is permitted to mark truly unperformed cases **NOT CHECKED/PARTIAL**, with correctly reduced PASS total and unchanged nonzero assertion-failure exit behavior. Never claim a full 24-row security pass on basis of missing or weaker tests. Keep separate product gate for true cross-logon/SMB, visible tray and package artifacts.

**M4 — Clean failure reporting:** Preserve `-InjectFailureAtGui` deliberately failing runner, bounded test-owned Host/GUI cooperative teardown with process PID/time/path verification and explicit residual file/process reporting. Do not use arbitrary `Stop-Process`/`taskkill`. Tests must be able to signal **NOT CLEAN** without claiming successful cleanup.

### Historical local NOT CLEAN — independent track, not authorization

Reviewer confirmed two residual historical paths under STARMER's TEMP (one with a denied-access `controller-auth.json` and an earlier orphaned fixture directory). Their existence must remain visible in the report; the older fake Host PID 23608 and independent review fake Host PID 40232 were no longer running when Reviewer inspected. **No permission takeover, ACL rewrite, delete, live process shutdown, global setting change or real Remote experiment is authorized here.** Obtain separate, explicit owner approval for exact-path inspection/cleanup only after verifying directory identity and no active process or external references. Do not conflate a clean new test run with a clean historical workstation.

## 3. What can merge, and when

- **Current decision:** PR #18 **stays Draft / NOT MERGED** while M1–M3 remain unmet; PR title and doc should not imply production IPC is ready.
- **Next Programmer stage:** `PROG-006A-P1A` on same prototype branch, **Tests/** and development docs only, satisfying M1/M2/M3 and preserving M4.
- **Independent Reviewer stage:** `REV-006A-P1A`, targeted independent security/negative validation on STARMER in disposable fake-only environment, with honest matrix totals and residual inventory.
- **Following Architect stage:** may accept/merge **research-only** PR #18 to `development` after P1A + Reviewer evidence; no `Source/`, real Remote, user installation, `main`, `stable` or release effect.
- **Product Host/GUI integration remains NO-GO:** `PROG-006A`, `PROG-006B`, `PROG-005B`, `PROG-005`. Needs separate approval of session/remote SMB verification, signing/path pinning, physical tray accessibility/UI, updater and safe Remote ownership/exit. Even corrected P1A fake IPC does not automatically establish product safety.

**Decision basis:** repeated normal use must not permanently strand a persistent Host; a secret must not be created world/inheritance-readable and retroactively protected; test labels must not overstate coverage. Research progress is accepted without relaxing these blockers.
