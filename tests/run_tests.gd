extends SceneTree

var failures: int = 0
var groups: int = 0
var passed_groups: int = 0
var current_group_failures: int = 0

func _initialize() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	_test_placement_and_ports()
	_test_deposit_reservations()
	_test_belt_validation_and_flow()
	_test_splitter_merger_backpressure()
	_test_production_and_port_routing()
	_test_save_migration_and_refunds()
	_test_diagnostics()
	_test_visual_state()
	_test_power_bypass()
	_test_ore_boulders()
	_test_foliage_state()
	_test_hotbar_model()
	_test_full_hotbar_build_menu_selection()
	_test_hotbar_input_filtering()
	print("RESULT: %d/%d test groups passed" % [passed_groups, groups])
	quit(1 if failures > 0 else 0)

func _test_placement_and_ports() -> void:
	var sim: FactorySim = FactorySim.new()
	var existing: int = sim.add_entity("smelter", Vector3.ZERO)
	_check("world-space entity has a stable ID", existing > 0, str(existing))
	var overlap: Dictionary = sim.check_place("constructor", Vector3(3.8, 0.0, 0.0), PI / 4.0)
	_check("rotated OBB overlap is rejected", not bool(overlap["ok"]), str(overlap))
	var edge_sim: FactorySim = FactorySim.new()
	edge_sim.add_entity("smelter", Vector3.ZERO)
	var edge: Dictionary = edge_sim.check_place("smelter", Vector3(4.0, 0.0, 0.0), 0.0)
	_check("edge-touching footprints are allowed", bool(edge["ok"]), str(edge))
	var port: Dictionary = sim.port_world(existing, "out0")
	_check("port transform uses metre-based local position and normal",
		port.get("pos", Vector3.ZERO).is_equal_approx(Vector3(-1.0, 0.62, 2.0))
		and port.get("normal", Vector3.ZERO).is_equal_approx(Vector3.BACK),
		str(port))
	_finish_group()

func _test_deposit_reservations() -> void:
	var sim: FactorySim = FactorySim.new()
	sim.register_node(7, "iron_ore", "pure", Vector3(20.0, 0.0, 10.0), 120.0)
	var no_node: Dictionary = sim.check_place("miner_mk1", Vector3.ZERO, 0.0)
	_check("miner requires a registered deposit", not bool(no_node["ok"]) and no_node["reason"] == "Place a Miner here", str(no_node))
	var off_deposit: Dictionary = sim.check_place("miner_mk1", Vector3(22.0, 0.0, 10.0), 0.0, 7)
	_check("miner center must be within 1.5 m of deposit", not bool(off_deposit["ok"]), str(off_deposit))
	var miner_id: int = sim.add_entity("miner_mk1", Vector3(20.0, 0.0, 10.0), 0.0, {"node_id": 7})
	var duplicate: Dictionary = sim.check_place("miner_mk1", Vector3(20.0, 0.0, 10.0), 0.0, 7)
	_check("one extractor reserves each deposit with the required reason",
		miner_id > 0 and duplicate["reason"] == "Deposit already has an extractor", str(duplicate))
	sim.remove_entity(miner_id)
	var released: int = sim.add_entity("miner_mk1", Vector3(20.0, 0.0, 10.0), 0.0, {"node_id": 7})
	_check("removing an extractor releases its deposit", released > 0 and sim.node_reservations.get(7, -1) == released, str(sim.node_reservations))
	var saved: Dictionary = sim.to_dict()
	var restored: FactorySim = FactorySim.new()
	restored.register_node(7, "iron_ore", "pure", Vector3(20.0, 0.0, 10.0), 120.0)
	restored.from_dict(saved)
	var restored_duplicate: Dictionary = restored.check_place("miner_mk1", Vector3(20.0, 0.0, 10.0), 0.0, 7)
	_check("deposit reservation is derived after save/load",
		restored.node_reservations.get(7, -1) == released
		and restored_duplicate["reason"] == "Deposit already has an extractor", str(restored.node_reservations))

	restored.register_vent("vent_a", Vector3(40.0, 0.0, 0.0))
	var tap_id: int = restored.add_entity("geo_tap", Vector3(40.0, 0.0, 0.0))
	var duplicate_tap: Dictionary = restored.check_place("geo_tap", Vector3(40.0, 0.0, 0.0), 0.0)
	_check("Geo Tap reserves one vent", tap_id > 0 and duplicate_tap["reason"] == "Vent already has a tap", str(duplicate_tap))
	restored.remove_entity(tap_id)
	_check("removing Geo Tap releases its vent", bool(restored.check_place("geo_tap", Vector3(40.0, 0.0, 0.0), 0.0)["ok"]), str(restored.vent_reservations))
	_finish_group()

