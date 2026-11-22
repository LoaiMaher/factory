extends CanvasLayer
class_name FactoryViewmodel

const VIEWMODEL_LAYER: int = 20
const VIEWMODEL_MASK: int = 1 << (VIEWMODEL_LAYER - 1)
const SWITCH_LOWER_DURATION: float = 0.12
const SWITCH_RAISE_DURATION: float = 0.15
const MINING_SWING_DURATION: float = 0.36

var player: FactoryPlayer
var hud: FactoryHUD
var visuals: FactoryVisuals
var machine_models: MachineModels
var hotbar_model: HotbarModel
var build_system: FactoryBuildSystem
var viewport_container: SubViewportContainer
var view_subviewport: SubViewport
var overlay_camera: Camera3D
var render_root: Node3D
var hand_left: Node3D
var hand_right: Node3D
var build_tool: Node3D
var screen_icon: MeshInstance3D
var screen_material: StandardMaterial3D
var held_item: MeshInstance3D
var desired_action: Dictionary = {"type": "empty", "id": ""}
var current_action: Dictionary = {"type": "empty", "id": ""}
var left_hand_base: Vector3 = Vector3(-0.40, -0.31, -0.58)
var right_hand_base: Vector3 = Vector3(0.40, -0.31, -0.58)
var mining_pick: Node3D
var mining_active: bool = false
var switch_phase: int = 0
var switch_elapsed: float = 0.0
var mining_swing_elapsed: float = MINING_SWING_DURATION
var animation_time: float = 0.0
var mouse_lag: Vector2 = Vector2.ZERO
var mouse_lag_velocity: Vector2 = Vector2.ZERO
var mouse_lag_target: Vector2 = Vector2.ZERO
var last_screen_icon_id: String = ""

func setup(factory_player: FactoryPlayer, factory_hud: FactoryHUD,
		factory_visuals: FactoryVisuals, models: MachineModels,
		factory_hotbar: HotbarModel, factory_build_system: FactoryBuildSystem) -> void:
	player = factory_player
	hud = factory_hud
	visuals = factory_visuals
	machine_models = models
	hotbar_model = factory_hotbar
	build_system = factory_build_system

func _ready() -> void:
	layer = 0
	if player != null and player.camera != null:
		player.camera.set_cull_mask_value(VIEWMODEL_LAYER, false)
	if DisplayServer.get_name() == "headless" and OS.get_name() != "Web":
		return
	_create_overlay()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and player != null and player.mouse_captured:
		mouse_lag_target.x = clampf(mouse_lag_target.x - event.relative.x * 0.00012, -0.055, 0.055)
		mouse_lag_target.y = clampf(mouse_lag_target.y + event.relative.y * 0.00012, -0.045, 0.045)

func _process(delta: float) -> void:
	if player == null or overlay_camera == null:
		return
	animation_time += delta
	var viewport_size: Vector2i = Vector2i(get_viewport().get_visible_rect().size)
	if view_subviewport.size != viewport_size:
		view_subviewport.size = viewport_size
	overlay_camera.global_transform = player.camera.global_transform
	overlay_camera.fov = 60.0
	var spring: Vector2 = (mouse_lag_target - mouse_lag) * 72.0
	mouse_lag_velocity = (mouse_lag_velocity + spring * delta) * exp(-15.0 * delta)
	mouse_lag += mouse_lag_velocity * delta
	mouse_lag_target = mouse_lag_target.lerp(Vector2.ZERO, minf(delta * 4.0, 1.0))

	var horizontal_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var walk_strength: float = clampf(horizontal_speed / 6.0, 0.0, 1.0)
	var walk_phase: float = animation_time * lerpf(7.0, 11.0, walk_strength)
	var bob: float = sin(walk_phase) * 0.018 * walk_strength
	var idle_x: float = sin(animation_time * 1.15) * 0.007
	var idle_y: float = cos(animation_time * 1.4) * 0.005
	var switch_offset: float = _update_switch(delta)
	if hand_left != null:
		hand_left.scale = Vector3.ONE * 0.55
		hand_left.position = left_hand_base + Vector3(idle_x - mouse_lag.x, bob + idle_y + mouse_lag.y + switch_offset, 0.0)
		hand_left.rotation = Vector3(0.15, -0.45, -0.08 + mouse_lag.x * 0.2)
	if hand_right != null:
		var mining_rotation: float = _mining_swing_rotation(delta)
		var swing_offset: Vector3 = Vector3(0.0, mining_rotation * 0.3, -mining_rotation * 0.1)
		hand_right.scale = Vector3.ONE * 0.55
		hand_right.position = right_hand_base + Vector3(idle_x + mouse_lag.x,
			bob - idle_y + mouse_lag.y + switch_offset, 0.0) + swing_offset
		hand_right.rotation.x = 0.15 - mining_rotation * 0.4
		hand_right.rotation.y = 0.45
		hand_right.rotation.z = 0.06 + mouse_lag.x * 0.2
		if build_tool != null:
			build_tool.rotation.x = mining_rotation * 0.75
		if mining_pick != null:
			mining_pick.visible = mining_active
			mining_pick.rotation.x = -0.18 + mining_rotation * 0.9
	if build_tool != null:
		var dismantling: bool = build_system != null and build_system.dismantle_mode
		build_tool.visible = current_action.get("type", "empty") == "building" or dismantling
		if screen_material != null:
			screen_material.albedo_color = Color("ff3029") if dismantling else Color.WHITE
		if screen_icon != null:
			screen_icon.visible = build_tool.visible
	if held_item != null:
		held_item.visible = current_action.get("type", "") == "item" and not mining_active
		held_item.position = Vector3(0.0, 0.2, -0.3)
		held_item.rotation = Vector3(0.6, 0.5, 0.3)
	_update_screen_icon()

