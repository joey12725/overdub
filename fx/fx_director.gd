class_name FxDirector
extends RefCounted
## The CPU half of the effects layer (port of prototype/src/render/fx/director.ts).
##
## Turns RenderFrame events into pooled sprites and readouts, runs the continuous world-speed and
## cinematic treatments, and computes the overlay state and the shake/focus requests. It owns no
## nodes, so it runs (and is tested) headless; fx/fx_layer.gd uploads its pools every frame.
##
## Never touches simulation state and never delays anything but its own sprites: the "hit-stop" here
## freezes a burst's particles for a few frames while the game keeps running (CINE-04, MUSIC-07).

const GLOW_CAPACITY := 1536
const INK_CAPACITY := 384
const TEXT_CAPACITY := 48
const RIBBON_POINTS := 40
## Max new readouts per frame: a skipped review can flush hundreds of events at once.
const WORDS_PER_FRAME := 6
## Seconds a fading readout is given to clear out when a new one lands on it.
const WORD_HURRY_S := 0.08
## Iso screen axes (camera yaw 45 deg, pitch ~35 deg; docs/GODOT-PORT.md "Presentation").
const _ISO_RIGHT := Vector3(0.7071, 0.0, -0.7071)
const _ISO_UP := Vector3(-0.4056, 0.8192, -0.4056)

## Height of impact effects above the floor (roughly Moxie's chest).
const H_IMPACT := 0.8
const H_FLOOR := 0.035
const H_WORD := 1.55

## Sprite tags for continuous (non-event) treatments, outside the EFFECT_IDS index range.
const TAG_WORLD_SPEED := 250
## Continuous cinematic flourishes (beat ripples); only ever spawned in cinematic mode.
const TAG_CINE_CONTINUOUS := 251


## Camera-space overlay state (letterbox, flashes, world-speed tint, speed lines, sweep, glitch).
class ScreenState:
	extends RefCounted
	var letterbox: float = 0.0
	var flash: Color = Color.BLACK
	var flash_a: float = 0.0
	var tint: Color = Color.BLACK
	var tint_a: float = 0.0
	## World-speed speed lines 0..1 and sign (+1 world sped up, -1 world slowed).
	var speed: float = 0.0
	var speed_sign: float = 0.0
	## Bar-synced light sweep: position 0..1 across the screen and strength.
	var sweep_pos: float = 0.0
	var sweep_a: float = 0.0
	## Radial speed-line burst around a world point (scene coordinates; cinematic impacts).
	var burst: Vector3 = Vector3.ZERO
	var burst_amt: float = 0.0
	## Glitch tear strength and colour (desync, boss recall).
	var glitch: float = 0.0
	var glitch_color: Color = Color.WHITE
	## Chromatic split kick 0..1 for ctx.post (desync / recall), decays here.
	var chromatic: float = 0.0
	var time: float = 0.0


## Per-tape colour ribbons for the cinematic (four performances read as four voices).
class Ribbons:
	extends RefCounted
	var pts: PackedVector3Array
	var head: PackedInt32Array
	var count: PackedInt32Array
	## Current visibility 0..1 (eases in and out).
	var alpha: PackedFloat32Array
	## 1 when the self is a ghost (fainter), 2 when desynced (flickers), 0 alive.
	var state: PackedByteArray
	var present: PackedByteArray
	var last: PackedVector2Array
	var sample_timer: float = 0.0

	func _init() -> void:
		pts.resize(4 * RIBBON_POINTS)
		head.resize(4)
		count.resize(4)
		alpha.resize(4)
		state.resize(4)
		present.resize(4)
		last.resize(4)

	func reset(t: int) -> void:
		count[t] = 0
		head[t] = 0

	func push(t: int, p: Vector3) -> void:
		var h := head[t]
		pts[t * RIBBON_POINTS + h] = p
		head[t] = (h + 1) % RIBBON_POINTS
		if count[t] < RIBBON_POINTS:
			count[t] += 1

	## Index into pts of the k-th point from oldest (0) to newest (count-1).
	func point_index(t: int, k: int) -> int:
		var start := (head[t] - count[t] + RIBBON_POINTS) % RIBBON_POINTS
		return t * RIBBON_POINTS + ((start + k) % RIBBON_POINTS)


var glow: FxSpritePool
var ink: FxSpritePool
var text: FxTextPool
var screen := ScreenState.new()
var ribbons := Ribbons.new()
## How many times each effect (index into EFFECT_IDS) was triggered since load.
var spawn_counts: PackedInt32Array

## Shake requested this frame (0..1, already scaled by mode).
var shake_out: float = 0.0
## Cinematic focus request: sim point and weight; weight 0 means none.
var focus_x: float = 0.0
var focus_y: float = 0.0
var focus_w: float = 0.0

## Smoothed signed world-speed amount (-1 slowed ... +1 sped up).
var world_speed: float = 0.0
var mode: StringName = ViewMode.IDLE
## Chord changes seen in cinematic mode (palette flashes fired).
var chord_flashes: int = 0

var env: FxEnv
var _rng := FxRng.new(1)
var _c := Color.WHITE
var _tag: int = 0
var _alpha_k: float = 1.0
var _count_k: float = 1.0
var _words_this_frame: int = 0
var _prof: FxCatalog.ModeProfile = FxCatalog.profile(ViewMode.IDLE)
var _last_master_beat: float = NAN
var _last_music_beat: float = NAN
var _last_chord: float = NAN
var _smear_timer: float = 0.0
## Full-screen flash budget (docs/ACCESSIBILITY.md "Photosensitivity limits"): screen time and peak
## of the last accepted flash.
var _last_flash_t: float = -INF
var _last_flash_peak: float = 0.0
## True while a cinematic director plan drives this frame (RenderFrame.cinema): its cues replace the
## director's own chord-change detection and its letterbox replaces the mode profile's.
var _directed: bool = false
## Flash / chromatic limits for the current reduce-flashing setting (AccessKit.flash_limits).
var _limits: Dictionary = {}
var _limits_reduced: int = -1


func _init(p_env: FxEnv) -> void:
	env = p_env
	var low := env.quality == WorldViewBase.QUALITY_LOW
	glow = FxSpritePool.new(GLOW_CAPACITY >> 1 if low else GLOW_CAPACITY)
	ink = FxSpritePool.new(INK_CAPACITY >> 1 if low else INK_CAPACITY)
	text = FxTextPool.new(TEXT_CAPACITY)
	spawn_counts.resize(FxCatalog.EFFECT_IDS.size())


func set_quality(q: StringName) -> void:
	env.quality = q


## The active mode profile.
func profile() -> FxCatalog.ModeProfile:
	return _prof


func update(frame: RenderFrame) -> void:
	var dt := clampf(frame.dt, 0.0, 0.1)
	var prof := FxCatalog.profile(frame.mode)
	mode = frame.mode
	_prof = prof
	screen.time += dt
	shake_out = 0.0
	_words_this_frame = 0
	_alpha_k = minf(1.1, 0.55 + 0.45 * prof.intensity)
	_count_k = prof.intensity * (0.6 if env.quality == WorldViewBase.QUALITY_LOW else 1.0)
	var cf: CinemaFrame = frame.cinema if frame.mode == ViewMode.CINEMATIC else null
	_directed = cf != null and cf.shot != null

	if prof.events:
		for ev: SimEvent in frame.events:
			if ev != null:
				_dispatch(ev, frame.mode)
	if _directed:
		_play_cues(cf)

	var wr := frame.world_rate if (frame.world_rate > 0.0 and is_finite(frame.world_rate)) else 1.0
	# World-attached effects run a little slower in a slowed world and faster in a sped one, so the
	# sparks themselves carry the tape speed; the square root keeps them readable at 0.25x / 4x.
	var fx_rate := clampf(sqrt(wr), 0.5, 2.0)

	if frame.snap != null:
		_update_world_speed(frame, prof, wr, fx_rate, dt)
		_update_music_flourishes(frame, dt, fx_rate)
		_update_ribbons(frame, dt)
		_update_focus(frame, dt)
	_decay_screen(dt, cf.letterbox if _directed else -1.0)

	glow.update(dt * fx_rate)
	ink.update(dt * fx_rate)
	# Readouts live on wall time: they are text to be read, not part of the world.
	text.update(dt)


## Remove every transient effect (level load / mode resets).
func clear() -> void:
	glow.clear()
	ink.clear()
	text.clear()
	for t: int in 4:
		ribbons.reset(t)
	screen.flash_a = 0.0
	screen.burst_amt = 0.0
	screen.glitch = 0.0
	screen.chromatic = 0.0
	focus_w = 0.0


# ───────────────────────────── routing ─────────────────────────────

