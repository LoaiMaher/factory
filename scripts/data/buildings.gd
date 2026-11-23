extends RefCounted
class_name BuildingDefs

static func _port(id: String, direction: String, position: Vector3, normal: Vector3) -> Dictionary:
	return {"id": id, "dir": direction, "pos": position, "normal": normal}

static func all() -> Dictionary:
	var north: Vector3 = Vector3(0.0, 0.0, -1.0)
	var south: Vector3 = Vector3(0.0, 0.0, 1.0)
	var west: Vector3 = Vector3(-1.0, 0.0, 0.0)
	var east: Vector3 = Vector3(1.0, 0.0, 0.0)
	return {
		"miner_mk1": {"size": Vector3(4.0, 6.0, 4.0), "ports": [_port("out0", "out", Vector3(-1.0, 1.0, 2.0), south)], "requires": "node", "power": 5.0, "cost": {"iron_plate": 10, "concrete": 10}, "tier": 0},
		"smelter": {"size": Vector3(4.0, 5.0, 4.0), "ports": [_port("in0", "in", Vector3(-1.0, 1.0, -2.0), north), _port("out0", "out", Vector3(-1.0, 1.0, 2.0), south)], "requires": "", "power": 4.0, "cost": {"iron_rod": 5, "wire": 8}, "tier": 0},
		"constructor": {"size": Vector3(4.0, 4.0, 6.0), "ports": [_port("in0", "in", Vector3(-1.0, 1.0, -3.0), north), _port("out0", "out", Vector3(-1.0, 1.0, 3.0), south)], "requires": "", "power": 4.0, "cost": {"iron_plate": 8, "wire": 10}, "tier": 0},
		"assembler": {"size": Vector3(6.0, 4.5, 6.0), "ports": [_port("in0", "in", Vector3(-2.0, 1.0, -3.0), north), _port("in1", "in", Vector3(2.0, 1.0, -3.0), north), _port("out0", "out", Vector3(0.0, 1.0, 3.0), south)], "requires": "", "power": 15.0, "cost": {"iron_plate": 20, "screw": 40, "cable": 10}, "tier": 2},
		"belt_mk1": {"size": Vector3(0.8, 0.5, 1.4), "ports": [], "requires": "", "power": 0.0, "cost": {"iron_plate": 1}, "tier": 0},
		"belt_mk2": {"size": Vector3(0.8, 0.5, 1.4), "ports": [], "requires": "", "power": 0.0, "cost": {"iron_plate": 1, "screw": 2}, "tier": 2},
		"belt_pole": {"size": Vector3(0.8, 1.5, 0.8), "ports": [_port("in0", "in", Vector3(0.0, 1.0, -0.4), north), _port("out0", "out", Vector3(0.0, 1.0, 0.4), south)], "requires": "", "power": 0.0, "cost": {"iron_rod": 1}, "tier": 0},
		"splitter": {"size": Vector3(2.0, 2.0, 2.0), "ports": [_port("in0", "in", Vector3(0.0, 0.55, -1.0), north), _port("out0", "out", Vector3(-1.0, 0.55, 0.0), west), _port("out1", "out", Vector3(0.0, 0.55, 1.0), south), _port("out2", "out", Vector3(1.0, 0.55, 0.0), east)], "requires": "", "power": 0.0, "cost": {"iron_plate": 2}, "tier": 1},
		"merger": {"size": Vector3(2.0, 2.0, 2.0), "ports": [_port("in0", "in", Vector3(-1.0, 0.55, 0.0), west), _port("in1", "in", Vector3(0.0, 0.55, -1.0), north), _port("in2", "in", Vector3(1.0, 0.55, 0.0), east), _port("out0", "out", Vector3(0.0, 0.55, 1.0), south)], "requires": "", "power": 0.0, "cost": {"iron_plate": 2}, "tier": 1},
		"storage": {"size": Vector3(4.0, 3.0, 4.0), "ports": [_port("in0", "in", Vector3(-1.0, 0.62, -2.0), north), _port("out0", "out", Vector3(-1.0, 0.62, 2.0), south)], "requires": "", "power": 0.0, "cost": {"iron_plate": 10}, "tier": 1},
		"power_pole": {"size": Vector3(2.0, 6.0, 2.0), "ports": [_port("in0", "in", Vector3(-1.0, 5.62, 0.0), west), _port("out0", "out", Vector3(1.0, 5.62, 0.0), east)], "requires": "", "power": 0.0, "cost": {"iron_rod": 1, "wire": 2}, "tier": 0},
		"geo_tap": {"size": Vector3(4.0, 4.5, 4.0), "ports": [_port("out0", "out", Vector3(-1.0, 0.62, 2.0), south)], "requires": "vent", "power": -50.0, "cost": {"iron_plate": 20, "iron_rod": 10, "wire": 10}, "tier": 0},
		"spire": {"size": Vector3(12.0, 17.0, 12.0), "ports": [_port("in0", "in", Vector3(-3.0, 0.72, 6.0), south), _port("in1", "in", Vector3(3.0, 0.72, 6.0), south), _port("in2", "in", Vector3(-1.0, 0.72, 6.0), south), _port("in3", "in", Vector3(1.0, 0.72, 6.0), south)], "requires": "", "power": 0.0, "cost": {}, "tier": 0}
	}

static func size_of(building_id: String) -> Vector3:
	return all().get(building_id, {}).get("size", Vector3.ONE)
