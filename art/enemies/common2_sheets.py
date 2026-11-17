"""Compose enemy preview sheets with PIL (system Python, outside Blender).

    python art/enemies/common2_sheets.py <type> <previews_dir>

Reads the stills art/enemies/<type>.py rendered into <previews_dir>:
  turn_{front,left,back,right,threequarter}.png  -> turnaround.png
  anim/<action>_NN.png                           -> anim_<action>.png (one row) and anim_all.png
  iso.png + thumb_160.png                        -> iso_thumb.png (side by side, thumbnail also at 1x)
"""
from __future__ import annotations

import glob
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

BG = (28, 27, 33)
FG = (235, 230, 220)
ACTION_ORDER = ["idle", "move", "telegraph", "attack", "stagger", "death"]


def font(size: int):
    for name in ("arialbd.ttf", "arial.ttf", "segoeui.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def labelled_row(images: list[Image.Image], labels: list[str], title: str | None, pad: int = 8) -> Image.Image:
    w = sum(i.width for i in images) + pad * (len(images) + 1)
    h = max(i.height for i in images) + pad * 2 + 22 + (30 if title else 0)
    out = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(out)
    y0 = pad
    if title:
        d.text((pad, pad), title, fill=FG, font=font(22))
        y0 += 30
    x = pad
    f = font(14)
    for im, lab in zip(images, labels):
        out.paste(im, (x, y0))
        d.text((x + 4, y0 + im.height + 3), lab, fill=FG, font=f)
        x += im.width + pad
    return out


def stack(rows: list[Image.Image]) -> Image.Image:
    w = max(r.width for r in rows)
    h = sum(r.height for r in rows)
    out = Image.new("RGB", (w, h), BG)
    y = 0
    for r in rows:
        out.paste(r, (0, y))
        y += r.height
    return out


def main() -> None:
    type_name, d = sys.argv[1], sys.argv[2]
    views = ["front", "left", "back", "right", "threequarter"]
    files = [os.path.join(d, f"turn_{v}.png") for v in views]
    if all(os.path.exists(f) for f in files):
        ims = [Image.open(f).convert("RGB") for f in files]
        labelled_row(ims, views, f"{type_name} - turnaround (orthographic)").save(os.path.join(d, "turnaround.png"))
    iso, thumb = os.path.join(d, "iso.png"), os.path.join(d, "thumb_160.png")
    if os.path.exists(iso) and os.path.exists(thumb):
        a = Image.open(iso).convert("RGB")
        t = Image.open(thumb).convert("RGB")
        big = t.resize((t.width * 4, t.height * 4), Image.NEAREST)
        ims, labs = [a, big, t], ["iso (yaw 45, pitch 35.3)", "160 px thumbnail x4", "160 px"]
        t100 = os.path.join(d, "thumb_100.png")
        if os.path.exists(t100):
            ims.append(Image.open(t100).convert("RGB"))
            labs.append("100 px")
        labelled_row(ims, labs, f"{type_name} - game camera").save(os.path.join(d, "iso_thumb.png"))
    anim_dir = os.path.join(d, "anim")
    rows = []
    if os.path.isdir(anim_dir):
        names = sorted({re.sub(r"_\d+\.png$", "", os.path.basename(p)) for p in glob.glob(os.path.join(anim_dir, "*_[0-9][0-9].png"))})
        names.sort(key=lambda n: (ACTION_ORDER.index(n) if n in ACTION_ORDER else 99, n))
        for n in names:
            fs = sorted(glob.glob(os.path.join(anim_dir, f"{n}_[0-9][0-9].png")))
            ims = [Image.open(f).convert("RGB") for f in fs]
            k = len(ims)
            labels = [f"t={i / (k - 1):.2f}" for i in range(k)]
            row = labelled_row(ims, labels, f"{type_name} - {n}")
            row.save(os.path.join(d, f"anim_{n}.png"))
            rows.append(row)
    if rows:
        stack(rows).save(os.path.join(d, "anim_all.png"))
    print("sheets written to", d)


if __name__ == "__main__":
    main()
