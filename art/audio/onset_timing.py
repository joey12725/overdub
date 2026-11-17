"""Measures real music timing from a recorded preview (we cannot hear, so we measure).

    python -I art/audio/onset_timing.py art/previews/audio/audio_preview_static_solo1.wav \
        art/previews/audio/audio_preview.log B 120

Reads the master-output WAV written by tools/audio_preview.gd and its event log, takes the
scheduled notes of one layer (letter A-D), finds each note's attack in the recording, fits one
constant offset (the capture's start relative to the planning clock) and reports how far each
attack lands from where it was scheduled: the timing jitter actually produced by the voice
engine's mix-boundary compensation. Run it on a solo recording (solo=<tape> nosfx) so attacks of
other layers and gameplay sounds do not blur the measurement.
"""
from __future__ import annotations

import re
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt


def main() -> int:
    if len(sys.argv) < 5:
        print(__doc__)
        return 2
    wav_path, log_path, layer, bpm = sys.argv[1], sys.argv[2], sys.argv[3].upper(), float(sys.argv[4])
    sr, x = wavfile.read(wav_path)
    x = x.astype(np.float64) / 32768.0
    mono = x.mean(axis=1) if x.ndim == 2 else x
    # Attacks: high-passed (drop sustained lows), rectified, 0.5 ms smoothing.
    sos = butter(2, 150.0, "highpass", fs=sr, output="sos")
    env = np.abs(sosfilt(sos, mono))
    k = max(1, int(0.0005 * sr))
    env = np.convolve(env, np.ones(k) / k, mode="same")

    pat = re.compile(r"^\[note\] (\w) beat\s+([\d.]+) .* at \+([\d.]+) s")
    onsets: dict[float, float] = {}
    with open(log_path, encoding="utf-8") as f:
        for line in f:
            m = pat.match(line)
            if m and m.group(1) == layer:
                beat, t = float(m.group(2)), float(m.group(3))
                onsets.setdefault(round(beat, 6), t)
    if not onsets:
        print("no notes for layer", layer)
        return 1
    planned = np.array(sorted(onsets.values()))

    # Onset function: rise of the log envelope over 1 ms (a new attack, not a decaying tail).
    lag = max(1, int(0.001 * sr))
    loge = np.log(env + 1e-5)
    rise = np.zeros_like(loge)
    rise[lag:] = loge[lag:] - loge[:-lag]

    def attack_near(t: float, window: float = 0.03) -> float | None:
        a, b = int((t - window) * sr), int((t + window) * sr)
        if a < 0 or b >= len(env):
            return None
        seg = rise[a:b]
        i = int(np.argmax(seg))
        if seg[i] < 1.0:  # less than a ~2.7x jump in 1 ms: no attack here
            return None
        return (a + i) / sr

    # Coarse offset: the capture starts when the preview's clock does, give or take one mix.
    best_off, best_score = 0.0, -1e30
    for off in np.arange(-0.05, 0.05, 0.00025):
        score = 0.0
        for t in planned[:24]:
            i = int((t + off) * sr)
            if 0 < i < len(rise) - lag:
                score += rise[i: i + 2 * lag].max()
        if score > best_score:
            best_off, best_score = off, score
    found = []
    times = []
    for t in planned:
        at = attack_near(t + best_off)
        if at is not None:
            found.append(at - t)
            times.append(t)
    found = np.array(found)
    times = np.array(times)
    if len(found) < 8:
        print("too few attacks found:", len(found))
        return 1
    # Remove a linear clock drift (capture rate vs the planning clock), then measure what is left.
    slope, icpt = np.polyfit(times, found, 1)
    resid = found - (slope * times + icpt)
    print(f"  clock drift between capture and planning clock: {slope * 1e6:+.1f} ppm")
    found = resid + np.median(found)
    offset = float(np.median(found))
    dev = (found - offset) * 1000.0
    sixteenth = 60.0 / bpm / 4.0 * 1000.0
    print(f"{wav_path}: {sr} Hz, layer {layer}: {len(planned)} scheduled onsets, {len(found)} attacks found")
    print(f"  constant offset (capture vs planning clock) {offset * 1000:.2f} ms")
    print(f"  deviation from schedule: mean {dev.mean():+.2f} ms, sd {dev.std():.2f} ms, "
          f"p95 |dev| {np.percentile(np.abs(dev), 95):.2f} ms, max |dev| {np.abs(dev).max():.2f} ms "
          f"(one sixteenth = {sixteenth:.0f} ms)")
    worst = np.argsort(-np.abs(dev))[:5]
    print("  worst:", ", ".join(f"{dev[i]:+.2f} ms" for i in worst))
    return 0


if __name__ == "__main__":
    sys.exit(main())
