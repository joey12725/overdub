"""Numerical analysis of four-colour cassette sets.

    python -I art/accessibility/analyze.py

Analyses the current set plus every set in sets.json, prints the headline numbers and writes
out/analysis.json and out/analysis.md (the tables quoted in docs/ACCESSIBILITY.md)."""
import itertools
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cvd
import refs

HERE = os.path.dirname(os.path.abspath(__file__))
PAIRS = list(itertools.combinations(range(4), 2))


def de(a, b, vision="normal"):
    return float(cvd.delta_e(cvd.hex_to_rgb(a), cvd.hex_to_rgb(b), vision))


def cr(a, b):
    return float(cvd.contrast(cvd.hex_to_rgb(a), cvd.hex_to_rgb(b)))


def analyse(colors):
    pal = refs.theme_palettes()
    res = {"colors": colors, "pairwise": {}, "pairwise_min": {}, "surfaces": {}, "accents": {}, "hud": {}, "reserved": {}}
    for v in cvd.VISIONS:
        d = {"%s-%s" % (refs.LETTERS[i], refs.LETTERS[j]): round(de(colors[i], colors[j], v), 1) for i, j in PAIRS}
        res["pairwise"][v] = d
        k = min(d, key=d.get)
        res["pairwise_min"][v] = {"pair": k, "dE": d[k]}
    for t in refs.THEMES:
        res["surfaces"][t] = {}
        for sk in refs.SURFACE_KEYS:
            row = {}
            for i, c in enumerate(colors):
                row[refs.LETTERS[i]] = {
                    "contrast": round(cr(c, pal[t][sk]), 2),
                    "dE": {v: round(de(c, pal[t][sk], v), 1) for v in cvd.VISIONS},
                }
            res["surfaces"][t][sk] = {"hex": pal[t][sk], "by_tape": row}
        res["accents"][t] = {}
        for ak in refs.ACCENT_KEYS:
            row = {refs.LETTERS[i]: {v: round(de(c, pal[t][ak], v), 1) for v in cvd.VISIONS} for i, c in enumerate(colors)}
            res["accents"][t][ak] = {"hex": pal[t][ak], "by_tape": row}
    for hk, hv in refs.HUD.items():
        res["hud"][hk] = {"hex": hv, "contrast": {refs.LETTERS[i]: round(cr(c, hv), 2) for i, c in enumerate(colors)}}
    for rk, rv in refs.RESERVED.items():
        res["reserved"][rk] = {"hex": rv, "by_tape": {refs.LETTERS[i]: {v: round(de(c, rv, v), 1) for v in cvd.VISIONS} for i, c in enumerate(colors)}}
    return res


def summary(res):
    """Headline numbers: worst pair per vision, worst floor contrast / distance, nearest reserved / accent."""
    s = {"worst_pair": res["pairwise_min"]}
    worst = (99.0, "")
    worst_de = (999.0, "")
    for t, d in res["surfaces"].items():
        for sk in ("floor_color", "floor_alt"):
            for L, x in d[sk]["by_tape"].items():
                if x["contrast"] < worst[0]:
                    worst = (x["contrast"], "%s on %s %s" % (L, t, sk))
                m = min(x["dE"].values())
                if m < worst_de[0]:
                    worst_de = (m, "%s on %s %s" % (L, t, sk))
    s["worst_floor_contrast"] = {"ratio": worst[0], "where": worst[1]}
    s["worst_floor_dE_any_vision"] = {"dE": worst_de[0], "where": worst_de[1]}
    near = []
    for rk, d in res["reserved"].items():
        for L, x in d["by_tape"].items():
            near.append((x["normal"], L, rk))
    near.sort()
    s["nearest_reserved"] = [{"dE": a, "tape": b, "to": c} for a, b, c in near[:6]]
    near = []
    for t, d in res["accents"].items():
        for ak, x in d.items():
            for L, y in x["by_tape"].items():
                near.append((y["normal"], L, "%s %s" % (t, ak)))
    near.sort()
    s["nearest_accent"] = [{"dE": a, "tape": b, "to": c} for a, b, c in near[:6]]
    s["ink_on_colour_min"] = min(res["hud"]["ink"]["contrast"].values())
    s["colour_on_panel_min"] = min(res["hud"]["panel"]["contrast"].values())
    return s