func _test_belt_validation_and_flow() -> void:
	var sim: FactorySim = FactorySim.new()
	var source_id: int = sim.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "iron_ingot"})
	var storage_id: int = sim.add_entity("storage", Vector3(0.0, 0.0, 8.0))
	var result: Dictionary = _connect(sim, "belt_mk1", source_id, "out0", storage_id, "in0")
	var belt_id: int = int(result["id"])
	_check("out-to-in belt link is created", belt_id > 0, str(result))
	var reverse: Dictionary = sim.add_belt("belt_mk1", source_id, "in0", storage_id, "out0",
		_port_curve(sim, source_id, "in0", storage_id, "out0"))
	_check("input-to-output links are rejected", reverse["reason"] == "Can't connect output to output", str(reverse))
	var same_entity: Dictionary = sim.add_belt("belt_mk1", source_id, "out0", source_id, "in0",
		_port_curve(sim, source_id, "out0", source_id, "in0"))
	_check("belt endpoints must be different entities", same_entity["reason"] == "Invalid belt endpoints", str(same_entity))
	var endpoint_sim: FactorySim = FactorySim.new()
	var endpoint_source: int = endpoint_sim.add_entity("smelter", Vector3.ZERO)
	var endpoint_storage: int = endpoint_sim.add_entity("storage", Vector3(0.0, 0.0, 8.0))
	var wrong_endpoint: PackedVector3Array = _port_curve(endpoint_sim, endpoint_source, "out0", endpoint_storage, "in0")
	wrong_endpoint[0].x += 0.1
	var endpoint_result: Dictionary = endpoint_sim.add_belt("belt_mk1", endpoint_source, "out0", endpoint_storage, "in0", wrong_endpoint)
	_check("curve endpoints must match port transforms", endpoint_result["reason"] == "Belt curve endpoints must match ports", str(endpoint_result))
	var occupied: Dictionary = sim.add_belt("belt_mk1", source_id, "out0", storage_id, "in0",
		_port_curve(sim, source_id, "out0", storage_id, "in0"))
	_check("occupied ports reject a second belt", occupied["reason"] == "Port already connected", str(occupied))
	_check("linked ports are no longer free",
		not sim.is_port_free(source_id, "out0") and not sim.is_port_free(storage_id, "in0"), str(sim.port_links))

	var first_pushed: bool = sim.try_push_from_port(source_id, "out0", "iron_ore")
	var second_blocked: bool = not sim.try_push_from_port(source_id, "out0", "iron_ore")
	sim.tick(1.0)
	var second_pushed: bool = sim.try_push_from_port(source_id, "out0", "iron_ore")
	sim.tick(1.0)
	var belt: FactoryEntity = sim.entities[belt_id]
	var spacing_ok: bool = (belt.belt_items.size() == 2 and is_equal_approx(float(belt.belt_items[0]["s"]), 2.0)
		and is_equal_approx(float(belt.belt_items[1]["s"]), 1.0))
	_check("Mk1 speed and one-metre item spacing", first_pushed and second_blocked and second_pushed and spacing_ok, str(belt.belt_items))
	sim.tick(3.0)
	_check("items deliver to the linked target port", int(sim.entities[storage_id].input_buffer.get("iron_ore", 0)) == 1,
		str(sim.entities[storage_id].input_buffer))

	var mk2: FactorySim = FactorySim.new()
	var mk2_source: int = mk2.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "iron_ingot"})
	var mk2_storage: int = mk2.add_entity("storage", Vector3(0.0, 0.0, 8.0))
	var mk2_result: Dictionary = _connect(mk2, "belt_mk2", mk2_source, "out0", mk2_storage, "in0")
	mk2.try_push_from_port(mk2_source, "out0", "iron_ore")
	mk2.tick(0.5)
	var mk2_belt: FactoryEntity = mk2.entities[int(mk2_result["id"])]
	_check("Mk2 moves at two metres per second", is_equal_approx(float(mk2_belt.belt_items[0]["s"]), 1.0),
		str(mk2_belt.belt_items))

	var blocked: FactorySim = FactorySim.new()
	var blocked_source: int = blocked.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "iron_ingot"})
	var blocked_storage: int = blocked.add_entity("storage", Vector3(0.0, 0.0, 8.0))
	var blocked_result: Dictionary = _connect(blocked, "belt_mk1", blocked_source, "out0", blocked_storage, "in0")
	blocked.entities[blocked_storage].input_buffer["iron_ore"] = 1000
	blocked.try_push_from_port(blocked_source, "out0", "iron_ore")
	blocked.tick(10.0)
	var blocked_belt: FactoryEntity = blocked.entities[int(blocked_result["id"])]
	_check("failed insertion leaves the leading item at the endpoint",
		blocked_belt.belt_items.size() == 1 and is_equal_approx(float(blocked_belt.belt_items[0]["s"]), float(blocked_belt.extra["length"])),
		str(blocked_belt.belt_items))

	var incompatible: FactorySim = FactorySim.new()
	incompatible.power.bypass = false
	incompatible.register_node(1, "iron_ore", "normal", Vector3.ZERO, 60.0)
	var miner: int = incompatible.add_entity("miner_mk1", Vector3.ZERO, 0.0, {"node_id": 1})
	var copper_smelter: int = incompatible.add_entity("smelter", Vector3(0.0, 0.0, 10.0), 0.0, {"recipe": "copper_ingot"})
	var incompatible_result: Dictionary = _connect(incompatible, "belt_mk1", miner, "out0", copper_smelter, "in0")
	incompatible.try_push_from_port(miner, "out0", "iron_ore")
	incompatible.tick(10.0)
	var incompatible_belt: FactoryEntity = incompatible.entities[int(incompatible_result["id"])]
	_check("item compatibility does not block link creation but rejected items back up",
		int(incompatible_result["id"]) > 0 and incompatible_belt.belt_items.size() == 1
		and is_equal_approx(float(incompatible_belt.belt_items[0]["s"]), float(incompatible_belt.extra["length"])),
		str(incompatible_result))
	_finish_group()

func _test_splitter_merger_backpressure() -> void:
	var splitter_sim: FactorySim = FactorySim.new()
	var splitter_id: int = splitter_sim.add_entity("splitter", Vector3.ZERO)
	var targets: Array[int] = [
		splitter_sim.add_entity("storage", Vector3(-8.0, 0.0, 0.0)),
		splitter_sim.add_entity("storage", Vector3(0.0, 0.0, 8.0)),
		splitter_sim.add_entity("storage", Vector3(8.0, 0.0, 0.0))
	]
	for index: int in range(3):
		var connected: Dictionary = _connect(splitter_sim, "belt_mk1", splitter_id, "out%d" % index, targets[index], "in0")
		_check("splitter output %d has a port-linked belt" % index, int(connected["id"]) > 0, str(connected))
	var accepted: int = 0
	for _step: int in range(700):
		if accepted < 6 and splitter_sim.try_insert(splitter_id, "iron_ore", "in0"):
			accepted += 1
		splitter_sim.tick(0.05)
	var counts: Array[int] = []
	for target_id: int in targets:
		counts.append(int(splitter_sim.entities[target_id].input_buffer.get("iron_ore", 0)))
	_check("splitter round-robins items across its three outputs",
		accepted == 6 and counts == [2, 2, 2], str(counts))

	var blocked_splitter: FactorySim = FactorySim.new()
	var blocked_splitter_id: int = blocked_splitter.add_entity("splitter", Vector3.ZERO)
	var blocked_targets: Array[int] = [
		blocked_splitter.add_entity("storage", Vector3(-8.0, 0.0, 0.0)),
		blocked_splitter.add_entity("storage", Vector3(0.0, 0.0, 8.0)),
		blocked_splitter.add_entity("storage", Vector3(8.0, 0.0, 0.0))
	]
	for index: int in range(3):
		_connect(blocked_splitter, "belt_mk1", blocked_splitter_id, "out%d" % index, blocked_targets[index], "in0")
		blocked_splitter.entities[blocked_targets[index]].input_buffer["iron_ore"] = 1000
		var output_belt_id: int = int(blocked_splitter.port_links["%d:out%d" % [blocked_splitter_id, index]])
		var output_belt: FactoryEntity = blocked_splitter.entities[output_belt_id]
		output_belt.belt_items = [{"item": "iron_ore", "s": 0.0, "born_at": -1.0}]
	var upstream: int = blocked_splitter.add_entity("storage", Vector3(0.0, 0.0, -10.0))
	_connect(blocked_splitter, "belt_mk1", upstream, "out0", blocked_splitter_id, "in0")
	blocked_splitter.try_insert(blocked_splitter_id, "iron_ore", "in0")
	var upstream_belt_id: int = int(blocked_splitter.port_links["%d:out0" % upstream])
	var upstream_belt: FactoryEntity = blocked_splitter.entities[upstream_belt_id]
	upstream_belt.belt_items = [{"item": "iron_ore", "s": float(upstream_belt.extra["length"]), "born_at": -1.0}]
	blocked_splitter.tick(0.05)
	var splitter_rejected_second: bool = not blocked_splitter.try_insert(blocked_splitter_id, "iron_ore", "in0")
	var splitter_buffer_count: int = int(blocked_splitter.entities[blocked_splitter_id].input_buffer.get("iron_ore", 0))
	var splitter_upstream_blocked: bool = upstream_belt.belt_items.size() == 1 and float(upstream_belt.belt_items[0]["s"]) >= float(upstream_belt.extra["length"]) - 0.01
	_check("all-blocked splitter caps its input at one and backs up the upstream belt",
		splitter_rejected_second and splitter_buffer_count == 1 and splitter_upstream_blocked,
		str([splitter_rejected_second, splitter_buffer_count, splitter_upstream_blocked, upstream_belt.belt_items, upstream_belt.extra["length"]]))

	var merger_sim: FactorySim = FactorySim.new()
	var merger_id: int = merger_sim.add_entity("merger", Vector3.ZERO)
	var output_storage: int = merger_sim.add_entity("storage", Vector3(0.0, 0.0, 8.0))
	_connect(merger_sim, "belt_mk1", merger_id, "out0", output_storage, "in0")
	var source_positions: Array[Vector3] = [Vector3(-8.0, 0.0, 0.0), Vector3(0.0, 0.0, -10.0), Vector3(8.0, 0.0, 0.0)]
	var input_ports: Array[String] = ["in0", "in1", "in2"]
	var source_ids: Array[int] = []
	var input_belt_ids: Array[int] = []
	var output_belt_id: int = int(merger_sim.port_links["%d:out0" % merger_id])
	var output_belt: FactoryEntity = merger_sim.entities[output_belt_id]
	output_belt.belt_items = [{"item": "iron_ore", "s": 0.0, "born_at": -1.0}]
	for index: int in range(3):
		var source_id: int = merger_sim.add_entity("storage", source_positions[index])
		source_ids.append(source_id)
		var result: Dictionary = _connect(merger_sim, "belt_mk1", source_id, "out0", merger_id, input_ports[index])
		input_belt_ids.append(int(result["id"]))
	merger_sim.entities[output_storage].input_buffer["iron_ore"] = 1000
	for index: int in range(3):
		_check("merger source queue %d accepts one item" % index,
			merger_sim.try_insert(merger_id, "iron_ore", input_ports[index]), input_ports[index])
		_check("merger source queue %d refuses a second item" % index,
			not merger_sim.try_insert(merger_id, "copper_ore", input_ports[index]), input_ports[index])
		var input_belt: FactoryEntity = merger_sim.entities[input_belt_ids[index]]
		input_belt.belt_items = [{"item": "iron_ore", "s": float(input_belt.extra["length"]), "born_at": -1.0}]
	merger_sim.tick(0.05)
	var queues: Dictionary = merger_sim.entities[merger_id].extra.get("merge_queues", {})
	var inputs_backed_up: bool = true
	for index: int in range(3):
		var input_belt: FactoryEntity = merger_sim.entities[input_belt_ids[index]]
		inputs_backed_up = (inputs_backed_up and input_belt.belt_items.size() == 1
			and is_equal_approx(float(input_belt.belt_items[0]["s"]), float(input_belt.extra["length"])))
	_check("blocked merger output fills one-item source queues and backs up all inputs",
		queues.get("in0", []).size() == 1 and queues.get("in1", []).size() == 1
		and queues.get("in2", []).size() == 1 and inputs_backed_up, str([queues, inputs_backed_up]))
	_finish_group()

