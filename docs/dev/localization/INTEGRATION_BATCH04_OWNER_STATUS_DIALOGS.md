# RDC Relay 1.6.0 — Owner statuses and dialogs, batch 04

**2026-11-18. Source-level integration only; not release approval.** Follows INTEGRATION_BATCH03_UPDATE_NOTICE.md.

## Reviewed changes

- Source/rc1-owner-gui.ps1 maps invariant Host state and allowlisted detail codes to RU/EN display labels only. Ownership checks and IPC verbs are unchanged. The last validated Host snapshot and its presentation color are cached for language-only rerender; denied IPC clears the cache.
- Quota and uptime labels use gui.quota.value / gui.quota.unknown / gui.runtime.uptime. The zero-percent warning color still depends on validated numerical quota, not translated text.
- Source/remote-window.ps1: Owner-only Stop, Reconnect and Account Switch dialogs load RU/EN text. DialogResult.No, default-No, Enter/Escape and website-helper safety are unchanged. The original 1.5.x UI path is untouched.
- Source/lang/ru-RU.json and en-US.json: 52 matching new keys for states, dialog labels and footer text. Status remains INTEGRATION_TEST.
- Targeted tests: Test-V16OwnerHeaderStatusRu.ps1 (97 PASS), Test-V16OwnerDialogLanguage.ps1 (26 PASS), Test-V16OwnerAccountSwitchDialog.ps1 (24 PASS), Test-V16OwnerStopHelpDialogs.ps1 (41 PASS), Test-V16OwnerLanguage.ps1 (25 PASS), Test-V16OwnerQuotaFooter.ps1 (35 PASS), Test-V16OwnerRealUpdateNotice.ps1 (23 PASS). Total 271 PASS / 0 FAIL.
- Resource binding checker: 191 RU/EN keys and 124 recognized call sites in the shared working tree at verification.

## Still open

1. Some startup ticket-mode, test-mode, navigation denial and IPC error texts are still direct Russian strings. A language switch during those transient states may not rewrite them. Integrate these separately before claiming complete GUI localization.
2. The vendor startup banner and Remote Connection renderer anchor remain invariant. Past journal lines are not rewritten.
3. Help/About full body, other legacy surfaces, and public Setup/Upgrade/Repair/Uninstall are not fully localized.
4. No running Host/Remote, installed client or public release was tested. Windows Sandbox review must cover RU/EN layout, accessibility, default-No buttons and Windows scale 100–200%.
5. Source inventories have documented drift; STRING_INVENTORY.csv remains historical until a controlled refresh.

**State: prepared for isolated Sandbox evaluation and further transient-UI work, not release GO.**
