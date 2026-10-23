# RDC Relay — coordination board

**Stage:** Playbook refresh and reversible core stabilization · **Updated:** 2026-10-23
**Status:** PROG-003 isolated characterization fixtures executed on STARMER (12 PASS, 0 FAIL); production source and running Remote unchanged. Independent review pending.
**Next:** Architect reviews PROG-003 baseline evidence and remaining live-route risks; PROG-004 not authorized to start.

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
| ARCH-004 | Sanitize, classify, migrate original records; verify links, archive, no release effect, merge only to `development` | Architect | done | [PR #1](https://github.com/1rubass1/RDC-Relay/pull/1) merged as `20b938b`; 10 local backup + 4 design-source SHA256 checks, link/secret scan PASS; local pointers created; existing v1.5.18 Portable 12 entries clean |
| ARCH-012 | Update RDC Relay to latest Playbook entrypoint and delegated-execution rules | Architect | review | Private Playbook `main@5cae0136c5eb`; renamed agent entrypoint, mode/model selection, permission and budget guardrails; this isolated docs branch |
| ARCH-013 | Stage owner-approved incremental behavior-preserving core-refactor plan | Architect | review | [Roadmap Stage B1](../docs/dev/planning/ROADMAP.md), [ADR-004](../DECISIONS.md); no product source changes |
| PROG-003 | Characterize existing Remote lifecycle and log/health behavior with isolated deterministic tests; no core refactor | Programmer | review | [12 PASS, 0 FAIL; real-process routes NOT CHECKED](../Tests/PROG-003-BASELINE.md); [isolated fixture](../Tests/Test-RemoteCharacterization.ps1), branch `tests/prog-003-remote-lifecycle-baseline`; Architect contract review pending |
| PROG-004 | Extract minimal pure `Remote observation` parser with equivalence tests | Programmer (not yet launched) | planned | Depends on PROG-003 and Architect contract review; no GUI behavior change |
| PROG-005 | Introduce explicit owned/adopted/external process contract and guarded lifecycle | Programmer (not yet launched) | planned | Depends on baseline/process test evidence; no user process or installed Remote modified |
| REV-002 | Independent regression/safety review of characterized behaviors and any refactor before release | Reviewer (not yet launched) | planned | Compare real routes versus fixtures and actual candidate; no self-approval |
| ARCH-003 | Define transport feasibility/auth/GO gates after core stabilization and client eligibility | Architect + owner | blocked | Deferred while Stage B1 is underway; Plus custom external MCP full write/exec not supported on current documented plan |
| PROG-001 | Narrow scoped actual ChatGPT plugin connection/authorization experiment | Programmer | blocked | Requires ARCH-003 and explicitly authorized scope |
| REV-001 | Independently check actual authentication/route behavior | Reviewer | planned | Depends on PROG-001 evidence and owner go-ahead |
| DES-001 | Obtain user review of editable Pen and resolve any UX discrepancies | Designer | planned | `docs/dev/design/`; separate request, no automatic visual acceptance |

**Updated Playbook delegation:** the owner starts continuing specialist chats. Architect may use a short CLI/tool executor only inside explicitly pre-authorized scope, tool/file access and budget. A task marked `ready` alone is not authorization to run an agent.

**Canonical sequencing:** [docs/dev/planning/ROADMAP.md](../docs/dev/planning/ROADMAP.md). **Legacy chronological history:** [docs/dev/history/WORKLOG_LEGACY.md](../docs/dev/history/WORKLOG_LEGACY.md). Do not duplicate task statuses there. A task marked ready does not independently authorize another agent to begin.
