extends Node3D
class_name FactoryTerrain

var noise: FastNoiseLite = FastNoiseLite.new()
var nodes: Array[Dictionary] = []
var vents: Array[Vector3] = []
var hidden_iron: Vector3 = Vector3(124.0, 0.0, -40.0)
var spire_position: Vector3 = Vector3(0.0, 0.0, -28.0)
var landing_position: Vector3 = Vector3(0.0, 0.0, 12.0)
var building_definitions: Dictionary = BuildingDefs.all()
var resource_sites: Array[Vector2] = [
	Vector2(-17.0, -2.0), Vector2(-30.0, 18.0), Vector2(18.0, 3.0), Vector2(28.0, 15.0),
	Vector2(-12.0, -35.0), Vector2(14.0, -40.0), Vector2(-35.0, -30.0), Vector2(-43.0, 32.0),
	Vector2(70.0, 20.0)
]

func _ready() -> void:
	noise.seed = 8142
	noise.frequency = 0.012
	_build_ground()
	_build_boundaries()
	_build_nodes()
	_build_vents()
	_build_landing_site()

func height_at(x: float, z: float) -> float:
	var radius: float = Vector2(x, z).length()
	var valley_rise: float = maxf(0.0, radius - 105.0) * 0.03
	var undulation: float = noise.get_noise_2d(x, z) * (0.5 if radius < 90.0 else 2.2)
	var mountain_factor: float = clampf((radius - 145.0) / 85.0, 0.0, 1.0)
	mountain_factor = mountain_factor * mountain_factor * (3.0 - 2.0 * mountain_factor)
	var outer_mountains: float = mountain_factor * (48.0 + noise.get_noise_2d(x + 1200.0, z - 900.0) * 12.0)
	var ridge: float = 0.0
	if x > 28.0 and x < 118.0:
		var ridge_profile: float = sin((x - 28.0) / 90.0 * PI)
		ridge = maxf(0.0, ridge_profile) * (23.0 + noise.get_noise_2d(x + 900.0, z) * 5.0)
	return valley_rise + undulation + outer_mountains + ridge

func point_for_cell(cell: Vector2i) -> Vector3:
	var x: float = float(cell.x) * 2.0 + 1.0
	var z: float = float(cell.y) * 2.0 + 1.0
	return Vector3(x, height_at(x, z), z)

func footprint_height(cell: Vector2i, building_id: String, rotation: int = 0) -> float:
	var size: Vector2i = _building_size(building_id, rotation)
	var highest: float = -INF
	for x: int in range(size.x):
		for z: int in range(size.y):
			highest = maxf(highest, point_for_cell(cell + Vector2i(x, z)).y)
	return highest

func is_buildable(cell: Vector2i, building_id: String, rotation: int = 0) -> bool:
	var size: Vector2i = _building_size(building_id, rotation)
	for x: int in range(size.x):
		for z: int in range(size.y):
			var point: Vector3 = point_for_cell(cell + Vector2i(x, z))
			var slope_x: float = (height_at(point.x + 1.0, point.z) - height_at(point.x - 1.0, point.z)) * 0.5
			var slope_z: float = (height_at(point.x, point.z + 1.0) - height_at(point.x, point.z - 1.0)) * 0.5
			if Vector2(slope_x, slope_z).length() >= 0.35:
				return false
	return true

func has_vent_in_footprint(cell: Vector2i, building_id: String, rotation: int = 0) -> bool:
	var size: Vector2i = _building_size(building_id, rotation)
	for vent: Vector3 in vents:
		var vent_cell: Vector2i = cell_from_world(vent)
		if vent_cell.x >= cell.x and vent_cell.x < cell.x + size.x and vent_cell.y >= cell.y and vent_cell.y < cell.y + size.y:
			return true
	return false

func cell_from_world(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / 2.0), floori(point.z / 2.0))

func _building_size(building_id: String, rotation: int = 0) -> Vector2i:
	var size: Vector2i = building_definitions.get(building_id, {}).get("size", Vector2i.ONE)
	return size if posmod(rotation, 2) == 0 else Vector2i(size.y, size.x)

