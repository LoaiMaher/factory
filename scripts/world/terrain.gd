extends Node3D
class_name FactoryTerrain

const WORLD_HALF_EXTENT: float = 512.0
const WORLD_CELLS: int = 512
const CHUNKS_PER_AXIS: int = 8
const CELLS_PER_CHUNK: int = 64
const CHUNK_SIZE: float = 128.0
const BACKDROP_HALF_EXTENT: float = 1536.0
const BACKDROP_STEP: float = 32.0
const LAKE_CENTER: Vector2 = Vector2(-205.0, 190.0)

var noise: FastNoiseLite = FastNoiseLite.new()
var warp_noise: FastNoiseLite = FastNoiseLite.new()
var detail_noise: FastNoiseLite = FastNoiseLite.new()
var ridge_noise: FastNoiseLite = FastNoiseLite.new()
var height_samples: PackedFloat32Array = PackedFloat32Array()
var nodes: Array[Dictionary] = []
var vents: Array[Vector3] = []
var resource_sites: Array[Vector2] = []
var boulder_definitions: Array[Dictionary] = []
var boulder_nodes: Dictionary = {}
var boulder_meshes: Dictionary = {}
var boulder_materials: Dictionary = {}
var ore_boulders: OreBoulders = OreBoulders.new()
var hidden_iron: Vector3 = Vector3(260.0, 0.0, -40.0)
var spire_position: Vector3 = Vector3(0.0, 0.0, -28.0)
var landing_position: Vector3 = Vector3(0.0, 0.0, 12.0)
var building_definitions: Dictionary = BuildingDefs.all()
var terrain_material: ShaderMaterial
var machine_models: MachineModels = MachineModels.new()
var world_environment: WorldEnvironment
var environment: Environment
var sun: DirectionalLight3D

func _ready() -> void:
	_configure_noise()
	_build_ground()
	if DisplayServer.get_name() != "headless":
		_create_environment()
	_build_boundaries()
	_build_backdrop()
	_build_lake()
	_build_nodes()
	_build_boulders()
	_build_vents()
	_build_landing_site()

func _configure_noise() -> void:
	noise.seed = 8142
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.0042
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.05
	noise.fractal_gain = 0.48
	warp_noise.seed = 26017
	warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	warp_noise.frequency = 0.0021
	warp_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	warp_noise.fractal_octaves = 3
	detail_noise.seed = 4771
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.021
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 2
	ridge_noise.seed = 90191
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge_noise.frequency = 0.006
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	ridge_noise.fractal_octaves = 4
	ridge_noise.fractal_lacunarity = 2.15
	ridge_noise.fractal_gain = 0.52

func height_at(x: float, z: float) -> float:
	var radius: float = Vector2(x, z).length()
	var warp_x: float = warp_noise.get_noise_2d(x, z) * 38.0
	var warp_z: float = warp_noise.get_noise_2d(x + 127.0, z - 311.0) * 38.0
	var nx: float = x + warp_x
	var nz: float = z + warp_z
	var outer_factor: float = _smoothstep(120.0, 270.0, radius)
	var broad_noise: float = noise.get_noise_2d(nx, nz) * lerpf(0.65, 10.5, outer_factor)
	var detail: float = detail_noise.get_noise_2d(nx, nz) * lerpf(0.18, 2.3, outer_factor)
	var valley_rise: float = maxf(0.0, radius - 140.0) * 0.047
	var ridge_center: float = 176.0 + sin(z * 0.0031) * 20.0 + warp_noise.get_noise_2d(300.0, z) * 15.0
	var ridge_distance: float = absf(x - ridge_center)
	var ridge_envelope: float = exp(-pow(ridge_distance / 52.0, 2.0))
	var ridge_detail: float = 1.0 - absf(ridge_noise.get_noise_2d(nx * 0.83, nz * 0.83))
	var east_ridge: float = ridge_envelope * (62.0 + ridge_detail * 56.0 + noise.get_noise_2d(x + 791.0, z - 83.0) * 13.0)
	var boundary_distance: float = maxf(absf(x), absf(z))
	var boundary_factor: float = _smoothstep(348.0, WORLD_HALF_EXTENT, boundary_distance)
	var boundary_ridge: float = boundary_factor * (150.0 + ridge_detail * 64.0 + noise.get_noise_2d(nx + 2090.0, nz - 1400.0) * 14.0)
	var canyon_line: float = -302.0 + sin(x * 0.004) * 20.0
	var canyon_distance: float = absf(z - canyon_line)
	var canyon_region: float = _smoothstep(90.0, 200.0, absf(x))
	var canyon_cut: float = exp(-pow(canyon_distance / 27.0, 2.0)) * canyon_region * 19.0
	var canyon_rim: float = exp(-pow((canyon_distance - 39.0) / 18.0, 2.0)) * canyon_region * 13.0
	var lake_distance: float = Vector2(x, z).distance_to(LAKE_CENTER)
	var lake_basin: float = exp(-pow(lake_distance / 112.0, 2.0)) * 25.0
	return valley_rise + broad_noise + detail + east_ridge + boundary_ridge - canyon_cut + canyon_rim - lake_basin

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

