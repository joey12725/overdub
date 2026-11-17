"""Colour science helpers for the OVERDUB accessibility analysis (numpy only).

sRGB <-> linear <-> CIELAB (D65), CIEDE2000, WCAG relative luminance / contrast ratio and
dichromat simulation (Machado, Oliveira & Fernandes 2009, severity 1.0, applied in linear RGB).
All functions take float arrays of shape (..., 3) with sRGB in 0..1 unless stated.
"""
import numpy as np

VISIONS = ("normal", "protanopia", "deuteranopia", "tritanopia")

_CVD = {
    "protanopia": np.array([[0.152286, 1.052583, -0.204868],
                            [0.114503, 0.786281, 0.099216],
                            [-0.003882, -0.048116, 1.051998]]),
    "deuteranopia": np.array([[0.367322, 0.860646, -0.227968],
                              [0.280085, 0.672501, 0.047413],
                              [-0.011820, 0.042940, 0.968881]]),
    "tritanopia": np.array([[1.255528, -0.076749, -0.178779],
                            [-0.078411, 0.930809, 0.147602],
                            [0.004733, 0.691367, 0.303900]]),
}

_M_RGB2XYZ = np.array([[0.4124564, 0.3575761, 0.1804375],
                       [0.2126729, 0.7151522, 0.0721750],
                       [0.0193339, 0.1191920, 0.9503041]])
_WHITE = np.array([0.95047, 1.0, 1.08883])


def hex_to_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=float) / 255.0


def rgb_to_hex(rgb):
    v = np.clip(np.round(np.asarray(rgb) * 255.0), 0, 255).astype(int)
    return "#%02x%02x%02x" % (v[0], v[1], v[2])


def to_linear(c):
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(l):
    l = np.clip(np.asarray(l, dtype=float), 0.0, 1.0)
    return np.where(l <= 0.0031308, l * 12.92, 1.055 * l ** (1 / 2.4) - 0.055)


def simulate(rgb, vision):
    """sRGB -> sRGB as seen with `vision` (one of VISIONS)."""
    if vision == "normal":
        return np.asarray(rgb, dtype=float)
    lin = to_linear(rgb)
    out = lin @ _CVD[vision].T
    return to_srgb(out)


def rgb_to_lab(rgb):
    xyz = to_linear(rgb) @ _M_RGB2XYZ.T / _WHITE
    e, k = 216 / 24389, 24389 / 27
    f = np.where(xyz > e, np.cbrt(xyz), (k * xyz + 16) / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], axis=-1)


def ciede2000(lab1, lab2):
    L1, a1, b1 = lab1[..., 0], lab1[..., 1], lab1[..., 2]
    L2, a2, b2 = lab2[..., 0], lab2[..., 1], lab2[..., 2]
    C1 = np.hypot(a1, b1)
    C2 = np.hypot(a2, b2)
    Cm = (C1 + C2) / 2
    G = 0.5 * (1 - np.sqrt(Cm ** 7 / (Cm ** 7 + 25.0 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = np.hypot(a1p, b1), np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360
    dLp = L2 - L1
    dCp = C2p - C1p
    dh = h2p - h1p
    dh = np.where(dh > 180, dh - 360, dh)
    dh = np.where(dh < -180, dh + 360, dh)
    dh = np.where(C1p * C2p == 0, 0.0, dh)
    dHp = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dh) / 2)
    Lm = (L1 + L2) / 2
    Cmp = (C1p + C2p) / 2
    hsum = h1p + h2p
    hm = np.where(np.abs(h1p - h2p) > 180, np.where(hsum < 360, hsum + 360, hsum - 360), hsum) / 2
    hm = np.where(C1p * C2p == 0, hsum, hm)
    T = (1 - 0.17 * np.cos(np.radians(hm - 30)) + 0.24 * np.cos(np.radians(2 * hm))
         + 0.32 * np.cos(np.radians(3 * hm + 6)) - 0.20 * np.cos(np.radians(4 * hm - 63)))
    dth = 30 * np.exp(-(((hm - 275) / 25) ** 2))
    Rc = 2 * np.sqrt(Cmp ** 7 / (Cmp ** 7 + 25.0 ** 7))
    Sl = 1 + 0.015 * (Lm - 50) ** 2 / np.sqrt(20 + (Lm - 50) ** 2)
    Sc = 1 + 0.045 * Cmp
    Sh = 1 + 0.015 * Cmp * T
    Rt = -np.sin(np.radians(2 * dth)) * Rc
    return np.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2 + Rt * (dCp / Sc) * (dHp / Sh))


def delta_e(rgb1, rgb2, vision="normal"):
    return ciede2000(rgb_to_lab(simulate(rgb1, vision)), rgb_to_lab(simulate(rgb2, vision)))


def luminance(rgb):
    return to_linear(rgb) @ np.array([0.2126, 0.7152, 0.0722])


def contrast(rgb1, rgb2):
    a, b = luminance(rgb1), luminance(rgb2)
    hi, lo = np.maximum(a, b), np.minimum(a, b)
    return (hi + 0.05) / (lo + 0.05)


def hsv_to_rgb(h, s, v):
    h = (h % 360) / 60.0
    i = int(h) % 6
    f = h - int(h)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    return np.array([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i])


def self_test():
    # Sharma, Wu & Dalal (2005) reference pairs.
    cases = [((50, 2.6772, -79.7751), (50, 0, -82.7485), 2.0425),
             ((50, 2.5, 0), (73, 25, -18), 27.1492),
             ((50, 2.5, 0), (50, 0, -2.5), 4.3065),
             ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387), 1.2644),
             ((22.7233, 20.0904, -46.6940), (23.0331, 14.9730, -42.5619), 2.0373),
             ((90.8027, -2.0831, 1.4410), (91.1528, -1.6435, 0.0447), 1.4441)]
    for a, b, want in cases:
        got = float(ciede2000(np.array(a, float), np.array(b, float)))
        assert abs(got - want) < 2e-4, (a, b, got, want)
    lab = rgb_to_lab(hex_to_rgb("#ffffff"))
    assert abs(lab[0] - 100) < 1e-3 and abs(lab[1]) < 1e-2 and abs(lab[2]) < 1e-2
    assert abs(float(contrast(hex_to_rgb("#000000"), hex_to_rgb("#ffffff"))) - 21.0) < 1e-6
    # Greys stay grey under every simulation (rows of each matrix sum to ~1).
    for v in VISIONS[1:]:
        g = simulate(np.array([0.5, 0.5, 0.5]), v)
        assert np.abs(g - 0.5).max() < 0.01, (v, g)
    return True


if __name__ == "__main__":
    print("self-test ok:", self_test())
