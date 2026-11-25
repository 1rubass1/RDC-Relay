# RDC Relay 1.6.0 — refreshed source/resource inventory reconciliation

**Development audit only; not a release or translation approval.**

## Source scanner

Historical immutable STRING_INVENTORY.csv: 2841 unique literals.
Current STRING_INVENTORY_CURRENT.csv: 3743 unique literals.
Shared IDs: 2764; added: 979; removed after source changes: 77.
New source candidates flagged for review: 256. Areas: legacy.gui=63, owner.gui=97, owner.tray-host=60, rc1.pilot-installer=10, release.installer-draft=21, shared.update-notice=5.
Original Excel book: 360 source IDs still resolve in the historical CSV. Current matching IDs: 294; historical-only IDs: 66.

CandidateId hashes source path + exact original literal. Refactoring a visible string changes its ID: never rewrite historical Excel IDs in bulk.

## Runtime semantic key inventory

RESOURCE_KEY_INVENTORY.csv contains 291 RU/EN pairs, named arguments, source refs and binding state.
Bindings: SOURCE_REFERENCED=280, UNWIRED_PREVIEW=11.
Unwired keys are proposals, not production coverage. The PowerShell/C# source scanner does not index JSON; the semantic index fills that blind spot.

## Open review and verification

Review 256 newly flagged REVIEW_* source strings in context, especially runtime display and legacy paths. Preserve IPC/control names, provider markers and exact Remote Connection renderer anchor.
The original historical CSV remains untouched; verify current scan via Build-StringInventory.ps1 -Current -Check. The 117-item historical classification remains valid for the original inventory only.

## Newly added REVIEW_* snippets (first 50)

| Area | Source line | Snippet |
| --- | --- | --- |
| owner.gui | Source/rc1-owner-gui.ps1:697 | owner.runtime.fakeDetail |
| owner.tray-host | Source/RdcOwnerRuntime.cs:937 | rc1-tray-confirm-no |
| owner.gui | Source/rc1-owner-gui.ps1:552 | owner.initial.managedName |
| legacy.gui | Source/remote-window.ps1:7577 | Не удалось открыть исходный лог Remote. |
| owner.gui | Source/rc1-owner-gui.ps1:111 | получено |
| legacy.gui | Source/remote-window.ps1:7515 | Файлы логов (*.log) |
| owner.gui | Source/rc1-owner-gui.ps1:337 | tray.menu.reconnect |
| owner.tray-host | Source/RdcOwnerRuntime.cs:2914 | tray.status.connecting |
| release.installer-draft | Installer/RdcReleaseMaintenanceDialog.cs:48 | Установлена версия {installedVersion}. Выберите действие. |
| owner.tray-host | Source/RdcOwnerRuntime.cs:1347 | tray.title.managedHost |
| owner.gui | Source/rc1-owner-gui.ps1:354 | gui.title.managedRemote |
| legacy.gui | Source/remote-window.ps1:6988 | dialog.switch.signOut |
| owner.gui | Source/rc1-owner-gui.ps1:806 | Host подтвердил выполнение: {action} |
| legacy.gui | Source/remote-window.ps1:7655 | journal.owner.contentAccessible |
| owner.gui | Source/rc1-owner-gui.ps1:344 | Справка / О программе |
| owner.tray-host | Source/RdcOwnerRuntime.cs:922 | rc1-tray-confirmation |
| owner.gui | Source/rc1-owner-gui.ps1:254 | Установление связи |
| owner.gui | Source/rc1-owner-gui.ps1:244 | Только наблюдение |
| legacy.gui | Source/remote-window.ps1:7304 | Отключён |
| owner.gui | Source/rc1-owner-gui.ps1:346 | gui.account.infoTooltip |
| owner.gui | Source/rc1-owner-gui.ps1:543 | owner.initial.observedDetail |
| owner.gui | Source/rc1-owner-gui.ps1:839 | переподключение |
| owner.gui | Source/rc1-owner-gui.ps1:839 | RECONNECT |
| owner.tray-host | Source/RdcOwnerRuntime.cs:1398 | Не удалось сохранить язык интерфейса. |
| owner.tray-host | Source/RdcOwnerRuntime.cs:1438 | Не удалось сохранить настройку автоподключения. |
| owner.gui | Source/rc1-owner-gui.ps1:768 | owner.fallback.label.ownership |
| owner.gui | Source/rc1-owner-gui.ps1:280 | Смена аккаунта отклонена; Remote остановлен |
| owner.gui | Source/rc1-owner-gui.ps1:558 | owner.initial.fakeEvent |
| legacy.gui | Source/remote-window.ps1:6906 | dialog.switch.title |
| owner.tray-host | Source/RdcOwnerRuntime.cs:1386 | Не удалось изменить автозапуск. Проверьте параметры автозагрузки Windows. |
| owner.gui | Source/rc1-owner-gui.ps1:265 | Проверка связи; только наблюдение |
| release.installer-draft | Installer/RdcReleasePathDialog.cs:188 | installer.path.dialogTitle |
| release.installer-draft | Installer/RdcReleaseMaintenanceDialog.cs:35 | installer.maintenance.cancel |
| owner.gui | Source/rc1-owner-gui.ps1:335 | Аккаунт |
| rc1.pilot-installer | Installer/Rc1CandidateSetup.cs:339 | Загрузка Node.js 24 LTS... |
| owner.gui | Source/rc1-owner-gui.ps1:229 | Выполнение запроса |
| owner.tray-host | Source/RdcOwnerRuntime.cs:1386 | tray.notice.autoStartFailed |
| owner.tray-host | Source/RdcOwnerRuntime.cs:1520 | {error} |
| owner.tray-host | Source/RdcOwnerRuntime.cs:572 | Язык / Language |
| owner.tray-host | Source/RdcOwnerRuntime.cs:2917 | tray.status.working |
| shared.update-notice | Source/update-notice.ps1:368 | update.owner.idleTooltip |
| legacy.gui | Source/remote-window.ps1:7320 | journal.owner.modePrefix |
| legacy.gui | Source/remote-window.ps1:7341 | Восстановление сохранённых логов ещё не завершено. |
| legacy.gui | Source/remote-window.ps1:7555 | Сохранить копию лога |
| legacy.gui | Source/remote-window.ps1:7343 | Поток исходного лога недоступен. |
| owner.gui | Source/rc1-owner-gui.ps1:261 | Ожидание подтверждения |
| owner.gui | Source/rc1-owner-gui.ps1:229 | Ожидание запроса |
| owner.gui | Source/rc1-owner-gui.ps1:286 | Выход не подтверждён; Remote остановлен |
| legacy.gui | Source/remote-window.ps1:6884 | Не удалось сохранить настройку остатка вызовов. |
| owner.gui | Source/rc1-owner-gui.ps1:545 | owner.initial.observedEvent |

No release GO.
