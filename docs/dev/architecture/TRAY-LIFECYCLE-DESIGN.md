# RDC Relay — Windows tray и жизненный цикл окна

> **Решение владельца по направлению UX: 2026-10-23. Архитектурный контракт, НЕ реализация.**
> При нажатии **X** окно убирается с экрана, а RDC Relay и подключение Remote **продолжают работать**. По значку в системном трее пользователь снова открывает актуальное окно. Владелец сообщил, что задание PROG-005A программисту **ещё не передавал**.
>
> Вопрос полного завершения фонового supervisor отдельно не утверждён; без новых разрешений **не** выполнять остановку Remote, `logout`, разрушительные или реальный UI/Windows process tests. Публичные релизные ветки и установленный RDC Relay не изменяются.

## 1. Правильная техническая интерпретация

**Не уничтожать и не пересоздавать WinForms Form при каждом открытии.** Для пользователя окно «закрывается»/«открывается», но внутри сохраняется **тот же экземпляр формы**, event subscriptions, reader, таймеры, state machine, process handle и WinForms message loop.

При `FormClosing` **только если `CloseReason.UserClosing` и не идёт разрешённый служебный shutdown**: `e.Cancel = $true`, `$form.Hide()`, `ShowInTaskbar = $false`; приложение и watchdog продолжают работать. Это безопаснее нового экземпляра Form с дублирующимися таймерами, updater-check, reader, mutex и потенциально повторным `Start-Remote`. Для восстановления: `ShowInTaskbar = $true`, `$form.Show()`, restore Normal, `Activate()`, однократный bounded status refresh; **не запускать Remote заново**.

`Application.Run($form)` уже является работающим message loop. При `Hide`, в отличие от `Close`, он остаётся активен. Если впоследствии потребуется уничтожать Form и пересоздавать его, потребуется отдельный `ApplicationContext`/host жизненного цикла и особое тестирование; **не входит в MVP**.

Технология: штатный Windows PowerShell 5.1 + .NET Framework **`System.Windows.Forms.NotifyIcon`** и `ContextMenuStrip`. Для иконки использовать уже имеющийся установленный RDC Relay ICO, без замены брендинга или создания нового движка/GUI.

**Не смешивать два процесса:** (a) скрытое окно WinForms/RDC Relay supervisor живо; (b) дочерний Remote продолжает выполнять MCP tools. Это обязательное поведение при X **независимо от Owned/Adopted**. При скрытом окне остаётся мониторинг/автовосстановление по существующим правилам, но опасную политику auto-stop/restart adopted надо решать отдельно в PROG-005.

## 2. Видимое поведение

| Действие | Ожидаемый результат |
| --- | --- |
| Нажатие **X** в обычном окне | Только скрыть форму; в трее остаётся значок; никаких `Stop-Remote`, `taskkill`, `remote --logout`, `Start-Remote` и reset health/log. |
| Двойной щелчок по значку / пункт «Открыть RDC Relay» | Показать **тот же** экземпляр формы с актуальными логами, статусом, scroll position; не запускать второй supervisor/Remote. |
| Однократный запуск программы при уже скрытой форме | Реактивировать существующий экземпляр, **не** считать его «зависшим». Если межпроцессное сообщение не дошло, безопасно завершить только новый launcher с понятной диагностикой: *никогда не уничтожать* старый GUI. |
| Сворачивание кнопкой «—» | Сохранять штатное поведение taskbar; **не** перехватывать Minimize как Close (согласно Windows UX guidance). |
| Правая кнопка по значку | Меню: **«Открыть RDC Relay»**, статус только для чтения; **«Завершить RDC Relay…»** отдельно от закрытия окна и остановки Remote. Реальное действие Exit пока требует решения о судьбе Remote. |
| Явная кнопка «Остановить Remote» в основном UI | Существующая функциональность пока **не изменяется** и не перемещается в tray; запрет для adopted/unknown — отдельный ownership PROG-005 после согласования. |
| Действительный Windows logoff/shutdown, updater relaunch, fatal startup error | **Не прятать окно вместо завершения**. Различать `CloseReason` и собственный флаг controlled exit. Очистить NotifyIcon; сохранить существующий механизм обновления/перезапуска и не запускать дубликат. |
| Explorer/taskbar перезапустился | Значок должен восстановиться при живом GUI-хосте, насколько это позволяет NotifyIcon/оболочка; проверить в **изолированном UI-тесте**, не перезапускать реальный Explorer пользователя. |

