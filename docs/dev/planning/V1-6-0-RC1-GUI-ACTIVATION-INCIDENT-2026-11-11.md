# 2026-11-11 incident — GUI seems absent after G121 and stable rollback

**Status: diagnosed partially / no code fix or installed mutation; owner-visible acceptance pending.** Safety scope: read-only Windows/session inspection and disposable preview/isolated SelfTest only. No live Remote, persistent Host, installed GUI, primary shortcut, registry, credentials, tray or published release changed.

## Report

Owner reported no RDC Relay GUI when opening from the 1.6.0 RC1 G121 tray, after reinstall, and even after rolling the primary Desktop shortcut back to stable 1.5.18. Owner kept 1.5.18 installed to preserve working access.

## Confirmed on STARMER

- The primary Desktop `RDC Relay.lnk` was correctly restored to stable `LocalAppData/RemoteDesktopCommanderLauncher/remote-window.ps1` under `powershell.exe`, with stable 1.5.18 icon and no unexpected argument. The script exists, contains the stable version, and PowerShell AST parsing reports zero errors.
- Node.js, npm and `npx.cmd` are present in the normal path; the current stable `remote-session.log` was empty when read. Its previous log had standard MCP startup lines, not a conclusive GUI error.
- **The stable GUI was already alive** in the logged-in interactive console session after rollback. It owned the expected single-instance mutex and had an actual `RDC Relay` top-level window. The window was `IsWindowVisible=true`, `IsWindowEnabled=true`, `IsIconic=false`, `DwmGetWindowAttribute(DWMWA_CLOAKED)=0`, and its normal rectangle was entirely inside the primary monitor. There was no evidence of a stable GUI crash, absent HWND, offscreen placement, or minimized state.
- When checked, the foreground belonged to a full-screen application; the stable GUI was deep below it in the window Z-order. That foreground application was started *after* the first G121 attempt, so it cannot by itself prove the initial G121 root cause. It does establish why the stable window was not currently observable and why starting a second copy did not produce another window.
- A **read-only installed stable file clone** passed `-SelfTest -SkipUpdate`, exit 0. A disposable copy of stable opened a real WinForms `-Preview` window with a nonzero HWND, then closed. A disposable copy of G121's packaged GUI source also opened a real WinForms `-Preview` window, without stderr and without launching Remote/Host, then closed. Thus there is no unconditional UI constructor crash in the legacy/preview G121 path.
- The real G121 **OwnerGui + authenticated Host/tray path** was NOT replayed after the owner rolled back. Its original failure cause remains unproven. Do not claim that the full Owner GUI session was validated by preview.

## Confirmed implementation deficiency common to stable and RC1

- Stable 1.5.18's duplicate-launch handler calls `ShowWindow(existing, SW_RESTORE)` then `SetForegroundWindow(existing)` but discards the activation result; the new launcher silently exits. This can look like 'nothing happened' when foreground activation is denied.
- In `Source/RdcOwnerRuntime.cs`, RC1 `OpenGui()` performs the same `ShowWindow` / `SetForegroundWindow` calls without checking whether they succeed. If a GUI process object still exists, it returns immediately even when `MainWindowHandle` is zero or the already-created window is behind another fullscreen application. Tray UI gives no visible fallback in that branch.
- This behavior is consistent with Microsoft Win32 foreground activation restrictions: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow . `FlashWindowEx` is the supported nonintrusive fallback to request attention: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-flashwindowex .

## Corrective work recommended to the parallel tray/Host owner (NOT implemented here)

1. Handle an explicit user **Open GUI** request as a visibility/activation result, not merely a process-alive check. Verify HWND, actual visibility, current monitor and minimized/cloaked state. Restore when appropriate without killing an owned GUI or changing Remote.
2. Check the return from `SetForegroundWindow`. If Windows denies focus, emit an actionable taskbar flash/notification or a visible menu explanation without stealing focus from a fullscreen program. Avoid permanent TOPMOST, process termination, sleep hacks or Alt-key injection as a silent workaround.
3. If a child is still live but has no HWND, use a bounded non-destructive readiness check and expose a categorized diagnostics status. No duplicate Host, no unverified force kill.
4. Add isolated full Owner ticket/Host/GUI/tray OS smoke scenarios to cover close/reopen, fullscreen app foreground, initial GUI not ready, update/install activation and stable rollback. The existing source/standalone Setup and preview tests do not establish end-to-end OS visibility.
5. Do not change installed stable 1.5.18, current Host/Remote, user shortcuts, registry or public feed until the owner explicitly approves an installation/test.

## Immediate user workaround

Use `Alt+Tab` or the taskbar to select the already-running **RDC Relay** window after leaving fullscreen mode. Do not repeatedly reinstall or stop Remote merely because the existing GUI is behind another application. If it cannot be selected, collect a fresh read-only HWND/foreground/mutex snapshot before taking action.

## Limits

Observed stable Window HWND/visibility and G121 preview are strong evidence against a generic failure to create GUI. **They do not prove** the earlier G121 Owner launch succeeded or establish the exact failure time/path; the Owner Host's protected ticketed run-state was intentionally not accessed, and no intrusive OS smoke was performed.
