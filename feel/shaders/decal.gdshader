shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// OVERDUB combat feel: flat world-space marks. kind 0 = wall-slam crack (jagged ink cracks radiating
// from the centre, with a pale chipped core); kind 1 = skid mark (two dashed ink streaks along +U).
instance uniform float progress = 0.0;
instance uniform float kind = 0.0;
instance uniform float seed = 0.0;
instance uniform float power = 1.0;

float hash(float n) { return fract(sin(n * 127.1 + seed * 31.7) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(hash(i), hash(i + 1.0), f); }

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float p = clamp(progress, 0.0, 1.0);
	vec3 ink = vec3(0.06, 0.04, 0.07);
	vec3 col = ink;
	float a = 0.0;
	if (kind < 0.5) {
		float r = length(q);
		float ang = atan(q.y, q.x);
		float grow = 1.0 - pow(1.0 - clamp(p * 6.0, 0.0, 1.0), 3.0);
		float n = 7.0 + floor(power * 2.0);
		float sector = 6.2831853 / n;
		float id = floor((ang + 3.14159265) / sector);
		float ca = -3.14159265 + (id + 0.5 + (hash(id) - 0.5) * 0.6) * sector;
		// The crack wanders as it runs outward.
		float wander = (n1(r * 9.0 + id * 5.0) - 0.5) * 0.35;
		float da = ang - ca - wander;
		da = atan(sin(da), cos(da));
		float len = (0.45 + 0.5 * hash(id + 2.0)) * grow;
		float w = 0.035 * (1.0 - r / max(len, 0.01)) + 0.008;
		float crack = step(abs(da) * r, w) * step(r, len);
		// Concentric fracture at mid radius.
		float ring = step(abs(r - 0.32 * grow - 0.05 * n1(ang * 3.0)), 0.012) * step(0.4, hash(id + 9.0));
		float core = step(r, 0.13 * grow * (0.8 + 0.4 * n1(ang * 4.0)));
		a = max(crack, ring);
		if (core > 0.5) { col = vec3(0.92, 0.9, 0.86); a = 1.0; }
		a *= 1.0 - smoothstep(0.7, 1.0, p);
	} else {
		float along = UV.x;
		float lane = min(abs(q.y - 0.45), abs(q.y + 0.45));
		float dash = step(0.25, fract(along * 7.0 + seed)) ;
		float taper = 0.16 * (1.0 - along) + 0.04;
		a = step(lane, taper) * dash * step(along, clamp(p * 5.0, 0.0, 1.0)) * (1.0 - smoothstep(0.55, 1.0, p)) * 0.8;
	}
	if (a < 0.02) { discard; }
	ALBEDO = col;
	ALPHA = a;
}
