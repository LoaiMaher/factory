extends CanvasLayer
class_name FrontierPerfOverlay

const WINDOW_SECONDS: float = 2.0

var graphics_settings: FrontierGraphicsSettings
var panel: PanelContainer
var summary_label: Label
var samples: Array[Dictionary] = []
var update_elapsed: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.position = Vector2(18.0, 175.0)
	panel.custom_minimum_size = Vector2(600.0, 185.0)
	panel.visible = false
	add_child(panel)
	summary_label = Label.new()
	summary_label.add_theme_font_size_override("font_size", 14)
	summary_label.add_theme_color_override("font_color", Color("d8f0d5"))
	summary_label.add_theme_color_override("font_outline_color", Color("142018"))
	summary_label.add_theme_constant_override("outline_size", 2)
	panel.add_child(summary_label)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func configure(settings: FrontierGraphicsSettings) -> void:
	graphics_settings = settings

func toggle_overlay() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func _process(delta: float) -> void:
	if not panel.visible:
		return
	var now_usec: int = Time.get_ticks_usec()
	samples.append({"time_usec": now_usec, "frame_ms": delta * 1000.0})
	while not samples.is_empty() \
			and float(now_usec - int(samples[0]["time_usec"])) / 1000000.0 > WINDOW_SECONDS:
		samples.pop_front()
	update_elapsed += delta
	if update_elapsed < 0.2:
		return
	update_elapsed = 0.0
	var frame_times: Array[float] = []
	var frame_total: float = 0.0
	for sample: Dictionary in samples:
		var frame_ms: float = float(sample["frame_ms"])
		frame_times.append(frame_ms)
		frame_total += frame_ms
	var average_ms: float = frame_total / maxf(1.0, float(frame_times.size()))
	var p99_ms: float = _percentile(frame_times, 0.99)
	var root_rid: RID = get_viewport().get_viewport_rid()
	var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(root_rid)
	var render_cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(root_rid)
	var draw_calls: int = roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects: int = roundi(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var primitives: int = roundi(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var static_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var node_count: int = roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var preset_name: String = graphics_settings.preset if graphics_settings != null else "unknown"
	summary_label.text = "PERFORMANCE  [F3]\nFPS %d  ·  frame avg %.2f ms  ·  p99 %.2f ms\nCPU process %.2f ms  ·  physics %.2f ms\nGPU %.2f ms  ·  render CPU %.2f ms\nDraw calls %d  ·  objects %d  ·  primitives %d\nVRAM %.1f MB  ·  static memory %.1f MB  ·  nodes %d\nAdapter %s  ·  preset %s" % [
		Engine.get_frames_per_second(), average_ms, p99_ms,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		gpu_ms, render_cpu_ms, draw_calls, objects, primitives, vram_mb, static_mb,
		node_count, RenderingServer.get_video_adapter_name(), preset_name
	]

func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var index: int = clampi(ceili(fraction * float(sorted_values.size())) - 1, 0,
		sorted_values.size() - 1)
	return sorted_values[index]
