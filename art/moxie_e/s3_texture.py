"""Step 3 (venv python): bake the albedo by projecting the model sheets back onto the mesh.

For every texel of the two 2k atlases (material 0 'body', 1 'head') we know its world position and normal
(UV rasterisation of work/mesh.npz). Each orthographic sheet view is sampled where the texel is visible in it
(z-buffer test against a dense point splat of the whole mesh) and the views are blended by facing^4, down-weighted
near the sheet silhouette so ink outlines do not smear onto grazing surfaces. Texels no sheet sees are filled from
the nearest painted texel in 3D.

  body : cut/moxie_front, moxie_back, moxie_left, moxie_right
  head : work/head_front1 (or head_grin1 with --grin), head_side1 (+ mirrored for her right side), head_back1
Writes assets/models/candidates/e/moxie_body.png, moxie_head.png (and moxie_head_grin.png)."""
import os, sys, json
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from scipy.spatial import cKDTree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sheet_tools import cutout
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
GEN = os.path.join(ROOT, 'docs', 'reference', 'generated'); WORK = os.path.join(HERE, 'work')
OUT = os.path.join(ROOT, 'assets', 'models', 'candidates', 'e'); os.makedirs(OUT, exist_ok=True)
TEX = 2048
A = json.load(open(os.path.join(WORK, 'align.json')))
M = np.load(os.path.join(WORK, 'mesh.npz'))
co, no, tri, uv, mat = M['co'].astype(np.float64), M['no'].astype(np.float64), M['tri'], M['uv'].astype(np.float64), M['mat']
ZS = float(M['zshift'])
rng = np.random.default_rng(3)


def pad_rgba(rgba, rim=7):
    """colour to project (ink outline at the silhouette removed, colour extended past the silhouette), mask, edge distance.
    The sheet's outer ink line would smear over every surface that turns away from the view; the game draws its own outline."""
    a = rgba[:, :, 3] > 128
    rgb = rgba[:, :, :3].astype(np.float32)
    edge = ndi.distance_transform_edt(a)
    lum = rgb @ np.array([0.3, 0.59, 0.11], np.float32)
    safe = a & (edge >= rim) & (lum > 70)
    idx = ndi.distance_transform_edt(~safe, return_distances=False, return_indices=True)
    near = rgb[idx[0], idx[1]]
    replace = ~a | (edge < 2.5) | ((edge < rim) & (lum < 95))
    out = np.where(replace[:, :, None], near, rgb)
    return out, a, edge


class View:
    """u = u0 + su * h / mpp ; v = v0 - z / mpp ; h = world x (axis 0) or y (axis 1); cam looks along dsign * depth axis"""
    def __init__(self, name, rgba, u0, v0, mpp, axis, su):
        self.name, self.u0, self.v0, self.mpp, self.axis, self.su = name, u0, v0, mpp, axis, su
        self.rgb, self.mask, self.edge = pad_rgba(rgba)
        self.daxis = 1 - axis
        # direction from surface toward the camera
        self.dir = np.zeros(3)
        if axis == 0: self.dir[1] = -su            # front (su=+1): camera at -Y ; back (su=-1): camera at +Y
        else: self.dir[0] = su                     # left (su=+1): camera at +X ; right: camera at -X
    def uv(self, P): return self.u0 + self.su * P[:, self.axis] / self.mpp, self.v0 - P[:, 2] / self.mpp
    def depth(self, P): return -(P @ self.dir)     # smaller = closer to the camera


def sample_surface(n, sel=None):
    t = tri if sel is None else tri[sel]
    a, b, c = co[t[:, 0]], co[t[:, 1]], co[t[:, 2]]
    area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    f = rng.choice(len(t), n, p=area / area.sum())
    r1, r2 = np.sqrt(rng.random(n)), rng.random(n)
    return a[f] * (1 - r1)[:, None] + b[f] * (r1 * (1 - r2))[:, None] + c[f] * (r1 * r2)[:, None]


