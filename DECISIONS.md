# RDC Relay — engineering decisions

## RDC-ADR-001 — Adopt AI Engineering Playbook
**Status:** Accepted by project owner, 2026-10-21.
**Scope:** AI-assisted development process, not runtime application architecture.

**Decision:** RDC Relay development uses the private `1rubass1/AI-Engineering-Playbook` as the read-only methodology. The owner assigns agent roles per chat. An Architect coordinates requirements, role ownership, gates, handoffs and substantial design decisions; implementation and independent verification belong to their designated specialists when engaged. Active roles and task states are visible through `COORDINATION/BOARD.md`.

**Rationale:** Reduce rediscovery of context, unreviewed architectural drift, role confusion and unverified releases while allowing lightweight work on small changes.

**Consequences:** Maintain only necessary project documents, use actual evidence for tests, keep Playbook itself unchanged, and avoid auto-launching other agents or approving unresolved high-impact decisions.

## Open decision — where strategic project documents should be versioned
**Status:** Proposal only; requires owner approval (`ARCH-002`).

**Problem:** The product code is in a Git repository, but the canonical `HANDOFF`, `WORKLOG`, `ROADMAP`, `TECHNICAL_DESIGN`, `SOURCES` and spikes are at `E:\Projects\GitSync\RDC\` outside the checkout. A GitHub-only agent cannot restore their content.

**Recommendation:** Move the canonical Markdown documents into a dedicated `docs/project/` subtree of the **existing product repository**, preserving content and history where available. Keep small pointer files at old paths for local tooling until references are updated. Do **not** keep two editable authoritative copies. Alternative: separate documentation repository (more access/configuration/coordination overhead). No migration or deletion performed pending approval.
