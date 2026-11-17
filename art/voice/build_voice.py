"""Builds OVERDUB's synthetic voice set with formant synthesis (no speech model was reachable).

  python -I art/voice/build_voice.py            # render everything, write manifest + report
  python -I art/voice/build_voice.py --plots    # also write spectrogram sheets (art/voice/report/*.png)

Outputs
  assets/audio/voice/count/<word>_<style><take>.wav       spoken / whispered / shouted count-in one-shots
  assets/audio/voice/count/pitched/<word>_p<midi>.wav     the same words intoned on each chromatic pitch
  assets/audio/voice/efforts/<name>.wav                   experimental non-verbal efforts
  assets/audio/voice/manifest.json                        ids -> file, text, duration, onset, loudness
  art/voice/source/<same tree>.wav                        untrimmed, un-normalised 32-bit float takes
  art/voice/report/loudness.json|md                       per-file measurements and pass/fail
All files: 44.1 kHz, mono, 16-bit PCM WAV.
"""
import hashlib, json, os, sys
import numpy as np
from scipy.io import wavfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import formant as fm
from formant import Utt, FS

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "voice")
SRC = os.path.join(HERE, "source")
REP = os.path.join(HERE, "report")
RES = "res://assets/audio/voice/"
TARGET_LKFS = -16.0
COUNT_MAX_MS = 350.0
WORDS = {"five": 5, "six": 6, "seven": 7, "eight": 8}
# spoken count climbs a little towards "eight" (the pickup into the take)
WORD_PITCH = {"five": 1.00, "six": 1.03, "seven": 1.06, "eight": 1.12}


def midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


# ---------------------------------------------------------------------------------------------
# the four words.  p = base f0 (Hz), ds = duration scale, mv = pitch-movement scale (0 = intoned flat)

def w_five(p, ds=1.0, mv=1.0):
    d = lambda ms: ms * ds
    u = Utt(f0=p * (1 + 0.04 * mv - (0.03 if mv == 0 else 0)), F1=700, F2=1150, F3=2700)
    u.noise("f", 0, d(80), 0.13, attack=d(26), release=14)           # /f/
    u.seg(d(66)).mark("vowel")
    u.seg(d(14), av=1.0, F1=860, F2=1350)                            # voice onset out of the lip
    u.seg(d(55), F1=880, F2=1420, F3=2750, f0=p)                     # /a/
    u.seg(d(90), F1=480, F2=2150, F3=2900, f0=p * (1 - 0.07 * mv))   # glide to /I/
    u.seg(d(20), av=0.45, F1=380, F2=1500, F3=2600)                  # lip closes for /v/
    tv = u.t
    u.seg(d(45), av=0.12, f0=p * (1 - 0.11 * mv))
    u.seg(8, av=0.0)
    u.noise("f", tv - 5, d(56), 0.075, attack=15, release=22)        # /v/ friction
    return u


def w_six(p, ds=1.0, mv=1.0):
    d = lambda ms: ms * ds
    u = Utt(f0=p * (1 + 0.03 * mv - (0.03 if mv == 0 else 0)), F1=400, F2=2200, F3=3000)
    u.noise("s", 0, d(82), 0.42, attack=d(24), release=16)           # /s/
    u.seg(d(68)).mark("vowel")
    u.seg(d(12), av=1.0, F1=440, F2=2330, F3=3050)
    u.seg(d(40), f0=p)                                               # /I/
    u.seg(d(22), F2=2520, F3=2760, f0=p * (1 - 0.03 * mv))           # velar pinch (F2 meets F3)
    u.seg(d(10), av=0.0, F1=320)
    u.seg(d(42))                                                     # /k/ closure
    tb = u.t
    u.noise("k", tb, 26, 0.50, attack=1, release=8, decay=9)         # /k/ burst
    u.noise("s", tb + 14, d(96), 0.36, attack=14, release=d(46))     # /s/
    u.seg(d(110))
    return u


