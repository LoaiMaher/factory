extends Node3D
class_name FactoryVisuals

const BELT_DIRECTIONS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

var sim: FactorySim
var terrain: FactoryTerrain
var entity_nodes: Dictionary = {}
var item_multimeshes: Dictionary = {}
var material_cache: Dictionary = {}
var mesh_cache: Dictionary = {}
var item_positions_by_type: Dictionary = {}
var building_definitions: Dictionary = BuildingDefs.all()
var interpolation_alpha: float = 0.0
var cable_visual: MeshInstance3D
var cable_mesh: ImmediateMesh
var cable_signature: String = ""

func setup(factory_sim: FactorySim, factory_terrain: FactoryTerrain) -> void:
	sim = factory_sim
	terrain = factory_terrain

func refresh() -> void:
	if sim == null or DisplayServer.get_name() == "headless":
		return
	var live_ids: Dictionary = {}
	for raw_id: Variant in sim.entities:
		var entity: FactoryEntity = sim.entities[raw_id]
		live_ids[entity.id] = true
		var signature: String = "%s:%d:%d:%d" % [entity.kind, entity.cell.x, entity.cell.y, entity.rotation]
		var is_new: bool = not entity_nodes.has(entity.id)
		if not is_new and str((entity_nodes[entity.id] as Node3D).get_meta("visual_signature", "")) != signature:
			(entity_nodes[entity.id] as Node).queue_free()
			entity_nodes.erase(entity.id)
			is_new = true
		if is_new:
			var building: Node3D = _make_entity_visual(entity)
			building.set_meta("visual_signature", signature)
			entity_nodes[entity.id] = building
			add_child(building)
		var visual: Node3D = entity_nodes[entity.id]
		if is_new:
			var base_size: Vector2i = building_definitions.get(entity.kind, {}).get("size", Vector2i.ONE)
			var size: Vector2i = base_size if entity.rotation % 2 == 0 else Vector2i(base_size.y, base_size.x)
			var rotation_angle: float = float(entity.rotation) * PI / 2.0
			var base_center: Vector3 = Vector3(float(base_size.x - 1), 0.0, float(base_size.y - 1))
			var rotated_center: Vector3 = Basis(Vector3.UP, rotation_angle) * base_center
			var target_center: Vector3 = Vector3(float(size.x - 1), 0.0, float(size.y - 1))
			var placement_offset: Vector3 = target_center - rotated_center
			visual.position = terrain.point_for_cell(entity.cell) + placement_offset
			if not entity.kind.begins_with("belt_"):
				visual.position.y = terrain.footprint_height(entity.cell, entity.kind, entity.rotation)
			visual.rotation.y = rotation_angle
		if entity.kind == "spire":
			_update_spire(visual, sim.spire_stage)
		var drill: Node3D = visual.get_node_or_null("DrillHead") as Node3D
		if drill != null:
			drill.rotation.y = Time.get_ticks_msec() * 0.002 if entity.status == "Running" else 0.0
		var furnace_mouth: MeshInstance3D = visual.get_node_or_null("FurnaceMouth") as MeshInstance3D
		if furnace_mouth != null:
			furnace_mouth.material_override = _material("furnace_mouth_on" if entity.status == "Running" else "furnace_mouth_off",
				Color("d46b31") if entity.status == "Running" else Color("393a35"), 0.15, 0.84, entity.status == "Running")
		var indicator: Label3D = visual.get_node_or_null("Status") as Label3D
		if indicator != null:
			indicator.text = "●" if entity.status == "Running" else "●"
			indicator.modulate = Color("73d38f") if entity.status == "Running" else Color("e4be58") if entity.status.begins_with("Low") else Color("e46e5d")
			indicator.visible = entity.status != "No recipe" and entity.status != "Stopped"
	for raw_id: Variant in entity_nodes.keys():
		if not live_ids.has(raw_id):
			(entity_nodes[raw_id] as Node).queue_free()
			entity_nodes.erase(raw_id)
	_update_item_instances()
	_refresh_power_cables()