func _test_production_and_port_routing() -> void:
	var sim: FactorySim = FactorySim.new()
	sim.register_node(1, "iron_ore", "normal", Vector3.ZERO, 60.0)
	sim.register_vent("vent_a", Vector3(-8.0, 0.0, 0.0))
	var miner: int = sim.add_entity("miner_mk1", Vector3.ZERO, 0.0, {"node_id": 1})
	var smelter: int = sim.add_entity("smelter", Vector3(0.0, 0.0, 6.0), 0.0, {"recipe": "iron_ingot"})
	var constructor: int = sim.add_entity("constructor", Vector3(0.0, 0.0, 12.0), 0.0, {"recipe": "iron_plate"})
	var storage: int = sim.add_entity("storage", Vector3(0.0, 0.0, 19.0))
	var tap: int = sim.add_entity("geo_tap", Vector3(-8.0, 0.0, 0.0))
	sim.add_entity("power_pole", Vector3(-4.0, 0.0, 0.0))
	sim.add_entity("power_pole", Vector3(-4.0, 0.0, 12.0))
	var links_ok: bool = (int(_connect(sim, "belt_mk1", miner, "out0", smelter, "in0")["id"]) > 0
		and int(_connect(sim, "belt_mk1", smelter, "out0", constructor, "in0")["id"]) > 0
		and int(_connect(sim, "belt_mk1", constructor, "out0", storage, "in0")["id"]) > 0)
	_run_for(sim, 180.0)
	_check("miner → smelter → constructor → storage runs over connected ports",
		links_ok and miner > 0 and smelter > 0 and constructor > 0 and storage > 0 and tap > 0
		and int(sim.entities[storage].input_buffer.get("iron_plate", 0)) > 0,
		str(sim.entities[storage].input_buffer))

	var assembler_sim: FactorySim = FactorySim.new()
	var assembler: int = assembler_sim.add_entity("assembler", Vector3(30.0, 0.0, 0.0), 0.0, {"recipe": "hull_panel"})
	var assembler_source: int = assembler_sim.add_entity("storage", Vector3(33.0, 0.0, -10.0))
	var assembler_link: Dictionary = _connect(assembler_sim, "belt_mk1", assembler_source, "out0", assembler, "in1")
	assembler_sim.try_push_from_port(assembler_source, "out0", "iron_plate")
	_run_for(assembler_sim, 8.0)
	_check("belt delivers into the selected assembler input mouth",
		int(assembler_link["id"]) > 0 and int(assembler_sim.entities[assembler].input_buffer.get("iron_plate", 0)) == 1,
		str(assembler_sim.entities[assembler].input_buffer))

	var spire_sim: FactorySim = FactorySim.new()
	var spire: int = spire_sim.add_entity("spire", Vector3(50.0, 0.0, 0.0))
	var spire_source: int = spire_sim.add_entity("storage", Vector3(53.0, 0.0, 16.0))
	var spire_link: Dictionary = _connect(spire_sim, "belt_mk1", spire_source, "out0", spire, "in1")
	spire_sim.try_push_from_port(spire_source, "out0", "hull_panel")
	_run_for(spire_sim, 16.0)
	_check("belt delivers to the selected Spire input port",
		int(spire_link["id"]) > 0 and spire_sim.entities[spire].last_delivery_time.has("hull_panel"),
		str(spire_sim.entities[spire].last_delivery_time))

	var pole_sim: FactorySim = FactorySim.new()
	pole_sim.power.bypass = false
	pole_sim.register_node(4, "iron_ore", "normal", Vector3.ZERO, 60.0)
	var pole_miner: int = pole_sim.add_entity("miner_mk1", Vector3.ZERO, 0.0, {"node_id": 4})
	var pole: int = pole_sim.add_entity("belt_pole", Vector3(0.0, 0.0, 8.0))
	var pole_storage: int = pole_sim.add_entity("storage", Vector3(0.0, 0.0, 16.0))
	var first_link: Dictionary = _connect(pole_sim, "belt_mk1", pole_miner, "out0", pole, "in0")
	var second_link: Dictionary = _connect(pole_sim, "belt_mk1", pole, "out0", pole_storage, "in0")
	for _item_index: int in range(5):
		var pushed: bool = pole_sim.try_push_from_port(pole_miner, "out0", "iron_ore")
		_run_for(pole_sim, 30.0)
		_check("miner-to-pole input belt accepts each item", pushed, str(first_link))
	_check("five items pass through miner, belt pole, and storage exactly once",
		int(first_link.get("id", -1)) > 0 and int(second_link.get("id", -1)) > 0
		and int(pole_sim.entities[pole_storage].input_buffer.get("iron_ore", 0)) == 5
		and pole_sim.entities[pole].input_buffer.is_empty(),
		str([pole_sim.entities[pole_storage].input_buffer, pole_sim.entities[pole].input_buffer]))
	_finish_group()

