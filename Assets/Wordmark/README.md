# Desktop Commander wordmark
Reference: project-owner design asset rdc-banner.png, 997 x 74 px.
Approved palette: DESKTOP #BF7643, COMMANDER #7B5FA2, top #DCDCDC.
The SVG is a pixel-grid reconstruction of the supplied bitmap, not an
original font outline. Transparent background and discrete coverage levels
remove the reference's RGB subpixel fringes. PNG variants are produced
from the same reconstructed geometry at 96/120/144/168/192 DPI.
The Owner GUI embeds all five variants in its existing manifest-hashed
remote-window.ps1, selects the smallest source that covers the target
pixel width, and paints a graphic within the shared header scroll viewport.
No runtime image decoder package or SVG dependency is downloaded.
Regenerate with Scripts/Generate-RdcWordmark.ps1 -Reference <reference.png>
-Output <Assets/Wordmark>. Synchronize the five embedded PNG strings in
Source/remote-window.ps1 (RDC_WORDMARK_RESOURCES markers) after regenerating.
Tests/Test-V160Wordmark.ps1 verifies byte equality and paint/geometry.