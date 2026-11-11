# G108 — Owner account-switch confirmation instruction and typographic emphasis

**Date:** 2026-11-11. **Status:** Programmer candidate source; independent Reviewer and owner visual acceptance pending. Installed RC1, Host and Remote not modified.

## Owner-approved copy

**Dialog title:** `Смена аккаунта Desktop Commander`

First paragraph **bold**:
> Сначала откройте сайт Desktop Commander и войдите в аккаунт, на который хотите переключиться.

Then regular text, no headings:
> Смена аккаунта разорвёт текущее соединение и отзовёт авторизацию этого устройства.

> После выхода из аккаунта RDC Relay запустит новый Remote и начнёт процедуру авторизации устройства.

> Продолжить смену аккаунта?

Buttons: **Да / Нет**. No "Перед началом процедуры", "Внимание!", "удалённое", or old third paragraph about a ChatGPT-linked account. There is no extra browser logout instruction.

## Implementation and safety

- `Source/remote-window.ps1`: only the Owner GUI's existing checked `$switchAccountItem.Add_Click` handler changes its visual confirmation from a monolithic MessageBox to `Show-RdcOwnerAccountSwitchConfirmation`, using a custom WinForms form built by `New-RdcOwnerAccountSwitchDialog`. Standard `MessageBox` cannot make just one sentence bold. Four auto-sized paragraphs use Segoe UI 10pt and one first-label bold font, matching the existing dark WinForms owner palette, centered fixed modal, dark buttons.
- **Cancel/deny safety:** AcceptButton **and** CancelButton are the **Нет** button; close/Esc/Enter cannot accidentally accept a destructive action. Only an explicit **Да** returns `DialogResult.Yes`. The original conditions `$script:ownerManagedMode` and `$script:ownerCanSwitchAccount`, the owner-only `SWITCH_ACCOUNT` queue, one-shot disabled menu item, and Host-side authenticated capability/owned Job/logout checks are unchanged.
- The old *legacy* 1.5.18 warning/function `Switch-RemoteAccount` is intentionally not modified; only the new Host-owned RC1 flow uses the edited message. No real Remote/Host/browser, quota or updater actions were executed. The installed candidate remains untouched.

## Bounded verification

**Verified on STARMER (2026-11-11):** real Owner dialog and mocked click flow **17/17 PASS**, existing account switch fake-only tests PASS, full safe regression **44/44 PASS** (exit 0), full Setup standalone inspection/extraction **19/19 PASS** (exit 0), full Setup/Portable build **21 SHA-verified members**. No actual installation.

### Staged Desktop G108

- `RDC-Relay-1.6.0-RC1-AccountSwitchDialog-Setup.exe` SHA256 `21F53A8B4461FE7D5208FB9CDA2BF994AA62442426FB3B385C8A5E94F9A74FD5`.
- `RDC-Relay-1.6.0-RC1-AccountSwitchDialog-Portable.zip` SHA256 `65A93552C488F466230EA47C936299DC0BE0F7B86B50A4CC12069A2A0BCE2BA7`.

G107 `RealUpdateOnly` Setup/Portable moved only after SHA checks to `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G108_Superseded_RealUpdateOnly`; stable 1.5.18 rollback Setup SHA verified and preserved. Both new Desktop files re-hashed after copying.

- `Tests/Test-V16OwnerAccountSwitchDialog.ps1`: parses actual GUI and extracts product dialog functions and actual click handler; tests exact title, all four user-approved phrases/order, bold on first paragraph only, dark palette, layout, explicit Да/Нет plus both keyboard defaults to Нет; mocked clicks confirm No never queues logout, Yes queues existing Host verb, and missing Host capability blocks confirmation. Uses disposable WinForms controls; no network/Remote.
- `Tests/Test-V16OwnerAccountSwitch.ps1`: existing fake-only managed-account switch test, including exact pinned logout and negative failure.
- `Tests/Invoke-V16Rc1SafeRegression.ps1`: complete safe suite includes new dialog test.
- `Tests/Test-V16StandaloneSetup.ps1`: self-contained Setup manifest/extraction, not installation.
- `Scripts/build-rc1-full.ps1 -Build`: private Setup and Portable only, no installed app/Remote impact.

**NOT CHECKED:** owner's on-screen modal at exact monitor DPI, actual Host logout sequence/live account switch (not authorized by this UI edit). Independent Reviewer + owner visual approval required; PR #23 stays Draft and no release/stable updater publication.
