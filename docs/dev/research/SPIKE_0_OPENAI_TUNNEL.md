> **LEGACY IMPORT, not current instructions.** Source: SPIKE_0_OPENAI_TUNNEL.md from STARMER before Playbook migration (2026-10-22). This document preserves historical research or decisions, may contain superseded instructions/versions, and is not a production requirement by itself. Refer first to repository PROJECT_INDEX.md, PROJECT_CONTEXT.md, COORDINATION/BOARD.md and current planning. Sensitive IDs are redacted in the Git copy; byte-exact historical original is preserved only in STARMER local archive.
# RDC Relay — Spike 0: OpenAI Secure MCP Tunnel

> Status: **NOT STARTED**
>
> Purpose: prove or reject the OpenAI Secure MCP Tunnel path **before** modifying RDC Relay production architecture.
>
> Production source must remain unchanged during this spike unless the user explicitly authorizes a separate experimental branch/change.

---

# 1. Goal

Prove this exact end-to-end path:

```text
ChatGPT
   │
   ▼
OpenAI Secure MCP Tunnel
   │
   ▼
tunnel-client on STARMER
   │
   ▼ stdio
@wonderwhy-er/desktop-commander@0.2.52
   │
   ▼
STARMER local resources
```

If successful, the transport feasibility for `OpenAITunnelProvider` is proven.

---

# 2. Why this spike comes first

A provider refactor is not useful if the target transport is unavailable for the user's exact:

- OpenAI Platform organization;
- ChatGPT workspace;
- roles/permissions;
- account configuration.

Therefore:

```text
prove transport first
→ refactor second
```

Do not edit `Source/remote-window.ps1` to support OpenAI until this checklist reaches GO.

---

# 3. Safety boundaries

During Spike 0:

- do not modify published `v1.5.12`;
- do not move production tags;
- do not replace installed RDC Relay unless explicitly required;
- do not log API keys;
- do not commit API keys;
- do not pass literal key in a committed command example;
- use a dedicated spike profile/state directory where possible;
- write test files only under a dedicated temporary directory;
- do not execute destructive filesystem/shell tests.

Recommended temporary root:

```text
%LOCALAPPDATA%\RDCRelay\spike-openai-tunnel
```

Recommended write-test root:

```text
%TEMP%\RDCRelay-Tunnel-Spike
```

---

# 4. Inputs needed from the user/account

Potential manual OpenAI UI steps may require the user.

Needed values:

```text
tunnel_id
runtime API key
target ChatGPT workspace
```

Do not paste the runtime key into this file.

If an agent needs the key for a process:

- obtain it only through an approved secret/input path;
- keep it out of command-line history where possible;
- do not print it back.

---

# 5. Step A — Confirm feature availability

Open:

```text
https://platform.openai.com/settings/organization/tunnels
```

Record:

```text
[ ] Tunnels page available
[ ] User can view tunnels
[ ] User can create or reuse a tunnel
[ ] Target ChatGPT workspace can be associated
```

If feature is absent:

```text
STOP
Result = NO-GO / account capability
```

Do not refactor RDC Relay around an unavailable feature.

---

# 6. Step B — Confirm permissions

Current OpenAI upstream docs say runtime use requires:

```text
Tunnels Read
Tunnels Use
```

Check role/group assignment.

Record:

```text
[ ] Read available
[ ] Use available
[ ] role assignment propagated
```

OpenAI docs warn role changes may take time to propagate.

If permission errors occur, record exact HTTP/error text without credentials.

---

# 7. Step C — Create/reuse tunnel

Preferred MVP:

- create tunnel manually in Platform UI;
- associate correct workspace;
- avoid using an admin key from RDC Relay.

Record only:

```text
Tunnel ID: <masked-or-nonsecret-id>
Tunnel display name:
Workspace:
Created/reused:
```

Do not record admin key.

---

# 8. Step D — Create runtime key

Create a Restricted runtime API key.

Permissions:

```text
Tunnels Read
Tunnels Use
```

Do not choose broad permissions unless required for troubleshooting.

Record:

```text
[ ] runtime key created
[ ] key NOT written to repo
[ ] key NOT written to this document
```

The key should ultimately be stored via protected Windows storage in production.

Spike may use a temporary environment/session secret handling mechanism.

---

