"""Post-process every extracted take into the game set under assets/audio/voice/elevenlabs/.

  takes/<id>.wav  ->  trim, fade, high-pass, the character's fiction treatment, loudness, limiter
                  ->  44.1 kHz mono 16-bit WAV, one per line id

Chains (all offline, deterministic: noise is seeded from the line id):
  moxie      dry.
  opal       varispeed -1.5 st, 350-3000 Hz radio band, 1.8 kHz presence, 4:1 compression 8 dB under the
             speech level, tanh saturation, hiss bed at -30 dB + sparse crackle (largest click 3 dB over the
             speech RMS, about 9 a second) with a squelch tail. Radio cuts ("d--", "--oxie") are cut at the word
             timestamp and closed/opened with a static burst.
  tolly      dry copy (he is met in person) and a mild comms copy: 250-4200 Hz, 2.5:1, faint hiss, no crackle.
  archivist  tape playback: 60 Hz-9 kHz, fixed 11/23 ms layering (a static comb, so pitch does not move),
             0.6 Hz wow + 6.5 Hz flutter of a few cents, post-echo print-through at -30 dB, hiss, saturation.
             expression "playback" (it is quoting): deeper wow and a 140 ms reel run-up; "still": single layer,
             no wow.
  count      the counted phrases are sliced into five/six/seven/eight one-shots at Scribe's word times refined
             by energy, leading consonant held to 80 ms, WSOLA-tightened (pitch kept, at most 1.3x) towards 345 ms and capped at 380 ms; calls and efforts are trimmed one-shots. All one-shots peak at -3 dBFS.

usage: python -I art/voice_el/process.py [id-regex]"""
import hashlib, json, os, re, sys
import numpy as np
from scipy import signal
from scipy.ndimage import minimum_filter1d, uniform_filter1d
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vx, script_lines

SR = vx.SR
HERE = os.path.dirname(os.path.abspath(__file__))
TAKES = os.path.join(HERE, "takes")
OUT = os.path.join(script_lines.ROOT, "assets", "audio", "voice", "elevenlabs")
LINE_LUFS = -18.0      # every dialogue line and bark, measured after treatment
CEIL_DB = -1.0         # limiter ceiling for lines
ONESHOT_PEAK_DB = -3.0  # count-in, calls, efforts
COUNT_MAX_S = 0.380


def rng_for(id_):
    return np.random.default_rng(int(hashlib.sha1(id_.encode()).hexdigest()[:8], 16))


def sos(kind, f, order=4):
    return signal.butter(order, f, kind, fs=SR, output="sos")


def filt(x, s):
    return signal.sosfilt(s, x)


def peaking(x, f0, gain_db, q):
    A = 10 ** (gain_db / 40); w = 2 * np.pi * f0 / SR; al = np.sin(w) / (2 * q)
    b = [1 + al * A, -2 * np.cos(w), 1 - al * A]; a = [1 + al / A, -2 * np.cos(w), 1 - al / A]
    return signal.lfilter(np.array(b) / a[0], np.array(a) / a[0], x)


