# Changelog

## 1.5.9 (2026-10-06)

- Replaced the recolored upstream-style application icon with an original RDC Relay identity: white rounded badge, relay chip, monitor and overlapping purple/orange windows.
- Added dedicated low-resolution icon artwork for 16-64 px frames so Explorer, taskbar and system UI remain legible without tiny text.
- Renamed the runtime icon payload from `DesktopCommander.ico` to `RDCRelay.ico` and updated Setup/Portable resources accordingly.
- Made shortcut migration verifiable and retryable after the window is shown; fixed the malformed PowerShell target path that prevented the 1.5.8 shortcut icon update.
- Assign a dedicated `RDCRelay.App` process AppUserModelID so the taskbar treats RDC Relay as its own application instead of a generic PowerShell host.
- Remove legacy `DesktopCommander*.ico` files only after existing RDC Relay shortcuts have successfully switched to the current versioned icon.

## 1.5.8 (2026-10-06)

- Pause the decorative GPU divider animation when the window is hidden, minimized or fully occluded by other top-level windows, while leaving status/log polling active.
- Resume from the frozen animation phase and snap activity to the current requested state so stale fades are not replayed after returning from the background.
- Refresh existing `RDC Relay` shortcuts on normal startup so updater-only releases keep target, arguments and the versioned icon path current without recreating shortcuts the user removed.
- Rename newly generated versioned shortcut icons to `RDCRelay-v<version>-<hash>.ico` for clearer branding and reliable shell icon-cache invalidation.

## 1.5.7 (2026-10-06)

- Renamed the application and repository branding from `Remote Desktop Commander` to `RDC Relay` to avoid conflict with the upstream Desktop Commander project.
- Changed future update checks to `1rubass1/RDC-Relay` while retaining the legacy install directory and mutex identifiers for seamless upgrades.
- Renamed Setup, Portable, launcher and shortcuts to `RDC Relay`.
- Added first-run migration that removes obsolete launchers and renames existing Desktop/Start Menu shortcuts without creating a parallel installation.

## 1.5.6 (2026-10-06)

- Replaced the ambiguous post-stop "Close" action with a Stop/Start state button: `■ Остановить` / `▶ Запустить`.
- Added vector Stop/Play button glyphs rendered by the shell itself.
- Refined the top-right command group: retained the 4 px utility spacing and 16 px separation before Stop, restored the purple Help treatment, and reduced only its visible circle while keeping the full hit target.
- Tightened startup banner line spacing by one physical pixel to remove dark seams between ASCII-art rows.
- Rebuilt the activity log viewport as a double-buffered panel with one atomic manual layout for the text area, vertical scrollbar, horizontal scrollbar and resize corner.
- Disabled RichEdit native scrollbars entirely and moved horizontal range calculation into the custom controls.
- Changed divider dragging to bitmap-backed live preview: text panes visually follow the pointer while the real RichEdit controls keep fixed geometry until one atomic resize on release.
- During divider drag, replace both vertical scrollbars with one unified rounded orange ruler using the real scrollbar arrow geometry, crisp 2 px / 2 px 45-degree hatching, a five-layer inward capsule edge fade, and a linear crossing fade around the animated divider.
- Added fade-in/fade-out transitions for the temporary drag overlay so the real controls finish repainting before the overlay disappears.
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
