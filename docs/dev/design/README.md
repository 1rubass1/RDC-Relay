# RDC Relay — editable UI reference (development only)

**Pen source:** `RDC-Relay-UI-Layout.pen`; corresponding resource: `RDC-Relay-UI-Layout-assets/rdc-banner.png`.
**Preview:** `RDC-Relay-Layout-Preview.png`.
**Measured pixel geometry and color tokens:** [NATIVE_UI_GEOMETRY.md](NATIVE_UI_GEOMETRY.md).

Design represents v1.5.18 at 1074×900 / 96 DPI, showing a static expanded update-notice state, editable controls, and non-secret representative placeholders. It is not the compiled UI. Two email-like account labels in the public Git copy were replaced with `ACCOUNT-PLACEHOLDER`; the original editable Pen file is backed up only on STARMER outside Git. The 2026-10-21 technical alignment of six scrollbar arrows, account chevron, footer and resize corner did not establish **human visual acceptance**.

Designer manages editable Pen UX/visual source and asks the user to evaluate significant subjective changes; Programmer implements and tests the real UI. Use focused captures for concrete rendering defects, not large numbers of screenshots.

Do not include Pen or these assets in Setup, Portable ZIP, runtime manifest or release artifacts.
