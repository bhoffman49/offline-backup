# Draws docs\social-preview.png (1280x640): the GitHub / SourceForge social preview - the app icon, name and what it
# does. Draws at twice the size and scales down, so edges are smooth. Needs Pillow and Windows' Segoe UI fonts:
#   python tools\make-banner.py
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'docs' / 'social-preview.png'
W, H = 1280, 640
K = 2                                   # drawn at 2x
TEAL = (18, 92, 104)
BG = (242, 246, 247)
DARK = (40, 52, 56)
GREY = (90, 104, 108)
FONTS = Path('C:/Windows/Fonts')


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), size * K)


def icon(d, x, y, size):
    """The app icon (same shapes as tools\\make-icon.py, drawn on a 256 grid) at x, y, size px - in 1x units."""
    s = size / 256 * K

    def box(x0, y0, x1, y1):
        return [x * K + x0 * s, y * K + y0 * s, x * K + x1 * s, y * K + y1 * s]

    d.rounded_rectangle(box(8, 8, 248, 248), radius=48 * s, fill=TEAL)
    d.rounded_rectangle(box(40, 150, 216, 222), radius=18 * s, fill=(240, 244, 245))
    d.ellipse(box(170, 176, 192, 198), fill=(60, 200, 110))
    d.rectangle(box(62, 182, 140, 192), fill=(150, 165, 170))
    d.rectangle(box(108, 30, 148, 92), fill=(255, 255, 255))
    d.polygon([(x * K + px * s, y * K + py * s) for px, py in [(72, 88), (184, 88), (128, 140)]], fill=(255, 255, 255))


def main():
    im = Image.new('RGB', (W * K, H * K), BG)
    d = ImageDraw.Draw(im)
    icon(d, 90, 120, 340)
    tx = 500
    d.text((tx * K, 128 * K), 'Offline Backup', font=font('segoeuib.ttf', 82), fill=TEAL)
    d.text((tx * K, 240 * K), 'Back up the folders you choose', font=font('segoeui.ttf', 36), fill=DARK)
    d.text((tx * K, 288 * K), 'to USB drives you keep unplugged.', font=font('segoeui.ttf', 36), fill=DARK)
    small = font('segoeui.ttf', 26)
    lines = ['Preview before every copy  \u2022  moved-file detection',
             'Old versions kept  \u2022  CRC32 / MD5 verify  \u2022  VeraCrypt-ready']
    for i, line in enumerate(lines):
        d.text((tx * K, (372 + i * 40) * K), line, font=small, fill=GREY)
    # footer band
    d.rectangle([0, (H - 84) * K, W * K, H * K], fill=TEAL)
    d.text((90 * K, (H - 62) * K), 'Free & open source (MIT)  \u2022  Windows 10 / 11  \u2022  github.com/bhoffman49/offline-backup',
           font=font('segoeui.ttf', 28), fill=(255, 255, 255))
    im.resize((W, H), Image.LANCZOS).save(OUT)
    print('wrote', OUT)


if __name__ == '__main__':
    main()
