class_name MVVariant
extends RefCounted
## Everything about a layer's situation that changes its generated notes (director.ts LayerVariant).

var speed: float = 1.0
## The self is a ghost this run: the pattern thins and falls onto chord tones (MUSIC-08).
var dead: bool = false
## 1 forward, -1 reverse pass (retrograde contour), 0 stopped (hold figure).
var transport: int = 1
## Desync drift 0..1 in quarter steps; 0 is the exact baseline.
var drift: float = 0.0


static func make(p_speed: float, p_dead: bool = false, p_transport: int = 1, p_drift: float = 0.0) -> MVVariant:
	var v := MVVariant.new()
	v.speed = p_speed
	v.dead = p_dead
	v.transport = p_transport
	v.drift = p_drift
	return v


func key() -> String:
	return "%s|%d|%d|%s" % [speed, 1 if dead else 0, transport, drift]
