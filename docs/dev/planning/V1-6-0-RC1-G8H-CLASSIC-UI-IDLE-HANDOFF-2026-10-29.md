# PROG-006A-G8H — classic startup UI, Remote uptime, cooperative idle Host update

**Date:** 2026-10-29. **Role:** Programmer. **Branch:** feature/v1.6-host-gui-owner-pilot. **PR:** #23 (Draft). Desktop Commander pinned at 0.2.52, unchanged.

## Owner request and comparison with 1.5.18

Owner requests actual replacement/restart of prior shell on manual upgrade if the prior Remote process is stopped; recovery of original richly colored startup presentation rather than a sparse text summary; original process uptime at the bottom instead of the label Host-owned Job. Compared the original **installed v1.5.18** remote-window.ps1 and source copy in RC1: old header used Set-StartupFromProbe to take initial Remote stdout, Render-CompactLog, StyleStartupBanner, Color-HeaderSemantics, Color-LogRegex/Token; process status footer used a verified startTime and formatted hh:mm:ss. RC1 had retained the native painter but was starving it of original startup art, and its footer was static ownership text.

## Product changes

- Host persists exact OS birth ticks from its private kernel Job Remote root, not a guessed PID, and exposes remoteBornUtcTicks only for managed mode. Original GUI uses its own 150ms Windows Forms timer to format 'Время работы hh:mm:ss' from this OS evidence, changing text at most once per second. It stops incrementing when authenticated Host snapshots have been stale for more than five seconds and clears uptime on Remote exit.
- Host accepts **only** up to seven graphic-only, 10–180 character lines from the first twelve lines of its own Remote startup log. Strips ANSI SGR, rejects letters/numbers or other untrusted content; retains actual original Unicode box-drawing startup art in RAM and publishes bounded remoteStartupArt through authenticated IPC. GUI revalidates length/character set and uses the **original RdcLogBox** painter, including unchanged original coloring for Remote Connection, Online/Offline and '- User/Device ID/Device Name' values. This is a faithful restoration of the logo/presentation mechanics with deliberately **filtered** connection text, not an unsafe raw reproduction of arbitrary Remote output. Identity values are still validated and Host-owned.
- A live prior RC1 Host from a *newly instrumented release* accepts a same-logon, exact-source-root 'Local/RdcRelayRC1IdleUpgrade-<hash>' AutoReset event. In its own UI pulse it independently checks managed/Owned mode, no running owned Job members, no external pinned Remote, no legacy GUI; it suppresses autostart, increments closeGeneration for cooperative GUI X-equivalent close, and exits, releasing its private singleton mutex. No force kill, PID-by-name or remote logout.
- Setup first validates immutable candidate and existing Desktop shortcut; if the old exact Host mutex is active, confirms the OS-pinned Remote commandline scan has no matches and is fully readable, then sends the exact event and waits up to 20s to acquire the old mutex. Only **after verified old Host exit** does Setup atomically replace the shortcut and launch a single new Full Host/GUI. A timeout refuses the transaction, leaving old shortcut intact. If old version has **no** such endpoint, one-time legacy fallback remains an explicit deferred upgrade with actionable notification (not falsely claimed a restart). Working Remote still blocks the idle-handoff route. No changes to installed 1.5.18 or public updater.

## Verification and remaining limits

- Static/compile/source-state regression: included in expanded safe suite, see current BOARD entry for exact total/exit.
- Disposable Windows event/mutex old-Host analog: 6/6 PASS exit0. Covers missing endpoint negative, exact event signal, former mutex release, no force kill. The fixture is **not** a full OS test of product Host exit with actual GUI.
- Native managed GUI/IPC OS fixture: PASS exit0. Real HWND authenticated, pre-GUI Remote creation refused, existing live Remote identity unchanged, GUI closed cooperatively.
- Full Setup/Portable isolated manifest build and standalone Setup tests: see BOARD for exact SHA and results.
- NOT CHECKED: owner-installed corrected GUI's full colored banner and uptime, live idle-to-new-Host handoff from a **supported instrumented predecessor**, and migration from an **older Host without endpoint** (will require one-time normal tray exit). A currently running Remote is **not** stopped for this test, as it provides STARMER access. No PR merge or release publication.

**Owner rollout:** Keep original 1.5.18 Setup on Desktop, current running Full RC1 and its Remote unchanged; archive only previous RC1 candidate installers. Next manual owner install should be done during a coordinated session if the installed prior Host has no cooperative endpoint; avoid a second Host/process tree. The owner alone determines when to interrupt the live Remote connection and validate new GUI.


## Final STARMER verification and candidate checkpoint

- Final isolated safe suite **27/27 PASS**, exit 0, stderr 0, captured under private temp run `RDC-G8H-regress-verified`.
- Embedded standalone Setup extracted and verified **18/18 PASS**, exit 0.
- Authentic Windows managed GUI/IPC test **PASS**, exit 0, original running Remote PID/birth unchanged; GUI cooperatively closed. Isolated event/mutex handoff **6/6 PASS**, exit 0; classic banner/uptime contract **8/8 PASS**, exit 0.
- Full Setup build exit 0, 20 manifest entries; Setup SHA256 `2691E0992876C2220630CFB35CD6A990A849B180429B52E8059041E35B0A6070`; Portable SHA256 `25A7FBE4300065D90BCC09F9EA2DFF6A24945C8C8411BF81AE88BF2EF56AC0A5`.
- Copied, hash-verified new Desktop candidate `RDC-Relay-1.6.0-RC1-Full-ClassicUI-Handoff-Setup.exe` and matching `...-Portable.zip`. Superseded AccountHeader Setup/Portable moved with SHA confirmation to `Desktop/RemoteDesktopCommander/Old_Installers_2026-10-29/G8H_Superseded_AccountHeader`. Stable v1.5.18 rollback Setup SHA256 `D4AD27F8569037E05F9F5E901F192979B42F7182BA455CF45D78FB596B6D9190` unchanged.
- All product changes committed to the existing Draft PR when submitted. The current installed RC1 Host/GUI and pinned Remote were **not** changed.
