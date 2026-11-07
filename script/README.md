# Development Guide

Everything you need to build Thorion from source, work on it locally, and ship a release. Run all commands from the repository root.

## Requirements

- Apple Silicon Mac
- Xcode with Swift 6 support (the helper targets need the macOS 15.7 SDK or newer)
- [`gh`](https://cli.github.com) — only for releases (`brew install gh`, then `gh auth login`)

Dependencies ([SMCKit](https://github.com/srimanachanta/SMCKit), [Defaults](https://github.com/sindresorhus/Defaults), …) resolve automatically through Swift Package Manager.

## Build from source

```bash
git clone https://github.com/cavaldos/Thorion.git
cd Thorion
open Thorion.xcodeproj
```

Or from the terminal:

```bash
# Build Debug and launch the app
./script/run.sh

# Build a Release DMG into release/ (optional version override)
./script/build.sh [vX.Y.Z]
```

Both scripts sign ad-hoc, so no Apple Developer certificate is needed.

## Project layout

| Folder | What lives there |
| --- | --- |
| `Thorion/` | Main app — SwiftUI views, menu bar, settings, business logic |
| `Helper/` | Privileged helper — the only place allowed to talk to the SMC |
| `ChargingHelper/` | Launch daemon that keeps charge limits enforced |
| `SMCPower/` | Shared SMC types and power readings |
| `Resources/` | Source app icon and the script that generates every icon size |
| `script/` | Build, run and release scripts |

All SMC commands must run inside the helper; the app asks for them over XPC.

## App icon

The source icon is `Resources/icon.png`. To change it, replace that file (square PNG, at least 1024×1024) and run:

```bash
python3 Resources/setup_icons.py         # uses Resources/icon.png
python3 Resources/setup_icons.py path/to.png  # or any other image
```

It regenerates every size in `Thorion/Assets.xcassets/AppIcon.appiconset` (16 → 1024 px) and rewrites `Contents.json`. It only uses macOS's built-in `sips`, so no Python packages are needed.

## Every release

```bash
# Commit your work, then build the DMG, tag, and publish it as the LATEST release
./script/release.sh vX.Y.Z
```

- **`release.sh` publishes the GitHub Release as Latest** and pushes the tag.
- **The tag push runs `.github/workflows/release.yml`.** Its `notify-users` job runs `./script/notify-update.sh`, which:
  1. adds the release to [`thorion/appcast.xml`](https://cavaldos.github.io/macos-app-releases/thorion/appcast.xml) in [`cavaldos/macos-app-releases`](https://github.com/cavaldos/macos-app-releases) (the Sparkle feed shared with Ice and Lumio), signed with the EdDSA key;
  2. writes `Casks/thorion.rb` in `cavaldos/homebrew-tap` with the new version and SHA-256, so `brew upgrade` picks it up.
- If the job fails or its secrets are not set, run `./script/notify-update.sh vX.Y.Z` yourself (needs `generate_appcast`: `brew install --cask sparkle`, and the key in `~/.sparkle/sparkle-priv.pem` or your Keychain). Pass `--skip-brew` to skip Homebrew.

### How users get the update

Thorion uses [Sparkle](https://sparkle-project.org). Release builds read `SUFeedURL` in `Thorion/Info.plist` and check the feed once a day:

- **A new version found in the background** shows a macOS notification. Clicking it (or **Install…** in Settings → General) opens Sparkle's dialog with the release notes; Sparkle downloads the DMG, verifies it against `SUPublicEDKey`, installs it and relaunches Thorion.
- **Right after launch**, or when notifications are off or not allowed, Sparkle shows its dialog directly.
- **Check Now** in Settings → General checks right away.
- Debug builds (`./script/run.sh`) never check, so they are not replaced by a release build.

Versions released before Sparkle (v0.0.2 and older) still check GitHub's `releases/latest` and link to the download, so they see the next release too and move to Sparkle after installing it.

### CI secrets (repo Settings → Secrets → Actions)

| Secret | What it is |
| --- | --- |
| `SPARKLE_PRIVATE_KEY` | Contents of `~/.sparkle/sparkle-priv.pem` (the EdDSA key shared with Ice and Lumio) |
| `MACOS_APP_RELEASES_DEPLOY_KEY` | Private half of a deploy key with write access on `cavaldos/macos-app-releases` |
| `HOMEBREW_TAP_DEPLOY_KEY` | Private half of a deploy key with write access on `cavaldos/homebrew-tap` |

### Tag rules

- Format `vX.Y.Z` (e.g. `v0.3.0`) and **greater** than the version users have — the update check ignores older or equal versions.
- Never re-tag an old number. No need to edit the version in Xcode — `build.sh` injects `MARKETING_VERSION` from the tag.
- `release.sh` refuses a dirty working tree — commit first.

### No update notification? Check

1. Does [`thorion/appcast.xml`](https://cavaldos.github.io/macos-app-releases/thorion/appcast.xml) list the new version? If not, check the `notify-users` job or run `./script/notify-update.sh vX.Y.Z`.
2. Is the installed app a Release build with a lower version? Debug builds never check.
3. Is **Settings → General → Automatically check for updates** on? Without notification permission Sparkle shows its dialog instead.
4. Sparkle checks once every 24 hours — use **Check Now** in Settings to test right away.

## Contributing

1. Fork the repo and create a branch from `main`.
2. Keep changes focused (no force unwraps, async/await, SwiftUI, SMC only in the helper).
3. Make sure `./script/run.sh` builds and the app launches.
4. Open a pull request describing what changed and how you tested it. For large changes, open an issue first.
