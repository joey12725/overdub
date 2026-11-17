"""Generate docs/ACCEPTANCE.md from the acceptance test sources and a `bash tools/gd test acceptance` log.

usage: python -I gen_acceptance.py <repo> <acceptance-run-log> <replay-run-log> <out.md>
"""
import os
import re
import sys

repo, log_path, replay_log, out_path = sys.argv[1:5]
acc_dir = os.path.join(repo, "tests", "acceptance")

kit = open(os.path.join(acc_dir, "acceptance_kit.gd"), encoding="utf-8").read()
rows = {}
for m in re.finditer(r'^\t"([A-Z-]+\d\d)": \["(.*?)", "(.*?)"\],$', kit, re.M):
    rows[m.group(1)] = (m.group(2), m.group(3))

tests = {}  # id -> [(file, name)]
for f in sorted(os.listdir(acc_dir)):
    if not (f.startswith("test_acceptance_") and f.endswith(".gd")):
        continue
    src = open(os.path.join(acc_dir, f), encoding="utf-8").read()
    for m in re.finditer(r"^func (test_[A-Za-z0-9_]+)\(", src, re.M):
        name = m.group(1)
        mm = re.match(r"test_(TEST|NEW|APPTEST)(\d\d)_", name)
        if not mm:
            continue
        pref = {"TEST": "TEST-", "NEW": "NEW-", "APPTEST": "APP-TEST-"}[mm.group(1)]
        tests.setdefault(pref + mm.group(2), []).append((f, name))

log = open(log_path, encoding="utf-8", errors="replace").read()
fails = {}  # (file, test) -> [msgs]
load_fail = {}
for m in re.finditer(r"^FAIL tests/acceptance/(\S+) :: (\S+) - (.*)$", log, re.M):
    f, t, msg = m.group(1), m.group(2), m.group(3)
    if t == "<load>":
        load_fail[f] = msg
    else:
        fails.setdefault((f, t), []).append(msg)
summary = re.search(r"^\[tests\] (\d+ suite\(s\), \d+ test\(s\):.*)$", log, re.M)
ran = summary is not None

BY_EYE = {
    "TEST-07": "How strong the recording-ghost distinction looks (hologram body, broken halo) — review in game.",
    "TEST-28": "Whether sounds feel tight to the beat is by ear.",
    "TEST-29": "How a dead/desynced layer sounds (thinning, drift) and whether the mix stays coherent is by ear.",
    "TEST-30": "That enemy hits keep time without muddying the cassette layers is by ear.",
    "TEST-32": "The cinematic flourishes and framing themselves are by eye.",
    "TEST-34": "Moxie's likeness, warm upper light and neon lower look against docs/reference/ R01-R04 are by eye.",
    "NEW-07": "That the four decks read as first-class, unmistakable UI is by eye.",
    "NEW-08": "Legibility of the speed readout and status words at play distance is by eye.",
    "NEW-09": "That the ruler is readable while recording is by eye.",
    "NEW-10": "That the reel animation visibly speeds up/slows down is by eye.",
    "NEW-11": "That the seven states are distinguishable at a glance (not only by icon/word tables) is by eye.",
}

# Things the suite noticed that are not acceptance failures; keep this list current by hand.
NOTES = [
    "APP-TEST-03 covers the levels `data/levels/index.json` lists as the campaign. At the last run that is "
    "only `sandbox`; the numbered levels `01`..`12` exist but are not in the index yet, and the solutions of "
    "`06-crossfire`, `10-heavy-rotation` and `sandbox-solo` have no `generated` block. When the index grows, "
    "the test covers each new level automatically (it fails if a listed level has no recorded solution).",
    "TEST-20 reads stagger from the `enemyStagger` event (its duration). A never-woken (asleep) enemy's "
    "snapshot state stays `stagger` until the horizon after any hit, because `core/enemies/common.gd` only "
    "moves an awake enemy out of STAGGER (the prototype behaves the same: the goldens agree). If an asleep "
    "enemy is ever shown with a stagger animation, it would look staggered forever; that is a presentation question.",
    "TEST-34 follows the revised Moxie contract in docs/GODOT-PORT.md: material names are discovered at load, so "
    "each signature part is matched by a family of name stems (headphones `hp_*`/`headphone*`, `top*`, `jacket*`, "
    "`pants*`, `shoe*`, `hair*`, `walkman*`, wrist `device*`), plus the SkeletonProfileHumanoid bone names and "
    "the pigtail bones.",
]


