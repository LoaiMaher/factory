extends RefCounted
class_name MachineModels

var mesh_cache: Dictionary = {}
var material_cache: Dictionary = {}

func build(kind: String, root: Node3D, size: Vector2i, body_position: Vector3) -> void:
	var asset_name: String = "ascent_spire" if kind == "spire" else kind
	if kind in ["belt_mk1", "belt_mk2"]:
		asset_name = "belt"
	var packed: PackedScene = load("res://assets/models/%s.glb" % asset_name) as PackedScene
	if packed == null:
		push_error("Missing Blender model: " + asset_name)
		return
	var model: Node3D = packed.instantiate() as Node3D
	model.name = "BlenderModel"
	model.position = body_position
	root.add_child(model)
	apply_pbr_materials(model)
	_ensure_status_light(kind, model)
	_validate_ports(kind, model, root)
	match kind:
		"miner_mk1":
			var drill: Node3D = model.find_child("Drill", true, false) as Node3D
			if drill != null:
				_add_particles(drill, "MinerDust", Vector3(0.0, -0.82, 0.0), 12, Color("9b8569"))
		"smelter":
			_add_particles(model, "SmelterSmoke", Vector3(0.85, 4.8, -0.65), 18, Color("82827a"))
		"constructor":
			var press: Node3D = model.find_child("Press", true, false) as Node3D
			if press != null:
				_add_particles(press, "ConstructorSparks", Vector3(0.0, -0.58, 0.08), 7, Color("ffb34d"))
		"assembler":
			var arm: Node3D = model.find_child("Arm_A", true, false) as Node3D
			if arm != null:
				_add_particles(arm, "AssemblerSparks", Vector3(0.0, -1.18, 0.08), 7, Color("ffb34d"))
		"geo_tap":
			_add_particles(model, "GeoSteam", Vector3(0.0, 4.0, 0.0), 20, Color("d4d1c5"))
	if kind in ["belt_mk1", "belt_mk2"]:
		var belt_surface: MeshInstance3D = model.find_child("Belt_Mesh", true, false) as MeshInstance3D
		if belt_surface != null:
			belt_surface.name = "BeltSurface"
			var belt_material: ShaderMaterial = ShaderMaterial.new()
			belt_material.shader = load("res://shaders/belt_surface.gdshader") as Shader
			belt_material.set_shader_parameter("belt_speed", 0.0)
			belt_surface.material_override = belt_material

func animate(root: Node3D, visual_state: Dictionary, delta: float, distance: float) -> void:
	var target_productivity: float = clampf(float(visual_state.get("productivity", 0.0)), 0.0, 1.0)
	var productivity: float = float(root.get_meta("visual_productivity", 0.0))
	productivity = move_toward(productivity, target_productivity, delta / 0.6)
	root.set_meta("visual_productivity", productivity)
	var phase: float = float(root.get_meta("machine_animation_phase", 0.0)) + delta * productivity
	root.set_meta("machine_animation_phase", phase)
	var status: String = str(visual_state.get("status", "Stopped"))
	var powered: bool = bool(visual_state.get("powered", false))

	var drill: Node3D = root.find_child("Drill", true, false) as Node3D
	if drill != null:
		if not drill.has_meta("factory_base_position"):
			drill.set_meta("factory_base_position", drill.position)
		var drill_base: Vector3 = drill.get_meta("factory_base_position")
		drill.rotation.y += delta * 6.0 * productivity
		drill.position.y = drill_base.y + sin(phase * 18.0) * 0.025 * productivity
	var piston: Node3D = root.find_child("Piston", true, false) as Node3D
	if piston != null:
		if not piston.has_meta("factory_base_position"):
			piston.set_meta("factory_base_position", piston.position)
		var piston_base: Vector3 = piston.get_meta("factory_base_position")
		piston.position.y = piston_base.y + sin(phase * 8.0) * 0.22 * productivity
	var press: Node3D = root.find_child("Press", true, false) as Node3D
	if press != null:
		if not press.has_meta("factory_base_position"):
			press.set_meta("factory_base_position", press.position)
		var press_base: Vector3 = press.get_meta("factory_base_position")
		press.position.y = press_base.y - absf(sin(phase * 5.0)) * 0.7 * productivity
	for arm_name: String in ["Arm_A", "Arm_B"]:
		var arm: Node3D = root.find_child(arm_name, true, false) as Node3D
		if arm != null:
			if not arm.has_meta("factory_base_rotation"):
				arm.set_meta("factory_base_rotation", arm.rotation)
			var arm_base: Vector3 = arm.get_meta("factory_base_rotation")
			var phase_offset: float = 0.0 if arm_name == "Arm_A" else PI
			arm.rotation.y = arm_base.y + sin(phase * 1.8 + phase_offset) * 0.55 * productivity
	var turbine: Node3D = root.find_child("Turbine", true, false) as Node3D
	if turbine != null:
		turbine.rotation.y += delta * 4.0 * productivity
	var belt: Node3D = root.find_child("Belt", true, false) as Node3D
	if belt != null:
		belt.position.x = sin(phase * 18.0) * 0.02 * productivity
	var in_range: bool = distance <= 60.0
	for particle_name: String in ["SmelterSmoke", "GeoSteam", "MinerDust",
			"ConstructorSparks", "AssemblerSparks"]:
		var particles: CPUParticles3D = root.find_child(particle_name, true, false) as CPUParticles3D
		if particles == null:
			continue
		var emit: bool = productivity > 0.02 and in_range
		if particle_name in ["ConstructorSparks", "AssemblerSparks"]:
			emit = emit and sin(phase * 5.0) > 0.82
		particles.emitting = emit
	var glow: Node3D = root.find_child("Furnace_Glow", true, false) as Node3D
	if glow != null:
		for child: Node in glow.get_children():
			if child is MeshInstance3D:
				var mesh: MeshInstance3D = child as MeshInstance3D
				if not mesh.has_meta("factory_glow_material"):
					var glow_material: StandardMaterial3D = _emission_material(Color("ff6320"), true)
					mesh.set_meta("factory_glow_material", glow_material)
					mesh.material_override = glow_material
				var material: StandardMaterial3D = mesh.get_meta("factory_glow_material")
				var glow_color: Color = Color("ff6320").lerp(Color("33342f"), 1.0 - productivity)
				material.albedo_color = glow_color
				material.emission = glow_color
				material.emission_energy_multiplier = 1.8 * productivity
				material.emission_enabled = productivity > 0.01
	_update_status_light(root, status, powered, Time.get_ticks_msec() * 0.001)