func _dispatch(ev: SimEvent, p_mode: StringName) -> void:
	# An event type from a newer sim build without a route is ignored rather than breaking a frame.
	var routes := FxCatalog.routes_for(ev.type)
	for r: Variant in routes:
		var id: StringName = r
		if not FxCatalog.effect_allowed(id, p_mode):
			continue
		_tag = FxCatalog.effect_index(id)
		spawn_counts[_tag] += 1
		_rng.reseed(FxRng.hash4(ev.sub, _tag, roundi(ev.x * 16.0), roundi(ev.y * 16.0)))
		_run(id, ev)


func _run(id: StringName, ev: SimEvent) -> void:
	match id:
		FxCatalog.HIT_BURST:
			_hit_burst(ev, 1.0)
		FxCatalog.HIT_STREAKS:
			_hit_streaks(ev)
		FxCatalog.TIER_WORD:
			_tier_word(ev)
		FxCatalog.KILL_BURST:
			_kill_burst(ev)
		FxCatalog.KILL_WORD:
			_color_tape(ev.tape, env.palette.hazard)
			_whiten(0.15)
			_word(FxWords.W_KO, ev.x, H_WORD + 0.15, ev.y, 0.55, 1.0, 0.09, 0.9)
		FxCatalog.DEBRIS:
			_debris(ev)
		FxCatalog.BREAK_WORD:
			_c = env.palette.hazard
			_word(FxWords.W_BREAK, ev.x, H_WORD + 0.1, ev.y, 0.5, 1.0, 0.08, 0.9)
		FxCatalog.CLANG_SPARK:
			_clang_spark(ev)
		FxCatalog.CLANG_TELL:
			_clang_tell(ev)
		FxCatalog.SWING_ARC:
			_swing_arc(ev)
		FxCatalog.WHIFF_PUFF:
			_whiff_puff(ev)
		FxCatalog.DODGE_AFTERIMAGE:
			_dodge_afterimage(ev)
		FxCatalog.MUZZLE_FLASH:
			_muzzle(ev, FxColors.tape(ev.tape), 0.5)
		FxCatalog.PROJECTILE_IMPACT:
			_hit_burst(ev, 0.75)
		FxCatalog.INTERACT_PING:
			_interact_ping(ev)
		FxCatalog.INTERACT_FAIL:
			_interact_fail(ev)
		FxCatalog.DOOR_PULSE:
			_door_pulse(ev)
		FxCatalog.PLATE_PULSE:
			_plate_pulse(ev)
		FxCatalog.LASER_PULSE:
			_laser_pulse(ev)
		FxCatalog.CORE_IGNITE:
			_core_ignite(ev)
		FxCatalog.DEATH_SHATTER:
			_death_shatter(ev)
		FxCatalog.TAPE_LETTER:
			_tape_letter(ev)
		FxCatalog.DESYNC_TEAR:
			_desync_tear(ev)
		FxCatalog.RESYNC_CONVERGE:
			_resync_converge(ev)
		FxCatalog.WRAP_BLINK:
			_wrap_blink(ev)
		FxCatalog.TURN_CHEVRONS:
			_turn_chevrons(ev)
		FxCatalog.END_STOP:
			_end_stop(ev)
		FxCatalog.TELEGRAPH_RING:
			_telegraph_ring(ev)
		FxCatalog.ENEMY_SLASH:
			_enemy_slash(ev)
		FxCatalog.ENEMY_MUZZLE:
			_muzzle(ev, env.palette.neon_b, 0.42)
		FxCatalog.STAGGER_STARS:
			_stagger_stars(ev)
		FxCatalog.BOSS_SHOCK:
			_boss_shock(ev)
		FxCatalog.BOSS_RECALL_TELL:
			_boss_recall_tell(ev)
		FxCatalog.OBJECTIVE_PULSE:
			_objective_pulse(ev)
		FxCatalog.STEP_DUST:
			_step_dust(ev)
		FxCatalog.IMPACT_DUST:
			_impact_dust(ev)
		FxCatalog.INK_SPLASH:
			_ink_splash(ev)
		FxCatalog.SPEED_LINE_BURST:
			_speed_line_burst(ev)
		FxCatalog.CINE_ECHO:
			_cine_echo(ev)
		FxCatalog.CINE_FOCUS:
			_cine_focus(ev)
		FxCatalog.FINALE_BURST:
			_finale_burst(ev)
		FxCatalog.TRAP_FX:
			_trap_fx(ev)
		_:
			push_warning("FxDirector: effect '%s' has no implementation" % id)


# ───────────────────────────── helpers ─────────────────────────────

func _color_tape(t: int, fallback: Color) -> void:
	_c = FxColors.tape(t, fallback)


func _whiten(k: float) -> void:
	_c = Color(_c.r + (1.0 - _c.r) * k, _c.g + (1.0 - _c.g) * k, _c.b + (1.0 - _c.b) * k)


func _n(cnt: float) -> int:
	return maxi(1, roundi(cnt * _count_k))


## Momentum relative to a 1x standing light blow.
func _ratio(ev: SimEvent) -> float:
	if not ev.has_power or not is_finite(ev.power):
		return 1.0
	return maxf(0.0, ev.power) / (env.ref_momentum if env.ref_momentum > 1e-6 else 1.0)


func _tier(ev: SimEvent) -> int:
	return FxWords.momentum_tier(ev.power if ev.has_power else env.ref_momentum, env.ref_momentum)


func _request_shake(m: float) -> void:
	var s := minf(1.0, m * _prof.shake)
	if s > shake_out:
		shake_out = s


func _emit(pool: FxSpritePool, p_shape: int, p_mode: int, x: float, y: float, z: float, s0: float, s1: float, p_life: float, a: float) -> int:
	var i := pool.spawn(_tag)
	pool.pos[i] = Vector3(x, y, z)
	pool.color[i] = _c
	pool.alpha[i] = a * _alpha_k
	pool.size0[i] = s0
	pool.size1[i] = s1
	pool.life[i] = p_life
	pool.shape[i] = p_shape
	pool.mode[i] = p_mode
	return i


func _set_vel(pool: FxSpritePool, i: int, vx: float, vy: float, vz: float) -> void:
	pool.vel[i] = Vector3(vx, vy, vz)


func _set_dir(pool: FxSpritePool, i: int, dx: float, dy: float, dz: float, p_stretch: float) -> void:
	pool.dir[i] = Vector3(dx, dy, dz)
	pool.stretch[i] = p_stretch


## Spawn a readout in the current colour. Returns -1 when the frame's word budget is spent.
func _word(w: int, x: float, y: float, z: float, h: float, p_life: float, p_freeze: float, p_pop: float) -> int:
	if _words_this_frame >= WORDS_PER_FRAME or _prof.text_scale <= 0.0:
		return -1
	# Legibility: a word never lands on top of another young word. The same word at the same spot
	# (a hit then the kill on one target) re-pops the existing readout instead of doubling it; a
	# different word is lifted above whatever it would overlap.
	var lift_y := y
	var hh := h * _prof.text_scale
	for _pass: int in 4:
		var moved := false
		for j: int in text.capacity:
			if text.alive[j] == 0:
				continue
			if not _words_overlap(j, w, x, lift_y, z, hh):
				continue
			if text.age[j] > text.life[j] * 0.6:
				# Already fading: hurry it out rather than stacking over it.
				text.life[j] = minf(text.life[j], text.age[j] + WORD_HURRY_S)
				continue
			if text.word[j] == w and _pass == 0:
				text.age[j] = 0.0
				text.freeze[j] = maxf(text.freeze[j], p_freeze)
				text.pop[j] = maxf(text.pop[j], p_pop)
				text.height[j] = maxf(text.height[j], h * _prof.text_scale)
				text.life[j] = maxf(text.life[j], p_life)
				text.tint[j] = _c
				return j
			# Raise the new word until its screen box sits just above word j's.
			var sy := (Vector3(x, lift_y, z) - text.pos[j]).dot(_ISO_UP)
			var need := 0.5 * (text.height[j] + hh) * 1.12
			lift_y += maxf(0.0, need - sy) / _ISO_UP.y
			moved = true
		if not moved:
			break
	_words_this_frame += 1
	var i := text.spawn(_tag, w)
	text.pos[i] = Vector3(x + _rng.sym(0.12), lift_y, z + _rng.sym(0.12))
	text.tint[i] = _c
	text.height[i] = h * _prof.text_scale
	text.life[i] = p_life
	text.freeze[i] = p_freeze
	text.pop[i] = p_pop
	# A slight hand-set tilt reads as inked lettering rather than UI text.
	text.rot[i] = _rng.sym(0.14)
	return i


## Rough on-screen half width of a word (atlas words are bold condensed caps: ~0.6 h per glyph).
static func _word_half_w(w: int, h: float) -> float:
	var n := FxWords.WORDS[w].length() if w >= 0 and w < FxWords.WORDS.size() else 4
	return 0.5 * h * (0.4 + 0.6 * n)


