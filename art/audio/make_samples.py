"""Builds every OVERDUB audio sample into assets/audio/ and writes assets/audio/manifest.json.

    python -I art/audio/make_samples.py            rebuild everything
    python -I art/audio/make_samples.py bass lead  rebuild only the named families

Sound brief: a warm lo-fi cassette character, clean and elegant: nothing harsh, nothing muddy.
Instruments are multi-sampled every 4 semitones (pitch shifts stay within +/-2 semitones); blip
and pitched SFX families every 6 semitones or at two roots a tritone apart (shifts within +/-3).

File contract (read by audio/audio_sample_bank.gd):
  * 16-bit PCM mono 44.1 kHz.
  * Every file starts with PAD seconds of exact digital silence. The runtime starts a voice at the
    next audio mix and seeks `PAD - delay` into the file, which places the attack within a sample
    of its intended time even though Godot can only start sounds on mix boundaries.
  * Looping families carry loop points (frames, pad included) in the manifest; the loop region is
    crossfaded so the sustain loops without a click.
  * Each family is RMS-matched across its members and then scaled so its loudest member peaks at
    PEAK_DBFS. Relative mix levels are applied at runtime (audio/audio_cues.gd).
"""
from __future__ import annotations

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402
from scipy.io import wavfile  # noqa: E402

import dsp  # noqa: E402
from dsp import SR, OS_SR  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio")
PAD = 0.1
PEAK_DBFS = -1.0


# ───────────────────────────── family registry ─────────────────────────────

FAMILIES: dict[str, dict] = {}


def family(name: str, *, roots=None, variants: int = 1, folder: str, loop: bool = False, release: float = 0.08,
           rms_window: float = 0.3, desc: str = ""):
    """Registers a sample family. The decorated function renders one member:
    pitched families get `(root_midi, freq_hz, index)`, unpitched ones `(variant_index)`.
    It returns a float array at SR, or (array, loop_start_s, loop_end_s, xfade_s)."""

    def deco(fn):
        FAMILIES[name] = dict(fn=fn, roots=list(roots) if roots is not None else None, variants=variants,
                              folder=folder, loop=loop, release=release, rms_window=rms_window, desc=desc)
        return fn

    return deco


# ───────────────────────────── helpers ─────────────────────────────


def osc_mix(n_out: int, parts) -> np.ndarray:
    """Renders oscillator parts at OS_SR and decimates. parts: list of (kind, freq_curve_or_hz, gain, cents)."""
    n = n_out * dsp.OS
    acc = np.zeros(n)
    for kind, freq, gain, cents in parts:
        f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,)) * 2.0 ** (cents / 1200.0) if np.ndim(freq) == 0 else \
            np.repeat(np.asarray(freq, dtype=np.float64), dsp.OS)[:n] * 2.0 ** (cents / 1200.0)
        ph = dsp.phase_of(f, n)
        if kind == "saw":
            w = dsp.saw(ph, f)
        elif kind == "square":
            w = dsp.square(ph, f)
        elif kind == "tri":
            w = dsp.triangle(ph)
        else:
            w = dsp.sine(ph)
        acc += gain * w
    return dsp.decimate2(acc)[:n_out]


def keytrack(f: float, ref: float, amount: float) -> float:
    return (f / ref) ** amount


def strike(n: int, seed: int, hp: float = 2500.0, seconds: float = 0.012, gain: float = 1.0, lp: float = 7500.0) -> np.ndarray:
    """A short noise tick, band-limited so clicks read as wood/plastic rather than a digital spike."""
    x = dsp.lowpass(dsp.highpass(dsp.noise(n, seed), hp, 2), max(lp, hp * 1.6), 2) * dsp.perc(n, 0.0005, seconds)
    return gain * x


def thump(n: int, f0: float, f1: float, glide: float, t60: float, gain: float = 1.0) -> np.ndarray:
    f = dsp.exp_glide(n, f0, f1, glide)
    return gain * osc_mix(n, [("sine", f, 1.0, 0.0)]) * dsp.perc(n, 0.001, t60)


def grains(n: int, seed: int, count: int, spread: float, lo: float, hi: float, decay: float) -> np.ndarray:
    """Sparse little noise clicks (debris, sparkle) with falling density."""
    r = dsp.rng(seed)
    out = np.zeros(n)
    for _ in range(count):
        at = int((r.random() ** 1.8) * spread * SR)
        ln = int(r.uniform(0.004, 0.018) * SR)
        if at + ln >= n:
            continue
        g = r.uniform(0.3, 1.0) * math.exp(-at / SR / decay)
        seg = dsp.bandpass(r.uniform(-1, 1, ln), lo, hi, 2) * dsp.perc(ln, 0.0005, ln / SR)
        out[at:at + ln] += g * seg
    return out


# ───────────────────────────── instruments ─────────────────────────────


@family("bass", roots=range(24, 73, 4), folder="inst", loop=True, release=0.09, rms_window=0.5,
        desc="Round subtractive bass: saw + square sub through a plucked resonant low-pass, sine core.")
def bass(root: int, f: float, i: int):
    dur = 2.6
    n = dsp.n_of(dur)
    kt = keytrack(f, 55.0, 0.4)
    body = osc_mix(n, [("saw", f, 0.55, 0.0), ("square", f / 2, 0.30, 0.0)])
    cut = dsp.exp_glide(n, 1650.0 * kt, 360.0 * kt, 0.22)
    lp = dsp.svf(body, cut, 1.5)
    lp = dsp.lowpass(lp, 2400.0, 2)
    core = osc_mix(n, [("sine", f, 0.5, 0.0)])
    x = (lp + core) * dsp.adsr(n, 0.004, 0.18, 0.68)
    x = dsp.tape(x * 0.9, 1.5, 9000.0)
    return x, 1.05, 2.45, 0.3


@family("lead", roots=range(40, 101, 4), folder="inst", loop=True, release=0.16, rms_window=0.4,
        desc="Plucky lead: detuned saw + triangle into a resonant low-pass that snaps shut.")
def lead(root: int, f: float, i: int):
    dur = 2.3
    n = dsp.n_of(dur)
    body = osc_mix(n, [("saw", f, 0.42, -6.0), ("tri", f, 0.5, 5.0)])
    start = min(3600.0 * keytrack(max(f, 220.0), 220.0, 0.5), 11000.0)
    end = max(700.0, 2.4 * f)
    lp = dsp.svf(body, dsp.exp_glide(n, start, end, 0.18), 1.35)
    air = osc_mix(n, [("sine", 2 * f, 0.05, 0.0)])
    x = (lp + air) * dsp.adsr(n, 0.003, 0.22, 0.2)
    x = dsp.tape(dsp.wow(x, 2.0, 0.5, 0.6, seed=root), 1.2, 13000.0)
    return x, 1.2, 2.2, 0.35


def _keys_osc(n: int, f: float, cutoff: float, fm: bool) -> np.ndarray:
    parts = [("sine", f, 0.5, 0.0), ("tri", 2 * f, 0.12, 0.0)]
    warm = osc_mix(n, parts)
    saws = osc_mix(n, [("saw", f, 0.12, -7.0), ("saw", f, 0.12, 7.0)])
    saws = dsp.lowpass(saws, min(cutoff * keytrack(f, 220.0, 0.35), 7000.0), 2)
    x = warm + saws
    if fm:
        # A soft electric-piano bark on the attack: sine FM with a fast-decaying index.
        nn = n * dsp.OS
        t = dsp.times(nn, OS_SR)
        idx = 1.1 * np.exp(-t / 0.05)
        car = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
        x = x + 0.18 * dsp.decimate2(car)[:n] * np.exp(-dsp.times(n) / 0.25)
    return x


@family("keys", roots=range(36, 97, 4), folder="inst", release=0.4, rms_window=0.4,
        desc="Warm keys: sine + soft octave + detuned saws, gentle EP bark, natural decay.")
