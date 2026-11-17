// Procedural effect sprites (port of prototype/src/render/fx/gpu/spriteMesh.ts). One MultiMesh of
// unit quads; every shape is drawn analytically, so no texture is needed. Per-instance data rides
// in the instance transform (FxSpritePool.write_instances), read back as MODEL_MATRIX columns:
//   [0] = dir.xyz            [1] = stretch, size, param
//   [2] = rot, t, shape + 32 * mode       [3] = position
// The MultiMeshInstance3D is top_level at the identity, so MODEL_MATRIX is exactly that data.

varying vec2 v_uv;
varying float v_shape;
varying float v_param;
varying float v_t;
varying float v_mode;

// Soft-particle fade: billboards and streaks dissolve where they meet the floor or a wall instead of
// being cut by a hard line (big impact glows straddle the floor plane). World units.
uniform sampler2D fx_depth : hint_depth_texture, filter_nearest;
uniform float soft_fade = 0.45;

vec3 fx_srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	vec4 c0 = MODEL_MATRIX[0];
	vec4 c1 = MODEL_MATRIX[1];
	vec4 c2 = MODEL_MATRIX[2];
	vec3 pos = MODEL_MATRIX[3].xyz;
	float shape_mode = c2.z;
	float mode = floor(shape_mode / 32.0 + 0.001);
	v_shape = shape_mode - mode * 32.0;
	v_param = c1.z;
	v_t = c2.y;
	v_mode = mode;
	float rot = c2.x;
	float s = c1.y;
	vec2 c = VERTEX.xy * 2.0;
	v_uv = c;
	float cr = cos(rot);
	float sr = sin(rot);
	vec2 rc = vec2(c.x * cr - c.y * sr, c.x * sr + c.y * cr);
	vec3 mv;
	if (mode < 0.5) {
		// Billboard: offset in view space.
		mv = (VIEW_MATRIX * vec4(pos, 1.0)).xyz;
		mv.xy += rc * s;
	} else if (mode < 1.5) {
		// Floor: local +x is the sim heading (scene X toward Z).
		vec3 wp = pos + vec3(rc.x * s, 0.0, rc.y * s);
		mv = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	} else {
		// Streak: camera-facing quad stretched along a world direction.
		vec3 a = (VIEW_MATRIX * vec4(pos, 1.0)).xyz;
		vec3 b = (VIEW_MATRIX * vec4(pos + c0.xyz, 1.0)).xyz;
		vec2 d = b.xy - a.xy;
		float L = length(d);
		d = L > 1e-5 ? d / L : vec2(1.0, 0.0);
		vec2 n = vec2(-d.y, d.x);
		mv = a;
		mv.xy += d * c.x * s * c1.x + n * c.y * s;
	}
	VERTEX = mv;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

