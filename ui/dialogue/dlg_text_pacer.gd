class_name DlgTextPacer
extends RefCounted
## Punctuation-aware typewriter timing. Node-free and deterministic.
##
## compute(text) builds `times`, where times[i] is the time in seconds (at speed 1) at which character
## i becomes visible. Characters appear at `cps` per second; after a clause mark (, ; :) the next
## character waits `pause_clause`; after a sentence end (. ! ?) `pause_sentence`; each dot of an
## ellipsis waits `pause_ellipsis_dot`; a mid-line dash pair "--" waits `pause_dash`. Closing quotes
## and brackets right after punctuation are typed with it and the pause moves after them. A pause is
## only ever inserted *between* characters, never after the last one, so a line never "hangs" at its
## end. Spaces cost `space_factor` of a normal character.
##
##   var p := DlgTextPacer.new(); p.compute("Hello, you.")
##   p.visible_at(0.1)   # how many characters are visible 0.1 s into the line
##   p.total_time()      # when the whole line is visible

var cps: float = 55.0
var pause_clause: float = 0.11
var pause_sentence: float = 0.26
var pause_ellipsis_dot: float = 0.13
var pause_dash: float = 0.18
var space_factor: float = 0.6

var text: String = ""
var times: PackedFloat32Array = PackedFloat32Array()

const CLOSERS := "\"')]}"
const CLAUSE := ",;:"
const SENTENCE := ".!?"


func _init(p_cps: float = 55.0) -> void:
	cps = maxf(1.0, p_cps)


func compute(p_text: String) -> DlgTextPacer:
	text = p_text
	var n := text.length()
	times.resize(n)
	var step := 1.0 / cps
	var t := 0.0
	for i in n:
		times[i] = t
		if i == n - 1:
			break
		var c := text[i]
		var nxt := text[i + 1]
		t += step * (space_factor if nxt == " " else 1.0)
		t += _pause_after(i, c, nxt)
	return self


## Extra wait after character i (c) before character i + 1 (nxt).
func _pause_after(i: int, c: String, nxt: String) -> float:
	# Let closers ride with the punctuation before them: pause after the closer instead.
	if CLOSERS.contains(nxt) and (CLAUSE.contains(c) or SENTENCE.contains(c) or c == "-"):
		return 0.0
	var mark := c
	var at := i
	if CLOSERS.contains(c) and i > 0:
		mark = text[i - 1]
		at = i - 1
	if mark == ".":
		var dots_before := at > 0 and text[at - 1] == "."
		var dots_after := nxt == "."
		if dots_before or dots_after:
			return pause_ellipsis_dot
		# "3.5" or "a.b": a dot between non-space characters is not a sentence end.
		if nxt != " " and not CLOSERS.contains(nxt) and at > 0 and text[at - 1] != " ":
			return 0.0
		return pause_sentence
	if mark == "!" or mark == "?":
		if nxt == "!" or nxt == "?":
			return 0.0
		return pause_sentence
	if CLAUSE.contains(mark):
		if nxt != " ":
			return 0.0
		return pause_clause
	if mark == "-" and at > 0 and text[at - 1] == "-" and nxt != "-":
		return pause_dash
	return 0.0


## Number of characters visible `t` seconds into the line (0 .. length).
func visible_at(t: float) -> int:
	var n := times.size()
	if n == 0:
		return 0
	if t < 0.0:
		return 0
	# Binary search: count of times[i] <= t.
	var lo := 0
	var hi := n
	while lo < hi:
		var mid := (lo + hi) >> 1
		if times[mid] <= t:
			lo = mid + 1
		else:
			hi = mid
	return lo


## Seconds until the full line is visible.
func total_time() -> float:
	return times[times.size() - 1] if times.size() > 0 else 0.0


func length() -> int:
	return times.size()
