shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;
// OVERDUB combat feel: one camera-facing quad that draws a whole hand-drawn impact.
// kind 0 = hit burst (white core, tinted spikes, black ink splash behind, scaled by tier)
// kind 1 = clang (small, grey, a dull cross and a few drooping ticks: the hit that did nothing)
// kind 2 = dust puff (two-tone toon cloud)
// kind 3 = near-miss flourish (thin crescents sliding past)
// kind 4 = kill burst (hit burst + an expanding ink ring)
// Everything is a hard-edged shape (no soft gradients): anime ink, not a particle glow.

instance uniform float progress = 0.0;      // 0..1 life
instance uniform float kind = 0.0;
instance uniform float tier = 1.0;          // 0..4
instance uniform float angle = 0.0;         // screen-space direction of the hit, radians
instance uniform float seed = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.82, 0.25, 1.0);
instance uniform float lines = 8.0;

varying vec2 uv;

void vertex() {
	vec4 c = VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float s = length(MODEL_MATRIX[0].xyz);
	uv = VERTEX.xy * 2.0;
	POSITION = PROJECTION_MATRIX * (c + vec4(VERTEX.xy * s, 0.0, 0.0));
}

float hash(float n) { return fract(sin(n * 127.1 + seed * 31.7) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.3) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Spikes: n wedges at jittered angles; returns 1 inside a wedge. bias > 0 lengthens those along +x.
float spikes(vec2 p, float n, float r0, float r1, float width, float bias) {
	float r = length(p);
	float a = atan(p.y, p.x);
	float m = 0.0;
	float sector = 6.2831853 / n;
	float idx = floor((a + 3.14159265) / sector);
	for (float k = -1.0; k <= 1.0; k += 1.0) {
		float id = mod(idx + k + n, n);
		float ca = -3.14159265 + (id + 0.5 + (hash(id) - 0.5) * 0.7) * sector;
		float da = a - ca;
		da = atan(sin(da), cos(da));
		float len = mix(0.45, 1.0, hash(id + 7.0));
		len *= 1.0 + bias * max(0.0, cos(ca));
		float o = r0 + (r1 - r0) * len;
		float t = clamp((r - r0) / max(o - r0, 0.001), 0.0, 1.0);
		float w = width * (1.0 - t) * (0.6 + 0.8 * hash(id + 3.0));
		float inside = step(abs(da) * r, w) * step(r0, r) * step(r, o);
		m = max(m, inside);
	}
	return m;
}

void fragment() {
	float p = clamp(progress, 0.0, 1.0);
	float ca = cos(-angle); float sa = sin(-angle);
	vec2 q = vec2(uv.x * ca - uv.y * sa, uv.x * sa + uv.y * ca);   // +x = along the hit
	float r = length(q);
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	vec3 ink = vec3(0.07, 0.05, 0.08);
	if (kind < 0.5 || kind > 3.5) {
		// ── hit / kill burst ──
		float tq = clamp(tier / 4.0, 0.0, 1.0);
		float e = 1.0 - pow(1.0 - p, 3.0);                    // fast out
		// Ink splash: a blobby ring thrown along the hit, drawn first (behind).
		vec2 sq = q - vec2(0.20 + 0.34 * e, 0.0);
		float sa2 = atan(sq.y, sq.x);
		float blob = 0.26 + 0.33 * e + 0.16 * vnoise(vec2(sa2 * 2.5, seed)) + 0.10 * vnoise(vec2(sa2 * 7.0, 3.0 + seed));
		blob *= mix(0.55, 1.0, tq);
		float hole = blob * smoothstep(0.25, 0.95, p) * 1.05;
		float splash = step(length(sq), blob) * step(hole, length(sq)) * step(p, 0.92);
		// Droplets flung further along the hit.
		vec2 dg = floor(q * 7.0 + vec2(seed));
		float drop = step(0.86 - 0.10 * tq, hash2(dg)) * step(length(fract(q * 7.0 + vec2(seed)) - 0.5), 0.26 * (1.0 - p));
		drop *= step(blob * 0.9, r) * step(r, blob + 0.35 * e) * step(-0.2, q.x);
		float inkm = max(splash, drop);
		// Impact lines: long thin wedges, strongest along the hit.
		float r0 = 0.16 + 0.55 * e;
		float r1 = r0 + (0.55 + 0.25 * tq) * (1.0 - 0.75 * p);
		float sp = spikes(q, lines, r0, min(r1, 0.98), 0.085 * (1.0 - 0.6 * p), 0.45);
		float spo = spikes(q, lines, r0 - 0.03, min(r1 + 0.04, 1.0), 0.13 * (1.0 - 0.6 * p), 0.45);
		// Core star: a hard white flash for the first third.
		float core_r = (0.30 + 0.16 * tq) * (1.0 - smoothstep(0.0, 0.42, p)) * (0.75 + 0.25 * cos(atan(q.y, q.x) * 4.0 + seed));
		float core = step(r, core_r);
		float core_o = step(r, core_r + 0.05) * step(p, 0.40);
		// Compose: ink behind, tinted outline, white on top.
		col = ink; alpha = inkm * 0.85;
		if (spo > 0.5 || core_o > 0.5) { col = mix(ink, tint.rgb, 0.85); alpha = 1.0; }
		if (sp > 0.5) { col = mix(vec3(1.0), tint.rgb, 0.25 + 0.5 * p); alpha = 1.0; }
		if (core > 0.5) { col = vec3(1.0); alpha = 1.0; }
		if (kind > 3.5) {
			// Kill: a thick ink ring racing out, with a tinted inner line.
			float rr = 0.25 + 0.72 * e;
			float th = 0.075 * (1.0 - p);
			if (abs(r - rr) < th) { col = ink; alpha = 1.0; }
			if (abs(r - rr + th * 0.6) < th * 0.35) { col = tint.rgb; alpha = 1.0; }
		}
		alpha *= step(p, 0.985);
	} else if (kind < 1.5) {
		// ── clang: grey, small, wrong ──
		float e = 1.0 - pow(1.0 - p, 2.0);
		vec3 grey = vec3(0.56, 0.57, 0.63);
		// A dull four-point tick that barely opens, and droops (gravity) as it dies.
		vec2 d = q; d.y += 0.22 * p * p;
		float arm = 0.20 + 0.30 * e;
		float th = 0.07 * (1.0 - 0.8 * p);
		float cross_m = max(step(abs(d.x), arm) * step(abs(d.y), th), step(abs(d.y), arm * 0.7) * step(abs(d.x), th));
		float cross_o = max(step(abs(d.x), arm + 0.05) * step(abs(d.y), th + 0.05), step(abs(d.y), arm * 0.7 + 0.05) * step(abs(d.x), th + 0.05));
		// Three short falling ticks.
		float ticks = 0.0;
		for (float k = 0.0; k < 3.0; k += 1.0) {
			float a = (hash(k) - 0.5) * 2.4;
			vec2 c = vec2(cos(a), sin(a)) * (0.30 + 0.35 * e) + vec2(0.0, -0.55 * p * p);
			vec2 dd = q - c;
			ticks = max(ticks, step(abs(dd.x), 0.035) * step(abs(dd.y), 0.11 * (1.0 - p)));
		}
		// A broken ring that does not expand: the energy went nowhere.
		float ring_o = step(abs(r - 0.42), 0.05) * step(0.33, fract(atan(q.y, q.x) * 1.9 + seed)) * step(p, 0.5);
		float ring = step(abs(r - 0.42), 0.022) * step(0.35, fract(atan(q.y, q.x) * 1.9 + seed)) * step(p, 0.5);
		if (cross_o > 0.5 || ring_o > 0.5) { col = ink; alpha = 1.0; }
		if (cross_m > 0.5 || ticks > 0.5 || ring > 0.5) { col = grey; alpha = 1.0; }
		alpha *= step(p, 0.97);
	} else if (kind < 2.5) {
		// ── dust puff: lumpy two-tone cloud ──
		float e = 1.0 - pow(1.0 - p, 2.0);
		float a = atan(uv.y, uv.x);
		float rad = (0.42 + 0.40 * e) * (0.78 + 0.22 * vnoise(vec2(a * 2.2, seed * 3.0)) + 0.10 * sin(a * 5.0 + seed));
		float inner = rad * (0.35 + 0.75 * smoothstep(0.3, 1.0, p));
		float body = step(r, rad) * step(inner * step(0.45, p), r);
		float rim = step(r, rad) * step(rad - 0.07, r);
		vec3 light = mix(tint.rgb, vec3(1.0), 0.55);
		col = mix(light, tint.rgb * 0.7, step(0.0, -uv.y - 0.15 + 0.2 * vnoise(uv * 4.0)));
		if (rim > 0.5) { col = ink; }
		alpha = body * (1.0 - smoothstep(0.75, 1.0, p)) * 0.95;
	} else {
		// ── near-miss: two thin crescents slipping past along the dodge ──
		float e = 1.0 - pow(1.0 - p, 3.0);
		float m = 0.0;
		for (float k = 0.0; k < 2.0; k += 1.0) {
			vec2 c = vec2(-0.55 + 0.25 * k, (k - 0.5) * 0.5);
			vec2 d = q - vec2(e * 0.5 - 0.2, 0.0);
			float rr = length(d - c);
			float arc = step(abs(rr - 0.62), 0.022 * (1.0 - p)) * step(0.0, (d - c).x) * step(abs((d - c).y), 0.34);
			m = max(m, arc);
		}
		// Speed ticks.
		float tk = step(abs(fract(q.y * 6.0 + seed) - 0.5), 0.05) * step(abs(q.x + 0.6 - 1.4 * e), 0.16) * step(abs(q.y), 0.55);
		tk *= step(0.5, hash(floor(q.y * 6.0 + seed)));
		col = mix(vec3(1.0), tint.rgb, 0.35);
		alpha = max(m, tk) * step(p, 0.97);
	}
	if (alpha < 0.02) { discard; }
	ALBEDO = col;
	ALPHA = alpha;
}
