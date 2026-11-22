extends RefCounted
class_name Items

static func all() -> Dictionary:
	return {
		"iron_ore": {"name": "Iron Ore", "color": Color("b9a597")},
		"copper_ore": {"name": "Copper Ore", "color": Color("db8444")},
		"limestone": {"name": "Limestone", "color": Color("d8d2bd")},
		"iron_ingot": {"name": "Iron Ingot", "color": Color("e0d2bd")},
		"copper_ingot": {"name": "Copper Ingot", "color": Color("df9657")},
		"concrete": {"name": "Concrete", "color": Color("aaa99f")},
		"iron_plate": {"name": "Iron Plate", "color": Color("b4c1c5")},
		"iron_rod": {"name": "Iron Rod", "color": Color("a7b5bd")},
		"screw": {"name": "Screw", "color": Color("d5c7b0")},
		"wire": {"name": "Wire", "color": Color("e8ba58")},
		"cable": {"name": "Cable", "color": Color("bd773c")},
		"hull_panel": {"name": "Hull Panel", "color": Color("aab8c4")},
		"rotor": {"name": "Rotor", "color": Color("b27f55")}
	}

static func item_name(item_id: String) -> String:
	return str(all().get(item_id, {}).get("name", item_id.capitalize()))
