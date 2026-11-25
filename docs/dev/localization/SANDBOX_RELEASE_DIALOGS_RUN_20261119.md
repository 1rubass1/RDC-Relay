# RDC Relay 1.6.0 — offline release-dialog visual smoke (Windows Sandbox)

**Date:** 2026-11-19. **Result:** PASS, prepared native RU/EN dialog previews and safe source-level tests. **NOT public installer acceptance / release GO.**

## Final tested snapshot and immutable input

- Git commit: `151c66a1a2901cc48cc1e3c8849ca3e41ce826c3`.
- Git-archive source ZIP SHA-256: `5dbd3104dcd01ce52b601a19e1241ef08f12478844917b92fc914037e72f3fda`. Contents: `Source`, `Installer`, `Tests`, `Scripts`, `Assets`.
- Offline Windows Sandbox configuration: `[local project root]\_archive\RDC_ReleaseVisual_151c66a_20261119\RDC-Release-Visual.wsb`.
- Guest has networking, clipboard, vGPU, audio/video input and printer redirection disabled. Input mapped read-only, Output separately writable for reports and PNG only.
- Guest `Output\done.txt` reads `PASS`; `Output\sandbox-release-report.txt` records all seven successes, `NO_SETUP_LAUNCH=true`, `NO_REMOTE_HOST=true`, exact revision and ZIP hash.

## Real guest Windows test results

| Guest suite | PASS | FAIL |
| --- | ---: | ---: |
| `Test-V16ReleaseInstallerLanguage.ps1` | 60 | 0 |
| `Test-V16ReleaseMaintenance.ps1` | 35 | 0 |
| `Test-V16ReleasePathDialog.ps1` | 21 | 0 |
| `Test-V16ReleaseInstallPolicy.ps1` | 27 | 0 |
| `Test-V16TrayV04Visual.ps1` | 89 | 0 |
| `Test-V16OwnerQuotaFooter.ps1` | 35 | 0 |
| **Six behavioral suites** | **267** | **0** |
| `Test-V16ReleaseInstallerSandboxVisual.ps1` | **12 PNG** | **0** |

## Windows visual results

- Guest DPI: **96 × 96 (100%)**. Native window screenshots are **636 × 291 px** for path selection and **636 × 277 px** for maintenance.
- RU and EN screenshots cover `path-fresh`, `path-existing`, `maintenance-upgrade`, `maintenance-repair`, `maintenance-newerinstalled`, and `maintenance-refuse` (12 total). Images in `Output\screens` outside Git.
- At 100% text is legible, headings and buttons fit, and native dialog layouts remain balanced. Blocked/downgrade modes show **Close only**; existing folder is read-only with disabled Browse; fresh folder offers Browse. No transaction action buttons were clicked.
- First preview (commit `f96b5e9`) found an existing-folder button inconsistency: the explanatory sentence said an update would occur but the button said Install. Fixed in `151c66a` using `installer.path.continue`: **Продолжить / Continue** for verified existing folder, **Установить / Install** for Fresh. The final two affected RU/EN screenshots were manually inspected and correctly display the new labels.
- The official quota percentage / `--%` display and language-dependent tray caption are checked by native NotifyIcon source tests, **not by an actual mouse-hover screenshot**. This boundary must be retained in release evidence.
- Standalone RU/EN embedded catalog now has **36 keys**, with **29 source-bound prepared release Setup keys** and seven legacy-Setup proposals intentionally unconnected; ten older (original-68) keys remain unwired for separate legacy/duplicate reasons.

## What remains outside this pass

- Neither the **public 1.6.0 full-Host installer** nor any actual Install/Update/Repair/Uninstall action was built or launched. No files, ARP registration, shortcut, Remote process, host-installed app or real account were changed.
- OS scaling at 125%, 150% and 200%, high contrast, screen readers, UAC elevation prompts, full Host/GUI first launch, migration from verified 1.5.18 + RC1 pilot, rollback and hard-kill/power-loss recovery remain **NOT CHECKED**.
- The legacy public builder's v1.6 blocker stays intact. Next engineering gate is a separate reproducible **transactional full-Host/GUI Setup** with durability/rollback and a disposable OS migration matrix, not another cosmetic change.

**Release GO remains closed.**