def keys(root: int, f: float, i: int):
    dur = 3.4
    n = dsp.n_of(dur)
    x = _keys_osc(n, f, 2200.0, True)
    env = dsp.adsr(n, 0.012, 0.45, 0.42) * np.exp(-dsp.times(n) / 2.4)
    x = dsp.lowpass(x, 8000.0, 2)
    x = dsp.tape(dsp.wow(x * env, 3.0, 0.45, 0.8, seed=100 + root), 1.15, 12500.0)
    return dsp.fade_out(x, 0.35)


@family("pad", roots=range(36, 97, 4), folder="inst", loop=True, release=0.7, rms_window=1.0,
        desc="Pad: the keys oscillators with a slow swell and a looped sustain.")
def pad(root: int, f: float, i: int):
    dur = 4.2
    n = dsp.n_of(dur)
    x = _keys_osc(n, f, 1800.0, False)
    # A slow third saw pair breathes against the first for width without phasing.
    x += dsp.lowpass(osc_mix(n, [("saw", f, 0.06, -12.0), ("saw", f, 0.06, 11.0)]), 1600.0, 2)
    env = dsp.adsr(n, 0.12, 0.6, 0.75, curve=3.0)
    x = dsp.lowpass(x, 5500.0, 2)
    x = dsp.tape(dsp.wow(x * env, 3.5, 0.4, 0.8, seed=200 + root), 1.15, 11000.0)
    return x, 1.7, 4.0, 0.5


# ───────────────────────────── drum kit ─────────────────────────────


@family("kick", folder="drums", release=0.03, rms_window=0.15, desc="Round kick: pitch-swept sine, soft click.")
def kick(v: int):
    n = dsp.n_of(0.5)
    body = thump(n, 160.0, 46.0, 0.11, 0.42)
    click = strike(n, 11 + v, 3000.0, 0.008, 0.18)
    x = dsp.tape(0.95 * body + click, 1.6, 9000.0)
    return dsp.fade_out(x, 0.05)


@family("snare", variants=2, folder="drums", release=0.03, rms_window=0.15, desc="Snare: band-passed noise + falling tone.")
def snare(v: int):
    n = dsp.n_of(0.32)
    nz = dsp.bandpass(dsp.noise(n, 21 + v), 900.0, 5200.0, 2)
    nz = dsp.peaking(nz, 1900.0, 4.0, 0.8) * dsp.perc(n, 0.0008, 0.2)
    tone = osc_mix(n, [("tri", dsp.exp_glide(n, 205.0, 165.0, 0.08), 1.0, 0.0)]) * dsp.perc(n, 0.001, 0.11)
    x = dsp.tape(dsp.lowpass(0.55 * nz, 9000.0, 2) + 0.42 * tone, 1.3, 11000.0)
    return dsp.fade_out(x, 0.04)


@family("clap", variants=2, folder="drums", release=0.03, rms_window=0.12, desc="Clap: three noise bursts and a short tail.")
def clap(v: int):
    n = dsp.n_of(0.3)
    nz = dsp.bandpass(dsp.noise(n, 31 + v), 800.0, 2400.0, 2)
    t = dsp.times(n)
    env = np.zeros(n)
    for off in (0.0, 0.011, 0.022):
        env += np.where(t >= off, np.exp(-(t - off) / 0.004), 0.0) * 0.8
    env += np.where(t >= 0.03, np.exp(-(t - 0.03) / 0.06), 0.0)
    x = dsp.tape(nz * env * dsp.perc(n, 0.0005, 0.3), 1.2, 10000.0)
    return dsp.fade_out(x, 0.04)


def _hat(n: int, seed: int, t60: float) -> np.ndarray:
    nz = dsp.highpass(dsp.noise(n, seed), 7000.0, 2)
    # 808-style square cluster adds a metallic body; kept low so it never rings harshly.
    metal = osc_mix(n, [("square", hz, 0.08, 0.0) for hz in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0)])
    metal = dsp.bandpass(metal, 6000.0, 12000.0, 2)
    x = (0.8 * nz + 0.5 * metal) * dsp.perc(n, 0.0004, t60)
    # Lo-fi hats: the top octave is rolled off so they shimmer without hiss or bite.
    return dsp.lowpass(dsp.peaking(x, 8500.0, 2.0, 0.7), 10500.0, 2)


@family("hat_closed", variants=3, folder="drums", release=0.02, rms_window=0.05, desc="Closed hat.")
def hat_closed(v: int):
    n = dsp.n_of(0.12)
    return dsp.fade_out(_hat(n, 41 + v, 0.06), 0.02)


@family("hat_open", variants=2, folder="drums", release=0.05, rms_window=0.2, desc="Open hat.")
def hat_open(v: int):
    n = dsp.n_of(0.55)
    return dsp.fade_out(_hat(n, 51 + v, 0.42), 0.05)


@family("tom", folder="drums", release=0.03, rms_window=0.2, desc="Tom: swept sine with a stick tick.")
def tom(v: int):
    n = dsp.n_of(0.45)
    x = thump(n, 175.0, 104.0, 0.2, 0.36) + strike(n, 61, 2000.0, 0.006, 0.08)
    return dsp.fade_out(dsp.tape(x, 1.4, 9000.0), 0.05)


@family("rim", variants=2, folder="drums", release=0.02, rms_window=0.04, desc="Rim: triangle ping + band noise.")
def rim(v: int):
    n = dsp.n_of(0.1)
    ping = osc_mix(n, [("tri", 1750.0 + 12 * v, 1.0, 0.0)]) * dsp.perc(n, 0.0004, 0.04)
    nz = dsp.bandpass(dsp.noise(n, 71 + v), 1800.0, 3600.0, 2) * dsp.perc(n, 0.0004, 0.03)
    return dsp.fade_out(dsp.lowpass(0.6 * ping + 0.5 * nz, 9000.0, 2), 0.02)


@family("perc", folder="drums", release=0.03, rms_window=0.08, desc="Woody FM perc blip.")
def perc_(v: int):
    n = dsp.n_of(0.2)
    nn = n * dsp.OS
    t = dsp.times(nn, OS_SR)
    idx = (420.0 / 930.0) * np.exp(-t / 0.03) * 1.0 + 0.02
    car = np.sin(2 * np.pi * 620.0 * t + idx * 6.0 * np.sin(2 * np.pi * 930.0 * t))
    x = dsp.decimate2(car)[:n] * dsp.perc(n, 0.001, 0.12)
    return dsp.fade_out(x, 0.03)


# ───────────────────────────── blips (pitched building blocks) ─────────────────────────────

BLIP_ROOTS = range(36, 97, 6)


def _blip(f: float, kind: str, t60: float, length: float) -> np.ndarray:
    n = dsp.n_of(length)
    if kind == "square":
        x = osc_mix(n, [("square", f, 0.8, 0.0)])
        x = dsp.lowpass(x, min(6.0 * f, 5000.0), 2)
    elif kind == "tri":
        x = osc_mix(n, [("tri", f, 1.0, 0.0), ("sine", 2 * f, 0.06, 0.0)])
    else:
        # A sine with a faint, fast-decaying inharmonic partial: a soft bell.
        x = osc_mix(n, [("sine", f, 1.0, 0.0)]) + osc_mix(n, [("sine", 3.01 * f, 0.08, 0.0)]) * np.exp(-dsp.times(n) / 0.08)
    x = x * dsp.perc(n, 0.002, t60)
    return dsp.fade_out(dsp.lowpass(x, 12000.0, 1), 0.01)


for _kind in ("tri", "sine", "square"):
    def _short(root, f, i, _k=_kind):
        return _blip(f, _k, 0.14, 0.2)

    def _long(root, f, i, _k=_kind):
        return _blip(f, _k, 0.9, 1.0)

    family(f"blip_{_kind}_short", roots=BLIP_ROOTS, folder="blip", release=0.02, rms_window=0.05,
           desc=f"Short {_kind} blip (-60 dB at 0.14 s).")(_short)
    family(f"blip_{_kind}_long", roots=BLIP_ROOTS, folder="blip", release=0.05, rms_window=0.2,
           desc=f"Long {_kind} blip (-60 dB at 0.9 s).")(_long)


