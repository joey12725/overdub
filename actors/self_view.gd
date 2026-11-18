class_name SelfView
extends Node3D
## One self (one cassette's Moxie) on screen (prototype selfView.ts): the rig and its pose, the
## state styling, cassette identity markers, dodge afterimages, swing trail, death transition and the
## desync spark / tether.
##
## Four selves, one Moxie (UI-02): identity is the cassette colour on the ink outline, the floor ring
## with the tape letter and the headphone glow - never a recoloured outfit. The live self gets a
## bouncing chevron drawn over walls, a pulsing outer ring and a thicker outline.
##
## The pose is a function of the snapshot: timed clips are scrubbed by the tape's local tick
## (MoxieAnim), idle is scrubbed by the tick, run by the distance travelled; a state change
## cross-fades from the pose actually on screen over BLEND_SECONDS of wall time.

const MOXIE_PATH: String = "res://assets/models/moxie.glb"
const BLEND_SECONDS: float = 0.09
const HISTORY: int = 12
const AFTERIMAGES: int = 3
const SPARK_TRAIL: int = 14
const MERGE_SECONDS: float = 0.55
const DUST_GREY: Color = Color(0.553, 0.561, 0.6)
## Ink-dark body of the inverted impact frame (the hull turns paper white around it).
const NEGATIVE_BODY: Color = Color(0.05, 0.03, 0.07)
## Flavour clips layered on idle (they have no anim state of their own): Env.flavour values.
const FLAVOUR_COUNTIN: StringName = &"countin"
const FLAVOUR_WIN: StringName = &"win"
const CLIP_RESYNC: StringName = &"resync"
const RESYNC_SECONDS: float = 0.5
const WIN_SECONDS: float = 1.0
## Outline width of a self (model units): the ink line takes ActorMaterials' ink share of it.
const HULL_WIDTH: float = 0.021
## Entries of the shown-clip history the visual hit-hold reads back from.
const CLIP_HISTORY: int = 32


## Per-level data shared by the four selves.
class Shared:
	extends RefCounted
	var mats: ActorMaterials = null
	var melee: MeleeWeaponDef = MeleeWeaponDef.new()
	var ranged: RangedWeaponDef = RangedWeaponDef.new()
	var melee_id: String = ""
	var ranged_id: String = ""
	var helmet_id: String = ""
	## Every equipped item id (wardrobe looks: top / pants / shoes tints).
	var item_ids: Array[String] = []
	var looks: Dictionary[StringName, GearLook] = {}
	var ink: Color = Color("#1f1412")
	var dust: ActorParticles = null
	var glow: ActorParticles = null
	var ring: ArrayMesh = null
	var ring_outer: ArrayMesh = null
	var disc: ArrayMesh = null
	var badge: ArrayMesh = null
	var chevron: ArrayMesh = null
	var halo: ArrayMesh = null
	var bar: ArrayMesh = null
	var strip: ArrayMesh = null
	var merge_ring: ArrayMesh = null
	var flash: SphereMesh = null
	## Floor ring in each cassette's own shape (AccessKit.ring_mesh) and its wider ink backing.
	var shape_rings: Array[ArrayMesh] = []
	var shape_rings_ink: Array[ArrayMesh] = []
	## The combat-feel layer (null: no hit-hold, smear or flash from it).
	var feel: CombatFeel = null


## Per-frame inputs shared by all selves.
class Env:
	extends RefCounted
	var dt: float = 0.0
	var time: float = 0.0
	var beat_pulse: float = 0.0
	var cam_basis: Basis = Basis.IDENTITY
	var cam_right: Vector3 = Vector3.RIGHT
	## Horizontal unit vector from the camera into the scene (screen-up on the floor).
	var cam_fwd: Vector2 = Vector2(0, 1)
	var is_live: bool = false
	## Global flourish intensity (cinematic mode turns it up).
	var flourish: float = 0.0
	## Master-time rate against wall time (RenderFrame.world_rate): turns ticks per wall second into
	## the tape's speed.
	var world_rate: float = 1.0
	## &"" / FLAVOUR_COUNTIN / FLAVOUR_WIN: what an idle living self does instead of idling.
	var flavour: StringName = &""
	## "Reduce flashing": no flicker, steady i-frames, weaker chromatic split.
	var reduce_flashing: bool = false
	var high_contrast: bool = false


var tape: int = 0
var color: Color = Color.WHITE
## Current interpolated projection position (for enemy target lines).
var pos: Vector2 = Vector2.ZERO
var shown: bool = false

var _S: Shared
var _facing: Node3D
var _lean: Node3D
var rig: ActorRig
var _sampler: ActorClipSampler
var _trail: ActorSwingTrail
var _weapon_hand: Node3D = null
var _weapon_back: Node3D = null
## Second gauntlet (speaker_knuckles are worn on both fists).
var _weapon_off: Node3D = null
var _ranged_weapon: Node3D = null
var _ranged_muzzle: Node3D = null
## Melee style (FeelRig.STYLES) and the clips that play this loadout's swings and shot.
var style: String = "blade"
var clip_light: StringName = MoxieAnim.CLIP_LIGHT
var clip_heavy: StringName = MoxieAnim.CLIP_HEAVY
var clip_ranged: StringName = MoxieAnim.CLIP_RANGED
var _muzzle: MeshInstance3D
var _echoes: Array[ActorRig] = []
var _style: ActorStyle.Resolved = ActorStyle.Resolved.new()

# markers
var _disc: MeshInstance3D
var _ring_ink: MeshInstance3D
var _ring: MeshInstance3D
var _live_ring: MeshInstance3D
var _badge: MeshInstance3D
var _letter: Label3D
var _chevron: Node3D
var _chev_ink: MeshInstance3D
var _chev: MeshInstance3D
var _halo: MeshInstance3D
var _pause: Node3D
var _pause_bars: Array[MeshInstance3D] = []

# world-space (spark, tether, merge flash): parented to the layer, not to this view
var world: Node3D
var _spark: MultiMeshInstance3D
var _tether: MeshInstance3D
var _merge: MeshInstance3D
var _trail_x: PackedFloat32Array = PackedFloat32Array()
var _trail_z: PackedFloat32Array = PackedFloat32Array()
var _trail_count: int = 0