func is_in_lake(position: Vector3) -> bool:
	return Vector2(position.x, position.z).distance_to(LAKE_CENTER) < 92.0

func is_boulder_in_footprint(position: Vector3, yaw: float, size: Vector3) -> bool:
	var inverse: Basis = Basis(Vector3.UP, -yaw)
	for definition: Dictionary in boulder_definitions:
		var delta: Vector3 = inverse * (definition["position"] - position)
		if absf(delta.x) < size.x * 0.5 + 0.7 and absf(delta.z) < size.z * 0.5 + 0.7:
			return true
	return false

func is_buildable(cell: Vector2i, building_id: String, rotation: int = 0) -> bool:
	var size: Vector2i = _building_size(building_id, rotation)
	if float(cell.x * 2) < -WORLD_HALF_EXTENT or float((cell.x + size.x) * 2) > WORLD_HALF_EXTENT:
		return false
	if float(cell.y * 2) < -WORLD_HALF_EXTENT or float((cell.y + size.y) * 2) > WORLD_HALF_EXTENT:
		return false
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

func forest_density_at(x: float, z: float) -> float:
	var radius: float = Vector2(x, z).length()
	var outward: float = _smoothstep(95.0, 240.0, radius)
	var wooded_slope: float = maxf(_smoothstep(95.0, 260.0, absf(x)), _smoothstep(120.0, 290.0, z))
	var variation: float = noise.get_noise_2d(x + 720.0, z - 510.0) * 0.24 + 0.7
	return clampf(maxf(outward * 0.5, wooded_slope) * variation, 0.0, 0.92)

func mine_boulder(boulder_id: String) -> Dictionary:
	var result: Dictionary = ore_boulders.mine(boulder_id)
	if result.is_empty():
		return {}
	_update_boulder_visual(boulder_id)
	return result

func restore_boulders(data: Dictionary) -> void:
	ore_boulders.from_dict(data)
	for boulder_id: String in ore_boulders.deposits:
		_update_boulder_visual(boulder_id)

func _building_size(building_id: String, rotation: int = 0) -> Vector2i:
	var size: Vector2i = building_definitions.get(building_id, {}).get("size", Vector2i.ONE)
	return size if posmod(rotation, 2) == 0 else Vector2i(size.y, size.x)

func _build_ground() -> void:
	var vertex_count: int = WORLD_CELLS + 1
	height_samples.resize(vertex_count * vertex_count)
	for z_index: int in range(vertex_count):
		for x_index: int in range(vertex_count):
			var x: float = -WORLD_HALF_EXTENT + float(x_index) * 2.0
			var z: float = -WORLD_HALF_EXTENT + float(z_index) * 2.0
			height_samples[z_index * vertex_count + x_index] = height_at(x, z)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	var shape: CollisionShape3D = CollisionShape3D.new()
	var heightmap: HeightMapShape3D = HeightMapShape3D.new()
	heightmap.map_width = vertex_count
	heightmap.map_depth = vertex_count
	heightmap.map_data = height_samples
	shape.shape = heightmap
	shape.scale = Vector3(2.0, 1.0, 2.0)
	body.add_child(shape)
	add_child(body)
	if DisplayServer.get_name() == "headless":
		return
	terrain_material = _create_terrain_material()
	for chunk_z: int in range(CHUNKS_PER_AXIS):
		for chunk_x: int in range(CHUNKS_PER_AXIS):
			_build_terrain_chunk(chunk_x, chunk_z)

func _build_terrain_chunk(chunk_x: int, chunk_z: int) -> void:
	var verts_per_side: int = CELLS_PER_CHUNK + 1
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var start_x: float = -WORLD_HALF_EXTENT + float(chunk_x) * CHUNK_SIZE
	var start_z: float = -WORLD_HALF_EXTENT + float(chunk_z) * CHUNK_SIZE
	var base_x_index: int = chunk_x * CELLS_PER_CHUNK
	var base_z_index: int = chunk_z * CELLS_PER_CHUNK
	for local_z: int in range(verts_per_side):
		for local_x: int in range(verts_per_side):
			var grid_x: int = base_x_index + local_x
			var grid_z: int = base_z_index + local_z
			var x: float = -WORLD_HALF_EXTENT + float(grid_x) * 2.0
			var z: float = -WORLD_HALF_EXTENT + float(grid_z) * 2.0
			var y: float = height_samples[grid_z * (WORLD_CELLS + 1) + grid_x]
			var normal: Vector3 = _terrain_normal(grid_x, grid_z)
			vertices.append(Vector3(float(local_x) * 2.0, y, float(local_z) * 2.0))
			normals.append(normal)
			uvs.append(Vector2(x, z))
			colors.append(_terrain_masks(x, z, y, normal))
	for local_z: int in range(CELLS_PER_CHUNK):
		for local_x: int in range(CELLS_PER_CHUNK):
			var p00: int = local_z * verts_per_side + local_x
			var p10: int = p00 + 1
			var p01: int = p00 + verts_per_side
			var p11: int = p01 + 1
			indices.append_array(PackedInt32Array([p00, p01, p10, p10, p01, p11]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, terrain_material)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "TerrainChunk_%d_%d" % [chunk_x, chunk_z]
	instance.mesh = mesh
	instance.position = Vector3(start_x, 0.0, start_z)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)

