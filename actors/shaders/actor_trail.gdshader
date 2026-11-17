// Melee swing trail (prototype swing.ts). Drawn on a sector whose UV.x is the angle fraction of
// the weapon's arc and UV.y the radius fraction (inner -> reach), so the trail doubles as an honest
// read of what the swing covers (WEAPON-04). Styled per weapon: 0 blade crescent, 1 blunt wedge,
// 2 whip lash, 3 gauntlet shock cone. preview = 1 draws only the outline of the hit volume
// (heavy wind-up: readable commitment).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

instance uniform vec4 trail_color : source_color = vec4(1.0);
instance uniform float progress = 0.0;
instance uniform float tail = 0.6;
instance uniform float style = 0.0;
instance uniform float preview = 0.0;

void fragment() {
	float x = UV.x;
	float r = UV.y;
	float op = trail_color.a;
	if (preview > 0.5) {
		float e = max(step(0.95, r), max(step(x, 0.015), step(0.985, x)));
		float dsh = step(0.5, fract(x * 18.0 - TIME * 2.0));
		float a = e * op * mix(dsh, 1.0, step(0.95, r));
		if (a <= 0.003) {
			discard;
		}
		ALBEDO = trail_color.rgb;
		ALPHA = a;
	} else {
		if (x > progress) {
			discard;
		}
		float tl = clamp(1.0 - (progress - x) / max(tail, 0.001), 0.0, 1.0);
		float shape = 0.0;
		float hot = 0.0;
		if (style < 0.5) {
			shape = smoothstep(0.45, 0.95, r) * (1.0 - smoothstep(0.975, 1.0, r));
			hot = smoothstep(0.86, 0.95, r) * (1.0 - smoothstep(0.95, 0.99, r));
		} else if (style < 1.5) {
			shape = smoothstep(0.1, 0.35, r) * (1.0 - smoothstep(0.96, 1.0, r));
			shape *= 0.75 + 0.25 * step(0.5, fract(r * 6.0));
			hot = smoothstep(0.85, 0.97, r) * 0.6;
		} else if (style < 2.5) {
			float w = 0.8 + 0.12 * sin(x * 26.0 - TIME * 18.0) * x;
			float d = abs(r - w);
			shape = 1.0 - smoothstep(0.015, 0.06, d);
			hot = 1.0 - smoothstep(0.0, 0.02, d);
		} else {
			float rings = 0.5 + 0.5 * sin(r * 28.0 - TIME * 26.0);
			shape = smoothstep(0.05, 0.3, r) * (1.0 - smoothstep(0.9, 1.0, r)) * (0.45 + 0.55 * rings);
			hot = (1.0 - smoothstep(0.0, 0.08, abs(x - progress))) * 0.8;
		}
		float a = shape * tl * op;
		if (a <= 0.003) {
			discard;
		}
		vec3 c = mix(trail_color.rgb, vec3(1.0), clamp(hot * tl + (1.0 - smoothstep(0.0, 0.05, progress - x)) * 0.5, 0.0, 1.0));
		ALBEDO = c;
		ALPHA = a;
	}
}