def silhouette(view, P, ds=2):
    h, w = view.mask.shape[0] // ds, view.mask.shape[1] // ds
    u, v = view.uv(P); ui, vi = np.floor(u / ds).astype(int), np.floor(v / ds).astype(int)
    ok = (ui >= 0) & (ui < w) & (vi >= 0) & (vi < h)
    m = np.zeros((h, w), bool); m[vi[ok], ui[ok]] = True
    return ndi.binary_closing(m, iterations=2)


def refit(view, P, rows=None, scale=False, ds=2):
    """slide (and optionally scale) the sheet so its silhouette best matches the mesh from that side"""
    h, w = view.mask.shape[0] // ds, view.mask.shape[1] // ds
    tgt = view.mask[:h * ds, :w * ds].reshape(h, ds, w, ds).mean((1, 3)) > 0.5
    def score():
        m = silhouette(view, P, ds); t = tgt
        if rows is not None: m = m[:rows // ds]; t = t[:rows // ds]
        return (m & t).sum() / max(1, (m | t).sum())
    # initial u0 from centres
    best = score(); steps = [16.0, 16.0, 0.02]
    for it in range(50):
        improved = False
        for k in range(3 if scale else 2):
            for sg in (1, -1):
                old = (view.u0, view.v0, view.mpp)
                if k == 0: view.u0 += sg * steps[0]
                elif k == 1: view.v0 += sg * steps[1]
                else:
                    f = 1 + sg * steps[2]; view.mpp *= f          # scale about the image centre of the silhouette
                sc = score()
                if sc > best + 1e-5: best, improved = sc, True
                else: view.u0, view.v0, view.mpp = old
        if not improved:
            steps = [s * 0.5 for s in steps]
            if steps[0] < 0.4: break
    print('  view %-11s IoU %.3f  u0 %.1f v0 %.1f mpp %.6f' % (view.name, best, view.u0, view.v0, view.mpp))
    return best


def load_rgba(path, cut=False):
    im = Image.open(path)
    return np.asarray(cutout(im) if cut else im.convert('RGBA'))


# ------------------------------------------------------------------ views
Vw = A['views']
P_all = sample_surface(3000000)
P_head = sample_surface(1200000, mat == 1)
S = A['S']
bf = View('body_front', load_rgba(os.path.join(GEN, 'cut', 'moxie_front.png')), Vw['body_front'][0], Vw['body_front'][1] - ZS / S, S, 0, +1)
bl = View('body_left', load_rgba(os.path.join(GEN, 'cut', 'moxie_left.png')), Vw['body_left'][0], Vw['body_left'][1] - ZS / Vw['body_left'][2], Vw['body_left'][2], 1, +1)
bb = View('body_back', load_rgba(os.path.join(GEN, 'cut', 'moxie_back.png')), 576.0, bf.v0, S, 0, -1)
br = View('body_right', load_rgba(os.path.join(GEN, 'cut', 'moxie_right.png')), 0, bl.v0, bl.mpp, 1, -1)
us = np.where(br.mask.any(0))[0]; br.u0 = (us[0] + us[-1]) / 2 + (P_all[:, 1].min() + P_all[:, 1].max()) / 2 / br.mpp
print('silhouette registration:')
for v in (bf, bl): print('  view %-11s (anchored) IoU %.3f' % (v.name, (lambda m, t: (m & t).sum() / (m | t).sum())(silhouette(v, P_all), v.mask[:v.mask.shape[0] // 2 * 2, :v.mask.shape[1] // 2 * 2].reshape(v.mask.shape[0] // 2, 2, v.mask.shape[1] // 2, 2).mean((1, 3)) > 0.5)))
refit(bb, P_all); refit(br, P_all)
Sh = Vw['head_front'][2]
front_src = 'head_grin1.png' if '--grin' in sys.argv else 'head_front1.png'
hf = View('head_front', load_rgba(os.path.join(GEN, 'work', front_src), True), Vw['head_front'][0], Vw['head_front'][1] - ZS / Sh, Sh, 0, +1)
hl_rgba = load_rgba(os.path.join(GEN, 'work', 'head_side1.png'), True)
hl = View('head_left', hl_rgba, Vw['head_left'][0], Vw['head_left'][1] - ZS / Vw['head_left'][2], Vw['head_left'][2], 1, +1)
# depth registration of the profile sheet on the FACE: slide it so the sheet's nose-to-chin profile lies on the mesh's
def _profile(mask):
    return np.where(mask.any(1), mask.argmax(1), -1).astype(float)
_pm = _profile(silhouette(hl, P_head, 1)); _ps = _profile(hl.mask[:_pm.shape[0], :])
_rows = np.arange(585, 705); _ok = (_pm[_rows] > 0) & (_ps[_rows] > 0)
_shift = float(np.median((_ps[_rows] - _pm[_rows])[_ok]))        # sheet profile minus mesh profile
hl.u0 += _shift          # a mesh point on the profile now projects onto the sheet profile
print('  view head_left   profile registration: sheet moved %.1f px (%.1f mm)' % (_shift, _shift * hl.mpp * 1000))
hr = View('head_right', hl_rgba[:, ::-1], 0, hl.v0, hl.mpp, 1, -1)
hr.u0 = (hl_rgba.shape[1] - 1) - hl.u0            # mirrored image: u' = W-1-u
hb = View('head_back', load_rgba(os.path.join(GEN, 'work', 'head_back1.png'), True), hf.mask.shape[1] - 1 - hf.u0, hf.v0, Sh, 0, -1)
ROWS = 800                                           # head sheets: compare above the choker only
refit(hb, P_head, rows=ROWS, scale=True)
VIEWS = {0: [bf, bb, bl, br], 1: [hf, hb, hl, hr]}
BONUS = {'body_front': 1.6, 'head_front': 2.5, 'body_back': 1.2, 'head_back': 1.2}


def zbuffer(view, ds):
    h, w = view.mask.shape[0] // ds + 1, view.mask.shape[1] // ds + 1
    u, v = view.uv(P_all); d = view.depth(P_all)
    ui, vi = np.floor(u / ds).astype(int), np.floor(v / ds).astype(int)
    ok = (ui >= 0) & (ui < w) & (vi >= 0) & (vi < h)
    zb = np.full((h, w), np.inf); np.minimum.at(zb, (vi[ok], ui[ok]), d[ok])
    return ndi.minimum_filter(zb, 3)


# ------------------------------------------------------------------ texel rasterisation
def raster(m):
    pos = np.zeros((TEX, TEX, 3), np.float32); nor = np.zeros((TEX, TEX, 3), np.float32); cov = np.zeros((TEX, TEX), bool)
    sel = np.where(mat == m)[0]
    T = uv[sel] * TEX; T[:, :, 1] = TEX - T[:, :, 1]                 # image row 0 = v 1
    for k, f in enumerate(sel):
        (x0, y0), (x1, y1), (x2, y2) = T[k]
        xa, xb = int(np.floor(min(x0, x1, x2) - 0.5)), int(np.ceil(max(x0, x1, x2) + 0.5))
        ya, yb = int(np.floor(min(y0, y1, y2) - 0.5)), int(np.ceil(max(y0, y1, y2) + 0.5))
        xa, ya, xb, yb = max(xa, 0), max(ya, 0), min(xb, TEX - 1), min(yb, TEX - 1)
        if xb < xa or yb < ya: continue
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-12: continue
        gx, gy = np.meshgrid(np.arange(xa, xb + 1) + 0.5, np.arange(ya, yb + 1) + 0.5)
        w0 = ((y1 - y2) * (gx - x2) + (x2 - x1) * (gy - y2)) / den
        w1 = ((y2 - y0) * (gx - x2) + (x0 - x2) * (gy - y2)) / den
        w2 = 1 - w0 - w1
        e = -0.35 / max(1.0, np.sqrt(abs(den)))                         # conservative: grab the border texels too
        ins = (w0 >= e) & (w1 >= e) & (w2 >= e)
        if not ins.any(): continue
        i0, i1, i2 = tri[f]
        yy, xx = np.where(ins)
        b0, b1, b2 = w0[ins][:, None], w1[ins][:, None], w2[ins][:, None]
        pos[ya + yy, xa + xx] = co[i0] * b0 + co[i1] * b1 + co[i2] * b2
        nor[ya + yy, xa + xx] = no[i0] * b0 + no[i1] * b1 + no[i2] * b2
        cov[ya + yy, xa + xx] = True
    return pos, nor, cov


def bilinear(img, u, v):
    return np.stack([ndi.map_coordinates(img[:, :, c], [v, u], order=1, mode='nearest') for c in range(3)], 1)


def bake(m, name):
    pos, nor, cov = raster(m)
    ys, xs = np.where(cov)
    Pt = pos[ys, xs].astype(np.float64); Nt = nor[ys, xs].astype(np.float64)
    Nt /= np.maximum(np.linalg.norm(Nt, axis=1, keepdims=True), 1e-9)
    acc = np.zeros((len(Pt), 3)); wsum = np.zeros(len(Pt))
    tol = 0.010 if m == 0 else 0.005
    for vw in VIEWS[m]:
        ds = 1 if m == 0 else 2
        zb = zbuffer(vw, ds)
        u, v = vw.uv(Pt); d = vw.depth(Pt)
        ui = np.clip(np.floor(u / ds).astype(int), 0, zb.shape[1] - 1); vi = np.clip(np.floor(v / ds).astype(int), 0, zb.shape[0] - 1)
        vis = d <= zb[vi, ui] + tol
        inb = (u >= 0) & (u < vw.mask.shape[1] - 1) & (v >= 0) & (v < vw.mask.shape[0] - 1)
        facing = np.clip(Nt @ vw.dir, 0, 1)
        edge = ndi.map_coordinates(vw.edge, [np.clip(v, 0, vw.mask.shape[0] - 1), np.clip(u, 0, vw.mask.shape[1] - 1)], order=1, mode='nearest')
        px = 0.004 / vw.mpp                                              # 4 mm in from the sheet outline = full weight
        ew = np.clip(edge / px, 0.0, 1.0) ** 2
        w = vis * inb * facing ** 4 * (0.02 + ew) * BONUS.get(vw.name, 1.0)
        if m == 1 and vw.axis == 0:
            cup = (np.abs(Pt[:, 0]) > 0.066) & (np.abs(Pt[:, 0]) < 0.128) & (Pt[:, 2] > 1.335) & (Pt[:, 2] < 1.425) & (Pt[:, 1] > -0.012) & (Pt[:, 1] < 0.078)
            w = np.where(cup, 0.0, w)
        acc += bilinear(vw.rgb, u, v) * w[:, None]; wsum += w
        print('   %-11s paints %4.1f%% of %s texels' % (vw.name, 100 * (w > 1e-4).mean(), name))
    good = wsum > 2e-3
    col = np.zeros((len(Pt), 3)); col[good] = acc[good] / wsum[good, None]
    if (~good).any():
        tree = cKDTree(Pt[good]); dd, j = tree.query(Pt[~good], k=4)
        wj = 1.0 / (dd + 1e-4); col[~good] = (col[good][j] * wj[:, :, None]).sum(1) / wj.sum(1, keepdims=True)
    print('   %s: %.1f%% of texels seen by no sheet (filled from 3D neighbours)' % (name, 100 * (~good).mean()))
    img = np.zeros((TEX, TEX, 3), np.float32); img[ys, xs] = col
    idx = ndi.distance_transform_edt(~cov, return_distances=False, return_indices=True)       # island padding
    img = img[idx[0], idx[1]]
    return Image.fromarray(np.clip(img + 0.5, 0, 255).astype(np.uint8), 'RGB')


if '--grin' in sys.argv:
    bake(1, 'head').save(os.path.join(OUT, 'moxie_head_grin.png'))
else:
    bake(0, 'body').save(os.path.join(OUT, 'moxie_body.png'))
    bake(1, 'head').save(os.path.join(OUT, 'moxie_head.png'))
    json.dump({v.name: [v.u0, v.v0, v.mpp, v.axis, v.su] for vs in VIEWS.values() for v in vs}, open(os.path.join(WORK, 'views_final.json'), 'w'), indent=1)
print('done')
