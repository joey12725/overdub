"""
Build every decor prop: model, export to assets/models/kit/<name>.glb, render previews, and merge
the decor keys into assets/models/kit/manifest.json (other keys in the manifest are preserved).

  blender --background --python art/kit/build_decor.py -- [--only a,b] [--no-previews] [--no-export]

Previews go to art/previews/decor/<name>/{front,side,back,threequarter,iso,thumb_iso,sheet_cell}.png.
Contact sheets are composed afterwards by art/kit/decor_sheet.py (plain Python + Pillow).

Naming: pieces whose shape differs between the warm upper look and the dark lower look are built
twice as <name>__upper and <name>__lower; the rest are a single <name> (Godot re-tints by
material name per theme).
"""
from __future__ import annotations

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Matrix  # noqa: E402

import importlib  # noqa: E402

import decor_lib as L  # noqa: E402

KIT_DIR = os.path.join(L.ROOT, "assets", "models", "kit")
PREVIEW_DIR = os.path.join(L.ROOT, "art", "previews", "decor")
MANIFEST = os.path.join(KIT_DIR, "manifest.json")

UPPER_THEMES = ["upper", "mid"]
LOWER_THEMES = ["lower", "core"]
ALL_THEMES = ["upper", "mid", "lower", "core"]

# (piece name, look used for the base colours, themes, "module:builder")
PIECES = [
    ("vines", "upper", ALL_THEMES, "decor_nature:vines"),
    ("bush", "upper", ALL_THEMES, "decor_nature:bush"),
    ("rubble__upper", "upper", UPPER_THEMES, "decor_nature:rubble_upper"),
    ("rubble__lower", "lower", LOWER_THEMES, "decor_nature:rubble_lower"),
    ("crate__upper", "upper", UPPER_THEMES, "decor_containers:crate_upper"),
    ("crate__lower", "lower", LOWER_THEMES, "decor_containers:crate_lower"),
    ("barrel__upper", "upper", UPPER_THEMES, "decor_containers:barrel_upper"),
    ("barrel__lower", "lower", LOWER_THEMES, "decor_containers:barrel_lower"),
    ("chest__upper", "upper", UPPER_THEMES, "decor_containers:chest_upper"),
    ("chest__lower", "lower", LOWER_THEMES, "decor_containers:chest_lower"),
    ("pipe__upper", "upper", UPPER_THEMES, "decor_machines:pipe_upper"),
    ("pipe__lower", "lower", LOWER_THEMES, "decor_machines:pipe_lower"),
    ("console__upper", "upper", UPPER_THEMES, "decor_machines:console_upper"),
    ("console__lower", "lower", LOWER_THEMES, "decor_machines:console_lower"),
    ("generator__upper", "upper", UPPER_THEMES, "decor_machines:generator_upper"),
    ("generator__lower", "lower", LOWER_THEMES, "decor_machines:generator_lower"),
    ("vent__upper", "upper", UPPER_THEMES, "decor_machines:vent_upper"),
    ("vent__lower", "lower", LOWER_THEMES, "decor_machines:vent_lower"),
    ("lamp__upper", "upper", UPPER_THEMES, "decor_machines:lamp_upper"),
    ("lamp__lower", "lower", LOWER_THEMES, "decor_machines:lamp_lower"),
    ("neon", "lower", ALL_THEMES, "decor_machines:neon"),
    ("cable", "upper", ALL_THEMES, "decor_machines:cable"),
    ("wave_screen", "lower", ALL_THEMES, "decor_machines:wave_screen"),
    ("arch__upper", "upper", UPPER_THEMES, "decor_structures:arch_upper"),
    ("arch__lower", "lower", LOWER_THEMES, "decor_structures:arch_lower"),
    ("rune_panel", "lower", ALL_THEMES, "decor_structures:rune_panel"),
    ("time_machine", "core", ALL_THEMES, "decor_time_machine:time_machine"),
]

SHEET_SCALE = 3.0          # ortho scale of the fixed-scale sheet cells (tiles across)
SHEET_CENTRE = (0.0, 0.0, 0.85)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    previews = True
    export = True
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--only":
            only = set(argv[i + 1].split(","))
            i += 1
        elif a == "--no-previews":
            previews = False
        elif a == "--no-export":
            export = False
        i += 1
    return only, previews, export


def round3(v):
    return [round(float(x), 3) for x in v]


def tile_plate():
    """Preview-only 1x1 floor tile under a piece, to show its footprint."""
    L.set_look("upper")
    t = L.box((1.0, 1.0, 0.04), (0, 0, -0.02), mat="mortar", name="TilePreview")
    return t


def resolve(spec):
    mod, fn = spec.split(":")
    return getattr(importlib.import_module(mod), fn)


