"""raw/<id>.json (ElevenLabs /with-timestamps response) -> takes/<id>.mp3, takes/<id>.wav (decoded, untouched)
and takes/<id>.align.json (character timings). Then measures every take into takes/metrics.json.
usage: python -I art/voice_el/extract.py [id-regex]"""
import base64, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vx, script_lines

HERE = os.path.dirname(os.path.abspath(__file__))
RAW, TAKES = os.path.join(HERE, "raw"), os.path.join(HERE, "takes")


def main():
    os.makedirs(TAKES, exist_ok=True)
    pat = re.compile(sys.argv[1]) if len(sys.argv) > 1 else None
    mpath = os.path.join(TAKES, "metrics.json")
    metrics = json.load(open(mpath)) if os.path.exists(mpath) else {}
    for j in script_lines.all_jobs():
        id_ = j["id"]
        src = os.path.join(RAW, id_ + ".json")
        if not os.path.exists(src) or (pat and not pat.search(id_)):
            continue
        wav = os.path.join(TAKES, id_ + ".wav")
        if not os.path.exists(wav) or os.path.getmtime(wav) < os.path.getmtime(src):
            try:
                with open(src, encoding="utf-8") as fh:
                    d = json.load(fh)
                base64.b64decode(d["audio_base64"], validate=True)
            except Exception as ex:   # a response cut off in transit: drop it so record.sh fetches it again
                print("INVALID raw response, removed:", id_, type(ex).__name__)
                os.remove(src); continue
            mp3 = os.path.join(TAKES, id_ + ".mp3")
            open(mp3, "wb").write(base64.b64decode(d["audio_base64"]))
            json.dump({"alignment": d.get("alignment"), "quality_check": d.get("quality_check")},
                      open(os.path.join(TAKES, id_ + ".align.json"), "w"))
            vx.write_wav(wav, vx.decode(mp3))
            metrics.pop(id_, None)
        if id_ not in metrics:
            x, _ = vx.read_wav(wav)
            m = vx.measure(x, vx.strip_tags(j["send"]))
            a = json.load(open(os.path.join(TAKES, id_ + ".align.json")))["alignment"] or {}
            ends = a.get("character_end_times_seconds") or [0]
            m["align_end"] = round(ends[-1], 3); m["raw_len"] = round(len(x) / vx.SR, 3)
            m["who"] = j["who"]; m["kind"] = j["kind"]
            metrics[id_] = m
    json.dump(metrics, open(mpath, "w"), indent=1)
    cols = ["dur", "syl", "syl_s", "f0_med", "f0_range_st", "lufs", "peak_db", "clipped", "max_gap", "lead", "tail", "tail50_db", "align_end"]
    print(f"{'id':26}" + " ".join(f"{c:>9}" for c in cols))
    for k, m in metrics.items():
        if pat and not pat.search(k):
            continue
        print(f"{k:26}" + " ".join(f"{str(m[c]):>9}" for c in cols))


if __name__ == "__main__":
    main()
