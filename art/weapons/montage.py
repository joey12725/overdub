"""Quick contact sheet:  python -I art/weapons/montage.py out.png cols cell_w cell_h img1 img2 ..."""
import sys
from PIL import Image
out, cols, cw, ch = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
files = sys.argv[5:]
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cw, rows * ch), (24, 22, 30))
for i, f in enumerate(files):
    try:
        im = Image.open(f).convert("RGB")
    except Exception:
        continue
    im.thumbnail((cw, ch), Image.LANCZOS)
    sheet.paste(im, ((i % cols) * cw + (cw - im.width) // 2, (i // cols) * ch + (ch - im.height) // 2))
sheet.save(out)
