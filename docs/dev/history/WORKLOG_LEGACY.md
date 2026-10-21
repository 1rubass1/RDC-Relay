> **LEGACY IMPORT, not current instructions.** Source: WORKLOG.md from STARMER before Playbook migration (2026-10-22). This document preserves historical research or decisions, may contain superseded instructions/versions, and is not a production requirement by itself. Refer first to repository PROJECT_INDEX.md, PROJECT_CONTEXT.md, COORDINATION/BOARD.md and current planning. Sensitive IDs are redacted in the Git copy; byte-exact historical original is preserved only in STARMER local archive.
# RDC Relay — Active Work Log

## 2026-10-21 — Pen visual fidelity refinement: native arrows, scrollbars, footer

- User noted misaligned arrows and missing scrollbar arrowheads; asked for careful native-pixel inspection without closing Pen.
- Compared **full-resolution 1074×900 / 96-DPI native captures** (`rdc-expanded-footer.png`) to Pen's 1:1 export using magnified nearest-neighbor crops and direct pixel scans; these are not source screenshots downscaled for saving resources.
- Read original RDC Relay C# UI geometry: `RdcOverlayScrollBar` has 17px thickness, 16px arrow end zones, 8×5/5×8 gray triangles, and `RdcScrollCorner` paints three diagonal 1.4px amber strokes. Native footer `RdcUpdateNoticeStrip` position derives from the right anchored hint, bullet, version, arrow and 84×21 update button.
- Fixed all **six** scrollbar arrows (main ↓/↑, activity ↓/↑, horizontal ←/→), resized activity vertical orange thumb to match observed y789–820 at x1058, adjusted horizontal thumb x/y and width, added three diagonal resize-corner strokes, and corrected the account dropdown chevron into a small filled triangle (actual native x~836 y68).
- Moved footer update arrow left and vertically into alignment with native static final stage. Corrected one-line note, body/footer/header fill, native purple separator y722/y728, action/button gold, track/thumb colors from source. Pen frame remains 1074×900, **95 individually editable named nodes**, no shader animations.
- Exported / visually reviewed `E:\Projects\GitSync\RDC\Design\RDC-Relay-Layout-Preview.png`; **restored minimized Pen** to save Ctrl+S, and verified physical `E:\Projects\GitSync\RDC\Design\RDC-Relay-UI-Layout.pen` file updated (41,823 bytes; 2026-10-21 08:31:48 local). Pen left open as requested.
- Added `E:\Projects\GitSync\RDC\Design\README.md` with measured pixel coordinate reference, color tokens, and source arrow geometry.
- NO RDC Relay production process restarted or edited; git checkout remains clean. Typography and dynamic logs deliberately not exact; geometry and icon/scrollbar details received priority.

---

## 2026-10-21 — Native pen.dev design reference for RDC Relay UI (read-only source)

- User asked to recreate RDC Relay desktop layout in pen.dev with **editable coordinates**, static final update-notice animation state, and no functional animations.
- Connected to running Pen desktop v1.2.18 on STARMER using its already-enabled `pencil` Codex CLI MCP server (`mcp-server-windows-x64.exe --app desktop --agent codexCLI`) via a local stdio bridge; used documented `get_app_state`, `read_skill` and `execute` operations.
- Captured actual installed RDC Relay v1.5.18 UI on STARMER at **1074×900**, 96 DPI, plus isolated `-Preview` with the **fully expanded** update button. Preview process was closed, production connection not restarted.
- Created fully editable native Pen frame **1074×900 / 86 named layers**: title bar, header/status, account/help/stop buttons, dark logs, static separators and scrollbars, expanded footer with current version, arrow, and update button. Preserved distinctive pixel-art banner as a single isolated graphic layer. Dynamic logs and account identification are **representative placeholders**, not live credentials. Font renderer differs from native Windows Segoe UI; strict screenshot-level text anti-aliasing match is not guaranteed.
- Pen design saved through the application's **Save As** workflow: `E:\Projects\GitSync\RDC\Design\RDC-Relay-UI-Layout.pen`. Supporting `rdc-banner.png` and `RDC-Relay-Layout-Preview.png` are adjacent. The .pen is open in the Pen designer; selecting grouped buttons allows manual x/y adjustments. The design was exported to PNG and visually inspected.
- Local input screenshots and temporary scripts: `E:\Projects\GitSync\RDC\_experiments\pen-relay-design`. These are reference/utility artifacts, not application changes.
- This is a **static design reference only**; no RDC Relay runtime source, installed payload, Git branches or releases were changed.

---

## 2026-10-20 — RELEASED v1.5.18: update-click fix and verified live notice refresh

- User explicitly approved release v1.5.18 and requested a pre-release check that an already visible v1.5.17 button updates to a newer release.
- **Confirmed existing feature:** `Update-RdcUpdateNoticePolling` polls the current `stable` branch and manifest approximately hourly. `Show-RdcUpdateNotice` updates `OfferedVersion` when the available version changes; identical versions do not restart animation, and current/older versions hide the notice.
- Added isolated `Tests/Test-UpdateNoticeVersionRefresh.ps1` with fake offline GitHub commit/manifest tasks: 1.5.17 → 1.5.18 changes the button without reopening; same 1.5.18 does not replay; local version 1.5.16 hides the notice; commit SHA pins manifest. **PASS**. Added real WinForms notice control transition to GUI self-test and registered the offline test in `Scripts/build-release.ps1`.
- Prior fix in `bb01e89`: update button click explicitly launches updater even when started with `-SkipUpdate`; `Tests/Test-UpdateNoticeClick.ps1` **PASS**.
- Full 1.5.18 release build **PASS** (GUI logic, full paint, lifecycle, click and version-refresh regression, transactional installer/updater); extracted Portable **PASS**; GPU offscreen test skipped due software fallback.
- Pushed commit `5b1fdf58a8873d6cd781b0a835f8e208eb46dbfb` to **main** and **stable**, created annotated tag `v1.5.18`, published GitHub latest release: https://github.com/1rubass1/RDC-Relay/releases/tag/v1.5.18.
- Published assets verified through GitHub API: `RDC.Relay.Setup.v1.5.18.exe` SHA256 `D4AD27F8569037E05F9F5E901F192979B42F7182BA455CF45D78FB596B6D9190`; `RDC.Relay.v1.5.18.Portable.zip` SHA256 `825D60816966A61C90630BDBBABBABB1EB6E918ED756AC6E41949F517DDFB688`. Concise RU/EN release notes.
- **No running RDC Relay app was restarted or installed payload replaced** on STARMER or workplace. Old v1.5.16/1.5.17 instances with `-SkipUpdate` cannot install by clicking until their first normal restart; user should close/reopen via usual shortcut to install latest stable v1.5.18. That temporarily interrupts Remote MCP.

