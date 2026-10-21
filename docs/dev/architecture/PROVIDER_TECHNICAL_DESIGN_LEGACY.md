> **LEGACY IMPORT, not current instructions.** Source: TECHNICAL_DESIGN.md from STARMER before Playbook migration (2026-10-22). This document preserves historical research or decisions, may contain superseded instructions/versions, and is not a production requirement by itself. Refer first to repository PROJECT_INDEX.md, PROJECT_CONTEXT.md, COORDINATION/BOARD.md and current planning. Sensitive IDs are redacted in the Git copy; byte-exact historical original is preserved only in STARMER local archive.
# RDC Relay — Technical Design

> Архитектурный документ для линии 1.6.x.
>
> Baseline: RDC Relay v1.5.12.
>
> Repository: `E:\Projects\GitSync\RDC\RDC-Relay Work`.
>
> Этот документ описывает **планируемую** архитектуру. Всё, что относится к OpenAI Secure MCP Tunnel, должно считаться design target до успешного завершения `SPIKE_0_OPENAI_TUNNEL.md`.

---

# 1. System context

## 1.1 Что такое RDC Relay сегодня

RDC Relay 1.5.12 — Windows GUI/supervisor вокруг:

```text
npx --yes @wonderwhy-er/desktop-commander@0.2.52 remote
```

RDC Relay:

- запускает Remote Device;
- скрывает консоль;
- читает `remote-session.log`;
- интерпретирует lifecycle/tool events;
- показывает connection/health state;
- управляет stop/restart/logout/account switch;
- восстанавливает Remote после transport/local MCP failures;
- визуализирует activity/recovery/fault через существующий UI.

RDC Relay **не является MCP client** и сам не вызывает MCP tools.

Текущий request path:

```text
ChatGPT
   │
   ▼
Desktop Commander Remote MCP service
   │
   ▼
Desktop Commander Remote Device
   │
   ▼
local DesktopCommanderMCP
   │
   ▼
STARMER
```

---

# 2. Problem statement

Текущий supervisor и UI полезны, но transport жёстко связан с Desktop Commander Remote.

Нужно:

1. сохранить зрелый local MCP execution engine;
2. сохранить supervisor/state machine;
3. позволить выбирать разные connection transports;
4. не дублировать UI/health logic для каждого transport;
5. использовать structured health там, где он доступен;
6. обеспечить безопасное хранение transport credentials.

Первый альтернативный transport — OpenAI Secure MCP Tunnel.

---

# 3. Target architecture

```text
┌──────────────────────────── RDC Relay UI ─────────────────────────────┐
│                                                                      │
│  Provider selector / actions / status / logs / activity indication   │
│                              │                                       │
│                              ▼                                       │
│                    Supervisor / State Machine                        │
│                              │                                       │
│                              ▼                                       │
│                       Normalized RDC Events                          │
│                              │                                       │
│                              ▼                                       │
│                     ConnectionProvider layer                         │
│                 ┌────────────┴────────────┐                          │
│                 ▼                         ▼                          │
│  DesktopCommanderRemoteProvider   OpenAITunnelProvider               │
│                 │                         │                          │
└─────────────────┼─────────────────────────┼──────────────────────────┘
                  │                         │
                  │                         ▼
                  │                   tunnel-client
                  │                         │ stdio
                  │                         ▼
                  └──────────────────► DesktopCommanderMCP
                                            │
                                            ▼
                                      machine resources
```

Позже:

```text
ConnectionProvider
├── DesktopCommanderRemoteProvider
├── OpenAITunnelProvider
└── ZrokProvider
```

---

# 4. Architectural rules

## 4.1 UI не знает transport internals

UI не должен проверять:

- конкретные строки `Channel subscribed`;
- конкретные OpenAI readiness JSON fields;
- конкретные zrok process messages.

UI получает только normalized state/events.

## 4.2 Supervisor не вызывает MCP tools

Supervisor управляет connection lifecycle и interprets events.

Execution остаётся внутри MCP engine.

## 4.3 Provider отвечает за transport-specific truth

Provider знает:

- process layout;
- auth model;
- log/health surfaces;
- identity;
- reconnect semantics;
- capabilities.

