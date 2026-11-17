#!/usr/bin/env bash
# Runs the portable Blender with a private user-resources dir (so MPFB lives inside art/moxie_b
# and nothing is installed into the machine-wide Blender profile).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BLENDER_USER_RESOURCES="$(cygpath -w "$HERE/_blender_user")"
exec "/c/Users/joeya/.t3/tools/blender-4.5.16-windows-x64/blender.exe" "$@"
