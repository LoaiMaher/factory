shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 ore_tint : source_color = vec4(0.58, 0.32, 0.22, 1.0);
uniform vec4 patina_tint : source_color = vec4(0.1, 0.35, 0.3, 1.0);
uniform float vein_glow = 0.0;
uniform float patina_strength = 0.0;

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
	float cracks = 1.0 - smoothstep(0.015, 0.05, voronoi_edge(point * 1.6));
	float base_blend = smoothstep(-0.18, 0.16, local_position.y);
	vec3 dirt = vec3(0.30, 0.25, 0.19);
	vec3 side_rock = mix(vec3(0.34, 0.30, 0.26), ore_tint.rgb, 0.35)
		* (0.92 + noise * 0.16);
	vec3 stone = ore_tint.rgb * (1.08 + noise * 0.12);
	float top_mask = smoothstep(0.2, 0.78, local_normal.y);
	float patina_field = value_noise_2oct(point * 17.0);
	float patina = smoothstep(0.72, 0.94, patina_field) * patina_strength;
	float warp_x = value_noise_2oct(point * 0.9);
	float warp_y = value_noise_2oct(point.yx * 0.9 + vec2(11.0, 7.0));
	vec2 vein_point = vec2(point.x * 2.2, point.y * 0.75)
		+ vec2((warp_x - 0.5) * 1.1, (warp_y - 0.5) * 0.35);
	float vein_field = value_noise_2oct(vein_point);
	float veins = 1.0 - smoothstep(0.02, 0.08, abs(vein_field - 0.5));
	stone = mix(stone, stone * 1.25, veins * 0.35);
	stone = mix(stone, patina_tint.rgb, patina * 0.7);
	stone = mix(stone, stone * 0.24, cracks * 0.72);
	vec3 rock = mix(dirt, side_rock, base_blend);
	rock = mix(rock, rock * 0.58, cracks * 0.55);
	ALBEDO = mix(rock, stone, top_mask * base_blend);
	ROUGHNESS = 0.86;
	METALLIC = 0.08;
	SPECULAR = 0.22;
	EMISSION = ore_tint.rgb * veins * vein_glow * top_mask;
}