func _ensure_status_light(kind: String, model: Node3D) -> void:
	if kind in ["belt_mk1", "belt_mk2", "spire"] or model.find_child("StatusLight", true, false) != null:
		return
	var light_positions: Dictionary = {
		"storage": Vector3(1.55, 2.85, 0.0),
		"splitter": Vector3(0.0, 1.65, 0.0),
		"merger": Vector3(0.0, 1.65, 0.0)
	}
	var light: Node3D = Node3D.new()
	light.name = "StatusLight"
	light.position = light_positions.get(kind, Vector3(0.0, BuildingDefs.size_of(kind).y + 0.25, 0.0))
	model.add_child(light)
	var lens: MeshInstance3D = MeshInstance3D.new()
	lens.name = "StatusLens"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	sphere.radial_segments = 12
	sphere.rings = 6
	lens.mesh = sphere
	lens.material_override = _emission_material(Color("434943"), false)
	light.add_child(lens)

func _update_status_light(root: Node3D, status: String, powered: bool, phase: float) -> void:
	var light: Node3D = root.find_child("StatusLight", true, false) as Node3D
	if light == null:
		return
	var lens: MeshInstance3D = light.find_child("StatusLens", true, false) as MeshInstance3D
	if lens == null:
		for child: Node in light.find_children("*", "MeshInstance3D", true, false):
			if str(child.name).to_lower().contains("lens"):
				lens = child as MeshInstance3D
				break
	if lens == null:
		return
	var color: Color = Color("434943")
	var blink_rate: float = 0.0
	var enabled: bool = true
	if status.begins_with("No power") or not powered:
		color = Color("f0443e")
		blink_rate = 4.0
	elif status.begins_with("Output full"):
		color = Color("ffb236")
		blink_rate = 7.0
	elif status.begins_with("Missing input") or status.begins_with("Low power"):
		color = Color("ffb236")
		blink_rate = 1.4
	elif status == "Running":
		color = Color("4ddd75")
	else:
		enabled = false
	var pulse: float = 1.0 if blink_rate <= 0.0 else 0.25 + 0.75 * maxf(0.0, sin(phase * blink_rate))
	var material: StandardMaterial3D = null
	if lens.has_meta("factory_status_material"):
		material = lens.get_meta("factory_status_material") as StandardMaterial3D
	else:
		material = StandardMaterial3D.new()
		material.roughness = 0.24
		material.metallic = 0.06
		lens.set_meta("factory_status_material", material)
		lens.material_override = material
	material.albedo_color = color if enabled else Color("434943")
	material.emission = color
	material.emission_enabled = enabled
	material.emission_energy_multiplier = 1.8 * pulse if enabled else 0.0

func apply_pbr_materials(model: Node) -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface: int in range(mesh_instance.mesh.get_surface_count()):
			var source: Material = mesh_instance.mesh.surface_get_material(surface)
			if source == null:
				continue
			var key: String = source.resource_name
			if key.is_empty():
				continue
			var replacement: Material = _pbr_material(key)
			if replacement != null:
				mesh_instance.set_surface_override_material(surface, replacement)

