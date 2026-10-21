# RDC Relay — transport evidence matrix

> Reconciled from tests run October 7–20, 2026; **not a new test run**. Check source records before any significant new implementation.

| Route | State | Limits and evidence |
| --- | --- | --- |
| Existing v1.5.18 Remote | Production baseline | Previously published/tested; no new runtime test during docs migration |
| OpenAI Tunnel local stdio client | Partial PASS | [Spike 0](SPIKE_0_OPENAI_TUNNEL.md) |
| ChatGPT workspace → OpenAI Tunnel | **BLOCKED / NO-GO** | Workspace authorization/eligibility path not proven |
| Local Streamable HTTP ping MCP | **PASS** | Initialize/list/fixed response on loopback, [Spike 1](SPIKE_1_DIRECT_HTTPS_MCP.md) |
| Local HTTP → stdio DesktopCommanderMCP | **PASS** | Fixed fixture read only, not arbitrary command authorization |
| Temporary public HTTPS ping-only MCP | **PASS** | Ephemeral test tunnel subsequently stopped |
| Synthetic Bearer missing/wrong/correct secret | **PASS** | One test gate; NOT OAuth 2.1 |
| Cloudflare Quick Tunnel on STARMER | **FAIL** | DNS SRV discovery failed in tested environment |
| Owner-account ChatGPT custom MCP registration + invocation | **NOT CHECKED** | Visible UI button does not confirm permission, [research](CHATGPT_PLUGIN_UI_REVIEW.md) |
| Actual authenticated ChatGPT → STARMER executable tool | **NOT CHECKED / NO RELEASE GO** | OAuth, scoped tools, negative tests, isolation, revocation and independent review outstanding |

Documentation: [legacy sources](SOURCES_REFERENCE.md), [OpenAI Tunnel Spike 0](SPIKE_0_OPENAI_TUNNEL.md), [Direct HTTPS Spike 1](SPIKE_1_DIRECT_HTTPS_MCP.md), [ChatGPT UI study](CHATGPT_PLUGIN_UI_REVIEW.md).

**Boundary:** scripts/fixtures from STARMER `_experiments/direct-https-mcp` are not release-ready and were intentionally not copied into this repository. Full executor tools must never be published behind the experimental ingress.
