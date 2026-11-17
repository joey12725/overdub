shader_type spatial;
render_mode cull_back, ambient_light_disabled;
// Reference implementation of a wardrobe LOOK on one outfit material (docs/WARDROBE.md):
// a flat base colour plus an optional seamless pattern mask painted in a second colour.
// The wardrobe preview (art/wardrobe/shot_wardrobe.gd) renders with this shader; the actor
// shader of the game only needs the block marked WARDROBE PATTERN copied into it.

uniform vec3 albedo : source_color = vec3(1.0);
uniform float is_glow = 0.0;

// ── WARDROBE PATTERN ──────────────────────────────────────────────────────────────────────
uniform sampler2D pattern_tex : filter_linear_mipmap, repeat_enable, hint_default_black;
uniform vec3 pattern_col : source_color = vec3(0.0);
uniform float pattern_amt = 0.0;          // 0 = no pattern; look.pattern.strength
uniform float pattern_scale = 4.0;        // repeats per metre (look.pattern.scale)
uniform float pattern_screen = 1.0;       // 1 = screen-tone projection, 0 = the UV of the mesh
uniform float pattern_px_per_m = 200.0;   // screen mode: viewport pixels per world metre
varying vec2 pattern_anchor;

vec2 pattern_anchor_of(mat4 proj, mat4 view, vec3 node_pos) {
	// The pattern is pinned to the origin of the character on screen, so it travels with her
	// instead of sliding across her as she moves (a screen-tone, like printed manga cloth).
	vec4 c = proj * view * vec4(node_pos, 1.0);
	return c.xy / c.w * 0.5 + 0.5;
}

vec3 pattern_mix(vec3 base, vec2 uv, vec2 screen_uv, vec2 viewport) {
	if (pattern_amt <= 0.0) {
		return base;
	}
	vec2 p = uv * pattern_scale;
	if (pattern_screen > 0.5) {
		p = (screen_uv - pattern_anchor) * viewport / pattern_px_per_m * pattern_scale;
		p.y = -p.y;
	}
	return mix(base, pattern_col, texture(pattern_tex, p).r * pattern_amt);
}
// ──────────────────────────────────────────────────────────────────────────────────────────

void vertex() {
	pattern_anchor = pattern_anchor_of(PROJECTION_MATRIX, VIEW_MATRIX, NODE_POSITION_WORLD);
}

void fragment() {
	vec3 col = pattern_mix(albedo, UV, SCREEN_UV, VIEWPORT_SIZE);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = col * is_glow * 1.4;
}

void light() {
	// two-step cel shading, close to the toon ramp of the game
	float n = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.02, 0.04, n) * ATTENUATION;
	DIFFUSE_LIGHT += mix(vec3(0.55, 0.5, 0.68), vec3(1.0, 0.97, 0.92), lit) * (1.0 - is_glow);
}
