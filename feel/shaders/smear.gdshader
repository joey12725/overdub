shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// OVERDUB combat feel: the weapon smear. The mesh is a ribbon swept along the weapon's real arc:
// UV.x = 0 at the weapon (head) .. 1 at the tail; UV.y = 0 at the inner edge .. 1 at the tip.
// Drawn like a cel smear frame: a flat bright shape with an ink edge, a dry-brush tail that breaks
// into streaks, and (fast tapes) discrete echo blades instead of one continuous sweep.
// look: 0 clean cut, 1 blunt mass, 2 whip line, 3 fist cone, 4 polearm sweep.

uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform float strength = 1.0;      // envelope 0..1
uniform float weight = 1.0;        // tape-speed weight: > 1 deep and heavy, < 1 thin
uniform float echoes = 0.0;        // > 0: number of discrete echo blades
uniform float look = 0.0;
uniform float seed = 0.0;

float hash(float n) { return fract(sin(n * 91.7 + seed * 13.1) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(hash(i), hash(i + 1.0), f); }

void fragment() {
	float u = UV.x;
	float v = UV.y;
	vec3 ink = vec3(0.07, 0.05, 0.08);
	// How far along the trail each radial band survives: jagged, longer at the tip.
	float band = n1(v * 23.0) * 0.55 + n1(v * 61.0) * 0.25;
	float reach = mix(0.35, 1.0, pow(v, 0.7)) * (0.55 + 0.45 * band) * strength;
	if (look > 0.5 && look < 1.5) { reach = (0.6 + 0.4 * band) * strength; }               // blunt: a slab
	if (look > 1.5 && look < 2.5) { reach = strength * (0.75 + 0.25 * band); }              // whip
	float body = step(u, reach);
	// Shape across the ribbon.
	float across = 1.0;
	if (look > 1.5 && look < 2.5) {
		// Whip: a thin line that wavers, thick only at the cracking tip.
		float c = 0.80 + 0.10 * sin(u * 14.0 + seed);
		across = step(abs(v - c), 0.035 + 0.11 * (1.0 - u) * (1.0 - u));
	} else if (look > 2.5 && look < 3.5) {
		// Fist: a cone converging on the knuckles.
		across = step(abs(v - 0.5), 0.5 * (1.0 - 0.75 * u));
	}
	// Echo blades (2x / 4x): the sweep is chopped into separate blade shapes.
	float chop = 1.0;
	if (echoes > 0.5) {
		float f = fract(u * (echoes + 0.5) / max(strength, 0.2) * 0.9);
		chop = step(f, 0.42) + step(u, 0.10);
		chop = min(chop, 1.0);
	}
	float m = body * across * chop;
	// Tone: white at the leading edge and the tip, tinted body, darker deep core on heavy tapes.
	vec3 col = mix(vec3(1.0), tint.rgb, smoothstep(0.02, 0.30, u));
	col = mix(col, vec3(1.0), step(0.90, v) * step(u, 0.5));
	if (weight > 1.15) {
		float core = step(abs(v - 0.55), 0.16) * step(0.12, u) * step(u, reach * 0.8);
		col = mix(col, mix(tint.rgb, ink, 0.55), core);
	}
	// Ink: the outer rim, the leading edge and the broken tail ends.
	float rim = step(0.965, v) + step(v, 0.03) * step(look, 0.5);
	float lead = step(u, 0.022);
	float tail = step(reach - 0.035, u);
	if (look > 1.5 && look < 2.5) { rim = 0.0; }
	col = mix(col, ink, clamp(rim + lead + tail * 0.9, 0.0, 1.0));
	float a = m * clamp(0.80 * weight, 0.45, 0.97);
	if (a < 0.02) { discard; }
	ALBEDO = col;
	ALPHA = a;
}
