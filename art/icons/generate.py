"""Generate raw icons through tools/img, two at a time.

  python -I art/icons/generate.py [--anchors a.png,b.png] [--force] [--suffix _v2] [--extra "more prompt"] <job id or prefix> ...

Job ids are "gear/<id>", "abilities/<id>", "slots/<id>" (a prefix such as "gear/" selects a group).
--anchors paths are relative to art/icons/raw/ and are passed as style references (tools/img edit).
Raw output goes to art/icons/raw/<group>/<id><suffix>.png ; process.py turns raws into the final 512px icons.
"""
import sys, os, subprocess, concurrent.futures as cf

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from prompts import all_jobs


def main():
    args = sys.argv[1:]
    anchors, force, suffix, extra, sel = [], False, "", "", []
    while args:
        a = args.pop(0)
        if a == "--anchors":
            anchors = [os.path.join(HERE, "raw", p) for p in args.pop(0).split(",")]
        elif a == "--force":
            force = True
        elif a == "--suffix":
            suffix = args.pop(0)
        elif a == "--extra":
            extra = args.pop(0)
        else:
            sel.append(a)
    jobs = {k: v for k, v in all_jobs().items() if any(k == s or (s.endswith("/") and k.startswith(s)) for s in sel)}

    def run(item):
        k, prompt = item
        out = os.path.join(HERE, "raw", k + suffix + ".png")
        if os.path.exists(out) and not force:
            return k, "skip"
        os.makedirs(os.path.dirname(out), exist_ok=True)
        env = dict(os.environ, IMG_BG="transparent", IMG_SIZE="1024x1024")
        if extra:
            prompt = prompt + " " + extra
        if anchors:
            prompt = ("Use the attached reference stickers ONLY as the style guide (outline weight, white sticker border, "
                      "flat cel shading, level of detail) - do not copy their objects. Draw a NEW icon. ") + prompt
            # tools/img sends the prompt with curl -F, where ';' starts form-field options and would cut the prompt short
            prompt = prompt.replace(";", ",")
            cmd = ["bash", "tools/img", "edit", out, prompt] + anchors
        else:
            cmd = ["bash", "tools/img", "gen", out, prompt, "1024x1024", "transparent"]
        r = None
        for _ in range(2):
            if os.path.exists(out):
                os.remove(out)
            r = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True)
            if os.path.exists(out) and r.returncode == 0:
                return k, "ok"
        return k, "FAIL " + (r.stdout + r.stderr)[-300:]

    with cf.ThreadPoolExecutor(2) as ex:
        for k, s in ex.map(run, jobs.items()):
            print(k, s, flush=True)


main()
