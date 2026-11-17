class_name ActorStyle
extends RefCounted
## State -> visual style for a self (UI-03, GHOST-01, GHOST-05, DESYNC-06; prototype style.ts).
##
## The readings that must never be confused with each other or with a living self:
##   REC_GHOST - live take after death: translucent cassette-coloured hologram, scanlines, broken halo.
##   GHOST     - played-back tape after death: faint grey hollow outline, trailing dust, inert.
##   DESYNCED  - alive but desynchronised projection: flickering, chromatic split, phased out,
##               tethered by a dashed line to the recovery spark.
##   ALIVE     - solid cel-shaded Moxie with a cassette-coloured ink outline.
## Layered on top (resolve()): dodge i-frames (afterimages + hard flicker between two
## translucencies, never fully solid) and a stopped tape (held pose, desaturated, greyed outline,
## pause glyph).
##
## Every (life, synced) combination has its own id. A death ghost does not become alive because a
## spark catches up (chapter 06 table), so the death reading dominates and the desync reading is
## layered on top of it rather than replacing it.

const ALIVE: StringName = &"alive"
const DESYNCED: StringName = &"desynced"
const REC_GHOST: StringName = &"recGhost"
const REC_GHOST_DESYNCED: StringName = &"recGhostDesynced"
const GHOST: StringName = &"ghost"
const GHOST_DESYNCED: StringName = &"ghostDesynced"
const ALL: Array[StringName] = [ALIVE, DESYNCED, REC_GHOST, REC_GHOST_DESYNCED, GHOST, GHOST_DESYNCED]

## How the body is drawn.
enum Body {
	## Opaque cel shading, coloured ink hull.
	SOLID,
	## Translucent cassette-tinted hologram with scanlines.
	HOLO,
	## Depth-only body: only the hull rim shows, so the silhouette is hollow.
	HOLLOW,
	## Translucent, desaturated, flickering body with red/cyan split echoes and sliced bands.
	PHASED,
}

enum Marker { NONE, BROKEN_HALO }
enum Trail { NONE, DUST, HOLO_BITS }

## Desaturation added on top of the style while a 'stop' tape holds its final pose.
const STOPPED_DESAT: float = 0.45
## Body opacity while dodge i-frames are active: visibly flickering between these two values.
const IFRAME_OPACITY_LOW: float = 0.3
const IFRAME_OPACITY_HIGH: float = 0.85
## Blue-grey outline for dead playback ghosts: reads as 'drained' on warm and dark floors alike.
const GHOST_GREY: Color = Color(0.49, 0.514, 0.58)
## Paper-white outline while dodge i-frames are active, so i-frames and desync (both translucent
## and flickering) differ by more than their flicker (docs/ACCESSIBILITY.md A5).
const IFRAME_HULL: Color = Color(1.0, 0.98, 0.94)
## Steady body opacity of dodge i-frames under "reduce flashing" (A6).
const IFRAME_OPACITY_STEADY: float = 0.6
## Lowest opacity of the floor ring and of the letter badge in any state (A2, A3).
const RING_FLOOR: float = 0.35
const BADGE_FLOOR: float = 0.6


class Params:
	extends RefCounted
	var body: int = Body.SOLID
	## Overall body opacity (solid ignores it unless dodging).
	var opacity: float = 1.0
	## 0 = full colour, 1 = greyscale.
	var desat: float = 0.0
	## Ink hull opacity and whether it uses the tape colour (else neutral grey).
	var hull_opacity: float = 1.0
	var hull_tape_color: bool = true
	## Hull thickness multiplier.
	var hull_scale: float = 1.0
	## Chromatic split echo strength 0..1.
	var chroma: float = 0.0
	## Visibility flicker strength 0..1.
	var flicker: float = 0.0
	## Floor ring opacity multiplier.
	var ring: float = 1.0
	## Headphone glow multiplier.
	var glow: float = 1.0
	var marker: int = Marker.NONE
	var trail: int = Trail.NONE
	## Draw the spark + dashed tether when a spark position exists.
	var tether: bool = false

	static func make(p_body: int, p_opacity: float, p_desat: float, p_hull_opacity: float, p_hull_tape: bool,
			p_hull_scale: float, p_chroma: float, p_flicker: float, p_ring: float, p_glow: float,
			p_marker: int, p_trail: int, p_tether: bool) -> Params:
		var p := Params.new()
		p.body = p_body
		p.opacity = p_opacity
		p.desat = p_desat
		p.hull_opacity = p_hull_opacity
		p.hull_tape_color = p_hull_tape
		p.hull_scale = p_hull_scale
		p.chroma = p_chroma
		p.flicker = p_flicker
		p.ring = p_ring
		p.glow = p_glow
		p.marker = p_marker
		p.trail = p_trail
		p.tether = p_tether
		return p

	## A comparable signature of every field (used by tests to prove the six styles differ).
	func signature() -> Array:
		return [body, opacity, desat, hull_opacity, hull_tape_color, hull_scale, chroma, flicker, ring, glow, marker, trail, tether]


