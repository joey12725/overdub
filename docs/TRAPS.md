# OVERDUB — traps and automated machinery

STATUS: IMPLEMENTED

Level designers: everything under "Vocabulary" is the contract you can author against. It is
implemented in the prototype (`prototype/src/core/traps/`), accepted by the level validator
(`prototype/src/content/validate.ts`) and covered by `prototype/tests/core/traps/*.test.ts`
(73 tests). Engineers porting to Godot: read "Porting notes" at the end. Audio, fx and model
artists: read "Events for audio and fx", "Snapshot fields" and "Presentation notes".

Three things changed between the first SPEC draft and this version — check them if you authored
against the draft: (1) shielders and the boss take NO damage from traps (their shield / armour
absorbs every hit that does not come from a tape); (2) a dart launcher's `every` / `offset` and a
relay's `quantize` / `delay` / `hold` must be whole local ticks (use multiples of 0.25 beat); (3) a
sensor's `from` / `to` must be over open tiles, not inside a wall tile.

Traps are machines. They are deterministic, beat-timed, and indifferent to who triggers them: they
kill Moxie's selves and hurt enemies by the same rule. They never target, never randomise, and never
remember anything across runs (AI-04, MUSIC-10). A trap gives the player something to plan around,
something to turn against the enemy roster, and — because several of them block or bend a path —
a new way to desynchronise a recorded self.

## Shared rules (read once)

**Entities.** A trap is one more entry in `LevelDef.entities`, same JSON shape as the level file.
Every trap has an `id`, unique in the level's single id namespace (shared with enemies, doors,
switches …).

**Signals.** Every trap publishes its `id` as a boolean signal (what it means is listed per trap),
readable by any `SignalExpr` in the level: doors, lasers, wake conditions, objectives and other
traps. Every trap that is driven takes an ordinary `SignalExpr`, so anything can drive anything:

```json
{ "sig": "plateA" }
{ "beat": { "every": 4, "from": 2, "to": 3 } }
{ "and": [ { "sig": "tripwire" }, { "not": { "sig": "safety" } } ] }
```

`beat {every, from, to}` is true while `masterBeat mod every` is in `[from, to)`. The window is on
the MASTER clock, so a 2× tape sees it last twice as long in wall time. Fractions are allowed
(`from: 1.5`); keep them on the sixteenth grid (multiples of 0.25).

**Directions.** `dir` is one of `"n" | "e" | "s" | "w"`. `n` points toward row 0 of the map array
(−y), `e` toward higher columns (+x), `s` toward higher rows (+y), `w` toward lower columns (−x).

**Cells.** `{ "c": column, "r": row }`, the same tile coordinates as doors and plates. "Standing on
a tile" always means the body's CENTRE is inside the tile (same rule as pressure plates).

**Lethality follows the signal exactly.** A hazard is dangerous on precisely the substeps its
expression is true — no hidden arming delay — so a beat window in the level file is the beat window
the player hears. The warning the player gets is separate and purely presentational: for one master
beat (`TRAP_WARN_BEATS`) before a beat-timed hazard turns on, its snapshot carries a rising `warn`
0→1 and a `trap` event with detail `<kind>:warn` is emitted once. A hazard driven by a non-timed
signal (a plate, a sensor) has no advance warning by itself: it fires when its cause fires. Put a
`relay` in between if you want the stroke quantised to the beat and telegraphed.

**Who a trap can hurt, move or sense** (the same words are used in every table below):

| Actor state | Hurt by hazards | Moved by belts / bumpers | Blocked by a crusher | Trips sensors |
|---|---|---|---|---|
| live self, alive | yes — one hit kills (dodge i-frames protect) | yes | yes (player physics) | yes |
| live self after death (`recGhost`) | no | yes (it still has a body) | yes | yes, in this take only |
| playback self, alive, synced | yes (recorded dodge i-frames protect) | **never** — its path is the tape | yes → **desync** | yes |
| playback self, dead (`ghost`) | no | no | no (passes through) | no |
| desynced projection | no | no | no | no |
| recovery spark | no | no | it routes around; waits if sealed in | no |
| grounded enemy (grunt, stalker, shielder, brute, boss) | yes (shielder and boss: immune, see below) | yes | pushed out after the stroke | yes |
| turret (bolted down, infinite mass) | yes | no | pushed out after the stroke | yes |
| drone (hovering) | flame, darts, crusher stroke: yes. spikes: no | no | pushed out after the stroke | yes |
| asleep enemy | as its type (a sleeping body is still a body) | as its type | as its type | yes |

**Damage to enemies** goes through the ordinary strike model, so each enemy's own hit rule applies
exactly as it does to any hit that does not come from a tape:
- grunt, stalker, turret (1 hp), drone (2 hp), brute (3 hp): damaged normally. Brutes are never
  staggered by a trap.
- **shielder: immune.** Its shield only drops to hits from two different tapes; a trap hit clangs.
- **boss: immune.** Its armour only opens to a tape striking from behind; a trap hit clangs.
  Traps still MOVE shielders and the boss (belts, bumpers, magnets, crusher push-out).

Continuous hazards (spikes, flame) hit an enemy once when contact starts and again after every full
master beat of unbroken contact (`HAZARD_RETICK_BEATS = 1`), with a 0.25 s stagger and no knockback.
Leaving the hazard resets that clock. Kills are credited to the trap ("spikes s1"), never to a tape,
and count toward `eliminate` objectives like any other kill.

**Recording vs playback.** The live self is physically affected (carried, launched, blocked) and the
result is baked into the take as an ordinary recorded path. On playback that path is replayed
regardless of what the machines are doing now. So a take recorded riding a belt still glides along
the belt's route even if a later tape reverses the belt — and if a later tape makes a crusher extend
where the take walked, the take desyncs there.

**Order inside a substep** (extends the list in `sim.ts`):

