#!/bin/bash

# Usage: ./script/run.sh — build Debug and launch the app locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

PROJECT_NAME="thorion"
APP_NAME="thorion"
ARCH="${ARCH:-arm64}"
DESTINATION="platform=macOS,arch=$ARCH"

# Same reason as build.sh: the pinned DEVELOPMENT_TEAM has no local certificate.
SIGN_ARGS=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
)

cd "$PROJECT_DIR"

xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$PROJECT_NAME" \
    -configuration Debug \
    -destination "$DESTINATION" \
    "${SIGN_ARGS[@]}" \
    build

BUILD_DIR=$(xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$PROJECT_NAME" \
    -configuration Debug \
    -destination "$DESTINATION" \
    -showBuildSettings 2>/dev/null \
    | sed -n 's/^ *BUILT_PRODUCTS_DIR *= *//p' \
    | head -1)

APP_PATH="$BUILD_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: built app not found at $APP_PATH"
    exit 1
fi

codesign --force --deep --sign - "$APP_PATH"

pkill -x "$APP_NAME" 2>/dev/null || true
open "$APP_PATH"