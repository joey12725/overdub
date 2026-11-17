class_name DialogueLayer
extends Control
## One node that carries the whole story / onboarding overlay: the DialoguePlayer (intro, outro,
## firsts, ending), barks, coach marks and the failure hint card. The game (or the UI root) adds it
## above the HUD and drives it with a handful of calls; everything else is internal. Full contract and
## integration steps: docs/DIALOGUE.md.
##
##   layer.setup(hud, world_to_screen)                   # anchors (once)
##   layer.set_seen_flags(save_seen); layer.seen_changed.connect(save_it)
##   layer.begin_level(level.id)                         # each level visit
##   if layer.play_intro(level.id): await layer.dialogue_finished
##   layer.update(view, events, dt, snapshot)            # every frame while a level is up
##   layer.notify_action(&"commit")                      # each SessionAction the game applies
##   layer.notify_input(&"move")                         # each gameplay input use (coach marks)
##   layer.on_review_result(outcome)                     # each resolved combined run
##   if layer.play_outro(level.id): await layer.dialogue_finished
##   layer.on_results(loot.size() > 0)

signal dialogue_finished(kind: StringName, key: String, skipped: bool)
## The seen store changed: persist get_seen_flags() (SaveData "seen").
signal seen_changed
signal bark_shown(key: String, line: DlgLine)
signal coach_shown(mark_id: String)
signal coach_completed(mark_id: String)

const IDLE_TOAST_AFTER := 40.0
## ONBOARDING.md "Living with the story layer": on the take where the mark shows, its bark is quiet.
const MARK_SUPPRESSES_BARK: Dictionary = {"death-ghost": "ghostTake", "rescue": "rescue", "desync": "desync"}

@export var story_path: String = DlgStoryData.DEFAULT_PATH
@export var coach_path: String = CoachEngine.DEFAULT_PATH
@export var hints_path: String = DlgFailureHints.DEFAULT_PATH
## Load the data files in _ready (tests turn this off and call load_data()).
@export var autoload_data: bool = true
## Barks float over Moxie's head (world anchor "world:self") instead of next to her deck.
@export var barks_over_head: bool = false

var story: DlgStoryData = DlgStoryData.new()
var seen: DlgSeenStore = DlgSeenStore.new()
var director: DlgStoryDirector = null
var portraits: DlgPortraits = DlgPortraits.new()
var bark_rules: DlgBarkRules = DlgBarkRules.new()
var bark_triggers: DlgBarkTriggers = DlgBarkTriggers.new()
var coach: CoachEngine = CoachEngine.new()
var hints: DlgFailureHints = DlgFailureHints.new()
var anchors: CoachAnchors = CoachAnchors.new()

var coach_layer: CoachLayer = null
var barks: BarkToast = null
var hint_card: DlgHintCard = null
var player: DialoguePlayer = null

var level_id: String = ""
var view: SessionView = null
var barks_enabled: bool = true
var coach_enabled: bool = true

var _phase: StringName = &""
var _idle: float = 0.0
var _idle_done: bool = false
var _result_reported: bool = false
var _pending_hint: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	coach_layer = CoachLayer.new()
	coach_layer.name = "Coach"
	add_child(coach_layer)
	barks = BarkToast.new()
	barks.name = "Barks"
	add_child(barks)
	hint_card = DlgHintCard.new()
	hint_card.name = "FailureHint"
	add_child(hint_card)
	player = DialoguePlayer.new()
	player.name = "Dialogue"
	add_child(player)
	coach_layer.anchors = anchors
	hint_card.anchors = anchors
	player.finished.connect(func(k: StringName, key: String, s: bool) -> void: dialogue_finished.emit(k, key, s))
	seen.changed.connect(func() -> void: seen_changed.emit())
	if autoload_data:
		load_data(story_path, coach_path, hints_path)
	else:
		_wire()


