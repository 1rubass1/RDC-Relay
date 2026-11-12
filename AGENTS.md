# RDC Relay — AI agent entrypoint (development only)

> Methodology: [AI DevBook](https://github.com/1rubass1/AI-DevBook), read-only external `main` (dynamic branch). Verified at commit `5d479bffc663f17aae7f721c89d5f47de8a7ffe6` on 2026-11-13, entry `00_START_HERE.md`, version `0.7-draft`. This is a verified reading checkpoint, **not a permanent pin**; other existing chats are **not automatically updated**.

**Working entry:** open and actually read [`00_START_HERE.md`](https://github.com/1rubass1/AI-DevBook/blob/main/00_START_HERE.md) from the available canonical source before a new AI DevBook work cycle. A filename or this bootstrap is not a substitute for its content.

- For a new working chat **without** a user-assigned role, follow the entrypoint's current role selection; do not infer a role. If the user already assigned a role, preserve it. Role applies to the **chat**, not the whole project.
- Read `CORE/ROLE_COORDINATION.md`, **only** the assigned `ROLES/<ROLE>.md`, and relevant `CORE/` or `WORKFLOWS/` modules. Current software profile is a navigation aid, not a grant of rights. Do not load `ZZ_PLAYBOOK_DEV/` for RDC Relay work.
- Verify the existing [chat registry](COORDINATION/CHAT_REGISTRY.md) before claiming any chat number. Use the established legacy project layout, **not** a parallel `AI Work/` tree without a separate migration approval.
- An Architect may choose roles, execution mode, available model and reasoning effort for a delegated scope; do not run a separate executor without the owner's already-approved scope, tool access and budget. New long-lived specialist chats are opened by the user.
- Store durable decisions and progress in this RDC Relay repository, never in AI DevBook. Updating these project files does not confirm any other chat has re-read its applicable instructions; re-read at its next safe task boundary.
- The prior private `1rubass1/AI-Engineering-Playbook` source was last recorded at `main@5cae0136c5eb0feaea4f00b8ba700199d58803c9` (2026-10-23); its current contents could not be verified during the switch. Old entry `00_AI_AGENT_IF_YOU_SEE_THIS_READ_IT.md` is **not** the new entrypoint.

## RDC Relay working context
1. [PROJECT_INDEX.md](PROJECT_INDEX.md) — project map and source of truth.
2. [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) — current stage.
3. [COORDINATION/BOARD.md](COORDINATION/BOARD.md) — one board for roles, IDs, statuses.
4. [COORDINATION/CHAT_REGISTRY.md](COORDINATION/CHAT_REGISTRY.md) — assigned chat IDs, never reuse numbers.
5. [docs/dev/README.md](docs/dev/README.md) and **only task-relevant documents/source/tests**.

## Hard boundaries
- Work on isolated branches targeting **`development`**. `main`/`stable` are release branches; never merge dev-only coordination, research, Pen/Design or `docs/dev/` into release commits/artifacts.
- **GitHub RDC Relay is PUBLIC, including development branches.** Never commit real keys, tokens, live private endpoints, personal data, private logs or credentials. Protected local backups on STARMER are outside Git.
- Do not stop/restart/logout running Desktop Commander Remote, alter installed RDC Relay, modify router/firewall, expose broad execution tools, or trigger paid APIs without explicit approved scope.
- Start with static inspection and isolated bounded tests. Bound recursive scans/logs; separate PASS/FAIL/NOT CHECKED and validate actual important routes before any release.
- Pin `@wonderwhy-er/desktop-commander@0.2.52` until verified update. Consult original upstream Remote Desktop Commander documentation for engine interaction contracts.
- Follow Windows App Design Guidelines / Fluent 2 for UI/motion/feedback where applicable; obtain owner visual acceptance for subjective changes.
- The project goal is eventually an independent, non-Remote-metered MCP transport with static public IP and existing Remote fallback, but **client permissions and network/security feasibility are separate gates**. No public general shell/file gateway by default.

Store decisions and feedback only in RDC Relay project documents, not in Playbook. No extra spending without authorization.
