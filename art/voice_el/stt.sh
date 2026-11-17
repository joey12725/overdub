#!/usr/bin/env bash
# Transcribe every extracted take with ElevenLabs Scribe (word timestamps) so the words and the endings can
# be checked without ears. Resumable: skips takes whose .stt.json is newer than the mp3.
#   usage (repo root): bash art/voice_el/stt.sh [id-regex]
set -u
D=art/voice_el/takes
FILTER="${1:-.}"
n=0
for mp3 in "$D"/*.mp3; do
  id="$(basename "$mp3" .mp3)"
  [[ "$id" =~ $FILTER ]] || continue
  out="$D/$id.stt.json"
  if [ -s "$out" ] && [ "$out" -nt "$mp3" ]; then continue; fi
  bash tools/voice raw POST /v1/speech-to-text -F model_id=scribe_v1 -F language_code=en -F tag_audio_events=true \
    -F "file=@$mp3" -o "$out.part"
  if grep -q '"words"' "$out.part" 2>/dev/null; then mv "$out.part" "$out"; n=$((n+1))
  else
    msg="$(head -c 300 "$out.part" 2>/dev/null)"; rm -f "$out.part"; echo "FAIL $id: $msg"
    if echo "$msg" | grep -qi 'quota'; then echo "QUOTA EXHAUSTED - stopping"; exit 3; fi
  fi
  sleep 0.3
done
echo "transcribed $n"
