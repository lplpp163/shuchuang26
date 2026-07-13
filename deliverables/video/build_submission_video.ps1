[CmdletBinding()]
param(
    [string]$OutputPath = '',
    [string]$PreviewOutputPath = '',
    [ValidateRange(14, 28)]
    [int]$Crf = 18,
    [switch]$KeepWorkFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or newer is required. Run this script with pwsh.'
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Speech

$script:Width = 1920
$script:Height = 1080
$script:Fps = 30
$script:FadeSeconds = 0.65
$script:FontName = 'Microsoft JhengHei'
$script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture

$script:Colors = @{
    BackgroundA = '#171425'
    BackgroundB = '#402448'
    Panel       = '#29253C'
    PanelLight  = '#39334E'
    Cream       = '#FFF7E8'
    Muted       = '#C9C1D1'
    Coral       = '#FF7655'
    Teal        = '#39B59F'
    Gold        = '#FFC857'
    White       = '#FFFFFF'
    Ink         = '#15121E'
}

function Get-HexColor {
    param(
        [Parameter(Mandatory)] [string]$Hex,
        [ValidateRange(0, 255)] [int]$Alpha = 255
    )

    $value = $Hex.Trim().TrimStart('#')
    if ($value.Length -ne 6) {
        throw "Invalid color: $Hex"
    }

    $red = [Convert]::ToInt32($value.Substring(0, 2), 16)
    $green = [Convert]::ToInt32($value.Substring(2, 2), 16)
    $blue = [Convert]::ToInt32($value.Substring(4, 2), 16)
    return [System.Drawing.Color]::FromArgb($Alpha, $red, $green, $blue)
}

function New-Font {
    param(
        [Parameter(Mandatory)] [single]$Size,
        [switch]$Bold
    )

    $style = if ($Bold) {
        [System.Drawing.FontStyle]::Bold
    } else {
        [System.Drawing.FontStyle]::Regular
    }

    return [System.Drawing.Font]::new(
        $script:FontName,
        $Size,
        $style,
        [System.Drawing.GraphicsUnit]::Pixel
    )
}

function New-Rect {
    param(
        [single]$X,
        [single]$Y,
        [single]$Width,
        [single]$Height
    )

    return [System.Drawing.RectangleF]::new($X, $Y, $Width, $Height)
}

function New-RoundedPath {
    param(
        [Parameter(Mandatory)] [System.Drawing.RectangleF]$Rect,
        [single]$Radius = 24
    )

    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = [single]($Radius * 2)

    if ($diameter -le 0) {
        $path.AddRectangle($Rect)
        return $path
    }

    $path.AddArc($Rect.X, $Rect.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Rect.X, $Rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Fill-RoundedRectangle {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [System.Drawing.Brush]$Brush,
        [Parameter(Mandatory)] [System.Drawing.RectangleF]$Rect,
        [single]$Radius = 24
    )

    $path = New-RoundedPath -Rect $Rect -Radius $Radius
    try {
        $Graphics.FillPath($Brush, $path)
    } finally {
        $path.Dispose()
    }
}

function Draw-RoundedRectangle {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [System.Drawing.Pen]$Pen,
        [Parameter(Mandatory)] [System.Drawing.RectangleF]$Rect,
        [single]$Radius = 24
    )

    $path = New-RoundedPath -Rect $Rect -Radius $Radius
    try {
        $Graphics.DrawPath($Pen, $path)
    } finally {
        $path.Dispose()
    }
}

function Draw-TextBlock {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [AllowEmptyString()] [string]$Text,
        [Parameter(Mandatory)] [System.Drawing.RectangleF]$Rect,
        [single]$Size,
        [string]$Color,
        [switch]$Bold,
        [ValidateSet('Near', 'Center', 'Far')] [string]$Align = 'Near',
        [ValidateSet('Near', 'Center', 'Far')] [string]$VerticalAlign = 'Near'
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    $font = New-Font -Size $Size -Bold:$Bold
    $brush = [System.Drawing.SolidBrush]::new((Get-HexColor -Hex $Color))
    $format = [System.Drawing.StringFormat]::new()
    try {
        $format.Alignment = [System.Drawing.StringAlignment]::$Align
        $format.LineAlignment = [System.Drawing.StringAlignment]::$VerticalAlign
        $format.Trimming = [System.Drawing.StringTrimming]::EllipsisWord
        $format.FormatFlags = [System.Drawing.StringFormatFlags]::LineLimit
        $Graphics.DrawString($Text, $font, $brush, $Rect, $format)
    } finally {
        $format.Dispose()
        $brush.Dispose()
        $font.Dispose()
    }
}

function Draw-ImageCover {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [System.Drawing.Image]$Image,
        [Parameter(Mandatory)] [System.Drawing.RectangleF]$Dest
    )

    $sourceRatio = $Image.Width / [double]$Image.Height
    $destRatio = $Dest.Width / [double]$Dest.Height

    if ($sourceRatio -gt $destRatio) {
        $sourceHeight = [double]$Image.Height
        $sourceWidth = $sourceHeight * $destRatio
        $sourceX = ($Image.Width - $sourceWidth) / 2
        $sourceY = 0
    } else {
        $sourceWidth = [double]$Image.Width
        $sourceHeight = $sourceWidth / $destRatio
        $sourceX = 0
        $sourceY = ($Image.Height - $sourceHeight) / 2
    }

    $destRect = [System.Drawing.Rectangle]::Round($Dest)
    $sourceRect = [System.Drawing.Rectangle]::FromLTRB(
        [int][Math]::Round($sourceX),
        [int][Math]::Round($sourceY),
        [int][Math]::Round($sourceX + $sourceWidth),
        [int][Math]::Round($sourceY + $sourceHeight)
    )
    $Graphics.DrawImage(
        $Image,
        $destRect,
        $sourceRect,
        [System.Drawing.GraphicsUnit]::Pixel
    )
}

function Draw-ImageContain {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [System.Drawing.Image]$Image,
        [Parameter(Mandatory)] [System.Drawing.RectangleF]$Dest
    )

    $scale = [Math]::Min(
        $Dest.Width / [double]$Image.Width,
        $Dest.Height / [double]$Image.Height
    )
    $width = $Image.Width * $scale
    $height = $Image.Height * $scale
    $x = $Dest.X + (($Dest.Width - $width) / 2)
    $y = $Dest.Y + (($Dest.Height - $height) / 2)
    $target = [System.Drawing.Rectangle]::Round(
        (New-Rect -X $x -Y $y -Width $width -Height $height)
    )
    $Graphics.DrawImage($Image, $target)
}

function Draw-ClippedImage {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [System.Drawing.Image]$Image,
        [Parameter(Mandatory)] [System.Drawing.RectangleF]$Dest,
        [single]$Radius = 24,
        [switch]$Contain
    )

    $path = New-RoundedPath -Rect $Dest -Radius $Radius
    $state = $Graphics.Save()
    try {
        $Graphics.SetClip($path)
        if ($Contain) {
            Draw-ImageContain -Graphics $Graphics -Image $Image -Dest $Dest
        } else {
            Draw-ImageCover -Graphics $Graphics -Image $Image -Dest $Dest
        }
    } finally {
        $Graphics.Restore($state)
        $path.Dispose()
    }
}

function Draw-BaseBackground {
    param([Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics)

    $canvas = New-Rect -X 0 -Y 0 -Width $script:Width -Height $script:Height
    $gradient = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $canvas,
        (Get-HexColor $script:Colors.BackgroundA),
        (Get-HexColor $script:Colors.BackgroundB),
        18.0
    )
    try {
        $Graphics.FillRectangle($gradient, $canvas)
    } finally {
        $gradient.Dispose()
    }

    $glowA = [System.Drawing.SolidBrush]::new((Get-HexColor $script:Colors.Coral 28))
    $glowB = [System.Drawing.SolidBrush]::new((Get-HexColor $script:Colors.Teal 24))
    try {
        $Graphics.FillEllipse($glowA, -180, -260, 760, 760)
        $Graphics.FillEllipse($glowB, 1460, 610, 650, 650)
    } finally {
        $glowA.Dispose()
        $glowB.Dispose()
    }
}

