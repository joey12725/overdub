class_name MVHelix
extends RefCounted
## "Constellation" (chapter 15): a voice traced on a pitch-class helix. MIDI pitch p sits at angle
## 2π·p/12 around the axis (pitch class 0 = C at the front) and at height (p - centre)/12 · rise, so
## every octave is one full turn and octave-equivalent notes line up vertically. Pure, static.
##
## project() turns the helix by `yaw` around its vertical axis, tilts it toward the viewer by `tilt`
## and returns an orthographic screen point (x right, y DOWN) plus depth (+1 front, -1 back) in z.


## Helix point (x, y up, z toward the viewer at yaw 0) of a (fractional) MIDI pitch.
static func point3(midi: float, radius: float = 1.0, rise: float = 1.0, centre: float = 60.0) -> Vector3:
	var a := TAU * midi / 12.0
	return Vector3(sin(a) * radius, (midi - centre) / 12.0 * rise, cos(a) * radius)


## Orthographic projection after yaw (around y) and tilt (around x). Returns (screen x, screen y with
## y down, depth -1..1 relative to radius 1).
static func project(p: Vector3, yaw: float, tilt: float) -> Vector3:
	var cy := cos(yaw)
	var sy := sin(yaw)
	var x := p.x * cy + p.z * sy
	var z := -p.x * sy + p.z * cy
	var ct := cos(tilt)
	var st := sin(tilt)
	var y := p.y * ct - z * st
	var d := p.y * st + z * ct
	return Vector3(x, -y, d)


## Screen point of a MIDI pitch (see project()); z is the depth.
static func screen(midi: float, yaw: float, tilt: float, radius: float = 1.0, rise: float = 1.0, centre: float = 60.0) -> Vector3:
	return project(point3(midi, radius, rise, centre), yaw, tilt)


## The rotation of project(): yaw around the vertical axis, then tilt around the screen x axis.
static func view_basis(yaw: float, tilt: float) -> Basis:
	return Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, yaw)


## project() for many points at once (one engine-side multiply plus a sign flip).
static func project_all(points: PackedVector3Array, yaw: float, tilt: float) -> PackedVector3Array:
	var out := Transform3D(view_basis(yaw, tilt), Vector3.ZERO) * points
	for i: int in out.size():
		out[i].y = -out[i].y
	return out


## Unrotated helix points from MIDI `lo` to `hi`, `per_turn` per octave (cache these; turn them
## with project_all each frame).
static func strand3(lo: float, hi: float, radius: float = 1.0, rise: float = 1.0, centre: float = 60.0, per_turn: int = 48) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := maxi(2, int(ceil((hi - lo) / 12.0 * per_turn)) + 1)
	out.resize(n)
	for i: int in n:
		out[i] = point3(lerpf(lo, hi, float(i) / float(n - 1)), radius, rise, centre)
	return out


## Polyline of the helix strand from MIDI `lo` to `hi`, `per_turn` points per octave. z of each point
## is its depth so drawers can dim the back half.
static func strand(lo: float, hi: float, yaw: float, tilt: float, radius: float = 1.0, rise: float = 1.0, centre: float = 60.0, per_turn: int = 48) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := maxi(2, int(ceil((hi - lo) / 12.0 * per_turn)) + 1)
	out.resize(n)
	for i: int in n:
		out[i] = screen(lerpf(lo, hi, float(i) / float(n - 1)), yaw, tilt, radius, rise, centre)
	return out