---

## 2026-10-20 — Candidate v1.5.18: update button click ignored after -SkipUpdate (confirmed)

- User reported workplace `Desktop 3.0` displayed the new version button but clicking only made a barely perceptible flicker.
- **Root cause confirmed in v1.5.16–1.5.17:** `Start-RuntimeInitialization` checks `if (-not $SkipUpdate)` even when `$script:updateInstallRequested=$true` after the click. The updater is never launched; `Complete-RuntimeInitialization` resets the short-lived UI state and calls `Start-Remote`, causing flicker.
- The reachable workplace machine `DESKTOP-000EQMS` runs installed v1.5.16 with **`-SkipUpdate`** since its October 17 update. Its `update.log` has no v1.5.17 attempt and the last check is Oct 17. Whether `Desktop 3.0` is this exact machine was not independently confirmed; the bug applies to all `-SkipUpdate` instances.
- **Fix staged, NOT pushed/published:** on branch `fix/1.5.18-update-skip-override` make the updater run when `(-not $SkipUpdate -or $script:updateInstallRequested)`, preserving skip-on-relaunch but forcing a user-requested install. Version files set to candidate 1.5.18.
- Added `Tests/Test-UpdateNoticeClick.ps1` with an in-memory process stub and test cases for no automatic check with `-SkipUpdate`, explicit click with `-Force`, normal startup, and missing updater. Added test to release build gate.
- **PASS:** full release build (GUI logic, button paint, UI lifecycle, new regression, transactional installer/updater); unpacked Portable self-test; GPU offscreen test skipped due software fallback. No production processes stopped and no existing installations changed.
- **Immediate field workaround for current v1.5.16:** close RDC Relay normally, then reopen via the standard desktop/Start-menu shortcut (without `-SkipUpdate`); it then performs its ordinary startup update check. This temporarily disconnects Remote MCP. Do not execute remotely without explicit user approval.
- Next: user approval for release v1.5.18; then commit/tag/push and upload installer/Portable with concise bilingual notes. Do not confuse with v1.5.17 which remains published stable.

---

## 2026-10-20 — RELEASED v1.5.17: npm -4058 recovery and simpler device onboarding

- User explicitly requested pushing the prepared changes to GitHub with concise release notes.
- Published commit `a86fef5616fb4bb1b8d69730fb8670569905523a`; `main`, `stable` and annotated `v1.5.17` all point to it.
- Published GitHub latest release: https://github.com/1rubass1/RDC-Relay/releases/tag/v1.5.17 (draft=false, prerelease=false).
- Uploaded Setup `RDC.Relay.Setup.v1.5.17.exe` (SHA256 `69F25742A58E6EBC19FC29554F635FCE310F10A4026A0CDACEEA4CE7B60A1CBC`) and Portable `RDC.Relay.v1.5.17.Portable.zip` (SHA256 `E63115B72BB86B8D31ED862AF044A7CAB014029694A5499FAA0AC07D374F77F3`); server-side asset digests match. Concise bilingual Russian/English release notes.
- Full release build passed: GUI self-test, button paint, UI lifecycle, installer/updater transactions, compilation and packaging. New isolated npm ENOENT regression tests passed all 7 scenarios. Extracted Portable self-test passed. Offscreen GPU visualization skipped due to software fallback.
- No installed STARMER runtime was replaced, and active Desktop Commander Remote connections were not intentionally stopped.
- **Future:** run a direct user visual review before considering further changes to new Account menu appearance final; field-test automatic npm cache recovery on a new Windows device. No other provider architecture work bundled into this patch.

---

## 2026-10-20 — Candidate 1.5.17: safe npm ENOENT recovery and first-device onboarding

- User reported new Windows PC startup `-4058` with npm `ENOENT` reading `%LOCALAPPDATA%\npm-cache\_npx\c329005a7fd3ed13\package.json`. After manual removal, `npm.ps1` was blocked by PowerShell execution policy (use `npm.cmd`; changing policy unnecessary).
- Created local **unreleased** branch `fix/1.5.17-npx-onboarding` from clean main. Source still identifies as 1.5.16 until release preparation; **no push, new tag, published release or installed runtime replacement**.
- Added bounded `Repair-DesktopCommanderMissingNpxPackageJson` for confirmed npm ENOENT with exact hash-named subdirectory under current user's `npm-cache\_npx`. Requires matching npm log path, refuses unrelated/missing/valid package paths, rejects reparse-point targets and limits deletion to one confirmed entry per startup episode. Retry uses existing 2/5/10-second reconnect scheduler.
- Preserved old `dist/index.js` recovery path, which remains distinct.
- Added Account-menu `Подтвердить новое устройство…` linking to official verification page. Updated authentication status/help and README: RDC Relay itself runs pinned `npx.cmd`, no need to copy any shell command from the website; user must still authorize OAuth device in browser and verify its code. Upstream opens browser on first authentication normally.
- Added isolated `Tests/Test-NpxRecovery.ps1` with fixtures outside real cache: 7 safety/recovery scenarios **PASS**. GUI logic self-test **PASS** (GPU offscreen **SKIPPED** as software fallback). UI lifecycle, transaction rollback and button-paint tests **PASS**. `git diff --check` clean.
- Still required before any publication: visually inspect actual Account menu and authorization text in isolated preview; decide final version number, run release gate, obtain user approval, then update stable/tag/release. Do not restart production Remote without need.

---

## 2026-10-20 — ChatGPT plugin UI screenshot and eligibility research

- User showed an actual `Новый плагин` dialog with archive input (`.zip`, `.tgz`, `.tar.gz`) and a distinct **`Создать MCP-приложение`** button. This **proves entry-point visibility**, NOT successful creation/authorization of a custom remote MCP server on ChatGPT Plus.
- Read the current OpenAI plugin packaging, custom MCP, ChatGPT Sites, and desktop-local guides. Key distinction: uploadable plugin archive is NOT a publicly hosted MCP service; the MCP button should lead to URL/tunnel/auth creation if the workspace grants access.
- The Help Center's ordinary **custom MCP server** route lists Business/Enterprise/Edu permissions, but **ChatGPT Sites** is now available on Plus/Pro and can host its own MCP plugin on eligible accounts. Sites still needs a safe, authorized transport to reach private STARMER; this is an alternative to test, not end-to-end proof.
- Added exact interpretation, official references, account-gating uncertainties, and continuation checkpoints to `CHATGPT_PLUGIN_UI_REVIEW_2026-10-20.md`.
- Safely called the OpenAI docs' public MCP example from STARMER using the pinned MCP SDK: `initialize`, `tools/list` (`roll_dice`), and `tools/call` all **PASS**, process exited 0. Experiment script: `_experiments/direct-https-mcp/test-official-public-example.mjs`.
- No external plugin registration, account changes, public tunnel, real device exposure, or production code changes in this review.
- **Next when user returns:** inspect the `Создать MCP-приложение` form/permissions in the actual ChatGPT session, then perform *ping-only* ChatGPT-to-STARMER connection test or evaluate a minimal Site-hosted ping plugin. No provider refactor until ChatGPT E2E GO.

