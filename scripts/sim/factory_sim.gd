extends RefCounted
class_name FactorySim

const RATE_WINDOW_TOLERANCE: float = 0.002
const BELT_GAP: float = 1.0
const BELT_MAX_LENGTH: float = 56.0
const EPSILON: float = 0.001

var entities: Dictionary = {}
var time: float = 0.0
var next_id: int = 1
var restore_failure_count: int = 0
var power: FactoryPower = FactoryPower.new()
var building_definitions: Dictionary = BuildingDefs.all()
var recipe_definitions: Dictionary = Recipes.all()
var milestone_definitions: Array[Dictionary] = Progression.milestones()
var spire_progress: Array[float] = [0.0, 0.0]
var spire_stage: int = 0
var discovered_nodes: Dictionary = {}
var nodes: Dictionary = {}
var vents: Dictionary = {}
var node_reservations: Dictionary = {}
var vent_reservations: Dictionary = {}
var port_links: Dictionary = {}

func register_node(node_id: int, item: String, purity: String, position: Vector3, rate: float = 60.0) -> void:
	nodes[node_id] = {"id": node_id, "item": item, "purity": purity, "position": position, "rate": rate}
	_rebuild_indexes()

func register_vent(vent_id: String, position: Vector3) -> void:
	vents[vent_id] = position
	_rebuild_indexes()

func check_place(kind: String, position: Vector3, yaw: float, node_id: int = -1) -> Dictionary:
	if not building_definitions.has(kind) or kind in ["belt_mk1", "belt_mk2"]:
		return {"ok": false, "reason": "Unknown building"}
	var requirement: String = str(building_definitions[kind].get("requires", ""))
	if requirement == "node":
		if node_id < 0 or not nodes.has(node_id):
			return {"ok": false, "reason": "Place a Miner here"}
		var node_position: Vector3 = nodes[node_id]["position"]
		if Vector2(position.x - node_position.x, position.z - node_position.z).length() > 1.5:
			return {"ok": false, "reason": "Place a Miner here"}
		if node_reservations.has(node_id):
			return {"ok": false, "reason": "Deposit already has an extractor"}
	elif requirement == "vent":
		var closest: String = ""
		var closest_distance: float = 1.5
		for vent_id: String in vents:
			var vent_position: Vector3 = vents[vent_id]
			var distance: float = Vector2(position.x - vent_position.x, position.z - vent_position.z).length()
			if distance <= closest_distance:
				closest = vent_id
				closest_distance = distance
		if closest.is_empty():
			return {"ok": false, "reason": "Place a Geo Tap on a vent"}
		if vent_reservations.has(closest):
			return {"ok": false, "reason": "Vent already has a tap"}
	for entity: FactoryEntity in entities.values():
		if _is_belt_segment(entity.kind):
			continue
		if _obb_overlap(position, yaw, BuildingDefs.size_of(kind), entity.position, entity.yaw, BuildingDefs.size_of(entity.kind)):
			return {"ok": false, "reason": "Blocked by %s" % entity.kind}
	return {"ok": true, "reason": ""}

func blocked_kind(position: Vector3, size: Vector3, yaw: float, ignored_ids: Array[int] = []) -> String:
	for entity: FactoryEntity in entities.values():
		if entity.id in ignored_ids or _is_belt_segment(entity.kind):
			continue
		if _obb_overlap(position, yaw, size, entity.position, entity.yaw, BuildingDefs.size_of(entity.kind)):
			return entity.kind
	return ""

func add_entity(kind: String, position: Vector3, yaw: float = 0.0, data: Dictionary = {}, forced_id: int = -1) -> int:
	var node_id: int = int(data.get("node_id", -1))
	var validation: Dictionary = check_place(kind, position, yaw, node_id)
	if not validation["ok"]:
		return -1
	var entity: FactoryEntity = SpireEntity.new() if kind == "spire" else MachineEntity.new()
	entity.id = forced_id if forced_id >= 0 else next_id
	if entities.has(entity.id):
		return -1
	next_id = maxi(next_id, entity.id + 1)
	entity.kind = kind
	entity.position = position
	entity.yaw = yaw
	entity.extra = data.duplicate(true)
	entity.recipe_id = str(data.get("recipe", ""))
	if not entity.recipe_id.is_empty():
		entity.extra["recipe_locked"] = true
	if entity.recipe_id.is_empty():
		entity.recipe_id = Recipes.default_for(kind)
		if not entity.recipe_id.is_empty():
			entity.extra["recipe_locked"] = false
	entity.cost = building_definitions[kind].get("cost", {}).duplicate(true)
	if kind == "miner_mk1":
		entity.extra["node_id"] = node_id
		entity.extra.erase("node")
	elif kind == "geo_tap":
		for vent_id: String in vents:
			var vent_position: Vector3 = vents[vent_id]
			if Vector2(position.x - vent_position.x, position.z - vent_position.z).length() <= 1.5:
				entity.extra["vent_id"] = vent_id
				break
	entities[entity.id] = entity
	_rebuild_indexes()
	power.rebuild(entities)
	return entity.id

func set_recipe(entity_id: int, recipe_id: String, locked: bool = true) -> bool:
	if not entities.has(entity_id):
		return false
	var entity: FactoryEntity = entities[entity_id]
	var recipe: Dictionary = recipe_definitions.get(recipe_id, {})
	if not _is_machine(entity.kind) or recipe.is_empty() or str(recipe.get("machine", "")) != entity.kind:
		return false
	entity.extra["recipe_locked"] = locked
	if entity.recipe_id != recipe_id:
		entity.recipe_id = recipe_id
		entity.extra.erase("input_mismatch")
		entity.progress = 0.0
	return true

