# RDC Relay 1.6.0 — language integration batch 02: journal and tray notices

**2026-11-18; source-level integration, NOT a release sign-off.** Continuation of `INTEGRATION_BATCH01_OWNER_GUI_TRAY.md`.

## Included

- `Source/rc1-owner-gui.ps1`: the Owner-only compact journal's **display formatter** now looks up allowlisted semantic keys for 16 known tool verbs, generic tool actions, missing subjects, eight event message presentations, UTC receipt labels, and GUI-only startup instructions. Three bounded Host synthetic journal messages and the epoch label are also localized. Tool names such as `read_file` / `start_process`, source markers `Remote tool completed`, `Remote Connection`, IPC statuses and IDs are **not translated**.
- Source event correlation and safety remain intact: six-digit sequence gutter, operation ID, sanitized subject/PID, icons, service parse grammar, 512-entry detailed history, rejection of unsafe origins/control characters/credential-like strings, and native RichEdit geometry. Completed `start_process` means **launch request completed**, not process exit.
- Previous detailed log entries are **not reprocessed** when the language changes. New records use the currently selected language and its receipt timestamp; historical records retain their original wording.
- `Source/RdcUiLanguage.cs` + `Source/RdcOwnerRuntime.cs`: only known GUI-window warning codes map to translated NotifyIcon balloon text. The original Host diagnostic code, owned GUI identity checks, one-shot 8-second gating, native `ShowBalloonTip(3000)` timing, and Remote ownership are unchanged. Unknown codes or missing resources retain the provided Russian fallback. A small managed-action warning uses a named `{error}` placeholder populated only from the CLR exception **type name**; no raw exception message or private path is added.
- `Source/lang/ru-RU.json` and `en-US.json`: **42 pairs** of semantic keys added to the existing integration-test dictionaries for these journal/notification surfaces; no unreviewed installer strings wired. `status=INTEGRATION_TEST` remains in force.
- `Tests/Test-V16OwnerJournalLanguage.ps1`: 24 isolated tests of both languages, malformed marker suppression, operation numbers and file subject preservation, historical-journal immutability, safe startup instructions, and allowlisted NotifyIcon warning translation. `Tests/Check-V16OwnerI18nBindingCoverage.py` now checks journal references and static notice-key selections in addition to GUI/tray/dialog references.

## Isolated regression evidence (no running product)

| Test | Result |
| --- | --- |
| Test-V16OwnerJournalLanguage.ps1 | **24 PASS / 0 FAIL** |
| Test-V16OwnerCompactJournal.ps1 | **29 PASS / 0 FAIL** |
| Test-V16FullOriginalStartupHeader.ps1 | **50 PASS / 0 FAIL** |
| Test-V16OwnerHelpJournalRoute.ps1 | **50 PASS / 0 FAIL** |
| Test-V16TrayGuiActivation.ps1 | **17 PASS / 0 FAIL** |
| Test-V16ProductHostGuiSource.ps1 | **22 PASS / 0 FAIL** |
| Test-V16OwnerTrayMenu.ps1 | **50 PASS / 0 FAIL** |
| Test-V16OwnerLanguage.ps1 | **25 PASS / 0 FAIL** |
| Test-V16OwnerDialogLanguage.ps1 (parallel uncommitted batch) | **26 PASS / 0 FAIL** |

**Total: 293 PASS / 0 FAIL** in these selected tests. The independent resource checker passed on **188** currently available source-catalog keys and **121** source references in the shared working directory, including concurrent uncommitted status/dialog changes. These figures are **working-tree state**, not necessarily a single isolated commit's catalog size.

## Boundaries and next work

- **Still not localized:** full vendor-authored startup banner and its protected renderer anchor, several Owner status/failure labels outside the safe renderer, update-install notices, Help content, legacy-only surfaces and release Setup/Repair/Uninstall. The 360 Excel texts are editorial drafts, not certified complete screen coverage.
- Real Host+GUI switch, notification balloons, DPI accessibility and layout, English/Russian Windows sandbox, new-install locale suggestion, update/installer transactions and rollback have **not** been performed.
- The shared branch also contains separate pending changes for Owner status/dialog translation; journal code is intentionally limited to its own source hunks and does not adopt or publish that parallel work.
- No build, installer, login/logout, running Remote, existing user preference or GitHub remote was touched.

**Independent Git-index check:** A temporary extraction of the *staged journal-only source tree* (without pending dialog/status edits) passed **267 PASS / 0 FAIL** across eight isolated PowerShell test scripts, plus the Python resource-coverage check. That index snapshot contains **136** resource keys per language (93 from batch 01, the missing Help accessibility key, and this batch's 42 new keys). The shared working directory has 188 because the unrelated 52-key status/dialog changes are not part of this commit. The temporary extraction was removed afterward.

**Release state:** partial localization only. VM test and release gates remain open.
