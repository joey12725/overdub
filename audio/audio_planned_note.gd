class_name AudioPlannedNote
extends RefCounted
## A layer note placed on the listening clock (scheduler.ts PlannedNote).

var id: int = 0
var note: AudioLayerNote
## When the note should be heard, in seconds on the caller's clock.
var time: float = 0.0
## Length in seconds.
var dur: float = 0.0


static func make(p_id: int, p_note: AudioLayerNote, p_time: float, p_dur: float) -> AudioPlannedNote:
	var p := AudioPlannedNote.new()
	p.id = p_id
	p.note = p_note
	p.time = p_time
	p.dur = p_dur
	return p
