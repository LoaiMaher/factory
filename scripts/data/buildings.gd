extends RefCounted
class_name BuildingDefs

static func all() -> Dictionary:
	return {
		"miner_mk1": {"size": Vector2i(2, 2), "power": 5.0, "cost": {"iron_plate": 10, "concrete": 10}, "tier": 0},
		"smelter": {"size": Vector2i(2, 2), "power": 4.0, "cost": {"iron_rod": 5, "wire": 8}, "tier": 0},
		"constructor": {"size": Vector2i(2, 3), "power": 4.0, "cost": {"iron_plate": 8, "wire": 10}, "tier": 0},
		"assembler": {"size": Vector2i(3, 3), "power": 15.0, "cost": {"iron_plate": 20, "screw": 40, "cable": 10}, "tier": 2},
		"belt_mk1": {"size": Vector2i.ONE, "power": 0.0, "cost": {"iron_plate": 1}, "tier": 0, "speed": 0.5},
		"belt_mk2": {"size": Vector2i.ONE, "power": 0.0, "cost": {"iron_plate": 1, "screw": 2}, "tier": 2, "speed": 1.0},
		"splitter": {"size": Vector2i.ONE, "power": 0.0, "cost": {"iron_plate": 2}, "tier": 1},
		"merger": {"size": Vector2i.ONE, "power": 0.0, "cost": {"iron_plate": 2}, "tier": 1},
		"storage": {"size": Vector2i(2, 2), "power": 0.0, "cost": {"iron_plate": 10}, "tier": 1},
		"power_pole": {"size": Vector2i.ONE, "power": 0.0, "cost": {"iron_rod": 1, "wire": 2}, "tier": 0},
		"geo_tap": {"size": Vector2i(2, 2), "power": -50.0, "cost": {"iron_plate": 20, "iron_rod": 10, "wire": 10}, "tier": 0},
		"spire": {"size": Vector2i(6, 6), "power": 0.0, "cost": {}, "tier": 0}
	}

static func size_of(building_id: String, rotation: int = 0) -> Vector2i:
	var size: Vector2i = all().get(building_id, {}).get("size", Vector2i.ONE)
	return size if posmod(rotation, 2) == 0 else Vector2i(size.y, size.x)
