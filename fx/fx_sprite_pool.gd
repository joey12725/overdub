class_name FxSpritePool
extends RefCounted
## Fixed-capacity particle pool (port of prototype/src/render/fx/pool.ts SpritePool).
##
## Struct of packed arrays, so it is testable headless and the steady state allocates nothing:
## spawning takes a slot from a free stack, and when the pool is full the slot closest to the end of
## its life is recycled instead of growing. FxSpriteRenderer uploads the live sprites into one
## MultiMesh every frame (write_instances packs them in the MultiMesh buffer layout).

## Floor height value meaning "no floor bounce".
const NO_FLOOR := -1.0e9
## Floats per instance in the MultiMesh buffer (3x4 transform rows + colour).
const STRIDE := 16

# Procedural shapes, drawn analytically by fx/shaders/fx_sprite.gdshader.
const SHAPE_GLOW := 0
const SHAPE_SPARK := 1
const SHAPE_STREAK := 2
const SHAPE_RING := 3
const SHAPE_DEBRIS := 4
const SHAPE_CHEVRON := 5
const SHAPE_INK := 6
const SHAPE_ARC := 7
const SHAPE_CROSS := 8
const SHAPE_DASHRING := 9
const SHAPE_GLITCH := 10
const SHAPE_STAR := 11
const SHAPE_STOP := 12
const SHAPE_SHARD := 13
const SHAPE_DOT := 14

## Camera-facing quad.
const MODE_BILLBOARD := 0
## Lies flat on the floor (XZ plane), rotated by `rot` (sim heading).
const MODE_FLOOR := 1
## Camera-facing quad stretched along a world direction (`dir`, length factor `stretch`).
const MODE_STREAK := 2

var capacity: int
var pos: PackedVector3Array
var vel: PackedVector3Array
## World direction for streaks.
var dir: PackedVector3Array
## Streak length factor.
var stretch: PackedFloat32Array
var color: PackedColorArray
var alpha: PackedFloat32Array
var size0: PackedFloat32Array
var size1: PackedFloat32Array
var life: PackedFloat32Array
var age: PackedFloat32Array
## Seconds the sprite stays frozen at its first frame (the effect's own hit-stop; never gameplay).
var freeze: PackedFloat32Array
var gravity: PackedFloat32Array
## Exponential velocity damping per second.
var drag: PackedFloat32Array
var rot: PackedFloat32Array
var rot_vel: PackedFloat32Array
## Shape parameter (ring thickness, arc half-width, ink seed...).
var param: PackedFloat32Array
var fade_in: PackedFloat32Array
## Exponent of the fade-out curve: < 1 holds longer, > 1 fades sooner.
var fade_pow: PackedFloat32Array
## Floor height the sprite bounces on when it has gravity (debris). NO_FLOOR disables bouncing.
var floor_y: PackedFloat32Array
var shape: PackedByteArray
var mode: PackedByteArray
## Which effect spawned the sprite (index into FxCatalog.EFFECT_IDS, or a FxDirector.TAG_*).
var tag: PackedByteArray
var alive: PackedByteArray

var _free: PackedInt32Array
var _free_top: int = 0
var _live: int = 0
## One past the highest slot handed out since clear(): loops stop there.
var _hi: int = 0


func _init(p_capacity: int) -> void:
	capacity = p_capacity
	pos.resize(capacity)
	vel.resize(capacity)
	dir.resize(capacity)
	stretch.resize(capacity)
	color.resize(capacity)
	alpha.resize(capacity)
	size0.resize(capacity)
	size1.resize(capacity)
	life.resize(capacity)
	age.resize(capacity)
	freeze.resize(capacity)
	gravity.resize(capacity)
	drag.resize(capacity)
	rot.resize(capacity)
	rot_vel.resize(capacity)
	param.resize(capacity)
	fade_in.resize(capacity)
	fade_pow.resize(capacity)
	floor_y.resize(capacity)
	shape.resize(capacity)
	mode.resize(capacity)
	tag.resize(capacity)
	alive.resize(capacity)
	_free.resize(capacity)
	clear()


## Number of live sprites.
func count() -> int:
	return _live


func clear() -> void:
	alive.fill(0)
	_live = 0
	_hi = 0
	# Pop order 0, 1, 2... so slot reuse is predictable.
	for i: int in capacity:
		_free[i] = capacity - 1 - i
	_free_top = capacity