function Draw-CommonHeader {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [object]$Slide,
        [int]$Index,
        [int]$Count
    )

    $markBrush = [System.Drawing.SolidBrush]::new((Get-HexColor $script:Colors.Coral))
    try {
        Fill-RoundedRectangle -Graphics $Graphics -Brush $markBrush -Rect (New-Rect 92 54 62 62) -Radius 19
    } finally {
        $markBrush.Dispose()
    }
    Draw-TextBlock -Graphics $Graphics -Text 'HT' -Rect (New-Rect 92 54 62 62) -Size 22 -Color $script:Colors.White -Bold -Align Center -VerticalAlign Center
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Config.brand) -Rect (New-Rect 176 53 500 62) -Size 29 -Color $script:Colors.Cream -Bold -VerticalAlign Center

    $progress = ('{0:00} / {1:00}' -f ($Index + 1), $Count)
    Draw-TextBlock -Graphics $Graphics -Text $progress -Rect (New-Rect 1640 58 190 48) -Size 23 -Color $script:Colors.Muted -Align Far -VerticalAlign Center

    $eyebrowRect = New-Rect 92 137 760 50
    $eyebrowBrush = [System.Drawing.SolidBrush]::new((Get-HexColor $script:Colors.Teal 38))
    try {
        Fill-RoundedRectangle -Graphics $Graphics -Brush $eyebrowBrush -Rect $eyebrowRect -Radius 25
    } finally {
        $eyebrowBrush.Dispose()
    }
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.eyebrow) -Rect (New-Rect 118 137 710 50) -Size 23 -Color $script:Colors.Teal -Bold -VerticalAlign Center
}

function Draw-PhoneFrame {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [string]$ImagePath,
        [single]$X,
        [single]$Y,
        [single]$Height
    )

    $width = [single]($Height * 412.0 / 915.0)
    $shadowRect = New-Rect ($X + 18) ($Y + 22) $width $Height
    $outerRect = New-Rect $X $Y $width $Height
    $innerRect = New-Rect ($X + 12) ($Y + 12) ($width - 24) ($Height - 24)
    $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(92, 0, 0, 0))
    $frame = [System.Drawing.SolidBrush]::new((Get-HexColor $script:Colors.Cream))
    $border = [System.Drawing.Pen]::new((Get-HexColor $script:Colors.White 105), 2.0)
    try {
        Fill-RoundedRectangle -Graphics $Graphics -Brush $shadow -Rect $shadowRect -Radius 48
        Fill-RoundedRectangle -Graphics $Graphics -Brush $frame -Rect $outerRect -Radius 48
        Draw-RoundedRectangle -Graphics $Graphics -Pen $border -Rect $outerRect -Radius 48
    } finally {
        $border.Dispose()
        $frame.Dispose()
        $shadow.Dispose()
    }

    $image = [System.Drawing.Image]::FromFile($ImagePath)
    try {
        Draw-ClippedImage -Graphics $Graphics -Image $image -Dest $innerRect -Radius 38
    } finally {
        $image.Dispose()
    }
}

function Draw-BulletList {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [object[]]$Items,
        [single]$X,
        [single]$Y,
        [single]$Width,
        [single]$ItemHeight = 62,
        [string]$DotColor = '#FFC857'
    )

    $currentY = $Y
    foreach ($item in @($Items)) {
        $dot = [System.Drawing.SolidBrush]::new((Get-HexColor $DotColor))
        try {
            $Graphics.FillEllipse($dot, $X, $currentY + 20, 15, 15)
        } finally {
            $dot.Dispose()
        }
        Draw-TextBlock -Graphics $Graphics -Text ([string]$item) -Rect (New-Rect ($X + 34) $currentY ($Width - 34) $ItemHeight) -Size 26 -Color $script:Colors.Cream -VerticalAlign Center
        $currentY += $ItemHeight
    }
}

function Draw-Badges {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [object[]]$Badges,
        [single]$X,
        [single]$Y,
        [single]$MaxWidth
    )

    $font = New-Font -Size 22 -Bold
    try {
        $currentX = $X
        $currentY = $Y
        foreach ($badge in @($Badges)) {
            $label = [string]$badge
            $measure = $Graphics.MeasureString($label, $font)
            $width = [single]([Math]::Min($measure.Width + 48, $MaxWidth))
            if (($currentX + $width) -gt ($X + $MaxWidth)) {
                $currentX = $X
                $currentY += 58
            }

            $rect = New-Rect $currentX $currentY $width 48
            $brush = [System.Drawing.SolidBrush]::new((Get-HexColor $script:Colors.Gold 42))
            try {
                Fill-RoundedRectangle -Graphics $Graphics -Brush $brush -Rect $rect -Radius 24
            } finally {
                $brush.Dispose()
            }
            Draw-TextBlock -Graphics $Graphics -Text $label -Rect $rect -Size 21 -Color $script:Colors.Gold -Bold -Align Center -VerticalAlign Center
            $currentX += $width + 14
        }
    } finally {
        $font.Dispose()
    }
}

function Draw-Footer {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [object]$Slide
    )

    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.note) -Rect (New-Rect 92 965 1735 42) -Size 19 -Color $script:Colors.Muted -VerticalAlign Center
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Config.footer) -Rect (New-Rect 92 1018 1735 34) -Size 17 -Color $script:Colors.Muted -Align Far -VerticalAlign Center
}

function Draw-AudioLabel {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [AllowEmptyString()] [string]$Text,
        [single]$X,
        [single]$Y,
        [single]$Width
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    $rect = New-Rect $X $Y $Width 50
    $brush = [System.Drawing.SolidBrush]::new((Get-HexColor $script:Colors.Coral 48))
    try {
        Fill-RoundedRectangle -Graphics $Graphics -Brush $brush -Rect $rect -Radius 25
    } finally {
        $brush.Dispose()
    }
    Draw-TextBlock -Graphics $Graphics -Text $Text -Rect $rect -Size 20 -Color $script:Colors.Coral -Bold -Align Center -VerticalAlign Center
}

function Draw-StandardSlide {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [object]$Slide,
        [int]$Index,
        [int]$Count,
        [Parameter(Mandatory)] [string]$ScreensDirectory
    )

    Draw-BaseBackground -Graphics $Graphics
    Draw-CommonHeader -Graphics $Graphics -Config $Config -Slide $Slide -Index $Index -Count $Count

    $isDual = ([string]$Slide.layout -eq 'dual')
    $textWidth = if ($isDual) { 890 } else { 1080 }
    $titleSize = if ($isDual) { 51 } else { 55 }

    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.title) -Rect (New-Rect 92 212 $textWidth 205) -Size $titleSize -Color $script:Colors.Cream -Bold
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.body) -Rect (New-Rect 92 430 $textWidth 150) -Size 29 -Color $script:Colors.Muted
    Draw-BulletList -Graphics $Graphics -Items @($Slide.bullets) -X 105 -Y 595 -Width ($textWidth - 20) -ItemHeight 65
    Draw-Badges -Graphics $Graphics -Badges @($Slide.badges) -X 92 -Y 835 -MaxWidth $textWidth
    Draw-AudioLabel -Graphics $Graphics -Text ([string]$Slide.audioLabel) -X 92 -Y 900 -Width ([Math]::Min(500, $textWidth))

    $screens = @($Slide.screenshots)
    if ($isDual) {
        if ($screens.Count -ne 2) {
            throw "Dual slide $Index requires exactly two screenshots."
        }
        Draw-PhoneFrame -Graphics $Graphics -ImagePath (Join-Path $ScreensDirectory $screens[0]) -X 1080 -Y 176 -Height 700
        Draw-PhoneFrame -Graphics $Graphics -ImagePath (Join-Path $ScreensDirectory $screens[1]) -X 1462 -Y 176 -Height 700
    } else {
        if ($screens.Count -ne 1) {
            throw "Single slide $Index requires exactly one screenshot."
        }
        Draw-PhoneFrame -Graphics $Graphics -ImagePath (Join-Path $ScreensDirectory $screens[0]) -X 1402 -Y 140 -Height 810
    }

    Draw-Footer -Graphics $Graphics -Config $Config -Slide $Slide
}

