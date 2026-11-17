// OVERDUB procedural environment surface: the same cel lighting as toon.gdshader plus world-space
// patterns (masonry, riveted plates, grates, rune inscriptions, hazard paint, rock strata), so the
// kit's procedural pieces get the material families of the R03 / R04 boards without textures and
// neighbouring tiles line up. Top faces (normal.y > 0.5) and side faces each pick a pattern.
// Uniforms: shaders/README.md.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/toon_lighting.gdshaderinc"

// Patterns: 0 plain, 1 masonry slabs / brick courses, 2 riveted metal plates, 3 grate,
// 4 rune-inscribed plate (emissive glyphs), 5 hazard stripes, 6 overgrown slabs, 7 rock strata,
// 8 inscribed metal wall panels (etched rune columns), 9 neon-seam floor plate.
uniform int top_pattern = 1;
uniform int side_pattern = 1;
uniform vec4 top_color : source_color = vec4(0.86, 0.73, 0.63, 1.0);
uniform vec4 side_color : source_color = vec4(0.73, 0.57, 0.47, 1.0);
// Grout, seams, grate holes, stripe dark.
uniform vec4 line_color : source_color = vec4(0.36, 0.26, 0.20, 1.0);
// Moss / rust / stripe paint.
uniform vec4 accent_color : source_color = vec4(0.58, 0.76, 0.17, 1.0);
// Inscription glow (patterns 4, 8, 9).
uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.48, 1.0);
uniform float glow_energy = 0.0;
// Fraction of plates whose inscription is lit (pattern 8 side walls).
uniform float glow_share : hint_range(0.0, 1.0) = 0.35;
// Dirt / wear darkening amount.
uniform float wear : hint_range(0.0, 1.0) = 0.35;
// Rust / moss blotch amount on top of the base (0 = none).
uniform float blotch : hint_range(0.0, 1.0) = 0.2;
// Rock strata (pattern 7): colour at Y = 0 fading to cliff_deep at Y = -cliff_depth.
uniform vec4 cliff_deep : source_color = vec4(0.16, 0.12, 0.11, 1.0);
uniform float cliff_depth = 2.2;
// Seed so two levels never share the exact same slab layout.
uniform float seed = 0.0;
uniform float vertex_color_mix : hint_range(0.0, 1.0) = 1.0;

instance uniform vec4 instance_tint : source_color, instance_index(0) = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 instance_emission : source_color, instance_index(1) = vec4(0.0, 0.0, 0.0, 0.0);

varying vec3 od_world_normal;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed * 0.137);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1.0, 0.0));
	float c = h21(i + vec2(0.0, 1.0));
	float d = h21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.7 + 1.3) * 0.1;
}

// 0 inside a line of half-width w around the cell border of a unit grid, 1 elsewhere.
float grid_line(vec2 p, float w) {
	vec2 f = fract(p);
	vec2 d = min(f, 1.0 - f);
	return smoothstep(w * 0.6, w, min(d.x, d.y));
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Rune glyph for a cell: 3-4 strokes between points of a 3x3 lattice, hashed by cell id.
float rune(vec2 uv, vec2 cell, float width) {
	float d = 10.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float ha = h21(cell + vec2(fi * 3.1, 1.7));
		float hb = h21(cell + vec2(fi * 5.3, 9.2));
		if (i == 3 && h21(cell + 4.4) < 0.5) {
			break;
		}
		vec2 a = vec2(floor(ha * 3.0), floor(fract(ha * 7.0) * 3.0)) * 0.5;
		vec2 b = vec2(floor(hb * 3.0), floor(fract(hb * 7.0) * 3.0)) * 0.5;
		if (distance(a, b) < 0.1) {
			b = vec2(1.0) - a;
		}
		d = min(d, seg(uv, a, b));
	}
	// Ring around the glyph on some cells.
	if (h21(cell + 2.2) < 0.35) {
		d = min(d, abs(length(uv - 0.5) - 0.62));
	}
	return 1.0 - smoothstep(width * 0.6, width, d);
}

struct Surf {
	vec3 col;
	float glow;
};

