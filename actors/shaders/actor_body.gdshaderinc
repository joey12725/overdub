// Shared cel shading for every self / enemy body (prototype render/actors/materials.ts CEL_FRAG).
// One shader drives every style through instance uniforms, so a style change is a per-instance
// parameter write (or a swap between the opaque and translucent twin), never a recompile.
//
// Material uniforms (per contract material, shared by all instances):
//   albedo     base colour of the material (from the imported material, or the gear tint)
//   albedo_tex multiplied into albedo when has_tex is 1 (the imported albedo texture, e.g. face_paint)
//   is_glow    1 for emissive parts (material name ends in "_glow"): unlit, bloom-bright
//   is_accent  1 for parts recoloured by the instance accent (headphone glow -> cassette colour,
//              an enemy optic -> its state colour)
//
// Instance uniforms carry explicit instance_index() slots that are unique across the whole pass
// chain (body 0-9, outline 10-11, echo 12-13, x-ray 14-15). Godot numbers them per shader in
// declaration order otherwise, so on one mesh the outline's colour, the echo's shift and the body's
// accent would all share slot 0 and overwrite each other. 16 slots is Godot's per-instance maximum.

uniform vec3 albedo : source_color = vec3(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform float has_tex = 0.0;
uniform float is_glow = 0.0;
uniform float is_accent = 0.0;
uniform vec3 light_dir = vec3(-0.45, 1.0, 0.55);
uniform vec3 lit_col : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 shade_col : source_color = vec3(0.55, 0.5, 0.68);
uniform sampler2D ramp : filter_linear, repeat_disable, hint_default_white;
uniform float has_ramp = 0.0;
// 0 = full cel ramp (flat-colour materials); toward 1 the lit / shade tints close in on white, for
// materials whose albedo texture already carries painted cel shading (the textured Moxie).
uniform float cel_soft = 0.0;
// Outfit zones of a single-texture body (tools/moxie_regions.py; docs/WARDROBE.md): two mask
// textures in the albedo's UV space, and per zone a tint (linear rgb, a = strength) and the mean
// luminance of the painted source. A zone is recoloured as tint * (luminance / zone luminance), so
// the painted folds, seams and shading survive. Order: top, jacket, jacket lining, pants, pants
// graphic, shoes.
uniform float has_zones = 0.0;
uniform sampler2D zone_a : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D zone_b : filter_linear, repeat_disable, hint_default_black;
uniform vec4 zone_tint[6];
uniform float zone_lum[6];

instance uniform vec4 accent : source_color, instance_index(0) = vec4(1.0, 0.82, 0.25, 1.0);
instance uniform float desat : instance_index(1) = 0.0;
instance uniform vec4 flash_col : source_color, instance_index(2) = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float glow_mul : instance_index(3) = 1.6;
instance uniform float rim_amt : instance_index(4) = 0.12;
instance uniform vec4 tint : source_color, instance_index(5) = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float body_opacity : instance_index(6) = 1.0;
instance uniform float holo : instance_index(7) = 0.0;
instance uniform float phase : instance_index(8) = 0.0;
instance uniform float hollow : instance_index(9) = 0.0;

varying vec3 v_world;
varying vec2 v_uv;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
}

float od_rim(vec3 view_normal) {
	return pow(1.0 - clamp(abs(view_normal.z), 0.0, 1.0), 3.0);
}

vec3 od_zones(vec3 col) {
	vec3 ma = texture(zone_a, v_uv).rgb;
	vec3 mb = texture(zone_b, v_uv).rgb;
	float w[6] = { ma.r, ma.g, ma.b, mb.r, mb.g, mb.b };
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	for (int i = 0; i < 6; i++) {
		float k = w[i] * zone_tint[i].a;
		if (k > 0.002) {
			float shade = mix(1.0, clamp(l / max(zone_lum[i], 0.02), 0.0, 2.0), 0.8);
			col = mix(col, zone_tint[i].rgb * shade, k);
		}
	}
	return col;
}

vec3 od_cel(vec3 view_normal, mat4 inv_view) {
	vec3 col = albedo;
	if (has_tex > 0.5) {
		col *= texture(albedo_tex, v_uv).rgb;
	}
	if (has_zones > 0.5) {
		col = od_zones(col);
	}
	vec3 base = mix(col, accent.rgb, is_accent);
	vec3 n = normalize((inv_view * vec4(view_normal, 0.0)).xyz);
	float ndl = dot(n, normalize(light_dir));
	float h = ndl * 0.5 + 0.5;
	float r;
	if (has_ramp > 0.5) {
		r = texture(ramp, vec2(clamp(h, 0.02, 0.98), 0.5)).r;
	} else {
		r = smoothstep(0.38, 0.46, h) * 0.85 + smoothstep(0.82, 0.86, h) * 0.15;
	}
	vec3 lit = mix(base * mix(shade_col, vec3(1.0), cel_soft), base * mix(lit_col, vec3(1.0), cel_soft * 0.6), r);
	lit += accent.rgb * od_rim(view_normal) * rim_amt;
	vec3 c = mix(lit, base * glow_mul, is_glow);
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(lum), desat);
	c = mix(c, tint.rgb, tint.a);
	return c;
}
