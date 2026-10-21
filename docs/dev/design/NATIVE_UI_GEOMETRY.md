> **LEGACY IMPORT, not current instructions.** Source: Design\README.md from STARMER before Playbook migration (2026-10-22). This document preserves historical research or decisions, may contain superseded instructions/versions, and is not a production requirement by itself. Refer first to repository PROJECT_INDEX.md, PROJECT_CONTEXT.md, COORDINATION/BOARD.md and current planning. Sensitive IDs are redacted in the Git copy; byte-exact historical original is preserved only in STARMER local archive.
# RDC Relay — Pen UI coordinate reference

Native design source: installed RDC Relay v1.5.18 on STARMER, Windows window 1074 × 900 px at 96 DPI, with a separate isolated -Preview showing the final expanded update state. Reference PNGs were captured at native resolution, without resizing the source. Pen text rasterization is not identical to Windows/Segoe UI. Dynamic log entries and account names are placeholders.

Edit `RDC-Relay-UI-Layout.pen` **inside Pen** using the already configured Pencil MCP plugin or Pen UI. Keep `rdc-banner.png` next to the design; it is a standalone original pixel-art layer. The `RDC-Relay-Layout-Preview.png` is just a static export, not the editable source.

Coordinates below are absolute relative to the 1074 × 900 application-window screenshot; 0,0 is the upper-left pixel of the outer window.

| Element | X | Y | W | H | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| OS title bar | 0 | 0 | 1074 | 32 | native active-blue bar |
| Header content | 7 | 32 | 1060 | 77 | status/title/actions |
| Account button | 754 | 52 | 119 | 36 | x/y from screenshot; native control is 120×36 |
| Account down triangle | 836 | 68 | 6 | 4 | *filled*, not a V-shaped chevron |
| Help circular outline | 880 | 54 | 32 | 32 | outer widget is 36×36 |
| Stop button | 930 | 52 | 119 | 36 | 9×9 filled stop glyph |
| Header bottom purple line | 7 | 108 | 1060 | 1 | #7B5FA2 |
| Main terminal | 7 | 110 | 1060 | 612 | actual background RGB (18,20,23) |
| Logo artwork | 10 | 124 | 997 | 74 | separate original pixel image |
| Splitter top/lower lines | 7 | 722 / 728 | 1060 | 1 | static, no effects; 7px overall |
| Activity pane | 7 | 729 | 1060 | 123 | logs are samples |
| Footer | 7 | 854 | 1060 | 39 | expanded update animation final state |
| Installed version | ~601 | ~860 | — | 23 | subdued gray |
| Footer update arrow | ~647 | ~872 | ~14 | ~8 | static rightward vector |
| Update button | 673 | 862 | 84 | 21 | #EBB857 border/text |
| Main scrollbar top arrow | 1054 | 115 | 8 | 5 | gray triangle |
| Main scrollbar bottom arrow | 1054 | 712 | 8 | 5 | gray triangle |
| Activity scrollbar top arrow | 1054 | 735 | 8 | 5 | gray triangle |
| Activity scrollbar bottom arrow | 1054 | 828 | 8 | 5 | gray triangle |
| Activity horizontal thumb (visible orange) | ~28 | ~840 | ~215 | ~12 | native scroll data varies |
| Activity resize grip | 1050 | 835 | 17 | 17 | three diagonal amber lines |

Vertical and horizontal custom scrollbars use a **17px control thickness** and **16px arrow end zones**. The source code is the authority for exact arrow triangles:
- Vertical: top vertices `(Width/2,5)`, `(Width/2-4,10)`, `(Width/2+4,10)`; bottom symmetric at `Height-5 / Height-10`.
- Horizontal: left `(5,Height/2)`, `(10,Height/2-4)`, `(10,Height/2+4)`; right symmetric at `Width-5 / Width-10`.
- Resize grip (within 17×17 lower-right corner): lines from (10,15)→(15,10), (6,15)→(15,6), and (2,15)→(15,2), stroke 1.4px.

Native key colors, sampled or verified from the implementation: background `#1D2024`, log surface `#121417`, scroll track `#323438`, orange thumb and action outlines `#BF7643`, muted arrow `#707378`, divider lines `#7B5FA2`, update button gold `#EBB857`.

All arrows, scrollbar handles, buttons, separators and resize grip are editable named Pen nodes; no motion or shader animation is recreated in the design. Pixel-level comparisons were made against native 1074×900 screenshots; exact typography/antialiasing and live changing scrollbar positions are not guaranteed to match across renderers.