---


## 2026-10-20 — Direct HTTPS external tunnel + MCP protocol PASS

- Confirmed official ChatGPT HTTPS MCP requirement and OAuth 2.1 requirements.
- Downloaded Cloudflare cloudflared v2026.10.1 into isolated experiment folder (published SHA256 verified; Windows Authenticode signature Valid). Cloudflare Quick Tunnel registered a URL but **FAILED to connect** because the environment's DNS did not resolve `_v2-origintunneld._tcp.argotunnel.com` SRV; public request was Cloudflare HTTP 530. No DNS/firewall settings were modified.
- Used isolated **Pinggy** free HTTPS development tunnel as alternate egress-only public ingress, not production. Generated temporary public HTTPS hostname; no local inbound port or firewall change. Free tunnel has 60-minute limit.
- Implemented separate `public-ping.mjs` with 127.0.0.1 bind, exact configured public Host allowlist, random 224-bit URL capability, global rate bound, input limits and only one inert `rdc_spike_public_ping` tool. NO DesktopCommanderMCP is spawned or exposed by this public process.
- Added `/protected/<capability>/mcp` endpoint with 256-bit random Bearer secret and constant-time comparison for synthetic authentication enforcement tests; these short-lived test values are in `%LOCALAPPDATA%\RDCRelay\spike-public-https\session.json`, not Git.
- Live public Pinggy HTTPS connection **PASS** using regular TLS validation and official MCP client: initialize → tools/list → tools/call returned fixed ping; missing/invalid Bearer 401; valid Bearer passed tool call; unknown URL 404.
- Independent TinyFish cloud HTTP GET reached Pinggy but was intercepted by Pinggy's free-tunnel human visitor warning page; their warning claims non-browser API clients bypass it. Actual external ChatGPT MCP plugin registration/invocation was **not** possible from the available signed-in browser/tool session.
- Actual workspace/plugin creation availability remains to be checked manually in ChatGPT. Authentication beyond a test Bearer requires proper OAuth 2.1 before any real RDC data/action tools can be exposed.
- Exact test URL and temporary tunnel lifecycle details are in the current experimental runtime and `SPIKE_1_DIRECT_HTTPS_MCP.md`; no secrets committed. Production Git checkout remains clean.
- **NO-GO** for exposing unrestricted/DesktopCommanderMCP or provider refactor. The user is on ChatGPT Plus; official Help Center presently lists custom MCP connection creation for Business/Enterprise/Edu, and Pro has read/fetch support. The actual user's Plugins UI was not available in this session, so Plus plugin creation cannot be assumed.
- **Cleanup complete:** temporary Pinggy tunnel `8e2adee3-d68` stopped, its daemon stopped, public ping Node stopped; temporary capability/Bearer runtime files deleted. Port `127.0.0.1:49155` has **zero listeners** and no experimental processes remain. Temporary URL is invalid.
- Next: if the user's account/workspace provides `Add custom MCP server`, recreate the harmless ping tunnel and verify ChatGPT discovery/call; otherwise choose a supported workspace or alternative integration. Do not publish real tools before OAuth and security review.

---


## 2026-10-20 — Direct HTTPS MCP Spike 1: isolated local transport proven

- User authorized starting the next connection experiment.
- Confirmed STARMER online and `RDC-Relay Work` on clean `main` (`307c2d1`).
- Created isolated sandbox `_experiments/direct-https-mcp/` OUTSIDE the production Git repository.
- Pinned official MCP SDK v2 packages and created loopback-only Streamable HTTP MCP with harmless ping.
- `npm test`: PASS (health, Host/Origin 403, initialize, list, call).
- Created and tested local HTTP-to-stdio bridge to pinned `@wonderwhy-er/desktop-commander@0.2.52`, with a single hardcoded fixture read.
- `npm run test:bridge`: PASS (actual stdio MCP read_file result obtained through HTTP bridge).
- Created `SPIKE_1_DIRECT_HTTPS_MCP.md` with result, remaining gates, safety model and sources.
- **No public HTTPS endpoint / Cloudflare/ngrok / authentication / ChatGPT plugin was created.**
- Existing installed Relay, Remote session, Git branches, releases and firewall were not modified.
- Post-test process audit: the only matching Desktop Commander cmd/node pair had the production `remote` argument; no `commander-bridge` or `test-bridge` process remained running.
- Final production Git check: `main...origin/main` clean.
- State: **LOCAL TRANSPORT PASS; public HTTPS / ChatGPT E2E NOT YET TESTED**.
- Next: design protected HTTPS ingress + OAuth model, then test actual ChatGPT custom MCP with ping-only tools before exposing any real executor.
- Do not start 1.6.0 provider refactor until end-to-end GO.

---


## 2026-10-20 — User-first UI visual review rule

- After user enabled STARMER connectivity, added the permanent rule to the main local handoff at `E:\Projects\GitSync\RDC\HANDOFF.md`, section 12 (Machine-work conventions).
- For UI layout/motion/visual feedback changes, **ask the user to assess the actual live preview**, rather than automatically recording large batches (such as 80 frames). A few targeted screenshots may be used for technical diagnosis. Tests complement but do not substitute for user visual approval. Keep visual work reversible and the production Remote session uninterrupted.
- GitHub `README.md` had already recorded the same rule on `main` via documentation-only commit `307c2d1`. Local main was clean and fast-forwarded to that commit; `stable` and the release tag `v1.5.16` remain on `cbbd3ec` to preserve the exact published build.
- No GUI, installed runtime, release asset, or process was modified.

---

## RELEASED — RDC Relay v1.5.16 (2026-10-17)

**User authorized GitHub publication after reviewing/accepting the UI.** Released and independently verified:

