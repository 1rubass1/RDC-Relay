# G100 — Owner update button outer height +1 px, caption unchanged

**Date:** 2026-11-10. **Status:** Programmer candidate staged; independent review / owner visual acceptance required. **NOT INSTALLED** by Programmer.

## Owner request and scope

The current RC1 Owner expanding update notice was visually accepted in animation, vertical positioning and caption alignment. Owner requested the **button itself** be one pixel taller, without shifting its text. No other footer, font, color, motion, timing, label, click or tooltip change authorized.

## Implementation

The pre-existing painted button rectangle at 25px footer height was `Y=2, Height=21, Bottom=23`. In `Source/update-notice.ps1`, the **Owner-only compact mode** now draws its surrounding button surface and border at `Y=1, Height=22, Bottom=23`: only its **top edge extends 1px upward**, with the bottom edge stationary. The original `textBounds` remains at `Y=2, Height=21`, and the text still uses the original bold Segoe UI 9.5 font, text center alignment and unchanged label. Input hit-testing, hover and focus follow the updated `buttonBounds` so there is no discrepancy between visible shape and click target. The legacy non-Owner update button stays at `Y=2, Height=21`. The 25px footer, animation easing/durations, colors and full GUI window geometry are unchanged.

The Owner update demo remains visual-preview-only; this build neither installs an update nor triggers any network call without a separate user action in a supported mode.

## STARMER evidence

| Verification | Result | Limit |
| --- | --- | --- |
| `Tests/Test-V16OwnerUpdateDemo.ps1` | **12/12 PASS** | Actual disposable WinForms button renderer, reflected Owner `buttonBounds` Y1/H22/B23, original caption draw rectangle and font, legacy Y2/H21, idle/animated bitmap gold output, preview-only security |
| `Tests/Invoke-V16Rc1SafeRegression.ps1` | **39/39 PASS**, exit 0 | Existing bounded static/mock/compile regressions including G96 account switching, G98 emoji, G99 journal |
| `Tests/Test-V16StandaloneSetup.ps1` | **19/19 PASS**, exit 0 | Standalone Setup manifest extraction, safe launch route; no installation |
| `Scripts/build-rc1-full.ps1 -Build` | **21 verified package members** | Setup/Portable staged; not installed |

STARMER Desktop:
- `RDC-Relay-1.6.0-RC1-UpdateButton1px-Setup.exe` — SHA256 `DC4888952765B459B8A752E900FB346AE49887746F399FDBBB465797ABD74C3F`.
- `RDC-Relay-1.6.0-RC1-UpdateButton1px-Portable.zip` — SHA256 `BAA639EE723A1FC57596346032A5C02D278D70260AC4330E7628F8B5BEB11513`.

Previous G99 `JournalGap` Setup and Portable were hash-checked and archived without deletion under `Desktop/RemoteDesktopCommander/Old_Installers_2026-11-10/G100_Superseded_JournalGap/`. Stable v1.5.18 rollback was verified and remains on Desktop.

## Gate

**NOT CHECKED:** user-installed visual perception of the 1px outline adjustment on the target monitor; other DPI factors. Independently review and let owner install/accept the actual display. No running Remote/Host/GUI, credentials, account, installed app, updater, public release channels or stable rollback changed.