# ───────────────────────────── pitched SFX (two roots a tritone apart) ─────────────────────────────

PAIR = (60, 66)


def semis(f: float, s: float) -> float:
    return f * 2.0 ** (s / 12.0)


@family("break_tone", roots=(48, 54), folder="sfx", rms_window=0.1, desc="Break: sine falling an octave.")
def break_tone(root, f, i):
    n = dsp.n_of(0.45)
    return dsp.fade_out(osc_mix(n, [("sine", dsp.exp_glide(n, f, f / 2, 0.32), 1.0, 0.0)]) * dsp.perc(n, 0.002, 0.36), 0.03)


@family("clang", roots=PAIR, folder="sfx", rms_window=0.1, desc="Clang: inharmonic metal rooted on a chord tone.")
def clang(root, f, i):
    n = dsp.n_of(0.75)
    t = dsp.times(n)
    x = np.zeros(n)
    for ratio, lvl, t60 in ((1.0, 0.5, 0.6), (1.003, 0.18, 0.55), (2.76, 0.25, 0.4), (5.4, 0.12, 0.22), (8.93, 0.04, 0.1)):
        x += lvl * np.sin(2 * np.pi * f * ratio * t) * dsp.perc(n, 0.0008, t60)
    x += strike(n, 300 + i, 3000.0, 0.008, 0.25)
    return dsp.fade_out(dsp.lowpass(x, 11000.0, 2), 0.05)


@family("dodge_tone", roots=PAIR, folder="sfx", rms_window=0.08, desc="Dodge: sine rising a fourth.")
def dodge_tone(root, f, i):
    n = dsp.n_of(0.2)
    return dsp.fade_out(osc_mix(n, [("sine", dsp.exp_glide(n, f, semis(f, 5), 0.1), 1.0, 0.0)]) * dsp.perc(n, 0.006, 0.13), 0.02)


@family("shot_missile", roots=PAIR, folder="sfx", rms_window=0.2, desc="Missile launch: saw rising an octave, rumble.")
def shot_missile(root, f, i):
    n = dsp.n_of(0.45)
    tone = osc_mix(n, [("saw", dsp.exp_glide(n, f / 2, f, 0.3), 1.0, 0.0)])
    tone = dsp.svf(tone, dsp.exp_glide(n, 400.0, 1600.0, 0.3), 1.2)
    rumble = dsp.lowpass(dsp.noise(n, 401), 900.0, 2)
    x = (0.8 * tone + 0.6 * rumble) * dsp.adsr(n, 0.02, 0.25, 0.0)
    return dsp.fade_out(dsp.tape(x, 1.4, 9000.0), 0.06)


@family("shot_pierce", roots=PAIR, folder="sfx", rms_window=0.06, desc="Pierce: square diving an octave.")
def shot_pierce(root, f, i):
    n = dsp.n_of(0.16)
    x = osc_mix(n, [("square", dsp.exp_glide(n, 2 * f, f, 0.09), 0.9, 0.0)])
    x = dsp.lowpass(x, 4200.0, 2) * dsp.perc(n, 0.001, 0.1)
    return dsp.fade_out(x, 0.02)


@family("shot_phase", roots=PAIR, folder="sfx", rms_window=0.15, desc="Phase: detuned sine shimmer.")
def shot_phase(root, f, i):
    n = dsp.n_of(0.4)
    x = osc_mix(n, [("sine", 2 * f, 0.55, 0.0), ("sine", 2 * f, 0.45, 12.0), ("sine", 4 * f, 0.08, 5.0)])
    return dsp.fade_out(x * dsp.perc(n, 0.004, 0.3), 0.04)


@family("shot_arc", roots=PAIR, folder="sfx", rms_window=0.1, desc="Arc lob: triangle gliding up a fourth.")
def shot_arc(root, f, i):
    n = dsp.n_of(0.26)
    x = osc_mix(n, [("tri", dsp.exp_glide(n, f, semis(f, 5), 0.18), 1.0, 0.0)])
    return dsp.fade_out(x * dsp.perc(n, 0.003, 0.2), 0.03)


@family("shot_bolt", roots=PAIR, folder="sfx", rms_window=0.08, desc="Default shot: triangle falling a third.")
def shot_bolt(root, f, i):
    n = dsp.n_of(0.2)
    x = osc_mix(n, [("tri", dsp.exp_glide(n, semis(f, 4), f, 0.1), 1.0, 0.0)])
    x += strike(n, 410 + i, 3500.0, 0.006, 0.12)
    return dsp.fade_out(x * dsp.perc(n, 0.002, 0.14), 0.03)


@family("enemy_shot", roots=PAIR, folder="sfx", rms_window=0.08, desc="Enemy shot: square dropping a fifth.")
def enemy_shot(root, f, i):
    n = dsp.n_of(0.2)
    x = osc_mix(n, [("square", dsp.exp_glide(n, f, semis(f, -7), 0.12), 0.9, 0.0)])
    return dsp.fade_out(dsp.lowpass(x, 3000.0, 2) * dsp.perc(n, 0.002, 0.14), 0.03)


@family("enemy_shock", roots=PAIR, folder="sfx", rms_window=0.1, desc="Enemy shock: buzzing square with crackle.")
def enemy_shock(root, f, i):
    n = dsp.n_of(0.24)
    t = dsp.times(n)
    buzz = osc_mix(n, [("square", f, 0.7, 0.0), ("square", f, 0.5, 9.0)]) * (0.6 + 0.4 * np.sin(2 * np.pi * 31.0 * t))
    crackle = grains(n, 420 + i, 30, 0.2, 2000.0, 7000.0, 0.15)
    x = dsp.lowpass(buzz, 2600.0, 2) + 0.5 * crackle
    return dsp.fade_out(x * dsp.perc(n, 0.002, 0.2), 0.03)


@family("enemy_attack", roots=(48, 54), folder="sfx", rms_window=0.12, desc="Enemy strike: sine thud dropping an octave, low noise.")
def enemy_attack(root, f, i):
    n = dsp.n_of(0.32)
    tone = osc_mix(n, [("sine", dsp.exp_glide(n, f, f / 2, 0.2), 1.0, 0.0)]) * dsp.perc(n, 0.002, 0.22)
    nz = dsp.svf(dsp.noise(n, 430 + i), dsp.exp_glide(n, 1600.0, 200.0, 0.15), 0.9) * dsp.perc(n, 0.002, 0.16)
    return dsp.fade_out(dsp.tape(tone + 0.6 * nz, 1.4, 8000.0), 0.04)


@family("enemy_telegraph", roots=(48, 54), folder="sfx", rms_window=0.15, desc="Telegraph: square opening up, then cut.")
def enemy_telegraph(root, f, i):
    n = dsp.n_of(0.26)
    x = osc_mix(n, [("square", f, 0.8, 0.0)])
    x = dsp.svf(x, dsp.exp_glide(n, 300.0, 2200.0, 0.18), 2.0)
    env = dsp.swell(n, 0.16, 0.06)
    return dsp.fade_out(x * env, 0.02)


@family("enemy_stagger", roots=(48, 54), folder="sfx", rms_window=0.12, desc="Stagger: triangle with a dizzy vibrato.")
def enemy_stagger(root, f, i):
    n = dsp.n_of(0.36)
    t = dsp.times(n)
    freq = f * 2.0 ** (45.0 * np.sin(2 * np.pi * 11.0 * t) / 1200.0)
    x = osc_mix(n, [("tri", freq, 1.0, 0.0)]) * dsp.perc(n, 0.004, 0.32)
    return dsp.fade_out(x, 0.03)


