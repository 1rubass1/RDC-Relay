# Changelog

## 1.5.6 (development)

- Replaced the ambiguous post-stop "Close" action with a Stop/Start state button: `■ Остановить` / `▶ Запустить`.
- Added vector Stop/Play button glyphs rendered by the shell itself.
- Added an orange outline to the Help button.
- Tightened startup banner line spacing by one physical pixel to remove dark seams between ASCII-art rows.
- Rebuilt the activity log viewport as a double-buffered panel with one atomic manual layout for the text area, vertical scrollbar, horizontal scrollbar and resize corner.
- Disabled RichEdit native scrollbars entirely and moved horizontal range calculation into the custom controls.
- Changed divider dragging to deferred resize: only a lightweight divider guide follows the pointer, while the RichEdit panes and scrollbars keep fixed geometry until one atomic resize on release.
- Coalesce expensive RichEdit thumb tracking to display-frame cadence while keeping the custom thumb visually responsive.
- Unified scrollbar/corner backgrounds to eliminate edge gaps during fast scrolling and pane resizing.
- Changed divider activity timing to an adaptive 10-30 second normal hold and a 60 second timeout for interrupted tool calls.

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
