#!/usr/bin/env python3
"""Regenerate every platform's app icon from branding/oxitalk-icon-source.png.

The source is a full-bleed 1024x1024 square: white bubble on a blue gradient.
Needs Pillow and numpy. Run from the repo root: python3 scripts/gen-icons.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "apps/oxitalk"
BRAND = ROOT / "branding"
SRC = BRAND / "oxitalk-icon-source.png"

ZOOM = 0.82          # crop factor for the full-bleed icon (bubble fills the tile)
ANDROID_PAD = 0.07   # extra gradient around the source for adaptive-icon safe zone


def load():
    return np.asarray(Image.open(SRC).convert("RGB")).astype(float)


def white_mask(a):
    r, b = a[..., 0], a[..., 2]
    return (r > 150) & (b - r < 70)


def fit_gradient(a):
    """Fit a smooth cubic gradient to the background so it can be extended."""
    h, w = a.shape[:2]
    obj = Image.fromarray((white_mask(a) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(61))
    ys, xs = np.where(np.asarray(obj) == 0)
    sel = np.random.default_rng(0).choice(len(ys), min(30000, len(ys)), replace=False)
    ys, xs = ys[sel], xs[sel]

    def feats(y, x):
        y, x = y / h, x / w
        return np.stack([np.ones_like(x), x, y, x * y, x * x, y * y,
                         x * x * y, x * y * y, x ** 3, y ** 3], 1)

    coef = [np.linalg.lstsq(feats(ys, xs), a[ys, xs, c], rcond=None)[0] for c in range(3)]
    return lambda yy, xx: np.stack([feats(yy.ravel(), xx.ravel()) @ c for c in coef], 1).reshape(*yy.shape, 3)


def full_bleed(a):
    """Square icon with the bubble zoomed to fill it (iOS, Play Store, Android legacy)."""
    im = Image.fromarray(a.astype(np.uint8))
    w = im.width
    c = int(w * ZOOM)
    o = (w - c) // 2
    return im.crop((o, o, o + c, o + c)).resize((1024, 1024), Image.Resampling.LANCZOS)


def padded(a, grad):
    """Source with the gradient extended on every side (Android adaptive background)."""
    h, w = a.shape[:2]
    pad = int(w * ANDROID_PAD)
    n = w + 2 * pad
    yy, xx = np.mgrid[0:n, 0:n].astype(float) - pad
    out = grad(yy, xx)
    feather = 24
    m = np.zeros((n, n))
    m[pad:pad + h, pad:pad + w] = 1
    m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(
        ImageFilter.MinFilter(2 * feather + 1)).filter(ImageFilter.GaussianBlur(feather / 2))) / 255
    inner = out.copy()
    inner[pad:pad + h, pad:pad + w] = a
    out = out * (1 - m[..., None]) + inner * m[..., None]
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)), pad


def monochrome(a, pad):
    """White silhouette of the bubble on transparent, same geometry as padded()."""
    h, w = a.shape[:2]
    n = w + 2 * pad
    m = np.zeros((n, n), np.uint8)
    m[pad:pad + h, pad:pad + w] = white_mask(a) * 255
    alpha = Image.fromarray(m).filter(ImageFilter.MedianFilter(5)).filter(ImageFilter.GaussianBlur(1.2))
    im = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    im.putalpha(alpha)
    return im


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
    a = load()
    grad = fit_gradient(a)
    icon = full_bleed(a)
    save(icon, BRAND / "oxitalk-icon-1024.png", mode="RGB")
    save(icon, BRAND / "play-store-512.png", 512, "RGB")

    # iOS: full-bleed, no alpha; the system masks the corners.
    ios = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for pts, scales in {20: (1, 2, 3), 29: (1, 2, 3), 40: (1, 2, 3), 60: (2, 3),
                        76: (1, 2), 83.5: (2,), 1024: (1,)}.items():
        for s in scales:
            name = f"Icon-App-{pts:g}x{pts:g}@{s}x.png"
            save(icon, ios / name, round(pts * s), "RGB")

    # Android: adaptive icon (minSdk 36), legacy PNGs kept in sync.
    res = APP / "android/app/src/main/res"
    bg, pad = padded(a, grad)
    mono = monochrome(a, pad)
    for d, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
        save(icon, res / f"mipmap-{d}/ic_launcher.png", int(48 * scale), "RGB")
        save(bg, res / f"mipmap-{d}/ic_launcher_background.png", int(108 * scale), "RGB")
        save(mono, res / f"mipmap-{d}/ic_launcher_monochrome.png", int(108 * scale))

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
