extends RefCounted
class_name FrontierInventory

const DEFAULT_CAPACITY: int = 48

var capacity: int = DEFAULT_CAPACITY
var slots: Array[Dictionary] = []

func _init(slot_capacity: int = DEFAULT_CAPACITY) -> void:
	capacity = maxi(0, slot_capacity)
	_reset_slots()

func count(item_id: String) -> int:
	var total: int = 0
	for slot: Dictionary in slots:
		if str(slot.get("item_id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total

func clear() -> void:
	_reset_slots()

func is_empty() -> bool:
	return totals().is_empty()

func totals() -> Dictionary:
	var result: Dictionary = {}
	for slot: Dictionary in slots:
		var item_id: String = str(slot.get("item_id", ""))
		var quantity: int = int(slot.get("count", 0))
		if not item_id.is_empty() and quantity > 0:
			result[item_id] = int(result.get(item_id, 0)) + quantity
	return result

func add(item_id: String, quantity: int) -> int:
	if item_id.is_empty() or quantity <= 0:
		return maxi(0, quantity)
	var remaining: int = quantity
	var limit: int = Items.stack_size(item_id)
	for index: int in range(capacity):
		var slot: Dictionary = slots[index]
		if str(slot.get("item_id", "")) != item_id:
			continue
		var space: int = limit - int(slot.get("count", 0))
		if space <= 0:
			continue
		var added: int = mini(space, remaining)
		slot["count"] = int(slot["count"]) + added
		slots[index] = slot
		remaining -= added
		if remaining == 0:
			return 0
	for index: int in range(capacity):
		if not slots[index].is_empty():
			continue
		var added: int = mini(limit, remaining)
		slots[index] = {"item_id": item_id, "count": added}
		remaining -= added
		if remaining == 0:
			return 0
	return remaining

func set_count(item_id: String, quantity: int) -> int:
	remove(item_id, count(item_id))
	return add(item_id, quantity)

func remove(item_id: String, quantity: int) -> bool:
	if item_id.is_empty() or quantity < 0 or count(item_id) < quantity:
		return false
	var remaining: int = quantity
	for index: int in range(slots.size() - 1, -1, -1):
		var slot: Dictionary = slots[index]
		if str(slot.get("item_id", "")) != item_id:
			continue
		var removed: int = mini(remaining, int(slot.get("count", 0)))
		slot["count"] = int(slot["count"]) - removed
		slots[index] = {} if int(slot["count"]) <= 0 else slot
		remaining -= removed
		if remaining == 0:
			return true
	return remaining == 0

func can_fit(items: Dictionary) -> bool:
	var test_inventory := FrontierInventory.new(capacity)
	test_inventory.from_data(to_data())
	for item_variant: Variant in items:
		var item_id: String = str(item_variant)
		var quantity: int = int(items[item_variant])
		if quantity > 0 and test_inventory.add(item_id, quantity) > 0:
			return false
	return true

func fit_count(item_id: String, quantity: int) -> int:
	var test_inventory := FrontierInventory.new(capacity)
	test_inventory.from_data(to_data())
	return quantity - test_inventory.add(item_id, quantity)

func can_afford(cost: Dictionary, multiplier: int = 1) -> bool:
	for item_variant: Variant in cost:
		var item_id: String = str(item_variant)
		if count(item_id) < int(cost[item_variant]) * multiplier:
			return false
	return true

func move(from_index: int, to_index: int) -> bool:
	if from_index < 0 or from_index >= slots.size() \
			or to_index < 0 or to_index >= capacity or from_index == to_index:
		return false
	var source: Dictionary = slots[from_index]
	if source.is_empty():
		return false
	var destination: Dictionary = slots[to_index]
	if destination.is_empty():
		var moved: int = mini(int(source["count"]), Items.stack_size(str(source["item_id"])))
		slots[to_index] = {"item_id": source["item_id"], "count": moved}
		source["count"] = int(source["count"]) - moved
		slots[from_index] = {} if int(source["count"]) <= 0 else source
		return true
	if str(source["item_id"]) == str(destination["item_id"]):
		var space: int = Items.stack_size(str(destination["item_id"])) - int(destination["count"])
		var moved: int = mini(maxi(0, space), int(source["count"]))
		if moved <= 0:
			return false
		destination["count"] = int(destination["count"]) + moved
		source["count"] = int(source["count"]) - moved
		slots[to_index] = destination
		slots[from_index] = {} if int(source["count"]) <= 0 else source
		return true
	if from_index >= capacity:
		return false
	slots[from_index] = destination
	slots[to_index] = source
	return true

func split(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= slots.size() or slots[slot_index].is_empty():
		return {}
	var slot: Dictionary = slots[slot_index]
	var lifted: int = ceili(float(int(slot["count"])) / 2.0)
	var result: Dictionary = {"item_id": slot["item_id"], "count": lifted}
	slot["count"] = int(slot["count"]) - lifted
	slots[slot_index] = {} if int(slot["count"]) <= 0 else slot
	return result

func take_slot(slot_index: int, quantity: int) -> Dictionary:
	if slot_index < 0 or slot_index >= slots.size() or quantity <= 0:
		return {}
	var slot: Dictionary = slots[slot_index]
	if slot.is_empty():
		return {}
	var removed: int = mini(quantity, int(slot["count"]))
	var result: Dictionary = {"item_id": slot["item_id"], "count": removed}
	slot["count"] = int(slot["count"]) - removed
	slots[slot_index] = {} if int(slot["count"]) <= 0 else slot
	return result

func place_into(slot_index: int, stack: Dictionary) -> Dictionary:
	if slot_index < 0 or slot_index >= capacity:
		return stack.duplicate(true)
	var item_id: String = str(stack.get("item_id", ""))
	var quantity: int = int(stack.get("count", 0))
	if item_id.is_empty() or quantity <= 0:
		return {}
	var remainder: Dictionary = {"item_id": item_id, "count": quantity}
	var destination: Dictionary = slots[slot_index]
	if destination.is_empty():
		var placed: int = mini(quantity, Items.stack_size(item_id))
		slots[slot_index] = {"item_id": item_id, "count": placed}
		return _stack_or_empty(item_id, quantity - placed)
	if str(destination.get("item_id", "")) == item_id:
		var moved: int = mini(quantity,
			maxi(0, Items.stack_size(item_id) - int(destination.get("count", 0))))
		if moved <= 0:
			return remainder
		destination["count"] = int(destination["count"]) + moved
		slots[slot_index] = destination
		return _stack_or_empty(item_id, quantity - moved)
	if quantity > Items.stack_size(item_id) or int(destination.get("count", 0)) > Items.stack_size(str(destination.get("item_id", ""))):
		return remainder
	slots[slot_index] = {"item_id": item_id, "count": quantity}
	return destination

func sort() -> void:
	var regular: Array[Dictionary] = []
	var overflow: Array[Dictionary] = []
	for index: int in range(slots.size()):
		if slots[index].is_empty():
			continue
		if index < capacity:
			regular.append(slots[index].duplicate(true))
		else:
			overflow.append(slots[index].duplicate(true))
	regular.sort_custom(_slot_before)
	overflow.sort_custom(_slot_before)
	_reset_slots()
	for slot: Dictionary in regular:
		var free_index: int = _first_empty_regular()
		if free_index >= 0:
			slots[free_index] = slot
	for slot: Dictionary in overflow:
		slots.append(slot)

func to_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: Dictionary in slots:
		result.append(slot.duplicate(true))
	return result

func from_data(data: Variant) -> void:
	_reset_slots()
	if not data is Array:
		return
	var saved_slots: Array = data
	for index: int in range(saved_slots.size()):
		var raw_slot: Variant = saved_slots[index]
		if not raw_slot is Dictionary:
			continue
		var item_id: String = str(raw_slot.get("item_id", ""))
		var quantity: int = int(raw_slot.get("count", 0))
		if item_id.is_empty() or quantity <= 0:
			continue
		var stack_limit: int = Items.stack_size(item_id)
		if index < capacity:
			var in_slot: int = mini(stack_limit, quantity)
			slots[index] = {"item_id": item_id, "count": in_slot}
			quantity -= in_slot
		if quantity > 0:
			_append_overflow(item_id, quantity)

func add_restored(item_id: String, quantity: int) -> int:
	var leftover: int = add(item_id, quantity)
	if leftover > 0:
		_append_overflow(item_id, leftover)
	return 0

static func from_totals(items: Dictionary, slot_capacity: int = DEFAULT_CAPACITY) -> FrontierInventory:
	var inventory := FrontierInventory.new(slot_capacity)
	var item_ids: Array[String] = []
	for item_variant: Variant in items:
		item_ids.append(str(item_variant))
	item_ids.sort()
	for item_id: String in item_ids:
		var quantity: int = int(items[item_id])
		if quantity <= 0:
			continue
		var leftover: int = inventory.add(item_id, quantity)
		if leftover > 0:
			inventory._append_overflow(item_id, leftover)
	return inventory

func _reset_slots() -> void:
	slots.clear()
	for _index: int in range(capacity):
		slots.append({})

func _append_overflow(item_id: String, quantity: int) -> void:
	var remaining: int = quantity
	var limit: int = Items.stack_size(item_id)
	while remaining > 0:
		var amount: int = mini(limit, remaining)
		slots.append({"item_id": item_id, "count": amount})
		remaining -= amount

func _first_empty_regular() -> int:
	for index: int in range(capacity):
		if slots[index].is_empty():
			return index
	return -1

static func _slot_before(first: Dictionary, second: Dictionary) -> bool:
	var first_id: String = str(first.get("item_id", ""))
	var second_id: String = str(second.get("item_id", ""))
	var first_category: String = Items.category(first_id)
	var second_category: String = Items.category(second_id)
	if first_category != second_category:
		return _category_order(first_category) < _category_order(second_category)
	return first_id < second_id

static func _category_order(category_name: String) -> int:
	return ["raw", "processed", "component", "special"].find(category_name)

func _stack_or_empty(item_id: String, quantity: int) -> Dictionary:
	return {} if quantity <= 0 else {"item_id": item_id, "count": quantity}
