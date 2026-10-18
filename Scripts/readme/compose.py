"""Builds the README images: rings and editors over a wallpaper, with simulated Liquid Glass.

Usage: compose.py <work dir with wall_*.png and shots/> <output dir>
"""
import math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

R = sys.argv[1]           # scratch readme dir
OUT = sys.argv[2]         # repo docs dir
SS = 4                    # supersampling for smooth masks

def aa_mask(size, draw_fn):
    big = Image.new("L", (size[0]*SS, size[1]*SS), 0)
    draw_fn(ImageDraw.Draw(big), SS)
    return big.resize(size, Image.LANCZOS)

def shadow(canvas, mask, offset, blur, opacity):
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    m = Image.new("L", canvas.size, 0)
    m.paste(mask, offset)
    m = m.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * opacity))
    sh.putalpha(m)
    canvas.alpha_composite(sh)

def glass(canvas, box, mask, dark, strength=1.0):
    """Frosted glass: blurred, tinted copy of what's behind, a top sheen and a hairline rim."""
    x0, y0, x1, y1 = box
    region = canvas.crop(box).filter(ImageFilter.GaussianBlur(26))
    region = ImageEnhance.Color(region).enhance(1.25)
    tint = Image.new("RGBA", region.size, (34, 34, 38, 255) if dark else (255, 255, 255, 255))
    region = Image.blend(region, tint, (0.42 if dark else 0.40) * strength)
    h = region.size[1]
    sheen = Image.new("RGBA", region.size, (255, 255, 255, 0))
    grad = np.linspace(0.16 if not dark else 0.08, 0, h)[:, None] * np.ones((1, region.size[0]))
    sheen.putalpha(Image.fromarray((grad * 255).astype(np.uint8)))
    region.alpha_composite(sheen)
    region.putalpha(mask)
    canvas.alpha_composite(region, (x0, y0))

def rim(canvas, box, shape, dark, radius=None):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    def draw(d, s):
        if shape == "circle":
            d.ellipse([s, s, w*s - s, h*s - s], outline=255, width=2*s)
        else:
            d.rounded_rectangle([s, s, w*s - s, h*s - s], radius*s, outline=255, width=2*s)
    m = aa_mask((w, h), draw).point(lambda v: int(v * (0.22 if dark else 0.6)))
    layer = Image.new("RGBA", (w, h), (255, 255, 255, 0)); layer.putalpha(m)
    canvas.alpha_composite(layer, (x0, y0))

def cursor(canvas, tip, scale=1.7):
    pts = [(0, 0), (0, 34), (8, 27), (14, 41), (19, 39), (13, 25), (24, 25)]
    pts = [(tip[0] + x*scale, tip[1] + y*scale) for x, y in pts]
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    shadow_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow_layer).polygon([(x + 2, y + 4) for x, y in pts], fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow_layer.filter(ImageFilter.GaussianBlur(3)))
    d.polygon(pts, fill=(0, 0, 0, 255), outline=(255, 255, 255, 255), width=4)
    canvas.alpha_composite(layer)
    # Green "+" badge: Finder's sign for a copy drop.
    bx, by, r = tip[0] + 30*scale, tip[1] + 36*scale, 13*scale
    d = ImageDraw.Draw(canvas)
    d.ellipse([bx - r - 3, by - r - 3, bx + r + 3, by + r + 3], fill=(255, 255, 255, 255))
    d.ellipse([bx - r, by - r, bx + r, by + r], fill=(52, 199, 89, 255))
    t = 3.2 * scale / 1.7
    d.rectangle([bx - r*0.55, by - t, bx + r*0.55, by + t], fill="white")
    d.rectangle([bx - t, by - r*0.55, bx + t, by + r*0.55], fill="white")

def ghost(canvas, thumb_path, center, size=150, opacity=0.78):
    t = Image.open(thumb_path).convert("RGBA")
    t.thumbnail((size, size), Image.LANCZOS)
    a = np.asarray(t).copy(); a[..., 3] = (a[..., 3] * opacity).astype(np.uint8)
    t = Image.fromarray(a)
    canvas.alpha_composite(t, (int(center[0] - t.width/2), int(center[1] - t.height/2)))

