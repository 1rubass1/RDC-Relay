# RDC Relay 1.6.0 RC1 — tray v04 integration and reliable GUI reopening

**Date:** 2026-11-11. **Tracking:** [GitHub Issue #24](https://github.com/1rubass1/RDC-Relay/issues/24). **Status:** owner confirmed tray artwork/motion approved; GUI-open corrective implementation started in Draft PR #25. Full tray rendering, Windows build and installed acceptance NOT CHECKED. **This is NOT a completed fix or a release.**

**Owners of work:** Designer DES-002 owns approval/final export of icon frames; Programmer owns Host/NotifyIcon integration and UI activation fix; independent Reviewer validates. Avoid parallel edits to Designer's in-progress files and to another Programmer's tray implementation.

## Inputs already available

Owner supplied `Desktop/RDC Relay - Значок 04/Трей/` on STARMER. **The folder is named «Трей»** (not Latin `tray`). It contains:

- `REVIEW.md` and `Начать здесь.txt`: states, color/motion assumptions, and explicit **pending visual approval**.
- `Просмотр.html`, `Обзор.png`, `Обзор.svg`: interactive animated/static and light/dark preview.
- `Параметры.json` plus `Проверка просмотра.json`: preview timings, palette and initial checks.
- `PNG/` and `SVG/`: **64 files of each type** (56 at 16–64 px, plus eight at 256 px), covering 8 icon frames (`offline`, `connecting-a/b`, `auth-a/b`, `ready`, `working`, `fault`) at 16/20/24/32/40/48/64/256 px.

Reference in project: `docs/dev/design/icon-concepts-2026-11-11/TRAY-HANDOFF.md`, `tray-v04-preview-01/REVIEW.md`, `COORDINATION/BOARD.md` DES-002, `docs/dev/architecture/TRAY-LIFECYCLE-DESIGN.md`.

**Owner explicitly approved this design on 2026-11-11** and authorized integration. The older preview REVIEW.md wording 'pending visual approval' is superseded; 16/20 px physical Windows tray QA is still mandatory. Do not alter the approved forms, palette or motion. The source folder itself must not be moved or modified in place; only approved, hash-checked copies should enter a private RC1 build. Existing *main application* icon v04 stays unchanged.

## Scope A — tray icon states (after design approval)

Use exactly the approved states and transitions, driven by authoritative sanitized Host state, not by guesses or a local socket retry timer:

| State | Preview frame(s) | Meaning |
| --- | --- | --- |
| `Disconnected` / unknown | `offline` | grey halves, transparent center |
| `Connecting` / `Reconnecting` | `connecting-a/b` | swap orange/grey halves |
| `AuthPending` | `auth-a/b` | swap orange/purple halves |
| `Ready` and idle | `ready` | orange halves, constant green center |
| `Ready` and `toolActivity=working` | `working` | orange halves, pulsing purple center |
| `Fault` | `fault` | grey halves, constant red center |

Keep link health ahead of tool activity; individual tool failures do not trigger a connection-fault icon. Do not extend the working animation on `toolActivity=hold`. Respect OS reduced-motion settings (static first frame), avoid repainting at excessive cadence, minimize allocations and safely dispose retired `Icon` objects; `NotifyIcon.Icon` needs a Windows `Icon` resource, not an SVG or PNG path. Approved design uses **800 ms half-swap / 1,800 ms center pulse**. Implement the preview timing subject to Windows reduced-motion fallback. Tooltip indicates the stable state, not each animation frame. Form X and Host exit retain the existing separate lifecycle rules.

## Scope B — blocking incident fix: reliable «Открыть RDC Relay» from tray and launcher

**Required in the same tray integration deliverable, BEFORE a user-facing G122 Setup candidate.**

The 2026-11-11 G121 incident [read-only investigation](V1-6-0-RC1-GUI-ACTIVATION-INCIDENT-2026-11-11.md) establishes that after rollback the stable 1.5.18 process *already had a responsive, visible, on-screen GUI* but was behind a fullscreen app; launching its shortcut again did not create another GUI because the single-instance mutex was held. The G121 GUI opened in disposable `-Preview`, but **full OwnerGui Host/tray startup failure remains unproven**. Never label this incident a fixed G121 crash without genuine authenticated Host+GUI OS evidence.

In `Source/RdcOwnerRuntime.cs` `OpenGui()` currently calls `ShowWindow(hwnd,9)` and `SetForegroundWindow(hwnd)` and returns without checking either result. In the stable legacy entry, a duplicate-launch path similarly attempts activation and exits. Windows may deny foreground activation, particularly with another full-screen app in control.

Implement one **non-destructive, bounded** activation policy for explicit tray `Open`, tray double-click and Owner launcher attach:

1. For a verified **live owned GUI**, detect a valid nonzero HWND, visibility, minimization and usable monitor placement. Restore only when hidden/minimized; avoid forceful moving or resizing an already-usable GUI.
2. Attempt `SetForegroundWindow` and **verify actual outcome**, e.g. foreground HWND/related activated window after a short bounded check. Treat an unsuccessful call as a recoverable **activation denial**, not success.
3. On denied foreground activation, use a nonintrusive Windows taskbar attention signal (`FlashWindowEx`) or bounded user-requested tray feedback: **«Окно RDC Relay уже открыто. Переключитесь через Alt+Tab или панель задач.»** Rate-limit feedback. Do not steal input from fullscreen apps; do not add permanent TopMost, synthetic Alt-key presses, UI automation, focus-lock registry tweaks or process kills.
4. A verified GUI process with **no HWND** must be distinguished from a working GUI and from a dead child. Implement a bounded readiness check and explicit diagnostic status; do **not** silently return from `OpenGui()` as though the window were visible, launch another competing GUI, or force-stop an unknown process.
5. A dead owned GUI may follow the existing authenticated ticket cleanup/restart path only after identity and ownership checks. Do not change Host singleton, adoption protection, Remote version, account state or user shortcuts.
6. On an initial GUI spawn failure, report a categorized actionable startup error separate from foreground denial and preserve current Host/Remote. Do not auto-reinstall or silently switch the user back to stable.

Important Win32 guidance: [SetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow) explicitly allows OS foreground-lock refusal; [notification area guidance](https://learn.microsoft.com/en-us/windows/win32/shell/notification-area) expects tray clicks to give visible feedback.

## Acceptance and negative tests

- **Isolated fake Host/GUI Windows OS smoke** (no production Remote) for initial Owner launch, close GUI via X while Host survives, tray re-open after GUI exit, tray open of already-visible and minimized windows, secondary launcher when GUI exists, repeated rapid requests, multiple monitors/DPI, and a fullscreen foreground app.
- Demonstrate a forced/controlled **foreground refusal**: GUI remains alive and reachable by taskbar, user gets bounded visible attention feedback, no silent success and no infinite retry. Verify separately a child alive with HWND=0, a dead child and an invalid ticket.
- Exercise icon transitions and animation/static reduced-motion fallbacks without affecting authentic Remote connection, tool commands or login. Check 16/20 px on actual Windows tray before approval; validate no resource/handle growth across repeated icon swaps and GUI open/close.
- Verify no duplicate Host, GUI, Remote process; no forced stops, credential reads, registry/shortcut mutation or stable 1.5.18 changes. Test clean shutdown disposes NotifyIcon and icons exactly once.
- Run all existing safe RC1 tests + standalone Setup isolation; independent Reviewer verifies real code and a reproducible negative test, not merely static source-string assertions.
- Owner manually installs a **private RC1** for visual acceptance only after tests and explicit decision; **no public release / merge** without the existing gates.

## Current boundary

STARMER recovered on 2026-11-11. **G122 implementation is now in [Draft PR #25](https://github.com/1rubass1/RDC-Relay/pull/25):** the approved 64 PNG assets were read in place, validated, and compiled into a 29-frame, SHA-attested multi-resolution Windows ICO binary. The six Host-state icon modes and exact preview fades/pulse, static reduced-motion fallback, DPI-aware small icon selection and cached resource disposal are implemented. Live Host GUI reactivation checks exact owned identity, HWND, restore/foreground outcome and taskbar fallback. Visual **21/21**, activation **12/12**, full safe regression **54/54**, standalone Setup **19/19** all PASS. A private, **not-installed** candidate has been built in the isolated ignored `dist`. **Pending before merge or Owner install:** disposable fake Host/GUI OS smoke, independent Reviewer, and physical Windows tray visual acceptance. No main-worktree Designer edits, installed 1.5.18, live Remote, shortcuts or registry were touched.