func _make_entity_visual(entity: FactoryEntity) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Entity_%d_%s" % [entity.id, entity.kind]
	root.set_meta("entity_id", entity.id)
	if entity.kind.begins_with("belt_"):
		var body: MeshInstance3D = MeshInstance3D.new()
		var belt_dimensions: Vector3 = Vector3(1.7, 0.18, 1.5)
		body.mesh = _box_mesh("belt_body", belt_dimensions)
		body.position.y = 0.18
		body.material_override = _material("belt", Color("303a3b"))
		root.add_child(body)
		_add_collider(root, belt_dimensions, body.position)
		for side: float in [-0.57, 0.57]:
			var rail: MeshInstance3D = MeshInstance3D.new()
			rail.mesh = _box_mesh("belt_rail", Vector3(1.6, 0.32, 0.08))
			rail.position = Vector3(0.0, 0.34, side)
			rail.material_override = _material("rail", Color("879492"))
			root.add_child(rail)
		for index: int in range(2):
			var cue: Node3D = _make_arrow("belt_chevron", Color("c3a451"))
			cue.scale = Vector3(0.64, 0.42, 0.64)
			cue.position = Vector3(0.0, 0.31, -0.35 + float(index) * 0.66)
			root.add_child(cue)
	else:
		var body: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		var size: Vector2i = building_definitions.get(entity.kind, {}).get("size", Vector2i.ONE)
		box.size = Vector3(float(size.x) * 1.75, 2.5, float(size.y) * 1.75)
		body.mesh = _box_mesh("building_%s" % entity.kind, box.size)
		body.position = Vector3((float(size.x) - 1.0) * 1.0, 1.25, (float(size.y) - 1.0) * 1.0)
		body.material_override = _material(entity.kind, _color_for(entity.kind), 0.28, 0.78)
		root.add_child(body)
		_add_collider(root, box.size, body.position)
		var plinth: MeshInstance3D = MeshInstance3D.new()
		plinth.mesh = _box_mesh("plinth_%s" % entity.kind, Vector3(box.size.x + 0.3, 1.0, box.size.z + 0.3))
		plinth.position = Vector3(body.position.x, -0.5, body.position.z)
		plinth.material_override = _material("plinth", Color("555b56"))
		root.add_child(plinth)
		var roof: MeshInstance3D = MeshInstance3D.new()
		var top: BoxMesh = BoxMesh.new()
		top.size = Vector3(box.size.x * 0.72, 0.22, box.size.z * 0.72)
		roof.mesh = top
		roof.position = body.position + Vector3(0.0, 1.36, 0.0)
		roof.material_override = _material("trim", Color("53656a"))
		root.add_child(roof)
		_add_machine_silhouette(root, entity, size, body.position)
		_add_port_markers(root, entity)
		var status: Label3D = Label3D.new()
		status.name = "Status"
		status.text = "●"
		status.position = body.position + Vector3(0.0, 2.2, 0.0)
		status.font_size = 44
		status.pixel_size = 0.012
		status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(status)
		if entity.kind == "spire":
			var spire: MeshInstance3D = MeshInstance3D.new()
			var spire_mesh: BoxMesh = BoxMesh.new()
			spire_mesh.size = Vector3(0.8, 12.0, 0.8)
			spire.mesh = spire_mesh
			spire.position = body.position + Vector3(5.0, 6.0, 5.0)
			spire.material_override = _material("spire_steel", Color("38403d"), 0.72, 0.74)
			spire.name = "Stage0"
			root.add_child(spire)
			var gantry: MeshInstance3D = MeshInstance3D.new()
			var gantry_mesh: BoxMesh = BoxMesh.new()
			gantry_mesh.size = Vector3(12.0, 0.55, 0.55)
			gantry.mesh = gantry_mesh
			gantry.position = body.position + Vector3(5.0, 8.0, 5.0)
			gantry.material_override = _material("gantry", Color("b48d43"), 0.42, 0.76)
			gantry.name = "Gantry"
			root.add_child(gantry)
			for side: float in [-4.8, 4.8]:
				var crane_leg: MeshInstance3D = MeshInstance3D.new()
				var leg_mesh: BoxMesh = BoxMesh.new()
				leg_mesh.size = Vector3(0.48, 8.0, 0.48)
				crane_leg.mesh = leg_mesh
				crane_leg.position = body.position + Vector3(5.0 + side, 4.0, 5.0)
				crane_leg.material_override = _material("gantry", Color("b48d43"), 0.42, 0.76)
				root.add_child(crane_leg)
			var assembly: SpireVisual = SpireVisual.new()
			assembly.name = "ShipSections"
			assembly.position = body.position
			root.add_child(assembly)
	return root