function Draw-HeroSlide {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [object]$Slide,
        [int]$Index,
        [int]$Count,
        [Parameter(Mandatory)] [string]$ImagesDirectory
    )

    $artPath = Join-Path $ImagesDirectory ([string]$Slide.art)
    $art = [System.Drawing.Image]::FromFile($artPath)
    try {
        Draw-ImageCover -Graphics $Graphics -Image $art -Dest (New-Rect 0 0 $script:Width $script:Height)
    } finally {
        $art.Dispose()
    }

    $veil = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(150, 18, 14, 31))
    $panel = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(178, 24, 20, 38))
    try {
        $Graphics.FillRectangle($veil, 0, 0, $script:Width, $script:Height)
        Fill-RoundedRectangle -Graphics $Graphics -Brush $panel -Rect (New-Rect 86 270 1040 585) -Radius 42
    } finally {
        $panel.Dispose()
        $veil.Dispose()
    }

    Draw-CommonHeader -Graphics $Graphics -Config $Config -Slide $Slide -Index $Index -Count $Count
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.title) -Rect (New-Rect 145 335 910 150) -Size 92 -Color $script:Colors.Cream -Bold
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.body) -Rect (New-Rect 150 510 880 100) -Size 43 -Color $script:Colors.Gold -Bold
    Draw-Badges -Graphics $Graphics -Badges @($Slide.badges) -X 150 -Y 660 -MaxWidth 850
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.note) -Rect (New-Rect 150 760 850 70) -Size 21 -Color $script:Colors.Muted
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Config.footer) -Rect (New-Rect 92 1018 1735 34) -Size 17 -Color $script:Colors.Cream -Align Far -VerticalAlign Center
}

function Draw-MosaicSlide {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [object]$Slide,
        [int]$Index,
        [int]$Count,
        [Parameter(Mandatory)] [string]$ImagesDirectory
    )

    Draw-BaseBackground -Graphics $Graphics
    Draw-CommonHeader -Graphics $Graphics -Config $Config -Slide $Slide -Index $Index -Count $Count
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.title) -Rect (New-Rect 92 207 1735 100) -Size 58 -Color $script:Colors.Cream -Bold
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.body) -Rect (New-Rect 92 315 1735 80) -Size 28 -Color $script:Colors.Muted

    $tiles = @($Slide.tiles)
    $tileWidth = 318
    $tileHeight = 480
    $gap = 36
    $startX = 93
    $y = 420
    for ($i = 0; $i -lt $tiles.Count; $i++) {
        $x = $startX + ($i * ($tileWidth + $gap))
        $shadowRect = New-Rect ($x + 13) ($y + 17) $tileWidth $tileHeight
        $cardRect = New-Rect $x $y $tileWidth $tileHeight
        $imageRect = New-Rect ($x + 10) ($y + 10) ($tileWidth - 20) 365
        $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(82, 0, 0, 0))
        $card = [System.Drawing.SolidBrush]::new((Get-HexColor $script:Colors.PanelLight))
        try {
            Fill-RoundedRectangle -Graphics $Graphics -Brush $shadow -Rect $shadowRect -Radius 30
            Fill-RoundedRectangle -Graphics $Graphics -Brush $card -Rect $cardRect -Radius 30
        } finally {
            $card.Dispose()
            $shadow.Dispose()
        }

        $imagePath = Join-Path $ImagesDirectory ([string]$tiles[$i].file)
        $image = [System.Drawing.Image]::FromFile($imagePath)
        try {
            Draw-ClippedImage -Graphics $Graphics -Image $image -Dest $imageRect -Radius 22
        } finally {
            $image.Dispose()
        }

        Draw-TextBlock -Graphics $Graphics -Text ([string]$tiles[$i].label) -Rect (New-Rect ($x + 18) ($y + 390) ($tileWidth - 36) 70) -Size 25 -Color $script:Colors.Cream -Bold -Align Center -VerticalAlign Center
    }

    Draw-AudioLabel -Graphics $Graphics -Text ([string]$Slide.audioLabel) -X 92 -Y 918 -Width 500
    Draw-Footer -Graphics $Graphics -Config $Config -Slide $Slide
}

function Draw-SplitSlide {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [object]$Slide,
        [int]$Index,
        [int]$Count
    )

    Draw-BaseBackground -Graphics $Graphics
    Draw-CommonHeader -Graphics $Graphics -Config $Config -Slide $Slide -Index $Index -Count $Count
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.title) -Rect (New-Rect 92 207 1735 100) -Size 58 -Color $script:Colors.Cream -Bold
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.body) -Rect (New-Rect 92 315 1735 75) -Size 28 -Color $script:Colors.Muted

    $leftRect = New-Rect 92 420 820 455
    $rightRect = New-Rect 1008 420 820 455
    $leftBrush = [System.Drawing.SolidBrush]::new((Get-HexColor $script:Colors.Teal 36))
    $rightBrush = [System.Drawing.SolidBrush]::new((Get-HexColor $script:Colors.Coral 34))
    try {
        Fill-RoundedRectangle -Graphics $Graphics -Brush $leftBrush -Rect $leftRect -Radius 34
        Fill-RoundedRectangle -Graphics $Graphics -Brush $rightBrush -Rect $rightRect -Radius 34
    } finally {
        $rightBrush.Dispose()
        $leftBrush.Dispose()
    }

    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.leftTitle) -Rect (New-Rect 135 450 735 62) -Size 32 -Color $script:Colors.Teal -Bold -VerticalAlign Center
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.rightTitle) -Rect (New-Rect 1051 450 735 62) -Size 32 -Color $script:Colors.Coral -Bold -VerticalAlign Center
    Draw-BulletList -Graphics $Graphics -Items @($Slide.leftItems) -X 142 -Y 530 -Width 700 -ItemHeight 72 -DotColor $script:Colors.Teal
    Draw-BulletList -Graphics $Graphics -Items @($Slide.rightItems) -X 1058 -Y 530 -Width 700 -ItemHeight 72 -DotColor $script:Colors.Coral
    Draw-Badges -Graphics $Graphics -Badges @($Slide.badges) -X 92 -Y 900 -MaxWidth 900
    Draw-Footer -Graphics $Graphics -Config $Config -Slide $Slide
}

function Draw-StatsSlide {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [object]$Slide,
        [int]$Index,
        [int]$Count
    )

    Draw-BaseBackground -Graphics $Graphics
    Draw-CommonHeader -Graphics $Graphics -Config $Config -Slide $Slide -Index $Index -Count $Count
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.title) -Rect (New-Rect 92 207 1735 100) -Size 58 -Color $script:Colors.Cream -Bold
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.body) -Rect (New-Rect 92 315 1735 90) -Size 28 -Color $script:Colors.Muted

    $stats = @($Slide.stats)
    $cardWidth = 405
    $cardHeight = 275
    $gap = 38
    $startX = 93
    $y = 468
    for ($i = 0; $i -lt $stats.Count; $i++) {
        $x = $startX + ($i * ($cardWidth + $gap))
        $rect = New-Rect $x $y $cardWidth $cardHeight
        $shadowRect = New-Rect ($x + 12) ($y + 16) $cardWidth $cardHeight
        $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(78, 0, 0, 0))
        $card = [System.Drawing.SolidBrush]::new((Get-HexColor $script:Colors.PanelLight 232))
        try {
            Fill-RoundedRectangle -Graphics $Graphics -Brush $shadow -Rect $shadowRect -Radius 34
            Fill-RoundedRectangle -Graphics $Graphics -Brush $card -Rect $rect -Radius 34
        } finally {
            $card.Dispose()
            $shadow.Dispose()
        }

        $valueColor = if (($i % 2) -eq 0) { $script:Colors.Gold } else { $script:Colors.Teal }
        Draw-TextBlock -Graphics $Graphics -Text ([string]$stats[$i].value) -Rect (New-Rect ($x + 22) ($y + 40) ($cardWidth - 44) 112) -Size 62 -Color $valueColor -Bold -Align Center -VerticalAlign Center
        Draw-TextBlock -Graphics $Graphics -Text ([string]$stats[$i].label) -Rect (New-Rect ($x + 28) ($y + 164) ($cardWidth - 56) 66) -Size 27 -Color $script:Colors.Cream -Bold -Align Center -VerticalAlign Center
    }

    Draw-Badges -Graphics $Graphics -Badges @($Slide.badges) -X 92 -Y 805 -MaxWidth 1500
    Draw-Footer -Graphics $Graphics -Config $Config -Slide $Slide
}

