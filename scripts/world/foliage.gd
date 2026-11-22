extends Node3D
class_name FactoryFoliage

const WORLD_HALF_EXTENT: float = 512.0
const CHUNK_SIZE: float = 128.0
const TREES_PER_CHUNK: int = 132
const GRASS_RADIUS: float = 60.0

var terrain: FactoryTerrain
var player: FactoryPlayer
var state: FoliageState = FoliageState.new()
var foliage_definitions: Array[Dictionary] = []
var instance_lookup: Dictionary = {}
var tree_colliders: Dictionary = {}
var chunk_bodies: Dictionary = {}
var grass_instance: MultiMeshInstance3D
var grass_mesh: ArrayMesh
var last_grass_region: Vector2i = Vector2i(999999, 999999)

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

func _process(_delta: float) -> void:
	if DisplayServer.get_name() != "headless":
		_update_grass(false)

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
				var variant: int = rng.randi_range(0, 4)
				var position: Vector3 = Vector3(x, terrain.height_at(x, z), z)
				var chunk: Vector2i = Vector2i(chunk_x, chunk_z)
				foliage_definitions.append({
					"id": "tree_%05d" % tree_index,
					"type": "tree",
					"variant": variant,
					"position": position,
					"height": rng.randf_range(5.4, 7.4),
					"scale": rng.randf_range(0.82, 1.2),
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
		var height: float = float(definition["height"])
		var scale: float = float(definition["scale"])
		var yaw: float = float(definition["yaw"])
		var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(scale, height / 5.4, scale))
		var trunk_index: int = group["trunks"].size()
		group["trunks"].append(Transform3D(basis, position + Vector3(0.0, height * 0.5, 0.0)))
		var canopy_count: int = 2 if variant < 3 else 1
		var canopy_index: int = group["canopies"].size()
		if variant < 3:
			group["canopies"].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(scale, 0.78 * scale, scale)),
				position + Vector3(0.0, height * 0.62, 0.0)))
			group["canopies"].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(scale * 0.72, 0.66 * scale, scale * 0.72)),
				position + Vector3(0.0, height * 0.86, 0.0)))
		else:
			group["canopies"].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale)),
				position + Vector3(0.0, height * 0.79, 0.0)))
		group["indices"][str(definition["id"])] = {
			"trunk": trunk_index,
			"canopy": canopy_index,
			"canopy_count": canopy_count
		}
		groups[variant] = group

	for variant: int in groups:
		var group: Dictionary = groups[variant]
		var trunk_mesh: CylinderMesh = CylinderMesh.new()
		trunk_mesh.top_radius = 0.17
		trunk_mesh.bottom_radius = 0.29
		trunk_mesh.height = 5.4
		trunk_mesh.radial_segments = 8
		var bark: StandardMaterial3D = StandardMaterial3D.new()
		bark.albedo_color = Color("514338")
		bark.roughness = 0.94
		var trunk_multimesh: MultiMesh = _make_multimesh("TreeTrunks_%d" % variant, trunk_mesh, bark, group["trunks"], 720.0)
		var canopy_mesh: Mesh
		if variant < 3:
			var cone: ConeMesh = ConeMesh.new()
			cone.bottom_radius = 1.7 + float(variant) * 0.12
			cone.height = 4.1 + float(variant) * 0.25
			cone.radial_segments = 7
			canopy_mesh = cone
		else:
			var crown: SphereMesh = SphereMesh.new()
			crown.radius = 1.55 + float(variant - 3) * 0.22
			crown.height = 2.8 + float(variant - 3) * 0.2
			crown.radial_segments = 9
			crown.rings = 6
			canopy_mesh = crown
		var leaf_color: Color = [Color("253d2b"), Color("304633"), Color("3b4b35"), Color("4c6242"), Color("566946")][variant]
		var leaves: ShaderMaterial = _wind_material(leaf_color, 0.08)
		var canopy_multimesh: MultiMesh = _make_multimesh("TreeCanopies_%d" % variant, canopy_mesh, leaves, group["canopies"], 720.0)
		for foliage_id: String in group["indices"]:
			var indices: Dictionary = group["indices"][foliage_id]
			var references: Array[Dictionary] = [
				{"multimesh": trunk_multimesh, "index": int(indices["trunk"])}
			]
			for canopy_index: int in range(int(indices["canopy_count"])):
				references.append({"multimesh": canopy_multimesh, "index": int(indices["canopy"]) + canopy_index})
			instance_lookup[foliage_id] = references
	for definition: Dictionary in foliage_definitions:
		if definition["type"] == "tree" and not state.is_removed(str(definition["id"])):
			_add_trunk_collision(definition)

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