# animation state
var _pose: ActorClipSampler.Pose
var _target: ActorClipSampler.Pose
var _from: ActorClipSampler.Pose
var _tmp: ActorClipSampler.Pose
var _history: Array[ActorClipSampler.Pose] = []
var _hist_x: PackedFloat32Array = PackedFloat32Array()
var _hist_y: PackedFloat32Array = PackedFloat32Array()
var _hist_f: PackedFloat32Array = PackedFloat32Array()
var _hist_head: int = 0
var _hist_fill: int = 0
var _last_anim: StringName = AnimState.IDLE
var _entry_tick: float = 0.0
var _last_traversal: int = 0
var _blend_t: float = 1.0
var _prev_x: float = 0.0
var _prev_y: float = 0.0
var _prev_tick: float = 0.0
var _speed: float = 0.0
var _run_dist: float = 0.0
var _initialized: bool = false
var _last_life: int = OD.LifeState.ALIVE
var _last_synced: bool = true
var _death_t: float = -1.0
var _merge_t: float = -1.0
var _merge_x: float = 0.0
var _merge_y: float = 0.0
var _after_t: float = 0.0
var _dust_acc: float = 0.0
var _bits_acc: float = 0.0
var _posed: bool = false
var _seed: float = 0.0
var _translucent: bool = false
## Progress of the current timed state (exposed for the screenshot tool / tests).
var progress: float = 0.0
## The clip and fraction actually DRAWN this frame (late while a hit is held), and whether the
## combat-feel smear is drawing (tests / the screenshot tool).
var shown_clip: StringName = &""
var shown_frac: float = 0.0
var smear_on: bool = false
## Tape speed measured from the playhead (snapped to 0.5 / 1 / 2 / 4).
var tape_speed: float = 1.0
## > 0: use this tape speed instead of the measured one (tools and tests that scrub slowly).
var speed_override: float = 0.0
var weapon_len: float = 0.8
var body_scale: float = 1.0
var _mode: StringName = AnimState.IDLE
var _resync_t: float = -1.0
var _win_t: float = 0.0
var _tps: float = 60.0
var _clock: float = 0.0
var _ch_time: PackedFloat32Array = PackedFloat32Array()
var _ch_frac: PackedFloat32Array = PackedFloat32Array()
var _ch_clip: Array[StringName] = []
var _ch_head: int = 0
var _ch_fill: int = 0
var _glaive_disc: Node3D = null
var _glaive_disc_rest: Basis = Basis.IDENTITY


func setup(p_tape: int, p_color: Color, S: Shared) -> void:
	tape = p_tape
	color = p_color
	_S = S
	_seed = ActorMath.hash01(float(tape + 1)) * 10.0
	name = "Self%d" % tape
	_facing = Node3D.new()
	_facing.name = "Facing"
	add_child(_facing)
	_lean = Node3D.new()
	_lean.name = "Lean"
	_facing.add_child(_lean)
	rig = _make_moxie()
	_lean.add_child(rig)
	_sampler = rig.sampler
	if not rig.is_standin:
		MoxieModel.bind_clips(_sampler)
	var mlook: GearLook = S.looks.get(GearSlot.MELEE)
	style = FeelRig.style_for(S.melee_id, String(S.melee.style), mlook.variant if mlook != null else "")
	var mc := MoxieModel.melee_clips(_sampler, style)
	clip_light = mc[0]
	clip_heavy = mc[1]
	clip_ranged = MoxieModel.ranged_clip(_sampler, String(S.ranged.archetype))
	var n := _sampler.bone_count
	_pose = ActorClipSampler.Pose.new(n)
	_target = ActorClipSampler.Pose.new(n)
	_from = ActorClipSampler.Pose.new(n)
	_tmp = ActorClipSampler.Pose.new(n)
	_pose.copy_from(_sampler.rest)
	for i: int in HISTORY:
		var hp := ActorClipSampler.Pose.new(n)
		hp.copy_from(_sampler.rest)
		_history.append(hp)
	_hist_x.resize(HISTORY)
	_hist_y.resize(HISTORY)
	_hist_f.resize(HISTORY)
	_trail_x.resize(SPARK_TRAIL)
	_trail_z.resize(SPARK_TRAIL)
	_ch_time.resize(CLIP_HISTORY)
	_ch_frac.resize(CLIP_HISTORY)
	_ch_clip.resize(CLIP_HISTORY)
	var hips := rig.skeleton.find_bone("Hips") if rig.skeleton != null else -1
	if hips >= 0:
		body_scale = rig.skeleton.get_bone_global_rest(hips).origin.y / FeelRig.REF_HIP_HEIGHT
	# Outfit tints (APPAREL-03) from the wardrobe, by material region of THIS model; the stand-in's
	# materials are the bare slot names. Only top / pants / shoes are ever recoloured.
	var body_meshes: Array[MeshInstance3D] = rig.meshes.duplicate()
	var names := Wardrobe.material_names(body_meshes)
	var ids: Array = []
	ids.assign(S.item_ids)
	var tints := Wardrobe.tints_for(ids, names)
	for slot: StringName in [GearSlot.TOP, GearSlot.PANTS, GearSlot.SHOES]:
		var lk: GearLook = S.looks.get(slot)
		if names.has(slot) and not tints.has(slot) and lk != null and not lk.color.is_empty():
			tints[slot] = lk.color_or(Color.WHITE)
	# Headphone glow: the model's own headphone glow material, else rings fitted to its ear cups.
	var accents: Array[StringName] = [MoxieModel.RING_GLOW]
	accents.append_array(MoxieModel.headphone_glow_names(body_meshes))
	if accents.size() == 1 and not rig.is_standin:
		var rings := MoxieModel.build_headphone_rings(rig.skeleton, body_meshes)
		if rings != null:
			rig.adopt(rings)
	_attach_gear(S, body_meshes)
	var hidden: Array[StringName] = []
	if _ranged_weapon != null:
		hidden = MoxieModel.wrist_device_names(body_meshes)
	# The textured body keeps its painted albedo: looks recolour its outfit zones (region masks),
	# identity is the two-tier outline (ink line + cassette-coloured hull) and the headphone glow.
	var zones: ActorMaterials.Zones = MoxieModel.outfit_zones(S.item_ids) if not rig.is_standin else null
	rig.apply_materials(S.mats, tints, accents, hidden, true, zones)
	# Grip-to-tip length of the equipped weapon, for the smear (the lash reaches its full length at
	# the crack; a stand-in has no Tip marker).
	weapon_len = maxf(0.3, S.melee.reach * 0.72)
	if _weapon_hand != null:
		var tip := _weapon_hand.find_child("Tip", true, false) as Node3D
		if tip != null and style != "whip" and tip.position.y > 0.05:
			weapon_len = tip.position.y
		_glaive_disc = _weapon_hand.find_child("Disc", true, false) as Node3D
		if _glaive_disc != null:
			_glaive_disc_rest = _glaive_disc.basis
	rig.set_param(&"accent", color)
	rig.set_param(&"xray_color", Color(color, 0.0))

	_trail = ActorSwingTrail.new()
	_trail.name = "SwingTrail"
	_trail.setup(S.melee, color, S.mats, rig.top)
	_facing.add_child(_trail)

	# Dodge afterimages: plain copies of the rig in a flat cassette-coloured additive material.
	for i: int in AFTERIMAGES:
		var e := ActorRig.new()
		e.name = "Afterimage%d" % i
		e.setup(MOXIE_PATH, MoxieStandin.instance)
		for mi: MeshInstance3D in e.meshes:
			mi.material_override = S.mats.afterimage
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			WebCompat.set_param(mi, &"color", Color(color, 0.0))
		e.visible = false
		e.top_level = true
		add_child(e)
		_echoes.append(e)

	_build_markers(S)
	_build_world(S)
	set_shown(false)


