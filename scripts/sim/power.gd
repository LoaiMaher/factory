extends RefCounted
class_name FactoryPower

var network_for: Dictionary = {}
var supply_for: Dictionary = {}
var demand_for: Dictionary = {}
var building_definitions: Dictionary = BuildingDefs.all()
var recipe_definitions: Dictionary = Recipes.all()

func rebuild(entities: Dictionary) -> void:
	network_for.clear()
	var poles: Array[int] = []
	for raw_id: Variant in entities:
		var entity: FactoryEntity = entities[raw_id]
		if entity.kind == "power_pole":
			poles.append(entity.id)
	var parent: Dictionary = {}
	for pole_id: int in poles:
		parent[pole_id] = pole_id
	for i: int in range(poles.size()):
		for j: int in range(i + 1, poles.size()):
			var first: FactoryEntity = entities[poles[i]]
			var second: FactoryEntity = entities[poles[j]]
			if first.cell.distance_to(second.cell) * 2.0 <= 24.0:
				_union(parent, first.id, second.id)
	for pole_id: int in poles:
		network_for[pole_id] = _find(parent, pole_id)
	for raw_id: Variant in entities:
		var entity: FactoryEntity = entities[raw_id]
		if entity.kind == "power_pole":
			continue
		if float(building_definitions.get(entity.kind, {}).get("power", 0.0)) == 0.0:
			continue
		network_for[entity.id] = _nearest_network(entity, poles, entities, 12.0)
	update_demand(entities)

func update_demand(entities: Dictionary) -> void:
	supply_for.clear()
	demand_for.clear()
	for raw_id: Variant in entities:
		var entity: FactoryEntity = entities[raw_id]
		var power_value: float = float(building_definitions.get(entity.kind, {}).get("power", 0.0))
		if power_value == 0.0:
			continue
		var network: int = int(network_for.get(entity.id, -1))
		if network < 0:
			continue
		if power_value < 0.0:
			supply_for[network] = float(supply_for.get(network, 0.0)) + absf(power_value)
		elif _is_crafting(entity):
			demand_for[network] = float(demand_for.get(network, 0.0)) + power_value

func _is_crafting(entity: FactoryEntity) -> bool:
	if entity.kind == "miner_mk1":
		return not entity.extra.get("node", {}).is_empty()
	if entity.kind not in ["smelter", "constructor", "assembler"] or not recipe_definitions.has(entity.recipe_id):
		return false
	var recipe: Dictionary = recipe_definitions[entity.recipe_id]
	for item_id: String in recipe["inputs"]:
		if int(entity.input_buffer.get(item_id, 0)) < int(recipe["inputs"][item_id]):
			return false
	for item_id: String in recipe["outputs"]:
		if int(entity.output_buffer.get(item_id, 0)) + int(recipe["outputs"][item_id]) > maxi(20, int(recipe["outputs"][item_id]) * 2):
			return false
	return true

func satisfaction(entity_id: int, _entities: Dictionary) -> float:
	var network: int = int(network_for.get(entity_id, -1))
	if network < 0:
		return -1.0
	var supply: float = float(supply_for.get(network, 0.0))
	var demand: float = float(demand_for.get(network, 0.0))
	if supply <= 0.0:
		return 0.0
	if demand <= 0.0:
		return 1.0
	return minf(1.0, supply / demand)

func totals_near(_cell: Vector2i) -> Vector2:
	var supply: float = 0.0
	var demand: float = 0.0
	for value: Variant in supply_for.values():
		supply += float(value)
	for value: Variant in demand_for.values():
		demand += float(value)
	return Vector2(supply, demand)

func _nearest_network(entity: FactoryEntity, poles: Array[int], entities: Dictionary, max_distance: float) -> int:
	var closest: int = -1
	var closest_distance: float = max_distance + 0.01
	for pole_id: int in poles:
		var pole: FactoryEntity = entities[pole_id]
		var distance: float = _distance_to_footprint(entity, pole)
		if distance <= max_distance and distance < closest_distance:
			closest_distance = distance
			closest = int(network_for.get(pole_id, -1))
	return closest

func _distance_to_footprint(entity: FactoryEntity, pole: FactoryEntity) -> float:
	var size: Vector2i = building_definitions.get(entity.kind, {}).get("size", Vector2i.ONE)
	if entity.rotation % 2 == 1:
		size = Vector2i(size.y, size.x)
	var shortest: float = INF
	for x: int in range(size.x):
		for y: int in range(size.y):
			shortest = minf(shortest, entity.cell.distance_to(pole.cell + Vector2i(x, y)) * 2.0)
	return shortest

func _find(parent: Dictionary, node: int) -> int:
	if int(parent[node]) != node:
		parent[node] = _find(parent, int(parent[node]))
	return int(parent[node])

func _union(parent: Dictionary, first: int, second: int) -> void:
	var a: int = _find(parent, first)
	var b: int = _find(parent, second)
	if a != b:
		parent[b] = a