func _build_ground() -> void:
	var render_ground: bool = DisplayServer.get_name() != "headless"
	var surface: SurfaceTool = SurfaceTool.new()
	if render_ground:
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var divisions: int = 320
	var map_width: int = divisions + 1
	var half_extent: float = 320.0
	var step: float = half_extent * 2.0 / float(divisions)
	var height_samples: PackedFloat32Array = PackedFloat32Array()
	height_samples.resize(map_width * map_width)
	for z_index: int in range(map_width):
		for x_index: int in range(map_width):
			var x: float = -half_extent + float(x_index) * step
			var z: float = -half_extent + float(z_index) * step
			height_samples[z_index * map_width + x_index] = height_at(x, z)
	if render_ground:
		for z_index: int in range(divisions):
			for x_index: int in range(divisions):
				var x0: float = -half_extent + float(x_index) * step
				var z0: float = -half_extent + float(z_index) * step
				var p00: Vector3 = Vector3(x0, height_samples[z_index * map_width + x_index], z0)
				var p10: Vector3 = Vector3(x0 + step, height_samples[z_index * map_width + x_index + 1], z0)
				var p01: Vector3 = Vector3(x0, height_samples[(z_index + 1) * map_width + x_index], z0 + step)
				var p11: Vector3 = Vector3(x0 + step, height_samples[(z_index + 1) * map_width + x_index + 1], z0 + step)
				_add_terrain_triangle(surface, p00, p01, p10)
				_add_terrain_triangle(surface, p10, p01, p11)
		surface.generate_normals()
		var mesh: ArrayMesh = surface.commit()
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.92
		var ground: MeshInstance3D = MeshInstance3D.new()
		ground.mesh = mesh
		ground.material_override = material
		add_child(ground)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var heightmap: HeightMapShape3D = HeightMapShape3D.new()
	heightmap.map_width = map_width
	heightmap.map_depth = map_width
	heightmap.map_data = height_samples
	shape.shape = heightmap
	shape.scale = Vector3(2.0, 1.0, 2.0)
	body.add_child(shape)
	add_child(body)
	if not render_ground:
		return
	var sky: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("517caa")
	sky_material.sky_horizon_color = Color("c6d8d5")
	sky_material.ground_bottom_color = Color("303b35")
	sky_material.ground_horizon_color = Color("a0ae9e")
	var sky_resource: Sky = Sky.new()
	sky_resource.sky_material = sky_material
	environment.sky = sky_resource
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("aab5a2")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("b9c9c4")
	environment.fog_density = 0.00035
	sky.environment = environment
	add_child(sky)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)

func _build_boundaries() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	for wall_data: Dictionary in [
		{"size": Vector3(410.0, 420.0, 8.0), "position": Vector3(0.0, 150.0, -200.0)},
		{"size": Vector3(410.0, 420.0, 8.0), "position": Vector3(0.0, 150.0, 200.0)},
		{"size": Vector3(8.0, 420.0, 410.0), "position": Vector3(-200.0, 150.0, 0.0)},
		{"size": Vector3(8.0, 420.0, 410.0), "position": Vector3(200.0, 150.0, 0.0)}
	]:
		var collision: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = wall_data["size"]
		collision.shape = box
		collision.position = wall_data["position"]
		body.add_child(collision)
	add_child(body)

func _add_terrain_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var center: Vector3 = (a + b + c) / 3.0
	var slope: float = (b - a).cross(c - a).normalized().y
	var variation: float = noise.get_noise_2d(center.x + 320.0, center.z - 180.0) * 0.5 + 0.5
	var grass_color: Color = Color("607847").lerp(Color("92a462"), variation)
	var rock_color: Color = Color("625a4b").lerp(Color("93846d"), variation)
	var color: Color = grass_color
	if slope < 0.82 or (center.x > 28.0 and center.x < 118.0 and center.y > 10.0):
		color = rock_color
	else:
		color = color.lerp(rock_color, clampf((center.y - 24.0) / 32.0, 0.0, 1.0))
	if center.y > 54.0:
		var peak_color: Color = Color("a49c89").lerp(Color("c2b7a0"), variation * 0.7)
		color = color.lerp(peak_color, clampf((center.y - 54.0) / 16.0, 0.0, 1.0))
	if Vector2(center.x, center.z).distance_to(Vector2(0.0, 12.0)) < 14.0:
		color = Color("72604b").lerp(Color("927c5f"), variation * 0.5)
	for site: Vector2 in resource_sites:
		if Vector2(center.x, center.z).distance_to(site) < 7.0:
			color = Color("756149").lerp(Color("988267"), variation * 0.55)
			break
	for point: Vector3 in [a, b, c]:
		var vertex_variation: float = noise.get_noise_2d(point.x + 320.0, point.z - 180.0)
		var height_tint: float = clampf((point.y - 28.0) / 80.0, 0.0, 1.0) * 0.1
		surface.set_color(color * (0.96 + vertex_variation * 0.08 + height_tint))
		surface.add_vertex(point)

