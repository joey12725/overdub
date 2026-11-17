#!/usr/bin/env bash
# Re-issue the most recent logged prompt for <name> (used after an interrupted run).
#   SIZE=1536x1024 bash art/ui_art/rerun.sh <name> <inputs...>
cd "$(dirname "$0")/../.." || exit 1
name="$1"; shift
prompt="$(python -I - "$name" <<'P'
import sys,re
t=open('art/ui_art/PROMPTS.md',encoding='utf-8').read()
blocks=re.split(r'(?m)^## ',t)
b=[x for x in blocks if x.split('\n',1)[0].strip()==sys.argv[1]][-1]
body=b.split('\n',1)[1]
lines=[l for l in body.split('\n') if l.strip() and not l.startswith('- call:')]
sys.stdout.write(' '.join(lines))
P
)"
[ -z "$prompt" ] && { echo "no prompt for $name"; exit 1; }
bash art/ui_art/run.sh edit "$name" "$prompt" "$@"
