# OVERDUB voice cast (ElevenLabs)

All 160 spoken lines of `data/story/story.json`, Moxie's count-in, deck calls and non-verbal efforts,
generated with ElevenLabs and processed offline so the game plays the files directly.

- Game files: `assets/audio/voice/elevenlabs/` (44.1 kHz, mono, 16-bit WAV) with `manifest.json`.
- Sources, scripts, raw takes, measurements: `art/voice_el/` (not imported by Godot: `art/.gdignore`).
- This set supersedes the fallback voice set elsewhere under `assets/audio/voice/` wherever both have a file.

Nobody listened to these files. Every choice below was made from measurements (pace, pitch, loudness,
artefact checks) and from ElevenLabs Scribe transcripts of each take. A human listen-through before release
is still needed; the section "Not verified" lists what measurement cannot tell.

## 1. Cast

| Character | Voice | Voice id | Model | Settings | Treatment |
|---|---|---|---|---|---|
| Moxie | Laura | `FGY2WhTYpPnrIDTdsKH5` | `eleven_v3` | stability 0.5 | dry |
| Opal | Lily | `pFZP5JQG7iQjIQuC4Bku` | `eleven_v3` | stability 0.5 | radio, pitched down 1.5 st |
| Tolliver | Eric | `cjVigY5qzO86Huf0OWal` | `eleven_v3` | stability 0.5 | dry, plus a mild comms copy |
| Archivist | Brian | `nPczCjzI2devNBz1zQrb` | `eleven_multilingual_v2` | stability 0.9, similarity 0.75, style 0, speaker boost on | tape playback |

Why these four:

- **Moxie: Laura.** Highest median pitch of the usable young voices (190 Hz) with the widest lively range
  short of Freya (10.7 st), the shortest internal pause (0.36 s) and the fastest articulation (4.84 syl/s):
  quick and conversational. Sarah measured flatter (6.4 st range: reads as a narrator) and hot (-0.6 dBFS
  peak); Freya and Gigi were slower (3.0 and 3.4 syl/s) with long pauses (0.82 s for Freya), which is the
  announcer cadence the brief rules out; Jessica was the runner-up (close pace, but 23 Hz lower and nearer
  to Opal's register).
- **Opal: Lily.** The flattest delivery of the six (6.2 st range) at an unhurried 3.44 syl/s, no clipping,
  the lowest peak. Deadpan is a narrow pitch range; Lily had it without being slow. Charlotte had a 1.47 s
  pause in a three-sentence line; Grace was the fastest and most animated (10.4 st); Serena and Glinda were
  flat but their short-term loudness barely moved (2.3 and 2.9 LU), which after radio compression leaves
  nothing. Lily's raw register (160 Hz) is close to Moxie's, so Opal is varisped down 1.5 semitones in
  processing (about 155 Hz across her lines against Moxie's 197 Hz) and band-limited, which also ages her.
- **Tolliver: Eric.** The widest pitch range of the four men (15.4 st: earnest, slightly breathless) at a
  careful 2.6 syl/s, 140 Hz: clearly above the Archivist and clearly below both women. Liam and Chris were
  low (93 and 105 Hz) and would crowd the Archivist; Charlie was the slowest with a dull top end.
- **Archivist: Brian.** The lowest voice auditioned (88 Hz median), the steadiest loudness (short-term
  s.d. 1.97 LU against 3.8 to 4.6 for the others), the shortest pauses (0.16 s) and an even, quick pace
  (4.8 syl/s): a catalogue being read out. River was flatter in pitch (6.2 st) but sits at 175 Hz, inside
  the women's range. On `eleven_multilingual_v2` with stability 0.9 and style 0 the reading does not act;
  the machine quality comes from the tape treatment, not from a robot preset.

Across the finished set (lines of five syllables or more) the four sit apart:

| Character | Lines | Median pitch | Pitch range | Pace (syl/s) | Articulation (syl/s) |
|---|---|---|---|---|---|
| Moxie | 107 | 197 Hz | 11.7 st | 3.48 | 4.43 |
| Opal | 16 | 169 Hz raw, about 155 Hz after varispeed | 9.3 st | 3.54 | 4.33 |
| Tolliver | 11 | 147 Hz | 13.6 st | 3.62 | 4.64 |
| Archivist | 26 | 95 Hz | 11.6 st | 4.81 | 5.31 |

### Audition table

One line per candidate, same line per character, `art/voice_el/audition/` (`audition.sh`,
`audition_analyze.py`, `metrics.json`). Pitch by normalised autocorrelation (`vx.pitch_track`), range is
5th to 95th percentile in semitones, loudness is BS.1770 integrated, "sd" is the spread of 400 ms short-term
loudness, "gap" is the longest internal silence. No take clipped.

Lines: Moxie "Bottom floor, biggest score, back by dinner. Easy money." / Opal "[deadpan] I sold you a
Walkman. You're wearing a miracle. Different shelf." / Tolliver "This floor needs four people. My four went
home. Sensibly." / Archivist "The master deck. It does not replay. It records over."

| Role | Voice | Dur s | Syl/s | Artic syl/s | F0 med Hz | F0 p5-p95 Hz | Range st | LUFS | sd LU | Peak dB | Gap s | HF dB | Chosen |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Moxie | Laura | 3.95 | 3.54 | 4.84 | 190 | 149-276 | 10.7 | -19.0 | 4.0 | -1.8 | 0.36 | -16.1 | yes |
| Moxie | Jessica | 3.91 | 3.58 | 4.83 | 167 | 147-245 | 8.8 | -18.9 | 3.6 | -2.0 | 0.51 | -15.1 | |
| Moxie | Sarah | 4.02 | 3.49 | 4.44 | 193 | 159-230 | 6.4 | -14.1 | 4.0 | -0.6 | 0.45 | -18.0 | |
| Moxie | Gigi | 4.10 | 3.41 | 4.58 | 160 | 128-216 | 9.1 | -15.2 | 3.7 | -1.5 | 0.48 | -10.2 | |
| Moxie | Freya | 4.64 | 3.02 | 4.43 | 153 | 121-248 | 12.4 | -14.2 | 3.7 | -0.8 | 0.82 | -11.1 | |
| Opal | Lily | 4.95 | 3.44 | 4.86 | 160 | 140-201 | 6.2 | -20.0 | 4.1 | -3.1 | 0.77 | -12.9 | yes |
| Opal | Serena | 4.47 | 3.81 | 5.67 | 153 | 128-190 | 6.8 | -17.6 | 2.3 | -2.8 | 0.73 | -9.2 | |
| Opal | Glinda | 4.92 | 3.45 | 5.11 | 165 | 131-204 | 7.7 | -17.4 | 2.9 | -1.2 | 0.98 | -11.6 | |
| Opal | Rachel | 4.88 | 3.48 | 5.35 | 155 | 133-216 | 8.4 | -17.2 | 3.3 | -2.4 | 0.84 | -9.3 | |
| Opal | Charlotte | 5.76 | 2.95 | 5.17 | 143 | 116-190 | 8.5 | -19.5 | 5.1 | -2.4 | 1.47 | -8.1 | |
| Opal | Grace | 4.20 | 4.05 | 5.41 | 131 | 104-190 | 10.4 | -16.9 | 4.5 | -0.3 | 0.47 | -10.1 | |
| Tolliver | Eric | 4.95 | 2.63 | 4.01 | 140 | 88-214 | 15.4 | -20.4 | 4.0 | -4.9 | 0.69 | -18.5 | yes |
| Tolliver | Chris | 3.68 | 3.53 | 4.73 | 105 | 76-165 | 13.5 | -19.2 | 4.0 | -1.8 | 0.53 | -19.1 | |
| Tolliver | Liam | 3.60 | 3.61 | 4.68 | 93 | 66-134 | 12.1 | -25.6 | 5.0 | -7.1 | 0.43 | -17.5 | |
| Tolliver | Charlie | 5.05 | 2.57 | 3.80 | 108 | 68-159 | 14.7 | -21.2 | 4.7 | -3.6 | 0.67 | -21.5 | |
| Archivist | Brian | 2.90 | 4.82 | 5.43 | 88 | 66-119 | 10.0 | -24.0 | 2.0 | -5.2 | 0.16 | -15.8 | yes |
| Archivist | River | 2.82 | 4.97 | 6.17 | 175 | 138-197 | 6.2 | -22.3 | 3.8 | -1.6 | 0.26 | -14.7 | |
| Archivist | George | 3.04 | 4.60 | 5.60 | 159 | 100-216 | 13.3 | -22.2 | 4.6 | -2.7 | 0.24 | -16.2 | |
| Archivist | Bill | 3.62 | 3.87 | 5.17 | 131 | 91-199 | 13.5 | -23.5 | 3.8 | -6.6 | 0.46 | -13.1 | |
| Archivist | Daniel | 3.89 | 3.60 | 5.04 | 127 | 76-156 | 12.5 | -23.4 | 4.1 | -6.8 | 0.46 | -10.0 | |

Six stock ids from the brief returned `voice_not_found` on this account and could not be auditioned: Aria,
Domi, Elli, Matilda, Alice and Will. Freya, Gigi, Glinda, Grace and Serena were added in their place.

## 2. What was recorded

| Set | Scripted | Recorded | Files |
|---|---|---|---|
| Story lines (levels, once, ending, stinger) | 160 | 160 | 171 (Tolliver's 11 exist dry and on comms) |
| Count-in words | 4 words, 2 intensities, 3 takes | 24 | 24 |
| Deck calls | 4 phrases, 2 readings | 8 | 8 |
| Efforts | 15 | 15 | 15 |

By character: Moxie 107 lines (4 min 41 s), Archivist 26 (1 min 04 s), Opal 16 (1 min 06 s), Tolliver 11
(36 s). Total dialogue 7 min 28 s. 189 requests, about 9,000 characters, plus 20 audition lines and 11
retakes.

Ids are positional and stable: `l01_intro_02` is `levels.01-*.intro[1]`, `l04_firstdeath_01`,
`once_firstghosttake_01`, `bark_death_03`, `ending_05`, `stinger_01`. `manifest.json` has `byLocation` for
the reverse lookup.

Direction was written as one `eleven_v3` audio tag in front of the line, chosen from the script's
`expression` (`art/voice_el/script_lines.py`, `TAGS`); the spoken words are exactly the script. Moxie's barks
use an "offhand" variant of each tag so they are thrown away, not performed. The Archivist gets no tags
(`eleven_multilingual_v2` would read them aloud). The two radio cuts in the script (`...don't you d--`,
`--oxie? ...`) were synthesised with the whole word and cut at Scribe's word timestamp, then closed or opened
with a static burst, so what is heard is the script.

Retakes (old takes kept in `art/voice_el/rejected/`):

| Id | Why |
|---|---|
| `ending_05` | `eleven_v3` returned music instead of speech |
| `bark_death_03` | "the next me" came out as another word twice; third take correct |
| `bark_desync_03` | final "take" lost its last consonant |
| `l12_outro_01` | "cut" heard as "cuts" |
| `l10_idle_01`, `once_firstghosttake_01`, `bark_rescue_04` | ended too abruptly to fade cleanly |
| `bark_bossrecall_02` | "It kept" heard as "I kept" in all three takes; the third is used (see Not verified) |
| `effort_dodge_2` | first prompt was spoken as letters; re-prompted as `[sharp gasp] Hh!` |

## 3. Processing chains

`python -I art/voice_el/process.py` (numpy/scipy; ffmpeg only for MP3 decoding). Deterministic: noise is
seeded from the line id.

Common to every line: trim to the speech bounds (12 ms pre-roll, up to 140 ms of the take's own tail),
4 ms fade in, fade out 40 ms where the take has a tail and 80 to 120 ms where it stops hot, the character's
treatment, then loudness to -18 LUFS (BS.1770, measured after treatment) through a look-ahead limiter with
a -1 dBFS ceiling.

- **Moxie**: 70 Hz high-pass. Nothing else.
- **Opal** (radio): varispeed -1.5 st, 350 to 3000 Hz band (4th-order), +4 dB presence at 1.8 kHz, 4:1
  compression 8 dB under the speech level, tanh saturation, hiss bed 30 dB under the speech, sparse crackle
  (about 9 clicks a second, the largest 3 dB over the speech RMS), 60 ms of bed before and a 160 ms squelch
  tail after.
- **Tolliver**: `tolly/` is dry (he is met in person). `tolly_radio/` is the same takes on comms: 250 to
  4200 Hz, +2 dB presence, 2.5:1, hiss at -40 dB, no crackle.
- **Archivist** (tape playback): 60 Hz to 9 kHz, +1.5 dB at 220 Hz, fixed 11 ms and 23 ms layers at -8 and
  -12 dB (a static comb, so pitch does not move), print-through echo 350 ms later at -30 dB, light
  saturation, hiss at -50 dB. By the script's expression: `idle` adds 4 cents of 0.6 Hz wow and 1.5 cents
  of 6.5 Hz flutter; `playback` (it is quoting a recording) 9 and 3 cents plus a 140 ms reel run-up; `still`
  uses one layer and no wow.
- **Count-in**: three counted phrases per intensity were recorded whole ("Five. Six. Seven. Eight." with
  `[counting in, clipped, rhythmic]`, and "Five! Six! Seven! Eight!" with `[calling out, loud, clipped,
  rhythmic]`) so the four words of a take share one breath and pitch centre, then sliced. Each word is cut
  from the silence before its consonant to the silence after it, a leading consonant longer than 80 ms is
  shortened to 80 ms, the word is tightened without changing pitch (WSOLA, at most 1.3x) towards 345 ms and
  capped at 380 ms with a 45 ms fade. Results: 346 to 381 ms; "five" and "eight" are mostly near 346 ms, "six"
  and "seven" mostly at the 381 ms cap, where the last consonant is faded short. Peak -3 dBFS.
- **Deck calls and efforts**: trimmed (4 ms pre-roll), 80 Hz high-pass, faded, peak -3 dBFS. Efforts keep
  only the strongest segment of the take when the model added a breath or second sound after a pause.

## 4. Loudness and verification

`python -I art/voice_el/verify.py` writes `art/voice_el/verify.json`. Final run: **189 jobs, 218 files,
0 problems**, 5 transcript differences waived.

| Folder | Files | Integrated LUFS (mean, s.d., min to max) | Peak dBFS (max) | Duration s | Longest internal gap s |
|---|---|---|---|---|---|
| `moxie/` | 107 | -17.94, 0.21, -18.98 to -17.25 | -1.00 | 0.76 to 6.10 | 0.68 |
| `opal/` | 16 | -17.96, 0.09, -18.10 to -17.81 | -5.51 | 1.94 to 6.75 | 0.61 |
| `tolly/` | 11 | -17.95, 0.21, -18.50 to -17.66 | -1.34 | 1.61 to 4.56 | 0.91 |
| `tolly_radio/` | 11 | -17.89, 0.13, -18.12 to -17.68 | -4.11 | 1.83 to 4.78 | 0.80 |
| `archivist/` | 26 | -17.91, 0.14, -18.13 to -17.67 | -1.00 | 0.93 to 4.73 | 0.42 |
| `count/` | 24 | one-shots | -3.00 | 0.35 to 0.38 | 0.08 |
| `calls/` | 8 | one-shots | -3.00 | 0.51 to 1.55 | 0.39 |
| `efforts/` | 15 | one-shots | -3.00 | 0.37 to 1.46 | 0.06 |

LUFS is over files of 1 s or more (gating is unreliable on shorter ones).

Checks per file: format 44.1 kHz mono 16-bit; peak under -0.5 dBFS; duration between syllables/8 and
syllables/1.4 + 1.2 s; no internal silence over 0.9 s (1.3 s where the line has an ellipsis); the last 50 ms
at least 9 dB under the speech level and the last 2 ms under -45 dBFS; lines within 1 LU of -18. Checks per
take: Scribe's transcript equals the script words, including the last word.

Exceptions made by hand, all recorded in `verify.py`:

- `l06_outro_01` ("You sent yourself out as bait. Twice.") is allowed a 1.0 s gap (measured 0.91 s): the
  pause before "Twice" is the line.
- Transcript differences waived as transcription, not performance: `l06_intro_01` ("Mind" heard as "Mine"),
  `l06_intro_02` ("How" spelled "Hao"), `l09_intro_04` ("Opal" split as "Oh pal"),
  `bark_archivistrecall_03` ("Read" pronounced "red", which is correct), `bark_bossrecall_02` (below).

### Not verified

- **Nobody has heard any of it.** Tone, sarcasm, whether a bark sounds thrown away, and whether the radio
  and tape treatments are pleasant are judged from numbers only.
- **`bark_bossrecall_02`** ("Old trick. It kept the receipt."): Scribe heard "I kept the receipt" in all
  three takes. Most likely an unreleased /t/ before /k/, but it may really say "I". Listen to this one.
- **Abrupt endings.** 36 of the `eleven_v3` takes end 40 to 60 ms after the last word with the vowel still
  sounding (the service trims tails hard). The words are complete by transcript and the files are released
  with an 80 to 120 ms fade, but some last words may sound clipped short. Retakes did not change this.
- **Efforts.** Scribe labels them only loosely (`[grunts]`, `[sighs]`, "Ha!", "Ah."). The two heavy attack
  shouts `effort_attack_heavy_1` and `_2` are long (1.38 and 1.29 s); `effort_death_1` was tagged as a sigh;
  `effort_laugh_1` was cut to its first 0.61 s. Whether they are convincing needs ears.
- **Count-in pitch.** The spoken takes sit around 180 to 315 Hz and the called takes 250 to 410 Hz, and the
  pitch moves from word to word. They are not tuned to any key.

## 5. Manifest

`assets/audio/voice/elevenlabs/manifest.json` (written by `art/voice_el/manifest.py`):

- `base`, `format`, `loudness`, `cast` (voice, id, model, settings, treatment per character).
- `lines[id]`: `file`, `character`, `expression`, `text` (exactly the script), `duration` (seconds),
  `location` (the story.json path, such as `levels.04-second-opinion.intro[0]`), `kind` (`line` or `bark`),
  `treatment`; Tolliver's lines also have `radio: {file, duration}`; the two cut lines have `radioCut`.
- `byLocation[location]` gives the id.
- `countIn[word][spoken|called]`: list of `{file, duration, vowelOnset, take}`.
- `deckCalls[one_more_time|rolling|thats_a_take|again]`: list of `{file, duration, text}`.
- `efforts[attack_light|attack_heavy|dodge|hit|death|laugh|hm]`: list of `{file, duration, prompt}`.
- `missing`: empty.

## 6. Integration

None of this is wired in. There is no dialogue bus and no voice setting in the project yet; the steps below
are what the audio and dialogue engineers need to add.

**Audio engineer**

1. Add a `Voice` bus sending to `Master` in `audio/audio_bus_setup.gd` `_plan()` (after `Ui`, so the order
   rule holds) and regenerate `default_bus_layout.tres`. Dialogue lines and barks play on `Voice`. The
   count-in, deck calls and efforts play on the existing `Ui` and `Sfx` buses (count and calls on `Ui`,
   efforts on the acting tape's `SfxA..D`).
2. Levels: lines are at -18 LUFS with a -1 dBFS ceiling. Start `Voice` at 0 dB and set one-shots by ear
   against the music; they are at -3 dBFS peak, so expect about -6 dB on count-in and -8 dB on efforts.
3. Ducking: while a dialogue line plays, lower `Music` by 6 dB (80 ms down, 400 ms back up after the line
   ends plus 150 ms). Barks duck `Music` by 3 dB only. Do not duck `Sfx`. A sidechain compressor on `Music`
   keyed from `Voice` (threshold -30 dB, ratio 3, attack 20 ms, release 350 ms) gives the same result with no
   script.
4. Count-in: once per count-in pick an intensity (`spoken` normally, `called` for the last tape or a boss
   floor) and one take number, and use that take for all four words so they match. Schedule each word at
   `beat_time - vowelOnset` (15 to 70 ms, per file, in the manifest) so the vowel lands on the beat; use the
   audio clock (`AudioServer.get_time_to_next_mix()` plus output latency), not `_process` time. Files are at
   most 381 ms, so they do not overlap at 150 bpm (400 ms a beat). Play at `pitch_scale` 1.0: they are not
   tuned, so do not transpose them to the level key; a shift of more than about 2 semitones also changes
   their length.
5. Efforts: choose at random within the group without repeating the last one; vary `pitch_scale` by plus or
   minus 3 per cent. At most one effort per tape every 150 ms; attack efforts on about one swing in three,
   not every swing.
6. Setting: add `voices` (`on`, `count-in only`, `off`) to the audio settings, plus a `Voice` volume slider
   bound to the bus. `off` mutes the `Voice` bus and skips count, calls and efforts; UI-04 requires the
   count-in to be audible by default, so `count-in only` keeps the count words and the visual count stays on
   in every mode.

**Dialogue engineer**

1. Load `manifest.json` once. For a story entry at `levels.<key>.<section>[i]`, `once.<key>[i]`,
   `barks.<key>[i]`, `ending[i]` or `stinger[i]`, look up `byLocation[location]`, then `lines[id].file`
   under `res://assets/audio/voice/elevenlabs/`. If the id is absent, show the text box silently.
2. Hold the text box for at least `duration + 0.35 s`; advancing early stops the line with a 60 ms fade.
3. Tolliver: play `tolly/` when he is on site and `radio.file` (`tolly_radio/`) when he is on comms. Opal
   and the Archivist have their treatment baked in; do not add a radio effect on top.
4. Barks: at most one bark at a time, never over a dialogue line, at least 6 s between barks and 20 s before
   the same bark key repeats, never the same line twice running. Death, fail and win barks may ignore the
   6 s gap. Play a bark on about half of its eligible events so it stays a remark, not a tic.
5. Deck calls (`rolling`, `one_more_time`, `again`, `thats_a_take`) are optional: `rolling` when recording
   starts, `again` or `one_more_time` on a retry, `thats_a_take` when a take is kept. They share the bark
   rate limit.

**Rebuilding**

From the repo root, with ffmpeg on PATH (or `OD_FFMPEG` set):

```
python -I art/voice_el/script_lines.py     # jobs.tsv from story.json
bash art/voice_el/record.sh                # only ids with no raw/<id>.json; delete one to re-record it
python -I art/voice_el/extract.py
bash art/voice_el/stt.sh                   # Scribe transcripts, used for checks and for slicing
python -I art/voice_el/process.py
python -I art/voice_el/verify.py
python -I art/voice_el/manifest.py
```

A changed line in `story.json` needs its `raw/<id>.json` deleted before `record.sh`. Inserting a line in the
middle of a list shifts the ids after it.

## 7. Licence and terms

What is known:

- Speech was generated through the account's API key with ElevenLabs' stock library voices (Laura, Lily,
  Eric, Brian), not cloned or community voices.
- ElevenLabs' published terms grant commercial use of generated audio to accounts on a paid plan. The free
  plan does not include a commercial licence and requires attribution to ElevenLabs.
- Their terms prohibit using output to train competing speech models and prohibit impersonating real people;
  neither applies here.

What could not be verified:

- **The plan this account is on.** The key lacks `user_read`, so the subscription cannot be queried. Whether
  these files may ship commercially depends on it. The account owner should check the plan in the ElevenLabs
  dashboard before release; if it is the free plan, either upgrade and regenerate, or ship non-commercially
  with attribution.
- Whether a licence obtained on a paid plan continues for files generated before a downgrade, and the
  current wording of the terms. They were not fetched for this work; read them at elevenlabs.io/terms before
  release.
- `eleven_v3` was used for three of the four voices; whether any model-specific terms apply to it was not
  checked.

Suggested credit line, to be confirmed against the plan: "Voices generated with ElevenLabs."
