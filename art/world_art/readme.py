"""Writes assets/textures/README.md from what is on disk (every world-art texture with its intended use).
Run:  python -I art/world_art/readme.py   (after process.py)"""
import glob, json, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import jobs  # noqa: E402  (the prompt list; LEVEL_TAGS maps file name -> the level's variant text)

TEX = os.path.join(ROOT, "assets", "textures")


def norm(s):
    return "".join(c for c in s.lower() if c.isalnum())


# graffiti variants the levels ask for
variants = {}
for p in glob.glob(os.path.join(ROOT, "data", "levels", "*.json")):
    def walk(o, lvl=os.path.basename(p)[:2]):
        if isinstance(o, dict):
            if o.get("type") == "graffiti" and o.get("variant"):
                variants.setdefault(o["variant"], set()).add(lvl)
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    with open(p, encoding="utf8") as f:
        walk(json.load(f))
by_norm = {norm(v): (v, sorted(l)) for v, l in variants.items()}
LEVEL = {f: w for f, w, c, e in jobs.LEVEL_TAGS}

G = {
    "mox": "Moxie's signature tag (R03/R04)", "rec": "tag with record dot", "loop": "tag with loop arrow", "dub": "bubble tag",
    "take_4": "tag, circled 4", "side_b": "tag", "rewind": "tag with rewind triangles", "hiss": "tag with static squiggle",
    "5678": "count-in tag 5-6-7-8!", "overdub": "title tag with crown", "play": "tag with play triangle",
    "loud": "tag with shout lines", "again": "scrawl AGAIN!", "no_skips": "scrawl", "moxie_was_here": "scrawl, two lines",
    "smiley": "the X-eyed smiley (R03/R04), pink", "smiley_violet": "X-eyed smiley, tongue out, violet",
    "star": "scribble star, pink", "star_yellow": "scribble star with small stars, yellow", "cassette": "cassette",
    "reel": "tape reel unspooling", "arrow": "arrow pointing right (rotate the decal to aim it)",
    "arrow_down": "arrow pointing down with chevrons", "crown": "crowned headphones, yellow",
    "headphones": "headphones with cable", "warning": "hand-drawn warning triangle", "bolt": "lightning bolt",
    "skull": "skull in headphones", "heart": "dripping heart", "ghost": "ghost with echo outline (ghost takes)",
    "boombox": "boombox", "wave": "audio waveform", "tally": "tally of five (counting takes)",
    "x": "circled X (marks a spot)", "splat": "plain paint burst, no drawing (filler, layering)",
}
D = {
    "hazard_stripe": "yellow/black hazard band, edge to edge horizontally (platform lips, door sills)",
    "hazard_chevrons": "row of five chevrons pointing right (conveyors, movers, direction of travel)",
    "lane_arrow": "straight lane arrow, points up; rotate the decal", "lane_arrow_turn": "lane arrow turning right",
    "bay_01": "numbered bay marking", "bay_02": "numbered bay marking", "bay_03": "numbered bay marking",
    "bay_04": "numbered bay marking",
    "bay_a": "tape bay ring A, WHITE: tint #ff4d6d", "bay_b": "tape bay ring B, WHITE: tint #ffd23f",
    "bay_c": "tape bay ring C, WHITE: tint #3ec5ff", "bay_d": "tape bay ring D, WHITE: tint #7dff6b",
    "worn_paint_yellow": "worn-away yellow paint patch (ageing over any floor)",
    "worn_line": "worn off-white boundary line, edge to edge",
    "exit": "EXIT stencil with arrow, signal green (exit pad approach)",
    "do_not_stand": "no-standing stencil for trap tiles (crossed boots, no lettering)",
    "keep_clear": "KEEP CLEAR trap stencil (crushers, laser lanes)",
    "moss_a": "moss clump overlay (upper / mid floors and wall bases)", "moss_b": "moss along a seam, horizontal",
    "leaves": "scatter of fallen leaves", "crack_a": "branching crack, dark ink lines",
    "crack_b": "impact crack, spiderweb", "scorch_a": "round blast scorch (soft alpha)",
    "scorch_b": "long burn streak (laser drag)",
}
R = {
    "rune_glyphs_atlas": "the forty glyphs, 8 x 5 cells of 128 px (glyph i = column i % 8, row i // 8); see rune_glyphs_atlas.json",
    "rune_ring": "sixteen glyphs round a double ring (floor seal, exit pad, core floor)",
    "rune_strip_h_01": "eight glyphs between rails, horizontal (wall bands, console fascias)",
    "rune_strip_h_02": "as above, different text", "rune_strip_h_03": "as above, different text",
    "rune_strip_v_01": "eight glyphs between rails, vertical (pillars, door jambs)",
    "rune_strip_v_02": "as above, different text",
}
T = {
    "jcard_a": "J-card cover with Moxie, tape A #ff4d6d", "jcard_b": "J-card cover with Moxie, tape B #ffd23f",
    "jcard_c": "J-card cover with Moxie, tape C #3ec5ff", "jcard_d": "J-card cover with Moxie, tape D #7dff6b",
    "label_a": "cassette shell label A (the window cut-out is transparent)", "label_b": "cassette shell label B",
    "label_c": "cassette shell label C", "label_d": "cassette shell label D",
}
S = {
    "rec": "REC with record dot (recording state)", "take": "TAKE (put the take number beside it in the HUD font)",
    "commit": "COMMIT with tick", "retry": "RETRY with loop arrow", "clang": "CLANG! impact burst (parry / block effect)",
    "desync": "DESYNC, glitch-split", "resync": "RESYNC with lock-in ticks", "wipe": "WIPE with smear (erase a take)",
    "5678": "5 6 7 8 count-in in the four tape colours",
}
B = {
    "upper": "theme `upper` (levels 01-04): golden sky through broken vaults, distant overgrown ruins",
    "mid": "theme `mid` (levels 05-07): machine well, light shafts into teal-violet gloom",
    "lower": "theme `lower` (levels 08-11): near-black depths, faint distant neon and runes",
    "core": "theme `core` (level 12): the time-machine chamber, soft violet core glow",
}