## Would a word `w` of height `hh` at (x, y, z) overlap live word j on screen (iso projection)?
func _words_overlap(j: int, w: int, x: float, y: float, z: float, hh: float) -> bool:
	var d := Vector3(x, y, z) - text.pos[j]
	var sx := absf(d.dot(_ISO_RIGHT))
	var sy := d.dot(_ISO_UP)
	var hj := text.height[j]
	if sx >= _word_half_w(w, hh) + _word_half_w(text.word[j], hj):
		return false
	# Overlapping columns: a clash unless the new word already sits fully above or below.
	return absf(sy) < 0.5 * (hj + hh) * 1.12 - 1e-4


func _dir_of(ev: SimEvent) -> float:
	return ev.dir if (ev.has_dir and is_finite(ev.dir)) else _rng.next() * TAU


## Sparks flying from (x, y, z) in a cone around angle `a` (sim / XZ plane).
func _sparks(cnt: int, x: float, y: float, z: float, a: float, spread: float, speed: float, sz: float, p_life: float, p_freeze: float, p_gravity: float) -> void:
	for _k: int in cnt:
		var ang := a + _rng.sym(spread)
		var sp := speed * _rng.range_f(0.55, 1.1)
		var vy := sp * _rng.range_f(-0.15, 0.45)
		var vx := cos(ang) * sp
		var vz := sin(ang) * sp
		var i := _emit(glow, FxSpritePool.SHAPE_STREAK, FxSpritePool.MODE_STREAK, x, y, z, sz, sz * 0.5, p_life * _rng.range_f(0.7, 1.2), 1.0)
		_set_vel(glow, i, vx, vy, vz)
		var inv := 1.0 / maxf(1e-4, Vector3(vx, vy, vz).length())
		_set_dir(glow, i, vx * inv, vy * inv, vz * inv, _rng.range_f(3.0, 5.5))
		glow.drag[i] = 5.0
		glow.gravity[i] = p_gravity
		glow.freeze[i] = p_freeze


# ───────────────────────────── effects ─────────────────────────────

func _hit_burst(ev: SimEvent, scale: float) -> void:
	var r := _ratio(ev)
	var tier := _tier(ev)
	var s := (0.6 + 0.4 * sqrt(minf(6.0, r))) * scale
	var frz := 0.035 + 0.022 * tier
	var x := ev.x
	var z := ev.y
	_color_tape(ev.tape, WorldTraps.WARN_COLOR if _trap_hit(ev) else FxColors.WHITE)
	_whiten(0.55)
	var i := _emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, x, H_IMPACT, z, 0.55 * s, 1.0 * s, 0.2, 0.95)
	glow.freeze[i] = frz
	_color_tape(ev.tape, WorldTraps.WARN_COLOR if _trap_hit(ev) else FxColors.WHITE)
	i = _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_BILLBOARD, x, H_IMPACT, z, 0.3 * s, 1.5 * s, 0.28, 0.85)
	glow.param[i] = 0.14
	glow.freeze[i] = frz
	i = _emit(glow, FxSpritePool.SHAPE_SPARK, FxSpritePool.MODE_BILLBOARD, x, H_IMPACT, z, 0.9 * s, 0.4 * s, 0.14, 1.0)
	glow.rot[i] = _rng.next() * PI
	glow.freeze[i] = frz
	_whiten(0.3)
	var a := _dir_of(ev)
	_sparks(_n(5 + 3 * tier), x, H_IMPACT, z, a, 0.9, 5.0 + 1.6 * tier, 0.07 * s, 0.3, frz, 4.0)
	if tier >= 1:
		_request_shake(0.06 + 0.06 * minf(6.0, r))


func _hit_streaks(ev: SimEvent) -> void:
	var tier := _tier(ev)
	var a := _dir_of(ev)
	var dx := cos(a)
	var dz := sin(a)
	_color_tape(ev.tape, FxColors.WHITE)
	_whiten(0.4)
	var cnt := _n(2 + tier)
	for _k: int in cnt:
		var off := _rng.sym(0.35)
		var px := ev.x - dz * off + dx * _rng.range_f(0.1, 0.5)
		var pz := ev.y + dx * off + dz * _rng.range_f(0.1, 0.5)
		var sp := 10.0 + 3.0 * tier
		var i := _emit(glow, FxSpritePool.SHAPE_STREAK, FxSpritePool.MODE_STREAK, px, H_IMPACT + _rng.sym(0.25), pz, 0.05, 0.03, 0.16, 0.9)
		_set_vel(glow, i, dx * sp, 0.0, dz * sp)
		_set_dir(glow, i, dx, 0.0, dz, 10.0 + 2.0 * tier)
		glow.drag[i] = 8.0
		glow.freeze[i] = 0.03 + 0.02 * tier


func _tier_word(ev: SimEvent) -> void:
	var tier := _tier(ev)
	if tier < _prof.min_word_tier:
		return
	if tier == 0:
		_c = FxColors.TIER0_WORD
	else:
		_color_tape(ev.tape, FxColors.WHITE)
		_whiten(0.1)
	_word(FxWords.tier_word(tier), ev.x, H_WORD, ev.y, 0.34 + 0.08 * tier, 0.75 + 0.1 * tier, 0.035 + 0.022 * tier, 0.55 + 0.15 * tier)


func _kill_burst(ev: SimEvent) -> void:
	_hit_burst(ev, 1.35)
	var x := ev.x
	var z := ev.y
	var a := _dir_of(ev)
	# Ink shards: the anime "shatter" read of a defeat, in the theme's ink so they read on any floor.
	_c = env.palette.ink
	for _k: int in _n(7):
		var ang := a + _rng.sym(1.4)
		var sp := _rng.range_f(2.5, 5.5)
		var i := _emit(ink, FxSpritePool.SHAPE_SHARD, FxSpritePool.MODE_BILLBOARD, x, H_IMPACT, z, _rng.range_f(0.1, 0.2), 0.08, _rng.range_f(0.5, 0.8), 0.9)
		_set_vel(ink, i, cos(ang) * sp, _rng.range_f(1.5, 4.0), sin(ang) * sp)
		ink.gravity[i] = 12.0
		ink.floor_y[i] = 0.05
		ink.rot[i] = _rng.next() * TAU
		ink.rot_vel[i] = _rng.sym(14.0)
		ink.fade_pow[i] = 2.0
	_color_tape(ev.tape, env.palette.hazard)
	var j := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, x, H_FLOOR, z, 0.4, 2.2, 0.45, 0.7)
	glow.param[j] = 0.08
	_request_shake(0.32)


func _debris(ev: SimEvent) -> void:
	var pal := env.palette
	var a := _dir_of(ev)
	var cnt := _n(14)
	for k: int in cnt:
		_c = pal.wall_top if k % 3 == 0 else pal.wall
		var ang := a + _rng.sym(1.2)
		var sp := _rng.range_f(2.0, 6.0)
		var i := _emit(ink, FxSpritePool.SHAPE_DEBRIS, FxSpritePool.MODE_BILLBOARD, ev.x + _rng.sym(0.4), _rng.range_f(0.3, 1.2), ev.y + _rng.sym(0.4), _rng.range_f(0.12, 0.26), 0.1, _rng.range_f(1.1, 1.6), 1.0)
		_set_vel(ink, i, cos(ang) * sp, _rng.range_f(2.0, 5.5), sin(ang) * sp)
		ink.gravity[i] = 14.0
		ink.floor_y[i] = 0.08
		ink.rot[i] = _rng.next() * TAU
		ink.rot_vel[i] = _rng.sym(10.0)
		ink.fade_pow[i] = 4.0
		ink.freeze[i] = 0.06
	_c = FxColors.DUST
	for _k: int in _n(6):
		var i := _emit(ink, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x + _rng.sym(0.6), _rng.range_f(0.2, 0.9), ev.y + _rng.sym(0.6), 0.4, 1.3, _rng.range_f(0.7, 1.0), 0.2)
		_set_vel(ink, i, _rng.sym(0.8), 0.4, _rng.sym(0.8))
		ink.drag[i] = 2.0
	_c = pal.hazard
	_whiten(0.4)
	var j := _emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 1.0, 1.8, 0.22, 0.8)
	glow.freeze[j] = 0.06
	_request_shake(0.45)


func _clang_spark(ev: SimEvent) -> void:
	# Deliberately dull: few, slow, grey sparks that drop, with no flash ring and no freeze, so a
	# blow without enough momentum (Scenario K) never reads as a real hit.
	_c = FxColors.CLANG
	var a := _dir_of(ev) + PI
	_sparks(_n(6), ev.x, H_IMPACT, ev.y, a, 1.3, 2.6, 0.05, 0.3, 0.0, 10.0)
	var i := _emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 0.3, 0.35, 0.12, 0.35)
	glow.fade_pow[i] = 2.0