```
1 playheads   2 sync   3 dispatch
3b traps.sense      beam sensors and relays publish their signals
4 mechanisms        plates, exits, doors, lasers (they read sensor/relay signals of THIS substep)
4b traps.step       in entity order: spikes, crushers, conveyors, flames, darts, bumpers, magnets
5 enemies   6 projectiles   7 damage   8 objective   9 events
```

Consequences worth knowing: a sensor or relay signal reaches doors and traps the same substep; the
`id` signal of any other trap reaches doors/lasers on the next substep (1/240 s) and reaches traps
later in entity order on the same substep. Trap damage is queued and applied in phase 7 with all
other hits, so a self and an enemy standing on the same spikes die simultaneously.

**Events.** One new `SimEvent.type`: `'trap'`, with `id` = the trap's id and `detail` =
`<kind>:<what>`. Damage reuses the existing `hit` / `kill` / `selfDeath` / `projectileHit` events,
whose `detail` carries the trap kind (`'spikes'`, `'crusher'`, `'flame'`, `'dart'`). Full list in
"Events for audio and fx".

---

## Vocabulary

### 1. Spikes — `spikes`

Floor tiles that are lethal while raised. The simplest beat hazard: a moving "don't be here now".

```json
{ "kind": "spikes", "id": "sp1",
  "cells": [ { "c": 4, "r": 3 }, { "c": 5, "r": 3 } ],
  "upWhen": { "beat": { "every": 4, "from": 2, "to": 3 } } }
```

| Field | Meaning |
|---|---|
| `cells` | Floor tiles covered. Any shape; need not be contiguous. |
| `upWhen` | Raised while true. |
| `damage` | Optional. Damage per hit to enemies (default 1). |

Rules
- Raised ⇔ `upWhen` is true. Raised spikes never block movement, shots or sight.
- While raised, every vulnerable self standing on a cell is killed ("skewered by spikes sp1");
  dodge i-frames carry a self across.
- Grounded enemies standing on a raised cell take `damage` on contact and again each full beat they
  stay. Hovering drones are not touched.
- Signal `sp1`: true while raised.

| Actor | Effect |
|---|---|
| live self | killed on a raised cell unless inside i-frames |
| recording ghost | walks over freely |
| playback self | killed exactly as the live self; a recorded dodge still protects it |
| dead ghost / desynced projection / spark | nothing |
| grunt, stalker | 1 hp: die on contact |
| shielder, boss | immune (shield / armour absorbs it; emits `clang`) |
| brute | 1 damage per beat of contact: dies after two full beats on the spikes |
| turret | damaged like any grounded enemy (put one on spikes to give it a timer) |
| drone | immune |
| projectiles | unaffected |

Puzzle uses
1. **The kill floor.** A corridor of spikes on beats 2–3. A grunt hunting the nearest self is led
   across by a recorded self that crossed on beat 0; the grunt arrives a beat later and dies. The
   player's job is choosing the tape speed that makes the grunt late.
2. **Sacrifice the timer.** Spikes driven by a plate: the self standing on the plate raises the
   spikes under a brute for exactly as long as it stays alive, so another tape must keep the
   plate-holder safe for three beats.

### 2. Crusher — `crusher`

A piston that slams out over a line of tiles. Lethal on the stroke; a solid wall while extended.

```json
{ "kind": "crusher", "id": "cr1",
  "cells": [ { "c": 6, "r": 2 }, { "c": 6, "r": 3 }, { "c": 6, "r": 4 } ],
  "dir": "s",
  "extendWhen": { "beat": { "every": 4, "from": 0, "to": 1 } } }
```

| Field | Meaning |
|---|---|
| `cells` | Floor tiles the piston occupies when extended, ordered from the housing outward. |
| `dir` | Optional, presentation only: the direction the piston travels. Default: inferred from the first two cells; a one-cell crusher with no `dir` is drawn as an overhead stamper. |
| `extendWhen` | Extended while true. |
| `damage` | Optional. Stroke damage to enemies (default 3: kills a grunt, stalker, turret, drone or brute outright; shielders and the boss are immune and are only pushed out). |

Rules
- **Stroke.** On the substep `extendWhen` becomes true, all cells become SOLID at once (movement,
  shots, flames, line of sight — exactly like a closed door). Every vulnerable self standing on a
  cell is killed ("crushed by crusher cr1") unless inside i-frames; every living enemy whose centre
  is on a cell (drones included) takes `damage`.
- **Extended.** While extended the piston only blocks. It is not lethal to touch. Anything alive
  left inside (an enemy that survived, a self that dodged) is handled like a door closing on it:
  enemies are pushed to the nearest free side, the live self is pushed out by its own collision, a
  playback self desyncs.
- **Retract.** When `extendWhen` becomes false the piston withdraws over `CRUSHER_RETRACT_SUBS`
  (60 substeps = 0.25 master s). It stays solid and harmless until the retract completes, then all
  cells open at once. If `extendWhen` turns true again mid-retract it re-extends WITHOUT a new
  stroke (nothing could have entered).
- A level that starts with `extendWhen` true starts extended, with no stroke at beat zero.
- Signal `cr1`: true while solid (from the stroke until the retract completes).

| Actor | Effect |
|---|---|
| live self | killed on the stroke; otherwise blocked like a wall |
| recording ghost | never killed; blocked |
| playback self | killed on the stroke; if its recorded path enters an extended piston it **desyncs** ("blocked by crusher cr1"); the spark waits or routes around and resyncs once the piston retracts and it catches the projection |
| dead ghost / desynced projection | pass through |
| spark | blocked; re-plans when the piston moves |
| any enemy incl. drone | stroke damage, then pushed out |
| projectiles, flame jets, darts, sensor beams | stopped by an extended piston |

Puzzle uses
1. **The moving shield.** A turret covers a corridor; a crusher across the corridor is extended on
   beats 0–2 of every 4. Record the crossing so the self is behind the piston whenever the turret
   fires on its grid.
