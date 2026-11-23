shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, unshaded;

uniform vec4 tint : source_color = vec4(0.2, 1.0, 0.5, 0.35);

void vertex() {
	VERTEX += NORMAL * 0.025;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = tint.rgb * (0.58 + fresnel * 1.45);
	ALPHA = 0.35;
}