func _build_nodes() -> void:
	var definitions: Array[Dictionary] = [
		{"position": Vector3(-17.0, 0.0, -2.0), "item": "iron_ore", "purity": "normal", "rate": 60.0},
		{"position": Vector3(-30.0, 0.0, 18.0), "item": "iron_ore", "purity": "normal", "rate": 60.0},
		{"position": Vector3(18.0, 0.0, 3.0), "item": "iron_ore", "purity": "normal", "rate": 60.0},
		{"position": Vector3(28.0, 0.0, 15.0), "item": "iron_ore", "purity": "impure", "rate": 30.0},
		{"position": Vector3(-12.0, 0.0, -35.0), "item": "copper_ore", "purity": "normal", "rate": 60.0},
		{"position": Vector3(14.0, 0.0, -40.0), "item": "copper_ore", "purity": "normal", "rate": 60.0},
		{"position": Vector3(-35.0, 0.0, -30.0), "item": "limestone", "purity": "normal", "rate": 60.0},
		{"position": Vector3(-43.0, 0.0, 32.0), "item": "limestone", "purity": "normal", "rate": 60.0},
		{"position": Vector3(70.0, 0.0, 20.0), "item": "iron_ore", "purity": "normal", "rate": 60.0},
		{"position": Vector3(124.0, 0.0, -40.0), "item": "iron_ore", "purity": "pure", "rate": 120.0, "hidden": true}
	]
	for definition: Dictionary in definitions:
		var point: Vector3 = definition["position"]
		point.y = height_at(point.x, point.z)
		definition["position"] = point
		if bool(definition.get("hidden", false)):
			hidden_iron = point
		nodes.append(definition)
		if not bool(definition.get("hidden", false)):
			_make_node_visual(definition)

