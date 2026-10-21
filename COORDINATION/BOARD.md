# RDC Relay — coordination board

**Stage:** Playbook onboarding and guarded transport feasibility · **Updated:** 2026-10-21
**State:** Documentation bootstrap checked in isolation; external-account transport and authentication gates unresolved.
**Next:** `ARCH-002` — owner decision on canonical strategic-document storage.

## Functional roles and ownership
| Role | Responsibility | Change boundaries |
| --- | --- | --- |
| **Architect** (assigned in current chat) | Contracts, architecture, priorities, decisions, task splitting and integration | Does not silently implement product features or release |
| **Programmer** (planned; not started) | Approved isolated protocol work, product code, regression tests, build | Do not touch active Remote, production runtime or public executor until gated |
| **Designer** (planned when UX is needed) | Editable Pen UX source, visual states and review with owner | No runtime/UI implementation or automatic approval of appearance |
| **Reviewer** (planned for security/release gates) | Independent verification on identified artifacts, meaningful alternate routes | No unverified PASS; does not self-approve risky transport |

## Assigned work (single status authority)
| ID | Verifiable outcome | Role / owner | Status | Evidence or blocker |
| --- | --- | --- | --- | --- |
| **ARCH-001** | Playbook bootstrap (`AGENTS`, index, context, decisions, coordination board) staged in isolated branch; no product changes | Architect / this chat | done | Local `docs/playbook-onboarding`; files staged and diff reviewed |
| **ARCH-002** | Owner chooses **one** canonical versioned home for existing strategic docs and preservation of old paths | Architect + owner | ready | See proposal in `DECISIONS.md`; do not move originals before approval |
| **ARCH-003** | Approve narrow transport feasibility criteria, threat boundary and GO/NO-GO plan | Architect + owner | planned | Based on local `SPIKE_1_DIRECT_HTTPS_MCP.md`; never treat ping as secured executor |
| **PROG-001** | Implement only authorized isolated feasibility probe and measured test report | Programmer (not engaged) | blocked | Depends on `ARCH-003` and explicit test scope; no production refactor |
| **DES-001** | Human review of current editable Pen reference and any targeted corrections | Designer (not engaged) | planned | Local `Design\RDC-Relay-UI-Layout.pen`; requires owner visual feedback |
| **REV-001** | Independently validate transport security/route behavior before provider design GO | Reviewer (not engaged) | planned | Depends on actual authorized end-to-end evidence from `PROG-001` |

## Routing
- Overall product phases: local `E:\Projects\GitSync\RDC\ROADMAP.md` — do not copy its phase checklist here.
- Chronological experiment and release facts: local `E:\Projects\GitSync\RDC\WORKLOG.md` — not task statuses.
- Keep the `stable` release branch untouched. An item marked `ready` is **not** permission for another agent to begin without owner assignment.
- Acceptance: actual changed files/commit and source links for `ARCH-001`; explicit owner decision for `ARCH-002`; isolated successful authenticated end-to-end plus negative tests for transport gates.
