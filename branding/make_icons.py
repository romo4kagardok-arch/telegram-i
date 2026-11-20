"""Builds Android launcher icons for "telegram i" from the source logo.

Usage: python3 make_icons.py <icon.webp> <res-dir>

The source is a green circle with a white paper plane on a white square.
Outputs, for every mipmap density:
  ic_launcher.png / ic_launcher_round.png   legacy round icon (48dp)
  tgi_launcher_fg.png                       adaptive foreground, plane only (108dp)
  icon_foreground*.png / icon_background*.png  overwritten in place (in-app icon picker preview)
plus mipmap-anydpi-v26/ic_launcher(.xml|_round.xml) and values/tgi_launcher_colors.xml.
"""
import os
import sys

from PIL import Image, ImageDraw

DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


def is_green(p):
    r, g, b = p[0], p[1], p[2]
    return g > 150 and r < 140 and b < 140


def find_circle(img):
    px = img.load()
    w, h = img.size
    step = max(1, w // 500)
    pts = [(x, y) for y in range(0, h, step) for x in range(0, w, step) if is_green(px[x, y])]
    if not pts:
        sys.exit("no green circle found in the source icon")
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    sample = pts[:: max(1, len(pts) // 2000)]
    color = tuple(sum(px[x, y][i] for x, y in sample) // len(sample) for i in range(3))
    return (x0, y0, x1 + 1, y1 + 1), color


def circle_mask(size, scale=4):
    big = Image.new("L", (size * scale, size * scale), 0)
    ImageDraw.Draw(big).ellipse((0, 0, size * scale - 1, size * scale - 1), fill=255)
    return big.resize((size, size), Image.LANCZOS)


def plane_layer(square):
    """White plane on transparent: alpha comes from how white the pixel is, inside the circle only."""
    n = square.size[0]
    mask = circle_mask(n)
    out = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    src = square.load()
    m = mask.load()
    o = out.load()
    inset = 0.92  # ignore the white corners and the anti-aliased rim of the circle
    c = (n - 1) / 2
    r2 = (c * inset) ** 2
    for y in range(n):
        for x in range(n):
            if (x - c) ** 2 + (y - c) ** 2 > r2 or m[x, y] == 0:
                continue
            r, g, b = src[x, y][:3]
            # green background has r and b near 0, the plane has r = b = 255
            a = max(0, min(255, ((r + b) // 2 - 24) * 255 // (255 - 24)))
            if a:
                o[x, y] = (255, 255, 255, a)
    return out


def main():
    src_path, res = sys.argv[1], sys.argv[2]
    img = Image.open(src_path).convert("RGBA")
    box, bg = find_circle(img)
    d = max(box[2] - box[0], box[3] - box[1])
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    square = img.crop((round(cx - d / 2), round(cy - d / 2), round(cx - d / 2) + d, round(cy - d / 2) + d))
    work = 864
    square = square.resize((work, work), Image.LANCZOS)
    bg_hex = "#%02X%02X%02X" % bg
    print(f"circle box {box}, background {bg_hex}")

    plane = plane_layer(square)
    # Clean green circle + plane: the source circle is hand-drawn, so cutting it out leaves white slivers.
    legacy = Image.new("RGBA", (work, work), bg + (255,))
    legacy.alpha_composite(plane)
    legacy.putalpha(circle_mask(work))

    # Adaptive foreground: the circle maps onto the 72dp visible viewport of the 108dp layer.
    fg_canvas = 108 * 8
    inner = round(fg_canvas * 72 / 108)
    fg = Image.new("RGBA", (fg_canvas, fg_canvas), (255, 255, 255, 0))
    off = (fg_canvas - inner) // 2
    fg.alpha_composite(plane.resize((inner, inner), Image.LANCZOS), (off, off))

    for name, scale in DENSITIES.items():
        folder = os.path.join(res, f"mipmap-{name}")
        os.makedirs(folder, exist_ok=True)
        s48 = round(48 * scale)
        s108 = round(108 * scale)
        icon = legacy.resize((s48, s48), Image.LANCZOS)
        icon.save(os.path.join(folder, "ic_launcher.png"))
        icon.save(os.path.join(folder, "ic_launcher_round.png"))
        fg.resize((s108, s108), Image.LANCZOS).save(os.path.join(folder, "tgi_launcher_fg.png"))
        for fname in sorted(os.listdir(folder)):
            path = os.path.join(folder, fname)
            if fname.startswith("icon_foreground") and fname.endswith(".png"):
                size = Image.open(path).size
                fg.resize(size, Image.LANCZOS).save(path)
            elif fname.startswith("icon_background") and fname.endswith(".png"):
                size = Image.open(path).size
                Image.new("RGBA", size, bg + (255,)).save(path)

    anydpi = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/tgi_launcher_bg"/>\n'
        '    <foreground android:drawable="@mipmap/tgi_launcher_fg"/>\n'
        '    <monochrome android:drawable="@mipmap/tgi_launcher_fg"/>\n'
        "</adaptive-icon>\n"
    )
    for fname in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, fname), "w", encoding="utf-8") as f:
            f.write(adaptive)

    with open(os.path.join(res, "values", "tgi_launcher_colors.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            f'    <color name="tgi_launcher_bg">{bg_hex}</color>\n</resources>\n'
        )

    preview = os.environ.get("ICON_PREVIEW")
    if preview:
        sheet = Image.new("RGBA", (3 * 200, 200), (230, 230, 230, 255))
        sheet.alpha_composite(legacy.resize((192, 192), Image.LANCZOS), (4, 4))
        ad = Image.new("RGBA", (192, 192), bg + (255,))
        ad.alpha_composite(fg.resize((288, 288), Image.LANCZOS).crop((48, 48, 240, 240)))
        ad.putalpha(circle_mask(192))
        sheet.alpha_composite(ad, (204, 4))
        sq = Image.new("RGBA", (192, 192), bg + (255,))
        sq.alpha_composite(fg.resize((288, 288), Image.LANCZOS).crop((48, 48, 240, 240)))
        sheet.alpha_composite(sq, (404, 4))
        sheet.save(preview)
        print(f"preview written to {preview}")
    print("icons done")


if __name__ == "__main__":
    main()
