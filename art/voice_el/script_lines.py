"""The recording plan: every spoken line in data/story/story.json plus Moxie's count-in, deck calls and
efforts, each with a stable id, the cast voice, the model/settings and the exact text sent to ElevenLabs.

usage: python -I art/voice_el/script_lines.py          writes art/voice_el/jobs.tsv and jobs.json
Imported by process.py / verify.py / manifest.py for the same list."""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
STORY = os.path.join(ROOT, "data", "story", "story.json")

CAST = {
    "moxie": {"voice": "Laura", "voice_id": "FGY2WhTYpPnrIDTdsKH5", "model": "eleven_v3",
              "settings": {"stability": 0.5}},
    "opal": {"voice": "Lily", "voice_id": "pFZP5JQG7iQjIQuC4Bku", "model": "eleven_v3",
             "settings": {"stability": 0.5}},
    "tolly": {"voice": "Eric", "voice_id": "cjVigY5qzO86Huf0OWal", "model": "eleven_v3",
              "settings": {"stability": 0.5}},
    "archivist": {"voice": "Brian", "voice_id": "nPczCjzI2devNBz1zQrb", "model": "eleven_multilingual_v2",
                  "settings": {"stability": 0.9, "similarity_boost": 0.75, "style": 0.0, "use_speaker_boost": True}},
}

# Direction per (character, expression): a v3 audio tag placed before the line. The Archivist is on
# multilingual v2, which would read a tag aloud, so it gets none; its direction is in settings + processing.
TAGS = {
    "moxie": {"neutral": "[dry]", "grin": "[playful]", "smug": "[smug]", "annoyed": "[annoyed]",
              "surprised": "[surprised]", "thinking": "[thoughtful]", "determined": "[determined]",
              "soft": "[quietly, sincere]"},
    "opal": {"neutral": "[deadpan]", "dry": "[deadpan]", "amused": "[deadpan, faintly amused]",
             "worried": "[flat, tense]", "soft": "[quietly]"},
    "tolly": {"neutral": "[earnest]", "earnest": "[earnest, brisk]", "flustered": "[flustered, slightly breathless]",
              "impressed": "[awestruck]"},
}
# Barks are thrown away, not performed: same expression, but offhand.
BARK_TAGS = {"neutral": "[offhand, dry]", "grin": "[offhand, playful]", "smug": "[offhand, smug]",
             "annoyed": "[offhand, annoyed]", "surprised": "[offhand, surprised]",
             "thinking": "[offhand, muttering]", "determined": "[offhand, firm]", "soft": "[offhand, quietly]"}

# Radio cuts (INTEGRATION.md: a line ending or starting with "--" is clipped with static). The clipped word is
# synthesised whole and cut in post at the character timestamp, so what is heard is exactly the script.
CUTS = {
    "Don't sell anything without me. And don't you d--":
        {"send": "Don't sell anything without me. And don't you dare.", "cut": "tail", "keep_chars": len("Don't sell anything without me. And don't you d")},
    "--oxie? Eleven hours of static. Well? Did you find it?":
        {"send": "Moxie? Eleven hours of static. Well? Did you find it?", "cut": "head", "drop_chars": 1},
}


def _job(id_, who, expression, line, loc, kind="line", tag=None, group=None, send=None, settings=None):
    c = CAST[who]
    cut = CUTS.get(line)
    spoken = send or (cut["send"] if cut else line)
    if tag is None:
        tag = TAGS.get(who, {}).get(expression, "")
    text = (tag + " " + spoken).strip() if tag else spoken
    j = {"id": id_, "who": who, "expression": expression, "line": line, "loc": loc, "kind": kind,
         "voice_id": c["voice_id"], "model": c["model"], "settings": settings or c["settings"], "send": text}
    if cut:
        j["cut"] = cut
    if group:
        j["group"] = group
    return j


