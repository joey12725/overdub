"""Step 1 (venv python): register the raw generator meshes to the model sheets.

  body  (gen/raw/body_flb.glb)      <-> docs/reference/generated/cut/moxie_front.png + moxie_left.png
  head  (gen/raw/head_full_s11.glb) <-> head sheets (head_front1 / head_side1), which are mapped into the body
  bare  (gen/raw/head_bare_s11.glb)     sheet frame by a silhouette fit (scale K + offsets)

World frame = Blender: X her left, -Y front, Z up, metres, feet on Z=0, 1.6 m tall.
Writes work/align.json, work/body_w.ply, work/head_w.ply (hair head with the face snapped onto the clean bare-head
face), work/bare_w.ply and overlay images work/ov_*.png (sheet mask = red, mesh silhouette = green, both = yellow)."""
import os, sys, json
import numpy as np, trimesh
from PIL import Image
from scipy import ndimage as ndi
from scipy.spatial import cKDTree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sheet_tools import cutout
HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, '..', '..', 'docs', 'reference', 'generated'); WORK = os.path.join(HERE, 'work'); RAW = os.path.join(HERE, 'gen', 'raw')
S = 1.6 / 1400; BASE = 1480; AXIS_X = 576.0; SIDE_REF = 520.0


def load(name):
    m = trimesh.load(os.path.join(RAW, name), force='mesh', process=False)
    v = np.asarray(m.vertices, np.float64); v = np.stack([v[:, 0], -v[:, 2], v[:, 1]], 1)      # glTF -> Blender axes
    return trimesh.Trimesh(v, np.asarray(m.faces), process=False)


def mask_of(path_or_im):
    im = path_or_im if isinstance(path_or_im, Image.Image) else Image.open(path_or_im)
    return np.asarray(im.convert('RGBA'))[:, :, 3] > 128


def splat(u, v, shape, ds):
    h, w = shape[0] // ds, shape[1] // ds
    ui = np.floor(u / ds).astype(int); vi = np.floor(v / ds).astype(int)
    ok = (ui >= 0) & (ui < w) & (vi >= 0) & (vi < h)
    m = np.zeros((h, w), bool); m[vi[ok], ui[ok]] = True
    return ndi.binary_closing(m, iterations=2)


def down(mask, ds):
    h, w = mask.shape[0] // ds, mask.shape[1] // ds
    return mask[:h * ds, :w * ds].reshape(h, ds, w, ds).mean((1, 3)) > 0.5


def iou(a, b): return (a & b).sum() / max(1, (a | b).sum())


class View:
    """sheet pixel <-> world: u = u0 + h/mpp, v = v0 - z/mpp   (h = world x for front, world y for left)"""
    def __init__(self, mask, u0, v0, mpp, axis): self.mask, self.u0, self.v0, self.mpp, self.axis = mask, u0, v0, mpp, axis
    def uv(self, P): return self.u0 + P[:, self.axis] / self.mpp, self.v0 - P[:, 2] / self.mpp


