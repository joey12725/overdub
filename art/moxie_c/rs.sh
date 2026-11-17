#!/usr/bin/env bash
# Render a shot set from the built model and montage it:
#   bash art/moxie_c/rs.sh <shot> [pose] [--toon]  -> art/previews/moxie_c/_wip_<shot>[_toon].png
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
BLENDER="${BLENDER:-/c/Users/joeya/.t3/tools/blender-4.5.16-windows-x64/blender.exe}"
SH="$1"; POSE="${2:-relaxed}"; S=""; T=""
[ "$3" = "--toon" ] && { S="_toon"; T="--toon"; }
P=art/previews/moxie_c
rm -f $P/_wip_${SH}[0-9]*$S.png
"$BLENDER" --background --threads 6 "${BLEND:-art/moxie_c/moxie_model.blend}" --python art/moxie_c/render.py -- --shots "$SH" --pose "$POSE" $T 2>&1 | grep -E "Error|Traceback|line [0-9]+" | head -20
python -I art/moxie_c/mc_sheet.py $P/_wip_$SH$S.png $(ls $P/_wip_${SH}[0-9]*$S.png | sort)