func _clang_tell(ev: SimEvent) -> void:
	_c = FxColors.CLANG
	# An inward-collapsing dashed ring: the force bounced off instead of radiating out.
	var i := _emit(glow, FxSpritePool.SHAPE_DASHRING, FxSpritePool.MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 1.1, 0.35, 0.38, 0.75)
	glow.param[i] = 0.12
	# A sagging down-chevron: "not enough".
	i = _emit(glow, FxSpritePool.SHAPE_CHEVRON, FxSpritePool.MODE_BILLBOARD, ev.x, H_IMPACT + 0.55, ev.y, 0.22, 0.2, 0.5, 0.8)
	glow.rot[i] = -PI / 2.0
	_set_vel(glow, i, 0.0, -0.6, 0.0)
	_c = FxColors.CLANG_WORD
	_word(FxWords.W_CLANG, ev.x, H_WORD - 0.1, ev.y, 0.34, 0.8, 0.0, 0.25)


func _swing_arc(ev: SimEvent) -> void:
	var heavy := ev.detail == "heavy"
	var reach := env.melee_reach if env.melee_reach > 0.0 else 1.2
	var half := deg_to_rad(env.melee_arc_deg if env.melee_arc_deg > 0.0 else 120.0) * 0.5
	_color_tape(ev.tape, FxColors.WHITE)
	_whiten(0.2)
	var s := reach / 0.78
	var i := _emit(glow, FxSpritePool.SHAPE_ARC, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR + 0.01, ev.y, s * 0.85, s, 0.22 if heavy else 0.15, 0.6 if heavy else 0.45)
	glow.param[i] = half
	glow.rot[i] = _dir_of(ev)


func _whiff_puff(ev: SimEvent) -> void:
	var a := _dir_of(ev)
	_c = FxColors.DUST
	for _k: int in _n(3):
		var d := _rng.range_f(0.5, 1.0)
		var i := _emit(ink, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x + cos(a) * d, _rng.range_f(0.4, 0.9), ev.y + sin(a) * d, 0.18, 0.45, 0.32, 0.25)
		_set_vel(ink, i, cos(a) * 0.6, 0.3, sin(a) * 0.6)


func _dodge_afterimage(ev: SimEvent) -> void:
	var a := _dir_of(ev)
	var dx := cos(a)
	var dz := sin(a)
	_color_tape(ev.tape, FxColors.WHITE)
	for k: int in 3:
		var back := 0.2 + k * 0.25
		var i := _emit(glow, FxSpritePool.SHAPE_STREAK, FxSpritePool.MODE_STREAK, ev.x - dx * back, 0.35 + k * 0.3, ev.y - dz * back, 0.12, 0.05, 0.25, 0.45)
		_set_dir(glow, i, dx, 0.0, dz, 6.0)
		_set_vel(glow, i, -dx * 1.5, 0.0, -dz * 1.5)
	var j := _emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.5, 0.9, 0.3, 0.3)
	glow.rot[j] = a


func _muzzle(ev: SimEvent, col: Color, sz: float) -> void:
	var a := _dir_of(ev)
	var dx := cos(a)
	var dz := sin(a)
	var x := ev.x + dx * 0.5
	var z := ev.y + dz * 0.5
	_c = col
	_whiten(0.35)
	var i := _emit(glow, FxSpritePool.SHAPE_STAR, FxSpritePool.MODE_BILLBOARD, x, H_IMPACT, z, sz, sz * 0.6, 0.11, 1.0)
	glow.rot[i] = _rng.next() * TAU
	for _k: int in _n(3):
		var j := _emit(glow, FxSpritePool.SHAPE_STREAK, FxSpritePool.MODE_STREAK, x, H_IMPACT, z, 0.05, 0.03, 0.12, 0.8)
		var ang := a + _rng.sym(0.3)
		_set_vel(glow, j, cos(ang) * 7.0, 0.0, sin(ang) * 7.0)
		_set_dir(glow, j, cos(ang), 0.0, sin(ang), 5.0)
		glow.drag[j] = 10.0


func _interact_ping(ev: SimEvent) -> void:
	_color_tape(ev.tape, FxColors.WHITE)
	var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.2, 1.0, 0.42, 0.75)
	glow.param[i] = 0.12
	var j := _emit(glow, FxSpritePool.SHAPE_DOT, FxSpritePool.MODE_BILLBOARD, ev.x, 0.9, ev.y, 0.16, 0.08, 0.45, 0.9)
	_set_vel(glow, j, 0.0, 1.6, 0.0)


func _interact_fail(ev: SimEvent) -> void:
	_c = FxColors.CLANG
	var i := _emit(glow, FxSpritePool.SHAPE_CROSS, FxSpritePool.MODE_BILLBOARD, ev.x, 1.25, ev.y, 0.32, 0.26, 0.45, 0.8)
	glow.fade_pow[i] = 0.6


func _door_pulse(ev: SimEvent) -> void:
	var open := ev.detail == "on" or ev.detail == "open"
	_c = env.palette.hazard if open else env.palette.neon_b
	var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.4, 1.6, 0.5, 0.55)
	glow.param[i] = 0.1
	_c = FxColors.DUST
	for _k: int in _n(4):
		var j := _emit(ink, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x + _rng.sym(0.5), 0.15, ev.y + _rng.sym(0.5), 0.25, 0.7, 0.6, 0.22)
		_set_vel(ink, j, _rng.sym(0.6), 0.5, _rng.sym(0.6))


func _plate_pulse(ev: SimEvent) -> void:
	var on := ev.detail != "off"
	_c = env.palette.hazard if on else FxColors.CLANG
	var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.3 if on else 0.9, 1.1 if on else 0.4, 0.4, 0.7 if on else 0.4)
	glow.param[i] = 0.12


func _laser_pulse(ev: SimEvent) -> void:
	var on := ev.detail != "off"
	_c = env.palette.neon_b
	var i := _emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x, 0.6, ev.y, 0.5 if on else 0.4, 0.9 if on else 0.1, 0.25 if on else 0.3, 0.8 if on else 0.4)
	glow.fade_pow[i] = 1.5
	if on:
		var j := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_BILLBOARD, ev.x, 0.6, ev.y, 0.2, 0.8, 0.22, 0.6)
		glow.param[j] = 0.15


func _core_ignite(ev: SimEvent) -> void:
	var pal := env.palette
	_c = pal.neon_a
	_whiten(0.3)
	var i := _emit(glow, FxSpritePool.SHAPE_STREAK, FxSpritePool.MODE_STREAK, ev.x, 1.4, ev.y, 0.35, 0.2, 0.7, 0.9)
	_set_dir(glow, i, 0.0, 1.0, 0.0, 9.0)
	glow.fade_pow[i] = 0.7
	i = _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.4, 2.8, 0.7, 0.8)
	glow.param[i] = 0.06
	_emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x, 0.9, ev.y, 0.8, 1.8, 0.35, 0.9)
	_sparks(_n(14), ev.x, 0.9, ev.y, 0.0, PI, 6.0, 0.06, 0.45, 0.05, 3.0)
	_request_shake(0.3)


func _death_shatter(ev: SimEvent) -> void:
	_color_tape(ev.tape, FxColors.WHITE)
	for _k: int in _n(10):
		var ang := _rng.next() * TAU
		var sp := _rng.range_f(1.5, 4.0)
		var i := _emit(glow, FxSpritePool.SHAPE_SHARD, FxSpritePool.MODE_BILLBOARD, ev.x, _rng.range_f(0.4, 1.2), ev.y, _rng.range_f(0.1, 0.18), 0.05, _rng.range_f(0.6, 0.9), 0.9)
		_set_vel(glow, i, cos(ang) * sp, _rng.range_f(1.0, 3.5), sin(ang) * sp)
		glow.gravity[i] = 7.0
		glow.rot[i] = ang
		glow.rot_vel[i] = _rng.sym(9.0)
		glow.freeze[i] = 0.08
	# The self leaves a rising wisp in its colour: it becomes a ghost, it does not vanish (GHOST-05).
	var j := _emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x, 1.0, ev.y, 0.5, 0.25, 0.9, 0.7)
	_set_vel(glow, j, 0.0, 1.3, 0.0)
	glow.fade_in[j] = 0.1
	j = _emit(glow, FxSpritePool.SHAPE_DASHRING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.3, 1.6, 0.6, 0.6)
	glow.param[j] = 0.08
	_request_shake(0.35)


func _tape_letter(ev: SimEvent) -> void:
	if ev.tape < 0 or ev.tape >= OD.TAPE_COUNT:
		return
	var x := ev.x
	var z := ev.y
	if ev.type == SimEventType.TAPE_WRAP:
		# The self reappears at the start position, so its letter does too.
		x = env.level.start.x
		z = env.level.start.y
	_color_tape(ev.tape, FxColors.WHITE)
	_word(FxWords.W_TAPE_A + ev.tape, x, H_WORD + 0.2, z, 0.62, 0.8, 0.0, 0.5)


