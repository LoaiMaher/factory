extends RefCounted
class_name FrontierGraphicsSettings

const SETTINGS_PATH: String = "user://settings.cfg"
const PRESETS: Dictionary = {
	"low": {
		"shadow_atlas_size": 2048, "soft_shadow_quality": "low", "shadow_distance": 180.0,
		"ssao": false, "ssil": false, "glow": false, "volumetric_fog": false,
		"foliage_density": 0.5, "grass_radius": 35.0, "tree_view_distance": 180.0,
		"antialiasing": "fxaa", "render_scale": 1.0, "scaling_mode": "bilinear"
	},
	"medium": {
		"shadow_atlas_size": 4096, "soft_shadow_quality": "medium", "shadow_distance": 300.0,
		"ssao": true, "ssil": false, "glow": false, "volumetric_fog": false,
		"foliage_density": 0.75, "grass_radius": 48.0, "tree_view_distance": 300.0,
		"antialiasing": "taa", "render_scale": 1.0, "scaling_mode": "bilinear"
	},
	"high": {
		"shadow_atlas_size": 4096, "soft_shadow_quality": "high", "shadow_distance": 450.0,
		"ssao": true, "ssil": true, "glow": true, "volumetric_fog": true,
		"foliage_density": 1.0, "grass_radius": 60.0, "tree_view_distance": 450.0,
		"antialiasing": "taa", "render_scale": 1.0, "scaling_mode": "bilinear"
	},
	"ultra": {
		"shadow_atlas_size": 8192, "soft_shadow_quality": "ultra", "shadow_distance": 700.0,
		"ssao": true, "ssil": true, "glow": true, "volumetric_fog": true,
		"foliage_density": 1.25, "grass_radius": 75.0, "tree_view_distance": 600.0,
		"antialiasing": "taa", "render_scale": 1.0, "scaling_mode": "bilinear"
	}
}

var settings_path: String = SETTINGS_PATH
var preset: String = "high"
var window_mode: String = "windowed"
var vsync: bool = true
var max_fps: int = 0
var render_scale: float = 1.0
var scaling_mode: String = "bilinear"
var antialiasing: String = "taa"
var shadow_atlas_size: int = 4096
var soft_shadow_quality: String = "high"
var shadow_distance: float = 450.0
var shadow_split_1: float = 0.1
var shadow_split_2: float = 0.25
var shadow_split_3: float = 0.55
var ssao: bool = true
var ssil: bool = true
var glow: bool = true
var volumetric_fog: bool = true
var foliage_density: float = 1.0
var grass_radius: float = 60.0
var tree_view_distance: float = 450.0

func _init() -> void:
	apply_preset("high")

func apply_preset(preset_name: String) -> bool:
	var normalized: String = preset_name.to_lower()
	if not PRESETS.has(normalized):
		return false
	var values: Dictionary = PRESETS[normalized]
	preset = normalized
	shadow_atlas_size = int(values["shadow_atlas_size"])
	soft_shadow_quality = str(values["soft_shadow_quality"])
	shadow_distance = float(values["shadow_distance"])
	ssao = bool(values["ssao"])
	ssil = bool(values["ssil"])
	glow = bool(values["glow"])
	volumetric_fog = bool(values["volumetric_fog"])
	foliage_density = float(values["foliage_density"])
	grass_radius = float(values["grass_radius"])
	tree_view_distance = float(values["tree_view_distance"])
	antialiasing = str(values["antialiasing"])
	render_scale = float(values["render_scale"])
	scaling_mode = str(values["scaling_mode"])
	return true

func load_settings(path: String = "") -> bool:
	if not path.is_empty():
		settings_path = path
	var config: ConfigFile = ConfigFile.new()
	if config.load(settings_path) != OK:
		return false
	var section: String = "graphics"
	preset = str(config.get_value(section, "preset", preset))
	window_mode = str(config.get_value(section, "window_mode", window_mode))
	vsync = bool(config.get_value(section, "vsync", vsync))
	max_fps = int(config.get_value(section, "max_fps", max_fps))
	render_scale = clampf(float(config.get_value(section, "render_scale", render_scale)), 0.5, 1.0)
	scaling_mode = str(config.get_value(section, "scaling_mode", scaling_mode))
	antialiasing = str(config.get_value(section, "antialiasing", antialiasing))
	shadow_atlas_size = clampi(int(config.get_value(section, "shadow_atlas_size", shadow_atlas_size)), 1024, 8192)
	soft_shadow_quality = str(config.get_value(section, "soft_shadow_quality", soft_shadow_quality))
	shadow_distance = clampf(float(config.get_value(section, "shadow_distance", shadow_distance)), 60.0, 1100.0)
	shadow_split_1 = clampf(float(config.get_value(section, "shadow_split_1", shadow_split_1)), 0.0, 1.0)
	shadow_split_2 = clampf(float(config.get_value(section, "shadow_split_2", shadow_split_2)), 0.0, 1.0)
	shadow_split_3 = clampf(float(config.get_value(section, "shadow_split_3", shadow_split_3)), 0.0, 1.0)
	ssao = bool(config.get_value(section, "ssao", ssao))
	ssil = bool(config.get_value(section, "ssil", ssil))
	glow = bool(config.get_value(section, "glow", glow))
	volumetric_fog = bool(config.get_value(section, "volumetric_fog", volumetric_fog))
	foliage_density = clampf(float(config.get_value(section, "foliage_density", foliage_density)), 0.5, 1.25)
	grass_radius = clampf(float(config.get_value(section, "grass_radius", grass_radius)), 20.0, 100.0)
	tree_view_distance = clampf(float(config.get_value(section, "tree_view_distance", tree_view_distance)), 100.0, 720.0)
	if preset not in ["low", "medium", "high", "ultra", "custom"]:
		preset = "custom"
	return true