## 4.4 Event normalization — единственный мост к общему supervisor

Provider-specific parser/adapter преобразует факты в `RdcEvent`.

---

# 5. Proposed source layout

Минимальный рефакторинг:

```text
Source/
├── remote-window.ps1
├── connection-providers.ps1
├── update.ps1
├── version.txt
└── ...
```

После стабилизации, если файл станет слишком большим:

```text
Source/
├── remote-window.ps1
├── providers/
│   ├── provider-core.ps1
│   ├── desktop-commander-remote.ps1
│   └── openai-tunnel.ps1
└── components/
    ├── openai/
    └── mcp/
```

На первом refactor лучше **не дробить всё сразу**. Один `connection-providers.ps1` снижает риск.

---

# 6. Provider model

Рекомендуемая внутренняя модель:

```powershell
ProviderState = [pscustomobject]@{
    Id             = 'desktop-commander-remote'
    DisplayName    = 'Desktop Commander Remote'
    Kind           = 'remote'
    Process        = $null
    Identity       = $null
    Capabilities   = @{}
    Health         = $null
    Ready          = $false
    StartedAt      = $null
    LastEventAt    = $null
    Diagnostics    = @{}
}
```

Для OpenAI:

```powershell
ProviderState = [pscustomobject]@{
    Id             = 'openai-tunnel'
    DisplayName    = 'OpenAI Secure Tunnel'
    Kind           = 'tunnel'
    Process        = $null
    Identity       = $tunnelId
    Capabilities   = @{
        StructuredHealth = $true
        ToolEvents       = 'partial'
        AccountSwitch    = $false
    }
    Health         = $null
    Ready          = $false
}
```

---

# 7. Provider contract

Минимальный API:

```text
Get-ProviderDefinition
Start-Provider
Stop-Provider
Restart-Provider
Find-ProviderProcess
Get-ProviderStatus
Get-ProviderIdentity
Get-ProviderCapabilities
Get-ProviderDiagnostics
Read-ProviderEvents
```

Provider не должен напрямую обновлять WinForms controls.

## 7.1 Start-Provider

Input:

- provider state;
- provider config;
- cancellation/lifecycle context.

Output:

- process/session descriptor;
- initial normalized events.

Не должен блокировать UI thread.

## 7.2 Stop-Provider

Требования:

- graceful stop first;
- bounded timeout;
- forced termination only when required;
- process tree cleanup;
- normalized `provider.stopped` or failure event.

## 7.3 Restart-Provider

Не просто `Stop; Start` без контроля.

State transition:

```text
ready
→ stopping
→ stopped
→ starting
→ connecting
→ ready
```

Failure должен оставлять понятный recoverable state.

---

# 8. Normalized event model

Предлагаемый envelope:

```powershell
$event = [pscustomobject]@{
    Type        = 'provider.ready'
    ProviderId  = 'openai-tunnel'
    Timestamp   = [DateTimeOffset]::UtcNow
    Severity    = 'info'
    Message     = 'Tunnel is ready.'
    ToolCallId  = $null
    Data        = @{}
    Raw         = $null
}
```

`Raw`:

- можно хранить для diagnostics;
- не использовать как UI state source;
- secrets/redacted fields не помещать туда без очистки.

---

# 9. Event taxonomy

## Provider lifecycle

```text
provider.starting
provider.auth-required
provider.connecting
provider.ready
provider.stopping
provider.stopped
provider.failed
```

## Transport

```text
transport.offline
transport.degraded
transport.recovered
```

## Executor

```text
executor.starting
executor.ready
executor.offline
executor.recovered
executor.failed
```

## Tool activity

```text
tool.started
tool.succeeded
tool.failed
```

## Identity/configuration

```text
identity.changed
device.changed
provider.configuration-required
provider.configuration-changed
```

## Diagnostics

```text
provider.warning
provider.info
provider.metric
```

---

# 10. Apply-RdcEvent

Общий supervisor должен постепенно перейти от:

```text
raw line
→ special-case parsing
→ immediate UI mutation
```

к:

```text
provider-specific observation
→ normalized RdcEvent
→ Apply-RdcEvent
→ supervisor state
→ UI render
```

`Apply-RdcEvent` отвечает за:

- ready/fault latch;
- recovery;
- tool activity;
- state transitions;
- user-facing status;
- activity indicator;
- log semantics.

Это позволит переиспользовать уже отлаженную health/UI логику.

---

# 11. DesktopCommanderRemoteProvider

## 11.1 Current command

Production pin:

```text
@wonderwhy-er/desktop-commander@0.2.52
```

Current launch path:

```text
npx --yes @wonderwhy-er/desktop-commander@0.2.52 remote
```

## 11.2 Observation source

Основной source остаётся:

```text
remote-session.log
```

Но `Process-RemoteLine` должен постепенно стать provider parser:

```text
Parse-DesktopCommanderEvent
```

а provider-specific health parsing не должен жить в UI layer.

## 11.3 Important existing distinctions

Нужно сохранить:

- startup;
- authentication;
- connecting;
- ready;
- transport lost;
- remote unreachable;
- local MCP lost;
- tool timeout;
- tool failure;
- automatic reconnect;
- recovery.

Уже исправленная защита от ложного parsing serialized tool payload как lifecycle events должна сохраниться.

## 11.4 Provider capabilities

Пример:

```powershell
@{
    AccountSwitch      = $true
    DeviceDashboard    = $true
    StructuredHealth   = $false
    ToolEvents         = $true
    LocalExecutor      = 'DesktopCommanderMCP'
}
```

---

# 12. OpenAITunnelProvider

## 12.1 Intended request path

```text
ChatGPT custom MCP/plugin
   │
   ▼
OpenAI Secure MCP Tunnel control/data plane
   │
   ▼
tunnel-client on STARMER
   │
   ▼ stdio
DesktopCommanderMCP
```

No inbound port or static public endpoint is required by tunnel-client; it needs outbound HTTPS to OpenAI plus local access to its MCP command/server.

## 12.2 MCP mode

Preferred first implementation:

```text
stdio
```

Conceptual command/profile:

```text
tunnel-client
    profile: rdc-openai
    tunnel_id: tunnel_...
    mcp-command:
        npx --yes @wonderwhy-er/desktop-commander@0.2.52
```

Do not hard-code this exact CLI until Spike 0 confirms the installed tunnel-client syntax.

## 12.3 Health

Primary sources:

```text
GET /healthz
GET /readyz
GET /health/mcp
GET /metrics
```

Interpretation:

- `/healthz`: process liveness;
- `/readyz`: readiness gate;
- `/health/mcp`: observed MCP component state;
- `/metrics`: diagnostics/telemetry, not primary state machine.

Important: health observations may be timestamped historical evidence, not an active network probe. Supervisor logic must not overstate guarantees.

## 12.4 Event mapping

Example:

```text
tunnel-client process created
→ provider.starting

/healthz 200, /readyz 503
→ provider.connecting

/readyz 200
→ provider.ready

process alive, readiness lost
→ transport.degraded or executor.offline depending on health detail

readiness restored
→ transport.recovered / executor.recovered
→ provider.ready
```

Exact mapping уточняется после Spike 0.

---

# 13. Tool activity under OpenAI Tunnel

Desktop Commander Remote provider даёт удобные tool lifecycle lines.

OpenAI Tunnel может не давать тот же уровень human-readable tool telemetry.

Поэтому capability:

```text
ToolEvents = full | partial | none
```

UI не должен требовать `tool.started` для подтверждения provider readiness.

Если tunnel-client metrics/health дают только aggregate activity:

- сохранить activity indication на доступном уровне;
- не подделывать fake tool names;
- UI может показывать generic `MCP activity`.

---

# 14. Credentials and security

## 14.1 Runtime key

OpenAI runtime principal:

```text
Tunnels Read
Tunnels Use
```

Runtime API key используется `tunnel-client run/doctor`.

## 14.2 Admin key

Admin key нужен только для CRUD tunnel metadata, если RDC Relay вообще возьмёт это на себя.

Правило:

```text
OPENAI_ADMIN_KEY
≠ long-running runtime credential
```

MVP лучше строить так, чтобы tunnel создавался в OpenAI Platform UI вручную, а RDC Relay управлял уже существующим `tunnel_id`.

Это резко уменьшает privilege surface.

## 14.3 Secret storage