func _desync_tear(ev: SimEvent) -> void:
	_color_tape(ev.tape, FxColors.RECALL)
	for k: int in 3:
		# Translucent so the desynced projection underneath stays readable (UI-03).
		var i := _emit(glow, FxSpritePool.SHAPE_GLITCH, FxSpritePool.MODE_BILLBOARD, ev.x + _rng.sym(0.2), 0.6 + k * 0.35, ev.y + _rng.sym(0.2), _rng.range_f(0.55, 0.85), 0.8, 0.45, 0.42)
		glow.param[i] = _rng.next() * 100.0
	_screen_glitch(_c, 0.55)
	_word(FxWords.W_DESYNC, ev.x, H_WORD, ev.y, 0.36, 0.95, 0.0, 0.45)


func _resync_converge(ev: SimEvent) -> void:
	_color_tape(ev.tape, FxColors.WHITE)
	var cnt := _n(12)
	var lf := 0.32
	for k: int in cnt:
		var ang := (float(k) / cnt) * TAU + _rng.sym(0.2)
		var r := 1.4
		var i := _emit(glow, FxSpritePool.SHAPE_DOT, FxSpritePool.MODE_BILLBOARD, ev.x + cos(ang) * r, H_IMPACT + _rng.sym(0.3), ev.y + sin(ang) * r, 0.12, 0.08, lf, 0.95)
		_set_vel(glow, i, (-cos(ang) * r) / lf, 0.0, (-sin(ang) * r) / lf)
	var j := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 1.6, 0.2, lf, 0.7)
	glow.param[j] = 0.1
	# The convergence flash blooms as the motes arrive.
	_whiten(0.5)
	j = _emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 0.3, 1.5, 0.55, 0.9)
	glow.age[j] = -lf * 0.85
	glow.fade_in[j] = 0.05
	_color_tape(ev.tape, FxColors.WHITE)
	var w := _word(FxWords.W_RESYNC, ev.x, H_WORD, ev.y, 0.36, 0.95, 0.0, 0.6)
	if w >= 0:
		text.age[w] = -lf * 0.8


func _wrap_blink(ev: SimEvent) -> void:
	_color_tape(ev.tape, FxColors.WHITE)
	# Blink out where the tape ran out...
	var i := _emit(glow, FxSpritePool.SHAPE_DASHRING, FxSpritePool.MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 0.9, 0.2, 0.25, 0.7)
	glow.param[i] = 0.12
	_emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x, H_IMPACT, ev.y, 0.6, 0.1, 0.2, 0.5)
	# ...and cut back in at the start position (PLAY 'repeat': a hard cut, never a slide).
	var sx := env.level.start.x
	var sz := env.level.start.y
	_whiten(0.3)
	i = _emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, sx, H_IMPACT, sz, 1.0, 0.5, 0.22, 0.9)
	glow.fade_in[i] = 0.03
	i = _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, sx, H_FLOOR, sz, 0.2, 1.3, 0.4, 0.7)
	glow.param[i] = 0.1


func _turn_chevrons(ev: SimEvent) -> void:
	# Reverse: chevrons pointing back along the path the tape will now retrace.
	var back := _dir_of(ev) + PI
	var dx := cos(back)
	var dz := sin(back)
	_color_tape(ev.tape, FxColors.WHITE)
	for k: int in 3:
		var d := 0.35 + k * 0.38
		var i := _emit(glow, FxSpritePool.SHAPE_CHEVRON, FxSpritePool.MODE_FLOOR, ev.x + dx * d, H_FLOOR + 0.01, ev.y + dz * d, 0.32, 0.3, 0.45, 0.85)
		glow.rot[i] = back
		glow.age[i] = -0.07 * k
		_set_vel(glow, i, dx * 0.8, 0.0, dz * 0.8)


func _end_stop(ev: SimEvent) -> void:
	_color_tape(ev.tape, FxColors.WHITE)
	var i := _emit(glow, FxSpritePool.SHAPE_STOP, FxSpritePool.MODE_BILLBOARD, ev.x, 1.35, ev.y, 0.4, 0.34, 0.9, 0.85)
	glow.fade_pow[i] = 0.5
	var j := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.9, 0.5, 0.35, 0.5)
	glow.param[j] = 0.1


func _telegraph_ring(ev: SimEvent) -> void:
	# Complements the actor layer's telegraph, never replaces it: a charging ring that tightens onto
	# the enemy plus a faint wedge toward the attack direction.
	_c = env.palette.hazard
	var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 1.5, 0.6, 0.35, 0.5)
	glow.param[i] = 0.08
	glow.fade_in[i] = 0.08
	if ev.has_dir:
		i = _emit(glow, FxSpritePool.SHAPE_ARC, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 1.0, 1.1, 0.35, 0.3)
		glow.param[i] = 0.6
		glow.rot[i] = ev.dir


func _enemy_slash(ev: SimEvent) -> void:
	_c = FxColors.ENEMY
	var a := _dir_of(ev)
	var i := _emit(glow, FxSpritePool.SHAPE_ARC, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR + 0.02, ev.y, 1.0, 1.25, 0.18, 0.65)
	glow.param[i] = 0.9
	glow.rot[i] = a
	_whiten(0.3)
	_sparks(_n(3), ev.x + cos(a) * 0.6, H_IMPACT, ev.y + sin(a) * 0.6, a, 0.5, 6.0, 0.05, 0.15, 0.0, 0.0)


func _stagger_stars(ev: SimEvent) -> void:
	_c = env.palette.hazard
	for k: int in 3:
		var ang := (k / 3.0) * TAU
		var i := _emit(glow, FxSpritePool.SHAPE_STAR, FxSpritePool.MODE_BILLBOARD, ev.x + cos(ang) * 0.35, 1.45, ev.y + sin(ang) * 0.35, 0.18, 0.12, 0.6, 0.85)
		_set_vel(glow, i, -sin(ang) * 1.4, 0.2, cos(ang) * 1.4)
		glow.drag[i] = 1.5
		glow.rot_vel[i] = 6.0


func _boss_shock(ev: SimEvent) -> void:
	var pal := env.palette
	_c = pal.neon_c
	var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 1.0, 5.5, 0.75, 0.85)
	glow.param[i] = 0.05
	i = _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.6, 3.5, 0.6, 0.6)
	glow.param[i] = 0.1
	glow.age[i] = -0.1
	_whiten(0.4)
	_emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x, 1.2, ev.y, 1.4, 2.6, 0.4, 0.8)
	_flash(pal.neon_c, 0.12)
	_c = pal.neon_c
	_whiten(0.2)
	_word(FxWords.W_PHASE, ev.x, H_WORD + 0.9, ev.y, 0.5, 1.2, 0.1, 0.8)
	_request_shake(0.75)


func _boss_recall_tell(ev: SimEvent) -> void:
	# "It remembers": unmistakable and different from every other tell - rewind chevrons collapse
	# onto the boss, an eye opens above it, the screen tears in the remembered tape's colour.
	var col := FxColors.tape(ev.tape, FxColors.RECALL)
	_c = col
	var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 3.2, 0.9, 0.55, 0.75)
	glow.param[i] = 0.07
	var n := 6
	for k: int in n:
		var ang := (float(k) / n) * TAU
		var r := 2.6
		i = _emit(glow, FxSpritePool.SHAPE_CHEVRON, FxSpritePool.MODE_FLOOR, ev.x + cos(ang) * r, H_FLOOR + 0.01, ev.y + sin(ang) * r, 0.34, 0.26, 0.5, 0.85)
		glow.rot[i] = ang + PI
		_set_vel(glow, i, -cos(ang) * 3.4, 0.0, -sin(ang) * 3.4)
		glow.age[i] = -0.03 * k
	i = _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_BILLBOARD, ev.x, 2.2, ev.y, 0.2, 0.6, 0.85, 0.95)
	glow.param[i] = 0.22
	glow.fade_pow[i] = 0.5
	_whiten(0.5)
	i = _emit(glow, FxSpritePool.SHAPE_DOT, FxSpritePool.MODE_BILLBOARD, ev.x, 2.2, ev.y, 0.18, 0.22, 0.85, 1.0)
	glow.fade_pow[i] = 0.5
	_c = col
	for k: int in 2:
		i = _emit(glow, FxSpritePool.SHAPE_GLITCH, FxSpritePool.MODE_BILLBOARD, ev.x, 1.7 + k * 0.5, ev.y, 1.0, 1.1, 0.5, 0.38)
		glow.param[i] = _rng.next() * 100.0
	_screen_glitch(col, 0.7)
	_flash(col, 0.08)
	_c = col
	_whiten(0.15)
	_word(FxWords.W_REMEMBERS, ev.x, 2.75, ev.y, 0.38, 1.3, 0.06, 0.5)
	if ev.tape >= 0 and ev.tape < OD.TAPE_COUNT:
		_word(FxWords.W_TAPE_A + ev.tape, ev.x + 0.9, 2.25, ev.y, 0.4, 1.3, 0.06, 0.5)
	_request_shake(0.25)


