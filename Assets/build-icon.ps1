param(
    [string]$AssetsDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$icoPath = Join-Path $AssetsDir 'RDCRelay.ico'
$sourceDir = Join-Path $AssetsDir 'IconSource'
$masterPath = Join-Path $sourceDir 'RDCRelay-master.png'
$workDir = Join-Path $env:TEMP 'RDCRelay_icon_build'

New-Item -ItemType Directory -Force -Path $sourceDir, $workDir | Out-Null

$White = [Drawing.Color]::FromArgb(255,255,255,255)
$BadgeEdge = [Drawing.Color]::FromArgb(255,220,222,226)
$BadgeShadow = [Drawing.Color]::FromArgb(38,0,0,0)
$Navy = [Drawing.Color]::FromArgb(255,28,34,71)
$Navy2 = [Drawing.Color]::FromArgb(255,48,55,91)
$ScreenColor = [Drawing.Color]::FromArgb(255,45,55,91)
$Lavender = [Drawing.Color]::FromArgb(255,211,219,250)
$Purple = [Drawing.Color]::FromArgb(255,94,73,239)
$Purple2 = [Drawing.Color]::FromArgb(255,112,82,246)
$Orange = [Drawing.Color]::FromArgb(255,246,119,55)
$Orange2 = [Drawing.Color]::FromArgb(255,255,172,91)
$TextDark = [Drawing.Color]::FromArgb(255,30,35,70)

function New-RoundedPath {
    param([Drawing.RectangleF]$Rect,[float]$Radius)

    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $d = [Math]::Max(0.1,$Radius * 2.0)
    $path.AddArc($Rect.Left,$Rect.Top,$d,$d,180,90)
    $path.AddArc($Rect.Right-$d,$Rect.Top,$d,$d,270,90)
    $path.AddArc($Rect.Right-$d,$Rect.Bottom-$d,$d,$d,0,90)
    $path.AddArc($Rect.Left,$Rect.Bottom-$d,$d,$d,90,90)
    $path.CloseFigure()
    return $path
}

function Fill-RoundedRect {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.RectangleF]$Rect,
        [float]$Radius,
        [Drawing.Color]$Color
    )

    $path = New-RoundedPath -Rect $Rect -Radius $Radius
    $brush = New-Object Drawing.SolidBrush $Color
    try { $Graphics.FillPath($brush,$path) }
    finally { $brush.Dispose(); $path.Dispose() }
}

function Fill-GradientRoundedRect {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.RectangleF]$Rect,
        [float]$Radius,
        [Drawing.Color]$Start,
        [Drawing.Color]$End,
        [float]$Angle = 0
    )

    $path = New-RoundedPath -Rect $Rect -Radius $Radius
    $brush = New-Object Drawing.Drawing2D.LinearGradientBrush($Rect,$Start,$End,$Angle)
    try { $Graphics.FillPath($brush,$path) }
    finally { $brush.Dispose(); $path.Dispose() }
}

function Stroke-RoundedRect {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.RectangleF]$Rect,
        [float]$Radius,
        [Drawing.Color]$Color,
        [float]$Width
    )

    $path = New-RoundedPath -Rect $Rect -Radius $Radius
    $pen = New-Object Drawing.Pen $Color,$Width
    try {
        $pen.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
        $Graphics.DrawPath($pen,$path)
    }
    finally { $pen.Dispose(); $path.Dispose() }
}

function Draw-TextGradient {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$Text,
        [Drawing.RectangleF]$Bounds,
        [float]$EmSize
    )

    $family = New-Object Drawing.FontFamily 'Segoe UI'
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $format = [Drawing.StringFormat]::GenericDefault
    try {
        $path.AddString(
            $Text,
            $family,
            [int][Drawing.FontStyle]::Bold,
            $EmSize,
            [Drawing.PointF]::new(0,0),
            $format
        )
        $b = $path.GetBounds()
        $matrix = New-Object Drawing.Drawing2D.Matrix
        try {
            $matrix.Translate(
                [single]($Bounds.X + (($Bounds.Width-$b.Width)/2.0) - $b.X),
                [single]($Bounds.Y + (($Bounds.Height-$b.Height)/2.0) - $b.Y)
            )
            $path.Transform($matrix)
        }
        finally { $matrix.Dispose() }

        $brush = New-Object Drawing.Drawing2D.LinearGradientBrush(
            $Bounds,
            $TextDark,
            $Orange,
            0
        )
        try { $Graphics.FillPath($brush,$path) }
        finally { $brush.Dispose() }
    }
    finally {
        $path.Dispose()
        $family.Dispose()
    }
}

