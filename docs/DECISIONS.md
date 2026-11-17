# OVERDUB — decisions register

Compiled 2026-11-16 from the code, not from memory. Every place where `docs/requirements.txt` (the
bible) leaves a detail OPEN, unselected or "for playtesting", this file says what the game does
today, where that is written, what the main alternative is, and how hard it would be to change. Its
purpose is to let the creator overrule any pick. It does not argue for the picks.

**What "the build" means here.** The rules live in the reference implementation
`prototype/src/` (TypeScript, about 650 tests). The Godot port mirrors it file for file: `core/*.gd`
has the same rules and the same constants (checked for `core/tuning.gd`, `core/sim.gd`,
`core/objective.gd`, `game/session.gd`). Two things existed only in the prototype when this was
written: the traps (`prototype/src/core/traps/`, no `core/` counterpart yet) and the music director
and sound-effect planner (`prototype/src/audio/`; Godot has only `audio/harmonograph/`). Locations
below give the prototype file and symbol first, then the Godot file.

**How each answer was established.** By reading the code named in the "where" column. Six answers
were also run: `art/decisions/probe.ts` (run with `npx vite-node ../art/decisions/probe.ts` from
`prototype/`) resolves small scripted encounters and prints the result; the entries that rely on it
say "probe".

**Statuses** (as asked for):

- **WI** — implemented as the bible's working interpretation.
- **OWN** — the build's own choice. Please confirm or overrule.
- **NONE** — not implemented.
- **CONTRA** — the implementation contradicts the bible. These are defects and come first.

**Switch cost:** *constant* = change a number or a data field; *rule* = change one function and
its tests; *redesign* = touches several systems, the levels or the interface.

---

## 1. Defects: where the implementation contradicts the bible

### D-1 — A winning take is locked in with no retry or commit decision

- **Bible** (ch. 04, "A normal recording cycle"): automatic playback "does not erase the
  requirement to offer a retry/commit decision at the appropriate point … not permission to
  auto-commit irrevocably."
- **Build:** the moment a take ends, the combined run is resolved. If it wins, the session goes
  straight to `cinematic`, then `results`. The only actions offered are `skip`, then `continue` /
  `quit`. The take is shown as `committed` on its deck. The player cannot discard a winning take
  and record a better one, and on a four-cassette level cannot go on to add more cassettes.
- **Evidence:** `prototype/src/game/session.ts` `finishTake()` (`if (outcome.win) … setPhase('cinematic')`),
  `actions()` cases `cinematic` and `results`, `deckStatus()` ("A winning take is final");
  same in `game/session.gd` line 743. Probe: a four-cassette level won on take one reports
  `phaseAfterFirstTake: "cinematic"`, `actions: ["skip"]`, `tapesUsed: 1`.
- **Fix size:** rule. Route a win through the same `decision` phase as a loss (retry / keep), or
  add "retry take" and "keep recording" to the results screen.

### D-2 — The story fixes facts the bible says must not be filled in

- **Bible** (ch. 18, "Supporting people and story scale"): "The conversation did not decide
  whether Moxie knows its true nature at the beginning, whether it is portable, whether she uses
  it, or whether the ending contains a time paradox. None of these should be filled in as
  established story." Also WORLD-05: the time machine's "connection to the Walkman, origin, scale
  and eventual use have not been defined."
- **Build:** `docs/story/BIBLE.md` and `data/story/story.json` decide all of them. Rumour tells
  Moxie it is a time machine from the start; it is a room-sized "master deck", not portable; she
  chooses not to rewind and records a mixtape instead; the Walkman's recording head came out of the
  ruins thirty years earlier. The story document says of itself that it "makes the smallest choice
  that gives the game an ending".
- **Fix size:** redesign of the story text only (no rules depend on it). See also OPEN-25 and
  section 6.

### Probably unintended, inside rules the bible leaves open

These do not contradict a confirmed rule, but they are side effects rather than decisions. They are
recorded as OWN in the register and repeated here so they are not missed.

- **P-1 — On a backward pass, a dodge protects the wrong moment and a swing lands in a different
  place.** Events re-fire when the playhead crosses the tick where the button was pressed, and the
  windup or i-frame window then runs *forward in time* while the body is moving *backward along the
  tape*. Probe, 1× tape, dodge recorded on ticks 40–54, heavy recorded at tick 80: on the forward
  pass the i-frames cover ticks 41–50 (inside the dodge); on the backward pass they cover ticks
  39–30 (the run-up before the dodge), and the visible dodge motion (54→40) has no protection. The
  forward heavy lands with the body at x = 7.31 and momentum 2.67; the backward one lands at
  x = 5.69 (1.6 tiles away) with momentum 1.5. Switch presses have no delay, so they do line up.
  See OPEN-06.
- **P-2 — The recovery spark cannot catch a running fast tape.** Spark speed is 7.5 tiles per
  *master* second. A recorded run is 4.5 tiles per *local* second, which is 9 tiles per master
  second on a 2× tape and 18 on a 4× tape. A desynced 2× or 4× self that keeps running pulls away
  from its spark; it can only resync when the recording slows, stops or doubles back. See OPEN-09.
- **P-3 — The count-in sounds the same at every tape speed.** The bible records a request for a
  "tape-speed-sensitive" count-in. The build counts four beats at the level tempo in wall time for
  every speed; only a line of text under the numbers changes. See OPEN-03.
- **P-4 — Losing window focus discards the take.** Pausing aborts a take (OPEN-21), and the app
  pauses itself when the window is hidden or loses focus (`prototype/src/game/shell.ts` lines
  727–730).

---

## 2. The register at a glance (OPEN-01 … OPEN-25)

| Id | Question | What the build does | Status | Switch cost |
|---|---|---|---|---|
| OPEN-01 | Speed menu; is 4× kept; labels | Four speeds exist (0.5, 1, 2, 4). Each level lists which it offers. Labels "½×", "1×", "2×", "4×". | OWN | constant |
| OPEN-02 | What sets the encounter length | A per-level authored number of master bars (`horizonBars`), by convention bars ÷ slowest offered speed. | OWN | constant per level |
| OPEN-03 | Local bars versus master bars; count-in | One master clock; `master = local ÷ speed`. Ruler is in master beats. Count-in is always at level tempo. | WI (clock) / OWN (count-in) | rule |
| OPEN-04 | Fast/slow tradeoff | Fast hits harder (momentum × speed) and covers less master time. It does not travel less far and is not harder to control. | OWN | rule |
| OPEN-05 | End-of-tape details | A stopped self stays solid, targetable, killable, holds plates, counts as a survivor. Dead stays dead across repeats. Projectiles persist. Spark does not teleport. | OWN | rule |
| OPEN-06 | Reverse event semantics | Every event fires again on the backward pass with its recorded direction. Switches toggle. Shots and swings are fresh. | OWN | rule |
| OPEN-07 | Result after a final recording ghost | Every take is re-run under playback rules; only that run decides. | WI | — |
| OPEN-08 | Survivor check | At the last instant of the encounter. Desynced-but-alive counts. Stopped counts. An exit is needed only on "reach" levels. | OWN | rule |
| OPEN-09 | Recovery tuning | 7.5 tiles/master s, no acceleration, A* route, resync within 0.35 tiles with a clear line. No route: it waits for ever. | OWN | constant |
| OPEN-10 | Collision permissions | Selves pass through each other and through enemies. No friendly fire. An enemy bolt stops in the first vulnerable self. Enemy bodies never cause desync. | OWN | rule |
| OPEN-11 | Can the live player desync | Only with one gear item (a manual toggle). Never from the environment. | OWN | rule |
| OPEN-12 | Momentum formula | `impact × gear × tapeSpeed × (1 + 0.5 × approach)`, speed counted once. | WI (shape) / OWN (numbers) | constant |
| OPEN-13 | Action timings | Per weapon, in local ticks. Dodge 14 ticks, 2.4 tiles, 10 i-frame ticks. | OWN | constant |
| OPEN-14 | Missile edge cases | See detail: flies straight with no target, ties by level order, never retargets, walls stop it, cooldown only. | OWN | rule |
| OPEN-15 | Enemy roster and targeting | Seven types. Ghosts and desynced selves are never targeted. | OWN | redesign (content) |
| OPEN-16 | Boss memory | Built from committed takes only: positions per beat and attack attempts. Telegraphed "memory strikes". | OWN | rule |
| OPEN-17 | Objectives and early completion | Five objective types. The first combined run that wins ends the level, with any number of cassettes. | OWN | rule |
| OPEN-18 | Gear structure | Six slots, one loadout shared by all cassettes, loot on first clear, locked during an attempt. Manual desync is in; extra time is not. | OWN | redesign |
| OPEN-19 | Build compatibility | Intended: every level beatable with the starting loadout. Only one level exists, so this is unverified. | OWN | — |
| OPEN-20 | Camera and input | True isometric (yaw 45°, pitch 35.26°). Whole level if it fits, else follow. WASD + mouse aim, twin-stick. | OWN | constant / rule |
| OPEN-21 | Retry, preview, pause | setup → count-in → record → review → decision. No mid-take pause: pausing discards the take. | OWN | rule |
| OPEN-22 | Music state maps | Dead: thinner, chord tones. Desync: phase drift. Reverse: retrograde. Stopped: held note. No voice for an unrecorded cassette. | OWN | constant |
| OPEN-23 | Sound quantisation | Late only, to the next sixteenth, never more than one sixteenth; impacts also get an instant soft click. Inputs are never quantised. | WI | constant |
| OPEN-24 | Visual reference reconciliation | R01 is the palette authority: dark jacket, yellow lining, cream top, triangle headphone emblem. | OWN | redesign (art) |
| OPEN-25 | Content and scope | Title OVERDUB. Story written for 12 levels and three named characters. One test level authored. | OWN / NONE | redesign |