function Draw-OutroSlide {
    param(
        [Parameter(Mandatory)] [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [object]$Slide,
        [int]$Index,
        [int]$Count,
        [Parameter(Mandatory)] [string]$ImagesDirectory
    )

    Draw-BaseBackground -Graphics $Graphics

    $artPath = Join-Path $ImagesDirectory ([string]$Slide.art)
    $art = [System.Drawing.Image]::FromFile($artPath)
    try {
        Draw-ImageContain -Graphics $Graphics -Image $art -Dest (New-Rect 820 105 1010 790)
    } finally {
        $art.Dispose()
    }

    Draw-CommonHeader -Graphics $Graphics -Config $Config -Slide $Slide -Index $Index -Count $Count
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.title) -Rect (New-Rect 95 255 820 135) -Size 78 -Color $script:Colors.Cream -Bold
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.body) -Rect (New-Rect 98 410 760 100) -Size 40 -Color $script:Colors.Gold -Bold
    Draw-BulletList -Graphics $Graphics -Items @($Slide.bullets) -X 108 -Y 555 -Width 760 -ItemHeight 72 -DotColor $script:Colors.Coral
    Draw-Badges -Graphics $Graphics -Badges @($Slide.badges) -X 95 -Y 812 -MaxWidth 760
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Slide.note) -Rect (New-Rect 95 925 1720 65) -Size 21 -Color $script:Colors.Muted
    Draw-TextBlock -Graphics $Graphics -Text ([string]$Config.footer) -Rect (New-Rect 92 1018 1735 34) -Size 17 -Color $script:Colors.Muted -Align Far -VerticalAlign Center
}