- Release: https://github.com/1rubass1/RDC-Relay/releases/tag/v1.5.16
- Commit: `cbbd3ecd9610a3cbca7fdb19c66d43380b7b34a0`.
- `main`, `stable`, and annotated `v1.5.16` tag all point to this exact commit on GitHub. Local `main` and `stable` were moved to this release; clean `main` checkout.
- GitHub Release is **published, not draft, not prerelease, latest**. English + correctly encoded Russian release notes verified using the public API.
- Two GitHub release assets verified by GitHub SHA256 digest and size:
  - `RDC.Relay.Setup.v1.5.16.exe` (460,288 bytes), `A7D702A4CC52CD4DB488F27D470D709DB63596B7BAD096AAC7546E2AF58B4B23`
  - `RDC.Relay.v1.5.16.Portable.zip` (149,003 bytes), `5C1263B637AE012E09744B15B3A00FC2B3FC7D5382664018F8271AD979891E23`
- Full `Scripts/build-release.ps1` release gate **passed**: HLSL shader rebuild, icon build, GUI logic self-test, button paint/keyboard test, UI lifecycle test, installer/updater transactional tests, compiled Setup/Portable and checksums. GPU visual offscreen test was SKIPPED due to software fallback, as recorded by the gate.
- **Additional extracted Portable ZIP `-SelfTest -SkipUpdate` passed**; `update-notice.ps1` and portable launcher confirmed inside archive. Build and manifest SHA256 values match.
- Release notes template followed prior releases: installer and portable instructions, highlights, antivirus note, bilingual English/Russian text; checksums were added.
- Installed STARMER runtime was **still 1.5.15** when publication finished, with Remote running (previously observed PID 23704). User did **not** request replacement of the live application. It can update via its existing startup updater on the next launch; do not claim auto-updating an already-running v1.5.15 instance through the newly released button.
- `dist/v1.5.16/` holds generated assets and bilingual `RELEASE_NOTES_RU_EN.md` locally; release API helper was written to ignored `dist/` without saving a token. Authentication used Git Credential Manager in memory only.
- Earlier preview branch `audit/1.5.15-manual-stop` was merged by fast-forward into the release commit. It remains a historical review branch, **not outstanding unpublished work**.
- Full UI work from 2026-10-16/17 (below) is now a shipped release. Next work may focus on separate MCP architecture research, maintaining the existing release as a rollback point.

---

## 2026-10-17 — Footer microinteraction: pixel-stable typography and clean border

User visually confirmed that the old version and right-hand informational label jumped/shrank when animation began, the gold outline looked distorted, and the white arrow should instead match muted gray informational text.

**Root cause confirmed**: the feature toggled **two different WinForms renderers** on every replay: an idle `FlowLayoutPanel` with Label controls and an animated `RdcUpdateNoticeStrip` with TextRenderer/GDI+ text. Reparenting forced font autoscaling/layout changes and different vertical centering. The old button was 24px high inside a 25px footer: the 2.15px inset stroke, located at y=0..24, could clip/warp antialiased corners.

**Local changes on `audit/1.5.15-manual-stop`**:
- `Source/update-notice.ps1`: when the optional feature is enabled, attach **one persistent 25px `RdcUpdateNoticeStrip`** during startup. `SetIdle` → `Begin` → `End` changes only drawing state; **no UI control is swapped, recreated, refonted, or reparented during animation**. The same TextRenderer paints the version, orange separator and static close warning at all stages.
- `Source/update-notice.ps1`: arrow now uses the exact muted gray `RGB(128,128,128)` of footer information. Button contour inset 1.5px and centered 2.2px stroke; button 21px high with 2px clearance at top/bottom (prevents border clipping). Normal accessibility role is static text; becomes a button only when an update exists.
- `Source/remote-window.ps1`: self-test now checks persistent renderer identity, font identity, same y position, 440→590→440 width transition, visibility, keyboard invocation, and **bit-for-bit identical right-hand informational text pixels** before/after full animation.
- Legacy footer remains **completely unchanged** with `$script:enableUpdateNotice = $false`; updater functions remain separate and unchanged.

**Tests/verification**:
- `remote-window.ps1 -SelfTest -SkipUpdate`: PASS, including new pixel and layout assertions. GPU visual test SKIPPED (software fallback).
- Explicit rollback/feature-off test (`dist/Test-NoticeDisabled.ps1`): PASS, and original source/manifest restored byte-for-byte.
- `Test-UiLifecycle`, `Test-ButtonPaint`, `Test-Transactions`: PASS.
- Actual `PrintWindow` from preview PID **21416** captured 80 sequential frames over ~14 seconds, including multiple replay stages. For the **rightmost 275 × 25 pixel** region containing the unchanging close warning, SHA256 had **exactly 1 unique frame hash across all 80 captures**. This confirms the informational label no longer shifts or changes glyph size/pixels in real UI.
- `dist/notice-motion-contact.png` records the stages; `dist/button-zoom.png` magnifies the smoother symmetric gold border. These are development diagnostics in ignored `dist`, not release assets.
- No published release, no push, no installed-client modifications. User still needs to approve the live appearance.

**Completed**: local commit `42afe2f` (feature remains independently revertible), Git worktree clean. Restarted only standalone `-Preview`; new PID **21668** is alive, responsive, window visible and brought to foreground on STARMER. Installed/Remote v1.5.15 remains intact. **Next**: user visual acceptance of the periodically repeated animation. Build/release/version bump remain separate pending approval.

---

## 2026-10-17 — Footer notification visual polish and repeatable preview

User feedback: arrow should be **white**, orange update button should become **gray with thick gold border and bold gold version text**, current-version font should match informational footer font, and the animation must be observable rather than completing before the user can see it.

Branch: `audit/1.5.15-manual-stop` (local only, based on published 1.5.15).

Changes:
- `Source/update-notice.ps1`: white arrow (RGB 239,240,244); gray button with gold 2.15px border and 9.5pt bold Segoe UI gold label; hover/press styles remain neutral/gold; connected move 300ms, arrow reveal 280ms (230ms delayed), button fade 230ms (480ms delayed), ~750ms overall. Windows Learn Fluent motion principles followed; no repeated motion in production.
- `Source/update-notice.ps1`: **only in `-Preview`**, wait 1.8s after Shown before starting and then replay the whole show/hide sequence approximately every 7.2s. Actual stable-release notification still enters only once per discovered version.
- `Source/remote-window.ps1`: preview synthetic notification now runs via `Start-RdcUpdateNoticePreview`, status text says the animation repeats; baseline version label explicitly uses the hint font, and new self-test checks the active custom strip's font matches it.
- **Important WinForms scaling detail**: assigning `rdcNoticeControl.Font = hint.Font` during module initialization or before reparenting left a 10pt custom font while the final hint was 8.25pt (confirmed by a failing self-test). Assigning it **after** `$bottom.Controls.Add(...)` in `Show-RdcUpdateNotice` resolves the actual discrepancy. This regression is now covered.
- `README.md` updated. `Source/update-manifest.json` SHA256 hashes synchronized; candidate still has version 1.5.15 and MUST be version-bumped before any publication.