func _test_save_migration_and_refunds() -> void:
	var sim: FactorySim = FactorySim.new()
	sim.register_node(3, "iron_ore", "normal", Vector3(2.0, 0.0, 2.0))
	var source: int = sim.add_entity("smelter", Vector3(100.0, 0.0, 100.0), 0.0, {"recipe": "iron_ingot"}, 42)
	var target: int = sim.add_entity("storage", Vector3(100.0, 0.0, 108.0))
	var linked: Dictionary = _connect(sim, "belt_mk2", source, "out0", target, "in0")
	var belt_id: int = int(linked["id"])
	var belt: FactoryEntity = sim.entities[belt_id]
	belt.belt_items = [{"item": "iron_ore", "s": 1.25, "born_at": 0.0}]
	var save_system: FactorySaveSystem = FactorySaveSystem.new()
	save_system.save_path = "user://phase2_round_trip_test.json"
	var player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(player)
	player.set_panel_open(true)
	player.inventory["cable"] = 17
	var world_state: Dictionary = {"boulders": {"iron_a": {"item": "iron_ore", "remaining": 4}},
		"foliage": ["tree_00001", "rock_00002"]}
	var hotbar: HotbarModel = HotbarModel.new()
	hotbar.assign(8, "item", "iron_ore")
	hotbar.select_slot(8, 2)
	var save_ok: bool = save_system.save_game(sim, player, 2, world_state, hotbar.to_dict())
	var restored: FactorySim = FactorySim.new()
	var restored_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(restored_player)
	restored_player.set_panel_open(true)
	var loaded: Dictionary = save_system.load_game(restored, restored_player) if save_ok else {}
	var restored_belt: FactoryEntity = restored.entities.get(belt_id)
	_check("v3 save round-trip succeeds", not loaded.is_empty(), str(loaded))
	_check("v3 saves world positions, yaw, belt curve and progress",
		restored.entities.has(source) and restored.entities.has(target) and restored_belt != null
		and restored_belt.extra.get("curve", PackedVector3Array()).size() == 4
		and is_equal_approx(float(restored_belt.belt_items[0]["s"]), 1.25)
		and restored.port_links.has("%d:out0" % source) and not restored.is_port_free(source, "out0"),
		str(restored_belt.extra if restored_belt != null else {}))
	_check("sparse forced IDs and player inventory survive save/load",
		restored.entities.has(42) and restored.next_id > belt_id and restored_player.inventory.get("cable", 0) == 17,
		str([restored.entities.keys(), restored.next_id, restored_player.inventory]))
	var saved_world: Dictionary = loaded.get("world", {})
	_check("boulder and removed-foliage state survive world save/load",
		int(saved_world.get("boulders", {}).get("iron_a", {}).get("remaining", -1)) == 4
		and saved_world.get("foliage", []).has("tree_00001"), str(saved_world))
	var restored_hotbar: HotbarModel = HotbarModel.from_dict(loaded.get("hotbar", {}))
	_check("hotbar selection and assignments survive save/load",
		restored_hotbar.selected_index == 8 and restored_hotbar.slot_at(8) == {"type": "item", "id": "iron_ore"},
		str(restored_hotbar.to_dict()))

	var legacy_system: FactorySaveSystem = FactorySaveSystem.new()
	legacy_system.save_path = "user://phase2_v2_migration_test.json"
	var legacy_root: Dictionary = {
		"version": 2,
		"sim": {"next_id": 9, "time": 0.0, "entities": [
			{"id": 5, "kind": "miner_mk1", "cell": [0, 0], "rotation": 0, "extra": {}, "input": {}, "output": {}},
			{"id": 6, "kind": "belt_mk1", "cell": [0, 2], "items": [{"item": "iron_ore", "pos": 0.5}]},
			{"id": 8, "kind": "smelter", "cell": [4, 0], "rotation": 1, "recipe": "iron_ingot", "extra": {}, "input": {}, "output": {}}
		]},
		"player": {"position": [0.0, 1.0, 0.0], "inventory": {"iron_plate": 1}},
		"unlocked_tiers": 1,
		"world": {"boulders": {"iron_a": {"item": "iron_ore", "remaining": 4}}, "foliage": ["tree_00001"]}
	}
	var legacy_file: FileAccess = FileAccess.open(legacy_system.save_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy_root))
	legacy_file.close()
	var migrated: FactorySim = FactorySim.new()
	migrated.register_node(3, "iron_ore", "normal", Vector3(2.0, 0.0, 2.0))
	var migrated_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(migrated_player)
	migrated_player.set_panel_open(true)
	var migration_result: Dictionary = legacy_system.load_game(migrated, migrated_player)
	var migrated_miner: FactoryEntity = migrated.entities.get(5)
	var migrated_smelter: FactoryEntity = migrated.entities.get(8)
	var safe_position: Vector3 = SafePlayerPosition.adjust(
		Vector3(800.0, -4.0, -900.0), 12.0, FactoryTerrain.WORLD_HALF_EXTENT)
	_check("loaded player position is clamped and raised above terrain",
		is_equal_approx(safe_position.x, 511.0) and is_equal_approx(safe_position.z, -511.0)
		and is_equal_approx(safe_position.y, 13.0), str(safe_position))
	_check("v2 grid entities migrate to world centers and quarter-turn yaw",
		int(migration_result.get("migrated_from", 0)) == 2 and migrated_miner != null and migrated_smelter != null
		and migrated_miner.position.is_equal_approx(Vector3(2.0, 0.0, 2.0))
		and is_equal_approx(migrated_smelter.yaw, PI / 2.0),
		str([migrated_miner, migrated_smelter]))
	_check("v2 miner is assigned to matching registered deposit",
		migrated_miner != null and int(migrated_miner.extra.get("node_id", -1)) == 3
		and migrated.node_reservations.get(3, -1) == 5, str(migrated.node_reservations))
	_check("legacy grid belts are removed and items/materials refunded",
		not migrated.entities.has(6) and int(migration_result.get("belt_refund", {}).get("iron_ore", 0)) == 1
		and int(migration_result.get("belt_refund", {}).get("iron_plate", 0)) == 1,
		str(migration_result.get("belt_refund", {})))
	_check("migration preserves boulder and foliage world state",
		migration_result.get("world", {}).get("foliage", []).has("tree_00001")
		and int(migration_result.get("world", {}).get("boulders", {}).get("iron_a", {}).get("remaining", -1)) == 4,
		str(migration_result.get("world", {})))

	var snapped_sim: FactorySim = FactorySim.new()
	snapped_sim.register_node(12, "iron_ore", "normal", Vector3(5.0, 0.0, 2.0))
	snapped_sim.from_dict({"entities": [
		{"id": 12, "kind": "miner_mk1", "cell": [0, 0], "rotation": 0,
			"extra": {"item": "iron_ore"}, "input": {}, "output": {}}
	]})
	var snapped_miner: FactoryEntity = snapped_sim.entities.get(12)
	_check("legacy miner three metres off a matching node snaps to its centre",
		snapped_miner != null and snapped_miner.position.is_equal_approx(Vector3(5.0, 0.0, 2.0))
		and int(snapped_miner.extra.get("node_id", -1)) == 12,
		str(snapped_miner.position if snapped_miner != null else Vector3.INF))

	var priority_sim: FactorySim = FactorySim.new()
	priority_sim.register_node(13, "iron_ore", "normal", Vector3(5.0, 0.0, 2.0))
	var priority_refund: Dictionary = priority_sim.from_dict({"entities": [
		{"id": 23, "kind": "miner_mk1", "cell": [0, 0], "rotation": 0,
			"extra": {"item": "iron_ore"}, "input": {"copper_ore": 1}, "output": {"iron_ingot": 2}},
		{"id": 24, "kind": "smelter", "cell": [1, 0], "rotation": 0,
			"recipe": "iron_ingot", "extra": {}, "input": {}, "output": {}}
	]})
	_check("snapped miner overlap is refunded without displacing its restored neighbor",
		priority_sim.entities.has(24) and not priority_sim.entities.has(23)
		and priority_sim.restore_failure_count == 1
		and int(priority_refund.get("iron_plate", 0)) == int(BuildingDefs.all()["miner_mk1"]["cost"]["iron_plate"])
		and int(priority_refund.get("concrete", 0)) == int(BuildingDefs.all()["miner_mk1"]["cost"]["concrete"])
		and int(priority_refund.get("copper_ore", 0)) == 1
		and int(priority_refund.get("iron_ingot", 0)) == 2,
		str([priority_sim.entities.keys(), priority_sim.restore_failure_count, priority_refund]))

	var overlap_sim: FactorySim = FactorySim.new()
	var overlap_refund: Dictionary = overlap_sim.from_dict({"entities": [
		{"id": 20, "kind": "storage", "cell": [5, 5], "rotation": 0, "extra": {}, "input": {}, "output": {}},
		{"id": 21, "kind": "merger", "cell": [5, 5], "rotation": 0,
			"extra": {"merge_queues": {"in0": ["wire"]}},
			"input": {"iron_ore": 2}, "output": {"iron_ingot": 1}}
	]})
	_check("overlapping legacy machine failure is counted and fully refunded",
		overlap_sim.restore_failure_count == 1 and overlap_sim.entities.has(20) and not overlap_sim.entities.has(21)
		and int(overlap_refund.get("iron_plate", 0)) == int(BuildingDefs.all()["merger"]["cost"]["iron_plate"])
		and int(overlap_refund.get("iron_ore", 0)) == 2 and int(overlap_refund.get("iron_ingot", 0)) == 1
		and int(overlap_refund.get("wire", 0)) == 1,
		str([overlap_sim.restore_failure_count, overlap_refund]))
	legacy_root["version"] = 1
	legacy_file = FileAccess.open(legacy_system.save_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy_root))
	legacy_file.close()
	var v1_sim: FactorySim = FactorySim.new()
	v1_sim.register_node(3, "iron_ore", "normal", Vector3(2.0, 0.0, 2.0))
	var v1_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(v1_player)
	v1_player.set_panel_open(true)
	var v1_result: Dictionary = legacy_system.load_game(v1_sim, v1_player)
	_check("repository v1 grid saves remain loadable",
		int(v1_result.get("migrated_from", 0)) == 1 and v1_sim.entities.has(5)
		and v1_sim.node_reservations.get(3, -1) == 5, str(v1_result))
	v1_player.queue_free()

	var refund_sim: FactorySim = FactorySim.new()
	var refund_source: int = refund_sim.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "iron_ingot"})
	var refund_target: int = refund_sim.add_entity("storage", Vector3(0.0, 0.0, 8.0))
	var refund_link: Dictionary = _connect(refund_sim, "belt_mk1", refund_source, "out0", refund_target, "in0")
	var refund_belt: FactoryEntity = refund_sim.entities[int(refund_link["id"])]
	refund_belt.belt_items = [{"item": "copper_ore", "s": 0.5}]
	refund_sim.entities[refund_source].input_buffer["iron_ore"] = 2
	refund_sim.entities[refund_source].output_buffer["iron_ingot"] = 1
	var expected_belt_plates: int = ceili(float(refund_belt.extra["length"]) / 2.0)
	var refund: Dictionary = refund_sim.remove_entity_with_refund(refund_source)
	_check("dismantling refunds buffers, belt items and belt length cost",
		not refund_sim.entities.has(int(refund_link["id"]))
		and int(refund.get("iron_rod", 0)) == 5 and int(refund.get("wire", 0)) == 8
		and int(refund.get("iron_ore", 0)) == 2 and int(refund.get("iron_ingot", 0)) == 1
		and int(refund.get("copper_ore", 0)) == 1 and int(refund.get("iron_plate", 0)) == expected_belt_plates,
		str(refund))

	var merger: int = refund_sim.add_entity("merger", Vector3(50.0, 0.0, 0.0))
	refund_sim.entities[merger].extra["merge_queues"] = {"in0": ["iron_ore"], "in1": ["copper_ore", "copper_ore"]}
	var merger_refund: Dictionary = refund_sim.remove_entity_with_refund(merger)
	_check("dismantling merger refunds every queued item",
		int(merger_refund.get("iron_ore", 0)) == 1 and int(merger_refund.get("copper_ore", 0)) == 2,
		str(merger_refund))
	var take_storage: int = refund_sim.add_entity("storage", Vector3(60.0, 0.0, 0.0))
	refund_sim.entities[take_storage].input_buffer = {"iron_plate": 3, "cable": 2}
	var taken: Dictionary = refund_sim.take_storage(take_storage)
	_check("Take all moves storage contents and clears the buffer",
		taken == {"iron_plate": 3, "cable": 2} and refund_sim.entities[take_storage].input_buffer.is_empty(), str(taken))

	for path: String in [save_system.save_path, legacy_system.save_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	player.queue_free()
	restored_player.queue_free()
	migrated_player.queue_free()
	_finish_group()

func _test_diagnostics() -> void:
	var sim: FactorySim = FactorySim.new()
	sim.power.bypass = false
	var smelter: int = sim.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "iron_ingot"})
	var lines: Array[String] = sim.diagnostics(smelter)
	sim.entities[smelter].input_buffer["iron_ore"] = 1
	sim.tick(0.05)
	_check("diagnostics report input and output rates with exact recipe labels",
		lines.size() == 3 and lines[1].contains("Input Iron Ore: 0.0/min — needs 30.0/min")
		and lines[2].contains("Output Iron Ingot: 0.0/min"), str(lines))
	_check("unpowered machine has an actionable status", sim.status_for(smelter).begins_with("No power: needs 4 MW"), sim.status_for(smelter))
	_finish_group()

