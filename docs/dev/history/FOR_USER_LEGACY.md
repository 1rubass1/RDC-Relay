> **LEGACY IMPORT, not current instructions.** Source: FOR_USER.md from STARMER before Playbook migration (2026-10-22). This document preserves historical research or decisions, may contain superseded instructions/versions, and is not a production requirement by itself. Refer first to repository PROJECT_INDEX.md, PROJECT_CONTEXT.md, COORDINATION/BOARD.md and current planning. Sensitive IDs are redacted in the Git copy; byte-exact historical original is preserved only in STARMER local archive.
# RDC Relay — For User

> Этот файл — простая памятка для владельца проекта.
>
> Здесь не описывается внутренняя архитектура во всех подробностях. Его задача — быстро объяснить, **что за файлы лежат в корне RDC, зачем каждый из них нужен и какие из них стоит закрепить в ChatGPT Project**.

---

# 1. Корень проекта

Основная папка проекта:

```text
E:\Projects\GitSync\RDC
```

Сейчас структура устроена так:

```text
E:\Projects\GitSync\RDC
│
├── FOR_USER.md
├── HANDOFF.md
├── WORKLOG.md
├── ROADMAP.md
├── TECHNICAL_DESIGN.md
├── SOURCES.md
├── SPIKE_0_OPENAI_TUNNEL.md
│
├── RDC-Relay Work\
│   └── активный Git-репозиторий с кодом RDC Relay
│
└── _archive\
    └── архив старых материалов/версий
```

---

# 2. Зачем стратегические файлы лежат в корне RDC

Они описывают **весь проект**, а не только конкретную рабочую копию Git.

Это важно, потому что со временем могут появиться:

- новые рабочие ветки;
- отдельные эксперименты;
- дополнительные checkout;
- архивные версии;
- отдельные компоненты;
- новые MCP transport/provider реализации.

Поэтому стратегия и память проекта лежат на уровень выше активного репозитория.

Активный код находится здесь:

```text
E:\Projects\GitSync\RDC\RDC-Relay Work
```

---

# 3. HANDOFF.md

Файл:

```text
E:\Projects\GitSync\RDC\HANDOFF.md
```

## Для чего нужен

Это **стабильная карта проекта для нового агента**.

Если открыть новый чат и агент почти ничего не знает о RDC Relay, этот файл должен дать ему базовое понимание:

- что это за проект;
- где лежит код;
- какая production-версия сейчас считается стабильной;
- какие основные архитектурные решения уже приняты;
- какие правила нельзя нарушать;
- какие документы читать дальше;
- что нельзя делать преждевременно.

## Как часто менять

Редко.

Его не нужно переписывать после каждой рабочей сессии.

Менять имеет смысл только когда действительно меняется:

- структура проекта;
- production baseline;
- фундаментальная архитектура;
- общий порядок работы;
- важные долговременные правила.

## Роль

```text
HANDOFF.md
= стабильная инструкция "что это за проект"
```

---

# 4. WORKLOG.md

Файл:

```text
E:\Projects\GitSync\RDC\WORKLOG.md
```

## Для чего нужен

Это **живая память текущей разработки**.

Именно сюда агент должен записывать:

- что делалось в последней сессии;
- что сейчас находится в работе;
- какие файлы менялись;
- какая ветка используется;
- что уже проверено;
- что не проверено;
- что осталось незавершённым;
- какие проблемы обнаружены;
- какой следующий конкретный шаг;
- есть ли незакоммиченные изменения;
- какое состояние у установленной тестовой версии.

Если чат внезапно закончится, следующий агент должен открыть WORKLOG и быстро понять, где остановилась работа.

## Как часто менять

Часто.

Практически после каждой существенной рабочей сессии.

## Роль

```text
WORKLOG.md
= "что происходило прямо сейчас и где мы остановились"
```

---

# 5. ROADMAP.md

Файл:

```text
E:\Projects\GitSync\RDC\ROADMAP.md
```

## Для чего нужен

Это **план развития проекта по этапам**.