function Draw-Badge {
    param([Drawing.Graphics]$Graphics,[float]$Scale)

    $shadow = [Drawing.RectangleF]::new(
        [single](62*$Scale),[single](72*$Scale),
        [single](900*$Scale),[single](890*$Scale))
    Fill-RoundedRect $Graphics $shadow (112*$Scale) $BadgeShadow

    $badge = [Drawing.RectangleF]::new(
        [single](52*$Scale),[single](48*$Scale),
        [single](920*$Scale),[single](900*$Scale))
    Fill-RoundedRect $Graphics $badge (112*$Scale) $White
    Stroke-RoundedRect $Graphics $badge (112*$Scale) $BadgeEdge (8*$Scale)
}

function Draw-ChipSymbol {
    param(
        [Drawing.Graphics]$Graphics,
        [float]$Scale,
        [bool]$Large
    )

    if ($Large) {
        $body = [Drawing.RectangleF]::new(
            [single](188*$Scale),[single](218*$Scale),
            [single](648*$Scale),[single](500*$Scale))
        $pinLength = 105
        $pinWidth = 48
        $pinXs = @(330,488,646)
        $pinYs = @(350,468,586)
    }
    else {
        $body = [Drawing.RectangleF]::new(
            [single](222*$Scale),[single](202*$Scale),
            [single](580*$Scale),[single](420*$Scale))
        $pinLength = 84
        $pinWidth = 42
        $pinXs = @(342,491,640)
        $pinYs = @(320,412,504)
    }

    foreach ($x in $pinXs) {
        $top = [Drawing.RectangleF]::new(
            [single](($x-$pinWidth/2)*$Scale),
            [single](($body.Y/$Scale-$pinLength+22)*$Scale),
            [single]($pinWidth*$Scale),
            [single](($pinLength+12)*$Scale))
        $bottom = [Drawing.RectangleF]::new(
            [single](($x-$pinWidth/2)*$Scale),
            [single](($body.Bottom/$Scale-20)*$Scale),
            [single]($pinWidth*$Scale),
            [single](($pinLength+8)*$Scale))
        Fill-GradientRoundedRect $Graphics $top (20*$Scale) $Purple $Orange 0
        Fill-GradientRoundedRect $Graphics $bottom (20*$Scale) $Purple $Navy2 90
    }

    foreach ($y in $pinYs) {
        $left = [Drawing.RectangleF]::new(
            [single](($body.X/$Scale-$pinLength+22)*$Scale),
            [single](($y-$pinWidth/2)*$Scale),
            [single](($pinLength+12)*$Scale),
            [single]($pinWidth*$Scale))
        $right = [Drawing.RectangleF]::new(
            [single](($body.Right/$Scale-20)*$Scale),
            [single](($y-$pinWidth/2)*$Scale),
            [single](($pinLength+8)*$Scale),
            [single]($pinWidth*$Scale))
        Fill-GradientRoundedRect $Graphics $left (20*$Scale) $Purple $Navy2 0
        Fill-GradientRoundedRect $Graphics $right (20*$Scale) $Navy2 $Orange 0
    }

    Fill-GradientRoundedRect $Graphics $body (72*$Scale) $Navy2 $Navy 0

    $monitor = if ($Large) {
        [Drawing.RectangleF]::new(
            [single](258*$Scale),[single](300*$Scale),
            [single](508*$Scale),[single](292*$Scale))
    } else {
        [Drawing.RectangleF]::new(
            [single](278*$Scale),[single](270*$Scale),
            [single](468*$Scale),[single](246*$Scale))
    }
    Fill-RoundedRect $Graphics $monitor (46*$Scale) $Lavender

    $screen = [Drawing.RectangleF]::new(
        [single](($monitor.X/$Scale+26)*$Scale),
        [single](($monitor.Y/$Scale+24)*$Scale),
        [single](($monitor.Width/$Scale-52)*$Scale),
        [single](($monitor.Height/$Scale-50)*$Scale))
    Fill-GradientRoundedRect $Graphics $screen (30*$Scale) $Navy2 $ScreenColor 90

    if ($Large) {
        $stand = [Drawing.RectangleF]::new(
            [single](463*$Scale),[single](575*$Scale),
            [single](98*$Scale),[single](72*$Scale))
        Fill-RoundedRect $Graphics $stand (18*$Scale) $Lavender
        $foot = [Drawing.RectangleF]::new(
            [single](420*$Scale),[single](628*$Scale),
            [single](184*$Scale),[single](24*$Scale))
        Fill-RoundedRect $Graphics $foot (10*$Scale) $Lavender
    } else {
        $stand = [Drawing.RectangleF]::new(
            [single](468*$Scale),[single](500*$Scale),
            [single](88*$Scale),[single](58*$Scale))
        Fill-RoundedRect $Graphics $stand (16*$Scale) $Lavender
        $foot = [Drawing.RectangleF]::new(
            [single](430*$Scale),[single](544*$Scale),
            [single](164*$Scale),[single](22*$Scale))
        Fill-RoundedRect $Graphics $foot (9*$Scale) $Lavender
    }

    $orangeWin = if ($Large) {
        [Drawing.RectangleF]::new(
            [single](535*$Scale),[single](390*$Scale),
            [single](165*$Scale),[single](138*$Scale))
    } else {
        [Drawing.RectangleF]::new(
            [single](530*$Scale),[single](338*$Scale),
            [single](150*$Scale),[single](120*$Scale))
    }
    Fill-GradientRoundedRect $Graphics $orangeWin (22*$Scale) $Orange2 $Orange 90

    $purpleWin = if ($Large) {
        [Drawing.RectangleF]::new(
            [single](372*$Scale),[single](450*$Scale),
            [single](192*$Scale),[single](132*$Scale))
    } else {
        [Drawing.RectangleF]::new(
            [single](390*$Scale),[single](380*$Scale),
            [single](170*$Scale),[single](116*$Scale))
    }
    Fill-GradientRoundedRect $Graphics $purpleWin (22*$Scale) $Purple2 $Purple 0

    $purpleInner = [Drawing.RectangleF]::new(
        [single](($purpleWin.X/$Scale+18)*$Scale),
        [single](($purpleWin.Y/$Scale+17)*$Scale),
        [single](($purpleWin.Width/$Scale-36)*$Scale),
        [single](($purpleWin.Height/$Scale-34)*$Scale))
    Fill-GradientRoundedRect $Graphics $purpleInner (14*$Scale) $Navy2 $Purple 0
}

