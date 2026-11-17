class_name FeelRig
extends RefCounted
## Names, paths and attachment maths of the humanoid animation library (docs/COMBAT-FEEL.md).
## Pure and static: unit-tested in tests/feel/.

const LIBRARY_PATH: String = "res://assets/anim/library/moxie_anims.res"
const MANNEQUIN_PATH: String = "res://assets/anim/library/mannequin.glb"

## Melee weapon style per catalogue item (gear.json's melee.style is coarser: three items say "blade").
const STYLE_OF_ITEM: Dictionary[String, String] = {
	"splice_blade": "blade", "stylus_shiv": "shiv", "amp_sledge": "blunt", "reel_lash": "whip",
	"speaker_knuckles": "gauntlet", "vinyl_glaive": "polearm",
}
const STYLES: Array[String] = ["blade", "shiv", "blunt", "whip", "gauntlet", "polearm"]
const ARCHETYPES: Array[String] = ["missile", "pierce", "phase", "arc", "burst"]
## Hips rest height of the body the clips' grip arcs were authored on.
const REF_HIP_HEIGHT: float = 0.84
## Clip fractions of the melee contract.
const WINDUP_END: float = 0.4
const ACTIVE_END: float = 0.6


## Style for a melee item: by id, else from the catalogue's look variant / style, else "blade".
static func style_for(item_id: String, style: String = "", variant: String = "") -> String:
	if STYLE_OF_ITEM.has(item_id):
		return STYLE_OF_ITEM[item_id]
	match variant:
		"shiv":
			return "shiv"
		"sledge":
			return "blunt"
		"whip":
			return "whip"
		"gauntlet":
			return "gauntlet"
		"glaive":
			return "polearm"
	match style:
		"blunt":
			return "blunt"
		"whip":
			return "whip"
		"gauntlet":
			return "gauntlet"
	return "blade"


## Clip name for a melee swing: "light_<style>" / "heavy_<style>", falling back to "light" / "heavy"
## when `has` (a Callable(StringName) -> bool, e.g. ActorClipSampler.has_clip) says it is missing.
static func melee_clip(heavy: bool, style: String, has: Callable = Callable()) -> StringName:
	var base := "heavy" if heavy else "light"
	var styled := StringName(base + "_" + style)
	if style.is_empty() or (has.is_valid() and not has.call(styled)):
		return StringName(base)
	return styled


## Clip name for a ranged shot: "ranged_<archetype>", falling back to "ranged".
static func ranged_clip(archetype: String, has: Callable = Callable()) -> StringName:
	var styled := StringName("ranged_" + archetype)
	if archetype.is_empty() or (has.is_valid() and not has.call(styled)):
		return &"ranged"
	return styled


## True for styles held in both hands (the left hand's place on the shaft is keyed in the clips).
static func is_two_handed(style: String) -> bool:
	return style == "blunt" or style == "polearm"


## True for styles worn on both fists rather than held (speaker_knuckles).
static func is_worn(style: String) -> bool:
	return style == "gauntlet"


## Model-space rest frame of a held weapon in a hand (columns: weapon X, Y, Z) on a T-posed body
## facing +Z: +Y (the business end) leaves the fist on the thumb side, +Z (edge / striking face)
## points the way the knuckles do. `worn`: gauntlet convention (knuckles +Y, back of the hand +Z).
static func grip_basis_model(right: bool, worn: bool) -> Basis:
	var out := Vector3(-1, 0, 0) if right else Vector3(1, 0, 0)
	if worn:
		var z := Vector3(0, 1, 0)
		return Basis(out.cross(z), out, z)
	var yy := Vector3(0, 0, 1)
	return Basis(yy.cross(out), yy, out)


## Local transform for a weapon node parented to a BoneAttachment3D on a hand bone, for ANY rig:
## derived from the hand's global rest, so bone axes do not matter. `hand_bone` is the skeleton's
## bone index of RightHand / LeftHand. Worn weapons: put the file's `Gauntlet_R` node on the right hand
## and `Gauntlet_L` on the left (each is modelled for its own hand; nothing is mirrored).
static func weapon_attach_transform(skel: Skeleton3D, hand_bone: int, right: bool = true, worn: bool = false) -> Transform3D:
	var g := Transform3D.IDENTITY
	var b := hand_bone
	while b >= 0:
		g = skel.get_bone_rest(b) * g
		b = skel.get_bone_parent(b)
	var basis_model := grip_basis_model(right, worn)
	var s := g.origin.y / 1.215 if g.origin.y > 0.2 else 1.0     # body scale, from the wrist height
	var palm := Vector3((-0.082 if right else 0.082), -0.022, 0.006) * s
	var hand_rot := g.basis.orthonormalized()
	return Transform3D(hand_rot.inverse() * basis_model, hand_rot.inverse() * palm)


## Grip arc sample of a library clip at fraction `frac` (0..1): [grip position, weapon dir, edge dir]
## in model space on the reference body; multiply positions by (hips rest height / REF_HIP_HEIGHT).
## Returns an empty array when the clip has no arc metadata.
static func arc_at(anim: Animation, frac: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if anim == null or not anim.has_meta(&"od_grip"):
		return out
	var grip: PackedVector3Array = anim.get_meta(&"od_grip")
	var w: PackedVector3Array = anim.get_meta(&"od_w")
	var e: PackedVector3Array = anim.get_meta(&"od_e")
	var n := grip.size()
	if n < 2:
		return out
	var x := clampf(frac, 0.0, 1.0) * float(n - 1)
	var i := mini(int(floorf(x)), n - 2)
	var t := x - float(i)
	out.append(grip[i].lerp(grip[i + 1], t))
	out.append(w[i].slerp(w[i + 1], t).normalized() if w[i].dot(w[i + 1]) > -0.999 else w[i])
	out.append(e[i].slerp(e[i + 1], t).normalized() if e[i].dot(e[i + 1]) > -0.999 else e[i])
	return out
