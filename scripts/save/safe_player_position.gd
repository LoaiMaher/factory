extends RefCounted
class_name SafePlayerPosition

static func adjust(position: Vector3, terrain_height: float,
		half_extent: float = 512.0) -> Vector3:
	var safe_position: Vector3 = position
	safe_position.x = clampf(safe_position.x, -half_extent + 1.0, half_extent - 1.0)
	safe_position.z = clampf(safe_position.z, -half_extent + 1.0, half_extent - 1.0)
	if safe_position.y < terrain_height + 0.2:
		safe_position.y = terrain_height + 1.0
	return safe_position
