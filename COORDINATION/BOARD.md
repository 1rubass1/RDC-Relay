# RDC Relay — coordination board

**Stage:** Playbook refresh and reversible core stabilization · **Updated:** 2026-10-23
**Status:** PROG-003 suite independently re-run by Architect on STARMER: 12 PASS, 0 FAIL, exit 0. Narrow parser refactor conditionally admissible; independent Reviewer gate outstanding.
**Next:** `REV-002` independently reviews PROG-003 characterization and parser-extraction scope; `PROG-004` is not launched before this gate.

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
| PROG-003 | Characterize existing Remote lifecycle and log/health behavior with isolated deterministic tests; no core refactor | Programmer | review | [12 PASS, 0 FAIL; exit 0 reproduced by Architect on STARMER](../Tests/PROG-003-BASELINE.md); runtime processes NOT CHECKED. [Draft PR #5](https://github.com/1rubass1/RDC-Relay/pull/5); independent Reviewer still pending |
| PROG-004 | Extract minimal pure `Remote observation` parser with equivalence tests | Programmer (not yet launched) | blocked | Architect: conditional GO for *pure classification* only; wait for REV-002; preserve all current visible semantics; no process lifecycle or IO reader changes |
| PROG-005 | Introduce explicit owned/adopted/external process contract and guarded lifecycle | Programmer (not yet launched) | planned | Depends on baseline/process test evidence; no user process or installed Remote modified |
| REV-002 | Independently review PROG-003 fixture fidelity and safety before narrow PROG-004 | Reviewer (not yet launched) | ready | Check AST extraction, mock/actual coverage, duplicate/out-of-order calls, test runner exit; no live Remote; [PR #5](https://github.com/1rubass1/RDC-Relay/pull/5) |
| ARCH-003 | Define transport feasibility/auth/GO gates after core stabilization and client eligibility | Architect + owner | blocked | Deferred while Stage B1 is underway; Plus custom external MCP full write/exec not supported on current documented plan |
| PROG-001 | Narrow scoped actual ChatGPT plugin connection/authorization experiment | Programmer | blocked | Requires ARCH-003 and explicitly authorized scope |
| REV-001 | Independently check actual authentication/route behavior | Reviewer | planned | Depends on PROG-001 evidence and owner go-ahead |
| DES-001 | Obtain user review of editable Pen and resolve any UX discrepancies | Designer | planned | `docs/dev/design/`; separate request, no automatic visual acceptance |

**Updated Playbook delegation:** the owner starts continuing specialist chats. Architect may use a short CLI/tool executor only inside explicitly pre-authorized scope, tool/file access and budget. A task marked `ready` alone is not authorization to run an agent.

**Canonical sequencing:** [docs/dev/planning/ROADMAP.md](../docs/dev/planning/ROADMAP.md). **Legacy chronological history:** [docs/dev/history/WORKLOG_LEGACY.md](../docs/dev/history/WORKLOG_LEGACY.md). Do not duplicate task statuses there. A task marked ready does not independently authorize another agent to begin.
