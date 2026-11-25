# RDC Relay 1.6.0 — isolated release-dialog and tray visual smoke

**Date:** 2026-11-19. **Scope:** source-built prepared Setup dialogs and tray UI, NOT installing an application.

**Visual review correction (2026-11-19):** The first 12 screenshots exposed a copy mismatch: the existing-install folder screen said the application would be updated but offered an `Install` button. Because this reusable dialog may precede either Update or Repair, its existing-root primary button is now **`Продолжить / Continue`**. The Fresh screen retains **`Установить / Install`**. This added one bilingual `installer.path.continue` display key; the standalone embedded catalog has 36 keys per locale, with 29 wired in prepared Setup dialogs and 7 preserved legacy draft keys. No transaction behavior was changed. A second independent Windows Sandbox run has now **passed** on commit `151c66a`; full evidence is in `SANDBOX_RELEASE_DIALOGS_RUN_20261119.md`.

## Goal and execution boundary

A dedicated offline Windows Sandbox compiles the **real** C# `Installer/RdcReleasePathDialog.cs`, `Installer/RdcReleaseMaintenanceDialog.cs`, `Installer/RdcReleaseMaintenancePolicy.cs`, `RdcReleaseUiLanguage.cs` and compiled RU/EN catalog. It opens native WinForms preview windows using `Show()`, captures PNGs and immediately disposes each window **without** clicking `Install`, `Update`, `Repair`, or `Uninstall`, calling `ShowDialog()` or executing any Setup transaction. No Desktop Commander Remote or connected account is used.

### Expected screenshots (12)

| Locale | Prepared release-only windows |
| --- | --- |
| ru-RU | Path fresh, Path existing/readonly, Upgrade, Repair, NewerInstalled/downgrade refusal, Pilot migration refusal |
| en-US | Same six windows |

The forms must retain Cancel/Escape semantics, readonly existing install path, blocked states with no destructive actions, and controls within window bounds. The actual guest OS DPI is recorded; **passing 96 DPI cannot be generalized to 125–200%**.

### Guest automation

`Tests/Sandbox-V16ReleaseVisualGuest.ps1` validates a SHA-256 Git snapshot, extracts only into guest, runs seven source-level suites (including native tray visual tests verifying the center `--%` placeholder), then calls `Tests/Test-V16ReleaseInstallerSandboxVisual.ps1`. Writes `Output/sandbox-release-report.txt`, `Output/done.txt`, `Output/screens/*.png`. Any failure produces a FAIL sentinel and retains reports for inspection. No attempt to open installers, modify ARP/shortcuts or initiate real Remote.

The `.wsb` is generated outside Git, with networking, vGPU, microphone, camera, clipboard and printer forwarding disabled; mapped ZIP input is read-only and a separate Output folder is writable.

### Still not release GO

The **public** 1.6.0 full-Host Setup transaction, stable 1.5.18 and private pilot migrations, update/repair/uninstall, durable rollback/kill recovery and user-approved distribution are incomplete. The legacy 1.5.x builder remains hard blocked for public v1.6. A passing screenshot is not evidence of a working install.

### Manual review checklist

Open PNGs for both languages and compare heading, description wrapping, path textbox and button spacing. Check that refusal/downgrade screens only offer Close, that fresh path displays Browse, and an existing path disables Browse. Any clipping, misaligned buttons or accessibility issues should be corrected before connecting the 1.6 installer transaction.
