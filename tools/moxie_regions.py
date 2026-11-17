"""Outfit region masks for the single-texture Moxie (docs/WARDROBE.md "Looks on a textured body").

The shipping model has one `body` albedo, so wardrobe looks cannot recolour named materials. This
script classifies every texel of that albedo into an outfit zone from WHERE it is on the rest-pose
body (its triangle is rasterised in UV space with interpolated positions) and WHAT colour it is,
and writes two mask textures next to the model:

    assets/models/moxie_regions_a.png   R = top (crop top)  G = jacket shell  B = jacket lining / trim
    assets/models/moxie_regions_b.png   R = pants           G = pants graphic B = shoes
    assets/models/moxie_regions.json    per zone: mean linear colour and luminance of the painted source

The actor body shader recolours a zone as  tint * (luminance / zone luminance), which keeps the
painted folds, seams and cel shading. Run after the model or its albedo changes:

    python -I tools/moxie_regions.py [preview_dir]
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GLB = os.path.join(ROOT, "assets", "models", "moxie.glb")
ALBEDO = os.path.join(ROOT, "assets", "models", "moxie_body.png")
OUT = os.path.join(ROOT, "assets", "models")
SIZE = 1024
ZONES = ["top", "jacket", "jacket_lining", "pants", "pants_graphic", "shoes"]


def load_body():
    d = open(GLB, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    blob = d[20 + jl + 8:]

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        dt = {5126: "<f4", 5123: "<u2", 5125: "<u4", 5121: "u1"}[a["componentType"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        return np.frombuffer(blob, dtype=dt, count=a["count"] * n, offset=off).reshape(a["count"], n)

    for m in j["meshes"]:
        for p in m["primitives"]:
            if j["materials"][p["material"]]["name"] == "body":
                return (acc(p["attributes"]["POSITION"]).astype(np.float64),
                        acc(p["attributes"]["TEXCOORD_0"]).astype(np.float64),
                        acc(p["indices"]).reshape(-1, 3).astype(np.int64))
    raise SystemExit("no 'body' material in " + GLB)


def rasterise(pos, uv, tris):
    """Per-texel rest position (NaN where no triangle covers the texel)."""
    out = np.full((SIZE, SIZE, 3), np.nan)
    px = uv * SIZE - 0.5
    for t in tris:
        a, b, c = px[t[0]], px[t[1]], px[t[2]]
        x0 = max(int(np.floor(min(a[0], b[0], c[0]))) - 1, 0)
        x1 = min(int(np.ceil(max(a[0], b[0], c[0]))) + 1, SIZE - 1)
        y0 = max(int(np.floor(min(a[1], b[1], c[1]))) - 1, 0)
        y1 = min(int(np.ceil(max(a[1], b[1], c[1]))) + 1, SIZE - 1)
        if x1 < x0 or y1 < y0:
            continue
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-12:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        w0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
        w1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
        w2 = 1.0 - w0 - w1
        # Half a texel of slack so island borders are covered (linear filtering reads them).
        inside = (w0 >= -0.35) & (w1 >= -0.35) & (w2 >= -0.35)
        if not inside.any():
            continue
        w0c, w1c, w2c = np.clip(w0, 0, 1), np.clip(w1, 0, 1), np.clip(w2, 0, 1)
        s = w0c + w1c + w2c
        p = (w0c[..., None] * pos[t[0]] + w1c[..., None] * pos[t[1]] + w2c[..., None] * pos[t[2]]) / s[..., None]
        sub = out[y0:y1 + 1, x0:x1 + 1]
        sub[inside] = p[inside]
    return out


def hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r)
    gm = m & (mx == g) & ~rm
    bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6.0
    h[gm] = (b - r)[gm] / d[gm] + 2.0
    h[bm] = (r - g)[bm] / d[bm] + 4.0
    return h * 60.0, np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0), mx


def main():
    pos, uv, tris = load_body()
    p = rasterise(pos, uv, tris)
    covered = ~np.isnan(p[..., 0])
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    img = Image.open(ALBEDO).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    rgb = np.asarray(img).astype(np.float64) / 255.0
    h, s, v = hsv(rgb)
    ax = np.abs(np.nan_to_num(x))
    y = np.nan_to_num(y, nan=-1.0)
    z = np.nan_to_num(z)

    skin = (h > 8) & (h < 32) & (s > 0.25) & (s < 0.62) & (v > 0.72)
    yellow = (h > 36) & (h < 58) & (s > 0.6) & (v > 0.6)
    khaki = (h > 24) & (h < 62) & (s > 0.2) & (s < 0.72) & (v > 0.14) & (v < 0.74) & ~yellow
    white = (s < 0.24) & (v > 0.55)
    dark = (v < 0.45) & (s < 0.5)
    upper = (y > 0.95) | ((y > 0.84) & (z < -0.03))
    jacket_dom = upper & (ax < 0.5) & ((ax > 0.1) | (z < -0.03))

    zone = {
        "shoes": covered & (y < 0.235) & ~skin,
        "pants": covered & (y > 0.26) & (y < 0.95) & khaki,
        "pants_graphic": covered & (y > 0.28) & (y < 0.62) & yellow,
        "top": covered & (y > 0.98) & (y < 1.27) & (ax < 0.2) & (z > -0.09) & white,
        "jacket": covered & jacket_dom & dark,
        "jacket_lining": covered & jacket_dom & yellow,
    }
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    lum = lin @ np.array([0.2126, 0.7152, 0.0722])
    stats = {}
    masks = {}
    for name in ZONES:
        m = zone[name]
        n = int(m.sum())
        col = lin[m].mean(0) if n else np.zeros(3)
        stats[name] = {"texels": n, "color": [round(float(c), 4) for c in col], "lum": round(float(lum[m].mean()) if n else 0.0, 4)}
        im = Image.fromarray((m * 255).astype(np.uint8))
        # Close pin-holes, then bleed one texel outward so filtered island borders stay inside the zone.
        im = im.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
        masks[name] = im
    Image.merge("RGB", [masks["top"], masks["jacket"], masks["jacket_lining"]]).save(os.path.join(OUT, "moxie_regions_a.png"))
    Image.merge("RGB", [masks["pants"], masks["pants_graphic"], masks["shoes"]]).save(os.path.join(OUT, "moxie_regions_b.png"))
    json.dump({"about": "Outfit zones of assets/models/moxie_body.png (tools/moxie_regions.py). color / lum are linear.",
               "size": SIZE, "zones": stats}, open(os.path.join(OUT, "moxie_regions.json"), "w"), indent=1)
    print(json.dumps(stats, indent=1))
    if len(sys.argv) > 1:
        os.makedirs(sys.argv[1], exist_ok=True)
        tint = {"top": (255, 0, 0), "jacket": (0, 120, 255), "jacket_lining": (0, 255, 255), "pants": (0, 255, 0),
                "pants_graphic": (255, 0, 255), "shoes": (255, 128, 0)}
        prev = np.asarray(img).astype(np.float64)
        for name in ZONES:
            m = np.asarray(masks[name]) > 127
            prev[m] = prev[m] * 0.35 + np.array(tint[name]) * 0.65
        Image.fromarray(prev.astype(np.uint8)).save(os.path.join(sys.argv[1], "moxie_regions_preview.png"))


if __name__ == "__main__":
    main()
