# RDC Relay — системное архитектурное ревью (23 октября 2026)

> **Статус: экспертная оценка и предложения, не принятое решение.** Роль Architect. **Только для development**. Рабочую программу, `Source/`, `main`, `stable`, пользовательский Codex и сетевые настройки этот документ не изменяет. Отдельный пересмотр идеи: [PR #2](https://github.com/1rubass1/RDC-Relay/pull/2) остаётся самостоятельным проектом решения.

## Краткий вердикт

**Сохранять RDC Relay и локальный DesktopCommanderMCP.** Исходная цель владельца оправданна: избегать счётчика вызовов коммерческого Desktop Commander Remote за счёт **своего транспорта**, иметь прямой HTTPS на статическом IP при возможности и резервные каналы. Но архитектура должна ясно разделять:

1. **AI client / permission model:** ChatGPT Plus, Codex CLI, Gemini CLI и т.д. (собственные ограничения и тарифные права).
2. **Transport / ingress:** hosted Desktop Commander Remote, локальный stdio, самоуправляемый HTTPS / MCP gateway, в будущем managed tunnel.
3. **Executor:** оригинальный локальный `@wonderwhy-er/desktop-commander`, выполняющий file/shell/process.
4. **Access policy / isolation:** граница между Internet-клиентом и привилегированным исполнителем; не доверять только UI/prompt.
5. **Supervisor / Windows GUI:** собственно RDC Relay — health, process ownership, lifecycle, обновления, состояние пользователя.

**Разные транспортные провайдеры и разные ИИ-клиенты не взаимозаменяемы.** Переключить локальную службу — не то же самое, что автоматически перенастроить ChatGPT connector. «Безлимитный собственный MCP» означает отсутствие **платы/квоты Remote-посредника**, но не отсутствие ограничений клиента-модели/электроэнергии/интернета.

## Что проверено в этот цикл

- Прочитаны `PROJECT_INDEX.md`, `PROJECT_CONTEXT.md`, `COORDINATION/BOARD.md`, product README, current roadmap/requirements, предыдущий technical design, transport evidence и release boundary.
- Исследован **фактический** `Source/remote-window.ps1` v1.5.18: **6676 строк, 71 PowerShell-функция**, UI и процессная логика в одном файле. Проанализированы lifecycle, считывание логов, health-эвристики, tool events, reconnect, обновление и тесты.
- Без запуска GUI/Remote выполнен PowerShell AST parse четырёх скриптов: `remote-window.ps1`, `update-notice.ps1`, `update.ps1`, `build-release.ps1` — **0 ошибок синтаксического разбора**. Это **не** проверка поведения.
- Прочитан `Scripts/build-release.ps1`: явный allowlist payload и отдельный installer/ZIP, но скрипт нормализует сами исходники в рабочем дереве перед build. Не запускался полный build, не выполнялись тесты реального UI/Remote.
- Текущая опубликованная база: v1.5.18, `main`/`stable` `5b1fdf5`; ветка `development` содержит только согласованную документационную миграцию. Codex preflight показывает наличие CLI/Node/login, но **реального Codex→MCP tools/call в проекте нет**. Задача `PROG-002` **предложена только в незамёрженном PR #2**; полномочия и реальная проверка всё ещё NOT CHECKED.

## Что существенно изменилось в экосистеме

### MCP 2026-07-28 — архитектурный фактор №1

Версия MCP **2026-07-28** опубликована и вводит **stateless** core: вместо `initialize/initialized` и `Mcp-Session-Id` — метаданные на каждом запросе и `server/discover`; `Mcp-Method` / `Mcp-Name` headers, cache hints, подписки и новое поведение авторизации. Старые `initialize`-тесты Spike 1 по прежнему протоколу подтверждают **только проверенную старую реализацию**, а не соответствие нового публичного сервера современным клиентам. Старые реализации продолжают встречаться и обычно поддерживаются SDK через **compatibility / negotiation**, поэтому нельзя «ломать» upstream из-за одного нового стандарта.

**Проектное следствие:** не писать вручную HTTP→JSON-RPC router по учебному примеру 2025 года. Выбрать актуальный SDK, проверяющий нужную ревизию и совместимость с upstream stdio. Сделать contract tests для legacy и 2026-07-28 маршрутов, включая `server/discover`, auth и неизвестные versions; задокументировать фактически поддерживаемые клиентские версии. Не утверждать автоматическую совместимость без теста.

Официальные источники: [MCP 2026-07-28 GA, 28 июля](https://blog.modelcontextprotocol.io/posts/2026-07-28/), [изменения спецификации](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/changelog.mdx), [официальное руководство TypeScript SDK по переходу](https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/migration/support-2026-07-28.md).

### Реальные клиентские альтернативы

- **ChatGPT Plus:** по текущей [официальной справке](https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt) **полный custom MCP** доступен Business и Enterprise/Edu; Pro имеет особый режим read/fetch. На Plus **не рассчитывать** как на клиента к *собственному* полноценному внешнему MCP. При этом существующий **официальный Remote** уже подключён через свою разрешённую интеграцию; нельзя приравнивать её к разрешению на arbitrary personal MCP.
- **Codex CLI:** позволяет конфигурировать local/remote MCP, а на STARMER уже установлен и авторизован; `PROG-002` до сих пор нужен для **реального** tools/list и безопасного tools/call через DesktopCommanderMCP. Не путать встроенный shell Codex и MCP-вызов. [OpenAI Docs MCP / Codex](https://developers.openai.com/learn/docs-mcp).
- **Gemini CLI:** официально поддерживает MCP **stdio и HTTP**; документирован бесплатный пользовательский вход через Google-аккаунт **до 1000 запросов в день** (модельный quota, **не** безлимит и **не** количество MCP-вызовов). Это интересный **второй независимый AI client** для сравнения Codex (со своими условиями и данными), но не транспортный провайдер RDC Relay. [MCP commands](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/cli-reference.md), [official quotas](https://geminicli.com/docs/resources/quota-and-pricing/).
- **OpenAI Responses/Agents API:** документирует remote MCP и session-local stdio, включая возможность `allowed_tools`, но это **отдельная developer/API поверхность с собственной тарификацией**, а не право ChatGPT Plus на custom connector. [Agents MCP](https://developers.openai.com/api/docs/guides/agents-api/tools/mcp).

### Upstream Desktop Commander

Hosted [Remote Desktop Commander](https://github.com/desktop-commander/remote-desktop-commander/blob/main/README.md) — проприетарный сервис, репозиторий публикует документы/manifest, **не self-hostable hosted server**. Локальный [DesktopCommanderMCP](https://github.com/wonderwhy-er/DesktopCommanderMCP) открытый и работает по stdio. На текущую дату релиз `v0.2.52` остаётся последним показанным upstream, а RDC Relay пинит именно его: **нет доказанной причины срочно обновлять pin**. Собственный HTTPS gateway — самостоятельный продукт поверх локального stdio, не переупаковка чужого hosted Remote.

## Конкретные находки по продукту (код v1.5.18)

### P1 — Структурная связанность UI, процесса и протокола

`Source/remote-window.ps1` — **6676 строк**, содержит inline UI/C# отрисовку, WinForms, разбор текстовых строк Remote, process ownership, обновление и state machine. `Process-RemoteLine` ~163 строки, `Render-CompactLog` ~151, `Refresh-Window` ~120; C# визуальных классов много, их не нужно переписывать ради транспортного сервиса.

**Рефакторинг по швам**, а не переписывание GUI: чистый парсер фактов `raw line → RemoteObservation`, чистый reducer `observation+old state → new state/effects`, отдельный adapter lifecycle реального Remote с PID/owner guard. UI **только отображает** уже вычисленное состояние. Оставить текущую тему, отрисовку и пользовательскую визуальную приёмку без изменений. Мигрировать пошагово с equivalence tests на записанных **санитизированных** trace fixtures.

### P1 — Process ownership / forced stop

`Start-Remote` вызывает `Find-ExistingRemote` и может **подхватить** работающий `cmd.exe` по совпадению собственной log path. `Stop-Remote` выполняет `taskkill /PID ... /T /F` даже для принятого процесса; это безусловное принудительное завершение всего дерева. `remote-window.ps1` при обнаружении второй GUI-копии считает GUI «зависшей», если через 1,5 с отсутствует окно и процесс старше 5 с, после чего вызывает `Stop-Process -Force`.

**Это риск, а не доказанный дефект.** При медленном создании окна или выполняющемся MCP tool можно убить живой процесс/сорвать операцию. Нужен контракт **owned/adopted/external**, PID+creation time, проверяемая session identity, test slow startup/no-window, active tool, orphan, restart, logout, updater concurrency; shutdown graceful при возможности и force только после bounded timeout/осознанного решения.

### P1 — Логи не равны типизированному health

`Update-RemoteHealthFromLine` выводит состояние из строк `Presence tracked`, `Channel closed`, `Local ... restarted`; `Process-RemoteLine` считает emoji-строки началом/успехом/ошибкой tools. Защита от сериализованных payload уже есть, но текстовые события меняются с upstream release и их происхождение остаётся важно.

**Не переводить всё на protocol-level health без проверенной поверхности upstream.** Сначала отдельные уровни `ProcessAlive`, `TransportConnected`, `ExecutorReady`, `LastToolSuccess`, `FaultLatched`; проверки на подставленные строки из tool output, дубли ready/failed, обрыв и сохранение последнего FAIL. Текущий pin обязателен, пока тесты фактически не приняты.

### P1 — Автоматический контроль регрессий покрывает не всё

`Tests/Test-UiLifecycle.ps1` парсит AST и **извлекает функции**, заменяя процессы на fake. Это хорошо для логики порядка операций, но **не доказывает** настоящий stop/restart windows process tree и remote→ChatGPT end-to-end. В `Tests/` есть `Test-NpxRecovery.ps1`, а в `Scripts/build-release.ps1` не обнаружен его явный вызов в release sequence, хотя npm `-4058/ENOENT` исправлялся недавно.

Предлагаю добавить именно этот целевой regression gate в **будущей задаче Programmer**, не запускать live Remote в тестах. Для наиболее рискованных веток сделать отдельные изолированные process- и integration-тесты; Reviewer проверяет реальные пути на candidate artifact. Все результаты только PASS/FAIL/NOT CHECKED с версией и фактическими доказательствами.

### P2 — Сборка изменяет tracked source

`Scripts/build-release.ps1` на старте вызывает `Convert-ToCanonicalUtf8Lf` на файлах `Source/`, то есть **переписывает исходники на месте**, ещё до компиляции. Это может порождать неожиданные local diffs/смешивать normalization с исходной разработкой.

Предложение: проверять LF/кодировки отдельным lint-check, а нормализацию выполнять в **временном staging directory** с последующим построением manifest/hashes из единого immutable staged payload. Для первой итерации не менять формат ZIP или updater; при изменении тестировать SHA256 и transactional rollback.

### P2 — Публичная supply-chain и dev/release separation

Updater получает `stable` branch HEAD, затем immutable SHA, затем manifest и файлы по HTTPS; **проверяет SHA256 payload** и делает rollback. Это хорошая защита от случайной подмены/частичной загрузки, но **хеши из того же репозитория не защищают от компрометации GitHub аккаунта или release branch** — не следует описывать их как independent code signing.

Рекомендуются branch protections, минимальные права токенов, проверенный manual release approval, независимые артефакты/проверка signature при обоснованной потребности. Документы и Pen остаются **только development**, `main/stable` не должны их получать; текущее правило «не делать merge development целиком» нужно со временем подкрепить CI-гейтом на release candidate.

### P2 — Избирательная производительность

`Add-RemoteChunk` уже обрабатывает порции, а `Render-CompactLog` вызывается после chunk; `Add-Log` отдельно вызывает render, таймер WinForms = 700 мс. Есть ограничение истории последних 6 UI событий и catch-up tail; **нет подтверждённого узкого места**. Сначала снять ограниченные performance traces на синтетических логах, затем при необходимости debounce render и кэширование layout. Не собирать сотни кадров ради перфоманса и не проводить стихийный UI-рефакторинг.

## Вердикт по архитектуре собственного gateway

**Самостоятельный MCP Gateway логичен как независимый транспорт при наличии совместимого AI-клиента; не как способ «обойти» права ChatGPT Plus.** Статический IP действительно даёт direct-IP HTTPS без SaaS tunnel при проверенных порте, firewall, certificate и клиента. Но full bridge к файловой системе/терминалу под пользовательскими правами за публичным IP — **высокорисковая поверхность**.

При реализации: trusted TLS+автоматическое обновление сертификата, OAuth/актуальный механизмы клиентской аутентификации, token audience/scope/expiry, resource-level authorization; отдельный малопривилегированный Windows account/VM, paths allowlist, tool allowlist и опасные действия — отдельное явное разрешение. Fail-closed, bounded requests/logs, rate-limit, concurrency и stop/recovery. Не пускать произвольный `cmd`/filesystem через experimental bridge. Router/firewall не менять до explicit owner authorization и Reviewer threat review.

**Не смешивать две вещи:** transport provider переключает локальную схему RDC Relay, а AI client имеет свою регистрацию MCP и собственные лимиты. MVP может быть **ручным** переключением двух подтверждённых вариантов (hosted Remote vs самоуправляемый gateway), без автоматического роутинга команд между клиентскими аккаунтами.

## Рекомендуемый план (вместо масштабного рефакторинга сейчас)

| Порядок | Результат | Роль | Критерий перехода |
| --- | --- | --- | --- |
| **0.** | Принять/исправить стратегию PR #2 и этот отчёт | Owner + Architect | Согласована матрица client vs transport vs executor, угрозы и границы стоимости |
| **1.** | `PROG-002` (запись пока лишь в PR #2): Codex CLI → pin v0.2.52 stdio MCP | Programmer | Изолированный `initialize/tools/list/tools/call` read-only fixture для legacy upstream; доказательство реального MCP маршрута; чистая остановка |
| **2.** | Gemini CLI vs Codex feasibility **при желании** | Programmer | Нативное MCP read-only и различия прав/лимитов; без новых платных аккаунтов/глобальных настроек |
| **3.** | Безопасный transport gate и протокол 2026 | Architect + Reviewer | Поддерживаемый AI-клиент; совместимые версии; negative auth + threat-model; только ping tool |
| **4.** | Пошаговые изолированные seam tests supervisor/Remote | Programmer | Нулевая регрессия v1.5.18; настоящий lifecycle в sandbox |
| **5.** | Подтверждённый protected gateway на статическом IP | Programmer + Reviewer | Успешный подтверждённый E2E по реальному клиенту и ограниченным tools; security GO |
| **6.** | Минимальный второй provider UI и отдельный release candidate | Programmer + Designer + Reviewer | Ручной выбор, безопасные stop/restart, recovery, полная регрессия/человеческая UX-приёмка |

**Stop rule:** если клиент не умеет подключаться к нашему собственному MCP — не строить дорогостоящий публичный gateway только ради ChatGPT Plus. Локальный клиент уже может решить значительную часть потребности без тоннелей. Учитывать расходы модели/питания/сети даже при `$0` за transport.

## Сводка проверки

| Что проверено | Состояние |
| --- | --- |
| Чтение проектных архитектурных документов | **PASS** |
| Код `remote-window.ps1` и ключевые process/log/refetch маршруты | **STATIC REVIEW** (нет подтверждённых runtime bugs) |
| AST syntax четырёх PowerShell scripts | **PASS: 0 parse errors** |
| Современная MCP 2026-07-28 и клиентские права Plus | **EXTERNAL DOCS VERIFIED**; production compatibility NOT CHECKED |
| Codex + DesktopCommanderMCP реальный `tools/call` | **NOT CHECKED**, `PROG-002` |
| Gemini CLI локальная MCP конфигурация/действие | **NOT CHECKED**, только официальная документация |
| Release candidate, actual updater, UI keyboard/click, public gateway security | **NOT CHECKED**, не утверждать PASS |

**Принцип Playbook:** решения owner approval прежде, чем менять roadmap, runtime, публичный порт или состав команды. На данном этапе этот отчёт — план выбора, а не разрешение на запуск дополнительных агентов.
