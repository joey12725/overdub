// OVERDUB shared cel lighting (ART-02: stepped light, graphic shadows, ink edges).
// Included by toon.gdshader, toon_cutout.gdshader and world_surface.gdshader; see shaders/README.md.
//
// Model per light:
//   x      = clamp(N.L * ATTENUATION)          (ATTENUATION carries the shadow map)
//   band   = toon_ramp(x)                      (stepped: deep shadow .. highlight)
//   key    = LIGHT_COLOR / PI * mix(shadow_tint * shadow_floor, 1, band)    (directional only)
//   omni   = LIGHT_COLOR / PI * band(N.L) * ATTENUATION                      (practicals, no floor)
// plus a stepped rim on the lit side and optional world-space hatching inside shadow.
// Environment ambient light is added by Godot outside light(), so shadowed faces read as
// ambient + tinted floor, never black.

uniform sampler2D toon_ramp : filter_nearest, repeat_disable, hint_default_white;
// When false the four built-in bands are used and toon_ramp is ignored.
uniform bool use_toon_ramp = false;
// Colour (and, via alpha, strength) that a directional light leaves in its own shadow.
uniform vec4 shadow_tint : source_color = vec4(0.30, 0.27, 0.34, 1.0);
// 0 = shadow side gets only ambient; 1 = it gets the full shadow_tint fraction of the key.
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.55;
// Lambert wrap before banding (0 = hard terminator; 0.3 softens tiny facets).
uniform float light_wrap : hint_range(0.0, 1.0) = 0.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.22;
// 0..1: fraction of the silhouette band the rim covers.
uniform float rim_width : hint_range(0.0, 1.0) = 0.3;
// World-space diagonal hatching drawn inside shadow (0 = off).
uniform float hatch_strength : hint_range(0.0, 1.0) = 0.0;
// Lines per world unit.
uniform float hatch_density = 7.0;

varying vec3 od_world_pos;

float od_band(float x) {
	if (use_toon_ramp) {
		return texture(toon_ramp, vec2(clamp(x, 0.0, 1.0) * 0.999, 0.5)).r;
	}
	// Four flat bands: shadow, half, lit, highlight.
	return x < 0.06 ? 0.0 : (x < 0.38 ? 0.55 : (x < 0.82 ? 0.86 : 1.0));
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = (ndl + light_wrap) / (1.0 + light_wrap);
	if (LIGHT_IS_DIRECTIONAL) {
		float x = clamp(wrapped, 0.0, 1.0) * clamp(ATTENUATION, 0.0, 1.0);
		float band = od_band(x);
		vec3 floor_col = shadow_tint.rgb * shadow_tint.a * shadow_floor;
		if (hatch_strength > 0.0 && band < 0.5) {
			// Ink hatching only in the deepest band, in world space so it never swims.
			float lines = step(0.78, fract(((od_world_pos.x + od_world_pos.z) * 0.7071 + od_world_pos.y * 0.6) * hatch_density));
			floor_col *= 1.0 - hatch_strength * lines * (1.0 - band * 2.0);
		}
		vec3 k = mix(floor_col, vec3(1.0), band);
		float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float rim_band = step(1.0 - rim_width, rim) * step(0.2, x);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * (k + rim_strength * rim_band);
	} else {
		float x = clamp(wrapped, 0.0, 1.0);
		float band = od_band(x);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * band * ATTENUATION;
	}
}
