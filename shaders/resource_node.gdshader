shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 ore_tint : source_color = vec4(0.58, 0.32, 0.22, 1.0);
uniform vec4 patina_tint : source_color = vec4(0.1, 0.35, 0.3, 1.0);
uniform float vein_glow = 0.0;
uniform float patina_strength = 0.0;
uniform int ore_style = 0;

varying vec3 local_position;
varying vec3 local_normal;

float hash21(vec2 point) {
	vec3 p3 = fract(vec3(point.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 point) {
	return vec2(hash21(point), hash21(point + vec2(19.19, 73.73)));
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float lower = mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), local.x);
	float upper = mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), local.x);
	return mix(lower, upper, local.y);
}

float value_noise_2oct(vec2 point) {
	return value_noise(point) * 0.67
		+ value_noise(point * 2.03 + vec2(17.3, 9.2)) * 0.33;
}

float voronoi_edge(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	float first = 1e6;
	float second = 1e6;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 feature = neighbor + hash22(cell + neighbor);
			float distance_to_feature = length(feature - local);
			if (distance_to_feature < first) {
				second = first;
				first = distance_to_feature;
			} else if (distance_to_feature < second) {
				second = distance_to_feature;
			}
		}
	}
	return second - first;
}

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec2 point = local_position.xz;
	float noise = value_noise_2oct(point * 2.7);
	float base_blend = smoothstep(-0.18, 0.16, local_position.y);
	vec3 dirt = vec3(0.30, 0.25, 0.19);
	vec3 side_rock = mix(vec3(0.34, 0.30, 0.26), ore_tint.rgb, 0.35)
		* (0.92 + noise * 0.16);
	float stone_strength = 1.08 + noise * 0.12;
	if (ore_style == 2) {
		stone_strength = 0.6 + noise * 0.06;
	}
	vec3 stone = ore_tint.rgb * stone_strength;
	float top_mask = smoothstep(0.2, 0.78, local_normal.y);
	vec2 branch_warp = vec2(
		value_noise_2oct(point * 1.35 + vec2(7.0, 13.0)),
		value_noise_2oct(point * 1.35 + vec2(29.0, 3.0))
	);
	vec2 iron_warp = vec2(
		value_noise_2oct(point * 0.62 + vec2(3.0, 17.0)),
		value_noise_2oct(point * 0.62 + vec2(21.0, 5.0))
	);
	vec2 iron_point = point * 0.92 + (iron_warp - 0.5) * 0.38;
	float iron_fracture_distance = voronoi_edge(iron_point);
	float iron_cracks = 1.0 - smoothstep(0.014, 0.05, iron_fracture_distance);
	vec2 copper_point = point * 1.2 + (branch_warp - 0.5) * 0.48;
	float copper_main_cracks = 1.0 - smoothstep(
		0.018, 0.052, voronoi_edge(copper_point * 1.1));
	float copper_branch_cracks = 1.0 - smoothstep(
		0.012, 0.036, voronoi_edge(copper_point * 2.7 + vec2(4.1, 9.2)));
	float copper_cracks = max(copper_main_cracks, copper_branch_cracks * 0.48);
	float limestone_cracks = 1.0 - smoothstep(
		0.018, 0.058, voronoi_edge(point * 1.12 + (branch_warp - 0.5) * 0.18));
	float cracks = iron_cracks;
	if (ore_style == 1) {
		cracks = copper_cracks;
	} else if (ore_style == 2) {
		cracks = limestone_cracks * 0.72;
	}
	float crack_distance = voronoi_edge(copper_point * 1.1);
	float copper_rim = smoothstep(0.045, 0.075, crack_distance)
		* (1.0 - smoothstep(0.13, 0.19, crack_distance));
	float patina_field = value_noise_2oct(point * 17.0);
	float patina = max(smoothstep(0.72, 0.94, patina_field), cracks * 0.74)
		* patina_strength;
	float limestone_bedding = 1.0 - smoothstep(0.025, 0.09,
		abs(fract((local_position.y + 0.42) * 16.0) - 0.5));
	vec2 pit_cell = floor(point * 11.0);
	vec2 pit_local = fract(point * 11.0) - hash22(pit_cell);
	float pit_seed = step(0.72, hash21(pit_cell + vec2(31.0, 17.0)));
	float fossil_pits = (1.0 - smoothstep(0.08, 0.2, length(pit_local)))
		* pit_seed * top_mask;
	float iron_flecks = smoothstep(0.91, 0.99, value_noise_2oct(point * 42.0))
		* top_mask;
	float rust_streak_field = value_noise_2oct(vec2(point.x * 5.0, point.y * 1.2));
	float rust_near_cracks = 1.0 - smoothstep(0.02, 0.2, iron_fracture_distance);
	float rust_streaks = rust_near_cracks
		* smoothstep(0.44, 0.73, rust_streak_field) * top_mask;
	if (ore_style != 0) {
		rust_streaks = 0.0;
		iron_flecks = 0.0;
	}
	if (ore_style != 2) {
		limestone_bedding = 0.0;
		fossil_pits = 0.0;
	}
	stone = mix(stone, vec3(0.72, 0.28, 0.1), rust_streaks * 0.82);
	stone = mix(stone, vec3(0.72, 0.53, 0.36), iron_flecks * 0.62);
	stone = mix(stone, patina_tint.rgb, patina * 0.72);
	stone = mix(stone, stone * 0.45, fossil_pits * 0.46);
	stone = mix(stone, vec3(0.65, 0.61, 0.51),
		limestone_bedding * (1.0 - top_mask) * 0.52);
	stone = mix(stone, stone * 0.55, limestone_bedding * (1.0 - top_mask) * 0.5);
	stone = mix(stone, stone * 0.76, cracks * 0.72);
	if (ore_style == 1) {
		stone = mix(stone, patina_tint.rgb, patina * 0.84);
	}
	vec3 rock = mix(dirt, side_rock, base_blend);
	rock = mix(rock, rock * 0.58, cracks * 0.55);
	ALBEDO = mix(rock, stone, top_mask * base_blend);
	ROUGHNESS = 0.86;
	if (ore_style == 1) {
		ROUGHNESS = 0.74;
	} else if (ore_style == 2) {
		ROUGHNESS = 0.96;
	}
	METALLIC = 0.08;
	if (ore_style == 1) {
		METALLIC = 0.08 + copper_rim * 0.3;
	} else if (ore_style == 0) {
		METALLIC = 0.08 + iron_flecks * 0.32;
	}
	SPECULAR = 0.22;
	EMISSION = ore_tint.rgb * cracks * vein_glow * top_mask;
}