Verification:
- GUI self-test PASS with explicit typography check; `Test-UiLifecycle.ps1`, `Test-ButtonPaint.ps1`, `Test-Transactions.ps1` PASS; manifest hashes match and `git diff --check` clean.
- Captured **actual rendering over time**, 80 frames roughly 125ms apart, using Win32 `PrintWindow` of standalone preview PID **11216**. Montage `dist/notice-motion-contact.png` shows old footer, version shift, arrow during reveal, gold-gray button and reset/replay. This is stronger than the earlier static `DrawToBitmap` assertion.
- Software GPU offscreen test still SKIPPED; user's actual visual acceptance remains required.
- Installed STARMER production remains **v1.5.15**, running Remote untouched; no GitHub push/release or installed-binary replacement.

Next: visually review the automatically repeating preview on STARMER with user; adjust style/motion if needed. Once accepted, plan a properly versioned candidate (e.g. 1.5.16) and perform full build/release acceptance. Optional notice stays separately revertible; keep local git commits.

---

## 2026-10-16 — FIX: blank footer in actual update-preview window

User reported the previous `-Preview` looked blank on the right (no update button, arrow, version, or close warning) and the account/runtime footer had two empty fields. This was **reproduced on STARMER**, not merely assumed from self-tests.

**Root cause:** the footer `TableLayoutPanel` has a 38 px outer height and 7/6 px vertical padding (25 px visible inner area), but its single auto-preferred row reports **100 px** because of the existing `FlowLayoutPanel`. The new custom `RdcUpdateNoticeStrip` was `Dock=Fill` and rendered all its text and button at the vertical center of the **100 px** logical row, outside the visible, clipped area. Previous `DrawToBitmap` self-tests rendered the entire 100 px and could not catch this.

**Changes in the local candidate (not production):**
- `Source/update-notice.ps1`: optional strip uses `Dock=Top` and `Height=25`, isolating the change to the reversible module without changing the existing footer layout or feature-off mode.
- `Source/remote-window.ps1`: new self-test assertion checks the real visible area and rejects controls taller than it; preview-only `Set-RuntimeDisplay 'Remote не запущен' 'Только предпросмотр'` replaces two meaningless empty placeholders.
- `Source/update-manifest.json`: hashes regenerated for source changes.

**Validation:** direct Windows `PrintWindow` screenshots of the running preview initially confirmed completely blank right footer, and after the fix confirmed `v1.5.15 → [orange v1.5.16] • Крестик закрывает окно вместе с remote-процессом.` with left-side preview labels. `-SelfTest -SkipUpdate`: PASS; `Test-UiLifecycle.ps1`: PASS; `Test-ButtonPaint.ps1`: PASS; `Test-Transactions.ps1`: PASS. Also explicitly toggled `$script:enableUpdateNotice = $false` and ran `-SelfTest` (PASS), then **restored the original candidate source and manifest byte-for-byte**. GPU offscreen visual test remains SKIPPED, so real motion and minimize/restore need user visual acceptance.

**Commit:** local-only `320c3e6` — footer clipping fix and regression; separate from reversible feature commit `243a16e`. Git worktree clean, no push.

**Preview on STARMER:** corrected standalone `-Preview` process PID **12456** was running at last check. It does not run or stop Remote, does not install updates, and does not reach GitHub. Published/installed v1.5.15 remains untouched; nothing pushed.

---

## CURRENT UI WORK — 2026-10-16 (supersedes older checkpoints below)

On STARMER, current production remains published/installed **v1.5.15**. The separate local development branch is `audit/1.5.15-manual-stop`.

**Commits made locally only**:
- `3345d8d` — manual Stop and damaged npx bootstrap-detection fixes.
- `118c397` — suppress playback of the stale green recovery flash on window restore; new offscreen regression.
- `243a16e` — optional reversible in-session update notification, including module, packaging, manifest and README.

**In-progress, NOT pushed/installed/released (but fully committed locally)**:
- `Source/update-notice.ps1`: opt-in feature module with an orange version button, version slide, arrow reveal, opacity fade; Unicode UTF-8 BOM required for Windows PowerShell 5.1.
- `Source/remote-window.ps1`: isolated feature flag, async hourly `stable` manifest check, manual `update.ps1 -Force` invocation, synthetic `-Preview`, UI regression tests.
- `Source/update-manifest.json`, `Scripts/build-release.ps1`, `Installer/Setup.cs`: include update-notice module with SHA256 verification in future release payloads.
- `README.md`: update feature/rollback instructions.

The old footer remains intact when the flag `$script:enableUpdateNotice = $false`. The old automatic startup updater remains unchanged; notifications target new releases discovered while RDC Relay stays running.

**Observed tests**: `remote-window.ps1 -SelfTest -SkipUpdate` PASS; button keyboard activation Enter/Space PASS; notice Show/Hide restoration PASS; synthetic version comparison PASS; restored-window recovery animation cancellation PASS; baseline `Test-UiLifecycle`, `Test-Transactions`, `Test-ButtonPaint` PASS. HTTP request with exactly the proposed `HttpClient` headers succeeded on STARMER: `stable` resolved to `eace20c`, manifest version `1.5.15`. The GPU self-test was SKIPPED because of offscreen software rendering. A rendered footer bitmap after fixing module UTF-8 BOM visually shows correct Russian text, arrow, dot, current version, and orange v1.5.16 button.

**Still pending**: actual on-screen animation/motion acceptance by user (new standalone `-Preview` process PID 23060 running on STARMER, safe and no Remote launched); future `v1.5.16` candidate packaging/full release build tests; real manual update click with a future stable version; any push/release or installed-runtime replacement. Do not claim these are completed. The existing `-Preview` is a safe standalone UI (does not start Remote or connect to GitHub).

User confirmed the old experimental `RDC Relay Tunnel Runtime` API key was destroyed/inactivated when the former Business workspace subscription ended. Do not attempt to use that abandoned workspace or its credentials.

**Next exact step**: user visually reviews the open `-Preview` on STARMER, including motion and footer geometry. Refine only if needed. After acceptance, choose a new version and run candidate release build; ask separately before push/release/deployment. The optional notice is fully isolated in local commit `243a16e` (revert it, or set `$script:enableUpdateNotice = $false`) independently of green flash and audit fixes.

