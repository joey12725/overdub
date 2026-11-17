# OVERDUB — the score

Requirements chapters 14 and 15: MUSIC-01..13, OPEN-22 (state maps), OPEN-23 (quantisation latency).

Every level's soundtrack is four generated cassette layers, one Harmonograph formula each. A layer
sounds only while its cassette is recorded (or being recorded), at that cassette's tape speed, and it
changes when that self dies, desyncs, reverses or stops. This document is the composer's hand-over:
what each piece is, how it was checked, and how to put it into the game.

**Nobody has heard this music.** The composer cannot listen. Everything below is verified
numerically, on the note streams the game's own code produces. The numbers say the pieces are in key,
aligned and uncluttered in every combination; they cannot say the pieces are beautiful. A person
should listen to each level once (`tools/audio_preview.gd`, or the prototype) before this is called
final.

| What | Where |
|---|---|
| One file per level, plus the menu bed | `data/music/<NN>-<slug>.json`, `data/music/menu.json` |
| The score as written by the composer (keys, roles, rhythm, formula shortlists) | `art/music/pieces.ts` |
| Tuned result of the search (source of the `music` blocks) | `art/music/tuned.json` |
| State maps, SFX pitch policy, latency policy | `art/music/statemaps.ts` (copied into every data file) |
| Analysis tools | `art/music/*.ts`, `art/music/merge.py` |
| Last measured numbers | `art/music/out/metrics.json` (after), `metrics-drafts.json` (before) |

## The arc

The descent is one long modulation away from home and back.

- **Upper ruins (01–04): warm and open.** Home is G. Major pentatonic, then Mixolydian, Lydian and
  Dorian: each level adds one coloured note to a bright scale. Lo-fi and boom-bap kits with swing.
