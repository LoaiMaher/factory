extends Node
class_name FrontierBenchmark

const DEFAULT_SECONDS: float = 60.0
const DEFAULT_WARMUP: float = 5.0
const HITCH_33_MS: float = 33.3
const HITCH_50_MS: float = 50.0
const MIN_FLY_CLEARANCE: float = 25.0
const ROUTES: Array[String] = ["flythrough", "walk", "factory"]

var main_node: Node
var graphics_settings: FrontierGraphicsSettings
var launch_options: Dictionary = {}
var route: String = ""
var duration_seconds: float = DEFAULT_SECONDS
var warmup_seconds: float = DEFAULT_WARMUP
var main_ready_ms: float = 0.0
var terrain_build_ms: float = 0.0
var foliage_build_ms: float = 0.0
var terrain: FactoryTerrain
var player: FactoryPlayer
var camera: Camera3D
var route_points: Array[Vector3] = []
var route_altitudes: Array[float] = []
var segment_lengths: Array[float] = []
var route_length: float = 0.0
var route_progress: float = 0.0
var run_started_usec: int = 0
var last_tick_usec: int = 0
var collection_started_usec: int = 0
var warmup_frame_count: int = 0
var warmup_max_frame_ms: float = 0.0
var frame_samples: Array[Dictionary] = []
var output_base_path: String = ""
var finished: bool = false

static func collect_command_line_args() -> PackedStringArray:
	var result: PackedStringArray = OS.get_cmdline_args()
	for argument: String in OS.get_cmdline_user_args():
		if not result.has(argument):
			result.append(argument)
	return result

