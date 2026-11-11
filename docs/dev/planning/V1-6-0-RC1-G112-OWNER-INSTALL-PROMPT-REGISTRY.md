# G112 — Owner Pilot installation prompt: registry and shortcut evidence

**Date:** 2026-11-11. **Status:** Programmer completed test candidate; owner GUI visual approval and independent Reviewer pending. **NOT A PUBLIC RELEASE.**

## User requirement

Prepare the next test installer to see the actual installation confirmation. For an existing installation, show **one line only**:

> Установить RDC Relay 1.6.0 RC1 как основную оболочку?

Version comes from the validated embedded `owner-source-manifest.json`. The Yes/No dialog defaults to No. Do not display technical paragraphs about rollback, Old Remote or retained files. On a genuinely clean system, do not ask whether to replace an earlier shell.

The user explicitly corrected the earlier prototype: use registered Installed Apps **and** the primary Desktop shortcut, while preserving the unique Owner Pilot fast rollback, where stable version 1.5.18 remains registered even when RC1 is the active GUI.

## Changes

- `Installer/Rc1CandidateSetup.cs`: added **read-only** registry checking in HKCU for `Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\RDC Relay`. Validate exact `DisplayName=RDC Relay`, historical `UMAS` or new `RUBASS`, numeric `DisplayVersion` identical to installed stable `version.txt`, matching `InstallLocation`, existing stable GUI and updater. Check HKLM uninstall records across 64/32-bit registry views, fail closed if a machine-wide RDC Relay installation is registered. Orphan stable files without the uninstall key, unexpected identity, and version inconsistencies fail closed.
- Existing Desktop shortcut probe is retained as **secondary evidence of prior pilot handoff**; actual replacement is performed by the existing `RdcRc1ManualUpgrade.ActivateDesktop` safe transaction, not this probe. Confirmation is shown for a valid registration **or** existing primary shortcut. A genuine absence of both produces no replacement prompt.
- No User Pilot registry write, logout, Remote stop, change of default Yes/No, or stable rollback mutation was introduced.
- `Tests/Test-V16ManualSetupPrompt.ps1`: updated source order assertions, actual compiled Setup helper, pure synthetic good/bad registry scenarios for UMAS/RUBASS, version mismatch, unknown publisher, missing files, wrong location, and both fake Desktop shortcut states.

## Tests and artifact evidence

- Owner Pilot prompt contract: **28/28 PASS**.
- Full isolated safe RC1 regression: **47/47 PASS**, exit 0.
- Standalone production Setup extraction/manifest and code guard: **19/19 PASS**, exit 0.
- Full Build: **21 hash-verified manifest payload members**. Setup compiled and staged, **never executed on installed system**.
- New STARMER Desktop: `RDC-Relay-1.6.0-RC1-InstallPrompt-Setup.exe`, SHA256 `C46A388476985D51124F355B19D7037E7A836F0EADE89BEE89B2DA2481EB77D0`.
- New STARMER Desktop: `RDC-Relay-1.6.0-RC1-InstallPrompt-Portable.zip`, SHA256 `E6F8E7BA532AF3855FAF47AFFF8C2EC9D0F5CCB87AFE664C79035A26DFB478A4`.
- Previous G110 AccountSettings Setup/Portable hash verified, archived under `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G112_Superseded_AccountSettings`.
- Stable 1.5.18 rollback installer SHA256 `D4AD27F8569037E05F9F5E901F192979B42F7182BA455CF45D78FB596B6D9190` preserved.

## Pending

**Owner must visually inspect on their monitor**, since tests do not click the live Setup's modal. Registration behavior is verified by read-only/synthetic checks but NOT by executing Setup or mutating live ARP. Review is independent. Existing stable install, Remote, GUI, user shortcuts and credentials remain untouched. No public release, merge or update feed changes.
