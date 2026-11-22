extends RefCounted
class_name MachineModels

var mesh_cache: Dictionary = {}
var material_cache: Dictionary = {}

func build(kind: String, root: Node3D, size: Vector2i, body_position: Vector3) -> void:
	match kind:
		"miner_mk1":
			_build_miner(root, size)
		"smelter":
			_build_smelter(root, body_position)
		"constructor":
			_build_constructor(root, body_position)
		"assembler":
			_build_assembler(root, body_position)
		"geo_tap":
			_build_geo_tap(root, body_position)
		"power_pole":
			_build_power_pole(root, body_position)
		"storage":
			_build_storage(root, body_position)
		"splitter", "merger":
			_build_junction(root, kind, body_position)
		"spire":
			_build_spire(root, body_position)

func animate(root: Node3D, entity: FactoryEntity) -> void:
	var running: bool = entity.status == "Running"
	var drill: Node3D = root.get_node_or_null("DrillHead") as Node3D
	if drill != null:
		drill.rotation.y = Time.get_ticks_msec() * 0.002 if running else 0.0
	var piston: Node3D = root.get_node_or_null("MinerPiston") as Node3D
	if piston != null:
		piston.position.y = 3.15 + (sin(Time.get_ticks_msec() * 0.006) * 0.24 if running else 0.0)
	var press: Node3D = root.get_node_or_null("ConstructorPress") as Node3D
	if press != null:
		press.position.y = 2.3 + (absf(sin(Time.get_ticks_msec() * 0.004)) * 0.7 if running else 0.0)
	for arm_name: String in ["AssemblerArmA", "AssemblerArmB"]:
		var arm: Node3D = root.get_node_or_null(arm_name) as Node3D
		if arm != null:
			arm.rotation.y = sin(Time.get_ticks_msec() * 0.0018 + (0.0 if arm_name == "AssemblerArmA" else PI)) * 0.55 if running else 0.0
	var turbine: Node3D = root.get_node_or_null("GeoTurbine") as Node3D
	if turbine != null:
		turbine.rotation.z = Time.get_ticks_msec() * 0.003 if running else 0.0
	for particle_name: String in ["SmelterSmoke", "GeoSteam"]:
		var particles: CPUParticles3D = root.get_node_or_null(particle_name) as CPUParticles3D
		if particles != null:
			particles.emitting = running
	var mouth: MeshInstance3D = root.get_node_or_null("FurnaceMouth") as MeshInstance3D
	if mouth != null:
		mouth.material_override = _material("furnace_glow" if running else "furnace_dark",
			Color("e16b28") if running else Color("2c302d"), 0.1, 0.88, running)

func _build_miner(root: Node3D, size: Vector2i) -> void:
	var center: Vector3 = Vector3(float(size.x - 1), 0.0, float(size.y - 1))
	_box_part(root, "MinerBase", Vector3(2.25, 0.28, 2.2), center + Vector3(0.0, 0.12, 0.0), "steel")
	for x: float in [-0.82, 0.82]:
		for z: float in [-0.72, 0.72]:
			_cylinder_part(root, "MinerTowerLeg", 0.12, 4.2, center + Vector3(x, 2.25, z), "dark_steel")
			_box_part(root, "MinerFoot", Vector3(0.38, 0.16, 0.38), center + Vector3(x, 0.28, z), "yellow")
	for y: float in [1.2, 2.6, 3.85]:
		for z: float in [-0.72, 0.72]:
			_box_part(root, "MinerCrossbar", Vector3(1.75, 0.11, 0.11), center + Vector3(0.0, y, z), "steel")
	_box_part(root, "MinerTopPanel", Vector3(2.0, 0.32, 1.8), center + Vector3(0.0, 4.25, 0.0), "orange")
	_box_part(root, "MinerHazard", Vector3(1.9, 0.12, 0.08), center + Vector3(0.0, 0.5, 0.92), "hazard")
	var piston: Node3D = Node3D.new()
	piston.name = "MinerPiston"
	piston.position = center + Vector3(0.0, 3.15, 0.0)
	root.add_child(piston)
	_cylinder_part(piston, "MinerCylinder", 0.24, 1.6, Vector3(0.0, -0.6, 0.0), "orange")
	var drill: Node3D = Node3D.new()
	drill.name = "DrillHead"
	drill.position = center + Vector3(0.0, 0.95, 0.0)
	root.add_child(drill)
	_cylinder_part(drill, "DrillCrown", 0.66, 0.36, Vector3.ZERO, "yellow")
	_cylinder_part(drill, "DrillBit", 0.16, 0.8, Vector3(0.0, -0.56, 0.0), "steel")
	_box_part(root, "MinerChute", Vector3(0.72, 0.55, 0.9), center + Vector3(0.98, 0.95, -0.3), "orange")
	_box_part(root, "MinerChuteLip", Vector3(0.85, 0.12, 0.16), center + Vector3(0.98, 0.65, 0.1), "yellow")
	_add_ladder(root, center + Vector3(-0.95, 1.8, 0.0), 3.4)

