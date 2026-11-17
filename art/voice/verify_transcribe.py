"""Objective intelligibility check: send the synthetic count through the proxy's transcription model.
Writes art/voice/report/transcripts.json.   python -I art/voice/verify_transcribe.py [phrases|words|all]
No prompt/hint is given to the transcriber, so a correct result is not primed."""
import json, os, re, sys, tempfile
import numpy as np
from scipy.io import wavfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import transcribe as tr

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "voice")
REP = os.path.join(HERE, "report")
NUM = {"5": "five", "6": "six", "7": "seven", "8": "eight"}


def norm(t):
    t = t.lower()
    for k, v in NUM.items():
        t = t.replace(k, " " + v + " ")
    return " ".join(re.findall(r"[a-z']+", t))


def main(what):
    res = {"model": "gpt-4o-transcribe", "phrases": {}, "words": {}}
    path = os.path.join(REP, "transcripts.json")
    if os.path.exists(path):
        old = json.load(open(path))
        res["phrases"] = old.get("phrases", {}) if what == "words" else {}
        res["words"] = old.get("words", {}) if what == "phrases" else {}
    if what in ("phrases", "all"):
        d = os.path.join(REP, "phrases")
        for fn in sorted(os.listdir(d)):
            s, text = tr.transcribe(os.path.join(d, fn))
            ok = norm(text) == "five six seven eight"
            res["phrases"][fn] = dict(status=s, text=text, exact=ok, words_found=[w for w in NUM.values() if w in norm(text).split()])
            print(fn, s, repr(text), "OK" if ok else "")
    if what in ("words", "all"):
        man = json.load(open(os.path.join(OUT, "manifest.json"), encoding="utf-8"))
        tmp = tempfile.mkdtemp()
        for id_, e in man["entries"].items():
            if e["kind"] != "count" or (e["style"] == "pitched" and e["midi"] not in (55, 60, 64)):
                continue
            fs, x = wavfile.read(os.path.join(ROOT, e["file"].replace("res://", "")))
            pad = np.zeros(int(0.3 * fs), dtype=np.int16)
            p = os.path.join(tmp, id_ + ".wav")
            wavfile.write(p, fs, np.concatenate([pad, x, pad]))
            s, text = tr.transcribe(p)
            ok = norm(text) == e["text"]
            res["words"][id_] = dict(status=s, text=text, exact=ok)
            print(id_, s, repr(text), "OK" if ok else "")
            os.remove(p)
    for k in ("phrases", "words"):
        if res[k]:
            res[k + "_exact"] = "%d/%d" % (sum(1 for v in res[k].values() if isinstance(v, dict) and v["exact"]), len(res[k]))
    json.dump(res, open(path, "w"), indent=1)
    print({k: v for k, v in res.items() if k.endswith("_exact")})


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "all")