@family("plate_thunk", roots=PAIR, folder="sfx", rms_window=0.08, desc="Plate: a low thunk an octave down.")
def plate_thunk(root, f, i):
    n = dsp.n_of(0.25)
    low = osc_mix(n, [("sine", dsp.exp_glide(n, f / 2, f / 4, 0.12), 1.0, 0.0)]) * dsp.perc(n, 0.001, 0.16)
    top = osc_mix(n, [("tri", f, 0.35, 0.0)]) * dsp.perc(n, 0.001, 0.12)
    return dsp.fade_out(dsp.tape(low + top + strike(n, 440, 1500.0, 0.01, 0.15), 1.3, 8000.0), 0.03)


@family("laser_on", roots=(48, 54), folder="sfx", rms_window=0.3, desc="Laser on: resonant saw + fifth, then a hum.")
def laser_on(root, f, i):
    n = dsp.n_of(0.6)
    t = dsp.times(n)
    x = osc_mix(n, [("saw", f, 0.7, 0.0), ("saw", semis(f, 7), 0.35, 9.0)])
    x = dsp.svf(x, dsp.exp_glide(n, 3200.0, 1100.0, 0.25), 2.5)
    env = np.minimum(1.0, t / 0.01) * (0.45 + 0.55 * np.exp(-t / 0.08)) * (1 + 0.08 * np.sin(2 * np.pi * 50 * t))
    return dsp.fade_out(x * env * np.minimum(1.0, (0.6 - t) / 0.25), 0.02)


@family("laser_off", roots=(48, 54), folder="sfx", rms_window=0.15, desc="Laser off: saw falling an octave, closing filter.")
def laser_off(root, f, i):
    n = dsp.n_of(0.3)
    x = osc_mix(n, [("saw", dsp.exp_glide(n, f, f / 2, 0.2), 0.7, 0.0), ("saw", dsp.exp_glide(n, semis(f, 7), semis(f, -5), 0.2), 0.3, 9.0)])
    x = dsp.svf(x, dsp.exp_glide(n, 1400.0, 300.0, 0.2), 2.0)
    return dsp.fade_out(x * dsp.perc(n, 0.005, 0.26), 0.03)


@family("tape_stop", roots=PAIR, folder="sfx", rms_window=0.15, desc="Self death: a tape-stop fall.")
def tape_stop(root, f, i):
    n = dsp.n_of(0.48)
    t = dsp.times(n)
    k = np.clip(t / 0.38, 0, 1) ** 1.7
    freq = f * 2.0 ** (-7.0 * k / 12.0)
    x = osc_mix(n, [("tri", freq, 0.8, 0.0), ("saw", freq, 0.25, 0.0)])
    x = dsp.svf(x, dsp.exp_glide(n, 3000.0, 400.0, 0.38), 0.9)
    return dsp.fade_out(x * dsp.adsr(n, 0.004, 0.42, 0.0, curve=3.0), 0.05)


@family("desync_glitch", roots=PAIR, folder="sfx", rms_window=0.2, desc="Desync: detuned wobbling voices with two tape dropouts.")
def desync_glitch(root, f, i):
    n = dsp.n_of(0.52)
    t = dsp.times(n)
    a = f * 2.0 ** ((-18.0 + 28.0 * np.sin(2 * np.pi * 6.5 * t)) / 1200.0)
    b = f * 2.0 ** ((22.0 + 28.0 * np.sin(2 * np.pi * 5.1 * t + 1.0)) / 1200.0)
    x = osc_mix(n, [("tri", a, 0.55, 0.0), ("tri", b, 0.55, 0.0)])
    gate = np.ones(n)
    for at, ln in ((0.09, 0.018), (0.2, 0.012)):
        m = (t >= at) & (t < at + ln)
        gate[m] = 0.15
    gate = dsp.lowpass(gate, 300.0, 1)
    x = x * gate * dsp.perc(n, 0.02, 0.48)
    return dsp.fade_out(dsp.lowpass(x, 5000.0, 2), 0.04)


@family("tape_turn", roots=PAIR, folder="sfx", rms_window=0.2, desc="Reverse tape turn: a swell that cuts off.")
def tape_turn(root, f, i):
    n = dsp.n_of(0.3)
    x = osc_mix(n, [("tri", f, 1.0, 0.0), ("sine", 2 * f, 0.1, 0.0)]) * dsp.swell(n, 0.22, 0.04)
    return dsp.fade_out(x, 0.02)


@family("tape_end", roots=(48, 54), folder="sfx", rms_window=0.2, desc="Tape end: winding down an octave, then a click.")
def tape_end(root, f, i):
    n = dsp.n_of(0.5)
    x = osc_mix(n, [("tri", dsp.exp_glide(n, f, f / 2, 0.4), 1.0, 0.0)]) * dsp.perc(n, 0.002, 0.42)
    click = np.zeros(n)
    at = dsp.n_of(0.38)
    click[at:] = strike(n - at, 450, 3000.0, 0.01, 0.4)
    return dsp.fade_out(x + click, 0.03)


@family("boss_drone", roots=(30, 36, 42, 48), folder="sfx", rms_window=0.5, desc="Boss phase: a big saw drone.")
def boss_drone(root, f, i):
    n = dsp.n_of(1.4)
    x = osc_mix(n, [("saw", f, 0.6, -5.0), ("saw", f, 0.6, 5.0), ("sine", f / 2 if f > 40 else f, 0.5, 0.0)])
    x = dsp.svf(x, dsp.exp_glide(n, 250.0, 2600.0, 0.9), 1.3)
    x = dsp.tape(x * dsp.adsr(n, 0.03, 0.9, 0.35) * np.exp(-dsp.times(n) / 0.9), 1.5, 9000.0)
    return dsp.fade_out(x, 0.2)


@family("reverse_swell", roots=PAIR, folder="sfx", rms_window=0.2, desc="Boss recall: remembered tones played backwards.")
def reverse_swell(root, f, i):
    n = dsp.n_of(0.4)
    x = osc_mix(n, [("sine", f, 0.75, 0.0), ("tri", f, 0.3, 6.0)]) * dsp.swell(n, 0.3, 0.04)
    return dsp.fade_out(x, 0.02)


@family("ui_glide", roots=PAIR, folder="ui", rms_window=0.1, desc="UI speed change: triangle gliding up a fifth.")
def ui_glide(root, f, i):
    n = dsp.n_of(0.2)
    x = osc_mix(n, [("tri", dsp.exp_glide(n, f, semis(f, 7), 0.12), 1.0, 0.0)]) * dsp.perc(n, 0.01, 0.16)
    return dsp.fade_out(x, 0.02)


@family("fail_thud", roots=(48, 54), folder="sfx", rms_window=0.08, desc="Interact fail: soft sine dipping a tone.")
def fail_thud(root, f, i):
    n = dsp.n_of(0.16)
    x = osc_mix(n, [("sine", dsp.exp_glide(n, f, semis(f, -2), 0.08), 1.0, 0.0)]) * dsp.perc(n, 0.003, 0.1)
    return dsp.fade_out(x, 0.02)


# ───────────────────────────── unpitched SFX ─────────────────────────────


def whoosh(n: int, f0: float, f1: float, glide: float, q: float, attack: float, dur: float, seed: int) -> np.ndarray:
    x = dsp.sweep_noise(n, f0, f1, glide, q, seed)
    t = dsp.times(n)
    env = np.where(t < attack, 0.5 - 0.5 * np.cos(np.pi * t / attack), np.exp(-5.0 * np.maximum(0.0, t - attack) / max(1e-3, dur - attack)))
    return x * env


@family("whoosh_light", variants=2, folder="sfx", rms_window=0.1, desc="Light swing whoosh.")
def whoosh_light(v):
    n = dsp.n_of(0.16)
    x = whoosh(n, 1400.0, 4200.0, 0.09, 1.1, 0.03, 0.12, 500 + v) + 0.4 * whoosh(n, 600.0, 1500.0, 0.09, 0.7, 0.03, 0.1, 510 + v)
    return dsp.fade_out(x, 0.02)


