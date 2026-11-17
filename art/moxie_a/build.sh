#!/usr/bin/env bash
# Rebuild Moxie (candidate A) from scratch. Run from anywhere:  bash art/moxie_a/build.sh [previews]
#   stages s1..s8 -> art/moxie_a/moxie.blend, s9 -> assets/models/candidates/a/moxie.glb,
#   then the Godot AnimationLibrary and the Godot-side check. `previews` also re-renders the stills.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BLENDER="${BLENDER:-/c/Users/joeya/.t3/tools/blender-4.5.16-windows-x64/blender.exe}"
W() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
run() { echo "== $*"; "$BLENDER" --background "$@" 2>&1 | grep -E "^S[0-9]+ |^S[0-9]+ OK|EXPORT OK|CONTROL|Traceback|Error|  File " || true; }
cd "$HERE"
mkdir -p work gen
[ -f gen/godot_humanoid_profile.json ] || (cd "$ROOT" && bash tools/gd script res://art/moxie_a/godot/dump_profile.gd)
for s in s1_base s2_face s3_hair s4_outfit s5_gear s6_assemble s7_anim s8_control; do run --python "$s.py"; done
run moxie.blend --python s9_export.py
(cd "$ROOT" && bash tools/gd script res://art/moxie_a/godot/build_anim_lib.gd | grep -E "clip|saved|ERROR" ; bash tools/gd script res://tools/moxie_a_check.gd | grep -E "RESULT|FAIL|humanoid|rest orientation|triangles")
if [ "${1:-}" = "previews" ]; then
  P="$(W "$ROOT/art/previews/moxie_a")"
  run moxie.blend --python render_previews.py -- "$P"
  run moxie.blend --python render_deform.py -- "$P\\deform_tests.png"
  run moxie.blend --python render_anim.py -- "$P" all 8
  run moxie.blend --python test_control.py -- "$P\\control_rig_test.png"
  (cd "$ROOT" && bash tools/gd shot res://tools/moxie_a_check.gd | grep -E "RESULT|screenshots")
fi
