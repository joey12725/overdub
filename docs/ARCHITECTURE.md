# OVERDUB — architecture and resolved decisions

OVERDUB is the game described in `docs/requirements.txt` (the "Moxie" requirements bible; the PDF's
legacy appendices are omitted). Reference art is in `docs/reference/*.png`. Read the requirement
chapters relevant to your module before writing code. Requirement ids (TIME-01, GHOST-03, NEW-07 …)
are used in comments and test names.

Stack: TypeScript, Vite, Three.js (orthographic isometric), Web Audio + the vendored Harmonograph
engine (`src/vendor/harmonograph.js`), Vitest. Runs in a desktop browser. No backend.

## Modules and ownership

| Path | Role | May import |
|---|---|---|
| `src/core/types.ts` | Shared data contracts | nothing |
| `src/contracts.ts` | Module facades (`IRenderer`, `IAudio`, `IUi`, `IInput`) | core/types |
| `src/core/**` | Deterministic simulation. Pure TS: no DOM, no `Math.random`, no `Date` | core only |
| `src/content/**` | Levels, gear catalogue, loadout resolution | core/types |
| `src/audio/**` | Harmonograph-driven music, quantised SFX | core/types, contracts, vendor |
| `src/render/**` | Three.js world, Moxie, enemies, FX, cinematic camera | core/types, contracts, three |
| `src/ui/**` | DOM/CSS HUD and menus | core/types, contracts |
| `src/game/**` | Session state machine, input, save, campaign, the main loop; wires everything | all |
| `tests/**` | Vitest suites | all |

Only `src/game` wires modules together. A module that needs something from another module gets it
through the facades in `src/contracts.ts` or through data in `src/core/types.ts`.

## One clock (TIME-01..07)

- The world lives on **master time**, stepped in **substeps** of 1/240 master second (`SUB_HZ`).
- A tape is sampled in **local ticks** of 1/60 local second (`LOCAL_HZ`). While recording, local
  time is wall time, so every tape takes the same real time to record (TIME-02).
- `master = local / speed`. Recording at speed `s` advances the world `4 / s` substeps per local
  tick (8, 4, 2, 1 for 0.5×, 1×, 2×, 4×). So a fast tape sees a slow world, and its recording
  occupies `bars / s` master bars (TIME-03). Nothing is ever stretched.
- Playback: at master substep `k`, tape `j` is at local tick `k · s_j / 4` on its first traversal;
  poses are linearly interpolated between samples. End behaviour then applies (below).
- `level.bpm` is the master tempo. `level.bars` is the local recording allowance.
  `level.horizonBars` is the authored length of the whole encounter in master bars (resolves
  OPEN-02 as "level-authored horizon"; the default authored value is `bars / slowest offered speed`).
- Count-in and the active cassette's own layer are heard at the base tempo in wall time; the rest of
  the world (and the master ruler) visibly runs at `1 / s`.

The live self is simulated **exactly like a playback self**: each local tick the player controller
turns input into the next pose and action events, appends them to the tape, and the world then runs
its substeps reading that pose by the same interpolation playback uses. A take played back against
an unchanged world therefore reproduces what the player saw.

## What a tape is (PLAY-01..06)

A `Tape` is a fixed trajectory (`pos`, `facing`, `anim` per local tick) plus `events` — attempts,
not results. Playback never re-aims and never re-runs player physics. The world owns outcomes.

End behaviour, applied when a tape's `ticks` run out before the horizon:

- **stop** — the self holds its final pose. It stays physically present: solid for plates,
  targetable, killable, and it counts as a survivor (resolves OPEN-05/08 for stop).
- **repeat** — cuts straight back to sample 0 and plays again; events fire again each traversal
  against the current world.
- **reverse** — ping-pongs. On a backward pass each event fires again when the playhead crosses
  its tick, with its recorded direction: a switch toggle toggles again (on → off), a swing or shot
  is a fresh swing or shot (it can hurt again, it never heals; PLAY-06).
- Life and desync state persist across boundaries: a dead tape stays dead for the rest of the run.
  On a repeat cut the projection teleports; a desynced self's spark does not — it must travel.

## Life, ghosts and desync (GHOST-01..06, DESYNC-01..08)

Per run, each self is `alive`, `recGhost` (live take after death) or `ghost` (played-back tape
after death), and independently `synced` or not. Survival is recomputed every run.

| State | Movement | Affects world | Takes hits |
|---|---|---|---|
| live, alive | player physics | yes | yes (one hit kills; HEALTH-01) |
| live, `recGhost` | player physics, walls still block | yes, in this take only | no |
| playback, alive, synced | fixed path | yes | yes |
| playback, `ghost` | fixed path, passes through everything | no | no |
| playback, alive, desynced | projection on fixed path; spark in reachable space | no | no |

- **Desync** happens to a living playback self when its next recorded position is inside solid
  geometry (wall, closed door, unbroken breakable) or the straight step to it is blocked. The
  projection keeps following the tape. A **recovery spark** starts at the last valid position and
  path-finds (A* over walkable tiles, re-planned as doors change) toward the projection at a finite
  speed (`sparkSpeed`, master time, faster than running). It cannot operate anything. It resyncs
  when it is within a small tolerance of the projection with a clear line. No timeout, no teleport,
  no auto-death if it never arrives (DESYNC "do not add one silently").
