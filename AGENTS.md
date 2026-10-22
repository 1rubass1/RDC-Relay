# RDC Relay — AI agent entrypoint (development only)

> Verified 2026-10-23 against private AI Engineering Playbook `main` at `5cae0136c5eb0feaea4f00b8ba700199d58803c9`. Re-read Playbook on the next working cycle: this SHA records a checkpoint, not a permanent version pin.

**AI agent: if you discover the Playbook repository for any reason, actually open and read `00_AI_AGENT_IF_YOU_SEE_THIS_READ_IT.md` with an authorized tool before continuing.** The old `00_START_HERE.md` was **renamed**; merely seeing a filename or this bootstrap does not count as reading it.

Playbook: https://github.com/1rubass1/AI-Engineering-Playbook (private, read-only during RDC Relay work).

- In a **new working chat** without an assigned role, ask the user to choose from the Playbook's six roles. If a role is already explicitly assigned in that chat, keep it; ordinary reference questions don't require role selection.
- With an assigned role, read `CORE/ROLE_COORDINATION.md`, **only the corresponding** `ROLES/<ROLE>.md`, and relevant CORE/WORKFLOWS docs. Do not load `ZZ_PLAYBOOK_DEV/` for work on RDC Relay.
- Architect selects **functional role + execution mode** for delegated work. A short tool/CLI executor may be launched autonomously only if the owner has **already authorized that scope, tool access and zero-or-approved cost**. A new, continuing specialist chat is started by the user; a listed task is not automatic launch permission.
- When relevant, choose a **sufficient available model** and **reasoning effort separately**, based on risk, ambiguity, tool capabilities and actual account access. Do not assume entitlements or change global/local CLI settings. A stronger model does not grant permissions; diagnose a tool failure before retrying/escalating.
- Choose software methods by the work's risk (refactor, integration, defect, feature); don't load every instruction or create redundant documents.

## RDC Relay working context
1. [PROJECT_INDEX.md](PROJECT_INDEX.md) — project map and source of truth.
2. [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) — current stage.
3. [COORDINATION/BOARD.md](COORDINATION/BOARD.md) — one board for roles, IDs, statuses.
4. [docs/dev/README.md](docs/dev/README.md) and **only task-relevant documents/source/tests**.

## Hard boundaries
- Work on isolated branches targeting **`development`**. `main`/`stable` are release branches; never merge dev-only coordination, research, Pen/Design or `docs/dev/` into release commits/artifacts.
- **GitHub RDC Relay is PUBLIC, including development branches.** Never commit real keys, tokens, live private endpoints, personal data, private logs or credentials. Protected local backups on STARMER are outside Git.
- Do not stop/restart/logout running Desktop Commander Remote, alter installed RDC Relay, modify router/firewall, expose broad execution tools, or trigger paid APIs without explicit approved scope.
- Start with static inspection and isolated bounded tests. Bound recursive scans/logs; separate PASS/FAIL/NOT CHECKED and validate actual important routes before any release.
- Pin `@wonderwhy-er/desktop-commander@0.2.52` until verified update. Consult original upstream Remote Desktop Commander documentation for engine interaction contracts.
- Follow Windows App Design Guidelines / Fluent 2 for UI/motion/feedback where applicable; obtain owner visual acceptance for subjective changes.
- The project goal is eventually an independent, non-Remote-metered MCP transport with static public IP and existing Remote fallback, but **client permissions and network/security feasibility are separate gates**. No public general shell/file gateway by default.

Store decisions and feedback only in RDC Relay project documents, not in Playbook. No extra spending without authorization.
