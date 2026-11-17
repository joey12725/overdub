# The field guide (codex)

An in-game notebook that states every rule the player plans against: what each machine targets and
on which beat, what each trap does to whom, what the tape keeps, how force works, what the gear
does. It exists for requirement AI-04 ("Legibility matters ... strategic, not arbitrary"), for the
closing note of chapter 21 (a failure must be explainable in the game's own terms) and for chapter
09 / Revision 1 (the ranged archetypes). Voice: Moxie's scavenger notebook, terse and dry, written
in the first person, consistent with `docs/story/BIBLE.md`.

Everything here lives in three places:

| Path | What |
|---|---|
| `data/codex/codex.json` | The 35 entries (the text the game shows) |
| `data/codex/codex.gd` | `class_name Codex`: loads the JSON, tracks unlocks, no nodes, no file writes |
| `data/codex/sources.json` | 202 factual claims, each with the source file, line and quoted source text |
| `data/codex/check_sources.py` | Re-checks every claim against its source; validates `codex.json` |
| `data/codex/codex_selfcheck.gd` | Headless Godot check of `Codex` and the unlock API |
| `assets/codex/<illustration>.png` | 30 plates, 1024x1024, 256-colour PNG, no lettering |

## Data

`codex.json` has `groups` (Machines, Traps, Tape, Force, Gear, in display order), `entries`, a
`baseline` block of footnotes the menu should print once (which blade the hit numbers assume, how
beats are counted, that a room can re-time a machine) and `lockedText` for a page not yet unlocked.

Each entry:

| Field | Meaning |
|---|---|
| `id` | Stable id; this is what the save file stores |
| `group` | One of the group ids |
| `title` | Page heading |
| `rule` | The rule in one line, stated exactly |
| `notes` | Two or three true consequences of the rule a player can exploit (never a hint to a specific room) |
| `numbers` | `[{label, value}]`, in beats, tiles and seconds; never ticks |
| `unlock` | `{ "any": [condition, ...] }`; the page unlocks when any one condition is met |
| `illustration` | Plate id: `res://assets/codex/<illustration>.png` (the five ranged-archetype pages and the Shots page share `gear-ranged`) |

Groups and entries:

- **Machines** (7): grunt, stalker, turret, shielder, brute, drone, archivist
- **Traps** (10): spikes, crusher, conveyor, flame, dart, bumper, sensor, relay, magnet, laser
- **Tape** (7): tape-speed, count-in, retry-commit-reset, dying-on-tape, rescue, desync, end-modes
- **Force** (4): momentum, knockback, stagger, breakables
- **Gear** (7): gear-slots, ranged-rule, ranged-missile, ranged-pierce, ranged-phase, ranged-arc, ranged-burst

The game overlays all text. The plates carry none: generated lettering is unreliable, so the plates
are ink drawings with arrows only, and the title, rule, notes and numbers are laid out by the menu.

## Where it appears

1. **Pause menu**: a "Field Guide" item. It opens the guide on the page most relevant to what just
   happened, when there is one: after a failed run, the page for whatever killed the last self
   (`Codex.entry_for_enemy(type)` / `Codex.entry_for_entity(kind)`), otherwise the last page read.
   Opening the guide in a take follows the normal pause rule (a pause during the count-in or a take
   discards the take), so it is intended for setup, decision and review.
2. **Campaign screen**: a "Field Guide" button beside the level list, with a count ("14 / 35") and
   a pip when any page is new (`is_new`).
3. **Failure notes** (chapter 21): where the review names a cause ("struck by brute b2", "burned"),
   the cause should link to its page with the same two lookups.
4. **New-page toast**: when `Codex.unlocked` fires, `UiBase.toast("Field guide: <title>", ...)`.

Suggested page layout (landscape 16:9): the plate on the left at up to 1024 px square; on the right
the title, the `rule` in the largest type, the notes as a hand-annotated list, the numbers as a
two-column table. Locked pages show the title as "???", `lockedText`, and no plate.

## Unlock rules

A page unlocks the first time the player meets the thing, and stays unlocked (saved by id).

| Condition | Met when | Reported by |
|---|---|---|
| `always` | From a fresh save | automatic |
| `enemySeen {enemy}` | A level containing that enemy type opens its briefing | `note_level` / `note_level_dict` |
| `entitySeen {kind}` | A level containing that entity kind opens its briefing | `note_level` / `note_level_dict` |
| `levelStarted {level}` | That level opens its briefing | `note_level` / `note_level_dict` |
| `endModeOffered {modes}` | A level offering any of those end modes opens its briefing | `note_level` / `note_level_dict` |
| `simEvent {event}` | A `SimEvent` of that type happens in a take or a review | `note_sim_event` |
| `storyTrigger {trigger}` | A story bark trigger fires (`docs/story/INTEGRATION.md`, "Barks") | `note_story_trigger` |
| `gearOwned {item}` | The item is in the inventory | `note_gear` |

Where each page first unlocks in the shipped campaign (`data/levels/01..12`), computed from the
level files on 2026-11-16:

| Page | Unlocks |
|---|---|
| tape-speed, count-in, retry-commit-reset, gear-slots, ranged-rule, ranged-missile | from the start |
| grunt, breakables | 01-soft-open |
| momentum, knockback, stagger | 02-hit-harder (or earlier, on the first `clang` / `hit` / `enemyStagger` event) |
| shielder | 04-second-opinion |
| turret, laser | 05-dead-air |
| stalker | 06-crossfire |
| end-modes | 07-out-of-phase |
| spikes, conveyor, relay | 08-loop-pedal |
| crusher, flame | 09-rewind |
| brute, drone, sensor | 10-heavy-rotation |
| archivist, dart | 11-the-archivist |
| dying-on-tape | first `selfDeath` event |
| desync | first `desync` event |
| rescue | first `rescue` or `ghostTake` bark trigger |
| ranged-pierce | owning `needle_rail` (loot of 03-hold-the-door) |
| ranged-burst | owning `static_spray` (loot of 05-dead-air) |
| ranged-arc | owning `bass_drop` (loot of 07-out-of-phase) |
| ranged-phase | owning `bleed_emitter` (loot of 10-heavy-rotation) |
| bumper, magnet | **no campaign level places one yet**; they unlock only in a level that does |

## API (`data/codex/codex.gd`)

```gdscript
var codex := Codex.new()                       # loads res://data/codex/codex.json
codex.load_unlocked(save.codex)                # Array of ids from the save; adds the `always` pages
codex.unlocked.connect(func(id): ...)          # toast + write codex.unlocked_ids() to the save

codex.note_level_dict(level_json)              # or note_level(id, enemy_types, entity_kinds, end_modes)
codex.note_sim_event(ev.type)                  # for every SimEvent of a take or review
codex.note_story_trigger("rescue")             # when the bark trigger fires ("rescue", "ghostTake")
codex.note_gear(inventory_ids)                 # at boot and whenever loot is awarded

codex.groups(); codex.entries_in(group_id); codex.entry(id)
codex.is_unlocked(id); codex.is_new(id); codex.clear_new(id)
codex.illustration_path(id); codex.locked_text(); codex.baseline()
codex.entry_for_enemy("brute"); codex.entry_for_entity("spikes")
codex.entry_count(); codex.unlocked_count(); codex.unlock_all()   # unlock_all: debug menu
```

Every `note_*` call returns the ids it newly unlocked and emits `unlocked` once per id. `Codex`
holds no nodes and writes nothing; persistence belongs to the game's save module.

### Integration steps

1. Save: add `codex: Array[String]` to the save data (default empty). At boot,
   `codex.load_unlocked(save.codex)` then `codex.note_gear(inventory)`. On `unlocked`, store
   `codex.unlocked_ids()` and toast.
2. Session: when a level's briefing opens, `note_level_dict(level_dict)` (or `note_level` with the
   `LevelDef` fields). Wherever sim events are already fanned out to audio (`on_events`), also call
   `note_sim_event(ev.type)` for each. Where the bark system fires `rescue` or `ghostTake`, call
   `note_story_trigger`. After loot in `results`, `note_gear`.
