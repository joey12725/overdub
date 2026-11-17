// Surface half of the OVERDUB toon material (toon.gdshader / toon_cutout.gdshader).
// Define OD_CUTOUT before including for alpha-scissor foliage / decals-on-quads.

#include "res://shaders/toon_lighting.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform bool use_albedo_texture = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
// How much vertex colour (and MultiMesh instance colour, which Godot folds into COLOR) tints albedo.
uniform float vertex_color_mix : hint_range(0.0, 1.0) = 1.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// HDR multiplier; > ~1.2 blooms through the WorldEnvironment glow.
uniform float emission_energy = 0.0;
uniform sampler2D emission_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform bool use_emission_texture = false;
// Pulled toward the albedo colour on the lit side (0 = pure cel, 1 = fully unlit look).
uniform float unlit_mix : hint_range(0.0, 1.0) = 0.0;
#ifdef OD_CUTOUT
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.4;
#endif

// Per-node overrides (GeometryInstance3D.set_instance_shader_parameter): one shared material,
// many tints. instance_tint multiplies albedo; instance_emission adds rgb * a.
instance uniform vec4 instance_tint : source_color, instance_index(0) = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 instance_emission : source_color, instance_index(1) = vec4(0.0, 0.0, 0.0, 0.0);

void vertex() {
	od_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec4 base = albedo;
	if (use_albedo_texture) {
		base *= texture(albedo_texture, uv);
	}
	base.rgb *= mix(vec3(1.0), COLOR.rgb, vertex_color_mix);
	base.rgb *= instance_tint.rgb;
	ALBEDO = base.rgb * (1.0 - unlit_mix);
	vec3 e = emission.rgb * emission_energy;
	if (use_emission_texture) {
		e *= texture(emission_texture, uv).rgb;
	}
	EMISSION = e + instance_emission.rgb * instance_emission.a + base.rgb * unlit_mix;
#ifdef OD_CUTOUT
	ALPHA = base.a * instance_tint.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
#endif
}