func _test_visual_state() -> void:
	var sim: FactorySim = FactorySim.new()
	var smelter: int = sim.add_entity("smelter", Vector3.ZERO)
	sim.tick(0.05)
	var idle: Dictionary = sim.visual_state(smelter)
	_check("visual state exposes idle status without productivity",
		idle.get("status", "") == "No recipe"
		and float(idle.get("productivity", -1.0)) == 0.0
		and bool(idle.get("powered", false)), str(idle))
	sim.entities[smelter].recipe_id = "iron_ingot"
	sim.tick(0.05)
	var starved: Dictionary = sim.visual_state(smelter)
	_check("visual state distinguishes input starvation",
		str(starved.get("status", "")).begins_with("Missing input")
		and float(starved.get("productivity", -1.0)) == 0.0, str(starved))
	sim.entities[smelter].input_buffer["iron_ore"] = 1
	sim.power.bypass = false
	sim.tick(0.05)
	var unpowered: Dictionary = sim.visual_state(smelter)
	_check("visual state marks an unpowered consumer",
		str(unpowered.get("status", "")).begins_with("No power")
		and not bool(unpowered.get("powered", true))
		and float(unpowered.get("productivity", -1.0)) == 0.0, str(unpowered))
	sim.power.bypass = true
	sim.tick(0.05)
	var running: Dictionary = sim.visual_state(smelter)
	_check("visual state scales productivity with powered running status",
		running.get("status", "") == "Running"
		and is_equal_approx(float(running.get("productivity", 0.0)), 1.0)
		and bool(running.get("powered", false)), str(running))
	var missing: Dictionary = sim.visual_state(-1)
	_check("missing visual entities return a stopped state",
		missing.get("status", "") == "Stopped"
		and float(missing.get("productivity", -1.0)) == 0.0
		and not bool(missing.get("powered", true)), str(missing))
	for bypass_enabled: bool in [true, false]:
		var tap_sim: FactorySim = FactorySim.new()
		tap_sim.register_vent("visual_vent", Vector3.ZERO)
		var tap_id: int = tap_sim.add_entity("geo_tap", Vector3.ZERO)
		tap_sim.power.bypass = bypass_enabled
		tap_sim.tick(0.05)
		var tap_state: Dictionary = tap_sim.visual_state(tap_id)
		_check("Geo Tap generates visual productivity with bypass %s" % bypass_enabled,
			tap_state.get("status", "") == "Running"
			and is_equal_approx(float(tap_state.get("productivity", 0.0)), 1.0)
			and bool(tap_state.get("powered", false)), str(tap_state))
		var vent_id: String = str(tap_sim.entities[tap_id].extra.get("vent_id", ""))
		tap_sim.vents.erase(vent_id)
		tap_sim.tick(0.05)
		var stopped_tap: Dictionary = tap_sim.visual_state(tap_id)
		_check("Geo Tap stops when its registered vent is absent",
			stopped_tap.get("status", "") == "Stopped"
			and float(stopped_tap.get("productivity", -1.0)) == 0.0, str(stopped_tap))
	_finish_group()

