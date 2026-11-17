class_name HGBuild
extends RefCounted
## The engine's build/riser state (`state.build`). The port reads it while compiling, exactly as
## the engine does (a held or released build mutes kick/bass, densifies the closed hat and adds a
## Zeno snare roll); the live commands that start and release builds are host features and are not
## ported, so it stays inactive unless a caller sets it.

var held: bool = false
var released: bool = false
## Beat the build started.
var start: float = 0.0
## Beat a released build ends; meaningful only when has_end (engine `end: null` otherwise).
var end: float = 0.0
var has_end: bool = false
## Zeno roll ratio, first gap (beats) and hit count.
var q: float = 0.8
var gap: float = 1.0
var hits: float = 32.0
var bars: float = 4.0
var target: String = "bar"
var riser: float = 0.8
var cc: float = 74.0
var mute_kick: bool = true
var mute_bass: bool = true
var density: bool = true


func active() -> bool:
	return held or released


func copy() -> HGBuild:
	var b := HGBuild.new()
	b.held = held
	b.released = released
	b.start = start
	b.end = end
	b.has_end = has_end
	b.q = q
	b.gap = gap
	b.hits = hits
	b.bars = bars
	b.target = target
	b.riser = riser
	b.cc = cc
	b.mute_kick = mute_kick
	b.mute_bass = mute_bass
	b.density = density
	return b


## Overwrites the fields present in `d` (engine JSON keys).
func apply_dict(d: Dictionary) -> void:
	held = ODJson.boolean(d, "held", held)
	released = ODJson.boolean(d, "released", released)
	start = ODJson.num(d, "start", start)
	if d.has("end"):
		has_end = ODJson.is_number(d["end"])
		end = float(d["end"]) if has_end else 0.0
	q = ODJson.num(d, "q", q)
	gap = ODJson.num(d, "gap", gap)
	hits = ODJson.num(d, "hits", hits)
	bars = ODJson.num(d, "bars", bars)
	target = ODJson.string(d, "target", target)
	riser = ODJson.num(d, "riser", riser)
	cc = ODJson.num(d, "cc", cc)
	mute_kick = ODJson.boolean(d, "muteKick", mute_kick)
	mute_bass = ODJson.boolean(d, "muteBass", mute_bass)
	density = ODJson.boolean(d, "density", density)


func to_dict() -> Dictionary:
	return {
		"held": held, "released": released, "start": start, "end": end if has_end else null, "q": q,
		"gap": gap, "hits": hits, "bars": bars, "target": target, "riser": riser, "cc": cc,
		"muteKick": mute_kick, "muteBass": mute_bass, "density": density,
	}
