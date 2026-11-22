extends RefCounted
class_name HotbarModel

const SLOT_COUNT: int = 10

var slots: Array[Dictionary] = []
var selected_index: int = -1

func _init() -> void:
	slots = default_slots()

static func default_slots() -> Array[Dictionary]:
	return [
		{"type": "building", "id": "miner_mk1"},
		{"type": "building", "id": "smelter"},
		{"type": "building", "id": "constructor"},
		{"type": "building", "id": "belt_mk1"},
		{"type": "building", "id": "belt_pole"},
		{"type": "building", "id": "power_pole"},
		{"type": "building", "id": "geo_tap"},
		{},
		{},
		{}
	]

func slot_at(index: int) -> Dictionary:
	return slots[index].duplicate(true) if index >= 0 and index < SLOT_COUNT else {}

func assign(index: int, slot_type: String, id: String) -> bool:
	if index < 0 or index >= SLOT_COUNT or id.is_empty():
		return false
	if slot_type == "building" and BuildingDefs.all().has(id):
		slots[index] = {"type": slot_type, "id": id}
		return true
	if slot_type == "item" and Items.all().has(id):
		slots[index] = {"type": slot_type, "id": id}
		return true
	return false

func clear_slot(index: int) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		return false
	slots[index] = {}
	return true

func is_locked(index: int, unlocked_tiers: int,
		building_definitions: Dictionary = {}) -> bool:
	var definitions: Dictionary = BuildingDefs.all() if building_definitions.is_empty() else building_definitions
	var slot: Dictionary = slot_at(index)
	if slot.get("type", "") != "building":
		return false
	var id: String = str(slot.get("id", ""))
	return not definitions.has(id) or int(definitions[id].get("tier", 0)) > unlocked_tiers

func select_slot(index: int, unlocked_tiers: int,
		building_definitions: Dictionary = {}) -> Dictionary:
	if index < 0 or index >= SLOT_COUNT:
		return {"ok": false, "reason": "Invalid hotbar slot", "index": index}
	if is_locked(index, unlocked_tiers, building_definitions):
		if selected_index == index:
			selected_index = -1
		var slot: Dictionary = slot_at(index)
		var definitions: Dictionary = BuildingDefs.all() if building_definitions.is_empty() else building_definitions
		var tier: int = int(definitions.get(str(slot.get("id", "")), {}).get("tier", 0))
		return {"ok": false, "locked": true, "reason": "Unlocks at Tier %d" % tier, "index": index}
	selected_index = -1 if selected_index == index else index
	return {"ok": true, "selected_index": selected_index, "slot": selected_action()}

func cycle(step: int, unlocked_tiers: int,
		building_definitions: Dictionary = {}) -> Dictionary:
	if step == 0:
		return {"ok": true, "selected_index": selected_index, "slot": selected_action()}
	var direction: int = 1 if step > 0 else -1
	var origin: int = selected_index
	if origin < 0:
		origin = -1 if direction > 0 else 0
	for offset: int in range(SLOT_COUNT):
		var index: int = posmod(origin + direction * (offset + 1), SLOT_COUNT)
		if is_locked(index, unlocked_tiers, building_definitions):
			continue
		return select_slot(index, unlocked_tiers, building_definitions)
	return {"ok": false, "reason": "No unlocked hotbar slots"}

func quantity(index: int, inventory: Dictionary,
		building_definitions: Dictionary = {}) -> int:
	var definitions: Dictionary = BuildingDefs.all() if building_definitions.is_empty() else building_definitions
	var slot: Dictionary = slot_at(index)
	var id: String = str(slot.get("id", ""))
	if slot.get("type", "") == "item":
		return maxi(0, int(inventory.get(id, 0)))
	if slot.get("type", "") != "building" or not definitions.has(id):
		return 0
	var cost: Dictionary = definitions[id].get("cost", {})
	if cost.is_empty():
		return 0
	var affordable: int = 2147483647
	for item_id: String in cost:
		var item_cost: int = int(cost[item_id])
		if item_cost <= 0:
			continue
		affordable = mini(affordable, floori(float(maxi(0, int(inventory.get(item_id, 0)))) / float(item_cost)))
	if affordable == 2147483647:
		return 0
	return affordable * 2 if id in ["belt_mk1", "belt_mk2"] else affordable

func selected_action() -> Dictionary:
	if selected_index < 0 or selected_index >= SLOT_COUNT:
		return {"type": "empty", "id": ""}
	var slot: Dictionary = slots[selected_index]
	return {"type": str(slot.get("type", "empty")), "id": str(slot.get("id", ""))}

func find_slot(slot_type: String, id: String) -> int:
	for index: int in range(SLOT_COUNT):
		var slot: Dictionary = slots[index]
		if slot.get("type", "") == slot_type and str(slot.get("id", "")) == id:
			return index
	return -1

func select_or_assign(slot_type: String, id: String, unlocked_tiers: int,
		building_definitions: Dictionary = {}) -> Dictionary:
	var index: int = find_slot(slot_type, id)
	if index < 0:
		index = selected_index if selected_index >= 0 else slots.find({})
		if index < 0:
			return {"ok": false, "reason": "No empty hotbar slots"}
		if not assign(index, slot_type, id):
			return {"ok": false, "reason": "Invalid hotbar item"}
	if is_locked(index, unlocked_tiers, building_definitions):
		var definitions: Dictionary = BuildingDefs.all() if building_definitions.is_empty() else building_definitions
		var tier: int = int(definitions.get(id, {}).get("tier", 0))
		return {"ok": false, "locked": true, "reason": "Unlocks at Tier %d" % tier, "index": index}
	selected_index = index
	return {"ok": true, "selected_index": index, "slot": selected_action()}

func apply_to_build_system(build_system: FactoryBuildSystem) -> Dictionary:
	var action: Dictionary = selected_action()
	build_system.choose(str(action.get("id", "")) if action.get("type", "") == "building" else "")
	return action

func to_dict() -> Dictionary:
	return {"slots": slots.duplicate(true), "selected_index": selected_index}

static func from_dict(data: Dictionary) -> HotbarModel:
	var model: HotbarModel = HotbarModel.new()
	model.load_dict(data)
	return model

func load_dict(data: Dictionary) -> void:
	var saved_slots: Variant = data.get("slots", null)
	if not saved_slots is Array:
		slots = default_slots()
		selected_index = -1
		return
	var restored: Array[Dictionary] = []
	for index: int in range(SLOT_COUNT):
		if index >= saved_slots.size():
			restored.append({})
			continue
		var entry: Variant = saved_slots[index]
		if entry is Dictionary and str(entry.get("type", "")) in ["building", "item"] \
				and not str(entry.get("id", "")).is_empty():
			restored.append({"type": str(entry["type"]), "id": str(entry["id"])})
		else:
			restored.append({})
	slots = restored
	var saved_index: int = int(data.get("selected_index", -1))
	selected_index = saved_index if saved_index >= 0 and saved_index < SLOT_COUNT else -1