@family("whoosh_heavy", variants=2, folder="sfx", rms_window=0.15, desc="Heavy swing whoosh.")
def whoosh_heavy(v):
    n = dsp.n_of(0.26)
    x = whoosh(n, 500.0, 1800.0, 0.16, 1.1, 0.05, 0.22, 520 + v) + 0.5 * whoosh(n, 220.0, 600.0, 0.16, 0.8, 0.05, 0.2, 530 + v)
    return dsp.fade_out(dsp.tape(x, 1.2, 9000.0), 0.03)


@family("impact_light", variants=2, folder="sfx", rms_window=0.05, desc="Light impact: crack + small thump.")
def impact_light(v):
    n = dsp.n_of(0.14)
    crack = dsp.sweep_noise(n, 3000.0, 1200.0, 0.05, 0.8, 540 + v, "hp") * dsp.perc(n, 0.0005, 0.05)
    x = 0.8 * crack + thump(n, 190.0, 95.0, 0.05, 0.07, 0.6)
    return dsp.fade_out(dsp.tape(x, 1.3, 11000.0), 0.02)


@family("impact_medium", variants=2, folder="sfx", rms_window=0.08, desc="Medium impact: band crack + thump.")
def impact_medium(v):
    n = dsp.n_of(0.22)
    crack = dsp.bandpass(dsp.noise(n, 550 + v), 1200.0, 4000.0, 2) * dsp.perc(n, 0.0005, 0.08)
    x = 0.7 * crack + thump(n, 150.0, 62.0, 0.1, 0.14, 0.8)
    return dsp.fade_out(dsp.tape(x, 1.5, 10000.0), 0.03)


@family("impact_heavy", variants=2, folder="sfx", rms_window=0.12, desc="Heavy impact: deep thump + crunch.")
def impact_heavy(v):
    n = dsp.n_of(0.4)
    crunch = dsp.svf(dsp.noise(n, 560 + v), dsp.exp_glide(n, 3000.0, 400.0, 0.2), 0.8) * dsp.perc(n, 0.0005, 0.22)
    x = thump(n, 115.0, 40.0, 0.22, 0.3, 1.0) + 0.6 * crunch + grains(n, 570 + v, 10, 0.12, 1500.0, 5000.0, 0.08) * 0.3
    return dsp.fade_out(dsp.tape(x, 1.8, 8000.0), 0.04)


@family("impact_small", variants=2, folder="sfx", rms_window=0.04, desc="Projectile hit crack.")
def impact_small(v):
    n = dsp.n_of(0.09)
    x = dsp.sweep_noise(n, 2000.0, 900.0, 0.05, 1.2, 580 + v) * dsp.perc(n, 0.0005, 0.06)
    return dsp.fade_out(x, 0.01)


@family("kill_pop", folder="sfx", rms_window=0.1, desc="Kill: a bright pop sweeping down.")
def kill_pop(v):
    n = dsp.n_of(0.24)
    x = dsp.sweep_noise(n, 2400.0, 600.0, 0.18, 1.0, 590) * dsp.perc(n, 0.001, 0.2) + strike(n, 591, 2500.0, 0.006, 0.4)
    return dsp.fade_out(x, 0.02)


@family("break_crumble", variants=2, folder="sfx", rms_window=0.2, desc="Breakable wall: crumble and debris.")
def break_crumble(v):
    n = dsp.n_of(0.7)
    body = dsp.svf(dsp.noise(n, 600 + v), dsp.exp_glide(n, 2600.0, 160.0, 0.45), 0.8) * dsp.perc(n, 0.002, 0.5)
    x = body + 0.45 * grains(n, 610 + v, 45, 0.5, 800.0, 4500.0, 0.25) + thump(n, 90.0, 40.0, 0.2, 0.3, 0.6)
    return dsp.fade_out(dsp.tape(x, 1.6, 8000.0), 0.06)


@family("dodge_swish", variants=2, folder="sfx", rms_window=0.1, desc="Dodge swish.")
def dodge_swish(v):
    n = dsp.n_of(0.18)
    return dsp.fade_out(whoosh(n, 800.0, 3600.0, 0.14, 2.0, 0.04, 0.14, 620 + v), 0.02)


@family("step", variants=3, folder="sfx", rms_window=0.03, desc="Footstep scuff.")
def step(v):
    n = dsp.n_of(0.06)
    x = dsp.sweep_noise(n, 1800.0, 900.0, 0.03, 1.5, 630 + v) * dsp.perc(n, 0.002, 0.035)
    return dsp.fade_out(x + thump(n, 120.0, 80.0, 0.02, 0.03, 0.15), 0.01)


@family("transient", variants=2, folder="sfx", rms_window=0.012, desc="Immediate soft transient ahead of a quantised impact.")
def transient(v):
    n = dsp.n_of(0.03)
    x = dsp.lowpass(dsp.sweep_noise(n, 2500.0, 1800.0, 0.012, 0.7, 640 + v, "hp"), 7000.0, 2) * dsp.perc(n, 0.0005, 0.014)
    return dsp.fade_out(x, 0.005)


@family("switch_click", folder="sfx", rms_window=0.03, desc="Switch lever: two mechanical clicks.")
def switch_click(v):
    n = dsp.n_of(0.08)
    x = strike(n, 650, 3500.0, 0.012, 1.0)
    at = dsp.n_of(0.026)
    x[at:] += strike(n - at, 651, 2200.0, 0.01, 0.6)
    return dsp.fade_out(x, 0.01)


def _door(n: int, f0: float, f1: float, seed: int) -> np.ndarray:
    t = dsp.times(n)
    slide = dsp.sweep_noise(n, f0, f1, 0.5, 1.5, seed, "lp")
    motor = dsp.lowpass(osc_mix(n, [("saw", dsp.lin_glide(n, 48.0, 62.0, 0.5), 0.5, 0.0)]), 400.0, 2)
    env = np.minimum(1.0, t / 0.05) * np.clip((0.55 - t) / 0.12, 0.0, 1.0)
    latch = np.zeros(n)
    at = dsp.n_of(0.52)
    latch[at:] = strike(n - at, seed + 1, 1200.0, 0.02, 0.7) + thump(n - at, 140.0, 70.0, 0.03, 0.06, 0.6)
    return dsp.tape((0.8 * slide + 0.35 * motor) * env + latch, 1.4, 8000.0)


@family("door_open", folder="sfx", rms_window=0.4, desc="Door sliding open, latch.")
def door_open(v):
    return dsp.fade_out(_door(dsp.n_of(0.68), 180.0, 700.0, 660), 0.04)


@family("door_close", folder="sfx", rms_window=0.4, desc="Door sliding shut, latch.")
def door_close(v):
    return dsp.fade_out(_door(dsp.n_of(0.68), 700.0, 160.0, 670), 0.04)


@family("core_swell", folder="sfx", rms_window=0.6, desc="Core activation: a rising shimmer.")
def core_swell(v):
    n = dsp.n_of(1.2)
    t = dsp.times(n)
    x = dsp.sweep_noise(n, 900.0, 6000.0, 0.7, 2.0, 680) * np.minimum(1.0, t / 0.5) * np.exp(-np.maximum(0, t - 0.5) / 0.25)
    x += 0.5 * grains(n, 681, 50, 1.0, 4000.0, 10000.0, 0.6)
    return dsp.fade_out(dsp.lowpass(x, 11000.0, 2), 0.1)


@family("death_sweep", folder="sfx", rms_window=0.3, desc="Self death: noise winding down.")
def death_sweep(v):
    n = dsp.n_of(0.65)
    return dsp.fade_out(dsp.svf(dsp.noise(n, 690), dsp.exp_glide(n, 1800.0, 120.0, 0.6), 1.2) * dsp.perc(n, 0.004, 0.6), 0.05)