func _terrain_normal(x_index: int, z_index: int) -> Vector3:
	var max_index: int = WORLD_CELLS
	var left: int = maxi(0, x_index - 1)
	var right: int = mini(max_index, x_index + 1)
	var north: int = maxi(0, z_index - 1)
	var south: int = mini(max_index, z_index + 1)
	var dx: float = float(right - left) * 2.0
	var dz: float = float(south - north) * 2.0
	var left_height: float = height_samples[z_index * (max_index + 1) + left]
	var right_height: float = height_samples[z_index * (max_index + 1) + right]
	var north_height: float = height_samples[north * (max_index + 1) + x_index]
	var south_height: float = height_samples[south * (max_index + 1) + x_index]
	return Vector3(-(right_height - left_height) / dx, 1.0, -(south_height - north_height) / dz).normalized()

func world_surface_normal_at(x: float, z: float) -> Vector3:
	var slope_x: float = (height_at(x + 1.0, z) - height_at(x - 1.0, z)) * 0.5
	var slope_z: float = (height_at(x, z + 1.0) - height_at(x, z - 1.0)) * 0.5
	return Vector3(-slope_x, 1.0, -slope_z).normalized()

func _terrain_masks(x: float, z: float, height: float, normal: Vector3) -> Color:
	var radius: float = Vector2(x, z).length()
	var lake_distance: float = Vector2(x, z).distance_to(LAKE_CENTER)
	var beach: float = clampf(1.0 - absf(lake_distance - 93.0) / 37.0, 0.0, 1.0)
	var forest: float = forest_density_at(x, z)
	var ridge_center: float = 176.0 + sin(z * 0.0031) * 20.0
	var ridge_weight: float = exp(-pow(absf(x - ridge_center) / 74.0, 2.0))
	var slope: float = 1.0 - normal.y
	var rock: float = clampf(slope * 2.2 + ridge_weight * _smoothstep(28.0, 70.0, height) + _smoothstep(105.0, 190.0, height) * 0.7, 0.0, 1.0)
	var sand: float = clampf(beach * 0.9 + (1.0 - _smoothstep(110.0, 170.0, height)) * beach * 0.25, 0.0, 1.0)
	if radius < 140.0:
		forest *= 0.25
	var variation: float = noise.get_noise_2d(x + 173.0, z - 87.0) * 0.5 + 0.5
	return Color(forest, sand, rock, variation)

func _create_terrain_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader_path: String = "res://shaders/terrain.gdshader"
	if not _uses_forward_plus():
		shader_path = "res://shaders/terrain_compat.gdshader"
	var shader: Shader = load(shader_path) as Shader
	if shader != null:
		material.shader = shader
		material.set_shader_parameter("grass_albedo", load("res://assets/textures/grass_ground_diff_1k.jpg"))
		material.set_shader_parameter("grass_normal", load("res://assets/textures/grass_ground_nor_gl_1k.jpg"))
		material.set_shader_parameter("grass_roughness", load("res://assets/textures/grass_ground_rough_1k.jpg"))
		material.set_shader_parameter("forest_albedo", load("res://assets/textures/forest_ground_04_diff_1k.jpg"))
		material.set_shader_parameter("forest_normal", load("res://assets/textures/forest_ground_04_nor_gl_1k.jpg"))
		material.set_shader_parameter("forest_roughness", load("res://assets/textures/forest_ground_04_rough_1k.jpg"))
		material.set_shader_parameter("rock_albedo", load("res://assets/textures/rocky_terrain_02_diff_1k.jpg"))
		material.set_shader_parameter("rock_normal", load("res://assets/textures/rocky_terrain_02_nor_gl_1k.jpg"))
		material.set_shader_parameter("rock_roughness", load("res://assets/textures/rocky_terrain_02_rough_1k.jpg"))
		material.set_shader_parameter("sand_albedo", load("res://assets/textures/sand_01_diff_1k.jpg"))
		material.set_shader_parameter("sand_normal", load("res://assets/textures/sand_01_nor_gl_1k.jpg"))
		material.set_shader_parameter("sand_roughness", load("res://assets/textures/sand_01_rough_1k.jpg"))
	return material

func _uses_forward_plus() -> bool:
	return RenderingServer.get_rendering_device() != null

