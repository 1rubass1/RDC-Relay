> **LEGACY IMPORT, not current instructions.** Source: ROADMAP.md from STARMER before Playbook migration (2026-10-22). This document preserves historical research or decisions, may contain superseded instructions/versions, and is not a production requirement by itself. Refer first to repository PROJECT_INDEX.md, PROJECT_CONTEXT.md, COORDINATION/BOARD.md and current planning. Sensitive IDs are redacted in the Git copy; byte-exact historical original is preserved only in STARMER local archive.
# RDC Relay — Roadmap

> **2026-10-20 PUBLIC HTTPS CHECKPOINT:** Isolated Pinggy external HTTPS tunnel plus
> official MCP Streamable HTTP client succeeded against the harmless
> `rdc_spike_public_ping` tool; a separate synthetic Bearer-gated endpoint
> correctly rejected wrong/missing secrets. This proves transport viability,
> NOT ChatGPT plugin/workspace access and NOT OAuth for real tools.
> Cloudflare Quick Tunnel failed on missing DNS SRV resolution on STARMER.
> `SPIKE_1_DIRECT_HTTPS_MCP.md` records exact tests and decision.
> Public DesktopCommanderMCP tools remain forbidden until OAuth, public
> ChatGPT end-to-end, threat model and reconnect gates pass.


> **Update 2026-10-20:** Spike 0 OpenAI Secure MCP Tunnel remains blocked at ChatGPT
> workspace validation. **Spike 1 Direct HTTPS MCP** is now active; the loopback
> Streamable HTTP MCP and localhost HTTP→stdio DesktopCommanderMCP fixture-read
> both PASSED. Public HTTPS, authentication, ChatGPT discovery and real end-to-end
> tool calls have NOT been tested. See `SPIKE_1_DIRECT_HTTPS_MCP.md`.
> **Priority:** prove authenticated public HTTPS transport in an isolated probe
> before Phase 1 ConnectionProvider. The historical "NEXT" in Phase 0.5 below
> does not override this newer status.


> Исторический план составлен 2026-10-07; базовый статус обновлён 2026-10-17.
>
> Current published production: **RDC Relay v1.5.16**, commit `cbbd3ecd9610a3cbca7fdb19c66d43380b7b34a0`, release `v1.5.16` (main/stable). v1.5.12 (`4e47cee`) и v1.5.15 (`eace20c`) остаются rollback/reference points. На STARMER после публикации ещё работала установленная 1.5.15, которую пользователь может обновить штатным механизмом.
>
> Spike 0 уже проведён и помечен **BLOCKED/NO-GO** для ChatGPT end-to-end, поэтому отмеченный ниже статус NEXT устарел. В дополнение к OpenAI Tunnel пользователь рассматривает прямой **self-hosted HTTPS MCP endpoint** и ChatGPT custom-MCP/plugin ZIP; это направления исследования, а не реализованные функции. Не начинать provider refactor без проверки реального вызова инструмента и модели угроз.
>
> Рабочий каталог: `E:\Projects\GitSync\RDC\RDC-Relay Work`.

## 1. Цель

Превратить RDC Relay из GUI/supervisor, жёстко привязанного к Desktop Commander Remote, в **supervisor нескольких способов доставки MCP до локальной машины**.

Ключевой практический мотив: сохранить DesktopCommanderMCP как зрелый локальный execution engine, но иметь альтернативный transport, который не проходит через коммерческий Desktop Commander Remote и, следовательно, не расходует его бесплатный лимит 10 000 Remote tool calls/month.

Целевая схема первого альтернативного пути:

```text
ChatGPT
   │
   ▼
OpenAI Secure MCP Tunnel
   │
   ▼
tunnel-client on STARMER
   │ stdio
   ▼
DesktopCommanderMCP
   │
   ▼
local machine resources
```

Важно: это не обещание «безлимитного бесплатного Remote». Документация Desktop Commander подтверждает, что их **локальный MCP server** бесплатен и не имеет месячного лимита. Публичная документация OpenAI Secure MCP Tunnel не должна интерпретироваться как гарантия отсутствия собственных будущих лимитов или тарифов OpenAI.

---

## 2. Принципы разработки

1. **Не переписывать рабочий RDC Relay целиком.**
2. **Сначала доказать transport отдельно от production-кода.**
3. Сохранить существующие supervisor/state-machine, health UI и visual states.
4. Provider-specific детали преобразовывать в **нормализованные события RDC**.
5. Не писать собственный execution engine, пока DesktopCommanderMCP удовлетворяет требованиям.
6. Не строить Google OAuth, собственный cloud broker и multi-device backend до появления реальной необходимости.
7. Секреты не хранить:
   - в command line;
   - в Git;
   - в plaintext config рядом с приложением.
