"""Write assets/audio/voice/elevenlabs/manifest.json from the exported files.
usage: python -I art/voice_el/manifest.py   (after process.py and verify.py)"""
import json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vx, script_lines, process

OUT = process.OUT
TREATMENT = {"moxie": "dry", "opal": "radio", "tolly": "dry", "archivist": "tape"}
SKIP = set()   # ids to leave out of the manifest (takes that failed verification and could not be re-recorded)


def info(rel):
    x, _ = vx.read_wav(os.path.join(OUT, rel))
    return x, round(len(x) / vx.SR, 3)


def main():
    skip_path = os.path.join(process.HERE, "rejected.json")
    rejected = json.load(open(skip_path)) if os.path.exists(skip_path) else {}
    man = {
        "version": 1,
        "source": "ElevenLabs text-to-speech; see docs/VOICE-CAST.md",
        "base": "res://assets/audio/voice/elevenlabs/",
        "format": {"sampleRate": 44100, "channels": 1, "bits": 16, "container": "wav"},
        "loudness": {"linesLUFS": process.LINE_LUFS, "linesCeilingDbfs": process.CEIL_DB, "oneShotPeakDbfs": process.ONESHOT_PEAK_DB},
        "cast": {k: {"voice": v["voice"], "voiceId": v["voice_id"], "model": v["model"], "settings": v["settings"],
                     "treatment": TREATMENT[k]} for k, v in script_lines.CAST.items()},
        "lines": {}, "byLocation": {}, "countIn": {}, "deckCalls": {}, "efforts": {}, "missing": [],
    }
    for j in script_lines.all_jobs():
        id_ = j["id"]
        if id_ in rejected:
            if j["kind"] in ("line", "bark"):
                man["missing"].append({"id": id_, "location": j["loc"], "text": j["line"], "reason": rejected[id_]})
            continue
        if j["kind"] in ("line", "bark"):
            rel = f"{j['who']}/{id_}.wav"
            if not os.path.exists(os.path.join(OUT, rel)):
                man["missing"].append({"id": id_, "location": j["loc"], "text": j["line"], "reason": "not recorded"}); continue
            _, dur = info(rel)
            e = {"file": rel, "character": j["who"], "expression": j["expression"], "text": j["line"],
                 "duration": dur, "location": j["loc"], "kind": j["kind"], "treatment": TREATMENT[j["who"]]}
            if j["who"] == "tolly":
                _, d2 = info(f"tolly_radio/{id_}.wav")
                e["radio"] = {"file": f"tolly_radio/{id_}.wav", "duration": d2}
            if j.get("cut"):
                e["radioCut"] = j["cut"]["cut"]
            man["lines"][id_] = e
            man["byLocation"][j["loc"]] = id_
        elif j["kind"] == "countsrc":
            _, style, take = id_.split("_")
            for w in ("five", "six", "seven", "eight"):
                rel = f"count/count_{w}_{style}_{take}.wav"
                if not os.path.exists(os.path.join(OUT, rel)):
                    continue
                x, dur = info(rel)
                man["countIn"].setdefault(w, {}).setdefault(style, []).append(
                    {"file": rel, "duration": dur, "vowelOnset": round(process.vowel_onset(x), 3), "take": int(take)})
        elif j["kind"] in ("call", "effort"):
            folder = "calls" if j["kind"] == "call" else "efforts"
            rel = f"{folder}/{id_}.wav"
            if not os.path.exists(os.path.join(OUT, rel)):
                continue
            _, dur = info(rel)
            key = "deckCalls" if j["kind"] == "call" else "efforts"
            e = {"file": rel, "duration": dur}
            if j["kind"] == "call":
                e["text"] = j["line"]
            else:
                e["prompt"] = j["send"]
            man[key].setdefault(j["group"], []).append(e)
    json.dump(man, open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8", newline="\n"), indent=1)
    print(len(man["lines"]), "lines;", len(man["missing"]), "missing;",
          {k: {s: len(v) for s, v in d.items()} for k, d in man["countIn"].items()},
          {k: len(v) for k, v in man["deckCalls"].items()}, {k: len(v) for k, v in man["efforts"].items()})


if __name__ == "__main__":
    main()