- Enemies do not target, and cannot hurt, dead ghosts or desynced projections (resolves the
  AI-07 targeting policy). The spark is not a target.
- Selves do not collide with or damage each other (no body blocking, no friendly fire; OPEN-10).
- The live self cannot desync unless gear grants `manualDesync` (OPEN-11).
- `recGhost` effects are real inside that take's sim and nowhere else: every later run replays the
  tape under playback rules, so a door opened only by a ghost stays shut (Scenario C).

## Authoritative result (REC-06, REC-07, OPEN-07)

`resolveEncounter(config)` runs every recorded tape — including the one just recorded — under
playback rules for the whole horizon and returns `{ outcome, frames, events }`. That, and only
that, decides victory: objective latched **and** at least one self `alive` when the horizon ends
(a desynced-but-alive self counts as a survivor; it cannot hold an exit). The cinematic replays
`frames` verbatim, so it can never diverge, re-randomise or re-teach the boss (CINE-04, BOSS).

A level can be won with fewer tapes than it offers: the first combined run that wins, wins.

## Session flow (REC-01..08, UI)

`briefing → setup → countin → recording → review → decision → (setup | cinematic → results)`

- **setup**: choose speed (and end behaviour once unlocked) on the active deck.
- **countin**: "five, six, seven, eight", visual and audible, at base tempo.
- **recording**: `level.bars` of wall-time play. Death does not end the take (GHOST-01).
- **review**: the resolved combined run plays at true master speed. Skippable; a failing run can be
  ended early (REC-08). If the run wins, review is replaced by **cinematic**.
- **decision**: `retryTake` (discard this take, keep committed tapes; REC-04), `commit` (lock it,
  arm the next cassette), `resetAll` (wipe every cassette; the only way to change an older tape;
  REC-05). Nothing is auto-committed.
- Equipment is locked for the attempt; loadouts change between levels only.
- No mid-take tactical pause: pausing during a take aborts the take back to setup (OPEN-21).

## Combat (COMBAT-01..04, MOM-01..06, HEALTH-01..04)

Actions: light, heavy, dodge (i-frames), ranged, interact. All timings are in local ticks and come
from the equipped weapon, so tape speed changes how long they occupy master time.

Momentum has one cause and is counted once:

```
approach = clamp(dot(localVelocity, swingDir) / runSpeed, -0.5, 1)
momentum = swing.impact × meleeImpactMod × tapeSpeed × (1 + approachBonus × approach)
damage    = floor(momentum × weapon.damageEff × damageMod / DAMAGE_UNIT)     (at least 0)
knockback = min(cap, momentum × weapon.knockbackEff × knockbackMod / enemyMass)
stagger   = momentum × weapon.staggerEff × staggerMod / enemyPoise
```

`tapeSpeed` enters once, as the master-time conversion of both swing and body velocity. Constants
are tuned so a 1× standing light attack kills a 1-hit enemy, a 0.5× one usually does not, and a
2× running heavy breaks the tutorial wall. Knockback really moves enemies; they carry on from where
they land (MOM-05). Enemy hits never displace a recorded self (MOM-06) — they kill it or do nothing.

Ranged weapons record a fixed launch event; the projectile is a world object simulated in master
time (missile: very slow, locks the nearest enemy once at launch, never retargets; pierce: fast,
passes through several enemies; phase: passes walls; arc: lobbed over low cover; burst: short-range
spread). Only an alive, synced self launches.

Enemies are deterministic rule-followers that act on the beat grid (AI-01..07, MUSIC-10). The boss
keeps `BossMemory` built from **committed** tapes only, and telegraphs when it acts on memory.

## Gear (GEAR-01..05, WEAPON-01..04, APPAREL-01..03)

Six slots: helmet, top, pants, shoes, melee, ranged. Items are data (`GearItem`): stat multipliers,
ability flags, weapon definitions. All four cassettes share the loadout. Found on first clear of a
level; never lost; swapped freely between levels. Every mandatory level is beatable with the
baseline loadout.

## Music (MUSIC-01..13)

The vendored Harmonograph engine generates everything. One key/scale/progression per level; four
cassette layers, each with its own formula, running at its tape's speed against the shared chord
clock. Layer state follows the self: dead → the pattern thins and drops to chord tones; desynced →
the phase drifts and the contour simplifies, converging back on resync; reversing → retrograde.
Gameplay sounds are pitched from the current chord and nudged to the nearest sixteenth **late only,
by at most one sixteenth**; gameplay timing is never touched. Enemies keep time but never change a
cassette's function.

## Presentation

- Isometric orthographic camera, cel-shaded with ink outlines, anime-graphic. Upper levels: warm
  sunlit stone, yellow utilities, green overgrowth, pink/purple graffiti (no purple light cast).
  Lower levels: dark rune-inscribed metal, magenta/cyan/violet neon, yellow hazard accents.
- Moxie: yellow headphones, messy dark pigtails, light crop top, dark jacket with yellow lining,
  olive low-rise cargo pants, belt Walkman, chunky high-tops. The four selves are the same Moxie,
  told apart by cassette colour (outline/aura/accent), never by redesign.
- HUD: four persistent cassette decks (colour, status, speed readout, spinning reels, end mode,
  life/sync state) and a continuous master beat ruler with one lane per cassette, visible while
  recording (UI-01..07, NEW-07..11).