func _make_moxie() -> ActorRig:
	var r := ActorRig.new()
	r.name = "Moxie"
	r.setup(MOXIE_PATH, MoxieStandin.instance)
	return r


## Rotation (bone-local) that gives an attached node the model-space orientation `model_basis` at
## the bone's rest pose, whatever the bone's own orientation.
func _bone_local(bone: int, model_basis: Basis) -> Basis:
	var g := rig.skeleton.get_bone_global_rest(bone).basis.orthonormalized()
	return g.inverse() * model_basis


## Only the copy's own half of a two-gauntlet file stays visible ("Gauntlet_R" / "Gauntlet_L").
static func _keep_gauntlet(node: Node, keep: String) -> void:
	for n: Node in node.find_children("Gauntlet_*", "Node3D", true, false):
		(n as Node3D).visible = String(n.name) == keep


func _attach_gear(S: Shared, body_meshes: Array[MeshInstance3D]) -> void:
	var sk := rig.skeleton
	if sk == null:
		return
	var scale_k := rig.top / ActorGear.STANDIN_TOP
	var look: GearLook = S.looks.get(GearSlot.MELEE)
	var worn := FeelRig.is_worn(style)
	var rh := MoxieModel.find_bone(sk, MoxieModel.RIGHT_HAND)
	var lh := MoxieModel.find_bone(sk, MoxieModel.LEFT_HAND)

	# Headgear first (it is fitted to the bare body's headphones): the wardrobe's model on the head
	# bone, sitting with the headphones (CHAR-05); the built-in variant shapes when the wardrobe has
	# no model for the item or the stand-in rig is shown.
	var head := MoxieModel.find_bone(sk, MoxieModel.HEAD)
	var hg: Node3D = null
	if head >= 0 and not S.helmet_id.is_empty() and not rig.is_standin and Wardrobe.has_item(S.helmet_id):
		hg = Wardrobe.attach_headgear(sk, S.helmet_id, Wardrobe.head_fit(sk, body_meshes, MOXIE_PATH))
		if hg != null:
			MoxieModel.seat_headgear(sk, head, hg, S.helmet_id)
	if hg == null and head >= 0:
		var hl: GearLook = S.looks.get(GearSlot.HELMET)
		var built := ActorGear.headgear(hl, scale_k) if hl != null else null
		if built != null:
			var at := MoxieModel.attach(sk, head, "At_Head")
			at.add_child(built)
			built.transform = Transform3D(_bone_local(head, Basis.IDENTITY), Vector3.ZERO)
			hg = at
	if hg != null:
		rig.adopt(hg)

	# Melee weapon in the right hand, in the grip frame the clips' grip arcs were authored for
	# (FeelRig: business end +Y out of the thumb side of the fist, edge +Z the knuckles' way).
	if rh >= 0:
		var w: Array = ActorGear.weapon(S.melee_id, S.melee, look)
		_weapon_hand = w[0]
		var at := MoxieModel.attach(sk, rh, "At_RightHand")
		at.add_child(_weapon_hand)
		_weapon_hand.transform = FeelRig.weapon_attach_transform(sk, rh, true, worn)
		if (w[1] as bool):
			_weapon_hand.scale = Vector3.ONE * scale_k
		elif worn:
			_keep_gauntlet(_weapon_hand, "Gauntlet_R")
		rig.adopt(_weapon_hand)
		# The second gauntlet on the left fist. The file's Gauntlet_L is already left-handed, so the
		# mirror FeelRig applies for a right gauntlet worn on the left is undone.
		if worn and lh >= 0 and not (w[1] as bool):
			var w2: Array = ActorGear.weapon(S.melee_id, S.melee, look)
			_weapon_off = w2[0]
			var atl := MoxieModel.attach(sk, lh, "At_LeftHand")
			atl.add_child(_weapon_off)
			var tl := FeelRig.weapon_attach_transform(sk, lh, false, true)
			tl.basis = tl.basis * Basis.from_scale(Vector3(-1, 1, 1))
			_weapon_off.transform = tl
			_keep_gauntlet(_weapon_off, "Gauntlet_L")
			rig.adopt(_weapon_off)

	# Stowed across the back between swings (gauntlets stay worn, so they have no stowed copy).
	var chest := MoxieModel.find_bone(sk, MoxieModel.CHEST)
	if chest >= 0 and not worn:
		var w3: Array = ActorGear.weapon(S.melee_id, S.melee, look)
		_weapon_back = w3[0]
		var atc := MoxieModel.attach(sk, chest, "At_Chest")
		atc.add_child(_weapon_back)
		var up := Vector3(0.45, 0.85, -0.1).normalized()
		var side := Vector3(0, 0, -1).cross(up).normalized()
		var model_b := Basis(side, up, side.cross(up).normalized())
		var g := sk.get_bone_global_rest(chest)
		# Behind the back: clear of the torso (and the jacket) whatever the model's depth.
		var depth := clampf(rig.bounds.size.z * 0.5, 0.08, 0.2)
		var back_pos := g.origin + Vector3(-0.08 * scale_k, -0.08 * scale_k, -depth - 0.03)
		_weapon_back.transform = Transform3D(_bone_local(chest, model_b), g.affine_inverse() * back_pos)
		if (w3[1] as bool):
			_weapon_back.scale = Vector3.ONE * scale_k
		rig.adopt(_weapon_back)

	# Ranged weapon worn on the left forearm, replacing the model's own wrist device.
	var fl := MoxieModel.find_bone(sk, MoxieModel.LEFT_FOREARM)
	if fl >= 0 and not rig.is_standin:
		_ranged_weapon = MoxieModel.ranged_weapon(S.ranged_id)
		if _ranged_weapon != null:
			var atf := MoxieModel.attach(sk, fl, "At_LeftLowerArm")
			atf.add_child(_ranged_weapon)
			_ranged_weapon.transform = MoxieModel.ranged_attach_transform(sk, fl, lh)
			_ranged_muzzle = _ranged_weapon.find_child("Muzzle", true, false) as Node3D
			rig.adopt(_ranged_weapon)

	# Muzzle flash: at the ranged weapon's Muzzle, else on the left hand (the ranged pose thrusts
	# the left wrist).
	_muzzle = MeshInstance3D.new()
	_muzzle.name = "MuzzleFlash"
	_muzzle.mesh = S.flash
	_muzzle.material_override = S.mats.flat_add
	_muzzle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	WebCompat.set_param(_muzzle, &"color", Color(color, 0.0))
	if _ranged_muzzle != null:
		_ranged_muzzle.add_child(_muzzle)
	elif lh >= 0:
		MoxieModel.attach(sk, lh, "At_LeftHandFlash").add_child(_muzzle)
	else:
		_facing.add_child(_muzzle)
	_muzzle.visible = false


