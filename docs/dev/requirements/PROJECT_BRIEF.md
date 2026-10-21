# RDC Relay — product brief

**Status:** requirements reconstructed from current documentation, 2026-10-22. Future provider details remain proposals until approved.

## Purpose and existing product
RDC Relay is a Windows 10/11 GUI launcher, status monitor and lifecycle supervisor of the official `@wonderwhy-er/desktop-commander` Remote. Requirements: PowerShell 5.1, Node.js 18+, pinned upstream Remote package v0.2.52. Production v1.5.18 has a per-user installer, portable mode, transactional updates with rollback, account/device management, readiness and tool activity states, recovery, GUI tests and human review of appearance. Current update channel: `stable`.

## Long-term goal
Add **secure selectable connection providers** while continuing to use DesktopCommanderMCP as the local execution engine. OpenAI Secure MCP Tunnel and authenticated direct HTTPS MCP are feasibility candidates. Eliminating dependency on Remote service quotas is a motivation, not an assurance of zero costs or unlimited access.

## Non-negotiable constraints
- Preserve working Remote, its state machine, tested UI and safe transactional updater. No wholesale rewrite.
- No public arbitrary filesystem/shell tools without OAuth/authorization, least privilege, negative tests, human approval where needed, and independent review.
- Begin with harmless ping/fixed-fixture protocols in isolated experiments, then prove actual account ChatGPT end-to-end.
- Never expose runtime tokens, credentials, live private endpoints, secrets or personal data in code, logs or Git.
- No new external spending without approval; do not stop existing Remote or reconfigure production without explicit authorization.
- UI subjective adjustments require user review; technical defects use targeted verification and applicable Windows App Design / Fluent 2 conventions.
- Project design, research and coordination documents are **dev-only**, never release payload.

## Next phase acceptance
Successful authenticated ChatGPT-to-harmless-MCP tool path on the owner's actual account; documented negative auth/reconnect, isolated tool permissions and GO/NO-GO decision. Existing public ping PASS is insufficient.

Source: [product README](../../../README.md), [release history](../../../CHANGELOG.md), [roadmap](../planning/ROADMAP.md), [evidence](../research/RESULTS_MATRIX.md). Frozen old requirements are preserved in [HANDOFF legacy](../history/HANDOFF_LEGACY.md), not authoritative for tasks.
