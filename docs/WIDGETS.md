# OVERDUB — force and danger widgets (`ui/widgets/`)

In-world and HUD widgets that make momentum, thresholds, the boss's memory and off-screen activity
legible. Every widget is driven purely by data the game already has (`FrameSnapshot`, `SessionView`,
`SimEvent`, `LevelDef`, `ResolvedLoadout`, `BossMemory`, `GearItem`); none of them reads the sim,
the scene tree outside itself, or the clock beyond animation.

| Requirement | Widget |
|---|---|
| HEALTH-03 bosses have health bars; BOSS-01..03; ch.10 "Fairness" (cues that reveal adaptation) | `WidgetBossBar` |
| MOM-01 "a legible common cause"; MOM-03 direction; MOM-04 light vs heavy; Scenario K | `WidgetMomentumGauge`, `WidgetThresholdBadges` |
| HEALTH-02 two- and three-hit enemies | gauge damage ticks, `WidgetThresholdBadges` hit-point pips |
| ch.16 "supplements off-screen activity with an interface indicator"; UI-03; OPEN-20 | `WidgetOffscreenIndicators` |
| GEAR-02 / APPAREL-02 loot is found physical equipment; APPAREL-03 effect lines | `WidgetLootReveal`, `WidgetLootCard` |
| `beatSight` ability (Click-Track Visor) | `WidgetThreatTicks` |

Nothing here is marked LATER or rejected in the requirements. Chapter 16 leaves "how to view other
rooms" open; the chevrons *supplement* whatever framing the camera does, they decide nothing.

## Files

```
ui/widgets/
  widget_math.gd           WidgetMath        pure: momentum preview (calls Tuning), targets, ticks, pips, failure text
  widget_offscreen.gd      WidgetOffscreen   pure: safe rect, edge projection, perimeter clustering
  widget_boss_model.gd     WidgetBossModel   pure state: hp, ghost bar, phase marks, armour, memory tell
  widget_threat.gd         WidgetThreat      pure: beatSight ticks on the ruler
  widget_projector.gd      WidgetProjector   sim point -> screen (Camera3D or a Callable)
  widget_draw.gd           WidgetDraw        drawing helpers + code-drawn icons (own copy; never borrows ui/hud internals)
  boss_bar.gd/.tscn        WidgetBossBar
  momentum_gauge.gd/.tscn  WidgetMomentumGauge
  threshold_badges.gd/.tscn WidgetThresholdBadges
  offscreen_indicators.gd/.tscn WidgetOffscreenIndicators
  threat_ticks.gd/.tscn    WidgetThreatTicks
  loot_card.gd             WidgetLootCard
  loot_reveal.gd/.tscn     WidgetLootReveal
  world_overlay.gd/.tscn   WidgetWorldOverlay  (badges + gauge + chevrons + boss bar behind one call)
tests/ui_widgets/          headless suites (52 tests) + widget_fixtures.gd (WidgetFixtures, shared fake data)
tools/shot_widgets.gd      screenshots of every widget, warm and dark backdrops
```

Sizes follow the shared fluid unit (`UiPalette.unit_for(viewport size)` via `WidgetDraw.unit`), so
the widgets scale with the HUD from 720p to 4K. Colours and fonts come from `UiPalette`; the loot
prompt's buttons use `res://ui/theme/od_theme.tres`. Every state carries an icon and a word as well
as a colour (NEW-11).

## The one-call integration: `WidgetWorldOverlay`

The simplest wiring mounts one overlay for the in-world widgets and the boss bar.

```gdscript
var overlay := (load("res://ui/widgets/world_overlay.tscn") as PackedScene).instantiate() as WidgetWorldOverlay
# on the UI CanvasLayer, BELOW the HUD (so the dock draws over chevrons), full rect, mouse-transparent
overlay.load_level(level, resolved_loadout, boss_memory)   # boss_memory: SimConfig.boss_memory or null
overlay.set_camera(world_camera)                            # the world view's Camera3D
hud.bottom_inset_changed.connect(overlay.set_bottom_inset)  # keep chevrons above the dock
# every rendered frame (the same data the renderer gets):
overlay.set_aim(live_aim)                                   # optional: PlayerInput.aim in sim radians; NAN = body facing
overlay.update_frame(frame.snap, session_view, frame.events)
# when committed tapes change (commit / resetAll):
overlay.set_boss_memory(new_memory)
```