def w_seven(p, ds=1.0, mv=1.0):
    d = lambda ms: ms * ds
    u = Utt(f0=p * (1 + 0.04 * mv - (0.03 if mv == 0 else 0)), F1=560, F2=2000, F3=2900)
    u.noise("s", 0, d(76), 0.42, attack=d(22), release=16)           # /s/
    u.seg(d(62)).mark("vowel")
    u.seg(d(12), av=1.0, F1=620, F2=2050, F3=2950)
    u.seg(d(55), f0=p)                                               # /E/
    u.seg(d(16), av=0.5, F1=400, F2=1450, F3=2600)                   # /v/
    tv = u.t
    u.seg(d(26))
    u.noise("f", tv - 4, d(34), 0.06, attack=10, release=12)
    u.seg(d(16), av=0.8, F1=520, F2=1650, F3=2800, f0=p * (1 - 0.05 * mv))   # schwa
    u.seg(d(28))
    u.seg(d(16), av=0.5, F1=280, F2=1750, F3=2650, B1=90, B2=380, B3=450)    # /n/ murmur
    u.seg(d(68), av=0.28, f0=p * (1 - 0.10 * mv))
    u.seg(14, av=0.0)
    return u


def w_eight(p, ds=1.0, mv=1.0):
    d = lambda ms: ms * ds
    u = Utt(f0=p * (1 - 0.03 * mv - (0.03 if mv == 0 else 0)), F1=540, F2=2250, F3=3000)
    u.mark("vowel")
    u.seg(7, av=1.0)                                                 # hard (glottal) attack
    u.seg(d(60), f0=p * (1 + 0.02 * mv))                             # /e/
    u.seg(d(88), F1=400, F2=2550, F3=3100, f0=p * (1 + 0.05 * mv))   # glide to /I/
    u.seg(d(12), av=0.0, F1=300, F2=2000)
    u.seg(d(46))                                                     # /t/ closure
    tb = u.t
    u.noise("t", tb, 20, 0.60, attack=1, release=6, decay=7)         # /t/ burst
    u.noise("t", tb + 8, d(55), 0.22, attack=6, release=d(30), decay=d(22))  # release aspiration
    u.seg(d(64))
    return u


WORD_FN = {"five": w_five, "six": w_six, "seven": w_seven, "eight": w_eight}


def scale_track(u, name, k):
    u.keys[name] = [(t, v * k) for t, v in u.keys[name]]


# takes: (style letter, take number, base f0, duration scale, pitch movement, render kwargs)
SPOKEN = [
    ("n", 1, 208.0, 1.00, 1.0, dict(mode="modal", breath=0.25)),
    ("n", 2, 199.0, 0.93, 0.6, dict(mode="modal", breath=0.15)),   # drier, flatter, tighter
    ("n", 3, 216.0, 1.05, 1.4, dict(mode="modal", breath=0.35)),   # more sing-song
    ("w", 1, 208.0, 1.02, 1.0, dict(mode="whisper", fric_gain=1.5)),
    ("w", 2, 208.0, 0.95, 1.0, dict(mode="whisper", fric_gain=1.7)),
    ("s", 1, 318.0, 1.06, 1.3, dict(mode="shout", fric_gain=0.9)),
    ("s", 2, 300.0, 1.00, 1.8, dict(mode="shout", fric_gain=0.9)),
]
STYLE_NAME = {"n": "normal", "w": "whisper", "s": "shout", "p": "pitched"}
PITCHED_MIDI = list(range(55, 67))  # G3 .. F#4: one file per pitch class


# ---------------------------------------------------------------------------------------------
# experimental non-verbal efforts

def e_breath(v):
    u = Utt(F1=[650, 600][v], F2=[1500, 1900][v], F3=2700)
    u.seg(12, av=1.0)
    u.seg([80, 60][v], av=0.8, F1=600)
    u.seg([110, 90][v], av=0.0, F1=520, F2=1400)
    return u, dict(mode="whisper"), "breath"


def e_sigh():
    u = Utt(f0=262, F1=720, F2=1400, F3=2700, B1=120)
    u.seg(40, ah=0.7)
    u.seg(60, av=0.55, f0=250)
    u.seg(260, av=0.35, ah=0.8, f0=185, F1=560, F2=1500)
    u.seg(110, av=0.0, ah=0.6, f0=168)
    u.seg(160, ah=0.0, F1=500)
    return u, dict(mode="modal", breath=1.4), "sigh"