func _add_collider(parent: Node3D, dimensions: Vector3, offset: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	shape.position = offset
	body.add_child(shape)
	parent.add_child(body)

func _add_machine_silhouette(root: Node3D, entity: FactoryEntity, size: Vector2i, body_position: Vector3) -> void:
	var center: Vector3 = Vector3(float(size.x - 1), 0.0, float(size.y - 1))
	match entity.kind:
		"miner_mk1":
			for x: float in [-0.72, 0.72]:
				for z: float in [-0.62, 0.62]:
					_add_cylinder(root, "miner_leg", 0.12, 4.4, center + Vector3(x, 2.0, z), Color("515b54"), 0.38)
			_add_box(root, "miner_crossbar", Vector3(1.9, 0.14, 0.14), center + Vector3(0.0, 3.9, 0.0), "miner_frame", Color("69736b"))
			_add_cylinder(root, "miner_shaft", 0.22, 2.0, center + Vector3(0.0, 0.0, 0.0), Color("6b7169"), 0.5)
			var drill: Node3D = Node3D.new()
			drill.name = "DrillHead"
			drill.position = center + Vector3(0.0, 0.82, 0.0)
			root.add_child(drill)
			_add_cylinder(drill, "drill_head", 0.75, 0.38, Vector3.ZERO, Color("b76a3f"), 0.58)
			_add_cylinder(drill, "drill_bit", 0.12, 0.78, Vector3(0.0, -0.55, 0.0), Color("49514d"), 0.65)
		"smelter":
			_add_cylinder(root, "smelter_chimney", 0.34, 3.2, body_position + Vector3(0.82, 2.25, -0.42), Color("555d59"), 0.4)
			_add_box(root, "smelter_chimney_rim", Vector3(0.82, 0.16, 0.82), body_position + Vector3(0.82, 3.9, -0.42), "warning_trim", Color("c08d43"))
			var mouth: MeshInstance3D = _add_box(root, "furnace_mouth", Vector3(0.72, 0.52, 0.12), body_position + Vector3(0.0, -0.25, 0.9), "furnace_mouth_off", Color("393a35"))
			mouth.name = "FurnaceMouth"
			_add_box(root, "smelter_brow", Vector3(0.96, 0.14, 0.2), body_position + Vector3(0.0, 0.1, 0.94), "warning_trim", Color("bd843d"))
		"constructor":
			for x: float in [-1.2, 1.2]:
				_add_box(root, "constructor_post", Vector3(0.16, 2.3, 0.16), body_position + Vector3(x, 1.75, 0.0), "machine_trim", Color("43514f"), 0.4)
			_add_box(root, "constructor_gantry", Vector3(2.8, 0.2, 0.28), body_position + Vector3(0.0, 2.8, 0.0), "machine_trim", Color("839087"), 0.42)
			_add_box(root, "constructor_carriage", Vector3(0.55, 0.44, 0.58), body_position + Vector3(0.0, 2.43, 0.12), "warning_trim", Color("ba8743"))
		"assembler":
			for x: float in [-0.86, 0.86]:
				_add_cylinder(root, "assembler_hopper", 0.48, 1.2, body_position + Vector3(x, 1.9, -0.68), Color("72786c"), 0.3)
				_add_cylinder(root, "assembler_hopper_lip", 0.56, 0.14, body_position + Vector3(x, 2.55, -0.68), Color("c18c43"), 0.35)
			_add_box(root, "assembler_bridge", Vector3(2.1, 0.18, 0.3), body_position + Vector3(0.0, 2.9, -0.68), "machine_trim", Color("59645d"))
		"storage":
			for x: float in [-1.45, -0.85, -0.25, 0.35, 0.95, 1.55]:
				_add_box(root, "storage_rib", Vector3(0.08, 2.35, 0.1), body_position + Vector3(x, 0.0, 0.9), "storage_rib", Color("88785d"), 0.28)
		"splitter", "merger":
			var outputs: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]
			for index: int in range(outputs.size()):
				var direction: Vector2i = outputs[index] if entity.kind == "splitter" else -outputs[index]
				var arrow: Node3D = _make_arrow("junction_arrow_%d" % index, Color("d2ae50"))
				arrow.position = center + Vector3(float(direction.x) * 0.38, 1.46, float(direction.y) * 0.38)
				arrow.rotation.y = _rotation_for(direction) * PI / 2.0
				root.add_child(arrow)
		"power_pole":
			_add_cylinder(root, "power_pole_mast", 0.12, 5.5, body_position + Vector3(0.0, 1.6, 0.0), Color("4d5752"), 0.54)
			_add_box(root, "power_lamp", Vector3(0.58, 0.35, 0.58), body_position + Vector3(0.0, 4.55, 0.0), "power_lamp", Color("d1a84f"), 0.18, true)
			_add_box(root, "power_crossarm", Vector3(1.35, 0.1, 0.12), body_position + Vector3(0.0, 4.1, 0.0), "machine_trim", Color("626e66"), 0.45)
		"geo_tap":
			_add_cylinder(root, "geo_stack_main", 0.3, 4.4, body_position + Vector3(0.35, 2.0, -0.25), Color("56605b"), 0.48)
			_add_cylinder(root, "geo_stack_side", 0.16, 3.1, body_position + Vector3(-0.48, 1.35, 0.32), Color("74776c"), 0.42)
			_add_box(root, "geo_warning", Vector3(1.45, 0.15, 0.15), body_position + Vector3(0.0, 0.7, 0.95), "warning_trim", Color("c18a42"))
		"spire":
			for x: float in [-3.4, 3.4]:
				for z: float in [-3.4, 3.4]:
					_add_box(root, "spire_pylon", Vector3(0.58, 16.0, 0.58), body_position + Vector3(x, 8.0, z), "spire_steel", Color("343d3d"), 0.72)
			for y: float in [3.0, 8.0, 13.0]:
				_add_box(root, "spire_ring", Vector3(8.0, 0.24, 8.0), body_position + Vector3(0.0, y, 0.0), "spire_warning", Color("d0a33f"), 0.46)
		_:
			pass

