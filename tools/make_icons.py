"""Generate the fleet's home-screen icons: green glyphs on black, one per
app, written into each app's Resources/ as Icon-60@2x.png (120x120, the
iPhone 4S home-screen size; iOS rounds the corners itself).

Usage: <venv>/python tools/make_icons.py     (needs Pillow)
"""
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
S = 120
GREEN = (64, 255, 90)
DIM = (26, 105, 42)
BLACK = (0, 0, 0)


def canvas():
    img = Image.new("RGB", (S, S), BLACK)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([6, 6, S - 7, S - 7], radius=22, outline=DIM, width=3)
    return img, d


def track_bag():
    # The dart, same silhouette as ArrowView.
    img, d = canvas()
    box, x0, y0 = 72, 24, 22
    pts = [(0.50, 0.02), (0.82, 0.88), (0.50, 0.64), (0.18, 0.88)]
    d.polygon([(x0 + u * box, y0 + v * box) for u, v in pts], fill=GREEN)
    return img


def map_bag():
    # Nested contour lines with a spot elevation dot.
    img, d = canvas()
    cx, cy = 58, 62
    for i, (rx, ry, dx, dy) in enumerate(
            [(14, 10, 6, 2), (26, 19, 3, 1), (38, 28, 0, 0)]):
        d.ellipse([cx - rx + dx, cy - ry + dy, cx + rx + dx, cy + ry + dy],
                  outline=GREEN, width=3)
    d.ellipse([cx + 3, cy - 3, cx + 11, cy + 5], fill=GREEN)
    return img


def gps_bag():
    # Position circle: ring, cardinal ticks, center dot.
    img, d = canvas()
    cx = cy = 60
    r = 28
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=GREEN, width=4)
    for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
        d.line([cx + dx * (r - 4), cy + dy * (r - 4),
                cx + dx * (r + 10), cy + dy * (r + 10)], fill=GREEN, width=4)
    d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=GREEN)
    return img


def device_bag():
    # Oscilloscope pulse.
    img, d = canvas()
    pts = [(16, 66), (38, 66), (48, 36), (62, 90), (74, 50),
           (82, 66), (104, 66)]
    d.line(pts, fill=GREEN, width=5, joint="curve")
    return img


ICONS = {
    "app": track_bag,
    "mapapp": map_bag,
    "rawapp": gps_bag,
    "deviceapp": device_bag,
}

if __name__ == "__main__":
    for app_dir, draw in ICONS.items():
        out = ROOT / app_dir / "Resources" / "Icon-60@2x.png"
        draw().save(out)
        print(f"{out.relative_to(ROOT)}")
