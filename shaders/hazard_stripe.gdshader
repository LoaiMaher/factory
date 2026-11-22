shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

void fragment() {
	float stripe = step(0.5, fract((UV.x + UV.y * 0.6) * 18.0));
	ALBEDO = mix(vec3(0.10, 0.12, 0.11), vec3(0.79, 0.53, 0.15), stripe);
	METALLIC = 0.32;
	ROUGHNESS = 0.72;
}
