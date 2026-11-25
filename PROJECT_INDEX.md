# RDC Relay — project index (development)

**Repository:** https://github.com/1rubass1/RDC-Relay

**Current release:** [1.6.0](https://github.com/1rubass1/RDC-Relay/releases/tag/v1.6.0); [1.5.18](https://github.com/1rubass1/RDC-Relay/releases/tag/v1.5.18) remains the legacy anchor.

**Methodology:** external read-only [AI DevBook](https://github.com/1rubass1/AI-DevBook), dynamic main. See [AGENTS.md](AGENTS.md) for the current reading checkpoint and task boundaries.

## Start here
- [Current context](PROJECT_CONTEXT.md)
- [Coordination board](COORDINATION/BOARD.md) and [chat registry](COORDINATION/CHAT_REGISTRY.md)
- [Roadmap](docs/dev/planning/ROADMAP.md) and [decisions](DECISIONS.md)
- [Development knowledge index](docs/dev/README.md)

## Engineering references
| Concern | Source |
| --- | --- |
| Product requirements | [Brief](docs/dev/requirements/PROJECT_BRIEF.md) |
| Runtime and IPC | [Architecture](docs/dev/architecture/OVERVIEW.md), [Host/GUI IPC contract](docs/dev/architecture/ARCH-016-P1-HOST-GUI-IPC-CONTRACT.md), [tray lifecycle](docs/dev/architecture/TRAY-LIFECYCLE-DESIGN.md) |
| Release engineering | [Release evidence](docs/dev/planning/V1-6-0-RELEASE-INSTALLER-INTEGRATION.md), [final review](docs/dev/reviews/REV-R2-007-RELEASE-33D7C76.md), [release boundary](docs/dev/operations/RELEASE_BOUNDARY.md) |
| QA | [Windows Sandbox procedure](docs/dev/operations/WINDOWS_SANDBOX_QA.md), `Tests/` |
| UI and localization | [Design](docs/dev/design/README.md), [localization](docs/dev/localization/README.md) |
| Future transport research | [Results matrix](docs/dev/research/RESULTS_MATRIX.md) (historical evidence, not current implementation authorization) |

## Source tree and release separation
Development: `Source/`, `Installer/`, `Scripts/`, `Tests/`, `Assets/`. The public snapshot uses legacy `Source/` and current `FullHost/`; do not merge development wholesale into public branches. Build the explicit qualification/public candidate via `Scripts/build-rc1-full.ps1 -Build -ReleaseQualification -PublicPreflight` only under release authorization. Publish exact reviewed assets, not a later source rebuild. Dev documentation, experiments and private data never belong in the payload.

The GitHub repository is public, including development branches. Local logs, account data, private paths and credentials must remain outside Git.
