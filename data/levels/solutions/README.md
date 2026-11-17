# Level solutions

`data/levels/solutions/<NN>-<slug>.json` is the designer's intended solution of
`data/levels/<NN>-<slug>.json`. It has two parts:

- what **you write**: the takes, each a short **plan** of timed steps;
- what **the tools write**: each take's recorded `inputs`, the `expect` block and the `generated`
  section — the exact performance that plan produced and the outcome it must give — so the Godot
  build can replay the identical performance without understanding plans at all.

One file serves both engines: it is also a plan file of the Godot bot (`game/bot.gd`), which reads
`version`, `level`, `loadout`, `expect` and each take's `speed`, `endMode` and `inputs`, and ignores
the rest.

```json
{
  "version": 1,
  "level": "07-two-hands",
  "loadout": { "melee": "reel_lash" },
  "expect": { "win": true, "takes": 1 },
  "takes": [
    {
      "speed": 2,
      "endMode": "stop",
      "note": "B waits for the gate, runs through and wakes the amp with a 2x heavy.",
      "plan": [
        { "goto": [4.4, 3.5] },
        { "waitFor": { "on": "gate" } },
        { "goto": [7.6, 4.7] },
        { "press": "heavy", "aim": "amp" }
      ],
      "inputs": [ "… written by the tools …" ]
    }
  ],
  "generated": { "…": "written by the tools" }
}
```

| Field | Written by | Meaning |
|---|---|---|
| `version` | you or the tools | `1`. The Godot bot refuses a file without it; `--write` always puts it in. |
| `level` | you | The level's `id` (the level file name without `.json`). |
| `loadout` | you, optional | Gear worn **instead of** the baseline, by slot: `{ "melee": "reel_lash" }` (slots: `helmet`, `top`, `pants`, `shoes`, `melee`, `ranged`; ids from `data/gear.json`). A plain list of gear ids (`["reel_lash"]`) is accepted too and rewritten by slot on `--write`. Omit it for the baseline. Campaign solutions must use the baseline (every mandatory level is beatable with it; the test suite enforces this), so this is for experiments and off-path files. |
| `takes` | you | One entry per cassette, in order: take 1 records tape A, take 2 tape B … Each take is recorded while the earlier ones play back, exactly as in the game. At most `maxTapes`, and no take the run never reaches: a plan that already wins after take 2 must not list a take 3. |
| `takes[].speed` | you | `0.5`, `1`, `2` or `4`; must be offered by the level. |
| `takes[].endMode` | you | `stop`, `repeat` or `reverse`; must be offered by the level. |
| `takes[].note` | you | What this take is for, in a sentence. Required: the next designer reads it. |
| `takes[].plan` | you | The steps (below). An empty plan stands still for the whole take. |
| `takes[].inputs` | tools | The input of every local tick of that take (last section). |
| `expect` | tools | `{ "win": true, "takes": N }`: what the Godot bot checks after replaying. |
| `generated` | tools | Tapes, expected outcome, event timeline, fingerprints (last section). |

Anything the tools write is replaced on the next `--write`; never edit it by hand. A take that
has `steps` / `reflex` instead of `plan` is the Godot bot's own closed-loop format (see
`game/bot.gd`); the level tools do not compile those.

Worked example to copy: `sandbox.json` in this folder.

## The plan language

A plan is a list of steps. The compiler turns it into one controller input per local tick by
**closed-loop steering**: every tick it looks at where the self really is and steers from there, so
a plan says where to go and what to do, never which stick angle to hold. Steps run in order; when
one finishes the next starts on the same tick; after the last one the self stands still until the
take ends.

"Run to the plate, wait for beat 6, heavy swing toward the door" is three lines:

```json
{ "goto": [1.5, 8.5] },
{ "waitUntilBeat": 6 },
{ "press": "heavy", "aim": "gate" }
```

or two, because `at` can ride on any step:

```json
{ "goto": [1.5, 8.5] },
{ "at": 6, "press": "heavy", "aim": "gate" }
```

### Values

**Points** are `[x, y]` in tiles. Tile `(c, r)` covers `x` in `[c, c+1)`, `y` in `[r, r+1)`; its
centre is `[c + 0.5, r + 0.5]`. y grows down the map. The body is a circle of radius 0.3.

**Times** (for `at`, `landAt`, `wait`, `hold`, `timeout`):

| Written | Means |
|---|---|
| `6` | master beats — the shared world clock every tape and enemy lives on, counted from 0 like the HUD ruler. Fractions allowed (`6.5`). |
| `"90t"` | local ticks of this take (60 per recorded second; at 120 bpm a local beat is 30 ticks). |
| `"3lb"` | local beats of this take (what the player hears while recording). |

