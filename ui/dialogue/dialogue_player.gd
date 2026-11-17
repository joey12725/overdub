class_name DialoguePlayer
extends Control
## Plays dialogue sequences in a DialogueBox over a dimmed (still visible) world: level intro before
## the briefing, outro before results, queued firsts at the next calm moment, and the ending (with its
## one hard cut). Sequences queue and play one after another. A box never opens while the session is
## in countin / recording / review / cinematic (DlgGate); if the phase changes to one of those while a
## box is open, the sequence ends at once (finished(skipped = true)), so the player is never trapped
## and a box never overlaps a take.
##
##   player.play(lines, DialoguePlayer.KIND_INTRO, "01-soft-open")
##   await player.finished          # (kind, key, skipped)
##
## Input: with handle_input on (default) it reads ui_accept (Enter / Space / pad A) and ui_cancel
## (Esc / pad B) plus left click and pad Start while open, and marks those events handled. A game with
## its own input layer turns handle_input off and calls input_accept(pressed) / input_skip(pressed) /
## input_skip_now().

signal started(kind: StringName, key: String)
signal line_shown(kind: StringName, index: int, line: DlgLine)
signal finished(kind: StringName, key: String, skipped: bool)
## Closed with nothing left queued.
signal idle

const KIND_INTRO: StringName = &"intro"
const KIND_OUTRO: StringName = &"outro"
const KIND_FIRST: StringName = &"first"
const KIND_ENDING: StringName = &"ending"
const KIND_STINGER: StringName = &"stinger"
const KIND_OTHER: StringName = &"other"

var story: DlgStoryData = DlgStoryData.new()
var portraits: DlgPortraits = DlgPortraits.new()
var runner: DlgRunner = DlgRunner.new()
var handle_input: bool = true
## Current session phase (SessionPhase.*), or "" outside a level.
var phase: StringName = &""
var dim_alpha: float = 0.42

var dim: ColorRect = null
var backdrop: TextureRect = null
var fade: ColorRect = null
var box: DialogueBox = null

