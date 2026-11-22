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
var item_mesh_cache: Dictionary = {}
var item_material_cache: Dictionary = {}
var building_definitions: Dictionary = BuildingDefs.all()
var machine_models: MachineModels = MachineModels.new()
var interpolation_alpha: float = 0.0
var cable_visual: MeshInstance3D
var cable_mesh: ImmediateMesh
var cable_signature: String = ""

func setup(factory_sim: FactorySim, factory_terrain: FactoryTerrain) -> void:
	sim = factory_sim
	terrain = factory_terrain

func add_preview_port_markers(root: Node3D, kind: String) -> void:
	var preview_entity: FactoryEntity = FactoryEntity.new()
	preview_entity.kind = kind
	_add_port_markers(root, preview_entity)
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func refresh() -> void:
	if sim == null or DisplayServer.get_name() == "headless":
		return
	var live_ids: Dictionary = {}
	for raw_id: Variant in sim.entities:
		var entity: FactoryEntity = sim.entities[raw_id]
		live_ids[entity.id] = true
		var signature: String = "%s:%.3f:%.3f:%.3f:%.3f" % [entity.kind, entity.position.x, entity.position.y, entity.position.z, entity.yaw]
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
			visual.position = Vector3.ZERO if entity.kind in ["belt_mk1", "belt_mk2"] else entity.position
			visual.rotation.y = entity.yaw
		if entity.kind == "spire":
			_update_spire(visual, sim.spire_stage)
		if entity.kind in ["belt_mk1", "belt_mk2"]:
			var belt_surface: MeshInstance3D = visual.find_child("BeltSurface", true, false) as MeshInstance3D
			if belt_surface != null and belt_surface.material_override is ShaderMaterial:
				var belt_shader: ShaderMaterial = belt_surface.material_override
				belt_shader.set_shader_parameter("belt_speed", 0.9 if not entity.belt_items.is_empty() else 0.0)
		else:
			machine_models.animate(visual, entity)
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
	var size: Vector3 = BuildingDefs.size_of(entity.kind)
	var footprint_cells := Vector2i(maxi(1, roundi(size.x * 0.5)), maxi(1, roundi(size.z * 0.5)))
	if entity.kind in ["belt_mk1", "belt_mk2"]:
		_add_belt_mesh(root, entity)
	elif entity.kind == "belt_pole":
		_add_collider(root, size, Vector3(0.0, size.y * 0.5, 0.0))
		_add_cylinder(root, "BeltPole", 0.07, 1.5, Vector3.ZERO, Color("5f6a62"), 0.55)
	else:
		var collider_size: Vector3 = Vector3(size.x, maxf(1.0, size.y), size.z)
		var collider_position: Vector3 = Vector3(0.0, size.y * 0.5, 0.0)
		_add_collider(root, collider_size, collider_position)
		var plinth: MeshInstance3D = MeshInstance3D.new()
		var plinth_mesh: BoxMesh = BoxMesh.new()
		plinth_mesh.size = Vector3(size.x, 1.6, size.z)
		plinth.mesh = plinth_mesh
		plinth.position.y = -0.8
		plinth.material_override = _material("machine_plinth", Color("535b57"), 0.35, 0.86)
		root.add_child(plinth)
		machine_models.build(entity.kind, root, footprint_cells, Vector3.ZERO)
		_add_port_markers(root, entity)
		var status: Label3D = Label3D.new()
		status.name = "Status"
		status.text = "●"
		var height: float = {"miner_mk1": 6.5, "smelter": 5.0, "constructor": 3.8,
			"assembler": 4.2, "geo_tap": 4.2, "power_pole": 6.3, "storage": 3.4,
			"splitter": 1.9, "merger": 1.9, "spire": 17.0}.get(entity.kind, 3.0)
		status.position = Vector3(0.0, height + 0.35, 0.0)
		status.font_size = 22
		status.pixel_size = 0.01
		status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(status)
		if entity.kind == "spire":
			var assembly: SpireVisual = SpireVisual.new()
			assembly.name = "ShipSections"
			assembly.position = Vector3.ZERO
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

