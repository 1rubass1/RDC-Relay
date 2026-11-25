# RDC Relay 1.6.0 — detailed review of 68 previously unwired locale keys

Historical baseline: source-key inventory at commit c750f6e; current binding evidence from RESOURCE_KEY_INVENTORY.csv.

## Classification

| Category | Count | Decision |
| --- | ---: | --- |
| Owner fallback connection banner | 19 connected, 1 duplicate | Use localized display text after invariant renderer anchor; Connected is already shown as Online |
| Owner tray | 10 connected | Eight semantic tooltip statuses/prefixes and two asset-fallback titles; no icon/animation changes |
| Empty Owner journal | 1 connected | Separate Owner and legacy behavior |
| Release Setup maintenance/path dialogs | 28 bound in prepared UI | Standalone compiled catalog, no installed files needed. Actual transaction still unconnected. |
| Legacy Setup/Launcher | 7 deferred | First establish path reachability in 1.6 and migration |
| Legacy GUI 1.5.x | 2 deferred | Outside Owner GUI 1.6 runtime; separate compatibility stage |
| **Total** | **68** | **58 source-bound (including 28 preparatory Setup), 10 deferred/redundant** |

## Installer scope

The two prepared release dialogs now use RdcReleaseUiLanguage and an independently compiled catalog generated from Source/lang. The generator embeds all 35 RU/EN installer keys, of which 28 are bound in release maintenance/path UI. No runtime Source/lang dependency. The 7 legacy Setup/Launcher entries are embedded as staging data but NOT wired into stable 1.5.x Setup, so no destructive installation behavior changes. Public 1.6 Setup, Upgrade/Repair/Uninstall, packaging, rollback and user-facing transaction entrypoints remain INCOMPLETE.

## Protected behavior

- The exact Remote Connection marker is not translated, because StyleStartupBanner uses it to find the artwork. When Host supplies its own original startup header, the vendor text remains byte-identical.
- The Connected resource key is an intentional unused duplicate: the code maps validated Ready/Connected to the Online resource key, matching its previous UI. It is retained for editorial traceability.
- NotifyIcon statuses are translated only from validated Host state; no icon frame changes, no animation phase reset, no new Remote action.
- Owner empty-journal text uses its dictionary only in Owner mode, leaving the historical GUI unchanged.

## Evidence and follow-up

- Current source/string and resource inventories are reproducible; all 68 keys have explicit rows in REMAINING_68_DECISIONS.csv.
- Native tray tests exercise the translated English and Russian tooltip with the real 49-icon bundle and safe semantic transitions.
- The artificial fallback uses 19 new keys, including the labels of previously validated and sanitized identity values, but is not the vendor startup header.
- Existing Windows Sandbox is a previous immutable revision; it will not hot-reload these changes. New screenshots require a fresh disposable session.

Prepared release dialog localization is now source-integrated for 28 keys; public installer transaction, rollback and full Remote integration still require separate approval. No release GO.