def rows(sub, uses, extra=None):
    out = ["| file | size | use |", "|---|---|---|"]
    for p in sorted(glob.glob(os.path.join(TEX, sub, "*.png"))):
        n = os.path.splitext(os.path.basename(p))[0]
        im = Image.open(p)
        use = uses.get(n) or (extra(n) if extra else None)
        if use is None:
            raise SystemExit("no README entry for %s/%s" % (sub, n))
        out.append("| `%s/%s.png` | %dx%d %s | %s |" % (sub, n, im.width, im.height,
                                                      "alpha" if im.mode == "RGBA" else "opaque", use))
    return "\n".join(out), len(out) - 2


def level_use(n):
    if n not in LEVEL:
        return None
    v, lv = by_norm.get(norm(n), (LEVEL[n], []))
    return "level tag, variant `%s`%s" % (v, (" (level " + ", ".join(lv) + ")") if lv else "")


g_uses = {k: v + ((" - also level variant `%s`" % by_norm[norm(k)][0]) if norm(k) in by_norm else "") for k, v in G.items()}
g, ng = rows("graffiti", g_uses, level_use)
d, nd = rows("decals", D)
r, nr = rows("decals/runes", R)
t, nt = rows("tape", T)
s, ns = rows("tape/stickers", S)
b, nb = rows("backdrops", B)
have = {norm(os.path.splitext(os.path.basename(p))[0]) for p in glob.glob(os.path.join(TEX, "graffiti", "*.png"))}
unpainted = sorted(v for v in variants if norm(v) not in have)
unp = ", ".join("`%s`" % v for v in unpainted) or "none"

