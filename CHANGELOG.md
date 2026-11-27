# Changelog / Журнал изменений

Краткая история выпущенных версий RDC Relay. Последние версии — в начале.

A concise history of RDC Relay releases, newest first.

## 1.6.0 — 2026-11-25

### Русский

- **Новая архитектура.** RDC Relay поддерживает соединение в фоновом режиме независимо от основного окна. Управление доступно через системный трей.
- **Стабильность и подключение.** Переработаны управление процессами Remote, контроль готовности и восстановление связи. Используется актуальная версия оригинального Desktop Commander Remote.
- **Мониторинг.** Синхронизировано отображение остатка вызовов в главном окне и трее; улучшены обновление данных и проверка их актуальности.
- **Интерфейс.** Улучшены индикация состояния, визуальные эффекты, контекстные меню и диалоги. Обновлены оформление заголовка, прокрутка и адаптация окна к разным размерам и масштабам.
- **Журнал событий.** Просмотр и сохранение логов, автоматическая ротация, ограничение занимаемого пространства и улучшенная диагностика запуска.
- **Установка и обновления.** Setup предлагает установить Node.js 24 LTS, если необходимые зависимости отсутствуют. Предусмотрен отдельный канал последующих обновлений. Перед установкой завершите работающий RDC Relay.
- **Локализация.** Русский и английский языки с переключением в программе.

### English

- **New architecture.** RDC Relay maintains its connection in the background, independently of the main window, with system tray controls.
- **Reliability and connection.** Reworked Remote process management, readiness tracking and connection recovery. Uses the latest version of the original Desktop Commander Remote.
- **Monitoring.** Synchronized remaining calls in the main window and system tray, with improved data refresh and freshness checks.
- **Interface.** Refined status indicators, visual effects, context menus and dialogs. Updated the header design, scrolling and adaptation to different window sizes and display scaling.
- **Activity journal.** Log viewing, exporting, automatic rotation, storage limits and improved startup diagnostics.
- **Installation and updates.** Setup offers Node.js 24 LTS when required dependencies are missing. A dedicated update feed supports subsequent releases. Exit any running instance of RDC Relay before installation.
- **Localization.** Russian and English with in-app switching.

