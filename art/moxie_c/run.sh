#!/usr/bin/env bash
# Dev helper: bash art/moxie_c/run.sh <blender build.py args...>
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BLENDER="${BLENDER:-/c/Users/joeya/.t3/tools/blender-4.5.16-windows-x64/blender.exe}"
cd "$ROOT" || exit 1
python -I art/moxie_c/mc_paint.py art/moxie_c/tex >/dev/null || exit 1
"$BLENDER" --background --threads 6 --python art/moxie_c/build.py -- "$@" 2>&1 | grep -vE "^(Fra:|Saved:| Time:|Time:|Blender |$|Info:|Warning: region type)" | tail -${TAILN:-25}