function Render-Slide {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [object]$Slide,
        [int]$Index,
        [int]$Count,
        [Parameter(Mandatory)] [string]$ScreensDirectory,
        [Parameter(Mandatory)] [string]$ImagesDirectory,
        [Parameter(Mandatory)] [string]$OutputFile
    )

    $bitmap = [System.Drawing.Bitmap]::new(
        $script:Width,
        $script:Height,
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    )
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

        switch ([string]$Slide.layout) {
            'hero' {
                Draw-HeroSlide -Graphics $graphics -Config $Config -Slide $Slide -Index $Index -Count $Count -ImagesDirectory $ImagesDirectory
            }
            { $_ -in @('single', 'dual') } {
                Draw-StandardSlide -Graphics $graphics -Config $Config -Slide $Slide -Index $Index -Count $Count -ScreensDirectory $ScreensDirectory
            }
            'mosaic' {
                Draw-MosaicSlide -Graphics $graphics -Config $Config -Slide $Slide -Index $Index -Count $Count -ImagesDirectory $ImagesDirectory
            }
            'split' {
                Draw-SplitSlide -Graphics $graphics -Config $Config -Slide $Slide -Index $Index -Count $Count
            }
            'stats' {
                Draw-StatsSlide -Graphics $graphics -Config $Config -Slide $Slide -Index $Index -Count $Count
            }
            'outro' {
                Draw-OutroSlide -Graphics $graphics -Config $Config -Slide $Slide -Index $Index -Count $Count -ImagesDirectory $ImagesDirectory
            }
            default {
                throw "Unsupported slide layout: $($Slide.layout)"
            }
        }

        $bitmap.Save($OutputFile, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Resolve-RequiredCommand {
    param([Parameter(Mandatory)] [string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        throw "$Name was not found on PATH."
    }
    return $command.Source
}

function Invoke-External {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [System.Collections.Generic.List[string]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath"
    }
}

function Format-Number {
    param([double]$Value, [string]$Pattern = '0.###')
    return $Value.ToString($Pattern, $script:Invariant)
}

function Get-MediaDurationSeconds {
    param(
        [Parameter(Mandatory)] [string]$FfprobePath,
        [Parameter(Mandatory)] [string]$MediaPath
    )

    $durationLines = @(
        & $FfprobePath `
            -v error `
            -show_entries 'format=duration' `
            -of 'default=noprint_wrappers=1:nokey=1' `
            $MediaPath |
            ForEach-Object { [string]$_ }
    )
    if ($LASTEXITCODE -ne 0 -or $durationLines.Count -ne 1) {
        throw "Unable to read media duration: $MediaPath"
    }
    return [double]::Parse($durationLines[0], $script:Invariant)
}

function Get-LoudnessMeasurement {
    param(
        [Parameter(Mandatory)] [string]$FfmpegPath,
        [Parameter(Mandatory)] [string]$MediaPath,
        [double]$StartSeconds = 0.0,
        [double]$DurationSeconds = 0.0
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @('-hide_banner', '-nostats', '-loglevel', 'info')) {
        $arguments.Add($argument)
    }
    if ($StartSeconds -gt 0) {
        $arguments.Add('-ss')
        $arguments.Add((Format-Number $StartSeconds))
    }
    if ($DurationSeconds -gt 0) {
        $arguments.Add('-t')
        $arguments.Add((Format-Number $DurationSeconds))
    }
    foreach ($argument in @(
        '-i', $MediaPath,
        '-map', '0:a:0',
        '-af', 'loudnorm=I=-16:TP=-2:LRA=11:print_format=json',
        '-f', 'null',
        'NUL'
    )) {
        $arguments.Add($argument)
    }

    $output = @(& $FfmpegPath @arguments 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg loudness analysis failed for $MediaPath."
    }
    $matches = [regex]::Matches(
        ($output -join [Environment]::NewLine),
        '\{\s*"input_i"[\s\S]*?\}'
    )
    if ($matches.Count -eq 0) {
        throw "FFmpeg did not return EBU R128 data for $MediaPath."
    }
    $data = $matches[$matches.Count - 1].Value | ConvertFrom-Json
    $integratedText = [string]$data.input_i
    $truePeakText = [string]$data.input_tp
    $isFinite = $integratedText -notmatch '(?i)inf|nan' -and $truePeakText -notmatch '(?i)inf|nan'

    return [ordered]@{
        startSeconds = [Math]::Round($StartSeconds, 3)
        durationSeconds = if ($DurationSeconds -gt 0) { [Math]::Round($DurationSeconds, 3) } else { $null }
        integratedLufs = if ($isFinite) { [double]::Parse($integratedText, $script:Invariant) } else { $null }
        truePeakDbtp = if ($isFinite) { [double]::Parse($truePeakText, $script:Invariant) } else { $null }
        loudnessRangeLu = if ([string]$data.input_lra -notmatch '(?i)inf|nan') {
            [double]::Parse([string]$data.input_lra, $script:Invariant)
        } else {
            $null
        }
        thresholdLufs = if ([string]$data.input_thresh -notmatch '(?i)inf|nan') {
            [double]::Parse([string]$data.input_thresh, $script:Invariant)
        } else {
            $null
        }
        finite = $isFinite
    }
}

function Get-AudioLoudnessVerification {
    param(
        [Parameter(Mandatory)] [string]$FfmpegPath,
        [Parameter(Mandatory)] [string]$MediaPath,
        [Parameter(Mandatory)] [string]$Role,
        [Parameter(Mandatory)] [object]$MixConfig,
        [Parameter(Mandatory)] [object[]]$SlideSegments,
        [Parameter(Mandatory)] [object[]]$SpeechSegments,
        [Parameter(Mandatory)] [double]$BackgroundIntegratedLufs
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $full = Get-LoudnessMeasurement -FfmpegPath $FfmpegPath -MediaPath $MediaPath
    if (-not $full.finite) {
        $errors.Add('Full programme loudness is not finite.')
    } else {
        if ($full.integratedLufs -lt [double]$MixConfig.fullMinLufs -or
            $full.integratedLufs -gt [double]$MixConfig.fullMaxLufs) {
            $errors.Add(
                "Full programme loudness $($full.integratedLufs) LUFS is outside $($MixConfig.fullMinLufs)..$($MixConfig.fullMaxLufs) LUFS."
            )
        }
        if ($full.truePeakDbtp -gt [double]$MixConfig.maxTruePeakDbtp) {
            $errors.Add(
                "Full programme true peak $($full.truePeakDbtp) dBTP exceeds $($MixConfig.maxTruePeakDbtp) dBTP."
            )
        }
    }

    $slideResults = [System.Collections.Generic.List[object]]::new()
    foreach ($segment in $SlideSegments) {
        $measurement = Get-LoudnessMeasurement `
            -FfmpegPath $FfmpegPath `
            -MediaPath $MediaPath `
            -StartSeconds ([double]$segment.startSeconds) `
            -DurationSeconds ([double]$segment.durationSeconds)
        $measurement['slide'] = [int]$segment.slide
        $measurement['validation'] = 'PASS'
        if (-not $measurement.finite -or
            $measurement.integratedLufs -lt [double]$MixConfig.slideMinLufs -or
            $measurement.integratedLufs -gt [double]$MixConfig.slideMaxLufs) {
            $measurement['validation'] = 'FAIL'
            $errors.Add(
                "Slide $($segment.slide) loudness is not within $($MixConfig.slideMinLufs)..$($MixConfig.slideMaxLufs) LUFS."
            )
        }
        $slideResults.Add($measurement)
    }

    $speechResults = [System.Collections.Generic.List[object]]::new()
    foreach ($segment in $SpeechSegments) {
        $measurement = Get-LoudnessMeasurement `
            -FfmpegPath $FfmpegPath `
            -MediaPath $MediaPath `
            -StartSeconds ([double]$segment.startSeconds) `
            -DurationSeconds ([double]$segment.durationSeconds)
        $measurement['kind'] = [string]$segment.kind
        $measurement['slide'] = [int]$segment.slide
        $measurement['label'] = [string]$segment.label
        $measurement['speechToBedLu'] = if ($measurement.finite) {
            [Math]::Round($measurement.integratedLufs - $BackgroundIntegratedLufs, 2)
        } else {
            $null
        }
        $measurement['validation'] = 'PASS'
        if (-not $measurement.finite -or
            $measurement.integratedLufs -lt [double]$MixConfig.speechMinLufs -or
            $measurement.integratedLufs -gt [double]$MixConfig.speechMaxLufs -or
            $measurement.speechToBedLu -lt [double]$MixConfig.minimumSpeechToBedLu) {
            $measurement['validation'] = 'FAIL'
            $errors.Add(
                "$($segment.kind) on slide $($segment.slide) is not clearly audible above the background bed."
            )
        }
        if ($measurement.finite -and $measurement.truePeakDbtp -gt [double]$MixConfig.maxTruePeakDbtp) {
            $measurement['validation'] = 'FAIL'
            $errors.Add(
                "$($segment.kind) on slide $($segment.slide) exceeds the true-peak ceiling."
            )
        }
        $speechResults.Add($measurement)
    }

    if ($errors.Count -gt 0) {
        throw "$Role EBU R128 validation failed: $($errors -join ' ')"
    }

    return [ordered]@{
        standard = 'EBU R128 / ITU-R BS.1770 (FFmpeg loudnorm analysis)'
        fullProgramme = $full
        slides = @($slideResults)
        speechWindows = @($speechResults)
        gates = [ordered]@{
            fullProgrammeLufs = "$($MixConfig.fullMinLufs)..$($MixConfig.fullMaxLufs)"
            maxTruePeakDbtp = [double]$MixConfig.maxTruePeakDbtp
            slideLufs = "$($MixConfig.slideMinLufs)..$($MixConfig.slideMaxLufs)"
            speechWindowLufs = "$($MixConfig.speechMinLufs)..$($MixConfig.speechMaxLufs)"
            minimumSpeechToBedLu = [double]$MixConfig.minimumSpeechToBedLu
        }
        validation = 'PASS'
    }
}

function Get-MediaVerificationRecord {
    param(
        [Parameter(Mandatory)] [string]$FfprobePath,
        [Parameter(Mandatory)] [string]$MediaPath,
        [Parameter(Mandatory)] [string]$Role,
        [int]$ExpectedWidth,
        [int]$ExpectedHeight,
        [int64]$SizeLimitBytes,
        [double]$DurationLimitSeconds = 180.0
    )

    $probeOutput = & $FfprobePath -v error -show_streams -show_format -of json $MediaPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe failed for $Role."
    }
    $probe = ($probeOutput -join [Environment]::NewLine) | ConvertFrom-Json
    $videoStream = @($probe.streams | Where-Object { $_.codec_type -eq 'video' }) | Select-Object -First 1
    $audioStream = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' }) | Select-Object -First 1
    if ($null -eq $videoStream -or $null -eq $audioStream) {
        throw "$Role must contain one video stream and one audio stream."
    }

    $duration = [double]::Parse([string]$probe.format.duration, $script:Invariant)
    $mediaItem = Get-Item -LiteralPath $MediaPath
    $errors = [System.Collections.Generic.List[string]]::new()
    if ([string]$videoStream.codec_name -ne 'h264') { $errors.Add('Video codec is not H.264.') }
    if ([int]$videoStream.width -ne $ExpectedWidth -or [int]$videoStream.height -ne $ExpectedHeight) {
        $errors.Add("Video resolution is not ${ExpectedWidth}x${ExpectedHeight}.")
    }
    if ([string]$videoStream.pix_fmt -ne 'yuv420p') { $errors.Add('Video pixel format is not yuv420p.') }
    if ([string]$videoStream.avg_frame_rate -ne '30/1') { $errors.Add('Average frame rate is not 30/1.') }
    if ($duration -le 0 -or $duration -gt $DurationLimitSeconds) { $errors.Add('Video duration is outside the allowed range.') }
    if ([string]$audioStream.codec_name -ne 'aac') { $errors.Add('Audio codec is not AAC.') }
    if ([int]$audioStream.sample_rate -ne 48000) { $errors.Add('Audio sample rate is not 48 kHz.') }
    if ([int]$audioStream.channels -ne 2) { $errors.Add('Audio is not stereo.') }
    if ($mediaItem.Length -ge $SizeLimitBytes) {
        $errors.Add("File size $($mediaItem.Length) is not strictly below $SizeLimitBytes bytes.")
    }

    $formatTags = [ordered]@{}
    $formatTagsProperty = $probe.format.PSObject.Properties['tags']
    if ($null -ne $formatTagsProperty -and $null -ne $formatTagsProperty.Value) {
        foreach ($property in $formatTagsProperty.Value.PSObject.Properties) {
            $formatTags[$property.Name] = [string]$property.Value
        }
    }
    $streamTags = [System.Collections.Generic.List[object]]::new()
    foreach ($stream in @($probe.streams)) {
        $tags = [ordered]@{}
        $streamTagsProperty = $stream.PSObject.Properties['tags']
        if ($null -ne $streamTagsProperty -and $null -ne $streamTagsProperty.Value) {
            foreach ($property in $streamTagsProperty.Value.PSObject.Properties) {
                $tags[$property.Name] = [string]$property.Value
            }
        }
        $streamTags.Add([ordered]@{
            index = [int]$stream.index
            codecType = [string]$stream.codec_type
            tags = $tags
        })
    }

    $metadataText = (($formatTags | ConvertTo-Json -Compress) + ($streamTags | ConvertTo-Json -Depth 5 -Compress))
    if ($metadataText -match '(?i)([a-z]:\\|\\\\[^\\]|/users/|/home/)') {
        $errors.Add('Container or stream metadata contains a local absolute path.')
    }
    if ($errors.Count -gt 0) {
        throw "$Role validation failed: $($errors -join ' ')"
    }

    $sha256 = (Get-FileHash -LiteralPath $MediaPath -Algorithm SHA256).Hash
    return [ordered]@{
        role = $Role
        file = $mediaItem.Name
        bytes = [int64]$mediaItem.Length
        sha256 = $sha256
        container = [string]$probe.format.format_name
        durationSeconds = [Math]::Round($duration, 3)
        video = [ordered]@{
            codec = [string]$videoStream.codec_name
            profile = [string]$videoStream.profile
            width = [int]$videoStream.width
            height = [int]$videoStream.height
            pixelFormat = [string]$videoStream.pix_fmt
            averageFrameRate = [string]$videoStream.avg_frame_rate
            bitrate = [int64]$videoStream.bit_rate
        }
        audio = [ordered]@{
            codec = [string]$audioStream.codec_name
            profile = [string]$audioStream.profile
            sampleRate = [int]$audioStream.sample_rate
            channels = [int]$audioStream.channels
            channelLayout = [string]$audioStream.channel_layout
            bitrate = [int64]$audioStream.bit_rate
        }
        limits = [ordered]@{
            durationSeconds = $DurationLimitSeconds
            sizeBytes = $SizeLimitBytes
            sizeRelation = 'strictly_less_than'
            remainingBytes = [int64]($SizeLimitBytes - $mediaItem.Length)
        }
        metadata = [ordered]@{
            anonymous = $true
            localAbsolutePathScan = 'PASS'
            formatTags = $formatTags
            streamTags = $streamTags
        }
        validation = 'PASS'
    }
}

$configPath = Join-Path $PSScriptRoot 'video_content.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing configuration: $configPath"
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
$canonicalBrand = '傳家話'
if ([string]$config.brand -ne $canonicalBrand) {
    throw "video_content.json brand must remain $canonicalBrand."
}

$deliverablesDirectory = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $deliverablesDirectory
$appCandidates = @(
    Get-ChildItem -LiteralPath $workspaceRoot -Directory -Recurse -Filter 'flutter_app' |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'pubspec.yaml') }
)
if ($appCandidates.Count -ne 1) {
    throw "Expected exactly one flutter_app under $workspaceRoot; found $($appCandidates.Count)."
}
$appRoot = $appCandidates[0].FullName
$screensDirectory = Join-Path $appRoot 'test-results'
$imagesDirectory = Join-Path $appRoot 'assets\images'
$audioDirectory = Join-Path $appRoot 'assets\audio'

