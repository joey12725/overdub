# OVERDUB levels

Levels are plain JSON. The TypeScript prototype (where you iterate: a run takes two seconds) and
the Godot game (what ships) load the very same files.

```
data/levels/<NN>-<slug>.json             a campaign level       e.g. 03-crossfire.json
data/levels/solutions/<NN>-<slug>.json   your solution for it   (format: solutions/README.md)
data/levels/sandbox.json                 the practice room: not on the campaign path
data/levels/index.json                   the list the Godot build loads (written by a tool)
```

## How to author a level in ten minutes

Every command runs from `prototype/`. `<level>` can be the campaign number (`07`), the file name
with or without `.json`, or a path.

```
cd prototype
```

**1. Look at a working example (1 min).**

```
npx vite-node scripts/level.ts show sandbox
npx vite-node scripts/level.ts run sandbox
```

`show` draws the room and lists every entity with its coordinates. `run` plays the sandbox's
solution (`data/levels/solutions/sandbox.json`) and tells you, beat by beat, what happened.

**2. Write the level file (3 min).** Copy this to `data/levels/07-two-hands.json` and change it.
The file name is `<two-digit campaign index>-<slug>.json`; `"index"` must be that number and `"id"`
must be the file name without `.json`.

```json
{
  "id": "07-two-hands",
  "index": 7,
  "name": "Two Hands",
  "tagline": "One of you holds the door. The other walks through it.",
  "theme": "upper",
  "bpm": 120,
  "bars": 4,
  "horizonBars": 8,
  "maxTapes": 2,
  "speeds": [1, 2],
  "endModes": ["stop"],
  "map": [
    "###########",
    "#....#....#",
    "#....#....#",
    "#.........#",
    "#....#....#",
    "#....#....#",
    "###########"
  ],
  "start": { "x": 2.5, "y": 3.5 },
  "startFacing": 0,
  "entities": [
    { "kind": "plate", "id": "pad", "c": 1, "r": 5 },
    { "kind": "door", "id": "gate", "cells": [{ "c": 5, "r": 3 }], "openWhen": { "sig": "pad" } },
    { "kind": "core", "id": "amp", "x": 8.5, "y": 5.5, "threshold": 3 }
  ],
  "objective": { "type": "activate", "text": "Wake the amp" },
  "music": {
    "root": 9,
    "scale": "Dorian",
    "progression": [0, 3, 0, 4],
    "tracks": [
      { "role": "bass", "formula": "fibonacci" },
      { "role": "drums", "formula": "groove" },
      { "role": "melody", "formula": "lissajous" },
      { "role": "chord", "formula": "voicelead" }
    ]
  },
  "loot": [],
  "briefing": ["The plate opens the gate only while someone stands on it."]
}
```

**3. Check it and look at it (1 min).**

```
npx vite-node scripts/level.ts validate 07
npx vite-node scripts/level.ts show 07
```

```
             1
   01234567890
0  ###########  0
1  #....#....#  1
2  #....#....#  2
3  #.@..+....#  3
4  #....#....#  4
5  #p...#..o.#  5
6  ###########  6

@  start at (2.50, 3.50), facing 0° E (every tape starts here at beat 0)
p  plate "pad" on tile (1,5)
+  door "gate" on tile (5,3): open while pad
o  core "amp" at (8.50, 5.50): needs momentum 3
```

**4. Ask the numbers before you guess (1 min).** How far can a self run in two beats at 2x? Does a
standing heavy at 2x reach momentum 3?

```
npx vite-node scripts/level.ts probe 07 --beats 2 --speed 2
```

`probe` answers from the running code and, given a level, tells you which swings break its
breakables and light its cores (`core "amp" needs momentum 3: 2x light running, 2x heavy standing,
2x heavy running`).

**5. Write the solution (2 min).** `data/levels/solutions/07-two-hands.json` — one short plan per
take. The whole language is in `solutions/README.md`.

