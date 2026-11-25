# RDC Relay 1.6.0 — Owner GUI final display pass and current string indexing

**2026-11-18. Source-level and isolated test status; not release GO.**

## GUI display-only localization

- Initial Managed/Observed/FakeOnly status captions, runtime labels, synthetic journal notices, navigation denial, IPC outage and denied Host actions use semantic RU/EN resources.
- Denied actions use an explicit START/STOP/RECONNECT/SWITCH_ACCOUNT allowlist to display an action name. Unknown values render a generic translated action, never raw IPC content.
- Owner Help/About modal, three complete mode-specific Help bodies, detailed diagnostic journal headings, accessibility, copy/select-all, save prompts and error notices are localized.
- Detailed journal state, Host ownership and activity labels are translated only after allowlist validation. Sanitized event history, raw protocol/state keys and original 1.5.x GUI behavior remain unchanged.
- Resource dictionaries currently have 261 matching keys per language (70 new display keys in this batch). All content is INTEGRATION_TEST and still needs visual/editorial acceptance. The resource reader's 400-key and 64 KiB limits are still enforced.

## Current index and provenance

- Historical STRING_INVENTORY.csv (2841 candidates) is immutable; the exact pre-refresh copy is kept outside Git under [local project root]\_archive.
- Build-StringInventory.ps1 -Current creates a separate current snapshot STRING_INVENTORY_CURRENT.csv (3144 distinct source literals, 24 source files). -Current -Check reproduces it byte-for-byte.
- 2828 candidate IDs are stable, 316 newly added and 13 historical IDs absent from current source due to refactoring. 347 of the 360 Excel IDs still match the current index; all 360 are preserved in historical inventory.
- Audit-CurrentInventory.py and Classify-CurrentReviewDelta.py generate CURRENT_INVENTORY_AUDIT.md, RESOURCE_KEY_INVENTORY.csv, CURRENT_REVIEW_DELTA.csv. All 127 new REVIEW_* candidates classified: 116 direct display-resource fallbacks, 5 exact dictionary values, 3 self-language names, 2 protected placeholder tokens and 1 fixed RDC Relay brand.
- The separate semantic inventory covers the JSON files omitted by the original source-string scanner: 261 keys, 193 with literal source references and 68 still unwired proposals (including Setup/Installer). This is not a declaration of completed installer translation.

## Safety and validation

- 14 isolated targeted regression suites: 516 PASS / 0 FAIL; PowerShell 5.1 parsing, WinForms help/journal layout, sanitized events and printer/export restriction retain existing behavior.
- Tests/Test-V16OwnerRemainingLanguage.ps1: 49 PASS, including no arbitrary IPC error action echo and preserved no-Remote test-mode labels.
- Tests/Test-V16OwnerHelpJournalRoute.ps1: 60 PASS, including native Help click, journal scrolling/copy/save, safe diagnostics and new RU/EN Help and journal labels.
- No installed client, real Desktop Commander Remote, real login or credential cache was altered. No GitHub push.

## Open work for human Sandbox acceptance

- One-click offline FakeOnly Sandbox must be smoke-tested, then owner can inspect the whole GUI and tray in RU/EN without Remote or accounts.
- Test 125%, 150%, 200% scaling, high contrast and accessibility. Existing 96 DPI screenshots cover only the Stop/Reconnect/AccountSwitch dialogs.
- Preview of actual Setup/Repair/Uninstall and new-install Windows language suggestion needs its own separate transaction-safe stage. No release GO.