def e_hm():
    u = Utt(f0=196, F1=270, F2=1250, F3=2500, B1=70, B2=400, B3=500)
    u.seg(18, av=0.7)
    u.seg(110, f0=228)
    u.seg(150, av=0.5, f0=178)
    u.seg(40, av=0.0)
    return u, dict(mode="modal", breath=0.2), "hm"


def e_grunt(v):
    f0 = [262, 284, 247, 298][v]
    F = [(760, 1350), (640, 1900), (700, 1250), (560, 2100)][v]
    dur = [95, 80, 110, 70][v]
    u = Utt(f0=f0 * 1.05, F1=F[0], F2=F[1], F3=2800)
    u.seg(22, ah=0.8)                                  # h-
    u.seg(8, av=1.0, ah=0.2)
    u.seg(dur * 0.5, f0=f0)
    u.seg(dur * 0.5, av=0.7, f0=f0 * 0.84, F1=F[0] * 0.9)
    u.seg(9, av=0.0, ah=0.0)                           # glottal cut
    u.seg(20)
    return u, dict(mode="shout", breath=0.2), "grunt"


def e_shout(v):
    f0 = [345, 370, 320][v]
    u = Utt(f0=f0 * 0.94, F1=[900, 480, 950][v], F2=[1500, 2400, 1450][v], F3=2850)
    u.seg(30, ah=0.9)
    u.seg(10, av=1.0, ah=0.25, f0=f0)
    u.seg([70, 60, 90][v], F1=[980, 950, 980][v], F2=[1500, 1550, 1400][v])
    u.seg([150, 170, 120][v], av=0.8, f0=f0 * [0.78, 0.74, 0.8][v], F1=880)
    u.seg(30, av=0.0, ah=0.5)
    u.seg(60, ah=0.0)
    return u, dict(mode="shout", breath=0.3), "shout"


def e_hit(v):
    if v == 0:    # "ah!"
        u = Utt(f0=390, F1=900, F2=1550, F3=2900)
        u.seg(6, av=1.0)
        u.seg(60, f0=360)
        u.seg(90, av=0.5, f0=285, F1=800)
        u.seg(25, av=0.0, ah=0.4)
        u.seg(50, ah=0.0)
        return u, dict(mode="shout", breath=0.3), "hit"
    if v == 1:    # "ugh"
        u = Utt(f0=268, F1=620, F2=1100, F3=2600)
        u.seg(8, av=1.0)
        u.seg(70, f0=250)
        u.seg(100, av=0.5, f0=200, F1=520, F2=1000)
        u.seg(20, av=0.0, ah=0.5)
        u.seg(70, ah=0.0)
        return u, dict(mode="shout", breath=0.4), "hit"
    # death: long falling "aaugh" into breath
    u = Utt(f0=335, F1=920, F2=1500, F3=2850)
    u.seg(10, av=1.0)
    u.seg(120, f0=320)
    u.seg(260, av=0.7, f0=215, F1=620, F2=980)
    u.seg(140, av=0.25, ah=0.6, f0=170, F1=540)
    u.seg(60, av=0.0)
    u.seg(160, ah=0.0)
    return u, dict(mode="shout", breath=0.5), "death"


def e_laugh():
    u = Utt(f0=280, F1=640, F2=1950, F3=2900)
    for i, (f0, a) in enumerate([(282, 1.0), (252, 0.8), (222, 0.6)]):
        u.seg(34, ah=0.8 * a, av=0.0, f0=f0 * 1.04)
        u.seg(8, av=a, ah=0.15)
        u.seg(58, f0=f0 * 0.95)
        u.seg(10, av=0.0, ah=0.0)
        u.seg(34)
    return u, dict(mode="modal", breath=0.5), "laugh"