Первое закрытие с успешным переходом в трей допускает **однократное тихое пояснение** «RDC Relay продолжает работать. Чтобы открыть окно, выберите значок в области уведомлений.» Если состояние не сохраняется, достаточно tooltip/подсказки в меню без повторных balloon notifications. Не блокировать UX модальным окном при каждом X. Tooltip должен отражать проверенное `Remote ready / connecting / error` состояние, **не** выдумывать статус по одному наличию PID.

**WinForms NotifyIcon:** `Visible=true` при активном supervisor; `Visible=false` и `Dispose()` при полном выходе; корректно освободить `ContextMenuStrip`/resurces. Не создавать значок в `-SelfTest` или `-Preview`, чтобы тестовый/демо-режим не оставлял фоновых инстансов.

## 3. Критический конфликт с существующим single-instance кодом

В `Source/remote-window.ps1` текущий mutex `Local\\RemoteDesktopCommanderWindow-...` использует `Get-Process.MainWindowHandle` повторно запущенного GUI: после 1,5 сек без видимого окна и при возрасте ≥5 сек выполняется `Stop-Process -Force` (примерно строки 307–373 на `development@e7b33c2`).

**Скрытая Form закономерно может иметь `MainWindowHandle=0`**. Поэтому простое добавление NotifyIcon при сохранении старой эвристики **небезопасно:** второй запуск может убить здоровый tray supervisor и сорвать Remote-сессию.

**Неразрушающее правило:** наличие mutex означает «сессия принадлежит существующему процессу», а **не** «процесс завис». Не убивать peer только из-за отсутствия окна. Для удобного повторного открытия — минимальный same-user IPC/rendezvous (например, скрытый HWND + безопасное сообщение либо локальный именованный канал), отдельно спроектированный и проверенный; не открывать сетевой listener. Проверить PID/creation-time и user/session ACL при выборе IPC. При недоступности IPC fallback **no kill/no duplicate Remote**, только уход второго launcher и необязательное объяснение.

**Отдельный edge case:** updater при `exit code 42` закрывает форму и перезапускает процесс; существующие `$script:allowClose`, `$script:closeRequested` и владение mutex нельзя нарушить. Обновление, начатое при скрытом окне, также не должно порождать второго Remote.

## 4. Вопрос полного «Завершить RDC Relay…» — ещё открытый

Нажатие **X** владельцем уже однозначно определено: *GUI прячется, Remote и supervisor работают дальше*.

Но отдельная команда **«Завершить RDC Relay…»** должна явно сообщать последствия:
- Если завершить *только GUI/supervisor*, Remote может продолжить работу **без watchdog и auto-reconnect**, а фактическая независимость дочернего дерева от окончания скрытого `cmd`/PowerShell ещё **NOT CHECKED**.
- Если одновременно остановить Remote, может быть оборван активный MCP call; для Adopted/Unknown это не допускается без будущего explicit ownership policy и тестов.
- Поэтому до утверждения выхода + проверки поведения **не привязывать Exit к старому `Begin-RemoteOperation 'close'`** без особого рассмотрения. Действие должно быть доступно пользователю и иметь явное подтверждение последствий; реализации меню могут быть выполнены поэтапно, но не выдавать неработающий пункт за работающий.