3. UI: a `UiScreen` for the guide, reachable from the pause menu and the campaign screen, built
   from `groups()` / `entries_in()`; plates via `load(codex.illustration_path(id))`.
4. `data/codex/codex.gd` sits in `data/` because that is the directory this module owns. If the
   integrator prefers it under `game/` or `ui/`, move the file; it has no path dependencies other
   than `DATA_PATH`.

## Illustrations

Thirty plates in `assets/codex/`, one per illustration id. All were generated with `bash tools/img
edit` (gpt-image-2.6-sunburst), each given the first finished plate as the style reference and, for
machines and traps, the model renders as subject references:

- Machines: `art/previews/enemies/<type>/` three-quarter, back and isometric renders.
- Traps: `art/previews/traps/pieces/trap_<kind>__upper_iso.png` plus the state crops of
  `art/previews/traps/contact_sheet__upper.png`; the laser from
  `art/previews/kit/pieces/laser_emitter__upper_iso.png`; the breakable wall from the kit renders.
- Tape / Force / Gear diagram plates: `docs/reference/generated/moxie_threequarter.png` and the
  weapon renders where a figure or weapon appears.

Each machine plate shows the model in three-quarter and back view and a small top-down diagram of
its rule (the grunt's arrow goes to the nearer figure, the stalker's past the nearer to the farther,
the turret's sight line stops at a wall, the brute's slam leaves a gap behind it, the drone holds a
ring round its target, the Archivist is struck from behind while watching someone else). Trap plates
show the states (down / warning / raised and so on) and who is and is not affected.