EFFORTS = [
    ("attack_light_1", lambda: e_grunt(0), "light attack grunt"),
    ("attack_light_2", lambda: e_grunt(1), "light attack grunt"),
    ("attack_light_3", lambda: e_grunt(2), "light attack grunt"),
    ("attack_light_4", lambda: e_grunt(3), "light attack grunt"),
    ("attack_heavy_1", lambda: e_shout(0), "heavy attack shout"),
    ("attack_heavy_2", lambda: e_shout(1), "heavy attack shout"),
    ("attack_heavy_3", lambda: e_shout(2), "heavy attack shout"),
    ("dodge_1", lambda: e_breath(0), "dodge breath"),
    ("dodge_2", lambda: e_breath(1), "dodge breath"),
    ("hit_1", lambda: e_hit(0), "hit reaction"),
    ("hit_2", lambda: e_hit(1), "hit reaction"),
    ("death_1", lambda: e_hit(2), "death cry"),
    ("laugh_1", e_laugh, "laugh"),
    ("hm_1", e_hm, "hm"),
    ("sigh_1", e_sigh, "sigh"),
]


# ---------------------------------------------------------------------------------------------

def write(rel, raw, target=TARGET_LKFS):
    """Save the raw take (float32) under art/voice/source and the mastered one under assets/."""
    src = os.path.join(SRC, rel)
    os.makedirs(os.path.dirname(src), exist_ok=True)
    wavfile.write(src, FS, (raw / (np.abs(raw).max() + 1e-9) * 0.5).astype(np.float32))
    x, lead_ms = fm.master(raw, target_lkfs=target)
    dst = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    pcm = fm.to_int16(x)
    wavfile.write(dst, FS, pcm)
    return pcm, lead_ms


def check(pcm, max_ms=None):
    """Re-measure the written PCM. Returns (stats, problems)."""
    x = pcm.astype(np.float64) / 32768.0
    st = fm.stats(x)
    bad = []
    if int(np.sum(np.abs(pcm.astype(np.int32)) >= 32767)) > 0:
        bad.append("clipped")
    if st["peak_dbfs"] > -0.9:
        bad.append("peak above ceiling")
    if st["peak_dbfs"] < -14.0:
        bad.append("too quiet")
    if abs(st["lkfs"] - TARGET_LKFS) > 1.0:
        bad.append("loudness off target")
    edge = int(0.002 * FS)
    pk = np.abs(x).max()
    if np.abs(x[:8]).max() > 0.05 * pk or np.abs(x[-edge:]).max() > 0.05 * pk:
        bad.append("truncated edge")
    if abs(st["dc"]) > 0.002:
        bad.append("dc offset")
    if max_ms is not None and st["duration_ms"] > max_ms:
        bad.append("too long (%.0f ms)" % st["duration_ms"])
    if st["duration_ms"] < 60:
        bad.append("too short")
    return st, bad


