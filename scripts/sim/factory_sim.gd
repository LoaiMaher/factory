extends RefCounted
class_name FactorySim

const BELT_GAP: float = 0.5
const RATE_WINDOW_TOLERANCE: float = 0.002

var entities: Dictionary = {}
var grid: Dictionary = {}
var time: float = 0.0
var next_id: int = 1
var power: FactoryPower = FactoryPower.new()
var building_definitions: Dictionary = BuildingDefs.all()
var recipe_definitions: Dictionary = Recipes.all()
var milestone_definitions: Array[Dictionary] = Progression.milestones()
var spire_progress: Array[float] = [0.0, 0.0]
var spire_stage: int = 0
var discovered_nodes: Dictionary = {}

func add_entity(kind: String, cell: Vector2i, rotation: int = 0, data: Dictionary = {}, forced_id: int = -1) -> int:
	var size: Vector2i = _building_size(kind, rotation)
	for x: int in range(size.x):
		for y: int in range(size.y):
			if grid.has(cell + Vector2i(x, y)):
				return -1
	if forced_id >= 0 and entities.has(forced_id):
		return -1
	var entity: FactoryEntity
	if kind.begins_with("belt_"):
		entity = BeltEntity.new()
		entity.kind = kind
	elif kind == "spire":
		entity = SpireEntity.new()
	else:
		entity = MachineEntity.new()
		entity.kind = kind
	entity.id = forced_id if forced_id >= 0 else next_id
	next_id = maxi(next_id, entity.id + 1)
	entity.cell = cell
	entity.rotation = posmod(rotation, 4)
	entity.cost = building_definitions.get(kind, {}).get("cost", {}).duplicate(true)
	entity.extra = data.duplicate(true)
	entity.recipe_id = str(data.get("recipe", ""))
	if kind == "belt_mk2":
		entity.extra["speed"] = 1.0
	elif kind.begins_with("belt_"):
		entity.extra["speed"] = 0.5
	entities[entity.id] = entity
	for x: int in range(size.x):
		for y: int in range(size.y):
			grid[cell + Vector2i(x, y)] = entity.id
	power.rebuild(entities)
	return entity.id

func remove_entity(entity_id: int) -> FactoryEntity:
	if not entities.has(entity_id):
		return null
	var entity: FactoryEntity = entities[entity_id]
	var size: Vector2i = _building_size(entity.kind, entity.rotation)
	for x: int in range(size.x):
		for y: int in range(size.y):
			grid.erase(entity.cell + Vector2i(x, y))
	entities.erase(entity_id)
	power.rebuild(entities)
	return entity

func entity_at(cell: Vector2i) -> FactoryEntity:
	var entity_id: int = int(grid.get(cell, -1))
	return entities.get(entity_id)

func front_port_for(entity_id: int) -> Vector2i:
	return _front_port(entities[entity_id]) if entities.has(entity_id) else Vector2i.ZERO

func back_port_for(entity_id: int) -> Vector2i:
	return _back_port(entities[entity_id]) if entities.has(entity_id) else Vector2i.ZERO

func port_cells(kind: String, cell: Vector2i, rotation: int = 0) -> Dictionary:
	var front: Vector2i = _front_port_at(kind, cell, rotation)
	var back: Vector2i = _back_port_at(kind, cell, rotation)
	var inputs: Array[Vector2i] = []
	var outputs: Array[Vector2i] = []
	if kind in ["smelter", "constructor", "storage"]:
		inputs = [back]
		outputs = [front]
	elif kind == "assembler":
		inputs = [back - _left(rotation), back + _left(rotation)]
		outputs = [front]
	elif kind == "miner_mk1":
		outputs = [front]
	elif kind == "splitter":
		inputs = [back]
		outputs = [cell + _left(rotation), front, cell + _right(rotation)]
	elif kind == "merger":
		inputs = [cell + _left(rotation), back, cell + _right(rotation)]
		outputs = [front]
	elif kind.begins_with("belt_"):
		inputs = [cell - _forward(rotation), cell + _left(rotation), cell + _right(rotation)]
		outputs = [front]
	return {"input": inputs, "output": outputs}

