"""Merge step for the integration engineer: copy each piece's "music" block into its level file.

    python -I art/music/merge.py            # dry run: says what would change, writes nothing
    python -I art/music/merge.py --write    # replaces the "music" object in data/levels/<id>.json
    python -I art/music/merge.py --write --out <dir>   # writes merged copies to <dir> instead

Only the top-level "music" object of the level file is replaced, in place, as text: every other byte
of the level file (map rows, entities, comments-by-formatting) is left exactly as the level designer
wrote it. The script refuses a level whose bpm differs from the tempo the piece was composed at
(bpm and bars belong to the level designer: change art/music/pieces.ts, retune and recompose instead).
"""
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MUSIC = os.path.join(REPO, "data", "music")
LEVELS = os.path.join(REPO, "data", "levels")


def find_music_span(text):
    """(start, end) of the value of the top-level "music" key, or None."""
    depth = 0
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            key = text[i + 1 : j]
            k = j + 1
            while k < n and text[k] in " \t\r\n":
                k += 1
            if depth == 1 and key == "music" and k < n and text[k] == ":":
                k += 1
                while text[k] in " \t\r\n":
                    k += 1
                if text[k] != "{":
                    return None
                d = 0
                m = k
                while True:
                    ch = text[m]
                    if ch == '"':
                        m += 1
                        while text[m] != '"':
                            m += 2 if text[m] == "\\" else 1
                    elif ch == "{":
                        d += 1
                    elif ch == "}":
                        d -= 1
                        if d == 0:
                            return (k, m + 1)
                    m += 1
            i = j + 1
            continue
        if c in "{[":
            depth += 1
        elif c in "}]":
            depth -= 1
        i += 1
    return None


def render(music, indent):
    """The music block, one track per line, indented to sit under a key at `indent` spaces."""
    pad = " " * indent
    lines = ["{"]
    lines.append(f'{pad}  "root": {music["root"]},')
    lines.append(f'{pad}  "scale": {json.dumps(music["scale"])},')
    lines.append(f'{pad}  "progression": {json.dumps(music["progression"])},')
    if "chordBars" in music:
        lines.append(f'{pad}  "chordBars": {music["chordBars"]},')
    lines.append(f'{pad}  "tracks": [')
    tr = music["tracks"]
    for i, t in enumerate(tr):
        lines.append(f"{pad}    {json.dumps(t, ensure_ascii=False)}{',' if i < len(tr) - 1 else ''}")
    lines.append(f"{pad}  ]")
    lines.append(f"{pad}}}")
    return "\n".join(lines)


def main():
    write = "--write" in sys.argv
    out_dir = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else None
    failed = 0
    for name in sorted(os.listdir(MUSIC)):
        if not name.endswith(".json") or name == "menu.json":
            continue
        piece = json.load(open(os.path.join(MUSIC, name), encoding="utf-8"))
        path = os.path.join(LEVELS, name)
        if not os.path.exists(path):
            print(f"{name:26} no level file yet: nothing to merge (the piece waits in data/music)")
            continue
        text = open(path, encoding="utf-8").read()
        level = json.loads(text)
        if level.get("bpm") != piece["bpm"]:
            print(f"{name:26} REFUSED: level bpm {level.get('bpm')} != piece bpm {piece['bpm']} (retune the piece)")
            failed += 1
            continue
        span = find_music_span(text)
        if span is None:
            print(f"{name:26} REFUSED: no top-level \"music\" object found")
            failed += 1
            continue
        line_start = text.rfind("\n", 0, span[0]) + 1
        indent = len(text[line_start : span[0]]) - len(text[line_start : span[0]].lstrip(" "))
        merged = text[: span[0]] + render(piece["music"], indent) + text[span[1] :]
        after = json.loads(merged)
        assert after["music"] == piece["music"], name
        before = dict(level)
        before.pop("music")
        rest = dict(after)
        rest.pop("music")
        assert before == rest, name
        same = level["music"] == piece["music"]
        roles = "/".join(t["role"] for t in piece["music"]["tracks"])
        tapes = level.get("maxTapes", 4)
        print(f"{name:26} {'already merged' if same else ('merged' if write else 'would merge')}: cassettes 1..4 = {roles}; the level uses {tapes}")
        if write and not same:
            target = os.path.join(out_dir, name) if out_dir else path
            if out_dir:
                os.makedirs(out_dir, exist_ok=True)
            with open(target, "w", encoding="utf-8", newline="") as f:
                f.write(merged)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