func _make_node_visual(definition: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var point: Vector3 = definition["position"]
	var node: Node3D = Node3D.new()
	node.position = point
	node.name = "%s_%s" % [definition["item"], definition["purity"]]
	node.set_meta("resource_node", definition)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("825343") if definition["item"] == "iron_ore" else Color("667a68") if definition["item"] == "copper_ore" else Color("a79b7b")
	material.roughness = 0.88
	var rock_offsets: Array[Vector3] = [
		Vector3(-0.75, 0.55, -0.48), Vector3(0.55, 0.7, -0.58), Vector3(-0.3, 0.8, 0.58),
		Vector3(0.82, 0.4, 0.45), Vector3(-0.95, 0.35, 0.45), Vector3(0.1, 0.46, -0.95)
	]
	for index: int in range(rock_offsets.size()):
		var rock: MeshInstance3D = MeshInstance3D.new()
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radius = 1.05 if index % 2 == 0 else 0.82
		mesh.height = 1.55
		rock.mesh = mesh
		rock.position = rock_offsets[index]
		rock.scale = Vector3(1.0 + float(index % 3) * 0.16, 0.8 + float(index % 2) * 0.2, 0.88)
		rock.rotation.z = -0.18 + float(index) * 0.07
		rock.material_override = material
		node.add_child(rock)
	var collision_body: StaticBody3D = StaticBody3D.new()
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 2.0
	collision_shape.shape = sphere
	collision_shape.position.y = 1.0
	collision_body.add_child(collision_shape)
	node.add_child(collision_body)
	var label: Label3D = Label3D.new()
	label.text = "%s · %s" % [Items.item_name(str(definition["item"])).replace(" Ore", ""), str(definition["purity"]).capitalize()]
	label.position = Vector3(0.0, 2.55, 0.0)
	label.font_size = 50
	label.pixel_size = 0.011
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.outline_size = 8
	label.outline_modulate = Color("202520")
	label.visibility_range_end = 45.0
	label.visibility_range_end_margin = 6.0
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	node.add_child(label)
	add_child(node)

func _build_vents() -> void:
	for point: Vector3 in [Vector3(-55.0, 0.0, 5.0), Vector3(42.0, 0.0, -52.0), Vector3(-102.0, 0.0, 72.0)]:
		point.y = height_at(point.x, point.z)
		vents.append(point)
		if DisplayServer.get_name() == "headless":
			continue
		var stack: Node3D = Node3D.new()
		stack.position = point
		var visual: MeshInstance3D = MeshInstance3D.new()
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = 0.22
		mesh.bottom_radius = 0.7
		mesh.height = 1.5
		visual.mesh = mesh
		visual.position.y = 0.75
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color("626a61")
		material.roughness = 0.86
		visual.material_override = material
		stack.add_child(visual)
		for pipe_x: float in [-0.46, 0.46]:
			var pipe: MeshInstance3D = MeshInstance3D.new()
			var pipe_mesh: CylinderMesh = CylinderMesh.new()
			pipe_mesh.top_radius = 0.09
			pipe_mesh.bottom_radius = 0.12
			pipe_mesh.height = 2.4
			pipe.mesh = pipe_mesh
			pipe.position = Vector3(pipe_x, 1.2, 0.0)
			pipe.material_override = material
			stack.add_child(pipe)
		var plume: MeshInstance3D = MeshInstance3D.new()
		var plume_mesh: SphereMesh = SphereMesh.new()
		plume_mesh.radius = 0.48
		plume_mesh.height = 1.6
		plume.mesh = plume_mesh
		plume.position = Vector3(0.0, 2.9, 0.0)
		var plume_material: StandardMaterial3D = StandardMaterial3D.new()
		plume_material.albedo_color = Color(0.55, 0.6, 0.57, 0.15)
		plume_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		plume_material.roughness = 1.0
		plume.material_override = plume_material
		stack.add_child(plume)
		var vent_label: Label3D = Label3D.new()
		vent_label.text = "Geothermal"
		vent_label.position = Vector3(0.0, 3.7, 0.0)
		vent_label.font_size = 46
		vent_label.pixel_size = 0.011
		vent_label.no_depth_test = false
		vent_label.outline_size = 8
		vent_label.outline_modulate = Color("202520")
		vent_label.visibility_range_end = 45.0
		vent_label.visibility_range_end_margin = 6.0
		vent_label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		stack.add_child(vent_label)
		add_child(stack)

func _build_landing_site() -> void:
	landing_position.y = height_at(landing_position.x, landing_position.z)
	spire_position.y = height_at(spire_position.x, spire_position.z)
	if DisplayServer.get_name() == "headless":
		return
	var pod: MeshInstance3D = MeshInstance3D.new()
	var pod_mesh: CapsuleMesh = CapsuleMesh.new()
	pod_mesh.radius = 1.4
	pod_mesh.height = 5.4
	pod.mesh = pod_mesh
	pod.position = landing_position + Vector3(-5.0, 1.5, 0.0)
	pod.rotation.z = PI / 2.0
	var pod_material: StandardMaterial3D = StandardMaterial3D.new()
	pod_material.albedo_color = Color("737b73")
	pod_material.metallic = 0.28
	pod_material.roughness = 0.84
	pod.material_override = pod_material
	add_child(pod)
	for band_x: float in [-6.9, -3.1]:
		var band: MeshInstance3D = MeshInstance3D.new()
		var band_mesh: CylinderMesh = CylinderMesh.new()
		band_mesh.top_radius = 1.45
		band_mesh.bottom_radius = 1.45
		band_mesh.height = 0.24
		band.mesh = band_mesh
		band.position = landing_position + Vector3(band_x, 1.55, 0.0)
		band.rotation.z = PI / 2.0
		var band_material: StandardMaterial3D = StandardMaterial3D.new()
		band_material.albedo_color = Color("c19543")
		band_material.metallic = 0.35
		band_material.roughness = 0.72
		band.material_override = band_material
		add_child(band)
	var hub: MeshInstance3D = MeshInstance3D.new()
	var hub_mesh: BoxMesh = BoxMesh.new()
	hub_mesh.size = Vector3(4.0, 2.8, 3.0)
	hub.mesh = hub_mesh
	hub.position = landing_position + Vector3(4.0, 1.4, 0.0)
	var hub_material: StandardMaterial3D = StandardMaterial3D.new()
	hub_material.albedo_color = Color("687f84")
	hub_material.metallic = 0.22
	hub_material.roughness = 0.82
	hub.material_override = hub_material
	hub.name = "HUB"
	hub.set_meta("interactable", "hub")
	add_child(hub)
	var hub_body: StaticBody3D = StaticBody3D.new()
	var hub_collision: CollisionShape3D = CollisionShape3D.new()
	var hub_box: BoxShape3D = BoxShape3D.new()
	hub_box.size = hub_mesh.size
	hub_collision.shape = hub_box
	hub_body.add_child(hub_collision)
	hub.add_child(hub_body)
	var screen: MeshInstance3D = MeshInstance3D.new()
	var screen_mesh: BoxMesh = BoxMesh.new()
	screen_mesh.size = Vector3(2.15, 1.05, 0.08)
	screen.mesh = screen_mesh
	screen.position = hub.position + Vector3(0.0, 0.15, 1.56)
	var screen_material: StandardMaterial3D = StandardMaterial3D.new()
	screen_material.albedo_color = Color("35636a")
	screen_material.emission_enabled = true
	screen_material.emission = Color("31515a") * 0.25
	screen_material.roughness = 0.65
	screen.material_override = screen_material
	add_child(screen)
	var terminal_label: Label3D = Label3D.new()
	terminal_label.text = "HUB"
	terminal_label.position = hub.position + Vector3(0.0, 0.16, 1.63)
	terminal_label.font_size = 42
	terminal_label.pixel_size = 0.008
	terminal_label.modulate = Color("ced8c9")
	terminal_label.no_depth_test = false
	add_child(terminal_label)
