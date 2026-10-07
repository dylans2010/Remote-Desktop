#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Remote Desktop - iOS Release Build & IPA Packaging Script
# ==============================================================================
# Builds an unsigned .ipa of Remote Desktop for iOS and reveals it in Finder.
# ==============================================================================

# Ensure standard utilities take precedence to prevent interactive aliases
export PATH="/bin:/usr/bin:/opt/homebrew/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> [iOS Build] Project Root: $PROJECT_ROOT"

SCHEME_NAME="Remote Desktop-iOS"
CONFIGURATION="Release"
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
OUTPUT_DIR="$BUILD_DIR/Artifacts"
IPA_NAME="Remote-Desktop-iOS.ipa"
FINAL_IPA="$OUTPUT_DIR/$IPA_NAME"

# 1. Ensure assets and icons exist
if [[ ! -f "$PROJECT_ROOT/Sources/iOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" ]]; then
    echo "==> [iOS Build] Assets missing. Generating application assets..."
    swift "$PROJECT_ROOT/Scripts/generate-assets.swift"
fi

# 2. Build iOS target with xcodebuild (unsigned)
echo "==> [iOS Build] Compiling $SCHEME_NAME in $CONFIGURATION configuration..."
mkdir -p "$OUTPUT_DIR"

xcodebuild \
    -project "$PROJECT_ROOT/Remote Desktop.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -destination "generic/platform=iOS" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

BUILT_APP="$DERIVED_DATA/Build/Products/Release-iphoneos/Remote Desktop.app"

if [[ ! -d "$BUILT_APP" ]]; then
    echo "ERROR: Built application bundle not found at: $BUILT_APP" >&2
    exit 1
fi

echo "==> [iOS Build] Application successfully compiled: $BUILT_APP"

# 3. Compile Asset Catalog and inject icon files into application bundle
echo "==> [iOS Build] Compiling asset catalogs and copying icons..."
xcrun actool \
    --output-format human-readable-text \
    --notices \
    --warnings \
    --platform iphoneos \
    --minimum-deployment-target 17.0 \
    --app-icon AppIcon \
    --output-partial-info-plist /tmp/partial_info.plist \
    --compile "$BUILT_APP" \
    "$PROJECT_ROOT/Sources/iOS/Resources/Assets.xcassets" >/dev/null 2>&1 || true

# Copy fallback PNG icons directly into app bundle for wide compatibility (Sideloadly, AltStore, etc.)
cp -f "$PROJECT_ROOT"/Sources/iOS/Resources/AppIcon-*.png "$BUILT_APP/" 2>/dev/null || true

# 4. Package into unsigned .ipa
echo "==> [iOS Build] Packaging into unsigned .ipa..."
IPA_TEMP="$(mktemp -d /tmp/remote-desktop-ipa.XXXXXX)"
mkdir -p "$IPA_TEMP/Payload"
cp -R "$BUILT_APP" "$IPA_TEMP/Payload/"

rm -f "$FINAL_IPA"
(cd "$IPA_TEMP" && /usr/bin/zip -q -r -y "$FINAL_IPA" Payload)
rm -rf "$IPA_TEMP"

echo "=============================================================================="
echo " SUCCESS: Unsigned iOS IPA package created successfully!"
echo " Location: $FINAL_IPA"
echo " Size:     $(du -h "$FINAL_IPA" | cut -f1)"
echo "=============================================================================="

# 5. Open and reveal in Finder
if command -v open >/dev/null 2>&1; then
    echo "==> [iOS Build] Revealing $IPA_NAME in Finder..."
    open -R "$FINAL_IPA"
fi