2. **Desync on purpose.** Tape A's route to the switch crosses a crusher lane. On its own A makes it.
   Tape B must step on a plate (to open the exit) that also extends the crusher: A desyncs, its spark
   waits at the piston, and A only resyncs — and only then can pull the switch — after B steps off.
   The player has to budget for A arriving late.

### 3. Conveyor — `conveyor`

Belts that carry bodies. Delivery, not damage.

```json
{ "kind": "conveyor", "id": "belt1",
  "cells": [ { "c": 2, "r": 5 }, { "c": 3, "r": 5 }, { "c": 4, "r": 5 }, { "c": 5, "r": 5 } ],
  "dir": "e", "speed": 2,
  "reverseWhen": { "sig": "leverA" } }
```

| Field | Meaning |
|---|---|
| `cells` | Floor tiles of the belt. |
| `dir` | Travel direction when not reversed. |
| `speed` | Optional. Tiles per MASTER second (default 2; a grunt walks 2.2, a brute 1.4). |
| `runWhen` | Optional. The belt runs while true (default: always). |
| `reverseWhen` | Optional. While true the belt runs the opposite way. |

Rules
- While running, each substep every carried body whose centre is on a belt cell is displaced by
  `speed / 240` tiles along the current direction, with normal wall collision, on top of whatever
  else moves it (its own walking, knockback).
- Carried: grounded enemies (awake, asleep, staggered or sliding); the LIVE self (alive or recording
  ghost); floor-height projectiles (everything except a lobbed shell in flight) drift sideways with
  the belt without changing heading.