var _queue: Array[Dictionary] = []
var _cur: Dictionary = {}
var _open: bool = false
var _dim_t: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(UiPalette.INK, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	backdrop = TextureRect.new()
	backdrop.name = "CutBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.modulate = Color(1, 1, 1, 0)
	add_child(backdrop)
	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	box = DialogueBox.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.visible = false
	add_child(box)
	box.accept_clicked.connect(func() -> void:
		input_accept(true)
		input_accept(false))
	box.skip_clicked.connect(input_skip_now)
	runner.line_started.connect(_on_line_started)
	runner.cut_started.connect(func(_i: int) -> void: box.visible = false)
	runner.finished.connect(_on_runner_finished)


## Queue a sequence. An empty sequence still emits finished (deferred) so `await finished` never hangs.
func play(lines: Array[DlgLine], kind: StringName = KIND_OTHER, key: String = "") -> void:
	if lines.is_empty():
		_emit_finished.call_deferred(kind, key, false)
		return
	_queue.append({"lines": lines.duplicate(), "kind": kind, "key": key})
	if not _open and DlgGate.box_allowed(phase):
		_start_next()


func is_open() -> bool:
	return _open


## Open, or something queued.
func is_busy() -> bool:
	return _open or not _queue.is_empty()


func queued() -> int:
	return _queue.size()


## The session phase changed. Entering a blocked phase ends an open sequence immediately.
func set_phase(p: StringName) -> void:
	phase = p
	if _open and not DlgGate.box_allowed(p):
		runner.skip_all()


## End the open sequence (skipped). `and_queue` also drops everything queued.
func skip_all(and_queue: bool = false) -> void:
	if and_queue:
		_queue.clear()
	if _open:
		runner.skip_all()


func clear_queue() -> void:
	_queue.clear()


## Key art shown through the ending's cut (null = black).
func set_cut_backdrop(tex: Texture2D) -> void:
	backdrop.texture = tex


func set_text_speed(mult: float) -> void:
	runner.speed_mult = clampf(mult, 0.25, 4.0)


func set_prompt_labels(accept_key: String, skip_key: String) -> void:
	box.accept_label = accept_key
	box.skip_label = skip_key


func input_accept(pressed: bool) -> void:
	if not _open:
		return
	if pressed:
		runner.press_accept()
	else:
		runner.release_accept()
	_sync()


func input_skip(pressed: bool) -> void:
	if _open:
		runner.set_skip_held(pressed)


func input_skip_now() -> void:
	if _open:
		runner.skip_all()


func _process(delta: float) -> void:
	if not _open and not _queue.is_empty() and DlgGate.box_allowed(phase):
		_start_next()
	var target := dim_alpha if _open else 0.0
	_dim_t = move_toward(_dim_t, target, delta * 3.0)
	dim.color = Color(UiPalette.INK, _dim_t)
	if not _open:
		fade.color.a = move_toward(fade.color.a, 0.0, delta * 3.0)
		backdrop.modulate.a = fade.color.a
		return
	runner.tick(delta)
	_sync()


func _sync() -> void:
	if not _open:
		return
	if runner.state == DlgRunner.State.CUT:
		var p := runner.cut_progress()
		var a := clampf(sin(p * PI) * 1.4, 0.0, 1.0)
		fade.color = Color(0, 0, 0, a)
		backdrop.modulate.a = a
		box.visible = false
		return
	fade.color.a = move_toward(fade.color.a, 0.0, 0.08)
	backdrop.modulate.a = fade.color.a
	box.set_visible_chars(runner.visible_chars())
	box.set_waiting(runner.is_waiting())
	box.fast = runner.is_fast_forward()
	box.skip_progress = runner.skip_progress()


func _start_next() -> void:
	if _queue.is_empty():
		return
	_cur = _queue.pop_front()
	_open = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	box.visible = false
	var lines: Array[DlgLine] = []
	for l: Variant in _cur["lines"]:
		if l is DlgLine:
			lines.append(l)
	started.emit(_cur["kind"], _cur["key"])
	runner.start(lines)


func _on_line_started(i: int) -> void:
	var l := runner.current()
	if l == null:
		return
	var ch := story.character(l.who)
	box.show_line(l, ch, portraits.texture(l.who, l.expression, ch.portraits))
	box.visible = true
	line_shown.emit(_cur.get("kind", KIND_OTHER), i, l)


func _on_runner_finished(skipped: bool) -> void:
	var kind: StringName = _cur.get("kind", KIND_OTHER)
	var key: String = _cur.get("key", "")
	_open = false
	_cur = {}
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	finished.emit(kind, key, skipped)
	if _queue.is_empty():
		idle.emit()


func _emit_finished(kind: StringName, key: String, skipped: bool) -> void:
	finished.emit(kind, key, skipped)


func _input(event: InputEvent) -> void:
	if not handle_input or not _open:
		return
	if event is InputEventMouseButton:
		return # the box handles clicks (_gui_input)
	# Only presses are swallowed. A release must still reach the game's input layer: a key that went
	# down before the box opened (Enter held to skip the cinematic, let go over the outro) would
	# otherwise stay "down" there and its next press would be ignored.
	if event.is_action("ui_accept") and not event.is_echo():
		input_accept(event.is_pressed())
		if event.is_pressed():
			get_viewport().set_input_as_handled()
	elif event.is_action("ui_cancel") and not event.is_echo():
		input_skip(event.is_pressed())
		if event.is_pressed():
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START and event.is_pressed():
		input_skip_now()
		get_viewport().set_input_as_handled()
	elif (event is InputEventKey or event is InputEventJoypadButton) and (event.is_pressed() or event.is_echo()):
		# Everything else is swallowed while a box is up so nothing leaks into the game.
		get_viewport().set_input_as_handled()
