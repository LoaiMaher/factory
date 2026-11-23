extends RefCounted
class_name CreativeMode

var active: bool = false
var survival_inventory: Dictionary = {}
var survival_unlocked_tiers: int = 0

func enter(inventory: Dictionary, unlocked_tiers: int) -> bool:
	if active:
		return false
	survival_inventory = inventory.duplicate(true)
	survival_unlocked_tiers = unlocked_tiers
	active = true
	return true

func exit() -> Dictionary:
	if not active:
		return {}
	var restored: Dictionary = {
		"inventory": survival_inventory.duplicate(true),
		"unlocked_tiers": survival_unlocked_tiers
	}
	active = false
	survival_inventory.clear()
	survival_unlocked_tiers = 0
	return restored

func can_afford(cost: Dictionary, inventory: Dictionary, multiplier: int) -> bool:
	if active:
		return true
	for item_id: String in cost:
		if int(inventory.get(item_id, 0)) < int(cost[item_id]) * multiplier:
			return false
	return true

func pay_cost(cost: Dictionary, inventory: Dictionary, multiplier: int) -> void:
	if active:
		return
	for item_id: String in cost:
		inventory[item_id] = int(inventory.get(item_id, 0)) - int(cost[item_id]) * multiplier

func add_refund(refund: Dictionary, inventory: Dictionary) -> void:
	if active:
		return
	for item_id: String in refund:
		inventory[item_id] = int(inventory.get(item_id, 0)) + int(refund[item_id])

func grant_stack(inventory: Dictionary, item_id: String, quantity: int = 100) -> bool:
	if not active or item_id not in Items.all() or quantity <= 0:
		return false
	inventory[item_id] = int(inventory.get(item_id, 0)) + quantity
	return true

func to_dict() -> Dictionary:
	return {
		"active": active,
		"survival_inventory": survival_inventory.duplicate(true),
		"survival_unlocked_tiers": survival_unlocked_tiers
	}

func load_dict(data: Dictionary) -> void:
	active = bool(data.get("active", false))
	var inventory: Variant = data.get("survival_inventory", {})
	survival_inventory.clear()
	if inventory is Dictionary:
		for item_id: Variant in inventory:
			survival_inventory[str(item_id)] = int(inventory[item_id])
	survival_unlocked_tiers = int(data.get("survival_unlocked_tiers", 0))
