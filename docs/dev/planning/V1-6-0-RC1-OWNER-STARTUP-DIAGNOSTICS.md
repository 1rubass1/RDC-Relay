# RDC Relay 1.6.0 RC1 — owner startup diagnostic logger (2026-10-29)

**Scope:** investigate owner-reported `RC1_AUTOLAUNCH_LAUNCHER_EXIT_42` while preserving v1.5.18 Remote access. Tool is **not** a new Host/GUI prototype and does not install, stop, reconnect or alter the product. Existing Draft PR #23 only.

## Owner workflow

1. Double-click Desktop `RDC-RC1-Diagnostic-Logger.cmd` **before** installing new FULL RC1.
2. Keep the console open. Install and attempt to open RC1 normally.
3. Return to the console, press `W` for visible RC1 window or `F` if no window appeared.
4. **Optional when failed:** press `P` once to explicitly invoke only the installed main desktop shortcut's verified `RC1 Pilot Launcher.exe --full` and capture sanitized stdout/stderr failure categories. It will **refuse** a stable/unknown shortcut, or a reparse-point release. The operator must request this action explicitly.
5. Press `S` to finish and save Desktop `RDC-RC1-Diagnostics-YYYYMMDD-HHMMSS-XXXXXXXX.zip`. Autocomplete after 20 minutes.
6. Owner sends that ZIP even if RC1 worked. If Remote access fails, owner restores v1.5.18 independently using the desktop `RDC.Relay.Setup.v1.5.18.exe`, which is never changed by this logger.

**What the ZIP captures:** timestamped process role/PID/parent/birth, GUI HWND existence and responding state transitions, best-effort WMI process start/exit statuses (including rapid launcher failure), Windows Application event provider/ID/recordID only, optional direct-launch exit code and allowlisted `RC1_*` categories. WMI event subscription is optional and failure falls back to CIM polling; polling can miss rapid processes.

**Not captured:** raw process commandlines, Remote log content, node/npx tokens, account/device identifiers, raw Windows event messages, raw stdout/stderr, environment variables, secret paths, credentials or file contents. Probe executable is verified by exact expected install root, release name, executable name and `--full` argument, then local SHA-256 is captured. Redacted report is still user-provided diagnostic data and must be reviewed before external sharing.

**Safety:** Diagnostic runs under current user with per-process ExecutionPolicy Bypass only; does not change ACL/registry/installed files; no taskkill or Stop-Process. Temporary capture is isolated under `%TEMP%/RDC-RC1-Diagnostic-<GUID>`; verified ZIP is written to user's desktop, and only two known own temporary files are deleted after successful packaging. No current Remote process is terminated. Current 1.5.18 installer and active connection unchanged. Diagnostic script is in `Scripts/Capture-RdcRc1Launch.ps1` and explicitly **not** part of Setup/Portable runtime payload.

## Tests and remaining limits

- Script self-test: generated, opened and removed a disposable ZIP, exit 0.
- Noninteractive real Windows collection dry run: WMI/CIM capture + Application event query + ZIP verification, exit 0.
- Desktop CMD entry-point dry run: `-DryRunSeconds 2` yielded `DIAG_DRYRUN_PASS=TRUE`, exit 0.
- Isolated negative fixture: expected no process termination route, diagnostics-only safe codes, no raw commandline capture.
- Product launch/installation under owner supervision while capture is active: **NOT CHECKED**. Console physical `S/F/W/P` key input: **NOT CHECKED** on owner's interactive desktop; command-line and noninteractive automatic-stop paths were tested.
- Only by repeating the failed installation and optional direct probe can we establish whether a future Launcher error is in product Host launch, GUI ticket, permissions, OS exception or another route. No claim that logger itself fixes the historical product defect.
