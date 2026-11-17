"""Reference nine-slice renderer (same rule as Godot's NinePatchRect in stretch mode), used by the checks."""
from PIL import Image


def render9(im, w, h, l, t, r, b):
    """Draw `im` at (w,h) keeping the l/t/r/b margins unscaled. t=b=0 -> horizontal 3-slice at native height."""
    if t == 0 and b == 0:
        h = im.height
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    sx = [0, l, im.width - r, im.width]; dx = [0, l, w - r, w]
    sy = [0, t, im.height - b, im.height]; dy = [0, t, h - b, h]
    for j in range(3):
        for i in range(3):
            sw, sh = sx[i + 1] - sx[i], sy[j + 1] - sy[j]
            dw, dh = dx[i + 1] - dx[i], dy[j + 1] - dy[j]
            if sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0:
                continue
            cell = im.crop((sx[i], sy[j], sx[i + 1], sy[j + 1])).resize((dw, dh), Image.BILINEAR)
            out.paste(cell, (dx[i], dy[j]))
    return out
