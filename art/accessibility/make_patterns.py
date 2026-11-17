"""Generate the cassette identity textures into assets/textures/patterns/ and verify them.

    python -I art/accessibility/make_patterns.py

Patterns: four seamless 128 px tiles, one per cassette, as 8-bit greyscale coverage masks
(white = pattern, black = gap) so a shader or a CanvasItem can tint them with any colour:
    A stripes   45 degree diagonal bars
    B dots      staggered round dots
    C chevrons  horizontal zigzag rows
    D grid      square lattice (0 / 90 degree cross-hatch)
Every tile repeats 4 times across 128 px (32 px period) and covers exactly 40 % of its area, so a
pattern never changes how light a cassette colour looks, only its texture. Each is an analytic
periodic function rendered at 8x supersampling, which makes it seamless by construction; verify()
then proves it by rendering a 2x2 field directly and comparing it with the tiled single tile.

Shapes: one 128 px RGBA mask (white, alpha = coverage) per cassette, filled and as a ring:
    A circle, B triangle, C square, D plus.
The same outlines are in data/accessibility/patterns.json as unit polygons for code that draws
them directly (HUD _draw, floor ring meshes).
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "patterns")
SIZE = 128
SS = 8
REPEATS = 4
COVERAGE = 0.40

NAMES = ["stripes", "dots", "chevrons", "grid"]
LETTERS = ["a", "b", "c", "d"]
SHAPES = ["circle", "triangle", "square", "plus"]


def frac(x):
    return x - np.floor(x)


def coverage_fn(name):
    """Returns f(u, v) -> bool mask for tile coordinates u, v (periodic with period 1)."""
    n = REPEATS
    if name == "stripes":
        return lambda u, v: frac((u + v) * n) < COVERAGE
    if name == "dots":
        r = math.sqrt(COVERAGE / (2.0 * math.pi))  # two dots per cell

        def f(u, v):
            x, y = frac(u * n), frac(v * n)
            d1 = np.hypot(x - 0.25, y - 0.25)
            d2 = np.hypot(x - 0.75, y - 0.75)
            return (d1 < r) | (d2 < r)
        return f
    if name == "chevrons":
        def f(u, v):
            tri = np.abs(frac(u * n) - 0.5) * 2.0
            return frac(v * n - tri * 0.5) < COVERAGE
        return f
    if name == "grid":
        w = 1.0 - math.sqrt(1.0 - COVERAGE)
        return lambda u, v: (frac(u * n) < w) | (frac(v * n) < w)
    raise ValueError(name)


def render(name, tiles=1):
    """Coverage 0..1 over `tiles` x `tiles` tiles at SIZE px per tile (box-filtered supersampling)."""
    px = SIZE * tiles
    n = px * SS
    c = (np.arange(n) + 0.5) / (SIZE * SS)
    u, v = np.meshgrid(c, c)
    m = coverage_fn(name)(u, v).astype(np.float64)
    return m.reshape(px, SS, px, SS).mean(axis=(1, 3))


def to_u8(a):
    return np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)


def verify(name, tile):
    """Seamless (2x2 direct render == tiled tile), coverage on target, edges as smooth as the interior."""
    field = to_u8(render(name, 2))
    tiled = np.tile(to_u8(tile), (2, 2))
    wrap_err = int(np.abs(field.astype(int) - tiled.astype(int)).max())
    t = tile
    # Step across the wrap seam vs the largest step between interior neighbours.
    seam_x = float(np.abs(t[:, 0] - t[:, -1]).mean())
    seam_y = float(np.abs(t[0, :] - t[-1, :]).mean())
    inner_x = float(np.abs(np.diff(t, axis=1)).mean(axis=0).max())
    inner_y = float(np.abs(np.diff(t, axis=0)).mean(axis=1).max())
    cov = float(t.mean())
    ok = wrap_err <= 1 and abs(cov - COVERAGE) < 0.01 and seam_x <= inner_x + 1e-9 and seam_y <= inner_y + 1e-9
    return {"pattern": name, "wrap_max_abs_diff_u8": wrap_err, "coverage": round(cov, 4),
            "seam_step_x": round(seam_x, 4), "max_interior_step_x": round(inner_x, 4),
            "seam_step_y": round(seam_y, 4), "max_interior_step_y": round(inner_y, 4), "ok": bool(ok)}


# ───────────────────────────── shapes ─────────────────────────────

def shape_polygon(name):
    """Unit outline, x right / y down, fitted in the [-1, 1] box with equal visual weight."""
    if name == "circle":
        return [[round(0.92 * math.cos(2 * math.pi * k / 48), 4), round(0.92 * math.sin(2 * math.pi * k / 48), 4)] for k in range(48)]
    if name == "triangle":
        # Point up; centred on its centroid, slightly larger so its area matches the others.
        return [[0.0, -1.0], [1.0, 0.74], [-1.0, 0.74]]
    if name == "square":
        return [[-0.82, -0.82], [0.82, -0.82], [0.82, 0.82], [-0.82, 0.82]]
    if name == "plus":
        a, b = 1.0, 0.36
        return [[-b, -a], [b, -a], [b, -b], [a, -b], [a, b], [b, b], [b, a], [-b, a], [-b, b], [-a, b], [-a, -b], [-b, -b]]
    raise ValueError(name)


def inside(poly, x, y):
    """Vectorised even-odd point-in-polygon."""
    res = np.zeros(x.shape, dtype=bool)
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        cond = (y0 > y) != (y1 > y)
        with np.errstate(divide="ignore", invalid="ignore"):
            xi = (x1 - x0) * (y - y0) / (y1 - y0 + 1e-30) + x0
        res ^= cond & (x < xi)
    return res


def render_shape(name, ring):
    n = SIZE * SS
    c = ((np.arange(n) + 0.5) / n * 2.0 - 1.0) / 0.9  # 10 % margin
    x, y = np.meshgrid(c, c)
    poly = shape_polygon(name)
    m = inside(poly, x, y)
    if ring:
        inner = [[px * 0.62, py * 0.62] for px, py in poly]
        if name == "triangle":
            # Scale about the centroid so the band is even.
            cy = sum(p[1] for p in poly) / 3.0
            inner = [[px * 0.5, cy + (py - cy) * 0.5] for px, py in poly]
        if name == "plus":
            a, b = 0.72, 0.13
            inner = [[-b, -a], [b, -a], [b, -b], [a, -b], [a, b], [b, b], [b, a], [-b, a], [-b, b], [-a, b], [-a, -b], [-b, -b]]
        m = m & ~inside(inner, x, y)
    return m.astype(np.float64).reshape(SIZE, SS, SIZE, SS).mean(axis=(1, 3))


def main():
    os.makedirs(OUT, exist_ok=True)
    report = []
    tiles = []
    for i, name in enumerate(NAMES):
        t = render(name)
        tiles.append(t)
        Image.fromarray(to_u8(t), "L").save(os.path.join(OUT, "pattern_%s_%s.png" % (LETTERS[i], name)))
        r = verify(name, t)
        report.append(r)
        print(r)
    # One 512x128 strip, A..D left to right, for a Texture2DArray import (4 horizontal slices).
    Image.fromarray(to_u8(np.concatenate(tiles, axis=1)), "L").save(os.path.join(OUT, "pattern_strip_abcd.png"))
    for i, name in enumerate(SHAPES):
        for ring in (False, True):
            a = to_u8(render_shape(name, ring))
            rgba = np.dstack([np.full_like(a, 255)] * 3 + [a])
            Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "shape_%s_%s%s.png" % (LETTERS[i], name, "_ring" if ring else "")))
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    json.dump({"size": SIZE, "supersample": SS, "repeats_per_tile": REPEATS, "coverage_target": COVERAGE, "patterns": report},
              open(os.path.join(HERE, "out", "pattern_check.json"), "w"), indent=1)
    assert all(r["ok"] for r in report), "pattern verification failed"
    print("all patterns seamless")


if __name__ == "__main__":
    main()
