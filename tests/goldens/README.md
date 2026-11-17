# Golden fixtures: the prototype's rules, as data

Each `tests/goldens/<name>.json` is one deterministic scenario run through the prototype's real
simulation (`prototype/src/core`). It carries everything needed to replay it with no other file: the
level, the loadout, the takes, the boss memory, and the expected results. The Godot port must
reproduce every file within the tolerances below. That is the evidence that the port preserves the
rules (docs/GODOT-PORT.md "Tests").

- Regenerate with `cd prototype && npx vite-node scripts/export-goldens.ts`. The exporter deletes
  and rewrites every `*.json` here, writes `index.json`, and leaves this README and the `.gd` suite
  alone. Two runs give byte-identical files.
- `test_goldens_format.gd` (`bash tools/gd test goldens/test_goldens`) checks only the files: they
  parse, load through the port's `from_dict()` types, round-trip, and follow the sampling rule.
  Replaying the scenarios through `ODSim` and comparing the results is the job of the core port's
  golden runner, which this README is written for.
- The scenarios come from the prototype's own suites (`prototype/tests/core/**`,
  `prototype/tests/game/**`). Each one's `covers` names the requirement ids, scenario letters and
  test names it reproduces. Every scenario has a check in the exporter that restates its test's
  assertions, and the export fails if any check fails, so a golden cannot quietly stop showing its
  rule.

## Comparison tolerance (what "reproduce" means)

| Quantity | Rule |
|---|---|
| Event list | **Same length, same order.** Per event, `sub`, `type`, `tape`, `id` and `detail` are **equal**, and a key's presence matches. |
| Event `x`, `y`, `power` | absolute difference ≤ **1e-3** |
| Event `dir`, actor `facing`, projectile `dir`, trap mech `dir` | angular difference, wrapped to (-π, π], ≤ **1e-3 rad**. Compare angles wrapped: π and -π are the same heading. |
| Positions (actor `x/y`, `spark`, enemy `x/y`, projectile `x/y/z`, `bossRecallAt`) | ≤ **1e-3 tiles** |
| `phase.tick`, mech `t` / `warn` / `reach`, objective `progress`, `beat`, `threatBeats[i]` | ≤ **1e-3** |
| Everything else (counts, ids, enums, booleans, `hp`, `maxHp`, `target`, `phase.dir/traversal/ended`, `survivors`, `reason`, `win`) | **equal** |
| Snapshot lists (`actors`, `enemies`, `projectiles`, `mechs`) | same length and order; optional keys (`spark`, `target`, `shield`, `boss*`, `targetId`, `t`, `warn`, `dir`, `reach`, `firing`) present exactly when the golden has them |
| Recorded tape (recordings only) | `index`, `speed`, `endMode`, `ticks`, `anim` bytes, event `tick` and `kind` **equal**; decoded `pos`/`facing` samples and event `dir/x/y` ≤ 1e-3; event `vx/vy` ≤ 1e-2 (tiles per local second, so 60 times a position step) |
| `outcome.notes` | informational. Compare exactly if the port formats beats like the prototype (`Math.round(b * 100) / 100`), or skip them. |

Values in the files that come out of float maths are rounded to 4 decimals
(`Math.round(v * 1e4) / 1e4`, with -0 written as 0). Always compare them with the tolerance, never as
rounded strings. Ticks, substeps, counts and the take inputs are exact.

**Why these tolerances hold.** Scenarios last a few bars, and the exporter's stability check re-runs
every one with all level coordinates and tape samples moved by ±1e-5 tiles (the same recorded
inputs replayed). It fails the export if any event's `(sub, type, tape, id, detail)` changes, if the
outcome changes, or if any sampled position moves by more than 1e-3. All 163 scenarios pass at ±1e-5
and at ±1e-6. So nothing in them sits on a knife-edge (a reach boundary, a tie between two targets,
a footstep stride landing exactly on its threshold, a contact on a substep boundary) at a scale far
above JavaScript/GDScript double-precision differences. Several scenarios were detuned from their
prototype test for this reason (odd waypoint ticks, off-centre positions, a non-round projectile
speed). The exporter's comments mark each one, and its check proves the scenario still shows its
rule. To explain a port mismatch, use `--diagnose <name>` (below).