func add_belt(kind: String, from_id: int, from_port: String, to_id: int, to_port: String,
		curve: PackedVector3Array, extra: Dictionary = {}) -> Dictionary:
	if kind not in ["belt_mk1", "belt_mk2"]:
		return {"id": -1, "reason": "Unknown belt type"}
	if not entities.has(from_id) or not entities.has(to_id) or from_id == to_id:
		return {"id": -1, "reason": "Invalid belt endpoints"}
	var source_port: Dictionary = _port_for(from_id, from_port)
	var target_port: Dictionary = _port_for(to_id, to_port)
	if source_port.is_empty() or target_port.is_empty() or source_port["dir"] != "out" or target_port["dir"] != "in":
		return {"id": -1, "reason": "Can't connect output to output"}
	if port_links.has(_port_key(from_id, from_port)) or port_links.has(_port_key(to_id, to_port)):
		return {"id": -1, "reason": "Port already connected"}
	if curve.size() != 4:
		return {"id": -1, "reason": "Belt requires four Bézier points"}
	var start: Dictionary = port_world(from_id, from_port)
	var finish: Dictionary = port_world(to_id, to_port)
	if curve[0].distance_to(start["pos"]) > 0.05 or curve[3].distance_to(finish["pos"]) > 0.05:
		return {"id": -1, "reason": "Belt curve endpoints must match ports"}
	var length: float = _curve_length(curve)
	if length < 0.5 or length > BELT_MAX_LENGTH:
		return {"id": -1, "reason": "Belt length must be 0.5–56 m"}
	var belt: BeltEntity = BeltEntity.new()
	belt.id = next_id
	next_id += 1
	belt.kind = kind
	belt.position = curve[0]
	belt.yaw = 0.0
	belt.extra = {"from": {"id": from_id, "port": from_port}, "to": {"id": to_id, "port": to_port},
		"curve": curve, "length": length, "speed": 2.0 if kind == "belt_mk2" else 1.0}
	belt.extra.merge(extra, true)
	belt.cost = {}
	entities[belt.id] = belt
	_rebuild_indexes()
	return {"id": belt.id, "reason": ""}

func port_world(entity_id: int, port_id: String) -> Dictionary:
	if not entities.has(entity_id):
		return {}
	var entity: FactoryEntity = entities[entity_id]
	var definition: Dictionary = _port_for(entity_id, port_id)
	if definition.is_empty():
		return {}
	var transform_basis: Basis = Basis(Vector3.UP, entity.yaw)
	return {"pos": entity.position + transform_basis * definition["pos"], "normal": (transform_basis * definition["normal"]).normalized()}

func is_port_free(entity_id: int, port_id: String) -> bool:
	return entities.has(entity_id) and not _port_for(entity_id, port_id).is_empty() and not port_links.has(_port_key(entity_id, port_id))

func try_push_from_port(entity_id: int, port_id: String, item_id: String) -> bool:
	if not port_links.has(_port_key(entity_id, port_id)):
		return false
	var belt: FactoryEntity = entities.get(int(port_links[_port_key(entity_id, port_id)]))
	if belt == null:
		return false
	for item: Dictionary in belt.belt_items:
		if float(item["s"]) < BELT_GAP:
			return false
	belt.belt_items.append({"item": item_id, "s": 0.0, "born_at": time})
	return true

func try_insert(entity_id: int, item_id: String, port_id: String) -> bool:
	if not entities.has(entity_id):
		return false
	var entity: FactoryEntity = entities[entity_id]
	var definition: Dictionary = _port_for(entity_id, port_id)
	if definition.is_empty() or definition["dir"] != "in":
		return false
	if entity.kind == "belt_pole":
		if not entity.input_buffer.is_empty():
			return false
		entity.input_buffer[item_id] = 1
		return true
	if entity.kind == "storage":
		if _inventory_total(entity.input_buffer) >= 1000:
			return false
		entity.input_buffer[item_id] = int(entity.input_buffer.get(item_id, 0)) + 1
		entity.record(item_id, 1.0, time)
		return true
	if entity.kind == "splitter":
		if port_id != "in0" or _inventory_total(entity.input_buffer) >= 1:
			return false
		entity.input_buffer[item_id] = 1
		return true
	if entity.kind == "merger":
		var queues: Dictionary = entity.extra.get("merge_queues", {})
		var queue: Array = queues.get(port_id, [])
		if not queues.has(port_id):
			queues[port_id] = queue
		if queue.size() >= 1:
			return false
		queue.append(item_id)
		entity.extra["merge_queues"] = queues
		return true
	if entity.kind == "spire":
		if item_id not in ["hull_panel", "rotor", "cable"] or (item_id == "cable" and spire_stage < 1):
			return false
		entity.record(item_id, 1.0, time)
		entity.last_delivery_time[item_id] = time
		return true
	if entity.kind in ["source", "sink"]:
		entity.record(item_id, 1.0, time)
		if entity.kind == "sink":
			entity.extra["received"] = int(entity.extra.get("received", 0)) + 1
			entity.input_buffer[item_id] = int(entity.input_buffer.get(item_id, 0)) + 1
		return true
	if not _is_machine(entity.kind):
		return false
	if not _valid_input(entity, item_id):
		if bool(entity.extra.get("recipe_locked", false)):
			entity.extra["input_mismatch"] = item_id
			entity.status = _input_recipe_mismatch(entity, item_id)
			return false
		if _inventory_total(entity.input_buffer) > 0 or _inventory_total(entity.output_buffer) > 0:
			return false
		var compatible_recipe: String = ""
		for recipe_id: String in Recipes.for_machine(entity.kind):
			var candidate: Dictionary = recipe_definitions.get(recipe_id, {})
			if candidate.get("inputs", {}).has(item_id):
				compatible_recipe = recipe_id
				break
		if compatible_recipe.is_empty():
			return false
		entity.recipe_id = compatible_recipe
		entity.progress = 0.0
	var recipe: Dictionary = recipe_definitions[entity.recipe_id]
	var maximum: int = input_capacity(entity_id, item_id)
	if int(entity.input_buffer.get(item_id, 0)) >= maximum:
		return false
	entity.input_buffer[item_id] = int(entity.input_buffer.get(item_id, 0)) + 1
	return true

