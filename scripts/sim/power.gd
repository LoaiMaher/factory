extends RefCounted
class_name FactoryPower

var network_for: Dictionary = {}
var supply_for: Dictionary = {}
var demand_for: Dictionary = {}
var building_definitions: Dictionary = BuildingDefs.all()
var recipe_definitions: Dictionary = Recipes.all()
var bypass: bool = bool(ProjectSettings.get_setting("factory/dev/power_bypass", true))

func apply_launch_flags(arguments: PackedStringArray) -> void:
	if arguments.has("--real-power"):
		bypass = false

func rebuild(entities: Dictionary) -> void:
	network_for.clear()
	var poles: Array[int] = []
	for entity: FactoryEntity in entities.values():
		if entity.kind == "power_pole":
			poles.append(entity.id)
	var parent: Dictionary = {}
	for pole_id: int in poles:
		parent[pole_id] = pole_id
	for i: int in range(poles.size()):
		for j: int in range(i + 1, poles.size()):
			var a: FactoryEntity = entities[poles[i]]
			var b: FactoryEntity = entities[poles[j]]
			if Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length() <= 24.0:
				_union(parent, a.id, b.id)
	for pole_id: int in poles:
		network_for[pole_id] = _find(parent, pole_id)
	for entity: FactoryEntity in entities.values():
		if entity.kind == "power_pole" or float(building_definitions.get(entity.kind, {}).get("power", 0.0)) == 0.0:
			continue
		network_for[entity.id] = _nearest_network(entity, poles, entities, 12.0)
	update_demand(entities)

func update_demand(entities: Dictionary) -> void:
	supply_for.clear()
	demand_for.clear()
	for entity: FactoryEntity in entities.values():
		var amount: float = float(building_definitions.get(entity.kind, {}).get("power", 0.0))
		var network: int = int(network_for.get(entity.id, -1))
		if amount == 0.0 or network < 0:
			continue
		if amount < 0.0:
			supply_for[network] = float(supply_for.get(network, 0.0)) + absf(amount)
		elif _is_crafting(entity):
			demand_for[network] = float(demand_for.get(network, 0.0)) + amount

func satisfaction(entity_id: int, _entities: Dictionary) -> float:
	if bypass:
		return 1.0
	var network: int = int(network_for.get(entity_id, -1))
	if network < 0:
		return -1.0
	var supply: float = float(supply_for.get(network, 0.0))
	var demand: float = float(demand_for.get(network, 0.0))
	if supply <= 0.0:
		return 0.0
	return 1.0 if demand <= 0.0 else minf(1.0, supply / demand)

func totals_near(_position: Vector3) -> Vector2:
	var supply: float = 0.0
	var demand: float = 0.0
	for value: Variant in supply_for.values():
		supply += float(value)
	for value: Variant in demand_for.values():
		demand += float(value)
	return Vector2(supply, demand)

func _is_crafting(entity: FactoryEntity) -> bool:
	if entity.kind == "miner_mk1":
		return int(entity.extra.get("node_id", -1)) >= 0
	if entity.kind not in ["smelter", "constructor", "assembler"] or not recipe_definitions.has(entity.recipe_id):
		return false
	var recipe: Dictionary = recipe_definitions[entity.recipe_id]
	for item_id: String in recipe["inputs"]:
		if int(entity.input_buffer.get(item_id, 0)) < int(recipe["inputs"][item_id]):
			return false
	return true

func _nearest_network(entity: FactoryEntity, poles: Array[int], entities: Dictionary, max_distance: float) -> int:
	var result: int = -1
	var best: float = max_distance
	for pole_id: int in poles:
		var pole: FactoryEntity = entities[pole_id]
		var size: Vector3 = BuildingDefs.size_of(entity.kind)
		var dx: float = maxf(0.0, absf(pole.position.x - entity.position.x) - size.x * 0.5)
		var dz: float = maxf(0.0, absf(pole.position.z - entity.position.z) - size.z * 0.5)
		var distance: float = Vector2(dx, dz).length()
		if distance <= best:
			result = int(network_for.get(pole_id, -1))
			best = distance
	return result

func _find(parent: Dictionary, node: int) -> int:
	if int(parent[node]) != node:
		parent[node] = _find(parent, int(parent[node]))
	return int(parent[node])

func _union(parent: Dictionary, first: int, second: int) -> void:
	var a: int = _find(parent, first)
	var b: int = _find(parent, second)
	if a != b:
		parent[b] = a
