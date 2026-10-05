param(
    [string]$AssetsDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$icoPath = Join-Path $AssetsDir 'DesktopCommander.ico'
$sourceDir = Join-Path $AssetsDir 'IconSource'
$masterPath = Join-Path $sourceDir 'DesktopCommander-master.png'
$workDir = Join-Path $env:TEMP 'RDC_icon_build'

New-Item -ItemType Directory -Force -Path $sourceDir, $workDir | Out-Null

$Purple = [Drawing.Color]::FromArgb(255, 123, 95, 162)
$Orange = [Drawing.Color]::FromArgb(255, 191, 118, 67)
$Chip = [Drawing.Color]::FromArgb(255, 11, 11, 12)
$Face = [Drawing.Color]::FromArgb(255, 5, 4, 5)
$Edge = [Drawing.Color]::FromArgb(255, 219, 219, 221)

function New-RoundedPath {
    param([Drawing.RectangleF]$Rect, [float]$Radius)

    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $diameter = [Math]::Max(0.1, $Radius * 2.0)
    $path.AddArc($Rect.Left, $Rect.Top, $diameter, $diameter, 180, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Top, $diameter, $diameter, 270, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Rect.Left, $Rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-DOuterPath {
    param([float]$Left, [float]$CenterX, [float]$CenterY, [float]$Radius)

    $top = $CenterY - $Radius
    $bottom = $CenterY + $Radius
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.StartFigure()
    $path.AddLine($Left, $top, $CenterX, $top)
    $path.AddArc($CenterX - $Radius, $CenterY - $Radius, 2.0 * $Radius, 2.0 * $Radius, -90, 180)
    $path.AddLine($CenterX, $bottom, $Left, $bottom)
    $path.CloseFigure()
    return $path
}

function New-DRegion {
    param(
        [float]$Left,
        [float]$OuterCenterX,
        [float]$CenterY,
        [float]$OuterRadius,
        [float]$InnerLeft,
        [float]$InnerRadius
    )

    $outer = New-DOuterPath -Left $Left -CenterX $OuterCenterX -CenterY $CenterY -Radius $OuterRadius
    $inner = New-Object Drawing.Drawing2D.GraphicsPath

    try {
        $innerTop = $CenterY - $InnerRadius
        $innerBottom = $CenterY + $InnerRadius
        $inner.StartFigure()
        $inner.AddLine($InnerLeft, $innerTop, $OuterCenterX, $innerTop)
        $inner.AddArc($OuterCenterX - $InnerRadius, $CenterY - $InnerRadius, 2.0 * $InnerRadius, 2.0 * $InnerRadius, -90, 180)
        $inner.AddLine($OuterCenterX, $innerBottom, $InnerLeft, $innerBottom)
        $inner.CloseFigure()

        $region = New-Object Drawing.Region($outer)
        $region.Exclude($inner)
        return $region
    }
    finally {
        $outer.Dispose()
        $inner.Dispose()
    }
}

function New-CRegion {
    param(
        [float]$CenterX,
        [float]$CenterY,
        [float]$OuterRadius,
        [float]$InnerRadius,
        [float]$OpeningHalfAngle
    )

    $outer = New-Object Drawing.Drawing2D.GraphicsPath
    $inner = New-Object Drawing.Drawing2D.GraphicsPath
    $wedge = New-Object Drawing.Drawing2D.GraphicsPath

    try {
        $outer.AddEllipse($CenterX - $OuterRadius, $CenterY - $OuterRadius, 2.0 * $OuterRadius, 2.0 * $OuterRadius)
        $inner.AddEllipse($CenterX - $InnerRadius, $CenterY - $InnerRadius, 2.0 * $InnerRadius, 2.0 * $InnerRadius)

        $far = $OuterRadius * 3.0
        $a1 = -$OpeningHalfAngle * [Math]::PI / 180.0
        $a2 = $OpeningHalfAngle * [Math]::PI / 180.0

        $points = [Drawing.PointF[]]@(
            [Drawing.PointF]::new([single]$CenterX, [single]$CenterY),
            [Drawing.PointF]::new([single]($CenterX + $far * [Math]::Cos($a1)), [single]($CenterY + $far * [Math]::Sin($a1))),
            [Drawing.PointF]::new([single]($CenterX + $far * [Math]::Cos($a2)), [single]($CenterY + $far * [Math]::Sin($a2)))
        )
        $wedge.AddPolygon($points)

        $region = New-Object Drawing.Region($outer)
        $region.Exclude($inner)
        $region.Exclude($wedge)
        return $region
    }
    finally {
        $outer.Dispose()
        $inner.Dispose()
        $wedge.Dispose()
    }
}

function Draw-Chip {
    param(
        [Drawing.Graphics]$Graphics,
        [float]$Scale,
        [ValidateSet('full','medium','tiny')]
        [string]$Variant
    )

    if ($Variant -eq 'tiny') {
        $bodyRect = [Drawing.RectangleF]::new([single](14 * $Scale), [single](14 * $Scale), [single](228 * $Scale), [single](228 * $Scale))
        $bodyRadius = 30 * $Scale
        $innerRect = [Drawing.RectangleF]::new([single](20 * $Scale), [single](20 * $Scale), [single](216 * $Scale), [single](216 * $Scale))
        $innerRadius = 24 * $Scale
        $borderWidth = 4.0 * $Scale
    }
    else {
        $pinCount = if ($Variant -eq 'medium') { 5 } else { 6 }
        $pinWidth = if ($Variant -eq 'medium') { 14.0 } else { 12.0 }
        $pinHeight = 25.0
        $centers = if ($pinCount -eq 6) { @(68, 92, 116, 140, 164, 188) } else { @(64, 96, 128, 160, 192) }

        $pinBrush = New-Object Drawing.SolidBrush $Chip
        try {
            foreach ($cx in $centers) {
                $topRect = [Drawing.RectangleF]::new([single](($cx - $pinWidth / 2.0) * $Scale), [single](3 * $Scale), [single]($pinWidth * $Scale), [single]($pinHeight * $Scale))
                $bottomRect = [Drawing.RectangleF]::new([single](($cx - $pinWidth / 2.0) * $Scale), [single](228 * $Scale), [single]($pinWidth * $Scale), [single]($pinHeight * $Scale))
                $topPath = New-RoundedPath -Rect $topRect -Radius (2.5 * $Scale)
                $bottomPath = New-RoundedPath -Rect $bottomRect -Radius (2.5 * $Scale)

                try {
                    $Graphics.FillPath($pinBrush, $topPath)
                    $Graphics.FillPath($pinBrush, $bottomPath)
                }
                finally {
                    $topPath.Dispose()
                    $bottomPath.Dispose()
                }
            }
        }
        finally {
            $pinBrush.Dispose()
        }

        $bodyRect = [Drawing.RectangleF]::new([single](20 * $Scale), [single](24 * $Scale), [single](216 * $Scale), [single](208 * $Scale))
        $bodyRadius = 28 * $Scale
        $innerRect = [Drawing.RectangleF]::new([single](26 * $Scale), [single](30 * $Scale), [single](204 * $Scale), [single](196 * $Scale))
        $innerRadius = 22 * $Scale
        $borderWidth = if ($Variant -eq 'medium') { 3.2 * $Scale } else { 2.4 * $Scale }
    }

    $bodyPath = New-RoundedPath -Rect $bodyRect -Radius $bodyRadius
    $innerPath = New-RoundedPath -Rect $innerRect -Radius $innerRadius
    $bodyBrush = New-Object Drawing.SolidBrush $Chip
    $faceBrush = New-Object Drawing.SolidBrush $Face
    $borderPen = New-Object Drawing.Pen $Edge, $borderWidth

    try {
        $Graphics.FillPath($bodyBrush, $bodyPath)
        $Graphics.FillPath($faceBrush, $innerPath)
        $Graphics.DrawPath($borderPen, $innerPath)
    }
    finally {
        $bodyPath.Dispose()
        $innerPath.Dispose()
        $bodyBrush.Dispose()
        $faceBrush.Dispose()
        $borderPen.Dispose()
    }
}

function Draw-Monogram {
    param(
        [Drawing.Graphics]$Graphics,
        [float]$Scale,
        [ValidateSet('full','medium','tiny')]
        [string]$Variant
    )

    if ($Variant -eq 'tiny') {
        $dLeft = 33.0
        $dCenterX = 68.0
        $dOuterRadius = 72.0
        $dInnerLeft = 62.0
        $dInnerRadius = 37.0
        $cCenterX = 159.0
        $cOuterRadius = 67.0
        $cInnerRadius = 37.0
        $cOpeningHalfAngle = 45.0
        $gapWidth = 7.0
    }
    elseif ($Variant -eq 'medium') {
        $dLeft = 34.0
        $dCenterX = 69.0
        $dOuterRadius = 71.0
        $dInnerLeft = 62.0
        $dInnerRadius = 36.5
        $cCenterX = 159.0
        $cOuterRadius = 65.0
        $cInnerRadius = 36.0
        $cOpeningHalfAngle = 43.5
        $gapWidth = 6.0
    }
    else {
        $dLeft = 35.0
        $dCenterX = 69.0
        $dOuterRadius = 70.0
        $dInnerLeft = 62.0
        $dInnerRadius = 36.0
        $cCenterX = 158.0
        $cOuterRadius = 64.0
        $cInnerRadius = 36.0
        $cOpeningHalfAngle = 42.0
        $gapWidth = 5.0
    }

    $centerY = 128.0
    $dLeft *= $Scale
    $dCenterX *= $Scale
    $centerY *= $Scale
    $dOuterRadius *= $Scale
    $dInnerLeft *= $Scale
    $dInnerRadius *= $Scale
    $cCenterX *= $Scale
    $cOuterRadius *= $Scale
    $cInnerRadius *= $Scale
    $gapWidth *= $Scale

    $cRegion = New-CRegion -CenterX $cCenterX -CenterY $centerY -OuterRadius $cOuterRadius -InnerRadius $cInnerRadius -OpeningHalfAngle $cOpeningHalfAngle
    $orangeBrush = New-Object Drawing.SolidBrush $Orange
    try {
        $Graphics.FillRegion($orangeBrush, $cRegion)
    }
    finally {
        $cRegion.Dispose()
        $orangeBrush.Dispose()
    }

    $dOuter = New-DOuterPath -Left $dLeft -CenterX $dCenterX -CenterY $centerY -Radius $dOuterRadius
    $maskBrush = New-Object Drawing.SolidBrush $Face
    $gapPen = New-Object Drawing.Pen $Face, $gapWidth
    try {
        $gapPen.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
        $Graphics.FillPath($maskBrush, $dOuter)
        $Graphics.DrawPath($gapPen, $dOuter)
    }
    finally {
        $dOuter.Dispose()
        $maskBrush.Dispose()
        $gapPen.Dispose()
    }

    $dRegion = New-DRegion -Left $dLeft -OuterCenterX $dCenterX -CenterY $centerY -OuterRadius $dOuterRadius -InnerLeft $dInnerLeft -InnerRadius $dInnerRadius
    $purpleBrush = New-Object Drawing.SolidBrush $Purple
    try {
        $Graphics.FillRegion($purpleBrush, $dRegion)
    }
    finally {
        $dRegion.Dispose()
        $purpleBrush.Dispose()
    }
}

function Render-VectorIcon {
    param(
        [ValidateSet('full','medium','tiny')]
        [string]$Variant,
        [int]$CanvasSize,
        [string]$OutputPng
    )

    $bmp = [Drawing.Bitmap]::new($CanvasSize, $CanvasSize, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [Drawing.Graphics]::FromImage($bmp)
        try {
            $g.Clear([Drawing.Color]::Transparent)
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
            $scale = $CanvasSize / 256.0
            Draw-Chip -Graphics $g -Scale $scale -Variant $Variant
            Draw-Monogram -Graphics $g -Scale $scale -Variant $Variant
        }
        finally {
            $g.Dispose()
        }
        $bmp.Save($OutputPng, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bmp.Dispose()
    }
}

function Resize-Png {
    param([string]$InputPng, [int]$Size, [string]$OutputPng)

    $src = [Drawing.Bitmap]::FromFile($InputPng)
    try {
        $dst = [Drawing.Bitmap]::new($Size, $Size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $g = [Drawing.Graphics]::FromImage($dst)
            try {
                $g.Clear([Drawing.Color]::Transparent)
                $g.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceOver
                $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.DrawImage($src, (New-Object Drawing.Rectangle 0, 0, $Size, $Size))
            }
            finally {
                $g.Dispose()
            }
            $dst.Save($OutputPng, [Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $dst.Dispose()
        }
    }
    finally {
        $src.Dispose()
    }
}

function Write-IcoFromPngs {
    param([string[]]$PngFiles, [int[]]$Sizes, [string]$OutputIco)

    if ($PngFiles.Count -ne $Sizes.Count) {
        throw 'PNG file count must match size count.'
    }

    $payloads = @()
    foreach ($file in $PngFiles) {
        $payloads += ,([IO.File]::ReadAllBytes($file))
    }

    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter $stream
    try {
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$PngFiles.Count)
        $offset = 6 + (16 * $PngFiles.Count)

        for ($i = 0; $i -lt $PngFiles.Count; $i++) {
            $size = $Sizes[$i]
            $dim = if ($size -eq 256) { 0 } else { $size }
            $writer.Write([Byte]$dim)
            $writer.Write([Byte]$dim)
            $writer.Write([Byte]0)
            $writer.Write([Byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$payloads[$i].Length)
            $writer.Write([UInt32]$offset)
            $offset += $payloads[$i].Length
        }

        foreach ($payload in $payloads) {
            $writer.Write($payload)
        }

        $writer.Flush()
        [IO.File]::WriteAllBytes($OutputIco, $stream.ToArray())
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

Render-VectorIcon -Variant full -CanvasSize 1024 -OutputPng $masterPath

$sizes = @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
$pngs = @()

foreach ($size in $sizes) {
    if ($size -le 24) {
        $variant = 'tiny'
    }
    elseif ($size -le 40) {
        $variant = 'medium'
    }
    else {
        $variant = 'full'
    }

    $rendered = Join-Path $workDir ("DesktopCommander_{0}_{1}_render.png" -f $size, $variant)
    $png = Join-Path $workDir ("DesktopCommander_{0}.png" -f $size)
    Render-VectorIcon -Variant $variant -CanvasSize 1024 -OutputPng $rendered
    Resize-Png -InputPng $rendered -Size $size -OutputPng $png
    $pngs += $png
}

Write-IcoFromPngs -PngFiles $pngs -Sizes $sizes -OutputIco $icoPath

Write-Output 'Geometry:'
Write-Output '  D outer: exact semicircle + straight stem'
Write-Output '  D counter: exact semicircle + straight stem'
Write-Output '  C: concentric outer/inner circles with a radial wedge removed'
Write-Output '  Full monogram bounds: X=35..222, Y=58..198, center=(128.5,128)'
Write-Output '  Chip body center: (128,128)'
Write-Output ''
Write-Output "Master: $masterPath"
Write-Output "ICO:    $icoPath"

foreach ($i in 0..($sizes.Count - 1)) {
    Write-Output ("{0,3}px: {1}" -f $sizes[$i], $pngs[$i])
}
