// Opaque cel body, double-sided: for materials imported as double-sided (open sheets such as a face
// plane or hair cards). A single-sided pass would cull the sheet's visible side and let the ink hull
// behind it show through. Godot flips NORMAL on back faces. See actor_body.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://actors/shaders/actor_body.gdshaderinc"

void fragment() {
	vec3 c = od_cel(NORMAL, INV_VIEW_MATRIX);
	ALBEDO = mix(c, flash_col.rgb, flash_col.a);
}