func _flat(mesh: Mesh, mat: Material, parent: Node3D, y: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = y
	WebCompat.set_param(mi, &"color", c)
	parent.add_child(mi)
	return mi


func _build_markers(S: Shared) -> void:
	var m := S.mats
	# Floor identity: tinted disc, ink-backed ring, letter badge on the camera side (UI-02).
	_disc = _flat(S.disc, m.flat_mix, self, 0.008, Color(color, 0.14))
	# The ring is the cassette's own shape (circle / triangle / square / plus) over an ink backing:
	# identity never rests on colour alone (docs/ACCESSIBILITY.md section 3).
	var ring_mesh: ArrayMesh = S.shape_rings[tape] if tape < S.shape_rings.size() else S.ring
	var ring_ink: ArrayMesh = S.shape_rings_ink[tape] if tape < S.shape_rings_ink.size() else S.ring_outer
	_ring_ink = _flat(ring_ink, m.flat_mix, self, 0.01, Color(S.ink, 0.7))
	_ring = _flat(ring_mesh, m.flat_mix, self, 0.012, Color(color, 0.95))
	_live_ring = _flat(ring_mesh, m.flat_add, self, 0.014, Color(color, 0.5))
	# Same material and priority as the ink backing: draw the colour over it, not under.
	_ring.sorting_offset = 0.4
	_live_ring.sorting_offset = 0.45
	_badge = _flat(S.badge, m.flat_mix, self, 0.016, Color(S.ink, 0.85))
	_badge.sorting_offset = 0.6
	_letter = Label3D.new()
	_letter.name = "Letter"
	_letter.text = OD.tape_letter(tape)
	_letter.font_size = 72
	_letter.pixel_size = 0.0032
	_letter.outline_size = 16
	_letter.modulate = color
	_letter.outline_modulate = Color(S.ink, 0.95)
	_letter.double_sided = true
	_letter.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_letter.shaded = false
	_letter.render_priority = ActorMaterials.PRI_DECAL + 1
	_letter.outline_render_priority = ActorMaterials.PRI_DECAL
	_letter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_letter)
	# Live marker: a bouncing chevron drawn over walls so the controlled self is never lost.
	_chevron = Node3D.new()
	_chevron.name = "LiveChevron"
	add_child(_chevron)
	_chev_ink = _flat(S.chevron, m.flat_overlay, _chevron, 0.0, Color(S.ink, 1.0))
	_chev_ink.scale = Vector3(1.35, 1.35, 1.0)
	_chev_ink.position.z = -0.01
	_chev = _flat(S.chevron, m.flat_overlay, _chevron, 0.0, Color(color, 1.0))
	_chev.sorting_offset = 0.05
	# Broken halo: "dead but still performing" (GHOST-01).
	_halo = _flat(S.halo, m.flat_add, self, 0.0, Color(color, 0.85))
	# Pause glyph for a 'stop' tape holding its final pose.
	_pause = Node3D.new()
	_pause.name = "Pause"
	add_child(_pause)
	for sx: float in [-0.045, 0.045]:
		var bmi := _flat(S.bar, m.flat_overlay, _pause, 0.0, Color(color, 0.9))
		bmi.position.x = sx
		_pause_bars.append(bmi)


func _build_world(S: Shared) -> void:
	var m := S.mats
	world = Node3D.new()
	world.name = "SelfWorld%d" % tape
	# Spark: soft glow + hot core + comet trail, drawn above walls (DESYNC-06).
	_spark = MultiMeshInstance3D.new()
	_spark.name = "Spark"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = SPARK_TRAIL + 2
	_spark.multimesh = mm
	_spark.material_override = m.particle_overlay
	_spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spark.custom_aabb = AABB(Vector3(-1000, -50, -1000), Vector3(2000, 100, 2000))
	world.add_child(_spark)
	_tether = _flat(S.strip, m.flat_overlay, world, 0.0, Color(color, 0.9))
	WebCompat.set_param(_tether, &"dash", 0.16)
	_merge = _flat(S.merge_ring, m.flat_overlay_add, world, 0.05, Color(color, 0.0))


func set_shown(v: bool) -> void:
	shown = v
	visible = v
	if world != null:
		world.visible = v
	if not v:
		_spark.visible = false
		_tether.visible = false
		_merge.visible = false
		for e: ActorRig in _echoes:
			e.visible = false
		_initialized = false
		_posed = false
		_trail_count = 0
		_death_t = -1.0
		_merge_t = -1.0
		_resync_t = -1.0
		_ch_fill = 0
		smear_on = false
		if _S != null and _S.feel != null:
			_S.feel.hide_swing(tape)
		if _trail != null:
			_trail.hide_all()


# ───────────────────────────── per frame ─────────────────────────────

