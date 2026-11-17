#!/usr/bin/env bash
# Wrapper around the image helper (art/ui_art/img_local = tools/img with an overridable tunnel port)
# that logs every prompt to art/ui_art/PROMPTS.md and retries when the response is cut off.
#   bash art/ui_art/run.sh gen  <name> "<prompt>" [size] [background]
#   SIZE=1536x1024 BG=transparent bash art/ui_art/run.sh edit <name> "<prompt>" <inputs...>
# Output lands in art/ui_art/raw/<name>.png
cd "$(dirname "$0")/../.." || exit 1
cmd="$1"; name="$2"; prompt="$3"; shift 3
out="art/ui_art/raw/$name.png"
{
  echo "## $name"
  echo "- call: $cmd  args: $* ${SIZE:+size=$SIZE} ${BG:+bg=$BG}"
  echo
  echo "$prompt"
  echo
} >> art/ui_art/PROMPTS.md
export OD_IMG_PORT="${OD_IMG_PORT:-18417}"
rm -f "$out"
for try in 1 2 3; do
  if [ "$cmd" = edit ]; then
    IMG_SIZE="${SIZE:-1024x1024}" IMG_BG="${BG:-auto}" bash art/ui_art/img_local edit "$out" "$prompt" "$@" 2>&1 | tail -c 200
  else
    bash art/ui_art/img_local gen "$out" "$prompt" "$@" 2>&1 | tail -c 200
  fi
  [ -s "$out" ] && exit 0
  echo "retry $try for $name"; sleep 5
done
exit 1