def fit(mesh, front, left, ds=3, tag=''):
    """Stage 1: scale + x + z from the FRONT silhouette. Stage 2: depth (y) from the LEFT silhouette, letting the left
    drawing have its own scale and height offset (the sheets are separate drawings); returns s, t and the fitted left View."""
    P = np.asarray(mesh.sample(500000))
    fm = down(front.mask, ds)
    vs, us = np.where(front.mask)
    zt, zb = (front.v0 - vs.min()) * front.mpp, (front.v0 - vs.max()) * front.mpp
    xc = ((us.min() + us.max()) / 2 - front.u0) * front.mpp
    s = (zt - zb) / (P[:, 2].max() - P[:, 2].min())
    t = np.array([xc - s * (P[:, 0].min() + P[:, 0].max()) / 2, 0.0, zt - s * P[:, 2].max()])

    def climb(score, x, steps, n=60):
        best = score(x)
        for it in range(n):
            improved = False
            for k in range(len(x)):
                for sg in (1, -1):
                    x2 = x.copy(); x2[k] += sg * steps[k]
                    sc = score(x2)
                    if sc > best + 1e-5: best, x, improved = sc, x2, True
            if not improved:
                steps = steps * 0.5
                if steps[0] < 2e-4: break
        return x, best
    px = front.mpp / S
    x, b1 = climb(lambda x: iou(splat(*front.uv(P * x[3] + np.array([x[0], 0, x[1]])), front.mask.shape, ds), fm) if True else 0,
                  np.array([t[0], t[2], 0.0, s]), np.array([0.012 * px, 0.012 * px, 0.0, 0.02 * s]))
    s, t = x[3], np.array([x[0], 0.0, x[1]])
    W = P * s + t
    # stage 2: left view  u = u0 + (y + ty) * r / mpp ,  v = v0 + dv - z * r / mpp
    lm = down(left.mask, ds)
    vs, us = np.where(left.mask)
    ty0 = ((us.min() + us.max()) / 2 - left.u0) * left.mpp - (W[:, 1].min() + W[:, 1].max()) / 2

    def lscore(x):
        ty, dv, r = x
        return iou(splat(left.u0 + (W[:, 1] + ty) * r / left.mpp, left.v0 + dv - W[:, 2] * r / left.mpp, left.mask.shape, ds), lm)
    x, b2 = climb(lscore, np.array([ty0, 0.0, 1.0]), np.array([0.012 * px, 8.0, 0.02]))
    ty, dv, r = x
    t[1] = ty
    lv = View(left.mask, left.u0, left.v0 + dv, left.mpp / r, 1)
    print(f'  {tag}: front IoU {b1:.3f}; left IoU {b2:.3f} (left drawing scale x{r:.3f}, dv {dv:.1f}px)')
    W = P * s + t
    for nm, vw in (('front', front), ('left', lv)):
        a_ = splat(*vw.uv(W), vw.mask.shape, 2); b_ = down(vw.mask, 2)
        Image.fromarray(np.dstack([b_ * 255, a_ * 255, np.zeros_like(a_)]).astype(np.uint8)).save(os.path.join(WORK, f'ov_{tag}_{nm}.png'))
    return float(s), t, lv


# ---------- sheets ----------
bf = mask_of(os.path.join(GEN, 'cut', 'moxie_front.png')); bl = mask_of(os.path.join(GEN, 'cut', 'moxie_left.png'))
body_front = View(bf, AXIS_X, BASE, S, 0); body_left = View(bl, SIDE_REF, BASE, S, 1)
hf_im = cutout(Image.open(os.path.join(GEN, 'work', 'head_front1.png'))); hl_im = cutout(Image.open(os.path.join(GEN, 'work', 'head_side1.png')))
hf, hl = mask_of(hf_im), mask_of(hl_im)


def fit_sheet(hm, bm, k0, rows=292):
    """head sheet -> body sheet: X = ox + u / K ; find K, ox, oy by IoU over the rows above the chin"""
    tgt = bm.copy(); tgt[rows:] = False
    ys, xs = np.where(tgt); y0, x0 = ys.min(), (xs.min() + xs.max()) // 2
    best = (-1,)
    for K in np.arange(k0 - 0.5, k0 + 0.5001, 0.02):
        w, h = int(round(hm.shape[1] / K)), int(round(hm.shape[0] / K))
        small = np.asarray(Image.fromarray((hm * 255).astype(np.uint8)).resize((w, h), Image.BOX)) > 127
        sy, sx = np.where(small); hy0, hx0 = sy.min(), (sx.min() + sx.max()) // 2
        for dy in range(-10, 11, 1):
            for dx in range(-10, 11, 1):
                oy, ox = y0 - hy0 + dy, x0 - hx0 + dx
                canvas = np.zeros_like(tgt)
                ya, yb = max(0, oy), min(tgt.shape[0], oy + h); xa, xb = max(0, ox), min(tgt.shape[1], ox + w)
                canvas[ya:yb, xa:xb] = small[ya - oy:yb - oy, xa - ox:xb - ox]
                canvas[rows:] = False
                sc = iou(canvas, tgt)
                if sc > best[0]: best = (sc, K, ox, oy)
    return best


