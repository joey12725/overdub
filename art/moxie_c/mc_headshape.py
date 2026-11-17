"""The traced head: silhouette curves measured from the head model sheet (ref/head_bald_front_side.png,
see ref_measure.py) and an implicit surface built from them.

Units in the tables are head heights (H = crown -> chin). t runs down the head: 0 = crown, 1 = chin.
  W   half-width of the front silhouette (ears excluded, jaw continued under the neck to the chin point)
  YF  front of the profile WITHOUT the nose (forehead, bridge, lips, chin), measured back from the nose tip
  YB  back of the profile (skull, nape, then the back edge of the jaw under the ear down to the chin)
Each horizontal slice of the head is a pair of half super-ellipses (front / back) meeting at the
widest point YC, so the front and side silhouettes of the surface are exactly these curves.
Plain numpy: imported by the Blender builders and by the plain-Python painters / checkers.
"""
import numpy as np

H = 0.214            # head height in metres (old-space build size; the proportion pass rescales it)
ZTOP = 0.100         # head-local z of the crown
Y0 = -0.101          # head-local y of the nose tip (profile origin)

_W = [(0.098, 0.254), (0.122, 0.277), (0.147, 0.296), (0.171, 0.311), (0.196, 0.325), (0.220, 0.337),
      (0.244, 0.347), (0.269, 0.354), (0.293, 0.360), (0.318, 0.365), (0.342, 0.369), (0.367, 0.370),
      (0.440, 0.368), (0.489, 0.363), (0.520, 0.360), (0.567, 0.357), (0.610, 0.350), (0.665, 0.337),
      (0.714, 0.319), (0.763, 0.290), (0.812, 0.256), (0.860, 0.226), (0.910, 0.188), (0.945, 0.150),
      (0.965, 0.118), (0.982, 0.070), (1.000, 0.018)]
_YF = [(0.098, 0.207), (0.122, 0.178), (0.147, 0.151), (0.171, 0.131), (0.196, 0.112), (0.220, 0.097),
       (0.244, 0.082), (0.269, 0.070), (0.293, 0.060), (0.318, 0.050), (0.342, 0.043), (0.367, 0.036),
       (0.391, 0.033), (0.416, 0.031), (0.465, 0.031), (0.489, 0.036), (0.513, 0.041), (0.538, 0.050),
       (0.562, 0.063), (0.587, 0.075), (0.611, 0.085), (0.636, 0.087), (0.700, 0.070), (0.760, 0.052),
       (0.800, 0.046), (0.831, 0.048), (0.856, 0.064), (0.880, 0.072), (0.905, 0.086), (0.930, 0.095),
       (0.954, 0.099), (0.978, 0.107), (1.000, 0.135)]
_YB = [(0.098, 0.729), (0.122, 0.754), (0.147, 0.774), (0.171, 0.791), (0.196, 0.805), (0.220, 0.820),
       (0.244, 0.832), (0.269, 0.842), (0.293, 0.849), (0.318, 0.857), (0.342, 0.864), (0.367, 0.869),
       (0.416, 0.874), (0.465, 0.874), (0.513, 0.866), (0.562, 0.854), (0.611, 0.835), (0.660, 0.808),
       (0.709, 0.769), (0.758, 0.722), (0.800, 0.672), (0.830, 0.610), (0.860, 0.530), (0.900, 0.430),
       (0.940, 0.340), (0.970, 0.265), (1.000, 0.175)]
# depth of the widest point of each slice, and the super-ellipse exponent of the front half
_YC = [(0.0, 0.52), (0.45, 0.56), (0.62, 0.55), (0.72, 0.50), (0.80, 0.46), (0.90, 0.36), (1.0, 0.165)]
_PF = [(0.0, 2.0), (0.40, 2.0), (0.55, 1.95), (0.70, 1.85), (0.85, 1.80), (1.0, 1.9)]

N = 512
TT = np.linspace(0.0, 1.0, N)


