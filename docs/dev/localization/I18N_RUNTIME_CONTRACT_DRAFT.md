# RDC Relay 1.6.0 — contract for safe language switching (DRAFT)

**Status 2026-11-18:** editorial proposal from Programmer 5. **Authorization now covers the first GUI/tray integration batch, but not Host/Remote process behavior or publishing.** All 360 lines in the local workbook have draft English translations; **none has been editorially approved** and full on-screen coverage remains unverified.

## What exists

- `RDC_Relay_UI_Texts.xlsx` (local STARMER only): 360 candidate IDs, exact original RU, draft EN, source paths, contexts; every row remains `На проверку`. The original `STRING_INVENTORY.csv` is unchanged.
- `ru-RU.preview.json` and `en-US.preview.json`: **86 proposed semantic keys** (tray/menu, GUI tooltips, Owner fallback banner, release/legacy installer dialogs), status `DRAFT_NOT_RUNTIME`. These are a **subset**, not complete language files. The additional 30 context-mapped entries are tracked in `COVERAGE_ADDENDUM_KEYS.preview.json`; some installer fragments have been consolidated into named templates. The key count is not equal to one-to-one workbook rows.
- `INTEGRATION_BATCH01_OWNER_GUI_TRAY.md`: first source-level GUI/tray integration, 93-key integration-test catalogs and per-user locale preference, with full test evidence and open gates.
- `Check-TranslationWorkbook.ps1`: read-only source-index, 360 text-pair, placeholder/space and identifier validation (no Excel application needed).
- `Check-ResourcePreview.ps1`: read-only key-set and named-placeholder parity check; verifies 30 coverage addendum entries and rejects non-preview status. **86 matching keys, 10 parameterized templates — PASS**.
- `BATCH01_TRAY_AND_TOOLTIPS.md`: first semantic key proposals and discussion of display-vs-command separation. The narrow tray click fix was separately committed in `c3c6149`, with isolated fake-only menu checks. A second narrow fix decouples zero-quota warning color from the Russian percentage label; the isolated quota-footer test reported 35 PASS / 0 FAIL.

- `REMAINING_117_CLASSIFICATION.csv` and `Classify-RemainingCandidates.py`: explicit per-candidate review of 117 previously excluded inventory entries. Breakdown: 29 `USER_VISIBLE`, 48 `PROTOCOL_LOCKED`, 40 `NOT_APPLICABLE` for the public 1.6 release (14 of the latter are user-facing only in the private RC1 Pilot installer). See `UI_COVERAGE_AUDIT_DRAFT.md` for renderer marker and fallback banner boundaries.

## Existing invariants and proposed integration boundaries

