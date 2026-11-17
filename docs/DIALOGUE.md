# OVERDUB — dialogue, barks, coach marks and failure hints (Godot runtime)

The runtime for the story layer (`data/story/story.json`, `docs/story/INTEGRATION.md`) and the
onboarding layer (`data/onboarding/*.json`, `docs/ONBOARDING.md`). Everything lives in
`ui/dialogue/` and `ui/coach/`; one node, **`DialogueLayer`**, is the whole surface the game and the
HUD talk to. Nothing outside those folders was edited: the steps under "Integration" are for the
integration, HUD and save engineers.

| Path | What |
|---|---|
| `ui/dialogue/dialogue_layer.gd` (+ `.tscn`) | **The facade.** Owns the dialogue player, barks, coach marks and the hint card |
| `ui/dialogue/dialogue_player.gd` (+ `.tscn`) | Plays sequences in a `DialogueBox` over a dimmed world; queue, gating, skip, the ending's cut |
| `ui/dialogue/dialogue_box.gd` (+ `.tscn`) | The box: portrait, name tab, typewriter text, advance / fast-forward / hold-to-skip cues |
| `ui/dialogue/bark_toast.gd` (+ `.tscn`) | Non-blocking speech toast (portrait chip + line) |
| `ui/dialogue/dlg_hint_card.gd` | The failure hint card on the decision screen |
| `ui/dialogue/dlg_portrait_view.gd` | A portrait in a fixed frame (no jump on swaps), coloured-initial fallback, radio scanlines |
| `ui/dialogue/dlg_*.gd` (node-free) | `DlgLine`, `DlgStoryData` (loader + validator), `DlgStoryDirector` (what plays when), `DlgRunner` (sequence state machine), `DlgTextPacer` (punctuation-aware typing), `DlgGate` (phase gating), `DlgBarkRules` (cooldowns, rate limit, no repeats), `DlgBarkTriggers` (view + events -> bark keys), `DlgFailureHints`, `DlgPortraits` (file lookup), `DlgSeenStore` (save flags), `DlgPrompts` (button tokens) |
| `ui/coach/coach_engine.gd` (node-free) | The coach-mark director: ONBOARDING.md "Lifecycle" |
| `ui/coach/coach_conditions.gd`, `coach_context.gd`, `coach_world.gd`, `coach_mark_def.gd` (node-free) | The condition language, the per-frame context and logs, world positions, mark definitions |
| `ui/coach/coach_anchors.gd` (node-free) | Anchor -> screen rect: HUD groups / hooks / node names, world points through a callable |
| `ui/coach/coach_layout.gd` (node-free) | Places a label beside an anchor, on screen, clear of avoided rects |
| `ui/coach/coach_layer.gd` (+ `.tscn`) | Draws the visible mark: label, leader line, dot |
| `tests/ui_dialogue/**` | 63 headless tests + fixtures (`bash tools/gd test ui_dialogue`) |
| `tools/shot_dialogue.gd` | 13 screenshots over the real HUD -> `art/previews/dialogue/` |

All logic (trigger evaluation, sequencing, cooldowns, pacing, hint streaks) is in node-free scripts
with headless tests; the nodes only draw and forward input.

## The facade: `DialogueLayer`

Add one `DialogueLayer` (`res://ui/dialogue/dialogue_layer.tscn`, or `DialogueLayer.new()`) as a
full-screen child of the UI root, **above the HUD and below menus / toasts**. It loads
`data/story/story.json`, `data/onboarding/coachmarks.json` and `data/onboarding/failure_hints.json`
in `_ready` (missing files are fine: that part simply has nothing to say). Add it to the tree before
calling it.