func insert_input(entity_id: int, item_id: String, quantity: int) -> int:
	if quantity <= 0 or not entities.has(entity_id):
		return 0
	var entity: FactoryEntity = entities[entity_id]
	if entity.kind == "storage":
		return insert_storage_item(entity_id, item_id, quantity)
	var input_ports: Array[String] = []
	for port: Dictionary in building_definitions.get(entity.kind, {}).get("ports", []):
		if str(port.get("dir", "")) == "in":
			input_ports.append(str(port.get("id", "")))
	var inserted: int = 0
	while inserted < quantity:
		var accepted: bool = false
		for port_id: String in input_ports:
			if try_insert(entity_id, item_id, port_id):
				accepted = true
				break
		if not accepted:
			break
		inserted += 1
	return inserted

func insert_input_items(entity_id: int, item_id: String, quantity: int) -> int:
	if quantity <= 0 or item_id.is_empty() or not entities.has(entity_id):
		return 0
	if not _is_machine(str(entities[entity_id].kind)):
		return 0
	return insert_input(entity_id, item_id, quantity)

func input_capacity(entity_id: int, item_id: String) -> int:
	if item_id.is_empty() or not entities.has(entity_id):
		return 0
	var entity: FactoryEntity = entities[entity_id]
	if not _is_machine(entity.kind):
		return 0
	var recipe: Dictionary = recipe_definitions.get(entity.recipe_id, {})
	var inputs: Dictionary = recipe.get("inputs", {})
	if not inputs.has(item_id):
		return 0
	return maxi(10, int(inputs[item_id]) * 2)

func output_capacity(entity_id: int, item_id: String) -> int:
	if item_id.is_empty() or not entities.has(entity_id):
		return 0
	var entity: FactoryEntity = entities[entity_id]
	if not _is_machine(entity.kind) and entity.kind != "miner_mk1":
		return 0
	if entity.kind == "miner_mk1":
		var node_id: int = int(entity.extra.get("node_id", -1))
		var node: Dictionary = nodes.get(node_id, {})
		if str(node.get("item", "")) != item_id \
				and not entity.output_buffer.has(item_id):
			return 0
	elif not entity.output_buffer.has(item_id) \
			and not recipe_definitions.get(entity.recipe_id, {}).get("outputs", {}).has(item_id):
		return 0
	return 20

func take_storage(entity_id: int) -> Dictionary:
	if not entities.has(entity_id) or entities[entity_id].kind != "storage":
		return {}
	var result: Dictionary = entities[entity_id].input_buffer.duplicate(true)
	entities[entity_id].input_buffer.clear()
	return result

func take_storage_item(entity_id: int, item_id: String, quantity: int) -> int:
	if quantity <= 0 or not entities.has(entity_id) or entities[entity_id].kind != "storage":
		return 0
	var storage: FactoryEntity = entities[entity_id]
	var moved: int = mini(quantity, int(storage.input_buffer.get(item_id, 0)))
	if moved <= 0:
		return 0
	storage.input_buffer[item_id] = int(storage.input_buffer[item_id]) - moved
	if int(storage.input_buffer[item_id]) <= 0:
		storage.input_buffer.erase(item_id)
	return moved

func insert_storage_item(entity_id: int, item_id: String, quantity: int) -> int:
	if quantity <= 0 or item_id.is_empty() or not entities.has(entity_id) \
			or entities[entity_id].kind != "storage":
		return 0
	var storage: FactoryEntity = entities[entity_id]
	var space: int = maxi(0, 1000 - _inventory_total(storage.input_buffer))
	var moved: int = mini(quantity, space)
	if moved <= 0:
		return 0
	storage.input_buffer[item_id] = int(storage.input_buffer.get(item_id, 0)) + moved
	return moved

func take_output_item(entity_id: int, item_id: String, quantity: int) -> int:
	if quantity <= 0 or not entities.has(entity_id):
		return 0
	var entity: FactoryEntity = entities[entity_id]
	var moved: int = mini(quantity, int(entity.output_buffer.get(item_id, 0)))
	if moved <= 0:
		return 0
	entity.output_buffer[item_id] = int(entity.output_buffer[item_id]) - moved
	if int(entity.output_buffer[item_id]) <= 0:
		entity.output_buffer.erase(item_id)
	return moved

func take_output_items(entity_id: int, item_id: String, quantity: int) -> int:
	return take_output_item(entity_id, item_id, quantity)

func insert_output_items(entity_id: int, item_id: String, quantity: int) -> int:
	if quantity <= 0 or item_id.is_empty() or not entities.has(entity_id):
		return 0
	var capacity: int = output_capacity(entity_id, item_id)
	if capacity <= 0:
		return 0
	var entity: FactoryEntity = entities[entity_id]
	var current: int = int(entity.output_buffer.get(item_id, 0))
	var moved: int = mini(quantity, maxi(0, capacity - current))
	if moved > 0:
		entity.output_buffer[item_id] = current + moved
	return moved

func take_output(entity_id: int) -> Dictionary:
	if not entities.has(entity_id):
		return {}
	var result: Dictionary = entities[entity_id].output_buffer.duplicate(true)
	entities[entity_id].output_buffer.clear()
	return result

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	time += dt
	power.update_demand(entities)
	for entity: FactoryEntity in entities.values():
		if _is_machine(entity.kind):
			entity.extra.erase("input_mismatch")
	_update_belts(dt)
	_update_machines(dt)
	_update_spires(dt)
	for entity: FactoryEntity in entities.values():
		entity.prune_rates(time)

func status_for(entity_id: int) -> String:
	return str(entities[entity_id].status) if entities.has(entity_id) else "Stopped"

func get_rate(entity_id: int, item_id: String) -> float:
	return entities[entity_id].rate(item_id, time) if entities.has(entity_id) else 0.0

func diagnostics(entity_id: int) -> Array[String]:
	var result: Array[String] = []
	if not entities.has(entity_id):
		return result
	var entity: FactoryEntity = entities[entity_id]
	result.append(_power_diagnostic(entity))
	var mismatch_item: String = str(entity.extra.get("input_mismatch", ""))
	if not mismatch_item.is_empty():
		result.append(_input_recipe_mismatch(entity, mismatch_item))
	if not recipe_definitions.has(entity.recipe_id):
		return result
	var recipe: Dictionary = recipe_definitions[entity.recipe_id]
	for item: String in recipe["inputs"]:
		result.append("Input %s: %.1f/min — needs %.1f/min" % [Items.item_name(item), entity.rate(item, time), float(recipe["inputs"][item]) * 60.0 / float(recipe["time"])])
	for item: String in recipe["outputs"]:
		result.append("Output %s: %.1f/min (max %.1f)" % [Items.item_name(item), entity.rate(item, time), float(recipe["outputs"][item]) * 60.0 / float(recipe["time"])])
	return result

