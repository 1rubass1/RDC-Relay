# RDC Relay 1.6.0 — offline Windows Sandbox RU/EN visual smoke

**Test-only procedure, not an installer or release gate.** 2026-11-18. Run only from an immutable Git commit; source and tests must be staged into a ZIP in an external temporary folder.

## Isolation

- Windows Sandbox configuration must explicitly disable networking, audio/video input, clipboard, printer redirection and vGPU, and should use at most 4 GiB RAM.
- Map Input (ZIP plus Tests/Sandbox-V16I18nGuest.ps1) into C:\RDC-I18n-Input, read-only. Map an empty Output directory to C:\RDC-I18n-Output, writable. All files must be in a dedicated folder outside the Git working tree.
- Guest script runs only nine known isolated PowerShell tests and saves six PNG screenshots of real WinForms Stop, Reconnect and Account Switch forms in RU/EN. The tests do NOT launch Desktop Commander Remote, the Host, the installed RDC Relay, Setup or any browser. No credentials, accounts or Remote session are required.
- Real window drawings, including actual title bars, are copied from the Sandbox desktop with System.Drawing.Graphics.CopyFromScreen and written as PNG into the mapped Output directory. Tests use current Sandbox desktop DPI; 125%, 150% and 200% need separate configured sessions/manual visual verification.
- Review Output/done.txt and Output/smoke-report.txt; six screenshots appear under Output/screens. A PASS report cannot prove live Host+GUI language switching, which needs a separately isolated Host simulation or a disposable VM without credentials.

## Required checks

1. Independently validate the exact source Git SHA and that all tests in the offline ZIP are from that revision.
2. Inspect test-only source scripts for external process, browser, network and installer side effects before launch. Only Windows PowerShell, local WinForms and safe synthetic data are permitted.
3. Verify 6 PNGs and 9 test result records, default-No confirmation flow, readable Russian and English text, no clipped labels, and Help/Account dialogs matching the accepted visual design.
4. If the Sandbox feature is unavailable or cannot start, mark the VM gate BLOCKED; source-level tests remain valid but must not be presented as Sandbox results.
5. Never enable a previously disabled Windows optional feature, modify the installed client or run a real Remote session without a separate explicit decision.

## Guest environment compatibility

The first isolated launch confirmed that Windows Sandbox starts but could not load the optional Microsoft.PowerShell.Archive module, so it failed **before any tests ran**. The guest bootstrap now uses System.IO.Compression.ZipFile.ExtractToDirectory from .NET instead. This change is confined to test setup and has no effect on RDC Relay code.

## Automated evidence

`Tests/Test-V16OwnerSandboxVisual.ps1` creates RU/EN screenshots using the actual dialog factories and resource reader. `Tests/Sandbox-V16I18nGuest.ps1` is the WSB LogonCommand entry point. Both deliberately operate on a ZIP copied into the disposable guest; they never read the live project worktree from inside Windows Sandbox.

**Do not merge/release solely on this smoke.** Visual UI review, full Host/Remote integration, Setup/Upgrade/Repair/Uninstall and rollbacks remain separate.