Phase rules inside `update_frame`: the gauge shows only while `SessionPhase.RECORDING` and the live
self is not a playback ghost; badges and chevrons hide in `CINEMATIC` (CINE-01/02); the boss bar
shows whenever a boss is in the snapshot. Each child is also usable on its own (below).

`set_camera` uses `Camera3D.unproject_position` on `RenderCtx.to_scene(x, y, h)`, which yields the
camera viewport's coordinates; that matches the UI layer when it shares the root viewport (the
project's `canvas_items` stretch). If the overlay ever sits under an offset, set
`overlay.projector.canvas_offset`. Tests and screenshots use `WidgetProjector.for_callable`.

## Widgets

### `WidgetBossBar` (`boss_bar.tscn`) — HEALTH-03, BOSS-01..03

Top-centre bar: name, `PHASE n` with three phase pips, health with a damage-lag ghost (holds 0.55 s
then drains), phase notches at the hp fractions where `BossBehaviour.boss_phase_for` changes phase
(found by calling it), hit flash. Armour row: plates left (3, one per phase, as the model's
`Armor_1..3` hide), `FRONT ARMOURED · WATCHING` with an eye and the cassette badge of
`EnemySnap.target` (its attention: the one self that can never hurt it), `STAGGERED — GUARD DOWN`
while staggered, `CLANG — HIT ITS BACK` on an armour clang. Right: `REMEMBERS` with a chip per
committed tape in its `BossMemory`.

The memory tell: while `EnemySnap.boss_recall`, a sticker hangs under the bar in the punished
cassette's colour — reels spinning backwards, the cassette letter, `MEMORY`, "punishing where TAPE B
WAITED/STRUCK · lands in N beats" (landing beat from the `bossRecall` event's power; estimated from
the telegraph's `state_t` if the event was missed), and that tape's `REMEMBERS` chip lights. That is
what the player exploits: while it punishes tape B's old spot, every other tape can hit its back.

```
set_boss_name(name)  set_memory(memory)  update_from_snapshot(snap)  update_boss(e, beat)
on_events(events)    clear()             top_inset() -> float       signal top_inset_changed(px)
```

### `WidgetMomentumGauge` (`momentum_gauge.tscn`) — MOM-01..04, HEALTH-02, Scenario K

A two-band arc beside the live self, following her on screen, on the side away from her target
(and never off-screen). Inner band = next LIGHT, outer = next HEAVY. Solid fill = momentum if she
pressed now; pale fill = how far it goes if she ran fully into the swing; a `1×` notch = the same
heavy on a 1× tape. One segment = one pip = `Tuning.DAMAGE_UNIT` of momentum, the same unit as the
badges. Ticks: a breakable/core threshold, an enemy's damage points (skull = KO) plus the brute's
shove line, or the boss's stagger line — red until met, green once met. Under it, a speed sticker
(`2×`) with three chevrons lit by how much of her motion goes into the swing (red, pointing back,
when she moves away). Above it, the target caption: "WALL NEEDS 5 — run INTO a heavy / needs a 2×
tape / heavy breaks it", "BRUTE 2/3 HP — H: 1 hit · L: 2 hits", "STAGGER NEEDS 4". After a live-tape
`clang` / `whiff`, a red sticker says why: "CLANG needs 5 · had 3 — run in or use a faster tape",
"NO DAMAGE", "ARMOUR — hit its back with another", "SHIELD — another tape must follow up", "WHIFF".

All numbers come from `WidgetMath.gauge_state`, which calls `Tuning.strike_approach`,
`Tuning.swing_momentum`, `Tuning.strike_momentum`, `Tuning.strike_damage`, `Combat.core_threshold`,
`BossBehaviour.BOSS_STAGGER_MOMENTUM` and `BruteBehaviour.BRUTE_POISE_MOMENTUM`. The live self's
local velocity is `ActorSnap.vx/vy ÷ tape speed` (snapshot velocity is master-space), so tape speed is
counted once, exactly as the sim does.

