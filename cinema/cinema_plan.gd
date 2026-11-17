class_name CinemaPlan
extends RefCounted
## The cinematic director's output for one winning encounter: the shot list on the master beat
## timeline, the flourish cues, and (for debugging / tests) every candidate moment and action.

## Whole master beats of the encounter (CINE-05: the replay is exactly the encounter's timeline).
var horizon_beats: int = 0
## Master substeps per beat (OD.SUB_HZ * 60 / bpm).
var subs_per_beat: float = 120.0
var shots: Array[CinemaShot] = []
var cues: Array[CinemaTypes.Cue] = []
## Every candidate moment, in priority order; `shot` says which shot shows it (-1 = none).
var moments: Array[CinemaMoment] = []
var actions: Array[CinemaTypes.Action] = []
## Shot-count cap used (proportional to length).
var shot_cap: int = 0


## Index of the shot containing `beat` (clamped to the first / last shot), -1 when empty.
func shot_index_at(beat: float) -> int:
	if shots.is_empty():
		return -1
	if beat < float(shots[0].start_beat):
		return 0
	var lo := 0
	var hi := shots.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if float(shots[mid].start_beat) <= beat:
			lo = mid
		else:
			hi = mid - 1
	return lo


func shot_at(beat: float) -> CinemaShot:
	var i := shot_index_at(beat)
	return shots[i] if i >= 0 else null


## The shot that shows event index `ev` (by its source events), or null.
func shot_for_event(ev: int) -> CinemaShot:
	for s: CinemaShot in shots:
		if s.source_events.has(ev):
			return s
	return null


func to_dict() -> Dictionary:
	var s: Array = []
	for x: CinemaShot in shots:
		s.append(x.to_dict())
	var c: Array = []
	for x: CinemaTypes.Cue in cues:
		c.append(x.to_dict())
	var m: Array = []
	for x: CinemaMoment in moments:
		m.append(x.to_dict())
	return {"horizonBeats": horizon_beats, "shots": s, "cues": c, "moments": m}


## Readable timeline, one line per shot plus a bar ruler (tools/cinema_demo.gd prints this).
func timeline_text() -> String:
	var lines: PackedStringArray = []
	lines.append("horizon %d beats (%d bars), %d shots (cap %d), %d cues, %d moments" % [horizon_beats, horizon_beats / OD.BEATS_PER_BAR, shots.size(), shot_cap, cues.size(), moments.size()])
	var ruler := ""
	for b: int in horizon_beats:
		ruler += "|" if b % OD.BEATS_PER_BAR == 0 else "."
	lines.append("        " + ruler)
	for i: int in shots.size():
		var sh := shots[i]
		var bar := ""
		for b: int in horizon_beats:
			if b < sh.start_beat or b >= sh.end_beat:
				bar += " "
			elif b == int(floor(sh.key_beat)) and sh.kind != CinemaGrammar.KIND_COVERAGE and sh.kind != CinemaGrammar.KIND_OPENING:
				bar += "*"
			else:
				bar += "="
		lines.append("  #%-3d %s" % [i, bar])
		var who := ""
		for t: int in sh.tapes:
			who += OD.tape_letter(t)
		var extra := ""
		if sh.emphasis != CinemaGrammar.EMPHASIS_NONE:
			extra += " +" + String(sh.emphasis)
			if not sh.panes.is_empty():
				var p := ""
				for pane: CinemaTypes.Pane in sh.panes:
					p += OD.tape_letter(pane.tape) if pane.tape >= 0 else "?"
				extra += "(" + p + ")"
		if sh.focus_tape >= 0:
			extra += " track " + OD.tape_letter(sh.focus_tape)
		var co := ""
		for c: CinemaTypes.Callout in sh.callouts:
			co += (" " + OD.tape_letter(c.tape)) if c.tape >= 0 else (" " + c.id)
		lines.append("       b%3d-%-3d %-10s %-8s %-8s %-6s %s%s  [%s]%s" % [sh.start_beat, sh.end_beat, String(sh.kind), String(sh.framing), String(sh.move), String(sh.transition), who, extra, co.strip_edges(), ""])
		lines.append("               " + sh.reason)
	var cue_line := ""
	for c: CinemaTypes.Cue in cues:
		if c.kind != CinemaGrammar.CUE_BAR_SWEEP:
			cue_line += " %s@%.2f" % [String(c.kind), c.beat]
	if not cue_line.is_empty():
		lines.append("  cues:" + cue_line)
	var dropped := ""
	for m: CinemaMoment in moments:
		if m.shot < 0:
			dropped += " %s@%.2f(%d)" % [String(m.kind), m.key_beat, int(m.score)]
	if not dropped.is_empty():
		lines.append("  not shown:" + dropped)
	return "\n".join(lines)