func _build_smelter(root: Node3D, center: Vector3) -> void:
	_box_part(root, "FurnaceLower", Vector3(3.35, 0.5, 3.2), center + Vector3(0.0, -0.1, 0.0), "dark_steel")
	_box_part(root, "FurnaceFrontPanel", Vector3(2.5, 1.6, 0.26), center + Vector3(0.0, 0.2, 1.47), "orange")
	_box_part(root, "FurnaceMouthFrame", Vector3(1.05, 0.76, 0.12), center + Vector3(0.0, -0.05, 1.63), "yellow")
	var mouth: MeshInstance3D = _box_part(root, "FurnaceMouth", Vector3(0.74, 0.48, 0.09),
		center + Vector3(0.0, -0.08, 1.72), "furnace_dark")
	mouth.name = "FurnaceMouth"
	_box_part(root, "FurnaceRoof", Vector3(3.1, 0.3, 2.9), center + Vector3(0.0, 1.95, 0.0), "steel")
	_cylinder_part(root, "Chimney", 0.35, 2.8, center + Vector3(1.0, 3.35, -0.65), "dark_steel")
	_box_part(root, "ChimneyRim", Vector3(0.82, 0.16, 0.82), center + Vector3(1.0, 4.78, -0.65), "yellow")
	_box_part(root, "SmelterHazardBand", Vector3(3.18, 0.14, 0.12), center + Vector3(0.0, -0.58, 1.55), "hazard")
	var smoke: CPUParticles3D = _particles("SmelterSmoke", Color("696d67"), 16)
	smoke.position = center + Vector3(1.0, 4.9, -0.65)
	smoke.emitting = false
	root.add_child(smoke)

func _build_constructor(root: Node3D, center: Vector3) -> void:
	_box_part(root, "ConstructorBase", Vector3(3.6, 0.5, 5.2), center + Vector3(0.0, -0.15, 0.0), "dark_steel")
	for x: float in [-1.42, 1.42]:
		_box_part(root, "ConstructorWall", Vector3(0.18, 2.6, 4.3), center + Vector3(x, 1.1, 0.0), "orange")
		_box_part(root, "ConstructorWindow", Vector3(0.08, 0.72, 1.4), center + Vector3(x * 1.08, 1.2, 0.1), "glass")
	_box_part(root, "ConstructorRoof", Vector3(3.3, 0.24, 4.8), center + Vector3(0.0, 2.45, 0.0), "steel")
	_box_part(root, "ConstructorGantry", Vector3(3.0, 0.18, 0.22), center + Vector3(0.0, 2.15, 0.0), "yellow")
	var press: Node3D = Node3D.new()
	press.name = "ConstructorPress"
	press.position = center + Vector3(0.0, 2.3, 0.0)
	root.add_child(press)
	_box_part(press, "PressHead", Vector3(0.9, 0.58, 1.0), Vector3(0.0, -0.05, 0.0), "orange")
	_cylinder_part(press, "PressRam", 0.13, 0.9, Vector3(0.0, -0.7, 0.0), "steel")
	_box_part(root, "ConstructorMouthFront", Vector3(0.75, 0.52, 0.85), center + Vector3(0.0, 0.34, 2.65), "yellow")
	_box_part(root, "ConstructorMouthBack", Vector3(0.75, 0.52, 0.85), center + Vector3(0.0, 0.34, -2.65), "yellow")
	_box_part(root, "ConstructorHazard", Vector3(3.2, 0.13, 0.1), center + Vector3(0.0, 0.2, 2.63), "hazard")

func _build_assembler(root: Node3D, center: Vector3) -> void:
	_box_part(root, "AssemblerBase", Vector3(5.3, 0.5, 5.3), center + Vector3(0.0, -0.15, 0.0), "dark_steel")
	for x: float in [-2.15, 2.15]:
		for z: float in [-2.1, 2.1]:
			_box_part(root, "AssemblerPost", Vector3(0.2, 3.4, 0.2), center + Vector3(x, 1.55, z), "steel")
	for x: float in [-1.35, 1.35]:
		_cylinder_part(root, "AssemblerHopper", 0.54, 1.5, center + Vector3(x, 2.15, -1.6), "yellow")
		var arm: Node3D = Node3D.new()
		arm.name = "AssemblerArmA" if x < 0.0 else "AssemblerArmB"
		arm.position = center + Vector3(x, 1.75, 0.35)
		root.add_child(arm)
		_cylinder_part(arm, "ArmShoulder", 0.22, 0.4, Vector3.ZERO, "orange")
		_box_part(arm, "ArmLink", Vector3(0.16, 0.16, 1.55), Vector3(0.0, 0.0, 0.75), "yellow")
		_box_part(arm, "ArmTool", Vector3(0.3, 0.3, 0.35), Vector3(0.0, -0.1, 1.48), "steel")
	_box_part(root, "AssemblerRoof", Vector3(5.0, 0.28, 5.0), center + Vector3(0.0, 3.35, 0.0), "orange")
	_box_part(root, "AssemblerScreen", Vector3(0.9, 0.56, 0.12), center + Vector3(0.0, 2.4, 2.62), "screen")

