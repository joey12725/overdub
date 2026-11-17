# The cinematic director

Requirements: chapter 16 "The cinematic result" (CINE-01..05), MUSIC-13, PILLAR-06. A winning
attempt culminates in an automatic, non-interactive replay at the world's true beat speed that is
"as cinematic as possible" while preserving exactly what happened and staying understandable:
"the payoff is seeing how the solution works, not hiding the causal chain under effects".

The replay itself (frames, events, timing) belongs to the session and the world view. This module
decides **where to look**. It never changes the resolved run, never stretches or re-times a tape
(CINE-04), and the cut always runs the encounter's own musical timeline, from beat 0 to the horizon
(CINE-05). Nothing here is marked LATER in the requirements; the requirements select no particular
camera technique (CINE-03), so this is one interpretation (see "Interpretation" at the end).

```
Resolution (events + snapshots) ─┐
LevelDef ────────────────────────┼─► CinemaPlanner.plan() ─► CinemaPlan (shot list, cues, callouts)
Context (earlier runs' deaths) ──┘                                │
                                         master beat ─► CinemaDirector.advance() ─► CinemaFrame
                                                                  │
                                    CinemaCameraBridge.pose() ◄───┘ (camera numbers)
```

## Files

| File | What |
|---|---|
| `cinema/cinema_grammar.gd` (`CinemaGrammar`) | Every constant the editor reasons with: kinds, framings, moves, emphasis, rules, the scoring table. |
| `cinema/cinema_types.gd` (`CinemaTypes`) | Small records: `Callout`, `Pane`, `Cue`, `Action`, `Context`. |
| `cinema/cinema_scene.gd` (`CinemaScene`) | Read-only view of the run: beat/sub conversion, positions of selves/enemies at any beat (dense or sparse snapshots), rooms (flood fill with doors and breakables as separators). |
| `cinema/cinema_analyzer.gd` (`CinemaAnalyzer`) | Reads the causal chain out of the events: actions (wind-up to impact) and candidate moments (cause to effect). |
| `cinema/cinema_moment.gd` (`CinemaMoment`) | One candidate story beat, with its score and deterministic order. |
| `cinema/cinema_planner.gd` (`CinemaPlanner`) | The editor: moments to shots, cut legalisation, bar snapping, cues. Pure. |
| `cinema/cinema_shot.gd` (`CinemaShot`) | One entry of the edit decision list. |
| `cinema/cinema_plan.gd` (`CinemaPlan`) | The output: shots, cues, moments, actions; lookup helpers; `timeline_text()`. |
| `cinema/cinema_director.gd` (`CinemaDirector`, a `Node`) | Runtime: plan + master beat to a `CinemaFrame`, eased. |
| `cinema/cinema_frame.gd` (`CinemaFrame`) | What the camera / fx owners apply this frame. |
| `cinema/cinema_camera_bridge.gd` (`CinemaCameraBridge`) | Pure maths: `CinemaFrame` to iso-camera view size / target / yaw / snap. |
| `cinema/cinema_golden.gd` (`CinemaGolden`) | Loads `tests/goldens/*.json` as planner input (tests and the demo). |
| `tests/cinema/*` | Headless suites and hand-built Resolution fixtures. |
| `tools/cinema_demo.gd` | Prints plans as readable timelines. |

## The editorial grammar

The editor thinks like the cutter of a heist film's payoff: *here is everyone at the start; watch
this, which causes that; and that is why it worked; here is who walked out.*

1. **Open wide on beat zero** with every self in frame and called out in its cassette colour
   (at least 2 beats, growing to a full bar when nothing important needs the time). A cause that
   happens inside the wide opening is already on screen, so the next story beat may start where
   the opening ends.
2. **Each link of the causal chain gets its beat, cause then effect.** A moment's shot starts a
   beat before its cause (`PRE_BEATS`) and holds 1.5 beats after its effect (`POST_BEATS`, 2 for
   the climax). Cause and effect that are close in space share a close-up; up to 12 tiles apart a
   two-shot holds both; further apart in one room a room shot; in different rooms a pan from cause
   to effect. Cause and effect more than 4 beats apart become two shots ("Cause - ...",
   "Effect - ...") and the time between belongs to someone else's story or coverage.
