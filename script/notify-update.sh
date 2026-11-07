#!/bin/bash
# Step 2: tell users about a release. CI runs this after every release (job notify-users
# in .github/workflows/release.yml); run it by hand only if that job failed or is not set up.
#   1. Sparkle: adds the release to thorion/appcast.xml in cavaldos/macos-app-releases
#      (GitHub Pages, shared with Ice and Lumio). Installed apps check it daily, show a
#      notification, then download, verify and install the update.
#   2. Homebrew: points Casks/thorion.rb in cavaldos/homebrew-tap at the new Thorion.dmg,
#      so `brew upgrade` installs it.
#
# Usage: ./script/notify-update.sh vX.Y.Z [--key <private-key-file>] [--skip-brew]
#   --key  Sparkle EdDSA private key. Default: $SPARKLE_PRIVATE_KEY, then
#          ~/.sparkle/sparkle-priv.pem, then the key in your Keychain. It must match
#          SUPublicEDKey in Thorion/Info.plist.
# Needs: gh logged in, generate_appcast (brew install --cask sparkle, or bin/ of
#        https://github.com/sparkle-project/Sparkle/releases), git push access to the repos
#        below. CI pushes with deploy keys: set RELEASES_SSH / HOMEBREW_TAP_SSH to an ssh
#        command using the key.
set -eo pipefail
cd "$(dirname "$0")/.."

REPOSITORY="cavaldos/Thorion"
RELEASES_REPOSITORY="cavaldos/macos-app-releases"
APPCAST="thorion/appcast.xml"
TAP_REPOSITORY="cavaldos/homebrew-tap"
CASK_PATH="Casks/thorion.rb"
DMG_NAME="Thorion.dmg"
FEED_URL="https://cavaldos.github.io/macos-app-releases/$APPCAST"

TAG=""
KEY="${SPARKLE_PRIVATE_KEY:-}"
SKIP_BREW=false
while [ $# -gt 0 ]; do
    case "$1" in
        --key) KEY="$2"; shift 2;;
        --skip-brew) SKIP_BREW=true; shift;;
        -h|--help) sed -n '2,18p' "$0"; exit 0;;
        v*) TAG="$1"; shift;;
        *) echo "unknown arg: $1" >&2; exit 1;;
    esac
done
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: $0 vX.Y.Z [--key <private-key-file>] [--skip-brew]" >&2
    exit 1
fi
VERSION="${TAG#v}"
command -v gh >/dev/null || { echo "missing gh: brew install gh" >&2; exit 1; }
command -v generate_appcast >/dev/null || {
    echo "missing generate_appcast: brew install --cask sparkle" >&2
    exit 1
}
if [ -z "$KEY" ] && [ -f "$HOME/.sparkle/sparkle-priv.pem" ]; then
    KEY="$HOME/.sparkle/sparkle-priv.pem"
fi
KEY_ARGS=()
if [ -n "$KEY" ]; then
    [ -f "$KEY" ] || { echo "private key not found: $KEY" >&2; exit 1; }
    # --ed-key-file, not -f: -f is for legacy DSA keys.
    KEY_ARGS=(--ed-key-file "$KEY")
fi

GIT_NAME="$(git config --global user.name || echo 'github-actions[bot]')"
GIT_EMAIL="$(git config --global user.email || echo 'github-actions[bot]@users.noreply.github.com')"

# Clones <owner/name> into <dir>: over SSH with <ssh command> (CI deploy key),
# otherwise over HTTPS with your own git credentials.
clone() {
    if [ -n "$3" ]; then
        GIT_SSH_COMMAND="$3" git clone --quiet --depth 1 "git@github.com:$1.git" "$2"
        git -C "$2" config core.sshCommand "$3"
    else
        gh repo clone "$1" "$2" -- --quiet --depth 1
    fi
    git -C "$2" config user.name "$GIT_NAME"
    git -C "$2" config user.email "$GIT_EMAIL"
}

# Commits what is staged in <dir> and pushes, retrying transient GitHub errors.
# A failed push fails the script, so CI never goes green without publishing.
publish() {
    if git -C "$1" diff --cached --quiet; then
        echo "    already up to date"
        return 0
    fi
    git -C "$1" commit --quiet -m "$2"
    for attempt in 1 2 3 4 5; do
        if git -C "$1" push --quiet origin HEAD; then
            return 0
        fi
        if [ "$attempt" -eq 5 ]; then
            echo "push from $1 failed" >&2
            exit 1
        fi
        echo "push failed (attempt $attempt), retrying in $((attempt * 10))s..."
        sleep $((attempt * 10))
        git -C "$1" pull --quiet --rebase
    done
}