```gdscript
# once
layer.setup(ui.hud, func(p: Vector2) -> Variant: return world_point_to_screen(p))  # see "World anchors"
layer.set_seen_flags(save.seen)                # Array[String]; see "Save data"
layer.seen_changed.connect(func() -> void: save.seen = layer.get_seen_flags(); persist())
layer.set_options(settings.barks, settings.coach_marks, settings.text_speed, settings.patterns)
layer.set_bindings(GameInput.prompts(device)); layer.set_device(device)   # whenever they change
layer.set_levels_cleared(save.cleared.size())

# each level visit
layer.begin_level(level.id, level)             # level ids are the story keys ("01-soft-open")
if layer.play_intro(level.id): await layer.dialogue_finished      # before the briefing
# every rendered frame while the level is up (play / pause / results screens)
layer.update(session.view(), frame_events, dt, frame.snap)
layer.notify_action(action)                    # every SessionAction the game applies
layer.notify_input(&"move")                    # every gameplay input use (coach marks; see below)
layer.on_review_result(outcome)                # when a combined run resolves (optional, see hints)
# win
if layer.play_outro(level.id): await layer.dialogue_finished      # after the cinematic, before results
layer.on_results(loot.size() > 0)
# leaving the level
layer.end_level()
# after the 12-master-tape outro, in place of results
if layer.play_ending(key_art_texture): await layer.dialogue_finished
```

| Call | Notes |
|---|---|
| `setup(hud_root: Node, world_to_screen: Callable)` | HUD root for anchors (the `HudBase`, or the UI root) and the world mapping. Call again if either changes |
| `set_seen_flags(Array)` / `get_seen_flags() -> Array[String]` | Persistence of every "seen" flag (see "Save data"). `seen_changed` fires when a flag is added |
| `set_options(barks: bool, coach: bool, text_speed := 1.0, patterns := false)` | Settings. Turning barks off clears the one on screen; turning coach marks off fades the visible one |
| `set_bindings(Dictionary)` / `set_device(StringName)` | The same `ButtonPrompt` map as `UiBase.set_bindings` (it already has `move` and `aim`). Used by `{btn:x}` tokens and the box's key hints |
| `set_levels_cleared(int)` | `SaveData.cleared.size()` (coach predicate `levelsCleared`) |
| `begin_level(id, level: LevelDef = null)` | Resets per-visit state: coach visit, hint streaks, bark state, queued firsts |
| `play_intro(id, replay := false) -> bool` | First visit only (or `replay` from level select). `true` = something is playing: await `dialogue_finished` |
| `play_outro(id, replay := false) -> bool` | First clear only |
| `play_ending(key_art: Texture2D = null, replay := false) -> bool` | Once per save; the fade between line 6 and 7 shows `key_art` (black when null) |
| `play_stinger() -> bool`, `play_lines(lines, kind, key) -> bool` | After the credits; anything scripted |
| `update(view: SessionView, events: Array[SimEvent], dt: float, snap: FrameSnapshot = null)` | Every rendered frame. `events` are the frame's `SimEvent`s (the ones put in `RenderFrame.events`: live during recording, replayed during review / cinematic); `snap` is `RenderFrame.snap` |
| `notify_action(StringName)` | Every applied `SessionAction` (keys, pad, HUD clicks). Drives `takeCommitted` / `retry` / `resetAll` barks and coach `sessionActionUsed` |
| `notify_input(StringName = &"")` | One use of a gameplay input: `move`, `aim`, `light`, `heavy`, `dodge`, `ranged`, `interact`, `ability`. `move` / `aim` count once each time the stick leaves its dead zone after 0.25 s neutral (mouse: every 24 px of travel). `&""` = other activity (resets the idle toast timer) |
| `on_review_result(outcome: Outcome)` | Optional: the authoritative outcome of a resolved combined run. Without it the layer reads `view.outcome` as review ends |
| `on_results(has_loot: bool)` | Results reached (loot bark / `once.firstLoot`) |
| `bark(key, force := false) -> bool` | A scripted bark (e.g. `archivistSurprised` in level 11). `force` skips chance and rate limits |
| `is_dialogue_open() -> bool`, `is_blocking() -> bool` | A box is up / a box is up or queued. While `is_blocking()`, hold the session's own input (the box consumes accept / cancel) and do not advance from briefing to setup |
| `end_level()` | Drops queued dialogue, barks and marks |

