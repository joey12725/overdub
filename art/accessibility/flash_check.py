"""Photosensitivity check for a captured frame sequence (WCAG 2.3.1 general + red flash thresholds).

    python -I art/accessibility/flash_check.py <frames_dir> [--fps 60] [--limits default|reduced]
    python -I art/accessibility/flash_check.py --self-test

<frames_dir> holds PNG frames in name order (e.g. from a `bash tools/gd shot` capture loop).

A flash is a pair of opposing changes in relative luminance of 10 % or more of full white where
the darker state is below 0.80. A red flash is a pair of opposing transitions involving saturated
red (R / (R + G + B) >= 0.8, and a change of (R - G - B) * 320 above 20 in either direction).
WCAG fails content with more than 3 flashes in any one second when the flashing area is larger than
25 % of a 10 degree visual field, which is a 341 x 256 px block on a 1024 x 768 screen, i.e. 2.8 %
of the screen. The frame is reduced to a 32 x 18 grid; a cell flashes when its mean does.

OVERDUB limits (data/accessibility/options.json "photosensitivity") are stricter than WCAG:
    default   at most 2 flashes in any second over 2.8 % of the screen, no red flash at all
    reduced   no flash at all over 2.8 % of the screen (reduce-flashing option)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np

GRID = (18, 32)
AREA = 0.028
LIMITS = {"wcag": 3, "default": 2, "reduced": 0}


def _lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def reduce_frame(rgb):
    """(H, W, 3) sRGB 0..1 -> (luminance grid, red-ness grid, red-saturation grid)."""
    h, w, _ = rgb.shape
    gh, gw = GRID
    ys = (np.arange(gh + 1) * h) // gh
    xs = (np.arange(gw + 1) * w) // gw
    lin = _lin(rgb)
    lum = lin @ np.array([0.2126, 0.7152, 0.0722])
    red = (rgb[..., 0] - rgb[..., 1] - rgb[..., 2]) * 320.0
    sat = rgb[..., 0] / np.maximum(rgb.sum(axis=-1), 1e-6)
    out = []
    for a in (lum, red, sat):
        g = np.add.reduceat(np.add.reduceat(a, ys[:-1], axis=0), xs[:-1], axis=1)
        counts = np.outer(np.diff(ys), np.diff(xs))
        out.append(g / counts)
    return out


def count_transitions(series, step, dark_gate=None):
    """Per cell: number of opposing-change pairs in `series` (T, cells). Returns (T,) flags per cell of
    the frame index at which each flash (second transition of a pair) completes."""
    t, n = series.shape
    ext = series[0].copy()        # running extreme since the last accepted transition
    direction = np.zeros(n, int)  # direction of the last accepted transition
    done = np.zeros((t, n), bool)
    for i in range(1, t):
        cur = series[i]
        up = cur - ext >= step
        down = ext - cur >= step
        if dark_gate is not None:
            lo = np.minimum(cur, ext)
            up &= lo < dark_gate
            down &= lo < dark_gate
        new_dir = np.where(up, 1, np.where(down, -1, 0))
        flash = (new_dir != 0) & (direction != 0) & (new_dir == -direction)
        done[i] = flash
        changed = new_dir != 0
        # Track the extreme: follow the signal while it keeps going the same way.
        ext = np.where(changed, cur, np.where(direction >= 0, np.maximum(ext, cur), np.minimum(ext, cur)))
        ext = np.where(direction == 0, np.where(changed, cur, ext), ext)
        direction = np.where(changed, new_dir, direction)
        # A flash consumes its pair: the next flash needs a fresh opposing pair.
        direction = np.where(flash, 0, direction)
    return done


def analyse(frames, fps):
    lum, red, sat = [], [], []
    for f in frames:
        a, b, c = reduce_frame(f)
        lum.append(a.ravel())
        red.append(b.ravel())
        sat.append(c.ravel())
    lum, red, sat = np.array(lum), np.array(red), np.array(sat)
    gen = count_transitions(lum, 0.10, dark_gate=0.80)
    redf = count_transitions(red, 20.0) & (np.maximum.accumulate(sat, axis=0) >= 0.8)
    win = max(1, int(round(fps)))
    res = {}
    for name, done in (("general", gen), ("red", redf)):
        worst, worst_area = 0, 0.0
        for s in range(0, max(1, len(frames) - win + 1)):
            per_cell = done[s:s + win].sum(axis=0)
            # Largest flash count shared by at least AREA of the screen within this second.
            k = int(per_cell.max()) if per_cell.size else 0
            while k > 0 and (per_cell >= k).mean() < AREA:
                k -= 1
            if k > worst:
                worst, worst_area = k, float((per_cell >= k).mean())
        res[name] = {"max_flashes_per_second": worst, "area_fraction": round(worst_area, 4)}
    return res


def verdict(res, limits):
    lim = LIMITS[limits]
    ok = res["general"]["max_flashes_per_second"] <= lim and res["red"]["max_flashes_per_second"] == 0
    return ok


def load_dir(path):
    from PIL import Image
    names = sorted(n for n in os.listdir(path) if n.lower().endswith(".png"))
    return [np.asarray(Image.open(os.path.join(path, n)).convert("RGB"), dtype=np.float64) / 255.0 for n in names]


def self_test():
    h, w, fps = 90, 160, 60

    def seq(fn, seconds=2.0):
        return [fn(i / fps) for i in range(int(seconds * fps))]

    def flat(v, col=(1, 1, 1)):
        return np.ones((h, w, 3)) * np.array(col) * v

    # 10 Hz full-screen white strobe: far over the limit.
    r = analyse(seq(lambda t: flat(1.0 if int(t * 20) % 2 == 0 else 0.0)), fps)
    assert r["general"]["max_flashes_per_second"] >= 9, r
    assert not verdict(r, "wcag")
    # 1 Hz full-screen flash: one flash a second, passes WCAG and the default limit, not "reduced".
    r = analyse(seq(lambda t: flat(1.0 if (t % 1.0) < 0.1 else 0.2), 3.0), fps)
    assert r["general"]["max_flashes_per_second"] in (1, 2), r
    assert verdict(r, "default") and not verdict(r, "reduced")
    # 10 Hz strobe on 1 % of the screen: under the area threshold, passes everything.
    def small(t):
        f = flat(0.2)
        if int(t * 20) % 2 == 0:
            f[:9, :16] = 1.0
        return f
    r = analyse(seq(small), fps)
    assert r["general"]["max_flashes_per_second"] == 0 and verdict(r, "reduced"), r
    # A soft full-screen pulse of 8 % luminance: not a flash at all.
    r = analyse(seq(lambda t: flat(0.5 + 0.02 * np.sin(t * 40.0))), fps)
    assert r["general"]["max_flashes_per_second"] == 0, r
    # 4 Hz saturated red flash over the whole screen: red flash failure.
    r = analyse(seq(lambda t: flat(1.0, (1, 0, 0)) if int(t * 8) % 2 == 0 else flat(0.0)), fps)
    assert r["red"]["max_flashes_per_second"] >= 3 and not verdict(r, "default"), r
    print("flash_check self-test ok")


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
        sys.exit(0)
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    fps = float(sys.argv[sys.argv.index("--fps") + 1]) if "--fps" in sys.argv else 60.0
    limits = sys.argv[sys.argv.index("--limits") + 1] if "--limits" in sys.argv else "default"
    out = analyse(load_dir(sys.argv[1]), fps)
    print(out, "PASS" if verdict(out, limits) else "FAIL", "(%s limits)" % limits)
    sys.exit(0 if verdict(out, limits) else 1)
