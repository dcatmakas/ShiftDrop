"""Sample files and wallpapers for the README screenshots. Usage: samples.py <work dir>"""
import sys, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
out = sys.argv[1]
random.seed(7)

def blobs(w, h, base, spots, blur):
    """Soft multi-color gradient: colored blobs on a base, heavily blurred."""
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)
    for (cx, cy, r, color) in spots:
        d.ellipse([cx*w - r*w, cy*h - r*w, cx*w + r*w, cy*h + r*w], fill=color)
    img = img.filter(ImageFilter.GaussianBlur(blur))
    # Fine grain so the gradient doesn't band.
    noise = (np.random.default_rng(1).normal(0, 2.2, (h, w, 1))).astype(np.int16)
    arr = np.clip(np.asarray(img).astype(np.int16) + noise, 0, 255).astype(np.uint8)
    return Image.fromarray(arr)

W, H = 2400, 1200
light = blobs(W, H, (226, 232, 246), [
    (0.12, 0.2, 0.30, (255, 196, 160)), (0.5, 0.95, 0.35, (170, 196, 255)),
    (0.88, 0.25, 0.32, (214, 186, 255)), (0.62, 0.35, 0.18, (255, 226, 200)), (0.3, 0.8, 0.2, (190, 230, 240))], 160)
light.save(f"{out}/wall_light.png")
dark = blobs(W, H, (16, 18, 34), [
    (0.15, 0.85, 0.32, (120, 52, 120)), (0.55, 0.1, 0.3, (32, 60, 140)),
    (0.92, 0.75, 0.3, (190, 80, 50)), (0.4, 0.55, 0.18, (40, 30, 90))], 170)
dark.save(f"{out}/wall_dark.png")

# A landscape photo stand-in: sky, sun, layered hills.
w, h = 1600, 1066
img = Image.new("RGB", (w, h))
px = img.load()
d = ImageDraw.Draw(img)
for y in range(h):
    t = y / h
    c = (int(255 - 60*t), int(170 + 40*t - 80*t*t), int(120 + 110*t))
    d.line([(0, y), (w, y)], fill=c)
d.ellipse([1040, 300, 1240, 500], fill=(255, 236, 200))
layers = [((236, 140, 120), 0.55, 90), ((196, 96, 110), 0.65, 70), ((120, 60, 96), 0.76, 60), ((52, 30, 60), 0.88, 40)]
for color, base, amp in layers:
    pts = [(0, h)]
    phase = random.random() * 6
    for x in range(0, w + 20, 20):
        y = base*h - amp*math.sin(x/260 + phase) - amp*0.5*math.sin(x/97 + phase*2)
        pts.append((x, y))
    pts.append((w, h))
    d.polygon(pts, fill=color)
img = img.filter(ImageFilter.GaussianBlur(0.8))
img.save(f"{out}/samples/Mountains.jpg", quality=92)

# A one-page "report" PDF: title, text lines and a small bar chart.
pw, ph = 1240, 1754
page = Image.new("RGB", (pw, ph), "white")
d = ImageDraw.Draw(page)
try:
    title = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 64)
    body = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 28)
except Exception:
    title = body = ImageFont.load_default()
d.text((120, 140), "Quarterly Report", fill=(20, 24, 40), font=title)
d.text((120, 230), "Q3 2026 · Product & growth", fill=(110, 116, 130), font=body)
y = 330
for i in range(9):
    d.rounded_rectangle([120, y, 120 + (980 if i % 4 != 3 else 620), y + 14], 7, fill=(214, 218, 228)); y += 38
bars = [0.42, 0.58, 0.51, 0.74, 0.9]
for i, b in enumerate(bars):
    x = 160 + i*190
    d.rounded_rectangle([x, 1200 - int(420*b), x + 120, 1200], 14, fill=(64, 120, 245) if i == 4 else (180, 200, 245))
d.line([120, 1204, 1120, 1204], fill=(200, 204, 214), width=3)
y = 1290
for i in range(6):
    d.rounded_rectangle([120, y, 120 + (980 if i % 3 != 2 else 540), y + 14], 7, fill=(214, 218, 228)); y += 38
page.save(f"{out}/samples/Report.pdf", resolution=150)
print("ok")
