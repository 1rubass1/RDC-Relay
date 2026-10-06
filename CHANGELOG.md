# Changelog

## 1.5.5

Maintenance and release-engineering release. No intentional UI redesign.

- Moved automatic updates from the moving `main` branch to a dedicated
  `stable` channel.
- Added same-version SHA256 repair, updater diagnostics and safer rollback
  behavior.
- Single-instance ownership is now acquired before update checks, preventing a
  second launcher from replacing files under a live window.
- Pinned Desktop Commander to `0.2.52`.
- Added PATH-aware `npx.cmd` resolution with standard Windows fallbacks.
- Restricted existing-process adoption to a launcher using this installation's
  own log path.
- Added a timeout and process-tree cleanup for account logout.
- Fixed pane-divider drag artifacts by suspending the transparent WPF overflow
  popup during the gesture and coalescing high-frequency layout updates.
- Added a static divider fallback when GPU shader initialization is unavailable.
- Added reproducible shader compilation through `d3dcompiler_47.dll`.
- Added a reproducible Setup EXE / portable ZIP release build and a testable
  silent installer mode.
- Removed legacy checked-in Setup/shortcut artifacts from the source tree.

## 1.5.4

- Added the GPU activity divider and adaptive 5-15 second activity hold.
- Prevented incoming remote tasks and second-launch behavior from stealing
  foreground focus.
- Added the first GitHub-backed self-update implementation with SHA256 payload
  verification and rollback.
- Refined the application icon and corrected monogram alignment/background.
