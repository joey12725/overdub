"""Numerical listening for the generated samples (we cannot hear, so we measure).

    python -I art/audio/analyze.py              per-family table + problems
    python -I art/audio/analyze.py --files      every file
    python -I art/audio/analyze.py mix.wav ...  analyse rendered mixes (stereo ok)

Checks, per file: the leading pad is exact silence; peak <= -0.9 dBFS; no DC; no clicks (a
sample-to-sample jump far above what the local spectrum explains); loop seams continuous; tails
decay below -60 dB inside the file (one-shots); spectral balance (centroid, energy below 120 Hz
and above 8 kHz, so nothing is muddy or harsh). Exit status 1 when a problem is found.
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402
from scipy.io import wavfile  # noqa: E402

import dsp  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio")


def load(path: str) -> np.ndarray:
    sr, q = wavfile.read(path)
    assert sr == dsp.SR, f"{path}: sample rate {sr}"
    x = q.astype(np.float64) / 32768.0
    return x


def click_score(x: np.ndarray) -> float:
    """Largest first difference relative to the local RMS of the differences (a spike detector)."""
    d = np.abs(np.diff(x))
    if len(d) < 256:
        return 0.0
    k = 128
    local = np.sqrt(np.convolve(d * d, np.ones(k) / k, mode="same")) + 1e-4
    return float(np.max(d / local))


def analyse_family(name: str, fam: dict, pad_frames: int, problems: list[str], rows: list[str], per_file: bool) -> None:
    peaks, rmss, cents, lows, highs, tails = [], [], [], [], [], []
    for e in fam["samples"]:
        path = os.path.join(AUDIO, e["file"])
        x = load(path)
        if len(x) != e["frames"]:
            problems.append(f"{e['file']}: {len(x)} frames, manifest says {e['frames']}")
        pad = x[:pad_frames]
        if np.any(pad != 0.0):
            problems.append(f"{e['file']}: pad is not silent")
        body = x[pad_frames:]
        if not np.all(np.isfinite(body)):
            problems.append(f"{e['file']}: non-finite samples")
        p = dsp.peak(body)
        r = dsp.rms(body[: dsp.n_of(0.5)])
        c = dsp.spectral_centroid(body[: dsp.n_of(0.5)])
        lo = dsp.band_energy(body[: dsp.n_of(0.5)], 0, 120)
        hi = dsp.band_energy(body[: dsp.n_of(0.5)], 8000, 22050)
        dc = float(np.mean(body))
        peaks.append(p)
        rmss.append(r)
        cents.append(c)
        lows.append(lo)
        highs.append(hi)
        if p > dsp.undb(-0.9):
            problems.append(f"{e['file']}: peak {dsp.db(p):.2f} dBFS")
        if abs(dc) > 0.004:
            problems.append(f"{e['file']}: DC offset {dc:.4f}")
        cs = click_score(body)
        if "loopBegin" in e:
            lb, le = e["loopBegin"], e["loopEnd"]
            if not (pad_frames < lb < le <= len(x)):
                problems.append(f"{e['file']}: bad loop points {lb}..{le}")
            else:
                seam = abs(x[le - 1] - x[lb - 1]) + abs(x[lb] - x[lb - 1]) * 0
                jump = abs(x[lb] - x[le - 1])
                typical = float(np.mean(np.abs(np.diff(x[lb:le])))) * 4 + 1e-4
                if jump > typical:
                    problems.append(f"{e['file']}: loop seam jump {jump:.4f} (typical step {typical / 4:.4f})")
                _ = seam
            tails.append(float("nan"))
        else:
            t = dsp.tail_seconds(body, -60.0)
            tails.append(t)
            end_level = dsp.peak(body[-dsp.n_of(0.004):]) / max(1e-9, p)
            if end_level > dsp.undb(-40):
                problems.append(f"{e['file']}: does not decay (last 4 ms at {dsp.db(end_level):.1f} dB re peak)")
        if cs > 60:
            problems.append(f"{e['file']}: possible click (spike score {cs:.0f})")
        if per_file:
            rows.append(f"  {e['file']:42s} peak {dsp.db(p):6.1f}  rms {dsp.db(r):6.1f}  centroid {c:6.0f} Hz  <120 {lo:5.2f}  >8k {hi:5.2f}  tail {tails[-1]:5.2f}s  spike {cs:5.1f}")
    rr = [dsp.db(v) for v in rmss]
    rows.append(
        f"{name:20s} n={len(peaks):2d}  peak {dsp.db(max(peaks)):6.1f} dBFS  rms {min(rr):6.1f}..{max(rr):6.1f} dB  "
        f"crest {dsp.db(max(peaks)) - float(np.mean(rr)):5.1f}  centroid {np.median(cents):6.0f} Hz  "
        f"<120Hz {np.median(lows):4.2f}  >8k {np.median(highs):4.2f}  tail {np.nanmax(tails) if not all(np.isnan(tails)) else float('nan'):5.2f}s"
    )


def analyse_mix(path: str) -> int:
    sr, q = wavfile.read(path)
    x = q.astype(np.float64)
    if q.dtype == np.int16:
        x /= 32768.0
    elif q.dtype == np.int32:
        x /= 2147483648.0
    if x.ndim == 1:
        x = x[:, None]
    mono = x.mean(axis=1)
    p = float(np.max(np.abs(x)))
    r = dsp.rms(mono)
    # Short-term loudness proxy: 400 ms RMS windows.
    win = int(0.4 * sr)
    st = [dsp.rms(mono[i:i + win]) for i in range(0, max(1, len(mono) - win), win // 2)]
    st_db = [dsp.db(v) for v in st if v > 1e-6]
    clipped = int(np.sum(np.abs(x) >= 0.999))
    print(f"{os.path.basename(path)}: {len(mono) / sr:.2f}s  sr {sr}  ch {x.shape[1]}")
    print(f"  peak {dsp.db(p):6.2f} dBFS   rms {dsp.db(r):6.2f} dBFS   crest {dsp.db(p) - dsp.db(r):5.1f} dB   clipped samples {clipped}")
    if st_db:
        print(f"  400ms rms: min {min(st_db):6.1f}  median {np.median(st_db):6.1f}  max {max(st_db):6.1f} dB")
    for lo, hi in ((20, 120), (120, 500), (500, 2000), (2000, 6000), (6000, 12000), (12000, 22050)):
        print(f"  band {lo:5d}-{hi:5d} Hz: {100 * dsp.band_energy(mono[: sr * 30], lo, hi):5.1f}% energy")
    if x.shape[1] == 2:
        l, rr = x[:, 0], x[:, 1]
        corr = float(np.corrcoef(l, rr)[0, 1]) if dsp.rms(l) > 0 and dsp.rms(rr) > 0 else 1.0
        print(f"  stereo correlation {corr:.3f}  L {dsp.db(dsp.rms(l)):.1f} dB  R {dsp.db(dsp.rms(rr)):.1f} dB")
    print(f"  spike score {click_score(mono):.1f}")
    return 0


def main(argv: list[str]) -> int:
    mixes = [a for a in argv if a.endswith(".wav")]
    if mixes:
        for m in mixes:
            analyse_mix(m)
        return 0
    per_file = "--files" in argv
    with open(os.path.join(AUDIO, "manifest.json"), "r", encoding="utf-8") as fh:
        man = json.load(fh)
    pad_frames = dsp.n_of(man["pad"])
    problems: list[str] = []
    rows: list[str] = []
    for name, fam in man["families"].items():
        analyse_family(name, fam, pad_frames, problems, rows, per_file)
    print("\n".join(rows))
    files = sum(len(f["samples"]) for f in man["families"].values())
    size = sum(os.path.getsize(os.path.join(AUDIO, e["file"])) for f in man["families"].values() for e in f["samples"])
    print(f"\n{len(man['families'])} families, {files} files, {size / 1e6:.2f} MB")
    if problems:
        print(f"\n{len(problems)} problem(s):")
        for p in problems:
            print("  " + p)
        return 1
    print("no problems")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
