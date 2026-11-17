"""Numeric mix check for a recording made by tools/audio_mix_check.gd.

    python -I art/audio/mix_check.py [<dir>]     (default %TEMP%/overdub_mix)

Per bus (fader and duck gains applied, as heard): integrated loudness (ITU-R BS.1770-4: K-weighting,
400 ms blocks, absolute -70 LUFS and relative -10 LU gates), short-term maximum, sample and true peak
(4x oversampled). On the master: headroom and clipped samples. Under every speech window: the speech
band (300 Hz - 4 kHz) energy of the Voice bus against the Music and SFX buses, i.e. how far dialogue
stands above everything else where intelligibility lives.

Exit 0 when every check passes. Targets (docs: the lead's mix brief):
    master integrated  -20 .. -14 LUFS        master true peak  <= -1.0 dBTP, no clipped samples
    speech band, voice over music + sfx while speaking  >= +6 dB (median over speech windows)
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from scipy.io import wavfile
from scipy import signal

BUSES = ["master", "music", "sfx", "ui", "voice"]
TARGET_MASTER = (-20.0, -14.0)
TARGET_TP = -1.0
TARGET_SPEECH_SNR = 6.0


def kweight(x: np.ndarray, fs: int) -> np.ndarray:
    """BS.1770 K-weighting (shelf + RLB high-pass), designed at fs (pyloudnorm's coefficients)."""
    G, Q, fc = 3.999843853973347, 0.7071752369554196, 1681.974450955533
    A = 10 ** (G / 40.0)
    w0 = 2.0 * math.pi * fc / fs
    alpha = math.sin(w0) / (2.0 * Q)
    c = math.cos(w0)
    b = [A * ((A + 1) + (A - 1) * c + 2 * math.sqrt(A) * alpha), -2 * A * ((A - 1) + (A + 1) * c),
         A * ((A + 1) + (A - 1) * c - 2 * math.sqrt(A) * alpha)]
    a = [(A + 1) - (A - 1) * c + 2 * math.sqrt(A) * alpha, 2 * ((A - 1) - (A + 1) * c),
         (A + 1) - (A - 1) * c - 2 * math.sqrt(A) * alpha]
    y = signal.lfilter(b, a, x, axis=0)
    Q2, fc2 = 0.5003270373238773, 38.13547087602444
    w0 = 2.0 * math.pi * fc2 / fs
    alpha = math.sin(w0) / (2.0 * Q2)
    c = math.cos(w0)
    b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    a = [1 + alpha, -2 * c, 1 - alpha]
    return signal.lfilter(b, a, y, axis=0)


def block_loudness(x: np.ndarray, fs: int, block: float = 0.4, overlap: float = 0.75) -> np.ndarray:
    y = kweight(x, fs)
    n = int(block * fs)
    hop = max(1, int(n * (1 - overlap)))
    out = []
    for s in range(0, max(0, len(y) - n) + 1, hop):
        ms = np.mean(y[s:s + n] ** 2, axis=0).sum()
        out.append(-0.691 + 10 * math.log10(ms) if ms > 0 else -200.0)
    return np.array(out)


def integrated(x: np.ndarray, fs: int) -> float:
    lb = block_loudness(x, fs)
    lb = lb[lb > -70.0]
    if lb.size == 0:
        return -200.0
    rel = 10 * math.log10(np.mean(10 ** (lb / 10.0))) - 10.0
    g = lb[lb > rel]
    return 10 * math.log10(np.mean(10 ** (g / 10.0))) if g.size else -200.0


def short_term_max(x: np.ndarray, fs: int) -> float:
    lb = block_loudness(x, fs, 3.0, 0.9)
    return float(lb.max()) if lb.size else -200.0


def true_peak(x: np.ndarray) -> float:
    up = signal.resample_poly(x, 4, 1, axis=0)
    p = float(np.max(np.abs(up))) if up.size else 0.0
    return 20 * math.log10(p) if p > 0 else -200.0


def dbfs(v: float) -> float:
    return 20 * math.log10(v) if v > 0 else -200.0


def band_energy(x: np.ndarray, fs: int, lo: float = 300.0, hi: float = 4000.0) -> float:
    sos = signal.butter(4, [lo, hi], btype="band", fs=fs, output="sos")
    y = signal.sosfilt(sos, x.mean(axis=1))
    return float(np.mean(y ** 2)) if y.size else 0.0


def apply_gains(x: np.ndarray, bus: str, gains: list, master_len: int) -> np.ndarray:
    """Fader and duck gains logged per frame (index into the master capture), interpolated."""
    if not gains:
        return x
    idx = np.array([g[0] for g in gains], dtype=float) * (len(x) / max(1, master_len))
    val = np.array([float(g[1].get(bus.capitalize() if bus != "ui" else "Ui", 1.0)) for g in gains])
    t = np.arange(len(x), dtype=float)
    return x * np.interp(t, idx, val)[:, None]


def main(argv: list[str]) -> int:
    d = argv[0] if argv else os.path.join(os.environ.get("TEMP", "."), "overdub_mix")
    meta = json.load(open(os.path.join(d, "mix.json"), encoding="utf-8"))
    fs = int(meta["rate"])
    raw = {}
    for b in BUSES:
        sr, x = wavfile.read(os.path.join(d, f"{b}.wav"))
        raw[b] = x.astype(np.float64) / 32768.0
    master_len = len(raw["master"])
    heard = {b: apply_gains(raw[b], b, meta["gains"], master_len) for b in BUSES if b != "master"}
    # The master capture sits before the master fader; the output is that times the fader.
    heard["master"] = apply_gains(raw["master"], "master", meta["gains"], master_len)
    # Duplicate-frame check: a capture running at twice the rate would repeat every sample.
    m = raw["master"][:, 0]
    dup = float(np.mean(m[1::2][: len(m) // 2] == m[0::2][: len(m) // 2])) if len(m) > 2 else 0.0
    print(f"level {meta['level']}  {meta['bpm']} bpm  {meta['bars']} bars  capture {fs} Hz (measured {meta['measuredRate']:.0f},"
          f" mix rate {meta['mixRate']}), {meta['elapsed']:.1f} s, {meta['events']} events, duplicate-pair ratio {dup:.3f}")
    print(f"voices fired {meta['voices']['fired']}, dropped {meta['voices']['dropped']}, stolen {meta['voices']['stolen']}")
    print()
    print(f"{'bus':8s} {'integrated':>11s} {'short-term max':>15s} {'sample peak':>12s} {'true peak':>10s}")
    rows = {}
    for b in BUSES:
        x = heard[b]
        il = integrated(x, fs)
        rows[b] = il
        print(f"{b:8s} {il:8.1f} LUFS {short_term_max(x, fs):10.1f} LUFS {dbfs(float(np.max(np.abs(x)))):9.1f} dB {true_peak(x):7.1f} dBTP")
    pre = raw["master"]
    clipped = int(np.sum(np.abs(pre) >= 0.9999))
    tp_pre = true_peak(pre)
    tp_out = true_peak(heard["master"])
    print()
    print(f"master before its fader: true peak {tp_pre:.2f} dBTP (limiter ceiling -0.8), clipped samples {clipped}")
    print(f"master as heard: headroom {-tp_out:.2f} dB to 0 dBTP")
    snrs = []
    print()
    print("speech windows (speech band 300 Hz - 4 kHz, voice vs music + sfx as heard):")
    for (t0, t1, kind, ident) in meta["speech"]:
        a, b2 = int(t0 * fs), int(t1 * fs)
        if b2 <= a:
            continue
        ev = band_energy(heard["voice"][a:b2], fs)
        em = band_energy(heard["music"][a:b2], fs)
        es = band_energy(heard["sfx"][a:b2], fs)
        snr = 10 * math.log10(ev / max(1e-12, em + es)) if ev > 0 else -200.0
        snr_m = 10 * math.log10(ev / max(1e-12, em)) if ev > 0 else -200.0
        lm = integrated(heard["music"][a:b2], fs)
        lv = integrated(heard["voice"][a:b2], fs)
        snrs.append(snr)
        print(f"  {kind:4s} {ident:28s} {t0:6.2f}-{t1:6.2f} s  voice {lv:6.1f} LUFS  music {lm:6.1f} LUFS  "
              f"band SNR vs music {snr_m:+5.1f} dB, vs music+sfx {snr:+5.1f} dB")
    ok = True
    problems = []
    if not (TARGET_MASTER[0] <= rows["master"] <= TARGET_MASTER[1]):
        problems.append(f"master integrated {rows['master']:.1f} LUFS outside {TARGET_MASTER}")
    if tp_out > TARGET_TP:
        problems.append(f"master true peak {tp_out:.2f} dBTP above {TARGET_TP}")
    if clipped:
        problems.append(f"{clipped} clipped samples")
    if snrs and float(np.median(snrs)) < TARGET_SPEECH_SNR:
        problems.append(f"speech band SNR median {np.median(snrs):.1f} dB below {TARGET_SPEECH_SNR}")
    if meta.get("errors"):
        problems.append(f"tool errors {meta['errors']}")
    print()
    if problems:
        ok = False
        for p in problems:
            print("PROBLEM:", p)
    print("mix check:", "OK" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
