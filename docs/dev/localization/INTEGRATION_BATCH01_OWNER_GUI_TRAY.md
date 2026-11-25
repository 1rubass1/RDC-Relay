# RDC Relay 1.6.0 — language integration batch 01 (Owner GUI + Tray)

**Date:** 2026-11-18. **Branch:** fix/rc1-tray-exit-prompt. **Scope:** new GUI/tray language selection, bounded per-user preference and test resources. No live Host/Remote, installed product, credentials or public release touched.

## Implemented at source level

- **Owner GUI**: Account menu gains a native **Язык / Language** submenu with **Русский** and **English**, and selected-locale checkmarks. GUI updates the window title, Account/Devices/Reconnect/Update/Quota menu captions, accessibility labels and tooltips. It reads a changed tray-side preference once per second, without Remote IPC. This batch does NOT yet localize every status, dialog or journal line.
- **Host tray**: native menu adds the same two language options. Existing action captions, Start/Stop, checkboxes and tips are displayed from validated locale resources on menu opening. New LANGUAGE_RU/LANGUAGE_EN actions are handled BEFORE the existing Host/Remote action dispatcher.
- **Preference**: Source/RdcUiLanguage.cs provides shared C# preference and catalog handling for the C# Host and PowerShell GUI. Per-user path: %LOCALAPPDATA%\RDCRelay\ui-language.json. Explicit small JSON: {"version":1,"locale":"en-US"} or ru-RU. Invalid/unsupported/missing input falls back to Russian; missing setting is not created. Writes use a unique temporary file and atomic File.Replace; no Remote credential store is touched. Fresh-install Windows UI language suggestion is NOT implemented yet.
- **Resources**: Source/lang/ru-RU.json and Source/lang/en-US.json each contain 93 matching semantic keys with status INTEGRATION_TEST. The reader enforces fixed locale/schema/status and bounded UTF-8 values, with explicit Russian fallbacks. Strings are only displayed, never executed or interpreted as IPC or provider protocol values.
- **Full private RC1 package**: Scripts/build-rc1-full.ps1, Installer/Rc1CandidateSetup.cs, Installer/Rc1CandidateLauncher.cs and Scripts/rc1-private-upgrade-transaction.ps1 now explicitly include the new C# source and both JSON files. The full builder creates the nested Source/lang folder during staging. The candidate was NOT built or installed here. Historical observer/owner staging variants are not yet migrated and must be separately checked before reuse.

## Safety invariants

- Tray START/STOP still depends on ownedRunning, not StartStopItem.Text. GUI action caption depends on the validated Host capability ownerCanStop, never on display text.
- All Host private Job/adopted-read-only ownership, Remote verbs, IPC protocol, account login and raw vendor parsing stay untouched.
- No motion or animation change. Only a bounded local file is polled once per second; this does not initiate a Remote call.
- Missing/invalid resources fall back to original Russian UI strings; existing installations without a setting remain Russian.
- Public Build-Release.ps1 stays blocked for RC1/1.6; development previews and docs/dev are not packaged.

## Targeted tests (isolated only; no running Host, GUI or Remote)

| Test | Result | What it proves |
| --- | --- | --- |
| Test-V16ProductHostGuiSource.ps1 | 22 PASS / 0 FAIL | Production Host+IPC compiles into disposable .NET Framework DLL with new language source |
| Test-V16OwnerTrayMenu.ps1 | 50 PASS / 0 FAIL | Actual native tray menu class/renderer, localized captions, language-only dispatch and START/STOP independence |
| Test-V16OwnerQuotaFooter.ps1 | 35 PASS / 0 FAIL | Existing quota and footer invariants |
| Test-V16OwnerLanguage.ps1 | 25 PASS / 0 FAIL | Malformed/unsupported/missing preference, JSON bounds and fallback, locale resources, source parser and full package allowlists |

**NOT TESTED:** real GUI/snapshot interaction, Host+GUI cross-process switching, installed build, tray geometry at DPI 100–200%, new-install language choice, any Setup/Repair/Uninstall or Windows Sandbox. An isolated PASS must not be reported as live product PASS.

## Next steps

1. Localize safe Owner connection status and detail presentation; then complete dialogs, journal, notifications and Help/About without translating any state or provider markers. The exact Remote Connection renderer anchor must remain unchanged.
2. Use disposable Windows Sandbox to test GUI and tray switching RU/EN in a real Host+GUI without starting or stopping user Remote; verify scaling and accessibility.
3. Separately approve installer transaction/rollback gates, implement fresh-install language selection from Windows UI with existing RU compatibility, then validate Upgrade/Repair/Uninstall and Portable.
4. Finish editorial approval/coverage checks, address historical STRING_INVENTORY.csv drift and review exact packaging contents before release.

**Development status: PARTIAL INTEGRATION ONLY.**
