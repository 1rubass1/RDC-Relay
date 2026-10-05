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

function Get-RoundedPath {
    param(
        [Drawing.RectangleF]$Rect,
        [float]$Radius
    )

    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $d = [Math]::Max(0.1, $Radius * 2.0)
    $path.AddArc($Rect.Left, $Rect.Top, $d, $d, 180, 90)
    $path.AddArc($Rect.Right - $d, $Rect.Top, $d, $d, 270, 90)
    $path.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($Rect.Left, $Rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function Extract-LargestPngFromIco {
    param(
        [string]$InputIco,
        [string]$OutputPng
    )

    $bytes = [IO.File]::ReadAllBytes($InputIco)
    $count = [BitConverter]::ToUInt16($bytes, 4)
    $bestArea = -1
    $bestLength = 0
    $bestOffset = 0

    for ($i = 0; $i -lt $count; $i++) {
        $entry = 6 + (16 * $i)
        $w = [int]$bytes[$entry]
        $h = [int]$bytes[$entry + 1]
        if ($w -eq 0) { $w = 256 }
        if ($h -eq 0) { $h = 256 }

        $length = [BitConverter]::ToUInt32($bytes, $entry + 8)
        $offset = [BitConverter]::ToUInt32($bytes, $entry + 12)
        $isPng =
            $bytes[$offset] -eq 137 -and
            $bytes[$offset + 1] -eq 80 -and
            $bytes[$offset + 2] -eq 78 -and
            $bytes[$offset + 3] -eq 71

        $area = $w * $h
        if ($isPng -and $area -gt $bestArea) {
            $bestArea = $area
            $bestLength = $length
            $bestOffset = $offset
        }
    }

    if ($bestArea -lt 0) {
        throw 'No PNG frame found in source ICO.'
    }

    $payload = New-Object byte[] $bestLength
    [Array]::Copy($bytes, [int]$bestOffset, $payload, 0, [int]$bestLength)
    [IO.File]::WriteAllBytes($OutputPng, $payload)
}

function New-AdjustedMaster {
    param(
        [string]$SourcePng,
        [string]$OutputPng
    )

    $src = [Drawing.Bitmap]::FromFile($SourcePng)
    try {
        if ($src.Width -ne 256 -or $src.Height -ne 256) {
            throw "Expected a 256x256 master, got $($src.Width)x$($src.Height)."
        }

        $dst = New-Object Drawing.Bitmap 256, 256, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $g = [Drawing.Graphics]::FromImage($dst)
            try {
                $g.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
                $g.DrawImageUnscaled($src, 0, 0)
            }
            finally {
                $g.Dispose()
            }

            $orangePixels = New-Object System.Collections.Generic.List[object]

            for ($y = 45; $y -le 200; $y++) {
                $background = $src.GetPixel(220, $y)

                for ($x = 118; $x -le 223; $x++) {
                    $c = $src.GetPixel($x, $y)
                    if ($c.A -eq 0) { continue }

                    $hue = $c.GetHue()
                    $sat = $c.GetSaturation()

                    $isOrange =
                        $hue -ge 10.0 -and
                        $hue -le 42.0 -and
                        $sat -ge 0.22 -and
                        $c.R -gt $c.G -and
                        $c.G -gt $c.B

                    if ($isOrange) {
                        $orangePixels.Add([pscustomobject]@{
                            X = $x
                            Y = $y
                            Color = $c
                        })
                        $dst.SetPixel($x, $y, $background)
                    }
                }
            }

            $shift = 8
            foreach ($px in $orangePixels) {
                $nx = $px.X + $shift
                if ($nx -lt 256) {
                    $dst.SetPixel($nx, $px.Y, $px.Color)
                }
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

function Resize-Png {
    param(
        [string]$InputPng,
        [int]$Size,
        [string]$OutputPng
    )

    $src = [Drawing.Bitmap]::FromFile($InputPng)
    try {
        $dst = New-Object Drawing.Bitmap $Size, $Size, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $g = [Drawing.Graphics]::FromImage($dst)
            try {
                $g.Clear([Drawing.Color]::Transparent)
                $g.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceOver
                $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
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

function New-TinyIcon {
    param(
        [int]$Size,
        [string]$OutputPng
    )

    $scale = 4
    $w = $Size * $scale
    $bmp = New-Object Drawing.Bitmap $w, $w, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)

    try {
        $g = [Drawing.Graphics]::FromImage($bmp)
        try {
            $g.Clear([Drawing.Color]::Transparent)
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality

            $body = New-Object Drawing.RectangleF(
                (0.8 * $scale),
                (0.8 * $scale),
                (($Size - 1.6) * $scale),
                (($Size - 1.6) * $scale)
            )
            $radius = 3.0 * $scale
            $bodyPath = Get-RoundedPath -Rect $body -Radius $radius
            try {
                $bodyBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 5, 4, 5))
                $bodyPen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 219, 219, 221)), (0.9 * $scale)
                try {
                    $g.FillPath($bodyBrush, $bodyPath)
                    $g.DrawPath($bodyPen, $bodyPath)
                }
                finally {
                    $bodyBrush.Dispose()
                    $bodyPen.Dispose()
                }
            }
            finally {
                $bodyPath.Dispose()
            }

            $purple = [Drawing.Color]::FromArgb(255, 123, 95, 162)
            $orange = [Drawing.Color]::FromArgb(255, 191, 118, 67)
            $black = [Drawing.Color]::FromArgb(255, 5, 4, 5)

            $dOuter = New-Object Drawing.Drawing2D.GraphicsPath
            try {
                $dOuter.StartFigure()
                $dOuter.AddLine(0.19*$w, 0.22*$w, 0.33*$w, 0.22*$w)
                $dOuter.AddBezier(0.33*$w, 0.22*$w, 0.50*$w, 0.22*$w, 0.56*$w, 0.33*$w, 0.56*$w, 0.50*$w)
                $dOuter.AddBezier(0.56*$w, 0.50*$w, 0.56*$w, 0.67*$w, 0.50*$w, 0.78*$w, 0.33*$w, 0.78*$w)
                $dOuter.AddLine(0.33*$w, 0.78*$w, 0.19*$w, 0.78*$w)
                $dOuter.CloseFigure()

                $dBrush = New-Object Drawing.SolidBrush $purple
                try { $g.FillPath($dBrush, $dOuter) }
                finally { $dBrush.Dispose() }
            }
            finally {
                $dOuter.Dispose()
            }

            $dInner = New-Object Drawing.Drawing2D.GraphicsPath
            try {
                $dInner.StartFigure()
                $dInner.AddLine(0.31*$w, 0.35*$w, 0.35*$w, 0.35*$w)
                $dInner.AddBezier(0.35*$w, 0.35*$w, 0.44*$w, 0.35*$w, 0.46*$w, 0.42*$w, 0.46*$w, 0.50*$w)
                $dInner.AddBezier(0.46*$w, 0.50*$w, 0.46*$w, 0.58*$w, 0.44*$w, 0.65*$w, 0.35*$w, 0.65*$w)
                $dInner.AddLine(0.35*$w, 0.65*$w, 0.31*$w, 0.65*$w)
                $dInner.CloseFigure()

                $holeBrush = New-Object Drawing.SolidBrush $black
                try { $g.FillPath($holeBrush, $dInner) }
                finally { $holeBrush.Dispose() }
            }
            finally {
                $dInner.Dispose()
            }

            $cRect = New-Object Drawing.RectangleF(
                (0.53 * $w),
                (0.24 * $w),
                (0.31 * $w),
                (0.52 * $w)
            )
            $cPen = New-Object Drawing.Pen $orange, (0.13 * $w)
            try {
                $cPen.StartCap = [Drawing.Drawing2D.LineCap]::Flat
                $cPen.EndCap = [Drawing.Drawing2D.LineCap]::Flat
                $g.DrawArc($cPen, $cRect, 43, 274)
            }
            finally {
                $cPen.Dispose()
            }
        }
        finally {
            $g.Dispose()
        }

        $dst = New-Object Drawing.Bitmap $Size, $Size, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $g2 = [Drawing.Graphics]::FromImage($dst)
            try {
                $g2.Clear([Drawing.Color]::Transparent)
                $g2.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $g2.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g2.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g2.DrawImage($bmp, (New-Object Drawing.Rectangle 0, 0, $Size, $Size))
            }
            finally {
                $g2.Dispose()
            }

            $dst.Save($OutputPng, [Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $dst.Dispose()
        }
    }
    finally {
        $bmp.Dispose()
    }
}

function Write-IcoFromPngs {
    param(
        [string[]]$PngFiles,
        [int[]]$Sizes,
        [string]$OutputIco
    )

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

if (-not (Test-Path $masterPath)) {
    throw "Missing icon master: $masterPath. Restore Assets\\IconSource from Git before rebuilding the ICO."
}

$sizes = @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
$pngs = @()

foreach ($size in $sizes) {
    $png = Join-Path $workDir ("DesktopCommander_{0}.png" -f $size)

    if ($size -le 24) {
        New-TinyIcon -Size $size -OutputPng $png
    }
    else {
        Resize-Png -InputPng $masterPath -Size $size -OutputPng $png
    }

    $pngs += $png
}

Write-IcoFromPngs -PngFiles $pngs -Sizes $sizes -OutputIco $icoPath

Write-Output "Master: $masterPath"
Write-Output "ICO:    $icoPath"
foreach ($i in 0..($sizes.Count - 1)) {
    Write-Output ("{0,3}px: {1}" -f $sizes[$i], $pngs[$i])
}
