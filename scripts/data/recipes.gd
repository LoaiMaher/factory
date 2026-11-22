extends RefCounted
class_name Recipes

static func all() -> Dictionary:
	return {
		"iron_ingot": {"machine": "smelter", "inputs": {"iron_ore": 1}, "outputs": {"iron_ingot": 1}, "time": 2.0},
		"copper_ingot": {"machine": "smelter", "inputs": {"copper_ore": 1}, "outputs": {"copper_ingot": 1}, "time": 2.0},
		"iron_plate": {"machine": "constructor", "inputs": {"iron_ingot": 3}, "outputs": {"iron_plate": 2}, "time": 6.0},
		"iron_rod": {"machine": "constructor", "inputs": {"iron_ingot": 1}, "outputs": {"iron_rod": 1}, "time": 4.0},
		"screw": {"machine": "constructor", "inputs": {"iron_rod": 1}, "outputs": {"screw": 4}, "time": 6.0},
		"wire": {"machine": "constructor", "inputs": {"copper_ingot": 1}, "outputs": {"wire": 2}, "time": 4.0},
		"cable": {"machine": "constructor", "inputs": {"wire": 2}, "outputs": {"cable": 1}, "time": 2.0},
		"concrete": {"machine": "constructor", "inputs": {"limestone": 3}, "outputs": {"concrete": 1}, "time": 4.0},
		"hull_panel": {"machine": "assembler", "inputs": {"iron_plate": 6, "screw": 12}, "outputs": {"hull_panel": 1}, "time": 12.0},
		"rotor": {"machine": "assembler", "inputs": {"iron_rod": 5, "screw": 25}, "outputs": {"rotor": 1}, "time": 15.0}
	}

static func for_machine(machine_id: String) -> Array[String]:
	var result: Array[String] = []
	for recipe_id: String in all():
		if str(all()[recipe_id]["machine"]) == machine_id:
			result.append(recipe_id)
	return result

static func default_for(machine_id: String) -> String:
	var recipes: Array[String] = for_machine(machine_id)
	return recipes[0] if not recipes.is_empty() else ""
