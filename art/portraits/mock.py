"""Contact sheets, cast line-up and dialogue-box mocks for the portraits.

usage (repo root): python -I art/portraits/mock.py
Writes art/portraits/sheets/: <id>_sheet.png (all expressions, 384 px, on dark and light),
<id>_overlay.png (all expressions stacked at 50% to show head drift), lineup.png (neutral of each character at equal scale),
dialogue_<id>.png (every expression in a mock dialogue box at 256 px with a real line from story.json).
"""
import json, os, sys
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sheet import font
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
P = os.path.join(ROOT, "assets", "portraits"); S = os.path.join(HERE, "sheets"); os.makedirs(S, exist_ok=True)
story = json.load(open(os.path.join(ROOT, "data", "story", "story.json"), encoding="utf-8"))
chars = story["characters"]

def lines():
    found = {}
    def walk(o):
        if isinstance(o, dict):
            if "who" in o and "expression" in o and "line" in o: found.setdefault((o["who"], o["expression"]), o["line"])
            for v in o.values(): walk(v)
        elif isinstance(o, list):
            for v in o: walk(v)
    walk(story); return found
LINES = lines()
def img(c, e): return Image.open(os.path.join(P, f"{c}_{e}.png")).convert("RGBA")
def hexrgb(h): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))

def char_sheet(c):
    es = c["portraits"]; cell = 384; lab = 28
    im = Image.new("RGB", (cell * len(es), (cell + lab) * 2), (20, 16, 28)); d = ImageDraw.Draw(im)
    for row, bg in enumerate([(24, 20, 34), (214, 196, 160)]):
        d.rectangle([0, row * (cell + lab), im.width, row * (cell + lab) + cell], fill=bg)
        for i, e in enumerate(es):
            s = img(c["id"], e).resize((cell, cell), Image.LANCZOS)
            im.paste(s, (i * cell, row * (cell + lab)), s)
            d.text((i * cell + 8, row * (cell + lab) + cell + 4), f"{c['id']}_{e}", fill=hexrgb(c["color"]), font=font(18))
    im.save(os.path.join(S, f"{c['id']}_sheet.png"))
    ov = Image.new("RGBA", (1024, 1024), (24, 20, 34, 255))
    for e in es:
        s = img(c["id"], e); s.putalpha(s.getchannel("A").point(lambda v: v * (1.6 / len(es)) if len(es) > 1 else v))
        ov.alpha_composite(s)
    ov.convert("RGB").resize((512, 512), Image.LANCZOS).save(os.path.join(S, f"{c['id']}_overlay.png"))

def lineup():
    cell = 512; im = Image.new("RGB", (cell * len(chars), cell + 34), (24, 20, 34)); d = ImageDraw.Draw(im)
    for i, c in enumerate(chars):
        s = img(c["id"], c["portraits"][0]).resize((cell, cell), Image.LANCZOS); im.paste(s, (i * cell, 0), s)
        d.text((i * cell + 10, cell + 6), c["name"], fill=hexrgb(c["color"]), font=font(22))
    im.save(os.path.join(S, "lineup.png"))

def box(c, e, W=960, H=300):
    """One mock dialogue box: 256 px portrait, name tab in the character colour, one story line."""
    col = hexrgb(c["color"]); left = c["id"] == "moxie"
    im = Image.new("RGB", (W, H), (58, 70, 62) if left else (40, 34, 60)); d = ImageDraw.Draw(im)   # stand-in for the dimmed world
    py0, py1 = H - 150, H - 14
    d.rounded_rectangle([14, py0, W - 14, py1], 10, fill=(18, 15, 26), outline=col, width=3)
    ps = 256; px = 26 if left else W - 26 - ps
    s = img(c["id"], e).resize((ps, ps), Image.LANCZOS)
    clip = Image.new("L", (ps, ps), 0); ImageDraw.Draw(clip).rectangle([0, 0, ps, ps - 3], fill=255)
    im.paste(s, (px, py1 - ps), Image.composite(s.getchannel("A"), Image.new("L", (ps, ps), 0), clip))
    d.line([14 + 6, py1 - 1, W - 14 - 6, py1 - 1], fill=col, width=3)                               # box edge over the bust's cut
    tx = px + ps + 20 if left else 40
    name = c["name"].upper(); f = font(20); tw = d.textlength(name, font=f)
    nx = tx if left else px - 20 - tw - 24
    d.rounded_rectangle([nx, py0 - 30, nx + tw + 24, py0 + 2], 6, fill=col)
    d.text((nx + 12, py0 - 26), name, fill=(18, 15, 26), font=f)
    line = LINES.get((c["id"], e), "(no line uses this portrait)")
    words = line.split(); rows = [""]
    for w in words:
        if len(rows[-1]) + len(w) + 1 > 45: rows.append("")
        rows[-1] = (rows[-1] + " " + w).strip()
    for i, r in enumerate(rows[:2]): d.text((tx, py0 + 28 + i * 38), r, fill=(240, 236, 226), font=font(26))
    d.text((W - 150 if left else 26, 8), f"{c['id']}_{e}", fill=(170, 170, 170), font=font(14))
    return im

def dialogue(c):
    es = c["portraits"]; cols = 2; W, H = 960, 300; rows = (len(es) + 1) // 2
    im = Image.new("RGB", (W * cols, H * rows), (0, 0, 0))
    for i, e in enumerate(es): im.paste(box(c, e), ((i % cols) * W, (i // cols) * H))
    im.save(os.path.join(S, f"dialogue_{c['id']}.png"))

if __name__ == "__main__":
    only = sys.argv[1:]
    for c in chars:
        if only and c["id"] not in only: continue
        char_sheet(c); dialogue(c)
    if not only: lineup()