func _test_power_bypass() -> void:
	var bypassed: FactorySim = FactorySim.new()
	var bypass_smelter: int = bypassed.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "iron_ingot"})
	bypassed.entities[bypass_smelter].input_buffer["iron_ore"] = 1
	bypassed.power.bypass = true
	_run_for(bypassed, 2.1)
	_check("unconnected smelter produces with power bypass",
		int(bypassed.entities[bypass_smelter].output_buffer.get("iron_ingot", 0)) == 1,
		str(bypassed.entities[bypass_smelter].output_buffer))
	_check("bypass diagnostics state the hypothetical power need",
		bypassed.diagnostics(bypass_smelter)[0] == "Power: bypassed (would need 4 MW)",
		str(bypassed.diagnostics(bypass_smelter)))

	var unpowered: FactorySim = FactorySim.new()
	var unpowered_smelter: int = unpowered.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "iron_ingot"})
	unpowered.entities[unpowered_smelter].input_buffer["iron_ore"] = 1
	unpowered.power.bypass = false
	_run_for(unpowered, 2.1)
	_check("unconnected smelter stalls without power",
		int(unpowered.entities[unpowered_smelter].output_buffer.get("iron_ingot", 0)) == 0
		and unpowered.status_for(unpowered_smelter) == "No power: needs 4 MW, network supplies 0 MW",
		str([unpowered.entities[unpowered_smelter].output_buffer, unpowered.status_for(unpowered_smelter)]))

	for bypass_mode: bool in [true, false]:
		var connected: FactorySim = FactorySim.new()
		connected.register_vent("vent_a", Vector3(-8.0, 0.0, 0.0))
		connected.add_entity("geo_tap", Vector3(-8.0, 0.0, 0.0))
		connected.add_entity("power_pole", Vector3(-4.0, 0.0, 0.0))
		var connected_smelter: int = connected.add_entity("smelter", Vector3(0.0, 0.0, 6.0), 0.0,
			{"recipe": "iron_ingot"})
		connected.entities[connected_smelter].input_buffer["iron_ore"] = 1
		connected.power.bypass = bypass_mode
		_run_for(connected, 2.1)
		_check("Geo Tap, pole and smelter produce with bypass %s" % ("on" if bypass_mode else "off"),
			connected_smelter > 0 and int(connected.entities[connected_smelter].output_buffer.get("iron_ingot", 0)) == 1,
			str(connected.entities[connected_smelter].output_buffer if connected_smelter > 0 else {}))

	var real_power: FactorySim = _make_overloaded_power_sim(false)
	var bypass_power: FactorySim = _make_overloaded_power_sim(true)
	_run_for(real_power, 1.0)
	_run_for(bypass_power, 1.0)
	var real_smelt: FactoryEntity = real_power.entities[real_power.next_id - 1]
	var bypass_smelt: FactoryEntity = bypass_power.entities[bypass_power.next_id - 1]
	var real_satisfaction: float = real_power.power.satisfaction(real_smelt.id, real_power.entities)
	var real_network: int = int(real_power.power.network_for.get(real_smelt.id, -1))
	_check("overloaded network browns out in real-power mode",
		real_satisfaction > 0.0 and real_satisfaction < 1.0
		and is_equal_approx(float(real_power.power.supply_for.get(real_network, 0.0)), 50.0)
		and is_equal_approx(float(real_power.power.demand_for.get(real_network, 0.0)), 52.0)
		and real_smelt.progress < bypass_smelt.progress,
		str([real_satisfaction, real_smelt.progress, bypass_smelt.progress,
			real_power.power.supply_for.get(real_network, 0.0),
			real_power.power.demand_for.get(real_network, 0.0), real_power.entities.size()]))
	_check("overloaded network runs at full speed with bypass",
		is_equal_approx(bypass_power.power.satisfaction(bypass_smelt.id, bypass_power.entities), 1.0)
		and is_equal_approx(bypass_smelt.progress, 1.0), str(bypass_smelt.progress))

	var save_system: FactorySaveSystem = FactorySaveSystem.new()
	save_system.save_path = "user://phase4_power_test.json"
	var saved_sim: FactorySim = FactorySim.new()
	saved_sim.power.bypass = false
	var saved_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(saved_player)
	save_system.save_game(saved_sim, saved_player, 0, {}, {}, saved_sim.power.bypass)
	var restored_sim: FactorySim = FactorySim.new()
	restored_sim.power.bypass = true
	var restored_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(restored_player)
	save_system.load_game(restored_sim, restored_player)
	_check("save/load keeps the power bypass flag", not restored_sim.power.bypass, str(restored_sim.power.bypass))

	var setting: Variant = ProjectSettings.get_setting("factory/dev/power_bypass", true)
	ProjectSettings.set_setting("factory/dev/power_bypass", false)
	var save_file: FileAccess = FileAccess.open(save_system.save_path, FileAccess.READ)
	var save_data: Dictionary = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	save_data.erase("power_bypass")
	save_file = FileAccess.open(save_system.save_path, FileAccess.WRITE)
	save_file.store_string(JSON.stringify(save_data))
	save_file.close()
	restored_sim.power.bypass = true
	save_system.load_game(restored_sim, restored_player)
	_check("legacy save uses the project power bypass setting", not restored_sim.power.bypass,
		str(restored_sim.power.bypass))
	ProjectSettings.set_setting("factory/dev/power_bypass", setting)

	var launch_power: FactoryPower = FactoryPower.new()
	launch_power.apply_launch_flags(PackedStringArray(["--real-power"]))
	_check("--real-power starts with bypass off", not launch_power.bypass, str(launch_power.bypass))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.save_path))
	saved_player.queue_free()
	restored_player.queue_free()
	_finish_group()