func set_action(action: Dictionary) -> void:
	if desired_action == action:
		return
	desired_action = action.duplicate(true)
	switch_phase = 1
	switch_elapsed = 0.0

func play_mining_swing() -> void:
	mining_swing_elapsed = 0.0

func set_mining_active(active: bool) -> void:
	mining_active = active

func _create_overlay() -> void:
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "ViewmodelViewportContainer"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport_container)
	view_subviewport = SubViewport.new()
	view_subviewport.name = "ViewmodelViewport"
	view_subviewport.size = Vector2i(get_viewport().get_visible_rect().size)
	view_subviewport.transparent_bg = true
	view_subviewport.own_world_3d = true
	view_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(view_subviewport)
	render_root = Node3D.new()
	render_root.name = "ViewmodelWorld"
	view_subviewport.add_child(render_root)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b2bdc4")
	environment.ambient_light_energy = 0.5
	environment_node.environment = environment
	render_root.add_child(environment_node)
	overlay_camera = Camera3D.new()
	overlay_camera.name = "ViewmodelCamera"
	overlay_camera.fov = 60.0
	overlay_camera.near = 0.04
	overlay_camera.far = 6.0
	overlay_camera.cull_mask = VIEWMODEL_MASK
	render_root.add_child(overlay_camera)
	overlay_camera.make_current()
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-40.0, 28.0, 0.0)
	key_light.light_color = Color("fff0db")
	key_light.light_energy = 1.15
	key_light.light_cull_mask = VIEWMODEL_MASK
	key_light.shadow_enabled = false
	render_root.add_child(key_light)
	var hands_scene: PackedScene = load("res://assets/models/hands.glb") as PackedScene
	if hands_scene != null:
		var hands: Node3D = hands_scene.instantiate() as Node3D
		overlay_camera.add_child(hands)
		hand_left = hands.find_child("Hand_L", true, false) as Node3D
		hand_right = hands.find_child("Hand_R", true, false) as Node3D
		machine_models.apply_pbr_materials(hands)
		if hand_left != null:
			hand_left.position = left_hand_base
			hand_left.rotation.z = -0.08
		if hand_right != null:
			hand_right.position = right_hand_base
		_set_viewmodel_layers(hands)
	else:
		push_error("Missing Blender hands model.")
	var tool_scene: PackedScene = load("res://assets/models/build_tool.glb") as PackedScene
	if tool_scene != null and hand_right != null:
		build_tool = tool_scene.instantiate() as Node3D
		build_tool.name = "BuildTool"
		hand_right.add_child(build_tool)
		build_tool.position = Vector3(-0.05, 0.27, 0.08)
		build_tool.scale = Vector3.ONE * 0.67
		build_tool.rotation = Vector3(-0.08, 0.0, 0.0)
		machine_models.apply_pbr_materials(build_tool)
		_set_viewmodel_layers(build_tool)
		build_tool.visible = false
		_create_screen_icon()
	else:
		push_error("Missing Blender build tool model or right hand.")
	var pick_scene: PackedScene = load("res://assets/models/hand_pick.glb") as PackedScene
	if pick_scene != null and hand_right != null:
		mining_pick = pick_scene.instantiate() as Node3D
		mining_pick.name = "MiningPick"
		hand_right.add_child(mining_pick)
		mining_pick.position = Vector3(-0.08, 0.02, -0.22)
		mining_pick.scale = Vector3.ONE * 0.82
		mining_pick.rotation.z = 0.35
		machine_models.apply_pbr_materials(mining_pick)
		_set_viewmodel_layers(mining_pick)
		mining_pick.visible = false
	if visuals != null and hand_right != null:
		held_item = MeshInstance3D.new()
		held_item.name = "HeldItem"
		held_item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		held_item.position = Vector3(0.0, 0.13, -0.43)
		held_item.scale = Vector3.ONE * 0.6
		hand_right.add_child(held_item)
		_set_viewmodel_layers(held_item)
		held_item.visible = false
	overlay_camera.global_transform = player.camera.global_transform
	_apply_current_action()

