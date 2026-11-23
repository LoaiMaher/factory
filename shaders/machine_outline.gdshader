shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;

uniform vec4 outline_color : source_color = vec4(0.82, 0.9, 0.94, 1.0);
uniform float outline_width = 0.08;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * 0.3;
	ALPHA = outline_color.a;
}
