# Draws common\OfflineBackup.ico (16-256 px): a drive with a down arrow on a dark teal tile.
# Writes classic BMP entries: Lazarus's icon loader rejects PNG-compressed ones.
# Needs Pillow:  python tools\make-icon.py
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = [ROOT / 'common' / 'OfflineBackup.ico', ROOT / 'lazarus' / 'OfflineBackup.ico']   # Lazarus wants it next to the .lpi
S = 256


def draw():
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([8, 8, S - 8, S - 8], radius=48, fill=(18, 92, 104, 255))
    # drive body with an activity light
    d.rounded_rectangle([40, 150, S - 40, 222], radius=18, fill=(240, 244, 245, 255))
    d.ellipse([S - 86, 176, S - 64, 198], fill=(60, 200, 110, 255))
    d.rectangle([62, 182, 140, 192], fill=(150, 165, 170, 255))
    # down arrow into the drive
    d.rectangle([108, 30, 148, 92], fill=(255, 255, 255, 255))
    d.polygon([(72, 88), (184, 88), (128, 140)], fill=(255, 255, 255, 255))
    return im


if __name__ == '__main__':
    im = draw()
    for out in OUT:
        im.save(out, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (256, 256)], bitmap_format='bmp')
        print('wrote', out)