def build():
    entries, index, problems = {}, {"normal": {}, "whisper": {}, "shout": {}, "pitched": {}}, []
    rendered = {}

    def add(id_, rel, text, kind, style, raw, extra, max_ms=None, vowel_ms=None, target=TARGET_LKFS):
        pcm, lead_ms = write(rel, raw, target)
        st, bad = check(pcm, max_ms)
        e = dict(file=RES + rel.replace(os.sep, "/"), text=text, kind=kind, style=style)
        e.update(extra)
        e.update(duration_ms=st["duration_ms"], peak_dbfs=st["peak_dbfs"], rms_dbfs=st["rms_dbfs"], lkfs=st["lkfs"])
        if vowel_ms is not None:
            e["onset_ms"] = round(max(0.0, vowel_ms - lead_ms), 1)
        entries[id_] = e
        rendered[id_] = pcm
        if bad:
            problems.append((id_, bad))
        return e

    for word, n in WORDS.items():
        for style, take, p, ds, mv, kw in SPOKEN:
            f0 = p * WORD_PITCH[word]
            u = WORD_FN[word](f0, ds, mv)
            if style == "s":
                scale_track(u, "F1", 1.13)   # open jaw
            raw = fm.render(u, seed=1000 * n + 10 * take + ord(style), **kw)
            id_ = "count.%s.%s%d" % (word, style, take)
            add(id_, os.path.join("count", "%s_%s%d.wav" % (word, style, take)), word, "count", STYLE_NAME[style], raw,
                dict(n=n, take=take, f0_hz=(None if style == "w" else round(f0, 1))), COUNT_MAX_MS, u.marks["vowel"])
            index[STYLE_NAME[style]].setdefault(str(n), []).append(id_)
        for m in PITCHED_MIDI:
            f0 = midi_hz(m)
            u = WORD_FN[word](f0, 1.0, 0.0)
            raw = fm.render(u, seed=5000 * n + m, mode="modal", breath=0.2)
            id_ = "count.%s.p%d" % (word, m)
            add(id_, os.path.join("count", "pitched", "%s_p%d.wav" % (word, m)), word, "count", "pitched", raw,
                dict(n=n, midi=m, pitch_class=m % 12, f0_hz=round(f0, 2)), COUNT_MAX_MS, u.marks["vowel"])
            index["pitched"].setdefault(str(n), {})[str(m % 12)] = id_

    efforts = {}
    for i, (name, fn, text) in enumerate(EFFORTS):
        u, kw, kind = fn()
        raw = fm.render(u, seed=9000 + i, **kw)
        id_ = "effort." + name
        add(id_, os.path.join("efforts", name + ".wav"), text, "effort", kind, raw, dict(experimental=True))
        efforts.setdefault(name.rsplit("_", 1)[0], []).append(id_)

    # bark ids (text only: no speech model was reachable, so no files)
    barks = {}
    sp = os.path.join(ROOT, "data", "story", "story.json")
    if os.path.exists(sp):
        story = json.load(open(sp, encoding="utf-8"))
        for group, lines in (story.get("barks") or {}).items():
            for i, ln in enumerate(lines):
                if ln.get("who", "moxie") != "moxie":
                    continue
                txt = ln.get("line", "")
                h = hashlib.sha1(txt.encode("utf-8")).hexdigest()[:8]
                barks["bark.%s.%02d" % (group, i)] = dict(group=group, index=i, expression=ln.get("expression"),
                                                           text=txt, text_sha1=h, file=None, duration_ms=None)

    manifest = dict(
        version=1,
        generator="art/voice/build_voice.py (formant synthesis; no speech model available)",
        format=dict(sample_rate=FS, channels=1, bits=16, container="wav"),
        target_lkfs=TARGET_LKFS, peak_ceiling_dbfs=-1.0,
        suggested_gain_db=dict(normal=0.0, pitched=0.0, whisper=-5.0, shout=1.5, effort=-2.0),
        count=index, efforts=efforts, entries=entries, barks=barks)
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
        f.write("\n")

    os.makedirs(REP, exist_ok=True)
    with open(os.path.join(REP, "loudness.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(dict(problems=[dict(id=i, problems=b) for i, b in problems],
                       files={k: {a: v[a] for a in ("file", "duration_ms", "onset_ms", "peak_dbfs", "rms_dbfs", "lkfs") if a in v}
                              for k, v in entries.items()}), f, indent=1)
    with open(os.path.join(REP, "loudness.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("| id | ms | onset ms | peak dBFS | RMS dBFS | LKFS | check |\n|---|---|---|---|---|---|---|\n")
        pb = dict(problems)
        for k, v in entries.items():
            f.write("| %s | %.0f | %s | %.1f | %.1f | %.1f | %s |\n" % (
                k, v["duration_ms"], ("%.0f" % v["onset_ms"]) if "onset_ms" in v else "-", v["peak_dbfs"], v["rms_dbfs"], v["lkfs"],
                "; ".join(pb[k]) if k in pb else "ok"))
    print("files: %d   barks listed (no audio): %d   problems: %d" % (len(entries), len(barks), len(problems)))
    for i, b in problems:
        print("  PROBLEM", i, b)
    durs = [v["duration_ms"] for v in entries.values() if v["kind"] == "count"]
    print("count durations: min %.0f  max %.0f ms" % (min(durs), max(durs)))
    return entries, rendered


def phrase(rendered, entries, ids, bpm=120.0, lead_ms=250.0):
    """Lay four count one-shots on a beat grid with each word's vowel onset on the beat."""
    beat = 60.0 / bpm
    n = int((lead_ms / 1000.0 + 4 * beat + 0.3) * FS)
    y = np.zeros(n)
    for i, id_ in enumerate(ids):
        x = rendered[id_].astype(np.float64) / 32768.0
        s = int((lead_ms / 1000.0 + i * beat - entries[id_].get("onset_ms", 0.0) / 1000.0) * FS)
        y[s:s + len(x)] += x
    return y


def plots(entries, rendered):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from scipy import signal

    def spec(ax, x, title, fmax=9000):
        f, t, S = signal.spectrogram(x, FS, window="hann", nperseg=384, noverlap=352, nfft=1024)
        S = 10 * np.log10(S + 1e-12)
        ax.pcolormesh(t * 1000, f, S, vmin=S.max() - 62, vmax=S.max(), cmap="magma", shading="auto")
        ax.set_ylim(0, fmax)
        ax.set_title(title, fontsize=8)
        ax.tick_params(labelsize=6)

    cols = [("n1", "normal take 1"), ("n2", "normal take 2"), ("w1", "whisper 1"), ("s1", "shout 1"), ("p60", "pitched C4")]
    fig, axs = plt.subplots(4, len(cols), figsize=(3.2 * len(cols), 9), constrained_layout=True)
    for r, word in enumerate(WORDS):
        for c, (suf, label) in enumerate(cols):
            id_ = "count.%s.%s" % (word, suf)
            x = rendered[id_].astype(np.float64) / 32768.0
            spec(axs[r][c], x, "%s  %s  (%.0f ms, onset %.0f)" % (word, label, entries[id_]["duration_ms"], entries[id_]["onset_ms"]))
            axs[r][c].axvline(entries[id_]["onset_ms"], color="cyan", lw=0.6, ls=":")
    fig.savefig(os.path.join(REP, "spectrograms_count.png"), dpi=110)
    plt.close(fig)

    fig, axs = plt.subplots(2, 1, figsize=(13, 6.5), constrained_layout=True)
    ids = ["count.%s.n1" % w for w in WORDS]
    y = phrase(rendered, entries, ids, 120.0)
    spec(axs[0], y, "five six seven eight - normal take 1 at 120 bpm (vowel onsets on the beat: dotted lines)")
    for i in range(4):
        axs[0].axvline(250 + i * 500, color="cyan", lw=0.6, ls=":")
    tt = np.arange(len(y)) * 1000.0 / FS
    axs[1].plot(tt, y, lw=0.4)
    axs[1].set_xlim(0, tt[-1])
    axs[1].set_title("waveform", fontsize=8)
    fig.savefig(os.path.join(REP, "phrase_120bpm.png"), dpi=110)
    plt.close(fig)

    names = [n for n, _, _ in EFFORTS]
    fig, axs = plt.subplots(3, 5, figsize=(16, 7.5), constrained_layout=True)
    for i, nm in enumerate(names):
        id_ = "effort." + nm
        spec(axs[i // 5][i % 5], rendered[id_].astype(np.float64) / 32768.0, "%s (%.0f ms)" % (nm, entries[id_]["duration_ms"]), 7000)
    fig.savefig(os.path.join(REP, "spectrograms_efforts.png"), dpi=110)
    plt.close(fig)
    print("plots written to", REP)


if __name__ == "__main__":
    entries, rendered = build()
    # phrases for listening / transcription checks
    ph = os.path.join(REP, "phrases")
    os.makedirs(ph, exist_ok=True)
    for suf in ["n1", "n2", "n3", "w1", "w2", "s1", "s2", "p55", "p60", "p64"]:
        for bpm in ([90, 120, 150] if suf == "n1" else [120]):
            y = phrase(rendered, entries, ["count.%s.%s" % (w, suf) for w in WORDS], float(bpm))
            wavfile.write(os.path.join(ph, "count_%s_%dbpm.wav" % (suf, bpm)), FS, fm.to_int16(y))
    if "--plots" in sys.argv:
        plots(entries, rendered)
