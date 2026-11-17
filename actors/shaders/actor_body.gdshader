// Opaque cel body (living selves, enemies). See actor_body.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://actors/shaders/actor_body.gdshaderinc"

void fragment() {
	vec3 c = od_cel(NORMAL, INV_VIEW_MATRIX);
	ALBEDO = mix(c, flash_col.rgb, flash_col.a);
}
