# 02 — Hit Harder

Upper ruins, 100 bpm, G Mixolydian (rock groove, rising saw melody). One cassette, speeds 1x and
2x, stop. 8 bars. The creator's Scenario K: a momentum threshold, before any overdubbing.
Files: `data/levels/02-hit-harder.json`, `data/levels/solutions/02-hit-harder.json`.

## The idea

momentum = swing x tape speed x (1 + run-up). The level isolates the two factors one after the
other on a single straight line running north from the start, marked by an inscribed floor strip:

```
#.....o.....#   amp (core): the objective
######%######   wall2, needs 4.0: only a 2x heavy WITH a run-up (5.4); a standing 2x heavy is 3.6
#........G..#   g1, asleep until wall1 breaks
######%######   wall1, needs 3.2: nothing at 1x (best is 2.7); a standing 2x heavy is 3.6
#.....@.....#   start, facing the wall
```

Wall 1 teaches tape speed (no swing at 1x can do it). Wall 2 teaches movement (at the right speed,
standing still is still not enough). Every failed hit is reported by the game with both numbers
("hit breakable wall wall2 with momentum 3.6; it needs 4.0"), so each clang says how far off it was.

## Intended solution (one 2x take, wins at beat 6.8; the tape covers 16 of the 32 beats)

| Beat | Tape A at 2x |
|---|---|
| 0–0.8 | Walk up to wall 1, heavy: 3.6, it breaks. g1 wakes. |
| 1.2–4.3 | Hold; g1 walks through the hole into a light swing (2x light = 2, dead). |
| 4.5–5.9 | Back off down the strip, run north through the hole, heavy while running: 5.4, wall 2 breaks. |
| 6.2–6.8 | Light on the amp. Objective complete; nothing is left alive to bother the idle self. |

## Naive plans, run with the tools

| Plan | Result |
|---|---|
| 1x tape, everything including a running heavy | FAIL — wall1 clangs: 2.7, 1.8, 1.0 against 3.2. Lesson: change the tape, not the swing. |
| 2x, standing heavies at both walls | FAIL — wall1 breaks, wall2 clangs twice at 3.6 against 4.0. Lesson: speed is not all of it. |
| 2x, running LIGHT swings | FAIL — 3.0 against 3.2 and against 4.0. Lesson: heavy and running, both. |
| 2x, sprint through both walls, wake the amp, ignore the grunt | FAIL (nobody survived) — objective complete at 3.1, then "Tape A died at beat 6: struck by grunt g1". Lesson for 03: the world keeps running after you are done. |

## Alternatives that win

- One sprint: running heavy through wall 1, straight on into a running heavy at wall 2, the amp,
  then turn and cut down the grunt as it catches up (objective at beat 3.1, grunt dead at 4.7).
- A run-up of 0.7 tiles inside the middle room is enough (top speed comes in 7 ticks), so a player
  who never goes back through the hole still gets there (wins at 6.6).

## Teaches for later

Tape speed as a choice made at the deck, heavy swings, run-up, reading a threshold off a clang, and
a first taste of "a take is longer than what I did in it". Levels 03+ add the cost of 2x (a short
tape); here it is deliberately free.

## Numbers relied on (`level.ts probe 02`)

Momentum: 1x light 1 / running 1.5, heavy 1.8 / running 2.7; 2x light 2 / 3, heavy 3.6 / 5.4.
The approach factor is clamped at 1, so a dodge cannot push a 1x swing past 2.7. Thresholds 3.2 and
4.0 sit at least 0.2 away from every reachable value (never on an exact one such as 3.0). A heavy
lands 16 ticks after the press and takes its momentum from the press. `mutate`: all 12 win.

Wall 2 was 4.5 until a player equipped level 1's Stylus Shiv (heavy impact 1.4) and could not
pass: its best swing here is a running 2x heavy at 4.2, so 4.5 was out of reach. At 4.0 the Shiv
still needs a run-up at both walls (standing 2x heavy 2.8; wall 1 at 3.2 also needs it), and the
baseline lesson is unchanged. `level.ts probe 02 --loadout stylus_shiv` shows both walls reachable.

## Presentation must-haves (Godot)

- Flow is south to north so Moxie hits the camera-facing (south) faces of both walls. The row
  directly north of each wall is in its shadow: nothing important stands there (g1 is two rows up,
  the amp sits against the far wall).
- The two cracked walls must read as the same kind of thing at different toughness (wall 2 visibly
  thicker), and clearly different from the plain wall around them.
- A clang should show both numbers at the wall, not only in the outcome notes.
- The inscribed strip is the run-up cue; graffiti "x2" beside wall 1 and "RUN IT" beside wall 2 are
  the diegetic hints. The speed dial on the deck must be discoverable before the count-in.