The plates were generated at 1254x1254, scaled to 1024x1024 and reduced to a 256-colour palette
(about 0.9 MB each). They contain no lettering. Rune-like marks on some machines are part of the
models. If a model changes, regenerate only its plate with the same recipe: style reference
`assets/codex/shielder.png` first, then the new renders, and a prompt that ends with the no-text
instruction.

## Re-checking after a tuning change

```
python -I data/codex/check_sources.py              # report: ok / moved / CHANGED, and codex.json validation
python -I data/codex/check_sources.py --relocate   # rewrite line numbers that only moved
python -I data/codex/check_sources.py --table      # regenerate the table below
bash tools/gd script res://data/codex/codex_selfcheck.gd
```

`CHANGED` means the quoted source text is gone, so a rule or number was edited: re-read the source,
correct the entry in `codex.json`, then update `text` and `claim` in `sources.json`. `moved` means
only the line number is stale. The script exits 1 on any `CHANGED` or any invalid entry, so it can
run in CI.

The sources are the reference implementation (`prototype/src/core/**`), `docs/TRAPS.md`,
`docs/ARCHITECTURE.md` and `data/gear.json`. The GDScript port in `core/` is required to match the
prototype tick for tick (golden tests), so the prototype is the single place the numbers are read
from.

Conversions used (`prototype/src/core/types.ts:21-23`): the world advances in substeps of 1/240
second (`SUB_HZ`); a take records at 60 ticks per second of its own clock (`LOCAL_HZ`), which is the
unit of the gear cooldowns ("60 ticks" is one second of tape); a beat is 60 / bpm seconds; one tile
is one world unit. Wind-ups and windows that the source gives in beats are quoted in beats; speeds are
in tiles per second of world time.

## Claims table

Every factual claim in the guide, with the file and line it was read from (as of 2026-11-16; all
202 verified `ok` by `check_sources.py`).

