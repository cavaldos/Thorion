<div align="center">
    <img src="Thorion/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width=200 height=200 alt="Thorion app icon">
    <h1>Thorion — Battery Monitor & Charge Limiter for macOS</h1>
    <p><strong>A smarter battery icon for your MacBook.</strong> Monitor power metrics, manage charge limits, and extend your battery's lifespan — all from the menu bar.</p>
</div>

<div align="center">

[![Download](https://img.shields.io/badge/download-latest-brightgreen?style=flat-square)](https://github.com/cavaldos/Thorion/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/cavaldos/Thorion/total?style=flat-square)](https://github.com/cavaldos/Thorion/releases)
![Platform](https://img.shields.io/badge/platform-macOS-blue?style=flat-square)
![Requirements](https://img.shields.io/badge/requirements-macOS%2014.8%2B-fa4e49?style=flat-square)
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-only-black?style=flat-square)
[![GitHub stars](https://img.shields.io/github/stars/cavaldos/Thorion?style=flat-square)](https://github.com/cavaldos/Thorion/stargazers)
[![License](https://img.shields.io/github/license/cavaldos/Thorion?style=flat-square)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor%20%E2%9D%A4%EF%B8%8F-8A2BE2?style=flat-square)](https://ko-fi.com/calvados)

<br>

<a href="https://ko-fi.com/calvados" target="_blank">
    <img src="https://storage.ko-fi.com/cdn/kofi5.png?v=6" alt="Support me on Ko-fi" style="height: 60px !important;width: 217px !important;">
</a>

</div>

Thorion gives you real-time insight into your MacBook's power system and lets you control charging behavior directly, without relying on macOS's opaque "Optimized Battery Charging."

> [!IMPORTANT]
> **Apple Silicon only.** The way metrics and charging are controlled differs a lot between Intel and Apple Silicon, so only Apple Silicon MacBooks are supported. Requires **macOS 14.8+**.

![Thorion in the menu bar](https://github.com/srimanachanta/Stasis/wiki/images/FullApp.jpg)

## Install

**Homebrew** (recommended — updates with `brew upgrade`):

```bash
brew tap cavaldos/tap
brew install --cask cavaldos/tap/thorion
```

**Manual:**

1. Download `Thorion.dmg` from the [latest release](https://github.com/cavaldos/Thorion/releases/latest).
2. Open the DMG and drag Thorion into `/Applications`.
3. Clear the quarantine flag — releases are ad-hoc signed and not notarized, so Gatekeeper would otherwise block the first launch:

```bash
xattr -dr com.apple.quarantine /Applications/thorion.app
```

Then open Thorion from Applications. Thorion checks GitHub for new versions once a day and sends a notification when one is available (you can turn this off in **Settings → General**).

Want to build from source or contribute? See [script/README.md](script/README.md).

## Uninstall

**Homebrew:**

```bash
brew uninstall --cask cavaldos/tap/thorion
```

**Manual:** quit Thorion, then drag it out of `/Applications` to the Trash. To also remove preferences, delete `~/Library/Preferences/com.thorion.app.plist`.

## Highlights

- **Charge Limit** — Set a max charge level (50–100%) enforced at the hardware level, even through sleep.
- **Sailing Mode** — Avoid micro-charging by letting the battery float within a configurable range.
- **Automatic Discharge** — Drain to your target level while staying plugged in.
- **Heat Protection** — Pause charging when battery temperature gets too high.
- **Power Dashboard** — Live voltage, current, wattage, temperature, health, and cycle count in the menu bar.
- **Power Flow Diagram** — Sankey visualization of real-time power distribution.
- **MagSafe LED Control** — Green at limit, orange while charging.

For detailed feature explanations, settings walkthroughs, architecture info, and FAQ, see the upstream **[Stasis Wiki](https://github.com/srimanachanta/Stasis/wiki)** — most of it still applies to Thorion.

## Contributing

Contributions are welcome! Read the [development guide](script/README.md) to build the app locally, and please open an issue first for large changes.

## Support

If Thorion helps your battery live longer, consider buying me a coffee:

<a href="https://ko-fi.com/calvados" target="_blank">
    <img src="https://storage.ko-fi.com/cdn/kofi5.png?v=6" alt="Support me on Ko-fi" style="height: 36px !important;width: 130px !important;">
</a>

<a href="https://www.paypal.com/paypalme/nnkhanh29" target="_blank">
    <img src="https://www.paypalobjects.com/webstatic/en_US/i/buttons/PP_logo_h_200x51.png" alt="Donate with PayPal" style="height: 36px !important;">
</a>

## Acknowledgments

Thorion is a fork of [Stasis](https://github.com/srimanachanta/Stasis) by [Sriman Achanta](https://github.com/srimanachanta) — huge thanks for the original work this project builds on.

Also built on the shoulders of:

- [SMCKit](https://github.com/srimanachanta/SMCKit) — SMC access library
- [AsahiLinux](https://asahilinux.org/) — SMC key reverse engineering
- [Battery-Toolkit](https://github.com/mhaeuser/Battery-Toolkit) — SMC key documentation

## License

[GPL-3.0](LICENSE) — Thorion is and will always remain open-source and free.

## Star History

<a href="https://star-history.com/#cavaldos/Thorion&Date">
    <img src="https://api.star-history.com/svg?repos=cavaldos/Thorion&type=Date" alt="Star History Chart" width="500">
</a>
