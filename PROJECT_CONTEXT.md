# RDC Relay — current development context

> Updated: 2026-10-23. Source: existing product history, 2026-10-23 static audit, owner-approved next stage and current private Playbook GitHub main.

**Stage:** Playbook governance and classified knowledge migration completed on `development` via PR #1 (merge `20b938b`). `main` and `stable` remain production-only.

**Production baseline:** Published RDC Relay **v1.5.18**, commit `5b1fdf58a8873d6cd781b0a835f8e208eb46dbfb`; `main`/`stable` remain unchanged. Pinned Desktop Commander Remote v0.2.52; existing live client/process **not restarted** by documentation work.

**Documents:** Index, context, decisions and board in dev branch root; sanitized classified docs at `docs/dev/`. Byte-identical local backup under STARMER `_archive/pre-playbook-2026-10-22`; ten old Markdown paths now point to the dev knowledge base. Three historical tunnel IDs and Pen account placeholders redacted from public Git copies. The original Pen working file remains local for the active editor. Public `development` is not a secret store.

**Experimental transport:** Local HTTP/stdio fixture and temporary public HTTPS ping-only succeeded; full authenticated ChatGPT owner's-account plugin invocation and scoped executable tool path **NOT CHECKED**. Secure MCP Tunnel workspace access BLOCKED; production OAuth/isolation/reconnect gates pending. Do not start v1.6 provider refactor until evidence and owner GO.

**UI reference:** Editable Pen v1.5.18 reference imported into `docs/dev/design/`; technical geometry review occurred 2026-10-21. User aesthetic acceptance was not newly requested as part of migration.

**Current approvals:** Architect role explicitly assigned for this chat. User approved moving and restructuring docs into Git under Playbook and excluding dev-only/sensitive material from releases. No authorization to publish product or alter running Remote is inferred.

**Verification:** 10 preserved document backup hashes and 4 design source hashes match their manifest values; internal current-document links resolved; committed Markdown and Pen patterns scanned without known credential/email hits; `git diff --check` passed. Current `main`/`stable` tree excludes dev paths; inspected packaging allowlist, and existing v1.5.18 Portable ZIP excluded dev records (12 entries). New Setup build **NOT CHECKED**; no runtime process was stopped.

**Playbook refresh (2026-10-23):** private `1rubass1/AI-Engineering-Playbook` `main@5cae0136c5eb` was directly read. Entry point renamed **`00_AI_AGENT_IF_YOU_SEE_THIS_READ_IT.md`**; old `00_START_HERE.md` is gone. The Architect now considers delegated executor *mode*, sufficient *available model* and *reasoning effort* separately, with **explicit prior scope/tool/budget authorization** required to run short CLI executors. Project bootstrap/roadmap/board were updated on isolated `docs/playbook-refresh-2026-10-23` branch; merge to `development` is pending.

**Core plan approval:** owner agreed to gradually strengthen the existing core before introducing a new provider. [ADR-004](DECISIONS.md), [Roadmap Stage B1](docs/dev/planning/ROADMAP.md) and `PROG-003` describe a no-behavior-change characterization-first cycle. [System audit PR #3](https://github.com/1rubass1/RDC-Relay/pull/3) and [transport strategy PR #2](https://github.com/1rubass1/RDC-Relay/pull/2) remain separate **drafts**, not merged/approved implementation.

**Next step:** After this docs PR is reviewed and integrated into `development`, owner may launch the **Programmer** role for `PROG-003`: isolated baseline characterization of process/log/health contracts, without source refactoring or touching live Remote. Core implementation and independent Reviewer gates follow only on actual evidence; public HTTP/auth experiments remain deferred.

**Checkpoint evidence:** Playbook files read from connected GitHub; staged project documents edited via connected GitHub. No new runtime test, UI acceptance, full release build, native connector E2E, user process stop or public port change claimed. STARMER connection was unresponsive while writing the local draft; the GitHub branch is the authoritative submitted snapshot pending local reconciliation.

**Main unresolved risk:** Public Git dev branch must never store actual sensitive data; existing release packaging uses explicit allowlisted payload, but every release artifact must still be checked.

**Work status:** [COORDINATION/BOARD.md](COORDINATION/BOARD.md) · **Plan:** [docs/dev/planning/ROADMAP.md](docs/dev/planning/ROADMAP.md).