## (Re)load the data files. Missing files are fine (the overlay simply has nothing to show).
func load_data(p_story: String, p_coach: String, p_hints: String) -> void:
	story = DlgStoryData.load_file(p_story)
	var flags := seen.to_array()
	coach = CoachEngine.load_file(p_coach)
	hints = DlgFailureHints.load_file(p_hints)
	seen.load_array(flags)
	_wire()


## Use already-built data objects (tests, tools).
func use_data(p_story: DlgStoryData, p_coach: CoachEngine, p_hints: DlgFailureHints) -> void:
	story = p_story if p_story != null else DlgStoryData.new()
	coach = p_coach if p_coach != null else CoachEngine.new()
	hints = p_hints if p_hints != null else DlgFailureHints.new()
	_wire()


func _wire() -> void:
	director = DlgStoryDirector.new(story, seen)
	coach.seen = seen
	coach.enabled = coach_enabled
	bark_rules.enabled = barks_enabled
	if not coach.shown.is_connected(_on_coach_shown):
		coach.shown.connect(_on_coach_shown)
		coach.hidden.connect(_on_coach_hidden)
	if player != null:
		player.story = story
		player.portraits = portraits
	if coach_layer != null:
		coach_layer.engine = coach


## HUD root for anchor lookups (the HudBase instance, or the UI root), and the game's
## world -> screen mapping (see CoachAnchors). Call again whenever either changes.
func setup(hud_root: Node, world_to_screen: Callable = Callable()) -> void:
	anchors.hud_root = hud_root
	anchors.world_to_screen = world_to_screen


# ───────────────────────────── save / settings ─────────────────────────────

func set_seen_flags(flags: Variant) -> void:
	seen.load_array(flags)


func get_seen_flags() -> Array[String]:
	return seen.to_array()


## SaveSettings "barks" / "coachMarks" / "textSpeed" (docs/DIALOGUE.md "Settings").
func set_options(p_barks: bool, p_coach: bool, text_speed: float = 1.0, patterns: bool = false) -> void:
	barks_enabled = p_barks
	coach_enabled = p_coach
	bark_rules.enabled = p_barks
	coach.enabled = p_coach
	if not p_barks and barks != null:
		barks.clear()
	if player != null:
		player.set_text_speed(text_speed)
	if coach_layer != null:
		coach_layer.patterns = patterns


## Text size option (SaveSettings textScale): the box, barks, coach labels and the hint card scale
## their type by UiPalette.text_scale.
func set_text_scale(scale: float) -> void:
	UiPalette.text_scale = clampf(scale, 0.75, 2.0)
	if player != null and player.box != null and player.box.is_node_ready():
		player.box.call("_layout")
	for c: Node in [coach_layer, barks, hint_card]:
		if c != null:
			(c as CanvasItem).queue_redraw()


## SaveData.cleared.size() (the coach `levelsCleared` predicate).
func set_levels_cleared(n: int) -> void:
	coach.ctx.levels_cleared = n


## Same map as UiBase.set_bindings: used for {action} prompts and the dialogue's key labels.
func set_bindings(prompts: Dictionary) -> void:
	coach_layer.bindings = prompts
	var acc := DlgPrompts.label_for("accept", prompts)
	var skp := DlgPrompts.label_for("cancel", prompts)
	player.set_prompt_labels(acc if acc != "Accept" else "Enter", skp if skp != "Cancel" else "Esc")


func set_device(device: StringName) -> void:
	coach.set_device(device)
	if device == HudBase.DEVICE_GAMEPAD:
		player.set_prompt_labels("A", "B")
	else:
		player.set_prompt_labels("Enter", "Esc")


# ───────────────────────────── level lifecycle ─────────────────────────────

func begin_level(p_level_id: String, level: LevelDef = null) -> void:
	level_id = p_level_id
	coach.begin_level(p_level_id, level)
	hints.begin_level(p_level_id)
	bark_triggers.reset()
	director.clear_pending()
	barks.clear()
	hint_card.clear()
	_pending_hint = ""
	_idle = 0.0
	_idle_done = false
	_result_reported = false
	_phase = &""


