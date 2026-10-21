# RDC Relay — current development context

> Updated: 2026-10-22. Source: production Git metadata and local strategic records on STARMER.

**Stage:** Adopt Playbook governance and migrate/sanitize development documents. `docs/playbook-onboarding` is a documentation-only branch intended for the `development` integration branch.

**Production baseline:** Published RDC Relay **v1.5.18**, commit `5b1fdf58a8873d6cd781b0a835f8e208eb46dbfb`; `main`/`stable` remain unchanged. Pinned Desktop Commander Remote v0.2.52; existing live client/process **not restarted** by documentation work.

**Documents:** Index, context, decisions and role coordination at repository root (development only); sanitized classified docs at `docs/dev/`. Exact original local root notes backed up to STARMER `_archive/pre-playbook-2026-10-22`. Three actual-looking tunnel IDs in prior Spike 0 have been redacted in Git copies. `development` is not private: public GitHub branch.

**Experimental transport:** Local HTTP/stdio fixture and temporary public HTTPS ping-only succeeded; full authenticated ChatGPT owner's-account plugin invocation and scoped executable tool path **NOT CHECKED**. Secure MCP Tunnel workspace access BLOCKED; production OAuth/isolation/reconnect gates pending. Do not start v1.6 provider refactor until evidence and owner GO.

**UI reference:** Editable Pen v1.5.18 reference imported into `docs/dev/design/`; technical geometry review occurred 2026-10-21. User aesthetic acceptance was not newly requested as part of migration.

**Current approvals:** Architect role explicitly assigned for this chat. User approved moving and restructuring docs into Git under Playbook and excluding dev-only/sensitive material from releases. No authorization to publish product or alter running Remote is inferred.

**Next step:** Verify imported documentation, secret redaction, local archive hashes, Git diff and release build inclusion rules; then merge documentation PR to `development` only. Afterwards prepare transport feasibility criteria and handoff, subject to scope/role assignment.

**Main unresolved risk:** Public Git dev branch must never store actual sensitive data; existing release packaging uses explicit allowlisted payload, but every release artifact must still be checked.

**Work status:** [COORDINATION/BOARD.md](COORDINATION/BOARD.md) · **Plan:** [docs/dev/planning/ROADMAP.md](docs/dev/planning/ROADMAP.md).