func _validate_ports(kind: String, model: Node3D, root: Node3D) -> void:
	if not OS.is_debug_build():
		return
	for definition: Dictionary in BuildingDefs.all().get(kind, {}).get("ports", []):
		var port: Node3D = model.find_child("Port_%s_%d" % [str(definition["dir"]).capitalize(), int(str(definition["id"]).trim_prefix(str(definition["dir"])))], true, false) as Node3D
		if port == null:
			push_warning("Missing model port %s on %s" % [definition["id"], kind])
			continue
		var local_transform: Transform3D = port.transform
		var ancestor: Node = port.get_parent()
		while ancestor != null and ancestor != root:
			local_transform = (ancestor as Node3D).transform * local_transform
			ancestor = ancestor.get_parent()
		if ancestor != root:
			push_warning("Model port %s is outside %s" % [definition["id"], kind])
			continue
		var local_position: Vector3 = local_transform.origin
		var local_normal: Vector3 = (local_transform.basis * Vector3.FORWARD).normalized()
		if local_position.distance_to(definition["pos"]) > 0.05 or local_normal.distance_to(definition["normal"]) > 0.05:
			push_warning("Model port mismatch %s on %s" % [definition["id"], kind])

func _pbr_material(key: String) -> Material:
	if material_cache.has(key):
		return material_cache[key]
	var paint_tints: Dictionary = {
		"Paint_Orange": Color("e8902a"), "Paint_Dark": Color("2b2e33"),
		"Steel": Color("b2b8b8"), "Concrete": Color("77766b"),
		"Glass": Color("75aeb2"), "Rubber": Color("252826"),
		"Glove_Charcoal": Color("2b2f34"),
		"Pick_Wood": Color("8b5b32"),
		"Foliage": Color("49643b"), "Bark": Color("594532"),
		"Ore_Iron": Color("a75a3d"), "Ore_Copper": Color("5f9c76"),
		"Ore_Limestone": Color("bcb48a")
	}
	if key == "Paint_Orange" or key == "Paint_Dark":
		var paint: StandardMaterial3D = StandardMaterial3D.new()
		paint.albedo_color = paint_tints[key]
		paint.metallic = 0.3 if key == "Paint_Orange" else 0.6
		paint.roughness = 0.45
		paint.normal_enabled = true
		paint.normal_texture = load("res://assets/textures/metal_plate_nor_gl_1k.jpg")
		paint.normal_scale = 0.035
		material_cache[key] = paint
		return paint
	if key == "Glove_Charcoal":
		var glove: StandardMaterial3D = StandardMaterial3D.new()
		glove.albedo_color = paint_tints[key]
		glove.metallic = 0.02
		glove.roughness = 0.62
		material_cache[key] = glove
		return glove
	if key == "Pick_Wood":
		var wood: StandardMaterial3D = StandardMaterial3D.new()
		wood.albedo_color = paint_tints[key]
		wood.metallic = 0.0
		wood.roughness = 0.82
		material_cache[key] = wood
		return wood
	if key == "Hazard":
		var hazard: ShaderMaterial = ShaderMaterial.new()
		hazard.shader = load("res://shaders/hazard_stripe.gdshader") as Shader
		material_cache[key] = hazard
		return hazard
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = paint_tints.get(key, Color("777c72"))
	material.roughness = 0.45 if key == "Steel" else 0.78
	material.metallic = 0.8 if key == "Steel" else 0.08
	if key == "Glass":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.62
	if key == "Emissive_Furnace" or key == "Emissive_Status":
		material = _emission_material(Color("ff6320") if key == "Emissive_Furnace" else Color("4ddd75"), true)
	material_cache[key] = material
	return material

func _emission_material(color: Color, enabled: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color if enabled else color.darkened(0.65)
	material.roughness = 0.28
	material.emission_enabled = enabled
	material.emission = color
	material.emission_energy_multiplier = 1.8 if enabled else 0.0
	return material

func _add_particles(parent: Node3D, node_name: String, offset: Vector3, amount: int, color: Color) -> void:
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.name = node_name
	particles.position = offset
	particles.amount = amount
	particles.lifetime = 1.4 if node_name in ["ConstructorSparks", "AssemblerSparks"] else 2.2
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 24.0 if node_name in ["ConstructorSparks", "AssemblerSparks"] else 14.0
	particles.initial_velocity_min = 0.45 if node_name in ["ConstructorSparks", "AssemblerSparks"] else 0.35
	particles.initial_velocity_max = 1.8 if node_name in ["ConstructorSparks", "AssemblerSparks"] else 0.95
	particles.gravity = Vector3(0.0, 0.18, 0.0)
	particles.emitting = false
	particles.fixed_fps = 30
	var puff: SphereMesh = SphereMesh.new()
	puff.radius = 0.07 if node_name in ["ConstructorSparks", "AssemblerSparks"] else 0.12
	puff.height = 0.14 if node_name in ["ConstructorSparks", "AssemblerSparks"] else 0.24
	particles.mesh = puff
	var smoke: StandardMaterial3D = StandardMaterial3D.new()
	smoke.albedo_color = color
	smoke.roughness = 1.0
	smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke.emission_enabled = node_name in ["ConstructorSparks", "AssemblerSparks"]
	smoke.emission = color
	smoke.emission_energy_multiplier = 1.2
	particles.material_override = smoke
	parent.add_child(particles)

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
