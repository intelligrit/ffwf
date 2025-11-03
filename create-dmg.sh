#!/bin/bash
set -e

# Version info
VERSION=${1:-1.1.2}
APP_NAME="FFWF"
DMG_NAME="${APP_NAME}-${VERSION}"
APP_PATH="${APP_NAME}.app"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found. Run 'make app' first."
    exit 1
fi

# Create temporary directory for DMG contents
TMP_DIR=$(mktemp -d)
echo "Creating DMG contents in $TMP_DIR..."

# Copy app to temp directory
cp -r "$APP_PATH" "$TMP_DIR/"

# Create Applications symlink
ln -s /Applications "$TMP_DIR/Applications"

# Create DMG
echo "Creating DMG..."
DMG_PATH="${DMG_NAME}.dmg"
rm -f "$DMG_PATH"

# Create DMG with hdiutil
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$TMP_DIR" \
    -ov -format UDZO \
    -fs HFS+ \
    "$DMG_PATH"

# Clean up temp directory
rm -rf "$TMP_DIR"

# Copy to docs directory for GitHub Pages
if [ -d "docs" ]; then
    echo "Copying DMG to docs/ for GitHub Pages..."
    cp "$DMG_PATH" "docs/"
fi

echo ""
echo "✓ DMG created successfully: $DMG_PATH"
echo ""
echo "To distribute:"
echo "  1. Test the DMG: open $DMG_PATH"
echo "  2. Drag FFWF.app to Applications to install"
echo ""
echo "For GitHub Pages:"
echo "  1. Commit docs/ directory with: git add docs && git commit -m 'Release v${VERSION}'"
echo "  2. Push to GitHub: git push"
echo "  3. Enable GitHub Pages in repository settings (source: docs/)"
echo ""
