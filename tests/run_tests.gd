extends SceneTree

var failures: int = 0
var groups: int = 0
var passed_groups: int = 0
var current_group_failures: int = 0

func _initialize() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	_test_belt_throughput()
	_test_production_line()
	_test_splitter_and_merger()
	_test_power_networks()
	_test_diagnostics()
	_test_spire_progress()
	_test_save_round_trip()
	print("RESULT: %d/7 test groups passed" % passed_groups)
	quit(1 if failures > 0 else 0)

func _test_belt_throughput() -> void:
	var sim: FactorySim = FactorySim.new()
	sim.add_entity("source", Vector2i(0, 0), 0, {"item": "iron_ore", "items_per_second": 1.0})
	for index: int in range(10):
		sim.add_entity("belt_mk1", Vector2i(0, index + 1))
	var sink_id: int = sim.add_entity("sink", Vector2i(0, 11))
	_run_for(sim, 120.0)
	var rate: float = sim.get_rate(sink_id, "iron_ore")
	_check("belt line delivers about 60/min", absf(rate - 60.0) <= 3.0, "observed %.1f/min" % rate)
	_finish_group()

func _test_production_line() -> void:
	var sim: FactorySim = FactorySim.new()
	var miner_id: int = sim.add_entity("miner_mk1", Vector2i(0, 0), 0, {"node": {"item": "iron_ore", "rate": 60.0}})
	sim.add_entity("belt_mk1", Vector2i(0, 2))
	sim.add_entity("belt_mk1", Vector2i(0, 3))
	var smelter_id: int = sim.add_entity("smelter", Vector2i(0, 4), 0, {"recipe": "iron_ingot"})
	sim.add_entity("belt_mk1", Vector2i(0, 6))
	sim.add_entity("belt_mk1", Vector2i(0, 7))
	var constructor_id: int = sim.add_entity("constructor", Vector2i(0, 8), 0, {"recipe": "iron_plate"})
	sim.add_entity("belt_mk1", Vector2i(0, 11))
	var storage_id: int = sim.add_entity("storage", Vector2i(0, 12))
	sim.add_entity("geo_tap", Vector2i(-6, 0))
	sim.add_entity("power_pole", Vector2i(-4, 0))
	sim.add_entity("power_pole", Vector2i(-2, 2))
	sim.add_entity("power_pole", Vector2i(2, 4))
	sim.add_entity("power_pole", Vector2i(2, 8))
	_run_for(sim, 120.0)
	var storage: FactoryEntity = sim.entities[storage_id]
	var ingot_rate: float = sim.get_rate(smelter_id, "iron_ingot")
	var plate_rate: float = sim.get_rate(constructor_id, "iron_plate")
	_check("miner → smelter → constructor stores plates", int(storage.input_buffer.get("iron_plate", 0)) > 0, "storage buffer %s" % str(storage.input_buffer))
	_check("smelter recipe rate is near 30/min", absf(ingot_rate - 30.0) <= 2.0, "observed %.1f/min" % ingot_rate)
	_check("plate recipe rate is near 20/min", absf(plate_rate - 20.0) <= 2.0, "observed %.1f/min" % plate_rate)
	_check("miner applies back pressure when the downstream line is saturated", sim.status_for(miner_id) == "Output full",
		"status %s" % sim.status_for(miner_id))
	var assembler_id: int = sim.add_entity("assembler", Vector2i(20, 20), 0, {"recipe": "hull_panel"})
	var assembler_ports: Array[Vector2i] = sim.port_cells("assembler", Vector2i(20, 20), 0)["input"]
	var left_accepted: bool = sim.try_insert(assembler_id, "iron_plate", assembler_ports[0])
	var right_accepted: bool = sim.try_insert(assembler_id, "iron_plate", assembler_ports[1])
	_check("assembler accepts both back ports", left_accepted and right_accepted, "ports %s" % str(assembler_ports))
	_finish_group()