func save_settings(path: String = "") -> bool:
	if not path.is_empty():
		settings_path = path
	var config: ConfigFile = ConfigFile.new()
	var section: String = "graphics"
	for key: String in to_dict():
		config.set_value(section, key, get(key))
	return config.save(settings_path) == OK

func to_dict() -> Dictionary:
	return {
		"preset": preset,
		"window_mode": window_mode,
		"vsync": vsync,
		"max_fps": max_fps,
		"render_scale": render_scale,
		"scaling_mode": scaling_mode,
		"antialiasing": antialiasing,
		"shadow_atlas_size": shadow_atlas_size,
		"soft_shadow_quality": soft_shadow_quality,
		"shadow_distance": shadow_distance,
		"shadow_split_1": shadow_split_1,
		"shadow_split_2": shadow_split_2,
		"shadow_split_3": shadow_split_3,
		"ssao": ssao,
		"ssil": ssil,
		"glow": glow,
		"volumetric_fog": volumetric_fog,
		"foliage_density": foliage_density,
		"grass_radius": grass_radius,
		"tree_view_distance": tree_view_distance
	}

func apply(viewport: Viewport, environment: Environment,
		sun: DirectionalLight3D, foliage: FactoryFoliage) -> bool:
	if DisplayServer.get_name() != "headless":
		var mode: int = DisplayServer.WINDOW_MODE_WINDOWED
		match window_mode:
			"borderless":
				mode = DisplayServer.WINDOW_MODE_FULLSCREEN
			"exclusive":
				mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	if viewport != null:
		viewport.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)
		viewport.scaling_3d_mode = _scaling_mode_value()
		viewport.msaa_3d = _msaa_value()
		viewport.use_taa = antialiasing == "taa"
		viewport.screen_space_aa = _screen_space_aa_value()
	RenderingServer.directional_shadow_atlas_set_size(shadow_atlas_size, false)
	RenderingServer.directional_soft_shadow_filter_set_quality(_soft_shadow_quality_value())
	if environment != null:
		environment.ssao_enabled = ssao
		environment.ssil_enabled = ssil
		environment.glow_enabled = glow
		environment.volumetric_fog_enabled = volumetric_fog
	if sun != null:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = shadow_distance
		sun.directional_shadow_split_1 = shadow_split_1
		sun.directional_shadow_split_2 = shadow_split_2
		sun.directional_shadow_split_3 = shadow_split_3
	return foliage.set_graphics_options(foliage_density, grass_radius, tree_view_distance) \
		if foliage != null else false

func _screen_space_aa_value() -> int:
	match antialiasing:
		"fxaa":
			return Viewport.SCREEN_SPACE_AA_FXAA
		"smaa":
			return Viewport.SCREEN_SPACE_AA_SMAA
		_:
			return Viewport.SCREEN_SPACE_AA_DISABLED

func _msaa_value() -> int:
	match antialiasing:
		"msaa2x":
			return Viewport.MSAA_2X
		"msaa4x":
			return Viewport.MSAA_4X
		_:
			return Viewport.MSAA_DISABLED

func _scaling_mode_value() -> int:
	match scaling_mode:
		"fsr1":
			return Viewport.SCALING_3D_MODE_FSR
		"fsr2":
			return Viewport.SCALING_3D_MODE_FSR2
		_:
			return Viewport.SCALING_3D_MODE_BILINEAR

func _soft_shadow_quality_value() -> int:
	match soft_shadow_quality:
		"very_low":
			return RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW
		"low":
			return RenderingServer.SHADOW_QUALITY_SOFT_LOW
		"medium":
			return RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
		"ultra":
			return RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
		_:
			return RenderingServer.SHADOW_QUALITY_SOFT_HIGH