## Plays the level intro if unseen (or replay). True when something was queued: await
## dialogue_finished before showing the briefing.
func play_intro(p_level_id: String, replay: bool = false) -> bool:
	return _play(director.intro(p_level_id, replay), DialoguePlayer.KIND_INTRO, p_level_id)


## Plays the outro on first clear. True when queued: await dialogue_finished before results.
func play_outro(p_level_id: String, replay: bool = false) -> bool:
	return _play(director.outro(p_level_id, replay), DialoguePlayer.KIND_OUTRO, p_level_id)


## The ending (with its fade between line 6 and line 7). `key_art` is shown through the cut.
func play_ending(key_art: Texture2D = null, replay: bool = false) -> bool:
	player.set_cut_backdrop(key_art)
	player.set_phase(&"")
	return _play(director.ending(replay), DialoguePlayer.KIND_ENDING, "ending")


func play_stinger() -> bool:
	player.set_phase(&"")
	return _play(director.stinger(), DialoguePlayer.KIND_STINGER, "stinger")


func play_lines(lines: Array[DlgLine], kind: StringName = DialoguePlayer.KIND_OTHER, key: String = "") -> bool:
	return _play(lines, kind, key)


func _play(lines: Array[DlgLine], kind: StringName, key: String) -> bool:
	if lines.is_empty():
		return false
	barks.clear()
	player.play(lines, kind, key)
	return true


func is_dialogue_open() -> bool:
	return player.is_open()


## True while a box is open or queued: the game should hold session input (and the next phase).
func is_blocking() -> bool:
	return player.is_busy()


## Leave the level / quit: drop queued dialogue, barks and marks.
func end_level() -> void:
	player.skip_all(true)
	barks.clear()
	hint_card.clear()
	director.clear_pending()
	coach.begin_level("")


# ───────────────────────────── per frame ─────────────────────────────

func update(p_view: SessionView, events: Array[SimEvent], dt: float, snap: FrameSnapshot = null) -> void:
	view = p_view
	if p_view == null:
		return
	var ph := p_view.phase
	var entered := ph != _phase
	var left := _phase
	_phase = ph
	player.set_phase(ph)
	coach.dialogue_open = player.is_open()
	coach.bark_on_screen = barks.is_showing()
	coach.update(dt, p_view, events, snap)
	bark_rules.tick(dt)
	if entered:
		bark_rules.new_phase()
		_on_phase(left, ph)
	# barks
	for key: String in bark_triggers.observe(p_view, events, dt):
		_bark_event(key)
	# queued firsts at the next calm moment
	if director.has_pending() and DlgGate.first_allowed(ph) and not player.is_busy():
		var p := director.take_pending()
		var lines: Array[DlgLine] = []
		for l: Variant in p["lines"]:
			lines.append(l)
		_play(lines, DialoguePlayer.KIND_FIRST, p["key"])
	# idle toast in setup
	if ph == SessionPhase.SETUP and not _idle_done and not player.is_open():
		_idle += dt
		if _idle >= IDLE_TOAST_AFTER:
			_idle_done = true
			var line := director.idle_line(level_id)
			if line != null and barks_enabled:
				_show_bark("idle", line)
	# hint card only on the decision screen
	if ph == SessionPhase.DECISION and _pending_hint != "" and not player.is_open():
		hint_card.avoid = coach_layer.avoid_rects()
		hint_card.show_hint(_pending_hint)
	elif ph != SessionPhase.DECISION or player.is_open():
		hint_card.clear()
	_place_barks()


func _on_phase(left: StringName, entered: StringName) -> void:
	if entered == SessionPhase.REVIEW:
		_result_reported = false
	if left == SessionPhase.REVIEW and not _result_reported and view != null and view.outcome != null:
		_record_result(view.outcome)
	if left == SessionPhase.DECISION:
		_pending_hint = ""


## Player activity: resets the idle timer. `input` is one use of a gameplay input for the coach
## marks (move, aim, light, heavy, dodge, ranged, interact, ability; ONBOARDING.md "inputUsed");
## "" for other activity (menu keys, mouse).
func notify_input(input: StringName = &"") -> void:
	_idle = 0.0
	if input != &"":
		coach.note_input(input)


