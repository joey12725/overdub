#!/usr/bin/env bash
# bash art/moxie_c/face.sh [--toon]   -> art/previews/moxie_c/_wip_face.png
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
S=""; [ "$1" = "--toon" ] && S="_toon"
bash art/moxie_c/run.sh --parts ${PARTS:-head} --shots face "$@" && python -I art/moxie_c/mc_sheet.py art/previews/moxie_c/_wip_face$S.png art/previews/moxie_c/_wip_face0$S.png art/previews/moxie_c/_wip_face35$S.png art/previews/moxie_c/_wip_face90$S.png
