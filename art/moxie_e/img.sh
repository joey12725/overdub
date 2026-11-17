#!/usr/bin/env bash
# Quiet, retrying wrapper around tools/img:  bash art/moxie_e/img.sh <gen|edit> <out.png> "<prompt>" [inputs...]
# (IMG_SIZE / IMG_BG pass through). Prints one line: OK <out> or FAIL <out>.
out="$2"
for try in 1 2 3; do
  rm -f "$out"
  bash "$(dirname "$0")/../../tools/img" "$@" >/dev/null 2>&1
  if [ -s "$out" ]; then echo "OK $out"; exit 0; fi
  sleep 5
done
echo "FAIL $out"; exit 1