**Port caution: keep simulation state in `float` (64-bit), not `Vector2`.** Standard Godot builds
store `Vector2` in 32-bit floats. The prototype simulates in doubles (only tape samples are float32).
A port that keeps positions, velocities or spark and projectile state in `Vector2` adds about 1e-6 of
error per operation. That error can grow past 1e-3 over a scenario (a projectile flying for 1000
substeps) and pushes the port toward the knife-edges the stability check guards against. Note that
`ODJson.vec2`, and therefore `LevelDef.start`, laser `from`/`to` and the skeleton's other `Vector2`
level fields, are float32. The goldens tolerate that one-off rounding (it is below 1e-6), but the
simulation should promote those values to `float` pairs on load.

## How to replay a golden

```
level    = LevelDef.from_dict(g.level)
loadout  = ResolvedLoadout.from_dict(g.loadout.resolved)
tapes    = []                                   # tapes available so far, in take order
for k, take in enumerate(g.takes):
    if take.source == "tape":
        tapes.append(ODTape.from_dict(take.tape))
    else:                                       # "inputs": record a live take
        rec = the entry of g.expected.recordings whose .take == k
        sim = ODSim.create_sim(SimConfig(level, loadout, copy of tapes,
                  live = {take.index, take.speed, OD.end_mode_from_name(take.endMode)},
                  bossMemory = rec.bossMemory (null -> none)))
        compare sim.snapshot() with rec.snapshots[0]                    # sub 0
        for each input in take.inputs:
            sim.step_local_tick(PlayerInput from the tuple)
            append sim.drain_events() to the recorded event list
            if sim.sub % 60 == 0: compare sim.snapshot() with the next rec.snapshots entry
        if the last sub was not a multiple of 60, the last rec.snapshots entry is the final snapshot
        compare events with rec.events, sim.outcome() with rec.outcome,
                sim.live_tape() with rec.tape (ODTape.from_dict)
        tapes.append(ODTape.from_dict(rec.tape))     # the GOLDEN tape, not the port's
res = g.expected.resolution
sim = ODSim.create_sim(SimConfig(level, loadout, tapes, bossMemory = res.bossMemory))
compare sim.snapshot() with res.snapshots[0]
while sim.sub < res.horizonSubs:
    sim.step_sub(); collect sim.drain_events()
    if sim.sub % 60 == 0 or sim.sub == res.horizonSubs: compare the snapshot (and threatBeats)
compare events with res.events and sim.outcome() with res.outcome
```

Each stage takes its inputs from the golden. A later take records against the golden tapes of
the earlier ones, and the resolution uses the golden recorded tapes. So a recording mismatch is
reported once, at the recording, instead of spreading through every later stage. A port that wants
an end-to-end check can also resolve with its own recorded tapes. Within tolerance the results must
still agree.

`ODResolve.resolve_encounter` stores a frame every 4 substeps. Comparing the frames whose `sub` is a
multiple of 60, plus the last frame, is equivalent to the loop above. The exporter asserts that its
own loop matches the prototype's `resolveEncounter` exactly (events, outcome and every sampled
frame).

Optional extra checks the files support:
- `g.loadout.gear` is not null: `LoadoutRules.resolve_loadout(gear)` must equal `g.loadout.resolved`
  (`to_dict()` JSON equality). That covers the catalogue and `combineMods`.
- `g.bossMemoryFrom` is not null: `BossMemoryLib.build_boss_memory(level, the tapes available at
  that stage whose index is in bossMemoryFrom)` must equal that stage's `bossMemory` (use 1e-6 for the
  float32 sample values).

## File format, field by field

All keys are the prototype's camelCase. Optional keys are left out when absent and are never `null`.
The exceptions are the top-level `loadout.gear` and `bossMemoryFrom` and each stage's `bossMemory`:
those are always present and are `null` when unused.

### Top level