func update_self(a: ActorInterp.SelfFrame, env: Env) -> void:
	if not shown:
		set_shown(true)
	var dt := env.dt
	pos.x = a.x
	pos.y = a.y

	# ── transitions ──
	var fresh := not _initialized or a.teleported
	if fresh:
		_prev_x = a.x
		_prev_y = a.y
		_prev_tick = a.tick
		_last_life = a.life
		_last_synced = a.synced
		_last_anim = a.anim
		_entry_tick = a.tick
		_last_traversal = a.traversal
		_blend_t = 1.0
		_trail_count = 0
		_hist_fill = 0
		if not _initialized:
			_death_t = -1.0
	else:
		if _last_life == OD.LifeState.ALIVE and a.life != OD.LifeState.ALIVE:
			_start_death(a)
		if not _last_synced and a.synced:
			_start_merge(a)
	if a.life == OD.LifeState.ALIVE and _last_life != OD.LifeState.ALIVE:
		_death_t = -1.0
	_last_life = a.life
	_last_synced = a.synced
	_initialized = true

	# ── locomotion measures (speed-invariant: distance per LOCAL tick) ──
	var dx := a.x - _prev_x
	var dy := a.y - _prev_y
	var dist := sqrt(dx * dx + dy * dy)
	var dtick := a.tick - _prev_tick
	if absf(dtick) > 1e-4:
		var local_speed := dist / absf(dtick) * float(OD.LOCAL_HZ)
		_speed += (local_speed - _speed) * ActorMath.damp_factor(14.0, dt)
	elif a.dir == 0 or a.ended:
		_speed += (0.0 - _speed) * ActorMath.damp_factor(10.0, dt)
	# Playhead rate in ticks per wall second -> tape speed (0.5 / 1 / 2 / 4) for the feel treatment.
	if dt > 1e-5 and absf(dtick) > 1e-4 and not fresh:
		_tps += (absf(dtick) / dt - _tps) * ActorMath.damp_factor(10.0, dt)
		tape_speed = FeelTune.SPEEDS[FeelTune.speed_index(_tps / (float(OD.LOCAL_HZ) * maxf(0.05, env.world_rate)))]
	if speed_override > 0.0:
		tape_speed = speed_override
	_clock += dt
	var fx: FeelSubject = _S.feel.self_fx(tape) if _S.feel != null else null
	# The run cycle follows distance, signed by the playhead: a reverse pass runs it backwards.
	_run_dist += dist * (-1.0 if dtick < 0.0 else 1.0)
	_prev_x = a.x
	_prev_y = a.y
	_prev_tick = a.tick

	# ── pose ──
	if a.anim != _last_anim or a.traversal != _last_traversal:
		_from.copy_from(_pose)
		_blend_t = 0.0
		_entry_tick = a.tick
		_last_anim = a.anim
		_last_traversal = a.traversal
	# Flavour on a living, idle self: the resync snap, the win pose, the count-in bounce.
	if _resync_t >= 0.0:
		_resync_t += dt
		if _resync_t >= RESYNC_SECONDS:
			_resync_t = -1.0
	var mode := a.anim
	if a.anim == AnimState.IDLE and a.life == OD.LifeState.ALIVE and a.synced:
		if _resync_t >= 0.0 and _sampler.has_clip(CLIP_RESYNC):
			mode = CLIP_RESYNC
		elif env.flavour == FLAVOUR_WIN and _sampler.has_clip(FLAVOUR_WIN):
			mode = FLAVOUR_WIN
		elif env.flavour == FLAVOUR_COUNTIN and _sampler.has_clip(FLAVOUR_COUNTIN):
			mode = FLAVOUR_COUNTIN
	if mode != _mode:
		if _blend_t >= 1.0:
			_from.copy_from(_pose)
			_blend_t = 0.0
		if mode == FLAVOUR_WIN:
			_win_t = 0.0
		_mode = mode
	if _mode == FLAVOUR_WIN:
		_win_t = minf(1.0, _win_t + dt / WIN_SECONDS)
	var dur := MoxieAnim.duration_ticks(a.anim, _S.melee, _S.ranged)
	var t := MoxieAnim.progress(_entry_tick, a.tick, a.dir, dur)
	progress = t
	var dying := _death_t >= 0.0 and _death_t < MoxieAnim.DEATH_SECONDS
	if dying:
		_death_t += dt
		_sampler.sample(MoxieAnim.CLIP_DEATH, _death_t / MoxieAnim.DEATH_SECONDS, _pose)
		_blend_t = 1.0
	elif a.anim == AnimState.STOPPED:
		# Hold whatever pose the tape ended on: the self reads as paused, not idling (stop mode).
		# Seen first already stopped (a seek): there is no prior pose to hold, use the held clip.
		if not _posed:
			_sampler.sample(MoxieAnim.CLIP_STOPPED, 0.0, _pose)
		_blend_t = 1.0
	else:
		_compute_target(a, t, fx, env)
		_blend_t = minf(1.0, _blend_t + dt / BLEND_SECONDS)
		if _blend_t < 1.0:
			ActorClipSampler.blend(_from, _target, ActorMath.smooth(0.0, 1.0, _blend_t), _pose)
		else:
			_pose.copy_from(_target)
	if dying or a.anim == AnimState.STOPPED:
		shown_clip = &""
	_posed = true
	_sampler.apply(_pose)
	_apply_lean(a, dt)
	var swinging := shown_clip != &"" and (shown_clip == clip_light or shown_clip == clip_heavy)
	var drawn := not dying and (MoxieAnim.is_melee(a.anim) or swinging or FeelRig.is_worn(style))
	# The glaive's record spins up through the hit window (a function of the shown fraction, so it
	# rewinds with the tape).
	if _glaive_disc != null:
		var spin := ActorMath.smooth(0.25, 0.8, shown_frac) * TAU * 3.0 if swinging else 0.0
		_glaive_disc.basis = _glaive_disc_rest * Basis(Vector3.RIGHT, spin)
	if _weapon_hand != null:
		_weapon_hand.visible = drawn
	if _weapon_back != null:
		_weapon_back.visible = not drawn
	if _weapon_off != null:
		_weapon_off.visible = drawn
	# Combat feel: drawn late while a hit is held (position too), squashed / tilted / shuddering on
	# the held frame. Only the body deforms: the floor markers stay put under it.
	var yaw_basis := Basis(Vector3.UP, RenderCtx.heading_to_yaw(a.facing))
	var off := Vector2.ZERO
	if fx != null:
		off = fx.lag_offset()
		_facing.transform = fx.apply(Transform3D(yaw_basis, Vector3.ZERO)) if fx.is_deformed() else Transform3D(yaw_basis, Vector3.ZERO)
	else:
		_facing.transform = Transform3D(yaw_basis, Vector3.ZERO)
	position = Vector3(a.x + off.x, 0, a.y + off.y)
	rig.update_xray(global_position if is_inside_tree() else position)
	smear_on = false
	if _S.feel != null:
		var clip_anim: Animation = _sampler.clip_animation(shown_clip) if swinging and not dying else null
		if clip_anim != null and clip_anim.has_meta(&"od_grip"):
			_S.feel.update_swing(tape, clip_anim, shown_frac, -1 if a.dir == -1 else 1, shown_clip == clip_heavy, Transform3D(yaw_basis, position))
			smear_on = true
		else:
			_S.feel.hide_swing(tape)

	# ── style ──
	var stopped := a.anim == AnimState.STOPPED
	var st := ActorStyle.resolve(a.life, a.synced, a.iframes, stopped, dying, env.time, _seed, _style, env.reduce_flashing)
	var sp := ActorStyle.params(st.style)
	rig.set_translucent(st.translucent)
	rig.set_param(&"body_opacity", st.opacity)
	rig.set_param(&"desat", st.desat)
	rig.set_param(&"holo", 1.0 if st.body == ActorStyle.Body.HOLO else 0.0)
	rig.set_param(&"phase", 1.0 if st.body == ActorStyle.Body.PHASED else 0.0)
	rig.set_param(&"hollow", 1.0 if st.body == ActorStyle.Body.HOLLOW else 0.0)
	rig.set_param(&"glow_mul", 1.5 * sp.glow * (1.0 + env.beat_pulse * 0.6) + (0.4 if env.is_live else 0.0))
	rig.set_param(&"rim_amt", 0.4 if st.body == ActorStyle.Body.PHASED else 0.14)
	var flash := 0.0
	var flash_c := Color.WHITE
	if dying:
		var dtn := _death_t / MoxieAnim.DEATH_SECONDS
		flash = 1.0 if dtn < 0.12 else maxf(0.0, 1.0 - (dtn - 0.12) / 0.5) * 0.7
		flash_c = Color.WHITE if dtn < 0.12 else color
	elif _merge_t >= 0.0:
		flash = maxf(0.0, 1.0 - _merge_t / 0.3) * 0.8
		flash_c = color
	var hull := ActorStyle.hull_color(st, color)
	# Impact frame from the feel layer (a death blow): white, or the inverted frame - ink body
	# inside a paper-white outline. Nothing under "reduce flashing".
	var ff: Vector2 = _S.feel.flash_of(fx) if _S.feel != null else Vector2.ZERO
	if ff.x > flash:
		flash = ff.x
		flash_c = NEGATIVE_BODY if ff.y > 0.5 else Color.WHITE
		if ff.y > 0.5:
			hull = ActorStyle.IFRAME_HULL
	if env.reduce_flashing:
		flash = minf(flash, 0.35)
	rig.set_param(&"flash_col", Color(flash_c, flash))
	rig.set_param(&"outline_color", Color(hull, st.hull_opacity))
	var hull_w := HULL_WIDTH * st.hull_scale * (1.2 if env.is_live else 1.0) * (1.3 if env.high_contrast else 1.0)
	rig.set_param(&"outline_width", hull_w * rig.top / ActorGear.STANDIN_TOP)
	var echo := st.chroma > 0.0
	if echo:
		var j := (ActorMath.flicker_value(env.time * 0.7, _seed + 7.0) - 0.5) * 0.02
		var split := ActorOptions.split_scale()
		var s := (0.05 * st.chroma + (0.0 if env.reduce_flashing else j)) * maxf(split, 0.5)
		rig.set_param(&"echo_shift", env.cam_right * s)
		rig.set_param(&"echo_amt", 0.45 * st.chroma * st.flick * split)
	else:
		rig.set_param(&"echo_amt", 0.0)
	# X-ray: occluded selves show a flat cassette-coloured silhouette (fainter for dead ghosts).
	var xa := 0.85 if st.body == ActorStyle.Body.SOLID else (0.4 if st.body == ActorStyle.Body.HOLLOW else 0.6)
	rig.set_param(&"xray_color", Color(color, xa))

	_update_markers(st, sp, env, stopped)

	# Muzzle flash on the wrist device (ranged recoil, interact press).
	var wrist := 0.0
	if not dying:
		if a.anim == AnimState.RANGED:
			var aim := ActorMath.smooth(0.0, 0.2, t) * (1.0 - ActorMath.smooth(0.8, 1.0, t))
			wrist = maxf(aim * 0.6, exp(-((t - 0.3) * (t - 0.3)) / 0.006))
		elif a.anim == AnimState.INTERACT:
			wrist = ActorMath.bump(t) * 0.5
	_muzzle.visible = wrist > 0.05
	if _muzzle.visible:
		var ms := 0.4 + wrist * 1.1
		_muzzle.scale = Vector3(ms, ms, ms)
		WebCompat.set_param(_muzzle, &"color", Color(color, wrist * 0.9))

	# ── swing trail ──
	var swing_k := 1.0 if st.body == ActorStyle.Body.SOLID else (0.8 if st.body == ActorStyle.Body.HOLO else 0.35)
	# With the feel smear on the real edge, the hit-volume sector steps back to a faint read.
	_trail.update_trail(AnimState.IDLE if dying else a.anim, t, dt, swing_k * (0.85 + env.flourish * 0.3) * (0.35 if smear_on else 1.0))

	# ── afterimages (dodge) ──
	_push_history(a)
	if a.anim == AnimState.DODGE and not dying:
		_after_t = 1.0
	else:
		_after_t = maxf(0.0, _after_t - dt * 5.0)
	for i: int in AFTERIMAGES:
		var e := _echoes[i]
		var back := (i + 1) * 3
		var show := _after_t > 0.01 and _hist_fill > back and st.body != ActorStyle.Body.HOLLOW
		e.visible = show
		if not show:
			continue
		var idx := (_hist_head - 1 - back + HISTORY * 4) % HISTORY
		ActorClipSampler.apply_to(e.skeleton, _history[idx])
		e.global_transform = Transform3D(Basis(Vector3.UP, RenderCtx.heading_to_yaw(_hist_f[idx])), Vector3(_hist_x[idx], 0, _hist_y[idx]))
		e.set_param(&"color", Color(color, 0.3 * _after_t * (1.0 - float(i) / AFTERIMAGES)))

	# ── particles: ghost dust, hologram bits ──
	if sp.trail == ActorStyle.Trail.DUST:
		_dust_acc += dist * 6.0 + dt * 1.5
		var k := 0
		while _dust_acc >= 1.0:
			_dust_acc -= 1.0
			k += 1
			var r := ActorMath.hash01(env.time * 91.0 + _seed + k * 7.1) - 0.5
			var r2 := ActorMath.hash01(env.time * 57.0 + _seed * 3.0 + k * 3.3) - 0.5
			_S.dust.emit(a.x + r * 0.25, 0.05 + absf(r2) * 0.2, a.y + r2 * 0.25, -dx * 2.0 + r * 0.1, 0.12, -dy * 2.0 + r2 * 0.1, 1.1, 0.07, 2.2, DUST_GREY, 0.45, 1.5, 0.0)
	else:
		_dust_acc = 0.0
	if sp.trail == ActorStyle.Trail.HOLO_BITS:
		_bits_acc += dt * 9.0 + dist * 5.0
		var k := 0
		while _bits_acc >= 1.0:
			_bits_acc -= 1.0
			k += 1
			var r := ActorMath.hash01(env.time * 71.0 + _seed + k * 5.7) - 0.5
			var r2 := ActorMath.hash01(env.time * 33.0 + _seed * 5.0 + k * 2.9) - 0.5
			var ry := ActorMath.hash01(env.time * 13.0 + _seed + k * 1.3)
			_S.glow.emit(a.x + r * 0.35, 0.1 + ry * rig.top * 0.75, a.y + r2 * 0.35, 0, 0.35, 0, 0.8, 0.035, 0.4, color, 0.8, 0.0, 0.0)
	else:
		_bits_acc = 0.0

	if _death_t >= MoxieAnim.DEATH_SECONDS:
		_death_t = -1.0
	_update_spark(a, sp.tether, env)