- Not carried: playback selves (the belt's effect is already in the tape), sparks, ghosts, drones,
  turrets (bolted down).
- The live self is displaced once per local tick by the amount the world moves in that tick
  (`speed × substepsPerTick / 240`), so at 2× the belt feels half as fast to the hands — the same
  "fast tape, slow world" rule as everything else.
- Direction changes take effect on the substep the signal changes; there is no spin-down.
- One belt per tile. Put belts of different directions side by side to build corners and junctions;
  a body is carried by at most one belt per substep.
- A belt adds no swing momentum (momentum is the body's own velocity) and never desyncs anything.
- Signal `belt1`: true while running. Signal `belt1.rev`: true while reversed.

| Actor | Effect |
|---|---|
| live self / recording ghost | carried; the recorded path includes the ride |
| playback self | not carried, never desynced by a belt; follows its tape |
| dead ghost / projection / spark | nothing |
| grunt, stalker, shielder, brute, boss | carried while they walk, fight, stagger or sleep |
| turret, drone | not carried |
| projectiles | drift with the belt (a slow missile visibly curves; a dart barely moves) |

Puzzle uses
1. **Delivery into a recorded swing.** A sleeping grunt sits on a belt. Tape A records a heavy swing
   at the belt's end on the beat the grunt arrives. Nothing woke it; the machine brought it.
2. **Reverse the line.** A belt carries stalkers toward the exit. Tape B's switch reverses it so the
   same belt feeds them into spikes instead — but tape A recorded its own walk with the belt's help,
   and A's take is unchanged by the reversal (it keeps its recorded path), so only the enemies are
   re-routed.

### 4. Flame jet — `flame`

A directional hazard from a nozzle out to a range. Doors and pistons are shields.

```json
{ "kind": "flame", "id": "fl1", "c": 1, "r": 4, "dir": "e", "range": 5,
  "onWhen": { "beat": { "every": 2, "from": 1, "to": 2 } } }
```

| Field | Meaning |
|---|---|
| `c`, `r` | The nozzle tile. Normally a wall tile; the nozzle itself never burns or blocks. |
| `dir` | Direction of the jet. |
| `range` | Whole tiles covered, starting with the tile next to the nozzle. |
| `onWhen` | Burning while true. |
| `damage` | Optional. Damage per hit to enemies (default 1). |

Rules
- While on, the jet covers the tiles in front of the nozzle up to `range`, cut short at the first
  tile that blocks shots: a wall, a closed door, an unbroken breakable, an extended crusher. Low
  barriers (`=`) and void do not stop it. The reach is re-measured every substep, so opening a door
  lets the fire through that instant.
- Every vulnerable self standing on a covered tile is killed ("burned by flame jet fl1"); i-frames
  protect. The `laserProof` ability does not.
- Every living enemy on a covered tile — drones included — takes `damage` on contact and each full
  beat it stays. Bodies do not shield what is behind them.
- Signal `fl1`: true while burning.

| Actor | Effect |
|---|---|
| live self | killed unless dodging |
| recording ghost | unharmed |
| playback self | killed unless its recorded dodge covers the crossing |
| dead ghost / projection / spark | nothing |
| grunt, stalker, turret, drone, brute | 1 damage on contact + 1 per beat of contact |
| shielder, boss | immune |
| projectiles | unaffected |

Puzzle uses
1. **Door as shield.** A jet rakes the only corridor on every off-beat. A door halfway along is
   normally open. Tape A holds the plate that CLOSES it; while the door is shut the far half of the
   corridor is safe and tape B walks it.
2. **Cook the brute.** A brute takes three hits. Lure it (it hunts the nearest self) so that it stands
   in the jet's lane for three beats, using a self parked behind a low barrier as bait: the barrier
   stops the brute, not the flame.

### 5. Dart launcher — `dart`

An indestructible automated shooter. It fires straight down its lane on a beat grid, at nothing.

```json
{ "kind": "dart", "id": "d1", "c": 0, "r": 3, "dir": "e", "every": 2, "offset": 0 }
```

| Field | Meaning |
|---|---|
| `c`, `r` | The launcher tile, normally a wall tile. It cannot be damaged, moved or turned. |
| `dir` | Lane direction. |
| `every`, `offset` | Fires on master beats `offset + k·every` (defaults 2 and 0). Both must land on whole local ticks (multiples of 1/30 beat at 120 bpm; use quarters). |
| `enabledWhen` | Optional. Fires only while true (default: always). |
| `speed` | Optional. Dart speed in tiles per master second (default 8). |

Rules
- On each grid beat while enabled it spawns one dart at the lane-side edge of its tile, flying
  straight along `dir`. No targeting, ever.
- A dart is a projectile (`archetype: 'dart'`, owner `{ enemy: <launcher id> }` in snapshots). It
  stops at walls, closed doors, unbroken breakables and extended crushers; it flies over low
  barriers. It kills the first vulnerable self it touches ("shot by dart launcher d1"); a self inside
  i-frames is passed through; ghosts, the recording ghost and desynced projections are passed
  through. It strikes the first living enemy it touches: 1 damage, 0.25 s stagger, no knockback.
- The `parry` gear ability turns a dart like any enemy shot.
- Signal `d1`: true while enabled.

| Actor | Effect |
|---|---|
| live self / playback self | killed on contact unless dodging |
| recording ghost, dead ghost, projection, spark | passed through |
| every enemy type | 1 damage + stagger; the dart stops |
| conveyor | a dart crossing a belt drifts with it |

Puzzle uses
1. **Knock them into the lane.** A 0.5× light swing has too little momentum to kill a grunt, but its
   knockback (0.6 tiles) shoves the grunt into a dart lane and the next dart finishes it. The slow
   tape is useful because of where the enemy lands, not because of the damage it does.
2. **A clock you can stand behind.** Darts cross a room every 2 beats. A stalker chasing the farthest
   self takes the straight route across the lane; the player leads it so its crossing lands on the
   beat.

### 6. Bumper — `bumper`

A spring plate: automated knockback.

```json
{ "kind": "bumper", "id": "bm1", "c": 7, "r": 4, "dir": "n", "power": 3,
  "fireWhen": { "beat": { "every": 4, "from": 3, "to": 3.5 } } }
```

| Field | Meaning |
|---|---|
| `c`, `r` | The plate's floor tile. |
| `dir` | Launch direction. |
| `power` | Optional. Launch distance in tiles for a body of mass 1 (default 3). |
| `fireWhen` | The plate fires once each time this BECOMES true (rising edge). |

Rules
- On the firing substep every grounded living enemy standing on the tile is knocked back
  `power / mass` tiles along `dir` — the same real knockback as a melee hit: it slides with wall
  collision, a telegraph in progress is broken, slamming a wall turns the rest into stagger, and the
  enemy carries on from where it lands (MOM-05). No damage.
- The LIVE self standing on it (alive or recording ghost) is thrown `power` tiles along `dir` over
  the same 0.18 master seconds, with wall collision; the flight is recorded as ordinary movement.
  The player keeps control of actions and may steer against it.
- A playback self is never launched (MOM-06: the world never displaces a recorded self). Drones and
  turrets are not launched.
- It then needs `fireWhen` to go false and true again to fire once more. A `fireWhen` that is
  already true at beat zero does not fire.
- The launch never adds swing momentum: momentum comes from the controller's own velocity, which a
  belt or a bumper does not change.
- Signal `bm1`: true for 0.25 master s after each firing (a pulse other machines can read).

| Actor | Effect |
|---|---|
| live self / recording ghost | thrown `power` tiles |
| playback self, ghost, projection, spark | nothing |
| grunt, stalker, shielder | thrown ≈ `power` tiles (mass 1, 0.8, 1.2) |
| brute | thrown `power / 3` |
| boss | thrown `power / 8` |
| turret, drone | nothing |
| projectiles | nothing |

Puzzle uses
1. **Two-stage knockback.** A light swing at 0.5× barely moves a grunt — but it moves it one tile,
   onto a bumper that fires on beat 3 and throws it into the spikes. The puzzle is landing the weak
   hit before the beat.
2. **Launch the live take.** A gap is too wide to dodge. The live self stands on the bumper on the
   beat and is thrown across; the recorded take then simply contains the flight. A later tape that
   closes a door in the flight path desyncs it mid-air.

### 7. Beam sensor — `sensor`

A tripwire that is a signal source. Harmless; it lets bodies drive machines.

```json
{ "kind": "sensor", "id": "trip1",
  "from": { "x": 3.5, "y": 2.0 }, "to": { "x": 3.5, "y": 6.0 },
  "detects": "enemies" }
```

| Field | Meaning |
|---|---|
| `from`, `to` | World-space ends of the beam (tile units; tile centres are `c + 0.5`). The emitter is at `from`. |
| `detects` | Optional. `"any"` (default), `"selves"` or `"enemies"`. |
| `latch` | Optional. If true the signal stays true for the rest of the run once tripped. |

Rules
- Signal `trip1` is true while at least one detected body overlaps the beam (centre within its own
  radius of the segment): effective selves — alive or recording ghost, and synced — and/or living
  enemies of every type, awake or asleep.
- The beam is cut at the first tile that blocks shots between `from` and `to` (wall, closed door,
  extended crusher, unbroken breakable). Bodies beyond the cut are not seen, and the cut itself does
  not trip the sensor. Both ends must be over open tiles (the validator rejects an end inside `#`).
- Projectiles, sparks, dead ghosts and desynced projections never trip it.
- It does no damage and blocks nothing.

| Actor | Effect |
|---|---|
| live self, recording ghost, playback self (synced) | trips it (unless `detects: "enemies"`) |
| dead ghost / projection / spark | invisible to it |
| every enemy type | trips it (unless `detects: "selves"`) |
| projectiles | invisible to it |

Puzzle uses
1. **The enemy opens the door.** The exit door opens on `trip1`, an enemies-only beam in a side
   passage. No self can trip it; the player must make a grunt walk through it (bait on the far side)
   at the moment another self is at the door.
2. **Self-triggered crusher.** A beam across a corridor fires a crusher further along one beat later
   (through a relay). The first tape through is safe; a second tape following two beats behind is
   crushed by the first tape's trip — so the two takes must be spaced by tape speed.

### 8. Relay — `relay` (addition)

Memory and timing for chains: turns any trigger into a beat-quantised pulse, latch or toggle. It has
no body; it is drawn as a small indicator lamp on the wall (place it with `x`, `y` if you want it
seen). It earns its place because a sensor is only true while something stands in it: the relay is
what makes "an enemy walked through, so the crusher slams ON THE NEXT BEAT" expressible, and what
gives signal-driven hazards a telegraph.

```json
{ "kind": "relay", "id": "slam", "trigger": { "sig": "trip1" },
  "mode": "pulse", "quantize": 1, "delay": 1, "hold": 1 }
```

| Field | Meaning |
|---|---|
| `trigger` | The relay arms each time this BECOMES true (rising edge). |
| `mode` | `"pulse"` (default): output true for `hold` beats. `"latch"`: output true forever. `"toggle"`: output flips. |
| `quantize` | Optional. The relay fires on the first master beat boundary that is a multiple of this many beats at or after the trigger (default 1; 0 = fire on the trigger's own substep). |
| `delay` | Optional. Extra beats after the quantised boundary (default 0). |
| `hold` | Optional, pulse mode. Output length in beats (default 1). |
| `x`, `y` | Optional. Where to draw the lamp. |

Rules
- Rising edge of `trigger` → the relay is ARMED and will fire at `ceil-to-quantize(now) + delay`.
  While armed, or while a pulse is still running, further rising edges are ignored (one job at a
  time; this keeps chains readable).
- Firing sets the output per `mode`. Signal `slam` is the output. Signal `slam.armed` is true from
  the trigger until it fires — a ready-made telegraph: drive a warning lamp with it.
- Hazards driven by a relay are telegraphed: the `warn` forecast of spikes, crushers and flames
  follows an armed relay's schedule. With `delay: 1` the player always gets the full one-beat ramp;
  with `delay: 0` they get whatever is left of the current beat.
- `quantize`, `delay` and `hold` must be whole local ticks (multiples of 0.25 beat are always safe).
- At beat zero the output is false and nothing is armed; a trigger that is already true at beat zero
  does not count as a rising edge.

Interacts with no actor directly.

Puzzle uses
1. **Quantised ambush.** `trip1 → relay(delay 1, hold 1) → crusher`: whenever an enemy crosses the
   beam, the crusher two tiles further slams exactly one beat later. The player times a knockback so
   the enemy is under it.
2. **One-shot bridge.** `latch`: the first body through a sensor permanently opens a door. Under
   playback a dead ghost no longer trips it, so a take that died before the beam leaves the door
   shut for everyone behind it (Scenario C, automated).

### 9. Magnet — `magnet` (addition)

Pull, to go with the bumper's push and the belt's carry: gathers enemies to a point.

```json
{ "kind": "magnet", "id": "mag1", "x": 6.5, "y": 4.5, "radius": 4, "pull": 1.5,
  "onWhen": { "sig": "leverM" } }
```

| Field | Meaning |
|---|---|
| `x`, `y` | The magnet's position (world units). It has no collision. |
| `radius` | Tiles. Bodies farther than this are unaffected. |
| `pull` | Optional. Tiles per master second for a body of mass 1 (default 1.5). |
| `onWhen` | Pulling while true. |

Rules
- While on, each substep every living enemy within `radius` (centre distance; walls do not shield)
  is displaced `pull / mass / 240` tiles straight toward the magnet, with its normal collision, on
  top of its own movement. It stops being pulled inside 0.6 tiles of the centre. Enemies keep
  thinking and attacking while pulled.
- Drones are pulled (they are metal and light: mass 0.7). Turrets are not (infinite mass).
- Selves, sparks and projectiles are never pulled.
- Signal `mag1`: true while on.

| Actor | Effect |
|---|---|
| every self state, spark, projectiles | nothing |
| grunt 1.5 t/s · stalker 1.9 · shielder 1.25 · brute 0.5 · drone 2.1 · boss 0.19 | dragged toward the centre |
| turret | nothing |

Puzzle uses
1. **Gather for one swing.** Three grunts spread out to chase three selves. A switch-driven magnet
   beside tape A's recorded heavy swing drags them into one arc for the two beats the lever is on.
2. **Hold the drone still.** A drone keeps its distance and cannot be reached. A magnet under a
   flame jet's lane pins it where the jet fires.

---

## Events for audio and fx

New `SimEvent.type: 'trap'`. `id` is the trap id, `x`/`y` its position (centre of its cells / its
tile / the beam's midpoint), `dir` in radians where meaningful. `<kind>:warn` events carry `power` =
beats until the activation.

Prototype caveat: the string `'trap'` is emitted, but it is not yet a member of the TypeScript
`SimEventType` union (`TRAP_EVENT` in `prototype/src/core/traps/tuning.ts` explains why: the fx
routing test requires a route in `src/render/fx/catalog.ts` for every declared type, and that file
belongs to the fx engineer). The prototype's fx director and sfx table ignore unrouted types, so
trap state changes are silent there until the union member and its route are added together. In the
Godot port it is simply one more event type string.

| `detail` | When | Notes |
|---|---|---|
| `spikes:warn` / `crusher:warn` / `flame:warn` | one beat before a beat-timed activation | telegraph cue |
| `spikes:up`, `spikes:down` | spikes raise / drop | |
| `crusher:slam` | the stroke | `power` = bodies struck |
| `crusher:retract` | retract begins | |
| `crusher:hold` | the signal returned mid-retract: re-extended, no stroke | |
| `crusher:open` | retract complete, tiles passable | |
| `conveyor:on`, `conveyor:off`, `conveyor:reverse`, `conveyor:forward` | belt state change | `dir` = new travel direction |
| `flame:on`, `flame:off` | jet ignites / stops | `power` = reach in tiles |
| `dart:fire` | a dart leaves the launcher | `dir` = lane |
| `dart:on`, `dart:off` | `enabledWhen` changed | |
| `bumper:fire` | the plate fires | `power` = bodies launched (0 = empty fire) |
| `sensor:on`, `sensor:off` | beam tripped / cleared | |
| `relay:armed`, `relay:on`, `relay:off` | relay accepted a trigger / output changed | `relay:armed` carries `power` = beats until it fires |
| `magnet:on`, `magnet:off` | | |

Reused events: `hit` and `kill` (enemy struck / killed by a trap; `detail` is `'spikes'`,
`'crusher'`, `'flame'` or `'dart'`, no `tape`), `selfDeath` (`detail` is the cause text, e.g.
"skewered by spikes sp1"), `projectileHit` (`detail` `'dart'` or `'dart:wall'`), `enemyStagger`,
`desync` (`detail` "blocked by crusher cr1").

## Snapshot fields (renderer)

Traps appear in `FrameSnapshot.mechs` after the classic mechanisms, in entity order, as `MechSnap`
with these `kind`s and optional fields:

| kind | `on` | `t` | other |
|---|---|---|---|
| `spikes` | raised | 1 raised, 0 down | `warn` 0..1 |
| `crusher` | solid | extension 0..1 (1 extended, ramps 1→0 during the retract) | `warn` 0..1, `dir` piston travel (absent for a one-cell crusher with no `dir`: draw an overhead stamper) |
| `conveyor` | running | — | `dir` current travel direction (radians) |
| `flame` | burning | — | `dir`, `reach` = tiles the jet covers right now (reported while off too: it is the danger lane), `warn` |
| `dart` | enabled | 0..1 progress toward the next shot | `dir`, `firing` true for 0.1 s after a shot |
| `bumper` | within 0.25 s of firing | 1→0 spring return | `dir`, `firing` |
| `sensor` | tripped | — | `reach` live beam length in tiles |
| `relay` | output | 0..1 progress from armed to firing | `warn` = 1 while armed |
| `magnet` | pulling | — | — |

## Porting notes

For the engineer porting this to GDScript. The reference is `prototype/src/core/traps/`; the tests
in `prototype/tests/core/traps/` state every rule with exact substep numbers and are the fastest way
to check a port (the fixtures are a 12×10 room at 120 bpm: 120 substeps per beat).

### Files

| File | What is in it |
|---|---|
| `src/core/traps/system.ts` | `Traps`: all state and rules for the nine kinds, the telegraph forecast, `liveCarry`, the snapshot. ~750 lines; port as one class. |
| `src/core/traps/dart.ts` | The `'dart'` projectile archetype (a targetless bolt) and `spawnDart`. Registers itself with the projectile system on import. |
| `src/core/traps/live.ts` | `displaceController`: sets the live PlayerController's position. See "The live self" below. |
| `src/core/traps/tuning.ts` | Every constant, and `TRAP_EVENT`. |
| `src/core/types.ts` | ADDED: `Dir4`, `TileRef`, `SpikesDef` … `MagnetDef`, `TrapDef`; nine members on `EntityDef`; nine `MechSnap.kind`s and the optional `warn`, `dir`, `reach`, `firing` fields; `'dart'` on `ProjectileSnap.archetype`. Nothing renamed or removed. |
| `src/core/sim.ts` | Six small hooks, listed below. |
| `src/content/validate.ts` | Trap kinds added to the entity / id / signal tables; one `case` per kind; `<belt>.rev` and `<relay>.armed` registered as signals; crusher-cell exclusivity check. |
| `src/core/mechanisms.ts`, `src/core/objective.ts` | NOT modified. Trap deaths, kills and desyncs flow through the existing `combat` queue, `RunLog` and `Sim.desync`, so objectives and outcome notes needed nothing new. |

### Hooks in `sim.ts` (all six)

1. Field `readonly traps: Traps`, constructed after `Mechanisms` with `(level, grid, signals)`.
2. Initial state: `traps.init(this); mechs.init(this); traps.init(this);` — `init` is idempotent. The
   first call publishes trap signals so doors can read them at beat zero; the second lets traps read
   door signals. Nothing strokes, fires, launches or counts as a rising edge at beat zero.
3. `stepLocalTick`, before `controller.step`: if `traps.count > 0`, `traps.liveCarry(this, pose.x,
   pose.y, subsPerLocalTick(speed))`; if it returns a position, move the controller there.
4. `substep`, between dispatch (3) and mechanisms (4): `traps.sense(this)`.
5. `substep`, between mechanisms (4) and enemies (5): `traps.step(this)`.
6. `snapshot`: `mechs = mechs.snapshot() ++ traps.snapshot(sub)` when `traps.count > 0`.
   `obstructionCause`: `mechs.ownerAt(c, r) ?? traps.ownerAt(c, r)` (gives "blocked by crusher cr1").

`traps.count == 0` makes every entry point return at once. That is the whole additivity guarantee:
a level without traps runs the old code path, bit for bit (the full prototype suite passes
unchanged: 756 tests).

### Evaluation order and timing conventions

`s` is the substep being simulated, `now = s + 1` the instant it produces, `beat = now / spb`.

- **Signal-driven state** (spikes up, crusher extend, flame on, conveyor run/reverse, magnet on, dart
  enabled, bumper and relay triggers) evaluates its expression at `beat`, exactly like doors and
  lasers. So a window `from: n` turns true in substep `n·spb − 1`.
- **Relay** quantisation is in `now` units: `fireAt = ceil(now / q) · q + delay` (or `now` when
  `quantize` is 0); it fires in the substep where `now >= fireAt`, i.e. the same substep a beat
  window starting on that beat turns true. Pulse end: `now >= fireAt + hold`. The end is processed
  before a new rising edge, so back-to-back pulses are possible.
- **Dart launcher** grid is in `s` units, like enemy attack grids (`isGridSub`): it fires when
  `s >= off && (s − off) % per == 0`. So a dart leaves one substep after a beat window on the same
  beat turns true, and on exactly the substep a turret with the same grid fires.
- `traps.sense`: sensors in entity order, then relays in entity order. A relay reads sensor signals
  of this substep and every other signal as of the previous substep.
- `traps.step`: first, if a crusher stroked on the previous substep, push every living enemy that is
  inside solid geometry to the nearest free side (`grid.moveCircle` with zero motion; drones use
  hover solidity). Doing it one substep late is deliberate: enemies killed by the stroke die where
  they stood. Then every non-sense trap in entity order.
- Hits are queued (`combat.hitSelf`, `combat.strikeEnemy` with `source: { env: "<kind> <id>" }`,
  explicit `damage`, `knockback: 0`, `stagger: 0.25`) and applied in phase 7. Vulnerability, i-frames
  and enemy `onHit` vetoes are the queue's existing rules; traps add none of their own.
- "On a tile" is always `floor(x) == c && floor(y) == r` on the body's centre.

Per kind, the non-obvious parts:

- **spikes / flame contact clock**: per trap, `Map<enemyId, nextHitSub>`. No entry → hit now, next =
  `s + spb`. Entry and `s >= next` → hit, next += `spb`. Not touching → delete the entry. Cleared
  when the hazard turns off.
- **crusher**: three phases. `open → extended` on the signal (the stroke: queue hits on centres in
  the cells, THEN set the cells dynamic-solid, set the signal, flag the push-out). `extended →
  retracting` when the signal drops (`k = 60`). `retracting`: signal back → `extended` with no
  stroke; else `k--`, and at 0 clear solidity and the signal. Solidity is the grid's existing dynamic
  overlay, so pathfinding, shots, flames, sensors and the desync test need no changes.
- **conveyor**: displacement per substep `speed / 240`, through `grid.moveCircle` for enemies (so
  walls stop them), added directly for projectiles with `z <= 0` unless the destination tile blocks
  shots. An enemy is carried by at most one belt per substep (`carriedAt` stamp).
- **flame**: reach is recomputed every substep, on or off: walk `k = 1..range` from the nozzle and
  stop at the first `grid.blocksShot` tile.
- **dart**: no dart is spawned when the tile in front of the launcher blocks shots. Spawn point is
  the tile centre + `0.5 + radius + 0.01` along `dir`. Owner is `{ enemy: <launcher id> }`.
- **bumper**: rising-edge detector (`prev`). Enemies: `applyKnockback(dir, power / mass)` — the
  existing knockback slide, so wall slams and telegraph breaks come for free. Live self: stores a
  per-substep displacement and 43 substeps; `liveCarry` consumes them.
- **magnet**: step = `min(pull / mass / 240, d − 0.6)` toward the centre; skips infinite mass;
  drones move with `hoverMove`.
- **sensor**: raycast `from → to` with projectile solidity gives the live length; test bodies
  against the cut segment with their own radius (selves: `canAct`; enemies: `alive`).

### The live self

`liveCarry(w, x, y, subs)` runs once per LOCAL tick, before the controller steps: it sums the
remaining bumper launch (`min(subs, left)` substeps of it) and the belt under the controller's tile
(`speed · subs / 240`), applies the sum with `grid.moveCircle` at the actor radius, and returns the
new position. Only a live self with a body is moved (alive or recording ghost, synced); a launch
that is pending while the self has no body is used up, not saved.

The prototype then writes the position into the PlayerController's private fields
(`traps/live.ts`), because `player.ts` belongs to another engineer. **In the port, give the
controller a public `displace(x, y)` that sets its position (rounded to float32 like every other
position it stores) and leaves velocity alone**, and call that.

Because the live self is read back through its own tape, nothing else is needed: the take records
the carried positions, and on playback `traps.step` finds no live self, so nothing moves the
recording twice.

### Telegraph (`warn`)

Presentation only; it never feeds back into the sim. For spikes, crushers and flames, while off: on
every substep where the cached forecast has expired, and otherwise 8 times per beat, scan the
instants `at` on the sixteenth grid (`spb / 4`) in `(now, min(now + spb, horizonSubs)]` and take the
first at which the expression is true, evaluated at beat `at / spb` against a signal table that is
the current one except that relay outputs are forecast from their schedule (armed and `fireAt <= at`
→ pulse on until `fireAt + hold`, latch on, toggle flipped; running pulse with `endAt <= at` → off).
`warn = 1 − (onAt − now) / spb`. Emit `<kind>:warn` when a forecast first appears. `warn` is 0
while the hazard is active.

### What a GDScript port must reproduce exactly

Entity order (it decides ties and same-substep signal visibility); the `sense` / `step` split; the
one-substep-late push-out; the `s`-based dart grid versus the `now`-based relay grid; float32
rounding of the displaced live position; and the snapshot order (classic mechanisms first, then
traps, each in entity order).

### Not done / known gaps

- `'trap'` is not in the `SimEventType` union (see "Events"). One-line follow-up for whoever owns
  `src/render/fx/catalog.ts`, together with a `trap` route.
- The prototype renderer, HUD and audio do not draw or sound traps (no code under `src/render`,
  `src/ui`, `src/audio` was touched). `ProjectileSnap.archetype` `'dart'` and the nine new
  `MechSnap.kind`s are unknown to the prototype's Three.js layers.
- `beatSight` (`ISim.threatBeats`) lists enemy attacks only; trap strokes are not included.
- The validator checks shapes, tiles and signal references. It does not prove a trap level is
  solvable or that a hazard cannot trap the start tile.
- No authored campaign level uses traps yet; only the test fixtures do.
- Enemy pathfinding does not avoid hazards. That is intended (enemies are rule-followers and traps
  are how the player kills them) but it means a grunt will walk through a flame lane to reach a self.

## Presentation notes

What each machine must look and sound like so the player can read it at a glance from the isometric
camera. Common language, so nine machines read as one family:

- **Hazard yellow-and-black chevrons** mark every tile a machine can hurt or move you on, always
  visible, in both themes. If a tile has chevrons, something happens there on a beat.
- **Three states, three looks**: SAFE (dim, cool, still) → WARNING (the `warn` ramp: a glow that
  fills 0→1 over exactly one beat, plus one pre-echo sound on `<kind>:warn`) → LIVE (hot, bright,
  moving). The ramp must be linear in `warn` so a player can time a crossing off it.
- **Everything lands on the beat.** Strokes, spikes, flames and darts fire on beat-grid instants;
  their sounds must be un-quantised (they already are on the grid) and pitched from the current
  chord, percussive, sitting with the drums (MUSIC-10). Never delay a trap sound.
- Machines never use a cassette colour. Cassette colours mean "a self did this".

| Trap | Safe | Warning | Live | Sound | Must be readable |
|---|---|---|---|---|---|
| **Spikes** | Flush floor plate with rows of dark holes, chevron border. | Tips rise ~10% and shiver; holes glow red-orange, brightness = `warn`. | Full-height steel spikes (about waist height), snapped up in ≤ 2 frames; drop is slower (~0.1 s). | `spikes:warn`: rising metallic scrape. `spikes:up`: sharp "shink" on the beat. `spikes:down`: soft ratchet. | Which tiles; that they are passable when down. |
| **Crusher** | Piston head withdrawn in its housing (a wall-mounted block, or an overhead stamper when the snapshot has no `dir`); the lane it will fill is chevron-striped floor with scuff marks. | Housing shudders, warning lamp fills with `warn`, dust falls; a ghosted outline of the head on the lane. | Head fills every cell floor-to-shoulder (`t` = 1) — it must look as solid as a wall, because it is. Retract: `t` 1→0 over 0.25 s, visibly slow and harmless (steam, no glow). | `crusher:warn`: hydraulic wind-up. `crusher:slam`: the heaviest hit in the kit, with screen shake scaled by `power` (bodies struck). `crusher:retract`: hiss. `crusher:open`: clunk. `crusher:hold`: short re-lock click. | The lane; direction of travel (`dir`); that the extended head is cover from fire. |
| **Conveyor** | — (a stopped belt: static tread, lamps off). | — | Tread texture scrolls along `dir` at the real speed (tiles per master second, so it visibly slows while a fast tape records); animated chevrons point the way; small rollers at both ends. Reversal: chevrons flip in one frame. | Looping low rumble while running, pitch tied to speed. `conveyor:reverse` / `forward`: gear clunk. `conveyor:on` / `off`: motor spin. | Direction of travel, always, even from a still frame (the chevrons). |
| **Flame jet** | Nozzle in the wall with a blue pilot light; scorch marks along the whole lane (`reach` is reported while off: scorch only as far as the jet can currently go, so a closed door visibly shortens the danger). | Pilot flares, gas shimmer along the lane, intensity = `warn`. | A roaring jet exactly `reach` tiles long, ending in a splash against whatever stops it (door, piston, wall). | `flame:warn`: gas hiss rising. `flame:on`: whoomp on the beat, then a roar loop. `flame:off`: cut with a short tail. | The lane and its current length; that doors and pistons cut it. |
| **Dart launcher** | A slotted block in the wall; a thin scored line on the floor down its lane. A ring of pips around the slot fills with `t` (progress to the next shot). | The last quarter of `t`: the slot glows. | `firing`: muzzle flash for 0.1 s; the dart is a short bright bolt with a hard trail, clearly not an enemy bolt (different colour from turret shots). Disabled (`on` false): slot shuttered, pips dark. | `dart:fire`: dry "thock", every time, on its grid — it becomes a rhythm part. `projectileHit` `dart:wall`: tick. | The lane; the rhythm; enabled vs shuttered. |
| **Bumper** | A round sprung plate with an arrow painted on it pointing along `dir`. | (driven by a beat window: use the plate's own compress animation over the beat before, if the designer adds a relay / the expression is timed) | `firing` / `t` 1→0: plate punches up and settles over 0.25 s; launched bodies get a speed-line streak. | `bumper:fire`: springy "boing-clank", louder when `power` > 0 (something was on it). | The launch direction (arrow). |
| **Beam sensor** | A thin, steady, pale beam between two small posts, drawn only as long as `reach` (it visibly stops at a closed door). Harmless: thin and cool-coloured, never red. | — | Tripped (`on`): the beam and both posts flash bright and stay lit while tripped; a pulse runs along the cable toward whatever it drives if decor cables are placed. | `sensor:on`: soft two-note chirp. `sensor:off`: single lower note. | That it is not a laser (lasers kill; this one is thin, pale and dotted). |
| **Relay** | A small wall lamp, dark. | Armed (`warn` = 1): lamp blinks, with a ring filling with `t` toward the firing beat. | Output on: lamp solid. | `relay:armed`: tick. `relay:on`: clack. `relay:off`: softer clack. | That a machine is about to act, and when. |
| **Magnet** | A floor disc or ceiling coil, inert, with a faint ring at `radius`. | — | Coil glows, concentric rings contract toward the centre, pulled enemies trail sparks toward it. | `magnet:on`: rising hum that holds. `magnet:off`: falling. | The radius, and that it only pulls enemies. |

Actor feedback the fx / audio engineers should route from the reused events:

- `selfDeath` with a trap cause ("skewered by spikes…", "crushed by crusher…", "burned by flame
  jet…", "shot by dart launcher…"): pick the death flourish from the first word of `detail`.
- `hit` / `kill` with `detail` `'spikes' | 'crusher' | 'flame' | 'dart'` and no `tape`: an
  environment kill — use the trap's own impact, not a cassette-coloured hit burst.
- `desync` with `detail` "blocked by crusher <id>": the existing desync treatment; the spark should
  be seen waiting at the piston face, which is what tells the player why the self is late.
- A self carried by a belt or thrown by a bumper is ordinary recorded movement: on playback it
  glides exactly as recorded even if the belt now runs the other way. A subtle ghosted trail in the
  cassette colour while a playback self's motion disagrees with the belt under it would help sell
  "this is a recording".
