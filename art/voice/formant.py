"""Small Klatt-style formant synthesiser (numpy/scipy only) for OVERDUB's synthetic voice.

Source  : differentiated Rosenberg glottal pulse train (per-cycle jitter + shimmer) + aspiration noise.
Tract   : cascade of five time-varying second-order resonators (F1..F3 move, F4/F5 fixed).
Fricatives / stop bursts: band-shaped noise mixed in parallel after the tract.

An utterance is described with `Utt`: piecewise-linear parameter tracks (av, ah, f0, F1..F3, B1..B3),
smoothed with a short Hann window so articulations glide, plus a list of noise layers.
Everything is deterministic for a given seed.
"""
import numpy as np
from scipy import signal

FS = 44100
F4, B4, F5, B5 = 4200.0, 260.0, 5000.0, 320.0  # adult female upper formants


def _n(ms):
    return int(round(ms * FS / 1000.0))


class Utt:
    """Keyframed utterance. seg(dur_ms, **targets) ramps the named tracks to their targets over the
    segment; unnamed tracks hold. noise(kind, t0, dur, amp, attack, release) adds a frication layer."""
    TRACKS = ("av", "ah", "f0", "F1", "F2", "F3", "B1", "B2", "B3")

    def __init__(self, **start):
        self.t = 0.0
        base = dict(av=0.0, ah=0.0, f0=200.0, F1=500.0, F2=1600.0, F3=2800.0, B1=80.0, B2=110.0, B3=170.0)
        base.update(start)
        self.keys = {k: [(0.0, float(base[k]))] for k in self.TRACKS}
        self.layers = []
        self.marks = {}

    def seg(self, dur, **targets):
        t1 = self.t + dur
        for k in self.TRACKS:
            v = float(targets[k]) if k in targets else self.keys[k][-1][1]
            self.keys[k].append((t1, v))
        self.t = t1
        return self

    def step(self, **targets):
        """Instant change (a 1 ms ramp)."""
        return self.seg(1.0, **targets)

    def mark(self, name):
        self.marks[name] = self.t
        return self

    def noise(self, kind, t0, dur, amp, attack=8.0, release=12.0, decay=None):
        self.layers.append(dict(kind=kind, t0=t0, dur=dur, amp=amp, attack=attack, release=release, decay=decay))
        return self

    def tracks(self, smooth_ms=14.0):
        n = _n(self.t) + 1
        tt = np.arange(n) * 1000.0 / FS
        out = {}
        w = signal.windows.hann(max(3, _n(smooth_ms) | 1))
        w /= w.sum()
        for k in self.TRACKS:
            ks = self.keys[k]
            x = np.interp(tt, [a for a, _ in ks], [b for _, b in ks])
            sm = smooth_ms if k not in ("av", "ah") else 5.0
            ww = signal.windows.hann(max(3, _n(sm) | 1))
            ww /= ww.sum()
            pad = len(ww) // 2
            out[k] = np.convolve(np.pad(x, pad, mode="edge"), ww, mode="valid")[:n]
        return out


def _resonate(x, F, B):
    T = 1.0 / FS
    C = -np.exp(-2.0 * np.pi * B * T)
    Bc = 2.0 * np.exp(-np.pi * B * T) * np.cos(2.0 * np.pi * F * T)
    A = 1.0 - Bc - C
    xl, Al, Bl, Cl = x.tolist(), A.tolist(), Bc.tolist(), C.tolist()
    y = [0.0] * len(xl)
    y1 = y2 = 0.0
    for i in range(len(xl)):
        v = Al[i] * xl[i] + Bl[i] * y1 + Cl[i] * y2
        y[i] = v
        y2 = y1
        y1 = v
    return np.asarray(y)


def _glottal(f0, rng, tp=0.40, tn=0.16, jitter=0.012, shimmer=0.05):
    """Differentiated Rosenberg pulse train. tp = opening fraction, tn = closing fraction (smaller =
    sharper closure = brighter, more pressed voice). Returns (source, open_flow)."""
    n = len(f0)
    # slow random pitch drift + per-cycle jitter
    drift = signal.lfilter([0.02], [1, -0.98], rng.standard_normal(n)) * 0.6 * jitter
    phase = np.cumsum(f0 * (1.0 + drift) / FS)
    cyc = np.floor(phase).astype(int)
    ncyc = cyc.max() + 2
    jit = 1.0 + jitter * rng.standard_normal(ncyc)
    phase = np.cumsum(f0 * (1.0 + drift) * jit[cyc] / FS)
    cyc = np.floor(phase).astype(int)
    p = phase - cyc
    shim = 1.0 + shimmer * rng.standard_normal(cyc.max() + 2)
    flow = np.where(p < tp, 0.5 * (1.0 - np.cos(np.pi * p / tp)),
                    np.where(p < tp + tn, np.cos(0.5 * np.pi * (p - tp) / tn), 0.0))
    d = np.diff(flow, prepend=0.0) * (FS / np.maximum(f0, 40.0)) * tn
    return d * shim[cyc], flow