---

## 3. The register in detail

Each entry: **Bible** (what it says and the constraint it sets) · **Build** · **Where** ·
**Alternative** (and what it changes for the player) · **Switch** · **Status**.

### Time and tape boundaries

**OPEN-01 — Exact speed menu.**
- Bible: half / middle / double is the confirmed relationship (TIME-06). 4× "remains historical or
  optional". Revision 1 says the HUD shows "0.5x / 1x / 2x / 4x or the level-supported subset".
- Build: the type allows exactly 0.5, 1, 2 and 4. Each level lists the speeds it offers; the
  default selection is 1× when offered. The one authored level offers all four. Labels are "½×",
  "1×", "2×", "4×", with a one-line consequence on the setup panel ("2× — this take plays back in
  half the time and hits twice as hard; the world runs at half speed while you record").
  Cassettes are named A, B, C, D.
- Where: `prototype/src/core/types.ts` `TapeSpeed`, `ALL_SPEEDS`, `LevelDef.speeds`;
  `ui/menus/format.ts` `speedLabel`; `ui/hud/model.ts` (speed consequence text);
  `game/session.ts` `defaultSpeed`. Godot: `core/types.gd`, `game/session.gd`.
- Alternative: drop 4×. The player loses the strongest hits and the quarter-speed world while
  recording. Today any 4× heavy, even standing still, breaks the tutorial wall (momentum 7.2
  against a threshold of 5), which skips the "run into the strike" lesson on levels that offer 4×.
- Switch: constant (remove 4 from the levels' `speeds`; nothing else depends on it).
- Status: OWN.

**OPEN-02 — Overall encounter horizon.**
- Bible: TIME-07 requires one common horizon; the choice between slowest selected, slowest
  allowed and level-authored "was not made". No padding or stretching.
- Build: level-authored. `LevelDef.horizonBars` is the encounter length in master bars. The
  convention (and the test helper's default) is `bars ÷ slowest offered speed`. The validator
  rejects a horizon shorter than one pass of the fastest speed and only warns when it is shorter
  than one pass of the slowest (that tape is then cut off). The horizon does not change with what
  the player selects. A consequence: while recording a fast tape the player sees only the first
  part of the encounter (a 2× take on an 8-bar, 16-bar-horizon level covers master bars 0–4); the
  rest is seen in the review.
- Where: `core/time.ts` `horizonSubs`; `content/validate.ts` lines 88–110; `core/types.ts`
  `LevelDef.horizonBars`. Godot: `core/time.gd`, `content/validate.gd`.
- Alternative: slowest *selected* tape sets the length. A fast-only attempt would end sooner, with
  fewer repeats, and the replay would be shorter.
- Switch: constant per level for a different authored value; rule for a selection-dependent
  horizon (session, HUD ruler and boss memory all read the fixed value).
- Status: OWN.

**OPEN-03 — Local bars versus master bars.**
- Bible: one unambiguous clock definition is needed; the illustrative equations
  (`master = local ÷ speed`) are a working interpretation. The count-in was requested as
  tape-speed-sensitive and "its exact relation to local tape tempo versus master tempo needs to be
  specified".
- Build: one clock. The world steps in 1/240 master second; a tape is sampled every 1/60 local
  second; recording at speed s advances the world 4 ÷ s steps per local tick. `level.bars` is
  local bars, `level.horizonBars` is master bars. The HUD ruler is in master beats; each deck
  shows local tape progress and how many master bars one pass spans (`bars ÷ speed`). While
  recording, the ruler and the world run at 1 ÷ s. The count-in is four beats at the level tempo
  in wall time at every speed; the text under it reads "TAPE A · 2× · world ×0.5 while you
  record". Its sound does not change with speed.
- Where: `core/time.ts` (module header, `tapeTicks`, `horizonSubs`, `spanBars`);
  `game/session.ts` `COUNT_IN_BEATS`, `countBeatSeconds`, `worldRate`; `ui/hud/panels.ts`
  `CountIn`. Godot: `core/time.gd`, `game/session.gd`, `ui/hud/hud_count_in.gd`.
- Alternative for the count-in: count at the *master* tempo as the player will hear it (half
  tempo before a 2× take, double before a 0.5× take), so the count announces how fast the world is
  about to move.
- Switch: rule (session timing and the count-in sound).
- Status: WI for the clock; OWN for the count-in (see P-3).

**OPEN-04 — Fast/slow tradeoffs.**
- Bible: the early wish ("faster hits harder, gets less far, and is harder to control") does not
  follow from the later equal-recording-time model. "Preserve the intent as a test target rather
  than hard-coding contradictory rules." No movement penalty may be invented.
- Build: nothing is hard-coded beyond the clock and momentum. What results:
  - *Hits harder:* yes. Momentum is multiplied by tape speed. With the starting blade, a standing
    light delivers 0.5 / 1 / 2 / 4 at ½× / 1× / 2× / 4×.
  - *Gets less far:* no. Every tape can walk the same distance; a fast tape does it in less
    master time and then stops, repeats or reverses.
  - *Harder to control:* no, the opposite. The world runs slower while a fast tape is recorded.
  - *Slow tapes are weak:* a ½× tape cannot kill a one-hit enemy with any light attack or a
    standing heavy (damage rounds down to 0); only a heavy while running into the target does.
  - No test targets the early intent.
- Where: `core/tuning.ts` `strikeMomentum`, `strikeDamage`; `core/time.ts`. Godot: `core/tuning.gd`.
- Alternative: give fast tapes a cost in control or reach (shorter allowance, more inertia). That
  would restore the early intent and contradict TIME-02's "consistent to the person holding the
  controls".
- Switch: rule.
- Status: OWN (the tradeoff as it stands is a consequence, not a tested target).

**OPEN-05 — End-behaviour details.**
- Bible: unspecified — what stays physical after stop; whether a dead cassette resets at a repeat;
  what persists; what happens to recovery state on a teleport or a reversal. "None should be
  inferred from the visual metaphor."
- Build:
  - *Stop:* the self holds its last pose and stays fully present: solid for pressure plates,
    targetable, killable, counts as a survivor (probe: plate still held at the end, survivor
    listed).
  - *Repeat:* cuts to sample 0; every event fires again each pass. A dead tape stays dead for the
    rest of the encounter (probe: killed on pass 2 of 4, still a ghost at the end, one death
    event). Nothing is restored at a boundary.
  - *Spawned objects:* projectiles from an earlier pass keep flying.
  - *Recovery state:* desync persists across boundaries. On a repeat cut the projection teleports;
    the spark does not, it has to travel. The cut itself is not treated as an obstructed step.
  - *Resources:* cooldowns exist only while recording; playback simply replays the recorded
    presses, so nothing "recharges".
  - *Default:* `stop` is preselected when the level offers it.
- Where: `core/time.ts` `tapePhaseInto`, `collectEventCrossings`; `core/actors.ts`
  `SelfActor.advance` (`cut`), `isObstructed`; `core/mechanisms.ts` `plateOccupied`; tests
  `tests/core/kernel/tapemodes.test.ts`, `desync.test.ts` line 312. Godot: `core/time.gd`,
  `core/actors.gd`, `core/mechanisms.gd`.
- Alternatives: (a) a stopped self vanishes or becomes untargetable — "park a self on a plate"
  stops working and stopped selves stop being safe survivors or bait; (b) a dead tape revives at
  each repeat — repeat becomes a way to get extra lives.
- Switch: rule each.
- Status: OWN.

**OPEN-06 — Reverse event semantics.**
- Bible: PLAY-06 confirmed — reverse the recorded actions, not the world; a returning shot can
  hurt again; a switch moved on can be moved back off. Unspecified: several actors on one switch,
  continuous interactions, projectile return, homing missiles.
- Build: on a backward pass each event fires again when the playhead crosses its tick.
  - *Switch:* an interact toggles the nearest switch's **current** value. It is not "set back to
    what it was" and not per-actor. Two tapes on one switch simply toggle it in time order.
  - *Swing / shot / missile:* a fresh swing or shot with the recorded direction. A missile
    re-acquires the nearest enemy at that moment. Nothing flies back and nothing heals.
  - *Momentum:* the recorded approach velocity is negated, so a swing recorded while running in is
    weaker on the way back.
  - *Continuous interactions (plates, exits):* follow the body, so they reverse naturally.
  - *Turn points:* an event on the last tick fires once per turn, not twice.
  - *Manual desync:* toggles again.
  - *Side effect (P-1):* dodge i-frames and swing hit windows are placed after the crossing, so on
    a backward pass they do not coincide with the recorded dodge or the recorded strike position.
- Where: `core/time.ts` `collectEventCrossings` (reverse ownership rule); `core/sim.ts`
  `dispatch`; `core/mechanisms.ts` `interact`; `core/combat.ts` `meleeMomentum`, `openSwing`;
  `core/weapons/missile.ts` header. Godot: `core/time.gd`, `core/sim.gd`, `core/combat.gd`.
- Alternatives: (a) mirror the timing on a backward pass so the hit and the i-frames fall where
  they were recorded — reverse becomes a true mirror the player can plan by eye; (b) a switch
  remembers each actor's contribution and reverse undoes only that — two tapes on one switch stop
  cancelling each other; (c) shots are not re-fired on the way back.
- Switch: rule each ((a) touches `dispatch`, `openSwing` and their tests).
- Status: OWN.

### State, collision and outcome

**OPEN-07 — Authoritative result after the final active ghost.**
- Bible: "a dead playback self cannot win the level through interactions it should no longer
  have." A non-interactive validation of all tapes under playback rules is named as one possible
  resolution.
- Build: exactly that. When a take ends, the live run is thrown away and `resolveEncounter` runs
  every tape, including the one just recorded, under playback rules for the whole horizon. Only
  that run decides the result, and its stored frames are what the review and the cinematic show.
  This applies to every take, not only the fourth.
- Where: `core/resolve.ts` `resolveEncounter`; `game/session.ts` `finishTake`. Godot:
  `core/resolve.gd`, `game/session.gd`.
- Alternative: mark events as authoritative or provisional during the live take and skip the
  re-run. The player would see no difference when it works.
- Switch: redesign (the replay and the HUD marks read the resolved run).
- Status: WI.

**OPEN-08 — Survivor evaluation.**
- Bible: unsettled — at what beat; whether an alive-but-desynced actor qualifies; a stopped tape;
  whether someone must be at an exit.
- Build: survival is read once, at the last instant of the horizon. A survivor is any self whose
  life state is `alive`. Alive-but-desynced counts (the result notes say "it survives, but it
  could not act or hold an exit"). A stopped tape counts. Most objectives latch the first moment
  they are met and stay met. Nobody has to be at an exit unless the level's objective type is
  `reach`, which needs an alive, synced self inside the exit at the final instant.
- Where: `core/objective.ts` `buildOutcome`, `ObjectiveTracker.satisfiedNow`, `exitHeld`;
  `core/mechanisms.ts` `step` (exit test). Godot: `core/objective.gd`.
- Alternative: a desynced self does not count as a survivor. Using desync to hide from danger
  until the end would stop being a way to win.
- Switch: rule (one condition in `buildOutcome`).
- Status: OWN.

**OPEN-09 — Recovery tuning.**
- Bible: DESYNC-02..05 confirmed (finite speed, real routes, blocked by geometry, resync on
  catch-up). Speed, tolerance, routing and the no-route case are open. "Do not add [a timeout,
  teleport rescue, automatic death or forced failure] silently."
- Build: spark speed 7.5 tiles per master second, constant, no acceleration (run speed is 4.5 per
  local second). It starts at the self's last valid position, heads straight for the projection
  when the line is clear, otherwise follows an A* route that is re-planned on every door change
  and at least every 24 steps (0.1 s). It resyncs when within 0.35 tiles with a clear line and the
  projection not inside something solid; no beat boundary is involved. With no route it goes as
  close as it can and waits; there is no timeout, teleport or death. One gear item makes it 40 %
  faster, another 15 %. See P-2 for the fast-tape consequence.
- Where: `core/tuning.ts` `BASE.sparkSpeed`, `sparkRadius`, `resyncTolerance`,
  `sparkReplanSubs`; `core/actors.ts` `stepSpark`, `canResync`, `beginDesync`. Godot:
  `core/tuning.gd`, `core/actors.gd`, `core/path.gd`.
- Alternative: scale spark speed with the tape's speed (or state it in local time), so fast tapes
  can be caught. Desync on fast tapes would then be recoverable rather than close to permanent.
- Switch: constant for the numbers; rule for speed scaling.
- Status: OWN.

**OPEN-10 — Collision permissions.**
- Bible: all of it is open and "should be handled as open collision policies, not inferred from
  action-game convention."
- Build:
  - *Self to self:* no blocking, no damage. All cassettes start on the same spot.
  - *Self to enemy bodies:* no blocking either way. Neither the live player nor a recorded path
    collides with enemies; an enemy standing on a recorded path never causes desync.
  - *Player shots:* never touch selves (no friendly fire).
  - *Enemy bolts:* stop in the first vulnerable self they meet and kill it, so one self can
    shield another by dying. They pass through ghosts, desynced projections, the recording ghost
    and a self inside i-frames. They hit other enemies (1 damage, 0.25 s stagger).
  - *What causes desync:* only solid geometry — walls, closed doors, unbroken breakables, an
    extended crusher.
  - *Hazards:* lasers and traps kill a self in one hit under the same rule as enemy hits.
  - *Spark:* collides with geometry only. Never targeted, never hurt, operates nothing.
  - *Enemies:* pushed out of a door that closes on them; they do not collide with each other.
  - *Pressure plates:* held by any self that can act and by grounded living enemies; drones do
    not count; "heavy" plates need a heavy enemy or one gear item.
- Where: `core/projectiles.ts` `BOLT`, `flyStraight`; `core/weapons/common.ts` `selfShot`
  (`hitsSelves: false`); `core/actors.ts` `isObstructed`; `core/mechanisms.ts` `plateOccupied`,
  `clearEnemiesFrom`; `core/player.ts` (no enemy collision). Godot: `core/projectiles.gd`,
  `core/actors.gd`, `core/mechanisms.gd`.
- Alternative: enemies are solid to selves. Brutes could body-block corridors and knock recorded
  selves into desync; herding enemies into a path would become a tool and a hazard.
- Switch: rule (a new obstruction source plus live-player collision).
- Status: OWN.

**OPEN-11 — Active-player desync.**
- Bible: DESYNC-08 — no baseline "press a button to desync". Whether live control can desync
  before a gear ability, and how it would record, "was not defined".
- Build: the live self never desyncs from the environment; a closing door pushes it out like any
  wall. With the Dropout Jacket equipped, the ability button toggles a voluntary desync: the self
  becomes harmless and invulnerable, a spark is left where the body was and is held there, and a
  second press releases it. The presses are recorded as events. On playback the released spark
  must travel to the projection under the normal rules, so the self rejoins later than it did
  live.
- Where: `core/sim.ts` step 2 (`!self.live && isObstructed`); `core/abilities.ts`
  `manualDesync`; `data/gear.json` item `dropout_jacket`. Godot: `core/sim.gd` line 420,
  `core/abilities.gd`.
- Alternative: no manual desync item in the first version (the bible calls it "a candidate
  equipment ability, not … a guaranteed unlock").
- Switch: constant (remove the item from the gear list and level loot).
- Status: OWN.

### Combat and enemies

**OPEN-12 — Momentum calculation.**
- Bible: MOM-01..04 confirmed (movement and tape speed feed momentum; it drives damage, stagger
  and knockback; direction matters; light and heavy differ). The formula and curves are unchosen;
  tape speed must not be counted twice.
- Build:
  ```
  approach  = clamp(recorded local velocity along the swing ÷ 4.5, −0.5, 1)
  momentum  = weapon impact × gear × tapeSpeed × (1 + 0.5 × gear × approach)
  damage    = floor(momentum × weapon damage factor × gear)
  knockback = min(3 tiles × gear, momentum × weapon factor × gear ÷ enemy mass)
  stagger   = momentum × weapon factor × gear ÷ enemy poise      (master seconds)
  ```
  Tape speed enters once. A standing swing carries full momentum. Running in adds up to 50 %;
  running away removes up to 25 %. Movement inertia is not carried beyond the recorded velocity at
  the press. Damage is a whole number, so thresholds are steps. Projectiles deliver the weapon's
  impact without the tape-speed factor. With the starting blade (light 1.0, heavy 1.8):

  | | ½× | 1× | 2× | 4× |
  |---|---|---|---|---|
  | light, standing / running in | 0.5 / 0.75 | 1 / 1.5 | 2 / 3 | 4 / 6 |
  | heavy, standing / running in | 0.9 / 1.35 | 1.8 / 2.7 | 3.6 / 5.4 | 7.2 / 10.8 |

- Where: `core/tuning.ts` `strikeApproach`, `strikeMomentum`, `strikeDamage`,
  `strikeKnockback`, `strikeStagger`; `core/combat.ts` `meleeMomentum`, `applyStrike`;
  `core/weapons/common.ts` (no tape speed for shots). Godot: `core/tuning.gd`, `core/combat.gd`.
- Alternative: make movement the main term (a standing swing is weak at any speed). Running
  starts and spacing would matter more than the speed selector.
- Switch: constant for weights and caps; rule for a different shape.
- Status: WI for the shape (it is the bible's "useful implementation interpretation"); OWN for
  every number.

**OPEN-13 — Action timings.**
- Bible: three actions confirmed; "the numbers are not". Working interpretation: timings constant
  in local tape time, then mapped to master time (COMBAT-04).
- Build: all timings are local ticks (1/60 s) and come from the equipped weapon, so they take
  1 ÷ speed as long in master time. Starting blade: light 6 windup + 4 active + 10 recovery
  (0.33 s), reach 1.3 tiles, 100° arc; heavy 16 + 5 + 20 (0.68 s). Dodge: 14 ticks (0.23 s),
  2.4 tiles, i-frames on ticks 1–10, next dodge 36 ticks after the start. A press during recovery
  is buffered for 8 ticks. Interact: 10 ticks, 1.2-tile reach, instant effect. Six melee weapons
  and five ranged weapons each have their own numbers.
- Where: `core/player.ts` `actionTiming`; `core/tuning.ts` `BASE`; `data/gear.json`
  (`melee`, `ranged` blocks). Godot: `core/player.gd`, `core/tuning.gd`.
- Alternative: n/a (pure tuning). See section 5.
- Switch: constant.
- Status: OWN.

**OPEN-14 — Missile edge cases.**
- Bible: MISSILE-01..04 and WEAPON-02 confirmed (fixed launch, nearest enemy locked once, very
  slow). Open: no target, ties, target death, walls, lifetime, resource limits, owner death,
  reverse. "Do not make ammunition management a mandatory puzzle dimension."
- Build:
  - *No enemy alive at launch:* flies straight along the recorded direction.
  - *Ties:* the enemy placed first in the level file.
  - *Line of sight:* not required; sleeping enemies can be chosen.
  - *Target dies:* it stops steering and flies straight on. It never retargets.
  - *Contact:* strikes the first enemy it actually touches, which may not be its target.
  - *Walls and closed doors:* stop it.
  - *Lifetime:* 20 tiles of flight (about 6.7 s at 3 tiles per master second, turning at most
    3 rad/s).
  - *Resource limit:* no ammunition; a 90-tick (1.5 local seconds) cooldown while recording.
  - *Owner dies or desyncs after launch:* the missile keeps flying. A dead or desynced self does
    not launch.
  - *Reverse pass:* a new missile with the recorded heading and a new lock.
  - *Initial orientation:* the recorded aim direction, from the self's centre.
- Where: `core/weapons/missile.ts` (header and `acquireNearestEnemy`); `core/weapons/common.ts`
  `selfShot`; `data/gear.json` `mixtape_rocket`. Godot: `core/weapons/missile.gd`.
- Alternative: the missile fizzles when its target dies, or when its owner dies. Both make it
  safer to stand near; the second makes protecting the shooter part of the puzzle.
- Switch: rule each.
- Status: OWN.

**OPEN-15 — Enemy roster and targeting detail.**
- Bible: AI-01..07 confirmed (rule-following, deterministic, on the beat). Classes, tells, grids,
  ghost/desync eligibility and stagger resistance are content decisions. Whether ghosts or
  desynced projections stay targetable "was not settled".
- Build: seven types.

  | Type | Rule | Hits to kill | Attack grid |
  |---|---|---|---|
  | grunt | walks at the nearest self, re-chosen every beat | 1 | every 2 beats |
  | stalker | hunts the farthest self, chosen on bar lines | 1 | every 2 beats, offset 1 |
  | turret | fixed; shoots the nearest self in range, arc and sight | 1 | every 2 beats |
  | shielder | shield pops on one self's hit; a different self must hit within 1 beat | 2 | every 4 beats |
  | brute | slow, heavy, wide swing | 3 | every 4 beats, offset 2 |
  | drone | hovers, keeps 5 tiles away, shoots | 2 | every 2 beats, offset 1 |
  | boss | anchored; frontal armour; three phases; memory strikes | 40 | every 4 beats |

  Every attack is announced by a telegraph of 0.5–2 beats. Only alive, synced selves are ever
  targeted or hurt: dead ghosts, the recording ghost, desynced projections and sparks are ignored
  by enemy decisions. Distance ties go to the lower cassette. Two helmets change how near a self
  appears to enemies. There is no randomness.
- Where: `core/enemies/*.ts` (rule in each file header); `core/enemies/common.ts` `targetable`,
  `nearestTarget`; `core/tuning.ts` `ENEMY_STATS`. Godot: `core/enemies/*.gd`.
- Alternative: enemies keep aiming at ghosts and desynced projections. A dead or desynced self
  becomes a decoy that soaks up attacks, which changes the wall-and-turret pattern (the turret
  would waste shots on the crossing self instead of picking someone else).
- Switch: rule for target eligibility (`targetable`); redesign for the roster.
- Status: OWN.

**OPEN-16 — Outside-loop boss memory.**
- Bible: BOSS-01..03 confirmed. What is remembered, when memory resets, what the boss can
  predict and how adaptation is shown are "material open decisions". The cinematic must not teach
  it again.
- Build: memory is rebuilt from the **committed** tapes only, at each commit and at a full reset.
  A discarded take, the review and the cinematic never feed it. It holds choreography, not
  outcomes: each committed tape's position at every whole master beat and every light, heavy or
  ranged attempt, with end behaviour applied. From it the boss plans "memory strikes" before the
  run starts: wherever a remembered self stood within 0.75 tiles for at least 2 beats, or
  attacked, it turns there, telegraphs for 2 beats and hits everything within 1.25 tiles on the
  beat. While doing so its attention is on the remembered cassette, so other selves can reach its
  back. A stagger of momentum 4 or more cancels a memory strike. Memory does not persist between
  attempts or visits. It is tied to the frontal-armour rule (only a self the boss is not watching
  can damage it, from behind), which makes it unbeatable by one self.
- Where: `core/bossMemory.ts` `buildBossMemory`, `recallCandidates`; `core/enemies/boss.ts`
  (header); `game/session.ts` `rebuildBossMemory`, `commit`. Godot: `core/boss_memory.gd`,
  `core/enemies/boss.gd`.
- Alternative: the boss also remembers discarded takes or earlier attempts. It would punish
  rehearsal, and retrying a take would stop being free.
- Switch: rule (what `buildBossMemory` is fed); redesign for a different adaptation.
- Status: OWN.

### Levels, progression and interface

**OPEN-17 — Objective types and early completion.**
- Bible: REC-06/07 confirmed (final combined run; objective plus one survivor). Objective types
  and whether a level can finish before all recordings are committed "were not settled".
- Build: five objective types — `eliminate` (all or listed enemies), `activate` (strike cores
  with enough momentum), `boss`, `reach` (an alive, synced self in the exit at the final
  instant), `signal` (a named condition becomes true). A level offers 1–4 cassettes
  (`maxTapes`). The first combined run that wins ends the level, however many cassettes have been
  used. The last cassette cannot be "committed": if its run fails the choices are retry or reset.
- Where: `core/objective.ts` `ObjectiveTracker.satisfiedNow`; `game/session.ts` `finishTake`,
  `canCommit`. Godot: `core/objective.gd`, `game/session.gd`.
- Alternative: the level is judged only once every offered cassette is recorded. Solutions with
  fewer cassettes would still need filler takes, and the player would always get all four layers
  of music.
- Switch: rule.
- Status: OWN (see also D-1).

**OPEN-18 — Gear structure.**
- Bible: GEAR-01..05, APPAREL-01..03 confirmed (physical gear, six named slots, swapped between
  levels, generous inventory). Open: shared versus per-tape, acquisition, visible outfit changes,
  whether time and desync upgrades enter the first version.
- Build: six slots (helmet, top, pants, shoes, melee, ranged). One loadout is shared by all
  cassettes and locked while a level attempt is in progress. Each level lists its loot; it is
  added to the inventory the first time the level is cleared and never removed. No loot from a
  failed attempt, no capacity limit, no rarity, no random rolls, no pickups during a take. The
  catalogue has 37 items: 6 helmets, 8 tops, 6 pants, 6 shoes, 6 melee, 5 ranged. Faster resync
  and manual desync are in it. Extra recording time is not. Items carry a "look" so equipped gear
  can show on the model; the wardrobe art is in progress (`art/wardrobe/`).
- Where: `data/gear.json`; `content/gear.ts`, `content/loadout.ts`; `game/campaign.ts`
  (`equip`, clear handling). Godot: `content/loadout.gd`, `game/campaign.gd`,
  `core/types/gear_item.gd`, `gear_look.gd`.
- Alternative: a loadout per cassette. One self could carry the hammer and another the needle
  gun; puzzles would gain a planning layer and the loadout screen four columns.
- Switch: redesign (the simulation takes one loadout per run).
- Status: OWN.

**OPEN-19 — Available-build compatibility.**
- Bible: the confirmed concern is no permanent dead end. APPAREL-02: "Mandatory levels must
  remain completable with equipment available at that point."
- Build: the stated intent is that every mandatory level is beatable with the starting loadout
  (`docs/ARCHITECTURE.md`, "Gear"). There is a solutions folder (`data/levels/solutions/`) for
  checking this. Only the `sandbox` level is authored, so the claim is unverified for a campaign.
  Old levels can be replayed with any owned gear.
- Where: `data/levels/index.json`; `content/validate.ts`; `game/campaign.ts`.
- Alternative: some levels expect a specific found item. Levels can be built around one weapon;
  the player must re-equip, and each such level needs its own proof.
- Switch: none in code; it is an authoring rule.
- Status: OWN (and unproven).

**OPEN-20 — Camera and input particulars.**
- Bible: isometric confirmed. Projection, framing, off-screen tapes, occlusion, attack facing
  and bindings are not.
- Build:
  - *Projection:* orthographic, yaw 45°, pitch 35.26° (true isometric).
  - *Framing:* while recording, the whole level if a tile stays at least 42 px, otherwise the
    camera follows the active self. The review frames the action. The cinematic drifts and pushes
    in.
  - *Off-screen selves:* no on-screen pointer was found; their state is on the cassette decks and
    the ruler only.
  - *Occlusion:* walls on the camera side are cut low; hidden actors show as an x-ray silhouette
    (Godot).
  - *Facing:* attacks go where the player aims. Mouse aim on keyboard (falls back to the movement
    direction after 1.5 s without mouse movement); right stick on a pad.
  - *Bindings:* WASD move; left click light; right click heavy; Space dodge; E interact; Q or F
    ranged; Shift ability; Q / E speed down / up in setup; Tab end mode; R retry; hold Backspace or
    Delete for 0.9 s to reset everything; Esc or P pause.
  - *Cassette colours:* red `#ff4d6d`, yellow `#ffd23f`, blue `#3ec5ff`, green `#7dff6b` (the jam
    palette order).
- Where: `render/camera.ts`; `game/input.ts` `BINDINGS`; `core/types.ts` `TAPE_COLORS`;
  `render/env/layout.ts` (cutaway). Godot: `world/world_camera.gd`, `docs/GODOT-PORT.md`
  "Presentation".
- Alternative: attacks face the movement direction (no aiming). One-stick play; less precise
  recorded strikes.
- Switch: constant for bindings and colours; rule for framing or facing.
- Status: OWN.

**OPEN-21 — Retry / preview interaction and pause.**
- Bible: settled — free retry of the current take, full reset to change an earlier one,
  automatic playback, early reset on failure. Unresolved: the exact sequence and the mid-recording
  pause. Scrubbing, stepping, soloing and timeline editing were not selected.
- Build: `briefing → setup → count-in → recording → review → decision → (setup | cinematic →
  results)`. After a take: a losing run plays as a review at true speed, which can be skipped,
  then offers *retry take*, *commit* (not on the last cassette) or *reset all*. A winning run goes
  to the cinematic (D-1). Nothing is committed by a timer. There is no pause during a take:
  pausing in count-in or recording discards the take and returns to setup; so does the window
  losing focus (P-4). No scrubbing, stepping, soloing or editing exists. Committed takes cannot be
  previewed alone, only as part of the next review.
- Where: `game/session.ts` (`actions`, `abortTake`, `retryTake`, `commit`, `resetAll`);
  `game/shell.ts` `pause`. Godot: `game/session.gd`.
- Alternative: a real pause that freezes the take and resumes it. Friendlier to interruptions; it
  also lets the player stop and think mid-performance, which the bible neither approved nor
  rejected.
- Switch: rule.
- Status: OWN.

### Audio, art and scope

**OPEN-22 — Music state maps.**
- Bible: MUSIC-08/09 confirmed (the cassette's own layer changes, through generative parameters,
  not only effects). The mapping, transition timing and whether every tape always has a voice are
  open.
- Build (prototype only): each recorded cassette has one Harmonograph layer with its own formula
  and role, stepping at its tape speed against the shared chord clock.
  - *Dead:* half the gated steps, velocities × 0.65, chord tones only, cycle a quarter as long,
    no chord extensions; the drum layer loses a lane and the snare becomes a rim click.
  - *Desynced:* the contour slips ahead in quarter steps and smooths; up to 18 % of a step late;
    accents down to 85 %. Drift rises 0.25 per bar while desynced and falls 0.5 per bar after
    resync, changing on bar lines.
  - *Reverse pass:* the contour is read backward (retrograde) on the same rhythm; the chord clock
    never rewinds.
  - *Stopped:* one sustained chord tone, re-voiced as the chords change.
  - *Unrecorded cassette:* silent. There is no backing layer independent of the cassettes, so a
    first take plays over a single voice.
- Where: `audio/director.ts` (`LayerVariant`, the `v.dead`, `v.drift`, `v.transport` branches);
  `audio/sequencer.ts` `DRIFT_RISE_PER_BAR`, `DRIFT_FALL_PER_BAR`; `game/session.ts`
  `trackAudioStates`. Godot: contract only (`game/contracts/track_audio_state.gd`).
- Alternative: all four layers always play a quiet base pattern and recording a cassette "wakes"
  its layer. Early takes would sound fuller; a recorded layer would be less distinct from an
  empty one.
- Switch: constant for amounts; rule for the always-on bed.
- Status: OWN.

**OPEN-23 — Sound quantisation latency.**
- Bible: MUSIC-05 (roughly a sixteenth grid) and MUSIC-07 (never move gameplay) confirmed. Grid,
  allowed delay and immediate feedback are open.
- Build (prototype only): gameplay events are never moved. Each event's accent is placed on the
  next sixteenth line at or after it, never early and never more than one sixteenth late (at
  120 bpm, at most 125 ms). While recording a fast tape the grid is subdivided so it is still a
  sixteenth of the tempo the player hears. Impacts also play a soft click at once (30 % gain)
  when the accent would be noticeably late. Repeats on one grid line merge into one cue. Player
  input is never quantised.
- Where: `audio/sfx.ts` (latency policy in the header, `quantizeLate`). Godot: not present yet.
- Alternative: nearest line rather than next line (half the average delay, but some sounds would
  need to play before their event, which is impossible live).
- Switch: constant.
- Status: WI (it follows MUSIC-05 and MUSIC-07 as written; the one-sixteenth cap is the build's
  number).

**OPEN-24 — Visual reference reconciliation.**
- Bible: R01 is the primary anchor for colour, face, Walkman and equipment; R02 is for angles,
  expressions and details. They disagree on jacket and top colours, the headphone emblem and hair
  accents: "reference variants to reconcile before final modeling". The "170 cm" on the sheet is
  not approved.
- Build: the model follows R01 wherever the two differ: dark jacket with yellow lining, cream
  crop top with a faint four-point star, triangle graphic on the headphones, yellow double chevron
  on the sleeve, olive low-rise cargos, taupe and brown high-tops, cyan vial and magenta straps on
  the belt. R02's yellow jacket, dark top, star emblem and hair accents are not used. Cassette
  identity is carried by outline, floor ring and headphone glow, not by the outfit. Several model
  variants are still in progress (`art/moxie_a` … `art/moxie_e`); no height was verified here.
- Where: `art/moxie/mx_geo.py` `PALETTE` ("R01 is the palette authority"), `mx_outfit.py`,
  `mx_hair.py` (triangle emblem); `docs/GODOT-PORT.md` "Presentation".
- Alternative: R02's yellow jacket and star emblem. She would read brighter at small size and
  the yellow would compete with cassette B's yellow.
- Switch: redesign (art).
- Status: OWN.

**OPEN-25 — Concrete content and delivery scope.**
- Bible: title, level count, bosses, equipment roster, campaign length, NPCs, ending and
  delivery targets "remain unspecified". B-sides and scoring are LATER.
- Build:
  - *Title:* OVERDUB. Tagline in the story data: "Be your own backing band."
  - *Levels:* the story is written for 12 named levels (`01-soft-open` … `12-master-tape`).
    Only `sandbox` exists as a playable level in `data/levels/`.
  - *Boss:* one boss type; the story names it the Archivist and places it on level 11.
  - *Characters:* Moxie, Opal, Tolliver "Tolly" Vance, the Archivist.
  - *Ending:* written (D-2).
  - *Gear:* 37 items (OPEN-18).
  - *Delivery:* Godot 4.4.1 desktop build; the browser prototype is kept as the rules reference.
  - *Not built:* B-sides, optional challenges, stars, scores (none found in the results screen or
    the save).
- Where: `data/story/story.json`, `docs/story/BIBLE.md`, `docs/story/CAST.md`;
  `data/levels/index.json`; `project.godot`.
- Alternative: n/a. These are the creator's to set.
- Switch: redesign.
- Status: OWN for the title, cast, level count and ending; NONE for the campaign levels.

---

## 4. Open items outside chapter 22

Inline "OPEN —" paragraphs, "not yet specified" sections and unselected details in chapters 03–16.
Items already covered above point to their entry.

| Chapter and item | Bible | Build | Where | Status |
|---|---|---|---|---|
| 03 TIME-05 — length of a take | No range chosen; tune by playtesting | Per level, in bars. Sandbox: 8 bars at 120 bpm = 16 s, horizon 16 bars = 32 s | `LevelDef.bars`, `bpm` | OWN (tuning) |
| 03 — what sets the horizon | Not chosen | See OPEN-02 | | OWN |
| 04 — recording pause | Not approved or rejected | No pause; pausing discards the take (OPEN-21) | `session.ts` `abortTake` | OWN |
| 04 — preview, skip, scrub | Scrub, step, solo, edit, export not selected | Skip only. None of the others exists | `session.ts` `actions` | WI |
| 04 REC-07 — fewer than four tapes | Working interpretation: judge the final required recording | Judge every combined run; first win ends the level (OPEN-17) | `session.ts` `finishTake` | OWN |
| 04 — boss memory versus reset | "Memory policy is still open" | See OPEN-16 | | OWN |
| 05 — storage model | Not chosen; path plus events is "one possible approach" | Path (position, facing, animation per 1/60 s) plus action events; linear interpolation | `core/tape.ts` | WI |
| 05 PLAY-05 — first available end mode | Not selected; "loop only first" was a suggestion | Each level lists its end modes; `stop` is the default. Sandbox offers all three | `LevelDef.endModes`, `session.ts` `defaultEndMode` | OWN |
| 05 — stop body policy | Not specified | See OPEN-05 | | OWN |
| 05 — two tapes on one switch | Not established | Each interact toggles the current value (OPEN-06) | `mechanisms.ts` `interact` | OWN |
| 06 — fourth take dies | Required outcome clear, method open | See OPEN-07 | | WI |
| 06 — death at loop boundaries | Open | Dead stays dead (OPEN-05) | | OWN |
| 07 DESYNC-05 — resync tolerance, beat boundary | Open | 0.35 tiles, clear line, any instant (OPEN-09) | `actors.ts` `canResync` | OWN |
| 07 — spark versus enemies | Not selected; "do not interpret it as … enemy bait" | Never targeted, never hurt | `enemies/common.ts` `targetable` | WI |
| 07 — spark never arrives | No timeout or rescue chosen; "do not add one silently" | It waits; nothing is added | `actors.ts` `stepSpark` | WI |
| 07 — desynced survivor | Open | Counts as a survivor; cannot hold an exit (OPEN-08) | `objective.ts` | OWN |
| 07 — enemy bodies, movable objects, floor changes causing desync | Need explicit rules | Only solid geometry causes desync. There are no movable objects. A crusher extending on the path does | `actors.ts` `isObstructed` | OWN |
| 07 — spark at a repeat cut or reversal | Needs a rule | Spark keeps its position and travels | `desync.test.ts` line 312 | OWN |
| 07 DESYNC-08 — on-demand desync | Candidate upgrade only | One gear item (OPEN-11) | `abilities.ts` | OWN |
| 08 — control scheme | Suggestions only | See OPEN-20 | | OWN |
| 08 COMBAT-04 — dodge numbers | Unchosen | See OPEN-13 | | OWN |
| 08 — standing swing, inertia, shared curve | Not settled | Standing swing has full base momentum; no inertia; one momentum value feeds all three results (OPEN-12) | `tuning.ts` | OWN |
| 08 MOM-05 — mass, enemy collisions, shields, boss immunity | Content choices | Mass and poise per type; turret immovable; boss never shoved; enemies do not collide with each other; knockback into a wall adds stagger (0.25 s per tile) | `tuning.ts` `ENEMY_STATS` | OWN |
| 08 — friendly fire, shielding, hazards | Open policies | See OPEN-10 | | OWN |
| 09 MISSILE-02 — initial orientation | Not specified | The recorded aim direction | `weapons/common.ts` `selfShot` | OWN |
| 09 — ammunition | Not chosen; must not become mandatory | No ammunition; a cooldown while recording (60–150 ticks by weapon) | `data/gear.json` | OWN |
| 09 — weapon roster | Undefined | Five ranged types: missile, pierce, wall-phasing, arc, burst. The missile is the starting weapon and can be swapped out | `data/gear.json` | OWN |
| 10 — targeting ghosts and desynced selves | Not settled | Never targeted (OPEN-15) | `enemies/common.ts` | OWN |
| 10 — taunt or aggro ability | Not confirmed | Two helmets shift perceived distance (×1.5 farther, ×0.75 nearer) | `abilities.ts` `effectiveDistance` | OWN |
| 11 — plates, force thresholds, enemies blocking doors | Unspecified | Grounded enemies hold plates; breakables and cores need one swing at or above a momentum threshold; enemies are pushed out of closing doors | `mechanisms.ts` | OWN |
| 11 — order of unlocking end modes; teaching desync | Not fixed | Per-level data; no campaign levels authored yet | `LevelDef` | NONE |
| 11 LEVEL-09 — revisiting | Details unspecified | Cleared levels replay with any owned gear; loot only on the first clear | `campaign.ts` | OWN |
| 11 LATER-01/02 — B-sides, stars | LATER | Not built | | NONE (correct) |
| 12 Scenario A — simultaneity window | Not specified; must be readable | Second hit from a different self within 1 master beat; same-instant hits count | `enemies/shielder.ts`, `SHIELDER_WINDOW_BEATS` | OWN |
| 12 Scenario K — wall threshold | Content decision | Momentum 5 (2× running heavy = 5.4 breaks it; 2× standing heavy = 3.6 and 1× running heavy = 2.7 do not; any 4× heavy does) | `TUTORIAL_WALL_THRESHOLD` | OWN (tuning) |
| 13 — per-tape loadouts, slots, rarity, loot on failure, pickups | Not settled | See OPEN-18 | | OWN |
| 13 — extra recording time upgrade | Floated, unresolved | Not implemented | | NONE |
| 14 — event-to-pitch mapping | Open | Pitches are chord tones of the chord sounding at that beat, one recipe per event type | `audio/sfx.ts` `RECIPES` | OWN |
| 14 MUSIC-02 — role per cassette | Not finalised | Each level assigns a role and formula per cassette (sandbox: bass, drums, melody, chords) | `LevelDef.music` | OWN |
| 15 — Harmonograph integration route | None chosen | Prototype: the JavaScript engine vendored and run live. Godot: a GDScript port of the engine | `prototype/src/vendor/`, `audio/harmonograph/` | OWN |
| 16 UI-02 — colours and keys | Not reconfirmed | Jam palette order red, yellow, blue, green; names A–D; no 1–4 keys | `TAPE_COLORS`, `TAPE_NAMES` | OWN |
| 16 UI-05 — selector layout and wording | Unchosen | On the active deck: Q / E speed, Tab end mode | `input.ts` | OWN |
| 16 — viewing other rooms | Open | See OPEN-20; no off-screen pointer | `camera.ts` | OWN |
| 16 CINE-02 — control during the cinematic | Free camera not retained | No control; the cinematic can be skipped to the results | `session.ts` `actions` | OWN |
| 16 CINE-03 — cinematic technique | None selected | Drifting camera, push-ins on impacts, music-linked effects | `render/camera.ts`, `render/fx/` | OWN |

### Chapter 21, "Tests awaiting an explicit policy"

The bible says tests that assume answers to these "would prematurely settle design decisions". The
prototype suite does assume the answers above. If a decision is overruled, these are the tests that
encode the old answer:

| Policy | Test that now assumes an answer |
|---|---|
| Stop-mode body and survival | `tests/core/kernel/tapemodes.test.ts` "a stop tape holds its final pose and stays a physical, living survivor" |
| Loop-boundary death | No dedicated test found. The rule is exercised only by `art/decisions/probe.ts` and, for enemies, by the repeat block of `tapemodes.test.ts` (a killed turret is not revived between passes) |
| Reverse switch conflicts | `tests/core/kernel/tapemodes.test.ts` "TEST-26" (toggle on, off, on, off) |
| Authoritative final-ghost evaluation | `tests/game/session.test.ts` "final-tape edge case: objectives completed only by the recording ghost do not win (OPEN-07)" |
| Spark damage and targeting | `tests/core/kernel/desync.test.ts` "a desynced swing deals no damage and a bolt passes through…" |
| Whole-attempt horizon | `tests/content/validate.test.ts` "rejects a horizon shorter than one pass of the fastest offered speed" and the note for the slowest |
| Early completion | `tests/game/session.test.ts` "a level can be won with fewer cassettes than it offers" |

---

## 5. Numbers that are tuning guesses

None of these has been playtested. All are in `prototype/src/core/tuning.ts` (`core/tuning.gd`)
unless another file is named. "Local" means seconds on the player's own clock while recording;
"master" means world time.

**Movement and dodge**

| Number | Value |
|---|---|
| Run speed | 4.5 tiles / local s |
| Acceleration / braking | 42 / 34 tiles / local s² |
| Body radius | 0.3 tiles |
| Dodge length / distance | 14 ticks (0.23 s) / 2.4 tiles |
| Dodge i-frames | ticks 1–10 of the dodge (0.17 s) |
| Dodge cooldown | 22 ticks after it ends |
| Input buffer | 8 ticks |
| Interact reach / commitment | 1.2 tiles / 10 ticks |
| Footstep stride | 0.85 tiles (`core/actors.ts`) |

**Desync and recovery**

| Number | Value |
|---|---|
| Spark speed | 7.5 tiles / master s (see P-2) |
| Resync distance | 0.35 tiles |
| Spark re-plan interval | 24 steps (0.1 master s) |
| Overlap forgiven before a recorded pose counts as blocked | 0.02 tiles |

**Momentum and combat**

| Number | Value |
|---|---|
| Bonus for running into a strike | up to +50 %; running away −25 % |
| Momentum per damage point | 1, rounded down |
| Knockback cap / slide time | 3 tiles / 0.18 master s |
| Wall slam | +0.25 s stagger per tile of knockback left |
| Tutorial breakable wall | momentum 5 |
| Default core threshold | momentum 1 |
| Starting blade | light impact 1.0, heavy 1.8, reach 1.3, arc 100° (`data/gear.json`) |
| Slide-strike bonus (gear) | ×1.5 within 8 ticks of a dodge (`core/abilities.ts`) |
| Door travel | 36 steps (0.15 master s) (`core/mechanisms.ts`) |

Note: comments in `tuning.ts` still describe an earlier blade (light 1.2, heavy 2: "a 1× running
heavy kills a brute"). With the shipped blade a 1× running heavy does 2 of a brute's 3 hit points.
The test helper loadout (`prototype/tests/helpers/loadout.ts`) also uses 1.2 / 2, so the combat
targets asserted by the tests are not the starting loadout's numbers.

**Enemies** (`ENEMY_STATS`)

| Type | Hits | Mass | Poise | Speed (tiles / master s) | Grid (beats) | Telegraph (beats) | Reach | Shot speed |
|---|---|---|---|---|---|---|---|---|
| grunt | 1 | 1 | 2 | 2.2 | 2 | 0.5 | 0.9 | — |
| stalker | 1 | 0.8 | 1.5 | 3.6 | 2 (+1) | 0.5 | 0.9 | — |
| turret | 1 | fixed | never | 0 | 2 | 1 | 12 | 6 |
| shielder | 2 | 1.2 | 2.5 | 1.8 | 4 | 0.75 | 0.9 | — |
| brute | 3 | 3 | 6 | 1.4 | 4 (+2) | 1.5 | 1.4 | — |
| drone | 2 | 0.7 | 1.5 | 2.5 | 2 (+1) | 0.5 | 8 | 5 |
| boss | 40 | 8 | 20 | 1.8 | 4 | 2 | 2.2 | 5 |

Others: shielder window 1 beat; drone keeps 5 tiles; stalker commits within 2.5 tiles; boss turn
rate 2.4 rad/s, back arc ±90°, phases at 2/3 and 1/3 health, stagger needs momentum 4, memory
strike telegraph 2 beats and radius 1.25 tiles, dwell = within 0.75 tiles for 2 beats
(`core/enemies/boss.ts`, `core/bossMemory.ts`); enemy bolt range 64 tiles.

**Ranged weapons** (`data/gear.json`; speed in tiles / master s, cooldown in local ticks)

| Weapon | Speed | Range | Impact | Cooldown | Special |
|---|---|---|---|---|---|
| Mixtape Rocket (missile) | 3 | 20 | 1.5 | 90 | turn 3 rad/s |
| Needle Rail (pierce) | 24 | 12 | 1 | 75 | passes 3 enemies |
| Bleed Emitter (phase) | 6 | 8 | 1 | 150 | passes walls |
| Bass Drop (arc) | 7 | 3–7 | 1.3 | 100 | 1.2-tile blast |
| Static Spray (burst) | 16 | 3.5 | 1 | 60 | 5 pellets, 40° |

**Session, camera, audio**

| Number | Value | Where |
|---|---|---|
| Count-in | 4 beats at level tempo | `game/session.ts` |
| Hold to reset everything | 0.9 s | `game/input.ts` |
| Mouse-aim timeout | 1.5 s | `game/input.ts` |
| Follow-camera threshold | 42 px per tile | `render/camera.ts` |
| Sound-effect lateness cap | one sixteenth | `audio/sfx.ts` |
| Desync drift | +0.25 per bar, −0.5 per bar | `audio/sequencer.ts` |
| Dead layer velocity | × 0.65 | `audio/director.ts` |
| Enemy "nearer / farther" gear factors | × 0.75 / × 1.5 | `core/abilities.ts` |

**Traps** (`prototype/src/core/traps/tuning.ts`): warning 1 beat; spikes and flame 1 damage,
re-hit every beat of contact; crusher 3 damage; conveyor 2 tiles / master s; dart every 2 beats at
8 tiles / s; bumper power 3; magnet pull 1.5 tiles / s.

---

## 6. Things the build added that the bible did not ask for

One line each on why it is there. None of these is a creator decision yet.

| Addition | Where | Why it was added |
|---|---|---|
| Traps: spikes, crusher, conveyor, flame jet, dart launcher, bumper, beam sensor, relay, magnet | `docs/TRAPS.md`, `prototype/src/core/traps/` | The bible lists lasers, moving platforms and conveyors only as inherited candidates "not all approved". Added as level vocabulary and as further ways to cause desync. Not in the Godot core yet. |
| Lasers, cores (strike to activate), exits, a signal language for doors | `core/mechanisms.ts`, `core/signals.ts` | Needed to express objectives and door logic in level data. Laser gates are a legacy candidate. |
| Story, ending, three named characters, 12 named levels, dialogue and barks | `docs/story/`, `data/story/story.json` | To give the campaign an arc and an ending. Conflicts with chapter 18 (D-2). |
| Character portraits | `art/portraits/`, `data/story/portraits.json` | To present the story lines. |
| Six enemy types beyond "turret" and "nearest / farthest" examples; boss frontal armour and three phases | `core/enemies/` | The bible leaves the roster to content design; these give the test levels something to fight. |
| Gear abilities: beat-sight ruler marks, laser immunity, heavy step, phase dodge, slide strike, parry (reflect shots), kill refresh, low profile, loudmouth | `core/abilities.ts`, `data/gear.json` | APPAREL-01 requires each slot to change play; these are the build's inventions to satisfy it. |
| Manual desync item | `data/gear.json` `dropout_jacket` | A candidate in the bible, not a commitment (OPEN-11). |
| Wardrobe: visible gear on the model | `art/wardrobe/`, `core/types/gear_look.gd` | APPAREL-03 says "when practical"; the build treats it as in scope. |
| Result notes that explain a run ("Tape B died at beat 12: shot by turret t1") | `core/objective.ts` `buildOutcome` | Chapter 21's aim that failures be explainable in the game's own terms. |
| Per-cassette setup hints and level briefings | `LevelDef.briefing`, `hints` | Teaching aid; no tutorial format was specified. |
| Spoken "five, six, seven, eight" | `prototype/src/audio/speech.ts`, `art/voice/` | UI-04 asks for an audible count; a voice is one way to do it. |
| Settings: three volumes, audio / video offset, screen shake on or off, a "patterns" option (cassettes told apart by pattern as well as colour); colour-vision checks of the art | `core/types/save_settings.gd`, `art/accessibility/` | Not requested; comfort and accessibility options. |
| Scripted bot and stored solutions for levels | `prototype/src/game/bot.ts`, `data/levels/solutions/` | Development tool to prove a level is beatable. Not player-facing. |
| Sandbox level | `data/levels/sandbox.json` | A test room, not campaign content. |
| Hold-to-confirm on "reset all" | `game/input.ts` | Guards the one destructive action (REC-05). |
| The title OVERDUB and the tagline | `data/story/story.json`, `project.godot` | The bible leaves the title unspecified. |

---

## 7. Evidence files

- `art/decisions/probe.ts` — the scripted checks quoted above (reverse-pass dodge and swing
  positions, stopped tape holding a plate, death across a repeat, the momentum table for the test
  loadout, action timings, a win on take one of a four-cassette level). Read-only; it resolves
  encounters and prints JSON.
