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

## G8B — Owner's real Setup warned that automatic GUI launch failed

The owner installed the FULL AutoConnect Setup and received the actual warning
`Новые файлы и основной ярлык подготовлены, но автоматический запуск не удался`.
He observed a tray icon but no window, and tray reopen did not restore it.
This warning is generated only after candidate file/shortcut publication and
a nonzero/timeout result from the immediate Launcher. It does not reveal the
original Host exception. When independently inspected, the Desktop shortcut
again selected stable 1.5.18, which was already running.

The historical failure was **not reproduced** on the subsequently running
legacy Remote. Relevant bounded startup deadlines were only **12 seconds in
the Launcher and 18 seconds in Setup**, potentially classifying slow cold
PowerShell/WinForms initialization as failed. Corrected to **45/55 seconds**
while monitoring early Host exit. The Launcher returns only allowlisted
`RC1_*` exception codes; Setup redirects its two streams asynchronously and
shows the sanitized code in the warning instead of an uninformative generic
dialog. Arbitrary exception messages/paths are not sent to UI.

| Test / artifact | Confirmed result |
| --- | --- |
| Current installed RC1 direct `-Full` observer Host with stable external Remote | **PASS** — Host PID31052; GUI PID18884 / HWND330152; live Remote PID38372 unchanged |
| GUI X, installed Launcher reactivation, replacement GUI | **PASS** — old GUI gone, same Host retained, Launcher exit0, new GUI PID39712; 2 snapshot/event clients |
| Exactly scoped diagnostic Host/GUI cooperative cleanup | **PASS** — Host exit0, both owned run directories removed, stable GUI PID33944 / Remote PID38372 still alive |
| Rebuilt FULL candidate cold Launcher directly from staged executable, **without installation** | **PASS** — Launcher exit0, Host PID36068, GUI PID29220 with HWND; own Host/GUI then exited safely |
| Embedded Setup+Launcher static/negative checks | **15 PASS / 0 FAIL / exit0** |
| All isolated regression suites | **21 PASS / 0 FAIL / exit0** |
| Setup and Portable compilation, private payload hash/package check | **PASS / builder exit0**, 20 manifest entries |
| Owner's original automatic Setup launch with no old Remote | **NOT REPRODUCED / NOT CHECKED** for new candidate |
| Real new Job-owned Remote auto-start, connection and daily usage | **NOT CHECKED** without ending old session |

Candidate (not installed):
- Desktop `RDC-Relay-1.6.0-RC1-Full-LaunchFix-Setup.exe` and `RDC-Relay-1.6.0-RC1-Full-LaunchFix-Portable.zip` — exact post-copy SHA verified.
- Superseded AutoConnect files moved without deletion to `Desktop/RemoteDesktopCommander/Old_Installers_2026-10-28/Superseded_AutoConnect_G8B_2026-10-28`, original hashes verified and older archive contents preserved.
- Setup SHA256 `607B121451BFAAF777A980B99651A625D234E2FAF882275B5896CBC1BE493085`.
- Portable SHA256 `5296AD663E6DB17644B0BA9C333A006C963DE79290AE8CDD200002256177434D`.
- Existing 1.5.18 binaries and live Remote remained untouched; Draft PR #23, no merge or stable publication.

## G8C — 2026-10-29 repeat FULL Setup `RC1_AUTOLAUNCH_LAUNCHER_EXIT_42`

The owner installed the LaunchFix EXE and received the exact error code `RC1_AUTOLAUNCH_LAUNCHER_EXIT_42`. This means Launcher process returned 42; the **original inner exception is unknown**, not proof of a timeout. The subsequent rollback returned the Desktop main shortcut to 1.5.18 and the stable Remote remains available. A direct launch of the previously installed RC1 Launcher **did succeed** in the re-established environment, so the historical error could not be reproduced.

Product changes: bounded initial GUI spawn retry only when Host reports `NONE` after verified private ticket cleanup, never for `UNVERIFIED`; on continued initial GUI failure the product Host fails visibly instead of leaving a nonfunctional tray. Launcher accepts Host startup stderr asynchronously on its early-exit path and exports **only** `RC1_INITIAL_GUI_NONE` / `RC1_INITIAL_GUI_UNVERIFIED` or `RC1_HOST_EARLY_EXIT_<code>` to Setup. Arbitrary exception text and paths remain redacted. This changes only the new RC1 shell/IPC startup, not the Remote process lifecycle.

**Evidence on STARMER:** 21 of 21 regression suites PASS, exit 0; final standalone full Setup inspection/negative cases **18 PASS, 0 FAIL, exit 0**; new final candidate cold Launcher **exit 0** created actual Host PID31868 and responsive GUI PID17808 (HWND). X closed that GUI, next Launcher **exit 0** reopened GUI PID31208 with the **same Host**; both diagnostic GUI generations and Host ended cooperatively. Existing 1.5.18 launcher and pinned Remote remained unchanged; no real new Remote started by the candidate. Final standalone Setup SHA256 `E377BF5C123093A1C6DC16D2F13FB0F578BFC7F2C4773197DB75F438A1F5A849`, Portable SHA256 `DD582CC187E96B5681D6DB483599B28B0FC5E41D6B9BF58D9A599BA402500CA0`. These are **current Desktop files** `RDC-Relay-1.6.0-RC1-Full-StartupGuard-Setup.exe` and `RDC-Relay-1.6.0-RC1-Full-StartupGuard-Portable.zip`, not installed. Previous LaunchFix RC1 artifacts moved to `Desktop/RemoteDesktopCommander/Old_Installers_2026-10-29/Superseded_Full_LaunchFix` and intermediate StartupGuard artifacts archived, without deletion. Reserve fallback `RDC.Relay.Setup.v1.5.18.exe` remains on Desktop, SHA256 `D4AD27F8569037E05F9F5E901F192979B42F7182BA455CF45D78FB596B6D9190` unchanged. **Actual full Setup first-boot and new real managed Remote connection remain NOT CHECKED.** Draft PR #23 only, no release/merge.

## Next owner live trial (not executed)

1. When ready to tolerate a brief Remote connection interruption, back up the running work and complete a **normal owner-controlled shutdown** of the old 1.5.18 shell and its Remote. Never use taskkill by name or force-stop unknown processes. If old GUI remains running, the RC1 Host must continue to refuse spawning a duplicate.
2. Run the current Desktop FULL StartupGuard Setup, which retains old installed 1.5.18 files, updates the primary shortcut, and opens RC1. If the legacy Remote is still active, RC1 waits in read-only mode; once both legacy processes end, a 5-second stable absence permits managed startup and a replacement GUI. Never assert real Remote connected merely because Setup exit0 or Host/GUI is visible.
3. Verify actual new `npx.cmd` PID/birth, OS Job membership, log `Remote connected`, exact one Remote, authenticated GUI state and menu Stop/Start/Reconnect. Stop only the new explicitly owned Job after full owner confirmation. If failure, use preserved stable installer/shortcut for rollback; do not touch credentials or historic TEMP.
4. One independent risk-based review in existing Draft PR #23; no stable publication or merge.
