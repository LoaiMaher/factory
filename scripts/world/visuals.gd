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

func setup(factory_sim: FactorySim, factory_terrain: FactoryTerrain) -> void:
	sim = factory_sim
	terrain = factory_terrain

func refresh() -> void:
	if sim == null:
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
	else:
		var body: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		var size: Vector2i = building_definitions.get(entity.kind, {}).get("size", Vector2i.ONE)
		box.size = Vector3(float(size.x) * 1.75, 2.5, float(size.y) * 1.75)
		body.mesh = _box_mesh("building_%s" % entity.kind, box.size)
		body.position = Vector3((float(size.x) - 1.0) * 1.0, 1.25, (float(size.y) - 1.0) * 1.0)
		body.material_override = _material(entity.kind, _color_for(entity.kind))
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
			spire.material_override = _material("spire", Color("d9c89c"))
			spire.name = "Stage0"
			root.add_child(spire)
			var gantry: MeshInstance3D = MeshInstance3D.new()
			var gantry_mesh: BoxMesh = BoxMesh.new()
			gantry_mesh.size = Vector3(12.0, 0.55, 0.55)
			gantry.mesh = gantry_mesh
			gantry.position = body.position + Vector3(5.0, 8.0, 5.0)
			gantry.material_override = _material("gantry", Color("837d68"))
			gantry.name = "Gantry"
			root.add_child(gantry)
			for side: float in [-4.8, 4.8]:
				var crane_leg: MeshInstance3D = MeshInstance3D.new()
				var leg_mesh: BoxMesh = BoxMesh.new()
				leg_mesh.size = Vector3(0.48, 8.0, 0.48)
				crane_leg.mesh = leg_mesh
				crane_leg.position = body.position + Vector3(5.0 + side, 4.0, 5.0)
				crane_leg.material_override = _material("gantry", Color("837d68"))
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
			var t: float = clampf(float(item["pos"]), 0.0, 1.0)
			var local_position: Vector3 = Vector3.ZERO
			var direction: Vector2i = BELT_DIRECTIONS[entity.rotation]
			local_position.x = float(direction.x) * (t - 0.5) * 2.0
			local_position.z = float(direction.y) * (t - 0.5) * 2.0
			var belt_position: Vector3 = (entity_nodes[entity.id] as Node3D).position
			item_positions_by_type[item_id].append(belt_position + local_position + Vector3(0.0, 0.48, 0.0))
	for item_id: String in item_positions_by_type:
		if item_positions_by_type[item_id].is_empty():
			continue
		if not item_multimeshes.has(item_id):
			var multimesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
			var multimesh: MultiMesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			var item_mesh: SphereMesh = SphereMesh.new()
			item_mesh.radius = 0.19
			item_mesh.height = 0.26
			multimesh.mesh = item_mesh
			multimesh_instance.multimesh = multimesh
			multimesh_instance.material_override = _material("item_%s" % item_id, Items.all()[item_id]["color"])
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

func _color_for(kind: String) -> Color:
	match kind:
		"miner_mk1": return Color("747b62")
		"smelter": return Color("a9654e")
		"constructor": return Color("6d8790")
		"assembler": return Color("897995")
		"power_pole": return Color("dbb862")
		"geo_tap": return Color("7aa4a3")
		"spire": return Color("c5b38e")
		"storage": return Color("9a8261")
		_: return Color("778489")

func _material(key: String, color: Color) -> StandardMaterial3D:
	if not material_cache.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.72
		material_cache[key] = material
	return material_cache[key]

func _box_mesh(key: String, dimensions: Vector3) -> BoxMesh:
	if not mesh_cache.has(key):
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = dimensions
		mesh_cache[key] = mesh
	return mesh_cache[key]
