"""Spectrogram contact sheets for reviewing samples by eye (art/previews/audio/, git-ignored).

    python -I art/audio/spectrograms.py [family ...]     default: count-in voice + one of each instrument
    python -I art/audio/spectrograms.py --mix file.wav   one rendered mix
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from scipy import signal  # noqa: E402
from scipy.io import wavfile  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio")
OUT = os.path.join(ROOT, "art", "previews", "audio")

DEFAULT = ["count_five", "count_six", "count_seven", "count_eight", "bass", "lead", "keys", "pad", "kick", "snare", "hat_closed", "clap"]


def load(path: str):
    sr, q = wavfile.read(path)
    x = q.astype(np.float64) / (32768.0 if q.dtype == np.int16 else 2147483648.0 if q.dtype == np.int32 else 1.0)
    if x.ndim == 2:
        x = x.mean(axis=1)
    return sr, x


def panel(ax, sr: int, x: np.ndarray, title: str, fmax: float = 8000.0) -> None:
    f, t, s = signal.spectrogram(x, sr, nperseg=512, noverlap=448)
    s = 10 * np.log10(s + 1e-12)
    ax.pcolormesh(t, f, s, shading="auto", vmin=s.max() - 80, vmax=s.max(), cmap="magma")
    ax.set_ylim(0, fmax)
    ax.set_title(title, fontsize=8)
    ax.tick_params(labelsize=6)


def main(argv: list[str]) -> int:
    os.makedirs(OUT, exist_ok=True)
    if argv and argv[0] == "--mix":
        sr, x = load(argv[1])
        fig, ax = plt.subplots(2, 1, figsize=(14, 7))
        panel(ax[0], sr, x, os.path.basename(argv[1]), 12000.0)
        ax[1].plot(np.arange(len(x)) / sr, x, linewidth=0.3)
        ax[1].set_ylim(-1, 1)
        out = os.path.join(OUT, os.path.splitext(os.path.basename(argv[1]))[0] + "_spec.png")
        fig.tight_layout()
        fig.savefig(out, dpi=110)
        print(out)
        return 0
    with open(os.path.join(AUDIO, "manifest.json"), encoding="utf-8") as fh:
        man = json.load(fh)
    names = argv or DEFAULT
    cols = 4
    rows = (len(names) + cols - 1) // cols
    fig, axes = plt.subplots(rows, cols, figsize=(16, 3.2 * rows))
    for ax, name in zip(np.ravel(axes), names):
        samples = man["families"][name]["samples"]
        e = samples[len(samples) // 2]
        sr, x = load(os.path.join(AUDIO, e["file"]))
        panel(ax, sr, x, f"{name} ({e['file']})", 8000.0 if name.startswith("count") else 12000.0)
    for ax in np.ravel(axes)[len(names):]:
        ax.axis("off")
    fig.tight_layout()
    out = os.path.join(OUT, "samples_spec.png")
    fig.savefig(out, dpi=100)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