func can_place(kind: String, cell: Vector2i, rotation: int = 0) -> bool:
	var size: Vector2i = _building_size(kind, rotation)
	for x: int in range(size.x):
		for y: int in range(size.y):
			if grid.has(cell + Vector2i(x, y)):
				return false
	return true

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	time += dt
	power.update_demand(entities)
	_update_belts(dt)
	_update_machines(dt)
	_update_spires(dt)
	for raw_id: Variant in entities:
		var entity: FactoryEntity = entities[raw_id]
		entity.prune_rates(time)

func status_for(entity_id: int) -> String:
	if not entities.has(entity_id):
		return "Stopped"
	return str(entities[entity_id].status)

func get_rate(entity_id: int, item_id: String) -> float:
	if not entities.has(entity_id):
		return 0.0
	return entities[entity_id].rate(item_id, time)

func diagnostics(entity_id: int) -> Array[String]:
	var result: Array[String] = []
	if not entities.has(entity_id):
		return result
	var entity: FactoryEntity = entities[entity_id]
	if entity.recipe_id.is_empty() or not recipe_definitions.has(entity.recipe_id):
		return result
	var recipe: Dictionary = recipe_definitions[entity.recipe_id]
	for item_id: String in recipe["inputs"]:
		var required_rate: float = float(recipe["inputs"][item_id]) * 60.0 / float(recipe["time"])
		result.append("Input %s: %.1f/min — needs %.1f/min" % [Items.item_name(item_id), entity.rate(item_id, time), required_rate])
	for item_id: String in recipe["outputs"]:
		var max_rate: float = float(recipe["outputs"][item_id]) * 60.0 / float(recipe["time"])
		result.append("Output %s: %.1f/min (max %.1f)" % [Items.item_name(item_id), entity.rate(item_id, time), max_rate])
	return result

func try_insert(entity_id: int, item_id: String, from_cell: Vector2i) -> bool:
	if not entities.has(entity_id):
		return false
	var entity: FactoryEntity = entities[entity_id]
	if entity.kind.begins_with("belt_"):
		var relative: Vector2i = from_cell - entity.cell
		if relative != -_forward(entity.rotation) and relative != _left(entity.rotation) and relative != _right(entity.rotation):
			return false
		if entity.belt_items.size() >= 2:
			return false
		for item: Dictionary in entity.belt_items:
			if float(item["pos"]) < BELT_GAP:
				return false
		entity.belt_items.append({"item": item_id, "pos": 0.0, "born_at": time})
		return true
	if entity.kind == "storage":
		if from_cell != _back_port(entity):
			return false
		if _inventory_total(entity.input_buffer) >= 1000:
			entity.status = "Output full"
			return false
		entity.input_buffer[item_id] = int(entity.input_buffer.get(item_id, 0)) + 1
		entity.record(item_id, 1.0, time)
		return true
	if entity.kind == "sink":
		entity.extra["received"] = int(entity.extra.get("received", 0)) + 1
		entity.extra["received_by_item"] = entity.extra.get("received_by_item", {})
		var sink_rates: Dictionary = entity.extra["received_by_item"]
		sink_rates[item_id] = int(sink_rates.get(item_id, 0)) + 1
		entity.record(item_id, 1.0, time)
		return true
	if entity.kind == "spire":
		var accepted: Array = ["hull_panel", "rotor"]
		if spire_stage >= 1:
			accepted.append("cable")
		if item_id not in accepted:
			entity.status = "Spire refuses %s" % Items.item_name(item_id)
			return false
		if not _valid_spire_port(entity, from_cell, item_id):
			return false
		entity.record(item_id, 1.0, time)
		entity.last_delivery_time[item_id] = time
		return true
	if entity.kind == "splitter":
		if from_cell != _back_port(entity):
			return false
		if _inventory_total(entity.input_buffer) >= 1:
			return false
		entity.input_buffer[item_id] = int(entity.input_buffer.get(item_id, 0)) + 1
		return true
	if entity.kind == "merger":
		if from_cell not in [entity.cell + _left(entity.rotation), _back_port(entity), entity.cell + _right(entity.rotation)]:
			return false
		var queues: Dictionary = entity.extra.get("merge_queues", {})
		var source_key: String = "%d,%d" % [from_cell.x, from_cell.y]
		if not queues.has(source_key):
			queues[source_key] = []
		if queues[source_key].size() >= 1:
			return false
		queues[source_key].append(item_id)
		entity.extra["merge_queues"] = queues
		return true
	if not _is_machine(entity.kind) or not _valid_input(entity, item_id):
		return false
	if from_cell not in _input_ports(entity):
		return false
	var max_input: int = 10
	if recipe_definitions.has(entity.recipe_id):
		var recipe: Dictionary = recipe_definitions[entity.recipe_id]
		max_input = maxi(10, int(recipe["inputs"].get(item_id, 0)) * 2)
	if int(entity.input_buffer.get(item_id, 0)) >= max_input:
		return false
	entity.input_buffer[item_id] = int(entity.input_buffer.get(item_id, 0)) + 1
	return true

