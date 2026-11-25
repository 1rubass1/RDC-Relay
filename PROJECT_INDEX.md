# RDC Relay — project index (development)

**Product:** Windows desktop GUI/supervisor for official Desktop Commander Remote; exploring alternate secure MCP transports after proven feasibility.

**Repository:** https://github.com/1rubass1/RDC-Relay
**Integration branch:** `development` (development-only records), with `main`/`stable` reserved for tested release source.
**Local environment:** owner-controlled Windows workstation; checkout paths are retained only in local continuation records.
**Methodology:** external read-only [AI DevBook](https://github.com/1rubass1/AI-DevBook), mode **dynamic `main`**, verified on **2026-11-13** at full `5d479bffc663f17aae7f721c89d5f47de8a7ffe6` (`0.7-draft`); entry [`00_START_HERE.md`](https://github.com/1rubass1/AI-DevBook/blob/main/00_START_HERE.md). **No copied central methodology or pinned project SHA**; `AGENTS.md` contains RDC-specific boundaries. Each new work cycle reads the available actual branch revision, recording the observed SHA. Old source was private `1rubass1/AI-Engineering-Playbook`, last documented `main@5cae0136c5eb0feaea4f00b8ba700199d58803c9` (2026-10-23); exact old contents were inaccessible during transition, so a full version diff is **NOT VERIFIED**. **Project files updated; existing agent instruction reloads are not confirmed** (see context/board).

## Begin work
- [AGENTS.md](AGENTS.md) — choose role by Playbook and enforce boundaries.
- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) — stage snapshot and next step.
- [COORDINATION/BOARD.md](COORDINATION/BOARD.md) — single task/role status authority.
- [COORDINATION/CHAT_REGISTRY.md](COORDINATION/CHAT_REGISTRY.md) — existing project chat registry (legacy equivalent of `AI Work/Coordination/`).
- [DECISIONS.md](DECISIONS.md) — substantial adopted decisions and open proposals.
- [Development knowledge index](docs/dev/README.md) — categorized documents.

- [Повторное ревью 33d7c76](docs/dev/reviews/REV-R2-007-RELEASE-33D7C76.md) — оба замечания R2-006 закрыты, передано на приёмку Architect.
- [Повторное ревью исправлений e8902a1](docs/dev/reviews/REV-R2-006-PUBLIC-CORRECTIVE.md) — 183/183, два остаточных сценария, NO-GO.
- [Предрелизное ревью 1.6.0](docs/dev/reviews/REV-R2-005-PUBLIC-PREFLIGHT.md) — публичный кандидат a6580eb, NO-GO, четыре замечания.
- [Reviewer 2 buffered-observer review](docs/dev/reviews/REV-R2-004-BUFFERED-F41B3D1.md) — f41b3d1 and exact private package: five R3 criteria PASS; release NO-GO pending remaining acceptance.
- [Reviewer 2 readiness follow-up review](docs/dev/reviews/REV-R2-003-READINESS-1E59DE4.md) — 1e59de4: prior two defects closed, new partial-line observer regression.
- [Reviewer 2 RC1 fixes re-review](docs/dev/reviews/REV-R2-002-RC1-FIXES-2026-11-15.md) — previous review cycle: partial acceptance, two residual readiness defects and independent 69/69 regression.
- [Reviewer 2 latest RC1 release-readiness review](docs/dev/reviews/REV-R2-001-LATEST-RC1-2026-11-15.md) — artifact-bound NO-GO verdict and reproducible findings.
- [PLAYBOOK_FEEDBACK.md](PLAYBOOK_FEEDBACK.md) — project-local methodology feedback.

## Source of truth by concern
| Concern | File(s) |
| --- | --- |
| Scope and acceptance | [Product brief](docs/dev/requirements/PROJECT_BRIEF.md) |
| Phase sequencing | [Roadmap](docs/dev/planning/ROADMAP.md) |
| System contracts and proposals | [Architecture overview](docs/dev/architecture/OVERVIEW.md), [PROG-005 process ownership/test plan — proposal](docs/dev/architecture/PROG-005-PROCESS-OWNERSHIP-PLAN.md), [tray lifecycle contract — owner UX decision](docs/dev/architecture/TRAY-LIFECYCLE-DESIGN.md), [ARCH-016-P1 Host/GUI IPC security and test contract](docs/dev/architecture/ARCH-016-P1-HOST-GUI-IPC-CONTRACT.md), [legacy technical proposal](docs/dev/architecture/PROVIDER_TECHNICAL_DESIGN_LEGACY.md) |
| Verified transport experiments | [Results matrix](docs/dev/research/RESULTS_MATRIX.md), [research archive](docs/dev/research/) |
| Editable GUI concept and geometry | [Design reference](docs/dev/design/README.md) |
| Dev branch / release / credential separation | [Release boundary](docs/dev/operations/RELEASE_BOUNDARY.md) |
| Pre-Playbook archived chronology and provenance | [Migration manifest](docs/dev/history/MIGRATION_MANIFEST.md), [historical worklog](docs/dev/history/WORKLOG_LEGACY.md) |
| Released functionality and user instructions | [Product README](README.md), [CHANGELOG](CHANGELOG.md) |

## Product source tree
`Source/`: runtime, UI, provider process and shader files. `Installer/`: setup and launcher. `Scripts/`: build/release. `Tests/`: UI, updater and lifecycle regressions. Production binaries in ignored `dist/`.

## Local preservation, no competing sources
Previous root planning and worklog documents were **migrated**. Byte-exact originals are preserved in the owner's local-only pre-Playbook archive. Their versioned sanitized copies are kept **as legacy evidence**, never as current task instructions. Future source-of-truth edits belong in the categorized development documents above.

**IMPORTANT:** This GitHub repository is public, including development branches. Actual secrets, active tunnel identifiers, private endpoints, credentials and user logs must never be committed. Do not ship `docs/dev/`, this index or the other coordination records in releases.
