#!/usr/bin/env python3
"""Regenerate every platform's app icon from the SVG masters in branding/.

branding/oxitalk-icon.svg            full-bleed 1024x1024 icon (ink background)
branding/oxitalk-icon-foreground.svg Android adaptive foreground, transparent

The SVGs are rendered with headless Chromium (chromium-browser, chromium or
google-chrome on PATH, or $CHROME), then resized with Pillow.
Run from anywhere: python3 scripts/gen-icons.py
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "apps/oxitalk"
BRAND = ROOT / "branding"


def chrome():
    for name in (os.environ.get("CHROME"), "chromium-browser", "chromium", "google-chrome"):
        path = shutil.which(name) if name else None
        if path:
            return path
    raise SystemExit("gen-icons: no Chromium found; set $CHROME")


def render(svg, out, size=1024):
    """Render an SVG to a size x size PNG, keeping transparency."""
    subprocess.run(
        [chrome(), "--headless=new", "--disable-gpu", "--hide-scrollbars",
         "--default-background-color=00000000", f"--window-size={size},{size}",
         f"--screenshot={out}", svg.resolve().as_uri()],
        check=True, capture_output=True)
    return Image.open(out).convert("RGBA")


def rounded_tile(img, size=1024, inset=100, radius_ratio=0.2237, shadow=True):
    """Rounded square with transparent margin, for desktops that do not mask icons."""
    t = size - 2 * inset
    tile = img.resize((t, t), Image.Resampling.LANCZOS).convert("RGBA")
    s = 4
    mask = Image.new("L", (t * s, t * s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, t * s - 1, t * s - 1), radius=int(t * radius_ratio * s), fill=255)
    mask = mask.resize((t, t), Image.Resampling.LANCZOS)
    tile.putalpha(mask)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if shadow:
        sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        sm = Image.new("L", (size, size), 0)
        sm.paste(mask, (inset, inset + size // 80))
        sh.putalpha(sm.point(lambda v: v * 0.35).filter(ImageFilter.GaussianBlur(size / 60)))
        out = Image.alpha_composite(out, sh)
    out.alpha_composite(tile, (inset, inset))
    return out


def save(im, path, size=None, mode=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if size:
        im = im.resize((size, size), Image.Resampling.LANCZOS)
    if mode:
        im = im.convert(mode)
    im.save(path, optimize=True)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        icon = render(BRAND / "oxitalk-icon.svg", Path(tmp) / "icon.png").convert("RGB")
        fg = render(BRAND / "oxitalk-icon-foreground.svg", Path(tmp) / "fg.png")

    save(icon, BRAND / "oxitalk-icon-1024.png")
    save(icon, BRAND / "play-store-512.png", 512)

    # In the app: title bar and About screen (full-bleed; the app rounds the corners).
    assets = APP / "assets/branding"
    save(icon, assets / "oxitalk-icon-96.png", 96)
    save(icon, assets / "oxitalk-icon-256.png", 256)

    # iOS: full-bleed, no alpha; the system masks the corners.
    ios = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for pts, scales in {20: (1, 2, 3), 29: (1, 2, 3), 40: (1, 2, 3), 60: (2, 3),
                        76: (1, 2), 83.5: (2,), 1024: (1,)}.items():
        for s in scales:
            save(icon, ios / f"Icon-App-{pts:g}x{pts:g}@{s}x.png", round(pts * s))

    # Android: adaptive icon (minSdk 36) = ink colour (values/ic_launcher_background.xml)
    # + transparent foreground + monochrome; legacy ic_launcher.png kept in sync.
    res = APP / "android/app/src/main/res"
    mono = Image.new("RGBA", fg.size, (255, 255, 255, 0))
    mono.putalpha(fg.getchannel("A"))
    for d, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
        save(icon, res / f"mipmap-{d}/ic_launcher.png", int(48 * scale))
        save(fg, res / f"mipmap-{d}/ic_launcher_foreground.png", int(108 * scale))
        save(mono, res / f"mipmap-{d}/ic_launcher_monochrome.png", int(108 * scale))
        (res / f"mipmap-{d}/ic_launcher_background.png").unlink(missing_ok=True)

    # macOS: Big Sur style tile, 824/1024 with shadow (macOS does not mask).
    tile = rounded_tile(icon)
    mac = APP / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for s in (16, 32, 64, 128, 256, 512, 1024):
        save(tile, mac / f"app_icon_{s}.png", s)

    # Windows: tighter rounded tile, no shadow, multi-size .ico.
    win = rounded_tile(icon, size=256, inset=8, radius_ratio=0.18, shadow=False)
    win.save(APP / "windows/runner/resources/app_icon.ico",
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    # Linux: window icon shipped in the bundle's data dir.
    save(tile, APP / "linux/runner/resources/app_icon.png", 256)


if __name__ == "__main__":
    main()
