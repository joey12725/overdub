#!/usr/bin/env bash
# Retarget the library clips and render contact sheets.
#   bash art/moxie_c/anim.sh [clip,clip] [--toon]
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
BLENDER="${BLENDER:-/c/Users/joeya/.t3/tools/blender-4.5.16-windows-x64/blender.exe}"
UAL="art/moxie_c/_dl/ual/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"
P=art/previews/moxie_c
if [ -z "$SKIP_RETARGET" ]; then
"$BLENDER" --background --threads 6 art/moxie_c/moxie_model.blend --python art/moxie_c/mc_anim.py -- "$UAL" 2>&1 | grep -E "clip |strike|Error|Traceback|line [0-9]+|ANIM DONE" 
fi
[ -n "$NO_SHEETS" ] && exit 0
rm -f $P/_c_*.png
"$BLENDER" --background --threads 6 art/moxie_c/moxie_anim.blend --python art/moxie_c/mc_contact.py -- "$@" 2>&1 | grep -E "Error|Traceback|line [0-9]+|CONTACT DONE"
for f in $(ls $P/_c_*_0.png); do n=$(basename $f | sed 's/_c_//; s/_0.png//'); python -I art/moxie_c/mc_sheet.py $P/contact_$n.png $(ls $P/_c_${n}_[0-9].png | sort); done