A tape at speed `s` lives `s` local beats per master beat, so master beat 6 is local tick
`6 × ticksPerBeat × s` (tick 360 at 120 bpm and 2x). A moment that falls between ticks is rounded up
to the next tick. `level.ts show <level>` prints the table for your level.

**Directions** (for `aim` and `face`):

| Written | Means |
|---|---|
| `90` | degrees, clockwise on the map: `0` east (+x), `90` south (down the map), `180` west, `270` north. |
| `"N"`, `"NE"`, `"E"`, `"SE"`, `"S"`, `"SW"`, `"W"`, `"NW"` | compass names; N is up the map. |
| `[8.5, 2.5]` | toward that point, from where the self stands on that tick. |
| `"g1"` | toward the entity with that id: an enemy's **current** position, or a mechanism's place. |

### Steps

Each step has one verb. `press` may also ride on `goto` / `via`. `at` (or `landAt` with a press) and
`note` may accompany any verb.

| Step | What it does | Finishes |
|---|---|---|
| `{ "goto": [x, y] }` | Run to the point and **stop** there. Finds its way around walls, closed doors, unbroken breakables and extended crushers, re-planning every tick (so it waits at a closed door and walks on when it opens). Brakes to a standstill. | Within `tol` tiles (default 0.12) and at rest. |
| `{ "via": [x, y] }` | Run **through** the point flat out without slowing: a waypoint, or a run-up. | Within `tol` tiles (default 0.3). |
| `{ "press": "light" }` | Press a button for one tick: `light`, `heavy`, `dodge`, `ranged`, `interact`, `ability`. Aims along `aim`, else the direction last faced or travelled. Then the plan waits until the action lets go of the body (`probe` lists the commit times); add `"nowait": true` to carry on at once. A dodge travels toward `aim`. A dodge or shot that is still cooling down is held back until it can start. | On the press tick (the wait follows). |
| `{ "goto": [x, y], "press": … }` | Go there, stop, then press: a **standing** action. | On the press tick. |
| `{ "via": [x, y], "press": … }` | Press on arrival **while running**, aimed along the direction of travel unless `aim` says otherwise, and keep moving that way through the action: a **running** swing with the full approach bonus. | On the press tick. |
| `{ "face": dir }` | Set the direction later presses use when they give no `aim`. (The body itself turns only by moving or acting.) | At once. |
| `{ "wait": time }`, `{ "hold": time }` | Stand still for that long. The two are the same. | After that long. |
| `{ "waitUntilBeat": 6 }` | Stand still until master beat 6. | On that tick. |
| `{ "waitUntilTick": 180 }` | Stand still until local tick 180. | On that tick. |
| `{ "at": time }` | The same wait, written with a time value. | On that tick. |
| `{ "waitFor": condition }` | Stand still until something is true in the world. Add `"timeout": time` to give up and carry on. | When true. |

`at` on a step: do nothing until that moment, then perform the step. On `goto` / `via` alone it
delays the departure. On `goto` / `via` **with** a press it times the press: the self sets off at
once and waits on the spot (so on a `via` the run-up is gone; time a running strike with an `at` on
the step before the run instead).

`landAt` (with a press): press early enough that the action's **effect** lands at that moment — the
hit frame of a swing (`light` 6 ticks, `heavy` 16 ticks after the press with the baseline blade),
the launch of a shot. `{ "landAt": 8, "press": "heavy", "aim": "E" }` opens the hit frame exactly on
master beat 8.

Conditions for `waitFor` (exactly one):

| Condition | True when |
|---|---|
| `{ "near": "g1", "dist": 1.5 }` | that enemy (alive) or mechanism is within `dist` tiles of this self. |
| `{ "on": "gate" }` | that mechanism is on: door open, switch on, plate pressed, breakable broken, laser firing, core lit, exit held, trap active. |
| `{ "off": "beam" }` | that mechanism is off. |
| `{ "dead": "g1" }` | that enemy is dead. |
| `{ "telegraph": "t1" }` | that enemy is winding up an attack. |
| `{ "boltWithin": 1.5 }` | an enemy projectile flying toward this self is within that many tiles. |

`"note": "…"` on a step is free text for the reader.

### Examples

Flip a switch, then come back and hold a plate:

```json
{ "goto": [3.5, 2.4], "press": "interact" },
{ "goto": [1.5, 8.5] }
```

