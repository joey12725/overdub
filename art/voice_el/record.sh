#!/usr/bin/env bash
# Record every job in art/voice_el/jobs.tsv through `tools/voice raw` (the /with-timestamps endpoint, so each
# take comes back with character timings). Resumable: a job whose raw/<id>.json exists is skipped, so a
# re-record is "delete raw/<id>.json, run again". Stops at the first quota error.
#   usage (repo root): bash art/voice_el/record.sh [id-regex]
set -u
D=art/voice_el
FILTER="${1:-.}"
mkdir -p "$D/raw"
ok=0; skip=0; fail=0
while IFS=$'\t' read -r id voice model settings text; do
  [[ "$id" =~ $FILTER ]] || continue
  out="$D/raw/$id.json"
  if [ -s "$out" ]; then skip=$((skip+1)); continue; fi
  req="$(mktemp)"
  node -e 'process.stdout.write(JSON.stringify({text:process.argv[1],model_id:process.argv[2],voice_settings:JSON.parse(process.argv[3])}))' "$text" "$model" "$settings" > "$req"
  bash tools/voice raw POST "/v1/text-to-speech/$voice/with-timestamps?output_format=mp3_44100_128" \
    -H 'Content-Type: application/json' --data-binary "@$req" -o "$out.part"
  rm -f "$req"
  if grep -q '"audio_base64"' "$out.part" 2>/dev/null; then
    mv "$out.part" "$out"; ok=$((ok+1)); echo "ok   $id"
  else
    msg="$(head -c 300 "$out.part" 2>/dev/null)"; rm -f "$out.part"; fail=$((fail+1))
    echo "FAIL $id: $msg"
    if echo "$msg" | grep -qi 'quota'; then echo "QUOTA EXHAUSTED - stopping (recorded $ok this run)"; exit 3; fi
    if echo "$msg" | grep -qi 'too_many\|rate'; then sleep 20; fi
  fi
  sleep 0.4
done < "$D/jobs.tsv"
echo "done: $ok recorded, $skip already present, $fail failed"
