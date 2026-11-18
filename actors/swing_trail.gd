class_name ActorSwingTrail
extends Node3D
## Melee swing trail (prototype swing.ts). The ribbon is a sector matching the equipped weapon's hit
## volume - reach and arcDeg from ctx.loadout.melee, centred on the swing direction - so the trail
## doubles as an honest read of what the swing covers (WEAPON-04). It sweeps across the arc during
## the hit window (light: chest height; heavy: low, with a ground shock ring for heavy impacts) and
## is scrubbed by the same animation progress as the pose, so a reversed pass sweeps it backwards.
## The heavy wind-up previews the full hit volume as a dashed outline (readable commitment).
## Lives under the self's facing node (+Z = facing).

const STYLE_INDEX: Dictionary[StringName, float] = {&"blade": 0.0, &"blunt": 1.0, &"whip": 2.0, &"gauntlet": 3.0}

var _light: MeshInstance3D
var _heavy: MeshInstance3D
var _impact: MeshInstance3D
var _style: float = 0.0
var _style_name: StringName = &"blade"
var _reach: float = 1.0
var _color: Color = Color.WHITE
var _fade: float = 0.0
var _fade_heavy: float = 0.0


func setup(melee: MeleeWeaponDef, color: Color, mats: ActorMaterials, actor_height: float) -> void:
	var arc := deg_to_rad(clampf(melee.arc_deg, 10.0, 360.0))
	_reach = maxf(0.4, melee.reach)
	_style_name = melee.style
	_style = STYLE_INDEX.get(melee.style, 0.0)
	_color = color
	var segs := maxi(8, roundi(arc * 12.0))
	_light = _mesh(ActorGeom.sector(_reach * 0.3, _reach, arc, segs, false), mats.trail)
	_light.position.y = actor_height * 0.42
	_heavy = _mesh(ActorGeom.sector(_reach * 0.2, _reach, arc, segs, false), mats.trail)
	_heavy.position.y = 0.08
	_impact = _mesh(ActorGeom.ring(0.8, 1.0, 36), mats.flat_add)
	_impact.position = Vector3(0, 0.03, _reach * 0.65)
	for m: MeshInstance3D in [_light, _heavy]:
		WebCompat.set_param(m, &"style", _style)
		WebCompat.set_param(m, &"trail_color", Color(color, 0.0))
	WebCompat.set_param(_impact, &"color", Color(color, 0.0))


func _mesh(mesh: ArrayMesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


## anim + its progress t; dt fades out the trail; intensity scales opacity (state, cinematic).
func update_trail(anim: StringName, t: float, dt: float, intensity: float) -> void:
	# Light.
	var lp := 0.0
	var tail := 0.55
	if anim == AnimState.LIGHT_ACTIVE:
		_fade = 1.0
		lp = ActorMath.ease_out_cubic(t) * 1.02
		tail = 1.2 if _style_name == MeleeStyle.WHIP else 0.55
	elif anim == AnimState.LIGHT_RECOVER:
		lp = 1.02
		_fade = maxf(0.0, _fade - dt * 7.0)
	else:
		lp = 1.02
		_fade = maxf(0.0, _fade - dt * 10.0)
	var lo := _fade * 0.9 * intensity
	_light.visible = lo > 0.01
	if _light.visible:
		WebCompat.set_param(_light, &"progress", lp)
		WebCompat.set_param(_light, &"tail", tail)
		WebCompat.set_param(_light, &"preview", 0.0)
		WebCompat.set_param(_light, &"trail_color", Color(_color, lo))
	# Heavy.
	var impact := 0.0
	if anim == AnimState.HEAVY_WINDUP:
		_fade_heavy = 0.0
		_heavy.visible = true
		WebCompat.set_param(_heavy, &"preview", 1.0)
		WebCompat.set_param(_heavy, &"progress", 1.0)
		WebCompat.set_param(_heavy, &"trail_color", Color(_color, (0.12 + 0.35 * ActorMath.clamp01(t)) * intensity))
	else:
		var hp := 1.02
		if anim == AnimState.HEAVY_ACTIVE:
			_fade_heavy = 1.0
			hp = ActorMath.ease_out_cubic(minf(1.0, t * 1.4)) * 1.02
			impact = ActorMath.clamp01((t - 0.35) / 0.65)
		elif anim == AnimState.HEAVY_RECOVER:
			_fade_heavy = maxf(0.0, _fade_heavy - dt * 4.0)
			impact = 1.0 + ActorMath.clamp01(t) * 0.5
		else:
			_fade_heavy = maxf(0.0, _fade_heavy - dt * 8.0)
		var ho := _fade_heavy * intensity
		_heavy.visible = ho > 0.01
		if _heavy.visible:
			WebCompat.set_param(_heavy, &"preview", 0.0)
			WebCompat.set_param(_heavy, &"progress", hp)
			WebCompat.set_param(_heavy, &"tail", 0.9)
			WebCompat.set_param(_heavy, &"trail_color", Color(_color, ho))
	# Ground shock ring for heavy impacts (not the whip: it lashes, it does not slam).
	var show := _style_name != MeleeStyle.WHIP and impact > 0.0 and _fade_heavy > 0.02
	_impact.visible = show
	if show:
		var s := _reach * (0.25 + 0.45 * minf(1.5, impact))
		_impact.scale = Vector3(s, 1.0, s)
		WebCompat.set_param(_impact, &"color", Color(_color, maxf(0.0, 1.0 - impact / 1.5) * _fade_heavy * intensity))


func hide_all() -> void:
	_fade = 0.0
	_fade_heavy = 0.0
	_light.visible = false
	_heavy.visible = false
	_impact.visible = false
