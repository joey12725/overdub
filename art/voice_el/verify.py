"""Verify the takes and the exported set. Writes art/voice_el/verify.json and prints every failure.

Per raw take (needs takes/<id>.stt.json from stt.sh):
  words     Scribe's transcript equals the script words (homophones and spelling variants tolerated)
  ending    the last script word is present in the transcript (a truncated take loses or mangles it)
Per exported file:
  format    44.1 kHz, mono, 16-bit
  peak      below -0.5 dBFS (never 0)
  duration  between syllables/8 and syllables/1.4 + 1.2 s (lines); one-shots within their own bounds
  gap       no internal silence longer than 0.9 s (1.3 s if the line contains an ellipsis)
  decay     last 50 ms at least 9 dB under the speech level, final 2 ms under -45 dBFS
  loudness  lines within 1 LU of the -18 LUFS target (takes shorter than 1.0 s are exempt: BS.1770 gating is unreliable there)

usage: python -I art/voice_el/verify.py"""
import difflib, glob, json, os, re, sys, wave
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vx, script_lines, process

HERE = os.path.dirname(os.path.abspath(__file__))
TAKES, OUT = process.TAKES, process.OUT
EQUIV = [{"ow", "oh", "ow!", "o"}, {"okay", "ok"}, {"mm", "hmm", "hm", "mhm", "mmm"}, {"ooh", "oh", "oo"},
         {"huh", "ha"}, {"tolly", "tali", "tully", "tolley", "tali", "toli", "tollie", "tally", "dolly"},
         {"moxie", "moxy", "moxi"}, {"1", "one"}, {"2", "two", "too", "to"}, {"3", "three"}, {"4", "four", "for"},
         {"asis", "as"}, {"rumour", "rumor"}, {"youre", "your"}, {"its", "it's"}, {"11", "eleven"}, {"40", "forty"},
         {"20", "twenty"}, {"60", "sixty"}, {"somebody", "someone"}]


# Transcript differences accepted after inspection (Scribe's language model, not the performance).
WAIVED = {
    "l06_intro_01": "Scribe hears 'Mine the next room' for 'Mind the next room': /d/ assimilated before 'the'",
    "l06_intro_02": "Scribe spells the isolated 'How' as 'Hao'",
    "l09_intro_04": "Scribe splits the name 'Opal' as 'Oh pal'",
    "bark_archivistrecall_03": "'Read' is the past participle, correctly pronounced 'red'",
    "bark_bossrecall_02": "three takes, all heard as 'I kept the receipt' for 'It kept the receipt': unreleased /t/ before /k/",
}
MAX_GAP = {"l06_outro_01": 1.0}   # "...as bait. Twice." - the beat before "Twice" is the line


def words_of(text):
    text = text.lower().replace("-", " ")
    return [re.sub(r"[^a-z0-9]", "", w) for w in re.findall(r"[a-z0-9']+", text) if re.sub(r"[^a-z0-9]", "", w)]


def same(a, b):
    return a == b or any(a in s and b in s for s in EQUIV)


def compare(script, heard):
    a, b = words_of(script), words_of(heard)
    if len(a) == len(b) and all(same(x, y) for x, y in zip(a, b)):
        return True, ""
    sm = difflib.SequenceMatcher(None, a, b)
    diffs = [f"{tag}:{' '.join(a[i1:i2])}>{' '.join(b[j1:j2])}" for tag, i1, i2, j1, j2 in sm.get_opcodes()
             if tag != "equal" and not (tag == "replace" and i2 - i1 == j2 - j1 and all(same(x, y) for x, y in zip(a[i1:i2], b[j1:j2])))]
    return (len(diffs) == 0), "; ".join(diffs)


