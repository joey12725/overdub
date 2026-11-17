"""Procedurally painted face texture for Moxie (moxie_face.png).

The head's front faces carry material `face_paint` with a planar front-projected UV (see
mx_body.make_head): u = 0.5 + x / FACE_UV_SCALE, v = 0.5 + (z - z_c) / FACE_UV_SCALE, so features
are drawn here directly in model metres (x to her left, z up). Painted at 2x and box-filtered
down for crisp anti-aliased edges. Background is exactly the skin colour so the textured region
blends into the untextured skin.

Design (R01): big amber eyes with heavy upper lash lines and a small wing, two highlights;
thick confident brows; a small nose; an open lopsided grin with teeth; warm blush; face paint -
two cream diagonal stripes on her right cheek and a small red triangle under her left eye.
"""
import math

import bpy
import numpy as np

import mx_body
from mx_geo import PALETTE

RES = 1024
SS = 2


def hex_rgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


class Canvas:
    def __init__(self, res, bg):
        self.n = res * SS
        self.img = np.ones((self.n, self.n, 3), np.float32) * hex_rgb(bg)
        self.scale = mx_body.FACE_UV_SCALE
        self.cx, self.cz = mx_body.FACE_UV_CENTRE

    def px(self, x, z):
        u = 0.5 + (x - self.cx) / self.scale
        v = 0.5 + (z - self.cz) / self.scale
        return u * self.n, v * self.n

    def poly_mask(self, pts):
        """Boolean mask (full canvas) of a polygon given in model metres [(x, z), ...]."""
        P = np.array([self.px(x, z) for x, z in pts], np.float64)
        x0, y0 = np.floor(P.min(0)).astype(int) - 1
        x1, y1 = np.ceil(P.max(0)).astype(int) + 1
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, self.n), min(y1, self.n)
        mask = np.zeros((self.n, self.n), bool)
        if x1 <= x0 or y1 <= y0:
            return mask
        ys, xs = np.mgrid[y0:y1, x0:x1]
        xs = xs + 0.5
        ys = ys + 0.5
        inside = np.zeros(xs.shape, bool)
        n = len(P)
        for i in range(n):
            ax, ay = P[i]
            bx, by = P[(i + 1) % n]
            cond = (ay > ys) != (by > ys)
            with np.errstate(divide='ignore', invalid='ignore'):
                xint = ax + (ys - ay) * (bx - ax) / (by - ay)
            inside ^= cond & (xs < xint)
        mask[y0:y1, x0:x1] = inside
        return mask

    def ellipse_mask(self, cx, cz, rx, rz, rot=0.0):
        pts = []
        for k in range(48):
            a = math.tau * k / 48
            ex, ez = math.cos(a) * rx, math.sin(a) * rz
            c, s = math.cos(rot), math.sin(rot)
            pts.append((cx + ex * c - ez * s, cz + ex * s + ez * c))
        return self.poly_mask(pts)

    def fill(self, mask, color, alpha=1.0):
        col = hex_rgb(color) if isinstance(color, str) else np.asarray(color, np.float32)
        self.img[mask] = self.img[mask] * (1 - alpha) + col * alpha

    def soft(self, cx, cz, rx, rz, color, alpha):
        """Gaussian-ish soft blob (blush)."""
        ys, xs = np.mgrid[0:self.n, 0:self.n]
        u, v = self.px(cx, cz)
        sx = rx / self.scale * self.n
        sz = rz / self.scale * self.n
        g = np.exp(-(((xs + 0.5 - u) / sx) ** 2 + ((ys + 0.5 - v) / sz) ** 2))
        col = hex_rgb(color)
        a = (g * alpha)[..., None]
        self.img = self.img * (1 - a) + col * a

    def stroke(self, pts, widths):
        """Outline polygon for a variable-width stroke along a polyline (model metres)."""
        left, right = [], []
        n = len(pts)
        for i in range(n):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, n - 1)]
            dx, dz = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dx, dz) or 1.0
            nx, nz = -dz / ln, dx / ln
            w = widths(i / (n - 1)) * 0.5
            left.append((pts[i][0] + nx * w, pts[i][1] + nz * w))
            right.append((pts[i][0] - nx * w, pts[i][1] - nz * w))
        return left + right[::-1]

    def result(self):
        r = self.img.reshape(RES, SS, RES, SS, 3).mean((1, 3))
        return np.clip(r, 0, 1)


