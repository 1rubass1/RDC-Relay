# Changelog

<p align="center">
  <a href="CHANGELOG.md">Русский</a> | <b>English</b>
</p>

A concise history of RDC Relay releases, newest first.

## 1.6.0 — 2026-11-25

- **New architecture.** RDC Relay maintains its connection in the background, independently of the main window, with system tray controls.
- **Reliability and connection.** Reworked Remote process management, readiness tracking and connection recovery. Uses the latest version of the original Desktop Commander Remote.
- **Monitoring.** Synchronized remaining calls in the main window and system tray, with improved data refresh and freshness checks.
- **Interface.** Refined status indicators, visual effects, context menus and dialogs. Updated the header design, scrolling and adaptation to different window sizes and display scaling.
- **Activity journal.** Log viewing, exporting, automatic rotation, storage limits and improved startup diagnostics.
- **Installation and updates.** Setup offers Node.js 24 LTS when required dependencies are missing. A dedicated update feed supports subsequent releases. Exit any running instance of RDC Relay before installation.
- **Localization.** Russian and English with in-app switching.

[Release 1.6.0](https://github.com/Rubo-Facility/RDC-Relay/releases/tag/v1.6.0)

## 1.5.18 — 2026-10-20

Fixed the update button when launched with `-SkipUpdate`; the version notice refreshes without restarting the window or replaying the animation. Expanded update tests.

## 1.5.17 — 2026-10-20

Safe recovery of incomplete npm cache entries on ENOENT/-4058; clarified first-device OAuth instructions and added a device verification shortcut.

## 1.5.16 — 2026-10-17

Animated update notice and background version checks; fixed stale recovery flashes, manual Stop state handling and npx startup error classification.

## 1.5.15 — 2026-10-08

Restored the 1.5.12 footer hint, separator and version layout.

## 1.5.14 — 2026-10-08

Corrected footer alignment and synchronized the runtime version with release metadata.

## 1.5.13 — 2026-10-08

Automatic recovery of corrupted npx cache entries; improved slow-connection handling and protected manual Stop from late Remote events.

## 1.5.12 — 2026-10-07

Transactional installation and updates with rollback; protected installed shortcuts from portable copies. Moved Remote operations off the UI thread, improved controls, keyboard navigation and single-instance recovery. Expanded integrity, rollback and GPU rendering tests.

## 1.5.11 — 2026-10-07

Windows Installed Apps registration and standard uninstall; EXE launcher for Portable. Retained the existing installation path for upgrade compatibility.

## 1.5.10 — 2026-10-06

- Remote readiness supervision, bounded restarts and connection recovery without competing with Desktop Commander's reconnect mechanism.
- Separated connection and tool activity events; prevented false faults and improved log routing, scrolling and previous-session log retention.
- Updated the GPU divider: connecting, fault and recovery colors, smoother animation, transparency and layering fixes. Reproducible four-shader build and expanded regression checks.

## 1.5.9 — 2026-10-06

Original RDC Relay icon, small-size artwork and a dedicated Windows application identity; fixed shortcut and icon migration.

## 1.5.8 — 2026-10-06

Paused GPU animation while hidden, minimized or fully occluded without stopping monitoring; improved animation resumption and existing shortcut updates.

## 1.5.7 — 2026-10-06

Renamed the application and repository to RDC Relay; updated the GitHub endpoint, installer, portable and shortcut names while preserving installation compatibility.

## 1.5.6 — 2026-10-06

Replaced the ambiguous close action with Stop/Start, added vector glyphs and refined controls. Reworked the log viewport, scrollbars and divider dragging; adaptive activity hold timing.

## 1.5.5

Introduced the `stable` update channel, SHA-256 verification and same-version repair; strengthened single-instance and process cleanup. Pinned Desktop Commander 0.2.52 and improved npx discovery. Added a static rendering fallback and reproducible shader, Setup and Portable builds.

## 1.5.4

Added the GPU activity divider with adaptive hold timing; prevented focus stealing by incoming tasks and second launches. Introduced GitHub-backed self-update with SHA-256 verification and rollback; refined the icon.

---

Detailed technical history of legacy versions remains in Git at the [v1.5.18 tag](https://github.com/1rubass1/RDC-Relay/blob/v1.5.18/CHANGELOG.md).
