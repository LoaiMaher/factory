shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float belt_speed = 0.0;

void fragment() {
	float lane = step(0.08, fract(UV.x * 10.0));
	float stripe = step(0.74, fract(UV.y * 7.0 - TIME * belt_speed));
	ALBEDO = mix(vec3(0.075, 0.09, 0.085), vec3(0.17, 0.19, 0.17), max(lane * 0.25, stripe * 0.72));
	METALLIC = 0.18;
	ROUGHNESS = 0.76;
}