---

## CURRENT AUDIT CHECKPOINT — 2026-10-16

The earlier 2026-10-07 "current objective" and v1.5.12 production wording below are historical. Current GitHub `main`/`stable` and installed STARMER runtime are **v1.5.15**, commit `eace20c1e283d57debbf135e28f18949bac628bd`. The original v1.5.12 commit remains a rollback reference.

User requested a review of changes previously made with the free ChatGPT model. Audit was performed against the real STARMER worktree and GitHub on 2026-10-16.

### Findings (confirmed in published v1.5.15 source)

- **Manual Stop regression:** `manualStopRequested` was initialized/reset to false but never set true; late Remote markers could incorrectly influence stopped state. Also `Set-DividerStoppedState($true)` was defined but never invoked, so the intended quiet/neutral stopped state was not activated.
- **Bootstrap recovery detection:** `Test-DesktopCommanderBootstrapFailure` used a slash-only `dist/index.js` segment even though Windows Node errors use `dist\\index.js`; the literal dot escaping was also incorrect. The retry branch for this error could be missed.
- **Dead shader parameter:** `StoppedProperty` was bound to a pixel-shader register not used by HLSL. Removed unused parameter; paused/stopped popup is now explicitly hidden, with gray neutral rails.
- **Documentation drift:** project-level HANDOFF/ROADMAP/WORKLOG still described v1.5.12 as current or OpenAI Tunnel Spike 0 as upcoming. HANDOFF production baseline corrected; this checkpoint overrides stale ROADMAP state until architecture roadmap is revised.
- **Auto-updater:** installed `update.log` confirms v1.5.12 → v1.5.15 completed on 2026-10-08. Installed version is 1.5.15; `.update-state.json` last check 2026-10-16. The 6-hour check cache may delay discovery of brand-new releases, by design.
- **OpenAI Tunnel Spike 0:** still BLOCKED/NO-GO at the ChatGPT → tunnel initiation step. No evidence to justify integrating this provider into production yet. Self-hosted HTTPS MCP endpoint and plugin ZIP are design ideas, not shipped or end-to-end-proven features.

### Local remediation state

- Git branch: `audit/1.5.15-manual-stop` (created from published `eace20c`).
- Historical note: initially uncommitted, these audit fixes were subsequently committed locally as `3345d8d`; they are not pushed/published/deployed. Green restore fix is separately committed as `118c397`. Update notice is pending as separate feature change.
- Fixed manual Stop guard and neutral stopped-state activation, inhibited late fault markers, corrected bootstrap failure regex, removed dead shader property, added regression tests.
- Manifest SHA256 synchronized with modified GUI source for **local self-test only**. A future publication must bump version (e.g. 1.5.16) and rebuild release assets, not silently overwrite v1.5.15.
- PASSED after edits: `remote-window.ps1 -SelfTest` GUI logic, `Test-UiLifecycle.ps1` (including Windows/POSIX bootstrap classification and stop-state assertions), `Test-Transactions.ps1`, `Test-ButtonPaint.ps1`. `git diff --check` showed no whitespace errors before manifest change.
- GPU offscreen visual test is **SKIPPED** under software fallback; actual GUI preview/manual acceptance is still required. No live Remote process stopped, no installed binaries replaced, no release pushed.
- Security cleanup: user confirmed on 2026-10-16 that the former Business workspace and experimental runtime key are destroyed/inactive. Do not reuse.

### Next exact action

Review the local audit diff and perform a **non-destructive visual preview** of stopped mode with user approval; add targeted tests for actual Stop/Start state transitions if necessary. After user acceptance, create a properly versioned release candidate, run release gates, then request separate permission before any push/release/installed-runtime replacement.

---

> **ОПЕРАТИВНЫЙ ДОКУМЕНТ ДЛЯ ПЕРЕДАЧИ РАБОТЫ МЕЖДУ АГЕНТАМИ**
>
> Этот файл предназначен для текущей разработки и экстренного handoff.
> Его нужно обновлять во время работы, чтобы новый агент мог быстро понять:
> - что делалось в последнее время;
> - что уже изменено;
> - что ещё не закончено;
> - что проверено, а что только предполагается;
> - какие файлы/ветки/процессы затронуты;
> - с какого конкретно шага продолжать.
>
> **Не заменяет** `HANDOFF.md`, `ROADMAP.md` и `TECHNICAL_DESIGN.md`.
> Стратегические документы меняются только при реальном изменении архитектуры/плана.
> Этот файл, напротив, должен оставаться живым и актуальным.

---

# 0. Правила ведения

Каждый агент, выполняющий существенную работу по RDC Relay, должен:

1. **Перед началом работы**
   - прочитать `HANDOFF.md`;
   - прочитать этот `WORKLOG.md`;
   - при необходимости прочитать соответствующий Roadmap/Technical Design/Spike;
   - сверить фактический Git/status/runtime, если задача требует работы с кодом.

2. **Во время работы**
   - обновлять раздел **Current Work** при изменении направления;
   - фиксировать важные промежуточные решения;
   - отмечать непроверенные предположения как непроверенные;
   - не записывать секреты/API keys/tokens.

3. **Перед завершением сессии**
   - обновить **Last Known State**;
   - записать реально выполненные проверки;
   - перечислить оставшиеся незавершённые пункты;
   - дать следующий конкретный шаг;
   - добавить короткую запись в **Recent Session Log**.

4. **При экстренном обрыве**
   следующий агент должен в первую очередь доверять:
   - фактическому Git/runtime состоянию;
   - затем этому файлу;
   - затем старому контексту чата.

5. Не использовать этот файл как бесконечный changelog.
   После выхода стабильного релиза устаревшие подробности можно:
   - кратко свернуть;
   - перенести в архив;
   - заменить ссылкой на Git commit/release.

---

# 1. Project Location

Project root:

```text
E:\Projects\GitSync\RDC
```

Active Git working tree:

```text
E:\Projects\GitSync\RDC\RDC-Relay Work
```

Archive:

```text
E:\Projects\GitSync\RDC\_archive
```

Strategic documents:

```text
HANDOFF.md
ROADMAP.md
TECHNICAL_DESIGN.md
SOURCES.md
SPIKE_0_OPENAI_TUNNEL.md
```

---

# 2. Last Known Stable Baseline

Production:

```text
RDC Relay v1.5.12
```

Commit:

```text
4e47cee861c077ddf050220a9dea5ed8d44d1b02
```

Desktop Commander package pin:

```text
@wonderwhy-er/desktop-commander@0.2.52
```

Published production release:

```text
https://github.com/1rubass1/RDC-Relay/releases/tag/v1.5.12
```

Important:

- v1.5.12 is the rollback/reference baseline.
- Do not rewrite its published tag/release.
- Provider architecture belongs to a new development line.

---

# 3. Current Work

## Current objective

Prepare and execute **Spike 0 — OpenAI Secure MCP Tunnel feasibility** before changing RDC Relay production architecture.

Operational browser rule for this project:

```text
Use Microsoft Edge for agent-driven web/UI work.
Do not interact with Opera; it is the user's primary browser.
Prefer a dedicated Edge window on the third/virtual monitor.
```

Target path to prove:

```text
ChatGPT
→ OpenAI Secure MCP Tunnel
→ tunnel-client on STARMER
→ local DesktopCommanderMCP via stdio
→ STARMER
```

Detailed checklist:

```text
E:\Projects\GitSync\RDC\SPIKE_0_OPENAI_TUNNEL.md
```

## Current development stage

```text
Architecture planning complete.
Spike 0 EXECUTED on 2026-10-07.
Local/tunnel runtime path is technically viable.
ChatGPT personal-workspace access is currently blocked upstream before MCP traffic reaches STARMER.
Production code remains unchanged for provider work.
```

Current Spike 0 checkpoint:

```text
- official OpenAI tunnel-client v0.0.16 verified by SHA256 and runs on STARMER;
- pinned @wonderwhy-er/desktop-commander@0.2.52 works as local stdio MCP;
- local initialize, tools/list and real read_file were proven;
- organization-backed tunnel doctor/runtime/health all pass;
- workspace-only control tunnel doctor/runtime/health all pass;
- both runtimes start DesktopCommanderMCP 0.2.52 successfully;
- ChatGPT rejects tunnel access before initialize reaches STARMER;
- /health/mcp remains not_observed after ChatGPT validation attempts;
- OpenAI tunnel-client issue #60 is open and describes the same active-organization/personal-workspace failure class;
- production RDC Relay code remains unchanged.
```

## Current architectural decision

If Spike 0 returns GO:

```text
ConnectionProvider
├── DesktopCommanderRemoteProvider
└── OpenAITunnelProvider
```

The existing RDC Relay supervisor/state machine should consume normalized provider events rather than being duplicated per transport.

---

# 4. Immediate Next Steps

Next agent should **not** begin the provider refactor or edit `remote-window.ps1` for OpenAI Tunnel integration yet.

Current decision:

```text
Spike 0 = BLOCKED / NO-GO for production integration at this time.
Local stdio + tunnel-client path works.
Hosted ChatGPT personal-workspace access blocks the request before MCP initialize reaches STARMER.
```

Proceed in this order:

1. Read the execution-result section appended to `SPIKE_0_OPENAI_TUNNEL.md`.
2. Check whether OpenAI tunnel-client issue #60 or related OpenAI documentation has changed since 2026-10-07.
3. Do not repeat local stdio, SHA256, doctor, or basic health experiments unless the environment materially changes; they already passed.
4. Retry ChatGPT integration only after there is evidence that the personal-workspace active-organization/access problem is fixed or a different eligible ChatGPT workspace is available.
5. On retry, require these gates:
   ```text
   ChatGPT custom MCP validation succeeds
   → /health/mcp records initialize
   → tools/list is observed
   → one safe read tool succeeds
   → one controlled write/read-back/cleanup succeeds
   ```
6. Only after all gates pass should the project move to:
   ```text
   develop/1.6.0-providers
   → ConnectionProvider abstraction
   → DesktopCommanderRemoteProvider parity
   → OpenAITunnelProvider
   ```

Until then, RDC Relay v1.5.12 remains the production baseline and provider production code should stay unchanged.

---

# 5. Do Not Do Yet

Unless new evidence changes the architecture, do not start:

- custom MCP executor;
- Google OAuth;
- custom cloud broker;
- device registry/database;
- production zrok integration;
- automatic provider failover;
- large UI rewrite;
- large C#/PowerShell rewrite;
- OpenAI provider integration before the transport spike succeeds.

---

# 6. Open Questions / Unknowns

These are unresolved and must not be presented as facts:

1. Is OpenAI Tunnels available to this exact account/workspace?
2. Which tunnel-client Windows version will be tested?
3. Does DesktopCommanderMCP behave correctly as tunnel-client stdio child?
4. How precisely do OpenAI health endpoints distinguish transport vs MCP child failure?
5. Are per-tool lifecycle events observable, or only generic activity/metrics?
6. How fast and reliably does tunnel-client reconnect?
7. Does ChatGPT retain the tunnel/plugin configuration after tunnel-client restart?
8. What OpenAI usage limits/costs apply in this exact account context?
9. Should production package tunnel-client or download/pin it separately?
10. Which Windows protected-secret mechanism is preferable after the spike:
    DPAPI CurrentUser or Credential Manager?

---

# 7. Last Known Git / Runtime State

As of the creation of this file:

```text
Active working tree:
E:\Projects\GitSync\RDC\RDC-Relay Work
```

Last verified state after folder rename:

```text
Git repository resolves correctly from the new path.
Working tree was clean.
No production source changes were introduced by moving project-level docs.
```

Important:

The strategic markdown files live **outside the Git working tree**, directly under:

```text
E:\Projects\GitSync\RDC
```

Therefore Git status inside `RDC-Relay Work` does not track changes to this WORKLOG or the strategic documents.

---

# 8. Active Files / Temporary Artifacts

Current project-level active documents:

```text
E:\Projects\GitSync\RDC\HANDOFF.md
E:\Projects\GitSync\RDC\WORKLOG.md
E:\Projects\GitSync\RDC\ROADMAP.md
E:\Projects\GitSync\RDC\TECHNICAL_DESIGN.md
E:\Projects\GitSync\RDC\SOURCES.md
E:\Projects\GitSync\RDC\SPIKE_0_OPENAI_TUNNEL.md
E:\Projects\GitSync\RDC\FOR_USER.md
```

No provider implementation files have been created yet.

---

# 9. Current Risks

## R1 — premature refactor

Risk:

Building provider architecture before proving the OpenAI transport could create significant code churn for an unavailable path.

Mitigation:

Spike 0 first.

## R2 — WORKLOG drift

Risk:

This file becomes stale and gives the next agent false confidence.

Mitigation:

Every substantial development session must update **Last Known State**, **Immediate Next Steps**, and **Recent Session Log**.

## R3 — mixing strategy with operations

Risk:

Frequent operational changes pollute `HANDOFF.md` / `TECHNICAL_DESIGN.md`.

Mitigation:

Operational detail belongs here.
Only durable architectural decisions graduate into strategic docs.

## R4 — undocumented local state

Risk:

An agent modifies local code/runtime but chat ends before commit or handoff.

Mitigation:

Before risky/long work, write a short checkpoint into **Current Work**.
After meaningful edits, update **Uncommitted / In Progress** below.

---

# 10. Uncommitted / In Progress

> Historical 2026-10-08 candidate entry below, abandoned and not present in current Git HEAD. For the real 2026-10-16 working state, see **CURRENT UI WORK** at the top of this document.

Current status (historical only):

```text
Update notification UI is implemented in Source\\remote-window.ps1.

Modified:
- Source/remote-window.ps1
- Source/update-manifest.json

Behavior:
- background GitHub latest-release check starts shortly after startup and repeats hourly;
- GitHub failures are non-fatal and do not alter Relay state;
- when a newer release is found, the bottom version group expands with a smooth version → arrow → orange update button sequence;
- update button invokes the existing transactional update.ps1 mechanism.

Visual preview:
- -Preview renders a synthetic v1.5.13 notification for visual inspection only.

Installed runtime:
not updated from the worktree yet.
```

Last successful test:
```text
GPU VISUAL SELF TEST SKIPPED: offscreen-software-fallback; transparent=0.000; visible=1.000; chromatic=0.000; meanAlpha=255.0; edgeMeanAlpha=255.0
GUI self-test completed without a reported assertion failure.
```

Known next step:
Run the candidate visually on STARMER, inspect the notification choreography, then install/merge only after approval.

When work begins, replace this section with exact entries, for example:

```text
Branch:
develop/1.6.0-providers

Modified:
- Source/connection-providers.ps1
- Source/remote-window.ps1

Untracked:
- Tests/provider-events.tests.ps1

Installed runtime:
not updated

Last successful test:
GUI LOGIC SELF TEST PASSED

Known failure:
OpenAI readyz remains 503 after MCP child restart
```

Never write vague text like “some files changed”.

---

# 11. Current Decisions Made During Active Development

## W-001 — Project-level strategy docs live outside active Git checkout

Decision:

```text
E:\Projects\GitSync\RDC
```

contains project strategy/handoff documents.

Active repository:

```text
E:\Projects\GitSync\RDC\RDC-Relay Work
```

Reason:

Project strategy spans the active checkout, archives, experiments and future working trees.

## W-002 — WORKLOG is mutable; HANDOFF is stable

`HANDOFF.md`:

- durable project identity;
- baseline;
- architectural orientation;
- rules for new agents.

`WORKLOG.md`:

- recent work;
- incomplete work;
- transient decisions;
- current blockers;
- exact next action.

When a WORKLOG decision becomes durable architecture, migrate/summarize it into the appropriate strategic document.

---

# 12. Recent Session Log

Keep this section concise. Newest first.

## 2026-10-08 — Hourly GitHub update notification candidate

Implemented in the active worktree:

- added a background latest-release check against the official GitHub Releases API;
- first check is delayed until after startup, then repeats every hour;
- network/API failure is isolated from Relay connection state;
- added a compact bottom-right update group: current version, animated arrow, and a custom orange update button with dark-orange outline;
- animation uses short staged ease-out motion: version group expands left, arrow enters first, then the button grows in;
- update click starts the existing transactional update.ps1 -Force path;
- -Preview contains a synthetic v1.5.13 visual probe only;
- updated update-manifest.json SHA256 for the modified runtime script.

Verification:

GUI self-test completed without assertion failure.
GPU VISUAL SELF TEST SKIPPED: offscreen-software-fallback; transparent=0.000; visible=1.000; chromatic=0.000; meanAlpha=255.0; edgeMeanAlpha=255.0

Design timing follows the Windows motion guidance range (roughly 167–250 ms per transition stage) with cubic ease-out behavior.

Next:

Inspect the -Preview choreography visually on STARMER, then decide whether to keep/tune it before installing the candidate runtime.

## 2026-10-07 — OpenAI Tunnel Spike 0 executed

Completed:

- verified official `tunnel-client v0.0.16` and local DesktopCommanderMCP stdio operation;
- proved local MCP initialize/tools-list/read path;
- created organization-backed and genuine workspace-only test tunnels;
- both tunnel runtimes passed doctor, metadata fetch, polling, healthz and readyz;
- ChatGPT rejected both before MCP initialize reached STARMER;
- correlated the failure with open upstream tunnel-client issue #60 / personal-workspace active-organization access behavior;
- stopped both temporary tunnel runtimes;
- production RDC Relay code remained untouched;
- full technical result appended to `SPIKE_0_OPENAI_TUNNEL.md`.

Security cleanup still required:

```text
Revoke/delete API key:
RDC Relay Tunnel Runtime
```

The temporary key was exposed in chat and must not be reused even if the chat is later deleted.

Next:

```text
Wait for an OpenAI fix/documented supported path or test with a different eligible ChatGPT workspace.
Do not start the provider refactor yet.
```

## 2026-10-07 — Project documentation restructuring

Completed:

- moved strategic documentation from the Git checkout to project root:
  ```text
  E:\Projects\GitSync\RDC
  ```
- renamed active Git working directory:
  ```text
  Remote Desktop Commander
  → RDC-Relay Work
  ```
- verified Git still resolves correctly after rename;
- verified working tree was clean;
- updated old absolute path references;
- expanded `HANDOFF.md` with explicit project-root/worktree/archive layout;
- created this `WORKLOG.md` as the mutable inter-agent development handoff;
- created `FOR_USER.md` as a user-facing index explaining what each project-level document is for and which files should be pinned in ChatGPT Project.

Next:

```text
Run Spike 0 when user gives the development go-ahead.
```

---

# 13. Emergency Handoff Template

Use this if a session is about to end unexpectedly.

```text
CURRENT TASK:
<one sentence>

BRANCH / HEAD:
<branch>
<commit>

WHAT CHANGED:
- ...
- ...

FILES TOUCHED:
- ...

RUNTIME/INSTALL STATE:
- ...

TESTS PASSED:
- ...

TESTS FAILED / NOT RUN:
- ...

KNOWN BUG / BLOCKER:
- ...

DO NOT DO:
- ...

NEXT EXACT STEP:
<one concrete action>

TEMP FILES / PROCESSES:
- ...

SECRETS:
No secrets are stored in this document.
```

---

# 14. Maintenance Rule

This file should answer, in under a few minutes:

> “The previous agent disappeared. What was it doing, what state did it leave the project in, and what exactly should I do next?”

If it cannot answer that, update it before doing more development.