# --- The GitHub Release must be public: the appcast and the cask download from it.
STATE="$(gh release view "$TAG" -R "$REPOSITORY" --json isDraft,isPrerelease,assets \
    --jq "[.isDraft, .isPrerelease, ([.assets[].name] | index(\"$DMG_NAME\") != null)] | map(tostring) | join(\" \")")" || {
    echo "no GitHub release for $TAG yet: run ./script/release.sh $TAG or wait for the Release workflow" >&2
    exit 1
}
read -r IS_DRAFT IS_PRERELEASE HAS_ASSET <<< "$STATE"
if [ "$HAS_ASSET" != true ]; then
    echo "release $TAG has no $DMG_NAME yet: wait for the Release workflow to finish" >&2
    exit 1
fi
if [ "$IS_DRAFT" = true ] || [ "$IS_PRERELEASE" = true ]; then
    echo "==> Publishing release $TAG (it was a draft or pre-release)"
    gh release edit "$TAG" -R "$REPOSITORY" --draft=false --prerelease=false --latest >/dev/null
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/archives"
gh release download "$TAG" -R "$REPOSITORY" -p "$DMG_NAME" -D "$WORK/archives"
SHA256="$(shasum -a 256 "$WORK/archives/$DMG_NAME" | cut -d' ' -f1)"

# --- 1. Sparkle appcast ---------------------------------------------------------
echo "==> Sparkle: adding $TAG to $APPCAST in $RELEASES_REPOSITORY"
clone "$RELEASES_REPOSITORY" "$WORK/releases" "${RELEASES_SSH:-}"
# Keep history: generate_appcast keeps the entries of an appcast.xml it finds next to the archives.
if [ -f "$WORK/releases/$APPCAST" ]; then
    cp "$WORK/releases/$APPCAST" "$WORK/archives/appcast.xml"
fi
generate_appcast ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} \
    --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
    "$WORK/archives"
if ! grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$WORK/archives/appcast.xml"; then
    echo "appcast has no $VERSION entry: is $DMG_NAME on $TAG really version $VERSION?" >&2
    exit 1
fi
mkdir -p "$(dirname "$WORK/releases/$APPCAST")"
cp "$WORK/archives/appcast.xml" "$WORK/releases/$APPCAST"
git -C "$WORK/releases" add "$APPCAST"

# List Thorion in the releases README once.
if [ -f "$WORK/releases/README.md" ] && ! grep -q '/thorion/appcast.xml' "$WORK/releases/README.md"; then
    awk -v row="| [Thorion](https://github.com/$REPOSITORY) | $FEED_URL |" '
        { print }
        /^\| \[Lumio\]/ && !done { print row; done = 1 }
    ' "$WORK/releases/README.md" > "$WORK/releases-readme.tmp"
    mv "$WORK/releases-readme.tmp" "$WORK/releases/README.md"
    git -C "$WORK/releases" add README.md
fi
publish "$WORK/releases" "appcast: Thorion $TAG"

# --- 2. Homebrew cask -----------------------------------------------------------
if [ "$SKIP_BREW" = true ]; then
    echo "==> Homebrew: skipped"
else
    echo "==> Homebrew: pointing $CASK_PATH in $TAP_REPOSITORY at $VERSION"
    clone "$TAP_REPOSITORY" "$WORK/tap" "${HOMEBREW_TAP_SSH:-}"
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
  depends_on macos: :sonoma

  app "thorion.app"

  # Releases are ad-hoc signed and not notarized; without this Gatekeeper blocks the first launch.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/thorion.app"],
        must_succeed: false
  end

  uninstall launchctl: "com.thorion.app.charging-helper",
            quit:      "com.thorion.app"

  zap trash: "~/Library/Preferences/com.thorion.app.plist"

  caveats <<~EOS
    Thorion is ad-hoc signed. If macOS still blocks it, run:
      xattr -dr com.apple.quarantine #{appdir}/thorion.app
  EOS
end
EOF

    # List Thorion in the tap README once.
    if [ -f "$WORK/tap/README.md" ] && ! grep -q '`thorion`' "$WORK/tap/README.md"; then
        awk -v row="| \`thorion\` | Menu bar battery monitor and charge limiter for Apple Silicon MacBooks ([$REPOSITORY](https://github.com/$REPOSITORY)) |" '
            { print }
            /^\| `ice` \|/ && !done { print row; done = 1 }
        ' "$WORK/tap/README.md" > "$WORK/tap-readme.tmp"
        printf '\n```bash\nbrew install --cask cavaldos/tap/thorion\n```\n' >> "$WORK/tap-readme.tmp"
        mv "$WORK/tap-readme.tmp" "$WORK/tap/README.md"
        git -C "$WORK/tap" add README.md
    fi

    git -C "$WORK/tap" add "$CASK_PATH"
    publish "$WORK/tap" "thorion $VERSION"
fi

echo ""
echo "Done. Users get Thorion $VERSION via:"
echo "  - the app: Sparkle checks $FEED_URL daily (or Settings > General > Check Now)"
echo "  - Homebrew: brew upgrade --cask thorion"
