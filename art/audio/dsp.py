"""Small offline DSP toolkit for the OVERDUB sample generators (numpy / scipy only).

Everything is deterministic: noise comes from seeded generators, so re-running the generators
rebuilds byte-identical .wav files.

Conventions: signals are float64 numpy arrays at SR (44.1 kHz) unless a function says otherwise;
oscillators that would alias are synthesised at 2x SR (OS_SR) and decimated with `decimate2`.
"""
from __future__ import annotations

import math

import numpy as np
from scipy import signal

SR = 44100
OS = 2
OS_SR = SR * OS


def midi_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def db(x: float) -> float:
    return 20.0 * math.log10(max(1e-12, x))


def undb(d: float) -> float:
    return 10.0 ** (d / 20.0)


def n_of(seconds: float, sr: int = SR) -> int:
    return max(1, int(round(seconds * sr)))


def times(n: int, sr: int = SR) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / sr


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


# ───────────────────────────── envelopes ─────────────────────────────


def exp_glide(n: int, a: float, b: float, seconds: float, sr: int = SR) -> np.ndarray:
    """Exponential move from a to b over `seconds`, then holds b (a, b > 0)."""
    t = times(n, sr)
    k = np.clip(t / max(1e-6, seconds), 0.0, 1.0)
    return a * (b / a) ** k


def lin_glide(n: int, a: float, b: float, seconds: float, sr: int = SR) -> np.ndarray:
    t = times(n, sr)
    k = np.clip(t / max(1e-6, seconds), 0.0, 1.0)
    return a + (b - a) * k


def adsr(n: int, attack: float, decay: float, sustain: float, sr: int = SR, curve: float = 4.0) -> np.ndarray:
    """Attack (raised-cosine) then exponential-ish decay to `sustain`, held to the end."""
    t = times(n, sr)
    env = np.empty(n)
    a = t < attack
    env[a] = 0.5 - 0.5 * np.cos(np.pi * t[a] / max(1e-6, attack))
    r = ~a
    td = (t[r] - attack) / max(1e-6, decay)
    env[r] = sustain + (1.0 - sustain) * np.exp(-curve * td)
    return env


def perc(n: int, attack: float, t60: float, sr: int = SR) -> np.ndarray:
    """Percussive envelope: short raised-cosine attack, exponential decay reaching -60 dB at t60."""
    t = times(n, sr)
    env = np.exp(-6.907755 * np.maximum(0.0, t - attack) / max(1e-6, t60))
    a = t < attack
    env[a] = 0.5 - 0.5 * np.cos(np.pi * t[a] / max(1e-6, attack))
    return env


def swell(n: int, rise: float, cut: float, sr: int = SR) -> np.ndarray:
    """Reverse-style swell: rises exponentially for `rise` seconds, then cuts off over `cut`."""
    t = times(n, sr)
    env = np.zeros(n)
    up = t < rise
    env[up] = (np.exp(4.0 * t[up] / rise) - 1.0) / (math.e ** 4 - 1.0)
    down = (t >= rise) & (t < rise + cut)
    env[down] = 0.5 + 0.5 * np.cos(np.pi * (t[down] - rise) / cut)
    return env


def fade_out(x: np.ndarray, seconds: float = 0.01) -> np.ndarray:
    m = min(len(x), n_of(seconds))
    if m > 1:
        x[-m:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, m))
    return x


def fade_in(x: np.ndarray, seconds: float = 0.001) -> np.ndarray:
    m = min(len(x), n_of(seconds))
    if m > 1:
        x[:m] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, m))
    return x


# ───────────────────────────── oscillators (run at OS_SR) ─────────────────────────────


def phase_of(freq: np.ndarray | float, n: int, sr: int = OS_SR, start: float = 0.0) -> np.ndarray:
    """Phase in cycles (not wrapped) for a frequency curve."""
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    return start + np.concatenate(([0.0], np.cumsum(f[:-1]))) / sr


def _blep(t: np.ndarray, dt: np.ndarray) -> np.ndarray:
    out = np.zeros_like(t)
    a = t < dt
    x = t[a] / dt[a]
    out[a] = x + x - x * x - 1.0
    b = t > 1.0 - dt
    y = (t[b] - 1.0) / dt[b]
    out[b] = y * y + y + y + 1.0
    return out