func _make_overloaded_power_sim(bypass_mode: bool) -> FactorySim:
	var sim: FactorySim = FactorySim.new()
	sim.register_vent("vent_overload", Vector3(-40.0, 0.0, 0.0))
	sim.add_entity("geo_tap", Vector3(-40.0, 0.0, 0.0))
	for x: float in [-28.0, -8.0, 12.0, 32.0]:
		sim.add_entity("power_pole", Vector3(x, 0.0, 8.0))
	for index: int in range(13):
		var x: float = -25.0 + float(index) * 4.0
		var smelter: int = sim.add_entity("smelter", Vector3(x, 0.0, 0.0), 0.0,
			{"recipe": "iron_ingot"})
		if smelter < 0:
			continue
		sim.entities[smelter].input_buffer["iron_ore"] = 1
	sim.power.bypass = bypass_mode
	return sim

func _test_ore_boulders() -> void:
	var boulders: OreBoulders = OreBoulders.new()
	boulders.register("iron_a", "iron_ore", 8)
	var first: Dictionary = boulders.mine("iron_a", 3)
	_check("ore boulder depletes by finite units", first.get("remaining", -1) == 5
		and not bool(first.get("depleted", true)), str(first))
	var saved: Dictionary = boulders.to_dict()
	var restored: OreBoulders = OreBoulders.new()
	restored.register("iron_a", "iron_ore", 8)
	restored.from_dict(saved)
	_check("partially mined boulder persists remaining quantity",
		restored.remaining_for("iron_a") == 5, str(restored.to_dict()))
	var last: Dictionary = restored.mine("iron_a", 5)
	var exhausted: Dictionary = restored.mine("iron_a")
	_check("depleted boulder stays empty and rejects further mining",
		bool(last.get("depleted", false)) and restored.remaining_for("iron_a") == 0 and exhausted.is_empty(),
		str([last, exhausted]))
	var legacy: OreBoulders = OreBoulders.new()
	legacy.register("iron_a", "iron_ore", 8)
	legacy.from_dict({})
	_check("legacy save without boulder state keeps deposits full",
		legacy.remaining_for("iron_a") == 8, str(legacy.to_dict()))
	_finish_group()

func _test_foliage_state() -> void:
	var foliage: FoliageState = FoliageState.new()
	foliage.remove("tree_00002")
	foliage.remove("rock_00001")
	var restored: FoliageState = FoliageState.new()
	restored.from_dict(foliage.to_dict())
	_check("foliage removals survive state round-trip",
		restored.is_removed("tree_00002") and restored.is_removed("rock_00001")
		and not restored.is_removed("tree_00003")
		and restored.to_dict() == ["rock_00001", "tree_00002"], str(restored.to_dict()))
	_finish_group()