def bezier(p0, p1, p2, p3, n=16):
    out = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t * t
        d = t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


# Eye layout (her left eye; the right one is mirrored). Model metres.
EYE_Z = 1.447
EYE_IN = (0.017, 1.441)
EYE_OUT = (0.063, 1.453)
EYE_TOP = 1.466
EYE_BOT = 1.425
IRIS_C = (0.040, 1.444)


def eye_outline(s):
    """Almond: flat-ish heavy upper lid, rounder lower lid. s=+1 her left, -1 her right."""
    ix, iz = EYE_IN
    ox, oz = EYE_OUT
    upper = bezier((ix, iz), (ix + 0.006, EYE_TOP - 0.002), (ox - 0.016, EYE_TOP + 0.002), (ox, oz))
    lower = bezier((ox, oz), (ox - 0.006, EYE_BOT - 0.002), (ix + 0.010, EYE_BOT + 0.001), (ix, iz))
    pts = upper + lower[1:-1]
    return [(s * x, z) for x, z in pts], [(s * x, z) for x, z in upper], [(s * x, z) for x, z in lower]


def paint_eye(cv, s):
    outline, upper, lower = eye_outline(s)
    sclera = cv.poly_mask(outline)
    cv.fill(sclera, '#FBF6EF')
    # lid shadow on the white just under the upper lid
    shadow = cv.poly_mask([(x, z - 0.0055) for x, z in upper] + [(x, z) for x, z in reversed(upper)])
    cv.fill(shadow & sclera, '#D9C3B8')
    ixc, izc = IRIS_C
    iris = cv.ellipse_mask(s * ixc, izc, 0.0146, 0.0198) & sclera
    cv.fill(iris, '#7A3E12')
    inner = cv.ellipse_mask(s * ixc, izc - 0.002, 0.0120, 0.0152) & sclera
    cv.fill(inner, '#C98A2A')
    low = cv.ellipse_mask(s * ixc, izc - 0.008, 0.0098, 0.0068) & sclera
    cv.fill(low, '#F6CC55')
    pupil = cv.ellipse_mask(s * ixc, izc + 0.0005, 0.0062, 0.0096) & sclera
    cv.fill(pupil, '#2A1409')
    top_dark = cv.poly_mask([(s * (ixc - 0.02), EYE_TOP + 0.01), (s * (ixc + 0.02), EYE_TOP + 0.01),
                             (s * (ixc + 0.02), izc + 0.010), (s * (ixc - 0.02), izc + 0.010)])
    cv.fill(top_dark & iris, '#4A230C', 0.65)
    # highlights: big one up and toward the nose side, small one low and outward
    cv.fill(cv.ellipse_mask(s * (ixc - 0.0050), izc + 0.0070, 0.0050, 0.0058) & sclera, '#FFFFFF')
    cv.fill(cv.ellipse_mask(s * (ixc + 0.0060), izc - 0.0078, 0.0024, 0.0024) & sclera, '#FFFFFF')
    # heavy upper lash line with a flicked wing past the outer corner
    ox, oz = EYE_OUT
    lash_path = [(x, z + 0.0012) for x, z in upper] + [(s * (ox + 0.006), oz + 0.0045),
                                                       (s * (ox + 0.010), oz + 0.0085)]
    cv.fill(cv.poly_mask(cv.stroke(lash_path, lambda t: 0.0034 + 0.0056 * math.sin(min(t * 1.15, 1) * math.pi * 0.62)
                                   if t < 0.86 else 0.0058 * (1 - t) / 0.14 + 0.0010)), '#1E1214')
    # thin lower lash on the outer half
    lo = [(x, z - 0.0006) for x, z in lower[:9]]
    cv.fill(cv.poly_mask(cv.stroke(lo, lambda t: 0.0016 * (1 - t) + 0.0004)), '#3A2220')
    # double-lid crease
    crease = [(x, z + 0.0055) for x, z in upper[3:14]]
    cv.fill(cv.poly_mask(cv.stroke(crease, lambda t: 0.0011 * math.sin(t * math.pi) + 0.0002)), '#7A4430')


def paint_brow(cv, s):
    pts = bezier((0.014, 1.474), (0.026, 1.4835), (0.046, 1.4885), (0.068, 1.4815), 14)
    pts = [(s * x, z) for x, z in pts]
    cv.fill(cv.poly_mask(cv.stroke(pts, lambda t: 0.0068 * (1 - t) ** 0.6 + 0.0015)), '#2A1916')


