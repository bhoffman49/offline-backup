# Draws the main window's sidebar icons into common\icons\*.ico (32-64 px, one per area).
# Our own drawings, in the app icon's teal. Classic BMP entries: Lazarus's icon loader rejects PNG-compressed ones.
# Needs Pillow:  python tools\make-sidebar-icons.py
import math
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'common' / 'icons'
S = 256
SIZES = [(32, 32), (40, 40), (48, 48), (64, 64)]
TEAL = (18, 92, 104, 255)
LIGHT = (240, 244, 245, 255)
GREEN = (60, 170, 100, 255)


def new():
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def drive(d, top, light=GREEN):
    # a USB drive seen from the front: teal body, light slot, activity light
    d.rounded_rectangle([20, top, S - 20, top + 84], radius=20, fill=TEAL)
    d.rounded_rectangle([44, top + 32, 150, top + 50], radius=6, fill=LIGHT)
    d.ellipse([S - 76, top + 28, S - 50, top + 54], fill=light)


def backup():
    im, d = new()
    drive(d, 150)
    d.rectangle([106, 16, 150, 84], fill=TEAL)                       # arrow down into the drive
    d.polygon([(64, 78), (192, 78), (128, 140)], fill=TEAL)
    return im


def drives():
    im, d = new()
    drive(d, 26, light=LIGHT)                                         # a stack of three drives
    drive(d, 98, light=LIGHT)
    drive(d, 170)
    return im


def check():
    im, d = new()
    d.rounded_rectangle([40, 14, 216, 242], radius=18, fill=TEAL)    # a sheet with a list ...
    d.rounded_rectangle([60, 34, 196, 222], radius=8, fill=LIGHT)
    for y in (60, 92, 124):
        d.rectangle([80, y, 176, y + 12], fill=(150, 165, 170, 255))
    d.line([(84, 176), (116, 206), (180, 140)], fill=GREEN, width=26, joint='curve')   # ... and a tick
    return im


def settings():
    im, d = new()
    c, r_out, r_in, teeth = S / 2, 116, 86, 8
    pts = []
    for i in range(teeth * 4):
        a = 2 * math.pi * i / (teeth * 4) - math.pi / (teeth * 4) * 1.5
        r = r_out if i % 4 in (1, 2) else r_in
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
    d.polygon(pts, fill=TEAL)
    d.ellipse([c - 40, c - 40, c + 40, c + 40], fill=(0, 0, 0, 0))   # the hole
    return im


def restore():
    im, d = new()
    drive(d, 150)
    d.rectangle([106, 72, 150, 140], fill=TEAL)                      # arrow up out of the drive
    d.polygon([(64, 78), (192, 78), (128, 16)], fill=TEAL)
    return im


if __name__ == '__main__':
    OUT.mkdir(exist_ok=True)
    for name, fn in [('backup', backup), ('drives', drives), ('check', check), ('settings', settings),
                     ('restore', restore)]:
        out = OUT / (name + '.ico')
        fn().save(out, sizes=SIZES, bitmap_format='bmp')
        print('wrote', out)
