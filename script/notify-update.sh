#!/bin/bash
# Step 2: publish the draft release and bump the Homebrew cask, so users hear about it.
#   - Installed apps poll GitHub's "latest release" daily and show a notification.
#   - Homebrew users get the new version with `brew upgrade`.
# Usage: ./script/notify-update.sh vX.Y.Z [--skip-brew]
# Needs: gh (logged in) with push access to cavaldos/homebrew-tap.
set -euo pipefail
cd "$(dirname "$0")/.."

REPOSITORY="cavaldos/Thorion"
TAP_REPOSITORY="cavaldos/homebrew-tap"
CASK_PATH="Casks/thorion.rb"
DMG_NAME="Thorion.dmg"

TAG=""
SKIP_BREW=false
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-brew) SKIP_BREW=true; shift;;
        -h|--help) sed -n '2,7p' "$0"; exit 0;;
        v*) TAG="$1"; shift;;
        *) echo "unknown arg: $1"; exit 1;;
    esac
done
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: $0 vX.Y.Z [--skip-brew]"
    exit 1
fi
command -v gh >/dev/null || { echo "missing gh — brew install gh"; exit 1; }
VERSION="${TAG#v}"

echo "[1/2] Publishing release $TAG..."
IS_DRAFT=$(gh release view "$TAG" --repo "$REPOSITORY" --json isDraft --jq .isDraft) \
    || { echo "release $TAG not found — run ./script/release.sh $TAG first"; exit 1; }
if [ "$IS_DRAFT" = "true" ]; then
    gh release edit "$TAG" --repo "$REPOSITORY" --draft=false --latest
else
    echo "already published"
fi

LATEST_TAG=$(gh api "repos/$REPOSITORY/releases/latest" --jq .tag_name)
if [ "$LATEST_TAG" != "$TAG" ]; then
    echo "warning: GitHub reports $LATEST_TAG as latest, not $TAG — apps will not see this update"
fi

if [ "$SKIP_BREW" = true ]; then
    echo "[2/2] Skipping Homebrew cask"
    exit 0
fi

echo "[2/2] Updating Homebrew cask..."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

gh release download "$TAG" --repo "$REPOSITORY" --pattern "$DMG_NAME" --dir "$WORK"
SHA256=$(shasum -a 256 "$WORK/$DMG_NAME" | awk '{print $1}')

gh repo clone "$TAP_REPOSITORY" "$WORK/tap" -- --depth 1 >/dev/null \
    || { echo "cannot clone $TAP_REPOSITORY — create it on GitHub first"; exit 1; }
mkdir -p "$WORK/tap/Casks"

cat > "$WORK/tap/$CASK_PATH" <<EOF
cask "thorion" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPOSITORY/releases/download/v#{version}/$DMG_NAME"
  name "Thorion"
  desc "Menu bar battery monitor and charge limiter for Apple Silicon MacBooks"
  homepage "https://github.com/$REPOSITORY"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "thorion.app"

  zap trash: "~/Library/Preferences/com.thorion.app.plist"
end
EOF

git -C "$WORK/tap" add "$CASK_PATH"
if git -C "$WORK/tap" diff --cached --quiet; then
    echo "cask already at $VERSION"
else
    git -C "$WORK/tap" \
        -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
        commit -m "thorion $VERSION" >/dev/null
    git -C "$WORK/tap" push origin HEAD
fi

echo ""
echo "Done — $TAG is live:"
echo "  • apps with 'Automatically check for updates' on will notify within 24h"
echo "  • brew users: brew upgrade --cask thorion"