func _add_trunk_collision(definition: Dictionary) -> void:
	var chunk: Vector2i = definition["chunk"]
	if not chunk_bodies.has(chunk):
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "TreeCollision_%d_%d" % [chunk.x, chunk.y]
		body.position = Vector3(-WORLD_HALF_EXTENT + float(chunk.x) * CHUNK_SIZE, 0.0,
			-WORLD_HALF_EXTENT + float(chunk.y) * CHUNK_SIZE)
		chunk_bodies[chunk] = body
		add_child(body)
	var body: StaticBody3D = chunk_bodies[chunk]
	var collision: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 4.8
	collision.shape = capsule
	var position: Vector3 = definition["position"]
	collision.position = Vector3(position.x - body.position.x, position.y + 2.3, position.z - body.position.z)
	body.add_child(collision)
	tree_colliders[str(definition["id"])] = collision

func _hide_instance(foliage_id: String) -> void:
	if instance_lookup.has(foliage_id):
		for reference: Dictionary in instance_lookup[foliage_id]:
			var multimesh: MultiMesh = reference["multimesh"]
			var index: int = int(reference["index"])
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -10000.0, 0.0)))
	if tree_colliders.has(foliage_id):
		(tree_colliders[foliage_id] as CollisionShape3D).disabled = true

func _build_grass_mesh() -> void:
	var vertices: PackedVector3Array = PackedVector3Array([
		Vector3(-0.18, 0.0, 0.0), Vector3(0.18, 0.0, 0.0), Vector3(0.08, 0.92, 0.0), Vector3(-0.08, 0.92, 0.0),
		Vector3(0.0, 0.0, -0.18), Vector3(0.0, 0.0, 0.18), Vector3(0.0, 0.92, 0.08), Vector3(0.0, 0.92, -0.08)
	])
	var normals: PackedVector3Array = PackedVector3Array([
		Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)
	])
	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)
	])
	var indices: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	grass_mesh = ArrayMesh.new()
	grass_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	grass_instance = MultiMeshInstance3D.new()
	grass_instance.name = "NearGrass"
	grass_instance.multimesh = MultiMesh.new()
	grass_instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	grass_instance.multimesh.mesh = grass_mesh
	grass_instance.material_override = _wind_material(Color("758b43"), 0.22)
	grass_instance.visibility_range_end = GRASS_RADIUS + 8.0
	grass_instance.visibility_range_end_margin = 8.0
	grass_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(grass_instance)

func _update_grass(force: bool) -> void:
	if player == null or grass_instance == null:
		return
	var region: Vector2i = Vector2i(floori(player.global_position.x / 20.0), floori(player.global_position.z / 20.0))
	if not force and region == last_grass_region:
		return
	last_grass_region = region
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(region.x * 73856093) ^ int(region.y * 19349663) ^ 1357
	var transforms: Array[Transform3D] = []
	for _index: int in range(4800):
		var angle: float = rng.randf_range(0.0, TAU)
		var radius: float = sqrt(rng.randf()) * GRASS_RADIUS
		var x: float = player.global_position.x + cos(angle) * radius
		var z: float = player.global_position.z + sin(angle) * radius
		if absf(x) > WORLD_HALF_EXTENT - 8.0 or absf(z) > WORLD_HALF_EXTENT - 8.0:
			continue
		if Vector2(x, z).distance_to(terrain.LAKE_CENTER) < 78.0:
			continue
		var position: Vector3 = Vector3(x, terrain.height_at(x, z), z)
		var scale: float = rng.randf_range(0.55, 1.3)
		var basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale, scale, scale))
		transforms.append(Transform3D(basis, position))
	grass_instance.multimesh.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		grass_instance.multimesh.set_instance_transform(index, transforms[index])

func _wind_material(tint: Color, strength: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/foliage_wind.gdshader") as Shader
	material.set_shader_parameter("foliage_tint", tint)
	material.set_shader_parameter("wind_strength", strength)
	return material