def check_file(path, kind, nsyl, text, target=None, max_gap=None):
    fails = []
    with wave.open(path, "rb") as w:
        fmt = (w.getframerate(), w.getnchannels(), w.getsampwidth())
    if fmt != (44100, 1, 2):
        fails.append(f"format {fmt}")
    x, _ = vx.read_wav(path)
    m = vx.measure(x, text)
    dur = len(x) / vx.SR
    if m["peak_db"] > -0.5:
        fails.append(f"peak {m['peak_db']}")
    if kind in ("line", "bark"):
        lo, hi = nsyl / 8.0, nsyl / 1.4 + 1.2
        if not (lo <= dur <= hi):
            fails.append(f"duration {dur:.2f}s for {nsyl} syllables")
        if m["max_gap"] > (max_gap or (1.3 if "..." in text else 0.9)):
            fails.append(f"gap {m['max_gap']}s")
        if target is not None and m["dur"] >= 1.0 and abs(m["lufs"] - target) > 1.0:
            fails.append(f"loudness {m['lufs']}")
    elif kind == "count":
        if not (0.12 <= dur <= 0.40):
            fails.append(f"duration {dur:.3f}s")
    elif kind in ("call", "effort"):
        if not (0.08 <= dur <= 2.5):
            fails.append(f"duration {dur:.3f}s")
    speech = vx.rms_db(x[np.abs(x) > 10 ** (-40 / 20)]) if np.any(np.abs(x) > 0.01) else -90
    last50 = vx.rms_db(x[-int(0.05 * vx.SR):]); last2 = vx.rms_db(x[-int(0.002 * vx.SR):])
    if last50 > speech - 9:
        fails.append(f"no decay: last 50 ms {last50:.1f} dB vs speech {speech:.1f} dB")
    if last2 > -45:
        fails.append(f"final 2 ms {last2:.1f} dBFS")
    m["file_dur"] = round(dur, 3)
    return fails, m


def main():
    report, bad, waived = {}, [], []
    for j in script_lines.all_jobs():
        id_ = j["id"]; r = {"kind": j["kind"], "who": j["who"]}
        if not os.path.exists(os.path.join(TAKES, id_ + ".wav")):
            r["missing"] = True; report[id_] = r; bad.append((id_, "NOT RECORDED")); continue
        spoken = vx.strip_tags(j["send"])
        sp = os.path.join(TAKES, id_ + ".stt.json")
        if os.path.exists(sp):
            st = json.load(open(sp, encoding="utf-8"))
            heard = "".join(w["text"] for w in st["words"] if w.get("type") != "audio_event")
            r["heard"] = heard.strip()
            r["events"] = [w["text"] for w in st["words"] if w.get("type") == "audio_event"]
            if j["kind"] != "effort":
                ok, diff = compare(spoken, heard)
                r["words_ok"] = ok
                if not ok and id_ in WAIVED:
                    r["words_waived"] = WAIVED[id_]; waived.append((id_, diff))
                elif not ok:
                    bad.append((id_, f"words: {diff}   heard: {heard.strip()!r}"))
        else:
            r["words_ok"] = None; bad.append((id_, "no transcript"))
        nsyl = vx.syllables(j["line"])
        files = []
        if j["kind"] in ("line", "bark"):
            files = [(os.path.join(OUT, folder, id_ + ".wav"), j["kind"]) for folder, _ in process.CHAINS[j["who"]]]
        elif j["kind"] == "countsrc":
            _, style, take = id_.split("_")
            files = [(os.path.join(OUT, "count", f"count_{w}_{style}_{take}.wav"), "count") for w in ("five", "six", "seven", "eight")]
        elif j["kind"] == "call":
            files = [(os.path.join(OUT, "calls", id_ + ".wav"), "call")]
        elif j["kind"] == "effort":
            files = [(os.path.join(OUT, "efforts", id_ + ".wav"), "effort")]
        r["files"] = {}
        for p, kind in files:
            rel = os.path.relpath(p, OUT).replace("\\", "/")
            if not os.path.exists(p):
                bad.append((id_, f"missing output {rel}")); continue
            fails, m = check_file(p, kind, nsyl, j["line"], process.LINE_LUFS if kind in ("line", "bark") else None, MAX_GAP.get(id_))
            r["files"][rel] = {"fails": fails, **m}
            for f in fails:
                bad.append((id_, f"{rel}: {f}"))
        report[id_] = r
    json.dump(report, open(os.path.join(HERE, "verify.json"), "w", encoding="utf-8"), indent=1)
    nfiles = sum(len(r.get("files", {})) for r in report.values())
    print(f"{len(report)} jobs, {nfiles} files checked, {len(bad)} problems, {len(waived)} transcript differences waived")
    for id_, d in waived:
        print(f"  waived {id_:24} {d}  ({WAIVED[id_]})")
    for id_, msg in bad:
        print(f"  {id_:24} {msg}")


if __name__ == "__main__":
    main()