func _add_port_markers(root: Node3D, entity: FactoryEntity) -> void:
	var ports: Dictionary = sim.port_cells(entity.kind, entity.cell, entity.rotation)
	for port_cell: Vector2i in ports.get("input", []):
		var direction: Vector2i = _forward(entity.rotation)
		if entity.kind == "merger":
			direction = Vector2i(signi(entity.cell.x - port_cell.x), signi(entity.cell.y - port_cell.y))
		_add_port_arrow(root, entity, port_cell, Color("4aa9d0"), direction)
	for port_cell: Vector2i in ports.get("output", []):
		var direction: Vector2i = port_cell - entity.cell if entity.kind == "splitter" else _forward(entity.rotation)
		_add_port_arrow(root, entity, port_cell, Color("df8845"), direction)

func _add_port_arrow(root: Node3D, entity: FactoryEntity, port_cell: Vector2i, color: Color, direction: Vector2i) -> void:
	var offset: Vector3 = Vector3(float(port_cell.x - entity.cell.x) * 2.0, 0.09, float(port_cell.y - entity.cell.y) * 2.0)
	offset = Basis(Vector3.UP, -float(entity.rotation) * PI / 2.0) * offset
	var arrow: Node3D = _make_arrow("port_arrow", color)
	arrow.position = offset
	arrow.rotation.y = float(posmod(_rotation_for(direction) - entity.rotation, 4)) * PI / 2.0
	root.add_child(arrow)

func _make_arrow(key: String, color: Color) -> Node3D:
	var arrow: Node3D = Node3D.new()
	arrow.name = key
	var shaft: MeshInstance3D = MeshInstance3D.new()
	shaft.mesh = _box_mesh("arrow_shaft", Vector3(0.075, 0.045, 0.38))
	shaft.material_override = _material("arrow_%s" % color.to_html(false), color, 0.05, 0.8)
	arrow.add_child(shaft)
	for side: float in [-1.0, 1.0]:
		var head: MeshInstance3D = MeshInstance3D.new()
		head.mesh = _box_mesh("arrow_head", Vector3(0.075, 0.045, 0.26))
		head.position = Vector3(side * 0.09, 0.0, 0.16)
		head.rotation.y = side * 0.7
		head.material_override = shaft.material_override
		arrow.add_child(head)
	return arrow