func _build_boundaries() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "WorldBoundary"
	body.collision_layer = 1
	for wall_data: Dictionary in [
		{"size": Vector3(1024.0, 600.0, 8.0), "position": Vector3(0.0, 250.0, -WORLD_HALF_EXTENT)},
		{"size": Vector3(1024.0, 600.0, 8.0), "position": Vector3(0.0, 250.0, WORLD_HALF_EXTENT)},
		{"size": Vector3(8.0, 600.0, 1024.0), "position": Vector3(-WORLD_HALF_EXTENT, 250.0, 0.0)},
		{"size": Vector3(8.0, 600.0, 1024.0), "position": Vector3(WORLD_HALF_EXTENT, 250.0, 0.0)}
	]:
		var collision: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = wall_data["size"]
		collision.shape = box
		collision.position = wall_data["position"]
		body.add_child(collision)
	add_child(body)

func _build_backdrop() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var divisions: int = int(BACKDROP_HALF_EXTENT * 2.0 / BACKDROP_STEP)
	var vertex_count: int = divisions + 1
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	for z_index: int in range(vertex_count):
		for x_index: int in range(vertex_count):
			var x: float = -BACKDROP_HALF_EXTENT + float(x_index) * BACKDROP_STEP
			var z: float = -BACKDROP_HALF_EXTENT + float(z_index) * BACKDROP_STEP
			var y: float = _backdrop_height(x, z)
			var sample_step: float = BACKDROP_STEP * 0.5
			var dx: float = (_backdrop_height(x + sample_step, z) - _backdrop_height(x - sample_step, z)) / (sample_step * 2.0)
			var dz: float = (_backdrop_height(x, z + sample_step) - _backdrop_height(x, z - sample_step)) / (sample_step * 2.0)
			vertices.append(Vector3(x, y, z))
			normals.append(Vector3(-dx, 1.0, -dz).normalized())
			uvs.append(Vector2(x, z))
			colors.append(Color(0.2, 0.0, 1.0, noise.get_noise_2d(x, z) * 0.5 + 0.5))
	for z_index: int in range(divisions):
		for x_index: int in range(divisions):
			var x0: float = -BACKDROP_HALF_EXTENT + float(x_index) * BACKDROP_STEP
			var x1: float = x0 + BACKDROP_STEP
			var z0: float = -BACKDROP_HALF_EXTENT + float(z_index) * BACKDROP_STEP
			var z1: float = z0 + BACKDROP_STEP
			if x0 >= -WORLD_HALF_EXTENT and x1 <= WORLD_HALF_EXTENT and z0 >= -WORLD_HALF_EXTENT and z1 <= WORLD_HALF_EXTENT:
				continue
			var p00: int = z_index * vertex_count + x_index
			var p10: int = p00 + 1
			var p01: int = p00 + vertex_count
			var p11: int = p01 + 1
			indices.append_array(PackedInt32Array([p00, p01, p10, p10, p01, p11]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, terrain_material)
	var backdrop: MeshInstance3D = MeshInstance3D.new()
	backdrop.name = "MountainBackdrop"
	backdrop.mesh = mesh
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backdrop)

func _backdrop_height(x: float, z: float) -> float:
	var ridge: float = 1.0 - absf(ridge_noise.get_noise_2d(x * 0.7 + 812.0, z * 0.7 - 623.0))
	var distance: float = Vector2(x, z).length()
	var far_rise: float = maxf(0.0, distance - 570.0) * 0.045
	var peaks: float = ridge * (42.0 + _smoothstep(480.0, 1300.0, distance) * 46.0)
	return height_at(x, z) + 25.0 + far_rise + peaks

func _build_lake() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var lake: MeshInstance3D = MeshInstance3D.new()
	lake.name = "Lake"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(190.0, 150.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	lake.mesh = plane
	lake.position = Vector3(LAKE_CENTER.x, height_at(LAKE_CENTER.x, LAKE_CENTER.y) + 7.0, LAKE_CENTER.y)
	var water_material: ShaderMaterial = ShaderMaterial.new()
	var water_shader_path: String = "res://shaders/water.gdshader"
	if _uses_forward_plus():
		water_shader_path = "res://shaders/water_forward_plus.gdshader"
	var water_shader: Shader = load(water_shader_path) as Shader
	if water_shader != null:
		water_material.shader = water_shader
		water_material.set_shader_parameter("water_color", Color("3f626a"))
		water_material.set_shader_parameter("deep_color", Color("183740"))
		water_material.set_shader_parameter("wave_normal", load("res://assets/textures/sand_01_nor_gl_1k.jpg"))
	lake.material_override = water_material
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)

