"""Face layout shared by the texture painter (plain Python + PIL) and the Blender head builder.

All coordinates are head-local metres in the frontal plane: x = her left (+) / right (-),
z = up. The head-local origin sits between the ears (see mc_head.HEAD_C).
"""
import math

import numpy as np

import mc_headshape as hs

# Landmarks traced from the head sheet (ref_measure.py), in head heights: eye line 0.597 down from
# the crown, eye centres 0.172 either side of the centre line, mouth line 0.846, nose tip 0.735.
EYE_C = (0.172 * hs.H, float(hs.z_of(0.597)))   # centre of her left eye (x, z); the right eye is mirrored
MOUTH_C = (0.0, float(hs.z_of(0.846)))
NOSE_TIP_Z = float(hs.z_of(0.735))

# Eye opening outline, mm relative to EYE_C, x positive = outward (away from the nose). Traced:
# opening 0.171 H wide, 0.098 H tall, inner corner low, upper lid peaking just outside the centre.
EYE_PTS_MM = [(-17.8, -4.2), (-12.0, 6.0), (-4.2, 9.9), (3.7, 11.0), (11.5, 9.4), (18.3, 5.2),
              (15.2, -5.2), (7.8, -9.9), (-1.6, -11.2), (-11.0, -9.2)]
# Mouth opening outline (a closed-teeth grin), mm relative to MOUTH_C.
MOUTH_PTS_MM = [(-19.0, 4.4), (-17.2, 3.1), (-9.2, 1.2), (0.0, 0.6), (9.2, 1.2), (17.2, 3.1),
                (19.0, 4.4), (16.0, -1.4), (9.2, -4.9), (0.0, -6.0), (-9.2, -4.9), (-16.0, -1.4)]

IRIS_C_MM = (-0.8, 0.4)          # iris centre relative to EYE_C
IRIS_R_MM = 11.0
EYE_K = 1.0

# Face texture mapping: u = 0.5 + x / FACE_SPAN, v = 0.5 + (z - FACE_Z0) / FACE_SPAN
FACE_SPAN = 0.22
FACE_Z0 = -0.03
# Eye texture: each eye uses half of a 2:1 image; local span around EYE_C
EYE_SPAN = 0.052


def _catmull_closed(pts, n):
    pts = np.asarray(pts, dtype=np.float64)
    k = len(pts)
    out = []
    for t in np.linspace(0, k, n, endpoint=False):
        i = int(math.floor(t))
        u = t - i
        p0, p1, p2, p3 = pts[(i - 1) % k], pts[i % k], pts[(i + 1) % k], pts[(i + 2) % k]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3))
    return np.array(out)


def eye_outline(side=1, n=96, scale=1.0):
    """Closed polyline (n,2) in head-local (x,z) metres for the eye opening. side=+1 her left."""
    p = _catmull_closed(EYE_PTS_MM, n) * 0.001 * scale * EYE_K
    p[:, 0] = EYE_C[0] + p[:, 0]
    p[:, 1] = EYE_C[1] + p[:, 1]
    if side < 0:
        p[:, 0] *= -1
        p = p[::-1]
    return p


def mouth_outline(n=96, scale=1.0):
    p = _catmull_closed(MOUTH_PTS_MM, n) * 0.001 * scale
    p[:, 0] += MOUTH_C[0]
    p[:, 1] += MOUTH_C[1]
    return p


def upper_lid(n=40, ext_in=0.0):
    """Open polyline along the upper lid of her left eye from the inner to the outer corner."""
    full = _catmull_closed(EYE_PTS_MM, 200) * 0.001 * EYE_K
    # control point 0 is the inner corner, point 5 the outer corner -> parameter 0 .. 5/10
    seg = full[0:101]
    idx = np.linspace(0, 100, n).round().astype(int)
    p = seg[idx].copy()
    p[:, 0] += EYE_C[0]
    p[:, 1] += EYE_C[1]
    return p


def lower_lid(n=30):
    full = _catmull_closed(EYE_PTS_MM, 200) * 0.001 * EYE_K
    seg = np.vstack([full[100:], full[:1]])
    idx = np.linspace(0, len(seg) - 1, n).round().astype(int)
    p = seg[idx].copy()
    p[:, 0] += EYE_C[0]
    p[:, 1] += EYE_C[1]
    return p


def point_in_poly(pt, poly):
    x, y = pt
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-30) + xi:
            inside = not inside
        j = i
    return inside


def face_uv(x, z):
    return 0.5 + x / FACE_SPAN, 0.5 + (z - FACE_Z0) / FACE_SPAN