func take_output(entity_id: int) -> Dictionary:
	if not entities.has(entity_id):
		return {}
	var entity: FactoryEntity = entities[entity_id]
	var taken: Dictionary = entity.output_buffer.duplicate(true)
	entity.output_buffer.clear()
	return taken

func insert_input(entity_id: int, item_id: String, amount: int) -> int:
	if not entities.has(entity_id) or amount <= 0:
		return 0
	var entity: FactoryEntity = entities[entity_id]
	var ports: Array[Vector2i] = _input_ports(entity)
	var accepted: int = 0
	for _i: int in range(amount):
		var inserted: bool = false
		for port: Vector2i in ports:
			if try_insert(entity_id, item_id, port):
				inserted = true
				break
		if not inserted:
			break
		accepted += 1
	return accepted

func to_dict() -> Dictionary:
	var saved_entities: Array[Dictionary] = []
	for entity: FactoryEntity in entities.values():
		saved_entities.append({
			"id": entity.id, "kind": entity.kind, "cell": [entity.cell.x, entity.cell.y],
			"rotation": entity.rotation, "recipe": entity.recipe_id,
			"input": entity.input_buffer.duplicate(true), "output": entity.output_buffer.duplicate(true),
			"items": entity.belt_items.duplicate(true), "progress": entity.progress,
			"extra": entity.extra.duplicate(true), "history": entity.rate_history.duplicate(true),
			"last_delivery": entity.last_delivery_time.duplicate(true)
		})
	return {"entities": saved_entities, "next_id": next_id, "time": time,
		"spire_progress": spire_progress.duplicate(), "spire_stage": spire_stage,
		"discovered_nodes": discovered_nodes.duplicate(true)}

func from_dict(data: Dictionary) -> void:
	entities.clear()
	grid.clear()
	time = float(data.get("time", 0.0))
	next_id = 1
	for saved: Dictionary in data.get("entities", []):
		var cell_data: Array = saved.get("cell", [0, 0])
		var cell: Vector2i = Vector2i(int(cell_data[0]), int(cell_data[1]))
		var saved_id: int = int(saved.get("id", next_id))
		var entity_id: int = add_entity(str(saved["kind"]), cell, int(saved.get("rotation", 0)), saved.get("extra", {}), saved_id)
		if entity_id < 0:
			continue
		var entity: FactoryEntity = entities[entity_id]
		entity.recipe_id = str(saved.get("recipe", ""))
		entity.input_buffer = _integer_dictionary(saved.get("input", {}))
		entity.output_buffer = _integer_dictionary(saved.get("output", {}))
		entity.belt_items.assign(saved.get("items", []))
		entity.progress = float(saved.get("progress", 0.0))
		entity.rate_history = saved.get("history", {}).duplicate(true)
		entity.last_delivery_time = saved.get("last_delivery", {}).duplicate(true)
		next_id = maxi(next_id, entity.id + 1)
	spire_progress.assign(data.get("spire_progress", [0.0, 0.0]))
	spire_stage = int(data.get("spire_stage", 0))
	discovered_nodes = data.get("discovered_nodes", {}).duplicate(true)
	next_id = maxi(next_id, int(data.get("next_id", next_id)))
	power.rebuild(entities)