@family("tape_wrap", folder="sfx", rms_window=0.1, desc="Repeat wrap: a quick rewind zip.")
def tape_wrap(v):
    n = dsp.n_of(0.16)
    return dsp.fade_out(whoosh(n, 900.0, 5200.0, 0.12, 3.0, 0.01, 0.12, 700) + strike(n, 701, 3000.0, 0.006, 0.2), 0.02)


@family("resync_lock", folder="sfx", rms_window=0.04, desc="Resync: a click-lock.")
def resync_lock(v):
    n = dsp.n_of(0.08)
    x = strike(n, 710, 2500.0, 0.008, 0.8)
    at = dsp.n_of(0.022)
    x[at:] += strike(n - at, 711, 4000.0, 0.006, 0.6)
    return dsp.fade_out(x, 0.01)


@family("objective_shimmer", folder="sfx", rms_window=0.5, desc="Objective complete: high sparkle.")
def objective_shimmer(v):
    n = dsp.n_of(0.9)
    x = 0.7 * grains(n, 720, 70, 0.8, 3000.0, 9000.0, 0.5) + 0.4 * dsp.bandpass(dsp.noise(n, 721), 4000.0, 9000.0, 2) * dsp.perc(n, 0.15, 0.7)
    return dsp.fade_out(x, 0.1)


@family("boss_riser", folder="sfx", rms_window=0.5, desc="Boss phase: filtered noise riser.")
def boss_riser(v):
    n = dsp.n_of(1.1)
    t = dsp.times(n)
    x = dsp.svf(dsp.noise(n, 730), dsp.exp_glide(n, 120.0, 3000.0, 0.9), 1.2)
    env = np.minimum(1.0, t / 0.3) * np.exp(-np.maximum(0.0, t - 0.6) / 0.15)
    return dsp.fade_out(x * env, 0.08)


@family("ui_click", folder="ui", rms_window=0.02, desc="UI click.")
def ui_click(v):
    n = dsp.n_of(0.04)
    x = dsp.lowpass(dsp.sweep_noise(n, 3000.0, 2000.0, 0.02, 0.7, 740, "hp"), 6500.0, 2)
    return dsp.fade_out(x * dsp.perc(n, 0.0005, 0.02), 0.005)


@family("ui_sweep", folder="ui", rms_window=0.15, desc="UI retry sweep.")
def ui_sweep(v):
    n = dsp.n_of(0.26)
    return dsp.fade_out(whoosh(n, 4200.0, 900.0, 0.22, 3.0, 0.01, 0.22, 750), 0.02)


@family("ui_sweep_long", folder="ui", rms_window=0.3, desc="UI reset sweep.")
def ui_sweep_long(v):
    n = dsp.n_of(0.5)
    return dsp.fade_out(whoosh(n, 5200.0, 500.0, 0.45, 3.0, 0.01, 0.45, 760), 0.03)


@family("tick_click", folder="ui", rms_window=0.015, desc="Count-in tick transient.")
def tick_click(v):
    n = dsp.n_of(0.03)
    x = dsp.bandpass(dsp.noise(n, 770), 2200.0, 3100.0, 2) * dsp.perc(n, 0.0005, 0.016)
    return dsp.fade_out(x, 0.005)


# ───────────────────────────── count-in voice ─────────────────────────────
#
# Godot has no speech synthesiser, so "five, six, seven, eight" are formant-synthesised:
# a glottal pulse train through three or four time-varying formant resonators, with noise
# fricatives and stop bursts. Each word is a short phoneme score: (phoneme, seconds). Vowel
# targets are interpolated so diphthongs glide. Pitch rises across the count and falls within a
# word, the way a count is spoken.

VOWELS = {
    # F1, F2, F3, F4 (Hz) — a light, neutral adult voice.
    "ah": (780, 1250, 2550, 3500),
    "ih": (420, 2050, 2700, 3600),
    "eh": (580, 1850, 2600, 3550),
    "ey": (480, 2000, 2650, 3600),
    "uh": (560, 1350, 2500, 3500),
    "n": (260, 1150, 2400, 3400),
    "v": (300, 1300, 2300, 3400),
}


def _glottal(n: int, f0: np.ndarray, seed: int) -> np.ndarray:
    """Band-limited glottal source: a sum of harmonics with a -12 dB/oct tilt and slight jitter."""
    t = dsp.times(n)
    ph = np.concatenate(([0.0], np.cumsum(f0[:-1]))) / SR
    jitter = dsp.lowpass(dsp.noise(n, seed), 30.0, 1) * 0.004
    ph = ph * (1.0 + jitter)
    out = np.zeros(n)
    for k in range(1, 40):
        amp = 1.0 / (k ** 1.15)
        mask = np.clip((5200.0 - k * f0) / 600.0, 0.0, 1.0)
        out += amp * mask * np.sin(2 * np.pi * k * ph)
    _ = t
    return out


def _formant_filter(src: np.ndarray, tracks: list[np.ndarray], bws=(80.0, 100.0, 140.0, 200.0), gains=(1.0, 0.7, 0.35, 0.18)) -> np.ndarray:
    out = np.zeros(len(src))
    for track, bw, g in zip(tracks, bws, gains):
        q = np.maximum(1.0, track / bw)
        # svf takes a scalar q; use the mean q of the track (formant Q varies little within a word).
        out += g * dsp.svf(src, track, float(np.mean(q)), "bp")
    return out


def _word(score: list[tuple[str, float]], f0_start: float, f0_end: float, seed: int) -> np.ndarray:
    total = sum(d for _, d in score)
    n = dsp.n_of(total)
    t = dsp.times(n)
    f0 = f0_start * (f0_end / f0_start) ** (t / total)
    voiced = np.zeros(n)
    fric = np.zeros(n)
    burst = np.zeros(n)
    tracks = [np.zeros(n) for _ in range(4)]
    # Build per-sample formant targets with smooth transitions between voiced segments.
    pos = 0
    keys = []
    for ph, d in score:
        m = dsp.n_of(d)
        seg = slice(pos, min(n, pos + m))
        if ph in VOWELS:
            keys.append((pos, ph))
            keys.append((pos + m - 1, ph))
            voiced[seg] = 1.0 if ph not in ("n", "v") else 0.55
            if ph == "v":
                fric[seg] = 0.35
        elif ph.startswith("~"):
            # A glide target: interpolate from the previous vowel into this one over the segment.
            v = ph[1:]
            keys.append((pos + m - 1, v))
            voiced[seg] = 1.0
        elif ph in ("f", "s"):
            fric[seg] = 1.0
        elif ph in ("k", "t"):
            b = min(n - pos, dsp.n_of(0.012))
            burst[pos:pos + b] = 1.0
        pos += m
    keys.sort()
    if not keys:
        keys = [(0, "uh"), (n - 1, "uh")]
    xs = [k for k, _ in keys]
    for j in range(4):
        ys = [VOWELS[v][j] for _, v in keys]
        tracks[j] = np.interp(np.arange(n), xs, ys)
    voiced = dsp.lowpass(voiced, 60.0, 2)
    fric = dsp.lowpass(fric, 80.0, 2)
    src = _glottal(n, f0, seed) * voiced + 0.04 * dsp.noise(n, seed + 1) * voiced
    vox = _formant_filter(src, tracks)
    # Fricatives: /s/ is high and narrow, /f/ and /v/ are broad and soft.
    hiss_s = dsp.bandpass(dsp.noise(n, seed + 2), 4800.0, 9000.0, 4)
    hiss_f = dsp.bandpass(dsp.noise(n, seed + 3), 1800.0, 6500.0, 2) * 0.35
    kinds = [ph for ph, _ in score]
    hiss = hiss_s if "s" in kinds else hiss_f
    stop = dsp.bandpass(dsp.noise(n, seed + 4), 1800.0, 5000.0, 2) * burst
    stop = dsp.lowpass(stop, 6000.0, 1)
    x = vox * 1.0 + hiss * fric * 0.14 + stop * 0.45
    x = dsp.highpass(x, 140.0, 2)
    x = dsp.lowpass(x, 7000.0, 2)
    # Every word releases over its last 80 ms so voiced endings (the n of "seven") never stop dead.
    tail = dsp.n_of(0.08)
    x[-tail:] *= np.linspace(1.0, 0.0, tail) ** 2
    return dsp.fade_in(x, 0.004)