def esc(s):
    return s.replace("|", "\\|")


lines = []
lines.append("# Acceptance status")
lines.append("")
lines.append("Every acceptance id of `docs/requirements.txt` — chapter 21 (TEST-01..34), Revision 1")
lines.append("(NEW-01..11) and Revision 2 (APP-TEST-01..03) — mapped to its automated test in")
lines.append("`tests/acceptance/`, with the status of the last run against the shipped Godot code. The")
lines.append("\"Expected result\" column is quoted from the requirements document; `test_acceptance_texts.gd`")
lines.append("fails if a quote stops matching it. Regenerate after a run:")
lines.append("")
lines.append("```")
lines.append("bash tools/gd test acceptance > acc.log; bash tools/gd test tests/replay > rep.log")
lines.append("python -I tests/acceptance/gen_acceptance.py . acc.log rep.log docs/ACCEPTANCE.md")
lines.append("```")
lines.append("")
lines.append("")
if ran:
    lines.append("Last run: `%s`." % summary.group(1))
else:
    lines.append("Last run: **no summary line in the log** (the run did not complete).")
lines.append("")
lines.append("Status: **pass** — every test for the id passed; **FAIL** — a test failed (reason quoted from")
lines.append("the run); **by eye** notes say what an automated test cannot judge.")
lines.append("")
lines.append("| Id | Expected result | Test | Status | By eye |")
lines.append("|---|---|---|---|---|")
counts = {"pass": 0, "fail": 0, "missing": 0}
for rid in rows:
    check, exp = rows[rid]
    ts = tests.get(rid, [])
    if not ts:
        status = "FAIL: no test"
        counts["missing"] += 1
        tnames = "—"
    else:
        msgs = []
        for f, t in ts:
            if f in load_fail:
                msgs.append("suite `%s` failed to load: %s" % (f, load_fail[f][:300]))
            elif (f, t) in fails:
                ms = fails[(f, t)]
                msgs.append("; ".join(m[:260] for m in ms[:3]) + (" (+%d more)" % (len(ms) - 3) if len(ms) > 3 else ""))
        if not ran:
            status = "not run"
        elif msgs:
            status = "**FAIL**: " + " / ".join(msgs)
            counts["fail"] += 1
        else:
            status = "pass"
            counts["pass"] += 1
        tnames = "<br>".join("`%s`<br>(%s)" % (t, f) for f, t in ts)
    lines.append("| %s | %s | %s | %s | %s |" % (rid, esc(exp), tnames, esc(status), esc(BY_EYE.get(rid, ""))))
lines.append("")
lines.append("Totals: %d pass, %d fail, %d without a test (of %d ids)." % (counts["pass"], counts["fail"], counts["missing"], len(rows)))
lines.append("")
other = [(k, v) for k, v in fails.items() if not re.match(r"test_(TEST|NEW|APPTEST)\d\d_", k[1])]
if other or load_fail:
    lines.append("Suite-integrity tests (`test_acceptance_texts.gd`) and load failures:")
    lines.append("")
    for (f, t), ms in other:
        lines.append("- `%s` %s: %s" % (f, t, "; ".join(ms[:3])))
    for f, msg in load_fail.items():
        lines.append("- `%s` did not load: %s" % (f, msg[:400]))
    lines.append("")
lines.append("## Observations (not failures)")
lines.append("")
for note in NOTES:
    lines.append("- " + note)
lines.append("")
rep = open(replay_log, encoding="utf-8", errors="replace").read() if os.path.exists(replay_log) else ""
rs = re.search(r"^\[tests\] (\d+ suite\(s\), \d+ test\(s\):.*)$", rep, re.M)
lines.append("## Replay integrity (CINE-01, LEVEL-09, chapter 20)")
lines.append("")
lines.append("`tests/replay/test_replay.gd` covers the replay keeper in `replay/` (see `replay/README.md`).")
lines.append("Last run: `%s`." % (rs.group(1) if rs else "no summary line"))
rfails = re.findall(r"^FAIL tests/replay/(\S+) :: (\S+) - (.*)$", rep, re.M)
for f, t, msg in rfails[:20]:
    lines.append("- FAIL `%s`: %s" % (t, msg[:300]))
lines.append("")
open(out_path, "w", encoding="utf-8").write("\n".join(lines))
print("wrote", out_path, counts)