| Key | Type | Meaning |
|---|---|---|
| `format` | int | File format version, `1`. |
| `name` | string | Scenario id; the file is `<name>.json`. |
| `description` | string | What the scenario shows. |
| `covers` | string[] | Requirement ids, scenario letters and prototype test names it reproduces. |
| `level` | LevelDef | The full level, in the same JSON shape as `data/levels/*.json` (types.ts `LevelDef`). Synthetic levels come from the prototype test helper `makeLevel` (id `test-level`, bpm 120, `startFacing: 0` written out). The `sandbox-*` scenarios embed the shipped sandbox level verbatim. |
| `loadout.resolved` | ResolvedLoadout | The numbers the sim uses (types.ts `ResolvedLoadout`): `loadout` (slot → id), `mods` (all 16 StatMods keys), `abilities`, `melee`, `ranged`. Most scenarios use the prototype test baseline (`tests/helpers/loadout.ts`, ids `base-*`, which are not catalogue items), so always load this, never the ids. |
| `loadout.gear` | Loadout or null | Catalogue gear ids (`data/gear.json`) when the loadout was resolved from the catalogue (`gear-*`, `sandbox-*`); otherwise `null`. |
| `bossMemoryFrom` | int[] or null | Cassette indices whose tapes count as committed and build the boss memory; `null` when the scenario uses no memory. |
| `takes` | Take[] | The cassettes, in the order they are added (see below). May be empty (`clock-empty-run`). |
| `expected.recordings` | Recording[] | One per `inputs` take, in take order. |
| `expected.resolution` | Resolution | The authoritative playback run of all takes. |

### Take

`{"source": "tape", "tape": SerializedTape}` is a trajectory take, played back as recorded.
`SerializedTape` is exactly the prototype's `serializeTape` format, which `ODTape.from_dict` reads:
`{v: 1, index, speed, endMode, ticks, pos, facing, anim, events}`. Here `pos`, `facing` and `anim`
are little-endian float32, float32 and uint8 arrays in standard base64. `events` are tuples
`[tick, kindIndex, dir, x, y, vx, vy]`, with kindIndex in `ActionKind.ALL` order (light, heavy,
dodge, ranged, interact, ability). Most of these tapes were built from waypoints (the prototype's
`pathTape`), so they need not start at `level.start`.

`{"source": "inputs", "index", "speed", "endMode", "inputs"}` is a live take. It is recorded by
feeding the player controller one input per local tick:

| Key | Type | Meaning |
|---|---|---|
| `index` | int 0..3 | Cassette. |
| `speed` | 0.5, 1, 2 or 4 | Tape speed. |
| `endMode` | "stop", "repeat" or "reverse" | End behaviour of the recorded tape. |
| `inputs` | `[moveX, moveY, aim, buttons][]` | One `PlayerInput` per local tick, tick 0 first. `moveX`, `moveY` and `aim` (radians) are exact doubles. `buttons` lists the edge-triggered buttons pressed on that tick (any of `"light"`, `"heavy"`, `"dodge"`, `"ranged"`, `"interact"`, `"ability"`); the rest are false. |

The take is exactly `inputs.length` local ticks long. A few takes stop short of the level's
allowance (`ability-manual-desync-record` at 160, `ability-phase-dodge-*` at 40,
`ability-kill-refresh*` at 60), and their recorded tape then has that many ticks (the prototype's
`liveTape()` of a partial take). Inputs that came from closed-loop bots (`ghost-final-tape-edge`,
`sandbox-*`) are written open-loop: replay them verbatim and do not re-run the bot.

### Recording (`expected.recordings[i]`)

| Key | Type | Meaning |
|---|---|---|
| `take` | int | Index into `takes` of the `inputs` take this records. |
| `bossMemory` | BossMemory or null | Memory the recording sim was given: built from the `bossMemoryFrom` tapes available before this take, or `null`. |
| `tape` | SerializedTape | `liveTape()` after the last input: the recorded tape. Later stages use this. |
| `outcome` | Outcome | `sim.outcome()` of the provisional live run after the last input. |
| `events` | Event[] | Every event drained during the recording, in order. |
| `snapshots` | Snapshot[] | `sim.snapshot()` at sub 0, after every local tick that leaves `sim.sub` a multiple of 60, and after the last tick if that was not already sampled. At 1x that is every 15 local ticks; at 0.5x (8 substeps per tick), every 120 substeps. The live self has `live: true`, and once dead it is `life: "recGhost"`. |

