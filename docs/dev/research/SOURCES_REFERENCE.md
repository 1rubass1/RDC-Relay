> **LEGACY IMPORT, not current instructions.** Source: SOURCES.md from STARMER before Playbook migration (2026-10-22). This document preserves historical research or decisions, may contain superseded instructions/versions, and is not a production requirement by itself. Refer first to repository PROJECT_INDEX.md, PROJECT_CONTEXT.md, COORDINATION/BOARD.md and current planning. Sensitive IDs are redacted in the Git copy; byte-exact historical original is preserved only in STARMER local archive.
# RDC Relay — Sources and References

> **2026-10-20 plugin UI/source verification:** User screenshot contains
> `Новый плагин` archive upload and `Создать MCP-приложение` control.
> Official current documentation:
> - https://developers.openai.com/plugins/quickstart (custom MCP URL, auth, install)
> - https://developers.openai.com/plugins/build/plugins (archive manifest, mcp.json)
> - https://help.openai.com/en/articles/20001256-plugins-in-chatgpt (UI, plans, Sites alternative)
> - https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt (workspace permissions)
> - https://help.openai.com/en/articles/20001339-creating-and-using-chatgpt-sites (Plus/Pro Sites)
> - https://help.openai.com/en/articles/20001547-hosting-a-plugin-with-chatgpt-sites (Site-hosted MCP)
> - https://developers.openai.com/plugins/deploy/desktop-only (local desktop constraints)
> An independent public OpenAI-quickstart-example MCP was called from STARMER
> successfully. User account/plugin registration remains unverified; the
> screenshot alone is insufficient for a Plus GO decision. See
> `CHATGPT_PLUGIN_UI_REVIEW_2026-10-20.md`.


