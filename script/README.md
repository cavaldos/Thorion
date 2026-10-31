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

## Every release (2 commands)

```bash
# 1. Commit your work, then build the DMG, tag, and publish it as the LATEST release
./script/release.sh vX.Y.Z

# 2. Bump the Homebrew cask
./script/notify-update.sh vX.Y.Z
```

- **Step 1 publishes the release as Latest** (same as Ice). Installed apps check `releases/latest` on GitHub once a day and show a notification that links to the download.
- **Step 2 updates Homebrew.** It also publishes the release if it is still a draft (e.g. old drafts).
  It writes `Casks/thorion.rb` in `cavaldos/homebrew-tap` with the new version and SHA-256, so `brew upgrade` picks it up. Pass `--skip-brew` to skip it.

### Tag rules

- Format `vX.Y.Z` (e.g. `v0.3.0`) and **greater** than the version users have — the update check ignores older or equal versions.
- Never re-tag an old number. No need to edit the version in Xcode — `build.sh` injects `MARKETING_VERSION` from the tag.
- `release.sh` refuses a dirty working tree — commit first.

### No update notification? Check

1. Is the release published (not draft) and marked **Latest** on GitHub?
2. Is **Settings → General → Automatically check for updates** on, and notifications allowed for Thorion in System Settings?
3. The check runs at launch and every 24 hours — use **Check Now** in Settings to test right away.

## Contributing

1. Fork the repo and create a branch from `main`.
2. Keep changes focused (no force unwraps, async/await, SwiftUI, SMC only in the helper).
3. Make sure `./script/run.sh` builds and the app launches.
4. Open a pull request describing what changed and how you tested it. For large changes, open an issue first.
