#!/usr/bin/env bash
# Build the web version and publish it to https://overdub.joeyhersh.com (here.now site
# open-yarrow-43vd, cross-origin isolation on, which the threaded web build needs).
#
#   bash tools/web/publish.sh            export + publish
#   bash tools/web/publish.sh --no-publish   export only (build/web/)
#
# Needs the Godot 4.4.1 web export templates in %APPDATA%/Godot/export_templates/4.4.1.stable and
# the here.now skill's publish.sh with an API key in ~/.herenow/credentials.
# Web-only behaviour lives in game/web_compat.gd; reproduce the web renderer on desktop with
#   OVERDUB_WEBCOMPAT=1 bash tools/gd raw --rendering-method gl_compatibility -s res://tools/smoke.gd -- <dir>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SLUG="open-yarrow-43vd"
PUBLISH="${HERENOW_PUBLISH:-$HOME/.claude/skills/here-now/scripts/publish.sh}"
cd "$ROOT"
rm -rf build/web && mkdir -p build/web
bash tools/gd raw --headless --export-release "Web" build/web/index.html > build/export.log 2>&1 || true
[ -s build/web/index.pck ] && [ -s build/web/index.wasm ] || { echo "export failed: see build/export.log" >&2; exit 1; }
ls -la build/web
[ "${1:-}" = "--no-publish" ] && exit 0
bash "$PUBLISH" build/web --slug "$SLUG" --client claude-code
echo "live: https://overdub.joeyhersh.com/"