**Архитектурная рекомендация на будущее:** «Завершить RDC Relay…» → неразрушающий уход supervisor с понятным предупреждением о потере мониторинга, **если** независимость Remote доказана; отдельная «Остановить Remote» только для проверенного Owned с подтверждением. Для adopted/unknown — no kill. Это не дополнительное согласованное решение владельца, а вариант для UX review.

## 5. Тесты и последовательность

**Первый шаг `PROG-005A` — только существующие функции и fake/AST проверки (Source не менять):**
- Зафиксировать текущую `FormClosing` семантику: X может вызвать `Begin-RemoteOperation 'close'`; во время `$script:initializing`/`$script:remoteOperation` closeRequested и deferred-close; `FormClosed` освобождает `timer`, `reader`, `proc`.
- Зафиксировать проверку duplicate-GUI/stale-PID и существующий update/relaunch exception; отдельно отметить, что AST mocks не проверяют реальный tray shell и Windows message pump.
- Никаких действий над реальным Remote, никаких OS child trees.

**Второй шаг `PROG-006` — *после независимого REV-005A и отдельного конкретного задания Programmer*:**
- Реализовать `NotifyIcon`/hide/show, защищённое различение closing reason/update/shell-exit, неповторяемую инициализацию и безопасный single-instance fallback.
- Минимальный объем `Source/remote-window.ps1` с тестами; не менять `Find-ExistingRemote`, `Stop-Remote`, `taskkill`, логику нового транспорта и обычную UI-визуализацию. Если для сценария «явный выход» потребуется ownership code, **отложить его** до отдельного решения, а не расширять PROG-006.
- Независимый Reviewer `REV-006`: сначала AST/fake контрактные тесты, затем **изолированный UI-тест в отдельной копии без настоящего Remote** с проверкой X → hidden → tray reopen и второго launcher. Не тестировать на пользовательской инсталляции; провести визуальную приёмку с владельцем.
- Негативные сценарии: повторный X, быстрое Open/Hide 10 раз, отсутствие/крах explorer, pending update, startup deferred close, Windows shutdown, repeated launcher while hidden, multiple display/DPI/scaling, keyboard-only и screenreader/tooltips, disposal и no leaked icon; сервисные операции не должны скрываться навсегда.
- Проверить недопустимость лишнего запуска `Start-Remote`, потери живого watchdog и повторения эффектов (таймер/reader/updater/лог).
- Любое реальное завершение процесса Remote через `taskkill`/переавторизацию для тестов **запрещено**.

**Третий шаг `PROG-005B` и основной `PROG-005`** остаются отдельными: реальные disposable process ownership tests только после конкретного разрешения и Reviewer; refactor stop-логики не зависит от прихода tray UI и не подменяется им.

## 6. Источники

- WinForms `NotifyIcon`: https://learn.microsoft.com/en-us/dotnet/desktop/winforms/controls/notifyicon-component-overview-windows-forms
- `FormClosing`, `Hide` vs `Close`: https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.form.formclosing
- `ApplicationContext` и корректный message loop: https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.applicationcontext
- Windows notification area guidance: https://learn.microsoft.com/en-us/windows/win32/uxguide/winenv-notification
- Проект: [PROG-005 process-ownership plan](PROG-005-PROCESS-OWNERSHIP-PLAN.md), [coordination board](../../../COORDINATION/BOARD.md), `Source/remote-window.ps1`.

**NOTE on UX conventions:** Windows guidance historically prefers normal Minimize и ясно различимые Close/Exit; **владелец прямо выбрал X → background tray**, поэтому для RDC Relay это согласованное исключение. Мы сохраняем штатное поведение кнопки «—», обеспечиваем доступный явный выход и объясняем фоновую работу без назойливых уведомлений.

**Verification boundary:** current source inspection, documented .NET/Windows APIs, feasibility reasoning. Tray executable, hidden form reactivation, shell restarts, installation/update integration, actual stream delivery: **NOT CHECKED**.
