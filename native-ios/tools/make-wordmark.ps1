Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$bitmap = [Drawing.Bitmap]::new(1100, 180, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$font = [Drawing.Font]::new('Arial Black', 105, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$format = [Drawing.StringFormat]::GenericTypographic
$format.FormatFlags = $format.FormatFlags -bor [Drawing.StringFormatFlags]::MeasureTrailingSpaces
$yellow = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(255, 222, 0))
$leftWidth = $graphics.MeasureString('Fot', $font, [Drawing.PointF]::Empty, $format).Width
$rightWidth = $graphics.MeasureString('marco', $font, [Drawing.PointF]::Empty, $format).Width
$x = 12
$graphics.DrawString('Fot', $font, [Drawing.Brushes]::White, [Drawing.PointF]::new($x, 15), $format)
$x += $leftWidth
$graphics.FillEllipse($yellow, $x, 43, 92, 92)
$arrow = [Drawing.Drawing2D.GraphicsPath]::new()
$arrow.StartFigure()
$arrow.AddBezier($x + 23, 88, $x + 20, 91, $x + 21, 94, $x + 26, 94)
$arrow.AddLine($x + 26, 94, $x + 44, 94)
$arrow.AddBezier($x + 44, 94, $x + 48, 94, $x + 48, 95, $x + 49, 99)
$arrow.AddLine($x + 49, 99, $x + 52, 115)
$arrow.AddBezier($x + 52, 115, $x + 53, 120, $x + 56, 120, $x + 58, 115)
$arrow.AddLine($x + 58, 115, $x + 73, 64)
$arrow.AddBezier($x + 73, 64, $x + 74, 60, $x + 71, 59, $x + 68, 61)
$arrow.AddLine($x + 68, 61, $x + 23, 88)
$arrow.CloseFigure()
$graphics.FillPath([Drawing.Brushes]::Black, $arrow)
$x += 95
$graphics.DrawString('marco', $font, [Drawing.Brushes]::White, [Drawing.PointF]::new($x, 15), $format)
$used = [int][Math]::Ceiling($x + $rightWidth + 12)
$result = $bitmap.Clone([Drawing.Rectangle]::new(0, 0, $used, 160), [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$destination = Join-Path $PSScriptRoot '../Momentra/Assets.xcassets/FotomarcoWordmark.imageset/wordmark.png'
$result.Save($destination, [Drawing.Imaging.ImageFormat]::Png)
$result.Dispose(); $graphics.Dispose(); $bitmap.Dispose(); $font.Dispose(); $yellow.Dispose(); $arrow.Dispose()