> **Added 2026-10-20:** Public HTTPS feasibility exercised with Pinggy
> temporary development tunnel (https://pinggy.io/docs/ and
> https://pinggy.io/docs/cli/) and official Cloudflare
> Quick Tunnel (https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)
> whose DNS SRV discovery failed on STARMER
> (https://developers.cloudflare.com/tunnel/troubleshooting/).
> ChatGPT plugin auth documentation
> https://developers.openai.com/plugins/build/auth specifies OAuth 2.1
> protected resource metadata, auth server discovery, PKCE S256, audience and
> scopes for sensitive/write tools. ChatGPT does not accept custom static API
> keys via generic client config. Public HTTPS connectivity with ping-only MCP
> succeeded, but ChatGPT user/plugin connection remains **unverified**.


> **Update 2026-10-20 — direct HTTPS transport Spike 1:**
> Official ChatGPT custom MCP setup accepts a public HTTPS MCP endpoint
> (https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt);
> the OpenAI plugin quickstart includes local Streamable HTTP testing and
> public HTTPS tunneling for developer tests
> (https://developers.openai.com/plugins/build/app-quickstart).
> OAuth resource/auth server requirements are documented at
> https://developers.openai.com/plugins/build/auth.
> MCP SDK v2 Streamable HTTP server and stdio client:
> https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/serving/http.md
> and https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/clients/connect.md.
> On STARMER, local HTTP and HTTP→stdio DesktopCommanderMCP tests passed; public
> HTTPS + ChatGPT plugin tests **not yet** verified. Details in
> `SPIKE_1_DIRECT_HTTPS_MCP.md`.


> Verified on 2026-10-07 unless stated otherwise.
>
> Purpose: give future agents a reproducible source list for the multi-provider / OpenAI Secure MCP Tunnel work.
>
> This file separates **external facts** from **project decisions**. If an external page changes, re-verify it before relying on the old conclusion.

---

# 1. RDC Relay project sources

## Repository

https://github.com/1rubass1/RDC-Relay

Use for:

- current source;
- branches/tags;
- README;
- changelog;
- release history.

## Current production release

https://github.com/1rubass1/RDC-Relay/releases/tag/v1.5.12

Baseline:

```text
version: v1.5.12
commit: 4e47cee861c077ddf050220a9dea5ed8d44d1b02
```

Do not rewrite this tag/release for provider development.

## Local repository

```text
E:\Projects\GitSync\RDC\RDC-Relay Work
```

Current production pin in `Source/remote-window.ps1`:

```text
@wonderwhy-er/desktop-commander@0.2.52
```

---

# 2. OpenAI Secure MCP Tunnel — official guide

## Secure MCP Tunnel guide

https://developers.openai.com/api/docs/guides/secure-mcp-tunnels

Authority: **OpenAI official documentation**

Supports these architectural assumptions:

- tunnel-client connects private/local MCP servers to ChatGPT;
- no inbound internet access is required on the tunnel-client host;
- outbound HTTPS to OpenAI is required;
- local MCP can be reached through stdio command or MCP server URL;
- ChatGPT custom MCP/plugin setup can select a Tunnel connection;
- tunnel-client exposes health/readiness surfaces;
- ChatGPT discovery/tool calls depend on tunnel-client remaining healthy.

Important current endpoints documented:

```text
/healthz
/readyz
/metrics
/ui
```

Current stdio setup documentation includes the concept:

```text
tunnel-client init
  --sample sample_mcp_stdio_local
  --profile ...
  --tunnel-id ...
  --mcp-command ...
```

Re-check exact CLI before implementation; do not rely on copied syntax forever.

---

# 3. OpenAI tunnel-client repository

## Repository

https://github.com/openai/tunnel-client

Authority: **OpenAI upstream source**

License at verification time:

```text
Apache License 2.0
```

Project description:

customer-run client for Secure MCP Tunnel, intended to connect private/localhost MCP servers to ChatGPT, Codex, Responses API and AgentKit without exposing them publicly.

Use this repository to verify:

- releases;
- Windows artifacts;
- CLI help;
- source behavior;
- license/NOTICE;
- issues;
- configuration changes.

Production packaging must pin a tested release; do not silently follow `latest`.

---

# 4. OpenAI tunnel permissions

## Permissions guide

https://github.com/openai/tunnel-client/blob/master/docs/permissions.md

Authority: **OpenAI upstream documentation**

Current permission model:

### Runtime daemon / ChatGPT tunnel user

```text
Tunnels Read
Tunnels Use
```

Permission atoms currently documented:

```text
api.organization.tunnel.read
api.organization.tunnel.write
api.organization.tunnel.use
```

### Tunnel CRUD operator

```text
Tunnels Read
Tunnels Manage
```

Use also required if the same principal runs/attaches to the tunnel.

### Runtime key

Documented as:

```text
CONTROL_PLANE_API_KEY
```

Recommended:

- Restricted;
- Tunnels Read + Use;
- not an admin key.

### Admin key

Documented as:

```text
OPENAI_ADMIN_KEY
```

Use only for administrative tunnel CRUD.

Project decision:

**RDC Relay MVP should not require an admin key.**
Create/configure the tunnel manually in OpenAI Platform first, then give RDC Relay an existing tunnel ID plus protected runtime credential.

---

# 5. OpenAI tunnel-client configuration

## Configuration guide

https://github.com/openai/tunnel-client/blob/master/docs/configuration.md

Authority: **OpenAI upstream documentation**

Use to verify:

- config/profile syntax;
- runtime profile locations;
- config precedence;
- secure secret references;
- `doctor`;
- sample profiles;
- local UI convention.

Notable commands/concepts currently documented:

```text
tunnel-client doctor --profile <name> --explain
tunnel-client profiles samples list
tunnel-client profiles samples show ...
tunnel-client runtimes list
tunnel-client runtimes status ...
```

Re-check exact commands during Spike 0.

---

# 6. OpenAI tunnel-client onboarding

## End-user guide

https://github.com/openai/tunnel-client/blob/master/docs/end-user-guide.md

## Onboarding guide

https://github.com/openai/tunnel-client/blob/master/docs/onboarding.md

Authority: **OpenAI upstream documentation**

Use for:

- where tunnel ID comes from;
- runtime key vs admin key;
- ChatGPT connector/plugin setup;
- permission troubleshooting;
- organization/workspace association.

Important distinction:

```text
CONTROL_PLANE_TUNNEL_ID
CONTROL_PLANE_API_KEY
OPENAI_ADMIN_KEY
```

These are not interchangeable.

---

# 7. OpenAI tunnel health

## Health documentation

https://github.com/openai/tunnel-client/blob/master/docs/health.md

Authority: **OpenAI upstream documentation**

Current routes:

```text
GET /healthz
GET /readyz
GET /metrics
GET /health
GET /health?details=true
GET /health/mcp
GET /health/{component}
```

Important semantic warning from upstream docs:

health observations are evidence at timestamps; reading health does not itself initialize MCP, list tools, start another child, or actively probe every dependency.

Design implication:

RDC Relay must not translate `healthz=200` into «all tools definitely reachable».

Keep separate:

```text
process liveness
readiness
MCP component state
last successful tool activity
```

---

# 8. OpenAI tunnel MCP plugin/runtime docs

## tunnel-mcp plugin README

https://github.com/openai/tunnel-client/blob/master/plugins/tunnel-mcp/README.md

Authority: **OpenAI upstream documentation**

Useful for secret handling and managed runtime state.

Current upstream documentation explicitly rejects literal API keys/tokens in plugin state/config generation and supports secret references such as environment/file references.

Design implication:

RDC Relay must store secrets separately from ordinary provider config.

---

# 9. Desktop Commander pricing / Remote limit

## Pricing

https://desktopcommander.app/pricing/

Authority: **Desktop Commander official site**

At verification time the Free Remote plan states:

```text
10,000 tool calls per month
```

The same page states that the **local MCP server is free and open source, with no account and no monthly limit**.

This is the central economic reason to investigate:

```text
ChatGPT
→ OpenAI Secure MCP Tunnel
→ local DesktopCommanderMCP
```

instead of routing every request through Desktop Commander Remote.

Important caveat:

This does **not** prove that OpenAI Secure MCP Tunnel has no limits/costs. Verify OpenAI terms/limits separately.

---

# 10. DesktopCommanderMCP upstream

## Repository

https://github.com/wonderwhy-er/DesktopCommanderMCP

Authority: **Desktop Commander local MCP upstream**

Package:

```text
@wonderwhy-er/desktop-commander
```

Current RDC Relay production pin:

```text
0.2.52
```

The upstream repository documents Desktop Commander as an MCP-compatible local server that can be started via npx and exposes terminal/filesystem/process/editing functionality.

Use for:

- local MCP CLI;
- package changes;
- issues;
- stdio compatibility;
- license;
- tool schema changes.

Do not switch RDC Relay from the tested pin to `latest` casually.

---

# 11. Desktop Commander Remote documentation

## Remote Device README

https://github.com/wonderwhy-er/DesktopCommanderMCP/blob/main/src/remote-device/README.md

Authority: **Desktop Commander upstream**

Documents the current hosted Remote path:

```text
AI client
→ Desktop Commander Remote MCP
→ Remote Device
→ local Desktop Commander MCP server
```

This is useful because it confirms the architectural separation already present upstream:

- hosted transport/control plane;
- local MCP execution.

RDC Relay 1.6 intends to preserve the local execution side while allowing another transport.

---

# 12. Desktop Commander hosted Remote repository

https://github.com/desktop-commander/remote-desktop-commander

Authority: **Desktop Commander official public Remote documentation repository**

At verification time it describes:

- hosted MCP endpoint;
- OAuth-based Remote service;
- local execution through Remote Device;
- hosted service implementation itself is not open source;
- local stdio server is the open-source DesktopCommanderMCP project.

Use this distinction when discussing licenses and architecture.

---

# 13. zrok / OpenZiti MCP Gateway

## Getting started

https://github.com/openziti/mcp-gateway/blob/main/docs/current/getting-started.md

Authority: **OpenZiti upstream**

Documents:

```text
mcp-bridge
mcp-tools
mcp-gateway
mcp-filesystem
```

and zrok private shares over OpenZiti.

Conceptual path:

```text
local stdio MCP
→ mcp-bridge
→ zrok private share
→ mcp-tools
→ MCP client
```

Use zrok as a **future vendor-independent provider candidate**, not as an assumption that web ChatGPT can consume a zrok share directly without client-side bridge considerations.

---

# 14. Source trust hierarchy

When sources disagree, prefer:

1. current official OpenAI/ Desktop Commander documentation;
2. current upstream repository documentation/source;
3. current release notes/issues;
4. project documents in this repository;
5. old chat summaries/planning notes.

Planning documents are decisions, not external truth.

---

# 15. Facts already verified for the current plan

As of 2026-10-07:

### Verified

- OpenAI Secure MCP Tunnel is a real supported product path.
- tunnel-client can target a local stdio MCP command.
- tunnel-client can target a local/private HTTP MCP endpoint.
- tunnel-client host uses outbound HTTPS; inbound public exposure is not required.
- health/readiness endpoints exist.
- ChatGPT supports Tunnel as a custom MCP/plugin connection path where account/workspace access permits it.
- runtime users need Tunnels Read + Use.
- tunnel-client is open source under Apache 2.0 at the time checked.
- Desktop Commander Free Remote currently advertises 10 000 tool calls/month.
- Desktop Commander local MCP is advertised as free/open source/no monthly limit.
- DesktopCommanderMCP can run as local stdio MCP.
- zrok/OpenZiti MCP Gateway provides stdio bridge components.

### Not yet verified on the user's account

- Tunnels feature visibility in the exact OpenAI Platform organization.
- exact ChatGPT workspace association.
- ability to create/select a tunnel with the user's current plan/roles.
- actual runtime key permissions on the user's account.
- Windows tunnel-client binary behavior on STARMER.
- DesktopCommanderMCP via tunnel-client stdio end-to-end.
- reconnect behavior under real failures.
- current OpenAI usage limits/cost policy for the tunnel in this account context.

These are Spike 0 tasks, not facts.

---

# 16. Security references to keep in mind

Do not paste real secrets into:

- ROADMAP.md;
- TECHNICAL_DESIGN.md;
- HANDOFF.md;
- GitHub issues;
- chat handoff files;
- command-line examples committed to Git.

Examples should always use:

```text
<CONTROL_PLANE_API_KEY>
<tunnel_id>
<workspace_id>
```

If a real key ever appears in a transcript or committed file, rotate it.

---

# 17. Re-verification checklist

Before starting implementation after a long pause, re-check:

- https://developers.openai.com/api/docs/guides/secure-mcp-tunnels
- https://github.com/openai/tunnel-client/releases
- tunnel-client permissions docs
- tunnel-client health docs
- Desktop Commander pricing
- DesktopCommanderMCP latest release/issues
- OpenZiti MCP Gateway docs if Phase 5 begins.

Record any breaking external change in `TECHNICAL_DESIGN.md` decision log or a new ADR.