func _create_screen_icon() -> void:
	var screen: Node3D = build_tool.find_child("ToolScreen", true, false) as Node3D
	if screen == null:
		push_warning("Build tool has no ToolScreen node.")
		return
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.12, 0.08)
	screen_icon = MeshInstance3D.new()
	screen_icon.name = "BuildingScreenIcon"
	screen_icon.mesh = quad
	screen_icon.position.z = 0.008
	screen_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen_material = StandardMaterial3D.new()
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	screen_material.albedo_color = Color.WHITE
	screen_icon.material_override = screen_material
	screen.add_child(screen_icon)
	_set_viewmodel_layers(screen_icon)
	screen_icon.visible = false

func _set_viewmodel_layers(node: Node) -> void:
	if node is VisualInstance3D:
		var visual: VisualInstance3D = node as VisualInstance3D
		visual.layers = VIEWMODEL_MASK
		if visual is GeometryInstance3D:
			(visual as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_set_viewmodel_layers(child)

func _update_switch(delta: float) -> float:
	if switch_phase == 0:
		return 0.0
	switch_elapsed += delta
	if switch_phase == 1:
		var lower_t: float = clampf(switch_elapsed / SWITCH_LOWER_DURATION, 0.0, 1.0)
		if switch_elapsed >= SWITCH_LOWER_DURATION:
			_apply_current_action()
			switch_phase = 2
			switch_elapsed = 0.0
		return -0.3 * lower_t
	var raise_t: float = clampf(switch_elapsed / SWITCH_RAISE_DURATION, 0.0, 1.0)
	if switch_elapsed >= SWITCH_RAISE_DURATION:
		switch_phase = 0
	return -0.3 * (1.0 - raise_t)

func _apply_current_action() -> void:
	current_action = desired_action.duplicate(true)
	var action_type: String = str(current_action.get("type", "empty"))
	if held_item != null:
		held_item.visible = action_type == "item" and not mining_active
		if action_type == "item":
			var item_id: String = str(current_action.get("id", ""))
			held_item.mesh = visuals._item_mesh(item_id)
			held_item.material_override = visuals._item_material(item_id)

func _update_screen_icon() -> void:
	if screen_icon == null or screen_material == null or hud == null or hud.icon_cache == null:
		return
	var selected_id: String = str(current_action.get("id", "")) if current_action.get("type", "") == "building" else ""
	if selected_id.is_empty():
		last_screen_icon_id = ""
		screen_material.albedo_texture = null
		return
	var texture: Texture2D = hud.icon_cache.get_icon("building", selected_id)
	if texture == null:
		return
	if last_screen_icon_id != selected_id or screen_material.albedo_texture != texture:
		screen_material.albedo_texture = texture
		last_screen_icon_id = selected_id

func _mining_swing_rotation(delta: float) -> float:
	if mining_swing_elapsed >= MINING_SWING_DURATION:
		return 0.0
	mining_swing_elapsed = minf(MINING_SWING_DURATION, mining_swing_elapsed + delta)
	var progress: float = mining_swing_elapsed / MINING_SWING_DURATION
	return sin(progress * PI) * 0.62
