// OVERDUB screen grade (canvas_item over the 3D view, under the UI): theme grade, saturation,
// vignette, chromatic split and flash. Driven by WorldPost from RenderCtx.post (PostControls).
// Uniforms: shaders/README.md.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
// Multiplied into the image (theme colour cast; white = neutral).
uniform vec4 grade_gain : source_color = vec4(1.0);
// Added to the shadows (lifts blacks toward a theme colour).
uniform vec4 grade_lift : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform float vignette = 0.3;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float chromatic = 0.0;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - 0.5;
	vec3 col;
	if (chromatic > 0.0005) {
		vec2 off = dir * chromatic * 0.018;
		col.r = textureLod(screen_tex, uv + off, 0.0).r;
		col.g = textureLod(screen_tex, uv, 0.0).g;
		col.b = textureLod(screen_tex, uv - off, 0.0).b;
	} else {
		col = textureLod(screen_tex, uv, 0.0).rgb;
	}
	col = col * grade_gain.rgb + grade_lift.rgb * (1.0 - clamp(col, 0.0, 1.0));
	col = (col - 0.5) * contrast + 0.5;
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(luma), col, saturation);
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float v = length(dir * vec2(aspect, 1.0)) / length(vec2(aspect, 1.0) * 0.5);
	col = mix(col, vignette_color.rgb, clamp(vignette * smoothstep(0.45, 1.05, v), 0.0, 1.0));
	col = mix(col, flash_color.rgb, clamp(flash, 0.0, 1.0));
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
