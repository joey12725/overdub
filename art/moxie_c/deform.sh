#!/usr/bin/env bash
# Deformation test sheet: bash art/moxie_c/deform.sh [--toon] -> art/previews/moxie_c/_wip_deform.png
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
P=art/previews/moxie_c
L=""
for p in ${POSES:-crouch arms_up arms_fwd stride twist head_turn fist}; do
  bash art/moxie_c/rs.sh pose2 $p $1 >/dev/null 2>&1
  S=""; [ "$1" = "--toon" ] && S="_toon"
  cp $P/_wip_pose2$S.png $P/_wip_d_$p.png; L="$L $P/_wip_d_$p.png"
done
python -I art/moxie_c/mc_sheet.py ${OUT:-$P/_wip_deform.png} --cols 4 --h 560 $L
