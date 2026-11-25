# RDC Relay 1.6.0 — visual text coverage gap audit (DRAFT)

**2026-11-18, Programmer 5.** Read-only comparison of local `STRING_INVENTORY.csv` (2,841 candidates) against the 360-ID Excel editorial catalog. **No source text, CSV, Host/Remote, installer, or Excel original RU was changed by the audit.**

## Result and scope

The original index marked **477** literals for translation/English-UI review (`REVIEW_TRANSLATION` = 390; `REVIEW_ENGLISH_UI` = 87). The separate editorial workbook contains **360** matching candidate IDs. The remaining **117** review candidates are not covered by the workbook: **87 English/neutral strings** and **30 Russian strings**. This does **not** imply 117 missing end-user translations: the heuristic also marked machine keys and test assertions.

| Source area | Initially excluded from the Excel shortlist |
| --- | ---: |
| `legacy.gui` | 37 |
| `legacy.installer` | 9 |
| `owner.gui` | 35 |
| `owner.tray-host` | 13 |
| `rc1.pilot-installer` | 14 |
| `release.installer-draft` | 9 |
| **Total** | **117** |

## Classification completed — source-aware pass

`Classify-RemainingCandidates.py` generated `REMAINING_117_CLASSIFICATION.csv` from the preserved source-index candidate IDs and the actual existing 360-item workbook. **All 117 have an explicit decision**, without falling back to machine guesses. The CSV includes area, source, source-snapshot line, original literal, candidate ID, classification, reachability scope, action and rationale.

| Classification | Number | Practical interpretation |
| --- | ---: | --- |
| `USER_VISIBLE` | **29** | 13 Owner fallback values; 3 tray/Host captions; 4 shared/legacy GUI captions or errors; 9 real historical Setup/Launcher prompts |
| `PROTOCOL_LOCKED` | **48** | Event parser markers, native/control IDs, branch values, provider allowlist, `Remote Connection` renderer anchor; **never replace in place** |
| `NOT_APPLICABLE` | **40** | Test/Preview-only, internal filenames/fonts, and **14 real messages shown only in private RC1 Pilot Setup**; the pilot messages are excluded from public 1.6 scope, **not** claimed to be invisible |
| **Total** | **117** | Individual decisions recorded in reproducible CSV |

Additional proposals cover status text, fallback banner labels overlooked by the original string-scope heuristic, and historical installer messages: `COVERAGE_ADDENDUM_KEYS.preview.json` (30 source-linked semantic entries), merged into `ru-RU.preview.json` and `en-US.preview.json`, now **86 matching keys**. These are **draft-only**. Messages containing variable version, error, or GUI status use named placeholders. Some new keys originate from excluded-review candidates; others are from the larger machine-preserve area after source context confirmed their UI role. No runtime strings were replaced.

**Important limitation:** `PRESERVE_PROTOCOL_OR_TECHNICAL` is also heuristic and can conceal actual visible English text. The Owner startup-banner fallback already contains such examples. Therefore even the 117 comparison is not a final visual coverage proof.

## Confirmed visible English-only UI — display mapping prepared, integration pending

The fallback block in `Source/rc1-owner-gui.ps1` around lines 581–625 builds a **user-visible, sanitized startup banner** if the validated provider banner is not available. It currently contains English even while the main GUI uses Russian.

| Context | Existing displayed English | Proposed ru-RU display | Classification |
| --- | --- | --- | --- |
| Status value | `Connected` | `Подключён` | `USER_VISIBLE` |
| Status value | `Connecting` | `Подключение` | `USER_VISIBLE` |
| Status value | `Authenticating` | `Авторизация` | `USER_VISIBLE` |
| Status value | `Reconnecting` | `Восстановление` | `USER_VISIBLE` |
| Status value | `Connection fault` | `Ошибка связи` | `USER_VISIBLE` |
| Status value | `Disconnected` | `Отключён` | `USER_VISIBLE` |
| Status value | `Online` | `В сети` | `USER_VISIBLE` |
| Fallback values | `not reported`, `not started` | `не указано`, `не запущен` | `USER_VISIBLE` |
| Ownership | `Managed: Host-owned Job` | `Управляемая сессия Host` | `USER_VISIBLE` |
| Ownership | `Adopted: read-only` | `Существующая сессия: только наблюдение` | `USER_VISIBLE` |
| Channel proof | `Remote connection marker received by Host` | `Host получил подтверждение подключения Remote` | `USER_VISIBLE` |
| Channel proof | `Connected state not currently confirmed` | `Подключение пока не подтверждено` | `USER_VISIBLE` |
| Labels | `Status: `, `Process: `, `Ownership: ` | `Состояние: `, `Процесс: `, `Принадлежность: ` | `USER_VISIBLE` |
| Labels | `- User: `, `- Device Name: `, `- Device ID: ` | `- Пользователь: `, `- Имя устройства: `, `- ID устройства: ` | `USER_VISIBLE` |

