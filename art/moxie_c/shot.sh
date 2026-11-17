#!/usr/bin/env bash
# bash art/moxie_c/shot.sh <shot> <parts> [--toon]  -> art/previews/moxie_c/_wip_<shot>[_toon].png (montage)
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
SH="$1"; P="$2"; shift; shift
S=""; [ "$1" = "--toon" ] && S="_toon"
rm -f art/previews/moxie_c/_wip_${SH}[0-9]*$S.png
bash art/moxie_c/run.sh --parts "$P" --shots "$SH" "$@" && python -I art/moxie_c/mc_sheet.py art/previews/moxie_c/_wip_$SH$S.png $(ls art/previews/moxie_c/_wip_${SH}[0-9]*$S.png | sort -t_ -k3 -V)
