shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_roughness : repeat_enable, filter_linear_mipmap;
uniform sampler2D forest_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D forest_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D forest_roughness : repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_roughness : repeat_enable, filter_linear_mipmap;
uniform sampler2D sand_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D sand_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D sand_roughness : repeat_enable, filter_linear_mipmap;
varying vec3 world_position;
varying vec3 world_normal;
varying vec4 terrain_masks;
varying float camera_distance;

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_position = world.xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	terrain_masks = COLOR;
	camera_distance = distance(CAMERA_POSITION_WORLD, world.xyz);
}

void fragment() {
	vec3 normal = normalize(world_normal);
	float variation = terrain_masks.a;
	float distant_scale = mix(1.0, 0.66, smoothstep(100.0, 720.0, camera_distance));
	float tiling = 0.12 * distant_scale * mix(0.78, 1.24, variation);
	vec2 ground_uv = world_position.xz * tiling;
	vec2 forest_uv = world_position.xz * (tiling * 0.82) + vec2(7.7, 13.1);
	vec2 sand_uv = world_position.xz * (tiling * 0.94) - vec2(4.3, 19.7);
	float slope = 1.0 - clamp(normal.y, 0.0, 1.0);
	float rock_weight = clamp(max(terrain_masks.b,
		smoothstep(0.13, 0.34, slope) * 0.97 + smoothstep(112.0, 185.0, world_position.y) * 0.42), 0.0, 1.0);
	float forest_weight = clamp(terrain_masks.r * (0.72 + variation * 0.42), 0.0, 0.92) * (1.0 - rock_weight);
	float sand_weight = clamp(terrain_masks.g * (0.86 + variation * 0.18), 0.0, 0.9) * (1.0 - rock_weight);
	float grass_weight = max(0.06, 1.0 - rock_weight - forest_weight - sand_weight);
	vec4 weights = vec4(grass_weight, forest_weight, rock_weight, sand_weight);
	weights /= max(dot(weights, vec4(1.0)), 0.0001);

	vec3 albedo = vec3(0.0);
	float roughness = 0.0;
	vec3 mapped_normal = vec3(0.0);
	if (weights.x > 0.01) {
		albedo += texture(grass_albedo, ground_uv).rgb * vec3(0.82, 1.18, 0.78) * weights.x;
		roughness += texture(grass_roughness, ground_uv).r * weights.x;
		mapped_normal += (texture(grass_normal, ground_uv).rgb * 2.0 - 1.0) * weights.x;
	}
	if (weights.y > 0.01) {
		albedo += texture(forest_albedo, forest_uv).rgb * weights.y;
		roughness += texture(forest_roughness, forest_uv).r * weights.y;
		mapped_normal += (texture(forest_normal, forest_uv).rgb * 2.0 - 1.0) * weights.y;
	}
	if (weights.z > 0.01) {
		vec3 triplanar_weight = pow(abs(normal), vec3(4.0));
		triplanar_weight /= max(dot(triplanar_weight, vec3(1.0)), 0.0001);
		vec3 rock_color = texture(rock_albedo, world_position.zy * tiling).rgb * triplanar_weight.x;
		rock_color += texture(rock_albedo, world_position.xz * tiling).rgb * triplanar_weight.y;
		rock_color += texture(rock_albedo, world_position.xy * tiling).rgb * triplanar_weight.z;
		rock_color *= mix(vec3(0.84, 0.82, 0.77), vec3(1.0, 0.98, 0.92),
			smoothstep(100.0, 185.0, world_position.y));
		albedo += rock_color * weights.z;
		roughness += texture(rock_roughness, world_position.xz * tiling).r * weights.z;
		vec3 rock_normal_map = texture(rock_normal, world_position.zy * tiling).rgb * triplanar_weight.x;
		rock_normal_map += texture(rock_normal, world_position.xz * tiling).rgb * triplanar_weight.y;
		rock_normal_map += texture(rock_normal, world_position.xy * tiling).rgb * triplanar_weight.z;
		mapped_normal += (rock_normal_map * 2.0 - 1.0) * weights.z;
	}
	if (weights.w > 0.01) {
		albedo += texture(sand_albedo, sand_uv).rgb * weights.w;
		roughness += texture(sand_roughness, sand_uv).r * weights.w;
		mapped_normal += (texture(sand_normal, sand_uv).rgb * 2.0 - 1.0) * weights.w;
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	NORMAL_MAP = normalize(mapped_normal) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.38;
	SPECULAR = 0.18;
	METALLIC = 0.0;
}
