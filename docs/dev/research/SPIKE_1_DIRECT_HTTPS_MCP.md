> **LEGACY IMPORT, not current instructions.** Source: SPIKE_1_DIRECT_HTTPS_MCP.md from STARMER before Playbook migration (2026-10-22). This document preserves historical research or decisions, may contain superseded instructions/versions, and is not a production requirement by itself. Refer first to repository PROJECT_INDEX.md, PROJECT_CONTEXT.md, COORDINATION/BOARD.md and current planning. Sensitive IDs are redacted in the Git copy; byte-exact historical original is preserved only in STARMER local archive.
# RDC Relay — Spike 1: Direct HTTPS MCP (isolated feasibility)

> **2026-10-20 UI and platform availability addendum:** The owner has
> confirmed a visible `Создать MCP-приложение` button inside the `Новый
> плагин` dialog (also offers archive upload). This does **not** prove
> Plus custom MCP registration permission. Updated OpenAI docs describe
> a separate **ChatGPT Sites-hosted plugin** option available on eligible
> Plus/Pro accounts; it does not remove the need for a protected connection
> from the Site to private STARMER.
> An independent public demo MCP server passed initialize/list/call from
> STARMER. Neither the user's ChatGPT plugin nor Sites has been created.
> See `CHATGPT_PLUGIN_UI_REVIEW_2026-10-20.md`.


> Date: 2026-10-20
> Status: **PUBLIC HTTPS + BEARER-GATED TEST PASS / CHATGPT PLUGIN NOT TESTED / ALL PUBLIC TEST RUNTIMES STOPPED**
> Production RDC Relay and GitHub releases are out of scope. Do not expose any
> actual DesktopCommanderMCP tools through a public unauthenticated endpoint.

## Why

Spike 0 (OpenAI Secure MCP Tunnel) proved local stdio execution and a healthy
tunnel-client, but ChatGPT rejected the Tunnel connection before MCP initialize.
Investigate a direct public HTTPS endpoint instead, without changing the existing
RDC Relay supervisor while end-to-end transport is unproven.

Official ChatGPT custom MCP setup accepts a **public HTTPS MCP endpoint**.
A local 127.0.0.1 listener, even using MCP correctly, cannot be connected from
ChatGPT without an additional secure ingress/deployment layer.

## Experiment workspace

`E:\Projects\GitSync\RDC\_experiments\direct-https-mcp`

Outside the active production Git working tree:
`E:\Projects\GitSync\RDC\RDC-Relay Work`

Files:
- `server.mjs` — loopback-only Streamable HTTP ping MCP with fixed response;
- `test.mjs` — local health, Host/Origin rejection, initialize, list, call;
- `commander-bridge.mjs` — **local-only** HTTP-to-stdio adapter to pinned DesktopCommanderMCP;
- `test-bridge.mjs` — reads only `fixture.txt` through the real local MCP;
- `package.json` / `package-lock.json` — reproducible pinned SDK dependency tree;
- `README.md` — run instructions and explicit safety boundary.

Node version: `v24.20.0`; npm `11.19.0`.

Test-time dependencies pinned to exact versions:
- `@modelcontextprotocol/server@2.3.1`
- `@modelcontextprotocol/client@2.3.1`
- `@modelcontextprotocol/node@2.1.1`
- `zod@4.6.7`
- existing executor: `@wonderwhy-er/desktop-commander@0.2.52` (no `remote` argument).

## Verified on STARMER, 2026-10-20

### Probe-only server

Command: `npm test`

**PASS**, process exit code 0:
- loopback health GET;
- hostile Host and Origin headers rejected with 403;
- Streamable HTTP MCP initialize;
- tools/list contains only `rdc_spike_ping`;
- tools/call returns exact fixed string `RDC_DIRECT_MCP_SPIKE_OK`.

### Local DesktopCommanderMCP bridge

Command: `npm run test:bridge`

**PASS**, process exit code 0:
- HTTP MCP client initializes with local bridge;
- tools/list contains only `rdc_spike_fixed_read`;
- actual call traverses **HTTP → bridge → stdio DesktopCommanderMCP → read_file**;
- response contains fixture `RDC_BRIDGE_FIXTURE_OK`.
- No arbitrary file path or executor tool is available through the bridge MCP API.

These tests prove local protocol compatibility, **not public HTTPS**, actual
ChatGPT tool discovery, auth, reconnect, reliability or unattended operation.