func _objective_pulse(ev: SimEvent) -> void:
	var pal := env.palette
	_c = pal.hazard
	_whiten(0.3)
	var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.5, 3.2, 0.8, 0.8)
	glow.param[i] = 0.06
	_emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x, 1.0, ev.y, 0.8, 1.6, 0.4, 0.8)
	_c = pal.hazard
	_word(FxWords.W_CLEAR, ev.x, H_WORD + 0.5, ev.y, 0.7 if mode == ViewMode.CINEMATIC else 0.5, 1.6, 0.12, 0.9)


func _step_dust(ev: SimEvent) -> void:
	_c = FxColors.DUST
	var i := _emit(ink, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, ev.x, 0.06, ev.y, 0.12, 0.32, 0.35, 0.18)
	_set_vel(ink, i, _rng.sym(0.3), 0.25, _rng.sym(0.3))


func _impact_dust(ev: SimEvent) -> void:
	_c = FxColors.DUST
	var i := _emit(ink, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.3, 1.3, 0.45, 0.3)
	ink.param[i] = 0.2


func _ink_splash(ev: SimEvent) -> void:
	# Impact freeze-frame: an ink splash painted on the floor UNDER the impact (never over the actors),
	# held still for a beat-fraction, then fading. Visual only: gameplay time never pauses.
	var r := _ratio(ev)
	var s := 0.55 + 0.25 * sqrt(minf(6.0, r))
	_c = env.palette.ink
	var i := _emit(ink, FxSpritePool.SHAPE_INK, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR - 0.005, ev.y, s * 0.6, s, 1.3, 0.6)
	ink.param[i] = _rng.next() * 50.0
	ink.rot[i] = _rng.next() * TAU
	ink.freeze[i] = 0.09
	ink.fade_pow[i] = 3.0
	var a := _dir_of(ev)
	for _k: int in _n(4):
		var ang := a + _rng.sym(0.7)
		var d := s * _rng.range_f(0.9, 1.6)
		i = _emit(ink, FxSpritePool.SHAPE_INK, FxSpritePool.MODE_FLOOR, ev.x + cos(ang) * d, H_FLOOR - 0.004, ev.y + sin(ang) * d, 0.08, 0.14, 1.2, 0.6)
		ink.param[i] = _rng.next() * 50.0
		ink.freeze[i] = 0.09
		ink.fade_pow[i] = 3.0
	_color_tape(ev.tape, env.palette.hazard)
	i = _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR + 0.004, ev.y, s * 0.8, s * 1.3, 0.5, 0.5)
	glow.param[i] = 0.05
	glow.freeze[i] = 0.09


func _speed_line_burst(ev: SimEvent) -> void:
	var tier := _tier(ev)
	var amt := (0.25 + 0.15 * tier) if ev.type == SimEventType.HIT else 0.85
	# Small hits don't get a radial burst; it would make every tap look like a finisher.
	if amt < 0.5:
		return
	if amt >= screen.burst_amt * 0.8:
		screen.burst = Vector3(ev.x, H_IMPACT, ev.y)
		screen.burst_amt = maxf(screen.burst_amt, minf(1.0, amt))


func _cine_echo(ev: SimEvent) -> void:
	_color_tape(ev.tape, FxColors.WHITE)
	var i := _emit(glow, FxSpritePool.SHAPE_DASHRING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR, ev.y, 0.5, 2.4, 0.6, 0.6)
	glow.param[i] = 0.06
	glow.rot_vel[i] = -2.0 if ev.type == SimEventType.DESYNC else 2.0


func _cine_focus(ev: SimEvent) -> void:
	var w := 0.4
	match ev.type:
		SimEventType.OBJECTIVE:
			w = 1.0
		SimEventType.BOSS_PHASE:
			w = 0.8
		SimEventType.BOSS_RECALL:
			w = 0.7
		SimEventType.KILL:
			w = 0.55
		SimEventType.RESYNC, SimEventType.CORE, SimEventType.BREAK:
			w = 0.5
		SimEventType.SELF_DEATH:
			w = 0.45
	if w >= focus_w * 0.8:
		focus_x = ev.x
		focus_y = ev.y
		focus_w = maxf(w, focus_w * 0.8)


## Trap state changes (docs/TRAPS.md "Events for audio and fx"; the machine itself animates from its
## snapshot in world/world_traps.gd, this is the punctuation): telegraphs tighten an orange ring onto
## the hazard, strokes hit with dust, sparks and a kick, belts throw chevrons the new way, beams and
## relays ping in their own cool / signal colours. Never a cassette colour.
func _trap_fx(ev: SimEvent) -> void:
	var d := ev.detail
	var kind := d.get_slice(":", 0)
	var what := d.get_slice(":", 1) if d.contains(":") else ""
	var x := ev.x
	var z := ev.y
	var warn := WorldTraps.WARN_COLOR
	match what:
		"warn":
			_c = warn
			var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, x, H_FLOOR + 0.01, z, 1.6, 0.5, 0.45, 0.75)
			glow.param[i] = 0.1
			glow.fade_in[i] = 0.06
			i = _emit(glow, FxSpritePool.SHAPE_DASHRING, FxSpritePool.MODE_FLOOR, x, H_FLOOR + 0.012, z, 1.1, 0.8, 0.5, 0.5)
			glow.param[i] = 0.08
			glow.rot_vel[i] = 3.0
			if ev.has_dir:
				i = _emit(glow, FxSpritePool.SHAPE_CHEVRON, FxSpritePool.MODE_FLOOR, x + cos(ev.dir) * 0.6, H_FLOOR + 0.014, z + sin(ev.dir) * 0.6, 0.34, 0.3, 0.45, 0.8)
				glow.rot[i] = ev.dir
		"up", "slam", "fire", "on":
			if kind == "sensor":
				_c = WorldTraps.SENSOR_COLOR
				var i := _emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, x, 0.35, z, 0.35, 0.8, 0.22, 0.7)
				glow.fade_pow[i] = 1.5
				return
			if kind == "relay" or kind == "magnet" or kind == "dart" and what == "on" or kind == "conveyor":
				_c = WorldTraps.MAGNET_COLOR if kind == "magnet" else (env.palette.neon_a if kind == "relay" else warn)
				var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, x, H_FLOOR, z, 0.3 if kind != "magnet" else 2.4, 1.2 if kind != "magnet" else 0.4, 0.4, 0.6)
				glow.param[i] = 0.1
				if kind == "conveyor":
					_conveyor_chevrons(ev)
				return
			if kind == "flame":
				_c = WorldTraps.FLAME_COLOR
				_whiten(0.2)
				var a := _dir_of(ev)
				_sparks(_n(8), x + cos(a) * 0.6, 0.3, z + sin(a) * 0.6, a, 0.35, 6.5, 0.07, 0.35, 0.0, -1.0)
				var i := _emit(glow, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, x + cos(a) * 0.7, 0.3, z + sin(a) * 0.7, 0.4, 1.0, 0.3, 0.8)
				glow.fade_pow[i] = 1.2
				_request_shake(0.08)
				return
			if kind == "dart":
				_muzzle(ev, warn, 0.3)
				return
			# A stroke: spikes rising, the crusher slamming, the bumper firing.
			var heavy := kind == "crusher"
			_c = FxColors.DUST
			for _k: int in _n(6 if heavy else 3):
				var j := _emit(ink, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, x + _rng.sym(0.5), 0.12, z + _rng.sym(0.5), 0.25, 0.8, 0.55, 0.28)
				_set_vel(ink, j, _rng.sym(1.2), 0.6, _rng.sym(1.2))
				ink.drag[j] = 2.0
			_c = warn
			_whiten(0.35)
			_sparks(_n(8 if heavy else 4), x, 0.25 if not heavy else 0.6, z, _dir_of(ev), PI, 4.5, 0.06, 0.25, 0.04 if heavy else 0.0, 8.0)
			var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, x, H_FLOOR, z, 0.4, 1.6 if heavy else 1.1, 0.35, 0.7)
			glow.param[i] = 0.1
			if heavy:
				_debris_puff(ev)
				_request_shake(0.18 + 0.08 * minf(3.0, ev.power if ev.has_power else 0.0))
			elif kind == "bumper":
				_request_shake(0.1)
		"down", "retract", "open", "off", "hold", "forward", "reverse", "armed":
			if kind == "conveyor":
				_conveyor_chevrons(ev)
				return
			if what == "armed":
				_c = env.palette.neon_a
				var i := _emit(glow, FxSpritePool.SHAPE_DASHRING, FxSpritePool.MODE_BILLBOARD, x, 1.0, z, 0.25, 0.6, 0.4, 0.8)
				glow.param[i] = 0.14
				return
			if what == "hold":
				_c = warn
				var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, x, H_FLOOR, z, 1.0, 0.6, 0.3, 0.6)
				glow.param[i] = 0.1
				return
			# Settling: a soft puff (spikes dropping, crusher back home, flame out, a machine off).
			_c = FxColors.DUST if kind != "flame" else FxColors.CLANG
			for _k: int in _n(3):
				var j := _emit(ink, FxSpritePool.SHAPE_GLOW, FxSpritePool.MODE_BILLBOARD, x + _rng.sym(0.4), 0.2 + _rng.next() * 0.3, z + _rng.sym(0.4), 0.2, 0.6, 0.6, 0.2)
				_set_vel(ink, j, _rng.sym(0.4), 0.5, _rng.sym(0.4))
		_:
			_c = warn
			var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, x, H_FLOOR, z, 0.3, 1.0, 0.35, 0.5)
			glow.param[i] = 0.1