func _add_box(parent: Node3D, key: String, dimensions: Vector3, position: Vector3, material_key: String, color: Color,
		metallic: float = 0.2, emissive: bool = false) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = _box_mesh("%s_%.2f_%.2f_%.2f" % [key, dimensions.x, dimensions.y, dimensions.z], dimensions)
	part.position = position
	part.material_override = _material(material_key, color, metallic, 0.78, emissive)
	parent.add_child(part)
	return part

func _add_cylinder(parent: Node3D, key: String, radius: float, height: float, position: Vector3,
		color: Color, metallic: float = 0.2) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = _cylinder_mesh("%s_%.2f_%.2f" % [key, radius, height], radius, height)
	part.position = position
	part.material_override = _material(key, color, metallic, 0.78)
	parent.add_child(part)
	return part

func _update_item_instances() -> void:
	for item_id: String in item_multimeshes:
		var instance: MultiMeshInstance3D = item_multimeshes[item_id]
		instance.multimesh.instance_count = 0
	for item_id: String in item_positions_by_type:
		(item_positions_by_type[item_id] as Array).clear()
	for entity_id: Variant in sim.entities:
		var entity: FactoryEntity = sim.entities[entity_id]
		if not entity.kind.begins_with("belt_"):
			continue
		for item: Dictionary in entity.belt_items:
			var item_id: String = str(item["item"])
			if not item_positions_by_type.has(item_id):
				item_positions_by_type[item_id] = []
			var item_speed: float = 1.0 if entity.kind == "belt_mk2" else 0.5
			var interpolation: float = interpolation_alpha if float(item.get("born_at", -1.0)) < sim.time else 0.0
			var t: float = clampf(float(item["pos"]) + item_speed * 0.05 * interpolation, 0.0, 1.0)
			var local_position: Vector3 = Vector3.ZERO
			local_position.z = (t - 0.5) * 2.0
			var belt_position: Vector3 = (entity_nodes[entity.id] as Node3D).position
			item_positions_by_type[item_id].append(belt_position + local_position + Vector3(0.0, 0.52, 0.0))
	for item_id: String in item_positions_by_type:
		if item_positions_by_type[item_id].is_empty():
			continue
		if not item_multimeshes.has(item_id):
			var multimesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
			var multimesh: MultiMesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = _box_mesh("belt_item_cube", Vector3(0.46, 0.48, 0.46))
			multimesh_instance.multimesh = multimesh
			multimesh_instance.material_override = _material("item_%s" % item_id, Items.all()[item_id]["color"], 0.08, 0.82)
			item_multimeshes[item_id] = multimesh_instance
			add_child(multimesh_instance)
		var mm: MultiMesh = item_multimeshes[item_id].multimesh
		mm.instance_count = item_positions_by_type[item_id].size()
		for index: int in range(item_positions_by_type[item_id].size()):
			mm.set_instance_transform(index, Transform3D(Basis.IDENTITY, item_positions_by_type[item_id][index]))

func _update_spire(root: Node3D, stage: int) -> void:
	if int(root.get_meta("visual_spire_stage", -1)) == stage:
		return
	root.set_meta("visual_spire_stage", stage)
	var stage_zero: Node3D = root.get_node_or_null("Stage0")
	if stage_zero != null:
		var target_height: float = 7.0 + float(stage)
		var tween: Tween = root.create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(stage_zero, "position:y", target_height, 8.0)
	var assembly: SpireVisual = root.get_node_or_null("ShipSections") as SpireVisual
	if assembly != null:
		assembly.set_stage(stage)