static func parse_arguments(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {
		"enabled": false,
		"route": "",
		"preset": "",
		"seconds": DEFAULT_SECONDS,
		"warmup": DEFAULT_WARMUP
	}
	for argument: String in arguments:
		if argument == "--" or argument == "++":
			continue
		var normalized: String = argument
		if normalized.begins_with("--") or normalized.begins_with("++"):
			normalized = normalized.substr(2)
		var separator: int = normalized.find("=")
		if separator < 0:
			continue
		var key: String = normalized.substr(0, separator)
		var value: String = normalized.substr(separator + 1)
		match key:
			"benchmark":
				result["route"] = value.to_lower()
				result["enabled"] = true
			"preset":
				result["preset"] = value.to_lower()
			"bench-seconds":
				result["seconds"] = maxf(1.0, value.to_float())
			"bench-warmup":
				result["warmup"] = maxf(0.0, value.to_float())
	return result

static func should_load_save(options: Dictionary) -> bool:
	return not bool(options.get("enabled", false))

static func summarize_frame_times(frame_times_ms: Array[float]) -> Dictionary:
	if frame_times_ms.is_empty():
		return {
			"average_fps": 0.0, "one_percent_low_fps": 0.0,
			"zero_point_one_percent_low_fps": 0.0, "p50_ms": 0.0,
			"p95_ms": 0.0, "p99_ms": 0.0, "max_ms": 0.0,
			"hitches_over_33_3_ms": 0, "hitches_over_50_ms": 0
		}
	var total_ms: float = 0.0
	var hitch_33: int = 0
	var hitch_50: int = 0
	for frame_ms: float in frame_times_ms:
		total_ms += frame_ms
		if frame_ms > HITCH_33_MS:
			hitch_33 += 1
		if frame_ms > HITCH_50_MS:
			hitch_50 += 1
	var average_ms: float = total_ms / float(frame_times_ms.size())
	return {
		"average_fps": 1000.0 / average_ms if average_ms > 0.0 else 0.0,
		"one_percent_low_fps": 1000.0 / _mean_slowest(frame_times_ms, 0.01),
		"zero_point_one_percent_low_fps": 1000.0 / _mean_slowest(frame_times_ms, 0.001),
		"p50_ms": _percentile(frame_times_ms, 0.50),
		"p95_ms": _percentile(frame_times_ms, 0.95),
		"p99_ms": _percentile(frame_times_ms, 0.99),
		"max_ms": _percentile(frame_times_ms, 1.0),
		"hitches_over_33_3_ms": hitch_33,
		"hitches_over_50_ms": hitch_50
	}

static func _mean_slowest(values: Array[float], fraction: float) -> float:
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var count: int = maxi(1, ceili(float(sorted_values.size()) * fraction))
	var total: float = 0.0
	for index: int in range(sorted_values.size() - count, sorted_values.size()):
		total += sorted_values[index]
	return total / float(count)

static func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var index: int = clampi(ceili(float(sorted_values.size()) * fraction) - 1, 0,
		sorted_values.size() - 1)
	return sorted_values[index]

func configure(factory_main: Node, settings: FrontierGraphicsSettings, options: Dictionary,
		ready_ms: float, terrain_ms: float, foliage_ms: float) -> void:
	main_node = factory_main
	graphics_settings = settings
	launch_options = options
	route = str(options.get("route", "")).to_lower()
	duration_seconds = maxf(1.0, float(options.get("seconds", DEFAULT_SECONDS)))
	warmup_seconds = maxf(0.0, float(options.get("warmup", DEFAULT_WARMUP)))
	main_ready_ms = ready_ms
	terrain_build_ms = terrain_ms
	foliage_build_ms = foliage_ms

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not ROUTES.has(route):
		printerr("Unknown benchmark route: %s" % route)
		get_tree().quit(1)
		return
	terrain = main_node.get("terrain") as FactoryTerrain
	player = main_node.get("player") as FactoryPlayer
	camera = get_viewport().get_camera_3d()
	if terrain == null or player == null or camera == null:
		printerr("Benchmark requires the initialized terrain, player, and camera.")
		get_tree().quit(1)
		return
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	var hud: FactoryHUD = main_node.get("hud") as FactoryHUD
	if hud != null:
		hud.set_process_input(false)
		hud.set_process_unhandled_input(false)
	_prepare_route()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	run_started_usec = Time.get_ticks_usec()
	last_tick_usec = run_started_usec

func _process(_delta: float) -> void:
	if finished or run_started_usec == 0:
		return
	var now_usec: int = Time.get_ticks_usec()
	var elapsed_before_frame: float = float(last_tick_usec - run_started_usec) / 1000000.0
	var frame_ms: float = float(now_usec - last_tick_usec) / 1000.0
	last_tick_usec = now_usec
	var elapsed_seconds: float = float(now_usec - run_started_usec) / 1000000.0
	_update_route(maxf(0.0, elapsed_seconds - warmup_seconds))
	if elapsed_before_frame < warmup_seconds:
		warmup_frame_count += 1
		warmup_max_frame_ms = maxf(warmup_max_frame_ms, frame_ms)
		return
	if collection_started_usec == 0:
		collection_started_usec = now_usec
	var sample_elapsed: float = float(now_usec - collection_started_usec) / 1000000.0
	frame_samples.append(_collect_sample(frame_ms, sample_elapsed))
	if sample_elapsed >= duration_seconds:
		_finish_benchmark()

func _prepare_route() -> void:
	var walk_xz: Array[Vector2] = [
		Vector2(0.0, 12.0), Vector2(110.0, 70.0), Vector2(245.0, -18.0),
		Vector2(350.0, -140.0), Vector2(250.0, -280.0), Vector2(40.0, -210.0),
		Vector2(-100.0, -80.0), Vector2(0.0, 12.0)
	]
	var fly_xz: Array[Vector2] = [
		Vector2(0.0, 38.0), Vector2(420.0, -90.0), Vector2(-205.0, 190.0),
		Vector2(-360.0, -260.0), Vector2(0.0, 38.0)
	]
	var fly_altitudes: Array[float] = [35.0, 55.0, 42.0, 28.0, 35.0]
	if route == "walk":
		for point: Vector2 in walk_xz:
			route_points.append(Vector3(point.x, terrain.height_at(point.x, point.y), point.y))
	elif route == "flythrough":
		for index: int in range(fly_xz.size()):
			var point: Vector2 = fly_xz[index]
			route_altitudes.append(fly_altitudes[index])
			route_points.append(Vector3(point.x,
				terrain.height_at(point.x, point.y) + maxf(fly_altitudes[index], MIN_FLY_CLEARANCE),
				point.y))
	for index: int in range(route_points.size() - 1):
		var length: float = route_points[index].distance_to(route_points[index + 1])
		segment_lengths.append(length)
		route_length += length
	if route == "walk":
		player.global_position = route_points[0]
		_set_camera_transform(route_points[0] + Vector3.UP * 1.62,
			route_points[0] + Vector3(0.0, 1.62, -10.0))
	elif route == "flythrough":
		_set_camera_transform(route_points[0],
			terrain.global_position + Vector3(0.0, terrain.height_at(0.0, 38.0), 0.0))
	else:
		var center: Vector3 = _factory_center()
		_set_factory_camera(center, 0.0)

func _update_route(route_elapsed: float) -> void:
	if route == "factory":
		var center: Vector3 = _factory_center()
		var angle: float = TAU * route_elapsed / duration_seconds
		_set_factory_camera(center, angle)
		route_progress = fposmod(route_elapsed / duration_seconds, 1.0)
		return
	if route == "walk":
		var distance: float = fposmod(route_elapsed * 11.5, maxf(0.001, route_length))
		var ground_position: Vector3 = _sample_route(distance)
		var walk_look_position: Vector3 = _sample_route(
			fposmod(distance + 5.0, maxf(0.001, route_length)))
		player.global_position = ground_position
		_set_camera_transform(ground_position + Vector3.UP * 1.62,
			walk_look_position + Vector3.UP * 1.62)
		route_progress = distance / route_length
		return
	var flight_distance: float = fposmod(route_elapsed * route_length / duration_seconds,
		maxf(0.001, route_length))
	var flight_position: Vector3 = _sample_route(flight_distance)
	var flight_look_position: Vector3 = _sample_route(fposmod(flight_distance + 2.0, route_length))
	_set_camera_transform(flight_position, flight_look_position)
	route_progress = flight_distance / route_length

func _sample_route(distance: float) -> Vector3:
	var remaining: float = distance
	for index: int in range(segment_lengths.size()):
		var segment_length: float = segment_lengths[index]
		if remaining <= segment_length:
			var weight: float = remaining / maxf(segment_length, 0.001)
			var point: Vector3 = route_points[index].lerp(route_points[index + 1], weight)
			var ground_height: float = terrain.height_at(point.x, point.z)
			if route == "walk":
				point.y = ground_height
			elif route == "flythrough":
				var altitude: float = lerpf(route_altitudes[index], route_altitudes[index + 1], weight)
				point.y = ground_height + maxf(altitude, MIN_FLY_CLEARANCE)
			return point
		remaining -= segment_length
	return route_points[route_points.size() - 1]

func _set_factory_camera(center: Vector3, angle: float) -> void:
	var camera_position: Vector3 = center + Vector3(sin(angle) * 32.0, 16.0, cos(angle) * 32.0)
	_set_camera_transform(camera_position, center)

func _factory_center() -> Vector3:
	return Vector3(-17.0, terrain.height_at(-17.0, 8.0) + 2.0, 8.0)

func _set_camera_transform(position: Vector3, target: Vector3) -> void:
	camera.global_position = position
	camera.look_at(target, Vector3.UP)

func _collect_sample(frame_ms: float, elapsed_seconds: float) -> Dictionary:
	var viewport_rid: RID = get_viewport().get_viewport_rid()
	return {
		"timestamp_s": elapsed_seconds,
		"route_progress": route_progress,
		"frame_time_ms": frame_ms,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"vram_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)
	}

func _finish_benchmark() -> void:
	finished = true
	var times: Array[float] = []
	var vram_values: Array[float] = []
	var ram_values: Array[float] = []
	var draw_call_values: Array[float] = []
	for sample: Dictionary in frame_samples:
		times.append(float(sample["frame_time_ms"]))
		vram_values.append(float(sample["vram_bytes"]))
		ram_values.append(float(sample["static_memory_bytes"]))
		draw_call_values.append(float(sample["draw_calls"]))
	var stats: Dictionary = summarize_frame_times(times)
	var summary: Dictionary = stats.duplicate()
	summary.merge({
		"route": route,
		"preset": graphics_settings.preset,
		"frame_count": frame_samples.size(),
		"warmup_frames": warmup_frame_count,
		"warmup_max_frame_time_ms": warmup_max_frame_ms,
		"duration_seconds": duration_seconds,
		"hitch_counts": {
			"over_33_3_ms": int(stats["hitches_over_33_3_ms"]),
			"over_50_ms": int(stats["hitches_over_50_ms"])
		},
		"hitch_frames_over_33_3_ms": _hitch_records(HITCH_33_MS),
		"hitch_frames_over_50_ms": _hitch_records(HITCH_50_MS),
		"average_vram_bytes": _average(vram_values),
		"peak_vram_bytes": _maximum(vram_values),
		"average_static_memory_bytes": _average(ram_values),
		"peak_static_memory_bytes": _maximum(ram_values),
		"average_draw_calls": _average(draw_call_values),
		"startup": {
			"engine_start_to_main_ready_ms": main_ready_ms,
			"terrain_build_ms": terrain_build_ms,
			"foliage_build_ms": foliage_build_ms
		},
		"system": _system_info(),
		"gpu_utilization_percent": null,
		"cpu_utilization_percent": null,
		"utilization_note": "Godot does not expose GPU or CPU utilization percentages; use PresentMon for Windows measurements."
	}, true)
	if not _write_results(summary):
		get_tree().quit(1)
		return
	print("BENCHMARK_SUMMARY %s" % JSON.stringify(summary))
	get_tree().quit(0)

func _hitch_records(threshold_ms: float) -> Array[Dictionary]:
	var hitches: Array[Dictionary] = []
	for sample: Dictionary in frame_samples:
		var frame_ms: float = float(sample["frame_time_ms"])
		if frame_ms > threshold_ms:
			hitches.append({
				"timestamp_s": sample["timestamp_s"],
				"route_progress": sample["route_progress"],
				"frame_time_ms": frame_ms
			})
	return hitches

func _system_info() -> Dictionary:
	var resolution: Vector2i = DisplayServer.window_get_size()
	return {
		"os": OS.get_name(),
		"os_version": OS.get_version(),
		"processor": OS.get_processor_name(),
		"processor_count": OS.get_processor_count(),
		"adapter_name": RenderingServer.get_video_adapter_name(),
		"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"adapter_api_version": RenderingServer.get_video_adapter_api_version(),
		"resolution": {"width": resolution.x, "height": resolution.y},
		"render_scale": graphics_settings.render_scale,
		"preset": graphics_settings.preset,
		"godot_version": str(Engine.get_version_info().get("string", "unknown"))
	}

func _write_results(summary: Dictionary) -> bool:
	var directory: String = "user://benchmarks"
	var absolute_directory: String = ProjectSettings.globalize_path(directory)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		printerr("Could not create benchmark output directory: %s" % make_error)
		return false
	var date: Dictionary = Time.get_datetime_dict_from_system()
	var timestamp: String = "%04d%02d%02d_%02d%02d%02d" % [
		date["year"], date["month"], date["day"], date["hour"], date["minute"], date["second"]
	]
	output_base_path = "%s/%s_%s_%s" % [directory, timestamp, route, graphics_settings.preset]
	summary["output_base_path"] = output_base_path
	var json_file: FileAccess = FileAccess.open(output_base_path + ".json", FileAccess.WRITE)
	if json_file == null:
		printerr("Could not write benchmark JSON: %s" % FileAccess.get_open_error())
		return false
	json_file.store_string(JSON.stringify(summary, "\t"))
	json_file.close()
	var csv_file: FileAccess = FileAccess.open(output_base_path + ".csv", FileAccess.WRITE)
	if csv_file == null:
		printerr("Could not write benchmark CSV: %s" % FileAccess.get_open_error())
		return false
	csv_file.store_csv_line(PackedStringArray([
		"timestamp_s", "route_progress", "frame_time_ms", "process_ms", "physics_ms",
		"gpu_ms", "render_cpu_ms", "draw_calls", "objects", "primitives",
		"vram_bytes", "static_memory_bytes"
	]))
	for sample: Dictionary in frame_samples:
		var row: PackedStringArray = PackedStringArray()
		for key: String in [
			"timestamp_s", "route_progress", "frame_time_ms", "process_ms", "physics_ms",
			"gpu_ms", "render_cpu_ms", "draw_calls", "objects", "primitives",
			"vram_bytes", "static_memory_bytes"
		]:
			row.append(str(sample[key]))
		csv_file.store_csv_line(row)
	csv_file.close()
	return true

func _average(values: Array[float]) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size()) if not values.is_empty() else 0.0

func _maximum(values: Array[float]) -> float:
	var result: float = 0.0
	for value: float in values:
		result = maxf(result, value)
	return result