def build_one(name, look, builder, previews, export):
    L.clear_scene()
    L.set_look(look)
    objs = resolve(builder)()
    bpy.context.view_layer.update()
    # Contract: the origin is on the floor and nothing sinks below it. Lift the whole piece by any
    # small undershoot (stem radii, faceted rock undersides) so it sits exactly on Y = 0.
    lo, _ = L.bounds(objs)
    if lo.z < 0:
        for o in objs:
            if o.parent is not None:
                continue
            if o.name == "Body":
                o.data.transform(Matrix.Translation((0, 0, -lo.z)))
            else:
                o.location.z -= lo.z
        bpy.context.view_layer.update()
    names = [o.name for o in objs]
    lo, hi = L.bounds(objs)
    tris = sum(L.tri_count(o) for o in objs)
    if export:
        L.export_glb(os.path.join(KIT_DIR, f"{name}.glb"), objs)
    if previews:
        out = os.path.join(PREVIEW_DIR, name)
        L.render_standard_views(out, objs)
        plate = tile_plate()
        if name == "time_machine":
            L.render_view(os.path.join(out, "sheet_cell.png"), objs + [plate], *L.VIEWS["iso"], 480, 480,
                          ortho_scale=SHEET_SCALE * 1.6, centre=(0, 0, 1.4))
            L.render_view(os.path.join(PREVIEW_DIR, "time_machine_iso_close.png"), objs, *L.VIEWS["iso"],
                          1400, 1400, margin=1.06)
        else:
            L.render_view(os.path.join(out, "sheet_cell.png"), objs + [plate], *L.VIEWS["iso"], 480, 480,
                          ortho_scale=SHEET_SCALE, centre=SHEET_CENTRE)
    # Godot size: x = Blender x, y = Blender z (height), z = Blender y (depth).
    size = [hi.x - lo.x, hi.z - lo.z, hi.y - lo.y]
    return {"objects": names, "tris": tris, "size": size, "min": [lo.x, lo.z, -hi.y], "max": [hi.x, hi.z, -lo.y]}


# Notes written into the manifest for the world engineer (front = Godot +Z, as DecorDef rot 0).
NOTES = {
    "vines": {"placement": "wall-mounted: origin at the foot of the wall face (the wall is the plane z = 0 behind "
                           "the piece, i.e. -Z); hangs in +Z from a wall top at y = 1.5 and spills over it; scale Y "
                           "by wall_height / 1.5 to fit"},
    "chest": {"open": {"object": "Lid", "axis": "x", "angle_deg": -110},
              "placement": "Lid origin is on the hinge (top back edge); rotate it about local X, negative opens"},
    "console": {"placement": "Screen faces +Z with 0-1 UVs (u left->right, v top->bottom) for a drawn display"},
    "wave_screen": {"placement": "Screen faces +Z with clean 0-1 UVs (u left->right, v top->bottom); the game draws "
                                 "the waveform onto it"},
    "generator": {"spin": {"object": "Fan", "axis": "x"}},
    "vent": {"spin": {"object": "Fan", "axis": "z"}},
    "pipe": {"placement": "runs along X through the tile centre, rising out of the floor at x = +-0.4"},
    "arch": {"placement": "spans X (opening 1.0 wide, about 1.7 overall); rotate 90 deg for a Z-facing gate"},
    "time_machine": {"placement": "set piece: about 3 x 3 tiles centred on its tile, 3 tall",
                     "spin": [{"object": "Ring_Outer", "axis": "z"}, {"object": "Ring_Mid", "axis": "y"},
                              {"object": "Ring_Inner", "axis": "x"}, {"object": "Reel_L", "axis": "z"},
                              {"object": "Reel_R", "axis": "z"}, {"object": "Heart", "axis": "y"}]},
}


def _entry(name, themes, r):
    base = name.split("__")[0]
    e = {"file": f"{name}.glb", "themes": themes, "size": round3(r["size"]),
         "aabb": {"min": round3(r["min"]), "max": round3(r["max"])}}
    if len(r["objects"]) > 1:
        e["objects"] = r["objects"]
    e.update(NOTES.get(base, {}))
    return e


def merge_manifest(results):
    """Write this script's keys (and only those) into the shared manifest. Like the structural
    pieces, every decor name gets an unsuffixed key plus one key per theme
    (<name>__upper/__mid/__lower/__core), pointing at the file built for that look."""
    data = {"pieces": {}}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, "r", encoding="utf-8") as f:
            data = json.load(f)
        data.setdefault("pieces", {})
    pieces = data["pieces"]
    by_base = {}
    for name, look, themes, _ in PIECES:
        if name in results:
            by_base.setdefault(name.split("__")[0], []).append((name, themes))
    for base, variants in by_base.items():
        entries = {n: _entry(n, t, results[n]) for n, t in variants}
        if len(variants) == 1 and variants[0][0] == base:
            e = dict(entries[base])
            e["themes"] = ALL_THEMES
            for key in [base] + [f"{base}__{t}" for t in ALL_THEMES]:
                pieces[key] = dict(e)
            continue
        up = entries.get(f"{base}__upper")
        lo = entries.get(f"{base}__lower")
        if up:
            pieces[base] = dict(up)
            pieces[f"{base}__upper"] = dict(up)
            pieces[f"{base}__mid"] = dict(up)
        if lo:
            pieces[f"{base}__lower"] = dict(lo)
            pieces[f"{base}__core"] = dict(lo)
    data["pieces"] = {k: pieces[k] for k in sorted(pieces)}
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def main():
    only, previews, export = parse_args()
    results = {}
    report = []
    for name, look, themes, builder in PIECES:
        base = name.split("__")[0]
        if only and name not in only and base not in only:
            continue
        t0 = time.time()
        r = build_one(name, look, builder, previews, export)
        results[name] = r
        warn = "  BELOW FLOOR" if r["min"][1] < -0.004 else ""
        report.append(f"{name:20s} tris={r['tris']:6d} size={round3(r['size'])} miny={r['min'][1]:.3f}{warn} "
                      f"objects={r['objects']} "
                      f"({time.time() - t0:.1f}s)")
        print("[decor]", report[-1], flush=True)
    if export and results:
        merge_manifest(results)
    print("\n".join(["[decor] summary"] + report), flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