func _compute_target(a: ActorInterp.SelfFrame, t: float, fx: FeelSubject, env: Env) -> void:
	var cur_clip: StringName = &""
	var cur_frac := 0.0
	if MoxieAnim.is_timed(a.anim):
		cur_clip = clip_for(a.anim)
		cur_frac = MoxieAnim.clip_fraction(a.anim, t)
	# Remember what a swing showed when; a held hit reads it back `lag` seconds late, so the body
	# freezes on the contact frame and then catches up, even across a state change.
	var melee := MoxieAnim.is_melee(a.anim)
	_ch_time[_ch_head] = _clock
	_ch_frac[_ch_head] = cur_frac
	_ch_clip[_ch_head] = cur_clip if melee else &""
	_ch_head = (_ch_head + 1) % CLIP_HISTORY
	_ch_fill = mini(CLIP_HISTORY, _ch_fill + 1)
	shown_clip = cur_clip
	shown_frac = cur_frac
	if fx != null and fx.lag > 0.0:
		_lagged_clip(_clock - fx.lag)
	if shown_clip != &"":
		if not _sampler.sample(shown_clip, shown_frac, _target):
			_sampler.sample(MoxieAnim.CLIP_IDLE, 0.0, _target)
		return
	if _mode == CLIP_RESYNC:
		_sampler.sample(CLIP_RESYNC, _resync_t / RESYNC_SECONDS, _target)
		return
	if _mode == FLAVOUR_WIN:
		_sampler.sample(FLAVOUR_WIN, _win_t, _target)
		return
	if _mode == FLAVOUR_COUNTIN:
		_sampler.sample(FLAVOUR_COUNTIN, env.time / _sampler.clip_length(FLAVOUR_COUNTIN), _target)
		return
	# Idle and run blend by speed; idle is scrubbed by the local tick (it rewinds and holds with
	# the tape), run by the distance travelled (feet stay planted at any tape speed).
	var w := MoxieAnim.run_weight(_speed) if a.anim == AnimState.RUN else 0.0
	_sampler.sample(MoxieAnim.CLIP_IDLE, a.tick / (float(OD.LOCAL_HZ) * MoxieAnim.IDLE_SECONDS), _target)
	if w > 0.001:
		_sampler.sample(MoxieAnim.CLIP_RUN, MoxieAnim.run_fraction(_run_dist), _tmp)
		ActorClipSampler.blend(_target, _tmp, w, _target)