| Entry | Claim | Source |
|---|---|---|
| `grunt` | Targets the nearest targetable self | `prototype/src/core/enemies/grunt.ts:26` |
| `grunt` | Re-targets on every beat, not while winding up or recovering | `prototype/src/core/enemies/grunt.ts:52` |
| `grunt` | Winds up only if the target is within reach exactly one telegraph before a grid beat; facing locks then | `prototype/src/core/enemies/grunt.ts:83` |
| `grunt` | Strike arc 120 degrees | `prototype/src/core/enemies/grunt.ts:19` |
| `grunt` | Strike hits selves within reach + body radius (0.9 + 0.3) | `prototype/src/core/enemies/grunt.ts:31` |
| `grunt` | hp 1, speed 2.2, every 2 beats offset 0, reach 0.9, telegraph 0.5 beat | `prototype/src/core/tuning.ts:281` |
| `grunt` | Ties go to the lowest tape index | `prototype/src/core/enemies/common.ts:142` |
| `grunt` | Only alive, synced selves are targeted | `prototype/src/core/enemies/common.ts:127` |
| `grunt` | Self run speed 4.5 tiles per local second | `prototype/src/core/tuning.ts:87` |
| `grunt` | Self body radius 0.3 | `prototype/src/core/tuning.ts:86` |
| `grunt` | Baseline light impact 1.0 / heavy 1.8 (Splice Blade) | `data/gear.json:390` |
| `stalker` | Picks the farthest targetable self | `prototype/src/core/enemies/stalker.ts:174` |
| `stalker` | Re-picks only on bar lines | `prototype/src/core/enemies/stalker.ts:176` |
| `stalker` | Keeps its quarry once within 2.5 tiles | `prototype/src/core/enemies/stalker.ts:148` |
| `stalker` | Re-picks after each strike | `prototype/src/core/enemies/stalker.ts:180` |
| `stalker` | Lunge arc 90 degrees | `prototype/src/core/enemies/stalker.ts:144` |
| `stalker` | hp 1, speed 3.6, every 2 beats offset 1, reach 0.9, telegraph 0.5 beat | `prototype/src/core/tuning.ts:282` |
| `turret` | hp 1, immovable, never staggers, every 2 beats offset 0, range 12, telegraph 1 beat, bolt 6 tiles/s | `prototype/src/core/tuning.ts:283` |
| `turret` | Chooses only at one telegraph before a grid beat; otherwise does nothing | `prototype/src/core/enemies/turret.ts:79` |
| `turret` | Nearest self in range, in sight, inside its aim arc | `prototype/src/core/enemies/turret.ts:39` |
| `turret` | Tracks its target while telegraphing | `prototype/src/core/enemies/turret.ts:70` |
| `turret` | Line of sight uses projectile solidity (walls and closed doors block, low barriers do not) | `prototype/src/core/enemies/turret.ts:35` |
| `turret` | A bolt strikes other enemies: 1 damage, no knockback, 0.25 s stagger | `prototype/src/core/projectiles.ts:353` |
| `turret` | A bolt never hits the enemy that fired it | `prototype/src/core/projectiles.ts:264` |
| `turret` | A bolt passes a self inside dodge i-frames | `prototype/src/core/projectiles.ts:333` |
| `shielder` | hp 2, speed 1.8, every 4 beats offset 0, reach 0.9, telegraph 0.75 beat | `prototype/src/core/tuning.ts:284` |
| `shielder` | Shield window 1 beat | `prototype/src/core/tuning.ts:291` |
| `shielder` | A hit from a different self inside the window lands and the shield returns | `prototype/src/core/enemies/shielder.ts:66` |
| `shielder` | Hits from anything that is not a self clang and do not pop | `prototype/src/core/enemies/shielder.ts:64` |
| `shielder` | Walks at the nearest self, re-picked every beat | `prototype/src/core/enemies/shielder.ts:49` |
| `brute` | hp 3, mass 3, poise 6, speed 1.4, every 4 beats offset 2, reach 1.4, telegraph 1.5 beats | `prototype/src/core/tuning.ts:285` |
| `brute` | Slam arc 240 degrees | `prototype/src/core/enemies/brute.ts:22` |
| `brute` | Recovers for 1 beat after a slam | `prototype/src/core/enemies/brute.ts:24` |
| `brute` | Hits under momentum 3 keep their damage but lose knockback and stagger | `prototype/src/core/enemies/brute.ts:49` |
| `brute` | Poise threshold: momentum 3 | `prototype/src/core/enemies/brute.ts:29` |
| `brute` | Heavy body: holds heavy pressure plates | `prototype/src/core/enemies/brute.ts:44` |
| `brute` | Heavy plates need a heavy body | `prototype/src/core/mechanisms.ts:341` |
| `drone` | hp 2, mass 0.7, speed 2.5, every 2 beats offset 1, range 8, telegraph 0.5 beat, bolt 5 tiles/s | `prototype/src/core/tuning.ts:286` |
| `drone` | Keeps 5 tiles from its target | `prototype/src/core/tuning.ts:293` |
| `drone` | Comfort band of half a tile either side | `prototype/src/core/enemies/drone.ts:32` |
| `drone` | Fires half a beat off its grid | `prototype/src/core/enemies/drone.ts:36` |
| `drone` | Aim locks at telegraph start | `prototype/src/core/enemies/drone.ts:149` |
| `drone` | Pushes from every self inside the comfort distance add up | `prototype/src/core/enemies/drone.ts:172` |
| `drone` | Hover collision: only shot-blocking tiles (walls, closed doors) stop it | `prototype/src/core/enemies/drone.ts:51` |
| `drone` | Hovering bodies never press plates | `prototype/src/core/mechanisms.ts:340` |
| `archivist` | hp 40, every 4 beats, reach 2.2, radius 0.9, telegraph 2 beats | `prototype/src/core/tuning.ts:287` |
| `archivist` | Attention is the nearest self, re-chosen each beat when not committed | `prototype/src/core/enemies/boss.ts:167` |
| `archivist` | Hits from the self holding its attention clang | `prototype/src/core/enemies/boss.ts:369` |
| `archivist` | Hits must land on the back half | `prototype/src/core/enemies/boss.ts:370` |
| `archivist` | Hits from non-selves (traps, bolts) clang | `prototype/src/core/enemies/boss.ts:368` |
| `archivist` | Never shoved; staggers only from momentum 4+ | `prototype/src/core/enemies/boss.ts:387` |
| `archivist` | Stagger threshold: momentum 4 | `prototype/src/core/enemies/boss.ts:83` |
| `archivist` | Cleave arc 150 degrees | `prototype/src/core/enemies/boss.ts:68` |
| `archivist` | Cleave reach = radius + reach (3.1), plus the self body radius when it lands (3.4) | `prototype/src/core/enemies/boss.ts:129` |
| `archivist` | Volley instead of cleave when its attention is beyond cleave range | `prototype/src/core/enemies/boss.ts:354` |
| `archivist` | Volley is 3 bolts | `prototype/src/core/enemies/boss.ts:70` |
| `archivist` | From phase 2 every other attack is a sweep | `prototype/src/core/enemies/boss.ts:352` |
| `archivist` | Sweep range 6 tiles | `prototype/src/core/enemies/boss.ts:74` |
| `archivist` | Sweep passes a self in i-frames | `prototype/src/core/enemies/boss.ts:263` |
| `archivist` | Phase 3 at one third health (phase 2 at two thirds on the next line) | `prototype/src/core/enemies/boss.ts:117` |
| `archivist` | Phase 3 halves the attack period | `prototype/src/core/enemies/boss.ts:143` |
| `archivist` | Memory strike telegraph 2 beats | `prototype/src/core/enemies/boss.ts:79` |
| `archivist` | Memory strike radius 1.25 tiles (+0.3 body radius) | `prototype/src/core/enemies/boss.ts:80` |
| `archivist` | During a memory strike its attention is the remembered tape | `prototype/src/core/enemies/boss.ts:161` |
| `archivist` | A memory strike whose start passes while it is staggered or busy is dropped | `prototype/src/core/enemies/boss.ts:328` |
| `archivist` | A dwell is staying within 0.75 tiles | `prototype/src/core/bossMemory.ts:27` |
| `archivist` | ...for at least 2 beats | `prototype/src/core/bossMemory.ts:29` |
| `archivist` | Remembers light, heavy and ranged attempts | `prototype/src/core/bossMemory.ts:24` |
| `archivist` | Memory is rebuilt only on commit and reset | `prototype/src/game/session.ts:560` |
| `archivist` | Memory is built only from committed tapes | `prototype/src/core/bossMemory.ts:5` |
| `spikes` | Kills vulnerable selves on a raised cell; i-frames protect | `docs/TRAPS.md:133` |
| `spikes` | Raised spikes block nothing | `docs/TRAPS.md:132` |
| `spikes` | Hovering enemies are not touched | `prototype/src/core/traps/system.ts:678` |
| `spikes` | Damage 1 | `prototype/src/core/traps/tuning.ts:31` |
| `spikes` | Enemies are hit on contact and after each full beat of contact | `prototype/src/core/traps/tuning.ts:27` |
| `spikes` | Hazard hits are environment strikes (so shields and boss armour block them) | `prototype/src/core/traps/system.ts:638` |
| `spikes` | Warning ramps over 1 beat before a beat-timed activation | `prototype/src/core/traps/tuning.ts:20` |
| `crusher` | Stroke damage 3 | `prototype/src/core/traps/tuning.ts:34` |
| `crusher` | Retract takes 60 substeps (0.25 s), solid and harmless | `prototype/src/core/traps/tuning.ts:36` |
| `crusher` | On the stroke all cells become solid like a closed door; selves on them die unless in i-frames | `docs/TRAPS.md:179` |
| `crusher` | A playback self whose path enters an extended piston desyncs | `docs/TRAPS.md:198` |
| `conveyor` | Default speed 2 tiles per master second | `prototype/src/core/traps/tuning.ts:39` |
| `conveyor` | Carries grounded enemies, the live self, floor-height projectiles | `docs/TRAPS.md:236` |
| `conveyor` | Does not carry playback selves, sparks, ghosts, drones, turrets | `docs/TRAPS.md:239` |
| `conveyor` | At 2x the belt feels half as fast | `docs/TRAPS.md:242` |
| `flame` | Jet is cut at the first shot-blocking tile; low barriers do not stop it | `docs/TRAPS.md:285` |
| `flame` | laserProof does not protect | `docs/TRAPS.md:290` |
| `flame` | Burns drones; bodies do not shield | `docs/TRAPS.md:291` |
| `flame` | Damage 1 | `prototype/src/core/traps/tuning.ts:41` |
| `dart` | Fires every 2 beats by default | `prototype/src/core/traps/tuning.ts:44` |
| `dart` | Dart speed 8 tiles per master second | `prototype/src/core/traps/tuning.ts:46` |
| `dart` | 1 damage, 0.25 s stagger, no knockback, and the dart stops | `prototype/src/core/traps/dart.ts:42` |
| `dart` | Hazard stagger 0.25 s | `prototype/src/core/traps/tuning.ts:29` |
| `dart` | Stops at walls, closed doors, unbroken breakables, extended crushers; flies over low barriers | `docs/TRAPS.md:333` |
| `bumper` | Default throw 3 tiles for mass 1 | `prototype/src/core/traps/tuning.ts:54` |
| `bumper` | Knockback is power / mass | `prototype/src/core/traps/system.ts:892` |
| `bumper` | Fires on the rising edge of its signal | `docs/TRAPS.md:369` |
| `bumper` | Never launches a playback self, a drone or a turret | `docs/TRAPS.md:379` |
| `sensor` | True while a detected body overlaps the beam; selves must be effective and synced | `docs/TRAPS.md:422` |
| `sensor` | Projectiles, sparks, dead ghosts and desynced projections never trip it | `docs/TRAPS.md:428` |
| `sensor` | Beam is cut at the first shot-blocking tile | `docs/TRAPS.md:425` |
| `relay` | Quantises to 1 beat by default | `prototype/src/core/traps/tuning.ts:66` |
| `relay` | Pulse holds 1 beat by default | `prototype/src/core/traps/tuning.ts:68` |
| `relay` | Ignores triggers while armed or pulsing | `docs/TRAPS.md:470` |
| `relay` | The armed signal is a ready-made telegraph | `docs/TRAPS.md:473` |
| `magnet` | Default pull 1.5 tiles/s for mass 1 | `prototype/src/core/traps/tuning.ts:61` |
| `magnet` | Stops pulling inside 0.6 tiles | `prototype/src/core/traps/tuning.ts:63` |
| `magnet` | Infinite-mass bodies (turrets) are skipped; pull is divided by mass | `prototype/src/core/traps/system.ts:921` |
| `magnet` | Walls do not shield; enemies keep thinking | `docs/TRAPS.md:508` |
| `magnet` | Selves, sparks and projectiles are never pulled | `docs/TRAPS.md:513` |
| `laser` | Kills selves touching the beam while on (laser hit); enemies are not tested | `prototype/src/core/mechanisms.ts:324` |
| `laser` | laserProof ignores laser hits | `prototype/src/core/combat.ts:111` |
| `laser` | Any self hit is skipped inside i-frames (and for non-vulnerable selves, one line above) | `prototype/src/core/combat.ts:110` |
| `laser` | On while its signal expression is true | `prototype/src/core/types.ts:420` |
| `tape-speed` | Speeds are 0.5, 1, 2, 4 | `prototype/src/core/types.ts:27` |
| `tape-speed` | Every recording has the same local length | `prototype/src/core/time.ts:43` |
| `tape-speed` | One traversal spans bars / speed master bars | `prototype/src/core/time.ts:88` |
| `tape-speed` | Fast tape sees a slow world | `docs/ARCHITECTURE.md:34` |
| `tape-speed` | The level lists which speeds are offered | `prototype/src/core/types.ts:710` |
| `tape-speed` | Enemies act on the master beat grid | `docs/ARCHITECTURE.md:143` |
| `count-in` | Count-in is 4 beats | `prototype/src/game/session.ts:55` |
| `count-in` | Count-in is heard at base tempo | `docs/ARCHITECTURE.md:41` |
| `count-in` | Pausing mid-take aborts the take | `prototype/src/game/session.ts:249` |
| `retry-commit-reset` | Retry discards only the pending take | `prototype/src/game/session.ts:547` |
| `retry-commit-reset` | Commit locks the take | `prototype/src/game/session.ts:558` |
| `retry-commit-reset` | Reset wipes every committed tape | `prototype/src/game/session.ts:573` |
| `retry-commit-reset` | Win = objective latched and at least one self alive at the horizon | `docs/ARCHITECTURE.md:97` |
| `retry-commit-reset` | A level can be won with fewer tapes | `docs/ARCHITECTURE.md:101` |
| `retry-commit-reset` | 1 to 4 tapes per level | `prototype/src/core/types.ts:708` |
| `dying-on-tape` | One hit kills; a live self becomes a recording ghost, a playback self a ghost | `prototype/src/core/combat.ts:122` |
| `dying-on-tape` | A dead playback self loses its pending attempts | `prototype/src/core/combat.ts:128` |
| `dying-on-tape` | recGhost: walls still block, affects this take only, takes no hits | `docs/ARCHITECTURE.md:74` |
| `dying-on-tape` | Playback ghost: passes through everything, affects nothing | `docs/ARCHITECTURE.md:76` |
| `dying-on-tape` | Vulnerable (targetable) = synced and alive | `prototype/src/core/actors.ts:160` |
| `dying-on-tape` | Dodge 2.4 tiles | `prototype/src/core/tuning.ts:96` |
| `dying-on-tape` | Dodge i-frames 10 ticks of a 14-tick dodge | `prototype/src/core/tuning.ts:98` |
| `rescue` | Survival is recomputed every run | `docs/ARCHITECTURE.md:69` |
| `rescue` | GHOST-06: a later cassette can prevent an earlier death, and the reverse | `docs/requirements.txt:500` |
| `rescue` | A rescued but obstructed character can still desynchronize | `docs/requirements.txt:577` |
| `desync` | Obstruction: recorded position in solid geometry or the step to it blocked | `prototype/src/core/actors.ts:207` |
| `desync` | Solid for this test: walls, void, low barriers, closed doors, unbroken breakables | `prototype/src/core/actors.ts:200` |
| `desync` | Spark speed 7.5 tiles per master second | `prototype/src/core/tuning.ts:111` |
| `desync` | Resync within 0.35 tiles | `prototype/src/core/tuning.ts:113` |
| `desync` | ...with a clear line | `prototype/src/core/actors.ts:236` |
| `desync` | Can act only when synced | `prototype/src/core/actors.ts:155` |
| `desync` | The spark cannot operate anything | `docs/ARCHITECTURE.md:83` |
| `desync` | No timeout, no teleport, no auto-death | `docs/ARCHITECTURE.md:84` |
| `desync` | A desynced survivor counts but cannot hold an exit | `docs/ARCHITECTURE.md:98` |
| `end-modes` | Three end modes | `prototype/src/core/types.ts:36` |
| `end-modes` | Stop: holds, stays solid for plates, targetable, killable, a survivor | `docs/ARCHITECTURE.md:56` |
| `end-modes` | Repeat: cuts to sample 0, events fire again | `docs/ARCHITECTURE.md:58` |
| `end-modes` | Reverse: events fire again on the backward pass; a toggle toggles again | `docs/ARCHITECTURE.md:60` |
| `end-modes` | On a reverse pass the recorded velocity is negated | `prototype/src/core/combat.ts:187` |
| `end-modes` | Approach is clamped at -0.5 (so 1 + 0.5 x -0.5 = 0.75) | `prototype/src/core/tuning.ts:169` |
| `end-modes` | Dead stays dead; on a repeat cut the spark does not teleport | `docs/ARCHITECTURE.md:63` |
| `end-modes` | The level lists which end modes are offered | `prototype/src/core/types.ts:711` |
| `momentum` | momentum = impact x meleeImpact x tapeSpeed x (1 + approachBonus x approach) | `prototype/src/core/tuning.ts:203` |
| `momentum` | Approach bonus 0.5 | `prototype/src/core/tuning.ts:116` |
| `momentum` | Approach capped at +1 | `prototype/src/core/tuning.ts:170` |
| `momentum` | Damage = floor(momentum x damageEff x damageMod) | `prototype/src/core/tuning.ts:220` |
| `momentum` | Projectiles do not multiply in tape speed | `prototype/src/core/weapons/common.ts:11` |
| `knockback` | knockback = momentum x eff / mass, capped | `prototype/src/core/tuning.ts:233` |
| `knockback` | Cap 3 tiles | `prototype/src/core/tuning.ts:117` |
| `knockback` | Slide lasts 0.18 master seconds | `prototype/src/core/tuning.ts:248` |
| `knockback` | Wall slam: 0.25 s stagger per remaining tile | `prototype/src/core/tuning.ts:250` |
| `knockback` | A shove cancels a telegraph | `prototype/src/core/enemies/common.ts:238` |
| `knockback` | Knockback is applied only if the hit did not kill (the kill branch returns above this line) | `prototype/src/core/combat.ts:173` |
| `knockback` | Enemy hits never displace a recorded self | `docs/ARCHITECTURE.md:136` |
| `stagger` | stagger seconds = momentum x eff / poise | `prototype/src/core/tuning.ts:241` |
| `stagger` | A staggered enemy skips its beat and step logic | `prototype/src/core/enemies/common.ts:76` |
| `stagger` | Stagger cancels any telegraph | `prototype/src/core/enemies/common.ts:267` |
| `stagger` | A longer stagger replaces, never adds to, a shorter one | `prototype/src/core/enemies/common.ts:271` |
| `breakables` | One swing with momentum >= threshold breaks it | `prototype/src/core/mechanisms.ts:236` |
| `breakables` | A weak swing clangs and reports the threshold | `prototype/src/core/mechanisms.ts:243` |
| `breakables` | Tutorial wall threshold 5 | `prototype/src/core/tuning.ts:176` |
| `breakables` | Only melee swings are tested against breakables | `prototype/src/core/combat.ts:277` |
| `gear-slots` | Six slots; items are data | `docs/ARCHITECTURE.md:148` |
| `gear-slots` | All four cassettes share the loadout; found on first clear | `docs/ARCHITECTURE.md:149` |
| `gear-slots` | Never lost; every mandatory level beatable with the baseline | `docs/ARCHITECTURE.md:150` |
| `gear-slots` | Equipment is locked for the attempt | `docs/ARCHITECTURE.md:115` |
| `gear-slots` | Base loadout | `data/gear.json:724` |
| `ranged-rule` | Fixed trigger, simulated projectile | `prototype/src/core/weapons/common.ts:4` |
| `ranged-rule` | Only an alive, synced self launches | `docs/ARCHITECTURE.md:141` |
| `ranged-rule` | A missile keeps flying if its launcher dies or desyncs | `prototype/src/core/weapons/missile.ts:19` |
| `ranged-rule` | Action timings are local ticks, so tape speed scales them in master time | `docs/ARCHITECTURE.md:120` |
| `ranged-missile` | Locks the nearest living enemy once at launch | `prototype/src/core/weapons/missile.ts:50` |
| `ranged-missile` | Never retargets; a dead target just stops the homing | `prototype/src/core/weapons/missile.ts:61` |
| `ranged-missile` | No line of sight needed; walls stop it | `prototype/src/core/weapons/missile.ts:8` |
| `ranged-missile` | Strikes whatever enemy it touches first | `prototype/src/core/weapons/missile.ts:13` |
| `ranged-missile` | Mixtape Rocket numbers (speed 3, range 20, impact 1.5, cooldown 90 ticks) | `data/gear.json:588` |
| `ranged-pierce` | Passes through up to `pierce` enemies and stops at the next | `prototype/src/core/weapons/common.ts:124` |
| `ranged-pierce` | Needle Rail numbers (speed 24, range 12, impact 1, pierce 3, cooldown 75 ticks) | `data/gear.json:615` |
| `ranged-phase` | Always passes walls | `prototype/src/core/weapons/phase.ts:19` |
| `ranged-phase` | Ends at the map edge | `prototype/src/core/weapons/phase.ts:34` |
| `ranged-phase` | Bleedthrough Emitter numbers (speed 6, range 8, impact 1, cooldown 150 ticks) | `data/gear.json:642` |
| `ranged-arc` | Lands at max(minRange, range), cut only by the map edge | `prototype/src/core/weapons/arc.ts:36` |
| `ranged-arc` | Touches no enemy in flight | `prototype/src/core/weapons/arc.ts:40` |
| `ranged-arc` | Walls shield from the blast unless the shell lands in a solid tile | `prototype/src/core/weapons/common.ts:106` |
| `ranged-arc` | Blast pushes away from the centre | `prototype/src/core/weapons/common.ts:108` |
| `ranged-arc` | Bass Drop numbers (speed 7, range 7, minRange 3, blast 1.2, impact 1.3, cooldown 100 ticks) | `data/gear.json:669` |
| `ranged-burst` | Each pellet is its own projectile with full impact | `prototype/src/core/weapons/burst.ts:27` |
| `ranged-burst` | Static Spray numbers (5 pellets, 40 degrees, range 3.5, impact 1, cooldown 60 ticks) | `data/gear.json:697` |
