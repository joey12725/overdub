// Lissajous / rose floor sigils that morph with the chord (port of prototype fx/music/ambient.ts
// updateSigils). Each sigil mesh holds two pre-extruded figures: VERTEX = the previous chord's
// figure, CUSTOM0.xyz = the new chord's; `morph` eases between them (smoothstep) after a change.
// UV.x = signed distance across the line. The node's rotation turns the sigil slowly with the beat.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

instance uniform float morph = 1.0;
instance uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.3);

void vertex() {
	float e = morph * morph * (3.0 - 2.0 * morph);
	VERTEX = mix(VERTEX, CUSTOM0.xyz, e);
}

void fragment() {
	float d = abs(UV.x);
	float a = tint.a * pow(max(0.0, 1.0 - d * d), 1.5);
	if (a < 0.003) {
		discard;
	}
	vec3 c = mix(tint.rgb, vec3(1.0), (1.0 - smoothstep(0.0, 0.45, d)) * 0.35);
	ALBEDO = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	ALPHA = a;
}