func _update_belts(dt: float) -> void:
	for raw_id: Variant in entities:
		var belt: FactoryEntity = entities[raw_id]
		if not belt.kind.begins_with("belt_"):
			continue
		var speed: float = float(belt.extra.get("speed", 0.5))
		var item_index: int = 0
		while item_index < belt.belt_items.size():
			var item: Dictionary = belt.belt_items[item_index]
			if float(item.get("born_at", -INF)) >= time:
				item_index += 1
				continue
			var next_position: float = minf(1.0, float(item["pos"]) + speed * dt)
			if item_index > 0:
				next_position = minf(next_position, float(belt.belt_items[item_index - 1]["pos"]) - BELT_GAP)
			if next_position >= 1.0:
				var target_cell: Vector2i = belt.cell + _forward(belt.rotation)
				var target: FactoryEntity = entity_at(target_cell)
				if target != null and try_insert(target.id, str(item["item"]), belt.cell):
					belt.record(str(item["item"]), 1.0, time)
					belt.belt_items.remove_at(item_index)
					continue
				item["pos"] = 1.0
			else:
				item["pos"] = next_position
			item_index += 1

func _update_machines(dt: float) -> void:
	for raw_id: Variant in entities:
		var entity: FactoryEntity = entities[raw_id]
		if entity.kind == "source":
			_update_source(entity, dt)
		elif entity.kind == "sink":
			continue
		elif entity.kind == "miner_mk1":
			_update_miner(entity, dt)
		elif _is_machine(entity.kind):
			_update_machine(entity, dt)
		elif entity.kind == "splitter":
			_update_splitter(entity)
		elif entity.kind == "merger":
			_update_merger(entity)
		elif entity.kind == "storage":
			_update_storage(entity)

func _update_source(entity: FactoryEntity, dt: float) -> void:
	var rate: float = float(entity.extra.get("items_per_second", 1.0))
	entity.progress += dt * rate
	while entity.progress >= 1.0:
		var target: FactoryEntity = entity_at(_front_port(entity))
		if target == null or not try_insert(target.id, str(entity.extra.get("item", "iron_ore")), _output_from_cell(entity)):
			entity.progress = 1.0
			break
		entity.progress -= 1.0

func _update_miner(entity: FactoryEntity, dt: float) -> void:
	var node: Dictionary = entity.extra.get("node", {})
	if node.is_empty():
		entity.status = "No resource node"
		return
	var satisfaction_value: float = _satisfaction(entity)
	if satisfaction_value < 0.0:
		entity.status = "Not connected to power"
		return
	if satisfaction_value <= 0.0:
		entity.status = "No power"
		return
	var speed: float = float(node.get("rate", 60.0)) / 60.0
	entity.progress += dt * speed * satisfaction_value
	var target: FactoryEntity = entity_at(_front_port(entity))
	while entity.progress >= 1.0:
		if target == null or not try_insert(target.id, str(node.get("item", "iron_ore")), _output_from_cell(entity)):
			entity.progress = 1.0
			entity.status = "Output full"
			return
		entity.progress -= 1.0
		entity.record(str(node.get("item", "iron_ore")), 1.0, time)
	entity.status = "Running" if satisfaction_value >= 1.0 else "Low power (%d%%)" % roundi(satisfaction_value * 100.0)

