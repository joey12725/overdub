class_name DeckView
extends RefCounted
## Everything the cassette-deck HUD needs for one cassette (types.ts DeckView; UI-06, UI-07,
## NEW-07..11). Built by the game's session, read by the HUD. Not serialised.

## TapeIndex.
var index: int = 0
## DeckStatus.*
var status: StringName = DeckStatus.EMPTY
## TapeSpeed, or 0.0 = none (prototype null).
var speed: float = 0.0
## OD.EndMode, or -1 = none (prototype null).
var end_mode: int = -1
## 0..1 progress along the local tape right now.
var local_progress: float = 0.0
## Playhead direction: 1 forward, -1 reversing, 0 stopped/idle.
var transport: int = 0
## Reel spin rate relative to the viewer's clock (so 2x visibly spins twice as fast as 1x).
var reel_rate: float = 0.0
## OD.LifeState, or -1 = none (prototype null).
var life: int = -1
var synced: bool = true
## Master-bar span of one traversal: level.bars / speed.
var span_bars: float = 0.0
## Event markers on this tape, in LOCAL ticks, for the timeline lane.
var marks: Array[DeckMark] = []
## Master beats at which this self died / desynced / resynced in the latest resolved run.
var state_marks: Array[DeckStateMark] = []


func copy() -> DeckView:
	var o := DeckView.new()
	o.index = index
	o.status = status
	o.speed = speed
	o.end_mode = end_mode
	o.local_progress = local_progress
	o.transport = transport
	o.reel_rate = reel_rate
	o.life = life
	o.synced = synced
	o.span_bars = span_bars
	for m: DeckMark in marks:
		o.marks.append(m.copy())
	for m: DeckStateMark in state_marks:
		o.state_marks.append(m.copy())
	return o
