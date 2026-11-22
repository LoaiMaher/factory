extends Node3D
class_name FactoryFoliage

const WORLD_HALF_EXTENT: float = 512.0
const CHUNK_SIZE: float = 128.0
const TREES_PER_CHUNK: int = 132
const GRASS_RADIUS: float = 60.0
const TREE_COLLISION_RADIUS: float = 76.0

var terrain: FactoryTerrain
var player: FactoryPlayer
var state: FoliageState = FoliageState.new()
var foliage_definitions: Array[Dictionary] = []
var instance_lookup: Dictionary = {}
var tree_colliders: Dictionary = {}
var chunk_bodies: Dictionary = {}
var grass_instances: Array[MultiMeshInstance3D] = []
var last_grass_region: Vector2i = Vector2i(999999, 999999)
var last_tree_collision_region: Vector2i = Vector2i(999999, 999999)

func setup(factory_terrain: FactoryTerrain, factory_player: FactoryPlayer) -> void:
	terrain = factory_terrain
	player = factory_player

func _ready() -> void:
	_generate_definitions()
	if DisplayServer.get_name() == "headless":
		return
	_build_tree_multimeshes()
	_build_scatter_multimeshes()
	_build_grass_mesh()
	_update_grass(true)
	_update_tree_collisions(true)

func _process(_delta: float) -> void:
	if DisplayServer.get_name() != "headless":
		_update_grass(false)
		_update_tree_collisions(false)

func restore_state(data: Variant) -> void:
	state.from_dict(data)
	for foliage_id: Variant in state.removed_ids:
		_hide_instance(str(foliage_id))

func remove_in_footprint(cell: Vector2i, size: Vector2i) -> void:
	for definition: Dictionary in foliage_definitions:
		var foliage_id: String = str(definition["id"])
		if state.is_removed(foliage_id):
			continue
		var foliage_cell: Vector2i = terrain.cell_from_world(definition["position"])
		if foliage_cell.x < cell.x or foliage_cell.x >= cell.x + size.x:
			continue
		if foliage_cell.y < cell.y or foliage_cell.y >= cell.y + size.y:
			continue
		state.remove(foliage_id)
		_hide_instance(foliage_id)

func remove_in_world_footprint(position: Vector3, yaw: float, size: Vector3) -> void:
	var inverse: Basis = Basis(Vector3.UP, -yaw)
	for definition: Dictionary in foliage_definitions:
		var foliage_id: String = str(definition["id"])
		if state.is_removed(foliage_id):
			continue
		var local: Vector3 = inverse * (definition["position"] - position)
		if absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.z * 0.5:
			state.remove(foliage_id)
			_hide_instance(foliage_id)

func _generate_definitions() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 88341
	var tree_index: int = 0
	var bush_index: int = 0
	var rock_index: int = 0
	var occupied: Dictionary = {}
	for chunk_z: int in range(8):
		for chunk_x: int in range(8):
			var start_x: float = -WORLD_HALF_EXTENT + float(chunk_x) * CHUNK_SIZE
			var start_z: float = -WORLD_HALF_EXTENT + float(chunk_z) * CHUNK_SIZE
			for _sample: int in range(TREES_PER_CHUNK):
				var x: float = start_x + rng.randf_range(4.0, CHUNK_SIZE - 4.0)
				var z: float = start_z + rng.randf_range(4.0, CHUNK_SIZE - 4.0)
				if Vector2(x, z).distance_to(Vector2(0.0, 38.0)) < 112.0:
					continue
				if Vector2(x, z).distance_to(terrain.LAKE_CENTER) < 120.0:
					continue
				var density: float = terrain.forest_density_at(x, z)
				if rng.randf() > density * 0.72:
					continue
				var cell_key: Vector2i = Vector2i(floori(x / 5.0), floori(z / 5.0))
				if occupied.has(cell_key):
					continue
				occupied[cell_key] = true
				var variant: int = rng.randi_range(0, 5)
				var position: Vector3 = Vector3(x, terrain.height_at(x, z), z)
				var chunk: Vector2i = Vector2i(chunk_x, chunk_z)
				var scale: float = rng.randf_range(0.82, 1.2)
				var tree_heights: Array[float] = [12.0, 15.8, 19.5, 8.8, 11.7, 14.5]
				foliage_definitions.append({
					"id": "tree_%05d" % tree_index,
					"type": "tree",
					"variant": variant,
					"position": position,
					"height": tree_heights[variant] * scale,
					"scale": scale,
					"yaw": rng.randf_range(0.0, TAU),
					"chunk": chunk
				})
				tree_index += 1
			for _sample: int in range(56):
				var bush_x: float = start_x + rng.randf_range(3.0, CHUNK_SIZE - 3.0)
				var bush_z: float = start_z + rng.randf_range(3.0, CHUNK_SIZE - 3.0)
				var bush_density: float = terrain.forest_density_at(bush_x, bush_z)
				if bush_density < 0.38 or rng.randf() > bush_density * 0.32:
					continue
				var bush_position: Vector3 = Vector3(bush_x, terrain.height_at(bush_x, bush_z), bush_z)
				foliage_definitions.append({
					"id": "bush_%05d" % bush_index,
					"type": "bush",
					"variant": rng.randi_range(0, 1),
					"position": bush_position,
					"scale": rng.randf_range(0.7, 1.25),
					"yaw": rng.randf_range(0.0, TAU),
					"chunk": Vector2i(chunk_x, chunk_z)
				})
				bush_index += 1
			for _sample: int in range(24):
				var rock_x: float = start_x + rng.randf_range(3.0, CHUNK_SIZE - 3.0)
				var rock_z: float = start_z + rng.randf_range(3.0, CHUNK_SIZE - 3.0)
				if Vector2(rock_x, rock_z).distance_to(Vector2(0.0, 38.0)) < 86.0 or rng.randf() > 0.28:
					continue
				var rock_position: Vector3 = Vector3(rock_x, terrain.height_at(rock_x, rock_z), rock_z)
				foliage_definitions.append({
					"id": "rock_%05d" % rock_index,
					"type": "rock",
					"variant": rng.randi_range(0, 1),
					"position": rock_position,
					"scale": rng.randf_range(0.38, 0.88),
					"yaw": rng.randf_range(0.0, TAU),
					"chunk": Vector2i(chunk_x, chunk_z)
				})
				rock_index += 1