Он отвечает на вопросы:

- куда вообще идёт RDC Relay;
- что должно быть сделано сначала;
- что должно быть сделано потом;
- какие этапы уже завершены;
- какой этап следующий;
- какие вещи сознательно отложены;
- при каких условиях мы переходим к следующей фазе.

Например, сейчас в Roadmap зафиксировано:

```text
production 1.5.12
→ OpenAI Tunnel Spike
→ ConnectionProvider abstraction
→ OpenAITunnelProvider
→ provider UX
→ security/packaging
→ позже zrok
→ ещё позже multi-device/broker
```

## Как часто менять

Когда меняется реальный план разработки.

Не после каждой мелкой правки.

## Роль

```text
ROADMAP.md
= "куда мы идём"
```

---

# 6. TECHNICAL_DESIGN.md

Файл:

```text
E:\Projects\GitSync\RDC\TECHNICAL_DESIGN.md
```

## Для чего нужен

Это **подробное техническое описание того, как проект планируется устроить**.

Там находятся:

- целевая архитектура;
- ConnectionProvider;
- DesktopCommanderRemoteProvider;
- OpenAITunnelProvider;
- normalized RDC events;
- state machine;
- health/readiness;
- failure semantics;
- credential handling;
- provider switching;
- packaging;
- process ownership;
- testing strategy;
- migration strategy;
- definition of done.

Если агенту нужно не просто понять «что делать дальше», а начать писать архитектурный код, ему нужен именно этот файл.

## Как часто менять

Когда принято устойчивое техническое решение.

Не использовать как дневник.

## Роль

```text
TECHNICAL_DESIGN.md
= "как это должно быть реализовано"
```

---

# 7. SOURCES.md

Файл:

```text
E:\Projects\GitSync\RDC\SOURCES.md
```

## Для чего нужен

Это **реестр внешних источников и проверенных утверждений**.

Там собраны ссылки на:

- OpenAI Secure MCP Tunnel;
- OpenAI tunnel-client;
- permissions;
- configuration;
- health endpoints;
- Desktop Commander pricing;
- DesktopCommanderMCP;
- Desktop Commander Remote;
- OpenZiti/zrok MCP Gateway.

Также там разделено:

```text
что уже подтверждено официальной документацией

и

что ещё нужно проверить на нашем конкретном аккаунте/машине
```

Это важно, чтобы следующий агент не строил архитектуру на основе старого чата или собственной памяти.

## Как часто менять

Когда:

- появляется новый важный внешний источник;
- документация поставщика изменилась;
- ранее непроверенная гипотеза стала фактом;
- внешний факт перестал быть актуальным.

## Роль

```text
SOURCES.md
= "откуда мы это знаем"
```

---

# 8. SPIKE_0_OPENAI_TUNNEL.md

Файл:

```text
E:\Projects\GitSync\RDC\SPIKE_0_OPENAI_TUNNEL.md
```

## Для чего нужен

Это **пошаговый эксперимент**, который нужно выполнить перед началом большого provider-refactor.

Он должен доказать реальную цепочку:

```text
ChatGPT
→ OpenAI Secure MCP Tunnel
→ tunnel-client
→ local DesktopCommanderMCP
→ STARMER
```

Внутри уже есть чек-лист:

- OpenAI Tunnels availability;
- permissions;
- tunnel ID;
- runtime key;
- tunnel-client;
- doctor;
- healthz;
- readyz;
- ChatGPT discovery;
- read tool;
- write tool;
- reconnect;
- MCP child failure;
- результаты;
- GO / NO-GO.

Главное преимущество — следующий агент не должен придумывать план эксперимента с нуля.

## Как часто менять

Во время самого Spike 0 — активно.

После его завершения результаты остаются как техническое доказательство принятого решения.

## Роль

```text
SPIKE_0_OPENAI_TUNNEL.md
= "конкретный эксперимент, который нужно выполнить сейчас"
```

---

# 9. FOR_USER.md

Файл:

```text
E:\Projects\GitSync\RDC\FOR_USER.md
```