func _build_geo_tap(root: Node3D, center: Vector3) -> void:
	_box_part(root, "GeoBase", Vector3(3.35, 0.45, 3.2), center + Vector3(0.0, -0.1, 0.0), "dark_steel")
	_cylinder_part(root, "Wellhead", 0.55, 2.1, center + Vector3(0.0, 0.95, 0.0), "steel")
	for x: float in [-1.05, 1.05]:
		_cylinder_part(root, "GeoPipe", 0.16, 3.4, center + Vector3(x, 1.55, -0.3), "orange")
		_cylinder_part(root, "GeoPipeBend", 0.32, 0.14, center + Vector3(x, 3.3, -0.3), "yellow")
	var turbine: Node3D = Node3D.new()
	turbine.name = "GeoTurbine"
	turbine.position = center + Vector3(0.0, 3.2, -0.25)
	root.add_child(turbine)
	_cylinder_part(turbine, "TurbineHub", 0.22, 0.55, Vector3.ZERO, "yellow")
	for angle: float in [0.0, PI / 2.0, PI, PI * 1.5]:
		_box_part(turbine, "TurbineBlade", Vector3(0.14, 0.86, 0.2),
			Vector3(cos(angle) * 0.43, sin(angle) * 0.43, 0.0), "steel")
	_box_part(root, "GeoWarning", Vector3(3.0, 0.14, 0.12), center + Vector3(0.0, 0.4, 1.62), "hazard")
	var steam: CPUParticles3D = _particles("GeoSteam", Color("d4d1c5"), 20)
	steam.position = center + Vector3(0.0, 3.5, -0.25)
	steam.emitting = false
	root.add_child(steam)

func _build_power_pole(root: Node3D, center: Vector3) -> void:
	for x: float in [-0.32, 0.32]:
		for z: float in [-0.32, 0.32]:
			_cylinder_part(root, "PoleLatticeLeg", 0.075, 5.1, center + Vector3(x, 2.5, z), "steel")
	_box_part(root, "PoleCrossarm", Vector3(1.7, 0.12, 0.14), center + Vector3(0.0, 4.2, 0.0), "orange")
	for x: float in [-0.58, 0.0, 0.58]:
		_cylinder_part(root, "PoleInsulator", 0.12, 0.38, center + Vector3(x, 4.5, 0.0), "yellow")
	for y: float in [1.0, 2.4, 3.5]:
		_box_part(root, "PoleBrace", Vector3(0.88, 0.08, 0.08), center + Vector3(0.0, y, 0.0), "steel")
	_box_part(root, "PoleLamp", Vector3(0.3, 0.28, 0.3), center + Vector3(0.0, 5.0, 0.0), "screen")

func _build_storage(root: Node3D, center: Vector3) -> void:
	_box_part(root, "StorageFrame", Vector3(3.5, 2.7, 3.4), center + Vector3(0.0, 1.15, 0.0), "orange")
	_box_part(root, "StorageDoor", Vector3(2.0, 2.1, 0.12), center + Vector3(0.0, 1.05, 1.75), "steel")
	for x: float in [-1.45, -0.9, -0.35, 0.35, 0.9, 1.45]:
		_box_part(root, "StorageRib", Vector3(0.09, 2.45, 0.12), center + Vector3(x, 1.15, 1.84), "yellow")
	_add_ladder(root, center + Vector3(-1.78, 1.0, 0.0), 2.2)
	_box_part(root, "StorageRoof", Vector3(3.8, 0.18, 3.7), center + Vector3(0.0, 2.65, 0.0), "steel")

func _build_junction(root: Node3D, kind: String, center: Vector3) -> void:
	_box_part(root, "JunctionCore", Vector3(1.55, 1.0, 1.55), center + Vector3(0.0, 0.62, 0.0), "orange")
	_box_part(root, "JunctionTop", Vector3(1.75, 0.18, 1.75), center + Vector3(0.0, 1.2, 0.0), "yellow")
	var directions: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1)]
	for index: int in range(directions.size()):
		var direction: Vector2i = directions[index]
		var mouth: Vector3 = center + Vector3(float(direction.x) * 0.9, 0.45, float(direction.y) * 0.9)
		_box_part(root, "JunctionMouth", Vector3(0.9, 0.45, 0.7), mouth, "steel")
		var arrow: MeshInstance3D = _box_part(root, "JunctionArrow", Vector3(0.52, 0.08, 0.14),
			center + Vector3(float(direction.x) * 0.15, 1.32, float(direction.y) * 0.15), "yellow")
		arrow.rotation.y = atan2(float(direction.x), float(direction.y))
		if kind == "merger" and index == 2:
			arrow.visible = false

