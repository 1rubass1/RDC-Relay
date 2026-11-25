# RDC Relay 1.6.0 — installer localization, batch 06

**2026-11-18, source-level integration, not public Setup.**

**Addendum 2026-11-19:** A visually reviewed existing-install folder mode now uses `installer.path.continue` (`Продолжить / Continue`) rather than `installer.path.install`, because the dialog can precede both update and repair. Catalog total: **36 bilingual keys**, with **29 bound to prepared Release Setup dialog UI** and 7 legacy staging entries. No Setup transaction is connected.

## What is integrated

- `Installer/RdcReleaseUiLanguage.cs`: self-contained C# display-only translator. It has NO dependency on installed Source/lang files, Host, Remote, web or registry. It reads the existing bounded per-user `RDCRelay/ui-language.json` preference **read-only**, validates the exact `version=1` + `locale=ru-RU/en-US` schema, refuses reparse points/oversized/malformed settings and defaults safely to Russian on corrupt data. It never writes the preference or credentials.
- With no preference, **existing installations** retain `ru-RU`. A genuine **fresh** install suggests `ru-RU` only when the Windows UI culture starts with `ru`, otherwise `en-US`. This is a suggestion for display only; no choice is silently persisted.
- `Installer/RdcReleaseUiCatalog.Generated.cs`: embedded RU/EN values from Source/lang, compiled into the future Setup executable. Generated deterministically by dev-only `docs/dev/localization/Generate-ReleaseInstallerCatalog.py`, with strict 35-key parity and named placeholder checks. All 35 original installer strings are present as **INTEGRATION_TEST** drafts; future editorial approval is required.
- Only 28 keys are **connected to actual release-only WinForms dialogs**: 15 `installer.maintenance.*` and 13 `installer.path.*`. The dialogs keep original control names, selected verified path logic, button choice enums, `DialogResult` and `RdcReleaseMaintenancePolicy.IsAllowed` gates. The installer version is inserted only through bounded numeric display substitution; no translation controls the action itself.
- Seven `installer.legacy.*` strings are **staged in the compiled catalog but intentionally not connected** to `Installer/Setup.cs`, `Launcher.cs` and `RdcReleaseInstallState.cs`, which belong to the earlier stable setup route. Modifying 1.5.x installer/launcher as a shortcut would risk regression; the builder correctly blocks any attempt to use this legacy Setup for a 1.6.0 public release.
- The release 1.6.0 Setup transaction, upgrade/repair/uninstall, rollback, ARP identity and custom install-root commit are NOT wired to these dialogs. No one should regard the completed display localization as a working installer.

## Verification

| Source-level check | Result |
| --- | --- |
| `Tests/Test-V16ReleaseInstallerLanguage.ps1` | **60 PASS / 0 FAIL**: RU/EN for Upgrade, Repair, NewerInstalled, Refuse, fresh/existing path, default/explicit language, corrupt file fallback, parameter constraints, safe buttons |
| `Tests/Test-V16ReleaseMaintenance.ps1` | **35 PASS / 0 FAIL**, real compiled policy and native dialog; Russian UI pinned explicitly for independence from Windows UI culture |
| `Tests/Test-V16ReleasePathDialog.ps1` | **21 PASS / 0 FAIL**, path validator and real native forms, Russian pinned explicitly |
| `Tests/Test-V16ReleaseInstallPolicy.ps1` | **27 PASS / 0 FAIL**, original release install safeguards |
| `Tests/Test-V16LegacyReleaseBuilderGate.ps1` | **5 PASS / 0 FAIL**, legacy builder still refuses public v1.6 |
| **Total** | **148 PASS / 0 FAIL** across five targeted suites |

- `Generate-ReleaseInstallerCatalog.py --check` reproduces the embedded C# catalog exactly; generated code is excluded from source literal counting (otherwise copied translations would be double-counted).
- `Audit-Remaining68.py` reconciles the original 68 keys: **30 Owner keys + 28 prepared Setup keys source-bound**, **7 legacy-Setup + 2 legacy-GUI + 1 redundant display key** remain unbound.
- All tests compile the new actual C# files in temporary PowerShell process and instantiate real WinForms controls **without calling ShowDialog or executing Setup**. No live files/ARP/shortcuts, installed Host/Remote, user preferences or credentials were changed.

## Not yet approved

1. Build a genuine **full Host/GUI 1.6.0 release Setup** with this resource class + generated catalog in its exact executable compile allowlist. `build-release.ps1` must remain hard blocked for 1.6 until this integration is reviewed. The Setup entrypoint must select a locale using the *verified* existing-install classification (not merely whether the new destination path is empty) and pass it to the new explicit `Choose(..., locale)` overloads. **Important first-run continuity gap:** the current UI-only stage does not persist the Windows-locale suggestion or communicate it to the GUI. Future Setup must either obtain an explicit language choice and persist it only upon user choice, or establish a verified fresh-install first-run locale decision without modifying preferences silently; otherwise an English Setup could be followed by a Russian GUI.
2. Full OS-level Windows Sandbox tests: RU and EN native Setup dialogs, DPI 100–200%, keyboard/assistive access, fake migration and downgrade refusal, fresh + stable 1.5.18 + pilot + 1.6 same-version scenarios. No live Remote.
3. Durable staged-update/rollback/power-loss recovery, ARP/shortcut migration, custom install path unification and uninstall entrypoint; a display-level `Choose` action must not be wired to an unfinished transaction.
4. Editorial review of installer translations in both languages (including the original 7 legacy messages). All values remain `INTEGRATION_TEST`, not launch-approved.

**GO for isolated testing of display-only Setup dialogs; NOT GO for a public installer or version 1.6.0 release.**