```
setup(level, loadout)  set_aim(angle)  update_gauge(snap, view, projector)  on_events(events)
set_state(state, anchor, target_screen := NAN)  settle()  show_failure(info)
```

### `WidgetThresholdBadges` (`threshold_badges.tscn`) — Scenario K, HEALTH-02

Screen-aligned stickers anchored in the world: on each unbroken breakable / inactive core, its icon,
the requirement as diamond pips (fractional thresholds fill part of the last pip) and the number.
While recording, the pips fill in the live cassette's colour up to what her heaviest swing could
reach at this tape speed running fully into it; a met requirement shows a tick, an unreachable one
names the slowest offered speed that reaches it (`2×`), or a cross. Over multi-hit enemies
(`max_hp >= 2`, not the boss): hit-point pips, plus a cyan shield while a shielder's shield is up.
`build_badges(...)` is static and returns the draw list (tested headless).

```
setup(level, loadout)  update_badges(snap, view, projector)
```

### `WidgetOffscreenIndicators` (`offscreen_indicators.tscn`) — chapter 16, UI-03

Edge chevrons for every self outside the safe rect (cassette colour, letter badge, state icon:
alive heart / recording-ghost outline / ghost / desync squiggle), each recovery spark (a spark in its
cassette colour), and each telegraphing enemy (red diamond with "!", throbbing faster as the
telegraph fills). A self that swings/fires/dodges/interacts pulses (from events, or from an anim
change when events are not forwarded). Items that pin within 4.5 units of each other along the
border merge into one chevron with a stack (`+N` past four); clustering walks the perimeter as a
loop, so a group wraps round corners. The safe rect excludes the boss bar (`top`) and the HUD dock
(`bottom`).

```
set_insets(top, bottom)  update_indicators(snap, projector)  on_events(events)
static collect_items(snap, projector, pulses)
```

### `WidgetThreatTicks` (`threat_ticks.tscn`) — beatSight

A Control for the HUD engineer to mount on the master ruler. It draws `SessionView.threat_beats`
(which the session fills from `ODSim.threat_beats` only when the loadout has `beatSight`) as red
markers that grow and throb within one beat of landing, merges near-coincident beats (`×2`), shows a
beat countdown (`3`, `2`, `1`, `NOW`) over the next one when it is four beats away or less, and a
faint bracket for the look-ahead window (`Abilities.BEAT_SIGHT_LOOKAHEAD_BEATS`).

```
set_track(track_x, track_w, horizon_beats)   # the ruler's track, in THIS control's x coordinates
set_threats(beats, now_beat)  set_view(view)  set_pulse(beat_pulse)
```

### `WidgetLootReveal` (`loot_reveal.tscn`) and `WidgetLootCard` — GEAR-02, APPAREL-02/03

