"""Shared audio helpers for the ElevenLabs voice set: decode, measure, write.
Run everything as `python -I` from the repo root. Needs numpy, scipy and an ffmpeg binary on PATH
(or OD_FFMPEG pointing at one) for MP3 decoding only."""
import os, re, shutil, subprocess, wave
import numpy as np
from scipy import signal

SR = 44100
FFMPEG = os.environ.get("OD_FFMPEG") or shutil.which("ffmpeg") or "ffmpeg"


def decode(path, sr=SR):
    """Any audio file -> float32 mono at sr, via ffmpeg."""
    raw = subprocess.run([FFMPEG, "-v", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(sr), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0


def read_wav(path):
    with wave.open(path, "rb") as w:
        assert w.getsampwidth() == 2
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768.0
        if w.getnchannels() > 1:
            x = x.reshape(-1, w.getnchannels()).mean(axis=1)
        return x, w.getframerate()


def write_wav(path, x, sr=SR):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    y = np.clip(x, -1.0, 1.0)
    pcm = np.round(y * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm.tobytes())


def db(v):
    return 20.0 * np.log10(np.maximum(v, 1e-9))


def envelope(x, sr=SR, win_ms=10.0):
    """RMS envelope, one value per hop (hop = win)."""
    n = max(1, int(sr * win_ms / 1000.0))
    m = len(x) // n
    if m == 0:
        return np.zeros(1)
    return np.sqrt(np.mean(x[: m * n].reshape(m, n) ** 2, axis=1) + 1e-12)


def speech_bounds(x, sr=SR, thresh_db=-42.0, win_ms=5.0):
    """(start, end) samples of the region whose 5 ms RMS is above thresh relative to the take's peak RMS."""
    e = db(envelope(x, sr, win_ms))
    ref = e.max()
    on = np.where(e > ref + thresh_db)[0]
    n = int(sr * win_ms / 1000.0)
    if len(on) == 0:
        return 0, len(x)
    return int(on[0] * n), int(min(len(x), (on[-1] + 1) * n))


def k_weight(x, sr=SR):
    """ITU-R BS.1770 K-weighting (shelf + high-pass), coefficients recomputed for sr."""
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = np.tan(np.pi * f0 / sr); Vh = 10 ** (G / 20); Vb = Vh ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    y = signal.lfilter(b, a, x)
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = np.tan(np.pi * f0 / sr); a0 = 1 + K / Q + K * K
    return signal.lfilter([1, -2, 1], [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0], y)


def lufs(x, sr=SR):
    """Integrated loudness, BS.1770 gating (400 ms blocks, 75 % overlap, -70 abs, -10 rel).
    For takes shorter than one block, the ungated K-weighted mean square is used."""
    y = k_weight(x, sr)
    n = int(0.4 * sr); hop = n // 4
    if len(y) < n:
        return float(-0.691 + 10 * np.log10(np.mean(y ** 2) + 1e-12))
    ms = np.array([np.mean(y[i:i + n] ** 2) for i in range(0, len(y) - n + 1, hop)])
    l = -0.691 + 10 * np.log10(ms + 1e-12)
    keep = ms[l > -70]
    if len(keep) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(keep)) - 10
    keep = ms[(l > -70) & (l > rel)]
    return float(-0.691 + 10 * np.log10(np.mean(keep) + 1e-12))


def short_term(x, sr=SR, win=0.4, hop=0.1):
    y = k_weight(x, sr); n = int(win * sr); h = int(hop * sr)
    if len(y) < n:
        return np.array([-0.691 + 10 * np.log10(np.mean(y ** 2) + 1e-12)])
    return np.array([-0.691 + 10 * np.log10(np.mean(y[i:i + n] ** 2) + 1e-12) for i in range(0, len(y) - n + 1, h)])


def pitch_track(x, sr=SR, fmin=60.0, fmax=500.0, frame=0.04, hop=0.01):
    """Normalised-autocorrelation pitch tracker. Returns f0 per frame (0 = unvoiced)."""
    ds = 4
    y = signal.resample_poly(x, 1, ds); fs = sr // ds
    sos = signal.butter(4, [50, 1000], "bandpass", fs=fs, output="sos")
    y = signal.sosfiltfilt(sos, y) if len(y) > 60 else y
    n = int(frame * fs); h = int(hop * fs)
    lo, hi = int(fs / fmax), int(fs / fmin)
    gate = np.sqrt(np.mean(y ** 2) + 1e-12) * 0.25
    out = []
    win = np.hanning(n)
    wac = np.correlate(win, win, "full")[n - 1:]
    for i in range(0, max(1, len(y) - n), h):
        f = y[i:i + n]
        if len(f) < n or np.sqrt(np.mean(f ** 2)) < gate:
            out.append(0.0); continue
        f = (f - f.mean()) * win
        ac = np.correlate(f, f, "full")[n - 1:]
        if ac[0] <= 0:
            out.append(0.0); continue
        nac = ac / ac[0] / np.maximum(wac / wac[0], 1e-3)
        seg = nac[lo:hi]
        k = int(np.argmax(seg))
        # prefer the shortest lag within 90 % of the best peak (avoids octave-down errors)
        cand = np.where(seg >= 0.9 * seg[k])[0]
        for c in cand:
            if 0 < c < len(seg) - 1 and seg[c] >= seg[c - 1] and seg[c] >= seg[c + 1]:
                k = int(c); break
        if seg[k] < 0.5:
            out.append(0.0); continue
        out.append(fs / (lo + k))
    f0 = np.array(out)
    v = f0[f0 > 0]
    if len(v) > 4:  # drop octave outliers relative to the median
        med = np.median(v)
        f0[(f0 > 0) & ((f0 > 1.8 * med) | (f0 < med / 1.8))] = 0.0
    return f0


def syllables(text):
    """Rough English syllable count for the spoken words of a line (audio tags stripped)."""
    text = re.sub(r"\[[^\]]*\]", " ", text.lower())
    n = 0
    for w in re.findall(r"[a-z']+", text):
        w = w.replace("'", "")
        if not w:
            continue
        c = len(re.findall(r"[aeiouy]+", w))
        if w.endswith("e") and not w.endswith(("le", "ee")) and c > 1:
            c -= 1
        if w.endswith("ed") and c > 1 and not w.endswith(("ted", "ded")):
            c -= 1
        n += max(1, c)
    return n


def strip_tags(text):
    return re.sub(r"\s+", " ", re.sub(r"\[[^\]]*\]", " ", text)).strip()


def hf_ratio(x, sr=SR):
    """Energy above 6 kHz relative to 300-3400 Hz, in dB: a crude brightness / hiss indicator."""
    if len(x) < 2048:
        return 0.0
    f, p = signal.welch(x, sr, nperseg=2048)
    return float(10 * np.log10((p[f > 6000].sum() + 1e-15) / (p[(f > 300) & (f < 3400)].sum() + 1e-15)))


def rms_db(x):
    return float(db(np.sqrt(np.mean(np.square(x, dtype=np.float64)) + 1e-12))) if len(x) else -180.0


def measure(x, text="", sr=SR):
    s, e = speech_bounds(x, sr)
    y = x[s:e]
    env = db(envelope(y, sr, 10.0))
    active = env > env.max() - 35
    run = best = 0  # longest internal run of silence
    for a in active:
        run = 0 if a else run + 1
        best = max(best, run)
    f0 = pitch_track(y, sr); v = f0[f0 > 0]
    st = short_term(y, sr)
    nsyl = syllables(text) if text else 0
    dur = len(y) / sr
    act = float(active.sum()) * 0.01
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    return {
        "dur": round(dur, 3), "active": round(act, 3), "lead": round(s / sr, 3), "tail": round((len(x) - e) / sr, 3),
        "syl": nsyl, "syl_s": round(nsyl / dur, 2) if dur > 0 else 0, "artic_syl_s": round(nsyl / act, 2) if act > 0 else 0,
        "f0_med": round(float(np.median(v)), 1) if len(v) else 0.0,
        "f0_p5": round(float(np.percentile(v, 5)), 1) if len(v) else 0.0,
        "f0_p95": round(float(np.percentile(v, 95)), 1) if len(v) else 0.0,
        "f0_range_st": round(float(12 * np.log2(np.percentile(v, 95) / np.percentile(v, 5))), 2) if len(v) > 4 else 0.0,
        "voiced_frac": round(float(len(v)) / max(1, len(f0)), 2),
        "lufs": round(lufs(y, sr), 2), "st_sd": round(float(np.std(st[st > st.max() - 20])), 2),
        "peak_db": round(float(db(peak)), 2), "clipped": int(np.sum(np.abs(x) >= 0.999)),
        "crest_db": round(float(db(peak)) - rms_db(y), 2),
        "max_gap": round(best * 0.01, 3), "dc": round(float(np.mean(x)), 5),
        "hf_ratio_db": round(hf_ratio(y, sr), 2),
        "tail50_db": round(rms_db(x[-int(0.05 * sr):]) - rms_db(y), 1),
    }
