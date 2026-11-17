class_name AudioLayerVariant
extends RefCounted
## Everything about a layer's situation that changes the generated notes (director.ts LayerVariant).

## Tape speed (0.5, 1, 2, 4).
var speed: float = 1.0
## The self is a ghost (dead this run): the pattern thins and falls onto chord tones.
var dead: bool = false
## 1 forward, -1 reverse pass (retrograde contour), 0 stopped (hold figure).
var transport: int = 1
## Desync drift 0..1 in quarter steps; 0 is the exact baseline.
var drift: float = 0.0


static func make(p_speed: float, p_dead: bool = false, p_transport: int = 1, p_drift: float = 0.0) -> AudioLayerVariant:
	var v := AudioLayerVariant.new()
	v.speed = p_speed
	v.dead = p_dead
	v.transport = p_transport
	v.drift = p_drift
	return v


## The undisturbed layer at a speed.
static func baseline(p_speed: float) -> AudioLayerVariant:
	return make(p_speed)


func copy() -> AudioLayerVariant:
	return make(speed, dead, transport, drift)


func key() -> String:
	return "%s|%d|%d|%s" % [speed, 1 if dead else 0, transport, drift]


func equals(o: AudioLayerVariant) -> bool:
	return o != null and speed == o.speed and dead == o.dead and transport == o.transport and drift == o.drift