func _build_tree_multimeshes() -> void:
	var groups: Dictionary = {}
	for definition: Dictionary in foliage_definitions:
		if definition["type"] != "tree" or state.is_removed(str(definition["id"])):
			continue
		var variant: int = int(definition["variant"])
		if not groups.has(variant):
			groups[variant] = {"trunks": [], "canopies": [], "indices": {}}
		var group: Dictionary = groups[variant]
		var position: Vector3 = definition["position"]
		var scale: float = float(definition["scale"])
		var yaw: float = float(definition["yaw"])
		var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
		var trunk_index: int = group["trunks"].size()
		group["trunks"].append(Transform3D(basis, position))
		var canopy_index: int = group["canopies"].size()
		group["canopies"].append(Transform3D(basis, position))
		group["indices"][str(definition["id"])] = {
			"trunk": trunk_index,
			"canopy": canopy_index
		}
		groups[variant] = group

	for variant: int in groups:
		var group: Dictionary = groups[variant]
		var model_name: String = "tree_conifer_%02d" % (variant + 1) if variant < 3 else "tree_broadleaf_%02d" % (variant - 2)
		var packed: PackedScene = load("res://assets/models/%s.glb" % model_name) as PackedScene
		var model: Node3D = packed.instantiate() as Node3D
		var trunk_source: MeshInstance3D = model.find_child("Trunk_Mesh", true, false) as MeshInstance3D
		var canopy_source: MeshInstance3D = model.find_child("Canopy_Mesh", true, false) as MeshInstance3D
		if trunk_source == null or canopy_source == null:
			model.queue_free()
			continue
		var trunk_local_transform: Transform3D = _relative_transform(model, trunk_source)
		var canopy_local_transform: Transform3D = _relative_transform(model, canopy_source)
		var trunk_transforms: Array[Transform3D] = []
		var canopy_transforms: Array[Transform3D] = []
		for transform: Transform3D in group["trunks"]:
			trunk_transforms.append(transform * trunk_local_transform)
		for transform: Transform3D in group["canopies"]:
			canopy_transforms.append(transform * canopy_local_transform)
		var bark: StandardMaterial3D = StandardMaterial3D.new()
		bark.albedo_color = Color("584331")
		bark.roughness = 0.94
		var leaves: ShaderMaterial = _wind_material(Color("3e6540"), 0.035, 680.0, 720.0)
		var trunk_multimesh: MultiMesh = _make_multimesh("TreeTrunks_%d" % variant,
			trunk_source.mesh, bark, trunk_transforms, 720.0)
		var canopy_multimesh: MultiMesh = _make_multimesh("TreeCanopies_%d" % variant,
			canopy_source.mesh, leaves, canopy_transforms, 720.0)
		for foliage_id: String in group["indices"]:
			var indices: Dictionary = group["indices"][foliage_id]
			var references: Array[Dictionary] = [
				{"multimesh": trunk_multimesh, "index": int(indices["trunk"])}
			]
			references.append({"multimesh": canopy_multimesh, "index": int(indices["canopy"])})
			instance_lookup[foliage_id] = references
		model.queue_free()