def place_ring(canvas, shot_path, center, dark, hover_angle_deg, thumb, ghost_offset=(46, 58)):
    shot = Image.open(shot_path).convert("RGBA")
    n = shot.size[0]
    ox, oy = int(center[0] - n/2), int(center[1] - n/2)
    dial = 156 * 2
    cx, cy = center
    box = (cx - dial, cy - dial, cx + dial, cy + dial)
    mask = aa_mask((dial*2, dial*2), lambda d, s: d.ellipse([0, 0, dial*2*s, dial*2*s], fill=255))
    shadow(canvas, mask, (box[0], box[1] + 26), 44, 0.30 if dark else 0.20)
    glass(canvas, box, mask, dark)
    rim(canvas, box, "circle", dark)

    # The mode capsule under the dial, found by its faint fill in the snapshot.
    # Scan only the capsule's own center row/column so the highlight's glow can't leak in.
    alpha = np.asarray(shot)[..., 3]
    def run(line, start):
        """Contiguous stretch of covered pixels around `start`."""
        lo = hi = start
        while lo > 0 and line[lo - 1] >= 1: lo -= 1
        while hi < len(line) - 1 and line[hi + 1] >= 1: hi += 1
        return lo, hi
    x0, x1 = run(alpha[804, :], 440)
    y0, y1 = run(alpha[:, 440], 804)
    y0 = max(y0, 804 - 28)  # the highlight's glow can touch the capsule's top edge
    cb = (ox + x0, oy + y0, ox + x1 + 1, oy + y1 + 1)
    cw, ch = cb[2] - cb[0], cb[3] - cb[1]
    cmask = aa_mask((cw, ch), lambda d, s: d.rounded_rectangle([0, 0, cw*s, ch*s], ch*s/2, fill=255))
    shadow(canvas, cmask, (cb[0], cb[1] + 8), 14, 0.22 if dark else 0.12)
    glass(canvas, cb, cmask, dark)
    rim(canvas, cb, "capsule", dark, radius=ch/2)

    canvas.alpha_composite(shot, (ox, oy))

    # Dragged file + cursor over the hovered segment.
    a = math.radians(hover_angle_deg)
    # Near the rim, so the hovered label stays readable.
    r = 292
    tip = (cx + r*math.sin(a), cy - r*math.cos(a))
    ghost(canvas, thumb, (tip[0] + ghost_offset[0], tip[1] + ghost_offset[1]), size=130, opacity=0.72)
    cursor(canvas, tip)

def wallpaper(name, size):
    w = Image.open(f"{R}/{name}").convert("RGBA")
    scale = max(size[0] / w.width, size[1] / w.height)
    w = w.resize((math.ceil(w.width*scale), math.ceil(w.height*scale)), Image.LANCZOS)
    return w.crop((0, 0) + size)

def save(img, path, width):
    img = img.convert("RGB")
    img = img.resize((width, round(img.height * width / img.width)), Image.LANCZOS)
    img.save(path, quality=90, optimize=True, progressive=True)

for mode in ("light", "dark"):
    dark = mode == "dark"
    # Hero: PDF → JPG on the left, image tools on the right.
    hero = wallpaper(f"wall_{mode}.png", (2400, 1180))
    place_ring(hero, f"{R}/shots/ring_convert_{mode}.png", (650, 560), dark, 90, f"{R}/shots/Report.pdf.png")
    place_ring(hero, f"{R}/shots/ring_tools_{mode}.png", (1750, 560), dark, 3*360/7, f"{R}/shots/Mountains.jpg.png", ghost_offset=(84, 28))
    save(hero, f"{OUT}/hero-{mode}.jpg", 1600)

    # Editors side by side as macOS windows.
    canvas = wallpaper(f"wall_{mode}.png", (2400, 1600))
    for path, pos in ((f"{R}/shots/ed_crop_{mode}.png", (110, 190)), (f"{R}/shots/ed_bg_{mode}.png", (1180, 100))):
        win = Image.open(path).convert("RGBA")
        w, h = win.size
        rad = 30
        wmask = aa_mask((w, h), lambda d, s: d.rounded_rectangle([0, 0, w*s, h*s], rad*s, fill=255))
        shadow(canvas, wmask, (pos[0], pos[1] + 30), 50, 0.45 if dark else 0.28)
        # Window material: blurred wallpaper under a mostly opaque window color.
        base = canvas.crop((pos[0], pos[1], pos[0] + w, pos[1] + h)).filter(ImageFilter.GaussianBlur(40))
        base = Image.blend(base, Image.new("RGBA", (w, h), (36, 36, 40, 255) if dark else (244, 244, 246, 255)), 0.86)
        base.alpha_composite(win)
        # Close button.
        d = ImageDraw.Draw(base)
        d.ellipse([28, 26, 28 + 26, 26 + 26], fill=(255, 95, 87, 255), outline=(224, 68, 62, 255), width=1)
        base.putalpha(wmask)
        canvas.alpha_composite(base, pos)
        rim(canvas, (pos[0], pos[1], pos[0] + w, pos[1] + h), "rect", dark, radius=rad)
    save(canvas, f"{OUT}/editors-{mode}.jpg", 1600)
print("done")
