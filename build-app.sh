#!/bin/bash
# Build script for Airtype.app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building Airtype..."
swift build -c release

echo "Creating app bundle..."
APP_NAME="Airtype"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Clean previous bundle
rm -rf "$APP_BUNDLE"

# Create bundle structure
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$MACOS/"

# Copy Info.plist
cp "Info.plist" "$CONTENTS/"

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

echo "App bundle created at: $APP_BUNDLE"
echo ""
echo "To run the app:"
echo "  open $APP_BUNDLE"
echo ""
echo "Or to test without bundling:"
echo "  swift run"