The quoted text is an *editorial proposal*, not approved runtime copy. Some entries were classified `PRESERVE_PROTOCOL_OR_TECHNICAL` despite being visible because the scanner cannot infer presentation context.

## Explicitly protected machine/render markers

- `Remote Connection` is the **exact parser anchor** in `Source/remote-window.ps1` (`StyleStartupBanner`, around line 2116) and is also emitted by Owner GUI fallback (around line 617). **Do not translate this anchor in place.** A later small, separately tested presentation refactor may render a localized caption without altering the renderer's fixed marker.
- `Remote tool started/completed/failed`, `Authentication pending`, `Local MCP recovering`, `Remote connected`, `GET_EVENTS`, `SNAPSHOT`, `Ready`, `AuthPending`, `START`, `STOP`, `guiBuild`, `userConfirmed`, JSON field names and provider identifiers are input grammar / IPC or decision keys, not UI copy.
- WinForms control `Name` values `RdcInstallBrowse`, `RdcMaintenanceHeading`, `RdcInstallConfirm` and their peers are identifiers, not captions. They remain invariant.
- `not reported`, `not started`, `Status: ` and `- Device Name: ` **are displayed labels** in the sanitized fallback and must not be excluded merely because they look technical.

## Other candidates requiring reachability review

- `owner.tray-host`: versioned tray titles (`RDC Relay 1.6.0 RC1 | Host`, test fallback `RDC Relay 1.6 RC1 | FAKE Remote`) and sanitized Host event summaries can reach visual tray/journal surfaces. Distinguish user-facing status from protocol/state and test-only fixtures before adding keys.
- `legacy.gui`: `npx.cmd не найден. Установите Node.js 18 или новее.` may appear on legacy startup; `Предпросмотр`, `Тест`, `Только предпросмотр`, self-test assertions and UI renderer literals need reachability decisions. The current 1.6 Owner GUI reuses parts of `remote-window.ps1`, so `legacy.gui` must **not** be excluded wholesale.
- `legacy.installer` (9 candidates): real 1.5.x Setup/Launcher error text. Decide separately whether it is invoked by a public 1.6 migration path; do not rewrite the stable installed 1.5.x installer.
- `rc1.pilot-installer` (14 candidates): private candidate setup messages, not automatically public release scope. If any RC1 migration/repair path reuses those screens, they must be localized or fully replaced by reviewed release UI.
- `release.installer-draft` (9 candidates): primarily control IDs and block reason constants, not text for translation.
- Provider's own full startup banner is external content and may remain vendor-authored English. Do not alter or forge it merely to make a spreadsheet count reach 100%.

## Next controlled work

1. **Prepared:** 30 source-linked display proposals in the separate addendum, without rewriting the 360-line historical workbook. Before runtime use, review the fallback label grammar, ensure display-only transformation, and bring the approved entries into the final resource mapping.
2. Determine the safe display boundary for the fixed `Remote Connection` marker before translating any banner heading; no global replacement.
3. Review remaining review candidates by actual GUI/Setup reachability, distinguishing `USER_VISIBLE`, `ACCESSIBILITY`, `DIAGNOSTIC_USER_VISIBLE`, `PROTOCOL_LOCKED`, `NOT_APPLICABLE`.
4. Only then finalize locale resources and integrate selection in narrow GUI/Tray/Setup batches. Preview JSON remains `DRAFT_NOT_RUNTIME`.

**Known index drift:** the reproducibility check `Build-StringInventory.ps1 -Check` currently reports `INVENTORY_STALE` on the modified source branch. Per task boundary, the original CSV was left untouched; the 360 Excel candidate IDs still resolve within that preserved snapshot. A controlled inventory refresh must be separately decided before release.
