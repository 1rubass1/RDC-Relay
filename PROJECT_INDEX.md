# RDC Relay — project index (development)

**Product:** Windows desktop GUI/supervisor for official Desktop Commander Remote; exploring alternate secure MCP transports after proven feasibility.

**Repository:** https://github.com/1rubass1/RDC-Relay
**Integration branch:** `development` (development-only records), with `main`/`stable` reserved for tested release source.
**Machine:** STARMER; working tree `E:\Projects\GitSync\RDC\RDC-Relay Work`.
**Methodology:** private `1rubass1/AI-Engineering-Playbook`, read-only here.

## Begin work
- [AGENTS.md](AGENTS.md) — choose role by Playbook and enforce boundaries.
- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) — stage snapshot and next step.
- [COORDINATION/BOARD.md](COORDINATION/BOARD.md) — single task/role status authority.
- [DECISIONS.md](DECISIONS.md) — substantial adopted decisions and open proposals.
- [Development knowledge index](docs/dev/README.md) — categorized documents.

## Source of truth by concern
| Concern | File(s) |
| --- | --- |
| Scope and acceptance | [Product brief](docs/dev/requirements/PROJECT_BRIEF.md) |
| Phase sequencing | [Roadmap](docs/dev/planning/ROADMAP.md) |
| System contracts and proposals | [Architecture overview](docs/dev/architecture/OVERVIEW.md), [legacy technical proposal](docs/dev/architecture/PROVIDER_TECHNICAL_DESIGN_LEGACY.md) |
| Verified transport experiments | [Results matrix](docs/dev/research/RESULTS_MATRIX.md), [research archive](docs/dev/research/) |
| Editable GUI concept and geometry | [Design reference](docs/dev/design/README.md) |
| Dev branch / release / credential separation | [Release boundary](docs/dev/operations/RELEASE_BOUNDARY.md) |
| Pre-Playbook archived chronology and provenance | [Migration manifest](docs/dev/history/MIGRATION_MANIFEST.md), [historical worklog](docs/dev/history/WORKLOG_LEGACY.md) |
| Released functionality and user instructions | [Product README](README.md), [CHANGELOG](CHANGELOG.md) |

## Product source tree
`Source/`: runtime, UI, provider process and shader files. `Installer/`: setup and launcher. `Scripts/`: build/release. `Tests/`: UI, updater and lifecycle regressions. Production binaries in ignored `dist/`.

## Local preservation, no competing sources
Previous root documents `E:\Projects\GitSync\RDC\{HANDOFF,WORKLOG,ROADMAP,TECHNICAL_DESIGN,SOURCES,...}.md` were **migrated**. Byte-exact originals are preserved under `E:\Projects\GitSync\RDC\_archive\pre-playbook-2026-10-22\` (local-only). Their versioned sanitized copies are kept **as legacy evidence**, never as current task instructions. Future source-of-truth edits belong in the categorized development documents above.

**IMPORTANT:** This GitHub repository is public, including development branches. Actual secrets, active tunnel identifiers, private endpoints, credentials and user logs must never be committed. Do not ship `docs/dev/`, this index or the other coordination records in releases.
