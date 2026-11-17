"""White-background cut-out by border flood fill (cel art with ink outlines): in.png -> RGBA out.png, cropped square with margin."""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB"); a = np.asarray(im).astype(np.int16)
near_white = (a.min(axis=2) > 236)
lab, n = ndi.label(near_white)
border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
bg = np.isin(lab, list(border))
# enclosed white pockets (between arm and body etc.) that are large are background too
sizes = ndi.sum(near_white, lab, range(1, n + 1))
cx = a.shape[1] / 2
for i, s in enumerate(sizes, 1):
    if i in border: continue
    # big pockets anywhere; small pockets only away from the centre column (teeth, eye whites, top stay)
    xm = ndi.center_of_mass(near_white, lab, i)[1]
    if s > 1500 or (s > 60 and abs(xm - cx) > 0.09 * a.shape[1]): bg |= (lab == i)
fg = ~bg
fg = ndi.binary_opening(fg, iterations=1)
lab2, n2 = ndi.label(fg); 
if n2 > 1:
    s2 = ndi.sum(fg, lab2, range(1, n2 + 1)); fg = lab2 == (1 + int(np.argmax(s2)))
alpha = ndi.gaussian_filter(fg.astype(np.float32), 0.7)
rgba = np.dstack([np.asarray(im), (np.clip(alpha, 0, 1) * 255).astype(np.uint8)])
ys, xs = np.where(fg); x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
out = Image.fromarray(rgba, "RGBA").crop((x0, y0, x1 + 1, y1 + 1))
side = int(max(out.size) * 1.08); sq = Image.new("RGBA", (side, side), (255, 255, 255, 0))
sq.paste(out, ((side - out.width) // 2, (side - out.height) // 2)); sq.save(dst); print(dst, sq.size, "bbox", x0, y0, x1, y1)
