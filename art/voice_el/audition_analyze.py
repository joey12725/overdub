"""Measure every audition take and write audition/metrics.json + a text table.
usage: python -I art/voice_el/audition_analyze.py"""
import glob, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vx

TEXT = {"moxie": "Bottom floor, biggest score, back by dinner. Easy money.",
        "opal": "I sold you a Walkman. You're wearing a miracle. Different shelf.",
        "tolly": "This floor needs four people. My four went home. Sensibly.",
        "archivist": "The master deck. It does not replay. It records over."}
here = os.path.dirname(os.path.abspath(__file__))
rows = []
for p in sorted(glob.glob(os.path.join(here, "audition", "*.mp3"))):
    ch, name = os.path.basename(p)[:-4].split("_", 1)
    m = vx.measure(vx.decode(p), TEXT[ch]); m.update(char=ch, voice=name); rows.append(m)
json.dump(rows, open(os.path.join(here, "audition", "metrics.json"), "w"), indent=1)
cols = ["char", "voice", "dur", "syl_s", "artic_syl_s", "f0_med", "f0_p5", "f0_p95", "f0_range_st", "lufs", "st_sd",
        "peak_db", "clipped", "crest_db", "max_gap", "hf_ratio_db", "voiced_frac"]
print(" ".join(f"{c:>11}" for c in cols))
for r in rows:
    print(" ".join(f"{str(r[c]):>11}" for c in cols))
