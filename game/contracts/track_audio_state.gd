class_name TrackAudioState
extends RefCounted
## State of one cassette's music layer for this instant (contracts.ts TrackAudioState).

## Layer is silent when false (cassette not yet recorded / not armed).
var present: bool = false
## TapeSpeed.
var speed: float = 1.0
## OD.LifeState.
var life: int = OD.LifeState.ALIVE
var synced: bool = true
## 1 forward, -1 reversing (retrograde contour), 0 stopped.
var transport: int = 0


static func make(p_present: bool, p_speed: float, p_life: int, p_synced: bool, p_transport: int) -> TrackAudioState:
	var t := TrackAudioState.new()
	t.present = p_present
	t.speed = p_speed
	t.life = p_life
	t.synced = p_synced
	t.transport = p_transport
	return t


func copy() -> TrackAudioState:
	return TrackAudioState.make(present, speed, life, synced, transport)
