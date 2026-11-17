"""
Writes data/wardrobe.json from art/wardrobe/spec.py plus what is actually on disk (the headgear
glbs are measured, textures and concept sheets are only referenced when they exist), and copies
half-size concept sheets to assets/textures/wardrobe/concepts/ (docs/ is not visible to Godot).

    python -I art/wardrobe/build_data.py
"""
import json
import os
import struct
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import spec  # noqa: E402

MODELS = "assets/models/wardrobe"
TEX = "assets/textures/wardrobe"
CONCEPTS = "docs/reference/generated/wardrobe"


def glb_info(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    tris = 0
    lo, hi = [1e9] * 3, [-1e9] * 3
    for m in j["meshes"]:
        for pr in m["primitives"]:
            acc = j["accessors"][pr["attributes"]["POSITION"]]
            for i in range(3):
                lo[i] = min(lo[i], acc["min"][i])
                hi[i] = max(hi[i], acc["max"][i])
            tris += j["accessors"][pr["indices"]]["count"] // 3
    mats = {}
    for m in j.get("materials", []):
        c = m.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
        mats[m["name"]] = lin_hex(c)
    return tris, [round(v, 3) for v in lo], [round(v, 3) for v in hi], mats


def lin_hex(c):
    f = lambda x: round(255 * (x * 12.92 if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055))
    return "#%02x%02x%02x" % tuple(max(0, min(255, f(x))) for x in c[:3])


def rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def shade(h, k):
    """Darker (k < 1) trim for a light base, lighter for a very dark one."""
    r, g, b = rgb(h)
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    if lum < 60:
        r, g, b = [min(255, int(v + (255 - v) * 0.22)) for v in (r, g, b)]
    else:
        r, g, b = [int(v * k) for v in (r, g, b)]
    return "#%02x%02x%02x" % (r, g, b)


def exists(rel):
    return os.path.exists(os.path.join(ROOT, rel))


def concept(ident):
    src = "%s/%s.png" % (CONCEPTS, ident)
    if not exists(src):
        return None, None
    dst = "%s/concepts/%s.png" % (TEX, ident)
    os.makedirs(os.path.join(ROOT, TEX, "concepts"), exist_ok=True)
    im = Image.open(os.path.join(ROOT, src)).convert("RGB")
    im = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
    im.save(os.path.join(ROOT, dst), optimize=True)
    return "res://" + dst, src


def main():
    items = {}
    missing = []
    for ident, h in spec.HEADGEAR.items():
        glb = "%s/%s.glb" % (MODELS, ident)
        e = {"slot": "helmet", "name": h["name"], "variant": h["variant"]}
        c, src = concept(ident)
        if c:
            e["concept"], e["concept_source"] = c, src
        else:
            missing.append("concept " + ident)
        if exists(glb):
            tris, lo, hi, mats = glb_info(os.path.join(ROOT, glb))
            glow = [v for k, v in mats.items() if k.endswith("_glow")]
            e["palette"] = {"base": mats.get("helmet", h["color"]), "trim": mats.get("helmet_trim", mats.get("helmet_dark", "#2c2729")),
                            "accent": glow[0] if glow else mats.get("helmet_accent", spec.YELLOW)}
            e["attach"] = {"model": "res://" + glb, "bone": "Head", "anchor": h["anchor"], "offset": [0, 0, 0], "scale": 1.0,
                           "triangles": tris, "bounds": {"min": lo, "max": hi}, "materials": mats}
        else:
            missing.append("model " + ident)
        items[ident] = e
    for ident, k in spec.LOOKS.items():
        slot = k["slot"]
        colors = dict(k["colors"])
        main_key = {"top": "jacket", "pants": "pants", "shoes": "shoes"}[slot]
        for region in ({"top": ["jacket"], "pants": ["pants"], "shoes": ["shoes"]}[slot]):
            colors.setdefault(region + "_trim", shade(colors[region], 0.62))
        if slot == "top":
            pal = {"base": colors["jacket"], "trim": colors["top"], "accent": colors["jacket_lining"]}
        elif slot == "pants":
            pal = {"base": colors["pants"], "trim": colors["pants_trim"], "accent": colors["pants_graphic"]}
        else:
            pal = {"base": colors["shoes"], "trim": colors["shoes_sole"], "accent": colors["shoes_lace"]}
        look = {"colors": colors}
        p = k.get("pattern")
        if p:
            tex = "%s/pattern_%s.png" % (TEX, p["id"])
            if exists(tex):
                look["pattern"] = {"id": p["id"], "texture": "res://" + tex, "region": p["region"], "color": p["color"],
                                   "strength": p["strength"], "scale": p["scale"]}
            else:
                missing.append("pattern %s (%s)" % (p["id"], ident))
        ds = []
        for d in k.get("decals", []):
            tex = "%s/decal_%s.png" % (TEX, d["id"])
            if exists(tex):
                ds.append({"id": d["id"], "texture": "res://" + tex, "place": d["place"], "color": d["color"], "opacity": d["opacity"]})
            else:
                missing.append("decal %s (%s)" % (d["id"], ident))
        if ds:
            look["decals"] = ds
        e = {"slot": slot, "name": k["name"], "palette": pal, "main_material": main_key, "look": look}
        c, src = concept(ident)
        if c:
            e["concept"], e["concept_source"] = c, src
        else:
            missing.append("concept " + ident)
        items[ident] = e

    mixes = {}
    for mid, ids in spec.MIXES.items():
        m = {"items": ids}
        c, src = concept(mid)
        if c:
            m["concept"], m["concept_source"] = c, src
        else:
            missing.append("mix " + mid)
        mixes[mid] = m

    data = {
        "version": 1,
        "about": "Generated by art/wardrobe/build_data.py from art/wardrobe/spec.py - edit the spec, not this file. See docs/WARDROBE.md.",
        "regions": {"top": ["top", "jacket"], "pants": ["pants"], "shoes": ["shoes"]},
        "aliases": {
            "laces": "shoes_lace", "shoes_laces": "shoes_lace", "lace": "shoes_lace", "sole": "shoes_sole",
            "pants_zig": "pants_graphic", "crop_top": "top", "shirt": "top", "bomber": "jacket",
            "lining": "jacket_lining", "cargo": "pants", "boots": "shoes",
            "top_light": "top", "jacket_dark": "jacket", "pants_olive": "pants", "shoes_main": "shoes",
            "shoes_accent": "shoes_lace",
        },
        "suffix_roles": {
            "trim": "trim", "rib": "trim", "ribbing": "trim", "dark": "trim", "cuff": "trim", "cuffs": "trim",
            "hem": "trim", "collar": "trim", "pocket": "trim", "pockets": "trim", "seam": "trim", "tongue": "trim",
            "graphic": "graphic", "zig": "graphic", "stripe": "graphic", "print": "graphic", "accent": "graphic",
            "lining": "lining", "inner": "lining", "sole": "sole", "lace": "lace", "laces": "lace",
        },
        "head_fit": {
            "about": "Headgear is authored around the Head bone joint of the reference head, +Y up, +Z front. 'models' pins an explicit fit per model path; otherwise the fit is measured from the model's headphones (materials named headphones*/phones*/hp_*), else from its head skin, else the reference fit is used unchanged.",
            "auto": True,
            "headphone_prefixes": ["headphones", "phones", "hp_"],
            "reference_model": "res://" + spec.HEAD["model"],
            "reference_head_bone": list(spec.HEAD["bone"]),
            "reference_skull": {"center": list(spec.HEAD["skull_c"]), "radii": list(spec.HEAD["skull_r"])},
            "reference_hair": {"brow": spec.HEAD["hair"], "crown": spec.HEAD["hair"] + spec.HEAD["hair_top"]},
            "reference_hair_front": spec.HEAD["hair_front"],
            "reference_headphones": {"min": list(spec.HEAD["headphones_min"]), "max": list(spec.HEAD["headphones_max"])},
            "reference_cup": {"center": list(spec.HEAD["cup_c"]), "radius": spec.HEAD["cup_r"]},
            "reference_skin": {"width": spec.HEAD["skin_width"], "top": spec.HEAD["skin_top"]},
            "skin_prefixes": ["skin"],
            "models": {},
        },
        "decal_places": {
            "jacket_back": {
                "about": "Fallback card centre relative to the first bone found, character axes. With the model's meshes passed to Wardrobe.attach_decals the card is placed on the measured back of the jacket instead.",
                "bones": {"UpperChest": [0.0, -0.075, -0.175], "Chest": [0.0, 0.03, -0.19], "chest": [0.0, -0.005, -0.158]},
                "normal": [0, 0, -1], "size": 0.24,
            },
        },
        "items": items,
        "mixes": mixes,
    }
    out = os.path.join(ROOT, "data", "wardrobe.json")
    with open(out, "w", encoding="utf8", newline="\n") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("wrote data/wardrobe.json: %d items" % len(items))
    for m in missing:
        print("  MISSING", m)


if __name__ == "__main__":
    main()
