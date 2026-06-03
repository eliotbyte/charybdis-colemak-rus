# Render keymap-drawer SVG locally (no CI).
param(
    [string]$Out = "keymap-drawer/charybdis.svg"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

$env:PYTHONIOENCODING = "utf-8"

if (-not (Get-Command keymap -ErrorAction SilentlyContinue)) {
    Write-Error "keymap-drawer not found. Install: pip install keymap-drawer"
}

New-Item -ItemType Directory -Force -Path (Split-Path $Out -Parent) | Out-Null
& keymap -c keymap-drawer/config.yaml draw keymap-drawer/charybdis.yaml -o $Out
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# keymap-drawer only injects CSS; gradients need SVG defs
# Two-layer keys: base 52×52 (#171717, rx=6), top inset 2px (gradient, rx=12)
$KeyOuter = 52
$KeyOuterOrigin = -26
$KeyInset = 2
$KeyInner = $KeyOuter - (2 * $KeyInset)
$KeyInnerOrigin = $KeyOuterOrigin + $KeyInset
$KeyTopRx = 12
$KeyBaseRx = 9
$KeyTopShadowBlur = 1.5
$KeyTopShadowOffset = 2
$KeyBaseShadowBlur = [math]::Round(3 * 1.3, 1)

$svgPath = Join-Path (Get-Location) $Out
$svg = [System.IO.File]::ReadAllText($svgPath)
$svg = [regex]::Replace($svg, '<defs class="charybdis-custom">[\s\S]*?</defs>\s*', '')
$svg = [regex]::Replace($svg, '<rect rx="[0-9.]+" ry="[0-9.]+" x="-26" y="-26" width="52" height="52" class="key-base"\s*/>\s*', '')
$svg = [regex]::Replace(
    $svg,
    '<rect rx="12" ry="12" x="-24" y="-24" width="48" height="48" class="key(?: key-top)?"[^>]*/>\s*',
    '<rect rx="12" ry="12" x="-26" y="-26" width="52" height="52" class="key"/>' + "`n"
)
$svg = [regex]::Replace($svg, 'class="key"\s+key-top', 'class="key"')
$svg = [regex]::Replace($svg, 'class="key key-top"', 'class="key"')
$svg = [regex]::Replace($svg, '\s*fill="url\(#key-fill\)"', '')
$svg = [regex]::Replace($svg, '\s*filter="url\(#key-inner-shadow\)"', '')
$svg = [regex]::Replace($svg, '\s*filter="url\(#key-base-inner-shadow\)"', '')
$customDefs = @"
<defs class="charybdis-custom">
  <linearGradient id="key-fill" gradientUnits="objectBoundingBox" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0%" stop-color="#2E2E2E"/>
    <stop offset="100%" stop-color="#3C3A37"/>
  </linearGradient>
  <linearGradient id="key-fill-lower" gradientUnits="objectBoundingBox" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0%" stop-color="#262020"/>
    <stop offset="100%" stop-color="#314A5C"/>
  </linearGradient>
  <linearGradient id="key-fill-raise" gradientUnits="objectBoundingBox" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0%" stop-color="#262020"/>
    <stop offset="100%" stop-color="#5E4053"/>
  </linearGradient>
  <linearGradient id="key-fill-fn" gradientUnits="objectBoundingBox" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0%" stop-color="#262020"/>
    <stop offset="100%" stop-color="#5B5540"/>
  </linearGradient>
  <linearGradient id="text-stroke" gradientUnits="objectBoundingBox" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#4A483D"/>
    <stop offset="100%" stop-color="#000000"/>
  </linearGradient>
  <filter id="key-inner-shadow" x="-50%" y="-50%" width="200%" height="200%" color-interpolation-filters="sRGB">
    <feGaussianBlur in="SourceAlpha" stdDeviation="$KeyTopShadowBlur" result="blur"/>
    <feOffset in="blur" dx="$KeyTopShadowOffset" dy="$KeyTopShadowOffset" result="lightBlur"/>
    <feComposite in="SourceAlpha" in2="lightBlur" operator="out" result="shadowMask"/>
    <feFlood flood-color="#9CA7DB" flood-opacity="0.1" result="shadowColor"/>
    <feComposite in="shadowColor" in2="shadowMask" operator="in" result="innerShadow"/>
    <feMerge>
      <feMergeNode in="SourceGraphic"/>
      <feMergeNode in="innerShadow"/>
    </feMerge>
  </filter>
  <filter id="key-base-inner-shadow" x="-50%" y="-50%" width="200%" height="200%" color-interpolation-filters="sRGB">
    <feGaussianBlur in="SourceAlpha" stdDeviation="$KeyBaseShadowBlur" result="blur"/>
    <feComposite in="SourceAlpha" in2="blur" operator="out" result="shadowMask"/>
    <feFlood flood-color="#2E3437" flood-opacity="0.5" result="shadowColor"/>
    <feComposite in="shadowColor" in2="shadowMask" operator="in" result="innerShadow"/>
    <feMerge>
      <feMergeNode in="SourceGraphic"/>
      <feMergeNode in="innerShadow"/>
    </feMerge>
  </filter>
</defs>
"@
$svg = [regex]::Replace($svg, '<style>', $customDefs + '<style>', 1)
$baseRect = "<rect rx=`"$KeyBaseRx`" ry=`"$KeyBaseRx`" x=`"$KeyOuterOrigin`" y=`"$KeyOuterOrigin`" width=`"$KeyOuter`" height=`"$KeyOuter`" class=`"key-base`" filter=`"url(#key-base-inner-shadow)`"/>"
$topRect = "<rect rx=`"$KeyTopRx`" ry=`"$KeyTopRx`" x=`"$KeyInnerOrigin`" y=`"$KeyInnerOrigin`" width=`"$KeyInner`" height=`"$KeyInner`" class=`"key key-top`" fill=`"url(#key-fill)`" filter=`"url(#key-inner-shadow)`"/>"
$svg = [regex]::Replace(
    $svg,
    '(<g transform="translate\([^"]+\)" class="key keypos-[0-9]+">)\s*<rect rx="12" ry="12" x="-26" y="-26" width="52" height="52" class="key"\s*/>',
    '$1' + "`n$baseRect`n$topRect"
)

function Set-LayerKeyTopFill {
    param(
        [string]$Svg,
        [string]$LayerName,
        [string]$GradientId
    )
    $pattern = "(<g transform=`"translate\(30, \d+\)`" class=`"layer-$LayerName`">)([\s\S]*?)(?=<g transform=`"translate\(30, \d+\)`" class=`"layer-|</svg>)"
    [regex]::Replace($Svg, $pattern, {
        param($m)
        $inner = $m.Groups[2].Value -replace 'fill="url\(#key-fill\)"', "fill=`"url(#$GradientId)`""
        $m.Groups[1].Value + $inner
    }, 1)
}

$svg = Set-LayerKeyTopFill -Svg $svg -LayerName 'Lower' -GradientId 'key-fill-lower'
$svg = Set-LayerKeyTopFill -Svg $svg -LayerName 'Raise' -GradientId 'key-fill-raise'
$svg = Set-LayerKeyTopFill -Svg $svg -LayerName 'Fn' -GradientId 'key-fill-fn'

$Lightning = [char]0x2607
$StackedLine1X = -6
$StackedLine2Y = 9
$StackedLine1Y = -7

$DualKeySpacingDefault = @{
    Line1Y = -9.5
    Line2Y = 11.5
    OffsetY = 0
}

# Per-key overrides: Line1Y/Line2Y, Gap (+ optional CenterY), and/or OffsetY (shifts both lines).
# Keys: tap id ('Space', ';', …) or 'Layer:tap' ('Russian:.') — layer-specific wins over tap-only.
$DualKeySpacingByTap = @{
    "'" = @{ OffsetY = 5 }
    ',' = @{ Gap = 13.5 }
    'Colemak:.' = @{ Gap = 13.5 }
    'Russian:.' = @{ Gap = 16.5; OffsetY = -4 }
    'Space' = @{ Gap = 6; Line1Class = 'dual-line1'; Line2Class = 'dual-line2'; Line2FontSize = 27 }
    'Enter' = @{ Gap = 16; OffsetY = 3; Line1Class = 'dual-line1'; Line2Class = 'dual-line2' }
}

function Get-DualKeySpacing {
    param([string[]]$Keys)
    $spacing = @{
        Line1Y = $DualKeySpacingDefault.Line1Y
        Line2Y = $DualKeySpacingDefault.Line2Y
        Line1Class = 'dual-line'
        Line2Class = 'dual-line'
        Line1FontSize = $null
        Line2FontSize = $null
    }
    $offsetY = $DualKeySpacingDefault.OffsetY
    foreach ($key in $Keys) {
        if (-not $DualKeySpacingByTap.ContainsKey($key)) { continue }
        $override = $DualKeySpacingByTap[$key]
        if ($override.Gap) {
            $centerY = if ($null -ne $override.CenterY) { $override.CenterY } else { 1 }
            $half = $override.Gap / 2
            $spacing.Line1Y = $centerY - $half
            $spacing.Line2Y = $centerY + $half
        }
        if ($null -ne $override.Line1Y) { $spacing.Line1Y = $override.Line1Y }
        if ($null -ne $override.Line2Y) { $spacing.Line2Y = $override.Line2Y }
        if ($null -ne $override.OffsetY) { $offsetY += $override.OffsetY }
        if ($override.Line1Class) { $spacing.Line1Class = $override.Line1Class }
        if ($override.Line2Class) { $spacing.Line2Class = $override.Line2Class }
        if ($null -ne $override.Line1FontSize) { $spacing.Line1FontSize = $override.Line1FontSize }
        if ($null -ne $override.Line2FontSize) { $spacing.Line2FontSize = $override.Line2FontSize }
    }
    $spacing.Line1Y += $offsetY
    $spacing.Line2Y += $offsetY
    return $spacing
}

function Escape-SvgText {
    param([string]$Text)
    $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function Format-DualKeyLine {
    param(
        [string]$Content,
        [double]$Y,
        [string]$Class,
        $FontSize = $null
    )
    $styleAttr = if ($null -ne $FontSize) { " style=`"font-size: ${FontSize}px`"" } else { '' }
    "<text x=`"0`" y=`"$Y`" class=`"$Class`"$styleAttr text-anchor=`"middle`">$Content</text>"
}

function Format-DualKeySvg {
    param(
        [string]$Line1,
        [string]$Line2,
        [double]$Line1Y = $DualKeySpacingDefault.Line1Y,
        [double]$Line2Y = $DualKeySpacingDefault.Line2Y,
        [string]$Line1Class = 'dual-line',
        [string]$Line2Class = 'dual-line',
        $Line1FontSize = $null,
        $Line2FontSize = $null
    )
    $l1 = Escape-SvgText $Line1
    $l2 = if ($Line2 -match '^&#') { $Line2 } else { Escape-SvgText $Line2 }
    $line1 = Format-DualKeyLine -Content $l1 -Y $Line1Y -Class $Line1Class -FontSize $Line1FontSize
    $line2 = Format-DualKeyLine -Content $l2 -Y $Line2Y -Class $Line2Class -FontSize $Line2FontSize
    @"
<g class="dual-key">
$line1
$line2
</g>
"@
}

function Set-DualKeyTapGlobal {
    param(
        [string]$Svg,
        [string]$TapKey,
        [string]$TapRegex,
        [string]$Line1,
        [string]$Line2
    )
    $spacing = Get-DualKeySpacing @($TapKey)
    $replacement = Format-DualKeySvg -Line1 $Line1 -Line2 $Line2 -Line1Y $spacing.Line1Y -Line2Y $spacing.Line2Y `
        -Line1Class $spacing.Line1Class -Line2Class $spacing.Line2Class `
        -Line1FontSize $spacing.Line1FontSize -Line2FontSize $spacing.Line2FontSize
    $pattern = "<text x=`"0`" y=`"\d+`" class=`"key tap`">$TapRegex</text>"
    [regex]::Replace($Svg, $pattern, $replacement)
}

function Set-DualKeyInLayer {
    param(
        [string]$Svg,
        [string]$LayerName,
        [string]$TapKey,
        [string]$TapRegex,
        [string]$Line1,
        [string]$Line2
    )
    $spacing = Get-DualKeySpacing @($TapKey, "${LayerName}:$TapKey")
    $replacement = Format-DualKeySvg -Line1 $Line1 -Line2 $Line2 -Line1Y $spacing.Line1Y -Line2Y $spacing.Line2Y `
        -Line1Class $spacing.Line1Class -Line2Class $spacing.Line2Class `
        -Line1FontSize $spacing.Line1FontSize -Line2FontSize $spacing.Line2FontSize
    $pattern = "(class=`"layer-$LayerName`">[\s\S]*?)<text x=`"0`" y=`"\d+`" class=`"key tap`">$TapRegex</text>"
    [regex]::Replace($Svg, $pattern, "`${1}$replacement", 1)
}

function Format-StackedKeySvg {
    param(
        [string]$Line1,
        [string]$Line2,
        [string]$Line1IconMarkup = $null,
        [double]$Line1X = $StackedLine1X,
        [double]$Line1Y = $StackedLine1Y,
        [double]$Line2X = 0
    )
    if ($Line1IconMarkup) {
        $line1Block = @"
<g transform="translate($Line1X, $Line1Y)">
<text x="0" y="0" class="stacked-line1" text-anchor="start" dominant-baseline="central">$Line1</text>
$Line1IconMarkup
</g>
"@
    } else {
        $line1Block = "<text x=`"$Line1X`" y=`"$Line1Y`" class=`"stacked-line1`" text-anchor=`"start`">$Line1</text>"
    }
    @"
<g class="stacked-key">
<text x="$Line2X" y="$StackedLine2Y" class="stacked-line2" text-anchor="middle">$Line2</text>
$line1Block
</g>
"@
}

function Format-ScaledIconPath {
    param(
        [string]$ViewBox,
        [string]$PathData,
        [double]$Size,
        [string]$FillColor,
        [string]$Class = 'inline-icon'
    )
    $parts = $ViewBox -split '\s+' | ForEach-Object { [double]$_ }
    $vbW = $parts[2]
    $vbH = $parts[3]
    $scale = [math]::Round($Size / [math]::Max($vbW, $vbH), 6)
    $cx = [math]::Round($vbW / 2, 3)
    $cy = [math]::Round($vbH / 2, 3)
    $tx = -$cx
    $ty = -$cy
    @"
<g class="$Class">
<g transform="scale($scale) translate($tx, $ty)">
<path d="$PathData" style="fill: $FillColor" vector-effect="non-scaling-stroke" stroke="url(#text-stroke)" stroke-opacity="0.25" stroke-width="4" stroke-linejoin="round" stroke-linecap="round" stroke-miterlimit="1" paint-order="stroke fill"/>
</g>
</g>
"@
}

function Format-InlineIconAfterText {
    param(
        [string]$ViewBox,
        [string]$PathData,
        [double]$Size,
        [string]$FillColor,
        [double]$OffsetX,
        [double]$OffsetY = 0
    )
    $icon = Format-ScaledIconPath -ViewBox $ViewBox -PathData $PathData -Size $Size -FillColor $FillColor
    @"
<g transform="translate($OffsetX, $OffsetY)">
$icon
</g>
"@
}

function Set-StackedKeyFromTapHold {
    param(
        [string]$Svg,
        [string]$Tap,
        [string]$HoldPattern,
        [string]$Line1,
        [scriptblock]$Line2FromHold,
        [string]$Line1IconFile = $null,
        [double]$Line1IconSize = 12,
        [string]$Line1IconFill = '#F9D382',
        [double]$Line1IconOffsetX = 7,
        [double]$Line1IconOffsetY = 0,
        [double]$Line1X = $StackedLine1X,
        [double]$Line1Y = $StackedLine1Y,
        [double]$Line2X = 0
    )
    $line1IconMarkup = $null
    if ($Line1IconFile) {
        $icon = Get-SvgIconMeta $Line1IconFile
        $line1IconMarkup = Format-InlineIconAfterText -ViewBox $icon.ViewBox -PathData $icon.PathData `
            -Size $Line1IconSize -FillColor $Line1IconFill -OffsetX $Line1IconOffsetX -OffsetY $Line1IconOffsetY
    }
    $pattern = "<text x=`"0`" y=`"\d+`" class=`"key tap`">$([regex]::Escape($Tap))</text>\s*(?:<a href=`"#[^`"]+`">\s*)?<text x=`"0`" y=`"\d+`" class=`"key hold(?: layer-activator)?`">($HoldPattern)</text>\s*(?:</a>)?"
    [regex]::Replace($Svg, $pattern, {
        param($m)
        $line2 = & $Line2FromHold $m.Groups[1].Value
        Format-StackedKeySvg -Line1 $Line1 -Line2 $line2 -Line1IconMarkup $line1IconMarkup -Line1X $Line1X -Line1Y $Line1Y -Line2X $Line2X
    })
}

function Get-SvgIconMeta {
    param([string]$SvgFile)
    $content = [System.IO.File]::ReadAllText((Join-Path (Get-Location) $SvgFile))
    $viewBoxMatch = [regex]::Match($content, 'viewBox="([^"]+)"')
    if (-not $viewBoxMatch.Success) { throw "viewBox not found in $SvgFile" }
    $pathMatch = [regex]::Match($content, '<path[^>]+d="([^"]+)"')
    if (-not $pathMatch.Success) { throw "path not found in $SvgFile" }
    return @{
        ViewBox = $viewBoxMatch.Groups[1].Value
        PathData = $pathMatch.Groups[1].Value
    }
}

function Format-KeyIconSvg {
    param(
        [string]$ViewBox,
        [string]$PathData,
        [double]$Size = 24,
        [string]$FillColor = '#FFFFFF',
        [string]$Class = 'key-icon'
    )
    $icon = Format-ScaledIconPath -ViewBox $ViewBox -PathData $PathData -Size $Size -FillColor $FillColor -Class 'inline-icon'
    @"
<g class="$Class">
$icon
</g>
"@
}

function Format-KeyIconWithDigit {
    param(
        [string]$ViewBox,
        [string]$PathData,
        [string]$Digit,
        [double]$IconSize = 21,
        [string]$FillColor = '#FFFFFF',
        [double]$IconOffsetX = -6.75,
        [double]$DigitOffsetX = 6.75
    )
    $icon = Format-ScaledIconPath -ViewBox $ViewBox -PathData $PathData -Size $IconSize -FillColor $FillColor
    @"
<g class="key-icon-combo">
<g transform="translate($IconOffsetX, 0)">
$icon
</g>
<text x="$DigitOffsetX" y="1" class="key tap" text-anchor="middle" dominant-baseline="central">$Digit</text>
</g>
"@
}

function Set-KeyIconFromTap {
    param(
        [string]$Svg,
        [string]$Tap,
        [string]$IconFile,
        [double]$Size = 24,
        [string]$FillColor = '#FFFFFF'
    )
    $escapedTap = [regex]::Escape($Tap)
    $icon = Get-SvgIconMeta $IconFile
    $replacement = Format-KeyIconSvg -ViewBox $icon.ViewBox -PathData $icon.PathData -Size $Size -FillColor $FillColor
    $pattern = "(?:<a href=`"#$escapedTap`">\s*)?<text x=`"0`" y=`"\d+`" class=`"key tap(?: layer-activator)?`">$escapedTap</text>\s*(?:</a>)?"
    [regex]::Replace($Svg, $pattern, $replacement)
}

function Set-KeyBluetoothSlotFromTap {
    param(
        [string]$Svg,
        [string]$Tap,
        [string]$IconFile = 'keymap-drawer/icons/bluetooth.svg',
        [double]$IconSize = 14,
        [string]$FillColor = '#FFFFFF'
    )
    if ($Tap -notmatch '^BT(\d)$') { throw "Expected BT slot tap (BT0-BT9), got: $Tap" }
    $icon = Get-SvgIconMeta $IconFile
    $replacement = Format-KeyIconWithDigit -ViewBox $icon.ViewBox -PathData $icon.PathData `
        -Digit $Matches[1] -IconSize $IconSize -FillColor $FillColor
    $escapedTap = [regex]::Escape($Tap)
    $pattern = "(?:<a href=`"#$escapedTap`">\s*)?<text x=`"0`" y=`"\d+`" class=`"key tap(?: layer-activator)?`">$escapedTap</text>\s*(?:</a>)?"
    [regex]::Replace($Svg, $pattern, $replacement)
}

$svg = [regex]::Replace($svg, '<g class="(?:stacked-key|lang-key|dual-key)">[\s\S]*?</g>\s*', '')
$svg = [regex]::Replace($svg, '<g class="key-icon">\s*<g class="inline-icon">[\s\S]*?</g>\s*</g>\s*</g>\s*', '')
$svg = [regex]::Replace($svg, '<g class="key-icon-combo">[\s\S]*?<text[^>]*>[\s\S]*?</text>\s*</g>\s*', '')

$svg = Set-StackedKeyFromTapHold -Svg $svg -Tap 'Alt' -HoldPattern 'RUS|ENG|RU|EN' `
    -Line1 "${Lightning}Alt" -Line2FromHold {
        param($hold)
        switch ($hold) { 'RU' { 'RUS' } 'EN' { 'ENG' } default { $hold } }
    }

$svg = Set-StackedKeyFromTapHold -Svg $svg -Tap 'Esc' -HoldPattern 'Fn' `
    -Line1 $Lightning -Line2FromHold { param($hold) 'Esc' } `
    -Line1IconFile 'keymap-drawer/icons/star.svg' -Line1IconSize 12 -Line1IconFill '#F9D382' `
    -Line1IconOffsetX 10 -Line1IconOffsetY -2.5 -Line1X -11

$Backtick = [char]0x60
$CyrE = [char]0x0415      # Е
$CyrYo = [char]0x0401      # Ё
$CyrShcha = [char]0x0429  # Щ
$CyrSha = [char]0x0428   # Ш
$CyrHard = [char]0x042A   # Ъ
$CyrSoft = [char]0x042C   # Ь

$svg = Set-StackedKeyFromTapHold -Svg $svg -Tap $Backtick -HoldPattern $CyrE `
    -Line1 "$Lightning$CyrYo" -Line2FromHold { param($hold) $hold } -Line2X 10
$svg = Set-StackedKeyFromTapHold -Svg $svg -Tap $CyrShcha -HoldPattern $CyrSha `
    -Line1 "$Lightning$CyrShcha" -Line2FromHold { param($hold) $hold } -Line2X 10
$svg = Set-StackedKeyFromTapHold -Svg $svg -Tap $CyrHard -HoldPattern $CyrSoft `
    -Line1 "$Lightning$CyrHard" -Line2FromHold { param($hold) $hold } -Line2X 10

$SpaceSymbol = '&#x2423;'
$EnterSymbol = '&#x21B5;'

$svg = Set-DualKeyTapGlobal -Svg $svg -TapKey ';' -TapRegex ';' -Line1 ':' -Line2 ';'
$svg = Set-DualKeyTapGlobal -Svg $svg -TapKey "'" -TapRegex '(?:&#x27;|'')' -Line1 '"' -Line2 "'"
$svg = Set-DualKeyTapGlobal -Svg $svg -TapKey ',' -TapRegex ',' -Line1 '<' -Line2 ','
$svg = Set-DualKeyInLayer -Svg $svg -LayerName 'Colemak' -TapKey '/' -TapRegex '/' -Line1 '?' -Line2 '/'
$svg = Set-DualKeyTapGlobal -Svg $svg -TapKey 'Space' -TapRegex 'Space' -Line1 'Space' -Line2 "$SpaceSymbol"
$svg = Set-DualKeyTapGlobal -Svg $svg -TapKey 'Enter' -TapRegex 'Enter' -Line1 'Enter' -Line2 "$EnterSymbol"
$svg = Set-DualKeyInLayer -Svg $svg -LayerName 'Colemak' -TapKey '.' -TapRegex '\.' -Line1 '>' -Line2 '.'
$svg = Set-DualKeyInLayer -Svg $svg -LayerName 'Russian' -TapKey '.' -TapRegex '\.' -Line1 ',' -Line2 '.'
$svg = Set-KeyIconFromTap -Svg $svg -Tap 'Lower' -IconFile 'keymap-drawer/icons/star.svg' -Size 18 -FillColor '#82C4F9'
$svg = Set-KeyIconFromTap -Svg $svg -Tap 'Raise' -IconFile 'keymap-drawer/icons/star.svg' -Size 18 -FillColor '#E582F9'

$LegendIconSize = 17
$TextIconFill = '#FFFFFF'
$svg = Set-KeyIconFromTap -Svg $svg -Tap 'Vol-' -IconFile 'keymap-drawer/icons/volume_down.svg' -Size $LegendIconSize -FillColor $TextIconFill
$svg = Set-KeyIconFromTap -Svg $svg -Tap 'Vol+' -IconFile 'keymap-drawer/icons/volume_up.svg' -Size $LegendIconSize -FillColor $TextIconFill
$svg = Set-KeyIconFromTap -Svg $svg -Tap 'Mute' -IconFile 'keymap-drawer/icons/volume_off.svg' -Size $LegendIconSize -FillColor $TextIconFill
$svg = Set-KeyIconFromTap -Svg $svg -Tap 'Up' -IconFile 'keymap-drawer/icons/up.svg' -Size $LegendIconSize -FillColor $TextIconFill
$svg = Set-KeyIconFromTap -Svg $svg -Tap 'Down' -IconFile 'keymap-drawer/icons/down.svg' -Size $LegendIconSize -FillColor $TextIconFill
$svg = Set-KeyIconFromTap -Svg $svg -Tap 'Left' -IconFile 'keymap-drawer/icons/left.svg' -Size $LegendIconSize -FillColor $TextIconFill
$svg = Set-KeyIconFromTap -Svg $svg -Tap 'Right' -IconFile 'keymap-drawer/icons/right.svg' -Size $LegendIconSize -FillColor $TextIconFill

$BtIconSize = 21
$svg = Set-KeyIconFromTap -Svg $svg -Tap 'BT_CLR' -IconFile 'keymap-drawer/icons/bluetooth_disabled.svg' -Size $BtIconSize -FillColor $TextIconFill
foreach ($btSlot in 0..4) {
    $svg = Set-KeyBluetoothSlotFromTap -Svg $svg -Tap "BT$btSlot" -IconSize $BtIconSize -FillColor $TextIconFill
}
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($svgPath, $svg, $utf8)

Write-Host "Wrote $Out"