func machine_view(entity_id: int) -> Dictionary:
	if not entities.has(entity_id):
		return {}
	var entity: FactoryEntity = entities[entity_id]
	if not _is_machine(entity.kind) and entity.kind != "miner_mk1":
		return {}
	var recipe: Dictionary = recipe_definitions.get(entity.recipe_id, {})
	var recipe_inputs: Dictionary = recipe.get("inputs", {})
	var recipe_outputs: Dictionary = recipe.get("outputs", {})
	var cycle_seconds: float = float(recipe.get("time", 0.0))
	var input_items: Array[Dictionary] = []
	var output_items: Array[Dictionary] = []
	var max_input_slots: int = recipe_inputs.size()
	var possible_output_ids: Dictionary = {}
	for item_variant: Variant in recipe_outputs:
		possible_output_ids[str(item_variant)] = true
	for recipe_id: String in Recipes.for_machine(entity.kind):
		var other_recipe: Dictionary = recipe_definitions.get(recipe_id, {})
		max_input_slots = maxi(max_input_slots, other_recipe.get("inputs", {}).size())
		for item_variant: Variant in other_recipe.get("outputs", {}):
			possible_output_ids[str(item_variant)] = true
	var max_output_slots: int = possible_output_ids.size()
	var maximum_rate: float = 0.0
	for item_variant: Variant in recipe_inputs:
		var item_id: String = str(item_variant)
		var recipe_count: int = int(recipe_inputs[item_variant])
		input_items.append({
			"item_id": item_id,
			"count": int(entity.input_buffer.get(item_id, 0)),
			"maximum": input_capacity(entity_id, item_id),
			"needs_per_min": float(recipe_count) * 60.0 / maxf(cycle_seconds, 0.001),
			"getting_per_min": entity.rate(item_id, time)
		})
	var output_item_ids: Array[String] = []
	for item_variant: Variant in recipe_outputs:
		output_item_ids.append(str(item_variant))
	for item_variant: Variant in entity.output_buffer:
		if str(item_variant) not in output_item_ids:
			output_item_ids.append(str(item_variant))
	for item_id: String in output_item_ids:
		var recipe_count: int = int(recipe_outputs.get(item_id, 0))
		output_items.append({
			"item_id": item_id,
			"count": int(entity.output_buffer.get(item_id, 0)),
			"maximum": output_capacity(entity_id, item_id),
			"per_min": float(recipe_count) * 60.0 / maxf(cycle_seconds, 0.001)
		})
		maximum_rate += float(recipe_count) * 60.0 / maxf(cycle_seconds, 0.001)
	var deposit: Dictionary = {}
	if entity.kind == "miner_mk1":
		var node_id: int = int(entity.extra.get("node_id", -1))
		if nodes.has(node_id):
			deposit = (nodes[node_id] as Dictionary).duplicate(true)
		cycle_seconds = 60.0 / maxf(float(deposit.get("rate", 0.0)), 0.001)
		maximum_rate = float(deposit.get("rate", 0.0))
		output_items.clear()
		var deposit_item: String = str(deposit.get("item", ""))
		if not deposit_item.is_empty():
			output_items.append({
				"item_id": deposit_item,
				"count": int(entity.output_buffer.get(deposit_item, 0)),
				"maximum": output_capacity(entity_id, deposit_item),
				"per_min": maximum_rate
			})
	var current_rate: float = 0.0
	if entity.kind == "miner_mk1":
		current_rate = entity.rate(str(deposit.get("item", "")), time)
	else:
		for item_variant: Variant in recipe_outputs:
			current_rate += entity.rate(str(item_variant), time)
	var satisfaction: float = power.satisfaction(entity_id, entities)
	var network_id: int = int(power.network_for.get(entity_id, -1))
	var power_need: float = float(building_definitions.get(entity.kind, {}).get("power", 0.0))
	var supply: float = float(power.supply_for.get(network_id, 0.0))
	var demand: float = float(power.demand_for.get(network_id, 0.0))
	var status_text: String = str(entity.status)
	var state: String = "idle"
	var display_status: String = "Idle"
	if status_text.begins_with("No power"):
		state = "no_power"
		display_status = "No power"
	elif status_text == "Output full":
		state = "output_full"
		display_status = "Output full"
	elif status_text.begins_with("Missing input") or status_text == "No resource node":
		state = "waiting_input"
		display_status = "Waiting for input"
	elif status_text.begins_with("Low power"):
		state = "low_power"
		display_status = status_text
	elif status_text == "Running":
		state = "running"
		display_status = "Running"
	elif status_text == "No recipe":
		display_status = "No recipe"
	var why_lines: Array[String] = diagnostics(entity_id)
	var progress_ratio: float = 0.0
	if entity.kind == "miner_mk1":
		progress_ratio = clampf(entity.progress, 0.0, 1.0)
	elif cycle_seconds > 0.0:
		progress_ratio = clampf(entity.progress / cycle_seconds, 0.0, 1.0)
	var power_state: String = "Free power (dev bypass)" if power.bypass else \
		("No connected network" if network_id < 0 else
			"Network %d · %.1f / %.1f MW" % [network_id, supply, demand])
	return {
		"entity_id": entity_id,
		"kind": entity.kind,
		"name": entity.kind.replace("_", " ").capitalize(),
		"status": status_text,
		"display_status": display_status,
		"state": state,
		"recipe_id": entity.recipe_id,
		"recipe_locked": bool(entity.extra.get("recipe_locked", false)),
		"recipes": _machine_recipe_options(entity),
		"inputs": input_items,
		"outputs": output_items,
		"input_slot_count": max_input_slots if entity.kind != "miner_mk1" else 0,
		"output_slot_count": max_output_slots,
		"output_buffer": entity.output_buffer.duplicate(true),
		"progress": progress_ratio,
		"cycle_seconds": cycle_seconds,
		"current_rate": current_rate,
		"maximum_rate": maximum_rate,
		"efficiency": clampf(current_rate / maximum_rate * 100.0, 0.0, 100.0)
			if maximum_rate > 0.0 else 0.0,
		"power_draw_mw": power_need * maxf(0.0, satisfaction),
		"power_need_mw": power_need,
		"power_state": power_state,
		"power_satisfaction": maxf(0.0, satisfaction),
		"power_bypassed": power.bypass,
		"deposit_item": str(deposit.get("item", "")),
		"deposit_purity": str(deposit.get("purity", "")),
		"deposit_rate": float(deposit.get("rate", 0.0)),
		"why": " · ".join(why_lines) if not why_lines.is_empty() else status_text
	}