func _update_machine(entity: FactoryEntity, dt: float) -> void:
	_push_outputs(entity)
	if entity.recipe_id.is_empty() or not recipe_definitions.has(entity.recipe_id):
		entity.status = "No recipe"
		return
	var recipe: Dictionary = recipe_definitions[entity.recipe_id]
	var missing: String = ""
	for item_id: String in recipe["inputs"]:
		if int(entity.input_buffer.get(item_id, 0)) < int(recipe["inputs"][item_id]):
			missing = item_id
			break
	if not missing.is_empty():
		entity.status = "Missing input: %s" % Items.item_name(missing)
		return
	var full: bool = false
	for item_id: String in recipe["outputs"]:
		var output_capacity: int = maxi(20, int(recipe["outputs"][item_id]) * 2)
		if int(entity.output_buffer.get(item_id, 0)) + int(recipe["outputs"][item_id]) > output_capacity:
			full = true
			break
	if full:
		entity.status = "Output full"
		return
	var satisfaction_value: float = _satisfaction(entity)
	if satisfaction_value < 0.0:
		entity.status = "Not connected to power"
		return
	if satisfaction_value <= 0.0:
		entity.status = "No power"
		return
	entity.progress += dt * satisfaction_value
	if entity.progress >= float(recipe["time"]):
		entity.progress -= float(recipe["time"])
		for item_id: String in recipe["outputs"]:
			var amount: int = int(recipe["outputs"][item_id])
			entity.output_buffer[item_id] = int(entity.output_buffer.get(item_id, 0)) + amount
			entity.record(item_id, float(amount), time)
		for item_id: String in recipe["inputs"]:
			entity.input_buffer[item_id] = int(entity.input_buffer[item_id]) - int(recipe["inputs"][item_id])
			entity.record(item_id, float(recipe["inputs"][item_id]), time)
	_push_outputs(entity)
	entity.status = "Running" if satisfaction_value >= 1.0 else "Low power (%d%%)" % roundi(satisfaction_value * 100.0)

func _update_splitter(entity: FactoryEntity) -> void:
	var outputs: Array[Vector2i] = [_left(entity.rotation), _forward(entity.rotation), _right(entity.rotation)]
	for item_id: String in entity.input_buffer.keys():
		if int(entity.input_buffer[item_id]) <= 0:
			continue
		for attempt: int in range(outputs.size()):
			var index: int = posmod(entity.splitter_cursor + attempt, outputs.size())
			var target_cell: Vector2i = entity.cell + outputs[index]
			var target: FactoryEntity = entity_at(target_cell)
			if target != null and try_insert(target.id, str(item_id), entity.cell):
				entity.input_buffer[item_id] = int(entity.input_buffer[item_id]) - 1
				entity.splitter_cursor = (index + 1) % outputs.size()
				break

func _update_merger(entity: FactoryEntity) -> void:
	var queues: Dictionary = entity.extra.get("merge_queues", {})
	var keys: Array = queues.keys()
	if keys.is_empty():
		return
	for attempt: int in range(keys.size()):
		var index: int = posmod(entity.merger_cursor + attempt, keys.size())
		var key: String = str(keys[index])
		var queue: Array = queues[key]
		if queue.is_empty():
			continue
		var target: FactoryEntity = entity_at(_front_port(entity))
		if target != null and try_insert(target.id, str(queue[0]), _output_from_cell(entity)):
			queue.pop_front()
			entity.merger_cursor = (index + 1) % keys.size()
			break

func _update_storage(entity: FactoryEntity) -> void:
	for item_id: String in entity.input_buffer:
		if int(entity.input_buffer[item_id]) <= 0:
			continue
		var target: FactoryEntity = entity_at(_front_port(entity))
		if target != null and try_insert(target.id, str(item_id), _output_from_cell(entity)):
			entity.input_buffer[item_id] = int(entity.input_buffer[item_id]) - 1
			break

func _update_spires(dt: float) -> void:
	for raw_id: Variant in entities:
		var entity: FactoryEntity = entities[raw_id]
		if entity.kind != "spire" or spire_stage >= milestone_definitions.size():
			continue
		var milestone: Dictionary = milestone_definitions[spire_stage]
		var all_met: bool = true
		for item_id: String in milestone["requirements"]:
			if entity.rate(item_id, time) + RATE_WINDOW_TOLERANCE < float(milestone["requirements"][item_id]):
				all_met = false
				break
		if all_met:
			spire_progress[spire_stage] += dt
			if spire_progress[spire_stage] >= float(milestone["duration"]):
				spire_stage += 1