def md_tables(name, res):
    L = refs.LETTERS
    o = ["### %s: %s" % (name, " ".join("%s `%s`" % (L[i], c) for i, c in enumerate(res["colors"]))), ""]
    o += ["Pairwise CIEDE2000:", "",
          "| vision | " + " | ".join("%s-%s" % (L[i], L[j]) for i, j in PAIRS) + " | min |", "|---|" + "---|" * (len(PAIRS) + 1)]
    for v in cvd.VISIONS:
        d = res["pairwise"][v]
        o.append("| %s | " % v + " | ".join("%.1f" % d["%s-%s" % (L[i], L[j])] for i, j in PAIRS) + " | **%.1f** (%s) |" % (res["pairwise_min"][v]["dE"], res["pairwise_min"][v]["pair"]))
    o += ["", "WCAG contrast ratio of the bare colour against each theme surface:", "",
          "| theme | surface | hex | " + " | ".join(L) + " |", "|---|---|---|---|---|---|---|"]
    for t in refs.THEMES:
        for sk in refs.SURFACE_KEYS:
            x = res["surfaces"][t][sk]
            o.append("| %s | %s | `%s` | " % (t, sk, x["hex"]) + " | ".join("%.2f" % x["by_tape"][l]["contrast"] for l in L) + " |")
    o += ["", "Contrast against HUD surfaces:", "", "| surface | hex | " + " | ".join(L) + " |", "|---|---|---|---|---|---|"]
    for hk, x in res["hud"].items():
        o.append("| %s | `%s` | " % (hk, x["hex"]) + " | ".join("%.2f" % x["contrast"][l] for l in L) + " |")
    o += ["", "CIEDE2000 to colours with a reserved meaning (normal / worst dichromat):", "", "| reserved | hex | " + " | ".join(L) + " |", "|---|---|---|---|---|---|"]
    for rk, x in res["reserved"].items():
        cells = []
        for l in L:
            d = x["by_tape"][l]
            lo = min(d[v] for v in cvd.VISIONS[1:])
            cell = "%.0f / %.0f" % (d["normal"], lo)
            cells.append("**%s**" % cell if d["normal"] < 12 else cell)
        o.append("| %s | `%s` | " % (rk, x["hex"]) + " | ".join(cells) + " |")
    o += ["", "CIEDE2000 to theme accents, normal vision (rows with a value under 25 only):", "", "| theme | accent | hex | " + " | ".join(L) + " |", "|---|---|---|---|---|---|---|"]
    for t in refs.THEMES:
        for ak in refs.ACCENT_KEYS:
            x = res["accents"][t][ak]
            vals = [x["by_tape"][l]["normal"] for l in L]
            if min(vals) < 25:
                o.append("| %s | %s | `%s` | " % (t, ak, x["hex"]) + " | ".join(("**%.0f**" % v) if v < 15 else "%.0f" % v for v in vals) + " |")
    o.append("")
    return "\n".join(o)


def main():
    sets = {"current": refs.CURRENT}
    p = os.path.join(HERE, "sets.json")
    if os.path.exists(p):
        sets.update(json.load(open(p)))
    cvd.self_test()
    out, md = {}, []
    for name, cols in sets.items():
        r = analyse(cols)
        r["summary"] = summary(r)
        out[name] = r
        md.append(md_tables(name, r))
        print("==", name, cols)
        print(json.dumps(r["summary"]))
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    json.dump(out, open(os.path.join(HERE, "out", "analysis.json"), "w"), indent=1)
    open(os.path.join(HERE, "out", "analysis.md"), "w", encoding="utf-8").write("\n".join(md))


if __name__ == "__main__":
    main()
