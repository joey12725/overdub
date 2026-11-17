"""Paints Moxie's face and eye textures (plain Python: numpy + PIL, no Blender).

    python -I art/moxie_c/mc_paint.py <out_dir>

Everything is drawn from the same layout numbers the head builder uses (mc_facedef), so painted
lines sit exactly on the modelled lids.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mc_facedef as fd  # noqa: E402

SKIN = (200, 137, 96)
SKIN_SHADE = (158, 92, 66)
BROW = (44, 24, 18)
LASH = (30, 16, 14)


def offset_poly(line, dist):
    """Offset an open polyline (n,2) sideways by dist (array or scalar), +dist = left of travel."""
    line = np.asarray(line)
    t = np.gradient(line, axis=0)
    t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-12)
    nrm = np.stack([-t[:, 1], t[:, 0]], axis=1)
    return line + nrm * np.broadcast_to(np.asarray(dist, dtype=np.float64), (len(line),))[:, None]


class Canvas:
    def __init__(self, size, span_x, cx, cz, bg, ss=2):
        self.ss = ss
        self.w, self.h = size[0] * ss, size[1] * ss
        self.size = size
        self.span = span_x
        self.cx, self.cz = cx, cz
        self.img = Image.new("RGB", (self.w, self.h), bg)

    def px(self, pts):
        pts = np.asarray(pts, dtype=np.float64).reshape(-1, 2)
        s = self.w / self.span
        return [(float((x - self.cx) * s + self.w / 2), float(self.h / 2 - (z - self.cz) * s))
                for x, z in pts]

    def poly(self, pts, col, blur_mm=0.0, alpha=1.0):
        layer = Image.new("L", (self.w, self.h), 0)
        ImageDraw.Draw(layer).polygon(self.px(pts), fill=int(255 * alpha))
        if blur_mm > 0:
            layer = layer.filter(ImageFilter.GaussianBlur(blur_mm * 0.001 * self.w / self.span))
        self.img.paste(Image.new("RGB", (self.w, self.h), col), (0, 0), layer)

    def ellipse(self, c, rx, rz, col, blur_mm=0.0, alpha=1.0, rot=0.0):
        a = np.linspace(0, 2 * math.pi, 90, endpoint=False)
        x, z = rx * np.cos(a), rz * np.sin(a)
        cr, sr = math.cos(rot), math.sin(rot)
        pts = np.stack([c[0] + x * cr - z * sr, c[1] + x * sr + z * cr], axis=1)
        self.poly(pts, col, blur_mm, alpha)

    def stroke(self, line, width, col, blur_mm=0.0, alpha=1.0):
        """Tapered stroke along an open polyline; width scalar or per-point array (metres)."""
        w = np.broadcast_to(np.asarray(width, dtype=np.float64), (len(line),)) * 0.5
        a = offset_poly(line, w)
        b = offset_poly(line, -w)
        self.poly(np.vstack([a, b[::-1]]), col, blur_mm, alpha)

    def done(self):
        return self.img.resize(self.size, Image.LANCZOS)


def mm(*a):
    return np.array(a, dtype=np.float64) * 0.001


def paint_face(path, size=2048):
    c = Canvas((size, size), fd.FACE_SPAN, 0.0, fd.FACE_Z0, SKIN)
    ex, ez = fd.EYE_C
    # soft warm shading low on the cheeks / jaw and a blush under the eyes
    for s in (1, -1):
        c.ellipse((s * 0.047, ez - 0.026), 0.019, 0.010, (214, 110, 92), blur_mm=5.5, alpha=0.32)
    # nose: small shadow wedge under the tip + side plane hint
    nz = fd.NOSE_TIP_Z
    c.poly([(-0.0030, nz - 0.0042), (0.0046, nz - 0.0040), (0.0012, nz - 0.0062)], SKIN_SHADE,
           blur_mm=0.35, alpha=0.9)
    c.stroke(np.array([(0.0050, nz + 0.016), (0.0062, nz + 0.008), (0.0058, nz + 0.001)]),
             np.array([0.0002, 0.0009, 0.0002]), SKIN_SHADE, blur_mm=0.3, alpha=0.55)
    # under-lip shadow
    mx, mz = fd.MOUTH_C
    c.stroke(np.array([(-0.007, mz - 0.0115), (0.0, mz - 0.0128), (0.007, mz - 0.0115)]),
             np.array([0.0003, 0.0016, 0.0003]), SKIN_SHADE, blur_mm=0.5, alpha=0.7)
    for s in (1, -1):
        lid = fd.upper_lid(60)
        low = fd.lower_lid(40)
        if s < 0:
            lid = lid * np.array([-1, 1])
            low = low * np.array([-1, 1])
        sg = 1.0 if s > 0 else -1.0
        # eyelid crease
        n = len(lid)
        t = np.linspace(0, 1, n)
        cre = offset_poly(lid, 0.0034 * sg)
        wcre = 0.0009 * np.clip(np.sin(np.clip((t - 0.12) / 0.7, 0, 1) * math.pi), 0, 1) ** 0.6
        sel = (t > 0.12) & (t < 0.82)
        c.stroke(cre[sel], wcre[sel] + 1e-5, SKIN_SHADE, blur_mm=0.15, alpha=0.95)
        # soft lid shadow just above the lash line
        c.stroke(offset_poly(lid, 0.0012 * sg), 0.0030, SKIN_SHADE, blur_mm=0.9, alpha=0.35)
        # lower lash line: outer 55 %
        t2 = np.linspace(0, 1, len(low))
        sel2 = t2 < 0.62
        wl = 0.0011 * (1 - t2 / 0.62).clip(0, 1) ** 0.7
        c.stroke(offset_poly(low, -0.0003 * sg)[sel2], wl[sel2] + 2e-5, LASH, blur_mm=0.1)
        # eyebrow: confident, inner end low, kink two thirds out
        bx = np.array([(0.0150, ez + 0.0170), (0.0270, ez + 0.0275), (0.0400, ez + 0.0335),
                       (0.0520, ez + 0.0340), (0.0610, ez + 0.0300)])
        bx = np.array(_spline(bx, 40))
        bw = 0.0046 * np.interp(np.linspace(0, 1, 40), [0, 0.15, 0.6, 1.0], [0.55, 1.0, 0.8, 0.05])
        bx[:, 0] *= s
        c.stroke(bx, bw, BROW, blur_mm=0.12)
    # face paint: a pale slanted mark on each cheek (as on the model sheet)
    for sgn in (1, -1):
        p = np.array([sgn * 0.0385, ez - 0.0345])
        d = np.array([sgn * math.cos(math.radians(58)), math.sin(math.radians(58))])
        nrm = np.array([-d[1], d[0]])
        L, W = 0.0090, 0.0042
        c.poly([p - d * L + nrm * W, p + d * L + nrm * W, p + d * L - nrm * W, p - d * L - nrm * W],
               (246, 226, 204), blur_mm=0.12, alpha=0.92)
    c.done().save(path)


def _spline(pts, n):
    pts = np.asarray(pts, dtype=np.float64)
    k = len(pts)
    out = []
    for t in np.linspace(0, k - 1, n):
        i = min(int(math.floor(t)), k - 2)
        u = t - i
        P = lambda j: pts[min(max(j, 0), k - 1)]  # noqa: E731
        p0, p1, p2, p3 = P(i - 1), P(i), P(i + 1), P(i + 2)
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3))
    return out


def paint_eye(side, size=1024):
    """One eye, drawn in true head orientation (x to her left)."""
    ex, ez = fd.EYE_C[0] * side, fd.EYE_C[1]
    c = Canvas((size, size), fd.EYE_SPAN, ex, ez, (246, 240, 232))
    icx, icz = ex + side * fd.IRIS_C_MM[0] * 0.001, ez + fd.IRIS_C_MM[1] * 0.001
    R = fd.IRIS_R_MM * 0.001
    ic = (icx, icz)
    c.ellipse(ic, R, R * 1.04, (58, 26, 8))                       # dark limbal ring
    c.ellipse(ic, R * 0.90, R * 0.94, (176, 92, 14))              # deep amber
    c.ellipse((icx, icz - R * 0.20), R * 0.80, R * 0.70, (236, 150, 22), blur_mm=1.4)
    c.ellipse((icx, icz - R * 0.50), R * 0.62, R * 0.36, (255, 208, 60), blur_mm=1.2)
    # radial flecks
    for k in range(22):
        a = math.pi * (1.02 + 0.96 * k / 21)
        p0 = np.array([icx + math.cos(a) * R * 0.42, icz + math.sin(a) * R * 0.44])
        p1 = np.array([icx + math.cos(a) * R * 0.80, icz + math.sin(a) * R * 0.84])
        c.stroke(np.array([p0, p1]), np.array([0.0002, 0.0005]), (255, 226, 120), blur_mm=0.12,
                 alpha=0.55)
    c.ellipse(ic, R * 0.40, R * 0.46, (34, 14, 6))                # pupil
    c.ellipse((icx, icz - R * 0.30), R * 0.20, R * 0.10, (120, 56, 10), blur_mm=0.5, alpha=0.8)
    # lid shadow across the top of the eye (follows the upper lid)
    lid = fd.upper_lid(50) * np.array([side, 1])
    top = lid + np.array([0, 0.012])
    bot = lid - np.array([0, 0.0048])
    c.poly(np.vstack([top, bot[::-1]]), (92, 50, 44), blur_mm=1.1, alpha=0.62)
    # highlights (same screen side on both eyes)
    c.ellipse((icx + R * 0.42, icz + R * 0.40), R * 0.27, R * 0.23, (255, 255, 255), rot=0.5)
    c.ellipse((icx - R * 0.46, icz - R * 0.44), R * 0.12, R * 0.10, (255, 250, 235))
    return c.done()


OLIVE = (106, 96, 56)


def paint_pants(path, size=2048):
    """Cargo-pants albedo. Layout (see mc_cloth.build_pants): left leg U 0..0.5, right leg U 0.5..1,
    V 0..0.74 = cuff..crotch; the seat/waist strip is V 0.76..1 (U = azimuth, 0 = front centre).
    Leg u: front 0.114, outside 0.364, back 0.614, inside 0.864."""
    W = H = size
    rng = np.random.RandomState(11)
    # mottled, slightly streaky cloth
    low = Image.fromarray((rng.rand(24, 24) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    streak = Image.fromarray((rng.rand(8, 160) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    n = (np.asarray(low, dtype=np.float64) / 255 - 0.5) * 0.16 + (np.asarray(streak, dtype=np.float64) / 255 - 0.5) * 0.07
    base = np.array(OLIVE, dtype=np.float64)[None, None, :] * (1.0 + n[:, :, None])
    vv = np.linspace(1, 0, H)[:, None, None]
    base = base * (0.93 + 0.09 * np.clip(vv / 0.74, 0, 1))          # a little darker toward the hems
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img, "RGBA")
    DARK = (62, 55, 30, 255)
    STITCH = (150, 140, 96, 255)

    def px(leg, u, z):
        return ((0.5 * leg + 0.5 * u) * W, (1 - 0.74 * (z - 0.19) / 0.61) * H)

    def line(pts, col, w):
        d.line(pts, fill=col, width=w, joint="curve")

    def dashes(leg, pts_uz, col=STITCH, w=3, dash=0.012):
        for i in range(len(pts_uz) - 1):
            (u0, z0), (u1, z1) = pts_uz[i], pts_uz[i + 1]
            L = math.hypot((u1 - u0) * 0.6, z1 - z0)
            k = max(1, int(L / dash))
            for j in range(0, k, 2):
                a, b = j / k, min(1.0, (j + 1) / k)
                line([px(leg, u0 + (u1 - u0) * a, z0 + (z1 - z0) * a),
                      px(leg, u0 + (u1 - u0) * b, z0 + (z1 - z0) * b)], col, w)
    for leg in (0, 1):
        for u in (0.364, 0.864):                      # side seams with twin stitching
            line([px(leg, u, 0.19), px(leg, u, 0.80)], DARK, 5)
            for du in (-0.012, 0.012):
                dashes(leg, [(u + du, 0.20), (u + du, 0.79)])
        for z, bow in ((0.555, 0.012), (0.405, -0.012)):      # knee panel
            pts = [(u, z + bow * math.sin(math.pi * (u + 0.136) / 0.5)) for u in np.linspace(-0.136, 0.364, 16)]
            pts = [(u % 1.0, zz) for u, zz in pts]
            seg1 = [p for p in pts if p[0] > 0.5]
            seg2 = [p for p in pts if p[0] <= 0.5]
            for seg in (seg1, seg2):
                if len(seg) > 1:
                    line([px(leg, u, zz) for u, zz in seg], DARK, 4)
                    dashes(leg, [(u, zz - 0.010) for u, zz in seg])
        # scuffs
        for _ in range(26):
            u, z = rng.uniform(0.02, 0.98), rng.uniform(0.22, 0.76)
            L = rng.uniform(0.006, 0.03)
            ang = rng.uniform(-0.6, 0.6)
            line([px(leg, u, z), px(leg, u + L * math.sin(ang), z + L * math.cos(ang))],
                 (140, 130, 86, 90) if rng.rand() < 0.6 else (60, 54, 30, 110), int(rng.uniform(2, 6)))
    # yellow zig-zag on her right shin
    zz = [(0.330, 0.470), (0.070, 0.400), (0.330, 0.330), (0.070, 0.260), (0.300, 0.200)]
    half = 0.017
    top = [px(1, u, z + half) for u, z in zz]
    bot = [px(1, u, z - half) for u, z in zz]
    d.polygon(top + bot[::-1], fill=(240, 180, 22, 255))
    d.line(top + bot[::-1] + top[:1], fill=(120, 84, 14, 255), width=3)
    # tears: skin showing through, dark frayed edge, loose threads
    def tear(leg, u, z, ru, rz, seed):
        r2 = np.random.RandomState(seed)
        k = 18
        pts, pts_o = [], []
        for i in range(k):
            a = 2 * math.pi * i / k
            s = 0.75 + 0.5 * r2.rand()
            pts.append(px(leg, u + math.cos(a) * ru * s, z + math.sin(a) * rz * s))
            pts_o.append(px(leg, u + math.cos(a) * ru * (s + 0.28), z + math.sin(a) * rz * (s + 0.38)))
        d.polygon(pts_o, fill=(52, 46, 26, 255))
        d.polygon(pts, fill=(196, 132, 92, 255))
        for i in range(9):
            uu = u + (r2.rand() - 0.5) * 1.7 * ru
            line([px(leg, uu, z + rz * 0.9), px(leg, uu + (r2.rand() - 0.5) * 0.02, z - rz * 0.9)],
                 (190, 180, 130, 255), 3)
    tear(1, 0.150, 0.625, 0.070, 0.022, 3)
    tear(0, 0.100, 0.478, 0.050, 0.017, 5)
    tear(1, 0.560, 0.300, 0.040, 0.014, 8)
    # seat / waist strip: fly, pocket stitching, yoke
    def sp(u, t):
        return (u * W, (1 - (0.76 + 0.24 * t)) * H)
    line([sp(0.0, 0.0), sp(0.0, 1.0)], DARK, 6)
    line([sp(1.0, 0.0), sp(1.0, 1.0)], DARK, 6)
    line([sp(0.5, 0.0), sp(0.5, 1.0)], DARK, 4)
    for u0 in (0.30, 0.62):
        box = [sp(u0, 0.22), sp(u0 + 0.08, 0.22), sp(u0 + 0.08, 0.78), sp(u0, 0.78), sp(u0, 0.22)]
        line(box, DARK, 4)
        line([sp(u0 + 0.006, 0.28), sp(u0 + 0.074, 0.28), sp(u0 + 0.074, 0.72), sp(u0 + 0.006, 0.72), sp(u0 + 0.006, 0.28)],
             STITCH, 2)
    for u0, u1 in ((0.035, 0.15), (0.85, 0.965)):
        line([sp(u0, 0.80), sp((u0 + u1) / 2, 0.45), sp(u1, 0.30)], DARK, 4)
    img.save(path)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    paint_face(os.path.join(out, "moxie_face.png"))
    eyes = Image.new("RGB", (2048, 1024))
    eyes.paste(paint_eye(1), (0, 0))        # her left eye  -> u 0..0.5
    eyes.paste(paint_eye(-1), (1024, 0))    # her right eye -> u 0.5..1
    eyes.save(os.path.join(out, "moxie_eyes.png"))
    paint_pants(os.path.join(out, "moxie_pants.png"))
    print("painted", out)


if __name__ == "__main__":
    main()
