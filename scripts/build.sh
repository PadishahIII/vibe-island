#!/bin/bash
# Build Codex Island for release
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/CodexIsland.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
SCHEME="CodexIsland"
APP_NAME="Codex Island"

run_xcodebuild() {
    if command -v xcpretty >/dev/null 2>&1; then
        if ! xcodebuild "$@" | xcpretty; then
            return "${PIPESTATUS[0]}"
        fi

        return 0
    fi

    xcodebuild "$@"
}

detect_team_id() {
    if [ -n "${CODEX_ISLAND_TEAM_ID:-}" ]; then
        echo "$CODEX_ISLAND_TEAM_ID"
        return
    fi

    if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
        echo "$DEVELOPMENT_TEAM"
        return
    fi

    local detected
    detected=$(
        xcodebuild -showBuildSettings -scheme "$SCHEME" -configuration Release 2>/dev/null \
            | sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM = //p' \
            | head -n 1
    )

    if [ -n "$detected" ]; then
        echo "$detected"
    fi
}

TEAM_ID="$(detect_team_id)"
ARCHIVE_APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

echo "=== Building Codex Island ==="
echo ""

# Clean previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$PROJECT_DIR"

# Build and archive
echo "Archiving..."
archive_args=(
    archive
    -scheme "$SCHEME"
    -configuration Release
    -archivePath "$ARCHIVE_PATH"
    -destination "generic/platform=macOS"
    ENABLE_HARDENED_RUNTIME=YES
)

if [ -n "$TEAM_ID" ]; then
    archive_args+=(
        CODE_SIGN_STYLE=Automatic
        CODE_SIGNING_ALLOWED=YES
        DEVELOPMENT_TEAM="$TEAM_ID"
    )
else
    archive_args+=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGNING_ALLOWED=NO
        CODE_SIGNING_REQUIRED=NO
    )
fi

run_xcodebuild "${archive_args[@]}"

if [ -z "$TEAM_ID" ]; then
    echo ""
    echo "No DEVELOPMENT_TEAM configured. Exporting unsigned app from archive..."

    if [ ! -d "$ARCHIVE_APP_PATH" ]; then
        echo "ERROR: Archived app not found at $ARCHIVE_APP_PATH"
        exit 1
    fi

    mkdir -p "$EXPORT_PATH"
    ditto "$ARCHIVE_APP_PATH" "$EXPORT_PATH/$APP_NAME.app"

    echo ""
    echo "=== Build Complete ==="
    echo "Unsigned app exported to: $EXPORT_PATH/$APP_NAME.app"
    echo ""
    echo "To create a signed Developer ID export, rerun with:"
    echo "  DEVELOPMENT_TEAM=YOURTEAMID ./scripts/build.sh"
    exit 0
fi

# Create ExportOptions.plist if it doesn't exist
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
EOF

# Export the archive
echo ""
echo "Exporting..."
run_xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

echo ""
echo "=== Build Complete ==="
echo "App exported to: $EXPORT_PATH/$APP_NAME.app"
echo ""
echo "Next: Run ./scripts/create-release.sh to notarize and create DMG"