### Resolution (`expected.resolution`)

| Key | Type | Meaning |
|---|---|---|
| `bossMemory` | BossMemory or null | Memory given to the playback run (`SimConfig.bossMemory`). |
| `horizonSubs` | int | `level.horizonBars × 4 × (14400 / bpm)`. The run steps exactly this many substeps. |
| `outcome` | Outcome | `sim.outcome()` at the horizon: the authoritative result. |
| `events` | Event[] | Every event of the run, in order (`Resolution.events`). |
| `snapshots` | Snapshot[] | `sim.snapshot()` at sub 0, after every substep that leaves `sim.sub` a multiple of 60, and at `horizonSubs` (`Resolution.frames` filtered to those subs). |

### BossMemory

This is types.ts `BossMemory`, verbatim. It is an input, so it is not rounded:
`{observed: [{tape, speed, samples: [{beat, x, y}], actions?: [{beat, x, y, kind}]}]}`. Pass it to
the sim as given.

### Outcome

`{win, objectiveComplete, survivors: int[], reason?: "objective" | "noSurvivor", notes: string[]}`.
`reason` is absent on a win.

### Event

`{sub, type, x, y, tape?, id?, dir?, power?, detail?}` is the prototype's `SimEvent` with `x`, `y`,
`dir` and `power` rounded. `sub` is the substep being simulated, the interval [sub, sub+1). An event
at `sub` therefore appears in the drain after the substep that ends at `sub + 1`.
`SimEvent.from_dict` reads it. Footstep events (`step`) are included, and their `detail` is the
self's life state.

### Snapshot

```
{ sub, beat,
  actors:      [{tape, live, x, y, facing, anim, life, synced, iframes,
                 phase: {tick, dir, traversal, ended}, spark?: {x, y}}],
  enemies:     [{id, type, x, y, hp, maxHp, alive, state, target?, shield?,
                 bossPhase?, bossRecall?, bossRecallTape?, bossRecallAt?: {x, y}}],
  projectiles: [{id, owner: {tape} | {enemy}, archetype, x, y, z, dir, targetId?}],
  mechs:       [{id, kind, on, t?, warn?, dir?, reach?, firing?}],
  objective:   {complete, progress, survivors},
  threatBeats?: number[] }
```

These are the prototype's `FrameSnapshot` fields, minus three that are too sensitive or too derived
to pin down: actor `vx/vy` (a velocity estimate that multiplies position error by 240), enemy
`facing` (undefined for a zero vector) and enemy `stateT`. Lists keep the sim's order: actors by
tape index, enemies in entity order, projectiles in spawn order (with their numeric spawn `id`), and
mechs in mechanism order (classic mechanisms first, then traps in entity order; the trap fields
`warn` / `dir` / `reach` / `firing` follow docs/TRAPS.md "Snapshot fields" and never appear on a
classic mechanism). Trap state changes are events of type `trap` (`id` = trap id, `detail` =
`<kind>:<what>`). The jitter check also moves sensor ends and magnet centres; tile cells (spikes,
crushers, belts, launcher and nozzle tiles) are geometry and stay put. `threatBeats` is present only when the loadout has `beatSight`
(`ability-beat-sight`, `gear-abilities-catalogue`). It holds `sim.threat_beats()` (default 8-beat
look-ahead), taken at the same instant as the snapshot.

### index.json

`{format: 1, sampleSubs: 60, decimals: 4, scenarios: [{name, file, description, covers,
takes: ["tape" | "inputs", ...], win, events}]}`, in export order. A golden runner can iterate it
instead of listing the directory; the format suite checks that the two agree.

## Exporter options

