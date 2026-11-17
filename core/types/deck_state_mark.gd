class_name DeckStateMark
extends RefCounted
## Master beat at which a self died / desynced / resynced in the latest resolved run
## (types.ts DeckView.stateMarks[]).

var beat: float = 0.0
## StateMarkKind.*
var kind: StringName = StateMarkKind.DEATH


static func make(p_beat: float, p_kind: StringName) -> DeckStateMark:
	var m := DeckStateMark.new()
	m.beat = p_beat
	m.kind = p_kind
	return m


func copy() -> DeckStateMark:
	return DeckStateMark.make(beat, kind)