_NOISE_FILTERS = {}


def _noise_filter(kind):
    if kind in _NOISE_FILTERS:
        return _NOISE_FILTERS[kind]
    ny = FS / 2.0
    if kind == "s":      # alveolar sibilant, female: energy 4.5-10 kHz, peak ~6.5 kHz
        sos = signal.butter(4, [4300 / ny, 10500 / ny], "bandpass", output="sos")
    elif kind == "f":    # labiodental: weak, flat, diffuse
        sos = signal.butter(2, [1400 / ny, 11000 / ny], "bandpass", output="sos")
    elif kind == "k":    # front velar burst: compact mid peak ~3 kHz
        sos = signal.butter(2, [2300 / ny, 4000 / ny], "bandpass", output="sos")
    elif kind == "t":    # alveolar burst: high, diffuse
        sos = signal.butter(3, 3600 / ny, "highpass", output="sos")
    elif kind == "h":    # breath: broad mid noise (used without the tract for exhale tails)
        sos = signal.butter(2, [500 / ny, 5000 / ny], "bandpass", output="sos")
    else:
        raise ValueError(kind)
    _NOISE_FILTERS[kind] = sos
    return sos


def _layer(n, L, rng):
    i0, m = _n(L["t0"]), max(8, _n(L["dur"]))
    x = signal.sosfilt(_noise_filter(L["kind"]), rng.standard_normal(m + 400))[400:]
    x /= (np.sqrt(np.mean(x * x)) + 1e-12)
    env = np.ones(m)
    a, r = min(m, max(1, _n(L["attack"]))), min(m, max(1, _n(L["release"])))
    env[:a] *= np.sin(0.5 * np.pi * np.arange(a) / a) ** 2
    env[m - r:] *= np.cos(0.5 * np.pi * np.arange(r) / r) ** 2
    if L["decay"]:
        env *= np.exp(-np.arange(m) / (L["decay"] * FS / 1000.0))
    y = np.zeros(max(n, i0 + m))
    y[i0:i0 + m] = x * env * L["amp"]
    return y


def render(u, seed=1, mode="modal", fscale=1.0, fric_gain=1.0, breath=0.0):
    """mode: 'modal' | 'shout' | 'whisper'. Returns float64 mono at FS, voiced part scaled so the
    loudest 20 ms of the tract output has RMS 1 (noise layer amps are relative to that)."""
    rng = np.random.default_rng(seed)
    tr = u.tracks()
    n = len(tr["av"])
    if mode == "shout":
        src, flow = _glottal(tr["f0"], rng, tp=0.36, tn=0.085, jitter=0.02, shimmer=0.08)
    else:
        src, flow = _glottal(tr["f0"], rng)
    asp = rng.standard_normal(n)
    asp = signal.lfilter([1.0], [1.0, -0.55], asp) * 0.5  # gentle -6 dB/oct tilt like turbulence at the glottis
    if mode == "whisper":
        # no voicing: the "voiced" amplitude track drives noise excitation instead
        exc = (tr["av"] * 1.0 + tr["ah"]) * asp
        exc = signal.lfilter([1.0, -0.6], [1.0], exc)  # whisper source is flatter / brighter than voice
    else:
        exc = tr["av"] * src + (tr["ah"] + breath * tr["av"]) * asp * (0.55 + 0.45 * flow) * 0.35
    f1 = tr["F1"] * fscale * (1.10 if mode == "whisper" else 1.0)
    y = exc
    y = _resonate(y, f1, tr["B1"] * (1.5 if mode == "whisper" else 1.0))
    y = _resonate(y, tr["F2"] * fscale, tr["B2"])
    y = _resonate(y, tr["F3"] * fscale, tr["B3"])
    y = _resonate(y, np.full(n, F4 * fscale), np.full(n, B4))
    y = _resonate(y, np.full(n, F5 * fscale), np.full(n, B5))
    # reference level: loudest 20 ms
    w = _n(20)
    p = np.convolve(y * y, np.ones(w) / w, mode="same")
    y = y / (np.sqrt(p.max()) + 1e-12)
    total = max([n] + [_n(L["t0"]) + max(8, _n(L["dur"])) for L in u.layers])
    out = np.zeros(total)
    out[:n] = y
    for L in u.layers:
        out += _layer(total, L, rng)[:total] * fric_gain
    if mode == "shout":
        out = np.tanh(out * 0.9) / 0.9  # a little chest-voice saturation
    sos = signal.butter(2, 70.0 / (FS / 2.0), "highpass", output="sos")
    return signal.sosfilt(sos, out)