Let an enemy come to you and cut it down the moment it is in reach (the baseline blade reaches 1.3
tiles plus the target's radius):

```json
{ "goto": [4.3, 7.5] },
{ "waitFor": { "near": "g2", "dist": 1.5 } },
{ "press": "light", "aim": "g2" }
```

A running heavy into a cracked wall (run-up along the row, swing on arrival, keep moving):

```json
{ "goto": [1.5, 7.5] },
{ "via": [4.0, 7.5], "press": "heavy" }
```

Stand in a turret's lane, roll out of the bolt's way, carry on:

```json
{ "waitFor": { "boltWithin": 1.5 } },
{ "press": "dodge", "aim": "N" }
```

Cross between two beats of a hazard, leaving on a known beat:

```json
{ "goto": [7.4, 1.5] },
{ "waitFor": { "off": "spikes1" } },
{ "goto": [10.5, 3.5] }
```

Hit exactly on a beat, from where you stand:

```json
{ "landAt": 8, "press": "heavy", "aim": "E" }
```

### What `run` tells you about a plan

```
 Plan as played:
   1. goto [4.4,3.5]         tick    0 ->   33   beat   0.00 ->   0.55  at (4.37, 3.50)
   2. waitFor {"on":"gate"}  tick   33 ->   59   beat   0.55 ->   0.98  at (4.37, 3.50)
   3. goto [7.6,4.7]         tick   59 ->  115   beat   0.98 ->   1.92  at (7.58, 4.68)
   4. press heavy, aim amp   tick  115 ->  115   beat   1.92 ->   1.92  at (7.58, 4.68)
```

Each step with the local tick and master beat it began and finished on and where the self stood.
Warnings are printed at the end of the report:

- `LATE: wanted tick 30, was free at tick 60` — an `at` / `waitUntil…` moment had already passed
  when the plan got to that step. The step ran anyway, late.
- `the heavy press on tick 80 was dropped` — the body was still committed to another action (a
  press is remembered for 8 ticks, then lost) or the loadout has nothing on that button.
- `never reached; the take ran out first` and `still in progress when the take ended (the way was
  blocked)` — the plan is longer than the tape, or a `goto` could not get there.
- `the run already wins after take 2` — later takes are never recorded; delete them (`--write`
  refuses to store a solution with dead takes).

### Writing solutions that survive

`level.ts mutate <level>` replays the solution with every take 1 and 2 local ticks late and early
(all takes together, then one take at a time: a late take starts late and every `at` /
`waitUntil…` / `landAt` moves with it) and with every `goto` / `via` target nudged 0.08 tiles in
each direction. Every variant has to win; the test suite runs the 1-tick ones. A solution that
passes only as written will break in the Godot build, whose arithmetic differs in the last digits.

- Prefer `waitFor` (a door is open, an enemy is in reach) to a tick count you measured once.
- Strike with a margin: stand well inside reach, break a wall with momentum to spare (`probe`).
- Do not stop on tile edges or brush past door frames; aim for tile centres.
- Cross a hazard in the middle of its safe window, not on its first tick.

## What the tools write

`npx vite-node scripts/level.ts run <level> --write` stores the performance — only when the run
wins and uses every take — after verifying it: the stored inputs must reproduce the tapes bit for
bit, and both must give the stored outcome. The tool rewrites the whole file in a fixed layout (one
plan step, one input entry, one tape and one event per line), so diffs stay small. Re-run `--write`
after any change to the level or the plan: `validate` and the test suite report a stale file.

```json
{
  "version": 1,
  "level": "sandbox",
  "expect": { "win": true, "takes": 2 },
  "takes": [
    {
      "speed": 2, "endMode": "stop", "note": "…", "plan": [ … ],
      "inputs": [
        { "tick": 37, "press": "heavy", "aim": 0.0169 },
        { "from": 0, "to": 24, "move": [0.3714, 0.9285], "aim": 1.1903 },
        { "from": 24, "to": 25, "move": [0.3461, 0.8651], "aim": 1.1903 },
        { "from": 37, "to": 260, "move": [0, 0], "aim": 0.0169 }
      ]
    }
  ],
  "generated": {
    "format": 1,
    "levelHash": "7b3036ad",
    "planHash": "8015eea9",
    "loadout": { "helmet": "scrap_cap", "top": "lined_bomber", "pants": "olive_cargos", "shoes": "beater_hightops", "melee": "splice_blade", "ranged": "mixtape_rocket" },
    "ticksPerBeat": 30,
    "takesRecorded": 2,
    "ticks": [960, 960],
    "tapes": [
      { "v": 1, "index": 0, "speed": 1, "endMode": "stop", "ticks": 960, "pos": "…", "facing": "…", "anim": "…", "events": [] }
    ],
    "outcome": { "win": true, "objectiveComplete": true, "survivors": [0, 1], "notes": ["…"] },
    "timeline": [
      [0.883, "swing", "B", "", "heavy"],
      [0.883, "break", "B", "cracked", "heavy"]
    ]
  }
}
```

**`takes[k].inputs`** — the controller input (`PlayerInput`) of every local tick of take `k + 1`
(tape index `k`), run-length encoded in the Godot bot's span format:

| Entry | Meaning |
|---|---|
| `{ "from": a, "to": b, "move": [x, y], "aim": r }` | For local ticks `a ≤ t < b` the stick is `(x, y)` — world axes, +x east, +y down the map, length at most 1 — and the aim is `r` radians (`atan2(y, x)`, in (−π, π]). |
| `{ "tick": t, "press": "heavy", "aim": r }` | That button goes **down** on local tick `t` (`light`, `heavy`, `dodge`, `ranged`, `interact`, `ability`), and the aim of that tick is `r`. Two buttons on one tick are two entries. |

The tools write the presses first, then spans that tile `[0, ticks)` with no gap or overlap, every
span carrying both `move` and `aim`, all values rounded to 4 decimals. Readers follow the Godot
bot's rules (`game/bot.gd` `TickScript`; `decodeInputs` in `prototype/scripts/lib/solution.ts` is
the same thing): the last span covering a tick wins, separately for stick and aim; a tick with no
aim span aims along its stick; a press's `aim` overrides the span's. A tick no span covers is a
neutral input.

