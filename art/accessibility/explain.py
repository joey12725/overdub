"""List the tightest requirement margins of a set: python -I explain.py '#aaaaaa' '#bbbbbb' '#cccccc' '#dddddd'"""
import itertools, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cvd, refs
from search import T_PAIR

def margins(cols):
    pal = refs.theme_palettes()
    rows = []
    def de(a, b, v): return float(cvd.delta_e(cvd.hex_to_rgb(a), cvd.hex_to_rgb(b), v))
    for i, j in itertools.combinations(range(4), 2):
        for v in cvd.VISIONS:
            d = de(cols[i], cols[j], v); rows.append((d / T_PAIR[v], d, "%s-%s %s" % (refs.LETTERS[i], refs.LETTERS[j], v)))
    for i, c in enumerate(cols):
        L = refs.LETTERS[i]
        for k in refs.DANGER:
            for v, t in (("normal", 14.0), ("protanopia", 8.0), ("deuteranopia", 8.0)):
                d = de(c, refs.RESERVED[k], v); rows.append((d / t, d, "%s vs %s %s" % (L, k, v)))
        for k in ("moxie_yellow", "hazard_upper", "hazard_lower", "chronal_amber", "ghost_grey", "state_dead", "state_desync", "boss_recall", "shield_teal"):
            d = de(c, refs.RESERVED[k], "normal"); rows.append((d / 12.0, d, "%s vs %s normal" % (L, k)))
        for t in refs.THEMES:
            for ak in refs.ACCENT_KEYS:
                d = de(c, pal[t][ak], "normal"); rows.append((d / 12.0, d, "%s vs %s %s normal" % (L, t, ak)))
            for sk in ("floor_color", "floor_alt"):
                d = de(c, pal[t][sk], "normal"); rows.append((d / 22.0, d, "%s vs %s %s normal" % (L, t, sk)))
                for v in cvd.VISIONS[1:]:
                    d = de(c, pal[t][sk], v); rows.append((d / 12.0, d, "%s vs %s %s %s" % (L, t, sk, v)))
    rows.sort()
    return rows

if __name__ == "__main__":
    for m, d, what in margins(sys.argv[1:5])[:14]:
        print("%.2f  dE %.1f  %s" % (m, d, what))
