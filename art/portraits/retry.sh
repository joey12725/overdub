#!/usr/bin/env bash
# usage: bash art/portraits/retry.sh <out.png> <command...>   - the image proxy sometimes returns an empty body; retry up to 4 times.
out="$1"; shift; rm -f "$out"
for i in 1 2 3 4; do "$@" >/dev/null 2>&1; [ -s "$out" ] && { echo "ok $out (try $i)"; exit 0; }; sleep 5; done
echo "FAILED $out"; exit 1