func _satisfaction(entity: FactoryEntity) -> float:
	return power.satisfaction(entity.id, entities)

func _valid_input(entity: FactoryEntity, item_id: String) -> bool:
	if not recipe_definitions.has(entity.recipe_id):
		return false
	return recipe_definitions[entity.recipe_id]["inputs"].has(item_id)

func _is_machine(kind: String) -> bool:
	return kind in ["smelter", "constructor", "assembler"]

func _inventory_total(inventory: Dictionary) -> int:
	var total: int = 0
	for amount: Variant in inventory.values():
		total += int(amount)
	return total

func _integer_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source:
		result[str(key)] = int(source[key])
	return result

func _forward(rotation: int) -> Vector2i:
	return [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)][posmod(rotation, 4)]

func _left(rotation: int) -> Vector2i:
	return _forward(rotation + 3)

func _right(rotation: int) -> Vector2i:
	return _forward(rotation + 1)

func _front_port(entity: FactoryEntity) -> Vector2i:
	return _front_port_at(entity.kind, entity.cell, entity.rotation)

func _back_port(entity: FactoryEntity) -> Vector2i:
	return _back_port_at(entity.kind, entity.cell, entity.rotation)

func _input_ports(entity: FactoryEntity) -> Array[Vector2i]:
	var back: Vector2i = _back_port(entity)
	if entity.kind == "assembler":
		return [back - _left(entity.rotation), back + _left(entity.rotation)]
	return [back]

func _front_port_at(kind: String, cell: Vector2i, rotation: int) -> Vector2i:
	var size: Vector2i = _building_size(kind, rotation)
	if rotation == 0:
		return cell + Vector2i((size.x - 1) / 2, size.y)
	if rotation == 1:
		return cell + Vector2i(size.x, (size.y - 1) / 2)
	if rotation == 2:
		return cell + Vector2i((size.x - 1) / 2, -1)
	return cell + Vector2i(-1, (size.y - 1) / 2)

func _back_port_at(kind: String, cell: Vector2i, rotation: int) -> Vector2i:
	var size: Vector2i = _building_size(kind, rotation)
	var length: int = size.x if rotation % 2 == 1 else size.y
	return _front_port_at(kind, cell, rotation) - _forward(rotation) * (length + 1)

func _building_size(kind: String, rotation: int = 0) -> Vector2i:
	var size: Vector2i = building_definitions.get(kind, {}).get("size", Vector2i.ONE)
	return size if posmod(rotation, 2) == 0 else Vector2i(size.y, size.x)

func _valid_spire_port(entity: FactoryEntity, from_cell: Vector2i, item_id: String) -> bool:
	var local: Vector2i = from_cell - entity.cell
	if entity.rotation == 0:
		return local.y == 6 and local.x in [1, 4] or (item_id == "cable" and local.y == 6 and local.x in [2, 3])
	if entity.rotation == 1:
		return local.x == 6 and local.y in [1, 4] or (item_id == "cable" and local.x == 6 and local.y in [2, 3])
	if entity.rotation == 2:
		return local.y == -1 and local.x in [1, 4] or (item_id == "cable" and local.y == -1 and local.x in [2, 3])
	return local.x == -1 and local.y in [1, 4] or (item_id == "cable" and local.x == -1 and local.y in [2, 3])

func _push_outputs(entity: FactoryEntity) -> void:
	var target: FactoryEntity = entity_at(_front_port(entity))
	if target == null:
		return
	for item_id: String in entity.output_buffer:
		while int(entity.output_buffer[item_id]) > 0 and try_insert(target.id, item_id, _output_from_cell(entity)):
			entity.output_buffer[item_id] = int(entity.output_buffer[item_id]) - 1

func _output_from_cell(entity: FactoryEntity) -> Vector2i:
	return _front_port(entity) - _forward(entity.rotation)