sc, K, ox, oy = fit_sheet(hf, bf, 3.5)
print('head front sheet -> body sheet: IoU %.3f K %.2f offset %d %d' % (sc, K, ox, oy))
sc2, K2, ox2, oy2 = fit_sheet(hl, bl, K)
print('head left  sheet -> body sheet: IoU %.3f K %.2f offset %d %d' % (sc2, K2, ox2, oy2))
print('eye anchor check (first pass noted 575.5,240): body px of head (767,545) =', ox + 767 / K, oy + 545 / K)
Sh = S / K
head_front = View(hf, (AXIS_X - ox) * K, (BASE - oy) * K, Sh, 0)
# the left sheet has its own drawing scale: use its own K2 for the depth axis but keep the front sheet's height mapping
head_left = View(hl, (SIDE_REF - ox2) * K, (BASE - oy2) * K, Sh, 1)

out = {'S': S, 'K': K, 'K2': K2, 'head_front': [head_front.u0, head_front.v0, Sh], 'head_left': [head_left.u0, head_left.v0, Sh]}
body = load('body_flb.glb'); s, t, body_left_v = fit(body, body_front, body_left, 3, 'body'); body.vertices = body.vertices * s + t
out['body'] = [s, *t]
head = load(sys.argv[1] if len(sys.argv) > 1 else 'head_full_s11.glb'); s, t, head_left_v = fit(head, head_front, head_left, 4, 'head'); head.vertices = head.vertices * s + t
out['head'] = [s, *t]
bfm = mask_of(cutout(Image.open(os.path.join(GEN, 'work', 'head_bare_front1.png')))); blm = mask_of(cutout(Image.open(os.path.join(GEN, 'work', 'head_bare_side1.png'))))
bare = load(sys.argv[2] if len(sys.argv) > 2 else 'head_bare_s11.glb')
s, t, bare_left_v = fit(bare, View(bfm, head_front.u0, head_front.v0, Sh, 0), View(blm, head_left.u0, head_left.v0, Sh, 1), 4, 'bare'); bare.vertices = bare.vertices * s + t
out['bare'] = [s, *t]
print('body z', body.vertices[:, 2].min(), body.vertices[:, 2].max(), 'head z', head.vertices[:, 2].min(), head.vertices[:, 2].max())

# ---------- face snap: full-head skin verts -> clean bare-head face ----------
hv = np.asarray(head.vertices); hn = np.asarray(head.vertex_normals)
bv = np.asarray(bare.vertices); bn = np.asarray(bare.vertex_normals)


def wz(v): return (head_front.v0 - v) * Sh
def wx(u): return (u - head_front.u0) * Sh


# face window from the head sheet (px): chin v~752, brow/fringe v~400, cheeks u 592..945
z_chin, z_top = wz(752), wz(400); x_l, x_r = wx(592), wx(945)
band = (bv[:, 2] > z_chin) & (bv[:, 2] < z_top)
ear_y = float(np.percentile(bv[band, 1], 55))
front_bare = (bv[:, 2] > z_chin - 0.004) & (bv[:, 2] < z_top + 0.02) & (bv[:, 1] < ear_y) & (bn[:, 1] < 0.25)
bsel = bv[front_bare]; tree = cKDTree(bsel)
cand = (hv[:, 2] > z_chin - 0.004) & (hv[:, 2] < z_top) & (hv[:, 0] > x_l) & (hv[:, 0] < x_r) & (hv[:, 1] < ear_y) & (hn[:, 1] < 0.0)
best = (1e9, 0, 0)
sub = hv[cand][::7]
for dy in np.arange(-0.016, 0.0161, 0.002):
    for dz in np.arange(-0.018, 0.0181, 0.002):
        dd, _ = tree.query(sub - np.array([0, dy, dz]))
        m_ = np.percentile(dd, 35)
        if m_ < best[0]: best = (m_, dy, dz)
