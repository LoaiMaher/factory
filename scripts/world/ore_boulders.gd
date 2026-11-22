extends RefCounted
class_name OreBoulders

var deposits: Dictionary = {}

func register(boulder_id: String, item_id: String, amount: int) -> void:
	deposits[boulder_id] = {
		"item": item_id,
		"remaining": maxi(0, amount),
		"capacity": maxi(0, amount)
	}

func mine(boulder_id: String, amount: int = 1) -> Dictionary:
	if not deposits.has(boulder_id):
		return {}
	var deposit: Dictionary = deposits[boulder_id]
	var remaining: int = int(deposit.get("remaining", 0))
	if remaining <= 0 or amount <= 0:
		return {}
	remaining = maxi(0, remaining - amount)
	deposit["remaining"] = remaining
	deposits[boulder_id] = deposit
	return {
		"item": str(deposit.get("item", "")),
		"remaining": remaining,
		"depleted": remaining == 0
	}

func remaining_for(boulder_id: String) -> int:
	return int(deposits.get(boulder_id, {}).get("remaining", 0))

func item_for(boulder_id: String) -> String:
	return str(deposits.get(boulder_id, {}).get("item", ""))

func to_dict() -> Dictionary:
	return deposits.duplicate(true)

func from_dict(data: Dictionary) -> void:
	for boulder_id: String in deposits:
		var saved: Variant = data.get(boulder_id, {})
		if not saved is Dictionary:
			continue
		var deposit: Dictionary = deposits[boulder_id]
		if str(saved.get("item", deposit["item"])) != str(deposit["item"]):
			continue
		deposit["remaining"] = clampi(int(saved.get("remaining", deposit["remaining"])), 0, int(deposit["capacity"]))
		deposits[boulder_id] = deposit