8. Каждый новый provider должен иметь:
   - явный lifecycle;
   - health/readiness;
   - понятную recovery-модель;
   - version pin или проверяемый binary provenance;
   - tests.
9. Production `v1.5.12` не менять задним числом. Новая transport-архитектура — новая minor-линия.

---

## 3. Текущее состояние — DONE

### Phase 0 — Production baseline

Статус: **DONE**

- RDC Relay v1.5.12 опубликован.
- `main`, `stable`, tag `v1.5.12` зафиксированы.
- Updater/installer transactional.
- UI lifecycle больше не блокируется длительными stop/restart/logout/reconnect.
- Button rendering, Tab navigation и stale-window recovery исправлены.
- Release build содержит paint/lifecycle/transaction tests.
- Desktop Commander pin: `@wonderwhy-er/desktop-commander@0.2.52`.

Эта версия является rollback/reference point для дальнейшей архитектурной работы.

---

## 4. Следующий шаг — Spike 0

### Phase 0.5 — OpenAI Secure MCP Tunnel feasibility spike

Статус: **NEXT**

Production-код RDC Relay на этом этапе **не изменять**.

Подробный executable checklist находится в:

- `SPIKE_0_OPENAI_TUNNEL.md`

Нужно доказать end-to-end:

```text
ChatGPT
→ OpenAI Secure MCP Tunnel
→ tunnel-client
→ local DesktopCommanderMCP
→ STARMER
```

### Минимальные проверки

1. Для текущего OpenAI Platform account доступна страница Tunnels.
2. Можно создать/получить `tunnel_id`.
3. Runtime principal имеет:
   - Tunnels Read;
   - Tunnels Use.
4. Создан restricted runtime API key.
5. `tunnel-client doctor --explain` проходит.
6. `/healthz` отвечает.
7. `/readyz` переходит в ready.
8. ChatGPT видит tunnel как custom MCP connection/plugin.
9. ChatGPT видит tools Desktop Commander.
10. Работает безопасный read-only tool call.
11. Работает контролируемый write tool call во временную директорию.
12. После kill/restart `tunnel-client` соединение восстанавливается без повторной ручной настройки ChatGPT.

### Exit criteria

**GO**, если:

- ChatGPT реально вызывает tools локального DesktopCommanderMCP через tunnel;
- read/write проходят;
- reconnect устойчив;
- health surfaces достаточно информативны для supervisor;
- нет блокирующей account/workspace/permission проблемы.

**NO-GO / PAUSE**, если:

- Tunnel недоступен для текущего account/workspace;
- ChatGPT не может привязать tunnel;
- stdio DesktopCommanderMCP несовместим;
- reconnect требует постоянной ручной перепривязки;
- control-plane условия делают решение непрактичным.

При NO-GO production не ломать; вернуться к варианту zrok/другому transport spike.

---

## 5. Phase 1 — ConnectionProvider abstraction

Статус: **PLANNED, only after Spike 0 GO**

Предлагаемая feature branch:

```text
develop/1.6.0-providers
```

Цель: отделить Desktop Commander-specific lifecycle от общего supervisor без функциональных изменений.

Первый новый файл:

```text
Source/connection-providers.ps1
```

На этом этапе implementation только один:

```text
DesktopCommanderRemoteProvider
```

Требование: поведение 1.5.12 должно сохраниться 1:1.

### Deliverables

- provider contract;
- normalized RDC event model;
- `Parse-DesktopCommanderEvent`;
- `Apply-RdcEvent`;
- start/stop/restart/process discovery через provider;
- provider status/identity/capabilities;
- tests на event normalization и lifecycle parity.

### Exit criteria

- Desktop Commander Remote работает так же, как в 1.5.12.
- UI/supervisor больше не зависят напрямую от конкретных строк Desktop Commander там, где это можно отделить.
- Все existing release gates зелёные.

---

## 6. Phase 2 — OpenAITunnelProvider

Статус: **PLANNED**

После доказанного Spike 0:

```text
ConnectionProvider
├── DesktopCommanderRemoteProvider
└── OpenAITunnelProvider
```

OpenAI provider должен управлять:

- `tunnel-client` lifecycle;
- выбранным tunnel/profile;
- локальным DesktopCommanderMCP child process или stdio command;
- `/healthz`;
- `/readyz`;
- при необходимости `/health/mcp`;
- reconnect/recovery;
- redacted diagnostics.

### Не использовать human-readable log parsing как основной health source

Для OpenAI provider приоритет:

```text
health/readiness endpoints
→ structured process state
→ logs only for diagnostics
```

### Exit criteria

- provider стартует/останавливается из RDC Relay;
- supervisor видит starting/ready/offline/recovered;
- tool calls идут через tunnel;
- restart tunnel-client корректно отражается в UI;
- Desktop Commander Remote provider остаётся рабочим fallback.

---

## 7. Phase 3 — Provider UX

Статус: **PLANNED**

Минимальный UI:

```text
Connection
──────────────
● Desktop Commander Remote
○ OpenAI Secure Tunnel
```

Не добавлять `Auto` до накопления реальных failure/recovery данных.

Для каждого provider показывать:

- DisplayName;
- state;
- identity/account if applicable;
- transport readiness;
- executor readiness;
- actionable diagnostics;
- switch/restart controls.

Provider switch должен быть transactional:

1. stop old provider;
2. confirm stopped;
3. start selected provider;
4. confirm ready;
5. rollback/recover if start failed.

---

## 8. Phase 4 — Security and packaging

Статус: **PLANNED**

### Credentials

Runtime tunnel key:

- minimum permissions: Tunnels Read + Use;
- не передавать как literal CLI argument;
- не писать в repo;
- не писать в plaintext runtime profile.

Предпочтительно:

```text
DPAPI CurrentUser
or
Windows Credential Manager
```

RDC Relay config хранит только reference/metadata.

Admin API key для tunnel CRUD:

- не нужен long-running daemon;
- не должен храниться RDC Relay постоянно;
- использовать только для setup/admin operations при необходимости.

### Packaging

До включения sidecar binaries сделать единый source of truth для release payload.

Sidecars:

- version pin;
- source URL;
- SHA256;
- license;
- architecture;
- update policy.

Не обязательно сразу встраивать `tunnel-client.exe` внутрь Setup. На первом production prototype допустима отдельная проверяемая загрузка, если provenance и hash validation надёжны.

---

## 9. Phase 5 — zrok/OpenZiti provider

Статус: **LATER**

Цель: vendor-independent transport.

Возможная схема:

```text
Local MCP
  │
mcp-bridge
  │
zrok/OpenZiti
  │
mcp-tools
  │
MCP client
```

Использовать только после стабилизации provider abstraction и OpenAI path.

Не считать zrok прямой заменой OpenAI Tunnel для ChatGPT web без проверки client-side bridge requirements.

---

## 10. Phase 6 — Multi-device

Статус: **LATER**

### Сначала простой MVP

Отдельное соединение на каждую машину:

```text
RDC — STARMER
RDC — LAPTOP
RDC — OFFICE
```

Это позволяет проверить реальный multi-machine UX без собственного backend.

### Собственный broker только при доказанной необходимости

Будущая схема:

```text
ChatGPT
   │
   ▼
RDC MCP Broker
   │
   ├── STARMER
   ├── LAPTOP
   └── OFFICE
```

Только тогда понадобятся:

- device registry;
- ownership;
- pairing;
- revocation;
- routing;
- возможно Google/OIDC identity.

Google OAuth до этого этапа не нужен.

---

## 11. Что специально НЕ делаем сейчас

Не начинать одновременно:

- собственный MCP executor;
- Google OAuth;
- RDC cloud broker;
- database/device registry;
- zrok integration;
- OpenAI integration;
- большой C#/PowerShell rewrite.

Правильный порядок уменьшает количество независимых неизвестных.

---

## 12. Версионная стратегия

Предлагаемая линия:

```text
1.5.12
  └── production baseline

1.6.0-dev
  ├── provider abstraction
  ├── DesktopCommanderRemoteProvider
  └── OpenAITunnelProvider

1.6.x
  └── provider UX / security / packaging hardening

later
  ├── zrok provider
  └── multi-device / broker if justified
```

Spike 0 может выполняться вообще без изменения версии и production source.

---

## 13. Критерий абсолютного успеха

Минимальный стратегический успех:

```text
ChatGPT
   ↓
OpenAI Secure MCP Tunnel
   ↓
RDC Relay supervised tunnel-client
   ↓
local DesktopCommanderMCP
   ↓
STARMER
```

при этом:

- Desktop Commander Remote остаётся fallback;
- переключение provider контролируется RDC Relay;
- health/recovery отображаются в существующем UI;
- нет inbound ports;
- нет static IP;
- секреты защищены;
- local DesktopCommanderMCP остаётся replaceable execution engine;
- архитектура допускает zrok и другие transports без нового rewrite.

Если этот путь доказан и интегрирован, основная архитектурная цель 1.6 считается достигнутой.