## Confirmed safety boundary

- Servers bind to `127.0.0.1` only.
- Only harmless fixed-string ping and local fixed-fixture bridge are exposed.
- No public tunnel / proxy / DNS / certificates / firewall / OAuth changes.
- No API keys or provider credentials used or recorded.
- No RDC production code, installer, remote process, config, release or Git tag changed.
- Tests start isolated processes and stop them on completion.

The generic local bridge is **not safe for internet deployment as-is**, even
though the current exposed bridge operation is fixed-path, because the child MCP
has broad device privileges. A real public gateway must have a full threat model.

## Next gates (not yet performed)

1. Design dedicated public HTTPS ingress with TLS validation and outbound-only
   STARMER connectivity if practical; document provider cost/limits/terms.
2. Design authentication **before** exposing local MCP; study OAuth protected
   resource metadata, authorization server, audience/resource binding, scopes,
   token validation/rotation, revocation, and acceptable UX with ChatGPT.
3. Verify authenticated public endpoint with a **ping-only** MCP tool and
   ChatGPT custom-MCP plugin registration / tool discovery / real call.
4. Add negative tests: missing/expired token, hostile Origin/Host, rate-limits,
   wrong audience, rejected tool, disconnect, process crash, and reconnect.
5. Separately prove least-privilege bridge to DesktopCommanderMCP. Real tool
   surface should start read-only/sandboxed with manual approval for writes and
   arbitrary shell; isolate process, path access and outbound network.
6. Only then decide GO / NO-GO and whether to begin
   `develop/1.6.0-providers`.

## GO criteria

- ChatGPT can discover and invoke one authenticated read-only tool on STARMER
  via PUBLIC HTTPS.
- Authorization is verified; unauthorized requests are rejected.
- Read and one controlled write/read-back/cleanup test works against a dedicated
  sandbox through the locally pinned MCP, after user approval.
- Fault/reconnect behavior is acceptable; logs do not contain secrets.
- Both installed RDC Relay production and original Desktop Commander Remote
  continue functioning unchanged.

Decision as of this run: **LOCAL GO, end-to-end decision PENDING**.

## Sources checked

- https://developers.openai.com/plugins/build/app-quickstart
- https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt
- https://developers.openai.com/plugins/build/auth
- https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/serving/http.md
- https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/clients/connect.md

---

# External HTTPS transport test — 2026-10-20

## Security scope: probe only

The public experiment is **NOT** the original local HTTP-to-stdio bridge.
Only `public-ping.mjs` is reachable over the internet. Its one tool
`rdc_spike_public_ping` returns only `RDC_HTTPS_PUBLIC_TEST_OK`; it has
no filesystem, terminal, config or real DesktopCommanderMCP access.

Public ping uses an unpredictable 224-bit random path capability under
`/gate/<capability>/mcp`; it is **not OAuth**. For testing an explicit
auth check, `/protected/<capability>/mcp` additionally requires an
independent 256-bit random Bearer token. This models bearer enforcement
but is NOT ChatGPT-compatible OAuth setup. Keys/capabilities are not
written to Git or the project documentation.

Both surfaces are bound on STARMER to `127.0.0.1:49155`, with exact
public Host allowlist, default-deny routes, same-origin check, no-store
responses, limited request sizes and a basic rate limit. Port 49155 was
NOT opened in Windows Firewall.

## Cloudflare Quick Tunnel — infrastructure NO-GO on this machine

Official `cloudflared-windows-amd64.exe`, version **2026.10.1**,
downloaded from the Cloudflare GitHub release directly into
`_experiments/direct-https-mcp/tools/`.

Binary SHA256 (matches GitHub published asset digest):
`4d2490e74082c5d48dbfedaf92576fa5bd1702379ab88eb7faa0cfbe8dc891b6`
Windows Authenticode: `Valid`.

A Quick Tunnel URL was allocated but edge discovery failed:
`lookup argotunnel.com: no such host` when resolving the Cloudflare
`_v2-origintunneld._tcp.argotunnel.com` SRV record. STARMER DNS SRV
queries returned no record with its default resolver AND explicit
`1.1.1.1`; the remote URL returned Cloudflare HTTP **530**, not an
origin response. Ordinary DNS A lookup of the regional edge succeeded
and TCP connectivity to port 7844 succeeded. No DNS or firewall
settings were changed. This does NOT disprove HTTPS MCP feasibility.