// p: 2D coordinates on the face in world units; up: true for top faces.
Surf pattern(int kind, vec2 p, vec3 base, bool top, float wy) {
	Surf s;
	s.col = base;
	s.glow = 0.0;
	if (kind == 1 || kind == 6) {
		if (top) {
			// Each tile is one slab, two halves or four quarters.
			vec2 tile = floor(p);
			float h = h21(tile);
			vec2 q = fract(p);
			vec2 sub = h < 0.45 ? vec2(1.0) : (h < 0.8 ? (h < 0.62 ? vec2(2.0, 1.0) : vec2(1.0, 2.0)) : vec2(2.0));
			vec2 sp = q * sub;
			vec2 sc = floor(sp) + tile * 4.0;
			float g = grid_line(sp / 1.0, 0.045 * max(sub.x, sub.y));
			float tone = 0.9 + 0.16 * h21(sc + 3.0);
			s.col = mix(line_color.rgb, base * tone, g);
			// Chips along slab edges.
			float chip = step(0.86, vnoise(p * 9.0)) * (1.0 - g * 0.6);
			s.col = mix(s.col, line_color.rgb * 1.2, chip * 0.5);
		} else {
			// Brick courses 0.25 high, staggered.
			float row = floor(wy / 0.25);
			vec2 bp = vec2(p.x / 0.5 + 0.5 * mod(row, 2.0), wy / 0.25);
			float g = grid_line(bp, 0.07);
			float tone = 0.88 + 0.18 * h21(floor(bp) + 11.0);
			s.col = mix(line_color.rgb, base * tone, g);
		}
		if (kind == 6) {
			float moss = smoothstep(0.52, 0.62, fbm(p * 2.3 + 5.0));
			s.col = mix(s.col, accent_color.rgb * (0.85 + 0.2 * vnoise(p * 11.0)), moss);
		}
	} else if (kind == 2 || kind == 4 || kind == 8 || kind == 9) {
		vec2 pp = top ? p : vec2(p.x, wy);
		vec2 cell = floor(pp);
		vec2 q = fract(pp);
		float g = grid_line(pp, 0.035);
		float tone = 0.92 + 0.1 * h21(cell + 7.0);
		s.col = mix(line_color.rgb, base * tone, g);
		// Bevel highlight on the upper-left edges of each plate.
		s.col *= 1.0 + 0.08 * (1.0 - smoothstep(0.03, 0.09, min(q.x, 1.0 - q.y)));
		// Rivets in the corners.
		vec2 rq = abs(q - 0.5);
		float rv = 1.0 - smoothstep(0.025, 0.04, length(rq - vec2(0.41)));
		s.col = mix(s.col, base * 1.25, rv);
		if (kind == 4) {
			float r = rune((q - 0.18) / 0.64, cell, 0.07);
			s.col = mix(s.col, line_color.rgb * 0.8, r);
			s.glow = r;
		} else if (kind == 8 && !top) {
			// Etched columns of glyphs on the wall plates; a share of plates is lit.
			float lit = step(h21(cell + 19.0), glow_share);
			vec2 gq = vec2((q.x - 0.32) / 0.36, fract(q.y * 2.0));
			float r = gq.x > 0.0 && gq.x < 1.0 ? rune(gq * 1.1 - 0.05, cell * 2.0 + floor(q.y * 2.0), 0.09) : 0.0;
			s.col = mix(s.col, line_color.rgb * 0.7, r);
			s.glow = r * lit;
		} else if (kind == 2) {
			// Faint etched lines.
			float e = 1.0 - smoothstep(0.008, 0.016, abs(q.y - 0.5 - 0.3 * (h21(cell) - 0.5)));
			s.col = mix(s.col, line_color.rgb * 1.1, e * step(0.6, h21(cell + 1.0)) * 0.6);
		} else if (kind == 9) {
			float seam = 1.0 - smoothstep(0.012, 0.03, abs(q.x - 0.5));
			s.glow = seam * step(0.55, h21(cell + 4.0));
		}
	} else if (kind == 3) {
		vec2 q = fract(p);
		vec2 gp = q * 7.0;
		float bars = grid_line(gp, 0.16);
		float frame = step(0.07, min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y)));
		// Holes are dark; the depth below shows faintly.
		s.col = mix(base, line_color.rgb * 0.35, bars * frame);
	} else if (kind == 5) {
		vec2 pp = top ? p : vec2(p.x, wy);
		float st = step(0.5, fract((pp.x + pp.y) * 2.2));
		s.col = mix(accent_color.rgb, line_color.rgb, st);
		s.col *= 0.92 + 0.12 * vnoise(pp * 6.0);
	} else if (kind == 7) {
		// Chunky strata that fade into the background with depth (floating diorama).
		float t = clamp(-wy / max(cliff_depth, 0.01), 0.0, 1.0);
		float strata = step(0.5, fract(wy * 2.6 + 0.4 * vnoise(vec2(p.x * 1.3, wy))));
		vec3 c = base * (0.88 + 0.16 * strata) * (0.9 + 0.2 * vnoise(vec2(p.x * 3.0, wy * 5.0)));
		float crack = 1.0 - smoothstep(0.02, 0.05, abs(fract(p.x * 0.9 + 0.3 * vnoise(vec2(p.x, wy * 2.0))) - 0.5));
		c = mix(c, line_color.rgb, crack * 0.6);
		s.col = mix(c, cliff_deep.rgb, pow(t, 1.15));
	}
	return s;
}

void vertex() {
	od_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	od_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 wp = od_world_pos;
	vec3 n = od_world_normal;
	bool top = n.y > 0.5;
	vec2 p;
	if (top) {
		p = wp.xz;
	} else if (abs(n.x) > abs(n.z)) {
		p = vec2(wp.z, wp.y);
	} else {
		p = vec2(wp.x, wp.y);
	}
	vec3 base = (top ? top_color.rgb : side_color.rgb);
	Surf s = pattern(top ? top_pattern : side_pattern, p, base, top, wp.y);
	vec3 col = s.col;
	// Wear: low-frequency dirt plus rust / moss blotches.
	float dirt = fbm(wp.xz * 0.9 + wp.y * 0.7);
	col *= 1.0 - wear * 0.22 * smoothstep(0.35, 0.8, dirt);
	if (blotch > 0.0) {
		float b = smoothstep(0.62, 0.7, fbm(wp.xz * 1.7 + vec2(wp.y * 1.3, 3.0)));
		col = mix(col, accent_color.rgb * 0.9, b * blotch);
	}
	col *= mix(vec3(1.0), COLOR.rgb, vertex_color_mix) * instance_tint.rgb;
	ALBEDO = col;
	EMISSION = glow_color.rgb * glow_energy * s.glow + instance_emission.rgb * instance_emission.a;
}