COUNT_WORDS = {
    "five": ([("f", 0.07), ("ah", 0.09), ("~ih", 0.11), ("v", 0.06)], 205.0, 175.0),
    "six": ([("s", 0.085), ("ih", 0.1), ("k", 0.035), ("s", 0.08)], 215.0, 190.0),
    "seven": ([("s", 0.075), ("eh", 0.09), ("v", 0.045), ("uh", 0.06), ("n", 0.08)], 225.0, 185.0),
    "eight": ([("ey", 0.09), ("~ih", 0.12), ("t", 0.04), ("_", 0.02)], 250.0, 205.0),
}


def _count(word: str):
    score, a, b = COUNT_WORDS[word]
    return lambda v: _word(score, a, b, 800 + list(COUNT_WORDS).index(word) * 10)


for _w in COUNT_WORDS:
    family(f"count_{_w}", folder="voice", rms_window=0.25, release=0.03, desc=f'Count-in voice: "{_w}".')(_count(_w))


# ───────────────────────────── traps (docs/TRAPS.md "Events for audio and fx") ─────────────────────────────
# Machines in the same lo-fi cassette voice: short, rounded, tape-saturated, nothing piercing. Seeds
# 900+ so they never collide with the families above. Registered after every older family so the
# older families keep their dither seeds when the library is rebuilt.


@family("trap_tick", roots=PAIR, folder="sfx", rms_window=0.04,
        desc="Trap telegraph: a woody ratchet tick with a pitched ring (tick on the beat before, tock half a beat later).")
def trap_tick(root, f, i):
    n = dsp.n_of(0.16)
    ring = osc_mix(n, [("tri", f, 0.8, 0.0), ("sine", 2 * f, 0.25, 0.0)]) * dsp.perc(n, 0.001, 0.11)
    click = strike(n, 900 + i, 1800.0, 0.008, 0.9, 6000.0)
    return dsp.fade_out(dsp.tape(ring + click, 1.3, 9000.0), 0.02)


@family("spike_up", variants=2, folder="sfx", rms_window=0.06,
        desc="Spikes raise: a short metallic shing over a floor knock.")
def spike_up(v):
    n = dsp.n_of(0.3)
    shing = dsp.sweep_noise(n, 2400.0, 5200.0, 0.05, 3.0, 910 + v) * dsp.perc(n, 0.002, 0.18)
    metal = osc_mix(n, [("sine", 1870.0 + 40 * v, 0.35, 0.0), ("sine", 2913.0, 0.2, 0.0), ("sine", 4120.0, 0.12, 0.0)]) * dsp.perc(n, 0.001, 0.22)
    knock = thump(n, 160.0, 90.0, 0.04, 0.06, 0.5)
    return dsp.fade_out(dsp.tape(0.6 * shing + metal + knock, 1.3, 9500.0), 0.03)


@family("spike_down", folder="sfx", rms_window=0.08, desc="Spikes drop: a soft scrape and a low tock.")
def spike_down(v):
    n = dsp.n_of(0.2)
    scrape = dsp.sweep_noise(n, 2200.0, 900.0, 0.12, 2.0, 915) * dsp.perc(n, 0.004, 0.14)
    return dsp.fade_out(dsp.tape(0.7 * scrape + thump(n, 130.0, 80.0, 0.04, 0.07, 0.5), 1.2, 8000.0), 0.02)


@family("crusher_slam", variants=2, folder="sfx", rms_window=0.1,
        desc="Crusher stroke: a heavy piston thump with a clanking metal head and a hiss of air.")
def crusher_slam(v):
    n = dsp.n_of(0.55)
    body = thump(n, 95.0, 34.0, 0.18, 0.34, 1.0)
    clank = osc_mix(n, [("sine", 410.0 + 12 * v, 0.5, 0.0), ("sine", 1033.0, 0.3, 0.0), ("sine", 1677.0, 0.18, 0.0)]) * dsp.perc(n, 0.001, 0.2)
    crack = dsp.bandpass(dsp.noise(n, 920 + v), 900.0, 3500.0, 2) * dsp.perc(n, 0.0005, 0.07)
    air = dsp.sweep_noise(n, 3000.0, 1200.0, 0.3, 0.8, 925 + v) * dsp.perc(n, 0.01, 0.35) * 0.25
    return dsp.fade_out(dsp.tape(body + clank + 0.6 * crack + air, 1.7, 8000.0), 0.05)


@family("crusher_retract", folder="sfx", rms_window=0.15, desc="Crusher retract: a hydraulic sigh and a soft rattle.")
def crusher_retract(v):
    n = dsp.n_of(0.36)
    t = dsp.times(n)
    sigh = dsp.sweep_noise(n, 1800.0, 600.0, 0.28, 1.2, 930) * np.minimum(1.0, t / 0.03) * np.exp(-t / 0.14)
    rattle = grains(n, 931, 10, 0.25, 1200.0, 3500.0, 0.15) * 0.4
    return dsp.fade_out(dsp.lowpass(sigh + rattle, 6000.0, 2), 0.04)


@family("conveyor_clunk", folder="sfx", rms_window=0.08, desc="Conveyor start / stop / reverse: a motor clunk and a belt jolt.")
def conveyor_clunk(v):
    n = dsp.n_of(0.3)
    clunk = thump(n, 120.0, 70.0, 0.05, 0.12, 0.8) + strike(n, 940, 900.0, 0.02, 0.5, 3000.0)
    motor = dsp.lowpass(osc_mix(n, [("saw", dsp.exp_glide(n, 30.0, 52.0, 0.2), 0.6, 0.0)]), 500.0, 2) * dsp.perc(n, 0.01, 0.26)
    return dsp.fade_out(dsp.tape(clunk + 0.5 * motor, 1.4, 7000.0), 0.03)


@family("conveyor_hum", roots=(36, 42, 48), folder="sfx", loop=True, release=0.25, rms_window=0.8,
        desc="Conveyor running (loop): a low motor hum on the key with a soft belt rattle; tuned per level.")
def conveyor_hum(root, f, i):
    n = dsp.n_of(2.4)
    t = dsp.times(n)
    hum = osc_mix(n, [("saw", f, 0.45, -4.0), ("saw", f, 0.45, 4.0), ("sine", f, 0.5, 0.0), ("sine", 2 * f, 0.15, 0.0)])
    hum = dsp.lowpass(hum, 380.0, 2)
    # Belt seams: a soft rattle four times a second (loop-safe: 2.4 s holds whole cycles).
    rattle = dsp.bandpass(dsp.noise(n, 950 + i), 900.0, 2500.0, 2) * (0.5 + 0.5 * np.cos(2 * np.pi * 5.0 * t)) ** 6
    x = (hum + 0.15 * rattle) * np.minimum(1.0, t / 0.06)
    return dsp.tape(x, 1.3, 7000.0), 0.4, 2.2, 0.2


@family("flame_ignite", folder="sfx", rms_window=0.12, desc="Flame jet ignites: a gas whoomp opening into a roar.")
def flame_ignite(v):
    n = dsp.n_of(0.5)
    t = dsp.times(n)
    whoomp = dsp.svf(dsp.noise(n, 960), dsp.exp_glide(n, 300.0, 2400.0, 0.12), 0.9) * np.minimum(1.0, t / 0.02) * np.exp(-t / 0.16)
    body = thump(n, 90.0, 60.0, 0.1, 0.2, 0.6)
    return dsp.fade_out(dsp.tape(whoomp + body, 1.6, 7000.0), 0.06)


@family("flame_roar", folder="sfx", loop=True, release=0.15, rms_window=0.8,
        desc="Flame jet burning (loop): a band-limited roar with slow flicker.")