1. **Machine values remain invariant.** Do not translate IPC JSON fields, Host state codes, Remote command verbs, tool names, registry keys, provider log markers, IDs, or strings used in branching. Only localize their **presentation**, after the normal Host state has been validated.
2. **Language is a user-display preference, not a Remote credential.** Store it in a dedicated, bounded, per-user setting using atomic replace and a safe read; never change, move, or parse the Remote authentication store. Do not write a preference until the user actually selects a language.
3. **Default:** existing installations without an explicit setting stay **Russian**. On a genuinely new installation, derive a *suggested* locale from Windows UI: `ru-RU` for Russian, `en-US` for others among these two choices; explicit user choice always wins. If preference data/resources are missing, malformed, or unsupported, fail to the available `ru-RU` UI.
4. **Selection in UI:** display `Русский` and `English` in their own scripts regardless of active language. Switching changes GUI labels, accessibility text, tray menus and notifications at a stable UI update boundary. Do not stop, restart, or adopt Remote/Host to refresh language. If a GUI-only restart proves necessary, it requires an independently safe scenario.
5. **Resource format:** UTF-8 JSON, fixed nested `strings` map with `locale` and reviewed schema. Keys are semantically named and equal across all supported languages; never use `TXT-...` (the inventory candidate hash) as a runtime localization key. No expression evaluation, PowerShell script execution, or dynamic property injection from resource values.
6. **Interpolation:** use reviewed **named** placeholders and explicit, safely escaped string substitution. Validate exactly matching argument sets in RU/EN; never interpolate unsanitized log lines, credentials or paths into diagnostic UI. Longer messages must be reassembled as full templates before connecting.
7. **Host-owned commands:** clicking a control sends a fixed invariant action determined by validated program state, never by its text/translation. The Start/Stop tray action is already decoupled from the label. Preserve all current ownership and denial checks.
8. **Historical journal:** previously captured diagnostic records do not get rewritten when switching language. For newly displayed activity, translate safe allowlisted event categories on the GUI side, not the raw provider/IPC content. Preserve event sequence IDs, sanitization, timings and data caps.
9. **Installer:** fresh Setup, Upgrade, Repair, Uninstall and refusal dialogs use the same localized resource set **before** GUI is installed. Locale persistence and fallback need isolated verification. Do not wire draft buttons to incomplete destructive transactions; current release installer still has independent rollback/migration gates.
10. **Release package:** approved `ru-RU`/`en-US` files must be staged explicitly in reviewed Setup and Portable allowlists. All `docs/dev/` including the Excel and `*.preview.json` **must be excluded**.

## Template assembly examples (no runtime use yet)

| Key | ru-RU | en-US |
| --- | --- | --- |
| `installer.maintenance.upgradeDescription` | `Установлена версия {installedVersion}. Доступна версия {targetVersion}.` | `Installed version {installedVersion}. Available version {targetVersion}.` |
| `installer.maintenance.repairDescription` | `Установлена версия {installedVersion}. Выберите действие.` | `Installed version {installedVersion}. Choose an action.` |
| `installer.maintenance.newerDescription` | `На компьютере уже установлена версия {installedVersion}. Установщик версии {targetVersion} не может её заменить.` | `This computer already has version {installedVersion} installed. Setup version {targetVersion} cannot replace it.` |
| `installer.path.windowTitle` | `Установка RDC Relay {version}` | `Installing RDC Relay {version}` |

The original C# dialog currently concatenates literal fragments; do not substitute the above without a small, isolated update to those dialogs and a geometry/behavior check. On the actual app's menu/tray surfaces, verify WinForms autoscale and accessibility names at Windows UI scale 100–200%. Use Windows App Design Guidelines/Fluent 2 recommendations for feedback without altering established interaction timing.

## Next checkpoints

1. **Editorial pass:** review 360 candidates for actual reachability and context; classify `USER_VISIBLE`, `ACCESSIBILITY`, `DIAGNOSTIC_USER_VISIBLE`, `PROTOCOL_LOCKED`, `NOT_APPLICABLE`; verify plurals, hints, combinations, legacy/RC1-only copies, and localized status UI at actual size.
2. **Key mapping:** extend the semantic key set beyond the 86 draft preview keys (93 initial integration-test keys including GUI-only keys) to every reviewed visible runtime text. Retain source candidate hashes only as a cross-reference in development documentation, not in payloads. Review duplicate RU/EN strings separately where context differs.
3. **Architecture review:** approve the preference location, fallback and trust boundary; approve installer transaction wiring independently.
4. **Integration in narrow batches:** owner GUI and tray first, then safe notification/journal rendering, then release Setup/Portable. Run targeted tests after each touched surface, not a full OS test suite for a text-only change.
5. **Release gate:** in disposable Windows Sandbox verify RU/EN choice, persistence, missing/malformed resource fallback, no Remote restart during switching, Windows scaling, accessibility and Setup/Upgrade/Repair/Uninstall. Independent install/rollback/migration and licensing gates remain separate.

**Preview files have no runtime authority.** A successful draft validator check proves structural consistency, not translation approval, UI completeness, or release readiness.