[Release / Релиз 1.6.0](https://github.com/Rubo-Facility/RDC-Relay/releases/tag/v1.6.0)

## 1.5.18 — 2026-10-20

**RU:** Исправлена кнопка обновления при запуске с `-SkipUpdate`; уведомление о новой версии обновляется без перезапуска окна и повторной анимации. Расширены тесты обновления.

**EN:** Fixed the update button when launched with `-SkipUpdate`; the version notice refreshes without restarting the window or replaying the animation. Expanded update tests.


## 1.5.17 — 2026-10-20

**RU:** Безопасное восстановление неполного кеша npm при ENOENT/-4058; уточнены инструкции первичной OAuth-авторизации и добавлена ссылка на страницу подтверждения устройства.

**EN:** Safe recovery of incomplete npm cache entries on ENOENT/-4058; clarified first-device OAuth instructions and added a device verification shortcut.

## 1.5.16 — 2026-10-17

**RU:** Анимированное уведомление об обновлении и фоновая проверка версии; исправлены повторные вспышки при восстановлении окна, обработка ручной остановки и ошибок запуска npx.

**EN:** Animated update notice and background version checks; fixed stale recovery flashes, manual Stop state handling and npx startup error classification.

## 1.5.15 — 2026-10-08

**RU:** Восстановлено расположение нижней подсказки, разделителя и номера версии по образцу 1.5.12.

**EN:** Restored the 1.5.12 footer hint, separator and version layout.

## 1.5.14 — 2026-10-08

**RU:** Исправлено выравнивание элементов нижней строки; синхронизирован номер версии в программе и метаданных релиза.

**EN:** Corrected footer alignment and synchronized the runtime version with release metadata.

## 1.5.13 — 2026-10-08

**RU:** Автоматическое восстановление повреждённого кеша npx; корректное ожидание медленного подключения и защита состояния ручной остановки от запоздалых событий Remote.

**EN:** Automatic recovery of corrupted npx cache entries; improved slow-connection handling and protected manual Stop from late Remote events.

## 1.5.12 — 2026-10-07

**RU:** Транзакционные установка и обновление с откатом; защита ярлыков установленной программы от Portable-копий. Операции Remote вынесены из UI-потока, улучшены кнопки, клавиатурная навигация и восстановление единственного экземпляра. Расширены проверки целостности, отката и GPU-отрисовки.

**EN:** Transactional installation and updates with rollback; protected installed shortcuts from portable copies. Moved Remote operations off the UI thread, improved controls, keyboard navigation and single-instance recovery. Expanded integrity, rollback and GPU rendering tests.

## 1.5.11 — 2026-10-07

**RU:** Регистрация программы в списке установленных приложений Windows и штатное удаление; EXE-запуск Portable. Сохранён прежний путь установки для совместимости обновлений.

**EN:** Windows Installed Apps registration and standard uninstall; EXE launcher for Portable. Retained the existing installation path for upgrade compatibility.

## 1.5.10 — 2026-10-06

**Русский**

- Контроль реальной готовности Remote, ограниченные повторные запуски и восстановление связи без конфликтов со встроенным механизмом переподключения Desktop Commander.
- Разделение событий подключения и выполнения команд; защита от ложных ошибок, улучшение журнала, прокрутки и сохранения предыдущего лога.
- Обновление GPU-разделителя: цветовые состояния подключения, ошибки и восстановления, плавность анимации, исправления прозрачности и порядка слоёв. Воспроизводимая сборка четырёх шейдеров и расширенные регрессионные проверки.

**English**

- Remote readiness supervision, bounded restarts and connection recovery without competing with Desktop Commander's reconnect mechanism.
- Separated connection and tool activity events; prevented false faults and improved log routing, scrolling and previous-session log retention.
- Updated the GPU divider: connecting, fault and recovery colors, smoother animation, transparency and layering fixes. Reproducible four-shader build and expanded regression checks.

## 1.5.9 — 2026-10-06

**RU:** Собственный фирменный значок RDC Relay, адаптация для малых размеров и отдельный идентификатор приложения Windows; исправлена миграция ярлыков и значков.

**EN:** Original RDC Relay icon, small-size artwork and a dedicated Windows application identity; fixed shortcut and icon migration.

## 1.5.8 — 2026-10-06

**RU:** Приостановка GPU-анимации при скрытом, свёрнутом или перекрытом окне без остановки мониторинга; корректное возобновление анимации и обновление существующих ярлыков.

**EN:** Paused GPU animation while hidden, minimized or fully occluded without stopping monitoring; improved animation resumption and existing shortcut updates.

## 1.5.7 — 2026-10-06

**RU:** Переименование приложения и репозитория в RDC Relay; обновление адреса GitHub, имён установщика, Portable и ярлыков с сохранением совместимости прежней установки.

**EN:** Renamed the application and repository to RDC Relay; updated the GitHub endpoint, installer, portable and shortcut names while preserving installation compatibility.

## 1.5.6 — 2026-10-06

**RU:** Кнопка Stop/Start вместо неоднозначного действия закрытия, векторные значки и доработка панели управления. Переработаны журнал, полосы прокрутки и перетаскивание разделителя; адаптивное время индикации активности.

**EN:** Replaced the ambiguous close action with Stop/Start, added vector glyphs and refined controls. Reworked the log viewport, scrollbars and divider dragging; adaptive activity hold timing.

## 1.5.5

**RU:** Выделен канал обновлений `stable`, проверка SHA-256 и восстановление файлов той же версии; усилены управление единственным экземпляром и завершение процессов. Закреплена версия Desktop Commander 0.2.52, улучшен поиск npx. Добавлены резервная статическая отрисовка и воспроизводимая сборка шейдеров, Setup и Portable.

**EN:** Introduced the `stable` update channel, SHA-256 verification and same-version repair; strengthened single-instance and process cleanup. Pinned Desktop Commander 0.2.52 and improved npx discovery. Added a static rendering fallback and reproducible shader, Setup and Portable builds.

## 1.5.4

**RU:** Добавлен GPU-разделитель с адаптивной индикацией активности; устранён перехват фокуса входящими задачами и повторным запуском. Первое самообновление через GitHub с проверкой SHA-256 и откатом; доработан значок.

**EN:** Added the GPU activity divider with adaptive hold timing; prevented focus stealing by incoming tasks and second launches. Introduced GitHub-backed self-update with SHA-256 verification and rollback; refined the icon.

---

Подробная техническая история старых версий сохранена в Git на теге [v1.5.18](https://github.com/1rubass1/RDC-Relay/blob/v1.5.18/CHANGELOG.md).

Detailed technical history of legacy versions remains in Git at the [v1.5.18 tag](https://github.com/1rubass1/RDC-Relay/blob/v1.5.18/CHANGELOG.md).
