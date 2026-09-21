#!/usr/bin/env bash
# Generate Textractor logo assets from source SVG
# Requires: imagemagick (brew install imagemagick), rsvg-convert (brew install librsvg)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PRESS_KIT_DIR="${ROOT_DIR}/marketing/press_kit"
LOGOS_DIR="${PRESS_KIT_DIR}/logos"
SCREENSHOTS_DIR="${PRESS_KIT_DIR}/screenshots"

mkdir -p "$LOGOS_DIR" "$SCREENSHOTS_DIR"

# Source SVG (create if missing)
SOURCE_SVG="${LOGOS_DIR}/logo-source.svg"

if [[ ! -f "$SOURCE_SVG" ]]; then
    cat > "$SOURCE_SVG" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#0B100A"/>
      <stop offset="100%" style="stop-color:#1a250f"/>
    </linearGradient>
    <linearGradient id="accentGrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" style="stop-color:#6BB534"/>
      <stop offset="100%" style="stop-color:#29ABE0"/>
    </linearGradient>
  </defs>
  
  <!-- Background rounded rect -->
  <rect x="64" y="64" width="896" height="896" rx="180" fill="url(#bgGrad)"/>
  
  <!-- Scanner beam -->
  <g transform="translate(512, 512)">
    <!-- Document outline -->
    <rect x="-200" y="-160" width="400" height="320" rx="16" fill="none" stroke="url(#accentGrad)" stroke-width="8"/>
    
    <!-- Text lines -->
    <g fill="#E6EADC" opacity="0.9">
      <rect x="-160" y="-100" width="280" height="16" rx="4"/>
      <rect x="-160" y="-70" width="240" height="16" rx="4"/>
      <rect x="-160" y="-40" width="300" height="16" rx="4"/>
      <rect x="-160" y="-10" width="200" height="16" rx="4"/>
      <rect x="-160" y="20" width="260" height="16" rx="4" opacity="0.6"/>
      <rect x="-160" y="50" width="180" height="16" rx="4" opacity="0.4"/>
    </g>
    
    <!-- Scanning beam -->
    <rect x="-170" y="-20" width="340" height="40" rx="4" fill="url(#accentGrad)" opacity="0.3">
      <animate attributeName="y" from="-120" to="80" dur="2s" repeatCount="indefinite"/>
    </rect>
    
    <!-- Cursor indicator -->
    <polygon points="-190,-130 -170,-110 -190,-90" fill="#6BB534"/>
  </g>
  
  <!-- "T" mark in corner -->
  <text x="512" y="880" font-family="-apple-system, SF Pro Display, sans-serif" 
        font-size="120" font-weight="700" fill="url(#accentGrad)" 
        text-anchor="middle" dominant-baseline="middle">T</text>
</svg>
SVGEOF
    echo "✅ Created source SVG: $SOURCE_SVG"
fi

# Check for conversion tools
if ! command -v rsvg-convert &> /dev/null; then
    echo "⚠️  rsvg-convert not found. Install with: brew install librsvg"
    echo "   Falling back to imagemagick..."
    USE_MAGICK=true
else
    USE_MAGICK=false
fi

if ! command -v magick &> /dev/null && ! command -v convert &> /dev/null; then
    if [[ "$USE_MAGICK" == "true" ]]; then
        echo "❌ Neither rsvg-convert nor imagemagick found."
        echo "   Install: brew install librsvg imagemagick"
        exit 1
    fi
fi

CONVERT_CMD=""
if command -v magick &> /dev/null; then
    CONVERT_CMD="magick"
elif command -v convert &> /dev/null; then
    CONVERT_CMD="convert"
fi

# Generate PNG sizes
SIZES=(16 32 48 64 128 256 512 1024)

echo "🎨 Generating logo assets..."
for size in "${SIZES[@]}"; do
    output="${LOGOS_DIR}/icon-${size}.png"
    
    if [[ "$USE_MAGICK" == "false" ]]; then
        rsvg-convert -w "$size" -h "$size" "$SOURCE_SVG" -o "$output"
    else
        $CONVERT_CMD "$SOURCE_SVG" -resize "${size}x${size}" "$output"
    fi
    
    echo "  ✅ icon-${size}.png"
done

