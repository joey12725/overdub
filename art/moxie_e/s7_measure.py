"""Step 7b (venv python): face check against the head sheet + preview tiling.

The head renders (work/ver_front.png, ver_left.png) are in the head sheets' own pixel frame, so landmarks can be
compared pixel for pixel:
  front : iris centroids (amber), eye spacing, eye height
  side  : profile curve of the face (left-most opaque pixel per row) -> brow dip, nose tip, mouth notch, chin tip; iris
Errors are printed in sheet pixels and as % of the head height (crown of the skull to chin, 590 px in the sheet).
Writes art/previews/moxie_e/face_overlay.png, face_check.json and tiles the preview sheets."""
import os, sys, json, subprocess
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sheet_tools import cutout
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
GEN = os.path.join(ROOT, 'docs', 'reference', 'generated'); WORK = os.path.join(HERE, 'work'); PREV = os.path.join(ROOT, 'art', 'previews', 'moxie_e')
HEAD_H = 590.0


def rgba(p, cut=False):
    im = Image.open(p)
    return np.asarray(cutout(im) if cut else im.convert('RGBA')).astype(np.float32)


def iris(a, box):
    u0, v0, u1, v1 = box
    r, g, b = a[v0:v1, u0:u1, 0], a[v0:v1, u0:u1, 1], a[v0:v1, u0:u1, 2]
    m = (r > 170) & (g > 110) & (g < 215) & (b < 95) & (r - b > 110) & (a[v0:v1, u0:u1, 3] > 128)
    lab, n = ndi.label(m)
    if n == 0: return None
    sizes = ndi.sum(m, lab, range(1, n + 1)); k = int(np.argmax(sizes)) + 1
    cy, cx = ndi.center_of_mass(lab == k)
    return np.array([u0 + cx, v0 + cy])


def profile(a):
    m = a[:, :, 3] > 128
    p = np.where(m.any(1), m.argmax(1), 9999).astype(float)
    return ndi.gaussian_filter1d(p, 1.5)


def side_marks(a):
    p = profile(a)
    nose = 560 + int(np.argmin(p[560:650])); chin = 690 + int(np.argmin(p[690:770]))
    brow = 470 + int(np.argmax(np.where(p[470:nose] < 9000, p[470:nose], -1)))        # deepest point between fringe and nose
    mouth = nose + int(np.argmax(p[nose:chin]))
    return {'brow': (p[brow], brow), 'nose': (p[nose], nose), 'mouth': (p[mouth], mouth), 'chin': (p[chin], chin)}, p


res = {}
sf, rf = rgba(os.path.join(GEN, 'work', 'head_front1.png'), True), rgba(os.path.join(WORK, 'ver_front.png'))
sl, rl = rgba(os.path.join(GEN, 'work', 'head_side1.png'), True), rgba(os.path.join(WORK, 'ver_left.png'))
print('FRONT (sheet px; + = right / down)')
for nm, box in (('eye_right(picture left)', (600, 480, 766, 610)), ('eye_left(picture right)', (766, 480, 940, 610))):
    a, b = iris(sf, box), iris(rf, box)
    d = b - a; res[nm] = {'sheet': a.tolist(), 'model': b.tolist(), 'err_px': d.tolist(), 'err_pct_head': (np.linalg.norm(d) / HEAD_H * 100)}
    print('  %-24s sheet (%.1f, %.1f) model (%.1f, %.1f)  error %.1f px = %.2f%% of head height' % (nm, *a, *b, np.linalg.norm(d), np.linalg.norm(d) / HEAD_H * 100))
ea = [iris(sf, (600, 480, 766, 610)), iris(sf, (766, 480, 940, 610))]; eb = [iris(rf, (600, 480, 766, 610)), iris(rf, (766, 480, 940, 610))]
sp_a, sp_b = ea[1][0] - ea[0][0], eb[1][0] - eb[0][0]
print('  eye spacing: sheet %.1f px, model %.1f px (%.2f%%)' % (sp_a, sp_b, (sp_b / sp_a - 1) * 100)); res['eye_spacing_pct'] = (sp_b / sp_a - 1) * 100
m_s, m_r = sf[:, :, 3] > 128, rf[:, :, 3] > 128
res['front_silhouette_iou_above_choker'] = float((m_s[:800] & m_r[:800]).sum() / (m_s[:800] | m_r[:800]).sum())
print('  head silhouette IoU (above the choker): %.3f' % res['front_silhouette_iou_above_choker'])
print('SIDE (profile of the face)')
ms, ps = side_marks(sl); mr, pr = side_marks(rl)
for k in ('brow', 'nose', 'mouth', 'chin'):
    d = np.array(mr[k]) - np.array(ms[k])
    res['profile_' + k] = {'sheet': list(map(float, ms[k])), 'model': list(map(float, mr[k])), 'err_px': d.tolist(), 'err_pct_head': float(np.linalg.norm(d) / HEAD_H * 100)}
    print('  %-6s sheet (%.1f, %d) model (%.1f, %d)  error %.1f px = %.2f%% of head height' % (k, *ms[k], *mr[k], np.linalg.norm(d), np.linalg.norm(d) / HEAD_H * 100))
