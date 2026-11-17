"""Search for a four-colour cassette set (python -I art/accessibility/search.py [config ...]).

Candidates are an HSV grid inside a hue band per cassette. A set is scored by its WORST normalised
margin (delta-E / target) over every requirement below, so the result is the set whose weakest
point is strongest; ties break on the mean margin. Coordinate ascent from many random starts over
precomputed delta-E tables (the grid is small enough that this converges to the same sets every
run; the seed is fixed).

Requirements (targets in CIEDE2000):
  pairwise, normal vision                      35
  pairwise, protanopia / deuteranopia          18
  pairwise, tritanopia                         14   (rare: about 1 in 10 000)
  vs danger colours (laser, enemy fx/eye...)   14 normal, 8 protan/deutan
  vs Moxie yellow and hazard yellow            12 normal
  vs theme accents (neon, graffiti, foliage)   12 normal
  vs every theme floor / floor_alt             22 normal, 12 worst dichromat
                                               (14 / 8 for the high-contrast set)
Hard limits: contrast >= 4.5 with ink text drawn on the colour and with the HUD panel behind it.
"""
import itertools
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import cvd
import refs

HERE = os.path.dirname(os.path.abspath(__file__))

CONFIGS = {
    # Keep the red / yellow / blue / green identities.
    "rybg": {"bands": [(325, 380), (40, 75), (190, 250), (90, 178)], "s": (0.5, 1.0), "v": (0.72, 1.0)},
    # No identity constraint at all: what an unconstrained optimum looks like.
    "free": {"bands": [(0, 360)] * 4, "s": (0.5, 1.0), "v": (0.72, 1.0)},
    # High-contrast alternative: lightness may spread further (it is always drawn with a
    # paper + ink double keyline, so bare contrast with the floor is not required).
    "high_contrast": {"bands": [(310, 380), (40, 75), (190, 255), (90, 178)], "s": (0.3, 1.0), "v": (0.5, 1.0), "hc": True},
}

# Refinement passes around the coarse optimum, and the pink-side alternative for cassette A.
CONFIGS["rybg_fine"] = {"bands": [(0, 18), (54, 70), (198, 226), (132, 164)], "s": (0.5, 1.0), "v": (0.8, 1.0), "steps": (2.0, 0.05, 0.025)}
CONFIGS["rybg_rose"] = {"bands": [(312, 346), (54, 70), (198, 226), (132, 164)], "s": (0.4, 1.0), "v": (0.8, 1.0), "steps": (2.0, 0.05, 0.025)}
CONFIGS["hc_fine"] = {"bands": [(310, 345), (56, 68), (205, 228), (150, 172)], "s": (0.3, 1.0), "v": (0.5, 1.0), "steps": (2.5, 0.05, 0.03), "hc": True}

T_PAIR = {"normal": 35.0, "protanopia": 18.0, "deuteranopia": 18.0, "tritanopia": 14.0}


def grid(band, s_rng, v_rng, steps=(3.0, 0.0625, 0.04)):
    out = []
    for h in np.arange(band[0], band[1] + 0.01, steps[0]):
        for s in np.arange(s_rng[0], s_rng[1] + 1e-6, steps[1]):
            for v in np.arange(v_rng[0], v_rng[1] + 1e-6, steps[2]):
                out.append(cvd.hsv_to_rgb(h, s, v))
    return np.array(out)


