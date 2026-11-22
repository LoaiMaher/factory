extends RefCounted
class_name Progression

static func tiers() -> Array[Dictionary]:
	return [
		{"name": "Foundation", "cost": {}, "unlocks": ["miner_mk1", "smelter", "constructor", "belt_mk1", "power_pole", "geo_tap"]},
		{"name": "Logistics", "cost": {"iron_plate": 50, "iron_rod": 30}, "unlocks": ["splitter", "merger", "storage"]},
		{"name": "Assembly", "cost": {"iron_plate": 100, "screw": 200, "cable": 50}, "unlocks": ["assembler", "belt_mk2"]}
	]

static func milestones() -> Array[Dictionary]:
	return [
		{"name": "Keel Laying", "duration": 120.0, "requirements": {"hull_panel": 2.0, "rotor": 1.5}},
		{"name": "Pressure Frame", "duration": 180.0, "requirements": {"hull_panel": 5.0, "rotor": 4.0, "cable": 20.0}}
	]
