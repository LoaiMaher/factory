extends Node3D
class_name BorebackHerd

var terrain: FactoryTerrain
var members: Array[Node3D] = []
var waypoints: Array[Vector3] = []
var waypoint_index: int = 0
var dig_timer: float = 0.0
var flee_timer: float = 0.0
var flee_from: Vector3 = Vector3.ZERO
var discovered: bool = false

func setup(factory_terrain: FactoryTerrain) -> void:
	terrain = factory_terrain
	waypoints = [
		Vector3(-62.0, 0.0, -45.0), Vector3(-34.0, 0.0, -20.0),
		Vector3(5.0, 0.0, -12.0), Vector3(42.0, 0.0, -30.0),
		terrain.hidden_iron
	]
	if DisplayServer.get_name() == "headless":
		return
	for index: int in range(3):
		var beast: Node3D = _make_beast(index)
		members.append(beast)
		add_child(beast)

func _process(delta: float) -> void:
	if terrain == null or waypoints.is_empty() or members.is_empty():
		return
	dig_timer = maxf(0.0, dig_timer - delta)
	flee_timer = maxf(0.0, flee_timer - delta)
	if dig_timer <= 0.0:
		var target: Vector3 = waypoints[waypoint_index]
		for index: int in range(members.size()):
			var beast: Node3D = members[index]
			var destination: Vector3
			var speed: float = 1.5
			if flee_timer > 0.0:
				var away: Vector3 = beast.position - flee_from
				away.y = 0.0
				destination = beast.position + (away.normalized() if away.length_squared() > 0.01 else Vector3.BACK) * 12.0
				speed = 4.2
			else:
				var offset: Vector3 = Vector3(float(index - 1) * 2.2, 0.0, float(index % 2) * 2.0)
				destination = target + offset
			var ground_position: Vector3 = beast.position
			ground_position.y = terrain.height_at(ground_position.x, ground_position.z)
			ground_position = ground_position.move_toward(Vector3(destination.x, terrain.height_at(destination.x, destination.z), destination.z), delta * speed)
			beast.position = ground_position
			beast.rotation.y = atan2(destination.x - beast.position.x, destination.z - beast.position.z)
			beast.position.y += 0.06 * sin(Time.get_ticks_msec() * 0.009 + float(index))
		var waypoint_distance_xz: float = Vector2(members[0].position.x, members[0].position.z).distance_to(Vector2(target.x, target.z))
		if flee_timer <= 0.0 and waypoint_distance_xz < 3.0:
			if waypoint_index == waypoints.size() - 1:
				dig_timer = 20.0
				waypoint_index = 0
			else:
				waypoint_index = (waypoint_index + 1) % waypoints.size()
	else:
		for beast: Node3D in members:
			beast.position.y += 0.015 * sin(Time.get_ticks_msec() * 0.006)

func alert_sprint(player_position: Vector3) -> void:
	if not members.is_empty() and members[0].position.distance_to(player_position) < 9.0:
		flee_timer = 5.0
		flee_from = player_position

func _make_beast(index: int) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Boreback_%d" % index
	var body: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: CapsuleMesh = CapsuleMesh.new()
	body_mesh.radius = 0.85
	body_mesh.height = 2.3
	body.mesh = body_mesh
	body.rotation.z = PI / 2.0
	body.position.y = 1.25
	var hide: StandardMaterial3D = StandardMaterial3D.new()
	hide.albedo_color = Color("4d4940")
	hide.roughness = 0.88
	hide.metallic = 0.08
	body.material_override = hide
	root.add_child(body)
	for x: float in [-0.52, 0.52]:
		for z: float in [-0.48, 0.48]:
			var leg: MeshInstance3D = MeshInstance3D.new()
			var leg_mesh: CylinderMesh = CylinderMesh.new()
			leg_mesh.top_radius = 0.13
			leg_mesh.bottom_radius = 0.19
			leg_mesh.height = 0.9
			leg.mesh = leg_mesh
			leg.position = Vector3(x, 0.48, z)
			leg.material_override = hide
			root.add_child(leg)
	for spike_index: int in range(4):
		var spike: MeshInstance3D = MeshInstance3D.new()
		var spike_mesh: PrismMesh = PrismMesh.new()
		spike_mesh.size = Vector3(0.55, 0.75, 0.5)
		spike.mesh = spike_mesh
		spike.position = Vector3(-0.62 + float(spike_index) * 0.42, 2.05, 0.0)
		var plate_material: StandardMaterial3D = StandardMaterial3D.new()
		plate_material.albedo_color = Color("74664e")
		plate_material.roughness = 0.82
		plate_material.metallic = 0.18
		spike.material_override = plate_material
		root.add_child(spike)
	root.position = Vector3(-62.0 + float(index) * 2.0, terrain.height_at(-62.0, -45.0), -45.0)
	return root
