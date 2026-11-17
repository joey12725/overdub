class_name DeckMark
extends RefCounted
## An event marker on a tape, in LOCAL ticks, for the timeline lane (types.ts DeckView.marks[]).

var tick: int = 0
## ActionKind.*
var kind: StringName = ActionKind.LIGHT


static func make(p_tick: int, p_kind: StringName) -> DeckMark:
	var m := DeckMark.new()
	m.tick = p_tick
	m.kind = p_kind
	return m


func copy() -> DeckMark:
	return DeckMark.make(tick, kind)