def saw(phase: np.ndarray, freq: np.ndarray | float, sr: int = OS_SR) -> np.ndarray:
    """PolyBLEP sawtooth (-1..1) from a phase in cycles."""
    t = np.mod(phase, 1.0)
    dt = np.broadcast_to(np.asarray(freq, dtype=np.float64) / sr, t.shape).copy()
    return 2.0 * t - 1.0 - _blep(t, dt)


def square(phase: np.ndarray, freq: np.ndarray | float, sr: int = OS_SR, width: float = 0.5) -> np.ndarray:
    return 0.5 * (saw(phase, freq, sr) - saw(phase + width, freq, sr))


def triangle(phase: np.ndarray) -> np.ndarray:
    t = np.mod(phase, 1.0)
    return 1.0 - 4.0 * np.abs(t - 0.5)


def sine(phase: np.ndarray) -> np.ndarray:
    return np.sin(2.0 * np.pi * phase)


def decimate2(x: np.ndarray) -> np.ndarray:
    """OS_SR -> SR with a steep anti-alias filter."""
    return signal.resample_poly(x, 1, OS, window=("kaiser", 10.0))


# ───────────────────────────── filters ─────────────────────────────


def svf(x: np.ndarray, cutoff: np.ndarray | float, q: float, mode: str = "lp", sr: int = SR) -> np.ndarray:
    """Zavalishin TPT state-variable filter with per-sample cutoff (stable under fast sweeps)."""
    n = len(x)
    fc = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), (n,))
    g_arr = np.tan(np.pi * np.clip(fc, 10.0, sr * 0.45) / sr)
    k = 1.0 / max(0.05, q)
    xs = x.tolist()
    gs = g_arr.tolist()
    out = [0.0] * n
    ic1 = 0.0
    ic2 = 0.0
    want = {"lp": 0, "bp": 1, "hp": 2}[mode]
    for i in range(n):
        g = gs[i]
        a1 = 1.0 / (1.0 + g * (g + k))
        v3 = xs[i] - ic2
        v1 = a1 * ic1 + g * a1 * v3
        v2 = ic2 + g * v1
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if want == 0:
            out[i] = v2
        elif want == 1:
            out[i] = v1 * k
        else:
            out[i] = xs[i] - k * v1 - v2
    return np.asarray(out)


def butter(x: np.ndarray, kind: str, freq, order: int = 2, sr: int = SR) -> np.ndarray:
    sos = signal.butter(order, freq, btype=kind, fs=sr, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x: np.ndarray, hz: float, order: int = 2, sr: int = SR) -> np.ndarray:
    return butter(x, "lowpass", min(hz, sr * 0.45), order, sr)


def highpass(x: np.ndarray, hz: float, order: int = 2, sr: int = SR) -> np.ndarray:
    return butter(x, "highpass", hz, order, sr)


def bandpass(x: np.ndarray, lo: float, hi: float, order: int = 2, sr: int = SR) -> np.ndarray:
    return butter(x, "bandpass", [lo, min(hi, sr * 0.45)], order, sr)


def peaking(x: np.ndarray, hz: float, gain_db: float, q: float = 1.0, sr: int = SR) -> np.ndarray:
    """RBJ peaking EQ."""
    a = 10 ** (gain_db / 40.0)
    w = 2 * np.pi * hz / sr
    alpha = np.sin(w) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w), 1 - alpha * a]
    aa = [1 + alpha / a, -2 * np.cos(w), 1 - alpha / a]
    return signal.lfilter(np.array(b) / aa[0], np.array(aa) / aa[0], x)


def shelf_high(x: np.ndarray, hz: float, gain_db: float, sr: int = SR) -> np.ndarray:
    """RBJ high shelf, slope 1."""
    a = 10 ** (gain_db / 40.0)
    w = 2 * np.pi * hz / sr
    cw = np.cos(w)
    alpha = np.sin(w) / 2 * np.sqrt(2)
    b0 = a * ((a + 1) + (a - 1) * cw + 2 * np.sqrt(a) * alpha)
    b1 = -2 * a * ((a - 1) + (a + 1) * cw)
    b2 = a * ((a + 1) + (a - 1) * cw - 2 * np.sqrt(a) * alpha)
    a0 = (a + 1) - (a - 1) * cw + 2 * np.sqrt(a) * alpha
    a1 = 2 * ((a - 1) - (a + 1) * cw)
    a2 = (a + 1) - (a - 1) * cw - 2 * np.sqrt(a) * alpha
    return signal.lfilter([b0 / a0, b1 / a0, b2 / a0], [1, a1 / a0, a2 / a0], x)