# Generate horizontal lockup (1200x400)
cat > "${LOGOS_DIR}/logo-horizontal.svg" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg width="1200" height="400" viewBox="0 0 1200 400" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="accentGrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" style="stop-color:#6BB534"/>
      <stop offset="100%" style="stop-color:#29ABE0"/>
    </linearGradient>
  </defs>
  <!-- Icon -->
  <g transform="translate(60, 60)">
    <rect x="0" y="0" width="280" height="280" rx="56" fill="#0B100A"/>
    <g transform="translate(140, 140)">
      <rect x="-80" y="-64" width="160" height="128" rx="8" fill="none" stroke="url(#accentGrad)" stroke-width="4"/>
      <g fill="#E6EADC" opacity="0.9">
        <rect x="-64" y="-40" width="112" height="10" rx="2"/>
        <rect x="-64" y="-24" width="96" height="10" rx="2"/>
        <rect x="-64" y="-8" width="120" height="10" rx="2"/>
        <rect x="-64" y="8" width="80" height="10" rx="2"/>
        <rect x="-64" y="24" width="104" height="10" rx="2" opacity="0.6"/>
      </g>
    </g>
  </g>
  <!-- Text -->
  <text x="380" y="240" font-family="-apple-system, SF Pro Display, sans-serif" 
        font-size="80" font-weight="700" fill="url(#accentGrad)" 
        dominant-baseline="middle">Textractor</text>
  <text x="380" y="290" font-family="-apple-system, SF Pro Text, sans-serif" 
        font-size="24" fill="#E6EADC" opacity="0.7"
        dominant-baseline="middle">Privacy-first OCR for Mac</text>
</svg>
SVGEOF

if [[ "$USE_MAGICK" == "false" ]]; then
    rsvg-convert -w 1200 -h 400 "${LOGOS_DIR}/logo-horizontal.svg" -o "${LOGOS_DIR}/logo-horizontal.png"
else
    $CONVERT_CMD "${LOGOS_DIR}/logo-horizontal.svg" -resize "1200x400" "${LOGOS_DIR}/logo-horizontal.png"
fi
echo "  ✅ logo-horizontal.png"

# Generate vertical lockup (400x800)
cat > "${LOGOS_DIR}/logo-vertical.svg" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg width="400" height="800" viewBox="0 0 400 800" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="accentGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#6BB534"/>
      <stop offset="100%" style="stop-color:#29ABE0"/>
    </linearGradient>
  </defs>
  <!-- Icon -->
  <g transform="translate(60, 80)">
    <rect x="0" y="0" width="280" height="280" rx="56" fill="#0B100A"/>
    <g transform="translate(140, 140)">
      <rect x="-80" y="-64" width="160" height="128" rx="8" fill="none" stroke="url(#accentGrad)" stroke-width="4"/>
      <g fill="#E6EADC" opacity="0.9">
        <rect x="-64" y="-40" width="112" height="10" rx="2"/>
        <rect x="-64" y="-24" width="96" height="10" rx="2"/>
        <rect x="-64" y="-8" width="120" height="10" rx="2"/>
        <rect x="-64" y="8" width="80" height="10" rx="2"/>
        <rect x="-64" y="24" width="104" height="10" rx="2" opacity="0.6"/>
      </g>
    </g>
  </g>
  <!-- Text -->
  <text x="200" y="420" font-family="-apple-system, SF Pro Display, sans-serif" 
        font-size="64" font-weight="700" fill="url(#accentGrad)" 
        text-anchor="middle" dominant-baseline="middle">Textractor</text>
  <text x="200" y="470" font-family="-apple-system, SF Pro Text, sans-serif" 
        font-size="20" fill="#E6EADC" opacity="0.7"
        text-anchor="middle" dominant-baseline="middle">Privacy-first OCR for Mac</text>
</svg>
SVGEOF

if [[ "$USE_MAGICK" == "false" ]]; then
    rsvg-convert -w 400 -h 800 "${LOGOS_DIR}/logo-vertical.svg" -o "${LOGOS_DIR}/logo-vertical.png"
else
    $CONVERT_CMD "${LOGOS_DIR}/logo-vertical.svg" -resize "400x800" "${LOGOS_DIR}/logo-vertical.png"
fi
echo "  ✅ logo-vertical.png"

