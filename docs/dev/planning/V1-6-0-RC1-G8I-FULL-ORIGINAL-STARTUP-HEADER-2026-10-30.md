# PROG-006A-G8I — Full original Remote startup header in RC1 Owner GUI

Date: 2026-10-30. Branch: `feature/v1.6-host-gui-owner-pilot`, existing Draft PR #23. No stable publish, installer execution or live Remote manipulation.

## Owner requirement

The G8H classic visual candidate restored only decorative banner art and an abbreviated synthetic connection summary. The original v1.5.18 main/upper console showed the **full** pinned Desktop Commander Remote 0.2.52 startup block: Unicode/box art, `Remote Connection`, local MCP and remote transport stages, session/presence/device readiness, User/Device ID/Device Name, connected status, and the original `Next` and `Commands` sections with complete help/logout terminal commands. The owner requires the exact original symbol styling and rich coloring.

## Implementation

- Compared installed v1.5.18 `%LOCALAPPDATA%/RemoteDesktopCommanderLauncher/remote-window.ps1` with the RC1 `Source/remote-window.ps1`. Reused the **same** original RichEdit `RdcLogBox`, `StyleStartupBanner`, compact Unicode line spacing, `Color-HeaderSemantics`, status/command token colors. The legacy and RC1 `Color-HeaderSemantics` rules were verified identical line for line. No new approximate renderer.
- Product `Source/RdcOwnerRuntime.cs` now captures `remoteStartupHeader` from **only the current Job-owned private Remote log** until the first tool-call boundary, with strict maximum of 90 scanned lines/54 visible lines/8192 characters. Per-line allowlist preserves exact safe symbol prefixes, ASCII/Unicode art, literal pinned Remote startup wording, user/device values already validated by bounded identity parser, Next/help/logout text; strips or normalizes the private filesystem path and endpoint from transport setup lines. Emoji UTF-16 surrogate pairs are explicitly supported, while malformed surrogate and control characters are rejected.
- Unrecognized lines, tool-call payloads, arbitrary stdout, secret values and private paths never enter the header. `Received tool call` permanently ends header capture; all later activity is processed solely by existing sanitized lower-pane journal logic. An explicit literal `remote --logout` is **only on-screen documentation from the original Remote**; the GUI/Host never executes it for process stop.
- Snapshot publishes the completed/partial original `remoteStartupHeader` only in `MANAGED_OWNER_RC1`. `Source/rc1-owner-gui.ps1` accepts only authenticated same-generation Host snapshot with bounded, non-control, non-tool-call header and sends that complete text to the unchanged `startupBlock` / original `Render-CompactLog`. Prior safe synthetic summary remains only as a fallback before the Remote supplies its header and for Adopted/read-only mode.
- No changes to the installed RC1, live Desktop Commander Remote, external installation channels or stable fallback.

## Evidence and validation

- The real Host-owned pinned Remote's current private startup log was read locally, shared read-only with the running process. **41 of 41** pre-tool-call startup lines were accepted by the new parser; all expected sections (`Remote Connection`, `Next`, `Commands`, both command references, account/device and connection stages) were present. **No raw identity values, paths or tool-call payloads were printed or committed.** The earliest tool-call line was not accepted.
- Dedicated isolated negative/positive C# parser test `Tests/Test-V16FullOriginalStartupHeader.ps1` includes emoji/box-art, real command syntax, malformed identity values, artificial tool-call payload, arbitrary fake command and other secret-text refusal. Original UI coloring pipeline is explicitly checked.
- Verification: **28/28** isolated regressions PASS exit 0, **35/35** focused full-header/negative/unchanged-1.5.18-colorizer checks PASS exit 0, standalone embedded Setup **18/18** PASS exit 0; full candidate builder exit 0 with 20 payload members.
- New STARMER Desktop: `RDC-Relay-1.6.0-RC1-Full-OriginalHeader-Setup.exe` SHA256 `859CF8B5C3719F6C2E006A4673A392CCF389FD110F93CC9A07E8F5E18B8E50E5`, Portable `RDC-Relay-1.6.0-RC1-Full-OriginalHeader-Portable.zip` SHA256 `6CA55563920859403E6D4C717F197EB0C18CE1C229659DCF26E55962DD2D93EF`. Prior `ClassicUI-Handoff` candidate moved, without deletion, to `Desktop/RemoteDesktopCommander/Old_Installers_2026-10-29/G8I_Superseded_ClassicUI`. Unmodified desktop v1.5.18 rollback installer SHA256 `D4AD27F8569037E05F9F5E901F192979B42F7182BA455CF45D78FB596B6D9190` reverified.
- The real live Owner Host/Remote were NOT stopped, upgraded, disconnected or reconnected. Full candidate Setup/Portable are built and staged only for owner-controlled update. No actual installed G8I visual verification.

## Remaining verification boundary

**NOT CHECKED:** owner-installed G8I visual screenshot of the *entire* RichTextBox header on actual Windows desktop; long-run graphic rendering with a newly spawned pinned Remote after update. Existing live RC1 access is intentionally preserved; owner should install G8I during a coordinated update window, retaining unchanged v1.5.18 fallback setup on Desktop.
