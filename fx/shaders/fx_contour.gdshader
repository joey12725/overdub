// "Stack"-style four-layer contour strips (port of prototype fx/music/ambient.ts updateStrip /
// updateScreens): each cassette layer's recent pitch against a shared playhead. The geometry is a
// fixed index grid; the vertex shader reads the pitch / level history from a small data texture
// (x = ring slot, y = tape; r = pitch 0..1, g = level 0..1), so the CPU only writes one texel row
// per history sample. Per vertex: VERTEX = (sample index i, side -1/+1, tape), UV.x = side.
//
// mode 0 (edge strip):  u = s0 + (play - s0) * (i + 1 - frac) / samples,  v = y0 + p * hgt + tape * 0.03
// mode 1 (wave screen): u = -hw + 2 hw i / (samples - 1),                 v = cy + (p - 0.5) * amp + (tape - 1.5) * 0.025
// world = origin + along * u + up * v. Visual only (MUSIC-12).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform sampler2D history : filter_nearest, repeat_disable;
uniform int history_len = 128;
uniform int head = 0;
uniform int count = 0;
uniform float frac = 0.0;
uniform float brightness = 1.0;
uniform vec3 tape_a : source_color = vec3(1.0, 0.3, 0.43);
uniform vec3 tape_b : source_color = vec3(1.0, 0.82, 0.25);
uniform vec3 tape_c : source_color = vec3(0.24, 0.77, 1.0);
uniform vec3 tape_d : source_color = vec3(0.49, 1.0, 0.42);

instance uniform vec3 origin = vec3(0.0);
instance uniform vec3 along = vec3(1.0, 0.0, 0.0);
instance uniform vec3 up = vec3(0.0, 1.0, 0.0);
// lay, mode 0: (s0, play, y0, hgt); mode 1: (hw, cy, amp, 0)
instance uniform vec4 lay = vec4(0.4, 10.0, 1.75, 0.95);
instance uniform float mode = 0.0;
instance uniform float samples = 128.0;
instance uniform float width = 0.06;

varying vec4 v_col;

vec3 tape_rgb(int t) {
	if (t == 0) return tape_a;
	if (t == 1) return tape_b;
	if (t == 2) return tape_c;
	return tape_d;
}

// (pitch, level, valid) of the sample `k` steps back from the newest.
vec3 sample_back(float k, int tape) {
	int ki = int(k + 0.5);
	if (ki < 0 || ki >= count) {
		return vec3(0.5, 0.0, 0.0);
	}
	int h = (head - 1 - ki + history_len * 2) % history_len;
	vec2 pl = texelFetch(history, ivec2(h, tape), 0).rg;
	return vec3(clamp(pl.x, 0.0, 1.0), clamp(pl.y, 0.0, 1.0), 1.0);
}

vec2 uv_of(float i, int tape) {
	float S = samples;
	vec3 s = sample_back(S - 1.0 - clamp(i, 0.0, S - 1.0), tape);
	if (mode < 0.5) {
		float s0 = lay.x;
		float play = lay.y;
		float u = s0 + (play - s0) * (i + 1.0 - frac) / S;
		return vec2(max(s0, u), lay.z + s.x * lay.w + float(tape) * 0.03);
	}
	float hw = lay.x;
	float u = -hw + 2.0 * hw * i / (S - 1.0);
	return vec2(u, lay.y + (s.x - 0.5) * lay.z + (float(tape) - 1.5) * 0.025);
}

void vertex() {
	float i = VERTEX.x;
	float side = VERTEX.y;
	int tape = clamp(int(VERTEX.z + 0.5), 0, 3);
	float S = samples;
	vec2 c = uv_of(i, tape);
	vec2 a = uv_of(max(0.0, i - 1.0), tape);
	vec2 b = uv_of(min(S - 1.0, i + 1.0), tape);
	vec2 t2 = b - a;
	float L = length(t2);
	t2 = L > 1e-5 ? t2 / L : vec2(1.0, 0.0);
	vec2 n2 = vec2(-t2.y, t2.x);
	vec2 o = c + n2 * side * width * 0.5;
	vec3 world = origin + along * o.x + up * o.y;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	vec3 s = sample_back(S - 1.0 - i, tape);
	float alpha;
	if (mode < 0.5) {
		// Older samples fade toward the left like ink drying.
		float age = i / (S - 1.0);
		alpha = (0.06 + 0.75 * s.y) * (0.25 + 0.75 * age) * brightness;
	} else {
		alpha = (0.08 + 0.8 * s.y) * brightness;
	}
	v_col = vec4(tape_rgb(tape), alpha);
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
