#!/bin/bash

# Thorion Build Script
# Builds the app in Release configuration and packages a DMG in ./release.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="$PROJECT_DIR/release"

PROJECT_NAME="thorion"
APP_NAME="thorion"
DISPLAY_NAME="Thorion"
DMG_NAME="$DISPLAY_NAME.dmg"
ARCH="${ARCH:-arm64}"
DESTINATION="platform=macOS,arch=$ARCH"

# The repo pins DEVELOPMENT_TEAM 447GJ83BJ5, which needs a certificate the
# local machine does not have. Ad-hoc signing keeps local builds working and
# matches what CI injects for unsigned artifacts.
SIGN_ARGS=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
)

# Optional version override: ./script/build.sh v0.2.2
VERSION_ARGS=()
if [ $# -ge 1 ]; then
    VERSION="${1#v}"
    if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Version '$1' must look like vX.Y.Z (e.g. ./script/build.sh v0.2.2)${NC}"
        exit 1
    fi
    BUILD_NUMBER=$(( $(git -C "$PROJECT_DIR" rev-list --count HEAD) ))
    echo -e "${YELLOW}Version override: $VERSION ($BUILD_NUMBER)${NC}"
    echo ""
    VERSION_ARGS=(MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
fi

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}   $DISPLAY_NAME Build Script${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

echo -e "${YELLOW}[1/5] Preparing release folder...${NC}"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo -e "${YELLOW}[2/5] Building $DISPLAY_NAME (Release)...${NC}"
if ! xcodebuild \
    -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$PROJECT_NAME" \
    -configuration Release \
    -destination "$DESTINATION" \
    "${SIGN_ARGS[@]}" \
    ${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"} \
    clean build; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Build succeeded!${NC}"

echo -e "${YELLOW}[3/5] Locating built app...${NC}"
BUILD_DIR=$(xcodebuild \
    -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$PROJECT_NAME" \
    -configuration Release \
    -destination "$DESTINATION" \
    ${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"} \
    -showBuildSettings 2>/dev/null \
    | sed -n 's/^ *BUILT_PRODUCTS_DIR *= *//p' \
    | head -1)

if [ -z "$BUILD_DIR" ]; then
    echo -e "${RED}Error: could not resolve BUILT_PRODUCTS_DIR${NC}"
    exit 1
fi

APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: built app not found at $APP_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}Found app at: $APP_PATH${NC}"

# Re-sign the bundle so the embedded XPC services (helper, charging-helper)
# carry the same identity as the host app; a mismatch fails at XPC connect.
echo -e "${YELLOW}[4/5] Re-signing app (ad-hoc)...${NC}"
codesign --force --deep --sign - "$APP_PATH"

if ! codesign --verify --deep --strict "$APP_PATH"; then
    echo -e "${RED}Signature verification failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Signature OK!${NC}"

echo -e "${YELLOW}[5/5] Creating DMG...${NC}"
TMP_DIR=$(mktemp -d)
# ditto (not cp -R) preserves symlinks, signatures and resource forks
ditto "$APP_PATH" "$TMP_DIR/$APP_NAME.app"
ln -sf /Applications "$TMP_DIR/Applications"

DMG_PATH="$RELEASE_DIR/$DMG_NAME"
if ! hdiutil create \
    -volname "$DISPLAY_NAME" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"; then
    rm -rf "$TMP_DIR"
    echo -e "${RED}Failed to create DMG!${NC}"
    exit 1
fi
rm -rf "$TMP_DIR"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "DMG file: ${GREEN}${DMG_PATH}${NC}"
echo ""
echo -e "Size: ${GREEN}$(ls -lh "$DMG_PATH" | awk '{print $5}')${NC}"
echo ""

open "$RELEASE_DIR"