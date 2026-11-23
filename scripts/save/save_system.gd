extends RefCounted
class_name FactorySaveSystem

const SAVE_PATH: String = "user://save.json"
const SAVE_VERSION: int = 3

var save_path: String = SAVE_PATH
var backup_path: String = "user://save.bak.json"

func save_game(sim: FactorySim, player: FactoryPlayer, unlocked_tiers: int,
		world_state: Dictionary = {}, hotbar_data: Dictionary = {}, power_bypass: bool = true,
		creative_data: Dictionary = {}) -> bool:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"sim": sim.to_dict(),
		"player": {"position": [player.position.x, player.position.y, player.position.z],
			"rotation_y": player.rotation.y, "pitch": player.pitch,
			"inventory": player.inventory.totals(),
			"inventory_slots": player.inventory.to_data()},
		"unlocked_tiers": unlocked_tiers,
		"world": world_state.duplicate(true),
		"hotbar": hotbar_data.duplicate(true),
		"power_bypass": power_bypass,
		"creative": creative_data.duplicate(true)
	}
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true

func backup_existing_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return true
	var backup_absolute: String = ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		var archive_path: String = "%s.%d" % [backup_path, int(Time.get_unix_time_from_system())]
		var suffix: int = 1
		while FileAccess.file_exists(archive_path):
			archive_path = "%s.%d.%d" % [backup_path, int(Time.get_unix_time_from_system()), suffix]
			suffix += 1
		var archive_error: Error = DirAccess.rename_absolute(backup_absolute, ProjectSettings.globalize_path(archive_path))
		if archive_error != OK:
			return false
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), backup_absolute)
	return rename_error == OK

func load_game(sim: FactorySim, player: FactoryPlayer) -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("version", 0)) not in [1, 2, SAVE_VERSION]:
		return {}
	var data: Dictionary = parsed
	var source_version: int = int(data.get("version", 0))
	var belt_refund: Dictionary = sim.from_dict(data.get("sim", {}))
	sim.power.bypass = bool(data.get("power_bypass",
		ProjectSettings.get_setting("factory/dev/power_bypass", true)))
	var player_data: Dictionary = data.get("player", {})
	var position: Array = player_data.get("position", [0.0, 1.0, 12.0])
	player.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	player.rotation.y = float(player_data.get("rotation_y", 0.0))
	player.pitch = float(player_data.get("pitch", 0.0))
	player.camera.rotation.x = player.pitch
	var inventory_slots: Variant = player_data.get("inventory_slots", null)
	if inventory_slots is Array:
		var restored_inventory := FrontierInventory.new()
		restored_inventory.from_data(inventory_slots)
		player.inventory = restored_inventory
	else:
		var legacy_inventory: Variant = player_data.get("inventory", {})
		player.inventory = FrontierInventory.from_totals(
			legacy_inventory if legacy_inventory is Dictionary else {})
	var world_state: Variant = data.get("world", {})
	if not world_state is Dictionary:
		world_state = {}
	var creative_state: Variant = data.get("creative", {})
	if not creative_state is Dictionary:
		creative_state = {}
	return {"unlocked_tiers": int(data.get("unlocked_tiers", 0)), "world": (world_state as Dictionary).duplicate(true),
		"hotbar": data.get("hotbar", {}),
		"creative": (creative_state as Dictionary).duplicate(true),
		"migrated_from": source_version if source_version < SAVE_VERSION else 0, "belt_refund": belt_refund}
