# RDC Relay — current development context

> Updated: 2026-10-22. Source: production Git metadata and local strategic records on STARMER.

**Stage:** Playbook governance and classified knowledge migration completed on `development` via PR #1 (merge `20b938b`). `main` and `stable` remain production-only.

**Production baseline:** Published RDC Relay **v1.5.18**, commit `5b1fdf58a8873d6cd781b0a835f8e208eb46dbfb`; `main`/`stable` remain unchanged. Pinned Desktop Commander Remote v0.2.52; existing live client/process **not restarted** by documentation work.

**Documents:** Index, context, decisions and board in dev branch root; sanitized classified docs at `docs/dev/`. Byte-identical local backup under STARMER `_archive/pre-playbook-2026-10-22`; ten old Markdown paths now point to the dev knowledge base. Three historical tunnel IDs and Pen account placeholders redacted from public Git copies. The original Pen working file remains local for the active editor. Public `development` is not a secret store.

**Experimental transport:** Local HTTP/stdio fixture and temporary public HTTPS ping-only succeeded; full authenticated ChatGPT owner's-account plugin invocation and scoped executable tool path **NOT CHECKED**. Secure MCP Tunnel workspace access BLOCKED; production OAuth/isolation/reconnect gates pending. Do not start v1.6 provider refactor until evidence and owner GO.

**UI reference:** Editable Pen v1.5.18 reference imported into `docs/dev/design/`; technical geometry review occurred 2026-10-21. User aesthetic acceptance was not newly requested as part of migration.

**Current approvals:** Architect role explicitly assigned for this chat. User approved moving and restructuring docs into Git under Playbook and excluding dev-only/sensitive material from releases. No authorization to publish product or alter running Remote is inferred.

**Verification:** 10 preserved document backup hashes and 4 design source hashes match their manifest values; internal current-document links resolved; committed Markdown and Pen patterns scanned without known credential/email hits; `git diff --check` passed. Current `main`/`stable` tree excludes dev paths; inspected packaging allowlist, and existing v1.5.18 Portable ZIP excluded dev records (12 entries). New Setup build **NOT CHECKED**; no runtime process was stopped.

**Owner's clarified requirement (2026-10-22):** Provide a self-hosted, no-metered-Remote-call alternative for AI→local DesktopCommanderMCP, using an available static public IP for direct HTTPS where safe. Existing hosted Remote stays as fallback; alternative services may be added if useful. The previous review underrated this core motivation and has been corrected.

**New account constraint (2026-10-22):** Owner reviewed official requirements and confirmed ChatGPT Plus cannot register a full-featured external custom MCP connection. Official Help lists full custom MCP for Business/Enterprise/Edu (Pro limited to read/fetch). Plugin and Sites packaging do not confer missing account privileges. Hence ChatGPT Plus → own public-IP HTTPS MCP is **PLAN-LEVEL NO-GO** at present; no account UI end-to-end trial was claimed.

**Next step:** Review [updated assessment](docs/dev/architecture/ARCHITECTURE_REVIEW_2026-10-22.md), task ARCH-005. Preserve self-host independence as a long-term goal, but select a supported client (e.g. local Codex CLI + stdio MCP within plan limits) before network-facing gateway development. **No public port or runtime code touched**. Revised strategy awaits owner approval.

**Main unresolved risk:** Public Git dev branch must never store actual sensitive data; existing release packaging uses explicit allowlisted payload, but every release artifact must still be checked.

**Work status:** [COORDINATION/BOARD.md](COORDINATION/BOARD.md) · **Plan:** [docs/dev/planning/ROADMAP.md](docs/dev/planning/ROADMAP.md).
