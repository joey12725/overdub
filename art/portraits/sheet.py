"""Contact-sheet helper. usage: python -I sheet.py out.png cell cols img1 img2 ...  (labels = file stems)"""
import sys, os
from PIL import Image, ImageDraw, ImageFont
def font(sz):
    for f in ("arialbd.ttf", "arial.ttf", "DejaVuSans-Bold.ttf"):
        try: return ImageFont.truetype(f, sz)
        except OSError: pass
    return ImageFont.load_default()
def sheet(out, cell, cols, paths, bg=(58, 52, 70), labels=None):
    rows = (len(paths) + cols - 1) // cols
    lab = 26
    im = Image.new("RGB", (cols * cell, rows * (cell + lab)), bg)
    d = ImageDraw.Draw(im); f = font(18)
    for i, p in enumerate(paths):
        x, y = (i % cols) * cell, (i // cols) * (cell + lab)
        # checker so transparency and halos show
        for cy in range(0, cell, 32):
            for cx in range(0, cell, 32):
                if (cx // 32 + cy // 32) % 2: d.rectangle([x + cx, y + cy, x + cx + 31, y + cy + 31], fill=(70, 64, 84))
        s = Image.open(p).convert("RGBA"); s.thumbnail((cell, cell), Image.LANCZOS)
        im.paste(s, (x + (cell - s.width) // 2, y + cell - s.height), s)
        d.text((x + 6, y + cell + 3), (labels[i] if labels else os.path.splitext(os.path.basename(p))[0]), fill=(255, 235, 150), font=f)
    im.save(out)
if __name__ == "__main__":
    sheet(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:])