func _refresh_power_cables() -> void:
	if sim == null or terrain == null or DisplayServer.get_name() == "headless":
		return
	var poles: Array[FactoryEntity] = []
	for entity: FactoryEntity in sim.entities.values():
		if entity.kind == "power_pole":
			poles.append(entity)
	var segments: Array[Array] = []
	var signature: String = ""
	for first_index: int in range(poles.size()):
		for second_index: int in range(first_index + 1, poles.size()):
			var first: FactoryEntity = poles[first_index]
			var second: FactoryEntity = poles[second_index]
			if sim.power.network_for.get(first.id, -1) != sim.power.network_for.get(second.id, -2):
				continue
			if terrain.point_for_cell(first.cell).distance_to(terrain.point_for_cell(second.cell)) > 24.0:
				continue
			segments.append([_cable_point(first), _cable_point(second)])
			signature += "%d-%d;" % [first.id, second.id]
	for building: FactoryEntity in sim.entities.values():
		if building.kind == "power_pole" or not sim.power.network_for.has(building.id):
			continue
		var nearest: FactoryEntity = null
		var nearest_distance: float = 14.0
		for pole: FactoryEntity in poles:
			if sim.power.network_for.get(building.id, -1) != sim.power.network_for.get(pole.id, -2):
				continue
			var distance: float = terrain.point_for_cell(building.cell).distance_to(terrain.point_for_cell(pole.cell))
			if distance < nearest_distance:
				nearest = pole
				nearest_distance = distance
		if nearest != null:
			segments.append([_cable_point(nearest), _cable_point(building)])
			signature += "%d-%d;" % [nearest.id, building.id]
	if signature == cable_signature:
		return
	cable_signature = signature
	if segments.is_empty():
		if cable_visual != null:
			cable_visual.visible = false
		return
	if cable_visual == null:
		cable_mesh = ImmediateMesh.new()
		cable_visual = MeshInstance3D.new()
		cable_visual.name = "PowerCables"
		cable_visual.mesh = cable_mesh
		cable_visual.material_override = _material("power_cable", Color("93a49b"), 0.58, 0.82)
		add_child(cable_visual)
	cable_mesh.clear_surfaces()
	cable_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for segment: Array in segments:
		cable_mesh.surface_add_vertex(segment[0])
		cable_mesh.surface_add_vertex(segment[1])
	cable_mesh.surface_end()
	cable_visual.visible = true

func _cable_point(entity: FactoryEntity) -> Vector3:
	var size: Vector2i = building_definitions.get(entity.kind, {}).get("size", Vector2i.ONE)
	var center: Vector3 = terrain.point_for_cell(entity.cell) + Vector3(float(size.x - 1), 0.0, float(size.y - 1))
	center.y = terrain.footprint_height(entity.cell, entity.kind, entity.rotation) + (4.8 if entity.kind == "power_pole" else 2.7)
	return center

func _color_for(kind: String) -> Color:
	match kind:
		"miner_mk1": return Color("747b62")
		"smelter": return Color("a9654e")
		"constructor": return Color("6d8790")
		"assembler": return Color("897995")
		"power_pole": return Color("5e6a60")
		"geo_tap": return Color("687a72")
		"spire": return Color("3b4340")
		"storage": return Color("786b55")
		_: return Color("5d6965")

func _material(key: String, color: Color, metallic: float = 0.18, roughness: float = 0.78,
		emissive: bool = false) -> StandardMaterial3D:
	if not material_cache.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = metallic
		material.roughness = roughness
		if emissive:
			material.emission_enabled = true
			material.emission = color * 0.5
		material_cache[key] = material
	return material_cache[key]

func _box_mesh(key: String, dimensions: Vector3) -> BoxMesh:
	if not mesh_cache.has(key):
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = dimensions
		mesh_cache[key] = mesh
	return mesh_cache[key]

func _cylinder_mesh(key: String, radius: float, height: float) -> CylinderMesh:
	if not mesh_cache.has(key):
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh_cache[key] = mesh
	return mesh_cache[key]

func _forward(rotation: int) -> Vector2i:
	return BELT_DIRECTIONS[posmod(rotation, 4)]

func _rotation_for(direction: Vector2i) -> int:
	if direction == Vector2i(1, 0):
		return 1
	if direction == Vector2i(0, -1):
		return 2
	if direction == Vector2i(-1, 0):
		return 3
	return 0