$ffmpeg = Resolve-RequiredCommand -Name 'ffmpeg'
$ffprobe = Resolve-RequiredCommand -Name 'ffprobe'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot ([string]$config.outputFile)
} else {
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
}
if ([string]::IsNullOrWhiteSpace($PreviewOutputPath)) {
    $PreviewOutputPath = Join-Path $PSScriptRoot ([string]$config.previewOutputFile)
} else {
    $PreviewOutputPath = [System.IO.Path]::GetFullPath($PreviewOutputPath)
}
if ($OutputPath -eq $PreviewOutputPath) {
    throw 'The submission output and Web preview output must be different files.'
}
$previewMaxBytes = [int64]$config.previewMaxBytes
$previewVideoBitrateKbps = [int]$config.previewVideoBitrateKbps
$mixConfig = $config.audioMix
if ($previewMaxBytes -ne 26214400) {
    throw 'The Web preview byte limit must remain exactly 26214400 bytes (25 MiB).'
}
if ($previewVideoBitrateKbps -lt 500 -or $previewVideoBitrateKbps -gt 1000) {
    throw 'The Web preview video bitrate must stay between 500 and 1000 kbps.'
}
if ([string]::IsNullOrWhiteSpace([string]$mixConfig.narrationVoice)) {
    throw 'audioMix.narrationVoice is required.'
}
if ([int]$mixConfig.narrationRate -lt -10 -or [int]$mixConfig.narrationRate -gt 10) {
    throw 'audioMix.narrationRate must stay between -10 and 10.'
}
if ([double]$mixConfig.programTargetLufs -lt -24 -or [double]$mixConfig.programTargetLufs -gt -14) {
    throw 'audioMix.programTargetLufs must stay between -24 and -14 LUFS.'
}
if ([double]$mixConfig.programTruePeakDbtp -gt -1.5) {
    throw 'audioMix.programTruePeakDbtp must be at or below -1.5 dBTP to leave AAC headroom.'
}
if ([double]$mixConfig.programGainDb -lt -6 -or [double]$mixConfig.programGainDb -gt 6) {
    throw 'audioMix.programGainDb must stay between -6 and +6 dB.'
}
if ([double]$mixConfig.backgroundTargetLufs -gt ([double]$mixConfig.narrationTargetLufs - [double]$mixConfig.minimumSpeechToBedLu)) {
    throw 'The configured background bed does not leave enough headroom below narration.'
}
$verificationPath = Join-Path $PSScriptRoot ([string]$config.verificationFile)

$workDirectory = Join-Path $env:TEMP ('hometongue-video-' + [Guid]::NewGuid().ToString('N'))
$slidesDirectory = Join-Path $workDirectory 'slides'
$narrationDirectory = Join-Path $workDirectory 'narration'
$null = New-Item -ItemType Directory -Path $slidesDirectory -Force
$null = New-Item -ItemType Directory -Path $narrationDirectory -Force
$baseVideo = Join-Path $workDirectory 'silent-master.mp4'
$bedAudio = Join-Path $workDirectory 'procedural-bed.wav'
$previewPassLog = Join-Path $workDirectory 'web-preview-pass'
$succeeded = $false

