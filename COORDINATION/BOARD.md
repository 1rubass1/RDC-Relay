# RDC Relay — coordination board

**Stage:** Playbook migration and secured-transport research · **Updated:** 2026-10-22
**Status:** Dev documentation migration authored; integration and validation pending.
**Next:** `ARCH-004` verify, integrate documentation to `development` only.

## Roles and ownership
| Role | Responsibility | Boundaries |
| --- | --- | --- |
| **Architect** — assigned in this chat | Contracts, decisions, role coordination, document governance, integration gates | No runtime implementation, spontaneous release or unsafe account changes |
| **Programmer** — planned, not launched | Isolated approved connector tests, code, builds | Never expose broad local executor to public ingress; preserve live Remote |
| **Designer** — planned, not launched | Pen UX source, layout and user visual review | Not the product code implementation owner |
| **Reviewer** — planned, not launched | Independent transport/auth and release verification | Does not mark untested routes PASS |

## Tasks (single source of truth)
| ID | Checkable outcome | Role | Status | Evidence / dependency |
| --- | --- | --- | --- | --- |
| ARCH-001 | Introduce Playbook roles, index, context, decisions and board on isolated branch | Architect | done | Documentation branch initial commit `d93e711` |
| ARCH-002 | Owner selects canonical project knowledge storage and dev-only distribution policy | Architect + owner | done | Owner approval; `DECISIONS.md` ADR-002 and ADR-003 |
| ARCH-004 | Sanitize, classify, migrate original records; verify links, archive, no release effect, merge only to `development` | Architect | in_progress | `docs/dev/`; local backup; Git diff and checks pending |
| ARCH-003 | Define transport feasibility/auth/GO gates and roles for next cycle | Architect + owner | ready | [Research matrix](../docs/dev/research/RESULTS_MATRIX.md); no executor release |
| PROG-001 | Narrow scoped actual ChatGPT plugin connection/authorization experiment | Programmer | blocked | Requires ARCH-003 and explicitly authorized scope |
| REV-001 | Independently check actual authentication/route behavior | Reviewer | planned | Depends on PROG-001 evidence and owner go-ahead |
| DES-001 | Obtain user review of editable Pen and resolve any UX discrepancies | Designer | planned | `docs/dev/design/`; separate request, no automatic visual acceptance |

**Canonical sequencing:** [docs/dev/planning/ROADMAP.md](../docs/dev/planning/ROADMAP.md). **Legacy chronological history:** [docs/dev/history/WORKLOG_LEGACY.md](../docs/dev/history/WORKLOG_LEGACY.md). Do not duplicate task statuses there. A task marked ready does not independently authorize another agent to begin.
