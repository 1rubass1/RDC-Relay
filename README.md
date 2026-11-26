<p align="center">
  <img src="Assets/README/Wordmark.svg" alt="RDC Relay" width="640">
</p>

<p align="center">
  <b>English</b> | <a href="README.ru.md">Русский</a>
</p>

**RDC Relay is an independent software supervisor for Desktop Commander Remote on Windows.**

It provides background management of Remote and monitors the state of the MCP connection used for AI interaction with your computer, without the need to work with a terminal.

## Key features

- **Remote management** — start, stop, reconnect and keep Remote running in the background.
- **Automatic recovery** — diagnose failures and restore the connection.
- **Real-time monitoring** — view connection status, Remote activity, the current account and remaining calls.
- **Account switching** — switch between Desktop Commander accounts.
- **System tray controls** — quick access to essential functions.
- **Informative logging** — turn the technical Remote event stream into a compact, readable journal while retaining access to the original logs.

## Installation

The latest version of RDC Relay is available in [Releases](https://github.com/Rubo-Facility/RDC-Relay/releases) in two formats:

- **Setup** — standard installer. If the required Node.js, npm and npx environment is missing, Setup offers to install Node.js 24 LTS.
- **Portable** — no installation required. Extract the entire ZIP archive to a local folder and launch `RDC Relay.exe`.

> [!IMPORTANT]
> **Updating from version 1.6.0:** due to the repository address change, upgrading from version 1.6.0 to a newer version must be performed manually. Download the latest version from [Releases](https://github.com/Rubo-Facility/RDC-Relay/releases).

> [!CAUTION]
> The installer is not digitally signed. Windows SmartScreen may display a warning, and Smart App Control may block execution.

## Original project

RDC Relay is an independent project and is not officially affiliated with the developers of Desktop Commander. Device pairing uses the official Desktop Commander approval flow; approve only devices you recognize.

[Desktop Commander](https://github.com/wonderwhy-er/DesktopCommanderMCP)

[Changelog](CHANGELOG.md)