func _test_hotbar_model() -> void:
	var model: HotbarModel = HotbarModel.new()
	_check("hotbar defaults to the seven starter building slots",
		model.slots.slice(0, 7) == [
			{"type": "building", "id": "miner_mk1"},
			{"type": "building", "id": "smelter"},
			{"type": "building", "id": "constructor"},
			{"type": "building", "id": "belt_mk1"},
			{"type": "building", "id": "belt_pole"},
			{"type": "building", "id": "power_pole"},
			{"type": "building", "id": "geo_tap"}
		] and model.slots.slice(7, 10) == [{}, {}, {}], str(model.slots))
	var selected: Dictionary = model.select_slot(0, 0)
	var build_system: FactoryBuildSystem = FactoryBuildSystem.new()
	var building_action: Dictionary = model.apply_to_build_system(build_system)
	_check("building selection drives build placement",
		bool(selected.get("ok", false)) and build_system.selected == "miner_mk1"
		and building_action.get("type", "") == "building", str([selected, build_system.selected]))
	model.select_slot(0, 0)
	model.apply_to_build_system(build_system)
	_check("reselecting the selected number clears to empty hands",
		model.selected_index == -1 and build_system.selected.is_empty(), str([model.selected_index, build_system.selected]))

	model.select_slot(0, 0)
	var wrapped: Dictionary = model.cycle(-1, 0)
	_check("mouse wheel wraps across all ten slots",
		bool(wrapped.get("ok", false)) and model.selected_index == 9, str(wrapped))

	_check("hotbar item assignment succeeds", model.assign(8, "item", "iron_ore"), str(model.slot_at(8)))
	var inventory: Dictionary = {"iron_ore": 4, "iron_rod": 22, "wire": 24, "iron_plate": 5}
	_check("item quantity follows inventory changes", model.quantity(8, inventory) == 4, str(model.quantity(8, inventory)))
	inventory["iron_ore"] = 9
	_check("item quantity updates after inventory changes", model.quantity(8, inventory) == 9, str(model.quantity(8, inventory)))
	_check("building quantity is the minimum affordable count",
		model.assign(2, "building", "smelter") and model.quantity(2, inventory) == 3, str(model.quantity(2, inventory)))
	_check("belt quantity is displayed as affordable metres",
		model.assign(7, "building", "belt_mk1") and model.quantity(7, inventory) == 10, str(model.quantity(7, inventory)))

	_check("hotbar slot can be cleared", model.clear_slot(8) and model.slot_at(8).is_empty(), str(model.slot_at(8)))
	model.assign(9, "building", "assembler")
	var locked: Dictionary = model.select_slot(9, 0)
	_check("locked buildings cannot be selected", not bool(locked.get("ok", true))
		and bool(locked.get("locked", false)) and locked.get("reason", "") == "Unlocks at Tier 2", str(locked))
	var unlocked: Dictionary = model.select_slot(9, 2)
	_check("unlocked building slots select normally", bool(unlocked.get("ok", false))
		and model.selected_index == 9, str(unlocked))

	model.assign(8, "item", "iron_plate")
	var restored: HotbarModel = HotbarModel.from_dict(model.to_dict())
	var old_save: HotbarModel = HotbarModel.from_dict({})
	var item_selection: Dictionary = restored.select_slot(8, 2)
	restored.apply_to_build_system(build_system)
	_check("hotbar model save/load round-trip retains slot state",
		restored.slot_at(8) == {"type": "item", "id": "iron_plate"}
		and restored.slot_at(9) == {"type": "building", "id": "assembler"}, str(restored.to_dict()))
	_check("selecting an item slot clears placement",
		bool(item_selection.get("ok", false)) and build_system.selected.is_empty()
		and restored.selected_action().get("type", "") == "item", str([item_selection, build_system.selected]))
	_check("old saves without hotbar data receive the defaults",
		old_save.slot_at(0) == {"type": "building", "id": "miner_mk1"}
		and old_save.selected_index == -1, str(old_save.to_dict()))

	var assignment_model: HotbarModel = HotbarModel.new()
	assignment_model.selected_index = 0
	var assignment: Dictionary = assignment_model.select_or_assign("building", "storage", 1)
	_check("build-menu assignment uses the first empty slot instead of overwriting selection",
		bool(assignment.get("ok", false)) and assignment.get("selected_index", -1) == 7
		and assignment_model.slot_at(0) == {"type": "building", "id": "miner_mk1"}
		and assignment_model.slot_at(7) == {"type": "building", "id": "storage"},
		str([assignment, assignment_model.to_dict()]))

	var full_model: HotbarModel = HotbarModel.new()
	for index: int in range(HotbarModel.SLOT_COUNT):
		full_model.assign(index, "item", "iron_ore")
	full_model.selected_index = 5
	var full_slots: Array[Dictionary] = full_model.slots.duplicate(true)
	var full_result: Dictionary = full_model.select_or_assign("building", "smelter", 0)
	var full_build_system: FactoryBuildSystem = FactoryBuildSystem.new()
	if bool(full_result.get("full", false)):
		full_build_system.choose("smelter")
	_check("full hotbar leaves assignments unchanged and still allows building placement",
		not bool(full_result.get("ok", true)) and bool(full_result.get("full", false))
		and full_model.slots == full_slots and full_model.selected_index == 5
		and full_build_system.selected == "smelter"
		and full_result.get("reason", "") == "Hotbar full — hover an entry and press 1–0 to assign",
		str([full_result, full_model.to_dict(), full_build_system.selected]))
	_finish_group()

func _test_full_hotbar_build_menu_selection() -> void:
	var main_script: Script = load("res://scripts/main.gd") as Script
	var app: Node = main_script.new() as Node
	var player: FactoryPlayer = FactoryPlayer.new()
	var model: HotbarModel = app.get("hotbar_model") as HotbarModel
	for index: int in range(HotbarModel.SLOT_COUNT):
		model.assign(index, "building", "miner_mk1")
	model.selected_index = 3
	var build_system: FactoryBuildSystem = app.get("build_system") as FactoryBuildSystem
	build_system.choose("belt_mk1")
	var hud: FactoryHUD = FactoryHUD.new()
	hud.setup(app.get("sim") as FactorySim, player, model)
	get_root().add_child(hud)
	hud.show_build_menu(["storage"])
	var viewmodel: FactoryViewmodel = FactoryViewmodel.new()
	app.set("hud", hud)
	app.set("player", player)
	app.set("viewmodel", viewmodel)
	app.set("unlocked_tiers", 1)
	app.set("belt_start", {"id": 12, "port": "out0"})
	var belt_preview: MeshInstance3D = MeshInstance3D.new()
	belt_preview.visible = true
	app.set("belt_preview_visual", belt_preview)
	app.call("_select_building", "storage")
	_check("full-hotbar build selection clears stale shortcut and belt state",
		model.selected_index == -1 and app.get("belt_start").is_empty()
		and build_system.selected == "storage" and not belt_preview.visible
		and viewmodel.desired_action == {"type": "building", "id": "storage"},
		str([model.selected_index, app.get("belt_start"), build_system.selected, viewmodel.desired_action]))
	belt_preview.free()
	viewmodel.free()
	app.free()
	hud.queue_free()
	player.free()
	_finish_group()

func _test_hotbar_input_filtering() -> void:
	var hotbar: FactoryHotbar = FactoryHotbar.new()
	hotbar.configure(HotbarModel.new(), FactoryIconCache.new())
	get_root().add_child(hotbar)
	hotbar.set_interactive(true)
	var row: Control = hotbar.get_node("SlotRow") as Control
	var first_slot: Control = row.get_child(0) as Control
	_check("hotbar containers ignore panel pointer events",
		hotbar.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and row.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		str([hotbar.mouse_filter, row.mouse_filter]))
	_check("hotbar slots alone accept panel pointer events",
		first_slot.mouse_filter == Control.MOUSE_FILTER_STOP,
		str(first_slot.mouse_filter))
	hotbar.set_interactive(false)
	_check("hotbar slots ignore pointer events outside panels",
		first_slot.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		str(first_slot.mouse_filter))
	hotbar.queue_free()
	_finish_group()

func _connect(sim: FactorySim, kind: String, from_id: int, from_port: String, to_id: int, to_port: String) -> Dictionary:
	return sim.add_belt(kind, from_id, from_port, to_id, to_port, _port_curve(sim, from_id, from_port, to_id, to_port))

func _port_curve(sim: FactorySim, from_id: int, from_port: String, to_id: int, to_port: String) -> PackedVector3Array:
	var start: Dictionary = sim.port_world(from_id, from_port)
	var finish: Dictionary = sim.port_world(to_id, to_port)
	var handle: float = clampf(start["pos"].distance_to(finish["pos"]) * 0.4, 1.0, 8.0)
	return PackedVector3Array([start["pos"], start["pos"] + start["normal"] * handle,
		finish["pos"] + finish["normal"] * handle, finish["pos"]])

func _run_for(sim: FactorySim, seconds: float) -> void:
	for _step: int in range(ceili(seconds / 0.05)):
		sim.tick(0.05)

func _check(name: String, passed: bool, detail: String) -> void:
	if passed:
		print("PASS: %s" % name)
	else:
		print("FAIL: %s — %s" % [name, detail])
		failures += 1
		current_group_failures += 1

func _finish_group() -> void:
	groups += 1
	if current_group_failures == 0:
		passed_groups += 1
	current_group_failures = 0
