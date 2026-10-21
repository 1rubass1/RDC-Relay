# RDC Relay — project index

**Purpose:** Windows UI and lifecycle supervisor for `@wonderwhy-er/desktop-commander` Remote, evolving toward safe alternative MCP connectivity without replacing the working local execution engine.

**Product Git repository:** https://github.com/1rubass1/RDC-Relay (`RDC-Relay Work` on STARMER).
**Engineering methodology:** private https://github.com/1rubass1/AI-Engineering-Playbook (read-only for RDC work).
**Local strategy/research root:** `E:\Projects\GitSync\RDC\` (outside this Git repository).
**Development machine:** STARMER.

## Start / authority
- [AGENTS.md](AGENTS.md) — Playbook-based agent entry and guardrails.
- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) — concise stage snapshot.
- [COORDINATION/BOARD.md](COORDINATION/BOARD.md) — **single source of truth for assigned task IDs, ownership, and statuses**. Links to the roadmap; does not duplicate its phase checklist.
- [DECISIONS.md](DECISIONS.md) — adopted long-term decisions; unresolved alternatives remain proposals.
- [README.md](README.md), [CHANGELOG.md](CHANGELOG.md) — product operation and released history.

## Existing authoritative materials on STARMER
These are **not committed to this repository yet**. Read them at the exact paths below; do not assume a new agent without STARMER can access them.

| Area | Canonical local source | Role |
| --- | --- | --- |
| Stable project identity / restrictions | `E:\Projects\GitSync\RDC\HANDOFF.md` | Stable handoff and known baseline |
| Current investigative/working state | `E:\Projects\GitSync\RDC\WORKLOG.md` | Time-ordered factual work history (not the role/task board) |
| Development priorities | `E:\Projects\GitSync\RDC\ROADMAP.md` | Phases, dependencies and feature priorities |
| Intended provider architecture | `E:\Projects\GitSync\RDC\TECHNICAL_DESIGN.md` | Proposed contracts; not proof of implementation |
| Verified external references | `E:\Projects\GitSync\RDC\SOURCES.md` | Sources and their verification dates |
| Secure MCP Tunnel feasibility | `E:\Projects\GitSync\RDC\SPIKE_0_OPENAI_TUNNEL.md` | Earlier blocked approach |
| Direct HTTPS MCP feasibility | `E:\Projects\GitSync\RDC\SPIKE_1_DIRECT_HTTPS_MCP.md` | Isolated experiment, results and security gates |
| ChatGPT plugin access questions | `E:\Projects\GitSync\RDC\CHATGPT_PLUGIN_UI_REVIEW_2026-10-20.md` | UI evidence vs actual account permissions |
| Editable UI reference | `E:\Projects\GitSync\RDC\Design\README.md` and `Design\RDC-Relay-UI-Layout.pen` | Pen model, geometry, human visual acceptance |

## Product map
| Area | Path |
| --- | --- |
| Runtime GUI and supervisor | [Source/](Source/) (especially `remote-window.ps1`, `update-notice.ps1`) |
| Shaders, icon | [Source/](Source/) and [Assets/](Assets/) |
| Setup and portable launcher | [Installer/](Installer/) |
| Release pipeline | [Scripts/](Scripts/) |
| Automated regression tests | [Tests/](Tests/) |
| Isolated connectivity research | STARMER `E:\Projects\GitSync\RDC\_experiments\direct-https-mcp\` |

## Navigation and non-duplication
`ROADMAP.md` owns overall **feature sequencing**; `WORKLOG.md` owns chronological **observations**; the coordination board owns **current task status and role assignment**. Update only the source relevant to the change. The repo does not currently mirror all local strategic files: this cross-machine continuity risk is tracked as `ARCH-002`, not silently resolved by creating copies.