## Final per-frame values after layering i-frames / stopped / flicker on a style.
class Resolved:
	extends RefCounted
	var style: StringName = ALIVE
	var body: int = Body.SOLID
	## True when the body must use the translucent material (everything except a plain solid body).
	var translucent: bool = false
	var opacity: float = 1.0
	var desat: float = 0.0
	var hull_color_is_tape: bool = true
	var hull_opacity: float = 1.0
	var hull_scale: float = 1.0
	var chroma: float = 0.0
	## Multiplier from the flicker (1 = steady).
	var flick: float = 1.0
	var stopped: bool = false
	var dodging: bool = false
	## Floor ring / letter badge opacity multipliers, floored so identity never fades out
	## (docs/ACCESSIBILITY.md A2, A3).
	var ring: float = 1.0


static var _table: Dictionary[StringName, Params] = {}


static func _ensure() -> void:
	if not _table.is_empty():
		return
	_table[ALIVE] = Params.make(Body.SOLID, 1.0, 0.0, 1.0, true, 1.0, 0.0, 0.0, 1.0, 1.0, Marker.NONE, Trail.NONE, false)
	_table[DESYNCED] = Params.make(Body.PHASED, 0.42, 0.55, 0.7, true, 0.8, 1.0, 0.6, 0.35, 0.5, Marker.NONE, Trail.NONE, true)
	_table[REC_GHOST] = Params.make(Body.HOLO, 0.55, 0.0, 0.95, true, 1.25, 0.0, 0.15, 0.6, 1.4, Marker.BROKEN_HALO, Trail.HOLO_BITS, false)
	_table[REC_GHOST_DESYNCED] = Params.make(Body.HOLO, 0.4, 0.0, 0.8, true, 1.1, 0.8, 0.55, 0.4, 1.0, Marker.BROKEN_HALO, Trail.HOLO_BITS, true)
	_table[GHOST] = Params.make(Body.HOLLOW, 0.0, 1.0, 0.6, false, 1.1, 0.0, 0.0, 0.18, 0.0, Marker.NONE, Trail.DUST, false)
	_table[GHOST_DESYNCED] = Params.make(Body.HOLLOW, 0.0, 1.0, 0.45, false, 1.1, 0.35, 0.3, 0.15, 0.0, Marker.NONE, Trail.DUST, true)


static func select(life: int, synced: bool) -> StringName:
	match life:
		OD.LifeState.REC_GHOST:
			return REC_GHOST if synced else REC_GHOST_DESYNCED
		OD.LifeState.GHOST:
			return GHOST if synced else GHOST_DESYNCED
		_:
			return ALIVE if synced else DESYNCED


static func params(id: StringName) -> Params:
	_ensure()
	return _table.get(id, _table[ALIVE])


## Layer i-frames, a stopped tape and the style's flicker onto a style, into `out`.
## `dying` forces the solid alive reading while the death transition plays.
## `steady` ("reduce flashing"): no flicker at all - styles hold their opacity and i-frames a steady
## translucency.
static func resolve(life: int, synced: bool, iframes: bool, stopped: bool, dying: bool, time: float, seed: float, out: Resolved, steady: bool = false) -> Resolved:
	var id: StringName = ALIVE if dying else select(life, synced)
	var st := params(id)
	out.style = id
	out.body = st.body
	out.stopped = stopped and not dying
	out.flick = 1.0 - st.flicker * (1.0 - ActorMath.flicker_value(time, seed)) if st.flicker > 0.0 and not steady else 1.0
	out.opacity = st.opacity * out.flick
	out.dodging = iframes and st.body == Body.SOLID
	if out.dodging:
		# Dodge i-frames: hard flicker between two translucencies (never fully solid).
		# (Unscaled time: every component of the flicker stays under the 10 Hz small-area limit.)
		if steady:
			out.opacity = IFRAME_OPACITY_STEADY
		else:
			out.opacity = IFRAME_OPACITY_HIGH if ActorMath.flicker_value(time, seed + 3.0) > 0.5 else IFRAME_OPACITY_LOW
	out.translucent = st.body != Body.SOLID or out.dodging
	out.desat = minf(1.0, st.desat + (STOPPED_DESAT if out.stopped else 0.0))
	out.hull_color_is_tape = st.hull_tape_color
	out.hull_opacity = st.hull_opacity * (1.0 if (st.body == Body.SOLID and not iframes) else out.flick)
	out.hull_scale = st.hull_scale
	out.chroma = st.chroma
	out.ring = maxf(RING_FLOOR, st.ring)
	return out


## The outline colour for a resolved style (cassette colour, or ghost grey; greyed when stopped).
static func hull_color(r: Resolved, tape_color: Color) -> Color:
	if r.dodging:
		return IFRAME_HULL
	var c := tape_color if r.hull_color_is_tape else GHOST_GREY
	if r.stopped:
		c = c.lerp(Color(0.5, 0.5, 0.5), 0.35)
	return c