def noise(n: int, seed: int) -> np.ndarray:
    return rng(seed).uniform(-1.0, 1.0, n)


def sweep_noise(n: int, f0: float, f1: float, seconds: float, q: float, seed: int, mode: str = "bp") -> np.ndarray:
    """White noise through a resonant SVF whose cutoff glides exponentially f0 -> f1."""
    return svf(noise(n, seed), exp_glide(n, f0, f1, seconds), q, mode)


# ───────────────────────────── character ─────────────────────────────


def tape(x: np.ndarray, drive: float = 1.2, tilt_hz: float = 14500.0) -> np.ndarray:
    """Gentle cassette colour: asymmetric tanh saturation (even harmonics) and a soft HF roll-off.

    Normalised so small signals pass at unity gain.
    """
    y = np.tanh(drive * (x + 0.04 * x * x)) / drive
    y = y - np.mean(y[: min(len(y), 64)]) * 0.0
    return lowpass(y, tilt_hz, 1)


def wow(x: np.ndarray, depth_cents: float = 3.0, rate: float = 0.55, flutter_cents: float = 0.8, seed: int = 0) -> np.ndarray:
    """Tiny tape pitch instability by resampling along a modulated read head."""
    n = len(x)
    t = times(n)
    ph = rng(seed).uniform(0, 2 * np.pi, 2)
    cents = depth_cents * np.sin(2 * np.pi * rate * t + ph[0]) + flutter_cents * np.sin(2 * np.pi * 7.1 * t + ph[1])
    ratio = 2.0 ** (cents / 1200.0)
    pos = np.concatenate(([0.0], np.cumsum(ratio[:-1])))
    pos = np.clip(pos, 0, n - 1)
    return np.interp(pos, np.arange(n), x)


def dc_block(x: np.ndarray) -> np.ndarray:
    return highpass(x, 18.0, 1)


def crossfade_loop(x: np.ndarray, loop_start: int, loop_end: int, xfade: int) -> np.ndarray:
    """Make [loop_start, loop_end) loop seamlessly: the last `xfade` samples before loop_end fade
    into the samples just before loop_start (equal power). Returns x truncated at loop_end."""
    y = x[:loop_end].copy()
    xfade = min(xfade, loop_start, loop_end - loop_start - 1)
    w = np.sin(0.5 * np.pi * np.linspace(0.0, 1.0, xfade))
    a = y[loop_end - xfade:loop_end]
    b = x[loop_start - xfade:loop_start]
    y[loop_end - xfade:loop_end] = a * np.cos(0.5 * np.pi * np.linspace(0.0, 1.0, xfade)) + b * w
    return y


# ───────────────────────────── analysis ─────────────────────────────


def peak(x: np.ndarray) -> float:
    return float(np.max(np.abs(x))) if len(x) else 0.0


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x * x))) if len(x) else 0.0


def windowed_rms(x: np.ndarray, start: float, seconds: float) -> float:
    a = n_of(start)
    return rms(x[a:a + n_of(seconds)])


def tail_seconds(x: np.ndarray, floor_db: float = -60.0) -> float:
    """Seconds from the start until the signal stays below `floor_db` relative to its peak."""
    p = peak(x)
    if p <= 0:
        return 0.0
    thr = p * undb(floor_db)
    idx = np.nonzero(np.abs(x) > thr)[0]
    return float(idx[-1] + 1) / SR if len(idx) else 0.0


def spectral_centroid(x: np.ndarray) -> float:
    if len(x) < 64:
        return 0.0
    w = x * np.hanning(len(x))
    mag = np.abs(np.fft.rfft(w))
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    s = np.sum(mag)
    return float(np.sum(f * mag) / s) if s > 0 else 0.0


def band_energy(x: np.ndarray, lo: float, hi: float) -> float:
    """Fraction of spectral energy in [lo, hi) Hz."""
    if len(x) < 64:
        return 0.0
    mag2 = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    tot = np.sum(mag2)
    return float(np.sum(mag2[(f >= lo) & (f < hi)]) / tot) if tot > 0 else 0.0