func _machine_recipe_options(entity: FactoryEntity) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for recipe_id: String in Recipes.for_machine(entity.kind):
		var label: String = recipe_id.replace("_", " ").capitalize()
		if recipe_id == entity.recipe_id and not bool(entity.extra.get("recipe_locked", false)):
			label += " (auto)"
		options.append({"id": recipe_id, "label": label})
	return options

func _power_diagnostic(entity: FactoryEntity) -> String:
	var need: float = float(building_definitions.get(entity.kind, {}).get("power", 0.0))
	if power.bypass:
		return "Power: bypassed (would need %.0f MW)" % need
	var network: int = int(power.network_for.get(entity.id, -1))
	var supply: float = float(power.supply_for.get(network, 0.0))
	var demand: float = float(power.demand_for.get(network, 0.0))
	var satisfaction: float = power.satisfaction(entity.id, entities)
	if satisfaction <= 0.0:
		return "No power: needs %.0f MW, network supplies %.0f MW" % [need, supply]
	return "Power: %.0f / %.0f MW network · %d%% satisfaction" % [
		supply, demand, roundi(satisfaction * 100.0)]

func preview_refund(entity_id: int) -> Dictionary:
	return _build_refund_preview(entity_id).get("refund", {})

func remove_entity_with_refund(entity_id: int, world_items: Dictionary = {}) -> Dictionary:
	if not entities.has(entity_id):
		return {}
	var preview: Dictionary = _build_refund_preview(entity_id)
	_add_items(world_items, preview.get("world_items", {}))
	for remove_id: int in preview.get("remove_ids", []):
		entities.erase(remove_id)
	_rebuild_indexes()
	power.rebuild(entities)
	return preview.get("refund", {})

func _build_refund_preview(entity_id: int) -> Dictionary:
	if not entities.has(entity_id):
		return {"refund": {}, "world_items": {}, "remove_ids": []}
	var remove_ids: Array[int] = [entity_id]
	for belt: FactoryEntity in entities.values():
		if _is_belt_segment(belt.kind) and (int(belt.extra["from"]["id"]) == entity_id or int(belt.extra["to"]["id"]) == entity_id):
			remove_ids.append(belt.id)
	var refund: Dictionary = {}
	var world_items: Dictionary = {}
	for remove_id: int in remove_ids:
		var entity: FactoryEntity = entities.get(remove_id)
		if entity == null:
			continue
		if _is_belt_segment(entity.kind):
			var count: int = ceili(float(entity.extra.get("length", 0.0)) / 2.0)
			if not bool(entity.extra.get("creative_built", false)):
				_add_items(refund, {"iron_plate": count})
				if entity.kind == "belt_mk2":
					_add_items(refund, {"screw": count * 2})
			for item: Dictionary in entity.belt_items:
				var item_id: String = str(item["item"])
				_add_items(refund, {item_id: 1})
				_add_items(world_items, {item_id: 1})
		else:
			if not bool(entity.extra.get("creative_built", false)):
				_add_items(refund, entity.cost)
			_add_items(refund, entity.input_buffer)
			_add_items(refund, entity.output_buffer)
			_add_items(world_items, entity.input_buffer)
			_add_items(world_items, entity.output_buffer)
			for queue: Array in entity.extra.get("merge_queues", {}).values():
				for item_id: String in queue:
					_add_items(refund, {item_id: 1})
					_add_items(world_items, {item_id: 1})
	return {"refund": refund, "world_items": world_items, "remove_ids": remove_ids}

func remove_entity(entity_id: int) -> FactoryEntity:
	if not entities.has(entity_id):
		return null
	var removed: FactoryEntity = entities[entity_id]
	entities.erase(entity_id)
	_rebuild_indexes()
	power.rebuild(entities)
	return removed

func to_dict() -> Dictionary:
	var saved: Array[Dictionary] = []
	for entity: FactoryEntity in entities.values():
		var extra: Dictionary = entity.extra.duplicate(true)
		if extra.get("curve") is PackedVector3Array:
			var encoded_curve: Array = []
			for point: Vector3 in extra["curve"]:
				encoded_curve.append([point.x, point.y, point.z])
			extra["curve"] = encoded_curve
		saved.append({"id": entity.id, "kind": entity.kind, "position": [entity.position.x, entity.position.y, entity.position.z],
			"yaw": entity.yaw, "recipe": entity.recipe_id, "input": entity.input_buffer.duplicate(true),
			"output": entity.output_buffer.duplicate(true), "items": entity.belt_items.duplicate(true),
			"progress": entity.progress, "extra": extra, "history": entity.rate_history.duplicate(true),
			"last_delivery": entity.last_delivery_time.duplicate(true)})
	return {"entities": saved, "next_id": next_id, "time": time, "spire_progress": spire_progress.duplicate(),
		"spire_stage": spire_stage, "discovered_nodes": discovered_nodes.duplicate(true)}

