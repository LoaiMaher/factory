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
	_test_save_backup()
	_test_ore_boulders()
	_test_foliage_state()
	print("RESULT: %d/10 test groups passed" % passed_groups)
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
	var stored_plates: int = int(storage.input_buffer.get("iron_plate", 0))
	var withdrawn_storage: Dictionary = sim.take_storage(storage_id)
	_check("storage Take all returns and clears stored items", int(withdrawn_storage.get("iron_plate", 0)) == stored_plates
		and stored_plates > 0 and sim.entities[storage_id].input_buffer.is_empty(), str(withdrawn_storage))
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

	var blocked: FactorySim = FactorySim.new()
	var upstream_id: int = blocked.add_entity("belt_mk1", Vector2i(10, -1))
	var blocked_splitter_id: int = blocked.add_entity("splitter", Vector2i(10, 0))
	for blocked_cell: Vector2i in [Vector2i(9, 0), Vector2i(10, 1), Vector2i(11, 0)]:
		var output_id: int = blocked.add_entity("belt_mk1", blocked_cell)
		blocked.entities[output_id].belt_items.assign([
			{"item": "iron_ore", "pos": 0.0},
			{"item": "iron_ore", "pos": 0.5}
		])
	_check("splitter accepts one buffered item", blocked.try_insert(blocked_splitter_id, "iron_ore", Vector2i(10, -1)), "first insert rejected")
	blocked.tick(0.05)
	var upstream_belt: FactoryEntity = blocked.entities[upstream_id]
	upstream_belt.belt_items = [{"item": "iron_ore", "pos": 0.99}]
	blocked.tick(0.05)
	_check("blocked splitter holds its item", int(blocked.entities[blocked_splitter_id].input_buffer.get("iron_ore", 0)) == 1, str(blocked.entities[blocked_splitter_id].input_buffer))
	_check("full splitter refuses another item", not blocked.try_insert(blocked_splitter_id, "copper_ore", Vector2i(10, -1)), str(blocked.entities[blocked_splitter_id].input_buffer))
	var second_upstream_accepted: bool = blocked.try_insert(upstream_id, "iron_ore", Vector2i(10, -2))
	_check("upstream belt backs up at blocked splitter", is_equal_approx(float(upstream_belt.belt_items[0]["pos"]), 1.0)
		and second_upstream_accepted and not blocked.try_insert(upstream_id, "iron_ore", Vector2i(10, -2)), str(upstream_belt.belt_items))

	var blocked_merger: FactorySim = FactorySim.new()
	var merger_input_a: int = blocked_merger.add_entity("belt_mk1", Vector2i(20, -1))
	var merger_input_b: int = blocked_merger.add_entity("belt_mk1", Vector2i(19, 0), 1)
	var blocked_merger_id: int = blocked_merger.add_entity("merger", Vector2i(20, 0))
	var merger_output: int = blocked_merger.add_entity("belt_mk1", Vector2i(20, 1))
	blocked_merger.entities[merger_output].belt_items.assign([
		{"item": "iron_ore", "pos": 0.0},
		{"item": "iron_ore", "pos": 0.5}
	])
	var merger_a_accepted: bool = blocked_merger.try_insert(blocked_merger_id, "iron_ore", Vector2i(20, -1))
	var merger_b_accepted: bool = blocked_merger.try_insert(blocked_merger_id, "copper_ore", Vector2i(19, 0))
	blocked_merger.tick(0.05)
	blocked_merger.entities[merger_input_a].belt_items.assign([{"item": "iron_ore", "pos": 0.99}])
	blocked_merger.entities[merger_input_b].belt_items.assign([{"item": "copper_ore", "pos": 0.99}])
	blocked_merger.tick(0.05)
	var blocked_queues: Dictionary = blocked_merger.entities[blocked_merger_id].extra["merge_queues"]
	_check("blocked merger output fills each source queue", merger_a_accepted and merger_b_accepted
		and blocked_queues["20,-1"].size() == 1 and blocked_queues["19,0"].size() == 1, str(blocked_queues))
	_check("blocked merger backpressures both inputs",
		is_equal_approx(float(blocked_merger.entities[merger_input_a].belt_items[0]["pos"]), 1.0)
		and is_equal_approx(float(blocked_merger.entities[merger_input_b].belt_items[0]["pos"]), 1.0)
		and not blocked_merger.try_insert(blocked_merger_id, "iron_ore", Vector2i(20, -1))
		and not blocked_merger.try_insert(blocked_merger_id, "copper_ore", Vector2i(19, 0)),
		str([blocked_merger.entities[merger_input_a].belt_items, blocked_merger.entities[merger_input_b].belt_items]))

	var path_sim: FactorySim = FactorySim.new()
	var input_machine_id: int = path_sim.add_entity("smelter", Vector2i(8, 4), 1, {"recipe": "iron_ingot"})
	var input_cell: Vector2i = path_sim.back_port_for(input_machine_id)
	var path_builder: FactoryBuildSystem = FactoryBuildSystem.new()
	var input_path: Array[Dictionary] = path_builder.belt_path(Vector2i.ZERO, input_cell, path_sim.entities[input_machine_id].rotation)
	_check("belt terminal faces into the machine input", input_path.back()["cell"] == input_cell
		and int(input_path.back()["rotation"]) == 1, str(input_path.back()))
	var side_merge_path: Array[Dictionary] = path_builder.belt_path_to_belt(Vector2i.ZERO, Vector2i(4, 0), 0)
	_check("belt path side-merges one cell before an existing belt", side_merge_path.back()["cell"] == Vector2i(3, 0)
		and int(side_merge_path.back()["rotation"]) == 1, str(side_merge_path.back()))

	var assembler_sim: FactorySim = FactorySim.new()
	var routed_assembler_id: int = assembler_sim.add_entity("assembler", Vector2i(20, 20), 0, {"recipe": "hull_panel"})
	var assembler_input_cells: Array[Vector2i] = assembler_sim.input_port_cells(routed_assembler_id)
	var chosen_assembler_input: Vector2i = assembler_input_cells[0]
	var assembler_start: Vector2i = chosen_assembler_input - Vector2i(0, 3)
	var assembler_path: Array[Dictionary] = path_builder.belt_path(assembler_start, chosen_assembler_input, 0)
	var assembler_path_placed: bool = path_builder.place_path(assembler_sim, assembler_path, "belt_mk1")
	var first_assembler_belt: FactoryEntity = assembler_sim.entity_at(assembler_start)
	var assembler_input_accepted: bool = false
	if assembler_path_placed and first_assembler_belt != null:
		var assembler_source_cell: Vector2i = assembler_start - path_builder._forward(int(assembler_path[0]["rotation"]))
		assembler_input_accepted = assembler_sim.try_insert(first_assembler_belt.id, "iron_plate", assembler_source_cell)
	_run_for(assembler_sim, 10.0)
	_check("belt delivers into the chosen assembler input", assembler_input_accepted
		and int(assembler_sim.entities[routed_assembler_id].input_buffer.get("iron_plate", 0)) == 1,
		str(assembler_sim.entities[routed_assembler_id].input_buffer))

	var spire_sim: FactorySim = FactorySim.new()
	var routed_spire_id: int = spire_sim.add_entity("spire", Vector2i(40, 40), 0)
	var spire_input_cells: Array[Vector2i] = spire_sim.input_port_cells(routed_spire_id)
	_check("Spire stage 0 exposes its accepted input ports", spire_input_cells.size() == 2
		and spire_input_cells.has(Vector2i(41, 46)) and spire_input_cells.has(Vector2i(44, 46)), str(spire_input_cells))
	spire_sim.spire_stage = 1
	var stage_one_spire_ports: Array[Vector2i] = spire_sim.input_port_cells(routed_spire_id)
	_check("Spire stage 1 adds cable input ports", stage_one_spire_ports.size() == 4
		and stage_one_spire_ports.has(Vector2i(42, 46)) and stage_one_spire_ports.has(Vector2i(43, 46)),
		str(stage_one_spire_ports))
	spire_sim.spire_stage = 0
	var chosen_spire_input: Vector2i = spire_input_cells[0]
	var spire_start: Vector2i = chosen_spire_input + Vector2i(0, 3)
	var spire_path: Array[Dictionary] = path_builder.belt_path(spire_start, chosen_spire_input, 2)
	var spire_path_placed: bool = path_builder.place_path(spire_sim, spire_path, "belt_mk1")
	var first_spire_belt: FactoryEntity = spire_sim.entity_at(spire_start)
	var spire_input_accepted: bool = false
	if spire_path_placed and first_spire_belt != null:
		var spire_source_cell: Vector2i = spire_start - path_builder._forward(int(spire_path[0]["rotation"]))
		spire_input_accepted = spire_sim.try_insert(first_spire_belt.id, "hull_panel", spire_source_cell)
	_run_for(spire_sim, 10.0)
	_check("belt delivers through a Spire input port", spire_input_accepted
		and spire_sim.entities[routed_spire_id].last_delivery_time.has("hull_panel"),
		str(spire_sim.entities[routed_spire_id].last_delivery_time))

	var merger_id: int = sim.add_entity("merger", Vector2i(10, 0))
	var merger_sink: int = sim.add_entity("sink", Vector2i(10, 1))
	var iron_inserted: int = 0
	var copper_inserted: int = 0
	var initial_iron_accepted: bool = sim.try_insert(merger_id, "iron_ore", Vector2i(10, -1))
	var second_iron_accepted: bool = sim.try_insert(merger_id, "iron_ore", Vector2i(10, -1))
	var initial_copper_accepted: bool = sim.try_insert(merger_id, "copper_ore", Vector2i(9, 0))
	var second_copper_accepted: bool = sim.try_insert(merger_id, "copper_ore", Vector2i(9, 0))
	iron_inserted += 1 if initial_iron_accepted else 0
	copper_inserted += 1 if initial_copper_accepted else 0
	_check("merger limits each source queue to one item",
		initial_iron_accepted and initial_copper_accepted and not second_iron_accepted and not second_copper_accepted,
		str(sim.entities[merger_id].extra.get("merge_queues", {})))
	for _index: int in range(120):
		if iron_inserted < 6 and sim.try_insert(merger_id, "iron_ore", Vector2i(10, -1)):
			iron_inserted += 1
		if copper_inserted < 6 and sim.try_insert(merger_id, "copper_ore", Vector2i(9, 0)):
			copper_inserted += 1
		sim.tick(0.05)
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
	var spire_id: int = sim.add_entity("spire", Vector2i(8, 0), 0, {}, 42)
	sim.spire_progress[0] = 47.5
	sim.discovered_nodes["hidden_iron"] = true
	var save_system: FactorySaveSystem = FactorySaveSystem.new()
	save_system.save_path = "user://factory_round_trip_test.json"
	var world_state: Dictionary = {
		"boulders": {"near_iron_00": {"item": "iron_ore", "remaining": 7, "capacity": 15}},
		"foliage": ["tree_00001", "rock_00002"]
	}
	var player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(player)
	player.set_panel_open(true)
	player.position = Vector3(4.0, 2.0, 9.0)
	player.inventory["cable"] = 17
	var saved: bool = save_system.save_game(sim, player, 2, world_state)
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
	_check("save/load preserves sparse IDs without rescanning the grid", restored.entities.has(42) and restored.next_id == 43,
		"IDs %s, next %d" % [str(restored.entities.keys()), restored.next_id])
	_check("save/load preserves player inventory, transform and tier", restored_player.inventory == player.inventory and restored_player.position.is_equal_approx(player.position) and int(loaded.get("unlocked_tiers", -1)) == 2,
		"inventory %s, position %s, tier %s" % [str(restored_player.inventory), str(restored_player.position), str(loaded.get("unlocked_tiers", -1))])
	var restored_world: Dictionary = loaded.get("world", {})
	var restored_boulder: Dictionary = restored_world.get("boulders", {}).get("near_iron_00", {})
	var restored_foliage: Array = restored_world.get("foliage", [])
	_check("save/load preserves world resource state",
		str(restored_boulder.get("item", "")) == "iron_ore" and int(restored_boulder.get("remaining", -1)) == 7
		and restored_foliage.has("tree_00001") and restored_foliage.has("rock_00002") and restored_foliage.size() == 2,
		str(restored_world))

	var legacy_data: Dictionary = {
		"version": FactorySaveSystem.SAVE_VERSION,
		"sim": sim.to_dict(),
		"player": {
			"position": [0.0, 1.0, 0.0],
			"rotation_y": 0.0,
			"pitch": 0.0,
			"inventory": {}
		},
		"unlocked_tiers": 0
	}
	var legacy_file: FileAccess = FileAccess.open(save_system.save_path, FileAccess.WRITE)
	if legacy_file != null:
		legacy_file.store_string(JSON.stringify(legacy_data))
		legacy_file.close()
	var legacy_sim: FactorySim = FactorySim.new()
	var legacy_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(legacy_player)
	legacy_player.set_panel_open(true)
	var legacy_loaded: Dictionary = save_system.load_game(legacy_sim, legacy_player)
	var legacy_boulders: OreBoulders = OreBoulders.new()
	legacy_boulders.register("near_iron_00", "iron_ore", 15)
	legacy_boulders.from_dict(legacy_loaded.get("world", {}).get("boulders", {}))
	_check("old saves without boulder data restore full boulders",
		legacy_loaded.get("world", {}).get("boulders", {}).is_empty() and legacy_boulders.remaining_for("near_iron_00") == 15,
		str(legacy_loaded.get("world", {})))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.save_path))
	player.queue_free()
	restored_player.queue_free()
	legacy_player.queue_free()
	_finish_group()

