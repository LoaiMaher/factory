shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.27, 0.48, 0.49, 1.0);
uniform vec4 deep_color : source_color = vec4(0.10, 0.23, 0.29, 1.0);
uniform sampler2D wave_normal : hint_normal, repeat_enable, filter_linear_mipmap;

#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
#endif

void fragment() {
	vec2 uv = UV * 5.0;
	vec3 wave_a = texture(wave_normal, uv + vec2(TIME * 0.014, TIME * 0.008)).rgb * 2.0 - 1.0;
	vec3 wave_b = texture(wave_normal, uv * 1.61 - vec2(TIME * 0.009, TIME * 0.012)).rgb * 2.0 - 1.0;
	NORMAL_MAP = normalize(vec3(wave_a.xy * 0.18 + wave_b.xy * 0.14, max(wave_a.z + wave_b.z, 0.4)));
	NORMAL_MAP_DEPTH = 0.52;

	float fresnel = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
	float shore = 0.0;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	float depth_gap = texture(scene_depth, SCREEN_UV).r - FRAGCOORD.z;
	shore = 1.0 - smoothstep(0.0005, 0.025, depth_gap);
#endif
	vec3 tint = mix(deep_color.rgb, water_color.rgb, max(shore, 0.36));
	ALBEDO = mix(tint, water_color.rgb, fresnel * 0.55);
	ROUGHNESS = 0.18;
	METALLIC = 0.08;
	SPECULAR = 0.86;
	ALPHA = 0.8 + fresnel * 0.1;
}
