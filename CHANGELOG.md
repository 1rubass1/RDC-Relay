# Changelog

## 1.5.10 (2026-10-06)

- Added a bounded Remote MCP health supervisor that distinguishes a live `cmd/npx` process from an actually ready remote session, tracks ready/fatal markers, restarts lost sessions with 2/5/10 second backoff, and handles unexpected process exits.
- Treat realtime transport loss (`Channel error`, `Channel closed`, `Device marked as offline`) as a persistent visual fault without competing with Desktop Commander's own channel reconnect.
- Require upstream's full reachability proof before green/ready: `Channel subscribed` and an online status write remain transitional; `Presence tracked` (or the final connected marker) confirms the realtime channel, capability publication and usable remote path.
- Track the original 0.2.52 local-executor loss/recovery markers (`Local Desktop Commander MCP went away` / `... restarted; device is online again`) instead of relying on an assumed disconnect string.
- Keep a slow first connection red after the readiness grace period but leave the live Remote process in charge of its own background reconnect; bounded supervisor restarts remain reserved for fatal session/startup/process failures.
- Fixed a PowerShell scope collision where the fault-detail string shadowed the WinForms status label and produced repeated modal `property "Text" not found` dialogs; background refresh exceptions are now logged without blocking the UI.
- Freeze the upper log pane at Desktop Commander's startup/Commands footer and route later channel/offline/reconnect/presence output to the lower activity pane, while preserving the complete raw session log on disk.
- Stabilize the lower RichEdit viewport after text replacement and pane resizing by restoring scroll position only after redraw is re-enabled and forcing immediate plus deferred repaint/reflow.
- Added a two-tone yellow/amber connecting palette for the initial Remote MCP startup (particles, caustic and rails). It transitions to the green ready confirmation on success, or yields to persistent red on a fault.
- Fixed the particle popup lifecycle: startup could open the transparent WPF popup before the WinForms owner existed, leaving it below the main window. Ownership/Z-order are now repaired after load without using global topmost behavior. With that fixed, the selected sandwich composition is restored: coupled halo, transparent caustic detail, then a wider soft-white hot core.
- Preserve the previous `remote-session.log` before a fresh launch so failed reconnect cycles remain diagnosable.
- Added persistent fault signalling: particles, caustic and divider rails smoothly move into a two-tone red/red-orange palette and remain there until the fault clears.
- Added a one-shot green/yellow-green recovery confirmation with a fast peak and a longer smooth return to the normal purple/orange palette; geometry and particle trajectories remain unchanged.
- Trigger the green confirmation on every real `not ready -> ready` transition, including the first successful connection after application startup, without retriggering on duplicate ready markers.
- Track Desktop Commander tool lifecycle using its leading Unicode markers (🔧/✅/❌). Explicit failed calls remain visibly faulted, but prolonged silence or a missing completion marker now retires to idle instead of being treated as a Remote MCP failure.
- Extended GUI self-tests for cold-start readiness, explicit tool failures, idle-timeout retirement, recovery signalling and GPU palette transitions.
- Restored a reproducible four-shader build: particle pass selection now uses an explicit `PassIndex` shader constant instead of overloading `Intensity`, and both particle/core bytecode files are rebuilt from their checked-in HLSL sources.
- Hardened release/UI integrity checks: self-test now validates the exact manifest payload and hashes, single-popup sandwich/transparency contracts and premultiplied-alpha guards; GPU initialization failures are logged instead of silently falling back.
- Kept explicit tool-call failures latched red across duplicate Presence/ready markers; only a later successful tool call clears that tool fault and triggers the recovery confirmation.
- Doubled divider particle density from roughly 12 to 24 simultaneous trajectories by adding two preserving GPU passes with independent time phases, without increasing ps_3_0 shader instruction count.
- Slowed particle animation to 50% speed and doubled only its horizontal geometry (heads, hot cores, tails and ghost offsets); then compressed the complete particle silhouette vertically to two thirds of its previous height and reduced particle/core luminance by 18% so purple/orange hue remains visible instead of clipping toward white.
- Simplified the divider-drag scrollbar crossing mask: keep the fully opaque center narrower, trim one additional pixel from its lower side for visual balance, and use a direct mirrored 15 px linear alpha ramp from 0 to 250 instead of the curved/dark overlay experiment.
- Apply the banner's proven 1 px exact RichEdit line-spacing correction to both full log surfaces so Unicode box-drawing groups such as Next / Commands no longer show horizontal seams outside the ASCII banner.
- Prevent false red connection faults when tool commands/results merely contain lifecycle-looking strings such as `Channel error:`; serialized tool payloads are excluded from health parsing, and any successful remote tool call now proves readiness, including after the GUI adopts an already-running Remote MCP whose earlier Presence marker is no longer replayed.

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