```json
{
  "version": 1,
  "level": "07-two-hands",
  "takes": [
    {
      "speed": 1,
      "endMode": "stop",
      "note": "A stands on the plate for the whole run, which holds the gate open.",
      "plan": [
        { "goto": [1.5, 5.5] }
      ]
    },
    {
      "speed": 2,
      "endMode": "stop",
      "note": "B waits for the gate, runs through and wakes the amp with a 2x heavy.",
      "plan": [
        { "goto": [4.4, 3.5] },
        { "waitFor": { "on": "gate" } },
        { "goto": [7.6, 4.7] },
        { "press": "heavy", "aim": "amp" }
      ]
    }
  ]
}
```

**6. Run it, look inside it, fix it (2 min).**

```
npx vite-node scripts/level.ts run 07                    the report; --upto 1 stops after take 1
npx vite-node scripts/level.ts ascii-at 07 --beat 2      the room at master beat 2
npx vite-node scripts/level.ts run 07 --trace B          where B is on every beat
```

`run` prints, per take, each plan step with the tick and beat it started and finished on, then the
events of the combined run (`B swings heavy toward 42° SE (momentum 3.60)`, `B LIGHTS core amp`),
then the outcome with the game's own explanation. Warnings at the bottom tell you about a step
that came too late, a press that was dropped, or a step the take never reached.

**7. Prove it is robust, then store it.**

```
npx vite-node scripts/level.ts mutate 07                 must say every variant wins
npx vite-node scripts/level.ts run 07 --write            stores inputs, tapes, expected outcome
npx vitest run tests/levels                              what the build checks for every level
```

`--write` records the performance into the solution file (each take's `inputs`, `expect`, and the
`generated` section). Re-run it whenever you change the level or the plan: the test suite fails on
a stale solution and tells you so. When your level is ready for the Godot build,
`npx vite-node scripts/level.ts index --write` adds it to `index.json`, and
`bash tools/gd script res://tools/bot.gd -- 07-two-hands` (from the repo root) replays your stored
inputs in Godot.

## Rules of the format

A level file is one `LevelDef` (authoritative definition and comments:
`prototype/src/core/types.ts`; traps: `docs/TRAPS.md`). `validate` checks all of it.

| Field | Meaning |
|---|---|
| `id` | The file name without `.json` (`"07-two-hands"`). The Godot loader opens `<id>.json`, so they must match. |
| `index` | Position on the campaign path, 1-based; equals the file's two-digit prefix. The campaign runs 1, 2, 3 … without gaps (index 0 is the sandbox, which is not on the path). |
| `name`, `tagline` | Shown on the campaign path. |
| `theme` | `upper`, `mid`, `lower` or `core` (look of the room). |
| `bpm` | Master tempo. `3600 / bpm` must be a whole number (60, 72, 75, 80, 90, 100, 120, 144, 150, 180 …) so a beat is a whole number of ticks. |
| `bars` | Length of one recording in bars of 4 beats. The same real time at every tape speed. |
| `horizonBars` | Length of the whole encounter on the master clock, in bars. The run is judged when it ends. Default choice: `bars / slowest speed`. |
| `maxTapes` | 1 to 4 cassettes. |
| `speeds` | Any of `0.5, 1, 2, 4`. A tape at speed `s` covers `bars / s` master bars and hits `s` times as hard. |
| `endModes` | Any of `stop`, `repeat`, `reverse`: what a tape does when it runs out before the horizon. |
| `map` | Rows of equal length, one character per tile (below). |
| `start`, `startFacing` | Where every tape starts at beat 0 (`x`, `y` in tiles) and the facing in radians. |
| `entities` | Everything dynamic (below). |
| `objective` | `{ "type", "text", "targets"?, "when"? }` — `eliminate` (all enemies, or `targets`), `reach` (an alive, synced self inside an exit when the horizon ends), `activate` (all cores, or `targets`), `boss`, `signal` (`when` becomes true once). |
| `music` | `root` 0–11, `scale`, `progression` (scale degrees 0–6), optional `chordBars`, exactly four `tracks` (`role` `bass`/`drums`/`melody`/`chord`, `formula`, optional `params`, `genre`). |
| `loot` | Gear ids (`data/gear.json`) awarded on the first clear. |
| `briefing` | At least one line. `hints` (optional) is keyed by tape number `"1"`–`"4"`. |

