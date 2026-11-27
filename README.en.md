<p align="center">
  <img src="Assets/README/Wordmark.svg" alt="RDC Relay" width="640">
</p>

<p align="center">
  <a href="README.md">Русский</a> | <b>English</b>
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

> [!CAUTION]
> The installer is not digitally signed. Windows SmartScreen may display a warning, and Smart App Control may block execution.
>
> **Smart App Control (SAC).**
> RDC Relay 1.6.0 is distributed without a trusted code-signing signature. With Smart App Control enabled, Windows may block both Setup and normal launches of an already installed copy. If you prefer to keep this protection, use the [original Desktop Commander](https://desktopcommander.app/).
>
> Turning SAC off reduces system-wide protection against untrusted applications; it is not an exception just for RDC Relay. There is no need to disable antivirus, SmartScreen or the firewall. RDC Relay never changes these security settings automatically.
>
> Manage SAC in **Windows Security → App & browser control → Smart App Control settings**. If you independently decide to change the setting, select Off or On where supported. Select On to restore protection. Before turning it off, confirm that your Windows build supports re-enabling SAC: older builds may require a reset or reinstallation, and returning to evaluation mode can also require a reset or reinstall. If the setting is unavailable, do not manually modify system policies.
>
> [Official Microsoft FAQ (EN)](https://support.microsoft.com/en-gb/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions)

## Original project

RDC Relay is an independent project and is not officially affiliated with the developers of Desktop Commander. Device pairing uses the official Desktop Commander approval flow; approve only devices you recognize.

[Desktop Commander](https://github.com/wonderwhy-er/DesktopCommanderMCP)

[Changelog](CHANGELOG.md)
