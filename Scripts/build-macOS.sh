#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Remote Desktop - macOS Release Build & Styled DMG Installer Script
# ==============================================================================
# Builds Remote Desktop for macOS, packages it into a styled .dmg with custom
# background art, SF Symbols, and Applications symlink, then reveals it in Finder.
# ==============================================================================

# Ensure standard utilities take precedence to prevent interactive aliases
export PATH="/bin:/usr/bin:/opt/homebrew/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> [macOS Build] Project Root: $PROJECT_ROOT"

SCHEME_NAME="Remote Desktop-macOS"
CONFIGURATION="Release"
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
OUTPUT_DIR="$BUILD_DIR/Artifacts"
DMG_NAME="Remote-Desktop-macOS.dmg"
FINAL_DMG="$OUTPUT_DIR/$DMG_NAME"

# 1. Ensure assets and icons exist
if [[ ! -f "$PROJECT_ROOT/Sources/macOS/Resources/AppIcon.icns" || ! -f "$PROJECT_ROOT/Scripts/assets/dmg-background.png" ]]; then
    echo "==> [macOS Build] Assets missing. Generating application assets..."
    swift "$PROJECT_ROOT/Scripts/generate-assets.swift"
fi

# 2. Build macOS target with xcodebuild
echo "==> [macOS Build] Compiling $SCHEME_NAME in $CONFIGURATION configuration..."
mkdir -p "$OUTPUT_DIR"

xcodebuild \
    -project "$PROJECT_ROOT/Remote Desktop.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

BUILT_APP="$DERIVED_DATA/Build/Products/Release/Remote Desktop.app"

if [[ ! -d "$BUILT_APP" ]]; then
    echo "ERROR: Built application bundle not found at: $BUILT_APP" >&2
    exit 1
fi

echo "==> [macOS Build] Application successfully compiled: $BUILT_APP"

# 3. Inject macOS depth icon into bundle Resources
echo "==> [macOS Build] Embedding AppIcon.icns and compiling asset catalog..."
mkdir -p "$BUILT_APP/Contents/Resources"
cp -f "$PROJECT_ROOT/Sources/macOS/Resources/AppIcon.icns" "$BUILT_APP/Contents/Resources/AppIcon.icns"

xcrun actool \
    --output-format human-readable-text \
    --notices \
    --warnings \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --compile "$BUILT_APP/Contents/Resources" \
    "$PROJECT_ROOT/Sources/macOS/Resources/Assets.xcassets" >/dev/null 2>&1 || true

# Strip quarantine and apply clean ad-hoc signature
xattr -cr "$BUILT_APP" 2>/dev/null || true
codesign --force --deep --sign - "$BUILT_APP" 2>/dev/null || true

# 4. Package into styled .dmg installer
echo "==> [macOS Build] Packaging into styled DMG installer..."
rm -f "$FINAL_DMG"

STAGING_DIR="$(mktemp -d /tmp/remote-desktop-dmg.XXXXXX)"
cp -R "$BUILT_APP" "$STAGING_DIR/"

BG_IMAGE="$PROJECT_ROOT/Scripts/assets/dmg-background.png"
VOL_ICON="$PROJECT_ROOT/Scripts/assets/volume-icon.icns"

if command -v create-dmg >/dev/null 2>&1; then
    echo "==> [macOS Build] Using create-dmg for styled installer layout..."
    set +e
    create-dmg \
        --volname "Remote Desktop" \
        --volicon "$VOL_ICON" \
        --background "$BG_IMAGE" \
        --window-pos 200 120 \
        --window-size 660 420 \
        --icon-size 128 \
        --icon "Remote Desktop.app" 170 205 \
        --app-drop-link 490 205 \
        --hide-extension "Remote Desktop.app" \
        --format UDZO \
        --hdiutil-quiet \
        --overwrite \
        "$FINAL_DMG" \
        "$STAGING_DIR"
    CREATE_DMG_EXIT=$?
    set -e

    if [[ $CREATE_DMG_EXIT -ne 0 || ! -f "$FINAL_DMG" ]]; then
        echo "==> [macOS Build] create-dmg encountered an issue; falling back to direct hdiutil build..."
        ln -s /Applications "$STAGING_DIR/Applications"
        hdiutil create -volname "Remote Desktop" -srcfolder "$STAGING_DIR" -ov -format UDZO "$FINAL_DMG" -quiet
    fi
else
    echo "==> [macOS Build] create-dmg not found. Falling back to native hdiutil..."
    ln -s /Applications "$STAGING_DIR/Applications"
    hdiutil create -volname "Remote Desktop" -srcfolder "$STAGING_DIR" -ov -format UDZO "$FINAL_DMG" -quiet
fi

rm -rf "$STAGING_DIR"

echo "=============================================================================="
echo " SUCCESS: Styled macOS DMG installer created successfully!"
echo " Location: $FINAL_DMG"
echo " Size:     $(du -h "$FINAL_DMG" | cut -f1)"
echo "=============================================================================="

# 5. Open and reveal in Finder
if command -v open >/dev/null 2>&1; then
    echo "==> [macOS Build] Revealing $DMG_NAME in Finder..."
    open -R "$FINAL_DMG"
fi