# ---------------------------------------------------------------------------------------------
# measurement / mastering

def k_weight(x):
    """ITU-R BS.1770 K-weighting at FS (coefficients derived for 44.1 kHz)."""
    def shelf(f0, G, Q):
        K = np.tan(np.pi * f0 / FS)
        Vh = 10.0 ** (G / 20.0)
        Vb = Vh ** 0.4996667741545416
        a0 = 1.0 + K / Q + K * K
        b = [(Vh + Vb * K / Q + K * K) / a0, 2.0 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
        a = [1.0, 2.0 * (K * K - 1.0) / a0, (1.0 - K / Q + K * K) / a0]
        return b, a

    def hp(f0, Q):
        K = np.tan(np.pi * f0 / FS)
        a0 = 1.0 + K / Q + K * K
        return [1.0, -2.0, 1.0], [1.0, 2.0 * (K * K - 1.0) / a0, (1.0 - K / Q + K * K) / a0]

    b, a = shelf(1681.974450955533, 3.999843853973347, 0.7071752369554196)
    x = signal.lfilter(b, a, x)
    b, a = hp(38.13547087602444, 0.5003270373238773)
    return signal.lfilter(b, a, x)


def lkfs(x):
    """Ungated K-weighted loudness of the whole file (one-shots are shorter than a gating block)."""
    k = k_weight(np.concatenate([x, np.zeros(2000)]))
    return -0.691 + 10.0 * np.log10(np.sum(k * k) / len(x) + 1e-20)


def db(v):
    return 20.0 * np.log10(max(float(v), 1e-12))


def master(x, target_lkfs=-16.0, ceiling_db=-1.0, fade_in_ms=1.5, fade_out_ms=8.0, trim_db=-46.0):
    """Trim to the onset, fade, normalise loudness, hold the peak under the ceiling (soft limit)."""
    x = np.asarray(x, dtype=np.float64)
    x = x - np.mean(x)
    env = np.abs(signal.hilbert(x)) if len(x) > 16 else np.abs(x)
    thr = env.max() * 10.0 ** (trim_db / 20.0)
    idx = np.nonzero(env > thr)[0]
    lead = max(0, idx[0] - _n(1.5))
    tail = min(len(x), idx[-1] + _n(6.0))
    x = x[lead:tail].copy()
    a, r = _n(fade_in_ms), _n(fade_out_ms)
    x[:a] *= np.sin(0.5 * np.pi * np.arange(a) / a) ** 2
    x[-r:] *= np.cos(0.5 * np.pi * np.arange(r) / r) ** 2
    ceil = 10.0 ** (ceiling_db / 20.0)
    for _ in range(4):
        x *= 10.0 ** ((target_lkfs - lkfs(x)) / 20.0)
        pk = np.abs(x).max()
        if pk <= ceil:
            break
        # soft-knee limiter: linear below 0.6*ceil, tanh above
        knee = 0.6 * ceil
        ax = np.abs(x)
        over = ax > knee
        x[over] = np.sign(x[over]) * (knee + (ceil - knee) * np.tanh((ax[over] - knee) / (ceil - knee)))
    return x, lead * 1000.0 / FS


def to_int16(x):
    return np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)


def stats(x):
    return dict(duration_ms=round(len(x) * 1000.0 / FS, 1), peak_dbfs=round(db(np.abs(x).max()), 2),
                rms_dbfs=round(db(np.sqrt(np.mean(x * x))), 2), lkfs=round(float(lkfs(x)), 2),
                dc=round(float(np.mean(x)), 5))
