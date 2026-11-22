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
uniform sampler2D ore_overlay : source_color, filter_linear, repeat_disable;
uniform float texture_scale = 0.12;

varying vec3 world_position;
varying vec3 world_normal;
varying vec4 terrain_masks;

float hash2(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float a = hash2(cell);
	float b = hash2(cell + vec2(1.0, 0.0));
	float c = hash2(cell + vec2(0.0, 1.0));
	float d = hash2(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, fraction.x), mix(c, d, fraction.x), fraction.y);
}

float layered_noise(vec2 point) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		value += value_noise(point) * amplitude;
		point *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_position = world.xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	terrain_masks = COLOR;
}

void fragment() {
	vec3 normal = normalize(world_normal);
	float distance_from_camera = distance(CAMERA_POSITION_WORLD, world_position);
	float distant_scale = mix(1.0, 0.66, smoothstep(100.0, 720.0, distance_from_camera));
	float variation = mix(terrain_masks.a, layered_noise(world_position.xz * 0.018), 0.48);
	float tiling = texture_scale * distant_scale * mix(0.78, 1.24, variation);
	vec2 ground_uv = world_position.xz * tiling;
	vec2 forest_uv = world_position.xz * (tiling * 0.82) + vec2(7.7, 13.1);
	vec2 sand_uv = world_position.xz * (tiling * 0.94) - vec2(4.3, 19.7);

	vec3 grass_color = mix(texture(grass_albedo, ground_uv).rgb,
		texture(grass_albedo, ground_uv * 1.71 + vec2(11.3, 3.9)).rgb, variation * 0.22);
	grass_color *= vec3(0.82, 1.18, 0.78);
	vec3 forest_color = mix(texture(forest_albedo, forest_uv).rgb,
		texture(forest_albedo, forest_uv * 1.53 - vec2(5.1, 17.3)).rgb, variation * 0.18);
	vec3 sand_color = texture(sand_albedo, sand_uv).rgb;

	vec3 triplanar_weight = pow(abs(normal), vec3(4.0));
	triplanar_weight /= max(dot(triplanar_weight, vec3(1.0)), 0.0001);
	vec3 rock_x = texture(rock_albedo, world_position.zy * tiling).rgb;
	vec3 rock_y = texture(rock_albedo, world_position.xz * tiling).rgb;
	vec3 rock_z = texture(rock_albedo, world_position.xy * tiling).rgb;
	vec3 rock_color = rock_x * triplanar_weight.x + rock_y * triplanar_weight.y + rock_z * triplanar_weight.z;
	rock_color *= mix(vec3(0.84, 0.82, 0.77), vec3(1.0, 0.98, 0.92),
		smoothstep(100.0, 185.0, world_position.y));

	float slope = 1.0 - clamp(normal.y, 0.0, 1.0);
	float rock_weight = clamp(max(terrain_masks.b,
		smoothstep(0.13, 0.34, slope) * 0.97 + smoothstep(112.0, 185.0, world_position.y) * 0.42), 0.0, 1.0);
	float forest_weight = clamp(terrain_masks.r * (0.72 + variation * 0.42), 0.0, 0.92) * (1.0 - rock_weight);
	float sand_weight = clamp(terrain_masks.g * (0.86 + variation * 0.18), 0.0, 0.9) * (1.0 - rock_weight);
	float grass_weight = max(0.06, 1.0 - rock_weight - forest_weight - sand_weight);
	float weight_total = grass_weight + forest_weight + rock_weight + sand_weight;
	vec4 weights = vec4(grass_weight, forest_weight, rock_weight, sand_weight) / weight_total;

	ALBEDO = grass_color * weights.x + forest_color * weights.y + rock_color * weights.z + sand_color * weights.w;
	vec4 ore_patch = texture(ore_overlay, (world_position.xz + vec2(512.0)) / 1024.0);
	ALBEDO = mix(ALBEDO, ore_patch.rgb, ore_patch.a);
	float grass_rough = texture(grass_roughness, ground_uv).r;
	float forest_rough = texture(forest_roughness, forest_uv).r;
	float rock_rough = texture(rock_roughness, world_position.xz * tiling).r;
	float sand_rough = texture(sand_roughness, sand_uv).r;
	ROUGHNESS = grass_rough * weights.x + forest_rough * weights.y + rock_rough * weights.z + sand_rough * weights.w;

	vec3 grass_n = texture(grass_normal, ground_uv).rgb * 2.0 - 1.0;
	vec3 forest_n = texture(forest_normal, forest_uv).rgb * 2.0 - 1.0;
	vec3 rock_n = (texture(rock_normal, world_position.zy * tiling).rgb * triplanar_weight.x
		+ texture(rock_normal, world_position.xz * tiling).rgb * triplanar_weight.y
		+ texture(rock_normal, world_position.xy * tiling).rgb * triplanar_weight.z) * 2.0 - 1.0;
	vec3 sand_n = texture(sand_normal, sand_uv).rgb * 2.0 - 1.0;
	NORMAL_MAP = normalize(grass_n * weights.x + forest_n * weights.y + rock_n * weights.z + sand_n * weights.w) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.38;
	SPECULAR = 0.18;
	METALLIC = 0.0;
}