func _test_save_backup() -> void:
	var save_system: FactorySaveSystem = FactorySaveSystem.new()
	var suffix: String = str(int(Time.get_unix_time_from_system()))
	save_system.save_path = "user://factory_backup_source_%s.json" % suffix
	save_system.backup_path = "user://factory_backup_target_%s.json" % suffix
	var source_file: FileAccess = FileAccess.open(save_system.save_path, FileAccess.WRITE)
	if source_file == null:
		_check("new game backs up an existing save", false, "source save could not be written")
		_finish_group()
		return
	source_file.store_string("existing save data")
	source_file.close()
	var backed_up: bool = save_system.backup_existing_save()
	var backup_file: FileAccess = FileAccess.open(save_system.backup_path, FileAccess.READ)
	var backup_text: String = backup_file.get_as_text() if backup_file != null else ""
	if backup_file != null:
		backup_file.close()
	_check("new game backs up an existing save", backed_up and not FileAccess.file_exists(save_system.save_path) and backup_text == "existing save data",
		"backup contents %s" % backup_text)
	if FileAccess.file_exists(save_system.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.save_path))
	if FileAccess.file_exists(save_system.backup_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.backup_path))
	_finish_group()

func _test_ore_boulders() -> void:
	var deposits: OreBoulders = OreBoulders.new()
	deposits.register("iron_0", "iron_ore", 8)
	var mined: Dictionary = {}
	for _index: int in range(8):
		mined = deposits.mine("iron_0")
	_check("ore boulder yields finite units and depletes", int(mined.get("remaining", -1)) == 0
		and bool(mined.get("depleted", false)) and deposits.mine("iron_0").is_empty(),
		"remaining %d, last result %s" % [deposits.remaining_for("iron_0"), str(mined)])

	var partially_mined: OreBoulders = OreBoulders.new()
	partially_mined.register("copper_0", "copper_ore", 14)
	for _index: int in range(5):
		partially_mined.mine("copper_0")
	var restored: OreBoulders = OreBoulders.new()
	restored.register("copper_0", "copper_ore", 14)
	restored.from_dict(partially_mined.to_dict())
	_check("ore boulder save/load preserves item and remaining count",
		restored.item_for("copper_0") == "copper_ore" and restored.remaining_for("copper_0") == 9,
		str(restored.to_dict()))

	var old_save: OreBoulders = OreBoulders.new()
	old_save.register("limestone_0", "limestone", 11)
	old_save.from_dict({})
	_check("missing boulder key leaves legacy deposits full", old_save.remaining_for("limestone_0") == 11,
		str(old_save.to_dict()))
	_finish_group()

func _test_foliage_state() -> void:
	var state: FoliageState = FoliageState.new()
	state.remove("tree_00001")
	state.remove("bush_00008")
	var restored: FoliageState = FoliageState.new()
	restored.from_dict(state.to_dict())
	_check("foliage removal IDs survive save/load", restored.is_removed("tree_00001")
		and restored.is_removed("bush_00008") and restored.to_dict().size() == 2, str(restored.to_dict()))
	var empty_state: FoliageState = FoliageState.new()
	empty_state.from_dict([])
	_check("missing foliage data starts with all foliage present", empty_state.to_dict().is_empty(), str(empty_state.to_dict()))
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