# 9. Step E — Obtain tunnel-client

Official upstream:

```text
https://github.com/openai/tunnel-client
```

Official guide recommends Platform download link or latest public release.

For the spike:

1. download official Windows artifact;
2. record exact version;
3. compute SHA256;
4. record source URL.

Record:

```text
Version:
File:
SHA256:
Source URL:
Architecture:
```

Do not commit the binary yet unless explicitly desired.

Production policy will be decided later.

---

# 10. Step F — Inspect binary/help before running

Run safe informational commands first.

Examples to verify against current binary:

```text
tunnel-client --help
tunnel-client help quickstart
tunnel-client profiles samples list
```

Do not assume old documentation syntax if binary help differs.

Record:

```text
[ ] binary launches
[ ] expected MCP stdio option exists
[ ] profile command exists
[ ] doctor command exists
[ ] health/UI option exists
```

---

# 11. Step G — Create isolated tunnel-client profile

Recommended profile name:

```text
rdc-spike
```

Concept only; exact syntax must come from current binary:

```text
tunnel-client init
  --sample sample_mcp_stdio_local
  --profile rdc-spike
  --tunnel-id <TUNNEL_ID>
  --mcp-command "<LOCAL_MCP_COMMAND>"
```

Local MCP command target:

```text
npx --yes @wonderwhy-er/desktop-commander@0.2.52
```

Do **not** include `remote`.

Why:

```text
remote
= Desktop Commander hosted Remote Device

no remote argument
= local stdio DesktopCommanderMCP
```

This distinction is essential.

---

# 12. Step H — Doctor

Run:

```text
tunnel-client doctor --profile rdc-spike --explain
```

or current equivalent.

Record:

```text
Doctor exit code:
Tunnel metadata:
Workspace visible:
Credential permission result:
Local MCP command validation:
Warnings:
Errors:
```

Redact secrets.

### Pass

Doctor confirms control plane + profile are usable.

### Fail

Do not proceed blindly. Categorize:

```text
permission
workspace association
credential
binary/config
local MCP command
network
unknown
```

---

# 13. Step I — Start tunnel-client

Start in a way that logs diagnostics without secrets.

Record:

```text
PID:
Started at:
Health listen address:
UI URL:
Profile:
```

Do not integrate with RDC Relay yet.

---

# 14. Step J — Health/readiness

Check:

```text
GET /healthz
GET /readyz
GET /health/mcp
```

If available:

```text
GET /health?details=true
GET /metrics
```

Record:

```text
healthz status:
readyz status:
mcp health:
time to healthz:
time to readyz:
```

### Expected conceptual result

```text
process starts
→ healthz 200
→ readiness initially gated if needed
→ local MCP starts
→ readyz 200
```

Do not assume exact ordering before observing it.

---

# 15. Step K — Confirm local DesktopCommanderMCP child

Verify:

- child process exists if tunnel-client spawns it;
- package/version is correct;
- no `remote` mode is accidentally running;
- stdio connection is active;
- child is owned by the spike runtime.

Record:

```text
[ ] local MCP started
[ ] correct package pin
[ ] no hosted Desktop Commander Remote involved in this test path
[ ] health reports MCP component
```

---

# 16. Step L — ChatGPT connection

In ChatGPT:

1. open Plugins / custom MCP setup;
2. add custom MCP server/plugin;
3. choose:
   ```text
   Connection: Tunnel
   ```
4. select/paste the configured tunnel;
5. review permissions/risk warning;
6. create/enable connection.

Record:

```text
[ ] tunnel appears
[ ] plugin creation succeeds
[ ] tool discovery succeeds
[ ] Desktop Commander tool names visible
```

If tunnel does not appear:

- verify workspace association;
- verify Read + Use;
- verify tunnel-client remains running;
- rerun doctor.

---

# 17. Step M — Read-only tool test

Choose a safe read-only Desktop Commander tool.

Examples:

- get/read current hostname/environment;
- list a dedicated temp directory;
- read an explicitly created harmless text file.

Do not use private user data for the first proof.

Record:

```text
Tool:
Arguments:
Result:
Latency:
RDC/tunnel health during call:
```

### Pass condition

ChatGPT receives a correct result from STARMER through the tunnel.

---

# 18. Step N — Controlled write test

Create test root:

```text
%TEMP%\RDCRelay-Tunnel-Spike
```

Allowed write:

```text
create one test text file
write known harmless text
read it back
delete only the spike test file/directory
```

Example content:

```text
RDC Relay OpenAI Tunnel Spike OK
```

Record:

```text
[ ] create succeeded
[ ] read-back matched
[ ] cleanup succeeded
```

This proves write-capable MCP calls, not just discovery.

---

# 19. Step O — Tool activity observability

During read/write calls inspect:

- tunnel-client logs;
- `/metrics`;
- `/health/mcp`;
- local process state.

Question:

Can RDC Relay observe:

```text
tool.started
tool.succeeded
tool.failed
```

or only generic traffic/aggregate health?

Record exactly what is observable.

This determines:

```text
OpenAITunnelProvider.Capabilities.ToolEvents
```

---

# 20. Step P — Reconnect test 1: restart tunnel-client

Procedure:

1. ensure ChatGPT connection works;
2. stop tunnel-client;
3. observe ChatGPT failure behavior;
4. restart same profile;
5. wait for `/readyz`;
6. invoke read-only tool again.

Record:

```text
offline detected after:
restart started:
healthz restored after:
readyz restored after:
ChatGPT tool usable after:
manual ChatGPT reconfiguration required: yes/no
```

### Critical pass condition

No need to recreate the entire ChatGPT plugin/connection after ordinary runtime restart.

---

# 21. Step Q — Reconnect test 2: local MCP child failure

If safe and tunnel-client child ownership is understood:

1. identify only the spike local MCP child;
2. terminate that child;
3. do not terminate unrelated Desktop Commander processes;
4. observe:
   - health;
   - readiness;
   - auto child restart if any;
   - ChatGPT call behavior.

Record:

```text
child failure detected:
readyz change:
auto restart:
time to recover:
manual action:
```

This is necessary to distinguish:

```text
transport failure
vs
executor failure
```

---

# 22. Step R — Network interruption test

Optional after basic success.

Simulate bounded loss if it can be done without disrupting other important work.

Prefer a targeted process/network test over disabling the whole machine network.

Observe:

- polling error;
- readiness;
- retry/backoff;
- recovery.

Record timings.

Do not destabilize STARMER unnecessarily.

---

# 23. Step S — Stop/cleanup

At the end:

- stop spike tunnel-client;
- stop its local MCP child if still running;
- delete spike temp test files;
- keep diagnostic results;
- do not delete user tunnel unless the user wants it removed;
- do not remove runtime key without user decision.

Do not accidentally stop production RDC Relay / Desktop Commander Remote.

---

# 24. Metrics table

Fill during spike:

| Metric | Value |
| --- | --- |
| tunnel-client version | |
| tunnel-client SHA256 | |
| healthz ready time | |
| readyz ready time | |
| ChatGPT tool discovery time | |
| first read tool latency | |
| first write tool latency | |
| restart → readyz | |
| restart → ChatGPT usable | |
| MCP child restart time | |
| manual reconnect required | |

---

# 25. Capability result

Fill after experiment:

```text
StructuredHealth:
  yes / no

McpComponentHealth:
  yes / no

ToolEvents:
  full / partial / none

AutomaticTunnelReconnect:
  yes / no

AutomaticMcpChildRecovery:
  yes / no

ChatGPTConfigSurvivesRestart:
  yes / no

ReadTools:
  pass / fail

WriteTools:
  pass / fail
```

---

# 26. GO / NO-GO decision

## GO

Choose GO only if all core conditions are satisfied:

```text
[ ] tunnel usable by this account/workspace
[ ] tunnel-client healthy on STARMER
[ ] local DesktopCommanderMCP starts through stdio
[ ] ChatGPT discovers tools
[ ] read call succeeds
[ ] write call succeeds
[ ] reconnect is operationally acceptable
[ ] no blocker in secret handling
```

Then proceed to:

```text
ROADMAP.md
Phase 1 — ConnectionProvider abstraction
```

Suggested branch:

```text
develop/1.6.0-providers
```

## NO-GO

Choose NO-GO if a fundamental blocker remains.

Record blocker category:

```text
account/workspace
permissions
ChatGPT connector support
tunnel-client Windows issue
DesktopCommanderMCP incompatibility
reconnect unacceptable
security problem
cost/limit problem
other
```

