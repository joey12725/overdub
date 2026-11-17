// Music visualiser surface (musicviz/, MUSIC-12): shows an MVCanvas texture (premultiplied colour)
// on a prop screen, a wall frieze or a floor inscription. Unshaded; bright parts are boosted by
// `energy` so they bloom through the WorldEnvironment glow. `backdrop` (alpha 1) turns the surface
// into an opaque display glass (wave_screen); alpha 0 lets the stone / metal show through (decals).
// `uv_rect` selects an atlas cell (offset.xy, size.zw). Visual only: no depth write, no shadows.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_premul_alpha;

// The canvas texture is sRGB (source_color): read as linear it would wash every colour pale.
uniform sampler2D tex : source_color, filter_linear, repeat_disable;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float energy = 1.8;
uniform vec4 backdrop : source_color = vec4(0.0, 0.0, 0.0, 0.0);
// Overall fade (0..1).
uniform float intensity = 1.0;
// Flip v (some meshes map v bottom-up).
uniform bool flip_v = false;
// Soft round mask for floor discs (1 = on).
uniform float disc_mask = 0.0;

void fragment() {
	vec2 uv0 = UV;
	if (flip_v) {
		uv0.y = 1.0 - uv0.y;
	}
	vec2 uv = uv_rect.xy + uv0 * uv_rect.zw;
	vec4 c = texture(tex, uv);
	float m = 1.0;
	if (disc_mask > 0.5) {
		float r = length(uv0 - vec2(0.5)) * 2.0;
		m = 1.0 - smoothstep(0.96, 1.0, r);
	}
	c *= m;
	float lum = max(c.r, max(c.g, c.b));
	// Premultiplied: rgb already carries alpha. Boost only the bright cores so ink stays ink.
	float boost = mix(1.0, energy, smoothstep(0.25, 0.9, lum));
	vec3 rgb = c.rgb * boost + backdrop.rgb * backdrop.a * (1.0 - c.a);
	float a = c.a + backdrop.a * (1.0 - c.a);
	ALBEDO = rgb * intensity;
	ALPHA = clamp(a * intensity, 0.0, 1.0);
}
