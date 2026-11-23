extends RefCounted
class_name FactoryPlacement

var yaw: float = 0.0
var grid_snap_enabled: bool = false
var preview_position: Vector3 = Vector3.ZERO
var preview_initialized: bool = false

func rotate_step(direction: int) -> void:
	yaw = wrapf(yaw + deg_to_rad(15.0 * float(direction)), -PI, PI)

func snap_yaw_to_nearby(position: Vector3, sim: FactorySim, radius: float = 4.0) -> void:
	var best: float = radius
	for entity: FactoryEntity in sim.entities.values():
		if entity.kind in ["belt_mk1", "belt_mk2"]:
			continue
		var distance: float = Vector2(position.x - entity.position.x, position.z - entity.position.z).length()
		if distance < best:
			best = distance
			yaw = entity.yaw

func snap_position(position: Vector3, sim: FactorySim) -> Vector3:
	if not grid_snap_enabled:
		return position
	var result := Vector3(roundf(position.x), position.y, roundf(position.z))
	yaw = roundf(yaw / (PI * 0.5)) * PI * 0.5
	snap_yaw_to_nearby(result, sim)
	return result

func fit_and_validate(kind: String, candidate: Vector3, sim: FactorySim, terrain: FactoryTerrain,
		player_position: Vector3, node_id: int = -1) -> Dictionary:
	var size: Vector3 = BuildingDefs.size_of(kind)
	var half_x: float = size.x * 0.5
	var half_z: float = size.z * 0.5
	var basis: Basis = Basis(Vector3.UP, yaw)
	var samples: Array[Vector2] = [Vector2.ZERO, Vector2(-half_x, -half_z), Vector2(half_x, -half_z),
		Vector2(-half_x, half_z), Vector2(half_x, half_z)]
	var heights: Array[float] = []
	var base_y: float = -INF
	for sample: Vector2 in samples:
		var offset: Vector3 = basis * Vector3(sample.x, 0.0, sample.y)
		var xz := Vector2(candidate.x + offset.x, candidate.z + offset.z)
		var height: float = terrain.height_at(xz.x, xz.y)
		heights.append(height)
		base_y = maxf(base_y, height)
		if absf(sample.x) > 0.01 and absf(sample.y) > 0.01:
			if absf(xz.x) > 511.5 or absf(xz.y) > 511.5:
				return {"ok": false, "reason": "Outside build area", "position": Vector3(candidate.x, base_y, candidate.z)}
	base_y = maxf(base_y, candidate.y)
	var result: Vector3 = Vector3(candidate.x, base_y, candidate.z)
	if heights.max() - heights.min() > 1.5:
		return {"ok": false, "reason": "Too steep", "position": result}
	for sample: Vector2 in samples:
		var offset: Vector3 = basis * Vector3(sample.x, 0.0, sample.y)
		if terrain.is_in_lake(Vector3(candidate.x + offset.x, base_y, candidate.z + offset.z)):
			return {"ok": false, "reason": "Can't build in water", "position": result}
	if terrain.is_boulder_in_footprint(result, yaw, size):
		return {"ok": false, "reason": "Blocked by boulder", "position": result}
	var player_local: Vector3 = Basis(Vector3.UP, -yaw) * (player_position - result)
	if absf(player_local.x) < half_x + 0.45 and absf(player_local.z) < half_z + 0.45 and absf(player_local.y) < size.y * 0.5 + 0.9:
		return {"ok": false, "reason": "Too close to player", "position": result}
	var checked: Dictionary = sim.check_place(kind, result, yaw, node_id)
	return {"ok": bool(checked["ok"]), "reason": str(checked["reason"]), "position": result}
