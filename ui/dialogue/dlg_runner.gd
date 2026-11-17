class_name DlgRunner
extends RefCounted
## Plays one dialogue sequence: typewriter progress, advance, hold-to-fast-forward, hold-to-skip and
## scene cuts. Node-free; the DialoguePlayer node feeds it time and input and draws its state.
##
## Input model (INTEGRATION.md "Dialogue box"):
##   - press accept while typing  -> the line completes at once
##   - press accept while waiting -> next line (or finish after the last)
##   - hold accept > HOLD_FF_AFTER -> fast-forward: typing at FF_MULT and each finished line advances
##     after FF_DWELL, until released
##   - hold skip for SKIP_HOLD (or call skip_all()) -> the whole sequence ends (skipped = true)
## No auto-advance otherwise. Every sequence can always be skipped: skip works in every state.

signal line_started(index: int)
signal line_completed(index: int)
## A cut before line `index` started (the player fades out, then in over CUT_TIME).
signal cut_started(index: int)
signal finished(skipped: bool)

enum State { IDLE, CUT, TYPING, WAITING, DONE }

const HOLD_FF_AFTER := 0.32
const FF_MULT := 5.0
const FF_DWELL := 0.22
const SKIP_HOLD := 0.7
const CUT_TIME := 1.4
## A press within this long of a line starting is ignored (an accept that completed or advanced the
## previous line must not also eat the next one on a key-repeat).
const PRESS_GUARD := 0.06

var lines: Array[DlgLine] = []
var index: int = -1
var state: State = State.IDLE
## Player text-speed setting (1 = default).
var speed_mult: float = 1.0
var cps: float = 55.0

var pacer: DlgTextPacer = DlgTextPacer.new()
## Virtual typing time inside the current line (advances faster when fast-forwarding).
var t: float = 0.0
## Real time since the line started / since it finished typing / since the cut started.
var line_age: float = 0.0
var wait_age: float = 0.0
var cut_age: float = 0.0
var accept_held: bool = false
var accept_hold_time: float = 0.0
var skip_held: bool = false
var skip_hold_time: float = 0.0
var skipped: bool = false


## Begin a sequence. An empty sequence finishes immediately (finished(false) is emitted from here).
func start(p_lines: Array[DlgLine]) -> void:
	lines = p_lines.duplicate()
	index = -1
	skipped = false
	accept_held = false
	accept_hold_time = 0.0
	skip_held = false
	skip_hold_time = 0.0
	state = State.IDLE
	_next()


func is_running() -> bool:
	return state == State.CUT or state == State.TYPING or state == State.WAITING


func current() -> DlgLine:
	return lines[index] if index >= 0 and index < lines.size() else null


## Characters of the current line visible now.
func visible_chars() -> int:
	match state:
		State.TYPING:
			return pacer.visible_at(t)
		State.WAITING:
			return pacer.length()
	return 0


func is_typing() -> bool:
	return state == State.TYPING


func is_waiting() -> bool:
	return state == State.WAITING


func is_fast_forward() -> bool:
	return accept_held and accept_hold_time >= HOLD_FF_AFTER


## 0..1 progress of a held skip.
func skip_progress() -> float:
	return clampf(skip_hold_time / SKIP_HOLD, 0.0, 1.0) if skip_held else 0.0


## 0..1 through the current cut (0.5 = fully black).
func cut_progress() -> float:
	return clampf(cut_age / CUT_TIME, 0.0, 1.0) if state == State.CUT else 0.0


func tick(dt: float) -> void:
	if not is_running():
		return
	if skip_held:
		skip_hold_time += dt
		if skip_hold_time >= SKIP_HOLD:
			skip_all()
			return
	if accept_held:
		accept_hold_time += dt
	var ff := is_fast_forward()
	match state:
		State.CUT:
			cut_age += dt
			if cut_age >= CUT_TIME:
				_begin_line()
		State.TYPING:
			line_age += dt
			t += dt * speed_mult * (FF_MULT if ff else 1.0)
			if t >= pacer.total_time():
				_complete_line()
		State.WAITING:
			wait_age += dt
			if ff and wait_age >= FF_DWELL:
				_next()


func press_accept() -> void:
	accept_held = true
	accept_hold_time = 0.0
	match state:
		State.TYPING:
			if line_age >= PRESS_GUARD:
				_complete_line()
		State.WAITING:
			if wait_age >= PRESS_GUARD:
				_next()


func release_accept() -> void:
	accept_held = false
	accept_hold_time = 0.0


func set_skip_held(held: bool) -> void:
	if held and not skip_held:
		skip_hold_time = 0.0
	skip_held = held
	if not held:
		skip_hold_time = 0.0


## End the whole sequence now (skip-all). Safe in any state.
func skip_all() -> void:
	if state == State.DONE or state == State.IDLE and lines.is_empty():
		return
	skipped = true
	_finish()


func _next() -> void:
	index += 1
	if index >= lines.size():
		_finish()
		return
	if lines[index].cut_before and index > 0:
		state = State.CUT
		cut_age = 0.0
		cut_started.emit(index)
		return
	_begin_line()


func _begin_line() -> void:
	pacer.cps = cps
	pacer.compute(lines[index].line)
	t = 0.0
	line_age = 0.0
	wait_age = 0.0
	state = State.TYPING
	line_started.emit(index)
	if pacer.length() == 0:
		_complete_line()


func _complete_line() -> void:
	state = State.WAITING
	wait_age = 0.0
	line_completed.emit(index)


func _finish() -> void:
	state = State.DONE
	accept_held = false
	skip_held = false
	finished.emit(skipped)
