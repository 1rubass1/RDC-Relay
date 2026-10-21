> **LEGACY IMPORT, not current instructions.** Source: CHATGPT_PLUGIN_UI_REVIEW_2026-10-20.md from STARMER before Playbook migration (2026-10-22). This document preserves historical research or decisions, may contain superseded instructions/versions, and is not a production requirement by itself. Refer first to repository PROJECT_INDEX.md, PROJECT_CONTEXT.md, COORDINATION/BOARD.md and current planning. Sensitive IDs are redacted in the Git copy; byte-exact historical original is preserved only in STARMER local archive.
# RDC Relay — ChatGPT Plugins UI capability review (2026-10-20)

Status: **research and independent protocol checks complete; user-account connection remains unverified.** No production code modified.

## Observed user UI

The screenshot shared by the project owner on 2026-10-20 shows:

- Dialog title: "Новый плагин" (New plugin).
- Upload surface supports `.tar.gz`, `.tgz`, `.zip`.
- Bottom-left button: **"Создать MCP-приложение"** (Create MCP app).
- "Добавить плагин" (Add plugin) is disabled while no archive is selected.

This is evidence that both a package-upload UI and an MCP-app-creation entry point
are visible. **It does not prove** this exact ChatGPT Plus account can register
an external custom HTTPS MCP server, or that any MCP tool is discoverable or callable.
We should not infer permission from a button alone.

## Different paths in the updated OpenAI product

### 1) Plugin archive upload

The upload surface takes a **plugin package archive**, not a standalone
`server.mjs` or arbitrary HTTP URL. Current portable package guidance uses
a root `plugin.json` and optional `mcp.json` / `skills/` / assets.
Bundled remote servers in `mcp.json` require a stable HTTPS URL and
connection setup; packaging does not host a local server or bypass authentication.
A plugin can also consist only of skills (no MCP tools).

Package instructions:
https://developers.openai.com/plugins/build/plugins

Plugin Help Center:
https://help.openai.com/en/articles/20001256-plugins-in-chatgpt

### 2) "Создать MCP-приложение" / custom MCP server

The official current flow is Plugins → Add (+) → Add custom MCP server
→ name + HTTPS MCP endpoint OR supported Tunnel → auth → risk confirmation
→ Create as plugin → install → new ChatGPT Work conversation and invoke.

A server can expose tool-only MCP; optional MCP Apps HTML/UI is **not required**.

Quickstart:
https://developers.openai.com/plugins/quickstart

MCP + optional UI:
https://developers.openai.com/plugins/build/app-quickstart

Official test server (owned by independent example provider, no RDC secrets):
https://tinymcp.dev/api/moldy-aloof-zettabyte/mcp
(Only provides public read-only `roll_dice` tool.)

**Plan nuance:** the current custom MCP help page lists Business and
Enterprise/Edu workspace creation rights, with admin/owner/RBAC policies.
The screenshot is from Plus and confirms UI visibility, not completed
permission checks. We must test the creation form and server registration in
the owner's actual session before declaring Plus GO or NO-GO.

Current custom MCP help:
https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt

### 3) ChatGPT Sites (possible Plus workaround, not proven for RDC)

Updated help says ChatGPT Sites is available for **Plus and Pro**, and a
Site can host its **own** MCP server and create a plugin. A Site-hosted MCP
plugin is supported on any ChatGPT plan that provides the required Sites
and plugin creation permissions. The Site owner needs to publish the Site.

However, Sites hosting **does not itself give private access to STARMER**.
To call a private STARMER executor, a secure external API/transport must be
set up, or an eligible workspace private tunnel must be available. Sites
private service tunnels are on a separate availability/permissions track.
Thus this is an option to investigate, **not a solved replacement**.

Sites creation:
https://help.openai.com/en/articles/20001339-creating-and-using-chatgpt-sites

Sites-hosted plugin:
https://help.openai.com/en/articles/20001547-hosting-a-plugin-with-chatgpt-sites

### 4) Desktop-local MCP plugin (not general remote access)

The current plugin guide also mentions local MCP apps in ChatGPT Desktop.
That requires local desktop execution on the user's machine and does not
make those tools usable from ChatGPT web or mobile. Public desktop-only
plugin submission has restricted partner eligibility; do not treat
packaging a local stdio process as equivalent to STARMER remote access.

Desktop-only:
https://developers.openai.com/plugins/deploy/desktop-only

## Independent protocol check performed on STARMER

Read-only test program, stored outside the Git checkout:

`_experiments/direct-https-mcp/test-official-public-example.mjs`

Connected through public HTTPS to the current OpenAI quickstart sample
`https://tinymcp.dev/api/moldy-aloof-zettabyte/mcp` using the already-pinned
official MCP SDK client:

- MCP initialize: PASS.
- tools/list: `roll_dice`: PASS.
- `tools/call` with `sides=6`: PASS (one ordinary dice result).
- Node process finished with exit code 0.
- No STARMER files or remote tools exposed.

Together with prior Spike 1 results:
- Loopback HTTP → local stdio DesktopCommanderMCP, harmless fixed fixture: PASS.
- Public HTTPS → temporary ping-only endpoint, authenticate synthetic Bearer: PASS.
- Public HTTPS → independent MCP sample server: PASS.
- ChatGPT plugin → custom endpoint → STARMER: **NOT TESTED**.

## Security / release rules

1. **Do not restore the previous ephemeral tunnel URI:** Pinggy tunnel and
   server were stopped; random capability/Bearer session files were deleted.
2. For any future public probing, expose **only an inert fixed-string read
   tool**. Never publish `commander-bridge.mjs` / DesktopCommanderMCP.
3. A transient bearer token test is not a production OAuth provider. Personal
   file/shell tools require OAuth 2.1 or another officially supported strong
   authorization model, least-privilege execution and audit trails.
4. Wait for user review before creating persistent ChatGPT plugins, Sites,
   account-scoped apps, subscriptions, or provider-side public resources.
5. No changes to the installed production `v1.5.16`, active Remote,
   `main`, `stable`, GitHub tags or firewall.

## Exact continuation when user is back

1. Open **"Создать MCP-приложение"**, inspect whether the actual form allows
   `Connection = Public HTTPS` and offers authentication settings, without
   approving or publishing anything yet.
2. If creation is allowed, bring up a **fresh** inert test server over a
   temporary HTTPS tunnel and test tool discovery / one call from ChatGPT.
   Old expired Pinggy URL MUST NOT be reused.
3. If the account blocks creation, test a minimal Site-hosted ping plugin
   from ChatGPT Work only if Sites access exists; record both permissions and
   whether Sites can reach a separate safe STARMER transport.
4. Only after a real ChatGPT → STARMER tool call succeeds should architecture
   choice be revisited. Production 1.6 provider work remains paused.

Prepared without using the owner's ChatGPT account or changing app settings.
