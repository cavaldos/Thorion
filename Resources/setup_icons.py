#!/usr/bin/env python3
"""Generate every macOS AppIcon size from a single source image.

Usage:
    python3 Resources/setup_icons.py [path/to/source.png]

Defaults to Resources/icon.png. The source should be a square
PNG of at least 1024x1024. Uses the built-in `sips` tool, so no Python
packages are needed.
"""

import json
import subprocess
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = REPOSITORY_ROOT / "Resources" / "icon.png"
APP_ICON_SET = REPOSITORY_ROOT / "Thorion" / "Assets.xcassets" / "AppIcon.appiconset"
MINIMUM_SOURCE_SIZE = 1024

# (point size, scale) pairs required by a macOS app icon set.
ICON_VARIANTS = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def read_pixel_size(image: Path) -> tuple[int, int]:
    result = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(image)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail(f"could not read {image}: {result.stderr.strip()}")

    values = {}
    for line in result.stdout.splitlines():
        parts = line.split(":")
        if len(parts) == 2 and parts[0].strip() in ("pixelWidth", "pixelHeight"):
            values[parts[0].strip()] = int(parts[1].strip())

    if "pixelWidth" not in values or "pixelHeight" not in values:
        fail(f"{image} does not look like an image")
    return values["pixelWidth"], values["pixelHeight"]


def file_name(point_size: int, scale: int) -> str:
    suffix = "" if scale == 1 else f"@{scale}x"
    return f"icon_{point_size}x{point_size}{suffix}.png"


def render(source: Path, pixel_size: int, destination: Path) -> None:
    result = subprocess.run(
        [
            "sips",
            "-s", "format", "png",
            "-z", str(pixel_size), str(pixel_size),
            str(source),
            "--out", str(destination),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail(f"sips failed for {destination.name}: {result.stderr.strip()}")


def main() -> None:
    if sys.platform != "darwin":
        fail("this script needs macOS (it uses the built-in `sips` tool)")

    source = Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not source.is_file():
        fail(f"source image not found: {source}")

    width, height = read_pixel_size(source)
    if width != height:
        fail(f"source must be square, got {width}x{height}")
    if width < MINIMUM_SOURCE_SIZE:
        fail(f"source must be at least {MINIMUM_SOURCE_SIZE}x{MINIMUM_SOURCE_SIZE}, got {width}x{height}")

    APP_ICON_SET.mkdir(parents=True, exist_ok=True)

    # Remove icons from a previous run so renamed or dropped sizes don't linger.
    for old_icon in APP_ICON_SET.glob("*.png"):
        old_icon.unlink()

    images = []
    for point_size, scale in ICON_VARIANTS:
        name = file_name(point_size, scale)
        render(source, point_size * scale, APP_ICON_SET / name)
        images.append({
            "filename": name,
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{point_size}x{point_size}",
        })
        print(f"  {name:<24} {point_size * scale}px")

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (APP_ICON_SET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

    print(f"Generated {len(images)} icons in {APP_ICON_SET.relative_to(REPOSITORY_ROOT)}")


if __name__ == "__main__":
    main()