A run **wins** when the objective is complete **and** at least one self is alive when the horizon
ends. A level may be won with fewer tapes than it offers.

### Coordinates and time

- Tile `(c, r)` is column `c`, row `r`; row 0 is the first string of `map`. It covers world
  `x` in `[c, c+1)` and `y` in `[r, r+1)`, so the centre of tile (3, 5) is `(3.5, 5.5)`. **y grows
  down the map.**
- Angles are radians in the level file (`0` = east / +x, `π/2` = south / down the map). The plan
  language of solutions uses degrees and compass names instead.
- Master beats count from 0. A local tick is 1/60 s of a tape's own time; at 120 bpm a beat is 30
  ticks. A tape at speed `s` advances `s` local beats per master beat. `show` prints the table for
  your level.

### Map characters

```
#  wall          .  floor         (space)  void: no floor, impassable
=  low barrier: blocks walking, not shots or line of sight
:  metal grate   ,  overgrown     ~  inscribed floor      (all three are ordinary floor)
```

The walkable area must be closed in by walls or void; the start and every enemy, switch, plate,
core and exit must be reachable from it (doors and breakables count as passable for this check).

### Entities

Every entity except decor has an `id`, unique in the level. Ids of switches, plates, breakables,
cores, exits and traps are also **signals** that expressions can read.

| `kind` | Fields | Notes |
|---|---|---|
| `enemy` | `id`, `type`, `x`, `y`, `facing`?, `hp`?, `beat`? `{every, offset}`, `arc`? (turret), `wakeWhen`? | Types: `grunt`, `stalker`, `turret`, `shielder`, `brute`, `drone`, `boss`. Numbers: `level.ts probe`. One enemy hit kills a self. |
| `door` | `id`, `cells` `[{c, r}]`, `openWhen` | Solid while closed. A recorded self whose path it blocks **desyncs**. |
| `switch` | `id`, `x`, `y`, `initial`? | An `interact` within 1.2 tiles toggles it. Occupies its tile. |
| `plate` | `id`, `c`, `r`, `heavy`? | On while an alive, synced self or an enemy stands on it. |
| `breakable` | `id`, `c`, `r`, `threshold` | Solid until one melee hit of at least `threshold` momentum. |
| `laser` | `id`, `from`, `to` `{x, y}`, `onWhen` | Kills selves that touch it while on. |
| `core` | `id`, `x`, `y`, `threshold`? | Lit by one melee hit of at least `threshold` momentum (default 1). |
| `exit` | `id`, `c`, `r`, `w`, `h` | On while an alive, synced self stands inside. |
| `decor` | `type`, `x`, `y`, `rot`?, `variant`? | Visual only. |
| `spikes`, `crusher`, `conveyor`, `flame`, `dart`, `bumper`, `sensor`, `relay`, `magnet` | see `docs/TRAPS.md` | Traps and machinery. |

Enemies, doors, switches, breakables and cores each need a tile of their own.

### Signal expressions

`openWhen`, `onWhen`, `wakeWhen`, the objective's `when` and every trap driver take one of:

```json
{ "sig": "pad" }                                   a signal id; "dead:<enemy id>" is true from the update after that enemy died
{ "not": { "sig": "pad" } }
{ "and": [ … ] }     { "or": [ … ] }     { "xor": [ a, b ] }
{ "const": true }
{ "beat": { "every": 4, "from": 2, "to": 3 } }      true while (master beat mod 4) is in [2, 3)
```

## The tools