# White version (for dark backgrounds)
cat > "${LOGOS_DIR}/logo-white.svg" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <g transform="translate(512, 512)">
    <rect x="-200" y="-160" width="400" height="320" rx="16" fill="none" stroke="#FFFFFF" stroke-width="8"/>
    <g fill="#FFFFFF" opacity="0.95">
      <rect x="-160" y="-100" width="280" height="16" rx="4"/>
      <rect x="-160" y="-70" width="240" height="16" rx="4"/>
      <rect x="-160" y="-40" width="300" height="16" rx="4"/>
      <rect x="-160" y="-10" width="200" height="16" rx="4"/>
      <rect x="-160" y="20" width="260" height="16" rx="4" opacity="0.6"/>
      <rect x="-160" y="50" width="180" height="16" rx="4" opacity="0.4"/>
    </g>
    <polygon points="-190,-130 -170,-110 -190,-90" fill="#FFFFFF"/>
  </g>
</svg>
SVGEOF

if [[ "$USE_MAGICK" == "false" ]]; then
    rsvg-convert -w 1024 -h 1024 "${LOGOS_DIR}/logo-white.svg" -o "${LOGOS_DIR}/logo-white.png"
else
    $CONVERT_CMD "${LOGOS_DIR}/logo-white.svg" -resize "1024x1024" "${LOGOS_DIR}/logo-white.png"
fi
echo "  ✅ logo-white.png"

# Black version (for light backgrounds)
cat > "${LOGOS_DIR}/logo-black.svg" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <g transform="translate(512, 512)">
    <rect x="-200" y="-160" width="400" height="320" rx="16" fill="none" stroke="#0B100A" stroke-width="8"/>
    <g fill="#0B100A" opacity="0.95">
      <rect x="-160" y="-100" width="280" height="16" rx="4"/>
      <rect x="-160" y="-70" width="240" height="16" rx="4"/>
      <rect x="-160" y="-40" width="300" height="16" rx="4"/>
      <rect x="-160" y="-10" width="200" height="16" rx="4"/>
      <rect x="-160" y="20" width="260" height="16" rx="4" opacity="0.6"/>
      <rect x="-160" y="50" width="180" height="16" rx="4" opacity="0.4"/>
    </g>
    <polygon points="-190,-130 -170,-110 -190,-90" fill="#0B100A"/>
  </g>
</svg>
SVGEOF

if [[ "$USE_MAGICK" == "false" ]]; then
    rsvg-convert -w 1024 -h 1024 "${LOGOS_DIR}/logo-black.svg" -o "${LOGOS_DIR}/logo-black.png"
else
    $CONVERT_CMD "${LOGOS_DIR}/logo-black.svg" -resize "1024x1024" "${LOGOS_DIR}/logo-black.png"
fi
echo "  ✅ logo-black.png"

# Generate favicon.ico (multi-res)
if command -v magick &> /dev/null; then
    magick "${LOGOS_DIR}/icon-16.png" "${LOGOS_DIR}/icon-32.png" "${LOGOS_DIR}/icon-48.png" "${LOGOS_DIR}/icon-64.png" "${LOGOS_DIR}/favicon.ico"
    echo "  ✅ favicon.ico"
elif command -v convert &> /dev/null; then
    convert "${LOGOS_DIR}/icon-16.png" "${LOGOS_DIR}/icon-32.png" "${LOGOS_DIR}/icon-48.png" "${LOGOS_DIR}/icon-64.png" "${LOGOS_DIR}/favicon.ico"
    echo "  ✅ favicon.ico"
fi

# Generate favicon.svg
cp "${LOGOS_DIR}/logo-source.svg" "${LOGOS_DIR}/favicon.svg"
echo "  ✅ favicon.svg"

# Create placeholder screenshots structure
cat > "${SCREENSHOTS_DIR}/README.md" << 'EOF'
# App Store Screenshots

Place your 1280x800 screenshots here:

| File | Description |
|------|-------------|
| `01-capture-overlay.png` | Region capture with live OCR preview grid |
| `02-window-capture.png` | Window picker mode |
| `03-history-grid.png` | History with thumbnails |
| `04-source-code-mode.png` | Settings: Source Code Mode enabled |
| `05-translation-settings.png` | Translation target language picker |
| `06-toast-actions.png` | Toast with Translate/Format Code buttons |
| `07-pii-redaction.png` | Privacy: PII Redaction enabled |

Run `../scripts/capture_screenshots.sh` to automate capture.
EOF

echo ""
echo "🎉 Press kit generated in: $PRESS_KIT_DIR"
echo ""
echo "Structure:"
find "$PRESS_KIT_DIR" -type f | sort