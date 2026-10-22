# RDC Relay — development knowledge base

> **DEVELOPMENT-ONLY. NOT A RELEASE COMPONENT.** This tree is intended for the `development` branch and development-only task branches. Do not distribute its files in Setup EXE, Portable ZIP, update payloads, end-user app folders, or public release assets. Do not promote it wholesale into `main`/`stable`.

**Entry points:** [project index](../../PROJECT_INDEX.md), [current context](../../PROJECT_CONTEXT.md), [coordination board](../../COORDINATION/BOARD.md), [decisions](../../DECISIONS.md). Open the private AI Engineering Playbook `00_AI_AGENT_IF_YOU_SEE_THIS_READ_IT.md` first (renamed from `00_START_HERE.md`). Read it even for repository orientation; select a role only for working tasks that lack a role assignment, then load that role and relevant modules.

## Knowledge layout
| Folder | Purpose | Authority |
| --- | --- | --- |
| [requirements/](requirements/PROJECT_BRIEF.md) | Product purpose, scope, constraints | Agreed user brief; proposed details labelled |
| [planning/](planning/ROADMAP.md) | Current phases, dependencies and gates | Current roadmap (supersedes imported legacy) |
| [architecture/](architecture/OVERVIEW.md) | System contracts, provider direction and uncertainties | Current overview plus explicitly marked **legacy proposal** |
| [research/](research/RESULTS_MATRIX.md) | Evidence, sources, experiments, verified vs missing | Experiment records with actual results |
| [design/](design/README.md) | Editable Pen reference, assets and UX acceptance | Design reference; user approval still needed |
| [operations/](operations/RELEASE_BOUNDARY.md) | Branch, packaging, distribution, credential boundaries | Release boundary policy |
| [tools/](tools/Check-ReleaseBoundary.ps1) | Development-only repeatable release-boundary guard | Read-only static checks plus optional Portable ZIP audit |
| [history/](history/MIGRATION_MANIFEST.md) | Read-only pre-Playbook documents and import provenance | **Archive, not instructions for next task** |

## Data classification — GitHub is public
The **RDC Relay GitHub repository is public. Development branches are public too.** A directory named `dev` does not make information confidential.

Never commit secrets or private user data to any branch, even this one: OAuth/runtime/API keys, bearer tokens, tunnel IDs, active endpoints tied to private hosts, device/account identifiers, private logs, credentials, diagnostic dumps, personal paths not needed for reproduction, or environment-specific configuration. Use redacted examples. Keep actual sensitive information only in authorized local protected storage; purge using proper key rotation if exposure is discovered.

Imported legacy documents were snapshotted locally and sanitized before versioning. Three real-looking tunnel IDs were removed from the committed copy. Archive originals remain **only on STARMER** outside Git. Do not recommit unfiltered local copies.

## Single source of truth and update workflow
- Current task IDs/status/owners: `COORDINATION/BOARD.md`.
- Current short stage snapshot: `PROJECT_CONTEXT.md`.
- Decided material architecture changes: `DECISIONS.md`.
- Future ordering and entrance/exit criteria: `docs/dev/planning/ROADMAP.md`.
- Experiments and exact claims: `docs/dev/research/`; distinguish PASS, FAIL, NOT CHECKED.
- Historical work chronology: `docs/dev/history/WORKLOG_LEGACY.md` (frozen) and git history; do not resume editing an old diary.
- Do not make a second editable copy of the same document elsewhere.

**Original local documents** under `E:\Projects\GitSync\RDC\` were the old source of truth; after migration the *sanitized, classified documents in the development branch* supersede them. Before changing local pointer files, verify the new branch/commit exists and the byte-exact local backup is intact. Runtime source and build packaging are unchanged by this migration.