float ring_mask(float r, float rad, float th) {
	return smoothstep(th, th * 0.35, abs(r - rad));
}

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void fragment() {
	vec2 p = v_uv;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float a = 0.0;
	float core = 0.0;
	vec3 col = COLOR.rgb;
	float s = floor(v_shape + 0.5);

	if (s < 0.5) { // glow
		a = exp(-r * r * 3.5) * (1.0 - smoothstep(0.8, 1.0, r));
		core = exp(-r * r * 14.0);
	} else if (s < 1.5) { // 4-point spark star
		float star = 0.05 / (abs(p.x * p.y) * 6.0 + 0.05);
		a = clamp(star * (1.0 - r), 0.0, 1.0);
		core = exp(-r * r * 20.0);
	} else if (s < 2.5) { // streak (tapered diamond)
		float d = 1.0 - abs(p.x) - abs(p.y) * 1.2;
		a = smoothstep(0.0, 0.35, d);
		core = smoothstep(0.4, 0.9, d);
	} else if (s < 3.5) { // ring
		float th = max(v_param, 0.02);
		a = ring_mask(r, 1.0 - th, th);
		core = a * 0.4;
	} else if (s < 4.5) { // debris chunk with an ink border
		float m = max(abs(p.x), abs(p.y));
		a = 1.0 - smoothstep(0.78, 0.84, m);
		col *= mix(1.0, 0.18, smoothstep(0.58, 0.66, m));
	} else if (s < 5.5) { // chevron pointing +x
		float d = abs(p.x - 0.15 + abs(p.y) * 1.05);
		a = (1.0 - smoothstep(0.18, 0.26, d)) * (1.0 - smoothstep(0.78, 0.86, abs(p.y)));
		core = a * 0.3;
	} else if (s < 6.5) { // ink splat
		float seed = v_param;
		float rr = 0.62 + 0.14 * sin(ang * 5.0 + seed) + 0.08 * sin(ang * 11.0 + seed * 2.3) + 0.05 * sin(ang * 17.0 + seed * 4.1);
		a = 1.0 - smoothstep(rr - 0.04, rr, r);
		for (int k = 0; k < 4; k++) {
			float fk = float(k);
			float da = hash11(seed + fk) * 6.2831;
			float dr = 0.78 + 0.16 * hash11(seed * 1.7 + fk);
			vec2 dc = vec2(cos(da), sin(da)) * dr;
			float ds = 0.05 + 0.06 * hash11(seed * 3.1 + fk);
			a = max(a, 1.0 - smoothstep(ds - 0.02, ds, length(p - dc)));
		}
	} else if (s < 7.5) { // arc: crescent around +x with half-width v_param (radians)
		float hw = max(v_param, 0.05);
		float along = 1.0 - smoothstep(hw * 0.7, hw, abs(ang));
		float taper = 1.0 - abs(ang) / hw;
		float th = 0.08 + 0.12 * clamp(taper, 0.0, 1.0);
		a = ring_mask(r, 0.8, th) * along;
		a = max(a, along * smoothstep(0.82, 0.3, r) * 0.18 * smoothstep(0.2, 0.8, r));
		core = a * 0.3;
	} else if (s < 8.5) { // cross
		float d1 = abs(p.x - p.y) * 0.7071;
		float d2 = abs(p.x + p.y) * 0.7071;
		a = (1.0 - smoothstep(0.1, 0.17, min(d1, d2))) * (1.0 - smoothstep(0.75, 0.85, r));
	} else if (s < 9.5) { // dashed ring
		float th = max(v_param, 0.02);
		float dash = step(0.0, sin(ang * 12.0 + v_t * 6.0));
		a = ring_mask(r, 1.0 - th, th) * dash;
	} else if (s < 10.5) { // glitch slabs
		float row = floor((p.y + 1.0) * 7.0);
		float h = hash11(row + v_param + floor(v_t * 18.0) * 7.0);
		float off = (h - 0.5) * 0.7;
		float w = 0.35 + 0.6 * hash11(row * 3.7 + v_param);
		float in_row = step(0.25, fract((p.y + 1.0) * 7.0));
		a = (1.0 - step(w, abs(p.x - off))) * in_row * step(0.25, h) * (1.0 - smoothstep(0.85, 1.0, abs(p.y)));
		col = mix(col, vec3(1.0), step(0.85, h) * 0.6);
	} else if (s < 11.5) { // 5-point star
		float rr = 0.5 + 0.32 * cos(ang * 5.0);
		a = 1.0 - smoothstep(rr - 0.06, rr, r);
		core = a * 0.4;
	} else if (s < 12.5) { // stop square
		float m = max(abs(p.x), abs(p.y));
		a = max(1.0 - smoothstep(0.08, 0.14, abs(m - 0.66)), (1.0 - step(0.42, m)) * 0.7);
	} else if (s < 13.5) { // shard (triangle)
		float tri = max(-p.y - 0.7, abs(p.x) * 1.7 + p.y - 0.8);
		a = 1.0 - smoothstep(-0.04, 0.0, tri);
	} else { // hard dot
		a = 1.0 - smoothstep(0.5, 0.62, r);
		core = 1.0 - smoothstep(0.1, 0.35, r);
	}

	a *= COLOR.a;
	if (FX_ADDITIVE > 0.5 && (v_mode < 0.5 || v_mode > 1.5)) {
		float d = texture(fx_depth, SCREEN_UV).r;
		vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
		float scene_z = -vp.z / vp.w;
		a *= clamp((scene_z + VERTEX.z) / soft_fade, 0.0, 1.0);
	}
	if (a < 0.004) {
		discard;
	}
	col = mix(col, vec3(1.0), clamp(core, 0.0, 1.0) * 0.55 * FX_ADDITIVE);
	ALBEDO = fx_srgb_to_linear(col) * FX_GAIN;
	ALPHA = a;
}