```
cd prototype && npx vite-node scripts/level.ts <command> <level> [options]

validate <level|all>      check the level, its file name and its solution's structure
show <level>              ASCII map, entities, objective, cassettes, timing        (--raw)
run <level>               compile and play the solution, report beat by beat
                          (--write, --upto N, --trace A, --every K, --full, --verbose, --loadout a,b)
ascii-at <level> --beat N the room at a beat of the combined run   (--to M --every K, --upto N, --stored)
probe [level]             run distances, swing momentum, action timings, enemy stats
                          (--beats N, --speed S, --loadout a,b)
mutate <level>            does the solution survive ±1/±2 ticks and nudged positions?   (--quick)
index                     the campaign in order; --write refreshes index.json for Godot
help                      every option, in full
```

Symbols used by `show` and `ascii-at`:

```
#  wall      .  floor     (space) void    =  low barrier       @  start (show only)
A B C D  a self, alive and synced     a b c d  that self dead     ?  desynced     !  its spark
G grunt  K stalker  T turret  H shielder  R brute  N drone  X boss     x  dead enemy     *  projectile
+  door closed   :  door open      s / S  switch off / on      p / P  plate up / pressed
%  breakable     ,  broken         o / O  core idle / lit      e / E  exit / exit held
~  laser firing (not drawn while off)
w / W  spikes down / raised    m / M  crusher retracted / extended    > < v ^  conveyor    - |  stopped
f / F  flame nozzle    &  flame jet    j / J  dart launcher    u / U  bumper    ;  sensor beam    q / Q  magnet
```

One character per tile, highest priority wins (a self hides the plate it stands on); the table
under the map always lists everything with exact positions and states.

## What the build checks (`prototype/tests/levels/campaign.test.ts`)

For every `data/levels/<NN>-<slug>.json`:

1. the level validates, and its file name, `id` and `index` agree;
2. `solutions/<same name>` exists, is well formed, wears the baseline loadout and was compiled
   against the current level and plan;
3. replaying the stored inputs through the real game session with the baseline loadout wins and
   reproduces the stored tapes bit for bit (APP-TEST-03);
4. resolving the stored tapes alone gives the same outcome and event timeline;
5. the plan still wins with every take one local tick late or early.

Campaign indices must run 1, 2, 3 … (the file prefixes) with no gap or duplicate; the sandbox is
index 0 and stays off the path. The same checks run on the sandbox's worked example.

The Godot build proves the same campaign in the shipped game (`tests/levels/test_campaign.gd`, run
with `bash tools/gd test levels`): every level listed in `index.json` loads through `ContentData` /
`CampaignData` and validates (typed and raw JSON); its stored inputs, replayed through the real
`GameSession` by the shipped bot (`GameBot`) with the baseline loadout, win with the stored takes,
outcome and survivors, and record tapes within float32 rounding of the prototype's (the two engines'
`atan2`/`sin` may differ in the last bit); its stored tapes, resolved by `ODResolve.resolve_encounter`,
give the same outcome and event timeline; loot names real gear, each found item is found once; and the
level's `music` block is the composer's (`data/music/<id>.json`). A level that passes here in the
prototype but fails in Godot means the two engines disagree: fix the rule in `core/` and add a golden
(`prototype/scripts/export-goldens.ts`), or re-author the solution with margin (`level.ts mutate`).

## How levels reach the game

- **Prototype:** `prototype/src/content/levelFiles.ts` loads every `<NN>-<slug>.json` at build time
  and `LEVELS` (the content module) is that list in `index` order. `sandbox.json` has no number, so
  it is never on the path; it is still exported as `SANDBOX`, and it stands in as the only level
  until the first campaign file exists.
- **Godot:** `content/data.gd` loads the ids listed in `data/levels/index.json` and opens
  `<id>.json` for each. `level.ts index --write` rewrites that list from the files present.
- Do not hand-edit `sandbox.json`: it is exported from `prototype/src/content/levels/sandbox.ts` by
  `prototype/scripts/export-data.ts`.
