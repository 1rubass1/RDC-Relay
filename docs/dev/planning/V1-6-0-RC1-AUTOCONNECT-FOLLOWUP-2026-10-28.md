# PROG-006A-G8A — Owner-reported disconnected Adopted shell and automatic Remote handoff (2026-10-28)

**Branch:** `feature/v1.6-host-gui-owner-pilot` · **Draft PR:** #23 · **Status:** source+candidate prepared, owner install and real newly Host-owned Remote trial **NOT CHECKED**. The owner explicitly keeps installed **v1.5.18** running during this correction.

## Failure evidence / actual root cause

Owner live screenshot of previously installed 1.6.0 RC1 shows `существующий Remote (только чтение)`, `Remote: Disconnected`, `Existing Remote identity lost; observing without control`, footer `Remote PID 23444 / Adopted`, with disabled stop. The owner restarted Remote, so the old PID is historical and cannot be reused for identity. After rollback through the original 1.5.18 GitHub Setup, current STARMER original GUI PID **22388** and its pinned `npx.cmd @wonderwhy-er/desktop-commander@0.2.52 remote` PID **14016**, birth ticks **639288039147159843**, were independently observed. The desktop shortcut once again targets `%LOCALAPPDATA%\RemoteDesktopCommanderLauncher\remote-window.ps1`. The owner reports stable 1.5.18 installer rollback worked.

Code root causes:
1. Full Host chose `OBSERVED_READ_ONLY_RC1` when previous 1.5.18 Remote was running. This was deliberately immutable, but **never promoted** to managed mode when the old GUI and Remote both ended.
2. With no external Remote, `EnableManagedRemote()` initialized a disconnected state, but **did not attempt automatic start**. OwnerGui required an explicit Start click and could appear broken.
3. Historical observed PID could disappear/restart while the GUI retained read-only mode. The original observer only reacquired a verified replacement PID or displayed `Disconnected`; it never offered a safe pending handoff.

## Corrected product behavior

- Full Host now calls `TryAutoStartManagedRemote()` when no verified existing legacy Remote can be attached. The actual private kernel-Job launcher remains the **only** new-Remote creation route.
- A real external Remote **or** other original `remote-window.ps1` GUI blocks all new Remote spawns. OS discovery failures fail closed. External blockers are retried no more frequently than every 5 seconds; a real launch error remains visible and requires user action.
- On lost Adopted identity, Observer first attempts PID+birth+session+commandline reacquisition. Only if no replacement and **both** legacy shell and all other Remote launchers are absent continuously for at least 5 seconds can Host reset Adopted PID/health/journal, switch to Managed and trigger its **own** Remote auto-start.
- Transition increments `closeGeneration`; previous read-only GUI closes itself, then the Host opens a fresh GUI ticket in Managed mode. No external process is killed or imported as Owned.
- Original GUI now explains pending safe handoff. Downloadable Setup warns explicitly that existing 1.5.18 Remote remains active/read-only until owner deliberately completes a normal old-session shutdown. It never claims that installation alone caused a new connection.
- Account switch is not claimed working. Failed/uncertain owner scans and foreign process identity remain denied. Full standalone RC1 is still not published to stable.

## Verified evidence on STARMER

| Check | Actual result |
| --- | --- |
| Observer mocked absence / 5-second grace / final denial | **22 PASS/0 FAIL/exit 0** in `Test-V16ObservedRemote.ps1` |
| State-store fake/synthetic promotion to Owned PID=0, no stop rights | **PASS** in safe regression, no real process control |
| WinPS 5.1 product host/GUI C# compile and AST | **PASS**, safe suites |
| All 21 allowed isolated regression suites | **21 PASS/0 FAIL/exit 0** |
| New full Setup+Portable stage, 20 pinned payload entries | **PASS**, builder exit 0 |
| Current existing v1.5.18 GUI and Remote PID/birth | **PASS**, observed alive, no new Host or Remote started |
| Real new managed Remote automatic start / authentication / physical GUI and cutover | **NOT CHECKED**, owner keeps stable 1.5.18 running |

**Current Desktop distributables, uninstalled:**

- `RDC-Relay-1.6.0-RC1-Full-AutoConnect-Setup.exe` — SHA256 `F2B5B9487800C2D66D28DF23125D675C2B942B42610EEA708DF1C2F3CEBB508C`.
- `RDC-Relay-1.6.0-RC1-Full-AutoConnect-Portable.zip` — SHA256 `517B08E2A0C8F945F5791C488572237E40E03E90E0FF8DA8074A304EC497A41E`.

Desktop cleanup requested by owner: four earlier root installers/archives (previous Full Setup/Portable, Observer-TEST Setup and stable v1.5.18 rollback installer) moved without deletion to `Desktop\RemoteDesktopCommander\Old_Installers_2026-10-28`; the initial pre-notice AutoConnect candidate was also archived there. Only the two newest unambiguous AutoConnect distributables remain on desktop. Installed v1.5.18 and its live genuine Remote remained untouched.

## Next owner live trial (not executed)

1. When ready to tolerate a brief Remote connection interruption, back up the running work and complete a **normal owner-controlled shutdown** of the old 1.5.18 shell and its Remote. Never use taskkill by name or force-stop unknown processes. If old GUI remains running, the RC1 Host must continue to refuse spawning a duplicate.
2. Run the new Desktop FULL AutoConnect Setup, which retains old installed 1.5.18 files, updates the primary shortcut, and opens RC1. If the legacy Remote is still active, RC1 waits in read-only mode; once both legacy processes end, a 5-second stable absence permits managed startup and a replacement GUI. Never assert real Remote connected merely because Setup exit0 or Host/GUI is visible.
3. Verify actual new `npx.cmd` PID/birth, OS Job membership, log `Remote connected`, exact one Remote, authenticated GUI state and menu Stop/Start/Reconnect. Stop only the new explicitly owned Job after full owner confirmation. If failure, use preserved stable installer/shortcut for rollback; do not touch credentials or historic TEMP.
4. One independent risk-based review in existing Draft PR #23; no stable publication or merge.