func _create_environment() -> void:
	world_environment = WorldEnvironment.new()
	environment = Environment.new()
	var use_forward_plus: bool = _uses_forward_plus()
	environment.background_mode = Environment.BG_SKY
	var sky_material: PanoramaSkyMaterial = PanoramaSkyMaterial.new()
	sky_material.panorama = load("res://assets/hdris/kloppenheim_06_puresky_2k.hdr")
	var sky_resource: Sky = Sky.new()
	sky_resource.sky_material = sky_material
	environment.sky = sky_resource
	environment.background_energy_multiplier = 0.76
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if use_forward_plus else Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a8b9af")
	environment.ambient_light_energy = 1.45
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05
	environment.fog_enabled = true
	environment.fog_light_color = Color("b7c8d2")
	environment.fog_sky_affect = 0.42
	environment.fog_density = 0.0001
	environment.ssao_enabled = use_forward_plus
	environment.ssao_radius = 1.6
	environment.ssao_intensity = 1.15
	environment.ssil_enabled = use_forward_plus
	environment.ssil_radius = 3.8
	environment.ssil_intensity = 0.55
	environment.sdfgi_enabled = false
	environment.glow_enabled = use_forward_plus
	environment.glow_intensity = 0.32
	environment.glow_bloom = 0.05
	environment.volumetric_fog_enabled = use_forward_plus
	environment.volumetric_fog_density = 0.00038
	environment.volumetric_fog_albedo = Color("a7bbc3")
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "LateMorningSun"
	sun.rotation_degrees = Vector3(-38.0, -34.0, 0.0)
	sun.light_color = Color("ffe2c4")
	sun.light_energy = 1.12
	sun.shadow_enabled = use_forward_plus
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 450.0
	sun.light_angular_distance = 0.6
	add_child(sun)

func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t: float = clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

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
		{"position": Vector3(235.0, 95.0, 120.0), "item": "iron_ore", "purity": "pure", "rate": 120.0},
		{"position": Vector3(325.0, 0.0, -245.0), "item": "iron_ore", "purity": "pure", "rate": 120.0},
		{"position": Vector3(-342.0, 0.0, -118.0), "item": "iron_ore", "purity": "pure", "rate": 120.0},
		{"position": Vector3(-275.0, 0.0, 300.0), "item": "iron_ore", "purity": "pure", "rate": 120.0},
		{"position": Vector3(118.0, 0.0, 322.0), "item": "copper_ore", "purity": "normal", "rate": 60.0},
		{"position": Vector3(-350.0, 0.0, 15.0), "item": "copper_ore", "purity": "pure", "rate": 120.0},
		{"position": Vector3(318.0, 0.0, 260.0), "item": "copper_ore", "purity": "pure", "rate": 120.0},
		{"position": Vector3(-205.0, 0.0, -335.0), "item": "copper_ore", "purity": "normal", "rate": 60.0},
		{"position": Vector3(15.0, 0.0, 340.0), "item": "limestone", "purity": "normal", "rate": 60.0},
		{"position": Vector3(-330.0, 0.0, 265.0), "item": "limestone", "purity": "pure", "rate": 120.0},
		{"position": Vector3(368.0, 0.0, -70.0), "item": "limestone", "purity": "normal", "rate": 60.0},
		{"position": Vector3(260.0, 0.0, -40.0), "item": "iron_ore", "purity": "pure", "rate": 120.0, "hidden": true}
	]
	for definition: Dictionary in definitions:
		var point: Vector3 = definition["position"]
		point.y = height_at(point.x, point.z)
		definition["position"] = point
		resource_sites.append(Vector2(point.x, point.z))
		if bool(definition.get("hidden", false)):
			hidden_iron = point
		definition["id"] = nodes.size()
		nodes.append(definition)
		if not bool(definition.get("hidden", false)):
			_make_node_visual(definition)

