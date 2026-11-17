#!/usr/bin/env bash
# Full rebuild of Moxie candidate C, one heavy process at a time:
#   bash art/moxie_c/rebuild.sh           model -> clips -> control rig -> glb -> previews
# then, for the Godot side (shared import cache, so run it on its own):
#   bash tools/gd script res://art/moxie_c/gd_build_anims.gd
#   bash tools/gd shot   res://tools/moxie_c_check.gd
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
BLENDER="${BLENDER:-/c/Users/joeya/.t3/tools/blender-4.5.16-windows-x64/blender.exe}"
P=art/previews/moxie_c
A=art/moxie_c
wait_mem() { while [ "$(bash tools/mem)" -gt 85 ]; do sleep 30; done; }
bl() { wait_mem; "$BLENDER" --background --threads 6 "$@" 2>&1 | grep -E "Error|Traceback|line [0-9]+|DONE|EXPORTED|REST|strike|tris=" ; }
set -x
wait_mem; TAILN=3 bash $A/run.sh || exit 1                       # parts, skinning, proportion pass -> moxie_model.blend
wait_mem; bash $A/anim.sh --toon                                  # retarget UAL clips -> moxie_anim.blend, contact sheets
bl $A/moxie_anim.blend --python $A/mc_ctrl.py                     # Rigify control rig -> moxie.blend
bl $A/moxie.blend --python $A/mc_ctrl_test.py                     # proves the control rig drives the export skeleton
bl $A/moxie_anim.blend --python $A/mc_export.py                   # -> assets/models/candidates/c/moxie.glb
# ---- previews
wait_mem; MC_NOWARP=1 TAILN=1 bash $A/run.sh --parts head --shots hc --toon && python -I $A/ref_compare.py > $P/head_check.txt
python -I $A/mc_sheet.py $P/head_check.png --cols 3 --h 700 $P/_wip_hc0_toon.png $P/_wip_overlay_front.png $P/_wip_hc2_toon.png $P/_wip_hc1_toon.png $P/_wip_overlay_side.png
for job in "turn relaxed" "turn relaxed --toon" "face relaxed --toon" "iso relaxed --toon" "body tpose" "sheet sheet --toon"; do wait_mem; bash $A/rs.sh $job; done
cp $P/_wip_turn.png $P/turnaround.png; cp $P/_wip_turn_toon.png $P/turnaround_toon.png
cp $P/_wip_face_toon.png $P/face.png; cp $P/_wip_iso0_toon.png $P/toon_iso.png; cp $P/_wip_body.png $P/tpose.png
python -I -c "
from PIL import Image
im=Image.open('$P/_wip_iso0_toon.png'); w,h=im.size
im=im.crop((int(w*0.2),int(h*0.06),int(w*0.8),int(h*0.94)))
im.resize((round(im.width*160/im.height),160),Image.LANCZOS).save('$P/thumb.png')"
python -I $A/body_compare.py > $P/body_check.txt
wait_mem; OUT=$P/deform_tests.png bash $A/deform.sh --toon
rm -f $P/_wip* $P/_c_*