func _build_spire(root: Node3D, center: Vector3) -> void:
	for x: float in [-3.4, 3.4]:
		for z: float in [-3.4, 3.4]:
			_box_part(root, "SpirePylon", Vector3(0.58, 16.0, 0.58), center + Vector3(x, 8.0, z), "dark_steel")
	for y: float in [3.0, 8.0, 13.0]:
		_box_part(root, "SpireWarningRing", Vector3(8.0, 0.24, 8.0), center + Vector3(0.0, y, 0.0), "hazard")
	var stage_pillar: MeshInstance3D = _box_part(root, "Stage0", Vector3(0.8, 12.0, 0.8), center + Vector3(0.0, 6.0, 0.0), "dark_steel")
	stage_pillar.position = center + Vector3(5.0, 6.0, 5.0)
	var gantry: MeshInstance3D = _box_part(root, "Gantry", Vector3(12.0, 0.48, 0.48), center + Vector3(5.0, 8.0, 5.0), "yellow")
	gantry.position = center + Vector3(5.0, 8.0, 5.0)

func _add_ladder(root: Node3D, center: Vector3, height: float) -> void:
	for x: float in [-0.28, 0.28]:
		_cylinder_part(root, "MachineLadderRail", 0.045, height, center + Vector3(x, height * 0.5, 0.0), "yellow")
	for index: int in range(floori(height / 0.36)):
		_cylinder_part(root, "MachineLadderRung", 0.04, 0.56,
			center + Vector3(0.0, 0.2 + float(index) * 0.36, 0.0), "steel")

func _particles(node_name: String, color: Color, amount: int) -> CPUParticles3D:
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = 2.1
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 14.0
	particles.initial_velocity_min = 0.35
	particles.initial_velocity_max = 1.0
	particles.gravity = Vector3(0.0, 0.2, 0.0)
	var puff: SphereMesh = SphereMesh.new()
	puff.radius = 0.13
	puff.height = 0.26
	particles.mesh = puff
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	particles.material_override = material
	return particles

func _box_part(root: Node3D, part_name: String, dimensions: Vector3, position: Vector3, material_key: String) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = part_name
	var key: String = "box_%s_%.2f_%.2f_%.2f" % [part_name, dimensions.x, dimensions.y, dimensions.z]
	if not mesh_cache.has(key):
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = dimensions
		mesh_cache[key] = mesh
	part.mesh = mesh_cache[key]
	part.position = position
	part.material_override = _material(material_key, Color.WHITE)
	root.add_child(part)
	return part

func _cylinder_part(root: Node3D, part_name: String, radius: float, height: float, position: Vector3, material_key: String) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = part_name
	var key: String = "cylinder_%s_%.2f_%.2f" % [part_name, radius, height]
	if not mesh_cache.has(key):
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = radius * 0.82
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 10
		mesh_cache[key] = mesh
	part.mesh = mesh_cache[key]
	part.position = position
	part.material_override = _material(material_key, Color.WHITE)
	root.add_child(part)
	return part

func _material(key: String, fallback: Color, metallic: float = 0.48, roughness: float = 0.72, emissive: bool = false) -> Material:
	if material_cache.has(key):
		return material_cache[key]
	if key == "hazard":
		var hazard: ShaderMaterial = ShaderMaterial.new()
		hazard.shader = load("res://shaders/hazard_stripe.gdshader") as Shader
		material_cache[key] = hazard
		return hazard
	var colors: Dictionary = {
		"orange": Color("b96329"),
		"yellow": Color("d3a63d"),
		"steel": Color("68716d"),
		"dark_steel": Color("343d3b"),
		"glass": Color("53706d"),
		"screen": Color("31898a"),
		"furnace_dark": Color("292d2b"),
		"furnace_glow": Color("e16b28")
	}
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colors.get(key, fallback)
	material.metallic = metallic
	material.roughness = roughness
	if key == "steel" or key == "dark_steel":
		material.albedo_texture = load("res://assets/textures/metal_plate_diff_1k.jpg") as Texture2D
		material.normal_enabled = true
		material.normal_texture = load("res://assets/textures/metal_plate_nor_gl_1k.jpg") as Texture2D
		material.roughness_texture = load("res://assets/textures/metal_plate_rough_1k.jpg") as Texture2D
	if emissive:
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 2.0
	material_cache[key] = material
	return material
