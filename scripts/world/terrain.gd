extends Node3D
class_name FactoryTerrain

var noise: FastNoiseLite = FastNoiseLite.new()
var nodes: Array[Dictionary] = []
var vents: Array[Vector3] = []
var hidden_iron: Vector3 = Vector3(124.0, 0.0, -40.0)
var spire_position: Vector3 = Vector3(0.0, 0.0, -28.0)
var landing_position: Vector3 = Vector3(0.0, 0.0, 12.0)
var building_definitions: Dictionary = BuildingDefs.all()

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
	var valley_rise: float = maxf(0.0, radius - 92.0) * 0.34 + maxf(0.0, radius - 158.0) * 1.3
	var undulation: float = noise.get_noise_2d(x, z) * (0.65 if radius < 100.0 else 3.2)
	var ridge: float = 0.0
	if x > 38.0 and x < 110.0:
		var ridge_profile: float = sin((x - 38.0) / 72.0 * PI)
		ridge = maxf(0.0, ridge_profile) * (9.0 + noise.get_noise_2d(x + 900.0, z) * 2.5)
	return valley_rise + undulation + ridge

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
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var divisions: int = 120
	var step: float = 400.0 / float(divisions)
	for z_index: int in range(divisions):
		for x_index: int in range(divisions):
			var x0: float = -200.0 + float(x_index) * step
			var z0: float = -200.0 + float(z_index) * step
			var p00: Vector3 = Vector3(x0, height_at(x0, z0), z0)
			var p10: Vector3 = Vector3(x0 + step, height_at(x0 + step, z0), z0)
			var p01: Vector3 = Vector3(x0, height_at(x0, z0 + step), z0 + step)
			var p11: Vector3 = Vector3(x0 + step, height_at(x0 + step, z0 + step), z0 + step)
			_add_terrain_triangle(surface, p00, p01, p10)
			_add_terrain_triangle(surface, p10, p01, p11)
	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.mesh = mesh
	ground.material_override = material
	add_child(ground)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
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
	environment.ambient_light_color = Color("b6c6d1")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("b9c9c4")
	environment.fog_density = 0.0018
	sky.environment = environment
	add_child(sky)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.1
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
	var slope: float = absf((b - a).cross(c - a).normalized().y)
	var color: Color = Color("657a50") if slope > 0.76 and center.y < 7.0 else Color("697064")
	if center.x > 38.0 and center.x < 110.0:
		color = Color("756f63")
	surface.set_color(color)
	surface.add_vertex(a)
	surface.set_color(color)
	surface.add_vertex(b)
	surface.set_color(color)
	surface.add_vertex(c)

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
	var point: Vector3 = definition["position"]
	var node: Node3D = Node3D.new()
	node.position = point
	node.name = "%s_%s" % [definition["item"], definition["purity"]]
	node.set_meta("resource_node", definition)
	var rock: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 1.7
	mesh.height = 2.1
	rock.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("a77c64") if definition["item"] == "iron_ore" else Color("d18442") if definition["item"] == "copper_ore" else Color("c8c1a8")
	material.roughness = 0.82
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.22
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
	label.text = "%s · %s · %d/min" % [Items.item_name(str(definition["item"])), str(definition["purity"]).capitalize(), int(definition["rate"])]
	label.position = Vector3(0.0, 2.7, 0.0)
	label.font_size = 36
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.add_child(label)
	add_child(node)

func _build_vents() -> void:
	for point: Vector3 in [Vector3(-55.0, 0.0, 5.0), Vector3(42.0, 0.0, -52.0), Vector3(-102.0, 0.0, 72.0)]:
		point.y = height_at(point.x, point.z)
		vents.append(point)
		var visual: MeshInstance3D = MeshInstance3D.new()
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = 0.18
		mesh.bottom_radius = 0.55
		mesh.height = 7.0
		visual.mesh = mesh
		visual.position = point + Vector3(0.0, 3.4, 0.0)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.72, 0.84, 0.87, 0.25)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.emission_enabled = true
		material.emission = Color("a8d8dc")
		visual.material_override = material
		add_child(visual)

func _build_landing_site() -> void:
	landing_position.y = height_at(landing_position.x, landing_position.z)
	spire_position.y = height_at(spire_position.x, spire_position.z)
	var pod: MeshInstance3D = MeshInstance3D.new()
	var pod_mesh: CapsuleMesh = CapsuleMesh.new()
	pod_mesh.radius = 2.3
	pod_mesh.height = 5.0
	pod.mesh = pod_mesh
	pod.position = landing_position + Vector3(-5.0, 2.5, 0.0)
	var pod_material: StandardMaterial3D = StandardMaterial3D.new()
	pod_material.albedo_color = Color("d0d2c7")
	pod.material_override = pod_material
	add_child(pod)
	var hub: MeshInstance3D = MeshInstance3D.new()
	var hub_mesh: BoxMesh = BoxMesh.new()
	hub_mesh.size = Vector3(4.0, 2.8, 3.0)
	hub.mesh = hub_mesh
	hub.position = landing_position + Vector3(4.0, 1.4, 0.0)
	var hub_material: StandardMaterial3D = StandardMaterial3D.new()
	hub_material.albedo_color = Color("687f84")
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