func _test_splitter_and_merger() -> void:
	var sim: FactorySim = FactorySim.new()
	sim.add_entity("source", Vector2i(0, -2), 0, {"item": "iron_ore", "items_per_second": 1.0})
	sim.add_entity("belt_mk1", Vector2i(0, -1))
	var splitter_id: int = sim.add_entity("splitter", Vector2i(0, 0))
	var sink_ids: Array[int] = [
		sim.add_entity("sink", Vector2i(-1, 0)),
		sim.add_entity("sink", Vector2i(0, 1)),
		sim.add_entity("sink", Vector2i(1, 0))
	]
	_run_for(sim, 60.0)
	var counts: Array[int] = []
	for sink_id: int in sink_ids:
		counts.append(int(sim.entities[sink_id].extra.get("received", 0)))
	var balanced: bool = maxi(counts[0], maxi(counts[1], counts[2])) - mini(counts[0], mini(counts[1], counts[2])) <= 1
	_check("splitter distributes evenly", balanced, "counts %s" % str(counts))
	var merger_id: int = sim.add_entity("merger", Vector2i(10, 0))
	var merger_sink: int = sim.add_entity("sink", Vector2i(10, 1))
	for _index: int in range(6):
		sim.try_insert(merger_id, "iron_ore", Vector2i(10, -1))
		sim.try_insert(merger_id, "copper_ore", Vector2i(9, 0))
	_run_for(sim, 0.6)
	var received: Dictionary = sim.entities[merger_sink].extra.get("received_by_item", {})
	_check("merger alternates queued input sources", int(received.get("iron_ore", 0)) == 6 and int(received.get("copper_ore", 0)) == 6,
		"received %s" % str(received))
	_check("splitter entity remains in sim", sim.entities.has(splitter_id), "entity missing")
	_finish_group()

func _test_power_networks() -> void:
	var sim: FactorySim = FactorySim.new()
	sim.add_entity("geo_tap", Vector2i(0, 0))
	sim.add_entity("power_pole", Vector2i(2, 2))
	sim.add_entity("power_pole", Vector2i(12, 2))
	var machines: Array[int] = []
	for index: int in range(12):
		var cell: Vector2i = Vector2i(4 + (index % 5) * 2, 4 + int(index / 5) * 2)
		var machine_id: int = sim.add_entity("smelter", cell, 0, {"recipe": "iron_ingot"})
		machines.append(machine_id)
		sim.entities[machine_id].input_buffer["iron_ore"] = 1
	sim.add_entity("power_pole", Vector2i(2, 10))
	sim.power.update_demand(sim.entities)
	var twelve_satisfaction: float = sim.power.satisfaction(machines[0], sim.entities)
	_check("50 MW covers twelve smelters", sim.power.demand_for.values().has(48.0) and twelve_satisfaction == 1.0, "satisfaction %.3f, demand %s" % [twelve_satisfaction, str(sim.power.demand_for)])
	for index: int in range(3):
		var machine_index: int = index + 12
		var cell: Vector2i = Vector2i(4 + (machine_index % 5) * 2, 4 + int(machine_index / 5) * 2)
		var machine_id: int = sim.add_entity("smelter", cell, 0, {"recipe": "iron_ingot"})
		machines.append(machine_id)
		sim.entities[machine_id].input_buffer["iron_ore"] = 1
	sim.power.update_demand(sim.entities)
	var fifteen_satisfaction: float = sim.power.satisfaction(machines[14], sim.entities)
	_run_for(sim, 0.1)
	_check("15 smelters receive less than full power", fifteen_satisfaction < 1.0, "satisfaction %.3f" % fifteen_satisfaction)
	_check("low-power status is readable", sim.status_for(machines[14]).begins_with("Low power"), sim.status_for(machines[14]))
	var isolated: FactorySim = FactorySim.new()
	var isolated_id: int = isolated.add_entity("smelter", Vector2i.ZERO, 0, {"recipe": "iron_ingot"})
	isolated.entities[isolated_id].input_buffer["iron_ore"] = 1
	isolated.tick(0.05)
	_check("unconnected machine reports not connected", isolated.status_for(isolated_id) == "Not connected to power", isolated.status_for(isolated_id))
	_finish_group()

func _test_diagnostics() -> void:
	var sim: FactorySim = FactorySim.new()
	var machine_id: int = sim.add_entity("smelter", Vector2i.ZERO, 0, {"recipe": "iron_ingot"})
	sim.add_entity("geo_tap", Vector2i(4, 0))
	sim.add_entity("power_pole", Vector2i(2, 0))
	sim.tick(0.05)
	_check("missing input names the required item", sim.status_for(machine_id) == "Missing input: Iron Ore", sim.status_for(machine_id))
	var machine: FactoryEntity = sim.entities[machine_id]
	machine.input_buffer["iron_ore"] = 1
	machine.output_buffer["iron_ingot"] = 20
	sim.tick(0.05)
	_check("blocked output reports Output full", sim.status_for(machine_id) == "Output full", sim.status_for(machine_id))
	var lines: Array[String] = sim.diagnostics(machine_id)
	_check("diagnostic panel includes per-port rates", lines.size() == 2 and lines[0].contains("needs 30.0/min"), str(lines))
	_finish_group()

