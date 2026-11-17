# OVERDUB — onboarding

How a new player learns the game without a manual. This covers requirements chapter 04 (the
recording workflow), chapter 11 "Teaching complexity", chapter 16 (UI-01..05) and Revision 1's HUD
page (UI-06, UI-07). It is a **data layer plus a specification**; the runtime that reads it is not
written yet (see "Integration").

| File | What it is |
|---|---|
| `data/onboarding/coachmarks.json` | 41 coach marks, in priority order |
| `data/onboarding/failure_hints.json` | 33 nudges keyed to the simulation's failure notes, plus 3 ignore patterns |
| `data/onboarding/vocabulary.json` | the trigger / anchor / token vocabulary, machine-readable |
| `data/onboarding/validate.py` | `python -I data/onboarding/validate.py` checks all of the above and this document |

## Principles

1. **Teach by doing.** A mark names one control or one thing on screen and goes away when the
   player does it or it happens in front of them. There is no OK button and no tutorial room.
2. **One idea at a time.** One mark on screen, a gap between marks, at most two ordinary marks per
   phase visit. The level carries the lesson; the mark only points.
3. **Never block play.** Marks take no input focus, never pause, never dim the world, never cover
   the decks or the ruler, and never appear over a story dialogue box.
4. **Never patronise.** A player who already does the thing never sees the mark for it (`skipIf`,
   and `inputNotUsedFor` in the triggers). Each mark shows once per save. Fourteen words at most.
5. **Skippable.** One setting turns the whole layer off. Nothing in a level depends on it.
6. **Point at the real thing.** Every mark is anchored to an actual HUD element or world object, so
   the player learns where to look next time, not what a pop-up said.
7. **The voice is Moxie's crew chief, not a manual.** Dry, short, second person. Marks state
   mechanics, which the story bible forbids dialogue from doing, so the two never say the same thing.
8. **Do not solve the room.** Marks and failure hints explain rules and point at evidence. They
   never name the route, the order of takes or the speed to choose.

## The teaching arc

Level ids are the story keys in `data/story/story.json`. No campaign level file exists yet
(`data/levels/` holds only `sandbox`), so most marks are written against **conditions** rather than
levels: `level` is `any` unless the mark only makes sense in one room. If a lesson moves to another
level, the condition-driven marks follow it with no edit; the level-bound ones (listed with their
level below) need their `level` field changed.

| Level | The idea | Marks, in the order a player usually meets them |
|---|---|---|
| 01 soft-open | move, attack, the deck, the ruler | `brief-objective` (01), `deck-armed` (01), `count-in`, `move` (01), `aim` (01), `light` (01), `ruler-lane` (01), then `review`, `decide` or `cinematic` depending on how the take went |
| 02 hit-harder | tape speed, momentum, heavy | `speed-pick` (02), `speed-span`, `speed-fast` / `speed-slow`, `heavy` (02), `clang`, `momentum-speed`, `tape-end` |
| 03 hold-the-door | the first overdub | `overdub-setup`, `previous-self`, `lanes`, `interact`, `decide-reset` when a kept take turns out to be the problem |
| 04 second-opinion | two selves at one moment | `same-beat` (04) |
| 05 dead-air | death and the ghost | `death-ghost`, `ghost-not-kept`, `previous-died`, `rescue`, `dodge` |
| 06 crossfire | knockback | `knockback` (06) |
| 07 out-of-phase | desync | `desync`, `spark`, `desync-lane` |
| 08 loop-pedal | repeat | `endmode-pick`, `repeat`, `repeat-wrap` |
| 09 rewind | reverse | `reverse`, `reverse-turn` |
| wherever traps first appear | traps | `trap-warn`, `trap-fair` |
| any | housekeeping | `review-skip` |

What each of the unusual ideas gets:

- **Tape speed changes how the world moves.** `speed-pick` (the control), `speed-span` (the lane on
  the ruler changes length: UI-07's "connect playback rate to tape duration"), `speed-fast` /
  `speed-slow` (the playhead visibly crawls or races), `momentum-speed` (speed multiplies hits).
- **Every take restarts at beat zero.** `count-in`, then `overdub-setup` on the second cassette.
- **Dying does not end a take.** `death-ghost` during the take, `ghost-not-kept` on the decision
  screen (Scenario C: the ghost's later actions will not replay).
- **Old selves are fixed, the world is not.** `previous-self`, `previous-died`, `rescue`.
- **Desync.** `desync` (the outline is only the recording), `spark` (the real self is the spark),
  `desync-lane` (how the ruler shows it).
- **The HUD.** `deck-armed`, `speed-pick`, `endmode-pick` (decks); `ruler-lane`, `lanes`,
  `same-beat`, `tape-end`, `desync-lane` (ruler); `count-in`; `brief-objective`.
- **Retry, commit, reset-all.** `decide` on the first decision; `decide-reset` only when the
  player has retried the same take twice with an older take committed, and has never used reset.

Level 01 is the busiest. A player who does nothing unprompted sees, across their first take:
count-in, move, then aim or light (the phase budget is two), and the rest on later takes. A player
who moves and swings straight away sees only the count-in and the ruler mark.

Not taught by marks, on purpose: ranged weapons and gear abilities (they belong to the level that
hands the item out, and the item card can carry the line), the boss's memory (the Archivist says it
in the level 11 intro), and scoring (LATER-02).

## Coach mark format

`coachmarks.json` is `{ version, limits, marks: [...] }`. Each mark:

| Field | Meaning |
|---|---|
| `id` | kebab-case, unique, stable (it is the save key) |
| `level` | a level id, or `"any"` |
| `phase` | a `SessionPhase` name, or a list of them. The mark can only be visible in these phases |
| `trigger` | condition that makes the mark eligible |
| `anchor` | what it points at (see "Anchors") |
| `text` | the line, at most 14 words, plain ASCII; may contain tokens |
| `dismissOn` | condition that retires the mark while it is visible: the player doing the thing, or, for marks about something the player only watches, the moment having passed |
| `once` | `true`: never again in this save once retired. `false`: retired per level visit instead |
| `skipIf` | optional. If true while the mark has not been shown, it is retired silently: the player already knows |
| `urgent` | optional. The mark is about something happening right now in the world |
| `linger` | optional seconds the mark may stay up before fading by itself (default `limits.defaultLingerSeconds`) |
| `teaches` | optional note for humans; ignored at runtime |

`limits`: `maxVisible` 1, `minGapSeconds` 1.5, `maxPerPhaseVisit` 2 (ordinary marks),
`maxUrgentPerPhaseVisit` 2, `defaultLingerSeconds` 10, `minShownSecondsToCount` 1.5.

### Lifecycle

Every mark is `unseen`, `visible` or `done`. `done` ids are stored in the save.

Each UI frame, with the layer enabled and no story dialogue box open:

1. **Skip.** For every `unseen` mark whose `level` matches: if `skipIf` is true, set it `done`.
2. **Visible mark.** If a mark is visible:
   - `dismissOn` true: retire it as *done by the player* (a short tick, then fade). → `done`.
   - the phase is no longer one of its `phase` values, or it has been up for `linger` seconds:
     fade. If it was visible for at least `minShownSecondsToCount` it is `done`; otherwise it goes
     back to `unseen` and may show again.
3. **Choose.** If nothing is visible, at least `minGapSeconds` have passed since the last mark
   faded, and the phase-visit budget is not spent: take the first `unseen` mark in file order,
   urgent marks first, whose `level` and `phase` match and whose `trigger` is true. Bind its
   subject (below), resolve its anchor and show it.
4. **Urgent pre-emption.** If an ordinary mark is visible and an urgent mark becomes eligible, the
   ordinary one fades under rule 2's "phase is no longer" branch and the urgent one shows at once
   (no gap).

A mark that fades without the player doing the thing is still spent. That is deliberate: it was
said once, the level will say it again by itself, and repeating it is the patronising option.

### Conditions

A condition is a JSON object with **exactly one key**. `N` below means a number (exact match) or
`{ "min": a, "max": b }` with either bound optional, both inclusive.

Combinators: `all` (list, every one true), `any` (list, at least one true), `not` (one condition).

**Session state**, read from `SessionView`:

| Predicate | Argument | True when |
|---|---|---|
| `firstTimePhase` | phase | the current phase is this phase and this is the first visit to it in the save |
| `phaseIs` | phase or list | the current phase is one of these |
| `phaseElapsed` | N seconds | wall seconds since the current phase visit began |
| `shownFor` | N seconds | wall seconds this mark has been visible. `dismissOn` only |
| `beat` | N | `view.beat`, the master playhead |
| `takeProgress` | N, 0..1 | `localProgress` of the deck whose status is `recording`; false when none is |
| `tapesCommitted` | N | number of decks with status `committed` |
| `deckStatusIs` | `{ deck, status }` | `deck` is `0..3`, `"active"` (`view.active`) or `"any"`; `status` is a `DeckStatus` |
| `speedsOffered` | N | `view.speeds.size()` |
| `activeSpeedIs` | N | the active deck's `speed`; false with no active deck |
| `endModesOffered` | N | `view.endModes.size()` |
| `activeEndModeIs` | end mode | the active deck's `endMode` |
| `outcomeIs` | `win`, `fail`, `none` | `view.outcome` is null (`none`), or its `win` flag |
| `retriesThisTake` | N | `retryTake` actions since the last `commit`, `resetAll` or level load |
| `levelsCleared` | N | `SaveData.cleared.size()` |

**Selves and the world**, read from the current `FrameSnapshot`:

| Predicate | Argument | True when |
|---|---|---|
| `liveSelfIs` | `alive`, `recGhost`, `desynced` | the live actor's `life` is that value (`desynced`: `life == alive` and not `synced`) |
| `selfIs` | `{ who, state }` | `who` is `"previous"` (any present tape other than the live one) or `0..3`; `state` is `alive` (alive and synced), `ghost`, or `desynced` (alive, not synced). Binds the lowest matching tape as subject |
| `selfFateChanged` | `{ who, to }` | compares a committed tape with the **latest resolved run**, using that deck's `stateMarks`. `to: "dead"`: a `selfDeath` event for the tape arrived in this phase visit and the deck has no `death` state mark. `to: "alive"`: the deck has a `death` state mark at beat D, `view.beat >= D + 0.5`, and the tape's actor is `alive`. Binds the tape as subject |
| `liveSelfNear` | `{ kind, tiles }` | straight-line distance from the live actor to the nearest entity of `kind` is at most `tiles`. Kinds: `enemy` (alive ones), `breakable` (unbroken ones), `switch`, `plate`, `door`, `core`, `exit`, `laser`, `trap` |
| `liveSelfTravelled` | `{ tiles, scope? }` | path length the live actor has covered within `scope` is at least `tiles` |

**History**:

| Predicate | Argument | True when |
|---|---|---|
| `eventSeen` | `{ type, tape?, detail?, detailPrefix?, detailSuffix?, detailIn?, target?, scope?, count? }` | at least `count` (default 1; an `N`) `SimEvent`s of `type` matching every given filter arrived within `scope`. `tape`: `"live"`, `"previous"`, `"any"` or `0..3`. The `detail*` filters test `SimEvent.detail`. `target`: `enemy`, `mech` or `trap`, by what `SimEvent.id` names. Binds the most recent matching event as subject |
| `inputUsed` | `{ input, scope?, count? }` | the player used `input` at least `count` times (default 1) within `scope`. Inputs: `move`, `aim`, `light`, `heavy`, `dodge`, `ranged`, `interact`, `ability`, or `"any"`. A button counts per press. `move` and `aim` count one use each time the input leaves its dead zone after 0.25 s neutral (for a mouse, each time the pointer moves 24 px) |
| `inputNotUsedFor` | `{ input, seconds }` | the phase is `recording` and `input` has not been used for `seconds` of this phase visit (counted from the start of the visit if never used) |
| `sessionActionUsed` | `{ action, scope? }` | a `SessionAction` (one, or any of a list) was taken within `scope` |
| `markDone` | mark id | that mark is `done`, whether shown, faded or skipped |

**Scopes.** `scope` defaults to `"phase"`.

| Scope | Since |
|---|---|
| `shown` | this mark became visible. `dismissOn` only |
| `phase` | the current phase visit began |
| `take` | the most recent count-in began; so it spans a recording, its review and its decision |
| `attempt` | the level loaded or `resetAll` was last used |
| `level` | the level loaded |
| `save` | ever; persisted |

**"live" and "previous".** During `countin` and `recording` the live tape is `view.active`. In
`review`, `decision` and `cinematic` it is the tape recorded in the current take (the deck that is
`pending`, or the last one committed). `previous` is every other tape that exists.

**Which events count.** Every `SimEvent` the presentation receives: the live simulation during
`recording`, and the replayed `Resolution.events` during `review` and `cinematic`.

**Subject.** When a trigger becomes true, its subject is taken from the first satisfied
`eventSeen`, `selfIs` or `selfFateChanged` leaf, depth-first, ignoring anything under `not`. An
event subject carries `tape`, `id`, `x`, `y`; a self subject carries `tape`. Anchors ending in
`:subject`, the `world:event` anchor and the `{tape}` token read it. It is fixed for as long as the
mark is visible.

### Anchors

| Anchor | Points at |
|---|---|
| `deck:<n>` | cassette deck `0..3`, `active`, or `subject` (the subject's tape) |
| `deck.<part>` | part of the active deck: `speed` (readout and selector), `endMode`, `reels`, `status` |
| `ruler` | the master beat ruler as a whole |
| `ruler.playhead` | the playhead line |
| `ruler.lane:<n>` | one cassette's lane: `0..3`, `active`, `subject` |
| `objective` | the objective chip (the briefing card's objective line during `briefing`) |
| `countin` | the count-in numerals |
| `world:self` | the live Moxie |
| `world:self:<n>` | the self of tape `0..3` or `subject` (the projection, if desynced) |
| `world:spark:<n>` | that self's recovery spark |
| `world:entity:<id>` | an enemy, mechanism or trap by id, or `subject` (the subject event's `id`) |
| `world:nearest:<kind>` | the nearest entity of a `liveSelfNear` kind to the live self |
| `world:event` | the fixed world position of the subject event |
| `prompt:<action>` | the button prompt for an input (`move`, `aim`, `light`, ...) or a `SessionAction` (`commit`, `resetAll`, ...). If that prompt is not on screen, the mark draws the glyph itself in the coach slot |

World anchors follow their target every frame. If an anchor cannot be resolved (entity gone,
off-screen, deck hidden), the mark is drawn in the coach slot with no leader line; it is never
dropped for that reason.

### Text tokens

| Token | Becomes |
|---|---|
| `{btn:<action>}` | the current device's glyph for that input or session action, from the `ButtonPrompt` map pushed through `set_bindings` |
| `{speed}` | the active deck's speed as the deck prints it ("2x", "0.5x") |
| `{tape}` | the subject's cassette as the HUD names it ("Tape A"). Failure hints use it for the captured tape |

A token counts as one word. Text is plain ASCII, like the story lines.

### Presentation

- A small label, one line (wrapping to two below about 420 px), with a thin leader line to its
  anchor and a dot on the anchor. Edge colour: the active cassette's colour for deck, ruler and
  self anchors; neutral otherwise. No panel behind the world, no dimming, no icon of a face.
- Placement: beside the anchor, on the side with more free space, never overlapping the four decks
  or the ruler body (the label sits above the dock for dock anchors), never over the objective
  chip, and inside the playfield's safe area. The fallback "coach slot" is centred just above the
  dock.
- In: 120 ms fade and 6 px slide. Out by the player: the dot ticks and the label fades in 200 ms.
  Out by time or phase: plain 300 ms fade. No sound of its own: the game's sounds are quantised
  to the music and a tutorial blip would not be.
- Colour-blind patterns setting: the leader dot uses the cassette's pattern as the decks do.

### Living with the story layer

`docs/story/INTEGRATION.md` defines dialogue boxes, `once.*` firsts and barks. The rules between
the two layers:

- A dialogue box always wins. Marks wait while one is open (boxes never open during `countin`,
  `recording`, `review` or `cinematic`, which is where most marks live).
- While a mark is visible, no bark is started. A bark already on screen delays the next mark until
  it has gone.
- The story's `once.firstDeath` / `firstGhostTake` / `firstDesync` lines play at the next
  `decision` or `review`; the marks `death-ghost`, `desync` and `spark` play during the take. On
  the decision screen the dialogue box comes first, then `ghost-not-kept` or `desync-lane`.
- On the take where `death-ghost` shows, suppress the `ghostTake` bark; where `rescue` shows,
  suppress the `rescue` bark; where `desync` shows, suppress the `desync` bark. The mark states the
  rule once; from then on the barks have the moment to themselves.
- `LevelDef.hints` (the setup hint line) and briefings are level content. Marks never repeat them:
  a mark is about a control or a rule, a briefing is about this room.

## Failure hints

`failure_hints.json` maps every failure note the simulation writes (`build_outcome` in
`core/objective.gd`, from `prototype/src/core/objective.ts`) to one nudge for the decision screen.

**When.** After the **second consecutive failed run with the same failure**, once per hint per
level visit, one hint per decision screen. The first failure gets only the simulation's own notes.

**Matching.** For each note of a failed resolved run, skip it if it matches an `ignore` pattern;
otherwise the first entry of `hints` whose `match` regex matches the whole note is its hint (file
order is priority: most specific and most actionable first). Regexes use `(?P<name>...)` groups so
the same source compiles in Godot's `RegEx` and in Python.

**Same failure.** A note's signature is its hint id plus the values of the groups named in
`signature`. The beat is never part of it (it shifts from take to take); the tape and the thing
that did it usually are. Keep a count per signature for the level visit. After each failed run,
signatures that occurred get +1 and signatures that did not are dropped. A win clears them.
`retryTake`, `commit` and `resetAll` do not.

**Choosing.** On entering `decision` after a failed run: of the hints with a signature count of 2
or more that have not been shown this visit, show the earliest in file order, under the notes list,
in the same label style as a coach mark anchored to the note it matched.

Every note the simulation can write, and where it lands:

| Note (from `build_outcome`) | Hint id |
|---|---|
| `Tape X's <kind> ... hit breakable wall <id> with momentum M; it needs K.` | `weak.breakable` |
| `... hit core <id> with momentum M; it needs K.` | `weak.core` |
| `... hit <id> but did no damage (shield, momentum M).` | `weak.shield` |
| `... (armour, momentum M).` | `weak.armour` |
| `... (no damage, momentum M).` | `weak.noDamage` |
| any other block reason | `weak.other` |
| `Tape X died at beat N: struck by boss <id> (remembering Tape Y).` | `death.bossRecall` |
| `... swept by boss <id>.` | `death.bossSweep` |
| `... struck by <type> <id>.` (grunt, stalker, brute, boss) | `death.struck` |
| `... burned by laser <id>.` | `death.laser` |
| `... shot by dart launcher <id>.` | `death.dart` |
| `... shot by a bolt.` | `death.shotStray` |
| `... shot by <type> <id>.` (turret, drone) | `death.shot` |
| `... skewered by spikes <id>.` | `death.spikes` |
| `... crushed by crusher <id>.` | `death.crusher` |
| `... burned by flame jet <id>.` | `death.flame` |
| any other cause | `death.other` |
| `Tape X desynced at beat N (blocked by door <id>); its spark never caught up.` | `desync.door` |
| `... (blocked by breakable wall <id>); ... never caught up.` | `desync.breakable` |
| `... (blocked by crusher <id>); ... never caught up.` | `desync.crusher` |
| `... (blocked by a wall); ... never caught up.` | `desync.wall` |
| `... (manual desync); ... never caught up.` | `desync.manual` |
| any other cause, never caught up | `desync.other` |
| `Tape X ended the run desynced: ...` | `desync.ended` |
| `No self survived to the end: ...` | `noSurvivor` |
| `Tape X desynced ...; its spark caught up at beat M.` | `desync.caughtUp` |
| `Objective not complete: <text>. No alive, synced self was in the exit ...` | `objective.reachEnd` |
| `... The encounter has not ended yet.` | `objective.reachEarly` |
| `... Still standing: <list>.` | `objective.eliminate` |
| `... Not activated: <list>.` | `objective.activate` |
| `... <id> survived with H of M hp.` | `objective.boss` |
| `... The required condition never happened.` | `objective.signal` |
| `Objective not complete: <text>.` with nothing after it | `objective.other` |
| `Objective complete at beat N: ...`, `Survivors: ...`, `... There is no boss in this level.` | ignored |

The objective hints sit last because an objective note is present in almost every failure and says
the least; a death, a weak hit or a desync is nearly always the reason behind it.

If a note template in `objective.gd` or a cause string in `core/` changes, change the regex here
and run the validator: it replays every note found in `tests/goldens/*.json` (134 distinct strings
from the real simulation) and fails on any note that resolves to nothing.

## Integration

Nothing outside `data/onboarding/` and this file was touched. To wire it:

1. **Director** (suggested `game/onboarding/coach_director.gd`, `RefCounted`). Loads
   `coachmarks.json`, owns the lifecycle above, and is fed once per rendered frame with:
   `SessionView`; the frame's `FrameSnapshot` and `Array[SimEvent]` (the same ones put in
   `RenderFrame`); wall `dt`; the inputs used this frame (the eight names above, from the input
   module); the `SessionAction`s taken this frame; `SaveData.cleared.size()`; whether a dialogue
   box or bark is on screen. It outputs at most one `{ id, text, anchor, subject, state }` for the
   HUD. Keep it free of nodes so it can be unit-tested with scripted feeds.
2. **Save.** Add to `SaveData`: `onboarding: { done: [mark ids], phaseVisits: { phase: count },
   facts: [strings] }` and the setting `coachMarks: bool` (default true) with a row in the settings
   menu. `facts` holds the `scope: "save"` conditions that have come true; today those are: three
   tiles travelled, a live kill, a live light swing, a live heavy swing, a live interact, two
   dodges, and each of `speedUp`/`speedDown`, `cycleEndMode`, `skip`/`endAttempt`, `resetAll` used.
3. **HUD.** A `HudCoach` control above the dock, and an anchor resolver on the HUD:
   `anchor_rect(anchor: String, subject) -> Rect2` built from what exists already
   (`HudDeck.geometry()` for `deck:*` and `deck.*`, `HudRuler.body_rect()` / `lane_span()` for
   `ruler*`, the objective, count-in, setup and decision panels for the rest). World anchors need a
   world-to-screen call: add `world_to_screen(x, y) -> Vector2` beside
   `WorldViewBase.screen_to_world` (it is `camera.unproject_position` of `RenderCtx.to_scene`).
4. **Prompts.** `set_bindings` carries `SessionAction` and `ActionKind` prompts today. Add `move`
   and `aim` entries so `{btn:move}` and `{btn:aim}` resolve ("WASD" / "L stick", "Mouse" / "R stick").
5. **Failure hints.** A small `FailureHints` helper with `on_resolved(outcome) -> String` (empty
   when there is nothing to say) implementing the streak rules, called when a run resolves; the
   decision panel draws the returned line under its notes.
6. **Story layer.** Apply the bark-suppression rules in "Living with the story layer".
7. **Export.** Include `data/onboarding/*.json` as non-resource files; exclude `validate.py`.
8. **Level ids.** When the campaign levels land, check their ids against the ten level-bound marks
   (`brief-objective`, `deck-armed`, `move`, `aim`, `light`, `ruler-lane` on 01; `speed-pick`,
   `heavy` on 02; `same-beat` on 04; `knockback` on 06) and against `vocabulary.json` `levels`.

## Validation

`python -I data/onboarding/validate.py` (no Godot, under a second) checks that:

- all three JSON files parse and every mark has exactly the documented fields;
- every `level`, `phase`, anchor, token and every leaf of every `trigger`, `dismissOn` and `skipIf`
  is in `vocabulary.json`, with correctly shaped arguments; `shown` and `shownFor` appear only in
  `dismissOn`; `markDone` references exist and do not form a cycle; subject anchors have a leaf
  that binds a subject; `firstTimePhase` names a phase the mark can be in;
- every line is at most 14 words and plain ASCII;
- each topic in the brief is covered by a named mark;
- every hint regex compiles, each example resolves to its own hint first, signature groups exist,
  and every note in the goldens resolves to a hint or an ignore pattern;
- this document names every predicate, anchor form, token, mark id and hint id.

## Known gaps

- **No runtime.** The director, the HUD control, the save fields and the hint helper are specified
  here and not built; nothing has been seen on screen. Word counts and vocabulary are checked;
  timing values (gaps, linger, distances in `liveSelfNear`) are first guesses to tune in playtests.
- **Levels 01-09 do not exist yet.** The arc follows the brief and the story keys. `same-beat`
  assumes level 04 uses a shielder (its trigger is a `clang` with detail `shield`); `knockback`
  assumes level 06 is where shoving matters; `heavy` assumes level 02 has a breakable wall. Text
  that leans on level content should be re-read once the rooms and their briefings are written.
- **The story's level 01 outro implies two takes there** ("There were two of me in there"), while
  the brief puts the first overdub in 03. The overdub marks are condition-driven, so they fire
  wherever the second cassette first appears, but the level 01 budget gets tighter if that is 01.
- **Trap notes and trap events** are taken from `docs/TRAPS.md` and the prototype source; no golden
  contains a trap death, so `death.spikes`, `death.crusher`, `death.flame` and `death.dart` are
  checked against hand-written examples only. The same holds for
  `death.shotStray`, `desync.breakable`, `desync.crusher` and `objective.reachEarly`.
- **Not covered by marks:** ranged attacks, gear abilities, the results screen and loot.
- `selfFateChanged` relies on `DeckView.stateMarks` reflecting the latest resolved run, as the
  prototype's session does; if the Godot session fills it differently the predicate needs a direct
  feed of the previous run's deaths.
