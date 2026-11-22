shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 foliage_tint : source_color = vec4(0.17, 0.28, 0.15, 1.0);
uniform float wind_strength = 0.13;

void vertex() {
	float height_weight = clamp(VERTEX.y * 0.22 + 0.5, 0.0, 1.0);
	float gust = sin(TIME * 1.35 + VERTEX.x * 0.8 + VERTEX.z * 1.1);
	VERTEX.x += gust * height_weight * wind_strength;
	VERTEX.z += cos(TIME * 0.9 + VERTEX.x * 0.45) * height_weight * wind_strength * 0.42;
}

void fragment() {
	ALBEDO = foliage_tint.rgb;
	ROUGHNESS = 0.92;
}
