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
- Standalone compiled RC1 Setup extraction/manifest/launcher check: **19/19 PASS**, 22 attested payload entries. Post-G121-fix private Setup SHA-256 `05C9DF9DB389B97A20B5078217830258CCB3B2B3D18D0C459244CF8CC065245E`; Portable SHA-256 `10090CC3742177FAD3F75A8B514A564B992D8A2C9AE6796B1A830C201B263A54`. Compiled but **not installed or copied as an Owner-approved installer**.
- Windows **fake-only OS smoke**: normal 1× GUI close/reopen with duplicate Host and IPC negative checks **20/20 PASS**, injected GUI Process.Start failure and recovery **20/20 PASS**, injected constructor failure and recovery **18/18 PASS**. Each successful run had no survivors and attested exact-file cleanup; previous NOT CLEAN diagnostics were preserved. 10-cycle stress run with 11 authenticated GUI generations, exact process identity, no duplicate Host, zero surviving trial processes and G7 attested cleanup: **48/48 PASS**, exit 0.
- **Pending:** independent Reviewer and owner physical Windows 16/20px tray/GUI visual acceptance. No authenticated live Remote integration test.

## Restriction

Do not install, publish or merge this candidate until independent Reviewer and owner pilot acceptance. Fake-only OS smoke is now complete. The approved main application icon v04 remains separate. No user account or private Remote integration test was performed.