## Set shown_clip / shown_frac to what a swing showed at wall time `at` (no change when the
## history has no swing there).
func _lagged_clip(at: float) -> void:
	var newer := -1
	for k: int in _ch_fill:
		var j := (_ch_head - 1 - k + CLIP_HISTORY * 2) % CLIP_HISTORY
		if _ch_time[j] <= at:
			if _ch_clip[j] == &"":
				return
			shown_clip = _ch_clip[j]
			shown_frac = _ch_frac[j]
			if newer >= 0 and _ch_clip[newer] == shown_clip:
				var span := _ch_time[newer] - _ch_time[j]
				if span > 1e-6:
					shown_frac = lerpf(_ch_frac[j], _ch_frac[newer], clampf((at - _ch_time[j]) / span, 0.0, 1.0))
			return
		newer = j


## The clip that plays an anim state with this loadout (per-weapon swings and shot when present).
func clip_for(anim: StringName) -> StringName:
	var c := MoxieAnim.clip_for(anim)
	if c == MoxieAnim.CLIP_LIGHT:
		return clip_light
	if c == MoxieAnim.CLIP_HEAVY:
		return clip_heavy
	if c == MoxieAnim.CLIP_RANGED:
		return clip_ranged
	return c


## Lean into velocity: forward pitch with speed, a bank into lateral motion (on top of the clip).
func _apply_lean(a: ActorInterp.SelfFrame, _dt: float) -> void:
	var sp := ActorMath.clamp01(_speed / MoxieAnim.RUN_SPEED)
	var vm := sqrt(a.vx * a.vx + a.vy * a.vy)
	var lf := 0.0
	var ls := 0.0
	if vm > 1e-4 and a.anim == AnimState.RUN:
		var cf := cos(a.facing)
		var sf := sin(a.facing)
		lf = (a.vx * cf + a.vy * sf) / vm * sp
		ls = (a.vx * sf - a.vy * cf) / vm * sp
	_lean.rotation = Vector3(clampf(lf, -1.0, 1.5) * 0.09, 0.0, clampf(ls, -1.0, 1.0) * 0.08)


