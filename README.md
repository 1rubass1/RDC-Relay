# RDC Relay

RDC Relay is a Windows GUI launcher and monitor for
`@wonderwhy-er/desktop-commander` Remote mode.

RDC Relay is an independent companion shell. It is not the upstream
`desktop-commander/remote-desktop-commander` project.

It keeps the Desktop Commander remote process hidden, shows connection/device
information and recent tool activity, and provides restart, logout and account
management actions.

## Requirements

- Windows 10/11
- Windows PowerShell 5.1
- Node.js 18 or newer
- The computer and ChatGPT must use the same Desktop Commander account

The launcher currently pins Desktop Commander to **0.2.52** so a new upstream
release cannot silently change the log protocol underneath an existing RDC Relay
release.

## Install

For a normal Windows installation, open **[GitHub Releases](https://github.com/1rubass1/RDC-Relay/releases/latest)**, download the latest
`RDC Relay Setup vX.Y.Z.exe` and run it. No source-code files are required.

The installer writes the application to:

`%LOCALAPPDATA%\RemoteDesktopCommanderLauncher`

The fixed per-user location intentionally avoids an administrator/UAC prompt and
keeps in-place updates predictable. RDC Relay is registered in **Settings -> Apps
-> Installed apps**, where it can be uninstalled normally. The installer also
creates `RDC Relay` Desktop/Start Menu shortcuts for the current user and removes
legacy `Remote Desktop Commander` shortcuts.

For portable use, download `RDC Relay vX.Y.Z Portable.zip`, extract its single
folder anywhere (for example to the Desktop), then double-click `RDC Relay.exe`.
The supporting runtime files remain in the same folder; no installation is
registered for portable copies.

## First launch on another Windows PC

1. Install Node.js 18+ and RDC Relay, then launch **RDC Relay**.
2. RDC Relay launches the pinned Desktop Commander Remote itself, via
   `npx.cmd`. **Do not copy the terminal command from the website**.
3. On first pairing, the upstream OAuth device flow opens a browser.
   Compare the one-time code shown in RDC Relay's startup log and approve
   the new device in the browser. If the browser does not open, choose
   **Account → Confirm new device** (official verification page).
4. Later launches reuse the authorized local session unless revoked.

The one-time browser approval is mandatory: RDC Relay does not impersonate
the user, silently approve devices, or store passwords/tokens.
The startup supervisor retries when npm reports a missing `package.json`
inside a partial `npm-cache\_npx` entry. It removes **only the identified
damaged cache entry**; it never clears the entire cache or requires
changing PowerShell execution policy.

## Repository layout

- `Source/` — runtime PowerShell, compiled WPF pixel shaders and HLSL sources
- `Assets/` — application icon source and icon build script
- `Installer/` — source for the small .NET Framework installer
- `Scripts/build-shaders.ps1` — reproducible HLSL -> ps_3_0 compiler
- `Scripts/build-release.ps1` — manifest, self-test, installer and portable ZIP build

Generated release binaries are written to `dist/` and are intentionally not
tracked by Git.

## Development review rules

### Visual UI changes

For changes to UI layout, animations, motion, or visual feedback, run an
isolated interactive preview and **ask the user to review the actual result**
before treating the appearance as accepted. Preserve any running production
Remote session and keep the preview non-destructive.

**Prefer direct user review over bulk screenshot collection.** Do not
routinely capture dozens of screenshots or animation frames to assess
appearance. Use a small number of targeted captures only when necessary to
diagnose a specific rendering problem or validate a concrete regression;
explain why if extensive frame capture is genuinely required. Automated
tests remain mandatory where applicable, but do not replace user visual
acceptance.

## Build a release

From the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Scripts\build-release.ps1
```

The build:

1. recompiles the HLSL shaders with `d3dcompiler_47.dll`;
2. synchronizes the runtime icon;
3. regenerates `Source/update-manifest.json` with SHA256 hashes;
4. runs the GUI self-test;
5. builds the Setup EXE;
6. builds a portable ZIP and `release-info.json`.

## Update channel

Released clients update from the **`stable`** branch of
`1rubass1/RDC-Relay`, not from moving development work on `main`.

Release procedure:

1. prepare and test the release on a release branch;
2. fast-forward `main`;
3. point `stable` at the same tested commit;
4. create tag `vX.Y.Z`;
5. publish the generated files from `dist/vX.Y.Z/`.

The updater resolves `stable` to an immutable Git commit before downloading
the manifest and payload. Payload files are SHA256-verified, backed up before
replacement, and same-version installations can self-repair missing or damaged
files.

The repository must be publicly readable for the unauthenticated updater to
reach GitHub.

### In-session update notifications

The original automatic update/repair check **at application launch is retained**.
When RDC Relay stays open, a separate nonblocking background check runs against
the same immutable `stable` commit and manifest roughly every hour. A newer
stable version triggers a staged footer microinteraction: installed version
moves left, an arrow in the same muted gray as the informational text slides
out from behind the orange separator, and a neutral-gray button with a thick,
rounded gold border and bold gold version text fades in. Clicking the button
invokes the existing transactional `update.ps1 -Force` and restarts RDC Relay
after success.

The code lives in `Source/update-notice.ps1`. To **revert only this optional
feature during development**, set `$script:enableUpdateNotice = $false` near
the beginning of `Source/remote-window.ps1` and regenerate the manifest for a
new candidate build. When enabled, one persistent 25-pixel footer renderer is
used for both idle and animated states: neither the font nor the informational
text control is replaced during the transition. When disabled, the original
footer controls remain in place and no hourly requests are made. The old
automatic startup updater still operates.

`-Preview` replays a synthetic next-patch-version notification about every
7 seconds, with a short initial pause so the movement can actually be observed.
The repeating animation is **preview-only**: in production the notification
animates exactly once per newly discovered version. Preview never calls GitHub
or performs an update.

## Runtime notes

- A second launcher instance exits without activating the existing window.
- The GUI only adopts a pre-existing remote process when its command line
  points at this installation's own `remote-session.log`.
- The GPU divider effect is decorative. If shader initialization fails, the
  normal static divider remains functional.
- Decorative GPU animation pauses while the window is hidden, minimized or
  fully covered by other top-level windows; status and log polling continue.
- During pane resizing the overflow GPU popup is suspended to avoid layered
  window trails and layout updates are coalesced to display-frame cadence.
- Update checks and remote stop/restart/logout operations are polled without
  blocking the window. Closing waits for an in-progress operation to finish.
- Portable copies only refresh shortcuts already pointing to that same copy.
- The installer refuses to replace an active GUI, serializes payload writes
  with the updater, and restores the previous payload after a failed install.

## Local release candidates

A locally installed review candidate can use `.local-candidate.json` containing
`version` and `runtimeSha256` (the SHA256 of its `remote-window.ps1`). Matching
candidates skip automatic updates so same-version stable repair cannot overwrite
unpublished changes. Remove this marker after accepting/publishing the candidate
to return to the normal stable channel. A normal successful Setup installation
also removes it; `update.ps1 -Force` explicitly overrides it.

Run the focused regression checks after building a release:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Test-Transactions.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Test-UiLifecycle.ps1
```

They use isolated payloads and fake process handles, without stopping the live
Desktop Commander server or logging out of the user's account.

## Security

No credentials or Desktop Commander authentication tokens are stored in this
repository.

The update transport uses HTTPS and payload hashes. Releases are currently not
code-signed, so SHA256 verification protects against corruption/mismatched
payloads but is not a substitute for publisher code signing.

Desktop Commander Remote itself may trigger behavior-based antivirus/EDR alerts
because it can execute user-authorized local commands. Kaspersky has an upstream
false-positive report for the official `@wonderwhy-er/desktop-commander` npm
entrypoint used by Remote mode. RDC Relay does not bundle that JavaScript file;
it is obtained from the official npm package by `npx`. Do not disable antivirus
or add blanket exclusions solely to run RDC Relay.