Signals: `dialogue_finished(kind, key, skipped)`, `seen_changed`, `bark_shown(key, line)`,
`coach_shown(mark_id)`, `coach_completed(mark_id)`.

## Dialogue box and player

- Bottom of the screen over a dimmed, still visible world. Moxie's portrait on the **left**, everyone
  else on the **right** (`"side": "left" | "right"` on a story.json character overrides). Portraits
  are never mirrored (`assets/portraits/README.md`); `"mirror": true` on a character opts in.
- The portrait sits in a fixed frame computed from the box alone (bottom-aligned, aspect-fitted), so
  an expression or speaker swap never moves it; a swap plays a 0.14 s pop, no cross-fade.
- Speaker name tab in `characters[].color` (ink or paper text by luminance); box edge tinted too.
- Opal and the Archivist (or any character with `"radio": true`) get a waveform top edge and cyan
  scanlines masked to the portrait's silhouette. A line beginning or ending with `--` gets a burst of
  static when it finishes (radio cut).
- Typewriter at 55 characters / s x the text-speed setting, with pauses after `, ; :` (0.11 s),
  `. ! ?` (0.26 s), each ellipsis dot (0.13 s) and a mid-line `--` (0.18 s); never a pause at the end
  of a line (`DlgTextPacer`).
- **Input** (keyboard / pad / mouse; the player reads `ui_accept`, `ui_cancel`, pad Start and left
  click and marks them handled, and swallows other keys while open): accept completes a typing line,
  otherwise advances; holding accept for 0.32 s fast-forwards (typing x5, each finished line advances
  after 0.22 s); holding cancel for 0.7 s skips the whole sequence (a ring shows progress); pad Start
  or a click on "hold to skip" skips at once. No auto-advance. A game with its own input layer sets
  `layer.player.handle_input = false` and calls `input_accept(pressed)`, `input_skip(pressed)`,
  `input_skip_now()`.
- **Never traps the player:** every sequence can be skipped in every state.
- **Never overlaps the count-in or a live take:** a box cannot open during `countin`, `recording`,
  `review` or `cinematic` (`DlgGate`); a sequence queued then waits. If the phase changes to one of
  those while a box is open, the sequence ends at once (`finished(skipped = true)`).
- Queued firsts (`levels[id].firstDeath`, `once.firstDeath` / `firstGhostTake` / `firstDesync` /
  `firstResetAll` / `firstLoot`) play at the next `decision`, `setup` or `results`; when one plays,
  its bark is dropped.
- The ending: line index 6 (the 7th line) carries a 1.4 s fade through `key_art`; the only hard-coded
  cut (INTEGRATION.md).
- Layout is in UI units (`UiPalette.unit_for`): verified on screen and readable from 1280x720 to
  3840x2160 (`test_layout_scales_720p_to_4k`, shots 02 to 04).
- Optional panel art: if `res://assets/ui/art/dialogue_box.png` exists it is drawn as a 9-slice
  (margins 18 % of the image) instead of the flat inked panel. No such file exists yet.

## Portraits

`DlgPortraits` looks, in order, for `res://assets/portraits/<who>_<expression>.png` (the delivered
art) and `res://assets/story/portraits/<who>.<expression>.png` (INTEGRATION.md's suggestion), then
the same for `neutral`, then for the character's first listed expression. An imported texture is
used when its import is valid; otherwise the PNG is read from disk (new art shows up without an
editor import). A miss draws a coloured disc with the speaker's initial. Bark chips crop the head with
`Rect2(162, 20, 700, 700)` of the 1024 px canvas, as the portraits README suggests.

## Barks

A toast with a round portrait chip and the line, about two seconds (1.8 to 3.6 s by length), next to
the active deck (above the dock), or over Moxie's head when `layer.barks_over_head = true` (world
anchor `world:self`). It never takes input and never covers the decks, the ruler, the objective chip
or a HUD panel. A HUD that wants a specific spot can expose a node in group `bark_anchor`.