3. **Split-screen when the simultaneity is the point**: a plate held in one room while another self
   crosses the laser in another, a fooled boss memory striking an empty spot while the self is
   elsewhere, or two strong story beats competing for the same beats in different rooms. Two to
   four panes, each following one self, bordered in its cassette colour. The shot's own focus/span
   still frames all panes together, as the fallback for a renderer without split-screen.
4. **Hold wide enough that the viewer can always see why.** A shot that absorbs a second moment is
   loosened (close to two-shot to wide) until both are in frame. Gaps between story beats are
   *coverage*: the living selves, framed by where they are (room / two-shot / wide), at most 8
   beats per shot, with a slow orbit.
5. **Build to the objective's completion as the climax** (deep letterbox, push-in). The moment that
   completed the objective (the last kill, the multi-self kill on the shielder, the boss kill, the
   last core, the exit) is folded into the climax.
6. **End on the survivors.** The last shot calls out every survivor (role `survivor`); when the
   climax runs to the end it doubles as the finale, otherwise a finale pulls out over them.

Rules (each one is a test):

| Rule | Value |
|---|---|
| Cuts only on whole beats, preferring bar lines (a boundary moves up to `BAR_SNAP_BEATS` = 1 beat to land on one when it breaks nothing) | `CinemaShot.start_beat`/`end_beat` are ints |
| Minimum shot length | `MIN_SHOT_BEATS` = 2 |
| Shots cover `[0, horizon)` with no gap or overlap | |
| Never cut away from an action between its wind-up and impact, plus `FOLLOW_THROUGH_BEATS` = 0.25 beat of follow-through, when the next shot would not show it. Actions are self swings (wind-up read from the snapshots' anim states), shots fired (until the projectile lands), enemy telegraphs (until the strike, or a boss memory's remembered beat) and interactions. The cut moves later, or earlier, or the two shots merge. | `CinemaPlanner.blockers()` |
| At most one emphasis effect per shot: deep letterbox, time ripple or split | `CinemaShot.emphasis` |
| Shot count proportional to length | cap = `ceil(beats / 3) + 1`, at least 2 |
| Music-linked flourishes are cues, never cuts | `CinemaPlan.cues` |
| A chord flash never plays over a shot that already has an emphasis | |