rows = slice(ms['brow'][1], ms['chin'][1] + 20)
rmsd = float(np.sqrt(np.mean((pr[rows] - ps[rows]) ** 2)))
res['profile_rms_px'] = rmsd; res['profile_rms_pct_head'] = rmsd / HEAD_H * 100
print('  profile curve brow..under-chin: RMS %.1f px = %.2f%% of head height' % (rmsd, rmsd / HEAD_H * 100))
a, b = iris(sl, (470, 470, 620, 600)), iris(rl, (470, 470, 620, 600))
if a is not None and b is not None:
    print('  iris: sheet (%.1f, %.1f) model (%.1f, %.1f) error %.1f px = %.2f%%' % (*a, *b, np.linalg.norm(b - a), np.linalg.norm(b - a) / HEAD_H * 100))
    res['side_iris_err_pct_head'] = float(np.linalg.norm(b - a) / HEAD_H * 100)
# face proportions from the 3D model's own profile (for the brief: tiny nose, small pointed chin, low-set eyes)
json.dump(res, open(os.path.join(PREV, 'face_check.json'), 'w'), indent=1)


def on_grey(a):
    bg = np.full(a.shape[:2] + (3,), 128, np.float32); al = a[:, :, 3:4] / 255
    return (a[:, :, :3] * al + bg * (1 - al))


def outline(a, col):
    m = a[:, :, 3] > 128; e = m & ~ndi.binary_erosion(m, iterations=2)
    o = np.zeros(a.shape[:2] + (4,), np.uint8); o[e] = col + (255,)
    return Image.fromarray(o)


tiles = []
for s, r in ((sf, rf), (sl, rl)):
    A, B = on_grey(s), on_grey(r)
    blend = Image.fromarray(((A + B) / 2).astype(np.uint8)).convert('RGBA')
    blend.alpha_composite(outline(s, (255, 0, 80))); blend.alpha_composite(outline(r, (0, 255, 255)))
    for im in (Image.fromarray(A.astype(np.uint8)), Image.fromarray(B.astype(np.uint8)), blend.convert('RGB')):
        tiles.append(im.crop((330, 60, 1210, 900)))
w, h = tiles[0].size
sheet = Image.new('RGB', (w * 3, h * 2), (128, 128, 128))
for k, t in enumerate(tiles): sheet.paste(t, ((k % 3) * w, (k // 3) * h))
d = ImageDraw.Draw(sheet)
for k, txt in enumerate(('model sheet', '3D model, same orthographic frame', '50/50 overlay (magenta = sheet outline, cyan = model outline)')): d.text((k * w + 12, 10), txt, fill=(255, 255, 255))
sheet.save(os.path.join(PREV, 'face_overlay.png')); print('wrote face_overlay.png', sheet.size)

# ---------------------------------------------------------------- preview tiling
P = os.path.join(PREV, '_parts'); T = os.path.join(HERE, 'tile.py')


def tile(out, cols, names, *extra):
    ps = [os.path.join(P, n) for n in names]
    if all(os.path.exists(p) for p in ps): subprocess.run([sys.executable, '-I', T, os.path.join(PREV, out), str(cols)] + ps + ['--bg', '128,128,128'] + list(extra), check=True)


tile('turnaround.png', 8, [f'turn_{i}.png' for i in range(8)])
tile('face.png', 3, [f'face_{i}.png' for i in range(6)])
if os.path.exists(os.path.join(P, 'iso.png')):
    im = Image.open(os.path.join(P, 'iso.png')).convert('RGBA')
    bb = im.getbbox(); im = im.crop(bb); s = 150 / max(im.size)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    th = Image.new('RGBA', (160, 160), (0, 0, 0, 0)); th.alpha_composite(im, ((160 - im.width) // 2, (160 - im.height) // 2)); th.save(os.path.join(PREV, 'thumb.png'))
    print('wrote thumb.png')
