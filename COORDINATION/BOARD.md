# RDC Relay — coordination board

**Stage:** Playbook refresh and reversible core stabilization · **Updated:** 2026-10-23
**Status:** REV-002 independent review: CONDITIONAL PASS for PROG-003 characterization only. Reviewer independently re-ran fixture on STARMER: 12 PASS, 0 FAIL, exit 0. Mandatory parser-boundary cases are still missing; PROG-004 remains blocked pending their completion/re-review.
**Next:** Programmer adds isolated pre-refactor characterization cases listed in REV-002 notes below; Reviewer verifies baseline; Architect then decides whether to unblock the narrow PROG-004 parser extraction.

## REV-002 — independent findings (2026-10-23)

- **Verdict: CONDITIONAL PASS** for the narrow, isolated PROG-003 baseline; **not GO for PROG-004 yet**. Reviewer executed `Tests/Test-RemoteCharacterization.ps1` independently on STARMER: **12 PASS, 0 FAIL, exit 0**; working tree was clean at inspection. Static cross-check against `Source/remote-window.ps1` confirms that AST extraction tests the real definitions of 20 selected functions, but **not** the actual file reader, GUI tick, adoption/start/stop or upstream event delivery.
- **Mandatory before PROG-004:** add *pre-refactor* equivalence fixtures for (1) duplicate start/completion/failure markers and overlapping calls, including completion-before-start, failure-after-success and zero-count completion, asserting fault/ready/activity/log/flash side effects; (2) exact boundary/near-match/embedded markers and non-JSON tool-output text carrying `Channel error:`/Presence, plus conflicting lifecycle messages in both orders; (3) byte/line/chunk-delivery representations of representative Unicode emoji and CRLF from a synthetic UTF-8 source, or explicitly constrain PROG-004 to parsed complete strings and assert that the reader remains unchanged; (4) startup/live transition, marker-free runtime episodes, and max-length/ring ordering; (5) fail-fast runner sanity (intentional failing assertion in an isolated disposable copy must yield a nonzero exit and ensure an expected minimum test count). Capture existing semantics, including anomalies; do **not** silently fix behavior during parser extraction.
- **Mock blind spots:** fake `Stop-Remote` bypasses `taskkill`, adoption and PID identity, and fake `Read-LiveLog` bypasses `Open-Reader`, rotation, encoding and log sharing. `Render-CompactLog` and WinForms effects are stubbed; success here is **not** safety proof for lifecycle, I/O or UI. Current string recognizer uses substring health matching and marker count rather than tool IDs; out-of-order outcomes can therefore change ready/fault states. Treat these as risks requiring regression capture, not as approved behavioral fixes.
- **Defer to separate isolated scopes:** real owned/adopted/external process-tree termination and stale PID, real upstream delivery and concurrency, log rotation/backlog under OS file sharing, real WinForms routes and packaged Setup/Portable acceptance. These remain **NOT CHECKED**; block process-lifecycle work / release, but not a strictly pure classifier extraction after the mandatory characterization cases pass. Do not touch running Remote, installed product or production branches.

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
| REV-002 | Independently review PROG-003 fixture fidelity and safety before narrow PROG-004 | Reviewer | done | **CONDITIONAL PASS** (characterization only); independent STARMER PowerShell 5.1 12 PASS / 0 FAIL / exit 0; source/static/fixture review completed. PROG-004 remains blocked on missing mandatory cases noted below. No live process touched; [PR #5](https://github.com/1rubass1/RDC-Relay/pull/5). |
| ARCH-003 | Define transport feasibility/auth/GO gates after core stabilization and client eligibility | Architect + owner | blocked | Deferred while Stage B1 is underway; Plus custom external MCP full write/exec not supported on current documented plan |
| PROG-001 | Narrow scoped actual ChatGPT plugin connection/authorization experiment | Programmer | blocked | Requires ARCH-003 and explicitly authorized scope |
| REV-001 | Independently check actual authentication/route behavior | Reviewer | planned | Depends on PROG-001 evidence and owner go-ahead |
| DES-001 | Obtain user review of editable Pen and resolve any UX discrepancies | Designer | planned | `docs/dev/design/`; separate request, no automatic visual acceptance |

**Updated Playbook delegation:** the owner starts continuing specialist chats. Architect may use a short CLI/tool executor only inside explicitly pre-authorized scope, tool/file access and budget. A task marked `ready` alone is not authorization to run an agent.

**Canonical sequencing:** [docs/dev/planning/ROADMAP.md](../docs/dev/planning/ROADMAP.md). **Legacy chronological history:** [docs/dev/history/WORKLOG_LEGACY.md](../docs/dev/history/WORKLOG_LEGACY.md). Do not duplicate task statuses there. A task marked ready does not independently authorize another agent to begin.