def _curve(pts, top=None, smooth=9.0):
    """Dense table from control points. top=(a, apex): near the crown the curve follows
    apex + a*sqrt(t) (an ellipse cap), blended into the measured points by t = 0.11."""
    pts = np.asarray(pts, dtype=np.float64)
    v = np.interp(TT, pts[:, 0], pts[:, 1])
    if top is not None:
        a, apex = top
        cap = apex + a * np.sqrt(TT)
        k = np.clip((TT - 0.06) / 0.05, 0, 1)
        k = k * k * (3 - 2 * k)
        v = cap * (1 - k) + v * k
    if smooth:
        g = np.exp(-0.5 * (np.arange(-30, 31) / smooth) ** 2)
        g /= g.sum()
        pad = np.concatenate([np.full(30, v[0]), v, np.full(30, v[-1])])
        s = np.convolve(pad, g, mode='valid')
        keep = np.clip((TT - 0.0) / 0.03, 0, 1) * np.clip((1.0 - TT) / 0.03, 0, 1)
        v = v * (1 - keep) + s * keep
    return v


W_T = _curve(_W, top=(0.254 / np.sqrt(0.098), 0.0)) * H
YF_T = Y0 + _curve(_YF, top=(-(0.49 - 0.207) / np.sqrt(0.098), 0.49)) * H
YB_T = Y0 + _curve(_YB, top=((0.729 - 0.49) / np.sqrt(0.098), 0.49)) * H
YC_T = Y0 + _curve(_YC, smooth=6.0) * H
YC_T = np.clip(YC_T, YF_T + 0.25 * (YB_T - YF_T), YB_T - 0.12 * (YB_T - YF_T))
PF_T = _curve(_PF, smooth=6.0)
TMIN, TMAX = 0.006, 0.994


def P(xh, f, t):
    """Head-height units -> head-local metres: xh sideways, f back from the nose tip, t down from the crown."""
    return np.array([xh * H, Y0 + f * H, ZTOP - t * H], dtype=np.float64)


def z_of(t):
    return ZTOP - t * H


def _tab(tab, t):
    return np.interp(t, TT, tab)


def _rho(ax, y, t):
    w = _tab(W_T, t)
    yc = _tab(YC_T, t)
    dy = y - yc
    front = dy < 0
    d = np.where(front, yc - _tab(YF_T, t), _tab(YB_T, t) - yc)
    p = np.where(front, _tab(PF_T, t), 2.0)
    u = ax / w
    v = np.abs(dy) / d
    rho = (u ** p + v ** p + 1e-12) ** (1.0 / p)
    return rho, u, v, w, d, p


def shape_sdf(pts):
    """Approximate signed distance (metres) to the traced head, no nose / ears / neck / sockets."""
    ax = np.abs(pts[:, 0])
    y = pts[:, 1]
    t = (ZTOP - pts[:, 2]) / H
    tc = np.clip(t, TMIN, TMAX)
    rho, u, v, w, d, p = _rho(ax, y, tc)
    r1 = np.maximum(rho, 1e-4) ** (1.0 - p)
    gx = r1 * u ** (p - 1.0) / w
    gy = r1 * v ** (p - 1.0) / d
    e = 0.004
    gz = (_rho(ax, y, np.clip(tc + e, TMIN, TMAX))[0] - _rho(ax, y, np.clip(tc - e, TMIN, TMAX))[0]) / (2 * e * H)
    g = np.sqrt(gx * gx + gy * gy + gz * gz)
    dist = (rho - 1.0) / np.maximum(g, 1.0 / 0.11)
    dist = np.clip(dist, -0.06, 1.0)
    dist = dist + (np.clip(TMIN - t, 0, None) + np.clip(t - TMAX, 0, None)) * H
    # crown: the slices degenerate at the pole, so the top 8 % is an ellipsoid cap with the same
    # sqrt-law outline (fitted to the traced points at t = 0.05 .. 0.10)
    q = (pts - P(0, 0.475, 0.30)) / (np.array([0.314, 0.323, 0.300]) * H)
    k0 = np.linalg.norm(q, axis=1)
    k1 = np.linalg.norm(q / (np.array([0.314, 0.323, 0.300]) * H), axis=1)
    cap = k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    k = np.clip((t - 0.035) / 0.07, 0, 1)
    k = k * k * (3 - 2 * k)
    dist = cap * (1 - k) + dist * k
    return np.where(dist > 0.004, dist * 0.8, dist)


def surface_y(xh, t):
    """Head-local y of the traced front surface at sideways position xh (H units) and height t."""
    t = np.asarray(t, dtype=np.float64)
    w, yc, yf, p = _tab(W_T, t), _tab(YC_T, t), _tab(YF_T, t), _tab(PF_T, t)
    u = np.clip(np.abs(xh) * H / w, 0, 0.999)
    return yc - (yc - yf) * (1 - u ** p) ** (1.0 / p)
