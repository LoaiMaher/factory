extends RefCounted
class_name FactoryIconCache

signal icons_ready

const ICON_SIZE: int = 128

var icons: Dictionary = {}
var prepared: bool = false

func get_icon(slot_type: String, id: String) -> Texture2D:
	return icons.get("%s:%s" % [slot_type, id]) as Texture2D

func prepare(host: Node, machine_models: MachineModels, visuals: FactoryVisuals) -> void:
	if prepared or (DisplayServer.get_name() == "headless" and OS.get_name() != "Web"):
		return
	var viewport: SubViewport = SubViewport.new()
	viewport.name = "HotbarIconViewport"
	viewport.size = Vector2i(ICON_SIZE, ICON_SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(viewport)
	var scene: Node3D = Node3D.new()
	scene.name = "IconScene"
	viewport.add_child(scene)
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a7b2ba")
	environment.ambient_light_energy = 0.8
	world_environment.environment = environment
	scene.add_child(world_environment)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 34.0
	camera.current = true
	scene.add_child(camera)
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35.0, 32.0, 0.0)
	key_light.light_color = Color("fff0db")
	key_light.light_energy = 1.45
	key_light.shadow_enabled = false
	scene.add_child(key_light)
	var rim_light: DirectionalLight3D = DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-20.0, -145.0, 0.0)
	rim_light.light_color = Color("88b9df")
	rim_light.light_energy = 0.7
	rim_light.shadow_enabled = false
	scene.add_child(rim_light)

	var building_definitions: Dictionary = BuildingDefs.all()
	for id: String in building_definitions:
		if id == "spire":
			continue
		if id == "belt_mk2":
			icons["building:belt_mk2"] = icons.get("building:belt_mk1")
			continue
		var preview: Node3D = _building_preview(id, machine_models, visuals)
		if preview == null:
			continue
		scene.add_child(preview)
		_frame_preview(camera, preview, BuildingDefs.size_of(id))
		await RenderingServer.frame_post_draw
		_store_viewport_icon(viewport, "building", id)
		preview.queue_free()
		await host.get_tree().process_frame

	for item_id: String in Items.all():
		var item_root: Node3D = Node3D.new()
		var item: MeshInstance3D = MeshInstance3D.new()
		item.mesh = visuals._item_mesh(item_id)
		item.material_override = visuals._item_material(item_id)
		item_root.add_child(item)
		scene.add_child(item_root)
		_frame_preview(camera, item_root, item.mesh.get_aabb().size, true)
		await RenderingServer.frame_post_draw
		_store_viewport_icon(viewport, "item", item_id)
		item_root.queue_free()
		await host.get_tree().process_frame

	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.queue_free()
	prepared = true
	icons_ready.emit()

func _building_preview(id: String, machine_models: MachineModels, visuals: FactoryVisuals) -> Node3D:
	if id == "belt_pole":
		var entity: FactoryEntity = FactoryEntity.new()
		entity.kind = id
		return visuals._make_entity_visual(entity)
	var root: Node3D = Node3D.new()
	var size: Vector3 = BuildingDefs.size_of(id)
	machine_models.build(id, root,
		Vector2i(maxi(1, roundi(size.x * 0.5)), maxi(1, roundi(size.z * 0.5))), Vector3.ZERO)
	if root.get_child_count() == 0:
		root.queue_free()
		return null
	return root

func _frame_preview(camera: Camera3D, preview: Node3D, dimensions: Vector3, item_icon: bool = false) -> void:
	preview.position = Vector3.ZERO
	preview.rotation = Vector3.ZERO
	preview.rotation.y = deg_to_rad(34.0)
	var height: float = maxf(dimensions.y, 0.05 if item_icon else 0.5)
	var radius: float = maxf(dimensions.x, dimensions.z)
	var target: Vector3 = Vector3.ZERO if item_icon else Vector3(0.0, height * 0.38, 0.0)
	var distance: float = maxf(1.7, maxf(radius, height) * 1.35)
	if item_icon:
		distance = maxf(0.32, maxf(radius, height) * 1.5)
	camera.position = target + Vector3(distance * 0.74, distance * 0.48, distance)
	camera.look_at(target, Vector3.UP)

func _store_viewport_icon(viewport: SubViewport, slot_type: String, id: String) -> void:
	var image: Image = viewport.get_texture().get_image()
	if image != null and not image.is_empty():
		icons["%s:%s" % [slot_type, id]] = ImageTexture.create_from_image(image)