try {
    $slides = @($config.slides)
    if ($slides.Count -lt 2) {
        throw 'At least two slides are required.'
    }

    Write-Host "Rendering $($slides.Count) evidence-based slides..."
    $slideFiles = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $slides.Count; $i++) {
        $slideFile = Join-Path $slidesDirectory ('slide-{0:00}.png' -f ($i + 1))
        Render-Slide `
            -Config $config `
            -Slide $slides[$i] `
            -Index $i `
            -Count $slides.Count `
            -ScreensDirectory $screensDirectory `
            -ImagesDirectory $imagesDirectory `
            -OutputFile $slideFile
        $slideFiles.Add($slideFile)
    }

    $inputArguments = [System.Collections.Generic.List[string]]::new()
    $filterParts = [System.Collections.Generic.List[string]]::new()
    $durations = [System.Collections.Generic.List[double]]::new()

    for ($i = 0; $i -lt $slides.Count; $i++) {
        $duration = [double]$slides[$i].duration
        if ($duration -le ($script:FadeSeconds + 1)) {
            throw "Slide $($i + 1) is too short for the configured transition."
        }
        $durations.Add($duration)
        $inputArguments.Add('-i')
        $inputArguments.Add($slideFiles[$i])

        $frames = [int][Math]::Round($duration * $script:Fps)
        $zoomIncrement = 0.024 / [Math]::Max($frames, 1)
        $zoomText = Format-Number $zoomIncrement '0.0000000'
        $filterParts.Add(
            "[$($i):v]zoompan=z='min(zoom+$zoomText,1.024)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$($frames):s=$($script:Width)x$($script:Height):fps=$($script:Fps),setsar=1,format=yuv420p,setpts=PTS-STARTPTS[v$i]"
        )
    }

    $currentLabel = 'v0'
    $timelineDuration = $durations[0]
    for ($i = 1; $i -lt $slides.Count; $i++) {
        $offset = $timelineDuration - $script:FadeSeconds
        $nextLabel = "x$i"
        # Omit the transition option so FFmpeg uses its default fade. FFmpeg
        # 8.1 on Windows advertises named modes but rejects the explicit enum.
        $filterParts.Add(
            "[$currentLabel][v$i]xfade=duration=$(Format-Number $script:FadeSeconds):offset=$(Format-Number $offset)[$nextLabel]"
        )
        $currentLabel = $nextLabel
        $timelineDuration += $durations[$i] - $script:FadeSeconds
    }
    $filterParts.Add(
        "[$currentLabel]trim=duration=$(Format-Number $timelineDuration),setpts=PTS-STARTPTS[vout]"
    )

    Write-Host ("Encoding silent 1080p master ({0:N1} seconds)..." -f $timelineDuration)
    $videoArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @('-y', '-hide_banner', '-loglevel', 'warning', '-stats')) {
        $videoArguments.Add($argument)
    }
    foreach ($argument in $inputArguments) {
        $videoArguments.Add($argument)
    }
    foreach ($argument in @(
        '-filter_complex', ($filterParts -join ';'),
        '-map', '[vout]',
        '-c:v', 'libx264',
        '-preset', 'medium',
        '-crf', [string]$Crf,
        '-profile:v', 'high',
        '-level:v', '4.1',
        '-pix_fmt', 'yuv420p',
        '-r', [string]$script:Fps,
        '-g', '60',
        '-an',
        '-movflags', '+faststart',
        $baseVideo
    )) {
        $videoArguments.Add($argument)
    }
    Invoke-External -FilePath $ffmpeg -Arguments $videoArguments

    $rootExpression = 'if(lt(mod(t,32),8),196,if(lt(mod(t,32),16),220,if(lt(mod(t,32),24),174.61,196)))'
    $envelope = '(0.5-0.5*cos(2*PI*mod(t,8)/8))'
    $leftExpression = "0.014*$envelope*(sin(2*PI*($rootExpression)*t)+0.48*sin(2*PI*($rootExpression)*1.5*t)+0.25*sin(2*PI*($rootExpression)*2*t))"
    $rightExpression = "0.014*$envelope*(sin(2*PI*($rootExpression)*t+0.35)+0.48*sin(2*PI*($rootExpression)*1.5*t+0.55)+0.25*sin(2*PI*($rootExpression)*2*t+0.2))"
    $bedFilter = "aevalsrc=exprs='$leftExpression|$rightExpression':s=48000:d=$(Format-Number $timelineDuration),highpass=f=90,lowpass=f=2400,aecho=0.8:0.5:180|360:0.10|0.06,afade=t=in:st=0:d=2,afade=t=out:st=$(Format-Number ($timelineDuration - 3)):d=3,loudnorm=I=$(Format-Number ([double]$mixConfig.backgroundTargetLufs)):TP=-8:LRA=7"

    Write-Host 'Synthesizing the original procedural background bed...'
    $bedArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(
        '-y', '-hide_banner', '-loglevel', 'warning',
        '-f', 'lavfi', '-i', $bedFilter,
        '-t', (Format-Number $timelineDuration),
        '-c:a', 'pcm_s16le',
        $bedAudio
    )) {
        $bedArguments.Add($argument)
    }
    Invoke-External -FilePath $ffmpeg -Arguments $bedArguments
    $bedLoudness = Get-LoudnessMeasurement -FfmpegPath $ffmpeg -MediaPath $bedAudio
    if (-not $bedLoudness.finite -or
        [Math]::Abs($bedLoudness.integratedLufs - [double]$mixConfig.backgroundTargetLufs) -gt 2.0) {
        throw "The procedural background bed did not reach its audible loudness target."
    }

    $slideStarts = [System.Collections.Generic.List[double]]::new()
    $slideStarts.Add(0.0)
    for ($i = 1; $i -lt $slides.Count; $i++) {
        $slideStarts.Add($slideStarts[$i - 1] + $durations[$i - 1] - $script:FadeSeconds)
    }

    $slideSegments = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $slides.Count; $i++) {
        $activeDuration = if ($i -lt ($slides.Count - 1)) {
            $durations[$i] - $script:FadeSeconds
        } else {
            $durations[$i]
        }
        $slideSegments.Add([pscustomobject]@{
            slide = $i + 1
            startSeconds = $slideStarts[$i] + 0.1
            durationSeconds = $activeDuration - 0.2
        })
    }

    Write-Host "Synthesizing Traditional Chinese narration with $($mixConfig.narrationVoice)..."
    $narrationFiles = [System.Collections.Generic.List[string]]::new()
    $speechSegments = [System.Collections.Generic.List[object]]::new()
    $synthesizer = [System.Speech.Synthesis.SpeechSynthesizer]::new()
    try {
        $installedVoice = @(
            $synthesizer.GetInstalledVoices() |
                Where-Object { $_.Enabled -and $_.VoiceInfo.Name -eq [string]$mixConfig.narrationVoice }
        )
        if ($installedVoice.Count -ne 1) {
            throw "Required narration voice is not installed: $($mixConfig.narrationVoice)"
        }
        $synthesizer.SelectVoice([string]$mixConfig.narrationVoice)
        $synthesizer.Rate = [int]$mixConfig.narrationRate
        $synthesizer.Volume = [int]$mixConfig.narrationVolume

        for ($i = 0; $i -lt $slides.Count; $i++) {
            $narrationProperty = $slides[$i].PSObject.Properties['narration']
            if ($null -eq $narrationProperty -or [string]::IsNullOrWhiteSpace([string]$narrationProperty.Value)) {
                throw "Slide $($i + 1) is missing narration text."
            }
            $delayProperty = $slides[$i].PSObject.Properties['narrationDelay']
            $narrationDelay = if ($null -ne $delayProperty) {
                [double]$delayProperty.Value
            } else {
                [double]$mixConfig.narrationDelaySeconds
            }
            $narrationFile = Join-Path $narrationDirectory ('narration-{0:00}.wav' -f ($i + 1))
            $synthesizer.SetOutputToWaveFile($narrationFile)
            $synthesizer.Speak([string]$narrationProperty.Value)
            $synthesizer.SetOutputToNull()

            $narrationDuration = Get-MediaDurationSeconds -FfprobePath $ffprobe -MediaPath $narrationFile
            $activeDuration = if ($i -lt ($slides.Count - 1)) {
                $durations[$i] - $script:FadeSeconds
            } else {
                $durations[$i]
            }
            if (($narrationDelay + $narrationDuration) -gt ($activeDuration - 0.3)) {
                throw (
                    "Narration on slide $($i + 1) is $([Math]::Round($narrationDuration, 2)) seconds and does not fit its $([Math]::Round($activeDuration, 2))-second audio window."
                )
            }

            $narrationFiles.Add($narrationFile)
            $speechSegments.Add([pscustomobject]@{
                kind = 'narration'
                slide = $i + 1
                label = ('narration-{0:00}' -f ($i + 1))
                startSeconds = [Math]::Max(0, $slideStarts[$i] + $narrationDelay - 0.1)
                durationSeconds = $narrationDuration + 0.2
            })
        }
    } finally {
        $synthesizer.Dispose()
    }

    $audioCues = @($config.audioCues)
    $mixArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @('-y', '-hide_banner', '-loglevel', 'warning', '-stats', '-i', $baseVideo, '-i', $bedAudio)) {
        $mixArguments.Add($argument)
    }

    foreach ($cue in $audioCues) {
        $audioPath = Join-Path $audioDirectory ([string]$cue.file)
        if (-not (Test-Path -LiteralPath $audioPath)) {
            throw "Missing audio cue: $audioPath"
        }
        $mixArguments.Add('-i')
        $mixArguments.Add($audioPath)
    }
    foreach ($narrationFile in $narrationFiles) {
        $mixArguments.Add('-i')
        $mixArguments.Add($narrationFile)
    }

    $audioFilters = [System.Collections.Generic.List[string]]::new()
    $audioFilters.Add('[1:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo[bed]')
    $speechLabels = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $audioCues.Count; $i++) {
        $cue = $audioCues[$i]
        $slideIndex = [int]$cue.slide - 1
        if ($slideIndex -lt 0 -or $slideIndex -ge $slides.Count) {
            throw "Audio cue $($i + 1) references an invalid slide."
        }
        $delaySeconds = $slideStarts[$slideIndex] + [double]$cue.delay
        $delayMilliseconds = [int][Math]::Round($delaySeconds * 1000)
        $inputIndex = $i + 2
        $label = "cue$i"
        $audioPath = Join-Path $audioDirectory ([string]$cue.file)
        $cueDuration = Get-MediaDurationSeconds -FfprobePath $ffprobe -MediaPath $audioPath
        $audioFilters.Add(
            "[$($inputIndex):a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,loudnorm=I=$(Format-Number ([double]$mixConfig.productSpeechTargetLufs)):TP=-2.5:LRA=7,adelay=$delayMilliseconds`:all=1[$label]"
        )
        $speechLabels.Add("[$label]")
        $speechSegments.Add([pscustomobject]@{
            kind = 'piper_product_demo'
            slide = [int]$cue.slide
            label = [string]$cue.text
            startSeconds = [Math]::Max(0, $delaySeconds - 0.1)
            durationSeconds = $cueDuration + 0.2
        })
    }
    $narrationInputStart = 2 + $audioCues.Count
    for ($i = 0; $i -lt $narrationFiles.Count; $i++) {
        $inputIndex = $narrationInputStart + $i
        $slide = $slides[$i]
        $delayProperty = $slide.PSObject.Properties['narrationDelay']
        $narrationDelay = if ($null -ne $delayProperty) {
            [double]$delayProperty.Value
        } else {
            [double]$mixConfig.narrationDelaySeconds
        }
        $delaySeconds = $slideStarts[$i] + $narrationDelay
        $delayMilliseconds = [int][Math]::Round($delaySeconds * 1000)
        $label = "narration$i"
        $audioFilters.Add(
            "[$($inputIndex):a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,highpass=f=80,lowpass=f=10000,acompressor=threshold=0.125:ratio=3:attack=15:release=250:makeup=2,loudnorm=I=$(Format-Number ([double]$mixConfig.narrationTargetLufs)):TP=-2:LRA=7,adelay=$delayMilliseconds`:all=1[$label]"
        )
        $speechLabels.Add("[$label]")
    }
    $audioFilters.Add(
        # FFmpeg 8.1 needs timestamps reset between apad and atrim; without it,
        # atrim can collapse a delayed mix to only the first delay interval.
        ($speechLabels -join '') + "amix=inputs=$($speechLabels.Count):duration=longest:dropout_transition=0:normalize=0,apad=whole_dur=$(Format-Number $timelineDuration),asetpts=PTS-STARTPTS,atrim=duration=$(Format-Number $timelineDuration)[speechraw]"
    )
    $audioFilters.Add(
        '[speechraw]asplit=2[speechsidechain][speechmix]'
    )
    $audioFilters.Add(
        '[bed][speechsidechain]sidechaincompress=threshold=0.04:ratio=8:attack=15:release=400:detection=rms:link=average[bedduck]'
    )
    $audioFilters.Add(
        # Apply one fixed programme gain after independently normalizing each
        # speech source. A whole-programme dynamic loudnorm pass would raise
        # quiet gaps and could make an almost-silent slide appear to pass.
        "[bedduck][speechmix]amix=inputs=2:duration=first:dropout_transition=0:normalize=0,volume=$(Format-Number ([double]$mixConfig.programGainDb))dB,alimiter=limit=$(Format-Number ([Math]::Pow(10, ([double]$mixConfig.programTruePeakDbtp / 20))) '0.000000'):level=disabled,aresample=48000[aout]"
    )

    foreach ($argument in @(
        '-filter_complex', ($audioFilters -join ';'),
        '-map', '0:v:0',
        '-map', '[aout]',
        '-c:v', 'copy',
        '-c:a', 'aac',
        '-b:a', '192k',
        '-ar', '48000',
        '-ac', '2',
        '-t', (Format-Number $timelineDuration),
        '-map_metadata', '-1',
        # Keep container metadata ASCII so ffprobe JSON remains portable across
        # Windows console code pages. The rendered title remains Traditional Chinese.
        '-metadata', 'title=Chuan Jia Hua - Submission Video',
        '-metadata', 'comment=Current interface evidence; synthetic Mandarin narration; procedural music bed; Piper product demo speech; no real-user testimony.',
        '-movflags', '+faststart',
        $OutputPath
    )) {
        $mixArguments.Add($argument)
    }

    Write-Host 'Mixing product audio demonstrations and writing the final MP4...'
    Invoke-External -FilePath $ffmpeg -Arguments $mixArguments

    Write-Host 'Encoding the size-constrained 720p Web preview from the formal MP4...'
    $previewBitrate = "${previewVideoBitrateKbps}k"
    $previewFirstPass = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(
        '-y', '-hide_banner', '-loglevel', 'warning', '-stats',
        '-i', $OutputPath,
        '-map', '0:v:0',
        '-vf', 'scale=1280:720:flags=lanczos,setsar=1',
        '-c:v', 'libx264',
        '-preset', 'slow',
        '-b:v', $previewBitrate,
        '-maxrate:v', '1000k',
        '-bufsize:v', '2000k',
        '-profile:v', 'high',
        '-level:v', '3.1',
        '-pix_fmt', 'yuv420p',
        '-r', '30',
        '-g', '60',
        '-fps_mode', 'cfr',
        '-pass', '1',
        '-passlogfile', $previewPassLog,
        '-an',
        '-f', 'null',
        'NUL'
    )) {
        $previewFirstPass.Add($argument)
    }
    Invoke-External -FilePath $ffmpeg -Arguments $previewFirstPass

    $previewSecondPass = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(
        '-y', '-hide_banner', '-loglevel', 'warning', '-stats',
        '-i', $OutputPath,
        '-map', '0:v:0',
        '-map', '0:a:0',
        '-vf', 'scale=1280:720:flags=lanczos,setsar=1',
        '-c:v', 'libx264',
        '-preset', 'slow',
        '-b:v', $previewBitrate,
        '-maxrate:v', '1000k',
        '-bufsize:v', '2000k',
        '-profile:v', 'high',
        '-level:v', '3.1',
        '-pix_fmt', 'yuv420p',
        '-r', '30',
        '-g', '60',
        '-fps_mode', 'cfr',
        '-pass', '2',
        '-passlogfile', $previewPassLog,
        '-c:a', 'aac',
        '-b:a', '128k',
        '-ar', '48000',
        '-ac', '2',
        '-map_metadata', '-1',
        '-metadata', 'title=Chuan Jia Hua - Web Preview',
        '-metadata', 'comment=Anonymous competition prototype; synthetic Mandarin narration; procedural audio; Piper product demo speech.',
        '-movflags', '+faststart',
        $PreviewOutputPath
    )) {
        $previewSecondPass.Add($argument)
    }
    Invoke-External -FilePath $ffmpeg -Arguments $previewSecondPass

    $formalRecord = Get-MediaVerificationRecord `
        -FfprobePath $ffprobe `
        -MediaPath $OutputPath `
        -Role 'submission_1080p' `
        -ExpectedWidth 1920 `
        -ExpectedHeight 1080 `
        -SizeLimitBytes 314572800
    $previewRecord = Get-MediaVerificationRecord `
        -FfprobePath $ffprobe `
        -MediaPath $PreviewOutputPath `
        -Role 'web_preview_720p' `
        -ExpectedWidth 1280 `
        -ExpectedHeight 720 `
        -SizeLimitBytes $previewMaxBytes

    Write-Host 'Running full-programme, per-slide, and per-speech EBU R128 gates...'
    $formalLoudness = Get-AudioLoudnessVerification `
        -FfmpegPath $ffmpeg `
        -MediaPath $OutputPath `
        -Role 'submission_1080p' `
        -MixConfig $mixConfig `
        -SlideSegments @($slideSegments) `
        -SpeechSegments @($speechSegments) `
        -BackgroundIntegratedLufs ([double]$bedLoudness.integratedLufs + [double]$mixConfig.programGainDb)
    $previewLoudness = Get-AudioLoudnessVerification `
        -FfmpegPath $ffmpeg `
        -MediaPath $PreviewOutputPath `
        -Role 'web_preview_720p' `
        -MixConfig $mixConfig `
        -SlideSegments @($slideSegments) `
        -SpeechSegments @($speechSegments) `
        -BackgroundIntegratedLufs ([double]$bedLoudness.integratedLufs + [double]$mixConfig.programGainDb)
    $formalRecord.audio['loudness'] = $formalLoudness
    $previewRecord.audio['loudness'] = $previewLoudness

    $verification = [ordered]@{
        schemaVersion = 3
        generatedAt = [DateTimeOffset]::Now.ToString('o')
        outputs = @($formalRecord, $previewRecord)
        derivation = [ordered]@{
            source = 'submission_1080p'
            derived = 'web_preview_720p'
            method = 'Two-pass H.264 transcode with Lanczos 1280x720 scaling and AAC audio; audio is remeasured after preview encoding.'
        }
        evidence = [ordered]@{
            slideCount = $slides.Count
            screenshotDirectory = '正式版/flutter_app/test-results'
            imageDirectory = '正式版/flutter_app/assets/images'
            audioCueCount = $audioCues.Count
            narrationCount = $narrationFiles.Count
            musicSource = 'Procedurally synthesized by FFmpeg aevalsrc; no third-party music or sound effects.'
            narration = "Synthetic Traditional Chinese narration generated locally with Windows SAPI voice $($mixConfig.narrationVoice)."
            productSpeech = 'Pinned Piper synthetic Vietnamese demonstration files from the current app manifest.'
            humanTestimony = $false
        }
        audioMix = [ordered]@{
            programmeTargetLufs = [double]$mixConfig.programTargetLufs
            programmeFixedGainDb = [double]$mixConfig.programGainDb
            programmeTruePeakTargetDbtp = [double]$mixConfig.programTruePeakDbtp
            backgroundTargetLufs = [double]$mixConfig.backgroundTargetLufs
            backgroundMeasuredBeforeProgrammeGainLufs = [double]$bedLoudness.integratedLufs
            backgroundBaselineAfterProgrammeGainLufs = [double]$bedLoudness.integratedLufs + [double]$mixConfig.programGainDb
            narrationTargetLufs = [double]$mixConfig.narrationTargetLufs
            productSpeechTargetLufs = [double]$mixConfig.productSpeechTargetLufs
            sidechainDucking = '8:1 compression of the bed while narration or product speech is active.'
            validation = 'PASS'
        }
        metadataPolicy = [ordered]@{
            anonymous = $true
            localAbsolutePathsAllowed = $false
            validation = 'PASS'
        }
        validation = 'PASS'
    }

    $verificationJson = $verification | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText(
        $verificationPath,
        $verificationJson + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host ''
    Write-Host 'VIDEO BUILD PASSED'
    foreach ($record in @($formalRecord, $previewRecord)) {
        Write-Host "Role: $($record.role)"
        Write-Host "Output: $($record.file)"
        Write-Host "Bytes: $($record.bytes)"
        Write-Host "Duration: $($record.durationSeconds) seconds"
        Write-Host "Video: $($record.video.codec), $($record.video.width)x$($record.video.height), $($record.video.averageFrameRate) fps"
        Write-Host "Audio: $($record.audio.codec), $($record.audio.sampleRate) Hz, $($record.audio.channels) channels"
        Write-Host "Loudness: $($record.audio.loudness.fullProgramme.integratedLufs) LUFS, $($record.audio.loudness.fullProgramme.truePeakDbtp) dBTP"
        Write-Host "SHA-256: $($record.sha256)"
    }
    Write-Host "Verification: $verificationPath"
    $succeeded = $true
} finally {
    if (-not $KeepWorkFiles -and $succeeded) {
        $resolvedTemp = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        $resolvedWork = [System.IO.Path]::GetFullPath($workDirectory)
        if (-not $resolvedWork.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove an unexpected work directory: $resolvedWork"
        }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    } else {
        Write-Host "Work files: $workDirectory"
    }
}
