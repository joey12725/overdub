"""Procedural HUD glyphs (actions + tape states). Drawn with PIL so they stay crisp at 24 px.

  python -I art/icons/glyphs.py      -> assets/ui/icons/actions/*.png, assets/ui/icons/tape/*.png  (256x256 RGBA)

Every glyph is a solid WHITE shape with a bold BLACK ink outline on a transparent canvas, so it reads on light and
dark panels and can be tinted with a modulate colour (white x tint = tint, the outline stays black).
The only coloured glyph is tape/rec (record red).
Shapes are authored in a 0..100 unit box, auto-fitted to the canvas, supersampled 4x.
"""
import os, math
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "assets", "ui", "icons")
SS = 1024          # supersampled working size
FINAL = 256
MARGIN = 0.065     # empty margin around the outlined glyph, fraction of canvas
OUTLINE = 0.050    # ink outline width, fraction of canvas (1.2 px at 24 px)
U = 8.0            # px per unit while authoring (0..100 box -> 800 px, drawn on a 1000 px pad with offset 100)


class G:
    def __init__(self):
        self.w = Image.new("L", (1000, 1000), 0)   # white fill
        self.k = Image.new("L", (1000, 1000), 0)   # black ink drawn on top of the fill
        self.dw, self.dk = ImageDraw.Draw(self.w), ImageDraw.Draw(self.k)

    @staticmethod
    def p(x, y):
        return (100 + x * U, 100 + y * U)

    def _d(self, ink):
        return self.dk if ink else self.dw

    def poly(self, pts, ink=False, v=255):
        self._d(ink).polygon([self.p(*q) for q in pts], fill=v)

    def circle(self, cx, cy, r, ink=False, v=255):
        self._d(ink).ellipse([self.p(cx - r, cy - r), self.p(cx + r, cy + r)], fill=v)

    def ellipse(self, x0, y0, x1, y1, ink=False, v=255):
        self._d(ink).ellipse([self.p(x0, y0), self.p(x1, y1)], fill=v)

    def rrect(self, x0, y0, x1, y1, r, ink=False, v=255):
        self._d(ink).rounded_rectangle([self.p(x0, y0), self.p(x1, y1)], radius=r * U, fill=v)

    def line(self, x0, y0, x1, y1, w, ink=False, v=255, cap=True):
        d = self._d(ink)
        d.line([self.p(x0, y0), self.p(x1, y1)], fill=v, width=int(w * U))
        if cap:
            for (x, y) in ((x0, y0), (x1, y1)):
                self.circle(x, y, w / 2, ink, v)

    def arc(self, cx, cy, r, a0, a1, w, ink=False, v=255):
        """Ring segment, angles in degrees clockwise from 3 o'clock, r = centre-line radius."""
        ro = r + w / 2
        self._d(ink).arc([self.p(cx - ro, cy - ro), self.p(cx + ro, cy + ro)], a0, a1, fill=v, width=int(w * U))

    def pie(self, cx, cy, r, a0, a1, ink=False, v=255):
        self._d(ink).pieslice([self.p(cx - r, cy - r), self.p(cx + r, cy + r)], a0, a1, fill=v)

    def render(self, fill=(255, 255, 255)):
        w = np.asarray(self.w) > 127
        k = np.asarray(self.k) > 127
        shape = w | k
        ys, xs = np.where(shape)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        box = SS * (1 - 2 * MARGIN - 2 * OUTLINE)
        s = box / max(y1 - y0, x1 - x0)
        tw, th = round((x1 - x0) * s), round((y1 - y0) * s)

        def fit(mask):
            m = Image.fromarray((mask[y0:y1, x0:x1] * 255).astype(np.uint8)).resize((tw, th), Image.LANCZOS)
            c = Image.new("L", (SS, SS), 0)
            c.paste(m, ((SS - tw) // 2, (SS - th) // 2))
            return np.asarray(c) > 127

        W, K = fit(w), fit(k)
        S = W | K
        dist = ndi.distance_transform_edt(~S)
        alpha = np.clip(OUTLINE * SS - dist + 0.5, 0, 1)
        rgb = np.zeros((SS, SS, 3), np.float32)
        rgb[W & ~K] = fill
        pm = np.dstack([rgb * alpha[..., None], alpha * 255])
        chans = [Image.fromarray(pm[..., i].astype(np.uint8)).resize((FINAL, FINAL), Image.LANCZOS) for i in range(4)]
        r = np.dstack([np.asarray(c).astype(np.float32) for c in chans])
        a = r[..., 3:4]
        out = np.dstack([np.where(a > 0, r[..., :3] * 255 / np.maximum(a, 1), 0), a])
        return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def star(g, cx, cy, n, ro, ri, rot=-90, ink=False):
    pts = []
    for i in range(n * 2):
        r = ro if i % 2 == 0 else ri
        a = math.radians(rot + i * 180 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    g.poly(pts, ink)


# ───────────── actions ─────────────
def light():      # one quick slash: a slim crescent
    g = G()
    g.circle(50, 50, 46)
    g.circle(34, 62, 47, v=0)
    return g


def heavy():      # big impact burst: fat crescent + shock star
    g = G()
    pts = []
    for i in range(16):
        r = (48, 27, 38, 27)[i % 4]
        a = math.radians(-90 + i * 22.5)
        pts.append((50 + r * math.cos(a), 50 + r * math.sin(a)))
    g.poly(pts)
    return g


def dodge():      # dash: two slanted chevrons
    g = G()
    for x in (4, 42):
        g.poly([(x + 8, 8), (x + 30, 8), (x + 52, 50), (x + 22, 92), (x, 92), (x + 28, 50)])
    return g


def ranged():     # crosshair
    g = G()
    g.arc(50, 50, 29, 0, 360, 14)
    for a in range(0, 360, 90):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        g.line(50 + c * 30, 50 + s * 30, 50 + c * 46, 50 + s * 46, 14, cap=False)
    g.circle(50, 50, 8)
    return g


def interact():   # lever switch thrown to one side
    g = G()
    g.rrect(10, 70, 90, 94, 8)
    g.line(50, 74, 72, 28, 15)
    g.circle(73, 24, 17)
    g.rrect(22, 79, 78, 85, 3, ink=True)
    return g


def ability():    # lightning bolt
    g = G()
    g.poly([(60, 2), (16, 56), (44, 56), (34, 98), (84, 38), (54, 38), (70, 2)])
    return g


# ───────────── tape ─────────────
def stop():
    g = G()
    g.rrect(12, 12, 88, 88, 10)
    return g


def rec():
    g = G()
    g.circle(50, 50, 40)
    return g


def repeat():     # loop arrow
    g = G()
    a_end = 285
    g.arc(50, 52, 30, 20, a_end, 16)
    t = math.radians(a_end)
    ex, ey = 50 + 30 * math.cos(t), 52 + 30 * math.sin(t)
    tx, ty = -math.sin(t), math.cos(t)
    nx, ny = math.cos(t), math.sin(t)
    g.poly([(ex + tx * 28, ey + ty * 28), (ex + nx * 22 - tx * 2, ey + ny * 22 - ty * 2), (ex - nx * 22 - tx * 2, ey - ny * 22 - ty * 2)])
    return g


def reverse():    # rewind
    g = G()
    g.poly([(50, 12), (50, 88), (6, 50)])
    g.poly([(94, 12), (94, 88), (50, 50)])
    return g


def alive():      # heart
    g = G()
    g.circle(30, 34, 23)
    g.circle(70, 34, 23)
    g.poly([(9.5, 44), (50, 94), (90.5, 44), (50, 30)])
    return g


def dead():       # skull
    g = G()
    g.ellipse(10, 6, 90, 74)
    g.rrect(29, 56, 71, 94, 7)
    g.ellipse(22, 32, 45, 58, ink=True)
    g.ellipse(55, 32, 78, 58, ink=True)
    g.poly([(50, 58), (44, 69), (56, 69)], ink=True)
    for x in (43, 57):
        g.line(x, 82, x, 96, 4, ink=True, cap=False)
    return g


def desync():     # a disc snapped in two, halves slipped out of line
    g = G()
    g.pie(40, 46, 38, 180, 360)
    g.pie(60, 54, 38, 0, 180)
    return g


def resync():     # the recovery spark flying home: spark with a comet tail
    g = G()
    g.poly([(52, 30), (72, 50), (4, 98)])
    star(g, 62, 40, 4, 40, 13)
    return g


def locked():     # padlock
    g = G()
    g.arc(50, 42, 21, 180, 360, 13)
    g.line(29, 42, 29, 52, 13, cap=False)
    g.line(71, 42, 71, 52, 13, cap=False)
    g.rrect(14, 46, 86, 96, 9)
    g.circle(50, 65, 8, ink=True)
    g.rrect(46, 66, 54, 84, 2, ink=True)
    return g


ACTIONS = {"light": light, "heavy": heavy, "dodge": dodge, "ranged": ranged, "interact": interact, "ability": ability}
TAPE = {"stop": stop, "repeat": repeat, "reverse": reverse, "alive": alive, "dead": dead, "desync": desync,
        "resync": resync, "locked": locked, "rec": rec}
FILL = {"rec": (255, 59, 78)}


def main():
    for group, table in (("actions", ACTIONS), ("tape", TAPE)):
        os.makedirs(os.path.join(OUT, group), exist_ok=True)
        for name, fn in table.items():
            fn().render(FILL.get(name, (255, 255, 255))).save(os.path.join(OUT, group, name + ".png"), optimize=True)
            print(group + "/" + name)


if __name__ == "__main__":
    main()
