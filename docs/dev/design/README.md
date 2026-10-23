# RDC Relay — editable UI reference (development only)

**Pen source:** `RDC-Relay-UI-Layout.pen`; corresponding resource: `RDC-Relay-UI-Layout-assets/rdc-banner.png`.
**Preview:** `RDC-Relay-Layout-Preview.png`.
**Measured pixel geometry and color tokens:** [NATIVE_UI_GEOMETRY.md](NATIVE_UI_GEOMETRY.md).

Design represents v1.5.18 at 1074×900 / 96 DPI, showing a static expanded update-notice state, editable controls, and non-secret representative placeholders. It is not the compiled UI. Two email-like account labels in the public Git copy were replaced with `ACCOUNT-PLACEHOLDER`; the original editable Pen file is backed up only on STARMER outside Git. The 2026-10-21 technical alignment of six scrollbar arrows, account chevron, footer and resize corner did not establish **human visual acceptance**.

Designer manages editable Pen UX/visual source and asks the user to evaluate significant subjective changes; Programmer implements and tests the real UI. Use focused captures for concrete rendering defects, not large numbers of screenshots.

Do not include Pen or these assets in Setup, Portable ZIP, runtime manifest or release artifacts.

## DES-002 — future application/shortcut/tray icon (queued, not assigned)

The owner dislikes the present icon: it does not communicate what RDC Relay does. This is a **backlog intake, not an approved design brief**. Later, Designer and owner should agree on the central visual metaphor (Remote, relay/bridge, continuous connection), relevant platforms (desktop shortcut, application window, notification tray, installer), alternatives, deliverables, ownership of editable source and user acceptance. Do not edit the present ICO, Pen, installer or live app now.

**Contrast and legibility to discuss later:** follow Microsoft [Windows app icon design guidelines](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-design) and [Fluent 2 iconography](https://fluent2.microsoft.design/iconography/); compare at actual 16/24/32/48 px on Windows light/dark/colored backgrounds, use recognizable silhouette as well as color, and test a high-contrast/monochrome alternative. Microsoft suggests that at least half an app icon reach roughly 3:1 contrast in light and dark themes; this is **design input**, not evidence that the current icon passes or a preselected palette. Actual creative specification and Designer launch require a separate owner discussion. Track status in [coordination board](../../../COORDINATION/BOARD.md).