def fade(x, in_ms=4.0, out_ms=30.0):
    x = x.copy()
    a = min(len(x) // 2, int(SR * in_ms / 1000)); b = min(len(x) // 2, int(SR * out_ms / 1000))
    if a > 0:
        x[:a] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    if b > 0:
        x[-b:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(b) / b)
    return x


def trim(x, pre_ms=12.0, tail_ms=140.0, thresh_db=-45.0):
    """Cut leading/trailing silence, keeping a short pre-roll and whatever natural tail exists (up to tail_ms)."""
    s, e = vx.speech_bounds(x, SR, thresh_db)
    s = max(0, s - int(SR * pre_ms / 1000)); e2 = min(len(x), e + int(SR * tail_ms / 1000))
    had_tail = (e2 - e) > int(0.03 * SR)
    return x[s:e2], had_tail


def end_fade_ms(x, had_tail):
    """eleven_v3 often ends a file 40-60 ms after the last word with the vowel still sounding. Where the
    take has its own tail a 40 ms fade is enough; where it stops hot, release it over 80-120 ms."""
    if had_tail:
        return 40.0
    hot = vx.rms_db(x[-int(0.05 * SR):]) - vx.db(speech_rms(x))
    return 120.0 if hot > -8.0 else 80.0


def limiter(x, ceil_db=CEIL_DB, look_ms=3.0):
    c = 10 ** (ceil_db / 20)
    g = np.minimum(1.0, c / np.maximum(np.abs(x), 1e-9))
    L = max(1, int(SR * look_ms / 1000))
    g = minimum_filter1d(g, size=2 * L + 1, mode="nearest")
    g = uniform_filter1d(g, size=L, mode="nearest")
    return x * g


def compress(x, thresh_db, ratio, attack_ms, release_ms, makeup_db=0.0):
    hop = 44
    n = len(x) // hop + 1
    pad = np.concatenate([x, np.zeros(n * hop - len(x))])
    lev = vx.db(np.sqrt(np.mean(pad.reshape(n, hop) ** 2, axis=1) + 1e-12))
    aa = np.exp(-1.0 / (attack_ms / 1000 * SR / hop)); ar = np.exp(-1.0 / (release_ms / 1000 * SR / hop))
    env = np.empty(n); e = -90.0
    for i in range(n):
        c = aa if lev[i] > e else ar
        e = c * e + (1 - c) * lev[i]
        env[i] = e
    gr = np.where(env > thresh_db, (thresh_db - env) * (1 - 1 / ratio), 0.0) + makeup_db
    g = np.interp(np.arange(len(x)), np.arange(n) * hop + hop / 2, 10 ** (gr / 20))
    return x * g


def varispeed(x, semitones):
    """Tape-style speed change: pitch and tempo move together (no time-stretch artefacts)."""
    r = 2 ** (semitones / 12.0)
    n = int(round(len(x) / r))
    return signal.resample_poly(x, 1000, int(round(1000 * r)))[: n + 8]


def wow(x, wow_cents, flutter_cents, phase=0.0, runup_ms=0.0, runup_depth=0.0):
    """Speed modulation by resampling along a wobbling read head. Depths are peak deviations in cents."""
    t = np.arange(len(x)) / SR
    dev = (2 ** (wow_cents / 1200) - 1) * np.sin(2 * np.pi * 0.6 * t + phase) \
        + (2 ** (flutter_cents / 1200) - 1) * np.sin(2 * np.pi * 6.5 * t + 2.1 * phase)
    if runup_ms > 0:  # reel coming up to speed
        tau = runup_ms / 1000.0 / 3.0
        dev = dev - runup_depth * np.exp(-t / tau)
    pos = np.cumsum(1.0 + dev)
    pos = pos - pos[0]
    pos = pos[pos < len(x) - 1]
    return np.interp(pos, np.arange(len(x)), x)


def noise_band(n, lo, hi, rng):
    return filt(rng.standard_normal(n), sos("bandpass", [lo, hi], 2))


def crackle(n, rate_hz, rng, peak):
    """Sparse clicks: Poisson impulses with random size, each rung through a short resonance.
    Scaled by peak (not RMS): the largest click reaches `peak`."""
    k = rng.poisson(rate_hz * n / SR)
    y = np.zeros(n)
    if k:
        idx = rng.integers(0, n, k)
        y[idx] = rng.choice([-1.0, 1.0], k) * rng.uniform(0.25, 1.0, k) ** 2
    y = filt(y, sos("bandpass", [900, 3200], 1))
    return y * (peak / max(1e-9, float(np.max(np.abs(y))))) if k else y


def scale_to(x, ref_rms, rel_db):
    r = np.sqrt(np.mean(x ** 2) + 1e-12)
    return x * (ref_rms * 10 ** (rel_db / 20) / r)


def speech_rms(x):
    e = vx.envelope(x, SR, 10.0)
    return float(np.sqrt(np.mean(e[e > e.max() * 10 ** (-25 / 20)] ** 2)))


def bed_env(n, lead, tail, floor=0.0):
    """Noise-bed gate: fades up over `lead`, holds, fades out over `tail` (samples)."""
    env = np.ones(n)
    if lead > 0:
        env[:lead] = np.linspace(floor, 1, lead)
    if tail > 0:
        env[-tail:] = np.linspace(1, 0, tail) ** 2
    return env


def normalise_line(x, target=LINE_LUFS):
    y = x
    for _ in range(3):  # the limiter trims loudness slightly, so iterate
        y = y * 10 ** ((target - vx.lufs(y, SR)) / 20)
        y = limiter(y)
    return y


def normalise_peak(x, peak_db=ONESHOT_PEAK_DB):
    return x * (10 ** (peak_db / 20) / max(1e-9, float(np.max(np.abs(x)))))


def stt_words(id_):
    p = os.path.join(TAKES, id_ + ".stt.json")
    if not os.path.exists(p):
        return []
    return [w for w in json.load(open(p, encoding="utf-8"))["words"] if w.get("type") == "word"]


def norm_word(w):
    return re.sub(r"[^a-z0-9']", "", w.lower())


# ---------------------------------------------------------------- characters

def chain_moxie(x, j):
    x, had_tail = trim(x)
    x = filt(x, sos("highpass", 70, 2))
    return fade(x, 4, end_fade_ms(x, had_tail))


def radio_cut(x, j):
    """Apply a scripted radio cut to the raw take. Returns (voice, head_static_s, tail_static_s)."""
    cut = j.get("cut")
    if not cut:
        return x, 0.0, 0.0
    words = stt_words(j["id"])
    if cut["cut"] == "tail":   # "...And don't you d--": keep the closure and burst of the d, about 70 ms
        w = words[-1]
        assert norm_word(w["text"]).startswith("dare"), w
        t = w["start"] + 0.07
        return x[: int(t * SR)], 0.0, 0.22
    w = words[0]               # "--oxie?": drop the M, about 80 ms into the word
    assert norm_word(w["text"]).startswith("moxie"), w
    t = w["start"] + 0.08
    return x[int(t * SR):], 0.16, 0.0


def chain_radio(x, j, lo, hi, presence_db, thresh, ratio, drive, hiss_db, crackle_db, crackle_rate, semis=0.0, cuts=True):
    rng = rng_for(j["id"])
    head_s = tail_s = 0.0
    if cuts and j.get("cut"):
        x, head_s, tail_s = radio_cut(x, j)
        x = x[vx.speech_bounds(x, SR, -45.0)[0]:] if not head_s else x
        x = fade(x, 3 if not head_s else 1, 3 if tail_s else 25)
    else:
        x, had_tail = trim(x)
        x = fade(x, 4, end_fade_ms(x, had_tail))
    if semis:
        x = varispeed(x, semis)
    x = filt(x, sos("highpass", lo, 4)); x = filt(x, sos("lowpass", hi, 4))
    if presence_db:
        x = peaking(x, 1800, presence_db, 1.2)
    x = x * (0.1 / speech_rms(x))                       # speech RMS at -20 dBFS
    x = compress(x, -20.0 + thresh, ratio, 4, 90)       # threshold is relative to the speech level
    x = x * (0.2 / speech_rms(x))                       # -14 dBFS into the saturator
    if drive > 0:
        x = np.tanh(x * drive) / drive
    ref = speech_rms(x)
    lead = int(0.06 * SR) if not head_s else int(head_s * SR)
    tail = int(0.16 * SR) if not tail_s else int(tail_s * SR)
    y = np.concatenate([np.zeros(lead), x, np.zeros(tail)])
    n = len(y)
    bed = scale_to(noise_band(n, lo, hi, rng), ref, hiss_db)
    if crackle_db is not None:
        bed = bed + crackle(n, crackle_rate, rng, ref * 10 ** (crackle_db / 20))
    y = y + bed * bed_env(n, int(0.05 * SR), int(0.14 * SR))
    if head_s:   # signal coming back: a burst of static that gives way to the voice
        b = scale_to(noise_band(lead, lo, hi, rng), ref, -5.0) * np.linspace(1, 0.15, lead) ** 1.5
        y[:lead] += fade(b, 8, 2)
    if tail_s:   # signal lost: the word is swallowed by static that dies away
        b = scale_to(noise_band(tail, lo, hi, rng), ref, -4.0) * np.exp(-np.arange(tail) / (0.07 * SR))
        y[-tail:] += fade(b, 1, 30)
    return fade(y, 3, 10)


def chain_opal(x, j):
    return chain_radio(x, j, 350, 3000, 4.0, -8.0, 4.0, 1.8, -30.0, 3.0, 9.0, semis=-1.5)


def chain_tolly_dry(x, j):
    return chain_moxie(x, j)


def chain_tolly_radio(x, j):
    return chain_radio(x, j, 250, 4200, 2.0, -4.0, 2.5, 1.0, -40.0, None, 0.0)


def chain_archivist(x, j):
    rng = rng_for(j["id"])
    mode = j["expression"]
    x, had_tail = trim(x)
    x = fade(x, 4, end_fade_ms(x, had_tail))
    x = filt(x, sos("highpass", 60, 2)); x = filt(x, sos("lowpass", 9000, 2))
    x = peaking(x, 220, 1.5, 0.8)
    pad = int(0.42 * SR)
    x = np.concatenate([x, np.zeros(pad)])
    y = x.copy()
    if mode != "still":            # fixed-delay layering: doubling with a static comb, pitch untouched
        for d_ms, g_db in ((11.0, -8.0), (23.0, -12.0)):
            d = int(SR * d_ms / 1000)
            y[d:] += x[:-d] * 10 ** (g_db / 20)
    else:
        d = int(SR * 11.0 / 1000)
        y[d:] += x[:-d] * 10 ** (-14.0 / 20)
    d = int(0.35 * SR)             # print-through: the next wrap of tape, heard faintly after the line
    y[d:] += filt(x[:-d], sos("lowpass", 1800, 2)) * 10 ** (-30.0 / 20)
    ph = float(rng.uniform(0, 2 * np.pi))
    if mode == "playback":
        y = wow(y, 9.0, 3.0, ph, runup_ms=140.0, runup_depth=0.07)
    elif mode == "idle":
        y = wow(y, 4.0, 1.5, ph)
    y = y / max(1e-9, np.max(np.abs(y))) * 0.6
    y = np.tanh(y * 1.2) / np.tanh(1.2)
    ref = speech_rms(y)
    hiss = scale_to(filt(rng.standard_normal(len(y)), sos("highpass", 2500, 1)), ref, -50.0)
    y = y + hiss * bed_env(len(y), int(0.02 * SR), int(0.2 * SR), floor=0.3)
    e, _ = 0, None
    s, e = vx.speech_bounds(y, SR, -52.0)
    return fade(y[: min(len(y), e + int(0.05 * SR))], 3, 60)


CHAINS = {"moxie": [("moxie", chain_moxie)], "opal": [("opal", chain_opal)],
          "tolly": [("tolly", chain_tolly_dry), ("tolly_radio", chain_tolly_radio)],
          "archivist": [("archivist", chain_archivist)]}


# ---------------------------------------------------------------- one-shots

SLICE_LOG = {}


def vowel_onset(x):
    """Seconds from file start to the vowel (the perceptual beat): first 5 ms frame where the band below
    1 kHz reaches 25 % of its peak envelope."""
    lowb = filt(x, sos("lowpass", 1000, 4))
    e = vx.envelope(lowb, SR, 5.0)
    k = np.where(e >= 0.25 * e.max())[0]
    return float(k[0]) * 0.005 if len(k) else 0.0


def wsola(x, ratio, frame_ms=24.0, tol_ms=6.0):
    """Pitch-preserving time compression (ratio > 1 shortens). Overlap-add of Hann frames, each taken from
    the spot near its nominal position that best continues the previous frame. The first frame is copied
    in place, so the consonant onset is untouched."""
    N = int(SR * frame_ms / 1000) // 2 * 2; Hs = N // 2; tol = int(SR * tol_ms / 1000)
    win = np.hanning(N + 1)[:N]
    xp = np.concatenate([x, np.zeros(2 * N + 2 * tol + Hs)])
    nfr = max(1, int(np.ceil(len(x) / ratio / Hs)))
    out = np.zeros(nfr * Hs + N); pos = 0
    for k in range(nfr):
        if k:
            nat = xp[pos + Hs: pos + Hs + N]          # what would follow the previous frame naturally
            c = int(round(k * Hs * ratio)); lo = max(0, c - tol); hi = min(len(xp) - N, c + tol)
            if hi <= lo or len(nat) < N:
                break
            best, bv = lo, -1e30
            for q in range(lo, hi, 4):
                v = float(np.dot(nat, xp[q:q + N]))
                if v > bv:
                    best, bv = q, v
            pos = best
        out[k * Hs: k * Hs + N] += xp[pos: pos + N] * win
    out[:Hs] = xp[:Hs]                                  # undo the window on the first half-frame
    return out[: int(len(x) / ratio)]


COUNT_TARGET_S = 0.345
COUNT_MAX_RATIO = 1.30
COUNT_MAX_LEAD_S = 0.080


def slice_count(x, id_):
    """Counted phrase -> {word: samples}. Scribe says roughly where each word's vowel is; the word's real
    edges are found by walking outwards through the 4 ms envelope to the surrounding silence (Scribe's
    times leave out leading fricatives: the "s" of six starts 140 ms before its stated start). A leading
    consonant longer than 80 ms is shortened to 80 ms, then the word is tightened towards 345 ms."""
    want = ["five", "six", "seven", "eight"]
    words = [w for w in stt_words(id_) if norm_word(w["text"]) in want]
    if [norm_word(w["text"]) for w in words] != want:
        return None
    hop = int(SR * 0.004)
    env = vx.db(vx.envelope(x, SR, 4.0))
    out = {}
    for i, w in enumerate(words):
        a, b = int(w["start"] * SR / hop), min(len(env) - 1, int(w["end"] * SR / hop))
        pk = env[a:b + 1].max()
        sil = pk - 36.0
        lo_lim = 0 if i == 0 else int(words[i - 1]["end"] * SR / hop)
        hi_lim = len(env) - 1 if i == 3 else int(words[i + 1]["start"] * SR / hop)
        s_i, run = a, 0                       # backwards: stop at 40 ms of silence
        for k in range(a, lo_lim - 1, -1):
            if env[k] > sil:
                s_i, run = k, 0
            else:
                run += 1
                if run >= 10:
                    break
        e_i, run = b, 0                       # forwards: stop at 100 ms of silence (stop closures are shorter)
        for k in range(b, hi_lim + 1):
            if env[k] > sil:
                e_i, run = k, 0
            else:
                run += 1
                if run >= 25:
                    break
        if i < 3:                             # never run into the next word's leading consonant
            gap = env[b:hi_lim + 1]
            e_i = min(e_i, b + int(np.argmin(gap)))
        y = x[max(0, s_i * hop - int(0.004 * SR)): (e_i + 1) * hop + int(0.010 * SR)]
        nat = len(y) / SR
        vo = vowel_onset(y)
        if vo > COUNT_MAX_LEAD_S:
            y = fade(y[int((vo - COUNT_MAX_LEAD_S) * SR):], 12, 0)
        if len(y) / SR > COUNT_TARGET_S:      # tighten without touching pitch, then cap
            y = wsola(y, min(COUNT_MAX_RATIO, len(y) / SR / COUNT_TARGET_S))
        SLICE_LOG[f"{id_}:{norm_word(w['text'])}"] = (round(nat, 3), round(len(y) / SR, 3))
        if len(y) > int(COUNT_MAX_S * SR):
            y = fade(y[: int(COUNT_MAX_S * SR)], 2, 45)
        else:
            y = fade(y, 2, 30)
        out[norm_word(w["text"])] = filt(np.concatenate([y, np.zeros(64)]), sos("highpass", 80, 2))
    return out


def main_segment(x, gap_ms=120.0):
    """An effort take sometimes carries a breath or a second sound after a pause: keep the segment with the
    most energy (segments are split at silences longer than gap_ms)."""
    e = vx.db(vx.envelope(x, SR, 5.0)); act = e > e.max() - 30
    segs, start, quiet, last = [], None, 0, 0
    lim = int(gap_ms / 5.0)
    for i, a in enumerate(act):
        if a:
            if start is None:
                start = i
            quiet = 0; last = i
        elif start is not None:
            quiet += 1
            if quiet > lim:
                segs.append((start, last)); start = None
    if start is not None:
        segs.append((start, last))
    if len(segs) < 2:
        return x
    n = int(SR * 0.005)
    a, b = max(segs, key=lambda s: float(np.sum(x[s[0] * n:(s[1] + 1) * n] ** 2)))
    return x[max(0, a * n - int(0.01 * SR)): min(len(x), (b + 1) * n + int(0.12 * SR))]


def oneshot(x, pick=False):
    if pick:
        x = main_segment(x)
    x, had_tail = trim(x, pre_ms=4.0, tail_ms=120.0, thresh_db=-40.0)
    x = filt(x, sos("highpass", 80, 2))
    return fade(x, 2, 40 if had_tail else 60)


def main():
    pat = re.compile(sys.argv[1]) if len(sys.argv) > 1 else None
    done = 0
    for j in script_lines.all_jobs():
        id_ = j["id"]
        src = os.path.join(TAKES, id_ + ".wav")
        if not os.path.exists(src) or (pat and not pat.search(id_)):
            continue
        x, _ = vx.read_wav(src)
        x = x.astype(np.float64)
        if j["kind"] in ("line", "bark"):
            for folder, fn in CHAINS[j["who"]]:
                vx.write_wav(os.path.join(OUT, folder, id_ + ".wav"), normalise_line(fn(x, j)))
        elif j["kind"] == "countsrc":
            parts = slice_count(x, id_)
            if parts is None:
                print("count slice failed:", id_); continue
            _, style, take = id_.split("_")
            for w, y in parts.items():
                vx.write_wav(os.path.join(OUT, "count", f"count_{w}_{style}_{take}.wav"), normalise_peak(y))
        elif j["kind"] == "call":
            vx.write_wav(os.path.join(OUT, "calls", id_ + ".wav"), normalise_peak(oneshot(x)))
        elif j["kind"] == "effort":
            vx.write_wav(os.path.join(OUT, "efforts", id_ + ".wav"), normalise_peak(oneshot(x, pick=True)))
        done += 1
    print("processed", done)
    for k, v in SLICE_LOG.items():
        print("  count", k, "natural", v[0], "s ->", v[1], "s")


if __name__ == "__main__":
    main()