func _add_belt_mesh(root: Node3D, entity: FactoryEntity) -> void:
	var curve: PackedVector3Array = entity.extra.get("curve", PackedVector3Array())
	if curve.size() != 4:
		return
	var length: float = float(entity.extra.get("length", 0.0))
	var steps: int = maxi(2, ceili(length * 2.0))
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails: SurfaceTool = SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous_center: Vector3 = _belt_point(curve, 0.0)
	var previous_tangent: Vector3 = (_belt_point(curve, 0.01) - previous_center).normalized()
	for index: int in range(1, steps + 1):
		var center: Vector3 = _belt_point(curve, float(index) / float(steps))
		var tangent: Vector3 = (center - previous_center).normalized()
		var side: Vector3 = Vector3.UP.cross(tangent).normalized() * 0.42
		var previous_side: Vector3 = Vector3.UP.cross(previous_tangent).normalized() * 0.42
		_add_quad(surface, previous_center - previous_side + Vector3.UP * 0.05, previous_center + previous_side + Vector3.UP * 0.05,
			center + side + Vector3.UP * 0.05, center - side + Vector3.UP * 0.05)
		_add_quad(rails, previous_center - previous_side + Vector3.UP * 0.22, previous_center - previous_side + Vector3.UP * 0.05,
			center - side + Vector3.UP * 0.05, center - side + Vector3.UP * 0.22)
		_add_quad(rails, previous_center + previous_side + Vector3.UP * 0.05, previous_center + previous_side + Vector3.UP * 0.22,
			center + side + Vector3.UP * 0.22, center + side + Vector3.UP * 0.05)
		previous_center = center
		previous_tangent = tangent
	var deck: MeshInstance3D = MeshInstance3D.new()
	deck.name = "BeltSurface"
	deck.mesh = surface.commit()
	deck.material_override = _material("belt_surface", Color("262a28"), 0.12, 0.88)
	root.add_child(deck)
	var rail_mesh: MeshInstance3D = MeshInstance3D.new()
	rail_mesh.mesh = rails.commit()
	rail_mesh.material_override = _material("belt_rail", Color("d29a3c"), 0.58, 0.7)
	(rail_mesh.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	root.add_child(rail_mesh)
	var collision_body: StaticBody3D = StaticBody3D.new()
	collision_body.name = "BeltCollision"
	for index: int in range(steps):
		var t0: float = float(index) / float(steps)
		var t1: float = float(index + 1) / float(steps)
		var start: Vector3 = _belt_point(curve, t0)
		var finish: Vector3 = _belt_point(curve, t1)
		var tangent: Vector3 = (finish - start).normalized()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(0.84, 0.5, start.distance_to(finish) + 0.08)
		collision.shape = box
		collision.position = (start + finish) * 0.5 + Vector3.UP * 0.12
		collision.rotation.y = atan2(tangent.x, tangent.z)
		collision_body.add_child(collision)
	root.add_child(collision_body)
	for distance: int in range(0, ceili(length) + 1, 4):
		var point: Vector3 = _belt_point(curve, clampf(float(distance) / length, 0.0, 1.0))
		var height: float = maxf(0.2, point.y - terrain.height_at(point.x, point.z))
		for side_sign: float in [-1.0, 1.0]:
			var leg: MeshInstance3D = MeshInstance3D.new()
			var leg_mesh: CylinderMesh = CylinderMesh.new()
			leg_mesh.top_radius = 0.045
			leg_mesh.bottom_radius = 0.065
			leg_mesh.height = height
			leg.mesh = leg_mesh
			leg.position = point + Vector3(side_sign * 0.34, -height * 0.5, 0.0)
			leg.material_override = _material("belt_support", Color("6d7770"), 0.62, 0.82)
			root.add_child(leg)

func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	tool.set_normal(Vector3.UP)
	tool.add_vertex(a)
	tool.add_vertex(c)
	tool.add_vertex(b)
	tool.add_vertex(a)
	tool.add_vertex(d)
	tool.add_vertex(c)

func _belt_point(curve: PackedVector3Array, t: float) -> Vector3:
	var u: float = 1.0 - t
	return curve[0] * u * u * u + curve[1] * 3.0 * u * u * t + curve[2] * 3.0 * u * t * t + curve[3] * t * t * t

func _belt_tangent(curve: PackedVector3Array, t: float) -> Vector3:
	return (_belt_point(curve, minf(1.0, t + 0.005)) - _belt_point(curve, maxf(0.0, t - 0.005))).normalized()

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
	for port: Dictionary in building_definitions.get(entity.kind, {}).get("ports", []):
		var color: Color = Color("4aa9d0") if port["dir"] == "in" else Color("df8845")
		var arrow: Node3D = _make_arrow("port_arrow", color)
		var local_position: Vector3 = port["pos"]
		arrow.position = Vector3(local_position.x, 0.09, local_position.z)
		var normal: Vector3 = port["normal"]
		arrow.rotation.y = atan2(normal.x, normal.z)
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
		if entity.kind not in ["belt_mk1", "belt_mk2"]:
			continue
		var curve: PackedVector3Array = entity.extra.get("curve", PackedVector3Array())
		if curve.size() != 4:
			continue
		for item: Dictionary in entity.belt_items:
			var item_id: String = str(item["item"])
			if not item_positions_by_type.has(item_id):
				item_positions_by_type[item_id] = []
			var interpolation: float = interpolation_alpha if float(item.get("born_at", -1.0)) < sim.time else 0.0
			var length: float = float(entity.extra["length"])
			var s: float = clampf(float(item["s"]) + float(entity.extra["speed"]) * 0.05 * interpolation, 0.0, length)
			var t: float = s / maxf(length, 0.01)
			item_positions_by_type[item_id].append({"position": _belt_point(curve, t) + Vector3.UP * 0.32,
				"tangent": _belt_tangent(curve, t)})
	for item_id: String in item_positions_by_type:
		if item_positions_by_type[item_id].is_empty():
			continue
		if not item_multimeshes.has(item_id):
			var multimesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
			var multimesh: MultiMesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = _item_mesh(item_id)
			multimesh_instance.multimesh = multimesh
			multimesh_instance.material_override = _item_material(item_id)
			item_multimeshes[item_id] = multimesh_instance
			add_child(multimesh_instance)
		var mm: MultiMesh = item_multimeshes[item_id].multimesh
		mm.instance_count = item_positions_by_type[item_id].size()
		for index: int in range(item_positions_by_type[item_id].size()):
			var item_transform: Dictionary = item_positions_by_type[item_id][index]
			mm.set_instance_transform(index, Transform3D(Basis.looking_at(item_transform["tangent"], Vector3.UP), item_transform["position"]))

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

func _item_mesh(item_id: String) -> Mesh:
	if item_mesh_cache.has(item_id):
		return item_mesh_cache[item_id]
	var mesh: Mesh
	match item_id:
		"iron_ore", "copper_ore", "limestone":
			var ore: SphereMesh = SphereMesh.new()
			ore.radius = 0.28
			ore.height = 0.42
			ore.radial_segments = 8
			ore.rings = 5
			mesh = ore
		"iron_ingot":
			var ingot: BoxMesh = BoxMesh.new()
			ingot.size = Vector3(0.58, 0.2, 0.28)
			mesh = ingot
		"iron_plate":
			var plate: BoxMesh = BoxMesh.new()
			plate.size = Vector3(0.62, 0.1, 0.44)
			mesh = plate
		"iron_rod", "screw":
			var rod: CylinderMesh = CylinderMesh.new()
			rod.top_radius = 0.1
			rod.bottom_radius = 0.1
			rod.height = 0.55
			rod.radial_segments = 8
			mesh = rod
		_:
			mesh = _box_mesh("belt_item_%s" % item_id, Vector3(0.42, 0.32, 0.38))
	item_mesh_cache[item_id] = mesh
	return mesh

func _item_material(item_id: String) -> StandardMaterial3D:
	if item_material_cache.has(item_id):
		return item_material_cache[item_id]
	var item_data: Dictionary = Items.all().get(item_id, {})
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = item_data.get("color", Color("9b8d73"))
	material.metallic = 0.22 if item_id in ["iron_ingot", "iron_plate", "iron_rod"] else 0.04
	material.roughness = 0.72
	item_material_cache[item_id] = material
	return material

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
			if first.position.distance_to(second.position) > 24.0:
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
			var distance: float = building.position.distance_to(pole.position)
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
		var start: Vector3 = segment[0]
		var finish: Vector3 = segment[1]
		for index: int in range(12):
			var first_t: float = float(index) / 12.0
			var second_t: float = float(index + 1) / 12.0
			var first_point: Vector3 = start.lerp(finish, first_t)
			var second_point: Vector3 = start.lerp(finish, second_t)
			first_point.y -= 1.6 * 4.0 * first_t * (1.0 - first_t)
			second_point.y -= 1.6 * 4.0 * second_t * (1.0 - second_t)
			cable_mesh.surface_add_vertex(first_point)
			cable_mesh.surface_add_vertex(second_point)
	cable_mesh.surface_end()
	cable_visual.visible = true

func _cable_point(entity: FactoryEntity) -> Vector3:
	return entity.position + Vector3(0.0, 4.8 if entity.kind == "power_pole" else maxf(2.0, BuildingDefs.size_of(entity.kind).y * 0.7), 0.0)

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
