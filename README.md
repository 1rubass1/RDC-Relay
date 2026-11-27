# RDC Relay — development

RDC Relay is an independent Windows companion GUI and supervisor for official Desktop Commander Remote, using the official `@wonderwhy-er/desktop-commander@latest` channel. The 1.6.0 architecture separates background Host from the replaceable GUI.

- [Current public README](https://github.com/Rubo-Facility/RDC-Relay/blob/main/README.md)
- [Current 1.6.0 release](https://github.com/Rubo-Facility/RDC-Relay/releases/tag/v1.6.0)

This is the development source layout, not the public release package. Start with [PROJECT_INDEX.md](PROJECT_INDEX.md), [AGENTS.md](AGENTS.md) and [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md). Public build targets Windows 10/11 with Windows PowerShell 5.1 and Node.js 24 LTS; see the public README for requirements and installation. The independently downloaded upstream package is MIT-licensed; see [third-party notices](Source/THIRD_PARTY_NOTICES.txt) and the upstream [project](https://github.com/wonderwhy-er/DesktopCommanderMCP). Hosted service use is governed by [provider terms](https://legal.desktopcommander.app/terms_of_service).

Do not distribute this development tree as an installation package or merge its development-only documentation into main/stable.

See [Windows 11 compatibility / Smart App Control](docs/release/SAC-CAUTION.md) before installing an unsigned build.
