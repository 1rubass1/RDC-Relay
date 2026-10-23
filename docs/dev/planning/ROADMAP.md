# RDC Relay — current roadmap

> Reconciled 2026-10-22. Old roadmap contained outdated v1.5.12/v1.5.16 baseline and obsolete “NEXT Spike 0”. It is preserved [as history](../history/ROADMAP_LEGACY.md), not a current instruction.

## Phase A — Production baseline [DONE]
RDC Relay v1.5.18 released 2026-10-20, commit `5b1fdf58a8873d6cd781b0a835f8e208eb46dbfb` on `main`/`stable`. Pinned upstream `@wonderwhy-er/desktop-commander@0.2.52`. Existing regression and release-gate evidence is in CHANGELOG and historical worklog; no fresh runtime test claimed here.

## Phase B — Playbook governance [COMPLETE; MAINTAINED]
- Store Playbook routing, assigned roles, coordinated task IDs, context, decisions and design/research documents in the **development branch only**.
- Back up source records; import sanitized material into classified folders.
- Verify links, preserved sources and packaging exclusion. No product code/runtime changes.

## Phase B1 — Core stabilization before provider integration [NEXT]

**Decision scope:** On 2026-10-23 the owner approved *gradual, behavior-preserving strengthening* of the existing core before introducing a second provider. Draft architectural audits ([PR #3](https://github.com/1rubass1/RDC-Relay/pull/3), [PR #2](https://github.com/1rubass1/RDC-Relay/pull/2)) are evidence and proposals, not merged implementation.

Proceed one bounded task/PR at a time, with status/role ownership **only** in [COORDINATION/BOARD.md](../../../COORDINATION/BOARD.md):

1. **Characterization baseline — first executable task:** document current contracts of Remote start/stop/adoption/reconnect, actual log markers, tool success/failure, fault latching and update behavior. Build *isolated, deterministic fixtures/tests* against existing code, including edge cases, without starting/stopping the owner's production Remote. Preserve GUI and source behavior. Mark real-process routes NOT CHECKED until independently tested.
2. **Observation parsing seam:** extract only the smallest pure `Remote log → typed observation` step proven equivalent by the fixture suite. No upstream version change or UI redesign. Keep unknown inputs safe.
3. **Process ownership contract:** explicitly distinguish owned / adopted / external processes and avoid stopping unrelated or in-flight processes. Isolated process-tree/startup-delay/restart tests before changing `taskkill` or stale-GUI handling; no experiments against live Remote.
3a. **Tray/window host lifecycle (ARCH-015 / PROG-006):** owner corrected goal to **close/dispose the GUI instance, modify its code and reopen a fresh updated GUI** from tray while an independent host/supervisor and Remote keep working; the original same-Form Hide/Show design is superseded. Do **not** replace this with a second running GUI/Remote or reinitialize the updater. Existing no-window GUI mutex forced-kill heuristic conflicts with a deliberately hidden form and must become non-destructive before delivery. PROG-005A/REV-005A fake-only baseline **completed and accepted**. The owner now requires **explicit tray Exit to stop all verified managed Remote/launcher/children and supervisor/GUI**, without logging out or touching unrelated processes. **ARCH-016-P0/P0A research accepted; ARCH-016-P1 design contract written** for replaceable GUI and secure bounded IPC. Stage **PROG-006A-P1** first as fake-only transport and Host/GUI implementation with independent REV-006A-P1; **full product PROG-006A** remains blocked until the separate integration GO and OS/IPC verification. [P1 contract](../architecture/ARCH-016-P1-HOST-GUI-IPC-CONTRACT.md). Split delivery after gate: PROG-006A (new GUI-process launch, NotifyIcon host, no-kill singleton) → independent REV-006A; PROG-005B disposable-process test and REV-005B require separate authorization, followed by safe PROG-005 ownership/stop; then PROG-006B full Exit wiring and independent final Review. **No release with dummy Exit or a partially working shutdown.** [Tray contract](../architecture/TRAY-LIFECYCLE-DESIGN.md); PROG-005B/PROG-005/PROG-006B are blocked until safety gates.
4. **State/view separation:** only after tested observations/ownership, decouple `process alive`, `transport ready`, `executor ready`, `last tool success`, `latched fault` from WinForms rendering. Maintain visual acceptance and existing behavior.
5. **Release gates:** cover npx recovery in release tests if previously omitted, reduce unintended source mutation by build preparation, and independently review real UI routes and actual Setup/Portable/update artifacts **on a separately approved candidate**.

**Stop conditions:** any unapproved behavior change, test touching live Remote or sensitive data, undocumented API assumptions, or unverified process termination. Keep main/stable and published packages unchanged. Short instrument/CLI agents require **pre-approved delegated scope and budget** under the updated Playbook; assigning a board task alone isn't permission to launch.

### Playbook bootstrap refresh
Reviewed private Playbook `main@5cae0136c5eb` on 2026-10-23. The mandatory agent entrypoint has been **renamed** to `00_AI_AGENT_IF_YOU_SEE_THIS_READ_IT.md`. New Architect procedure chooses not only functional role but execution mode and sufficient available model/reasoning effort independently; **delegated CLI execution is allowed only within previously authorized scope**. User-project records remain in this repo, never in Playbook.

**Designer queue DES-002 (no active brief):** redesign application/desktop shortcut and future tray icon because the owner finds its current meaning unsatisfactory. Separate Designer + owner discovery should establish metaphor, small-size contrast and Windows light/dark behavior before any assets or code change. [Design intake](../design/README.md).

## Phase C — Secure transport feasibility [NOT YET GO]
1. Check a **supported AI client** and its actual MCP permissions first. The user's ChatGPT Plus plan does not provide documented full personal external MCP write/exec; Codex CLI/local stdio and other eligible clients are separate research paths. Visible plugin/Sites UI is not sufficient.
2. Only when a compatible client has been verified, prove authenticated public HTTPS → harmless fixed-response MCP tool using **that supported client**; never expose privileged local executor for a ping test.
3. Test TLS, token audience/scopes/expiry/revocation, absent/wrong creds, hostile Host/Origin, rate limit, shutdown and reconnect.
4. Define least-privilege tool allowlist, filesystem isolation and manual approval for dangerous operations; independent Reviewer gate.
5. Architect and owner decide GO / NO-GO before implementing provider architecture.

**Earlier evidence:** OpenAI Tunnel Spike 0 BLOCKED by workspace path; Spike 1 local HTTP/stdio PASS; public temporary ping PASS; ChatGPT plugin end-to-end NOT CHECKED. See [results matrix](../research/RESULTS_MATRIX.md).

## Phase D — Provider architecture [NOT STARTED]
After GO only: design/implement ConnectionProvider seam, normalized RdcEvent, health/fault state separation, process ownership, explicit recoverable switching and backwards compatibility. [Architecture](../architecture/OVERVIEW.md).

## Phase E — Security, provider UX and distribution [NOT STARTED]
Protected credential store, pin/provenance for binaries, packaging allowlists, tested migrations/update rollback, human acceptance of GUI and independent regression tests.

## Deferred
zrok/OpenZiti, a multi-device broker and a new execution engine require separate justification/approval; do not build them opportunistically.

The live role/task statuses reside **only** in [COORDINATION/BOARD.md](../../../COORDINATION/BOARD.md); this is strategic sequencing, not a competing task board.