func _update_markers(st: ActorStyle.Resolved, sp: ActorStyle.Params, env: Env, stopped: bool) -> void:
	var live := env.is_live
	# Floored: a ghost's ring and letter are the identity it has left (ACCESSIBILITY A2, A3).
	var ring_k := maxf(ActorStyle.RING_FLOOR, st.ring * (1.0 if live else 0.8))
	WebCompat.set_param(_ring, &"color", Color(color, 0.95 * ring_k))
	WebCompat.set_param(_ring_ink, &"color", Color(_S.ink, (0.85 if env.high_contrast else 0.7) * ring_k))
	WebCompat.set_param(_disc, &"color", Color(color, (0.26 if live else 0.14) * ring_k))
	_live_ring.visible = live
	if live:
		var pulse := 1.18 + env.beat_pulse * 0.25
		_live_ring.scale = Vector3(pulse, 1.0, pulse)
		WebCompat.set_param(_live_ring, &"color", Color(color, 0.3 + 0.5 * env.beat_pulse))
	var badge_k := maxf(ActorStyle.BADGE_FLOOR, ring_k)
	var off := Vector3(-env.cam_fwd.x * 0.5, 0.0, -env.cam_fwd.y * 0.5) * maxf(1.0, rig.top / ActorGear.STANDIN_TOP)
	_badge.position = Vector3(off.x, 0.016, off.z)
	WebCompat.set_param(_badge, &"color", Color(_S.ink, 0.85 * badge_k))
	# Letter lies flat on the floor, upright as seen from the camera.
	_letter.position = Vector3(off.x, 0.02, off.z)
	var yaw := atan2(-env.cam_fwd.x, -env.cam_fwd.y)
	_letter.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5)
	_letter.modulate = Color(color, badge_k)
	_chevron.visible = live
	if live:
		_chevron.position = Vector3(0, rig.top + 0.24 + env.beat_pulse * 0.06 + absf(sin(env.time * 3.2)) * 0.06, 0)
		_chevron.basis = env.cam_basis
	_halo.visible = sp.marker == ActorStyle.Marker.BROKEN_HALO
	if _halo.visible:
		_halo.position = Vector3(0, rig.top + 0.08 + sin(env.time * 2.3) * 0.015, 0)
		_halo.rotation = Vector3(0.25 + sin(env.time * 1.3) * 0.08, env.time * 0.9, 0.12)
		WebCompat.set_param(_halo, &"color", Color(color, 0.9 * st.flick))
	_pause.visible = stopped
	if stopped:
		_pause.position = Vector3(0, rig.top + 0.16, 0)
		_pause.basis = env.cam_basis
		for b: MeshInstance3D in _pause_bars:
			WebCompat.set_param(b, &"color", Color(color.lerp(Color(0.6, 0.6, 0.6), 0.3), 0.65 + 0.3 * sin(env.time * 2.0)))


func _start_death(a: ActorInterp.SelfFrame) -> void:
	_death_t = 0.0
	for i: int in 26:
		var ang := float(i) / 26.0 * TAU + ActorMath.hash01(i + _seed) * 0.4
		var spd := 0.9 + ActorMath.hash01(i * 7 + _seed) * 1.6
		_S.glow.emit(a.x, 0.45 * rig.top + ActorMath.hash01(i * 3 + _seed) * 0.4, a.y, cos(ang) * spd, 0.6 + ActorMath.hash01(i * 11) * 1.4, sin(ang) * spd,
			0.7, 0.06, 0.3, Color.WHITE if i % 3 == 0 else color, 1.0, 2.5, 2.5)


func _start_merge(a: ActorInterp.SelfFrame) -> void:
	_merge_t = 0.0
	_resync_t = 0.0
	_merge_x = a.x
	_merge_y = a.y
	for i: int in 20:
		var ang := float(i) / 20.0 * TAU
		_S.glow.emit(a.x + cos(ang) * 0.1, 0.5, a.y + sin(ang) * 0.1, cos(ang) * 1.8, 0.4, sin(ang) * 1.8, 0.5, 0.05, 0.4,
			Color.WHITE if i % 2 == 1 else color, 1.0, 4.0, 0.0)


func _push_history(a: ActorInterp.SelfFrame) -> void:
	var i := _hist_head
	_history[i].copy_from(_pose)
	_hist_x[i] = a.x
	_hist_y[i] = a.y
	_hist_f[i] = a.facing
	_hist_head = (i + 1) % HISTORY
	_hist_fill = mini(HISTORY, _hist_fill + 1)


func _update_spark(a: ActorInterp.SelfFrame, want_tether: bool, env: Env) -> void:
	var show := want_tether and a.has_spark
	_spark.visible = show
	_tether.visible = show
	if show:
		# Comet trail: positions sampled as the spark moves.
		var lx := _trail_x[0] if _trail_count > 0 else a.spark_x + 1e3
		var lz := _trail_z[0] if _trail_count > 0 else a.spark_y + 1e3
		if Vector2(a.spark_x - lx, a.spark_y - lz).length() > 0.04:
			for i: int in range(SPARK_TRAIL - 1, 0, -1):
				_trail_x[i] = _trail_x[i - 1]
				_trail_z[i] = _trail_z[i - 1]
			_trail_x[0] = a.spark_x
			_trail_z[0] = a.spark_y
			_trail_count = mini(SPARK_TRAIL, _trail_count + 1)
		var h := 0.36 + sin(env.time * 6.0) * 0.02
		var pulse := 0.85 + 0.15 * sin(env.time * 14.0)
		var mm := _spark.multimesh
		var halo_s := 0.42 * pulse
		mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(halo_s, halo_s, halo_s)), Vector3(a.spark_x, h, a.spark_y)))
		mm.set_instance_color(0, Color(color, 0.6))
		mm.set_instance_transform(1, Transform3D(Basis.from_scale(Vector3(0.13, 0.13, 0.13)), Vector3(a.spark_x, h, a.spark_y)))
		mm.set_instance_color(1, Color(color.lerp(Color.WHITE, 0.65), 1.0))
		for i: int in SPARK_TRAIL:
			var on := i < _trail_count
			var f := 1.0 - float(i) / SPARK_TRAIL
			var s := 0.11 * f + 0.02
			var px := _trail_x[i] if on else a.spark_x
			var pz := _trail_z[i] if on else a.spark_y
			mm.set_instance_transform(2 + i, Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(px, h - (1.0 - f) * 0.05, pz)))
			mm.set_instance_color(2 + i, Color(color, 0.7 * f * f if on else 0.0))
		var length := ActorGeom.place_strip(_tether, a.spark_x, a.spark_y, a.x, a.y, 0.05, 0.03)
		WebCompat.set_param(_tether, &"len", length)
		WebCompat.set_param(_tether, &"color", Color(color, 0.9))
	else:
		_trail_count = 0
	if _merge_t >= 0.0:
		_merge_t += env.dt
		var k := _merge_t / MERGE_SECONDS
		if k >= 1.0:
			_merge_t = -1.0
			_merge.visible = false
		else:
			_merge.visible = true
			var s := 0.25 + 0.9 * sqrt(k)
			_merge.transform = Transform3D(Basis.from_scale(Vector3(s, 1.0, s)), Vector3(_merge_x, 0.05, _merge_y))
			WebCompat.set_param(_merge, &"color", Color(color, (1.0 - k) * (0.6 + 0.4 * ActorMath.bump(k * 2.0))))


## Scene anchor at chest height (camera framing / fx).
func anchor() -> Vector3:
	return Vector3(pos.x, rig.top * 0.55, pos.y)
