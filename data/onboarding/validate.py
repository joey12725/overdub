"""Validate data/onboarding/*.json against data/onboarding/vocabulary.json and docs/ONBOARDING.md.

Run from the repo root:   python -I data/onboarding/validate.py

Checks
  coachmarks.json     parses; required/optional fields; unique ids; level, phase, anchor, text tokens,
                      word limit and every trigger / dismissOn / skipIf condition use the vocabulary;
                      markDone references exist and are acyclic; 'subject' anchors have a binding leaf;
                      every teaching topic the brief lists is covered by a mark.
  failure_hints.json  parses; every regex compiles; every example matches its own hint FIRST in
                      priority order; signature groups exist; word limit; and every Outcome note found
                      in tests/goldens/*.json (real simulation output) resolves to a hint or an ignore.
  docs/ONBOARDING.md  mentions every predicate, anchor form, mark id and hint id (doc/data in sync).

Exit code 0 when clean. No third-party imports.
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
errors = []
warnings = []


def err(msg):
    errors.append(msg)


def load(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return json.load(f)


V = load("vocabulary.json")
PHASES = set(V["phases"])
LEVELS = set(V["levels"])
INPUTS = set(V["inputs"])
ACTIONS = set(V["sessionActions"])
EVENTS = set(V["simEvents"])
SCOPES = set(V["scopes"])
ANCHORS = {k: re.compile(p) for k, p in V["anchors"].items()}
TOKENS = {k: re.compile(p) for k, p in V["tokens"].items()}
MAX_WORDS = V["maxWords"]


def is_num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def check_n(x, where):
    """N: a number (exact) or { min?, max? } (inclusive)."""
    if is_num(x):
        return
    if isinstance(x, dict) and x and set(x) <= {"min", "max"} and all(is_num(v) for v in x.values()):
        if "min" in x and "max" in x and x["min"] > x["max"]:
            err(f"{where}: min > max")
        return
    err(f"{where}: expected a number or {{min,max}}, got {x!r}")


def check_enum(x, allowed, where):
    if x not in allowed:
        err(f"{where}: {x!r} is not one of {sorted(map(str, allowed))}")


def check_keys(d, required, optional, where):
    if not isinstance(d, dict):
        err(f"{where}: expected an object, got {d!r}")
        return False
    for k in required:
        if k not in d:
            err(f"{where}: missing '{k}'")
    for k in d:
        if k not in required and k not in optional:
            err(f"{where}: unknown key '{k}'")
    return True


def check_scope(x, where, ctx):
    check_enum(x, SCOPES, where)
    if x == "shown" and ctx != "dismissOn":
        err(f"{where}: scope 'shown' is only meaningful in dismissOn")


def one_or_list(x):
    return x if isinstance(x, list) else [x]


used_predicates = set()
mark_refs = {}  # mark id -> set of ids referenced by markDone in its trigger


def check_cond(c, where, ctx, refs):
    """ctx is 'trigger' | 'dismissOn' | 'skipIf'."""
    if not isinstance(c, dict) or len(c) != 1:
        err(f"{where}: a condition is an object with exactly one key, got {c!r}")
        return
    (op, arg), = c.items()
    w = f"{where}.{op}"
    if op in ("all", "any"):
        if not isinstance(arg, list) or not arg:
            err(f"{w}: expected a non-empty list")
            return
        for i, sub in enumerate(arg):
            check_cond(sub, f"{w}[{i}]", ctx, refs)
        return
    if op == "not":
        check_cond(arg, w, ctx, refs)
        return
    if op not in V["predicates"]:
        err(f"{w}: unknown predicate")
        return
    used_predicates.add(op)

    if op == "firstTimePhase":
        check_enum(arg, PHASES, w)
    elif op == "phaseIs":
        for p in one_or_list(arg):
            check_enum(p, PHASES, w)
    elif op in ("phaseElapsed", "beat", "takeProgress", "tapesCommitted", "speedsOffered", "activeSpeedIs",
                "endModesOffered", "retriesThisTake", "levelsCleared"):
        check_n(arg, w)
    elif op == "shownFor":
        check_n(arg, w)
        if ctx != "dismissOn":
            err(f"{w}: only meaningful in dismissOn")
    elif op == "deckStatusIs":
        if check_keys(arg, ["deck", "status"], [], w):
            check_enum(arg.get("deck"), V["deckSelectors"], w + ".deck")
            check_enum(arg.get("status"), V["deckStatuses"], w + ".status")
    elif op == "activeEndModeIs":
        check_enum(arg, V["endModes"], w)
    elif op == "outcomeIs":
        check_enum(arg, V["outcomes"], w)
    elif op == "liveSelfIs":
        check_enum(arg, V["liveStates"], w)
    elif op == "selfIs":
        if check_keys(arg, ["who", "state"], [], w):
            check_enum(arg.get("who"), ["previous", 0, 1, 2, 3], w + ".who")
            check_enum(arg.get("state"), V["selfStates"], w + ".state")
    elif op == "selfFateChanged":
        if check_keys(arg, ["who", "to"], [], w):
            check_enum(arg.get("who"), ["previous", 0, 1, 2, 3], w + ".who")
            check_enum(arg.get("to"), V["fates"], w + ".to")
    elif op == "liveSelfNear":
        if check_keys(arg, ["kind", "tiles"], [], w):
            check_enum(arg.get("kind"), V["nearKinds"], w + ".kind")
            if not is_num(arg.get("tiles")) or arg.get("tiles", 0) <= 0:
                err(f"{w}.tiles: expected a positive number")
    elif op == "liveSelfTravelled":
        if check_keys(arg, ["tiles"], ["scope"], w):
            if not is_num(arg.get("tiles")) or arg.get("tiles", 0) <= 0:
                err(f"{w}.tiles: expected a positive number")
            if "scope" in arg:
                check_scope(arg["scope"], w + ".scope", ctx)
    elif op == "eventSeen":
        opt = ["tape", "detail", "detailPrefix", "detailSuffix", "detailIn", "target", "scope", "count"]
        if check_keys(arg, ["type"], opt, w):
            check_enum(arg.get("type"), EVENTS, w + ".type")
            if "tape" in arg:
                check_enum(arg["tape"], V["tapeSelectors"], w + ".tape")
            for k in ("detail", "detailPrefix", "detailSuffix"):
                if k in arg and not isinstance(arg[k], str):
                    err(f"{w}.{k}: expected a string")
            if "detailIn" in arg and not (isinstance(arg["detailIn"], list) and arg["detailIn"]
                                          and all(isinstance(s, str) for s in arg["detailIn"])):
                err(f"{w}.detailIn: expected a non-empty list of strings")
            if "target" in arg:
                check_enum(arg["target"], V["eventTargets"], w + ".target")
            if "scope" in arg:
                check_scope(arg["scope"], w + ".scope", ctx)
            if "count" in arg:
                check_n(arg["count"], w + ".count")
    elif op == "inputUsed":
        if check_keys(arg, ["input"], ["scope", "count"], w):
            check_enum(arg.get("input"), INPUTS | {"any"}, w + ".input")
            if "scope" in arg:
                check_scope(arg["scope"], w + ".scope", ctx)
            if "count" in arg:
                check_n(arg["count"], w + ".count")
    elif op == "inputNotUsedFor":
        if check_keys(arg, ["input", "seconds"], [], w):
            check_enum(arg.get("input"), INPUTS, w + ".input")
            if not is_num(arg.get("seconds")) or arg.get("seconds", 0) <= 0:
                err(f"{w}.seconds: expected a positive number")
    elif op == "sessionActionUsed":
        if check_keys(arg, ["action"], ["scope"], w):
            for a in one_or_list(arg.get("action")):
                check_enum(a, ACTIONS, w + ".action")
            if "scope" in arg:
                check_scope(arg["scope"], w + ".scope", ctx)
    elif op == "markDone":
        if not isinstance(arg, str):
            err(f"{w}: expected a mark id")
        else:
            refs.add(arg)
    else:  # a predicate in the vocabulary with no checker here
        err(f"{w}: validate.py has no checker for this predicate")


SUBJECT_LEAVES = {"eventSeen", "selfIs", "selfFateChanged"}


def has_subject_leaf(c):
    if not isinstance(c, dict) or len(c) != 1:
        return False
    (op, arg), = c.items()
    if op in ("all", "any"):
        return any(has_subject_leaf(s) for s in arg) if isinstance(arg, list) else False
    if op == "not":
        return False  # a negated leaf binds nothing
    return op in SUBJECT_LEAVES


def check_text(text, where, allow_tape):
    if not isinstance(text, str) or not text.strip():
        err(f"{where}: empty text")
        return
    try:
        text.encode("ascii")
    except UnicodeEncodeError:
        err(f"{where}: text must be plain ASCII (story data convention): {text!r}")
    words = text.split()
    if len(words) > MAX_WORDS:
        err(f"{where}: {len(words)} words (limit {MAX_WORDS}): {text!r}")
    for tok in re.findall(r"\{[^}]*\}", text):
        if not any(p.match(tok) for p in TOKENS.values()):
            err(f"{where}: unknown token {tok}")
        if tok == "{tape}" and not allow_tape:
            err(f"{where}: {{tape}} used but nothing binds a tape")
    if "{" in re.sub(r"\{[^}]*\}", "", text) or "}" in re.sub(r"\{[^}]*\}", "", text):
        err(f"{where}: unbalanced braces")


# ───────────────────────────── coachmarks.json ─────────────────────────────

CM = load("coachmarks.json")
marks = CM.get("marks")
if not isinstance(marks, list) or not marks:
    err("coachmarks.json: 'marks' must be a non-empty list")
    marks = []
for k in ("maxVisible", "minGapSeconds", "maxPerPhaseVisit", "maxUrgentPerPhaseVisit", "defaultLingerSeconds",
          "minShownSecondsToCount"):
    if not is_num(CM.get("limits", {}).get(k)):
        err(f"coachmarks.json: limits.{k} missing or not a number")

ids = []
REQ = V["markFields"]["required"]
OPT = V["markFields"]["optional"]
for i, m in enumerate(marks):
    mid = m.get("id", f"#{i}") if isinstance(m, dict) else f"#{i}"
    w = f"mark '{mid}'"
    if not check_keys(m, REQ, OPT, w):
        continue
    if not isinstance(m.get("id"), str) or not re.match(r"^[a-z0-9]+(-[a-z0-9]+)*$", m.get("id", "")):
        err(f"{w}: id must be kebab-case")
    ids.append(mid)
    if m.get("level") != "any":
        check_enum(m.get("level"), LEVELS, w + ".level")
    phases = one_or_list(m.get("phase"))
    if not phases:
        err(f"{w}: empty phase")
    for p in phases:
        check_enum(p, PHASES, w + ".phase")
    if m.get("once") is not True and m.get("once") is not False:
        err(f"{w}.once: expected true or false")
    for k in ("urgent",):
        if k in m and not isinstance(m[k], bool):
            err(f"{w}.{k}: expected a boolean")
    if "linger" in m and (not is_num(m["linger"]) or m["linger"] <= 0):
        err(f"{w}.linger: expected positive seconds")
    anchor = m.get("anchor")
    if not isinstance(anchor, str) or not any(p.match(anchor) for p in ANCHORS.values()):
        err(f"{w}.anchor: {anchor!r} is not in the anchor vocabulary")
    refs = set()
    check_cond(m.get("trigger"), w + ".trigger", "trigger", refs)
    mark_refs[mid] = set(refs)
    check_cond(m.get("dismissOn"), w + ".dismissOn", "dismissOn", refs)
    if "skipIf" in m:
        check_cond(m["skipIf"], w + ".skipIf", "skipIf", refs)
    subj = has_subject_leaf(m.get("trigger"))
    if isinstance(anchor, str) and (anchor.endswith(":subject") or anchor == "world:event") and not subj:
        err(f"{w}.anchor: uses the trigger subject but the trigger has no eventSeen / selfIs / selfFateChanged leaf")
    check_text(m.get("text"), w + ".text", allow_tape=subj)
    # a mark's first phase must be able to satisfy firstTimePhase leaves it uses
    def phases_in(c, out):
        if isinstance(c, dict) and len(c) == 1:
            (op, arg), = c.items()
            if op in ("all", "any"):
                for s in arg:
                    phases_in(s, out)
            elif op == "not":
                phases_in(arg, out)
            elif op == "firstTimePhase":
                out.add(arg)
    fp = set()
    phases_in(m.get("trigger"), fp)
    for p in fp:
        if p not in phases:
            err(f"{w}: firstTimePhase('{p}') can never be true in phase {phases}")

dupes = sorted({x for x in ids if ids.count(x) > 1})
if dupes:
    err(f"coachmarks.json: duplicate ids {dupes}")
idset = set(ids)
for mid, refs in mark_refs.items():
    for r in refs:
        if r not in idset:
            err(f"mark '{mid}': markDone references unknown mark '{r}'")


def cyclic(start):
    seen, stack = set(), [start]
    while stack:
        cur = stack.pop()
        for r in mark_refs.get(cur, ()):
            if r == start:
                return True
            if r not in seen:
                seen.add(r)
                stack.append(r)
    return False


for mid in ids:
    if cyclic(mid):
        err(f"mark '{mid}': markDone dependency cycle")

# Every topic the brief asks for must be taught by at least one mark.
COVERAGE = {
    "movement and aim": ["move", "aim"],
    "light attack": ["light"],
    "the count-in": ["count-in"],
    "reading the ruler": ["ruler-lane", "lanes"],
    "what the deck shows": ["deck-armed"],
    "choosing a speed": ["speed-pick", "speed-span"],
    "what speed does to the world": ["speed-fast", "speed-slow"],
    "heavy attack and momentum (why the wall clanged)": ["heavy", "clang", "momentum-speed"],
    "retry versus commit": ["decide"],
    "reset-all wipes everything": ["decide-reset"],
    "first previous self": ["overdub-setup", "previous-self"],
    "first death": ["death-ghost", "ghost-not-kept"],
    "first rescue": ["rescue"],
    "first desync and the spark": ["desync", "spark"],
    "repeat": ["repeat", "repeat-wrap"],
    "reverse": ["reverse", "reverse-turn"],
    "first trap": ["trap-warn"],
    "the cinematic": ["cinematic"],
}
for topic, need in COVERAGE.items():
    for n in need:
        if n not in idset:
            err(f"coverage: topic '{topic}' expects mark '{n}'")
phases_covered = set()
for m in marks:
    if isinstance(m, dict):
        phases_covered.update(one_or_list(m.get("phase")))
unused_pred = sorted(set(V["predicates"]) - used_predicates)
if unused_pred:
    warnings.append(f"predicates in the vocabulary that no mark uses: {unused_pred}")

# ───────────────────────────── failure_hints.json ─────────────────────────────

FH = load("failure_hints.json")
hints = FH.get("hints", [])
ignores = FH.get("ignore", [])
compiled = []
hint_ids = []
for h in hints:
    hid = h.get("id", "?")
    w = f"hint '{hid}'"
    check_keys(h, ["id", "match", "signature", "text", "examples"], [], w)
    hint_ids.append(hid)
    try:
        rx = re.compile(h.get("match", ""))
    except re.error as e:
        err(f"{w}: regex does not compile: {e}")
        continue
    if "(?<" in h["match"].replace("(?<=", "").replace("(?<!", ""):
        err(f"{w}: use (?P<name>...) groups so the source compiles in both Godot and Python")
    compiled.append((hid, rx))
    for g in h.get("signature", []):
        if g not in rx.groupindex:
            err(f"{w}: signature group '{g}' is not a named group of the regex")
    check_text(h.get("text"), w + ".text", allow_tape="tape" in rx.groupindex)
    if not h.get("examples"):
        err(f"{w}: needs at least one example note")
ign = []
for g in ignores:
    try:
        ign.append((g.get("id", "?"), re.compile(g.get("match", ""))))
    except re.error as e:
        err(f"ignore '{g.get('id')}': regex does not compile: {e}")
if len(set(hint_ids)) != len(hint_ids):
    err("failure_hints.json: duplicate hint ids")
if FH.get("rules", {}).get("showAfter") != 2:
    err("failure_hints.json: rules.showAfter must be 2 (the brief: after the SECOND identical failure)")


def resolve(note):
    for gid, rx in ign:
        if rx.fullmatch(note):
            return ("ignore", gid)
    for hid, rx in compiled:
        if rx.fullmatch(note):
            return ("hint", hid)
    return (None, None)


for h in hints:
    for ex in h.get("examples", []):
        kind, got = resolve(ex)
        if got != h.get("id"):
            err(f"hint '{h.get('id')}': example resolves to {kind} '{got}' instead: {ex!r}")

# Real notes written by the simulation, harvested from the prototype goldens.
real = set()


def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "notes" and isinstance(v, list):
                real.update(x for x in v if isinstance(x, str))
            else:
                walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)


for path in sorted(glob.glob(os.path.join(ROOT, "tests", "goldens", "*.json"))):
    try:
        with open(path, encoding="utf-8") as f:
            walk(json.load(f))
    except (OSError, ValueError) as e:
        warnings.append(f"could not read golden {os.path.basename(path)}: {e}")
tally = {}
for note in sorted(real):
    kind, got = resolve(note)
    if kind is None:
        err(f"golden note matches no hint and no ignore: {note!r}")
    else:
        tally[got] = tally.get(got, 0) + 1
    if got in ("death.other", "desync.other", "weak.other", "objective.other"):
        warnings.append(f"golden note fell through to the generic '{got}': {note!r}")

# ───────────────────────────── docs/ONBOARDING.md in sync ─────────────────────────────

doc_path = os.path.join(ROOT, "docs", "ONBOARDING.md")
if os.path.exists(doc_path):
    with open(doc_path, encoding="utf-8") as f:
        doc = f.read()
    for name in list(V["predicates"]) + V["combinators"]:
        if f"`{name}" not in doc:
            err(f"docs/ONBOARDING.md does not document predicate `{name}`")
    for name in V["anchors"]:
        if f"`{name}`" not in doc:
            err(f"docs/ONBOARDING.md does not document anchor `{name}`")
    for name in V["tokens"]:
        if f"`{name}`" not in doc:
            err(f"docs/ONBOARDING.md does not document token `{name}`")
    for mid in ids:
        if f"`{mid}`" not in doc:
            err(f"docs/ONBOARDING.md does not mention mark `{mid}`")
    for hid in hint_ids:
        if f"`{hid}`" not in doc:
            err(f"docs/ONBOARDING.md does not mention hint `{hid}`")
else:
    err("docs/ONBOARDING.md is missing")

# ───────────────────────────── report ─────────────────────────────

print(f"coach marks: {len(marks)}  (phases with marks: {sorted(phases_covered)})")
print(f"predicates used: {len(used_predicates)} of {len(V['predicates'])}")
print(f"failure hints: {len(hints)} + {len(ignores)} ignore patterns")
print(f"golden notes checked: {len(real)}  ->  " + ", ".join(f"{k}:{v}" for k, v in sorted(tally.items())))
longest = max((len(m["text"].split()), m["id"]) for m in marks if isinstance(m, dict) and isinstance(m.get("text"), str))
print(f"longest coach mark: {longest[0]} words ({longest[1]})")
for wmsg in warnings:
    print("WARN  " + wmsg)
for e in errors:
    print("ERROR " + e)
print("OK" if not errors else f"FAILED: {len(errors)} error(s)")
sys.exit(1 if errors else 0)