func _conveyor_chevrons(ev: SimEvent) -> void:
	var a := ev.dir if ev.has_dir and is_finite(ev.dir) else 0.0
	_c = WorldTraps.WARN_COLOR
	_whiten(0.3)
	for k: int in 3:
		var dd := -0.4 + k * 0.4
		var i := _emit(glow, FxSpritePool.SHAPE_CHEVRON, FxSpritePool.MODE_FLOOR, ev.x + cos(a) * dd, H_FLOOR + 0.012, ev.y + sin(a) * dd, 0.32, 0.3, 0.5, 0.85)
		glow.rot[i] = a
		glow.age[i] = -0.06 * k
		_set_vel(glow, i, cos(a) * 1.2, 0.0, sin(a) * 1.2)


func _debris_puff(ev: SimEvent) -> void:
	var pal := env.palette
	for k: int in _n(6):
		_c = pal.wall_top if k % 2 == 0 else pal.wall
		var ang := _rng.next() * TAU
		var sp := _rng.range_f(1.5, 3.5)
		var i := _emit(ink, FxSpritePool.SHAPE_DEBRIS, FxSpritePool.MODE_BILLBOARD, ev.x + _rng.sym(0.3), 0.3, ev.y + _rng.sym(0.3), _rng.range_f(0.08, 0.16), 0.08, _rng.range_f(0.6, 0.9), 1.0)
		_set_vel(ink, i, cos(ang) * sp, _rng.range_f(1.5, 3.0), sin(ang) * sp)
		ink.gravity[i] = 14.0
		ink.floor_y[i] = 0.06
		ink.rot_vel[i] = _rng.sym(9.0)


## Environment kills / hits (detail 'spikes' | 'crusher' | 'flame' | 'dart', no tape): the trap's own
## impact colour, not a cassette colour (docs/TRAPS.md "Actor feedback").
static func _trap_hit(ev: SimEvent) -> bool:
	return ev.tape < 0 and (ev.detail == "spikes" or ev.detail == "crusher" or ev.detail == "flame" or ev.detail == "dart")


func _finale_burst(ev: SimEvent) -> void:
	# Four rings in the four cassette colours: the voices resolving together.
	for t: int in 4:
		_c = OD.tape_color(t)
		var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, ev.x, H_FLOOR + 0.004 * t, ev.y, 0.5, 4.0 + t * 0.9, 1.0, 0.8)
		glow.param[i] = 0.05
		glow.age[i] = -0.09 * t
		_whiten(0.25)
		_sparks(_n(10), ev.x, 1.0, ev.y, (t / 4.0) * TAU, 1.2, 8.0, 0.07, 0.7, 0.06, 5.0)
	_c = env.palette.ink
	for _k: int in _n(14):
		var ang := _rng.next() * TAU
		var sp := _rng.range_f(3.0, 7.0)
		var i := _emit(ink, FxSpritePool.SHAPE_SHARD, FxSpritePool.MODE_BILLBOARD, ev.x, 1.0, ev.y, _rng.range_f(0.12, 0.24), 0.08, _rng.range_f(0.8, 1.2), 0.85)
		_set_vel(ink, i, cos(ang) * sp, _rng.range_f(2.0, 6.0), sin(ang) * sp)
		ink.gravity[i] = 10.0
		ink.floor_y[i] = 0.05
		ink.rot_vel[i] = _rng.sym(12.0)
	_flash(Color.WHITE, 0.22)
	screen.burst = Vector3(ev.x, 1.0, ev.y)
	screen.burst_amt = 1.0
	_request_shake(0.6)


# ───────────────────────────── screen helpers ─────────────────────────────

func _flash_limits() -> Dictionary:
	var k := 1 if env.reduce_flashing else 0
	if k != _limits_reduced:
		_limits_reduced = k
		_limits = AccessKit.flash_limits(env.reduce_flashing)
	return _limits


## Full-screen flash, within the photosensitivity budget (docs/ACCESSIBILITY.md): alpha clamped to
## the mode's limit, a new flash refused within the minimum gap of the last one unless it is clearly
## stronger (so four selves landing hits on consecutive beats never add up to a strobe), and never a
## large saturated-red flash.
func _flash(col: Color, a: float) -> void:
	var lim := _flash_limits()
	var aa := minf(a * _alpha_k, float(lim.get("fullscreen_flash_max_alpha", 0.25)))
	if aa <= 0.0:
		return
	var gap := float(lim.get("min_seconds_between_fullscreen_flashes", 0.5))
	if env.reduce_flashing:
		gap = maxf(gap, float(lim.get("fullscreen_change_min_fade_seconds", 0.4)))
	if screen.time - _last_flash_t < gap and aa < _last_flash_peak + 0.1:
		return
	var sum := col.r + col.g + col.b
	if sum > 0.0 and col.r / sum >= 0.8:
		col = col.lerp(Color.WHITE, 0.45)
	if aa >= screen.flash_a:
		screen.flash = col
		screen.flash_a = aa
		_last_flash_t = screen.time
		_last_flash_peak = aa


func _screen_glitch(col: Color, a: float) -> void:
	var k := float(_flash_limits().get("chromatic_split_max", 1.0))
	var aa := a * _alpha_k * k
	if aa >= screen.glitch:
		screen.glitch_color = col
		screen.glitch = aa
	# A short chromatic split rides along with the tear (ctx.post; no-op on low quality).
	screen.chromatic = maxf(screen.chromatic, aa * 0.6)


## Cinematic director cues (docs/CINEMATIC.md "Integration" step 6): the chord-change palette flash
## (instead of this director's own detection, so a flash never lands over another emphasis), the
## bar sweep, and impact accents (speed lines and an ink ring at the cue's point in its tape colour).
func _play_cues(cf: CinemaFrame) -> void:
	var pal := env.palette
	for cue: CinemaTypes.Cue in cf.cues:
		match cue.kind:
			CinemaGrammar.CUE_CHORD_FLASH:
				var idx := ((maxi(0, cue.chord) % 4) + 4) % 4
				var col: Color = [pal.neon_a, pal.neon_b, pal.neon_c, pal.hazard][idx]
				_flash(col, 0.1 * cue.strength)
				chord_flashes += 1
			CinemaGrammar.CUE_BAR_SWEEP:
				screen.sweep_a = maxf(screen.sweep_a, 0.05 + 0.04 * cue.strength)
			CinemaGrammar.CUE_IMPACT:
				_tag = TAG_CINE_CONTINUOUS
				_color_tape(cue.tape, pal.hazard)
				var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, cue.point.x, H_FLOOR + 0.006, cue.point.y, 0.4, 2.0 + cue.strength, 0.5, 0.55)
				glow.param[i] = 0.06
				var amt := 0.5 + 0.4 * cue.strength
				if amt >= screen.burst_amt * 0.8:
					screen.burst = Vector3(cue.point.x, H_IMPACT, cue.point.y)
					screen.burst_amt = maxf(screen.burst_amt, minf(1.0, amt))


func _decay_screen(dt: float, letterbox_target: float = -1.0) -> void:
	screen.flash_a *= exp(-dt * 3.5)
	screen.burst_amt *= exp(-dt * 3.2)
	screen.glitch *= exp(-dt * 4.5)
	screen.chromatic *= exp(-dt * 6.0)
	if screen.flash_a < 0.002:
		screen.flash_a = 0.0
	if screen.burst_amt < 0.01:
		screen.burst_amt = 0.0
	if screen.glitch < 0.01:
		screen.glitch = 0.0
	if screen.chromatic < 0.01:
		screen.chromatic = 0.0
	var target := _prof.letterbox
	if letterbox_target >= 0.0:
		# The director's letterbox is already eased (and deepens for climax shots): follow it closely.
		target = letterbox_target
		screen.letterbox += (target - screen.letterbox) * (1.0 - exp(-dt * 12.0))
	# Letterbox eases in over about a second (and back out when the cinematic ends).
	screen.letterbox += (target - screen.letterbox) * (1.0 - exp(-dt * 2.5))
	if absf(screen.letterbox - target) < 1e-4:
		screen.letterbox = target


