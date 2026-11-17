// Music-linked rune strokes (port of prototype fx/music/ambient.ts updateRunes / updatePanels).
// Static geometry built once per level; this shader animates it from the music uniforms, so the
// CPU only sets a handful of uniforms per frame. Per vertex: UV.x = signed distance across the
// stroke, CUSTOM0 = (tape, phase, kind, glyph) with kind 0 = floor rune, 1 = rune-panel glyph.
// Visual only (MUSIC-12): nothing here collides or feeds back into gameplay.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

uniform vec4 levels = vec4(0.0);
uniform float beat = 0.0;
uniform float beat_pulse = 0.0;
uniform float bar_pulse = 0.0;
uniform float brightness = 1.0;
uniform vec3 rune_color : source_color = vec3(0.7, 0.4, 1.0);
uniform vec3 tape_a : source_color = vec3(1.0, 0.3, 0.43);
uniform vec3 tape_b : source_color = vec3(1.0, 0.82, 0.25);
uniform vec3 tape_c : source_color = vec3(0.24, 0.77, 1.0);
uniform vec3 tape_d : source_color = vec3(0.49, 1.0, 0.42);

varying vec4 v_col;

vec3 tape_rgb(int t) {
	if (t == 0) return tape_a;
	if (t == 1) return tape_b;
	if (t == 2) return tape_c;
	return tape_d;
}

float tape_level(int t) {
	if (t == 0) return levels.x;
	if (t == 1) return levels.y;
	if (t == 2) return levels.z;
	return levels.w;
}

void vertex() {
	int tape = clamp(int(CUSTOM0.x + 0.5), 0, 3);
	float phase = CUSTOM0.y;
	float kind = CUSTOM0.z;
	float glyph = CUSTOM0.w;
	float lvl = tape_level(tape);
	vec3 tc = tape_rgb(tape);
	if (kind < 0.5) {
		float wave = max(0.0, cos(phase - beat * PI * 0.5));
		float a = (0.1 + 0.5 * lvl + 0.12 * beat_pulse + 0.16 * wave * wave * wave) * brightness;
		float k = 0.35 * min(1.0, lvl * 1.5);
		v_col = vec4(mix(rune_color, tc, k), a);
	} else {
		float beat_in_bar = mod(floor(beat), 4.0);
		float lit = abs(beat_in_bar - glyph) < 0.5 ? beat_pulse * 0.35 : 0.0;
		float a = (0.16 + 0.55 * lvl + 0.25 * bar_pulse + lit) * brightness;
		v_col = vec4(tc * 0.5 + rune_color * 0.5, a);
	}
}

void fragment() {
	float e = abs(UV.x);
	float a = v_col.a * pow(max(0.0, 1.0 - e * e), 1.5);
	if (a < 0.003) {
		discard;
	}
	ALBEDO = mix(v_col.rgb, vec3(1.0), (1.0 - smoothstep(0.0, 0.45, e)) * 0.35);
	ALPHA = a;
}
