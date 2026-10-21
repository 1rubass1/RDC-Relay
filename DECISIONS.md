# RDC Relay — adopted engineering decisions

## RDC-ADR-001 — AI Engineering Playbook governance
**Accepted:** 2026-10-21, user. RDC Relay agents follow private AI Engineering Playbook read-only; role selection is per working chat. Architect owns architecture and cross-role coordination; Programmer, Designer and Reviewer join for their genuinely assigned scopes. Current task status is [COORDINATION/BOARD.md](COORDINATION/BOARD.md), not the historical worklog.

**Reason:** Durable handoff, clear responsibility and evidence-based reviews with minimum bureaucracy.

## RDC-ADR-002 — Versioned, classified project knowledge
**Accepted:** 2026-10-22, user. Consolidate relevant project documentation into the **existing** RDC Relay GitHub repository following the Playbook's `PROJECT_INDEX`, `PROJECT_CONTEXT`, `DECISIONS`, `COORDINATION/BOARD` structure and categorized `docs/dev`. Keep only **one editable authoritative current** location for each fact. Reconcile stale roadmap/status notes; preserve source documents as frozen, clearly non-authoritative history.

**Reason:** Agents operating from GitHub should be able to recover state without local-only STARMER notes. Migration preserves byte-exact originals locally and includes sanitized copies for historical traceability. The dev documentation is a change to development workflow, not application behavior.

## RDC-ADR-003 — Dev-only branch and release/data boundary
**Accepted:** 2026-10-22, user. Use long-lived `development` branch since `develop/*` exists and Git cannot contain both refs. The project knowledge base and Pen design belong **only to development branches**; `main`/`stable` release commits and release artifacts must exclude them. Release preparation must select shippable files explicitly, not merge development wholesale.

**Security qualification:** RDC Relay GitHub is **public**, so development branches are public. No real credentials, private tunnel IDs, active endpoints, sensitive user/device/account data or unredacted logs in any Git branch. Such material stays in authorized protected local stores. Existing `Scripts/build-release.ps1` explicitly whitelists product payload; validate built artifacts before every release.

## Pending architectural decisions
- Whether ChatGPT custom MCP / Sites can securely access the owner's environment: actual entitlement and authenticated end-to-end route unproven.
- Provider architecture and concrete auth/transport choices remain conditional on a controlled GO/NO-GO research gate, not endorsed by migration.
