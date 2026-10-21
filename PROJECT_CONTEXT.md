# RDC Relay — current project context

> Updated: 2026-10-21. Evidence baseline: STARMER project documents and clean local Git working tree examined before this documentation branch.

**Current objective:** Introduce AI Engineering Playbook governance without changing production code or live Remote processes; then complete security and account-feasibility gates before considering provider expansion.

**Known product state:**
- Published baseline: **v1.5.18**, commit `5b1fdf58a8873d6cd781b0a835f8e208eb46dbfb`. `stable` is the release channel; no production cutover is part of this work.
- STARMER checkout `E:\Projects\GitSync\RDC\RDC-Relay Work` was on clean `main` at that commit before creating isolated `docs/playbook-onboarding`.
- Runtime still uses the pinned Desktop Commander Remote `@wonderwhy-er/desktop-commander@0.2.52`.
- STARMER Pen UI layout `Design\RDC-Relay-UI-Layout.pen` was updated on 2026-10-21; last recorded export/technical geometry review is **not** a claim of user visual acceptance.

**Transport evidence (latest local records, 2026-10-20):**
- OpenAI Secure MCP Tunnel / ChatGPT account connection: **BLOCKED / not proven**.
- Isolated local MCP Streamable HTTP and HTTP→stdio fixed-fixture bridge: **PASS**.
- Isolated temporary public HTTPS ping-only MCP and synthetic Bearer rejection: **PASS**; temporary test tunnel stopped.
- Actual ChatGPT custom MCP plugin registration/tool invocation on the owner's account: **NOT CHECKED**.
- Production OAuth 2.1, least-privilege public gateway, fault/reconnect gates: **NOT CHECKED**.
- No arbitrary local executor tools may be exposed by these experiments.

**Constraints:** Preserve live Desktop Commander sessions, existing installation, production `stable` branch and rollback paths. Do not start the 1.6 provider refactor prematurely. Budget for new services: 0 until approved.

**Current coordination:** See [COORDINATION/BOARD.md](COORDINATION/BOARD.md). Architect is assigned in the present user conversation. Other role work is planned, not silently launched.

**Unresolved architecture decision:** Should the strategic documents currently stored only outside Git be migrated (with old-path pointers) into the product repo, or versioned in a separate documentation repo? Recommendation and trade-off in `ARCH-002`; no source migration yet.

**Next architectural step:** Validate and obtain approval for the documentation source-of-truth consolidation, then issue a narrowly scoped, security-gated feasibility assignment before any provider implementation.
