# RDC Relay — current roadmap

> Reconciled 2026-10-22. Old roadmap contained outdated v1.5.12/v1.5.16 baseline and obsolete “NEXT Spike 0”. It is preserved [as history](../history/ROADMAP_LEGACY.md), not a current instruction.

## Phase A — Production baseline [DONE]
RDC Relay v1.5.18 released 2026-10-20, commit `5b1fdf58a8873d6cd781b0a835f8e208eb46dbfb` on `main`/`stable`. Pinned upstream `@wonderwhy-er/desktop-commander@0.2.52`. Existing regression and release-gate evidence is in CHANGELOG and historical worklog; no fresh runtime test claimed here.

## Phase B — Playbook governance [CURRENT]
- Store Playbook routing, assigned roles, coordinated task IDs, context, decisions and design/research documents in the **development branch only**.
- Back up source records; import sanitized material into classified folders.
- Verify links, preserved sources and packaging exclusion. No product code/runtime changes.

## Phase C — Secure transport feasibility [NOT YET GO]
1. Verify actual ChatGPT custom MCP/Sites account rights, not merely visibility of a creation button.
2. Prove authenticated public HTTPS → harmless fixed-response MCP tool via **actual ChatGPT account**.
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
