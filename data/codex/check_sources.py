"""Re-check the field guide against the files it was written from.

    python -I data/codex/check_sources.py            # report
    python -I data/codex/check_sources.py --relocate # also rewrite line numbers that only moved
    python -I data/codex/check_sources.py --table    # print the docs/CODEX.md claims table

Run from the repo root. For every claim in data/codex/sources.json it checks that the quoted source
text is still on the recorded line. Three outcomes:

    ok       the text is on that line
    moved    the text exists elsewhere in the file (the rule is unchanged, only the line number is
             stale; --relocate fixes it, choosing the occurrence nearest the old line)
    CHANGED  the text is gone: the rule or number was edited. Re-read the source, correct the entry
             in codex.json, then update `text` (and `claim`) in sources.json.

It also validates codex.json: unique ids, known groups, 2-3 notes, an illustration file per entry,
a claim for every entry, no claim for an unknown entry. Exit code 1 if anything is CHANGED or
invalid. No dependencies beyond the standard library.
"""
import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CODEX = os.path.join(ROOT, 'data', 'codex', 'codex.json')
SOURCES = os.path.join(ROOT, 'data', 'codex', 'sources.json')
UNLOCK_TYPES = {
    'always': [],
    'enemySeen': ['enemy'],
    'entitySeen': ['kind'],
    'levelStarted': ['level'],
    'simEvent': ['event'],
    'storyTrigger': ['trigger'],
    'endModeOffered': ['modes'],
    'gearOwned': ['item'],
}


def load(path):
    with io.open(path, encoding='utf-8') as f:
        return json.load(f)


def validate_codex(codex, claims):
    problems = []
    groups = {g['id'] for g in codex['groups']}
    seen = set()
    for e in codex['entries']:
        eid = e.get('id', '?')
        if eid in seen:
            problems.append('duplicate id %s' % eid)
        seen.add(eid)
        for key in ('id', 'group', 'title', 'rule', 'notes', 'numbers', 'unlock', 'illustration'):
            if key not in e:
                problems.append('%s: missing %s' % (eid, key))
        if e.get('group') not in groups:
            problems.append('%s: unknown group %s' % (eid, e.get('group')))
        if not 2 <= len(e.get('notes', [])) <= 3:
            problems.append('%s: needs 2-3 notes' % eid)
        for n in e.get('numbers', []):
            if set(n) != {'label', 'value'}:
                problems.append('%s: bad number row %r' % (eid, n))
        conds = e.get('unlock', {}).get('any', [])
        if not conds:
            problems.append('%s: unlock.any is empty' % eid)
        for c in conds:
            t = c.get('type')
            if t not in UNLOCK_TYPES:
                problems.append('%s: unknown unlock type %r' % (eid, t))
            else:
                for field in UNLOCK_TYPES[t]:
                    if field not in c:
                        problems.append('%s: unlock %s needs "%s"' % (eid, t, field))
        img = os.path.join(ROOT, 'assets', 'codex', e.get('illustration', '') + '.png')
        if not os.path.isfile(img):
            problems.append('%s: missing illustration assets/codex/%s.png' % (eid, e.get('illustration')))
    claimed = {c['entry'] for c in claims}
    for eid in sorted(seen - claimed):
        problems.append('%s: no source claims' % eid)
    for eid in sorted(claimed - seen):
        problems.append('claims reference unknown entry %s' % eid)
    return problems


def main(argv):
    relocate = '--relocate' in argv
    table = '--table' in argv
    codex = load(CODEX)
    src = load(SOURCES)
    claims = src['claims']
    if table:
        print('| Entry | Claim | Source |')
        print('|---|---|---|')
        for c in claims:
            print('| `%s` | %s | `%s:%d` |' % (c['entry'], c['claim'].replace('|', '/'), c['file'], c['line']))
        return 0
    cache = {}
    ok = moved = changed = 0
    for c in claims:
        path = os.path.join(ROOT, c['file'])
        if c['file'] not in cache:
            try:
                with io.open(path, encoding='utf-8') as f:
                    cache[c['file']] = f.read().split('\n')
            except IOError:
                cache[c['file']] = None
        lines = cache[c['file']]
        if lines is None:
            print('CHANGED  %s  %s  (file missing)  -- %s' % (c['entry'], c['file'], c['claim']))
            changed += 1
            continue
        i = c['line'] - 1
        if 0 <= i < len(lines) and c['text'] in lines[i]:
            ok += 1
            continue
        hits = [n + 1 for n, l in enumerate(lines) if c['text'] in l]
        if hits:
            new = min(hits, key=lambda n: abs(n - c['line']))
            print('moved    %s  %s:%d -> %d  -- %s' % (c['entry'], c['file'], c['line'], new, c['claim']))
            moved += 1
            if relocate:
                c['line'] = new
        else:
            print('CHANGED  %s  %s:%d  -- %s\n         was: %s' % (c['entry'], c['file'], c['line'], c['claim'], c['text']))
            changed += 1
    if relocate and moved:
        with io.open(SOURCES, 'w', encoding='utf-8', newline='\n') as f:
            f.write(json.dumps(src, indent=1, ensure_ascii=False) + '\n')
        print('sources.json rewritten with %d new line numbers' % moved)
    problems = validate_codex(codex, claims)
    for p in problems:
        print('INVALID  ' + p)
    print('%d claims: %d ok, %d moved, %d changed; %d entries, %d codex problems'
          % (len(claims), ok, moved, changed, len(codex['entries']), len(problems)))
    return 1 if changed or problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
