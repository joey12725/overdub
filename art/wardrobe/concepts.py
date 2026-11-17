"""
Concept sheets, pattern sources, decal sources and outfit mixes for the wardrobe (image model,
reference-guided by Moxie's approved art).

    python -I art/wardrobe/concepts.py [kind ...] [id ...]      kinds: items patterns decals mixes
    FORCE=1 regenerates files that already exist.  Two requests run at a time (tools/img limit).

Outputs
    docs/reference/generated/wardrobe/<item id>.png        one sheet per item, Moxie wearing it
    docs/reference/generated/wardrobe/mix_*.png            full-outfit mixes (identity check)
    art/wardrobe/src/pattern_<id>.png, decal_<id>.png      raw image-model output; textures.py turns
                                                           them into the shipped 512 px textures
"""
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import spec  # noqa: E402

OUT = "docs/reference/generated/wardrobe"
SRC = "art/wardrobe/src"
REFS = ["docs/reference/R01-moxie-concept.png", "docs/reference/R02-moxie-sheet.png"]
# Looks and mixes are guided by the single-figure concept only: with the R02 line-up as an input
# the model redraws that line-up and ignores the requested garment.
REF1 = ["docs/reference/R01-moxie-concept.png"]
# Item sheets of looks use the clean front/back model sheets (no page frame to copy).
REF_LOOK = ["docs/reference/generated/moxie_front.png", "docs/reference/generated/moxie_back.png"]
KEEP = (
    " Her identity must stay unmistakable: the yellow headphones, the yellow belt Walkman, the scrappy "
    "dark-brown pigtails, the face paint, the crop top showing her midriff and the low-rise baggy pants "
    "are all clearly visible and unchanged."
)

def jobs():
    j = []
    for i, h in spec.HEADGEAR.items():
        p = (
            f"{spec.STYLE} Design sheet for ONE NEW piece of headgear that this character adds to her look. "
            f"THE NEW ITEM: {h['concept']} "
            f"LEFT HALF of the sheet: only this new item by itself as a prop with nobody wearing it (do NOT "
            f"draw the headphones as the prop), shown three times: front view, side view and three-quarter "
            f"view, chunky readable shapes with real separate parts. RIGHT HALF: a large head-and-shoulders "
            f"portrait of {spec.MOXIE} wearing the new item on her head TOGETHER WITH her yellow headphones, "
            f"three-quarter view, and beside it a small full-body figure of her wearing it. The new item never "
            f"covers or replaces the headphones: both yellow ear cups and the yellow band stay fully visible. "
            f"She otherwise wears her usual outfit: cream crop top, dark bomber jacket with yellow lining, "
            f"olive cargo pants, sand high-tops.{KEEP}"
        )
        j.append(("items", i, f"{OUT}/{i}.png", p, "1536x1024", "auto", REFS))
    # Looks: short, garment-first prompts. (Long identity-first prompts make the model redraw the
    # reference unchanged; so does passing the R02 line-up as an input.)
    what = {"top": "top and jacket", "pants": "pants", "shoes": "shoes"}
    rest = {
        "top": "her olive cargo pants and sand high-tops",
        "pants": "her cream crop top, dark bomber jacket with yellow lining and sand high-tops",
        "shoes": "her cream crop top, dark bomber jacket with yellow lining and olive cargo pants",
    }
    close = {"top": "the jacket and crop top", "pants": "the pants fabric and details", "shoes": "the pair of shoes"}
    for i, k in spec.LOOKS.items():
        sl = k["slot"]
        p = (
            f"Change her {what[sl]}. Redraw this exact character (shown from the front and from the back in "
            f"the two reference images) in the same art style, standing relaxed with her arms down, with the same face, "
            f"face paint, scrappy pigtails, yellow headphones, yellow belt Walkman, tool belt, bare midriff, "
            f"and {rest[sl]} unchanged, but now wearing {k['concept']} The garment keeps the same cut and "
            f"silhouette as her original (a short crop top under an open oversized jacket slipping off the "
            f"shoulders; baggy low-rise pants; chunky high-top shoes) and its colours are exactly as described. "
            f"Character sheet on a plain dark charcoal background: full-body front view on the left, "
            f"full-body back view in the centre, a large close-up of {close[sl]} on the right. No text, no labels."
        )
        j.append(("items", i, f"{OUT}/{i}.png", p, "1536x1024", "auto", REF_LOOK))
    for i, d in spec.PATTERNS.items():
        p = (
            f"Seamless tileable repeating texture swatch, perfectly flat, viewed straight on, filling the "
            f"whole square edge to edge with no border, no vignette, no shading, no perspective: {d}. "
            f"Pure black and white only, crisp flat graphic shapes, uniform density everywhere, the pattern "
            f"continues identically past every edge so that the left edge matches the right edge and the top "
            f"edge matches the bottom edge."
        )
        j.append(("patterns", i, f"{SRC}/pattern_{i}.png", p, "1024x1024", "opaque", None))
    for i, d in spec.DECALS.items():
        p = (
            f"A single flat pure-white stencil graphic centred on a plain solid black background, bold spray "
            f"stencil streetwear print style, thick clean shapes with slightly rough sprayed edges, no text, "
            f"no letters, no gradients, generous black margin around it: {d}."
        )
        j.append(("decals", i, f"{SRC}/decal_{i}.png", p, "1024x1024", "opaque", None))
    for i, ids in spec.MIXES.items():
        parts = [(spec.HEADGEAR.get(x) or spec.LOOKS[x])["concept"] for x in ids]
        p = (
            f"Change her outfit. Redraw this exact character in the same art style, with the same face, face "
            f"paint, scrappy pigtails, yellow headphones, yellow belt Walkman, tool belt and bare midriff, but "
            f"wearing this full loadout, all four pieces together and each in exactly the colours described: "
            f"ON HER HEAD (together with the yellow headphones, never covering them): {parts[0]} "
            f"TOP: {parts[1]} PANTS: {parts[2]} SHOES: {parts[3]} "
            f"One single full-body figure, three-quarter front view, head to toe in frame, relaxed confident "
            f"stance, plain dark charcoal background. No text, no labels."
        )
        j.append(("mixes", i, f"{OUT}/{i}.png", p, "1024x1536", "auto", REF1))
    return j