md = f"""# assets/textures - world art

Painted 2D art the 3D kit cannot give: graffiti, floor decals and signage, rune glyphs, background plates and tape art.
This file covers `graffiti/`, `decals/`, `backdrops/` and `tape/` (`patterns/` and `wardrobe/` belong to other owners).
It is written by `art/world_art/readme.py`; do not edit it by hand.

Source of record: `art/world_art/jobs.py` holds every prompt (model gpt-image-2.6-sunburst through `tools/img`);
`art/world_art/process.py` trims, pads, checks alpha, exports, and builds the contact sheets in `art/world_art/contact/`
(each set on warm stone and on dark metal). Raw model output is in `art/world_art/raw/`, rejected takes in
`raw/_rejected/`. To add or redo a piece: add or change its job, delete its raw file, then run
`python -I art/world_art/jobs.py <name>`, then `process.py`, then `readme.py`.

Conventions for everything with alpha: straight (not premultiplied) alpha, the subject trimmed and centred on a fixed
canvas with a clear margin, and the colour of fully transparent pixels bled outward from the paint so filtering and
mipmaps do not pull in a fringe. Import with mipmaps on and repeat off.

## graffiti/ ({ng} pieces, 768x768, alpha)

Spray paint on transparent. Project with a `Decal` using albedo only, so it takes the surface's cel lighting (ART-03:
it is paint, not light - do not make it emissive). `world/world_graffiti.gd` already finds these: a decor's `variant`
is lower-cased and stripped to letters and digits, and a file whose name matches the same way replaces the procedural
tag (`"ROLL TAPE"` -> `roll_tape.png`, `"+1"` -> `1.png`, `"3/4"` -> `34.png`, `"A/B"` -> `ab.png`,
`"5 6 7 8"` -> `5678.png`). An empty variant picks any file here from the seed. A piece does not fill its square:
wide tags sit in a horizontal band, so size the decal by its width.

Level variants with no painted file (they fall back to the procedural tag): {unp}.

{g}

## decals/ ({nd} pieces, alpha)

Floor markings and overlays for the ruins' technology, drawn straight top-down. Square pieces are 512x512, wide pieces
1024x512, bands 1024x256. The two bands run off the left and right edges so they can be butted end to end; they are not
seamless tiles, so overlap them or alternate flips. Coloured pieces are final colour; the bay rings A-D are white so
the game tints them with the tape colour. Moss, leaves and cracks suit the upper and mid themes; scorches go anywhere.

{d}

## decals/runes/ ({nr} sheets, plus 40 single glyphs)

An invented angular alphabet, pure white on transparent with the shape in alpha: tint with the albedo / modulate colour
and drive emission from the same texture to make it glow (cyan, magenta or violet in the lower themes; a dark carved
tint or yellow paint in the upper ones). `glyphs/rune_00.png` to `rune_39.png` are the forty glyphs, one per 128x128
file, in atlas order; `process.py` checks that no two overlap by more than 72 percent, mirrored or not.
`musicviz/mv_glyphs.gd` falls back to procedural glyphs when no sheet is found here.

{r}

## backdrops/ ({nb} plates, 1536x1024, opaque)

One soft, low-contrast plate per depth theme. `world/world_view.gd` loads `backdrops/<theme>.png` behind the diorama
by itself. The centre is kept calm and detail sits at the edges. `art/world_art/contact/backdrop_test_<theme>.png`
shows each one behind a kit diorama.

{b}

## tape/ ({nt} pieces) and tape/stickers/ ({ns} pieces)

J-cards are 1024x1536 opaque covers for the four tapes (tape select, pause and results screens, the tape rack). Labels
are 1024x640 with alpha, to sit on a cassette shell in the HUD. Stickers are 1024x512 with alpha, die-cut with a white
border, for HUD states and hit / sync effects (pop them in with a little rotation and scale).

{t}

{s}
"""
with open(os.path.join(TEX, "README.md"), "w", encoding="utf8", newline="\n") as f:
    f.write(md)
print("README written:", ng, nd, nr, nt, ns, nb, "| unpainted level variants:", unpainted)
