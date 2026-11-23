extends RefCounted
class_name CreativeMode

var active: bool = false
var survival_inventory: Array[Dictionary] = []
var survival_unlocked_tiers: int = 0
var world_gains: Dictionary = {}
var inventory: FrontierInventory = FrontierInventory.new()

func enter(survival: FrontierInventory, unlocked_tiers: int) -> bool:
	if active or survival == null:
		return false
	survival_inventory = survival.to_data()
	survival_unlocked_tiers = unlocked_tiers
	world_gains.clear()
	inventory = FrontierInventory.new()
	active = true
	return true

func exit() -> Dictionary:
	if not active:
		return {}
	var restored_inventory := FrontierInventory.new()
	restored_inventory.from_data(survival_inventory)
	for item_variant: Variant in world_gains:
		restored_inventory.add_restored(str(item_variant), int(world_gains[item_variant]))
	var restored: Dictionary = {
		"inventory": restored_inventory,
		"unlocked_tiers": survival_unlocked_tiers
	}
	active = false
	survival_inventory.clear()
	survival_unlocked_tiers = 0
	world_gains.clear()
	inventory = FrontierInventory.new()
	return restored

func record_world_gain(item_id: String, quantity: int) -> void:
	if not active or item_id.is_empty() or quantity <= 0:
		return
	world_gains[item_id] = int(world_gains.get(item_id, 0)) + quantity

func can_afford(cost: Dictionary, current_inventory: FrontierInventory, multiplier: int) -> bool:
	return active or current_inventory.can_afford(cost, multiplier)

func pay_cost(cost: Dictionary, current_inventory: FrontierInventory, multiplier: int) -> void:
	if active or not current_inventory.can_afford(cost, multiplier):
		return
	for item_variant: Variant in cost:
		current_inventory.remove(str(item_variant), int(cost[item_variant]) * multiplier)

func add_refund(refund: Dictionary, current_inventory: FrontierInventory) -> void:
	if active:
		return
	for item_variant: Variant in refund:
		current_inventory.add_restored(str(item_variant), int(refund[item_variant]))

func grant_stack(item_id: String) -> bool:
	if not active or item_id not in Items.all():
		return false
	var quantity: int = Items.stack_size(item_id)
	if not inventory.can_fit({item_id: quantity}):
		return false
	return inventory.add(item_id, quantity) == 0

func to_dict() -> Dictionary:
	var survival_totals: Dictionary = {}
	if not survival_inventory.is_empty():
		var snapshot := FrontierInventory.new()
		snapshot.from_data(survival_inventory)
		survival_totals = snapshot.totals()
	return {
		"active": active,
		"survival_inventory": survival_totals,
		"survival_inventory_slots": survival_inventory.duplicate(true),
		"survival_unlocked_tiers": survival_unlocked_tiers,
		"world_gains": world_gains.duplicate(true)
	}

func load_dict(data: Dictionary) -> void:
	active = bool(data.get("active", false))
	survival_inventory.clear()
	var saved_slots: Variant = data.get("survival_inventory_slots", null)
	if saved_slots is Array:
		var snapshot := FrontierInventory.new()
		snapshot.from_data(saved_slots)
		survival_inventory = snapshot.to_data()
	else:
		var legacy_totals: Variant = data.get("survival_inventory", {})
		if legacy_totals is Dictionary:
			survival_inventory = FrontierInventory.from_totals(legacy_totals).to_data()
	survival_unlocked_tiers = int(data.get("survival_unlocked_tiers", 0))
	var gains: Variant = data.get("world_gains", {})
	world_gains.clear()
	if gains is Dictionary:
		for item_variant: Variant in gains:
			var quantity: int = int(gains[item_variant])
			if quantity > 0:
				world_gains[str(item_variant)] = quantity
