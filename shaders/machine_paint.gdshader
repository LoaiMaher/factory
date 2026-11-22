shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D plate_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D plate_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D plate_roughness : filter_linear_mipmap, repeat_enable;
uniform vec4 paint_tint : source_color = vec4(0.8, 0.3, 0.08, 1.0);
uniform float texture_scale = 0.38;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_position = world.xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 weights = pow(abs(normalize(world_normal)), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	vec2 uv_x = world_position.zy * texture_scale;
	vec2 uv_y = world_position.xz * texture_scale;
	vec2 uv_z = world_position.xy * texture_scale;
	vec3 albedo = texture(plate_albedo, uv_x).rgb * weights.x;
	albedo += texture(plate_albedo, uv_y).rgb * weights.y;
	albedo += texture(plate_albedo, uv_z).rgb * weights.z;
	vec3 normal_map = (texture(plate_normal, uv_x).rgb * 2.0 - 1.0) * weights.x;
	normal_map += (texture(plate_normal, uv_y).rgb * 2.0 - 1.0) * weights.y;
	normal_map += (texture(plate_normal, uv_z).rgb * 2.0 - 1.0) * weights.z;
	ALBEDO = albedo * paint_tint.rgb;
	NORMAL_MAP = normalize(normal_map) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.28;
	ROUGHNESS = texture(plate_roughness, uv_y).r * 0.7 + 0.2;
	METALLIC = 0.36;
}