def run(job):
    kind, ident, out, prompt, size, bg, refs = job
    dst = os.path.join(ROOT, out)
    if os.path.exists(dst) and not os.environ.get("FORCE"):
        return ident, "exists"
    env = dict(os.environ, IMG_SIZE=size, IMG_BG=bg, IMG_QUALITY=os.environ.get("IMG_QUALITY", "medium"))
    tries = int(os.environ.get("TRIES", "8"))
    tmp = out[:-4] + ".new.png"          # never mistake an older file for a fresh result
    tmp_abs = os.path.join(ROOT, tmp)
    r = None
    for attempt in range(tries):
        if os.path.exists(tmp_abs):
            os.remove(tmp_abs)
        if refs:
            cmd = ["bash", "tools/img", "edit", tmp, prompt] + refs
        else:
            cmd = ["bash", "tools/img", "gen", tmp, prompt, size, bg]
        r = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True)
        if os.path.exists(tmp_abs) and os.path.getsize(tmp_abs) > 20000:
            os.replace(tmp_abs, dst)
            return ident, "ok"
        time.sleep(min(90, 15 * (attempt + 1)))   # the shared image proxy drops requests when busy
    return ident, "FAILED " + (r.stdout + r.stderr)[-300:].replace("\n", " ")


def main():
    args = sys.argv[1:]
    kinds = [a for a in args if a in ("items", "patterns", "decals", "mixes")]
    ids = [a for a in args if a not in kinds]
    todo = [j for j in jobs() if (not kinds or j[0] in kinds) and (not ids or j[1] in ids)]
    os.makedirs(os.path.join(ROOT, SRC), exist_ok=True)
    with ThreadPoolExecutor(max_workers=2) as ex:
        for ident, status in ex.map(run, todo):
            print(ident, status, flush=True)


if __name__ == "__main__":
    main()
