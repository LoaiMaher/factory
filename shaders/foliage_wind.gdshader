shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

uniform vec4 foliage_tint : source_color = vec4(0.17, 0.28, 0.15, 1.0);
uniform float wind_strength = 0.13;
uniform float fade_start = 52.0;
uniform float fade_end = 60.0;

varying float foliage_fade;

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float height_weight = clamp(VERTEX.y * 0.12 + 0.3, 0.0, 1.0);
	float gust = sin(TIME * 1.35 + VERTEX.x * 0.8 + VERTEX.z * 1.1);
	VERTEX.x += gust * height_weight * wind_strength;
	VERTEX.z += cos(TIME * 0.9 + VERTEX.x * 0.45) * height_weight * wind_strength * 0.42;
	foliage_fade = 1.0 - smoothstep(fade_start, fade_end, distance(CAMERA_POSITION_WORLD, world_position));
}

void fragment() {
	ALBEDO = foliage_tint.rgb * COLOR.rgb;
	ROUGHNESS = 0.92;
	ALPHA = foliage_fade;
}
