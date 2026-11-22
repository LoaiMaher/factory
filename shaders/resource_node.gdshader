shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 ore_tint : source_color = vec4(0.58, 0.32, 0.22, 1.0);
uniform vec4 patina_tint : source_color = vec4(0.1, 0.35, 0.3, 1.0);
uniform float vein_glow = 0.0;
uniform float patina_strength = 0.0;

varying vec3 local_position;
varying vec3 local_normal;

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec2 point = local_position.xz;
	float crack_field = abs(sin(point.x * 4.7 + sin(point.y * 2.1) * 2.3)
		* sin(point.y * 5.1 + point.x * 1.7));
	float cracks = 1.0 - smoothstep(0.0, 0.09, crack_field);
	float noise = sin(point.x * 2.7 + cos(point.y * 2.1))
		* sin(point.y * 3.3 - point.x * 1.8);
	float base_blend = smoothstep(-0.18, 0.16, local_position.y);
	float edge_darkening = 1.0 - 0.34 * (1.0 - base_blend);
	vec3 dirt = vec3(0.19, 0.16, 0.12);
	vec3 stone = ore_tint.rgb * (0.88 + noise * 0.08);
	float top_mask = smoothstep(0.2, 0.78, local_normal.y);
	vec3 side_rock = vec3(0.12, 0.11, 0.095) * (0.86 + noise * 0.2);
	float patina_field = abs(sin(point.x * 17.0 + sin(point.y * 11.0))
		* sin(point.y * 19.0 - point.x * 7.0));
	float patina = smoothstep(0.92, 0.985, patina_field) * patina_strength;
	stone = mix(stone, patina_tint.rgb, patina * 0.7);
	stone = mix(stone, stone * 0.24, cracks * 0.72);
	vec3 rock = mix(dirt, side_rock * edge_darkening, base_blend);
	ALBEDO = mix(rock, stone * edge_darkening, top_mask * base_blend);
	ROUGHNESS = 0.86;
	METALLIC = 0.08;
	SPECULAR = 0.22;
	float veins = smoothstep(0.91, 0.98, abs(sin(point.x * 1.8 + point.y * 1.3 + noise)));
	EMISSION = ore_tint.rgb * veins * vein_glow * top_mask;
}