func from_dict(data: Dictionary) -> Dictionary:
	entities.clear()
	node_reservations.clear()
	vent_reservations.clear()
	port_links.clear()
	restore_failure_count = 0
	time = float(data.get("time", 0.0))
	next_id = int(data.get("next_id", 1))
	var refund: Dictionary = {}
	var saved_entities: Array = data.get("entities", [])
	var restore_order: Array[Dictionary] = []
	for saved: Dictionary in saved_entities:
		if str(saved.get("kind", "")) != "miner_mk1":
			restore_order.append(saved)
	for saved: Dictionary in saved_entities:
		if str(saved.get("kind", "")) == "miner_mk1":
			restore_order.append(saved)
	for saved: Dictionary in restore_order:
		var kind: String = str(saved["kind"])
		if _is_belt_segment(kind) and saved.has("position"):
			var saved_position: Array = saved["position"]
			var belt_entity: BeltEntity = BeltEntity.new()
			belt_entity.id = int(saved["id"])
			belt_entity.kind = kind
			belt_entity.position = Vector3(float(saved_position[0]), float(saved_position[1]), float(saved_position[2]))
			belt_entity.yaw = float(saved.get("yaw", 0.0))
			belt_entity.extra = saved.get("extra", {}).duplicate(true)
			var points: PackedVector3Array = PackedVector3Array()
			for point: Variant in belt_entity.extra.get("curve", []):
				points.append(Vector3(float(point[0]), float(point[1]), float(point[2])) if point is Array else point)
			belt_entity.extra["curve"] = points
			belt_entity.belt_items.assign(saved.get("items", []))
			entities[belt_entity.id] = belt_entity
			next_id = maxi(next_id, belt_entity.id + 1)
			continue
		if _is_belt_segment(kind) and not saved.has("position"):
			var items: Array = saved.get("items", saved.get("belt_items", []))
			for item: Dictionary in items:
				_add_items(refund, {str(item["item"]): 1})
			_add_items(refund, {"iron_plate": 1})
			continue
		var position: Vector3
		var yaw: float
		var extra: Dictionary = saved.get("extra", {}).duplicate(true)
		if saved.has("position"):
			var p: Array = saved["position"]
			position = Vector3(float(p[0]), float(p[1]), float(p[2]))
			yaw = float(saved.get("yaw", 0.0))
		else:
			var c: Array = saved.get("cell", [0, 0])
			var cell := Vector2i(int(c[0]), int(c[1]))
			var size: Vector3 = BuildingDefs.size_of(kind)
			var old_rotation: int = int(saved.get("rotation", 0))
			var world_size: Vector2 = Vector2(size.x, size.z) if posmod(old_rotation, 2) == 0 else Vector2(size.z, size.x)
			position = Vector3(float(cell.x) * 2.0 + world_size.x * 0.5, 0.0, float(cell.y) * 2.0 + world_size.y * 0.5)
			yaw = float(old_rotation) * PI / 2.0
			if kind == "miner_mk1":
				var nearest: int = _nearest_migration_node(position, extra)
				if nearest >= 0:
					extra["node_id"] = nearest
					position = nodes[nearest]["position"]
		var entity_id: int = add_entity(kind, position, yaw, extra, int(saved.get("id", -1)))
		if entity_id < 0:
			_refund_unrestored_entity(kind, saved, refund)
			restore_failure_count += 1
			continue
		var entity: FactoryEntity = entities[entity_id]
		var saved_recipe: String = str(saved.get("recipe", ""))
		if not saved_recipe.is_empty():
			entity.recipe_id = saved_recipe
			entity.extra["recipe_locked"] = bool(extra.get("recipe_locked", true))
		entity.input_buffer = _int_dict(saved.get("input", saved.get("input_buffer", {})))
		entity.output_buffer = _int_dict(saved.get("output", saved.get("output_buffer", {})))
		entity.belt_items.assign(saved.get("items", saved.get("belt_items", [])))
		for item: Dictionary in entity.belt_items:
			if item.has("pos"):
				item["s"] = float(item["pos"]) * float(entity.extra.get("length", 2.0))
				item.erase("pos")
		entity.progress = float(saved.get("progress", 0.0))
		entity.extra.merge(saved.get("extra", {}), true)
		entity.rate_history = saved.get("history", {}).duplicate(true)
		entity.last_delivery_time = saved.get("last_delivery", {}).duplicate(true)
	spire_progress.assign(data.get("spire_progress", [0.0, 0.0]))
	spire_stage = int(data.get("spire_stage", 0))
	discovered_nodes = data.get("discovered_nodes", {}).duplicate(true)
	_rebuild_indexes()
	power.rebuild(entities)
	return refund

func _update_belts(dt: float) -> void:
	for belt: FactoryEntity in entities.values():
		if not _is_belt_segment(belt.kind):
			continue
		var curve: PackedVector3Array = belt.extra["curve"]
		var length: float = float(belt.extra["length"])
		for index: int in range(belt.belt_items.size()):
			var item: Dictionary = belt.belt_items[index]
			if float(item.get("born_at", -INF)) >= time:
				continue
			var next_s: float = minf(length, float(item["s"]) + float(belt.extra["speed"]) * dt)
			if index > 0:
				next_s = minf(next_s, float(belt.belt_items[index - 1]["s"]) - BELT_GAP)
			if next_s >= length:
				var target: Dictionary = belt.extra["to"]
				if try_insert(int(target["id"]), str(item["item"]), str(target["port"])):
					belt.record(str(item["item"]), 1.0, time)
					belt.belt_items.remove_at(index)
					break
				item["s"] = length
			else:
				item["s"] = next_s

func _update_machines(dt: float) -> void:
	for entity: FactoryEntity in entities.values():
		if entity.kind == "belt_pole":
			for item_variant: Variant in entity.input_buffer.keys():
				var item_id: String = str(item_variant)
				var count: int = int(entity.input_buffer[item_id])
				if count <= 0:
					entity.input_buffer.erase(item_id)
					continue
				if try_push_from_port(entity.id, "out0", item_id):
					count -= 1
					if count == 0:
						entity.input_buffer.erase(item_id)
					else:
						entity.input_buffer[item_id] = count
					break
		elif entity.kind == "miner_mk1":
			_update_miner(entity, dt)
		elif entity.kind == "geo_tap":
			var vent_id: String = str(entity.extra.get("vent_id", ""))
			entity.status = "Running" if vents.has(vent_id) else "Stopped"
		elif _is_machine(entity.kind):
			_update_machine(entity, dt)
			var mismatch_item: String = str(entity.extra.get("input_mismatch", ""))
			if not mismatch_item.is_empty():
				entity.status = _input_recipe_mismatch(entity, mismatch_item)
		elif entity.kind == "splitter":
			_update_splitter(entity)
		elif entity.kind == "merger":
			_update_merger(entity)
		elif entity.kind == "storage":
			_update_storage(entity)

