# Changelog

## 1.5.6 (development)

- Replaced the ambiguous post-stop "Close" action with a Start/Stop state button.
- Added vector Stop/Play button glyphs rendered by the shell itself.
- Tightened startup banner line spacing by one physical pixel to remove dark seams between ASCII-art rows.
- Rebuilt the activity log scroll area as a fixed 2x2 grid instead of overlaying custom scrollbars on RichEdit native scrollbars.
- Hide RichEdit native scrollbars while preserving their scroll metrics for the custom controls.
- Coalesce expensive RichEdit thumb tracking to display-frame cadence while keeping the custom thumb visually responsive.
- Unified scrollbar/corner backgrounds to eliminate edge gaps during fast scrolling and pane resizing.

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