| Key | Fires on | Chance / cooldown |
|---|---|---|
| `countIn` | entering `countin` | 34 % / 25 s |
| `lastTape` | entering `setup` on the level's last cassette (never on a one-tape level) | 100 % / 30 s |
| `death` | `selfDeath` for the live tape during recording (first time: the story's firstDeath instead) | 50 % / 10 s |
| `ghostTake` | 2.5 s into recording as `recGhost`, once per take | 100 % / 20 s |
| `desync` / `resync` | a `desync` / `resync` event in recording or review | 50 % / 12 s |
| `rescue` | review ended with a survivor that died in the previous combined run | 100 % / 8 s |
| `fail` | review ended with a failed outcome | 40 % / 15 s |
| `win` | entering `cinematic` | 100 % |
| `takeCommitted` / `retry` / `resetAll` | `notify_action` | 50 % / 40 % / 100 % |
| `loot` | `on_results(true)` | 100 % |
| `bossRecall` | a `bossRecall` sim event: the Archivist's `archivistRecall`, then Moxie's `bossRecall` | 100 % / 6 s |
| `idle` | `levels[id].idle` after 40 s with no input in `setup`, once per visit | |

Rules (`DlgBarkRules`, seedable): per-key chance and cooldown (a failed roll also starts the
cooldown), at least 4 s between barks, at most 5 per 60 s, at most one per session phase, never the
same line twice running, one bark on screen (a newer one waits behind it). No bark while a dialogue
box is open or while a coach mark is visible; on the take where coach mark `death-ghost`, `rescue`
or `desync` showed, the matching bark (`ghostTake`, `rescue`, `desync`) stays quiet
(ONBOARDING.md "Living with the story layer"). Barks can be turned off (`set_options`).

## Coach marks

`CoachEngine` implements ONBOARDING.md's lifecycle exactly: skip (`skipIf`) -> visible mark
(`dismissOn` = done by the player; leaving its phases or outliving `linger` = fade, done only if up
`minShownSecondsToCount`) -> choose (urgent first, then file order; `minGapSeconds`;
`maxPerPhaseVisit` / `maxUrgentPerPhaseVisit`) -> urgent pre-emption. One mark at a time. `once`
marks are saved; `once: false` marks retire per level visit. Marks wait while a dialogue box is open
(a visible one fades) and while a bark is on screen. All 25 predicates, the three combinators, all
six scopes, subject binding and the `{btn:x}` / `{speed}` / `{tape}` tokens are implemented
(`coach_conditions.gd`). `scope: "save"` leaves that come true are stored as facts so they stay true
in later sessions. `data/onboarding/coachmarks.json` validates with no unknown predicate
(`test_real_coachmarks_validate_if_present`).

Drawn as ONBOARDING.md "Presentation" specifies: a one-line label (two below about 420 px), a leader
line and a dot on the anchor, edge in the cassette's colour for deck / ruler / self anchors, 120 ms
fade + 6 px slide in, a tick and 200 ms fade when done by the player, a 300 ms fade otherwise, a
pattern ring on the dot with colour-blind patterns on. The label never covers the decks, the ruler,
the dock band, the objective chip or a HUD panel; an anchor that cannot be resolved puts it in the
**coach slot**, centred just above the dock, with the button glyph for `prompt:` anchors (unless the
text already names that button).

### HUD anchors (for the HUD engineer)

Each spec anchor maps to a group name (`:active` and `:subject` are substituted first):

| Spec anchor | Group | Today's fallback (works with the current `ui/hud` with no change) |
|---|---|---|
| `deck:<n>` | `deck_<n>` | node `Deck<A..D>` (whole deck) |
| `deck.speed` | `deck_speed` | `Deck<active>.geometry().speed` |
| `deck.endMode`, `deck.reels`, `deck.status` | `deck_endMode`, `deck_reels`, `deck_status` | the active deck (whole) |
| `ruler` | `ruler` | node `Ruler`, `body_rect()` |
| `ruler.playhead` | `ruler_playhead` | computed from `Ruler.view` / `HudModel.ruler_geometry` |
| `ruler.lane:<n>` | `ruler_lane_<n>` | computed from `HudModel.ruler_geometry` |
| `objective` | `objective` | node `Objective` |
| `countin` | `count_in` | node `CountIn` |
| `prompt:<action>` | `prompt_<action>` | the enabled click zone for that action in any visible `HudPanel.zones()` (setup, decision...) |
| (barks) | `bark_anchor` | the active deck |
| (avoid list) | `setup`, `decision`, `briefing`, `banner` | nodes `Setup`, `Decision`, `Briefing`, `Banner` |

Lookup order, first hit wins (`CoachAnchors._hud`):

1. `hud_root.anchor_rect(anchor: String, subject: Dictionary) -> Rect2`: ONBOARDING.md's hook, in
   hud-root-local coordinates, with `:active` / `:subject` already replaced (`"deck:2"`). `subject`
   is `{kind, tape, id, x?, y?}` or `{}`. Return `Rect2()` for "not on screen".
2. `hud_root.coach_anchor_rect(group: StringName) -> Rect2` (hud-root-local).
3. The first visible node in that **group** (`Control`: its rect; `Node2D`: a small box around it).
4. The fallbacks in the table.
5. A node path relative to `hud_root` (for one-off anchors).

So the HUD engineer can do nothing (fallbacks), add `add_to_group("prompt_move")` on a control that
shows the move prompt (there is none today, so `move` / `aim` / `light` / `heavy` / `dodge` /
`interact` / `skip` marks use the coach slot), or implement `anchor_rect` for exact sub-rects (deck
end-mode chip, reels, status, the decision note a hint is about). `HudBase.bottom_inset()` is used for
the dock band when present.

### World anchors (for the game engineer)

`world:self`, `world:self:<n|subject>`, `world:spark:<n|subject>`, `world:entity:<id|subject>`,
`world:nearest:<kind>` and `world:event` are positioned in sim tiles from the `FrameSnapshot`
(selves, sparks, enemies, mechanisms) and the `LevelDef` (fixed entities), then passed to the
callable given to `setup()`:

```gdscript
# p: sim tiles (x, y). Return a Vector2 in viewport 2D coordinates, or null when off screen / behind
# the camera (the mark then uses the coach slot and the bark falls back to the deck).
func world_point_to_screen(p: Vector2) -> Variant:
	var sp: Vector2 = world.world_to_screen(p.x, p.y, 1.2)   # WorldView.world_to_screen(x, y, h); ~head height
	return sp if get_viewport().get_visible_rect().has_point(sp) else null
```

### Feeding it

`update()` takes the view, the frame's sim events and the snapshot; the rest comes through
`notify_action` (session actions), `notify_input` (the eight inputs) and `set_levels_cleared`. While
a dialogue box is open the engine waits; while a bark is on screen it delays the next mark.

## Failure hints

`DlgFailureHints` implements ONBOARDING.md "Failure hints": every note of a failed run is matched
against `ignore`, then the `hints` regexes in file order (whole-note match, Godot `RegEx`; every
example in `failure_hints.json` resolves to its own hint, `test_real_failure_hints_load`); the
signature is the hint id plus the named groups in `signature`; streaks per level visit (present +1,
absent dropped, a win clears; retry / commit / reset do not); after the **second consecutive
identical failure** the earliest eligible hint is shown, once per hint per visit, one per decision
screen. `{tape}` becomes "Tape A". The card ("TIP" sticker) sits under the HUD's decision panel and
clears outside `decision` or while a dialogue box is open. The first time a hint is shown,
`hint.<id>` is added to the seen flags.

## Save data (for the save engineer; `game/save.gd` was not touched)

One new field, a sorted unique string array:

```
SaveData.seen: Array[String]      # JSON key "seen"; missing = []
```

| Flag | Meaning |
|---|---|
| `story.<levelId>.intro` / `.outro` | INTEGRATION.md's `introSeen` / `outroSeen` |
| `story.<levelId>.firstDeath` (etc.) | a level's own first-event lines played |
| `once.<key>` | `once.firstDeath`, `once.firstGhostTake`, `once.firstDesync`, `once.firstResetAll`, `once.firstLoot` |
| `story.ending` | the ending played |
| `coach.<markId>` | ONBOARDING.md `onboarding.done` |
| `phase.<phase>` | the phase has been visited in this save (`firstTimePhase`; ONBOARDING.md `phaseVisits`) |
| `fact.<predicate>:<json>` | a `scope: "save"` condition came true (ONBOARDING.md `facts`) |
| `hint.<hintId>` | that failure hint was shown at least once |

ONBOARDING.md proposed `onboarding: { done, phaseVisits, facts }`; the single prefixed list carries
the same information in one field. "Reset tutorials" in settings = remove the `coach.`, `phase.` and
`fact.` prefixes (`layer.seen.clear_prefix("coach.")` etc.) and persist.

Settings, three new `SaveSettings` fields with rows in the settings menu:

| Field | JSON key | Default | Passed as |
|---|---|---|---|
| `barks: bool` | `barks` | `true` | `set_options(barks, ...)` |
| `coach_marks: bool` | `coachMarks` | `true` | `set_options(_, coach_marks, ...)` |
| `text_speed: float` | `textSpeed` | `1.0` (0.25..4) | `set_options(_, _, text_speed)` |

## Integration steps

**Game / integration engineer (`game/app.gd`)**

1. In `_ready`, after the UI exists: `dialogue = (load("res://ui/dialogue/dialogue_layer.tscn") as PackedScene).instantiate()`;
   add it to the UI root **after** `attach_hud()` and before the menus (e.g.
   `ui.add_child(dialogue); ui.move_child(dialogue, ui.hud.get_index() + 1)`), then
   `dialogue.setup(ui.hud, world_point_to_screen)` with the callable above.
2. Load / save: `dialogue.set_seen_flags(campaign.save.seen)`; on `dialogue.seen_changed` copy
   `get_seen_flags()` into the save and persist (debounce if you like; flags only ever get added in
   play). Push `set_options(...)` from `SaveSettings` at boot and when settings change; push
   `set_levels_cleared(save.cleared.size())` at boot and after a clear.
3. Where `ui.set_bindings(GameInput.prompts(d))` and `ui.set_device(d)` are called, call the same on
   the layer.
4. Level start: `dialogue.begin_level(level.id, level)`, then
   `if dialogue.play_intro(level.id): await dialogue.dialogue_finished` **before** the session enters
   `briefing` (or keep the session in briefing and hold its input while `dialogue.is_blocking()`).
   Level select "replay story" = `play_intro(id, true)`.
5. In `_present` (the branch that calls `ui.update_hud`): `dialogue.update(v, events, dt, f.snap)`
   with the same `events` given to `RenderFrame.events`. While `dialogue.is_blocking()`, do not pass
   accept / cancel to the session.
6. Where a `SessionAction` is applied (keys, pads and `UiIntent` session actions):
   `dialogue.notify_action(action)`. Where the input module registers a gameplay input use:
   `dialogue.notify_input(&"light")` etc. (`move` / `aim` per the dead-zone rule above).
7. When a combined run resolves: `dialogue.on_review_result(outcome)` (optional; `view.outcome` is
   read otherwise).
8. On a win: after the cinematic, `if dialogue.play_outro(level.id): await dialogue.dialogue_finished`,
   then show results and call `dialogue.on_results(not loot.is_empty())`. After `12-master-tape`'s
   outro: `play_ending(key_art)` in place of results, then credits, then `play_stinger()`.
9. Leaving a level (quit, menu): `dialogue.end_level()`.
10. Level 11: when the boss telegraphs a remembered action the `bossRecall` sim event triggers the
    paired bark by itself; `dialogue.bark("archivistSurprised")` for a committed take it has no
    answer for.
11. Export: include `data/story/*.json` and `data/onboarding/*.json` as non-resource files.

**HUD engineer** (optional; everything works with today's HUD through the fallbacks)

1. For marks that point at button prompts that are not on screen today (`move`, `aim`, `light`,
   `heavy`, `dodge`, `interact`, `skip`): show the prompt somewhere and put it in group
   `prompt_<action>`; until then those marks sit in the coach slot with the glyph.
2. For exact sub-rects add `func anchor_rect(anchor: String, subject: Dictionary) -> Rect2` on the HUD
   root (deck `endMode` / `reels` / `status` chips, `ruler.lane:<n>`, and the decision note a failure
   hint matched if you want the card to point at it).
3. Keep `HudBase.bottom_inset()` accurate: labels, barks and the hint card stay above it.

**Save engineer**: add `SaveData.seen` and the three settings as above (validate as a string list /
bool / unit float), and a settings row each for barks, coach marks and text speed, plus an optional
"reset tutorials" button.

## Verification

- `bash tools/gd test ui_dialogue`: 63 tests, 837 assertions, all passing: text pacing, runner input
  model (complete, advance, fast-forward, hold-to-skip, cut), story loading and validation of the
  real `story.json`, director flags and queued firsts, bark triggers and rules (cooldowns, chance,
  gap, rate, one per phase, no repeats, off switch), every coach predicate and scope, the engine
  lifecycle (skip, dismiss, gap, linger, minShown, phase budget, urgent pre-emption, per-visit marks,
  dialogue / bark gating, disable, seen persistence), anchor resolution (fallbacks, groups, node
  paths, both hooks, world callable, off-screen), placement, failure hints against the fixture and
  every example in the real file, and the scene end to end (portraits, fallback initial, frame never
  moves on swaps, 720p to 4K, phase gating, skip-all, barks clear of the dock, hint card).
- `bash tools/gd shot res://tools/shot_dialogue.gd` writes 13 PNGs to `art/previews/dialogue/`:
  intro typing (Opal, radio), a Moxie line at 1600x900, 720p and 4K, the Archivist (ending), a bark
  by the deck and one over Moxie's head, coach marks on a deck, a ruler lane, a world self (desync
  subject) and the commit prompt, the coach-slot fallback, and the failure hint card. Coach marks in
  the shots are set directly on the engine so each frame is deterministic; world selves are drawn as
  simple stand-ins.

## Known gaps

- Not wired into `game/app.gd`, the HUD or `game/save.gd` (not mine to edit): the steps above.
- No `prompt_move` / `prompt_light` / ... controls exist on the HUD, so those marks use the coach slot.
- Failure hints point at the decision panel, not at the specific note row (needs the HUD's
  `anchor_rect`).
- `selfFateChanged` relies on `DeckView.state_marks` reflecting the latest resolved run, as
  ONBOARDING.md notes.
- No dialogue panel art in `assets/ui/art/` yet; the box is drawn. It picks up
  `assets/ui/art/dialogue_box.png` automatically when it appears.
- Voice lines (`art/voice_el/`) are not played by the box yet; `line_shown(kind, index, line)` on
  `layer.player` is the hook for an audio engineer.
- Timings (bark chances and cooldowns, typing speed, pauses) are first guesses for playtesting.
