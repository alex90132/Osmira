#!/usr/bin/env python3
"""Generate Osmira launcher + notification icons from the source logo.

The source PNG has an opaque black background with a bright (near-white) logo.
We rebuild the alpha channel from luminance so the background becomes fully
transparent and paint the whole logo solid white. That white+alpha image is
exactly what Android notification small-icons need, and also feeds the
adaptive/legacy launcher icons.
"""
import os
from PIL import Image, ImageFilter

SRC = "/home/x4690/most/1783952321337.png"
RES = "/home/x4690/most/awg2-client/app/android/app/src/main/res"

# Luminance below this is background (killed). Set high enough to erase the
# soft blue glow around the logo so the cutout is genuinely transparent.
FLOOR = 84
GAIN = 2.2
# Dilate the alpha by this radius to thicken the line-art strokes ("шире обводку").
DILATE = 3


def white_logo():
    im = Image.open(SRC).convert("RGBA")
    r, g, b, _ = im.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L")
    px = lum.load()
    w, h = lum.size
    alpha = Image.new("L", (w, h), 0)
    ap = alpha.load()
    for y in range(h):
        for x in range(w):
            v = px[x, y]
            if v <= FLOOR:
                ap[x, y] = 0
            else:
                nv = int(min(255, (v - FLOOR) * GAIN * 255 / (255 - FLOOR)))
                ap[x, y] = nv
    # Thicken strokes: a MaxFilter grows opaque regions outward.
    if DILATE > 0:
        alpha = alpha.filter(ImageFilter.MaxFilter(DILATE * 2 + 1))
    white = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    white.putalpha(alpha)
    # Trim to content so scaling/padding is predictable.
    bbox = alpha.getbbox()
    if bbox:
        white = white.crop(bbox)
    return white


def fit(logo, canvas, scale):
    """Return canvas x canvas RGBA with logo scaled to `scale` fraction, centered."""
    target = int(canvas * scale)
    lw, lh = logo.size
    ratio = min(target / lw, target / lh)
    new = logo.resize((max(1, int(lw * ratio)), max(1, int(lh * ratio))), Image.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.alpha_composite(new, ((canvas - new.width) // 2, (canvas - new.height) // 2))
    return out


def on_bg(fg, color):
    bg = Image.new("RGBA", fg.size, color)
    bg.alpha_composite(fg)
    return bg


DENS = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}

NAVY = (0, 0, 0, 255)  # pure black to match the app canvas


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def main():
    logo = white_logo()

    # Adaptive foreground master (432 = 108dp @ xxxhdpi). Keep the logo well
    # inside the ~72dp masked circle so there's a generous black margin and the
    # art never hugs the icon edge (scale is a fraction of the 108dp canvas).
    fg_master = fit(logo, 432, 0.46)
    save(fg_master, f"{RES}/drawable/ic_launcher_foreground.png")

    for name, k in DENS.items():
        # Legacy square launcher icon: white logo on black with roomy padding.
        legacy_px = int(48 * k)
        legacy = on_bg(fit(logo, legacy_px, 0.58), NAVY)
        save(legacy, f"{RES}/mipmap-{name}/ic_launcher.png")
        save(legacy, f"{RES}/mipmap-{name}/ic_launcher_round.png")

        # Adaptive foreground per density (108dp canvas).
        fg_px = int(108 * k)
        save(fit(logo, fg_px, 0.46), f"{RES}/mipmap-{name}/ic_launcher_foreground.png")

        # Notification small icon: white + alpha only (24dp).
        notif_px = int(24 * k)
        save(fit(logo, notif_px, 0.92), f"{RES}/drawable-{name}/ic_stat_vpn.png")

    print("icons generated")


if __name__ == "__main__":
    main()
