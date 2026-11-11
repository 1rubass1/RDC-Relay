# G122 — approved tray v04 and non-destructive GUI reactivation

**Date 2026-11-11.** Work-in-progress RC1 implementation on isolated branch `feature/rc1-tray-v04-gui-reactivation`, [Draft PR #25](https://github.com/1rubass1/RDC-Relay/pull/25), [Issue #24](https://github.com/1rubass1/RDC-Relay/issues/24). No install, public release or merge.

## Source and immutable visual contract

Owner explicitly approved the Designer's `Desktop/RDC Relay - Значок 04/Трей/` graphics and preview on 2026-11-11. Old `REVIEW.md` phrasing 'approval pending' is superseded by that confirmation. All source PNG/SVG remain in Designer's folder, untouched.

`Scripts/Generate-TrayV04Bundle.py` is an **inert, developer-invoked**, standard-library-only Python 3 script. It validates exactly 64 RGBA PNG assets (8 base states × 8 sizes) and creates `Source/RdcTrayV04.bin` (188483 bytes, **29 cached Win32 ICO frames**; each frame contains exact 16/20/24/32/40/48/64/256px PNG-backed icon entries). 29 frames = 7 stable/base frames, 10 opacity steps for working, 12 transitional color frames for connecting/authorization. The bundle is used only by private Owner Host and strictly attested at runtime and build time:

`607D271A09983A407F3E8CC8560A93DC59385C18DCEC08ECA1740318C2B1AD59`

WinForms `NotifyIcon` uses Windows `SystemInformation.SmallIconSize`, choosing source 16/20/24px assets appropriately for DPI instead of default 32px scaling. Only preloaded and cached `System.Drawing.Icon` frames are assigned on ticks; retired icons/streams and timers are disposed after the NotifyIcon is hidden and disposed. No per-frame GDI allocation, rasterization or network lookup.

## Six states

| Authoritative Host `state` + activity | Icon and motion |
| --- | --- |
| `Disconnected` / unknown | `offline` grey halves, transparent center |
| `Connecting` / `Reconnecting` | `connecting-a/b`; orange ↔ grey; 0.8s half-cycle and 160ms 25/50/75% transition frames |
| `AuthPending` | `auth-a/b`; orange ↔ purple, same timing |
| `Ready` and `toolActivity=idle` / `hold` | `ready`; orange halves, solid green center; no hold pulse |
| `Ready` and `toolActivity=working` | `work-00..09`; orange halves, purple center pulsing 100→45→100% with eased 1.8s cycle |
| `Fault` | `fault`; grey halves, solid red center; overrides tool activity |

Windows reduced-motion (`SPI_GETCLIENTAREAANIMATION`) chooses static first-phase connecting/auth frames and a full-opacity working center. Status tooltip is updated only on a semantic state change, not on an animation frame. The Host's 250ms supervisor snapshot polling is separate from a 40ms cached-icon animation timer.

## Reliable GUI opening from tray / launcher

`Source/RdcOwnerRuntime.cs` now validates tracked GUI PID, session and process birth before activating an existing child. It refreshes the cached MainWindowHandle and, if missing, finds the release-specific `RDC Relay 1.6.0 RC1` top-level window **of the same verified PID** (excluding versionless About/Journal modals); prevents adopting any similarly titled foreign process. Minimized or hidden windows are restored. The Win32 foreground result is checked; Windows foreground-lock denial signals bounded taskbar flash + rate-limited tray explanation instead of falsely claiming the window has opened. Zero-HWND, unverified child and categorized startup failure paths do not force kill or start duplicate GUI/Host/Remote. No Alt injection, permanent TopMost or window-position override.

## G121 launch failure — reproduced and corrected

During the first genuine fake-only Host→Owner GUI OS smoke, the product failed before displaying the window. G121 had removed the Help context-menu item `$openLogItem` from `Source/remote-window.ps1`, but **two live OwnerGui references** to `$openLogItem.Enabled` remained in `Source/rc1-owner-gui.ps1` (startup and snapshot refresh). PowerShell raised `PropertyNotFound` and the process exited; earlier Preview tests never exercised authenticated OwnerGui startup. This is the confirmed root cause of the G121 window-not-opening regression.

Both stale references were removed; the new About dialog's left-hand `Показать журнал` button uses the authenticated Host `sanitizedJournal` capability at startup and each snapshot. The initial `$initialCapabilities` assignment is now validated **before** any field reads. The G121 route regression and Owner boundary checks reject stale menu dereferences and test allowed/denied journal capability. The corrected product successfully opened two genuine GUI generations through the disposable Host.

Two failed preliminary OS diagnostic fixtures (one missed `rc1-quota-client.ps1` in the G7 allowlist and one reproduced G121 startup crash) are **NOT CLEAN** and remain protected, not forcibly removed. The exact fixture allowlist now contains the required quota client and tray binary.

## Package and safety boundaries

Updated full RC1 private builder `Scripts/build-rc1-full.ps1`, private Setup's exact embedded payload allowlist (`Installer/Rc1CandidateSetup.cs`), and launcher's Source preflight (`Installer/Rc1CandidateLauncher.cs`) to require and hash the new bundle. Isolated OS fixture manifest includes the bundle. Stable public v1.5.18 updater, installed stable and registered shortcuts, live Remote/Host, account and registry were **not touched**.

## Verification

- Production C# compiled with installed .NET Framework csc; approved ICO bundle loaded with a real invisible WinForms NotifyIcon.
- `Tests/Test-V16TrayV04Visual.ps1`: **21/21 PASS**, including exact SHA, all 29×8 PNG-backed ICO entries, host state precedence, 160ms fades, 1.8s eased working pulse, reduced motion, real NotifyIcon, 500 icon substitutions with GDI resources 91→91, and tampered bundle SHA rejection.
- `Tests/Test-V16TrayGuiActivation.ps1`: **14/14 PASS**, including Owner release-title window discovery, wrong PID refusal, excluded About dialogs and no competing GUI process.
- Complete isolated RC1 safe regression **54/54 PASS** (fresh post-G121-fix run). Updated historical `Test-V16OwnerBoundaryStatic.ps1` to assert the new Host-authorized About journal button rather than the deleted context-menu item; targeted **26/26 PASS**. Four required historical G0/G4 test fixtures were verified in ignored `dist/` in this isolated worktree. The earlier runs with missing fixtures and an obsolete assertion were not new product-code failures.
- Standalone compiled RC1 Setup extraction/manifest/launcher check: **19/19 PASS** on the final private G122 Setup, 22 attested payload entries. Post-G121-fix private Setup SHA-256 `4E4C1D9BACBC12015D2E3D1F1FF0E46D4182E6395833D8AC290665A997F33ABA`; Portable SHA-256 `B4FF22EFC20B28258D21A5CE09B673D20EAEF01ECDBE4E7AD6C5B84142A7752C`.
- **Desktop final staging (NOT installed):** `RDC-Relay-1.6.0-RC1-G122-TrayV04-Setup.exe` SHA-256 `4E4C1D9BACBC12015D2E3D1F1FF0E46D4182E6395833D8AC290665A997F33ABA`; `RDC-Relay-1.6.0-RC1-G122-TrayV04-Portable.zip` SHA-256 `B4FF22EFC20B28258D21A5CE09B673D20EAEF01ECDBE4E7AD6C5B84142A7752C`. Both Desktop files now match the compiled and tested final package `dist/RDCRelay-1.6.0-RC1-Full-298802ca961b42a5a817d90b1a6aa518`. The earlier G122 Desktop Setup and Portable pair was atomically replaced with exact-hash backups under `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G122_Superseded_PreCommit_Candidate/`. Original G121 NativeHelpJournal files remain archived in `G122_Superseded_NativeHelpJournal/`. Desktop was confirmed as an expected OneDrive cloud reparse point (tag 0x9000601a); backup directory and leaf files were checked as non-reparse. Stable v1.5.18 rollback Setup was rechecked unchanged. **No installation; independent Reviewer and Owner visual acceptance still pending.**
- Windows **fake-only OS smoke**: normal 1× GUI close/reopen with duplicate Host and IPC negative checks **20/20 PASS** (additional no-duplicate baseline **17/17 PASS**), injected GUI Process.Start failure and recovery **20/20 PASS**, injected constructor failure and recovery **18/18 PASS**. Each successful run had no survivors and attested exact-file cleanup; previous NOT CLEAN diagnostics were preserved. 10-cycle stress run with 11 authenticated GUI generations, exact process identity, no duplicate Host, zero surviving trial processes and G7 attested cleanup: **48/48 PASS**, exit 0. Owner clarified that an earlier observation of repeated GUI openings could have been this interrupted-visibility stress test; spontaneous production looping is **not independently reproduced** and must not be reported as a confirmed defect.
- **Pending:** independent Reviewer and owner physical Windows 16/20px tray/GUI visual acceptance. No authenticated live Remote integration test.

## Restriction

Do not install, publish or merge this candidate until independent Reviewer and owner pilot acceptance. Fake-only OS smoke is now complete. The approved main application icon v04 remains separate. No user account or private Remote integration test was performed.

## Owner-driven visual iteration: quiet Help button (2026-11-12)

The owner explicitly switched this phase to direct owner visual acceptance with the independent Reviewer deferred until the owner considers the pilot ready. This supersedes the reviewer-first timing in the restriction above **only for private iterative owner testing**; it does not approve public release, merge, unattended installation, changes to the installed stable version, or live Remote operations by the Programmer.

`Source/remote-window.ps1` keeps the existing native Windows blue `SystemIcons.Question` glyph and `Windows.Forms.Button` in the title row. It sets both `FlatAppearance.MouseDownBackColor` and `MouseOverBackColor` to the button's existing background; `FlatStyle.Flat` and `BorderSize=0` remain. A small `MouseDown` event and the existing direct About click route clear the mouse-acquired `Form.ActiveControl` (after returning from About), without adding a custom WinForms control or changing the three-target `TabStop` traversal. This is a **simple first trial**, not a claim of subjective physical focus-ring elimination on all Windows themes/DPI; the owner will inspect that personally.

`Tests/Test-V16OwnerHelpJournalRoute.ps1` extended to **24/24 PASS**: source parsing, explicit quiet hover/press properties, retained TabStop/accessibility, real native WinForms focus clear on mouse press and post-About, direct click once, retained journal and Host capability checks. Full fake-only safe regression **54/54 PASS**; standalone compiled Setup extraction/manifest **19/19 PASS**; one-cycle disposable Host/GUI OS smoke **17/17 PASS**, zero trial processes and G7 attested cleanup. Stable v1.5.18 and running Remote remained untouched. No real Remote or physical visual acceptance was claimed.

New private, uninstalled desktop candidate: `RDC-Relay-1.6.0-RC1-G122-HelpQuiet-Setup.exe`, SHA256 `8280C14D43A9E0DB787D612EE0EFBB05A4AF39D19FC5986A81F130B6E1C0DE15`; `RDC-Relay-1.6.0-RC1-G122-HelpQuiet-Portable.zip`, SHA256 `458D89F7A6C9E9D4A83C80EECFA84734767213940006DBE184C19763608772C0`. Both staged with SHA checks from `dist/RDCRelay-1.6.0-RC1-Full-a9231d14ab904bdfbba403eec5760ef0`. Previous G122 TrayV04 Setup and Portable were moved with their exact SHA verification into `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G122_Superseded_PreHelpQuiet/`, preserving rollback artifacts. The new Setup was **not executed**. Next gate is the owner's physical Windows Help icon test.

## Owner iteration: deferred startup no-window notice (2026-11-12)

The owner reported a premature tray message ("GUI window has not appeared; try opening it through the tray again") immediately before the freshly upgraded RC1 GUI appeared normally. The cause was in `Source/RdcOwnerRuntime.cs`: an immediate `OpenGui()` retry could report `NO_WINDOW` while the WinForms window was still initializing; a separate `RefreshGui()` poll warned at seven seconds. Neither condition by itself proves a GUI launch failure.

Selected a **time-based grace of eight seconds**, not a second-attempt threshold. `RdcOwnerGuiStartupNotice.IsDue()` is an isolated pure predicate shared between the windowless `OpenGui()` path and the periodic `RefreshGui()` check. It requires an actual GUI-spawn timestamp, at least eight seconds elapsed, no confirmed owned HWND, and no previous warning for that GUI generation. Windowless activation during the grace period remains silent and never starts a duplicate child. The periodic probe warns once after the grace if the actual owned window still does not exist. Existing verified-child identity checks, unverified-child fail-closed decisions, foreground-lock feedback, launch errors, 250ms polling and Remote process ownership remain unchanged. There is no blocking eight-second sleep, UI freeze, extra restart, or extra Remote request. The one-shot latch resets on the next GUI generation.

`Tests/Test-V16TrayGuiActivation.ps1`: **17/17 PASS**, including real compiled C# predicate at launch, 7.999s, 8s and 12s, already-warned and owned-window cases; original 14 window/identity/activation checks retained. RC1 fake-only safe regression **54/54 PASS**; newly compiled standalone Setup integrity check **19/19 PASS**; isolated one-cycle fake Host/GUI OS smoke **17/17 PASS**, 0 surviving own fixture processes, attested cleanup. Real user's installed GUI boot and subjective notification timing are **NOT CHECKED** by automation and await owner acceptance.

New owner-desktop candidate (NOT installed): `RDC-Relay-1.6.0-RC1-G122-GuiStartupGrace8-Setup.exe` SHA256 `313339323A12D105182FF3D3C8B3BD588AE81D7AB5FD5AB3DC14E5236CB40001`; `RDC-Relay-1.6.0-RC1-G122-GuiStartupGrace8-Portable.zip` SHA256 `B486FCEB0591B45C5EEABA8318AF0FA8B1999E9D0CED53E1709D014E6896A09F`. Exact source build stage: `dist/RDCRelay-1.6.0-RC1-Full-563da54610ef4dd5922e99984f7ed577`. Previous HelpQuiet pair was SHA-verified and moved to `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G122_Superseded_PreStartupGrace8/`. The new pair's desktop hashes match stage. Installed stable v1.5.18, running Remote, accounts, live Host, registry, old NOT CLEAN test fixtures and release branches untouched. Independent Reviewer remains deferred by owner's instruction until the owner considers the candidate ready.