Emphasis per kind (a shot carries at most one): climax and boss phase take the **deep letterbox**
(0.15 of the screen per bar instead of the resting 0.085); rescue, desync and a fooled boss memory
take the **time ripple** (peaks on the shot's key beat; they are the time-themed links); a split is
its own emphasis.

Camera moves: `hold`; `pushIn` (span x1.25 to x0.85 over the shot); `pullOut` (x0.85 to x1.35);
`pan` (target travels cause to effect between the cause and key beats); `orbit` (+-4 degrees of yaw
through the iso yaw, alternating direction on consecutive orbits). Climax pushes in, boss phase and
multi-kill orbit, rescue and fooled memory pull out, knockback / desync / mechanisms hold so the
geometry reads. Transitions are hard cuts on the beat, except a one-beat `blend` when the next shot
frames the same place at a different size.

Flourish cues (MUSIC-13): a `barSweep` on every bar line, a `chordFlash` where the level's chord
progression changes (`LevelMusicDef.progression`, `chord_bars` per chord), and an `impact` accent
on the exact beat of every kill-class moment and rescue. Cues fire once each; the fx layer plays
them.

## What the editor looks for

`CinemaAnalyzer` reads the events (and, for wind-ups and positions, the snapshots):

| Link | How it is read |
|---|---|
| multi-self kill | another self struck the same enemy within 1.5 beats before the kill (the shielder pincer: "the shield can only face one of them") |
| knockback delivery | a hit by another self within 6 beats moved the enemy at least 0.75 tiles before the kill (into another self's swing, or into a hazard) |
| trap kill | a kill with no self: the latest trap / laser / door event within 4 tiles in the 2 beats before ("spikes springs on grunt g1") |
| ranged kill | a projectile fired at least half a beat before its kill |
| save | the killed enemy was telegraphing on *another* self and never struck |
| rescue | a self that died in an earlier run of this attempt (`Context.prior_events`) is alive at that beat now; the cause is whoever killed, or hit, its killer first (that kill is folded in) |
| desync / resync | a desync, its resync, and the other self who opened the door / broke the wall that blocked it |
| opened-for / plate-hold | a switch, plate or strike changes a door / laser / wall favourably, and *another* self passes it while it stays so |
| mechanism / break | a state change nobody else uses |
| boss phase | an armour break and who did it |
| boss memory | a recall whose remembered self is not there (`bossFooled`) or is (`bossRecall`, folding in the death) |
| death | a self dying in the winning run (a sacrifice) |
| objective | the climax; absorbs the moment that completed it |

### Scoring table

objective-critical > kills > rescues / desync > mechanisms > movement.

| Kind | Score | Emphasis |
|---|---|---|
| climax (objective) | 100 | letterbox |
| finale / opening (structural) | 95 / 90 | none |
| bossFooled | 78 | time ripple |
| bossPhase | 72 | letterbox |
| multiKill | 66 | |
| knockback | 62 | |
| trapKill | 58 | |
| shotKill | 52 | |
| save | 50 | |
| bossRecall | 46 | |
| kill | 44 | |
| rescue | 42 (a rescue by a kill keeps the kill's score) | time ripple |
| desync | 38 | time ripple |
| plateHold | 36 | |
| death | 34 | |
| openedFor | 32 | |
| break | 28 | |
| mechanism | 18 (-6 if unfavourable) | |
| coverage | 5 | |

Bonuses: +8 when two or more selves are involved (coordination is the point of the game), +10
when the enemy is a named objective target, +12 to a kill that also saved another self.

### Overlap resolution (deterministic)

Moments are placed in priority order: higher score first, then earlier key beat, then
`KIND_ORDER`, then the first event index. Each moment's shot is placed in free time around its
*core* (cause to effect plus follow-through) as close to its desired lead-in / tail as the
neighbours allow, snapping to a bar line when within one beat. A moment that cannot get its own
time (overlap, or the shot cap) is folded into the shot already covering it: that shot's time is
extended where possible, its framing is loosened to include the newcomer, or, when both are strong
(score >= 30) and in different rooms, it becomes a split (up to four panes). A moment that fits
nowhere is listed as "not shown" in the timeline. Then gaps are filled with coverage, cuts are
legalised against the actions, boundaries snap to bars, and a final repair guarantees the
contiguity and minimum-length rules. Same input, same plan, byte for byte (tested on copies).

## API

```gdscript
# Planning (pure; call once when the session enters CINEMATIC):
var ctx := CinemaTypes.Context.new()          # optional; null is fine
ctx.prior_events = <selfDeath events of the earlier runs of this attempt>
var plan: CinemaPlan = CinemaPlanner.plan(resolution, level, ctx)

plan.shots            # Array[CinemaShot], contiguous, [0, horizon_beats)
plan.cues             # Array[CinemaTypes.Cue], sorted by beat
plan.moments          # every candidate story beat, with .shot (index or -1 = not shown)
plan.shot_at(beat) / plan.shot_index_at(beat) / plan.shot_for_event(event_index)
plan.timeline_text()  # the demo's readable timeline;  plan.to_dict() for JSON

# Runtime (a Node; one per cinematic):
var director := CinemaDirector.new()
add_child(director)
director.set_plan(plan)
var cf: CinemaFrame = director.advance(master_beat, frame.snap)   # every rendered frame
director.shot_started   # signal (index, shot)
director.cue_fired      # signal (cue)
CinemaDirector.sample_plan(plan, beat, snap)                      # pure, for scrubbing / tools

# Camera numbers:
var pose := CinemaCameraBridge.pose(cf, iso.aspect(), iso.fit_size())
pose.target, pose.view_size, pose.yaw_offset, pose.snap, pose.pane_view_sizes, pose.pane_targets
```

`CinemaShot` (the edit decision list entry): `start_beat`, `end_beat` (ints), `kind`, `framing`
(`wide` / `room` / `twoShot` / `close`), `focus_point` (+ `focus_to` for a pan), `focus_tape`
(self to track, -1 none), `focus_id` (enemy / mechanism), `span` (visible floor diameter in tiles),
`move`, `move_sign`, `emphasis`, `letterbox`, `ripple`, `panes`, `callouts`, `transition`,
`cause_beat`, `key_beat`, `reason` (why; never shown on screen), `shows` (every kind it explains),
`source_events` (indices into `Resolution.events`), `tapes`, `ids`, `score`.

`CinemaFrame` (per rendered frame): `target` (floor point, sim axes), `span`, `wide` (0..1 blend to
"fit the level"), `yaw_offset` (radians), `letterbox`, `ripple` (0..1), `emphasis`, `panes` (with
live focus), `split_t` (0..1 open), `callouts` (each with `strength` 0..1, fading in, swelling on the
key beat), `cut` (first frame of a hard cut: snap, do not damp), `cues` (crossed since last
advance), `progress`, `shot`, `shot_index`.

Callouts are captions-free: a self (`tape`) or an entity (`id`) to highlight in a cassette colour
(`color`; an entity takes the colour of the self acting on it) with a `role` (`cause`, `effect`,
`target`, `subject`, `survivor`).

Tracking: a shot with `focus_tape` follows that self's live position from the snapshot (80% for
close shots, 50% otherwise; a desynced self is framed between body and spark). Without a snapshot
the planned point is used, so `sample_plan` is pure either way.

## Integration (for the integration engineer; nothing outside `cinema/` was edited)

1. **Prior deaths (rescues).** The session should keep the `selfDeath` events of every resolved run
   of the current attempt that was not the win (each `_proceed_with(res)` with `!res.outcome.win`),
   cleared when the level is (re)started. Pass them as `CinemaTypes.Context.prior_events`. Without
   them the plan is still valid; it just cannot show rescues.
2. **Plan on entering CINEMATIC.** In `game/` (app or session wiring), when the phase becomes
   `SessionPhase.CINEMATIC`: `plan = CinemaPlanner.plan(session.resolution, level, ctx)`, create a
   `CinemaDirector`, `set_plan(plan)`. Planning is cheap (a few milliseconds on the goldens) and
   synchronous. Free the director on leaving the phase (results / skip).
3. **Per frame.** `var cf := director.advance(master_beat, render_frame.snap)` where `master_beat`
   is the beat of the playback clock (`render_frame.snap.beat` / `music.beat`). Carry `cf` to the
   world view; the simplest path is a new field on `RenderFrame` (game/contracts), e.g.
   `var cinema: CinemaFrame = null`, filled only in cinematic mode.
4. **Camera (world/world_camera.gd, CINEMATIC branch of `update()`).** When a `CinemaFrame` is
   present, replace the drifting push-in logic with:
   ```gdscript
   var pose := CinemaCameraBridge.pose(cf, aspect(), fit_size())
   size = pose.view_size
   var p := clamp_target(pose.target.x, pose.target.y, size, 1.5)
   tx = p.x; tz = p.y
   target_yaw = ISO_YAW + pose.yaw_offset
   if pose.snap:                 # a hard cut on the beat: no damping
       view_size = size; target_x = tx; target_z = tz; yaw = target_yaw
   size_rate = 6.0; move_rate = 6.0   # the director already eases inside a shot
   ```
   Keep the existing drift as the fallback when no plan exists. The fx layer's focus requests
   (`ctx.focus`) should be ignored while a plan drives the camera, or they will fight it.
5. **Letterbox, ripple (fx/).** FxDirector eases toward its mode profile's letterbox (0.085 in
   cinematic). With a `CinemaFrame`, use `cf.letterbox` as that target (it is already eased; the
   deep letterbox is 0.15). Feed `cf.ripple` (0..1) to a screen-space time-ripple / chromatic
   distortion in the post stack; it is 0 outside time-ripple shots.
6. **Cues (fx/ and audio-free).** Play `cf.cues` (or connect `cue_fired`): `barSweep` = the beat-ruler
   / floor-rune sweep the fx layer already does on bars, `chordFlash` = the palette flash (FxDirector
   currently detects chord changes itself; switch it to these cues in cinematic mode so a flash
   never lands over another emphasis), `impact` = speed lines / ink splash at `cue.point` in
   `OD.tape_color(cue.tape)`.
7. **Callouts (actors/).** For each `cf.callouts` entry, rim-light or outline that self (`tape`) or
   enemy / mechanism (`id`) in `color` at `strength`. No text.
8. **Split-screen (world/).** When `cf.panes` is non-empty, render each pane with its own Camera3D
   in a SubViewport (or a viewport-rect camera) at `pane.rect` (0..1 of the screen), looking at
   `pose.pane_targets[i]` with `pose.pane_view_sizes[i]`, bordered in `pane.color`, opening with
   `cf.split_t`. If split-screen is not implemented, ignoring the panes is safe: the shot's own
   target / span frames every pane's subject together.
9. **Docs.** Add `cinema/  cinematic director: shot planner + runtime framing` to the layout in
   docs/GODOT-PORT.md.

## Tools and verification

```
bash tools/gd test cinema                                    # both suites
bash tools/gd script res://tools/cinema_demo.gd              # a representative set of goldens
bash tools/gd script res://tools/cinema_demo.gd ghost-rescue # one scenario
bash tools/gd script res://tools/cinema_demo.gd --all        # every golden
bash tools/gd script res://tools/cinema_demo.gd --json NAME  # the plan as JSON
bash tools/gd script res://tools/cinema_demo.gd --stats      # kinds detected / shown over all goldens
```

Timeline legend: `|` bar line, `.` beat; in a shot's row `=` is screen time and `*` its key beat.
Example (ghost-rescue):

```
horizon 16 beats (4 bars), 4 shots (cap 7), 8 cues, 3 moments
        |...|...|...|...
  #0   ==
       b  0-2   opening    wide     hold     cut    AB  [A B]
  #1     =*==
       b  2-6   climax     close    pushIn   cut    AB +letterbox track A  [A g1 B t1 gate]
               Objective: Destroy the grunt - A takes down grunt g1 (light); also Last take A died
               here at beat 2.3 (shot by turret t1). This time B takes out turret t1 first - A lives
  #2         ======
       b  6-12  coverage   wide     orbit    cut    AB  []
  #3               ===*
       b 12-16  finale     wide     pullOut  cut    AB  [A B]
```

Tests (`tests/cinema/`): determinism (same plan from a copy and from a second call); planning does
not touch the Resolution; every rule above checked on all 162 goldens (contiguity, start 0, end on
the horizon, minimum length, one emphasis, panes only on splits, key beat on screen, the cut rule
by the planner's definition and by an independent narrow one, the proportional cap, cue placement);
opening wide with every self; finale calls out every survivor; synthetic and golden cases for the
rescue, shielder pincer, knockback, desync + reopener, plate hold, opened-for, trap kill, save,
sacrifice, boss phases, boss memory (recall and fooled with a time ripple), a split in cassette
colours across far rooms, a busy fight, a wind-up straddling the natural cut; an event-free run is
one graceful wide orbit; an empty Resolution still plans. The runtime: purity of `sample`, cuts
only at shot boundaries, cues once each and not refired on seeking back, eased letterbox, push-in /
ripple / orbit / split shapes, tracking, the camera bridge maths, the node's signals in the tree.

## Interpretation and known limits

- The requirements leave camera technique open (CINE-03). This document's grammar is the
  director's interpretation; every value is a constant in `CinemaGrammar` for tuning.
- Goldens carry sparse snapshots (every 60 substeps); wind-up starts then fall back to fixed
  lengths (0.35 beat light, 0.7 heavy). The real Resolution has dense frames and the analyzer reads
  the anim states.
- Most goldens are one room; split-screen appears rarely there (once in 162) and mainly in larger
  levels.
- Off-screen story beats that lose their slot to a higher one are listed as "not shown" in the
  timeline; there is no on-screen indicator for them.
