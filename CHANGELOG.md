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
