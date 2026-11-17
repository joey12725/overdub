"""Montage helper (plain Python + PIL): python -I mc_sheet.py out.png [--cols N] [--h PX] a.png b.png ..."""
import sys
from PIL import Image


def main():
    args = sys.argv[1:]
    out = args.pop(0)
    cols, h = 0, 0
    while args and args[0].startswith("--"):
        k = args.pop(0)
        v = int(args.pop(0))
        if k == "--cols":
            cols = v
        if k == "--h":
            h = v
    ims = [Image.open(a).convert("RGB") for a in args]
    if h:
        ims = [im.resize((round(im.width * h / im.height), h), Image.LANCZOS) for im in ims]
    cols = cols or len(ims)
    rows = (len(ims) + cols - 1) // cols
    cw = max(im.width for im in ims)
    ch = max(im.height for im in ims)
    sheet = Image.new("RGB", (cols * cw + (cols - 1) * 4, rows * ch + (rows - 1) * 4), (40, 40, 46))
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % cols) * (cw + 4), (i // cols) * (ch + 4)))
    sheet.save(out)


if __name__ == "__main__":
    main()