func _update_miner(entity: FactoryEntity, dt: float) -> void:
	var node_id: int = int(entity.extra.get("node_id", -1))
	if node_id < 0 or not nodes.has(node_id):
		entity.status = "No resource node"
		return
	var sat: float = power.satisfaction(entity.id, entities)
	if sat <= 0.0:
		entity.status = _power_diagnostic(entity)
		return
	var node: Dictionary = nodes[node_id]
	entity.progress += dt * float(node["rate"]) / 60.0 * sat
	while entity.progress >= 1.0:
		if not try_push_from_port(entity.id, "out0", str(node["item"])):
			entity.status = "Output full"
			return
		entity.progress -= 1.0
		entity.record(str(node["item"]), 1.0, time)
	entity.status = "Running" if sat >= 1.0 else "Low power (%d%%)" % roundi(sat * 100.0)

func _update_machine(entity: FactoryEntity, dt: float) -> void:
	_push_outputs(entity)
	if not recipe_definitions.has(entity.recipe_id):
		entity.status = "No recipe"
		return
	var recipe: Dictionary = recipe_definitions[entity.recipe_id]
	for item_id: String in recipe["inputs"]:
		if int(entity.input_buffer.get(item_id, 0)) < int(recipe["inputs"][item_id]):
			entity.status = "Missing input: %s" % Items.item_name(item_id)
			return
	for item_id: String in recipe["outputs"]:
		if int(entity.output_buffer.get(item_id, 0)) + int(recipe["outputs"][item_id]) \
				> output_capacity(entity.id, item_id):
			entity.status = "Output full"
			return
	var sat: float = power.satisfaction(entity.id, entities)
	if sat <= 0.0:
		entity.status = _power_diagnostic(entity)
		return
	entity.progress += dt * sat
	if entity.progress >= float(recipe["time"]):
		entity.progress -= float(recipe["time"])
		for item_id: String in recipe["inputs"]:
			entity.input_buffer[item_id] = int(entity.input_buffer[item_id]) - int(recipe["inputs"][item_id])
		for item_id: String in recipe["outputs"]:
			var count: int = int(recipe["outputs"][item_id])
			entity.output_buffer[item_id] = int(entity.output_buffer.get(item_id, 0)) + count
			entity.record(item_id, count, time)
		_push_outputs(entity)
	entity.status = "Running" if sat >= 1.0 else "Low power (%d%%)" % roundi(sat * 100.0)

func _push_outputs(entity: FactoryEntity) -> void:
	for item_id: String in entity.output_buffer:
		while int(entity.output_buffer[item_id]) > 0 and try_push_from_port(entity.id, "out0", item_id):
			entity.output_buffer[item_id] = int(entity.output_buffer[item_id]) - 1

func _update_splitter(entity: FactoryEntity) -> void:
	var ports: Array[String] = ["out0", "out1", "out2"]
	for item_id: String in entity.input_buffer:
		if int(entity.input_buffer[item_id]) <= 0:
			continue
		for offset: int in range(ports.size()):
			var index: int = posmod(entity.splitter_cursor + offset, ports.size())
			if try_push_from_port(entity.id, ports[index], item_id):
				entity.input_buffer[item_id] -= 1
				entity.splitter_cursor = (index + 1) % ports.size()
				break

func _update_merger(entity: FactoryEntity) -> void:
	var queues: Dictionary = entity.extra.get("merge_queues", {})
	var ports: Array[String] = ["in0", "in1", "in2"]
	for offset: int in range(ports.size()):
		var index: int = posmod(entity.merger_cursor + offset, ports.size())
		var queue: Array = queues.get(ports[index], [])
		if not queue.is_empty() and try_push_from_port(entity.id, "out0", str(queue[0])):
			queue.pop_front()
			entity.merger_cursor = (index + 1) % ports.size()
			break

func _update_storage(entity: FactoryEntity) -> void:
	for item_id: String in entity.input_buffer:
		if int(entity.input_buffer[item_id]) > 0 and try_push_from_port(entity.id, "out0", item_id):
			entity.input_buffer[item_id] -= 1
			break

func _update_spires(dt: float) -> void:
	if spire_stage >= milestone_definitions.size():
		return
	for entity: FactoryEntity in entities.values():
		if entity.kind != "spire":
			continue
		var milestone: Dictionary = milestone_definitions[spire_stage]
		var met: bool = true
		for item_id: String in milestone["requirements"]:
			if entity.rate(item_id, time) + RATE_WINDOW_TOLERANCE < float(milestone["requirements"][item_id]):
				met = false
		if met:
			spire_progress[spire_stage] += dt
			if spire_progress[spire_stage] >= float(milestone["duration"]):
				spire_stage += 1

func _port_for(entity_id: int, port_id: String) -> Dictionary:
	if not entities.has(entity_id):
		return {}
	for port: Dictionary in building_definitions.get(entities[entity_id].kind, {}).get("ports", []):
		if str(port["id"]) == port_id:
			return port
	return {}

func _rebuild_indexes() -> void:
	node_reservations.clear()
	vent_reservations.clear()
	port_links.clear()
	for entity: FactoryEntity in entities.values():
		if entity.kind == "miner_mk1":
			var node_id: int = int(entity.extra.get("node_id", -1))
			if node_id >= 0:
				node_reservations[node_id] = entity.id
		if entity.kind == "geo_tap":
			var vent_id: String = str(entity.extra.get("vent_id", ""))
			if not vent_id.is_empty():
				vent_reservations[vent_id] = entity.id
		if _is_belt_segment(entity.kind):
			var source: Dictionary = entity.extra.get("from", {})
			var target: Dictionary = entity.extra.get("to", {})
			if not source.is_empty():
				port_links[_port_key(int(source["id"]), str(source["port"]))] = entity.id
			if not target.is_empty():
				port_links[_port_key(int(target["id"]), str(target["port"]))] = entity.id

