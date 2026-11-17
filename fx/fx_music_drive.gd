class_name FxMusicDrive
extends RefCounted
## Pulses the world's music-reactive surfaces (ctx.music_reactive: rune grooves, neon, screens, the
## core heart) with the music (MUSIC-12, chapter 18 "Musical architecture"). The world view builds
## and registers them at level 1; the fx layer owns their modulation from then on. Visual only:
## brightness never feeds back into anything.
##
## Levels per kind (1 = as built):
##   rune    a wave that travels across the floor on the beat, tinted by "its" cassette's level
##           (each surface is assigned a tape from its position, like the prototype's rune tiles)
##   neon    breathes with the bar, flickers up on the beat
##   screen  follows the combined layer energy
##   core    a slow heartbeat on the bar
## The result is blended toward 1 by the mode's ambient strength, so recording stays restrained and
## the idle menu backdrop gets the full treatment.


## Ambient scale under reduce flashing: the largest swing (rune, ~+0.95) becomes ~+0.15.
const REDUCED_FLASH_SCALE := 0.16


## Tape a surface listens to: from its position when it has one, else from its index.
static func tape_for(m: MusicReactive, index: int) -> int:
	if m.has_at:
		return absi(floori(m.at.x) * 7 + floori(m.at.y) * 3) % 4
	return index % 4


## Raw level (before the ambient blend) of surface `m` for this music state.
static func level_for(m: MusicReactive, index: int, music: MusicPulse) -> float:
	var lv := music.levels
	var avg := 0.0
	for t: int in 4:
		avg += clampf(lv[t], 0.0, 1.0) if t < lv.size() else 0.0
	avg *= 0.25
	var bp := clampf(music.beat_pulse, 0.0, 1.0)
	var br := clampf(music.bar_pulse, 0.0, 1.0)
	match m.kind:
		MusicReactive.KIND_RUNE:
			var tape := tape_for(m, index)
			var own := clampf(lv[tape], 0.0, 1.0) if tape < lv.size() else 0.0
			var phase := (m.at.x + m.at.y) * 0.6 if m.has_at else index * 0.9
			var wave := maxf(0.0, cos(phase - music.beat * PI * 0.5))
			return 0.55 + 0.6 * own + 0.2 * bp + 0.35 * wave * wave * wave
		MusicReactive.KIND_NEON:
			return 0.85 + 0.3 * br + 0.12 * bp
		MusicReactive.KIND_SCREEN:
			return 0.7 + 0.55 * avg + 0.2 * bp
		MusicReactive.KIND_CORE:
			return 0.8 + 0.45 * br + 0.2 * bp
	return 1.0


## Apply the music to every surface. `ambient` is the mode's ambient strength (0 = as built).
## Returns how many surfaces were driven.
static func apply(reactive: Array[MusicReactive], music: MusicPulse, ambient: float) -> int:
	if music == null:
		return 0
	var k := clampf(ambient, 0.0, 1.0)
	var n := 0
	for i: int in reactive.size():
		var m := reactive[i]
		if m == null:
			continue
		var raw := level_for(m, i, music)
		m.set_level(1.0 + (raw - 1.0) * k)
		n += 1
	return n


## Return every surface to its authored look (level change / dispose).
static func reset(reactive: Array[MusicReactive]) -> void:
	for m: MusicReactive in reactive:
		if m != null:
			m.set_level(1.0)
