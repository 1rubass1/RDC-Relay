# RDC Relay — instructions for AI agents

## Entry point
This project uses the separate **AI Engineering Playbook** repository:
https://github.com/1rubass1/AI-Engineering-Playbook

First read the Playbook's `00_START_HERE.md`. In a **new working chat** without an explicitly assigned role, ask the user to choose a role as required by that entry point. A role assigned for one chat does not automatically apply to others. Once assigned, read `CORE/ROLE_COORDINATION.md`, only `ROLES/<chosen role>.md`, and the task-relevant instructions. Treat Playbook files as read-only during RDC Relay work.

Then read, in order:
1. `PROJECT_INDEX.md` — where facts and project artifacts live.
2. `PROJECT_CONTEXT.md` — stage snapshot.
3. `COORDINATION/BOARD.md` — task ownership, status, and next handoff.
4. Only the task-relevant strategic documents and source files.

## Existing project documentation
Canonical historical and current strategic documents are presently outside this Git working tree, at `E:\Projects\GitSync\RDC\` on **STARMER**: `HANDOFF.md`, `WORKLOG.md`, `ROADMAP.md`, `TECHNICAL_DESIGN.md`, `SOURCES.md`, and transport spikes. Do **not** invent their contents if STARMER is unavailable. Their relocation/versioning is a pending architectural decision, not an accomplished migration.

## Safety and delivery constraints
- Do not stop/restart/logout the running Desktop Commander Remote session, change installed production RDC Relay, or expose local execution tools to the internet without explicit scope and user approval.
- No production provider refactor before actual authenticated ChatGPT end-to-end transport feasibility and security gates pass.
- `stable` is the production update branch. Use isolated feature branches; do not move `stable`, tag or publish a release without explicit approval.
- Use the official original Remote Desktop Commander documentation to verify upstream engine behavior. For UI, follow the project's established visual acceptance rule and applicable Windows App Design / Fluent 2 guidance.
- Minimize diagnostic captures, logs, resource usage and extra documents. No additional spending without explicit authorization.
- Record verified results separately from assumptions, and do not mark an untested behavior PASS.