**`expect`** — `win` and `takes` (how many takes are recorded) of the run below.

**`generated`**:

| Field | Exact meaning |
|---|---|
| `format` | `1`. |
| `levelHash` | FNV-1a (32 bit, 8 hex digits) of `JSON.stringify(level)` as parsed from the level file. Changes when the level's data changes; not when its whitespace does. |
| `planHash` | The same hash of `JSON.stringify({ level, loadout, takes })` with `loadout` the full slot → id map and each take reduced to `{ speed, endMode, note, plan }`. |
| `loadout` | The gear worn by every take, one id per slot (`helmet`, `top`, `pants`, `shoes`, `melee`, `ranged`). |
| `ticksPerBeat` | `3600 / bpm`: local ticks in one beat. |
| `takesRecorded` | The number of takes. |
| `ticks[k]` | Local ticks recorded in take `k + 1`, i.e. how many ticks its `inputs` cover. Normally `bars × 4 × ticksPerBeat`; fewer when the master horizon ends the take first. |
| `tapes[k]` | The recorded trajectory of tape `k`, as `serializeTape` writes it (`prototype/src/core/tape.ts`): `v` 1, `index`, `speed`, `endMode`, `ticks`; `pos` = base64 of little-endian float32 `x, y` pairs, `ticks + 1` samples (sample 0 is the start pose); `facing` = base64 of little-endian float32 radians, `ticks + 1` values; `anim` = base64 of one byte per sample, an index into `ANIM_STATES` (`idle, run, lightWindup, lightActive, lightRecover, heavyWindup, heavyActive, heavyRecover, dodge, ranged, interact, stopped`); `events` = `[tick, kind, dir, x, y, vx, vy]` with `kind` an index into `light, heavy, dodge, ranged, interact, ability`, `dir` in radians, position in tiles and velocity in tiles per local second at the tick the action started. |
| `outcome` | The `Outcome` of the combined run of those tapes: `win`, `objectiveComplete`, `survivors` (tape indices), `reason` when it fails, `notes` (the game's explanation). |
| `timeline` | The gameplay events of that combined run in order: `[master beat (3 decimals), event type, tape letter or "", entity id or "", detail or ""]`. Types kept: `swing, hit, kill, break, clang, dodge, fire, interact, interactFail, door, plate, laser, core, selfDeath, desync, resync, tapeWrap, tapeTurn, tapeEnd, enemyAttack, enemyShot, bossPhase, objective`. An event's beat is the substep it was emitted on divided by the substeps per beat (240 × 60 / bpm). |

### Replaying a solution in another engine

Two ways, from most to least robust:

1. **From the tapes.** Deserialise `tapes`, run the encounter under playback rules for the whole
   horizon with `generated.loadout`, building boss memory from every tape but the last (the last
   one is the take "just recorded"), and compare the result with `outcome` and `timeline`. Nothing
   is re-simulated on the player's side, so this depends only on the world simulation. This is
   what `resolveEncounter` does in the prototype (`replayStoredTapes` in
   `prototype/scripts/lib/run.ts`).
2. **From the inputs.** For each take in order: start a recording at the level's start with the
   earlier tapes playing back, at that take's `speed` and `endMode`, and feed tick `t` the `t`-th
   expanded input, one per local tick, until the take ends. Commit it and go on to the next. The
   recorded tapes should match `tapes` (to float tolerance in an engine with different arithmetic)
   and the final combined run should match `outcome`. In the prototype this is
   `replayStoredInputs` (it drives the real `Session` through `runBot`); in Godot it is the bot,
   run from the repo root:

   ```
   bash tools/gd script res://tools/bot.gd -- 07-two-hands     one solution
   bash tools/gd script res://tools/bot.gd                     every file in this folder
   ```

   which prints `ok … WIN with 2 take(s); …` when the replay meets `expect`.

The plan itself is never needed outside the prototype: it exists so that a designer can write and
change a solution in a few lines, and so `mutate` can perturb it.