def story_jobs():
    s = json.load(open(STORY, encoding="utf-8"))
    jobs = []
    for key, lv in s["levels"].items():
        n = key.split("-")[0]
        for sec in ("intro", "outro", "firstDeath", "firstDesync", "idle"):
            for i, e in enumerate(lv.get(sec, [])):
                jobs.append(_job(f"l{n}_{sec.lower()}_{i + 1:02d}", e["who"], e["expression"], e["line"],
                                 f"levels.{key}.{sec}[{i}]"))
    for key, arr in s["once"].items():
        for i, e in enumerate(arr):
            jobs.append(_job(f"once_{key.lower()}_{i + 1:02d}", e["who"], e["expression"], e["line"], f"once.{key}[{i}]"))
    for key, arr in s["barks"].items():
        for i, e in enumerate(arr):
            tag = BARK_TAGS[e["expression"]] if e["who"] == "moxie" else None
            jobs.append(_job(f"bark_{key.lower()}_{i + 1:02d}", e["who"], e["expression"], e["line"],
                             f"barks.{key}[{i}]", kind="bark", tag=tag))
    for i, e in enumerate(s["ending"]):
        jobs.append(_job(f"ending_{i + 1:02d}", e["who"], e["expression"], e["line"], f"ending[{i}]"))
    for i, e in enumerate(s.get("stinger", [])):
        jobs.append(_job(f"stinger_{i + 1:02d}", e["who"], e["expression"], e["line"], f"stinger[{i}]"))
    return jobs


def extra_jobs():
    """Count-in, deck calls and non-verbal efforts, all Moxie. The count is recorded as whole counted phrases
    (so the four words share one breath and one pitch centre) and sliced into one-shots in post."""
    J = []
    for t in (1, 2, 3):
        J.append(_job(f"countsrc_spoken_{t}", "moxie", "neutral", "Five. Six. Seven. Eight.", None, kind="countsrc",
                      tag="[counting in, clipped, rhythmic]", group="spoken"))
        J.append(_job(f"countsrc_called_{t}", "moxie", "determined", "Five! Six! Seven! Eight!", None, kind="countsrc",
                      tag="[calling out, loud, clipped, rhythmic]", group="called"))
    calls = [("one_more_time", "One more time."), ("rolling", "Rolling."), ("thats_a_take", "That's a take."), ("again", "Again.")]
    for key, text in calls:
        for t in (1, 2):
            J.append(_job(f"call_{key}_{t}", "moxie", "neutral", text, None, kind="call",
                          tag="[offhand, confident]" if t == 1 else "[calling out]", group=key))
    efforts = [
        ("attack_light", ["[short sharp effort grunt] Hah!", "[short sharp effort grunt] Hup!", "[short sharp effort grunt] Ha!", "[quick effort grunt] Tsah!"]),
        ("attack_heavy", ["[shouting, big effort] Hyaah!", "[shouting, big effort] Raah!", "[shouting, big effort] Haaah!"]),
        ("dodge", ["[quick sharp exhale] Hff!", "[sharp gasp] Hh!"]),
        ("hit", ["[pained grunt] Ugh!", "[pained grunt] Agh!"]),
        ("death", ["[pained cry, fading] Aaagh...", "[pained groan, collapsing] Nnngh..."]),
        ("laugh", ["[short laugh] Heh."]),
        ("hm", ["[thoughtful] Hm."]),
    ]
    for key, texts in efforts:
        for t, text in enumerate(texts, 1):
            j = _job(f"effort_{key}_{t}", "moxie", "neutral", re.sub(r"\[[^\]]*\]\s*", "", text), None, kind="effort",
                     tag="", send=text, group=key)
            J.append(j)
    return J


def all_jobs():
    return story_jobs() + extra_jobs()


if __name__ == "__main__":
    jobs = all_jobs()
    json.dump(jobs, open(os.path.join(HERE, "jobs.json"), "w", encoding="utf-8"), indent=1)
    with open(os.path.join(HERE, "jobs.tsv"), "w", encoding="utf-8", newline="\n") as f:
        for j in jobs:
            f.write("\t".join([j["id"], j["voice_id"], j["model"], json.dumps(j["settings"]), j["send"]]) + "\n")
    from collections import Counter
    sj = story_jobs()
    print(len(sj), "story lines;", len(jobs) - len(sj), "extra requests;", sum(len(j["send"]) for j in jobs), "characters")
    print(Counter(j["who"] for j in sj))