Then evaluate zrok/other transport spike without contaminating production code.

---

# 27. Results section

Fill this section during execution.

## Date

```text
Not started
```

## Operator / agent

```text
Not started
```

## tunnel-client

```text
Version:
SHA256:
Source:
```

## Tunnel

```text
Tunnel ID:
Workspace:
Runtime role:
```

Do not put API key here.

## Doctor

```text
Not run
```

## Health

```text
healthz:
readyz:
health/mcp:
```

## ChatGPT discovery

```text
Not run
```

## Read test

```text
Not run
```

## Write test

```text
Not run
```

## Reconnect test

```text
Not run
```

## Observability

```text
Not run
```

## Decision

```text
NOT STARTED
```

## Notes

```text
None yet.
```


---

# Spike 0 execution result — 2026-10-07

## Result

**STATUS: BLOCKED / NO-GO FOR PRODUCTION INTEGRATION YET**

The local and tunnel runtime path was successfully proven, but ChatGPT rejected the tunnel before any real MCP traffic reached STARMER.

## Proven working

- Official `openai/tunnel-client v0.0.16` Windows amd64 artifact downloaded and SHA256-verified.
- STARMER is AMD64 / 64-bit Windows.
- Node v24.20.0 and `npx.cmd` are available.
- Pinned local executor `@wonderwhy-er/desktop-commander@0.2.52` works as stdio MCP.
- Local MCP `initialize`, `tools/list`, and a real `read_file` succeeded outside Desktop Commander Remote.
- OpenAI Platform Tunnels are available in the user's Personal Platform organization.
- Owner role includes `Tunnels: Read, Manage, Use`.
- Restricted runtime API key with tunnel runtime permissions is accepted by `tunnel-client`.
- `doctor --explain` returns `RESULT ok`.
- Runtime health endpoints return `/healthz = 200` and `/readyz = 200`.
- `DesktopCommanderMCP 0.2.52` starts as the stdio child.
- Tunnel metadata fetch and control-plane polling succeed.

## Organization-backed tunnel

Created:

```text
RDC Relay - STARMER
[REDACTED-tunnel-id]
```

Associated with the Personal Platform organization and the available ChatGPT workspace.

ChatGPT custom MCP validation failed with:

```text
Сервер MCP отказал в доступе.
Проверьте настройки аутентификации,
а если используете туннель — его доступ к рабочей области.
```

At the same time, `/health/mcp` remained:

```text
state = not_observed
initialize_epoch = 0
```

Therefore the rejected request never reached the local MCP child.

## Workspace-only control experiment

A second tunnel was created with the organization deselected and only the ChatGPT workspace selected:

```text
RDC Relay - STARMER WS
[REDACTED-tunnel-id]
```

Its `doctor`, metadata fetch, control-plane polling, stdio child startup, `/healthz`, and `/readyz` all succeeded.

ChatGPT nevertheless returned the same access-denied validation before sending MCP traffic.

## Upstream evidence

OpenAI `tunnel-client` issue #60 remains open as of 2026-10-07:

```text
ChatGPT Pro MCP calls fail with 401 [REDACTED-tunnel-id]
despite selected Platform org
```

Reported symptoms include a healthy/ready tunnel, correct organization/workspace association, and rejection before the private MCP server sees the call.

`tunnel-client v0.0.16` was published 2026-10-06. Its release notes cover MCP timing, optional trace-context forwarding and dependency updates; they do not list a fix for this personal-workspace organization-context failure.

## Decision

Do **not** start the RDC Relay provider refactor against OpenAI Tunnel yet.

The transport/client/local-MCP design remains promising and technically compatible, but production implementation should wait until one of these is true:

1. OpenAI fixes the personal ChatGPT workspace active-organization/tunnel access path;
2. an eligible ChatGPT workspace type is available that demonstrably passes the same test;
3. OpenAI documents another supported configuration that reaches MCP `initialize` from this account.

The strongest success criterion for retry is:

```text
ChatGPT custom MCP creation/discovery succeeds
→ /health/mcp records initialize
→ tools/list is observed
→ one read tool succeeds
→ one controlled write/read-back/cleanup succeeds
```

Production RDC Relay v1.5.12 was not modified during this spike.