def flame_roar(v):
    n = dsp.n_of(2.0)
    t = dsp.times(n)
    roar = dsp.bandpass(dsp.noise(n, 965), 180.0, 1800.0, 2)
    flicker = 0.75 + 0.25 * np.sin(2 * np.pi * 2.0 * t) * np.sin(2 * np.pi * 7.0 * t + 0.4)
    crackle = grains(n, 966, 40, 2.0, 2500.0, 6000.0, 10.0) * 0.25
    x = (roar * flicker + crackle) * np.minimum(1.0, t / 0.05)
    return dsp.tape(x, 1.4, 6000.0), 0.3, 1.8, 0.25


@family("flame_out", folder="sfx", rms_window=0.1, desc="Flame jet cuts off: a short falling hiss.")
def flame_out(v):
    n = dsp.n_of(0.3)
    return dsp.fade_out(dsp.svf(dsp.noise(n, 970), dsp.exp_glide(n, 2200.0, 300.0, 0.22), 0.8) * dsp.perc(n, 0.003, 0.26), 0.03)


@family("dart_fire", variants=2, folder="sfx", rms_window=0.04, desc="Dart launcher: a pneumatic pfft and a thin whistle.")
def dart_fire(v):
    n = dsp.n_of(0.22)
    pfft = dsp.sweep_noise(n, 2600.0, 900.0, 0.06, 1.0, 975 + v) * dsp.perc(n, 0.001, 0.07)
    whistle = osc_mix(n, [("sine", dsp.exp_glide(n, 2600.0 + 150 * v, 1500.0, 0.18), 0.25, 0.0)]) * dsp.perc(n, 0.01, 0.18)
    return dsp.fade_out(pfft + whistle + strike(n, 978 + v, 2000.0, 0.006, 0.4), 0.02)


@family("bumper_boing", roots=PAIR, folder="sfx", rms_window=0.12, desc="Bumper fires: a sprung plate boing with a knock.")
def bumper_boing(root, f, i):
    n = dsp.n_of(0.4)
    t = dsp.times(n)
    freq = f * 2.0 ** ((-5.0 * np.exp(-t / 0.03) + 0.4 * np.sin(2 * np.pi * 9.0 * t) * np.exp(-t / 0.2)) / 12.0)
    spring = osc_mix(n, [("tri", freq, 0.8, 0.0), ("sine", freq / 2, 0.4, 0.0)]) * dsp.perc(n, 0.002, 0.34)
    knock = thump(n, 180.0, 90.0, 0.03, 0.06, 0.5) + strike(n, 980 + i, 1500.0, 0.01, 0.3)
    return dsp.fade_out(dsp.tape(spring + knock, 1.3, 8500.0), 0.03)


@family("sensor_beep", roots=PAIR, folder="sfx", rms_window=0.08, desc="Beam sensor tripped: a soft two-partial beep.")
def sensor_beep(root, f, i):
    n = dsp.n_of(0.18)
    x = osc_mix(n, [("sine", f, 0.8, 0.0), ("tri", 2 * f, 0.15, 3.0)]) * dsp.adsr(n, 0.004, 0.08, 0.25) * np.clip((0.18 - dsp.times(n)) / 0.05, 0.0, 1.0)
    return dsp.fade_out(dsp.lowpass(x, 6000.0, 2), 0.02)


# ───────────────────────────── build ─────────────────────────────


def render_family(name: str, spec: dict) -> list[dict]:
    members = []
    if spec["roots"] is not None:
        for i, root in enumerate(spec["roots"]):
            res = spec["fn"](root, dsp.midi_hz(root), i)
            members.append(dict(key=str(root), root=root, res=res))
    else:
        for v in range(spec["variants"]):
            res = spec["fn"](v)
            members.append(dict(key=f"v{v}", root=-1, res=res))
    # Unpack and loop.
    for m in members:
        res = m.pop("res")
        if isinstance(res, tuple):
            x, ls, le, xf = res
            x = dsp.dc_block(x)
            ls_i, le_i = dsp.n_of(ls), dsp.n_of(le)
            x = dsp.crossfade_loop(x, ls_i, le_i, dsp.n_of(xf))
            m["loop"] = (ls_i, le_i)
        else:
            x = dsp.fade_out(dsp.dc_block(res), 0.004)
            m["loop"] = None
        x = dsp.fade_in(x, 0.0008)
        m["x"] = x
    # RMS-match members, then scale the family so its loudest member peaks at PEAK_DBFS.
    win = spec["rms_window"]
    levels = [max(1e-9, dsp.windowed_rms(m["x"], 0.0, win)) for m in members]
    ref = float(np.exp(np.mean(np.log(levels))))
    for m, lv in zip(members, levels):
        m["x"] = m["x"] * (ref / lv)
    top = max(dsp.peak(m["x"]) for m in members)
    scale = dsp.undb(PEAK_DBFS) / max(1e-9, top)
    for m in members:
        m["x"] = m["x"] * scale
    return members


def write_wav(path: str, x: np.ndarray, seed: int) -> None:
    pad = np.zeros(dsp.n_of(PAD))
    y = np.concatenate((pad, x))
    # TPDF dither at 16 bits, deterministic. The pad stays exactly zero.
    r = dsp.rng(seed)
    d = (r.random(len(y)) - r.random(len(y))) / 32768.0
    d[: len(pad)] = 0.0
    q = np.clip(np.round((y + d) * 32767.0), -32767, 32767).astype(np.int16)
    q[: len(pad)] = 0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    wavfile.write(path, SR, q)


IMPORT_PARAMS = """[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=0
edit/loop_begin=0
edit/loop_end=-1
compress/mode=0
"""


def ensure_import_settings(wav_path: str) -> None:
    """Godot 4.4 imports WAV as lossy QOA by default. The samples must stay PCM (exact seeking into
    the silent pad, no decode cost per voice) and untrimmed (the pad is load-bearing), so pin the
    import parameters. Existing .import files keep their uid; new ones get a minimal header that
    Godot completes on the next import."""
    imp = wav_path + ".import"
    if os.path.exists(imp):
        with open(imp, "r", encoding="utf-8") as fh:
            text = fh.read()
        head = text.split("[params]")[0]
        new = head + IMPORT_PARAMS
    else:
        new = '[remap]' + chr(10) * 2 + 'importer="wav"' + chr(10) + 'type="AudioStreamWAV"' + chr(10) * 2 + IMPORT_PARAMS
        text = ""
    if new != text:
        with open(imp, "w", encoding="utf-8", newline=chr(10)) as fh:
            fh.write(new)


def main(argv: list[str]) -> int:
    want = set(argv) if argv else None
    manifest_path = os.path.join(OUT, "manifest.json")
    manifest = {"version": 1, "sampleRate": SR, "pad": PAD, "peakDbfs": PEAK_DBFS, "families": {}}
    if want and os.path.exists(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
    padn = dsp.n_of(PAD)
    for seed, (name, spec) in enumerate(FAMILIES.items()):
        if want and name not in want:
            continue
        members = render_family(name, spec)
        entries = []
        for j, m in enumerate(members):
            rel = f"{spec['folder']}/{name}_{m['key']}.wav"
            write_wav(os.path.join(OUT, rel), m["x"], 1000 + seed * 64 + j)
            ensure_import_settings(os.path.join(OUT, rel))
            e = {"file": rel, "root": m["root"], "frames": int(len(m["x"]) + padn)}
            if m["loop"] is not None:
                e["loopBegin"] = int(m["loop"][0] + padn)
                e["loopEnd"] = int(m["loop"][1] + padn)
            entries.append(e)
        manifest["families"][name] = {
            "pitched": spec["roots"] is not None,
            "loop": spec["loop"],
            "release": spec["release"],
            "desc": spec["desc"],
            "samples": entries,
        }
        print(f"{name:20s} {len(entries):3d} file(s)")
    manifest["families"] = dict(sorted(manifest["families"].items()))
    with open(manifest_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(manifest, fh, indent=1)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