# ───────────────────────────── continuous treatments ─────────────────────────────

func _find_active(frame: RenderFrame) -> ActorSnap:
	var actors := frame.snap.actors
	if frame.active >= 0:
		for a: ActorSnap in actors:
			if a.tape == frame.active:
				return a
	for a: ActorSnap in actors:
		if a.live:
			return a
	return null


func _update_world_speed(frame: RenderFrame, prof: FxCatalog.ModeProfile, wr: float, fx_rate: float, dt: float) -> void:
	var target := prof.world_speed * clampf(log(wr) / log(2.0) / 2.0, -1.0, 1.0)
	world_speed += (target - world_speed) * (1.0 - exp(-dt * 4.0))
	if absf(world_speed) < 1e-4:
		world_speed = 0.0
	var ws := world_speed
	var amt := absf(ws)
	screen.tint = FxColors.SLOW_WORLD if ws < 0.0 else FxColors.FAST_WORLD
	screen.tint_a = amt * 0.07
	screen.speed = amt
	screen.speed_sign = -1.0 if ws < 0.0 else (1.0 if ws > 0.0 else 0.0)

	var mb := floorf(frame.snap.beat)
	var prev_mb := _last_master_beat
	_last_master_beat = mb
	if amt < 0.08 or not prof.events or is_nan(prev_mb) or mb <= prev_mb or mb - prev_mb > 4.0:
		return

	# Time-ripple: one floor ring per MASTER beat from the active self, expanding over one master beat
	# of wall time - slow, lazy rings in a slowed world, quick ones in a sped-up world.
	var actor := _find_active(frame)
	if actor != null:
		_tag = TAG_WORLD_SPEED
		_c = FxColors.SLOW_WORLD if ws < 0.0 else FxColors.FAST_WORLD
		var beat_wall := 60.0 / maxf(1.0, env.level.bpm) / wr
		var i := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, actor.x, H_FLOOR - 0.01, actor.y, 0.5, 3.2, beat_wall * fx_rate, 0.12 + 0.18 * amt)
		glow.param[i] = 0.04
		glow.fade_pow[i] = 1.5

	# Motion smear: when the world runs fast around a slow tape, moving enemies leave faint streaks.
	if ws > 0.15:
		_smear_timer += dt
		if _smear_timer >= 0.05:
			_smear_timer = 0.0
			_smear(frame, ws)


func _smear(frame: RenderFrame, ws: float) -> void:
	if frame.prev == null:
		return
	var en := frame.snap.enemies
	var pe := frame.prev.enemies
	_c = FxColors.FAST_WORLD
	_tag = TAG_WORLD_SPEED
	var lim := mini(16, en.size())
	for i: int in lim:
		var e := en[i]
		if not e.alive:
			continue
		var p: EnemySnap = pe[i] if (i < pe.size() and pe[i].id == e.id) else null
		if p == null:
			continue
		var dx := e.x - p.x
		var dz := e.y - p.y
		var d := Vector2(dx, dz).length()
		if d < 0.002 or d > 2.0:
			continue
		var k := _emit(glow, FxSpritePool.SHAPE_STREAK, FxSpritePool.MODE_STREAK, e.x - (dx / d) * 0.35, 0.6, e.y - (dz / d) * 0.35, 0.18, 0.1, 0.2, 0.22 * ws)
		_set_dir(glow, k, dx / d, 0.0, dz / d, 4.0)


func _update_music_flourishes(frame: RenderFrame, dt: float, fx_rate: float) -> void:
	var m := frame.music
	if m == null:
		return
	var cine := frame.mode == ViewMode.CINEMATIC
	var chord := float(m.chord)
	var prev_chord := _last_chord
	_last_chord = chord
	var beat := floorf(m.beat)
	var prev_beat := _last_music_beat
	_last_music_beat = beat

	if cine:
		# Bar-synced light sweep across the frame.
		screen.sweep_pos = m.beat / 4.0 - floorf(m.beat / 4.0)
		screen.sweep_a = 0.03 + 0.05 * m.bar_pulse
	else:
		screen.sweep_a *= exp(-dt * 6.0)
		if screen.sweep_a < 1e-4:
			screen.sweep_a = 0.0
	if not cine:
		return

	# Chord-change palette flash, drawn from the level theme's own neon / accent colours (with a
	# director plan the flash comes from its chordFlash cues instead; _play_cues).
	if not _directed and not is_nan(prev_chord) and chord != prev_chord:
		var pal := env.palette
		var idx := ((roundi(chord) % 4) + 4) % 4
		var col: Color = [pal.neon_a, pal.neon_b, pal.neon_c, pal.hazard][idx]
		_flash(col, 0.1)
		chord_flashes += 1

	# Beat-synced floor ripples under every living self, in its tape colour.
	if not is_nan(prev_beat) and beat > prev_beat and beat - prev_beat <= 2.0:
		var bar := (int(beat) % 4) == 0
		_tag = TAG_CINE_CONTINUOUS
		for a: ActorSnap in frame.snap.actors:
			if a.life != OD.LifeState.ALIVE or a.tape < 0 or a.tape >= OD.TAPE_COUNT:
				continue
			_c = OD.tape_color(a.tape)
			var lv := m.levels[a.tape] if a.tape < m.levels.size() else 0.0
			var k := _emit(glow, FxSpritePool.SHAPE_RING, FxSpritePool.MODE_FLOOR, a.x, H_FLOOR - 0.008, a.y, 0.3, 1.9 if bar else 1.1, 0.5 * fx_rate, 0.22 + 0.2 * lv + (0.15 if bar else 0.0))
			glow.param[k] = 0.06


func _update_ribbons(frame: RenderFrame, dt: float) -> void:
	var rb := ribbons
	var cine := frame.mode == ViewMode.CINEMATIC
	var prev: Array[ActorSnap] = frame.prev.actors if frame.prev != null else frame.snap.actors
	rb.present.fill(0)
	rb.sample_timer += dt
	var sample := rb.sample_timer >= 1.0 / 30.0
	if sample:
		rb.sample_timer = 0.0
	for a: ActorSnap in frame.snap.actors:
		var t := a.tape
		if t < 0 or t > 3:
			continue
		rb.present[t] = 1
		var x := a.x
		var z := a.y
		for p: ActorSnap in prev:
			if p.tape != t:
				continue
			if absf(p.x - a.x) + absf(p.y - a.y) < 3.0:
				x = p.x + (a.x - p.x) * frame.alpha
				z = p.y + (a.y - p.y) * frame.alpha
			break
		rb.state[t] = 1 if a.life != OD.LifeState.ALIVE else (0 if a.synced else 2)
		var target := (1.0 if a.life == OD.LifeState.ALIVE else 0.35) if cine else 0.0
		rb.alpha[t] += (target - rb.alpha[t]) * (1.0 - exp(-dt * 3.0))
		if not cine:
			if rb.alpha[t] < 0.01:
				rb.reset(t)
			continue
		# A 'repeat' cut teleports the self: break the ribbon instead of drawing a line across the room.
		var lst := rb.last[t]
		if rb.count[t] > 0 and absf(x - lst.x) + absf(z - lst.y) > 2.5:
			rb.reset(t)
		if sample or rb.count[t] == 0:
			rb.push(t, Vector3(x, 0.045, z))
		else:
			# Keep the newest point glued to the self between samples.
			var o := rb.point_index(t, rb.count[t] - 1)
			rb.pts[o] = Vector3(x, rb.pts[o].y, z)
		rb.last[t] = Vector2(x, z)
	for t: int in 4:
		if rb.present[t] == 0:
			rb.alpha[t] *= exp(-dt * 4.0)
			if rb.alpha[t] < 0.01:
				rb.reset(t)


func _update_focus(frame: RenderFrame, dt: float) -> void:
	if frame.mode != ViewMode.CINEMATIC:
		focus_w = 0.0
		return
	focus_w *= exp(-dt * 0.9)
	# The boss is always worth a glance when nothing louder is happening.
	for e: EnemySnap in frame.snap.enemies:
		if e.type == EnemyType.BOSS and e.alive and focus_w < 0.25:
			focus_x = e.x
			focus_y = e.y
			focus_w = 0.25
			break
	if focus_w < 0.02:
		focus_w = 0.0