func _build_scatter_multimeshes() -> void:
	var groups: Dictionary = {}
	for definition: Dictionary in foliage_definitions:
		if definition["type"] == "tree" or state.is_removed(str(definition["id"])):
			continue
		var group_key: String = "%s_%d" % [definition["type"], int(definition["variant"])]
		if not groups.has(group_key):
			groups[group_key] = {"transforms": [], "indices": {}}
		var group: Dictionary = groups[group_key]
		var position: Vector3 = definition["position"]
		var scale: float = float(definition["scale"])
		var basis: Basis = Basis(Vector3.UP, float(definition["yaw"])).scaled(Vector3(scale, scale, scale))
		var instance_index: int = group["transforms"].size()
		var vertical_offset: float = 0.44 if definition["type"] == "bush" else 0.35 * scale
		group["transforms"].append(Transform3D(basis, position + Vector3(0.0, vertical_offset, 0.0)))
		group["indices"][str(definition["id"])] = instance_index
		groups[group_key] = group

	for group_key: String in groups:
		var group: Dictionary = groups[group_key]
		var pieces: PackedStringArray = group_key.split("_")
		var kind: String = pieces[0]
		var variant: int = int(pieces[1])
		var mesh: Mesh
		var material: Material
		if kind == "bush":
			var bush: SphereMesh = SphereMesh.new()
			bush.radius = 0.68 + float(variant) * 0.12
			bush.height = 0.92 + float(variant) * 0.14
			mesh = bush
			material = _wind_material(Color("384a2e") if variant == 0 else Color("536342"), 0.05)
		else:
			var rock: SphereMesh = SphereMesh.new()
			rock.radius = 0.72
			rock.height = 1.05
			rock.radial_segments = 8
			rock.rings = 5
			mesh = rock
			var rock_material: StandardMaterial3D = StandardMaterial3D.new()
			rock_material.albedo_color = Color("68655a") if variant == 0 else Color("82786a")
			rock_material.roughness = 0.95
			material = rock_material
		var multimesh: MultiMesh = _make_multimesh("Foliage_%s" % group_key, mesh, material, group["transforms"], 720.0)
		for foliage_id: String in group["indices"]:
			instance_lookup[foliage_id] = [{"multimesh": multimesh, "index": int(group["indices"][foliage_id])}]

func _make_multimesh(node_name: String, mesh: Mesh, material: Material, transforms: Array, visibility_end: float) -> MultiMesh:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.visibility_range_end = visibility_end
	instance.visibility_range_end_margin = 64.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(instance)
	return multimesh

func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var relative: Transform3D = Transform3D.IDENTITY
	var current: Node3D = node
	while current != root:
		relative = current.transform * relative
		current = current.get_parent() as Node3D
		if current == null:
			return Transform3D.IDENTITY
	return relative

func _add_trunk_collision(definition: Dictionary) -> void:
	var chunk: Vector2i = definition["chunk"]
	if not chunk_bodies.has(chunk):
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "TreeCollision_%d_%d" % [chunk.x, chunk.y]
		body.collision_layer = 2
		body.position = Vector3(-WORLD_HALF_EXTENT + float(chunk.x) * CHUNK_SIZE, 0.0,
			-WORLD_HALF_EXTENT + float(chunk.y) * CHUNK_SIZE)
		chunk_bodies[chunk] = body
		add_child(body)
	var body: StaticBody3D = chunk_bodies[chunk]
	var collision: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = maxf(2.0, minf(5.0, float(definition["height"]) * 0.45))
	collision.shape = capsule
	var position: Vector3 = definition["position"]
	collision.position = Vector3(position.x - body.position.x,
		position.y + capsule.height * 0.5, position.z - body.position.z)
	body.add_child(collision)
	tree_colliders[str(definition["id"])] = collision