A full-screen modal moment: the kit chest (`assets/models/kit/chest__upper.glb` for upper/mid,
`chest__lower.glb` for lower/core; a drawn chest if missing) drops in, rattles and opens in its own
SubViewport (its `Lid` rotates −110° about local X, per the kit manifest note), light rays in the
found items' slot colours, then each item pops out as a sticker card: icon
(`res://assets/ui/icons/gear/<id>.png`, else a drawn slot glyph), slot chip, name, effect line, and a
NEW stamp for items not in `owned_before`. Then `EQUIP NOW` / `LATER` (and a "gear swaps freely
between levels" line). No loot: "NOTHING NEW IN THIS ONE" and `CONTINUE`.

```
show_loot(items: Array[GearItem], theme := LevelTheme.UPPER, owned_before := [])
skip()  seek(t)  duration()
signal choice_made(equip_now: bool, item_ids: PackedStringArray)   # once; ids = the found items either way
signal reveal_finished()
```
`ui_accept` skips the animation, then means EQUIP NOW; `ui_cancel` skips, then means LATER. The
widget equips nothing itself.

## Integration steps (for the integration engineer)

1. **World overlay** — in `ui/ui_root.gd` (menus owner) or the game wiring: instance
   `res://ui/widgets/world_overlay.tscn` as a child of the UI root *before* the HUD (so the HUD
   draws on top), call `load_level` when a level loads, `set_camera(world_view camera)`, connect
   `hud.bottom_inset_changed` → `overlay.set_bottom_inset`, and call
   `overlay.update_frame(frame.snap, session_view, frame.events)` wherever `render(frame)` and
   `update_hud(view, pulse)` are called each frame. Optionally `overlay.set_aim(input.aim)` while
   recording. The world view needs to expose its `Camera3D` (it is `RenderCtx.camera`; a getter on
   `WorldViewBase` or passing `ctx.camera` up is enough). The boss memory is `SimConfig.boss_memory`
   (built by `BossMemoryLib.build_boss_memory` from committed tapes); pass it on level load and on
   every commit / reset.
2. **Camera framing** — `overlay.boss_bar.top_inset_changed(px)` reports the pixels the boss bar
   covers at the top; the camera may treat it like the HUD's bottom inset if the boss should never
   sit under the bar.
3. **beatSight on the ruler** (HUD owner) — in `ui/hud/hud_ruler.gd` (or hud.gd), add a
   `WidgetThreatTicks` child with `mouse_filter = IGNORE`, positioned over the strip
   `Rect2(0, 0, ruler.size.x, geo.threat_h)` of `HudModel.ruler_geometry(...)`, and each frame call
   `ticks.set_track(geo.track_x, geo.track_w, view.horizon_beats)` then `ticks.set_view(view)` (and
   `set_pulse(pulse.beat_pulse)`). Then drop the ruler's own triangle drawing in `_draw_body`
   ("Threat beats (beatSight)") so the markers are not drawn twice. When `threat_h` is 0 (no
   beatSight), hide the widget.
4. **Loot moment** (menus owner) — on the results screen, when `ResultsModel.loot` is non-empty,
   instance `res://ui/widgets/loot_reveal.tscn` full-screen over the results view, call
   `show_loot(model.loot, model.level.theme, owned_ids_before_this_level)` and connect
   `choice_made`: `equip_now == true` → open the loadout screen (or emit `UiIntent.equip(slot, id)`
   for each item, as the menus prefer); either way free the reveal and show the results. The
   inventory before the level is the save's inventory minus `model.loot` ids if the game does not
   keep the earlier copy.
5. **Icons** — gear icon art is read from `res://assets/ui/icons/gear/<item id>.png` when present; the
   cards fall back to drawn slot glyphs, so missing art is never an error.

## Verification

- `bash tools/gd test ui_widgets` — 52 tests: momentum preview equals `Tuning` for every speed /
  motion / direction; Scenario K (2× running heavy breaks the tutorial wall; 1× running fails and names
  2×; 2× standing fails but run-in would do); damage ticks agree with `Tuning.strike_damage` under a
  1.35 damage mod; brute bands and hits; boss stagger tick; facing / range / broken / dead filtering;
  failure text for every clang reason; perimeter projection, clustering across the corner seam,
  behind-camera mirroring; boss phase marks vs `boss_phase_for`, ghost hold/drain, memory tell,
  landing beat from event or telegraph; threat tick mapping/merging/countdown; every scene loads,
  takes a frame of data, and the loot reveal emits exactly one `choice_made`.
- `bash tools/gd shot res://tools/shot_widgets.gd` writes ten PNGs to
  `%TEMP%/overdub_widget_shots` (world, gauge, boss, loot mid / done; each on the warm R03 and dark
  R04 boards).

## Known gaps

- The gauge previews "if pressed now" with the body facing unless `set_aim` is given the live aim; it
  does not include the `slideStrike` bonus (it needs the tape's dodge timing, which only the sim has)
  — with Slick Sliders equipped a swing out of a dodge hits harder than the arc shows.
- Enemy-specific hit rules other than the brute's shove line and the boss's armour are not previewed
  (a shielder's first hit always pops the shield; the caption says so only after a clang).
- Badges and chevrons do not test occlusion (a badge behind a wall still draws; the x-ray silhouettes
  are the actor layer's job).
- The loot chest uses the glb's imported materials and a local light rig, not the world's toon
  shader.
