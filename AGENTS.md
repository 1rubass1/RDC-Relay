# RDC Relay — AI agent entrypoint (development only)

**This file is for development branch agents, not a product or release artifact.**

The project uses the private [AI Engineering Playbook](https://github.com/1rubass1/AI-Engineering-Playbook) as its read-only methodology. Read `00_START_HERE.md` there. If no role is assigned in a *new working chat*, present the Playbook's six roles and await user selection; never infer the role. If a role has been assigned for this chat, read `CORE/ROLE_COORDINATION.md`, **only that role** in `ROLES/`, and the task-relevant modules. Do not read `ZZ_PLAYBOOK_DEV/` for ordinary RDC work.

Then consult, in order:
1. [PROJECT_INDEX.md](PROJECT_INDEX.md) — canonical project knowledge map.
2. [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) — current stage and next action.
3. [COORDINATION/BOARD.md](COORDINATION/BOARD.md) — active task status, owner and handoff.
4. [docs/dev/README.md](docs/dev/README.md) and **only** relevant scope documents.

## Branch and secret boundaries
- **`development`** is the dev-only integration branch; task branches should target it. Old `develop/*` Git refs prohibit a top-level branch called `develop`.
- `main` and `stable` remain published v1.5.18 production baselines until a separate, approved release. **Never merge the entire development branch into a production branch** with docs/dev, coordination, designs or internal reports.
- Source code and approved public user documentation must be selected explicitly for release. Dev-only files must not be embedded in Setup, Portable ZIP, updater payload, or GitHub release assets.
- GitHub RDC Relay repository is **PUBLIC**, including this dev branch. Never commit real credentials, bearer tokens, tunnel IDs, private endpoints, device/account IDs or sensitive logs. Local byte-exact backups are outside Git on STARMER.
- Do not stop/restart/logout active production Remote, change installed payload or expose arbitrary local tools publicly without explicit authorization.
- No production provider refactor before an authenticated real ChatGPT end-to-end proof, least privilege, failure testing, threat review, and owner GO decision. No new expenses without permission.
- Original Remote engine technical behavior: official `@wonderwhy-er/desktop-commander` documentation. UI: Windows App Design/Fluent 2 as applicable, focused technical validation and **human visual acceptance**.
- Preserve actual evidence and differentiate PASS, FAIL and NOT CHECKED. All Playbook instructions are read-only in user project work.