func _obb_overlap(pa: Vector3, ya: float, sa: Vector3, pb: Vector3, yb: float, sb: Vector3) -> bool:
	var axes: Array[Vector2] = []
	for yaw: float in [ya, yb]:
		axes.append(Vector2(cos(yaw), -sin(yaw)))
		axes.append(Vector2(sin(yaw), cos(yaw)))
	for axis: Vector2 in axes:
		var first: Array[float] = _project_rect(pa, ya, sa, axis)
		var second: Array[float] = _project_rect(pb, yb, sb, axis)
		if first[1] <= second[0] + EPSILON or second[1] <= first[0] + EPSILON:
			return false
	return true

func _project_rect(position: Vector3, yaw: float, size: Vector3, axis: Vector2) -> Array[float]:
	var c: float = cos(yaw)
	var s: float = sin(yaw)
	var ext: float = absf(axis.x * c - axis.y * s) * size.x * 0.5 + absf(axis.x * s + axis.y * c) * size.z * 0.5
	var center: float = position.x * axis.x + position.z * axis.y
	return [center - ext, center + ext]

func _curve_length(curve: PackedVector3Array) -> float:
	var previous: Vector3 = curve[0]
	var length: float = 0.0
	for index: int in range(1, 65):
		var point: Vector3 = _bezier(curve, float(index) / 64.0)
		length += previous.distance_to(point)
		previous = point
	return length

func _bezier(curve: PackedVector3Array, t: float) -> Vector3:
	var u: float = 1.0 - t
	return curve[0] * u * u * u + curve[1] * 3.0 * u * u * t + curve[2] * 3.0 * u * t * t + curve[3] * t * t * t

func _nearest_node(position: Vector3) -> int:
	var closest: int = -1
	var distance: float = 1.5
	for node_id: Variant in nodes:
		var node_position: Vector3 = nodes[node_id]["position"]
		var candidate: float = Vector2(position.x - node_position.x, position.z - node_position.z).length()
		if candidate <= distance:
			closest = int(node_id)
			distance = candidate
	return closest

func _nearest_migration_node(position: Vector3, saved_extra: Dictionary) -> int:
	var requested_item: String = str(saved_extra.get("item", saved_extra.get("node_item", "")))
	var node_value: Variant = saved_extra.get("node", null)
	if node_value is String:
		requested_item = str(node_value)
	elif node_value is Dictionary:
		requested_item = str(node_value.get("item", requested_item))
	var saved_node_id: int = int(saved_extra.get("node_id", -1))
	if nodes.has(saved_node_id):
		requested_item = str(nodes[saved_node_id].get("item", requested_item))
	var closest: int = -1
	var distance: float = 6.0
	for node_id: Variant in nodes:
		var node: Dictionary = nodes[node_id]
		if not requested_item.is_empty() and str(node.get("item", "")) != requested_item:
			continue
		var node_position: Vector3 = node["position"]
		var candidate: float = Vector2(position.x - node_position.x, position.z - node_position.z).length()
		if candidate <= distance:
			closest = int(node_id)
			distance = candidate
	return closest

func _refund_unrestored_entity(kind: String, saved: Dictionary, refund: Dictionary) -> void:
	var definition: Dictionary = building_definitions.get(kind, {})
	_add_items(refund, definition.get("cost", {}))
	var input: Variant = saved.get("input", saved.get("input_buffer", {}))
	if input is Dictionary:
		_add_items(refund, _int_dict(input))
	var output: Variant = saved.get("output", saved.get("output_buffer", {}))
	if output is Dictionary:
		_add_items(refund, _int_dict(output))
	var extra: Dictionary = saved.get("extra", {})
	var merge_queues: Variant = extra.get("merge_queues", {})
	if merge_queues is Dictionary:
		for queue_variant: Variant in merge_queues.values():
			if not queue_variant is Array:
				continue
			for queued_item: Variant in queue_variant:
				var item_id: String = str(queued_item.get("item", "")) if queued_item is Dictionary else str(queued_item)
				if not item_id.is_empty():
					_add_items(refund, {item_id: 1})

func _is_belt_segment(kind: String) -> bool:
	return kind in ["belt_mk1", "belt_mk2"]

func _is_machine(kind: String) -> bool:
	return kind in ["smelter", "constructor", "assembler"]

func _valid_input(entity: FactoryEntity, item_id: String) -> bool:
	return recipe_definitions.has(entity.recipe_id) and recipe_definitions[entity.recipe_id]["inputs"].has(item_id)

func _input_recipe_mismatch(entity: FactoryEntity, item_id: String) -> String:
	var recipe_name: String = entity.recipe_id.replace("_", " ").capitalize()
	return "Input %s doesn't match recipe %s" % [Items.item_name(item_id), recipe_name]

func _inventory_total(items: Dictionary) -> int:
	var total: int = 0
	for count: Variant in items.values():
		total += int(count)
	return total

func _int_dict(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source:
		result[str(key)] = int(source[key])
	return result

func _add_items(target: Dictionary, source: Dictionary) -> void:
	for item: String in source:
		target[item] = int(target.get(item, 0)) + int(source[item])

func _port_key(entity_id: int, port_id: String) -> String:
	return "%d:%s" % [entity_id, port_id]

func visual_state(entity_id: int) -> Dictionary:
	if not entities.has(entity_id):
		return {"status": "Stopped", "productivity": 0.0, "powered": false}
	var entity: FactoryEntity = entities[entity_id]
	if entity.kind == "geo_tap":
		var generating: bool = entity.status == "Running"
		return {
			"status": entity.status,
			"productivity": 1.0 if generating else 0.0,
			"powered": generating
		}
	var satisfaction: float = power.satisfaction(entity_id, entities)
	var running: bool = entity.status == "Running" or entity.status.begins_with("Low power")
	return {
		"status": entity.status,
		"productivity": clampf(satisfaction, 0.0, 1.0) if running else 0.0,
		"powered": satisfaction > 0.0
	}