Запрещено:

```text
tunnel-client --api-key sk-...
```

Запрещено:

```json
{
  "apiKey": "sk-..."
}
```

в обычном plaintext config.

Предпочтительно:

```text
DPAPI CurrentUser
```

или Windows Credential Manager.

Metadata config:

```json
{
  "provider": "openai-tunnel",
  "tunnelId": "tunnel_...",
  "credentialRef": "rdc-relay/openai/runtime"
}
```

Runtime secret передавать через:

- environment variable;
- supported secure reference;
- stdin/config reference;

в зависимости от подтверждённых возможностей tunnel-client.

## 14.4 Log redaction

Никогда не логировать:

- API keys;
- bearer tokens;
- cookies;
- full Authorization headers;
- credential store plaintext.

Diagnostics export должен быть redacted.

---

# 15. Configuration model

Предлагаемый config:

```json
{
  "schemaVersion": 1,
  "selectedProvider": "desktop-commander-remote",
  "providers": {
    "desktop-commander-remote": {
      "package": "@wonderwhy-er/desktop-commander@0.2.52"
    },
    "openai-tunnel": {
      "profile": "rdc-openai",
      "tunnelId": "tunnel_...",
      "credentialRef": "rdc-relay/openai/runtime",
      "healthUrl": "http://127.0.0.1:<dynamic-or-configured-port>"
    }
  }
}
```

Не включать secrets.

---

# 16. Provider switching

Switch должен быть explicit и recoverable.

```text
current provider ready
   │
user selects another provider
   ▼
disable provider switch UI
   ▼
stop current provider
   ▼
verify stopped
   ▼
start target provider
   ▼
wait bounded readiness
   ├── ready → persist selected provider
   └── failed → show fault / offer rollback
```

Нельзя:

- одновременно запускать два provider, если они конфликтуют за один local executor;
- менять persisted selection до успешного start нового provider;
- блокировать UI thread.

---

# 17. Process ownership

Каждый provider должен иметь чёткую ownership-модель.

Provider state должен знать:

- root process PID;
- child process policy;
- process start time;
- command fingerprint;
- whether process was started by RDC Relay;
- health endpoint ownership.

Stop не должен прибивать посторонний процесс, только потому что имя совпало.

Использовать:

- exact command/path fingerprint;
- process tree relationship;
- provider-specific mutex/state file при необходимости.

---

# 18. Failure model

## 18.1 Provider unavailable before start

Пример:

- tunnel-client binary missing;
- Node/npx missing;
- config invalid.

Event:

```text
provider.configuration-required
or
provider.failed
```

## 18.2 Transport loss

Provider process жив, connection потеряна.

```text
transport.offline
```

UI:

- persistent fault indication;
- auto-recovery if provider supports it;
- no false ready until readiness restored.

## 18.3 Executor loss

Tunnel жив, MCP child умер.

```text
executor.offline
```

Provider may restart child or whole runtime depending on tunnel-client behavior.

## 18.4 Stale process

Existing process has no usable window/health and still owns lifecycle lock.

Reuse v1.5.12 philosophy:

- detect stale owner;
- recycle only owned process;
- recover automatically.

## 18.5 Repeated crash

Use bounded backoff.

Do not create infinite tight restart loop.

Possible sequence:

```text
1 s
2 s
5 s
10 s
30 s cap
```

Exact values only after real observations.

---

# 19. Health semantics

Нельзя смешивать:

```text
process alive
transport connected
executor ready
tool call success
```

Это разные facts.

Recommended model:

```text
ProcessAlive
TransportReady
ExecutorReady
ProviderReady
LastSuccessfulActivity
FaultLatched
```

`ProviderReady` должен быть вычисляемым, а не просто одним bool из случайной строки.

---

# 20. UI state mapping

Current main states можно сохранить:

```text
starting
auth-required
connecting
ready
fault
recovering
stopped
```

Provider-specific detail идёт во вторичную строку.

Пример:

```text
RDC Relay — Работает
OpenAI Tunnel подключён; local MCP готов.
```

или:

```text
RDC Relay — Проблема связи
Tunnel process жив, но MCP readiness потеряна.
```

---

# 21. Provider selector UX

MVP:

```text
Connection
──────────────
● Desktop Commander Remote
○ OpenAI Secure Tunnel
```

Показывать unavailable provider disabled с объяснением, если:

- binary missing;
- config missing;
- credential missing;
- tunnel not configured.

Не скрывать provider молча.

---

# 22. OpenAI setup UX — recommended MVP

RDC Relay 1.6 MVP не должен создавать OpenAI organization roles или admin keys.

Setup flow:

1. пользователь создаёт tunnel в OpenAI Platform;
2. связывает его с нужным ChatGPT workspace;
3. создаёт restricted runtime key;
4. RDC Relay принимает:
   - tunnel ID;
   - runtime key;
5. runtime key сразу уходит в protected storage;
6. UI хранит только masked identity/reference;
7. RDC Relay запускает doctor;
8. показывает actionable result.

Позже можно автоматизировать CRUD, если это действительно нужно.

---

# 23. Local MCP engine

Первый engine:

```text
DesktopCommanderMCP
```

Production 1.5.12 pin:

```text
@wonderwhy-er/desktop-commander@0.2.52
```

Почему переиспользуем:

- filesystem;
- terminal;
- process sessions;
- search;
- editing;
- mature MCP implementation.

Execution engine abstraction **не вводить заранее**, если provider layer решает текущую задачу.

Future:

```text
DesktopCommanderMCP
→ RDC Agent
```

должно быть возможно без изменения transport/UI architecture.

---

# 24. Packaging

Сейчас payload существует в нескольких местах:

- build;
- installer;
- manifest/self-test.

До sidecars желательно сделать release payload metadata единым source of truth.

Concept:

```json
{
  "components": [
    {
      "name": "tunnel-client",
      "version": "...",
      "arch": "windows-amd64",
      "sha256": "...",
      "source": "https://github.com/openai/tunnel-client/...",
      "license": "Apache-2.0"
    }
  ]
}
```

Installer/build/self-test должны читать одно описание, а не иметь три независимых списка.

---

# 25. tunnel-client distribution policy

Для Spike 0:

- использовать официальный latest public release/download path;
- записать точную tested version/hash в результаты spike.

Для production:

- выбрать конкретную tested version;
- pin version;
- verify SHA256;
- проверить license/NOTICE obligations;
- обновлять только через explicit release work.

Не запускать production на `latest` без контроля.

---

# 26. zrok provider

zrok/OpenZiti рассматривается как второй transport.

Потенциальная схема:

```text
DesktopCommanderMCP
   │
mcp-bridge
   │
zrok private share
   │
mcp-tools
   │
MCP client
```

OpenZiti MCP Gateway предоставляет готовые компоненты `mcp-bridge` и `mcp-tools`.

Но для ChatGPT web важен вопрос, где будет жить client-side bridge. Поэтому zrok не внедрять раньше доказанного OpenAI path, если OpenAI path работает.

---

# 27. Multi-device

До broker:

- отдельный tunnel/connection на устройство;
- отдельное имя plugin/connection;
- проверить UX.

Broker вводить только если станет болезненно управлять несколькими независимыми connections.

Future tool model:

```text
list_devices()

execute_command(
    deviceId = "starmer"
)
```

Это уже другой архитектурный слой и не должен смешиваться с provider refactor.

---

# 28. Testing strategy

## Unit/contract tests

- normalized event parsing;
- provider status mapping;
- provider config validation;
- secret redaction;
- provider selection persistence.

## Process tests

- start;
- ready;
- stop;
- restart;
- child crash;
- transport loss;
- stale process;
- repeated reconnect.

## Integration tests

Desktop Commander Remote:

- preserve 1.5.12 behavior.

OpenAI:

- doctor;
- healthz;
- readyz;
- ChatGPT discovery;
- read tool;
- write tool;
- restart.

## Release gates

Будущий build должен требовать:

- PowerShell parser clean;
- provider contract tests;
- existing GUI logic tests;
- button paint tests;
- UI lifecycle tests;
- installer/updater transaction tests;
- manifest/hash validation.

GPU visual validation по-прежнему отдельно от software fallback logic pass.

---

# 29. Migration strategy

## Step 1

Extract provider definitions, не меняя behavior.

## Step 2