## A SessionAction the game applied (from keys, pads or HUD clicks).
func notify_action(action: StringName) -> void:
	notify_input()
	coach.note_action(action)
	match action:
		SessionAction.COMMIT:
			_bark_event("takeCommitted")
		SessionAction.RETRY_TAKE:
			_bark_event("retry")
		SessionAction.RESET_ALL:
			if not director.note_first(level_id, "resetAll"):
				_bark_event("resetAll")


## A combined run resolved (call with the authoritative outcome; ONBOARDING.md "Failure hints").
## Optional: without it the layer reads view.outcome when review ends.
func on_review_result(outcome: Outcome, _run_events: Array[SimEvent] = []) -> void:
	_result_reported = true
	_record_result(outcome)


func _record_result(outcome: Outcome) -> void:
	if outcome == null:
		return
	var line := hints.on_resolved(outcome)
	_pending_hint = DlgPrompts.substitute(line, coach_layer.bindings) if line != "" else ""
	if hints.last != null:
		seen.mark("hint." + hints.last.hint.id)


## Results reached. `has_loot`: gear was awarded.
func on_results(has_loot: bool) -> void:
	if has_loot and not director.note_first(level_id, "loot"):
		_bark_event("loot")


## A scripted bark (e.g. "archivistSurprised"). `force` skips chance and rate limits.
func bark(key: String, force: bool = false) -> bool:
	return _bark_event(key, force)


func _bark_event(key: String, force: bool = false) -> bool:
	match key:
		"death":
			if director.note_first(level_id, "death"):
				return false
		"desync":
			if director.note_first(level_id, "desync"):
				return false
		"ghostTake":
			if director.note_first(level_id, "ghostTake"):
				return false
		"bossRecall":
			# The Archivist reads the tape back, then Moxie answers (INTEGRATION.md).
			var a := bark_rules.request("archivistRecall", story.barks("archivistRecall"), force)
			if a == null:
				return false
			_show_bark("archivistRecall", a)
			var m := bark_rules.request("bossRecall", story.barks("bossRecall"), true)
			if m != null:
				_show_bark("bossRecall", m)
			return true
	if player.is_open() or not DlgGate.bark_allowed(_phase) and _phase != &"":
		return false
	if not force and coach.current != null:
		return false # ONBOARDING.md: no bark starts while a coach mark is visible
	for mark_id: String in MARK_SUPPRESSES_BARK:
		if MARK_SUPPRESSES_BARK[mark_id] == key and coach.shown_this_take.has(mark_id):
			return false
	var line := bark_rules.request(key, story.barks(key), force)
	if line == null:
		return false
	_show_bark(key, line)
	return true


func _show_bark(key: String, line: DlgLine) -> void:
	if not barks_enabled or player.is_open():
		return
	var ch := story.character(line.who)
	barks.show_bark(line, ch, portraits.texture(line.who, line.expression, ch.portraits))
	bark_shown.emit(key, line)


func _place_barks() -> void:
	if not barks.is_showing():
		return
	var ctx := coach.ctx
	var r := CoachAnchors.Resolved.new()
	if barks_over_head:
		r = anchors.resolve("world:self", barks, ctx)
	if not r.ok:
		r = anchors.resolve("bark_anchor", barks, ctx)
	if not r.ok:
		r = anchors.resolve("deck:active", barks, ctx)
	barks.has_anchor = r.ok
	barks.anchor_rect = r.rect
	# Same space as the coach layer (both fill this node): never over the decks, the ruler, the
	# objective, the HUD panels or the dock.
	barks.avoid = coach_layer.avoid_rects()


func _on_coach_shown(m: CoachMarkDef) -> void:
	coach_shown.emit(m.id)


func _on_coach_hidden(m: CoachMarkDef, _reason: String, done: bool) -> void:
	if done:
		coach_completed.emit(m.id)
