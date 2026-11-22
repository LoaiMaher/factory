shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 hazard_yellow : source_color = vec4(0.93, 0.56, 0.08, 1.0);
uniform vec4 hazard_dark : source_color = vec4(0.055, 0.065, 0.06, 1.0);

void fragment() {
	float stripe = step(0.48, fract((UV.x + UV.y * 0.22) * 14.0));
	ALBEDO = mix(hazard_dark.rgb, hazard_yellow.rgb, stripe);
	METALLIC = 0.18;
	ROUGHNESS = 0.52;
}