`Process-RemoteLine` постепенно разделить:

```text
Parse-DesktopCommanderEvent
Apply-RdcEvent
```

## Step 3

Все existing Desktop Commander actions routed through provider API.

## Step 4

Add OpenAI provider behind feature/experimental selection.

## Step 5

Only after field testing make provider choice persistent/default-capable.

---

# 30. Backward compatibility

Existing user of 1.5.12 должен после upgrade получить:

```text
selectedProvider = desktop-commander-remote
```

без обязательной OpenAI setup.

OpenAI provider должен быть opt-in.

Никакая новая credential requirement не должна блокировать existing Desktop Commander path.

---

# 31. Observability

Provider diagnostics screen/log должен иметь:

- provider ID;
- provider version;
- process PID/start time;
- health URL;
- tunnel ID masked/partial;
- readiness;
- last state transition;
- last recovery;
- executor state;
- last tool activity if available.

Не показывать secret.

---

# 32. Metrics worth recording

Для OpenAI spike/integration:

- startup → healthz time;
- startup → readyz time;
- first tool discovery latency;
- tool call latency;
- reconnect duration;
- number of reconnect attempts;
- child MCP restart count;
- provider process crashes.

Эти данные помогут решить, нужен ли `Auto` provider selection later.

---

# 33. Non-goals for 1.6.0

Не входят:

- собственный cloud relay;
- собственный account system;
- Google OAuth;
- device registry DB;
- custom MCP executor;
- automatic provider failover;
- zrok production support;
- mobile client;
- remote desktop streaming.

---

# 34. Decision log

## D-001

**Decision:** use `ConnectionProvider`, не low-level `CommanderBackend`.

**Reason:** RDC Relay supervises connection lifecycle, а не вызывает tools.

## D-002

**Decision:** OpenAI Secure MCP Tunnel — first alternative transport candidate.

**Reason:** official path for private/local MCP to ChatGPT with outbound-only host connection and structured health surfaces.

## D-003

**Decision:** reuse DesktopCommanderMCP initially.

**Reason:** separate transport risk from execution-engine risk.

## D-004

**Decision:** Spike 0 before provider refactor.

**Reason:** account/workspace/permission feasibility must be proven before architecture work.

## D-005

**Decision:** Desktop Commander Remote remains fallback.

**Reason:** do not regress existing working production path.

## D-006

**Decision:** no Google/broker before real multi-device requirement.

**Reason:** avoid premature backend/control-plane complexity.

## D-007

**Decision:** runtime secrets use least privilege and protected storage.

**Reason:** long-lived transport key becomes RDC Relay responsibility.

---

# 35. Open technical questions

Resolve during Spike 0 / early 1.6:

1. Is OpenAI Tunnel visible for the current Platform organization and ChatGPT workspace?
2. What exact tunnel-client Windows binary/version is tested?
3. Does stdio child management behave well with DesktopCommanderMCP?
4. Which health endpoint best distinguishes transport loss from executor loss?
5. Are per-tool lifecycle events observable without log scraping?
6. How quickly does reconnect converge?
7. Does ChatGPT retain the plugin/tunnel configuration after client restart?
8. What exact profile files does tunnel-client persist and where?
9. What is the cleanest DPAPI/Credential Manager integration for PowerShell 5.1?
10. Should tunnel-client binary ship with Setup or be downloaded after install?
11. Do current OpenAI tunnel terms/limits introduce a material usage ceiling?
12. Is separate tunnel per machine acceptable for the first multi-device experience?

---

# 36. Definition of done for 1.6.0

1. Desktop Commander Remote provider matches 1.5.12 behavior.
2. OpenAI Tunnel provider can be configured safely.
3. ChatGPT can discover Desktop Commander tools through it.
4. Read/write tools execute locally on STARMER.
5. Provider health is visible in RDC Relay.
6. Transport/executor failure is distinguishable.
7. Restart/reconnect is automatic and bounded.
8. Switching provider does not freeze UI.
9. Secrets are not present in command line or repo.
10. Installer/updater remain transactional.
11. All release gates pass.
12. Existing users can stay on Desktop Commander Remote without new setup.

That is the target architecture for the first successful multi-provider RDC Relay release.