## Recycle the alive slot with the highest age/life fraction (the one closest to vanishing).
func _steal() -> int:
	var best := 0
	var best_t := -INF
	for i: int in capacity:
		if alive[i] == 0:
			return i
		var t := age[i] / (life[i] if life[i] > 1e-6 else 1e-6)
		if t > best_t:
			best_t = t
			best = i
	return best


## Take a slot (recycling the oldest when full) and reset it to defaults.
func spawn(p_tag: int) -> int:
	var i: int
	if _free_top > 0:
		_free_top -= 1
		i = _free[_free_top]
		_live += 1
	else:
		i = _steal()
	if i + 1 > _hi:
		_hi = i + 1
	alive[i] = 1
	tag[i] = p_tag
	pos[i] = Vector3.ZERO
	vel[i] = Vector3.ZERO
	dir[i] = Vector3.RIGHT
	stretch[i] = 1.0
	color[i] = Color.WHITE
	alpha[i] = 1.0
	size0[i] = 0.3
	size1[i] = 0.3
	life[i] = 0.5
	age[i] = 0.0
	freeze[i] = 0.0
	gravity[i] = 0.0
	drag[i] = 0.0
	rot[i] = 0.0
	rot_vel[i] = 0.0
	param[i] = 0.0
	fade_in[i] = 0.0
	fade_pow[i] = 1.0
	floor_y[i] = NO_FLOOR
	shape[i] = 0
	mode[i] = 0
	return i


func kill(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	_free[_free_top] = i
	_free_top += 1
	_live -= 1


## Advance every live sprite by dt seconds of effect time.
func update(dt: float) -> void:
	if _live == 0:
		return
	for i: int in _hi:
		if alive[i] == 0:
			continue
		if freeze[i] > 0.0:
			freeze[i] -= dt
			continue
		var a := age[i] + dt
		if a >= life[i]:
			kill(i)
			continue
		age[i] = a
		# Negative age is a spawn delay (staggered chevrons, finale rings): hold still until born.
		if a < 0.0:
			continue
		var v := vel[i]
		if drag[i] > 0.0:
			v *= exp(-drag[i] * dt)
		v.y -= gravity[i] * dt
		var p := pos[i] + v * dt
		var fy := floor_y[i]
		if fy > NO_FLOOR and p.y < fy:
			p.y = fy
			v = Vector3(v.x * 0.6, -v.y * 0.35, v.z * 0.6)
			rot_vel[i] *= 0.5
		vel[i] = v
		pos[i] = p
		rot[i] += rot_vel[i] * dt


## Pack live sprites into a MultiMesh buffer (STRIDE floats each; the buffer must hold capacity).
## Layout (rows of the 3x4 instance transform, read back as MODEL_MATRIX columns in the shader):
##   row0: dir.x, stretch, rot,  pos.x      row1: dir.y, size, t, pos.y
##   row2: dir.z, param,   shape + 32 * mode, pos.z      then colour r, g, b, a.
## Returns the instance count.
func write_instances(buf: PackedFloat32Array) -> int:
	var n := 0
	for i: int in _hi:
		if alive[i] == 0 or age[i] < 0.0:
			continue
		var lf := life[i] if life[i] > 1e-6 else 1e-6
		var t := minf(1.0, age[i] / lf)
		var frozen := freeze[i] > 0.0
		var fin := 1.0 if (frozen or fade_in[i] <= 0.0) else minf(1.0, age[i] / fade_in[i])
		var a := alpha[i] * fin * pow(1.0 - t, fade_pow[i])
		if a <= 0.002:
			continue
		var e := 1.0 - (1.0 - t) * (1.0 - t)
		var sz := size0[i] + (size1[i] - size0[i]) * e
		var o := n * STRIDE
		var p := pos[i]
		var d := dir[i]
		var c := color[i]
		buf[o] = d.x
		buf[o + 1] = stretch[i]
		buf[o + 2] = rot[i]
		buf[o + 3] = p.x
		buf[o + 4] = d.y
		buf[o + 5] = sz
		buf[o + 6] = t
		buf[o + 7] = p.y
		buf[o + 8] = d.z
		buf[o + 9] = param[i]
		buf[o + 10] = float(shape[i] + 32 * mode[i])
		buf[o + 11] = p.z
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = a
		n += 1
	return n
