extends RefCounted
class_name FactorySaveSystem

const SAVE_PATH: String = "user://save.json"
const SAVE_VERSION: int = 1

var save_path: String = SAVE_PATH

func save_game(sim: FactorySim, player: FactoryPlayer, unlocked_tiers: int) -> bool:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"sim": sim.to_dict(),
		"player": {"position": [player.position.x, player.position.y, player.position.z],
			"rotation_y": player.rotation.y, "pitch": player.pitch,
			"inventory": player.inventory.duplicate(true)},
		"unlocked_tiers": unlocked_tiers
	}
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true

func load_game(sim: FactorySim, player: FactoryPlayer) -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("version", 0)) != SAVE_VERSION:
		return {}
	var data: Dictionary = parsed
	sim.from_dict(data.get("sim", {}))
	var player_data: Dictionary = data.get("player", {})
	var position: Array = player_data.get("position", [0.0, 1.0, 12.0])
	player.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	player.rotation.y = float(player_data.get("rotation_y", 0.0))
	player.pitch = float(player_data.get("pitch", 0.0))
	player.camera.rotation.x = player.pitch
	player.inventory.clear()
	var inventory: Dictionary = player_data.get("inventory", {})
	for item_id: Variant in inventory:
		player.inventory[str(item_id)] = int(inventory[item_id])
	return {"unlocked_tiers": int(data.get("unlocked_tiers", 0))}