## Pinggy alternative — public HTTPS transport PASS

An isolated Pinggy v0.6.1 Node CLI development tunnel was established
using outbound connectivity to the free provider. TLS was provided
at Pinggy's HTTPS edge; the local forwarding endpoint remained loopback.
The ephemeral public host was:
`ovutc-204-62-120-30.free.pinggy.net`
(with unguessable path capability NOT recorded here).

Pinggy reports the free tunnel expires after **60 minutes**, then the
random hostname must be recreated. Free visitors using regular browsers
may see a one-time Pinggy warning page. Standard non-browser MCP SDK
requests worked during testing.

Test script:
`_experiments/direct-https-mcp/test-public-https.ps1`

**PASS**, exit code 0:
- default TLS certificate validation from STARMER via public Pinggy HTTPS;
- public secret-path health endpoint returned HTTP 200;
- unknown route returned 404 (default deny);
- public Streamable HTTP MCP initialize succeeded;
- `tools/list` returned exactly `rdc_spike_public_ping`;
- `tools/call` returned exact constant `RDC_HTTPS_PUBLIC_TEST_OK`;
- synthetic protected endpoint rejected missing/invalid Bearer with HTTP 401;
- correct Bearer enabled the same harmless MCP initialize/list/call.

TinyFish's independent cloud GET reached Pinggy's free-tunnel
**browser warning**, proving the external hostname was reachable;
this external browser-like GET did not reach origin. This is separate
from the successful real HTTPS MCP client requests above.

## ChatGPT plugin end-to-end — NOT YET TESTED

The available browser automation profile is NOT signed in to
`chatgpt.com`; available ChatGPT Plugin Management actions cannot
create a custom MCP server/plugin connection. No actual ChatGPT
registration, tool discovery or tool call was made. Account/workspace
eligibility is also unverified (OpenAI Help Center notes plan- and
workspace-specific restrictions).

The `/gate/<capability>/mcp` endpoint may be used **only for harmless
plugin discovery/ping testing** if the user has the "Add custom MCP
server" control. It is a short-lived URL; recreate the tunnel for
subsequent testing. It is never a substitute for production OAuth.

Real permissions and personal tools require:
- durable named HTTPS ingress and provider policies;
- OAuth 2.1 auth server + MCP protected-resource metadata;
- PKCE S256, token issuer/audience/scope validation and rotation;
- restrictive executor bridging and user confirmations for writes;
- negative auth/replay/rate/recovery tests and an actual ChatGPT call.

## Decision

- Local MCP protocol: **PASS**
- Public HTTPS ingress: **PASS** (Pinggy temporary development tunnel)
- Explicit Bearer gate, invalid/valid bearer: **PASS** (test-only)
- Authenticated ChatGPT MCP plugin: **NOT VERIFIED**
- Public real DesktopCommanderMCP tools: **NOT EXPOSED**
- RDC Relay ConnectionProvider refactor: **NOT AUTHORIZED BY GO gate**

Temporary runtime files are under
`%LOCALAPPDATA%\RDCRelay\spike-public-https`.
The full public capability URL is only in the temporary local runtime
metadata and the specific chat response. Stop the Pinggy experiment
before exposing any real device data.

## Shutdown / secret cleanup (completed 2026-10-20)

The experimental tunnel was **stopped immediately after testing**:
- Pinggy tunnel `8e2adee3-d68`: stopped;
- Pinggy helper daemon started by this experiment: stopped;
- isolated `public-ping.mjs` Node process: stopped;
- temporary runtime `session.json` (capability + Bearer) and
  `allowed-host.txt`: deleted;
- process audit: `SPIKE_PROCESSES_REMAINING=0`;
- `127.0.0.1:49155` listening sockets: `0`.

The formerly generated public HTTPS URL is **no longer valid** and should
not be reused for ChatGPT registration. Public transport was proven with
a generic MCP client only, not through the ChatGPT plugin UI.

Current ChatGPT Help Center states that full custom MCP server connections
are available for Business and Enterprise/Edu, with a limited Pro read/fetch
exception; Plus is not listed as enabled. Account UI eligibility has not
been confirmed and the available web automation browser profile is not
logged into the user's ChatGPT account. Therefore the actual ChatGPT
connection attempt remains blocked/unverified, NOT PASS.
