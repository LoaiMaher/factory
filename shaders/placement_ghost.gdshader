shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform vec4 tint : source_color = vec4(0.2, 1.0, 0.5, 0.38);

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	float scanline = 0.92 + 0.08 * sin(FRAGCOORD.y * 0.65);
	ALBEDO = tint.rgb * (0.75 + fresnel * 0.6) * scanline;
	ALPHA = tint.a;
}