def paint_mouth(cv):
    # An open, slightly lopsided confident grin (her left corner higher).
    lc, rc = (0.029, 1.4005), (-0.026, 1.3970)
    top = bezier(rc, (-0.012, 1.3915), (0.012, 1.3925), lc, 18)
    bot = bezier(lc, (0.016, 1.3755), (-0.012, 1.3745), rc, 18)
    mouth = cv.poly_mask(top + bot[1:-1])
    cv.fill(mouth, '#5B1F22')
    tongue = cv.ellipse_mask(0.002, 1.3790, 0.013, 0.0055)
    cv.fill(tongue & mouth, '#B5545A')
    teeth = cv.poly_mask(top + [(x, z - 0.0055) for x, z in reversed(top)])
    cv.fill(teeth & mouth, '#FFFDF7')
    # lip line (heavier on the top), corner smirk ticks
    cv.fill(cv.poly_mask(cv.stroke(top, lambda t: 0.0021)), '#3A1A18')
    cv.fill(cv.poly_mask(cv.stroke(bot, lambda t: 0.0010 + 0.0006 * math.sin(t * math.pi))), '#5A2A26')
    cv.fill(cv.poly_mask(cv.stroke([(lc[0] - 0.001, lc[1] - 0.002), (lc[0] + 0.004, lc[1] + 0.0015)],
                                   lambda t: 0.0016)), '#4A2420')
    cv.fill(cv.poly_mask(cv.stroke([(rc[0] + 0.001, rc[1] - 0.002), (rc[0] - 0.003, rc[1] + 0.0012)],
                                   lambda t: 0.0013)), '#4A2420')
    # lower lip highlight shadow
    cv.fill(cv.poly_mask(cv.stroke(bezier((-0.010, 1.3685), (-0.004, 1.3665), (0.006, 1.3665),
                                          (0.011, 1.3690), 8), lambda t: 0.0014 * math.sin(t * math.pi))),
            '#94553C', 0.7)


def paint_nose(cv):
    cv.fill(cv.poly_mask(cv.stroke([(0.0005, 1.4265), (0.0035, 1.4240), (0.0070, 1.4250)],
                                   lambda t: 0.0024 * math.sin(t * math.pi) + 0.0004)), '#7E4A31')
    cv.soft(-0.003, 1.433, 0.004, 0.009, '#8E5536', 0.25)


def paint_face_marks(cv):
    # Her right cheek (-x): two cream diagonal stripes (R01's light cheek band).
    for dz in (0.0, -0.0085):
        p0 = (-0.072, 1.4245 + dz)
        p1 = (-0.036, 1.4125 + dz)
        cv.fill(cv.poly_mask(cv.stroke([p0, p1], lambda t: 0.0050 * (1 - 0.35 * t))), PALETTE['face_paint'])
    # Her left cheek: a small red triangle under the eye.
    cv.fill(cv.poly_mask([(0.050, 1.4185), (0.066, 1.4215), (0.056, 1.4065)]), '#C8283F')


def paint():
    cv = Canvas(RES, PALETTE['skin'])
    # warm blush under the eyes
    for s in (1, -1):
        cv.soft(s * 0.050, 1.423, 0.016, 0.008, '#C9604D', 0.35)
    paint_nose(cv)
    for s in (1, -1):
        paint_eye(cv, s)
        paint_brow(cv, s)
    paint_mouth(cv)
    paint_face_marks(cv)
    return cv.result()


def make_image(path=None):
    """Paint, store as a packed Blender image (and optionally save a PNG), return the image."""
    rgb = paint()
    rgba = np.concatenate([rgb, np.ones((RES, RES, 1), np.float32)], 2)
    img = bpy.data.images.get("moxie_face")
    if img is None:
        img = bpy.data.images.new("moxie_face", RES, RES, alpha=False)
    img.colorspace_settings.name = 'sRGB'
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    if path:
        img.filepath_raw = path
        img.file_format = 'PNG'
        img.save()
    img.pack()
    return img


def hook_material(img):
    """Give the face_paint material an image texture node feeding Base Color."""
    mat = bpy.data.materials.get('face_paint')
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = 'Linear'
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.nodes.active = tex
    mat.diffuse_color = (1, 1, 1, 1)