func _test_spire_progress() -> void:
	var sim: FactorySim = FactorySim.new()
	var spire_id: int = sim.add_entity("spire", Vector2i.ZERO)
	var spire: FactoryEntity = sim.entities[spire_id]
	var dt: float = 0.05
	for tick: int in range(1800):
		spire.record("hull_panel", 2.0 * dt / 60.0, sim.time)
		spire.record("rotor", 1.5 * dt / 60.0, sim.time)
		sim.tick(dt)
	for tick: int in range(400):
		sim.tick(dt)
	var saved_progress: float = sim.spire_progress[0]
	for tick: int in range(800):
		sim.tick(dt)
	var paused_progress: float = sim.spire_progress[0]
	_check("starvation pauses accumulated milestone progress", is_equal_approx(paused_progress, saved_progress), "progress %.1f → %.1f" % [saved_progress, paused_progress])
	for tick: int in range(3600):
		spire.record("hull_panel", 2.0 * dt / 60.0, sim.time)
		spire.record("rotor", 1.5 * dt / 60.0, sim.time)
		sim.tick(dt)
	_check("milestone completes after 120 s of met rates", sim.spire_stage >= 1 and sim.spire_progress[0] >= 120.0,
		"stage %d, progress %.1f, time %.0f" % [sim.spire_stage, sim.spire_progress[0], sim.time])
	_finish_group()

func _test_save_round_trip() -> void:
	var sim: FactorySim = FactorySim.new()
	var belt_id: int = sim.add_entity("belt_mk1", Vector2i.ZERO)
	sim.entities[belt_id].belt_items.append({"item": "iron_ore", "pos": 0.62})
	var machine_id: int = sim.add_entity("smelter", Vector2i(2, 0), 0, {"recipe": "iron_ingot"})
	sim.entities[machine_id].input_buffer["iron_ore"] = 3
	sim.entities[machine_id].output_buffer["iron_ingot"] = 2
	var spire_id: int = sim.add_entity("spire", Vector2i(8, 0))
	sim.spire_progress[0] = 47.5
	sim.discovered_nodes["hidden_iron"] = true
	var save_system: FactorySaveSystem = FactorySaveSystem.new()
	save_system.save_path = "user://factory_round_trip_test.json"
	var player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(player)
	player.set_panel_open(true)
	player.position = Vector3(4.0, 2.0, 9.0)
	player.inventory["cable"] = 17
	var saved: bool = save_system.save_game(sim, player, 2)
	var restored: FactorySim = FactorySim.new()
	var restored_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(restored_player)
	restored_player.set_panel_open(true)
	if not saved:
		_check("save/load file round trip succeeds", false, "save file could not be written")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.save_path))
		player.queue_free()
		restored_player.queue_free()
		_finish_group()
		return
	var loaded: Dictionary = save_system.load_game(restored, restored_player) if saved else {}
	if loaded.is_empty():
		_check("save/load file round trip succeeds", false, "save file could not be read")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.save_path))
		player.queue_free()
		restored_player.queue_free()
		_finish_group()
		return
	var restored_machine: FactoryEntity = restored.entities[machine_id]
	var restored_belt: FactoryEntity = restored.entities[belt_id]
	_check("save/load file round trip succeeds", true, "loaded %s" % str(loaded))
	_check("save/load preserves entity count", restored.entities.size() == sim.entities.size(), "%d vs %d" % [restored.entities.size(), sim.entities.size()])
	_check("save/load preserves belt items", restored_belt.belt_items.size() == 1 and str(restored_belt.belt_items[0]["item"]) == "iron_ore", str(restored_belt.belt_items))
	_check("save/load preserves machine buffers", restored_machine.input_buffer == {"iron_ore": 3} and restored_machine.output_buffer == {"iron_ingot": 2}, "%s / %s" % [str(restored_machine.input_buffer), str(restored_machine.output_buffer)])
	_check("save/load preserves milestone and discovery", is_equal_approx(restored.spire_progress[0], 47.5) and restored.discovered_nodes.get("hidden_iron", false) and restored.entities.has(spire_id), "progress %.1f" % restored.spire_progress[0])
	_check("save/load preserves player inventory, transform and tier", restored_player.inventory == player.inventory and restored_player.position.is_equal_approx(player.position) and int(loaded.get("unlocked_tiers", -1)) == 2,
		"inventory %s, position %s, tier %s" % [str(restored_player.inventory), str(restored_player.position), str(loaded.get("unlocked_tiers", -1))])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.save_path))
	player.queue_free()
	restored_player.queue_free()
	_finish_group()

func _run_for(sim: FactorySim, seconds: float) -> void:
	var ticks: int = roundi(seconds / 0.05)
	for _index: int in range(ticks):
		sim.tick(0.05)

func _check(label: String, passed: bool, details: String) -> void:
	if passed:
		print("PASS: ", label)
	else:
		print("FAIL: ", label, " — ", details)
		failures += 1
		current_group_failures += 1

func _finish_group() -> void:
	groups += 1
	if current_group_failures == 0:
		passed_groups += 1
		print("PASS: test group %d" % groups)
	else:
		print("FAIL: test group %d (%d failed assertions)" % [groups, current_group_failures])
	current_group_failures = 0
