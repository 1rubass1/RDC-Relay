# RDC Relay 1.6.0 — пакет перевода 01: трей и подсказки

> Черновик редакторского этапа, 2026-11-17. **НЕ ПОДКЛЮЧЁН К ПРОГРАММЕ.** Это предложения для переноса в `RDC_Relay_UI_Texts.xlsx` после проверки, не второй действующий словарь и не команда на изменение механизма Host/Remote.

**Охват:** 28 пользовательских строк из групп «Трей и меню» и «Подсказки». `TXT-786a4027c0876eab` (фрагмент « (первый)») исключён: его надо проверить в составном контексте отдельно. Исходные фразы и временные TXT-ID сохранены без изменения.

| CandidateId | Предлагаемый стабильный ключ | ru-RU (оригинал) | en-US (черновик) |
| --- | --- | --- | --- |
| TXT-c07f2a91d76f744e | tray.menu.openWindow | Открыть окно RDC Relay | Open RDC Relay window |
| TXT-b3ff09b7cb0387dd | tray.menu.switchAccount | Сменить аккаунт | Switch account |
| TXT-6476cfaa752ebef9 | tray.menu.reconnect | Переподключить | Reconnect |
| TXT-b1d07a6c10ddf82a | tray.menu.manageDevices | Управление устройствами | Manage devices |
| TXT-6b071883117228af | tray.menu.showRemainingCalls | Выводить остаток вызовов | Show remaining calls |
| TXT-8668ac1effba131d | tray.menu.autoUpdate | Автообновление | Automatic updates |
| TXT-501de1748f00cdcf | tray.menu.autoUpdateTooltip | Установка при запуске; поиск обновлений и ручная кнопка работают отдельно | Install updates at startup; update checks and the manual button work separately |
| TXT-2785b00b0f4a781e | tray.menu.start | Запустить | Start |
| TXT-f3648ad1692db4fb | tray.menu.stop | Остановить | Stop |
| TXT-c75390caeb1b5c4f | tray.menu.about | Справка о программе | About RDC Relay |
| TXT-22f40c7d3d3951ce | tray.menu.exit | Завершить RDC Relay | Exit RDC Relay |
| TXT-112ba9fe25968468 | tray.title.observed | RDC Relay 1.6 RC1 \| наблюдение | RDC Relay 1.6 RC1 \| observing |
| TXT-e4a93624f4417003 | tray.status.connecting | Подключение | Connecting |
| TXT-724fdb7af09a2e67 | tray.status.authenticating | Авторизация | Authenticating |
| TXT-d862e789ff42bec7 | tray.status.ready | Готов к работе | Ready |
| TXT-98189892f3e1aa97 | tray.status.working | Выполнение | Working |
| TXT-66ce8630ab9bb632 | tray.status.connectionError | Ошибка соединения | Connection error |
| TXT-a471f9b76d8abd2f | tray.status.disconnected | Отключён | Disconnected |
| TXT-f62db119d451e214 | tray.status.waitingForCall | Ожидание следующего вызова | Waiting for the next call |
| TXT-d1ca354c4c6386a2 | tray.status.testPrefix | Тест \| (пробел после разделителя обязателен) | Test \| (сохранить пробел после разделителя) |
| TXT-a3cc7f303aa702d2 | gui.title.observedRemote | RDC Relay 1.6.0 RC1 — существующий Remote (только чтение) | RDC Relay 1.6.0 RC1 — existing Remote (read-only) |
| TXT-b941a0009322a40f | gui.title.managedRemote | RDC Relay 1.6.0 RC1 — управляемый Host/GUI | RDC Relay 1.6.0 RC1 — managed Host/GUI |
| TXT-f1c07b0ef4dd4e68 | gui.title.testMode | RDC Relay 1.6.0 RC1 — Remote не подключён (режим проверки) | RDC Relay 1.6.0 RC1 — Remote disconnected (test mode) |
| TXT-2a98a6e3812bf837 | gui.tooltip.ownedRemoteOnly | Запуск или остановка только Remote, принадлежащего текущему Host. | Only Remote owned by the current Host can be started or stopped. |
| TXT-e7c36317ff0cc637 | gui.tooltip.unownedRemote | Управление существующим Remote недоступно: сессия не принадлежит RC1. | The existing Remote cannot be controlled: the session is not owned by RC1. |
| TXT-48d5116c4b955f7b | gui.tooltip.manageOwnedRemote | Управление только собственным Remote этого Host. | Only Remote owned by this Host can be controlled. |
| TXT-1e674483f51f9550 | gui.tooltip.legacyRemote | Существующий Remote принадлежит старой оболочке. После её штатного завершения RC1 создаст новую управляемую сессию. | The existing Remote belongs to the legacy UI. After it exits normally, RC1 will create a new managed session. |
| TXT-0c0daa364833a631 | gui.accessibility.accountDeviceManagement | Аккаунт: переход к управлению устройствами без изменения Remote. | Account: opens device management without changing Remote. |

## Обязательные ограничения интеграции

1. **Развязка команды и подписи исправлена в исходниках по разрешению владельца (2026-11-17).** `Source/RdcOwnerRuntime.cs`, `RdcOwnerTrayMenu`: обработчик `StartStopItem.Click` выбирает `STOP/START` по последнему полученному от Host признаку `ownedRunning`, независимо от `StartStopItem.Text`. Адресный тест `Tests/Test-V16OwnerTrayMenu.ps1`: **46 PASS / 0 FAIL**, включая искусственную смену текста в обоих состояниях. Живой Remote и установленный клиент не изменялись; поведение установленной сборки **NOT CHECKED**.
2. Метки `START`, `STOP`, `OPEN`, `SWITCH_ACCOUNT`, `RECONNECT` и состояния Host/IPC не переводятся и не переименовываются.
3. `tray.Text` ограничен 63 символами: перед интеграцией проверять итоговую длину для обеих локалей. Не переносить эту метку в логику состояния.
4. Заголовки, содержащие `1.6.0 RC1`, требуют отдельной проверки при выпуске публичной версии; не менять версию автоматически в составе перевода.
5. Динамический префикс тестового режима должен сохранять завершающий пробел. Приведённое в таблице пояснение в скобках **не является переводимым литералом**; фактические строки `Тест | ` и `Test | `.
6. Не выполнять замену всех найденных литералов по текстовому совпадению: временные `TXT-...` привязаны к источнику, а семантика зависит от места вызова.
7. **Обновлено 2026-11-18:** все 28 вариантов этого пакета перенесены в существующую Excel-книгу, а смысловые ключи включены в отдельные редакторские `ru-RU.preview.json` и `en-US.preview.json` под `docs/dev/localization/`. Статус переводов остаётся «На проверку», файлы помечены `DRAFT_NOT_RUNTIME` и не загружаются приложением. Помимо узкого исправления диспетчеризации в исходниках никакие изменения runtime не выполнялись; установленная программа, CSV и сборка не затронуты.

## Терминология для этого пакета

- **Remote** и **Host** — имена компонентов, оставлять без перевода.
- **RC1** — обозначение тестовой сборки, не локаль.
- **Account** — «аккаунт», в меню использовать «Switch account».
- **Read-only / observing** — режим наблюдения без управления чужой сессией; не путать с отказом соединения.
- **Ready / Working / Disconnected** — только видимые статусы; внутренние машинные значения не меняются.