def unary_margin(rgb, hc):
    """Worst normalised margin of each candidate against everything that is not another cassette."""
    pal = refs.theme_palettes()
    n = len(rgb)
    worst = np.full(n, 1e9)

    def upd(target_hex, vision, target):
        nonlocal worst
        d = cvd.delta_e(rgb, cvd.hex_to_rgb(target_hex)[None, :], vision)
        worst = np.minimum(worst, d / target)

    for k in refs.DANGER:
        upd(refs.RESERVED[k], "normal", 14.0)
        upd(refs.RESERVED[k], "protanopia", 8.0)
        upd(refs.RESERVED[k], "deuteranopia", 8.0)
    for k in ("moxie_yellow", "hazard_upper", "hazard_lower", "chronal_amber"):
        upd(refs.RESERVED[k], "normal", 12.0)
    for k in ("ghost_grey", "state_dead", "state_desync", "boss_recall", "shield_teal"):
        upd(refs.RESERVED[k], "normal", 12.0)
    for t in refs.THEMES:
        for ak in refs.ACCENT_KEYS:
            upd(pal[t][ak], "normal", 12.0)
        # The high-contrast set is always drawn with a paper + ink double keyline, so it needs
        # less bare separation from the floor than the default set.
        for sk in ("floor_color", "floor_alt"):
            upd(pal[t][sk], "normal", 14.0 if hc else 22.0)
            for v in cvd.VISIONS[1:]:
                upd(pal[t][sk], v, 8.0 if hc else 12.0)
    ink = cvd.contrast(rgb, cvd.hex_to_rgb(refs.HUD["ink"])[None, :])
    panel = cvd.contrast(rgb, cvd.hex_to_rgb(refs.HUD["panel"])[None, :])
    lim = 3.0 if hc else 4.5
    worst = np.where((ink >= lim) & (panel >= lim), worst, -1.0)
    return worst


def pair_margin(ra, rb):
    """Worst normalised pairwise margin for every (a, b) candidate pair."""
    out = np.full((len(ra), len(rb)), 1e9)
    for v in cvd.VISIONS:
        la = cvd.rgb_to_lab(cvd.simulate(ra, v))[:, None, :]
        lb = cvd.rgb_to_lab(cvd.simulate(rb, v))[None, :, :]
        out = np.minimum(out, cvd.ciede2000(la, lb) / T_PAIR[v])
    return out


def run(name, cfg, top=5, starts=400, seed=7):
    rng = np.random.default_rng(seed)
    cands = [grid(b, cfg["s"], cfg["v"], cfg.get("steps", (3.0, 0.0625, 0.04))) for b in cfg["bands"]]
    un = [unary_margin(c, cfg.get("hc", False)) for c in cands]
    keep = [u > 0.3 for u in un]
    cands = [c[k] for c, k in zip(cands, keep)]
    un = [u[k] for u, k in zip(un, keep)]
    pm = {(i, j): pair_margin(cands[i], cands[j]) for i, j in itertools.combinations(range(4), 2)}

    def pmg(i, j, a, b):
        return pm[(i, j)][a, b] if i < j else pm[(j, i)][b, a]

    def score(ix):
        ms = [un[i][ix[i]] for i in range(4)] + [pmg(i, j, ix[i], ix[j]) for i, j in itertools.combinations(range(4), 2)]
        return min(ms), float(np.mean(ms))

    found = {}
    for _ in range(starts):
        ix = [int(rng.integers(len(c))) for c in cands]
        best = score(ix)
        improved = True
        while improved:
            improved = False
            for i in range(4):
                # Vectorised: worst margin for every candidate in slot i with the others fixed.
                m = un[i].copy()
                tot = un[i].copy()
                for j in range(4):
                    if j == i:
                        continue
                    row = pm[(i, j)][:, ix[j]] if i < j else pm[(j, i)][ix[j], :]
                    m = np.minimum(m, row)
                    tot = tot + row
                k = int(np.lexsort((tot, m))[-1])
                if k != ix[i]:
                    trial = ix[:i] + [k] + ix[i + 1:]
                    sc = score(trial)
                    if sc > best:
                        ix, best, improved = trial, sc, True
        found[tuple(ix)] = best
    ranked = sorted(found.items(), key=lambda kv: kv[1], reverse=True)[:top]
    res = []
    for ix, sc in ranked:
        cols = [cvd.rgb_to_hex(cands[i][ix[i]]) for i in range(4)]
        res.append({"colors": cols, "worst_margin": round(float(sc[0]), 3), "mean_margin": round(sc[1], 3)})
        print(name, cols, "worst %.3f mean %.3f" % (sc[0], sc[1]))
    return res


if __name__ == "__main__":
    names = sys.argv[1:] or list(CONFIGS)
    out = {}
    for n in names:
        out[n] = run(n, CONFIGS[n])
    p = os.path.join(HERE, "out", "search.json")
    prev = json.load(open(p)) if os.path.exists(p) else {}
    prev.update(out)
    json.dump(prev, open(p, "w"), indent=1)
