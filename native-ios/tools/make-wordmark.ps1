Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$bitmap = [Drawing.Bitmap]::new(1100, 180, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$font = [Drawing.Font]::new('Arial', 115, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
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
$arrow.AddPolygon([Drawing.PointF[]]@([Drawing.PointF]::new($x + 21, 89), [Drawing.PointF]::new($x + 72, 61), [Drawing.PointF]::new($x + 52, 119), [Drawing.PointF]::new($x + 46, 95)))
$graphics.FillPath([Drawing.Brushes]::Black, $arrow)
$x += 95
$graphics.DrawString('marco', $font, [Drawing.Brushes]::White, [Drawing.PointF]::new($x, 15), $format)
$used = [int][Math]::Ceiling($x + $rightWidth + 12)
$result = $bitmap.Clone([Drawing.Rectangle]::new(0, 0, $used, 160), [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$destination = Join-Path $PSScriptRoot '../Momentra/Assets.xcassets/FotomarcoWordmark.imageset/wordmark.png'
$result.Save($destination, [Drawing.Imaging.ImageFormat]::Png)
$result.Dispose(); $graphics.Dispose(); $bitmap.Dispose(); $font.Dispose(); $yellow.Dispose(); $arrow.Dispose()