print('bare -> full rigid refine (m): dy %.3f dz %.3f' % best[1:])
shift = np.array([0, best[1], best[2]]); bare.vertices = bare.vertices + shift; bv = bv + shift; bsel = bsel + shift; tree = cKDTree(bsel)
out['bare'][2] += float(best[1]); out['bare'][3] += float(best[2])
d, j = tree.query(hv[cand])
print('face candidates', int(cand.sum()), 'distance to bare face mm: pct 10/25/50/75/90', np.round(np.percentile(d, [10, 25, 50, 75, 90]) * 1000, 2))
out.update({'z_chin': float(z_chin), 'z_top': float(z_top), 'ear_y': ear_y, 'x_l': float(x_l), 'x_r': float(x_r)})
# heightfield of the clean face: front-most bare surface depth y(x, z) on a 0.5 mm grid
RES = 0.0005; PAD = 0.012
gx0, gz0 = x_l - PAD, z_chin - PAD
gw, gh = int((x_r - x_l + 2 * PAD) / RES) + 1, int((z_top - z_chin + 2 * PAD) / RES) + 1
Pb, fidx = trimesh.sample.sample_surface(bare, 4000000)
Pb = np.asarray(Pb); fn = np.asarray(bare.face_normals)[fidx]
ok = (fn[:, 1] < 0.1) & (Pb[:, 1] < ear_y)
Pb = Pb[ok]
ix = np.floor((Pb[:, 0] - gx0) / RES).astype(int); iz = np.floor((Pb[:, 2] - gz0) / RES).astype(int)
ok = (ix >= 0) & (ix < gw) & (iz >= 0) & (iz < gh)
Hf = np.full((gh, gw), np.inf); np.minimum.at(Hf, (iz[ok], ix[ok]), Pb[ok, 1])
valid = np.isfinite(Hf)
ind = ndi.distance_transform_edt(~valid, return_distances=False, return_indices=True)
Hf = Hf[ind[0], ind[1]]
Hf = ndi.gaussian_filter(Hf, 1.2)
inside = ndi.binary_erosion(ndi.binary_fill_holes(valid), iterations=3)
edge_w = np.clip(ndi.distance_transform_edt(inside) * RES / 0.008, 0, 1)          # feather 8 mm in from the face outline
edge_w = edge_w * edge_w * (3 - 2 * edge_w)
idx = np.where(cand)[0]; p = hv[idx]
fx = (p[:, 0] - gx0) / RES - 0.5; fz = (p[:, 2] - gz0) / RES - 0.5
yb = ndi.map_coordinates(Hf, [fz, fx], order=1, mode='nearest')
ew = ndi.map_coordinates(edge_w, [fz, fx], order=1, mode='nearest')
delta = yb - p[:, 1]                       # > 0: the vertex stands in front of the clean face (a hair strand)
SN0, SN1 = float(os.environ.get('SN0', 0.0035)), float(os.environ.get('SN1', 0.0075))
w = np.clip((SN1 - delta) / (SN1 - SN0), 0, 1); w = w * w * (3 - 2 * w) * ew
wb = np.clip((delta + 0.016) / 0.005, 0, 1); w = w * wb * wb * (3 - 2 * wb)      # leave inner shells far behind the face alone
hv2 = hv.copy(); hv2[idx, 1] = p[:, 1] + delta * w
head.vertices = hv2
print('face relief: moved %d verts; mean |dy| %.2f mm, max %.2f mm' % ((w > 0.5).sum(), np.abs(delta * w).mean() * 1000, np.abs(delta * w).max() * 1000))
np.save(os.path.join(WORK, 'face_height.npy'), Hf.astype(np.float32))
out['head_shift'] = [0.0, float(best[1]), float(best[2])]
out['views'] = {  # sheet px <-> world: u = u0 + h/mpp, v = v0 - z/mpp ; head views already include head_shift
    'body_front': [AXIS_X, BASE, S], 'body_left': [body_left_v.u0, body_left_v.v0, body_left_v.mpp],
    'head_front': [head_front.u0, head_front.v0 + best[2] / Sh, Sh],
    'head_left': [bare_left_v.u0 + best[1] / bare_left_v.mpp, bare_left_v.v0 + best[2] / bare_left_v.mpp, bare_left_v.mpp]}
json.dump(out, open(os.path.join(WORK, 'align.json'), 'w'), indent=1)
for nm, m in (('body_w', body), ('head_w', head), ('bare_w', bare)):
    m.export(os.path.join(WORK, nm + '.ply'))
print('wrote plys')
