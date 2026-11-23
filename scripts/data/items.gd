extends RefCounted
class_name Items

static func all() -> Dictionary:
	return {
		"iron_ore": {"name": "Iron Ore", "color": Color("b9a597"), "category": "raw", "description": "Iron-bearing ore mined from surface deposits.", "stack": 64},
		"copper_ore": {"name": "Copper Ore", "color": Color("db8444"), "category": "raw", "description": "Copper-bearing ore used for conductive parts.", "stack": 64},
		"limestone": {"name": "Limestone", "color": Color("d8d2bd"), "category": "raw", "description": "Calcium-rich stone used to make concrete.", "stack": 64},
		"iron_ingot": {"name": "Iron Ingot", "color": Color("e0d2bd"), "category": "processed", "description": "Smelted iron ready for fabrication.", "stack": 64},
		"copper_ingot": {"name": "Copper Ingot", "color": Color("df9657"), "category": "processed", "description": "Smelted copper ready for wiring.", "stack": 64},
		"concrete": {"name": "Concrete", "color": Color("aaa99f"), "category": "processed", "description": "Durable construction material made from limestone.", "stack": 64},
		"iron_plate": {"name": "Iron Plate", "color": Color("b4c1c5"), "category": "component", "description": "Flat iron stock for factory structures.", "stack": 64},
		"iron_rod": {"name": "Iron Rod", "color": Color("a7b5bd"), "category": "component", "description": "Structural iron stock for machines and rotors.", "stack": 64},
		"screw": {"name": "Screw", "color": Color("d5c7b0"), "category": "component", "description": "Fasteners fabricated from iron rods.", "stack": 64},
		"wire": {"name": "Wire", "color": Color("e8ba58"), "category": "component", "description": "Conductive copper wire for electrical parts.", "stack": 64},
		"cable": {"name": "Cable", "color": Color("bd773c"), "category": "component", "description": "Insulated cable for power connections.", "stack": 64},
		"hull_panel": {"name": "Hull Panel", "color": Color("aab8c4"), "category": "special", "description": "Heavy panel delivered to the ascent spire.", "stack": 64},
		"rotor": {"name": "Rotor", "color": Color("b27f55"), "category": "special", "description": "Precision rotor required by the ascent spire.", "stack": 32}
	}

static func item_name(item_id: String) -> String:
	return str(all().get(item_id, {}).get("name", item_id.capitalize()))

static func stack_size(item_id: String) -> int:
	return maxi(1, int(all().get(item_id, {}).get("stack", 64)))

static func category(item_id: String) -> String:
	return str(all().get(item_id, {}).get("category", "special"))

static func description(item_id: String) -> String:
	return str(all().get(item_id, {}).get("description", "Factory item."))