func _update_tree_collisions(force: bool) -> void:
	if player == null:
		return
	var region: Vector2i = Vector2i(floori(player.global_position.x / 20.0),
		floori(player.global_position.z / 20.0))
	if not force and region == last_tree_collision_region:
		return
	last_tree_collision_region = region
	var player_position: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	var desired: Dictionary = {}
	for definition: Dictionary in foliage_definitions:
		if definition["type"] != "tree" or state.is_removed(str(definition["id"])):
			continue
		var position: Vector3 = definition["position"]
		if Vector2(position.x, position.z).distance_to(player_position) <= TREE_COLLISION_RADIUS:
			desired[str(definition["id"])] = definition
	for raw_id: Variant in tree_colliders.keys():
		var foliage_id: String = str(raw_id)
		if desired.has(foliage_id):
			continue
		var collision: CollisionShape3D = tree_colliders[foliage_id]
		var body: StaticBody3D = collision.get_parent() as StaticBody3D
		if body != null:
			body.remove_child(collision)
		collision.queue_free()
		tree_colliders.erase(foliage_id)
	for raw_id: Variant in desired:
		var foliage_id: String = str(raw_id)
		if not tree_colliders.has(foliage_id):
			_add_trunk_collision(desired[foliage_id])
	for raw_chunk: Variant in chunk_bodies.keys():
		var body: StaticBody3D = chunk_bodies[raw_chunk]
		if body.get_child_count() > 0:
			continue
		remove_child(body)
		body.queue_free()
		chunk_bodies.erase(raw_chunk)

func _hide_instance(foliage_id: String) -> void:
	if instance_lookup.has(foliage_id):
		for reference: Dictionary in instance_lookup[foliage_id]:
			var multimesh: MultiMesh = reference["multimesh"]
			var index: int = int(reference["index"])
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -10000.0, 0.0)))
	if tree_colliders.has(foliage_id):
		(tree_colliders[foliage_id] as CollisionShape3D).disabled = true

func _build_grass_mesh() -> void:
	for variant: int in range(3):
		var packed: PackedScene = load("res://assets/models/grass_clump_%02d.glb" % (variant + 1)) as PackedScene
		var model: Node3D = packed.instantiate() as Node3D
		var grass_source: MeshInstance3D = model.find_child("Grass_Clump", true, false) as MeshInstance3D
		var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
		instance.name = "NearGrass_%d" % variant
		instance.multimesh = MultiMesh.new()
		instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		instance.multimesh.mesh = grass_source.mesh
		instance.material_override = _wind_material(Color.WHITE, 0.12)
		instance.visibility_range_end = GRASS_RADIUS + 8.0
		instance.visibility_range_end_margin = 8.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(instance)
		grass_instances.append(instance)
		model.queue_free()

func _update_grass(force: bool) -> void:
	if player == null or grass_instances.size() != 3:
		return
	var region: Vector2i = Vector2i(floori(player.global_position.x / 20.0), floori(player.global_position.z / 20.0))
	if not force and region == last_grass_region:
		return
	last_grass_region = region
	var transforms_by_variant: Array = [[], [], []]
	var spacing: float = 1.7
	var min_cell_x: int = floori((player.global_position.x - GRASS_RADIUS) / spacing)
	var max_cell_x: int = floori((player.global_position.x + GRASS_RADIUS) / spacing)
	var min_cell_z: int = floori((player.global_position.z - GRASS_RADIUS) / spacing)
	var max_cell_z: int = floori((player.global_position.z + GRASS_RADIUS) / spacing)
	for cell_x: int in range(min_cell_x, max_cell_x + 1):
		for cell_z: int in range(min_cell_z, max_cell_z + 1):
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = absi((cell_x * 73856093) ^ (cell_z * 19349663) ^ 1357)
			var x: float = (float(cell_x) + rng.randf()) * spacing
			var z: float = (float(cell_z) + rng.randf()) * spacing
			if Vector2(x, z).distance_to(Vector2(player.global_position.x, player.global_position.z)) > GRASS_RADIUS:
				continue
			if absf(x) > WORLD_HALF_EXTENT - 8.0 or absf(z) > WORLD_HALF_EXTENT - 8.0:
				continue
			if Vector2(x, z).distance_to(terrain.LAKE_CENTER) < 78.0:
				continue
			var position: Vector3 = Vector3(x, terrain.height_at(x, z), z)
			var scale: float = rng.randf_range(0.72, 1.22)
			var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale, scale, scale))
			var variant: int = rng.randi_range(0, 2)
			transforms_by_variant[variant].append(Transform3D(basis, position))
	for variant: int in range(3):
		var transforms: Array = transforms_by_variant[variant]
		var multimesh: MultiMesh = grass_instances[variant].multimesh
		multimesh.instance_count = transforms.size()
		for index: int in range(transforms.size()):
			multimesh.set_instance_transform(index, transforms[index])

func _wind_material(tint: Color, strength: float, fade_start: float = 52.0, fade_end: float = 60.0) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/foliage_wind.gdshader") as Shader
	material.set_shader_parameter("foliage_tint", tint)
	material.set_shader_parameter("wind_strength", strength)
	material.set_shader_parameter("fade_start", fade_start)
	material.set_shader_parameter("fade_end", fade_end)
	return material
