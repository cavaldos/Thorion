#!/bin/bash
# Step 1: build the DMG, tag the commit and publish it as the LATEST GitHub Release.
# Usage: ./script/release.sh vX.Y.Z   (e.g. ./script/release.sh v0.3.0)
# Next:  ./script/notify-update.sh vX.Y.Z to bump the Homebrew cask.
# Needs: gh (logged in), Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")/.."

REPOSITORY="cavaldos/Thorion"
DMG_PATH="release/Thorion.dmg"

TAG="${1:-}"
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: $0 vX.Y.Z   (e.g. $0 v0.3.0)"
    exit 1
fi
command -v gh >/dev/null || { echo "missing gh — brew install gh"; exit 1; }
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "tag '$TAG' already exists"
    exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "working tree dirty — commit or stash first"
    exit 1
fi

# build.sh injects MARKETING_VERSION from the tag, so Xcode never needs a manual bump.
./script/build.sh "$TAG"
[ -f "$DMG_PATH" ] || { echo "build did not produce $DMG_PATH"; exit 1; }

git tag "$TAG"
git push origin "$TAG"

# Published as latest right away: installed apps see it on their next daily check.
gh release create "$TAG" "$DMG_PATH" \
    --repo "$REPOSITORY" \
    --title "Thorion $TAG" \
    --generate-notes \
    --latest

echo ""
echo "Release $TAG published as latest: https://github.com/$REPOSITORY/releases/tag/$TAG"
echo "Next, update Homebrew: ./script/notify-update.sh $TAG"