func _make_node_visual(definition: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var point: Vector3 = definition["position"]
	var root: Node3D = Node3D.new()
	root.position = point
	root.name = "%s_%s" % [definition["item"], definition["purity"]]
	root.set_meta("resource_node", definition)
	var packed: PackedScene = load("res://assets/models/ore_node.glb") as PackedScene
	if packed == null:
		push_error("Missing Blender model: ore_node")
		return
	var model: Node3D = packed.instantiate() as Node3D
	model.name = "OreNodeModel"
	root.add_child(model)
	var purity: String = str(definition["purity"])
	var variant_name: String = "OreNode_A" if purity == "impure" else "OreNode_C" if purity == "pure" else ["OreNode_A", "OreNode_B", "OreNode_C"][int(definition["id"]) % 3]
	var active_part: Node3D = null
	for variant: String in ["OreNode_A", "OreNode_B", "OreNode_C"]:
		var part: Node3D = model.find_child(variant, true, false) as Node3D
		if part == null:
			push_error("Ore node model missing variant: " + variant)
			continue
		part.visible = variant == variant_name
		if not part.visible:
			continue
		active_part = part
		var purity_scale: float = 0.8 if purity == "impure" else 1.2 if purity == "pure" else 1.0
		part.scale = Vector3.ONE * purity_scale
		for mesh_node: Node in part.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = mesh_node as MeshInstance3D
			var ore_material: ShaderMaterial = ShaderMaterial.new()
			ore_material.shader = load("res://shaders/resource_node.gdshader") as Shader
			var item: String = str(definition["item"])
			ore_material.set_shader_parameter("ore_tint", _ore_tint(item))
			ore_material.set_shader_parameter("patina_tint", Color("358876"))
			ore_material.set_shader_parameter("patina_strength", 0.55 if item == "copper_ore" else 0.0)
			ore_material.set_shader_parameter("vein_glow", 0.18 if purity == "pure" else 0.0)
			mesh.material_override = ore_material
	var normal: Vector3 = world_surface_normal_at(point.x, point.z)
	root.basis = Basis(Quaternion(Vector3.UP, normal))
	var collision_body: StaticBody3D = StaticBody3D.new()
	collision_body.collision_layer = 2
	var collision_faces: PackedVector3Array = PackedVector3Array()
	for mesh_node: Node in active_part.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var mesh_transform: Transform3D = mesh_instance.transform
		var ancestor: Node = mesh_instance.get_parent()
		while ancestor != null and ancestor != root:
			mesh_transform = (ancestor as Node3D).transform * mesh_transform
			ancestor = ancestor.get_parent()
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for vertex: Vector3 in vertices:
					collision_faces.append(mesh_transform * vertex)
			else:
				for triangle_index: int in range(0, indices.size(), 3):
					for vertex_index: int in range(3):
						collision_faces.append(mesh_transform * vertices[indices[triangle_index + vertex_index]])
	if not collision_faces.is_empty():
		var collision_shape: CollisionShape3D = CollisionShape3D.new()
		var slab_shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
		slab_shape.set_faces(collision_faces)
		collision_shape.shape = slab_shape
		collision_body.add_child(collision_shape)
	root.add_child(collision_body)
	var label: Label3D = Label3D.new()
	label.text = "%s · %s" % [Items.item_name(str(definition["item"])).replace(" Ore", ""), str(definition["purity"]).capitalize()]
	label.position = Vector3(0.0, 1.85, 0.0)
	label.font_size = 30
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.outline_size = 5
	label.outline_modulate = Color("202520")
	label.visibility_range_end = 12.0
	label.visibility_range_end_margin = 3.0
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(label)
	add_child(root)

func _ore_tint(item: String) -> Color:
	match item:
		"iron_ore":
			return Color("9b5945")
		"copper_ore":
			return Color("b87333")
		"limestone":
			return Color("c6bea5")
		"caterium_ore":
			return Color("d8bb4b")
		_:
			return Color("b89445")

func _build_boulders() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 70217
	for resource: Dictionary in [
		{"item": "iron_ore", "count": 15, "prefix": "near_iron"},
		{"item": "copper_ore", "count": 10, "prefix": "near_copper"},
		{"item": "limestone", "count": 10, "prefix": "near_limestone"}
	]:
		for index: int in range(int(resource["count"])):
			var point: Vector3 = _nearby_boulder_position(rng)
			var boulder_id: String = "%s_%02d" % [resource["prefix"], index]
			_add_boulder(boulder_id, str(resource["item"]), rng.randi_range(8, 20), point)
	for index: int in range(125):
		var point: Vector3 = Vector3.ZERO
		var attempts: int = 0
		while attempts < 80:
			attempts += 1
			point.x = rng.randf_range(-482.0, 482.0)
			point.z = rng.randf_range(-482.0, 482.0)
			if Vector2(point.x, point.z).distance_to(LAKE_CENTER) < 125.0:
				continue
			if Vector2(point.x, point.z).distance_to(Vector2(0.0, 38.0)) < 105.0:
				continue
			break
		var item_id: String = ["iron_ore", "copper_ore", "limestone"][rng.randi_range(0, 2)]
		point.y = height_at(point.x, point.z)
		_add_boulder("world_%03d" % index, item_id, rng.randi_range(8, 20), point)

func _nearby_boulder_position(rng: RandomNumberGenerator) -> Vector3:
	var point: Vector3 = Vector3.ZERO
	for attempt: int in range(80):
		var angle: float = rng.randf_range(0.0, TAU)
		var radius: float = rng.randf_range(24.0, 78.0)
		point.x = cos(angle) * radius
		point.z = 38.0 + sin(angle) * radius
		var overlaps_node: bool = false
		for node: Dictionary in nodes:
			if Vector2(point.x, point.z).distance_to(Vector2(node["position"].x, node["position"].z)) < 6.0:
				overlaps_node = true
				break
		if not overlaps_node and _boulder_spacing_ok(point):
			break
	point.y = height_at(point.x, point.z)
	return point

func _boulder_spacing_ok(point: Vector3) -> bool:
	for existing: Dictionary in boulder_definitions:
		if Vector2(point.x, point.z).distance_to(Vector2(existing["position"].x, existing["position"].z)) < 5.5:
			return false
	return true

func _add_boulder(boulder_id: String, item_id: String, amount: int, point: Vector3) -> void:
	var definition: Dictionary = {
		"id": boulder_id,
		"item": item_id,
		"remaining": amount,
		"position": point
	}
	boulder_definitions.append(definition)
	ore_boulders.register(boulder_id, item_id, amount)
	if DisplayServer.get_name() != "headless":
		_make_boulder_visual(definition)

func _make_boulder_visual(definition: Dictionary) -> void:
	var boulder_id: String = str(definition["id"])
	var item_id: String = str(definition["item"])
	var root: Node3D = Node3D.new()
	root.name = "OreBoulder_%s" % boulder_id
	root.position = definition["position"]
	root.rotation.y = deg_to_rad(float(boulder_id.hash() % 360))
	root.set_meta("ore_boulder", boulder_id)
	var rock_parts: Array[Dictionary] = [
		{"position": Vector3(0.0, 0.91, 0.0), "scale": Vector3(0.86, 0.9, 0.74), "mesh": "rock_a"},
		{"position": Vector3(-0.55, 0.43, 0.16), "scale": Vector3(0.55, 0.5, 0.48), "mesh": "rock_b"},
		{"position": Vector3(0.48, 0.39, -0.27), "scale": Vector3(0.44, 0.43, 0.42), "mesh": "rock_c"}
	]
	var rock_surface: SurfaceTool = SurfaceTool.new()
	rock_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Dictionary in rock_parts:
		var rock_transform: Transform3D = Transform3D(Basis().scaled(part["scale"]), part["position"])
		_append_boulder_mesh(rock_surface, _boulder_mesh(str(part["mesh"])), rock_transform)
	rock_surface.generate_normals()
	var rock: MeshInstance3D = MeshInstance3D.new()
	rock.mesh = rock_surface.commit()
	rock.material_override = _boulder_material(item_id, false)
	root.add_child(rock)
	var vein_surface: SurfaceTool = SurfaceTool.new()
	vein_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(5):
		var vein_position: Vector3 = Vector3(
			-0.42 + float(index % 3) * 0.36,
			0.55 + float(index / 3) * 0.48,
			0.63
		)
		var vein_rotation: float = -0.55 + float(index % 3) * 0.5
		var vein_basis: Basis = Basis(Vector3.FORWARD, vein_rotation).scaled(Vector3(0.46, 0.75, 0.9))
		_append_boulder_mesh(vein_surface, _boulder_mesh("vein"), Transform3D(vein_basis, vein_position))
	vein_surface.generate_normals()
	var veins: MeshInstance3D = MeshInstance3D.new()
	veins.mesh = vein_surface.commit()
	veins.material_override = _boulder_material(item_id, true)
	root.add_child(veins)
	var collision_body: StaticBody3D = StaticBody3D.new()
	collision_body.collision_layer = 2
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 1.12
	collision_shape.shape = sphere
	collision_shape.position.y = 0.9
	collision_body.add_child(collision_shape)
	root.add_child(collision_body)
	boulder_nodes[boulder_id] = root
	add_child(root)

func _append_boulder_mesh(surface: SurfaceTool, source: Mesh, transform: Transform3D) -> void:
	var arrays: Array = source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if indices is PackedInt32Array and not indices.is_empty():
		for index: int in indices:
			surface.add_vertex(transform * vertices[index])
	else:
		for vertex: Vector3 in vertices:
			surface.add_vertex(transform * vertex)

func _boulder_mesh(kind: String) -> Mesh:
	if not boulder_meshes.has(kind):
		if kind == "vein":
			var vein_mesh: BoxMesh = BoxMesh.new()
			vein_mesh.size = Vector3(1.0, 0.2, 0.12)
			boulder_meshes[kind] = vein_mesh
		else:
			var phi: float = (1.0 + sqrt(5.0)) * 0.5
			var points: Array[Vector3] = [
				Vector3(-1.0, phi, 0.0), Vector3(1.0, phi, 0.0),
				Vector3(-1.0, -phi, 0.0), Vector3(1.0, -phi, 0.0),
				Vector3(0.0, -1.0, phi), Vector3(0.0, 1.0, phi),
				Vector3(0.0, -1.0, -phi), Vector3(0.0, 1.0, -phi),
				Vector3(phi, 0.0, -1.0), Vector3(phi, 0.0, 1.0),
				Vector3(-phi, 0.0, -1.0), Vector3(-phi, 0.0, 1.0)
			]
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = 18271 + abs(kind.hash() % 10000)
			for index: int in range(points.size()):
				points[index] = points[index].normalized() * rng.randf_range(0.82, 1.15)
			var faces: Array[Vector3i] = [
				Vector3i(0, 11, 5), Vector3i(0, 5, 1),
				Vector3i(0, 1, 7), Vector3i(0, 7, 10),
				Vector3i(0, 10, 11), Vector3i(1, 5, 9),
				Vector3i(5, 11, 4), Vector3i(11, 10, 2),
				Vector3i(10, 7, 6), Vector3i(7, 1, 8),
				Vector3i(3, 9, 4), Vector3i(3, 4, 2),
				Vector3i(3, 2, 6), Vector3i(3, 6, 8),
				Vector3i(3, 8, 9), Vector3i(4, 9, 5),
				Vector3i(2, 4, 11), Vector3i(6, 2, 10),
				Vector3i(8, 6, 7), Vector3i(9, 8, 1)
			]
			var surface: SurfaceTool = SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for face: Vector3i in faces:
				surface.add_vertex(points[face.x])
				surface.add_vertex(points[face.y])
				surface.add_vertex(points[face.z])
			surface.generate_normals()
			boulder_meshes[kind] = surface.commit()
	return boulder_meshes[kind] as Mesh

func _boulder_material(item_id: String, vein: bool) -> StandardMaterial3D:
	var cache_key: String = "%s_%s" % [item_id, "vein" if vein else "rock"]
	if not boulder_materials.has(cache_key):
		var rock_colors: Dictionary = {
			"iron_ore": Color("40332f"),
			"copper_ore": Color("294744"),
			"limestone": Color("706b5e")
		}
		var vein_colors: Dictionary = {
			"iron_ore": Color("a5593a"),
			"copper_ore": Color("d68649"),
			"limestone": Color("c9c3a7")
		}
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = vein_colors[item_id] if vein else rock_colors[item_id]
		material.roughness = 0.92 if not vein else 0.72
		material.metallic = 0.1 if vein else 0.02
		boulder_materials[cache_key] = material
	return boulder_materials[cache_key]

func _update_boulder_visual(boulder_id: String) -> void:
	if not boulder_nodes.has(boulder_id):
		return
	var root: Node3D = boulder_nodes[boulder_id]
	var remaining: int = ore_boulders.remaining_for(boulder_id)
	if remaining <= 0:
		_spawn_boulder_burst(root.position)
		root.queue_free()
		boulder_nodes.erase(boulder_id)
		return
	var capacity: int = int(ore_boulders.deposits[boulder_id]["capacity"])
	var size: float = maxf(0.42, pow(float(remaining) / float(capacity), 0.58))
	root.scale = Vector3.ONE * size

func _spawn_boulder_burst(point: Vector3) -> void:
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.name = "OreBoulderBurst"
	particles.position = point + Vector3(0.0, 0.8, 0.0)
	particles.amount = 18
	particles.lifetime = 0.7
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.direction = Vector3.UP
	particles.spread = 150.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 3.2
	particles.gravity = Vector3(0.0, -6.0, 0.0)
	var dust_mesh: SphereMesh = SphereMesh.new()
	dust_mesh.radius = 0.12
	dust_mesh.height = 0.2
	particles.mesh = dust_mesh
	var dust_material: StandardMaterial3D = StandardMaterial3D.new()
	dust_material.albedo_color = Color("9b8772")
	dust_material.roughness = 1.0
	particles.material_override = dust_material
	add_child(particles)
	particles.finished.connect(particles.queue_free)
	particles.emitting = true

func _build_vents() -> void:
	for point: Vector3 in [
		Vector3(-55.0, 0.0, 5.0), Vector3(42.0, 0.0, -52.0), Vector3(-102.0, 0.0, 72.0),
		Vector3(192.0, 0.0, 245.0), Vector3(-330.0, 0.0, -260.0), Vector3(355.0, 0.0, 205.0)
	]:
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
		var vent_label: Label3D = Label3D.new()
		vent_label.text = "Geothermal"
		vent_label.position = Vector3(0.0, 3.0, 0.0)
		vent_label.font_size = 30
		vent_label.pixel_size = 0.009
		vent_label.no_depth_test = false
		vent_label.outline_size = 5
		vent_label.outline_modulate = Color("202520")
		vent_label.visibility_range_end = 12.0
		vent_label.visibility_range_end_margin = 3.0
		vent_label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		stack.add_child(vent_label)
		add_child(stack)

func _build_landing_site() -> void:
	landing_position.y = height_at(landing_position.x, landing_position.z)
	spire_position.y = height_at(spire_position.x, spire_position.z)
	if DisplayServer.get_name() == "headless":
		return
	var pod_scene: PackedScene = load("res://assets/models/drop_pod.glb") as PackedScene
	var pod: Node3D = pod_scene.instantiate() as Node3D
	pod.name = "DropPod"
	pod.position = landing_position + Vector3(-5.0, 0.0, 0.0)
	machine_models.apply_pbr_materials(pod)
	add_child(pod)
	var hub_scene: PackedScene = load("res://assets/models/hub.glb") as PackedScene
	var hub: Node3D = hub_scene.instantiate() as Node3D
	hub.name = "HUB"
	hub.position = landing_position + Vector3(4.0, 0.0, 0.0)
	machine_models.apply_pbr_materials(hub)
	hub.set_meta("interactable", "hub")
	add_child(hub)
	var hub_body: StaticBody3D = StaticBody3D.new()
	hub_body.collision_layer = 2
	var hub_collision: CollisionShape3D = CollisionShape3D.new()
	var hub_box: BoxShape3D = BoxShape3D.new()
	hub_box.size = Vector3(4.0, 3.5, 3.0)
	hub_collision.shape = hub_box
	hub_collision.position.y = 1.75
	hub_body.add_child(hub_collision)
	hub.add_child(hub_body)
