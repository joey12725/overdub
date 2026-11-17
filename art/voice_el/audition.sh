#!/usr/bin/env bash
# Audition: one short characteristic line per candidate voice. Skips takes that already exist.
# usage: bash art/voice_el/audition.sh   (run from repo root)
set -u
A=art/voice_el/audition
M="Bottom floor, biggest score, back by dinner. Easy money."
O="I sold you a Walkman. You're wearing a miracle. Different shelf."
T="This floor needs four people. My four went home. Sensibly."
R="The master deck. It does not replay. It records over."
go() { # char name voice text model settings
  local out="$A/$1_$2.mp3"; [ -s "$out" ] && return 0
  bash tools/voice tts "$out" "$3" "$4" "$5" "$6" || echo "FAIL $1 $2"
  sleep 1
}
V3='{"stability":0.5}'
go moxie laura   FGY2WhTYpPnrIDTdsKH5 "$M" eleven_v3 "$V3"
go moxie aria    9BWtsMINqrJLrRacOO3C "$M" eleven_v3 "$V3"
go moxie sarah   EXAVITQu4vr4xnSDxMaL "$M" eleven_v3 "$V3"
go moxie domi    AZnzlnDR4QXp1BHB5isn "$M" eleven_v3 "$V3"
go moxie elli    MF3mGyEYCl7XYlAyWlXr "$M" eleven_v3 "$V3"
go opal matilda   XrExE9yKDx5AmxEUTxtp "[deadpan] $O" eleven_v3 "$V3"
go opal alice     Xb7hH8MSUJpSvxLZwZvK "[deadpan] $O" eleven_v3 "$V3"
go opal lily      pFZP5JQG7iQjIQuC4Bku "[deadpan] $O" eleven_v3 "$V3"
go opal charlotte XB0fDUnXU5powFXDhCwa "[deadpan] $O" eleven_v3 "$V3"
go opal rachel    21m00Tcm4TlvDq8ikWAM "[deadpan] $O" eleven_v3 "$V3"
go opal serena    pMsXgVXv3BLzUgSXRplE "[deadpan] $O" eleven_v3 "$V3"
go tolly liam    TX3LPaxmHKxFdv7VOQHJ "$T" eleven_v3 "$V3"
go tolly will    bIHbv24MWmeRgasZH3fv "$T" eleven_v3 "$V3"
go tolly chris   iP95p4xoKVk53GoZ742B "$T" eleven_v3 "$V3"
go tolly charlie IKne3meq5aSn9XLyUdCD "$T" eleven_v3 "$V3"
go tolly eric    cjVigY5qzO86Huf0OWal "$T" eleven_v3 "$V3"
V2='{"stability":0.9,"similarity_boost":0.75,"style":0.0,"use_speaker_boost":true}'
go archivist brian  nPczCjzI2devNBz1zQrb "$R" eleven_multilingual_v2 "$V2"
go archivist bill   pqHfZKP75CvOlQylNhV4 "$R" eleven_multilingual_v2 "$V2"
go archivist george JBFqnCBsd6RMkjVDRZzb "$R" eleven_multilingual_v2 "$V2"
go archivist daniel onwK4e9ZLuTAKqWW03F9 "$R" eleven_multilingual_v2 "$V2"
go archivist river  SAz9YHcvj6GT2YYXdXww "$R" eleven_multilingual_v2 "$V2"
# second round: replacements for retired ids (aria, domi, elli, matilda, alice, will were voice_not_found)
go moxie freya   jsCqWAovK2LkecY7zXl4 "$M" eleven_v3 "$V3"
go moxie gigi    jBpfuIE2acCO8z3wKNLl "$M" eleven_v3 "$V3"
go opal glinda   z9fAnlkpzviPz146aGWa "[deadpan] $O" eleven_v3 "$V3"
go opal grace    oWAxZDx7w5VEj9dCyTzz "[deadpan] $O" eleven_v3 "$V3"