Это текущий документ.

Он нужен только для владельца проекта, чтобы не вспоминать назначение каждого служебного файла.

Агенту он практически не нужен — вся необходимая рабочая информация уже есть в HANDOFF/WORKLOG/ROADMAP/TECHNICAL_DESIGN.

## Роль

```text
FOR_USER.md
= "что за документы здесь лежат и зачем они нужны"
```

---

# 10. RDC-Relay Work

Папка:

```text
E:\Projects\GitSync\RDC\RDC-Relay Work
```

Это **активный Git working tree**.

Внутри находятся:

- Source;
- Installer;
- Scripts;
- Tests;
- README;
- CHANGELOG;
- Git metadata;
- build/release logic;
- исходный код RDC Relay.

Именно здесь агенты вносят изменения в программу.

Стратегические документы намеренно находятся уровнем выше.

---

# 11. _archive

Папка:

```text
E:\Projects\GitSync\RDC\_archive
```

Это архив.

Новый агент не должен автоматически считать материалы из архива актуальными.

Если между архивом и текущей рабочей копией есть противоречие, приоритет:

```text
фактический текущий Git/runtime
→ WORKLOG
→ HANDOFF
→ ROADMAP / TECHNICAL_DESIGN
→ архив
```

---

# 12. Что закрепить в ChatGPT Project

Рекомендую закрепить все основные файлы:

```text
HANDOFF.md
WORKLOG.md
ROADMAP.md
TECHNICAL_DESIGN.md
SPIKE_0_OPENAI_TUNNEL.md
SOURCES.md
```

`FOR_USER.md` можно закрепить тоже, но он предназначен прежде всего для пользователя и не обязателен агенту.

---

# 13. Рекомендуемый порядок чтения для нового агента

```text
1. HANDOFF.md
2. WORKLOG.md
3. ROADMAP.md
4. SPIKE_0_OPENAI_TUNNEL.md
5. TECHNICAL_DESIGN.md
6. SOURCES.md
7. код / README / CHANGELOG по необходимости
```

Почему именно так:

### HANDOFF

Сначала понять проект и правила.

### WORKLOG

Потом понять, где именно остановилась текущая работа.

### ROADMAP

После этого понять, какое место текущая задача занимает в общем плане.

### SPIKE

Если текущая работа относится к OpenAI Tunnel, получить конкретный чек-лист.

### TECHNICAL DESIGN

Когда нужно проектировать или менять код — читать архитектуру.

### SOURCES

Когда нужно перепроверять внешние факты.

---

# 14. Что обновляет агент после рабочей сессии

Минимально:

```text
WORKLOG.md
```

Если изменился долговременный план:

```text
ROADMAP.md
```

Если принято новое устойчивое архитектурное решение:

```text
TECHNICAL_DESIGN.md
```

Если появился новый внешний факт/источник:

```text
SOURCES.md
```

Если изменился фундаментальный baseline/структура проекта:

```text
HANDOFF.md
```

---

# 15. Главное правило

Не превращать все документы в один огромный постоянно переписываемый файл.

Разделение специально сделано таким:

```text
HANDOFF
= стабильная основа

WORKLOG
= текущее состояние

ROADMAP
= план

TECHNICAL_DESIGN
= архитектура

SPIKE
= текущий эксперимент

SOURCES
= доказательства и внешние ссылки

FOR_USER
= памятка владельцу проекта
```

Так следующий агент может получить именно тот слой информации, который ему нужен, не разрушая остальную документацию.

---

# 16. Короткая версия

Если нужно помнить только одну схему:

```text
HANDOFF.md
"Что это за проект?"

WORKLOG.md
"Что сейчас происходит?"

ROADMAP.md
"Куда мы идём?"

TECHNICAL_DESIGN.md
"Как это должно работать?"

SPIKE_0_OPENAI_TUNNEL.md
"Что конкретно проверяем следующим?"

SOURCES.md
"Почему мы считаем это правдой?"

FOR_USER.md
"Что за файлы я вообще вижу?"
```