- **The middle (05–07): colder and off the bar.** B minor (the relative of home's dominant), F# Dorian,
  C# Phrygian: a walk up the circle of fifths while the modes darken. Phrases of 7, 6, 5 and 3 steps
  that cross the barline. No swing.
- **Lower levels (08–10): heavy, neon, hypnotic.** C minor pentatonic, F minor, A# Phrygian: the floor
  drops a semitone from C# to C, then falls by fifths into flat keys. Short loops, straight eighths, half-time kits that turn into
  four-on-the-floor when a tape runs double.
- **The boss (11): F# harmonic minor**, one semitone under home and pulling at it. Two chords, i and
  iv, and never a dominant: no release.
- **The finale (12): G major.** Home with every note filled in. The first level's Fibonacci lead and
  Euclidean hats return over a Lucas bass (Fibonacci's sibling) and chords drawn by the harmonograph
  curve itself.

## The pieces

Cassettes are listed 1 to 4. A level only ever sounds cassettes 1..`maxTapes`, so the order is part of
the composition: cassette 1 has to stand alone.

| # | Level | Key, bpm | Cassettes 1–4 | The piece |
|---|---|---|---|---|
| 01 | Soft Open | G major pentatonic, 90 | lead `fibonacci` · pad `sine` · bass `triangle` · kit `euclid` (Lo-fi 80) | A Fibonacci music-box line, alone (the level has one cassette). Five notes, no possible clash: the warmest the game sounds. |
| 02 | Hit Harder | A Mixolydian, 100 | bass `collatz` · kit `euclid` (Boom bap) · lead `triangular` · chords `saw` | A Collatz hailstone riff that climbs and crashes. It is the only layer the level plays: a walk at 1x, a drive at 2x. |
| 03 | Hold the Door | C Lydian, 120 | chords `spiral` · bass `ruler` · lead `popcount` · kit `modgate` (Dancehall) | One long chord per bar on a spiral, over a ruler-sequence bass in slow quarters. Music that waits. |
| 04 | Second Opinion | E Dorian, 100 | lead `norgard` · chords `lissajous` 2:3 · bass `linear` · kit `staircase` (Lo-fi 80) | Nørgård's infinity series contains itself at half speed, so a 2x take and a 1x take sing in canon; Lissajous chords answer off the beat. |
| 05 | Dead Air | B minor, 120 | bass `recaman` · lead `primes` · chords `cardioid` · kit `logistic` (Trap) | Seven-step phrases that never sit square. A searching Recamán bass, a lead that only knows primes, one swell per bar. No kit in the level as it stands. |
| 06 | Crossfire | F# Dorian, 100 | kit `polymeter` 3\|8 (Jungle) · lead `lissajous` 3:5 · bass `times` · chords `rose` | Threes against fours: hats every third step, a lead phrased in six, chords every third beat. |
| 07 | Out of Phase | C# Phrygian, 80 | lead `circle` · chords `sine` · bass `triangle` · kit `beatty` (Drill) | Phase music: loops of 8, 5 and 7 steps slide apart and meet again every few bars. |
| 08 | Loop Pedal | C minor pentatonic, 120 | bass `polygon` · kit `bit` (House) · lead `kolakoski` · chords `triangle` | Every layer a short loop. A self-describing Kolakoski lead over a star-polygon bass; the kick goes four-on-the-floor at 2x. |
| 09 | Rewind | F minor, 120 | lead `triangle` · bass `sine` · kit `gray` (Reggaeton) · chords `saw` | Mirrors: the bass is note for note the same when its tape runs backwards (measured: 0 % of steps change). The triangle lead reversed is a variation of itself (73 % change), and the saw chords audibly turn around. |
| 10 | Heavy Rotation | A# Phrygian, 150 | kit `vertices` (Funk / disco) · bass `spirograph` · lead `rose` · chords `polygon` | Everything is a wheel: a spirograph bass on a three-beat turn, a rose-curve lead on six, a chord stab every third beat. |
| 11 | The Archivist | F# harmonic minor, 90 | bass `collatz` (s = 871) · kit `ca` Rule 90 (Drill) · lead `digits` · chords `primes` | A Collatz orbit that never settles, hats read off a cellular automaton, a lead reading out a digit stream. i–iv–iv, two bars each: one turn per 6-bar loop. |
| 12 | Master Tape | G major, 120 | lead `fibonacci` · chords `harmonograph` · bass `lucas` · kit `euclid` (Funk / disco) | Soft Open's lead and hats, same functions and parameters, in the full major scale at a faster tempo, over I–vi–iii–V. |
| — | Menu | G major pentatonic, 72 | pad `spiral` · line `cardioid` · bass `sine` · (kit `modgate`, not played) | A calm bed: cassettes 1–3 at half speed, no drums. `menu.json` → `bed.tracks` gives the `TrackAudioState` per cassette. |

Exact parameters are in each file's `music` block; `layers[]` gives each formula's equation and what
the layer is for in words.

## Data format

`data/music/<id>.json`:

| Field | Meaning |
|---|---|
| `music` | The `LevelMusicDef` block, exactly as the level JSON wants it: `root`, `scale`, `progression`, `chordBars`, four `tracks` (`role`, `formula`, `params`, `genre`). |
| `bpm` | Tempo the piece was composed and measured at. It equals the level file's bpm (the tools refuse otherwise). |
| `title`, `description`, `arc`, `key` | One-line description and place in the arc. |
| `layers[]` | Per cassette: role, formula name, equation, purpose. |
| `inLevel` | What a player can hear in the level as it stands (cassettes 1..`maxTapes`, the level's speeds), measured. |
| `stateMaps` | OPEN-22: generative-parameter changes for `dead`, `desynced`, `reversing`, `stopped`. Same in every file. |
| `sfx` | MUSIC-05 pitch policy per event class, the level's palette, UI pitches, and the OPEN-23 latency policy with milliseconds at this tempo. |
| `analysis` | The headline numbers below, per piece. |
| `bed` (menu only) | Which cassettes play, and at which speed. |

## State maps (OPEN-22)

A present cassette always has its layer sounding, independent of action sounds; an unrecorded cassette
is silent. States change the *generated notes*, not a filter on a finished stem (MUSIC-09). Each map is
a list of operations on named channel parameters (`stateMaps.paramGlossary` maps each name to the
engine field). Maps are applied in the order dead, desynced, reversing, stopped.

| State | What changes | By how much | How fast |
|---|---|---|---|
| **dead** | The layer thins to its skeleton and falls onto chord tones. Pitched: gate pulses halved, palette chord-tones-only, gravity 1, formula cycle quartered, triads instead of sevenths, velocity ×0.65. Kit: perc lane dropped, backbeat becomes a rim, density ×0.5, hat threshold ≥ 0.8. | Onsets fall to 51–69 % of alive (mean 58 %); 100 % chord tones. | Immediately, at the first step after the death. No recovery in this run (a new run that keeps the self alive restores it). |
| **desynced** | The contour slips ahead of the rhythm: phase +4 steps, contour blend +0.45, accent ×0.85, notes up to 0.18 of a step late; kit: hat and perc lanes only. The gate is untouched, so rhythm and key hold. All scaled by the drift level 0..1. | At full drift 58–86 % of steps play a different pitch; 100 % in scale. | Drift rises 0.25 per bar (full in the fourth bar) and falls 0.5 per bar after resync: exactly on the baseline within two bars. A dead self never drifts. |
| **reversing** | The contour is read backwards (retrograde). Gate, chord clock and tempo unchanged. | 45–87 % of steps change per piece. Per layer it runs from 0 % (Rewind's mirror bass, and three sparse leads) to 100 % (`probe.ts` prints it). | Immediately at the next step, both ways. |
| **stopped** | A hold figure: one sustained chord tone per layer (bass: the chord root), a single soft kick heartbeat. Tape speed ignored. | 5–6 onsets per bar from all four layers together. | Immediately at the next step, both ways. |

The default maps reproduce the prototype's `director.ts` note for note
(`verify-statemaps.ts`: 13 pieces, 3 744 layer variants, 226 866 notes, 0 mismatches). The Godot audio
director can therefore either keep its port of `director.ts` or read these tables: the notes are the
same. If the tables are edited later, `lib.mapNotes` is the reference implementation.

## SFX pitch policy (MUSIC-05) and latency (OPEN-23)

Each event class plays one to seven tones, in order. A tone is either an index into the triad of the
chord in force at the cue's grid line (0 root, 1 third, 2 fifth, 3 root an octave up…) or a 0-based
degree of the level scale, in a MIDI octave. `perTape` adds the acting cassette's index, so four
selves doing the same thing spell the chord instead of doubling a note. `off` replaces `tones` for
closing events, `heavy` for power ≥ 6.

| Group | Classes | Tones |
|---|---|---|
| movement | step, dodge | step: root, low; dodge: third, high. Per tape. |
| attack | swingLight, swingHeavy, fire | fifth; low root; root then fifth. Per tape. |
| impact | hit, projectileHit, clang, kill, break | hit: root + fifth (heavy: fifth + upper third); kill: the triad rising; break: root in two low octaves. |
| mechanism | interact, door, plate, laser, core, objective | on: third → fifth, off: fifth → third; door: root → fifth, low; core and objective: the triad rising to the octave. |
| tape | selfDeath, desync, resync, tapeWrap, tapeTurn, tapeEnd | selfDeath: fifth → third → root, falling; resync: root → octave. |
| enemy | enemyTelegraph, enemyAttack, enemyShot, enemyStagger, bossPhase, bossRecall | low register; telegraph root → third, attack on the low root. |

Five palettes recolour the same table down the descent (`sfx.palette`):

- **warm** (01–04, menu): the default table. Thirds and full triads: every action a small chime.
- **hollow** (05–07): thirds drop out of hits, shots and kills (root and fifth only), so the mode stays
  ambiguous. Mechanisms keep their thirds so puzzles still read as friendly.
- **neon** (08–10): impacts an octave down as power dyads; high blips stay above the lead.
- **boss** (11): enemy telegraphs sound the raised seventh of the key and attacks land on the key root,
  so every enemy attack is a small cadence the player hears coming.
- **resolved** (12): the warm table, kills and the objective opened up by an octave.

UI blips and the count-in use scale degrees of the key in force (`sfx.ui`).

Checked by `sfxcheck.ts` for every class, cassette and chord of every progression: 100 % of tones in
scale in all 13 pieces; 100 % chord tones in 12. In The Archivist 4.8 % are deliberately not chord
tones (the leading-tone telegraph, `enemyTelegraph` / `bossPhase` / `bossRecall`).

Latency policy (`sfx.latency`):

- Only the **audible accent** is moved, never the simulation event, and only later: to the next grid
  line at or after the event. Player inputs are not quantised (MUSIC-07).
- Grid: the sixteenth. Worst-case lateness is one grid step (100 ms at 150 bpm, 188 ms at 80 bpm).
- Impact classes also fire an immediate soft transient (30 % gain, first pitch) at the event whenever
  the accent is more than 12 ms away, so a hit never feels late.
- **Proposal beyond the prototype:** impact classes use the 32nd grid when a sixteenth is longer than
  130 ms (below 116 bpm). This keeps a hit's accent within about 100 ms. Not built anywhere yet.
- Merge rule: same class on the same grid line is one cue; at most 8 cues per line, by priority.

## Analysis method

All tools run the prototype's `MusicDirector` and the vendored Harmonograph engine from Node
(`cd prototype && npx vite-node ../art/music/<tool>.ts`), so they measure the notes the game plays.
Sixteen master bars per stream.

| Tool | What it does |
|---|---|
| `analyze.ts` | The whole matrix per piece (below). `-- --drafts` measures the first-pass drafts; `-- --only 07 --verbose` prints one piece in detail. |
| `levelcheck-run.ts` | Only what the level as it stands can sound: every subset of cassettes 1..`maxTapes` at every allowed speed. Fails if a piece's bpm differs from its level file. |
| `scenario.ts` | A scripted attempt through the game's `LayerSequencer`: cassettes join one by one at 1x, 2x, 0.5x and 4x, one desyncs and resyncs, one dies, one reverses, all stop. |
| `verify-statemaps.ts` | State-map data against the prototype, note for note. |
| `probe.ts`, `explore.ts` | Per-layer change under reversal; the search that found Rewind's mirror bass. |
| `tune.ts` | The iteration: coordinate descent over progression, formula, formula parameters and layer shaping, inside the shortlists in `pieces.ts`. Deterministic. About 30 s per piece. |
| `compose.ts` | Writes `data/music/*.json` from `pieces.ts` + `tuned.json` + `statemaps.ts`. |
| `merge.py` | The merge step (below). |

What `analyze.ts` measures:

- **In scale.** Every pitched note of every layer at 0.5, 1, 2 and 4x, alive, dead, at four drift
  levels, reversing, stopped, and three combined states.
- **Vertical consonance.** On every downbeat and every beat, all cross-layer pairs of sounding
  pitches, for all 81 speed combinations of 0.5/1/2x and the 175 combinations containing a 4x layer.
  "Harsh" is a minor second, a minor ninth, or a tritone within an octave and a half. Because the
  worst single layer pair is also reported, the result bounds every subset of layers. Also the share
  of downbeat notes that are tones of the active seventh chord, and an interval-class histogram.
- **Rhythmic alignment.** Share of step onsets on the master sixteenth grid (0.5/1/2x) and the 32nd
  grid (including 4x). Swing and chord strum are reported separately, not counted as misalignment.
- **Density.** Onsets per bar for each layer and speed, and for the full mix. Bounds: a pitched layer
  0.5–16 per bar (24 at 4x), a kit 2–32 (48 at 4x), no gap longer than two bars.
- **Register.** Share of moments when two pitched layers both sound below 150 Hz; share of moments the
  lead is at or above the chord's top note.
- **Melodic contour.** Step, skip and leap shares in scale degrees, largest leap, range, distinct
  pitches, distinct bar shapes in eight bars.
- **States.** Dead-to-alive onset ratio and chord-tone share; share of steps changed by full drift and
  by reverse; in-scale share of each.
- **Score.** One number, 100 minus weighted penalties (`lib.scoreReport`). The weights are the
  composer's judgement, fixed before tuning so before and after are comparable.

## Results

Before = first-pass drafts written from the level ideas with engine defaults. After = `data/music`.
hDn = mean share of harsh cross-layer pairs on downbeats over the 81 combinations; worst = the worst
of the 81.

| Piece | Score before → after | hDn % before → after | Worst of 81 % | 16th grid % | Mix onsets/bar | Mud % before → after | Lead above chords % | Dead ratio | Drift changed % | Flags after |
|---|---|---|---|---|---|---|---|---|---|---|
| 01 Soft Open | 62.2 → 97.6 | 0.0 → 0.0 | 0.0 | 92 | 10–42 | 7.7 → 0.0 | 79 → 94 | 0.58 | 76 | – |
| 02 Hit Harder | 12.5 → 89.2 | 6.3 → 0.3 | 1.0 | 87 | 10–44 | 0.0 → 0.0 | 17 → 88 | 0.61 | 74 | – |
| 03 Hold the Door | 21.4 → 92.0 | 3.1 → 2.6 | 3.8 | 87 | 7–35 | 0.0 → 0.0 | 22 → 92 | 0.58 | 84 | – |
| 04 Second Opinion | 31.3 → 92.0 | 1.9 → 0.0 | 0.0 | 89 | 9–43 | 0.0 → 0.0 | 81 → 86 | 0.58 | 68 | – |
| 05 Dead Air | 52.9 → 94.6 | 0.3 → 0.0 | 0.0 | 85 | 8–37 | 0.0 → 0.0 | 38 → 95 | 0.57 | 81 | – |
| 06 Crossfire | 55.6 → 94.5 | 2.1 → 0.0 | 0.0 | 90 | 11–50 | 0.0 → 0.0 | 96 → 100 | 0.69 | 86 | kit at 4x: 61 hits in a bar |
| 07 Out of Phase | 71.7 → 98.0 | 1.8 → 0.0 | 0.0 | 93 | 7–33 | 0.0 → 0.0 | 92 → 90 | 0.51 | 79 | – |
| 08 Loop Pedal | 65.2 → 99.3 | 0.0 → 0.0 | 0.0 | 100 | 9–42 | 0.0 → 0.0 | 60 → 87 | 0.58 | 58 | – |
| 09 Rewind | 14.4 → 98.0 | 6.9 → 0.0 | 0.0 | 100 | 9–43 | 0.0 → 0.0 | 92 → 91 | 0.58 | 73 | – |
| 10 Heavy Rotation | 5.0 → 100.0 | 1.7 → 0.0 | 0.0 | 100 | 8–42 | 0.0 → 0.0 | 37 → 100 | 0.60 | 76 | – |
| 11 The Archivist | 33.0 → 90.2 | 0.9 → 0.6 | 1.4 | 94 | 8–38 | 0.0 → 0.0 | 16 → 95 | 0.51 | 73 | – |
| 12 Master Tape | 36.6 → 87.8 | 3.1 → 2.1 | 2.1 | 100 | 8–38 | 1.5 → 0.0 | 76 → 94 | 0.53 | 66 | – |
| Menu | 88.3 → 100.0 | 0.0 → 0.0 | 0.0 | 100 | 4–20 | 8.1 → 0.0 | 86 → 91 | 0.60 | 63 | – |
| **Mean** | **42.3 → 94.9** | **2.2 → 0.4** | **3.8 (was 11.5)** | | | | | | | 1 flag (was 20) |

- In scale: 100 % of 92 763 notes, in every piece, speed and state (also 100 % before: the engine
  quantises to the scale, so this is a guard, not an achievement).
- Chord tones on downbeats: 99–100 % in every piece.
- Onsets off the sixteenth grid are swing-free steps of slow layers at 0.5x and 16th-note kits at 2x
  (which land on the 32nd grid). Every step length is a power-of-two fraction of a beat by
  construction, so layers at different speeds always share a grid.
- Scripted attempt (`scenario.ts`): all 13 pieces 100 % in key through join, desync, resync, death,
  reverse and stop; worst downbeat harshness 1.6 % (03 and 11).
- As the levels stand (`levelcheck-run.ts`): levels 01–10 have 0.0 % harsh downbeats in every audible
  subset and speed combination. 11: mean 0.9 %, worst single combination 6.3 % (lead at 4x with chords
  at 0.5x). 12: mean 1.9 %, worst 6.3 % (lead and chords both at 0.5x).

### What is not clean, and why

- **03, 11 and 12 keep a small residue of harsh downbeats (0.6–2.6 %).** The cause is the same in all
  three: the chord layer always voices sevenths, and the tonic seventh chord of Lydian, major and
  harmonic minor contains a semitone against its own root (B–C, F#–G, E#–F#). When another layer
  holds the root on the downbeat it rubs. In 11 this is the sound of the mode and is wanted; in 12 it
  is a major seventh under the tune, usually heard as warm rather than wrong, but the metric counts
  it. Removing it needs a chord layer that can play triads (see the optional hook below).
- **06 kit at 4x** reaches 61 hits in one bar (bound 48). The level as it stands allows 0.5/1/2x only,
  so it cannot be heard today. If 06 ever gains 4x, set the kit's `rate` to 0.5.
- **Two melodies have few distinct bar shapes** (02: 2 of 8, 03: 3 of 8). They are sparse three-note
  stabs by design, and neither is audible in its level as it stands (cassette 3 of 1 and of 2).
- **04's lead leaps on 36 % of intervals** at 1x: that is the infinity series, kept.
- The score's weights are judgement. A different composer would weight differently.

## Integration

1. **Merge.** Copy each piece's `music` object over the `music` object of the level file with the
   same name. Nothing else in the level file changes.

   ```
   python -I art/music/merge.py            # dry run
   python -I art/music/merge.py --write    # replaces only the top-level "music" object, as text
   ```

   The script checks that every other field of the level is unchanged after the edit and refuses a
   level whose bpm differs from the piece's. At the time of writing all twelve level files exist and
   all twelve would merge.

2. **Cassette order changes with the merge.** Most level drafts put the kit on cassette 1; the pieces
   do not (see the table above). Any level text, hint or story line that names what a cassette plays
   ("your drum track") should be read against the new order. Level solutions are unaffected: music
   does not touch the simulation.

3. **If a level designer changes a level's bpm**, the piece must follow: change `bpm` in
   `art/music/pieces.ts`, then `tune.ts -- <id>`, `compose.ts`, `analyze.ts`. `compose.ts` refuses to
   write while the two disagree. Changes to `bars`, `maxTapes` or `speeds` need only `compose.ts`
   (it refreshes `inLevel`). Level 11's progression is three chords of two bars to fit its 6-bar loop;
   if that loop length changes, give it new candidates in `pieces.ts`.

4. **Menu.** Start the director with `menu.json` → `music` at `bpm` 72 and the `bed.tracks` states
   (cassettes 1–3 present at 0.5x, cassette 4 absent).

5. **State maps.** Nothing to do if the Godot director is a faithful port of `director.ts`. To make
   the behaviour data-driven, apply `stateMaps` as in `art/music/lib.ts` → `mapBar`.

6. **SFX.** The audio engineer reads `sfx.classes` (already merged with the level's palette) and
   `sfx.ui` instead of a hard-coded recipe table; `sfx.pitchRule` states the lookup. The palette is the
   only per-level difference. `sfx.latency` holds the grid in milliseconds at the level's tempo.

7. **Optional hook, not required:** a per-track layer parameter `extension` (0 = triads, 1 = sevenths,
   default 1) in the director's chord role. With it, 03 and 12 could be made fully clean. The
   prototype director hard-codes sevenths, so the pieces do not use it.

## Reproducing

```
cd prototype
npx vite-node ../art/music/analyze.ts -- --drafts     # before
npx vite-node ../art/music/analyze.ts                 # after
npx vite-node ../art/music/levelcheck-run.ts
npx vite-node ../art/music/scenario.ts
npx vite-node ../art/music/verify-statemaps.ts
```

Each takes a few seconds. `tune.ts` (all 13 pieces) takes about seven minutes and rewrites
`art/music/tuned.json`; run `compose.ts` after it.