function Render-IconFrame {
    param(
        [int]$CanvasSize,
        [ValidateSet('full','symbol')]
        [string]$Variant,
        [string]$OutputPng
    )

    $bmp = [Drawing.Bitmap]::new(
        $CanvasSize,$CanvasSize,
        [Drawing.Imaging.PixelFormat]::Format32bppArgb)

    try {
        $g = [Drawing.Graphics]::FromImage($bmp)
        try {
            $g.Clear($White)
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
            $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

            $scale = $CanvasSize / 1024.0
            Draw-Badge $g $scale

            if ($Variant -eq 'symbol') {
                Draw-ChipSymbol $g $scale $true
            }
            else {
                Draw-ChipSymbol $g $scale $false
                $textBounds = [Drawing.RectangleF]::new(
                    [single](110*$scale),[single](660*$scale),
                    [single](804*$scale),[single](240*$scale))
                Draw-TextGradient $g 'RDC Relay' $textBounds (122*$scale)
            }
        }
        finally { $g.Dispose() }

        $bmp.Save($OutputPng,[Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $bmp.Dispose() }
}

function Write-IcoFromPngs {
    param([string[]]$PngFiles,[int[]]$Sizes,[string]$OutputIco)

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
        [IO.File]::WriteAllBytes($OutputIco,$stream.ToArray())
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

Render-IconFrame -CanvasSize 1024 -Variant full -OutputPng $masterPath

$sizes = @(16,20,24,32,40,48,64,96,128,256)
$pngs = @()

foreach ($size in $sizes) {
    $variant = if ($size -le 64) { 'symbol' } else { 'full' }
    $render = Join-Path $workDir ("RDCRelay_{0}_{1}.png" -f $size,$variant)
    Render-IconFrame -CanvasSize $size -Variant $variant -OutputPng $render
    $pngs += $render
}

Write-IcoFromPngs -PngFiles $pngs -Sizes $sizes -OutputIco $icoPath

Write-Output "Master: $masterPath"
Write-Output "ICO:    $icoPath"
foreach ($i in 0..($sizes.Count-1)) {
    Write-Output ("{0,3}px: {1}" -f $sizes[$i],$pngs[$i])
}