```
cd prototype
npx vite-node scripts/export-goldens.ts                       # export, scenario checks, ±1e-5 stability check
npx vite-node scripts/export-goldens.ts -- --fast             # export and scenario checks only
npx vite-node scripts/export-goldens.ts -- --jitter 1e-6      # stability check at another scale
npx vite-node scripts/export-goldens.ts -- --diagnose <name>  # where a jittered run departs from the base run (writes nothing)
```

The export exits non-zero if a scenario check fails or a scenario is unstable. At ±1e-4 (a hundred
times float32 rounding at map scale), 7 scenarios have a footstep or another event move by one
substep. That is expected at that scale. It is also why the simulation must not hold its state in
32-bit floats.

## Scenarios (163)

Takes: `T` = trajectory tape, `I` = recorded from inputs. Result is the authoritative outcome.

| Scenario | Takes | Result | Covers |
|---|---|---|---|
| `clock-record-0_5x` | I | win | TEST-01, TIME-02, TIME-03, kernel clock |
| `clock-record-1x` | I | win | TEST-01, TIME-02, TIME-03, kernel clock |
| `clock-record-2x` | I | win | TEST-01, TIME-02, TIME-03, kernel clock |
| `clock-record-4x` | I | win | TEST-01, TIME-02, TIME-03, kernel clock |
| `clock-plate-2x-record-replay` | I | win | TEST-02 |
| `record-busy-death` | I | fail | kernel determinism, record → resolve reproduction, GHOST-01 |
| `record-two-takes-busy` | II | fail | TEST-03, TEST-04, kernel determinism |
| `record-calm-kill-win` | I | win | kernel determinism, AI-01, win with one survivor |
| `mech-dead-signal-opens-door` | I | win | dead:<enemy> signal, LEVEL signal expressions |
| `clock-empty-run` |  | fail | TEST-06 |
| `tapemode-stop` | T | fail | PLAY-05, OPEN-05 |
| `tapemode-repeat` | T | win | TEST-25, Scenario G |
| `tapemode-reverse` | T | win | TEST-26, PLAY-06 |
| `tapemode-mixed-four` | TTTT | win | TIME-03, PLAY-05, PLAY-06, every speed and end mode |
| `tapemode-record-4x-reverse` | I | win | TIME-03, PLAY-06, record at 4x |
| `ghost-scenario-c` | I | fail | Scenario C, TEST-07, TEST-09, TEST-10, GHOST-01..05 |
| `ghost-recghost-blocked-by-door` | I | fail | TEST-08, GHOST-02 |
| `ghost-rescue` | II | win | TEST-11, rescue, Scenario C |
| `ghost-scenario-d-alone` | T | fail | Scenario D |
| `ghost-scenario-d` | TT | win | Scenario D, TEST-12, GHOST-05, win with one survivor |
| `survivors-one-wins` | TTTT | win | TEST-23, REC-07, win with one survivor |
| `survivors-none-fails` | TT | fail | TEST-24, REC-07, fail with none |
| `ghost-final-tape-edge` | II | fail | OPEN-07, REC-06, GHOST-03 |
| `desync-scenario-i-detour` | TT | win | Scenario I, TEST-13, TEST-14, DESYNC-01..05, detour recovery |
| `desync-scenario-i-reopened` | TT | win | Scenario I, reopened route, DESYNC-04 |
| `desync-no-route` | TT | fail | DESYNC-03, TEST-15 |
| `desync-route-reopened-by-other` | TT | win | TEST-15, Scenario J, reopened route |
| `desync-repeat-cut-spark` | TT | fail | DESYNC, What a tape is, repeat |
| `desync-harmless-invulnerable` | TT | fail | TEST-16, DESYNC-07, AI-07 targeting policy |
| `desync-scenario-j-control` | T | fail | Scenario J, TEST-17 |
| `desync-scenario-j` | TT | win | Scenario J, DESYNC-02..07, detour recovery |
| `desync-scenario-j-no-detour` | TT | fail | TEST-17, Scenario J |
| `enemy-grunt-strike` | T | fail | AI-01, AI-07, HEALTH-01 |
| `enemy-grunt-target-switch` | TT | fail | TEST-18, AI-02..04 |
| `combat-knockback-alone-whiff` | T | fail | TEST-19 |
| `combat-knockback-changes-later-hit` | TT | win | TEST-19, MOM-05, knockback changing later hits |
| `momentum-0_5x-stand` | T | fail | TEST-20, MOM-01..04 |
| `momentum-1x-stand` | T | fail | TEST-20, MOM-01..04 |
| `momentum-2x-stand` | T | fail | TEST-20, MOM-01..04 |
| `momentum-1x-into` | T | fail | TEST-20, MOM-01..04 |
| `momentum-1x-away` | T | fail | TEST-20, MOM-01..04 |
| `dodge-iframes-pass-through` | T | fail | TEST-21, COMBAT-04 |
| `dodge-too-early-dies` | T | fail | TEST-21, COMBAT-04, fail with none |
| `dodge-record-live-iframes` | I | fail | TEST-21, COMBAT-04, record |
| `momentum-wall-1x-stand-light` | I | fail | Scenario K, MOM-01..04, momentum thresholds |
| `momentum-wall-1x-run-heavy` | I | fail | Scenario K, MOM-01..04, momentum thresholds |
| `momentum-wall-2x-stand-heavy` | I | fail | Scenario K, MOM-01..04, momentum thresholds |
| `momentum-wall-2x-run-heavy` | I | win | Scenario K, MOM-01..04, momentum thresholds |
| `mech-door-closes-on-playback` | TT | win | DESYNC-01, doors never delete a body |
| `mech-door-closes-on-live` | TI | win | doors never delete a body, record |
| `mech-door-pushes-enemy` | T | fail | doors never delete a body |
| `mech-interact-nothing` | T | win | interactFail |
| `mech-plate-holds-laser-off` | TT | win | plates, lasers, signals |
| `mech-laser-kills` | T | fail | lasers, fail with none |
| `ability-laser-proof` | T | win | laserProof, every ability |
| `mech-heavy-plate-needs-heavystep` | T | win | plates, heavyStep |
| `ability-heavy-step` | T | win | heavyStep, every ability |
| `mech-dead-ghost-no-plate` | T | fail | GHOST-05, plates |
| `objective-reach-win` | T | win | reach objective, exit |
| `objective-reach-pass-by-fails` | T | fail | reach objective, exit |
| `objective-core-weak-clang` | T | fail | activate objective, cores |
| `objective-core-activated` | T | win | activate objective, cores |
| `enemy-stalker-alone` | T | fail | AI-01, AI-02, stalker |
| `enemy-stalker-farthest` | TT | fail | AI-01, AI-02, AI-07, stalker |
| `enemy-shielder-alone-clangs` | T | fail | Scenario A, AI-05, shielder |
| `enemy-shielder-pair-hit` | TT | fail | Scenario A, AI-05, shielder |
| `enemy-shielder-two-pairs-kill` | TTT | win | Scenario A, shielder two-self kill, MOM-05 |
| `enemy-shielder-same-substep-kill` | TT | win | Scenario A, shielder two-self kill |
| `enemy-shielder-blocks-bolts` | T | fail | shielder, turret |
| `enemy-brute-three-lights` | T | win | HEALTH-02, MOM-05, brute |
| `enemy-brute-poise-broken` | T | fail | MOM-05, brute |
| `enemy-grunt-shoved` | T | fail | MOM-05, knockback |
| `enemy-brute-running-heavy` | T | win | MOM-01..04, brute |
| `enemy-brute-slam-wide` | TT | fail | AI-04, AI-07, brute, fail with none |
| `enemy-brute-holds-heavy-plate` | T | fail | brute, plates |
| `enemy-drone-backs-off` | T | fail | AI-01, drone |
| `enemy-drone-hovers-over-void` | T | fail | AI-01, drone, void |
| `enemy-drone-fire` | TTT | fail | AI-06, AI-07, drone |
| `enemy-drone-two-hits` | T | win | HEALTH-02, drone |
| `boss-coordinated-win` | TT | win | BOSS-03, HEALTH-03, boss fight without memory |
| `boss-alone-armour` | T | fail | BOSS-03, AI-07 |
| `boss-phases` | TT | fail | HEALTH-03, AI-07, shock projectiles |
| `boss-memory-none` | T | fail | BOSS-01, boss fight without memory |
| `boss-memory-dwell` | T | fail | BOSS-01, BOSS-02, boss fight with memory |
| `boss-memory-blind-armour` | TT | fail | BOSS-03, boss fight without memory |
| `boss-memory-exploited` | TT | fail | BOSS-02, BOSS-03, boss fight with memory |
| `boss-memory-guard-cancels` | TT | fail | BOSS-02, boss fight with memory |
| `boss-memory-attack-recall` | T | fail | BOSS-02, boss fight with memory |
| `boss-memory-record` | TI | fail | BOSS-01, BOSS-02, record, boss fight with memory |
| `ranged-pierce-line` | T | fail | NEW-04, WEAPON-01, pierce |
| `ranged-pierce-1-stops` | T | fail | NEW-04, pierce |
| `ranged-phase-through-wall` | T | win | NEW-05, phase |
| `ranged-phase-map-edge` | T | win | NEW-05, phase |
| `ranged-burst-wall` | T | fail | NEW-05, burst |
| `ranged-arc-over-wall` | T | win | NEW-05, arc |
| `ranged-arc-blast` | T | fail | arc, blast |
| `ranged-arc-min-range` | T | win | arc, minRange |
| `ranged-burst-fan` | T | fail | burst, WEAPON-01 |
| `ranged-momentum-model` | T | fail | WEAPON-03, momentum model |
| `ranged-door-blocks-straight-shot` | T | fail | NEW-05, doors |
| `ranged-reverse-pass-fires-again` | T | fail | PLAY-06, reverse |
| `missile-scenario-f-alone` | T | fail | Scenario F, TEST-22, NEW-03, missile |
| `missile-scenario-f-target-change` | TT | fail | Scenario F, TEST-22, missile target change |
| `missile-no-retarget` | TT | fail | MISSILE-03, NEW-03 |
| `missile-target-dies-first` | TT | fail | MISSILE-03, NEW-03 |
| `missile-turn-rate` | T | fail | MISSILE-02, missile |
| `missile-no-enemy-straight` | T | win | MISSILE-04, missile |
| `ranged-ghost-launch-gating` | I | fail | GHOST-03, GHOST-05, launch gating |
| `ranged-desynced-launches-nothing` | T | fail | DESYNC-07, launch gating |
| `ranged-synced-launches` | T | fail | launch gating, missile |
| `ability-manual-desync-record` | I | win | manualDesync, every ability, OPEN-11, record |
| `ability-manual-desync-turret` | T | fail | manualDesync, DESYNC-07 |
| `ability-manual-desync-paired` | T | win | manualDesync, beat signals |
| `desync-beat-door` | T | win | DESYNC-04, beat signals |
| `ability-low-profile` | T | fail | lowProfile, every ability |
| `ability-low-profile-control` | T | fail | lowProfile, turret |
| `ability-loudmouth` | T | fail | loudmouth, every ability |
| `ability-beat-sight` | T | fail | beatSight, every ability |
| `ability-phase-dodge-record` | I | win | phaseDodge, every ability, record |
| `ability-phase-dodge-blocked` | I | win | phaseDodge, dodge |
| `ability-phase-dodge-replayed-without-gear` | T | win | phaseDodge, DESYNC-01 |
| `ability-slide-strike` | T | fail | slideStrike, every ability, reverse |
| `ability-parry` | T | win | parry, every ability |
| `ability-parry-control` | T | fail | parry, turret |
| `ability-kill-refresh` | I | win | killRefresh, every ability, record |
| `ability-kill-refresh-control` | I | win | killRefresh, dodge cooldown |
| `gear-ranged-mixtape-rocket` | I | fail | WEAPON-01..03, every ranged archetype (missile), catalogue gear |
| `gear-ranged-needle-rail` | I | fail | WEAPON-01..03, every ranged archetype (pierce), catalogue gear |
| `gear-ranged-bleed-emitter` | I | fail | WEAPON-01..03, every ranged archetype (phase), catalogue gear |
| `gear-ranged-bass-drop` | I | fail | WEAPON-01..03, every ranged archetype (arc), catalogue gear |
| `gear-ranged-static-spray` | I | fail | WEAPON-01..03, every ranged archetype (burst), catalogue gear |
| `gear-melee-splice-blade` | I | fail | WEAPON-04, COMBAT-01..03, catalogue gear |
| `gear-melee-stylus-shiv` | I | fail | WEAPON-04, COMBAT-01..03, catalogue gear |
| `gear-melee-amp-sledge` | I | fail | WEAPON-04, COMBAT-01..03, catalogue gear |
| `gear-melee-reel-lash` | I | fail | WEAPON-04, COMBAT-01..03, catalogue gear |
| `gear-melee-speaker-knuckles` | I | fail | WEAPON-04, COMBAT-01..03, catalogue gear |
| `gear-melee-vinyl-glaive` | I | fail | WEAPON-04, COMBAT-01..03, catalogue gear |
| `gear-apparel-mods` | I | win | GEAR-01..03, APPAREL-01..03, catalogue gear, combineMods |
| `gear-abilities-catalogue` | I | fail | manualDesync, slideStrike, beatSight, catalogue gear |
| `trap-spikes` | TT | fail | TRAPS spikes, trap signals, trap telegraph, HAZARD_RETICK_BEATS, shielder immune to traps |
| `trap-spikes-dodge` | TT | win | TRAPS spikes, dodge i-frames vs traps |
| `trap-spikes-live` | I | fail | TRAPS spikes, record, recGhost |
| `trap-crusher-stroke` | TTT | fail | TRAPS crusher, crusher push-out, dodge i-frames vs traps, desync blocked by crusher |
| `trap-crusher-desync-recover` | T | win | TRAPS crusher, desync blocked by crusher, DESYNC-02..05 |
| `trap-crusher-live-hold` | I | fail | TRAPS crusher, crusher:hold, record |
| `trap-flame` | TT | win | TRAPS flame, doors are shields, flame reach, HAZARD_RETICK_BEATS |
| `trap-conveyor` | TT | fail | TRAPS conveyor, <id>.rev, trap signals |
| `trap-conveyor-dart-drift` | T | win | TRAPS conveyor, TRAPS dart, floor-height projectiles drift |
| `trap-conveyor-live-ride` | ITI | win | TRAPS conveyor, liveCarry, PlayerController.displace, record, TIME-02 |
| `trap-bumper` | T | fail | TRAPS bumper, MOM-05, MOM-06, wall slam stagger |
| `trap-bumper-live` | II | win | TRAPS bumper, liveCarry, BUMPER_FLIGHT_SUBS, record, TIME-02 |
| `trap-magnet` | T | fail | TRAPS magnet |
| `trap-dart` | TTT | win | TRAPS dart, dart archetype, trap kills count for eliminate |
| `trap-dart-crusher` | T | win | TRAPS dart, TRAPS crusher, muzzle blocked |
| `trap-dart-dodge-parry` | TT | win | TRAPS dart, dodge i-frames vs traps, parry |
| `trap-sensor` | T | fail | TRAPS sensor, trap signals, latch, detects |
| `trap-sensor-relay-chain` | T | win | TRAPS sensor, TRAPS relay, TRAPS crusher, TRAPS conveyor, chained machines |
| `trap-relay-modes` | TTT | win | TRAPS relay, <id>.armed, relay forecast telegraph |
| `trap-machines-vs-enemies` | TT | win | TRAPS puzzle uses, MOM-05, trap kills count for eliminate |
| `trap-spikes-hunter` | T | win | TRAPS spikes, TRAPS puzzle uses |
| `trap-gauntlet` | II | fail | TRAPS all nine kinds, trap determinism, record, liveCarry |
| `sandbox-bot-solo` | I | win | APP-TEST-03, sandbox, catalogue gear, every enemy type (grunt, turret) |
| `sandbox-bot-two-cassettes` | II | win | APP-TEST-03, sandbox, plates, lasers, record against playback |
