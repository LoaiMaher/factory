extends SceneTree

var failures: int = 0
var groups: int = 0
var passed_groups: int = 0
var current_group_failures: int = 0

func _initialize() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	_test_placement_and_ports()
	_test_glb_model_ports()
	_test_ore_node_model()
	_test_ore_node_world_normal()
	_test_deposit_reservations()
	_test_belt_validation_and_flow()
	_test_splitter_merger_backpressure()
	_test_production_and_port_routing()
	_test_recipe_less_smelter_repro()
	_test_recipe_defaults_and_input_autoselect()
	_test_mismatched_input_does_not_halt_production()
	_test_full_chain_power_and_round_trip()
	_test_save_migration_and_refunds()
	_test_diagnostics()
	_test_visual_state()
	_test_belt_audio_localization()
	_test_power_bypass()
	_test_ore_boulders()
	_test_foliage_state()
	_test_foliage_density_persistence()
	_test_foliage_chunk_visibility()
	_test_hotbar_model()
	_test_creative_mode()
	_test_full_hotbar_build_menu_selection()
	_test_creative_cursor_focus()
	_test_hotbar_input_filtering()
	_test_graphics_settings_and_persistence()
	_test_graphics_pending_preset()
	_test_grass_fade_settings()
	_test_graphics_shortcuts()
	_test_benchmark_stats_and_cli()
	_test_benchmark_route_clearance()
	_test_benchmark_no_save()
	_test_inventory_model()
	_test_inventory_gameplay()
	_test_inventory_save_migration()
	_test_cursor_stack_save()
	_test_cursor_stack_load()
	_test_creative_storage_deposits()
	_test_storage_origin_return_gain()
	_test_refund_preview()
	_test_storage_grid_mapping_refresh()
	_test_storage_stack_withdrawals()
	_test_machine_view_and_transfers()
	_test_machine_panel_refresh_and_close()
	_test_machine_panel_creative_transfers()
	print("RESULT: %d/%d test groups passed" % [passed_groups, groups])
	quit(1 if failures > 0 else 0)

func _test_inventory_model() -> void:
	var inventory := FrontierInventory.new(3)
	var leftover: int = inventory.add("iron_ore", 130)
	_check("inventory fills default 64-item stacks before empty slots",
		leftover == 0 and inventory.count("iron_ore") == 130
		and inventory.slots[0]["count"] == 64 and inventory.slots[1]["count"] == 64
		and inventory.slots[2]["count"] == 2, str(inventory.to_data()))
	var custom_stack := FrontierInventory.new(2)
	leftover = custom_stack.add("rotor", 40)
	_check("item metadata supports a custom stack cap",
		Items.stack_size("iron_ore") == 64 and Items.stack_size("rotor") == 32
		and leftover == 0 and custom_stack.slots[0]["count"] == 32
		and custom_stack.slots[1]["count"] == 8, str(custom_stack.to_data()))
	var capped_merge := FrontierInventory.new()
	capped_merge.from_data([
		{"item_id": "iron_ore", "count": 60},
		{"item_id": "iron_ore", "count": 10}
	])
	var cap_merge_ok: bool = capped_merge.move(0, 1)
	_check("move merges only up to the item stack cap",
		cap_merge_ok and capped_merge.slots[0]["count"] == 6
		and capped_merge.slots[1]["count"] == 64, str(capped_merge.to_data()))
	var full := FrontierInventory.new(1)
	leftover = full.add("iron_ore", 70)
	var rejected_add: int = full.add("copper_ore", 1)
	_check("full inventory returns leftovers without adding to overflow",
		leftover == 6 and rejected_add == 1 and full.count("iron_ore") == 64
		and full.count("copper_ore") == 0, str(full.to_data()))
	var full_inventory_rejects_add: bool = not full.can_fit({"iron_ore": 1})
	full.remove("iron_ore", 1)
	var can_fit_item: bool = full.can_fit({"iron_ore": 1})
	_check("remove is all-or-nothing",
		not full.remove("iron_ore", 65) and full.count("iron_ore") == 63
		and full_inventory_rejects_add and can_fit_item
		and full.can_afford({"iron_ore": 63}),
		str(full.to_data()))
	_check("item metadata provides recipe-role categories and descriptions",
		Items.category("iron_ore") == "raw" and Items.category("iron_ingot") == "processed"
		and Items.category("iron_plate") == "component"
		and not Items.description("iron_plate").is_empty(), Items.description("iron_plate"))

	var moves := FrontierInventory.new()
	moves.from_data([
		{"item_id": "iron_ore", "count": 10},
		{"item_id": "iron_ore", "count": 12},
		{"item_id": "copper_ore", "count": 4}
	])
	var merged: bool = moves.move(0, 1)
	var merged_count: int = int(moves.slots[1].get("count", 0))
	var swapped: bool = moves.move(1, 2)
	_check("move merges matching stacks and swaps different items",
		merged and merged_count == 22 and moves.slots[0].is_empty()
		and swapped and moves.slots[1]["item_id"] == "copper_ore"
		and moves.slots[2]["item_id"] == "iron_ore", str(moves.to_data()))

	var split_inventory := FrontierInventory.new()
	split_inventory.add("iron_ore", 9)
	var lifted: Dictionary = split_inventory.split(0)
	var remainder: Dictionary = split_inventory.place_into(1, lifted)
	var placed_one: Dictionary = split_inventory.place_into(2, {
		"item_id": "iron_ore", "count": 1
	})
	var taken_one: Dictionary = split_inventory.take_slot(2, 1)
	_check("split lifts half rounded up and place_into accepts one",
		lifted == {"item_id": "iron_ore", "count": 5}
		and split_inventory.slots[0]["count"] == 4
		and split_inventory.slots[1]["count"] == 5 and remainder.is_empty()
		and placed_one.is_empty() and taken_one == {"item_id": "iron_ore", "count": 1}
		and split_inventory.slots[2].is_empty(),
		str(split_inventory.to_data()))
	var place_inventory := FrontierInventory.new()
	place_inventory.from_data([
		{"item_id": "iron_ore", "count": 60},
		{"item_id": "copper_ore", "count": 5}
	])
	var place_remainder: Dictionary = place_inventory.place_into(0, {
		"item_id": "iron_ore", "count": 10
	})
	var place_swap: Dictionary = place_inventory.place_into(1, {
		"item_id": "iron_ore", "count": 4
	})
	_check("place_into merges to cap and swaps different item stacks",
		place_remainder == {"item_id": "iron_ore", "count": 6}
		and place_inventory.slots[0]["count"] == 64
		and place_swap == {"item_id": "copper_ore", "count": 5}
		and place_inventory.slots[1] == {"item_id": "iron_ore", "count": 4},
		str(place_inventory.to_data()))

	var sortable := FrontierInventory.new()
	sortable.from_data([
		{"item_id": "rotor", "count": 1},
		{"item_id": "iron_plate", "count": 1},
		{"item_id": "iron_ingot", "count": 1},
		{"item_id": "iron_ore", "count": 1},
		{"item_id": "copper_ore", "count": 1}
	])
	sortable.sort()
	var sorted_ids: Array[String] = []
	for slot: Dictionary in sortable.slots:
		if not slot.is_empty():
			sorted_ids.append(str(slot["item_id"]))
	var round_trip := FrontierInventory.new()
	round_trip.from_data(sortable.to_data())
	_check("sort groups category then ID and data round-trips",
		sorted_ids == ["copper_ore", "iron_ore", "iron_ingot", "iron_plate", "rotor"]
		and round_trip.totals() == sortable.totals()
		and round_trip.to_data() == sortable.to_data(), str(sorted_ids))

	var migrated := FrontierInventory.from_totals({
		"iron_ore": 6400, "copper_ore": 64
	}, 1)
	var overflow_count: int = migrated.slots.size() - migrated.capacity
	var overflow_add: int = migrated.add("iron_ore", 1)
	var migrated_iron: int = migrated.count("iron_ore")
	var overflow_remove: bool = migrated.remove("iron_ore", 1)
	_check("totals migration preserves stable order and removal-only overflow",
		migrated.slots[0]["item_id"] == "copper_ore" and overflow_count > 0
		and migrated_iron == 6400 and migrated.count("iron_ore") == 6399
		and overflow_add == 1 and overflow_remove,
		str([migrated.slots.size(), migrated.totals()]))
	_finish_group()

func _test_inventory_gameplay() -> void:
	var app: Node = (load("res://scripts/main.gd") as Script).new() as Node
	var player := FactoryPlayer.new()
	var fake_hud := FactoryHUD.new()
	fake_hud.toast_label = Label.new()
	app.set("player", player)
	app.set("hud", fake_hud)
	var terrain := FactoryTerrain.new()
	terrain._configure_noise()
	terrain._build_boulders()
	app.set("terrain", terrain)
	player.inventory = FrontierInventory.from_totals({"iron_plate": 64}, 1)
	var boulder_id: String = "near_iron_00"
	var boulder_before: int = terrain.ore_boulders.remaining_for(boulder_id)
	var mining_result: Dictionary = app.call("_mine_boulder_into_inventory", boulder_id)
	_check("full inventory blocks hand mining without depleting the boulder",
		mining_result.is_empty() and terrain.ore_boulders.remaining_for(boulder_id) == boulder_before
		and player.inventory.count("iron_plate") == 64
		and fake_hud.toast_label.text == "Inventory full", str(mining_result))

	var sim := FactorySim.new()
	var storage_id: int = sim.add_entity("storage", Vector3.ZERO)
	sim.entities[storage_id].extra["creative_built"] = true
	sim.entities[storage_id].input_buffer["iron_ore"] = 1
	var refund_player_inventory := FrontierInventory.from_totals({"iron_ore": 64}, 1)
	player.inventory = refund_player_inventory
	app.set("sim", sim)
	var dismantle_fits: bool = app.call("_dismantle_refund_fits", storage_id)
	_check("full inventory blocks dismantling before removing the entity",
		not dismantle_fits and sim.entities.has(storage_id)
		and fake_hud.toast_label.text == "Inventory full", str(sim.entities.keys()))

	var miner_sim := FactorySim.new()
	miner_sim.register_node(1, "iron_ore", "pure", Vector3.ZERO)
	var miner_id: int = miner_sim.add_entity("miner_mk1", Vector3.ZERO, 0.0, {"node_id": 1})
	app.set("sim", miner_sim)
	var miner_refund_fits: bool = app.call("_dismantle_refund_fits", miner_id)
	_check("full inventory blocks dismantling a miner on its deposit",
		not miner_refund_fits and miner_sim.entities.has(miner_id)
		and fake_hud.toast_label.text == "Inventory full", str(miner_sim.entities.keys()))

	player.inventory = FrontierInventory.new(48)
	var full_slots: Array[Dictionary] = []
	full_slots.append({"item_id": "iron_ore", "count": 64})
	for _index: int in range(47):
		full_slots.append({"item_id": "iron_ore", "count": 64})
	player.inventory.from_data(full_slots)
	var before_craft: Array[Dictionary] = player.inventory.to_data()
	var craft_ok: bool = app.call("_can_hand_craft_outputs", Recipes.all()["iron_ingot"])
	_check("hand crafting refuses an output that cannot fit after inputs",
		not craft_ok and player.inventory.to_data() == before_craft
		and fake_hud.toast_label.text == "Inventory full", str(player.inventory.totals()))

	var survival := FrontierInventory.from_totals({"iron_ore": 64 * 48}, 48)
	var creative := CreativeMode.new()
	creative.enter(survival, 2)
	creative.record_world_gain("copper_ore", 3)
	var restored: Dictionary = creative.exit()
	var restored_inventory: FrontierInventory = restored["inventory"]
	_check("Creative restores world gains to removal-only overflow",
		restored_inventory.count("iron_ore") == 64 * 48
		and restored_inventory.count("copper_ore") == 3
		and restored_inventory.slots.size() > restored_inventory.capacity
		and restored_inventory.remove("copper_ore", 1),
		str(restored_inventory.to_data()))

	var storage_sim := FactorySim.new()
	var transfer_storage: int = storage_sim.add_entity("storage", Vector3.ZERO)
	var stored: FactoryEntity = storage_sim.entities[transfer_storage]
	stored.input_buffer["iron_ore"] = 1000
	var receiver := FrontierInventory.from_totals({"iron_ore": 63}, 1)
	var inserted_full: int = storage_sim.insert_storage_item(
		transfer_storage, "copper_ore", 1)
	var transfer_count: int = receiver.fit_count("iron_ore", 100)
	var taken: int = storage_sim.take_storage_item(transfer_storage, "iron_ore", transfer_count)
	receiver.add("iron_ore", taken)
	var inserted: int = storage_sim.insert_storage_item(transfer_storage, "copper_ore", 10)
	_check("storage transfer respects capacity and moves only what fits",
		transfer_count == 1 and taken == 1 and receiver.count("iron_ore") == 64
		and inserted_full == 0 and inserted == 1
		and int(stored.input_buffer["iron_ore"]) == 999
		and int(stored.input_buffer["copper_ore"]) == 1,
		str([receiver.totals(), stored.input_buffer]))

	var storage_ui_sim := FactorySim.new()
	var storage_ui_id: int = storage_ui_sim.add_entity("storage", Vector3.ZERO)
	var storage_ui_player := FactoryPlayer.new()
	get_root().add_child(storage_ui_player)
	storage_ui_player.inventory = FrontierInventory.from_totals({"iron_ore": 10, "copper_ore": 5})
	var storage_ui_hud := FactoryHUD.new()
	storage_ui_hud.setup(storage_ui_sim, storage_ui_player)
	get_root().add_child(storage_ui_hud)
	storage_ui_hud.open_entity(storage_ui_id)
	storage_ui_hud.cursor_stack = storage_ui_player.inventory.take_slot(0, 5)
	storage_ui_hud._set_cursor_origin("player", 0, -1, "copper_ore")
	storage_ui_hud._on_storage_slot_input(0, MOUSE_BUTTON_LEFT, false)
	var empty_slot_placed: bool = storage_ui_sim.entities[storage_ui_id].input_buffer \
		== {"copper_ore": 5} and storage_ui_hud.cursor_stack.is_empty()
	storage_ui_hud.cursor_stack = storage_ui_player.inventory.take_slot(1, 10)
	storage_ui_hud._set_cursor_origin("player", 1, -1, "iron_ore")
	storage_ui_hud._on_storage_slot_input(0, MOUSE_BUTTON_LEFT, false)
	var swapped_into_storage: bool = storage_ui_sim.entities[storage_ui_id].input_buffer \
		== {"iron_ore": 10} and storage_ui_hud.cursor_stack \
			== {"item_id": "copper_ore", "count": 5}
	var input_main: Node = (load("res://scripts/main.gd") as Script).new() as Node
	input_main.set("hud", storage_ui_hud)
	storage_ui_hud.open_entity(storage_ui_id)
	var tab_event := InputEventKey.new()
	tab_event.keycode = KEY_TAB
	tab_event.pressed = true
	input_main.call("_input", tab_event)
	var tab_returned: bool = not storage_ui_hud.panel_is_open() \
		and storage_ui_hud.cursor_stack.is_empty()
	storage_ui_hud.open_entity(storage_ui_id)
	storage_ui_hud._on_storage_slot_input(0, MOUSE_BUTTON_LEFT, false)
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	input_main.call("_input", escape_event)
	var escape_returned: bool = not storage_ui_hud.panel_is_open() \
		and storage_ui_hud.cursor_stack.is_empty()
	_check("storage grid accepts cursor stacks in empty slots and swaps safely",
		empty_slot_placed and swapped_into_storage
		and tab_returned and escape_returned
		and storage_ui_sim.entities[storage_ui_id].input_buffer
			== {"iron_ore": 10, "copper_ore": 5},
			str([storage_ui_sim.entities[storage_ui_id].input_buffer, tab_returned,
				escape_returned, storage_ui_hud.cursor_stack]))
	input_main.free()
	storage_ui_hud.free()
	storage_ui_player.free()
	fake_hud.toast_label.free()
	fake_hud.free()
	player.free()
	terrain.free()
	app.free()
	_finish_group()

func _test_inventory_save_migration() -> void:
	var save_system := FactorySaveSystem.new()
	save_system.save_path = "user://inventory_migration_test.json"
	var sim := FactorySim.new()
	var player := FactoryPlayer.new()
	get_root().add_child(player)
	player.inventory = FrontierInventory.from_totals({"iron_ore": 6400, "copper_ore": 64})
	var saved: bool = save_system.save_game(sim, player, 0, {}, {})
	var file := FileAccess.open(save_system.save_path, FileAccess.READ)
	var save_data: Dictionary = {}
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			save_data = parsed
	var has_slots: bool = save_data.get("player", {}).has("inventory_slots")
	var legacy_totals: Dictionary = save_data.get("player", {}).get("inventory", {})
	var expected_totals: Dictionary = player.inventory.totals()
	var has_legacy_totals: bool = legacy_totals.size() == expected_totals.size()
	for item_id: String in expected_totals:
		has_legacy_totals = has_legacy_totals \
			and int(legacy_totals.get(item_id, -1)) == int(expected_totals[item_id])
	if save_data.has("player"):
		save_data["player"].erase("inventory_slots")
	var legacy_file := FileAccess.open(save_system.save_path, FileAccess.WRITE)
	var legacy_written: bool = false
	if legacy_file != null and save_data.has("player"):
		legacy_file.store_string(JSON.stringify(save_data))
		legacy_file.close()
		legacy_written = true
	var restored_player := FactoryPlayer.new()
	get_root().add_child(restored_player)
	var restored_sim := FactorySim.new()
	var loaded: Dictionary = save_system.load_game(restored_sim, restored_player)
	_check("legacy totals migrate in stable order and preserve overflow",
		saved and legacy_written and has_slots and has_legacy_totals and not loaded.is_empty()
		and restored_player.inventory.slots[0]["item_id"] == "copper_ore"
		and restored_player.inventory.count("iron_ore") == 6400
		and restored_player.inventory.slots.size() > restored_player.inventory.capacity,
		str([has_slots, has_legacy_totals, legacy_totals, expected_totals,
			restored_player.inventory.totals()]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.save_path))
	player.free()
	restored_player.free()
	_finish_group()

func _test_cursor_stack_save() -> void:
	var main_script: Script = load("res://scripts/main.gd") as Script
	var app: Node = main_script.new() as Node
	var sim: FactorySim = app.get("sim") as FactorySim
	var player := FactoryPlayer.new()
	get_root().add_child(player)
	player.inventory = FrontierInventory.from_totals({"iron_ore": 10})
	var hud := FactoryHUD.new()
	hud.setup(sim, player)
	get_root().add_child(hud)
	hud.cursor_stack = player.inventory.take_slot(0, 10)
	hud._set_cursor_origin("player", 0, -1, "iron_ore")
	var terrain := FactoryTerrain.new()
	terrain._configure_noise()
	terrain._build_boulders()
	var foliage := FactoryFoliage.new()
	var save_system := FactorySaveSystem.new()
	save_system.save_path = "user://cursor_stack_save_test.json"
	app.set("player", player)
	app.set("hud", hud)
	app.set("terrain", terrain)
	app.set("foliage", foliage)
	app.set("save_system", save_system)
	app.call("_save_game")
	var restored_player := FactoryPlayer.new()
	get_root().add_child(restored_player)
	var loaded: Dictionary = save_system.load_game(sim, restored_player)
	_check("saving while holding a cursor stack restores it before serialization",
		not loaded.is_empty() and hud.cursor_stack.is_empty()
		and restored_player.inventory.count("iron_ore") == 10,
		str([hud.cursor_stack, restored_player.inventory.totals()]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.save_path))
	restored_player.free()
	hud.free()
	player.free()
	terrain.free()
	foliage.free()
	app.free()
	_finish_group()

func _test_cursor_stack_load() -> void:
	var sim := FactorySim.new()
	var player := FactoryPlayer.new()
	get_root().add_child(player)
	player.inventory = FrontierInventory.from_totals({"iron_ore": 10})
	var save_system := FactorySaveSystem.new()
	save_system.save_path = "user://cursor_stack_load_test.json"
	save_system.save_game(sim, player, 0)
	player.inventory = FrontierInventory.new()
	var hud := FactoryHUD.new()
	hud.setup(sim, player)
	get_root().add_child(hud)
	hud.cursor_stack = {"item_id": "copper_ore", "count": 5}
	hud._set_cursor_origin("player", 0, -1, "copper_ore")
	var load_data: Dictionary = save_system.load_game(sim, player)
	var main_script: Script = load("res://scripts/main.gd") as Script
	var app: Node = main_script.new() as Node
	app.set("hud", hud)
	app.call("_discard_cursor_stack_after_load")
	_check("loading while holding a cursor stack discards it without duplication",
		not load_data.is_empty() and hud.cursor_stack.is_empty()
		and player.inventory.count("iron_ore") == 10
		and player.inventory.count("copper_ore") == 0,
		str([player.inventory.totals(), hud.cursor_stack]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.save_path))
	app.free()
	hud.free()
	player.free()
	_finish_group()

func _test_creative_storage_deposits() -> void:
	var sim := FactorySim.new()
	var storage_id: int = sim.add_entity("storage", Vector3.ZERO)
	var player := FactoryPlayer.new()
	get_root().add_child(player)
	player.inventory = FrontierInventory.from_totals({"iron_ore": 5})
	var hud := FactoryHUD.new()
	hud.setup(sim, player)
	get_root().add_child(hud)
	hud.selected_entity_id = storage_id
	hud.storage_open = true
	hud.set_creative_mode(true)
	hud._on_player_slot_input(0, MOUSE_BUTTON_LEFT, true)
	var shift_blocked: bool = sim.entities[storage_id].input_buffer.is_empty()
	hud.cursor_stack = {"item_id": "copper_ore", "count": 3}
	hud._set_cursor_origin("player", -1, -1, "copper_ore")
	hud._on_storage_slot_input(0, MOUSE_BUTTON_LEFT, false)
	_check("Creative inventory deposits are blocked by shift-click and cursor placement",
		shift_blocked and sim.entities[storage_id].input_buffer.is_empty()
		and player.inventory.count("iron_ore") == 5
		and hud.cursor_stack == {"item_id": "copper_ore", "count": 3}
		and hud.toast_label.text == "Creative items can't be stored",
		str([sim.entities[storage_id].input_buffer, player.inventory.totals(),
			hud.cursor_stack, hud.toast_label.text]))
	hud.free()
	player.free()
	_finish_group()

func _test_refund_preview() -> void:
	var miner_sim := FactorySim.new()
	miner_sim.register_node(1, "iron_ore", "pure", Vector3.ZERO)
	var miner_id: int = miner_sim.add_entity("miner_mk1", Vector3.ZERO, 0.0, {"node_id": 1})
	miner_sim.entities[miner_id].output_buffer["iron_ore"] = 3
	var miner_matches: bool = _refund_preview_matches_removal(miner_sim, miner_id)

	var tap_sim := FactorySim.new()
	tap_sim.register_vent("vent", Vector3.ZERO)
	var tap_id: int = tap_sim.add_entity("geo_tap", Vector3.ZERO)
	tap_sim.entities[tap_id].output_buffer["geothermal_power"] = 2
	var tap_matches: bool = _refund_preview_matches_removal(tap_sim, tap_id)

	var machine_sim := FactorySim.new()
	var machine_id: int = machine_sim.add_entity("smelter", Vector3.ZERO)
	machine_sim.entities[machine_id].input_buffer["iron_ore"] = 7
	machine_sim.entities[machine_id].output_buffer["iron_ingot"] = 4
	var machine_matches: bool = _refund_preview_matches_removal(machine_sim, machine_id)

	var belt_sim := FactorySim.new()
	var source_id: int = belt_sim.add_entity("smelter", Vector3.ZERO)
	var target_id: int = belt_sim.add_entity("storage", Vector3(0.0, 0.0, 10.0))
	var belt_result: Dictionary = _connect(belt_sim, "belt_mk1", source_id, "out0",
		target_id, "in0")
	var belt_id: int = int(belt_result.get("id", -1))
	if belt_id >= 0:
		var belt_items: Array[Dictionary] = [
			{"item": "copper_ore", "s": 0.5, "born_at": 0.0}
		]
		belt_sim.entities[belt_id].belt_items = belt_items
	var belt_matches: bool = belt_id >= 0 \
		and _refund_preview_matches_removal(belt_sim, source_id)
	_check("refund preview matches removal for miner, geo tap, buffers, and loaded belts",
		miner_matches and tap_matches and machine_matches and belt_matches,
		str([miner_matches, tap_matches, machine_matches, belt_result, belt_matches]))
	_finish_group()

func _refund_preview_matches_removal(sim: FactorySim, entity_id: int) -> bool:
	var expected: Dictionary = sim.preview_refund(entity_id)
	var actual: Dictionary = sim.remove_entity_with_refund(entity_id)
	return expected == actual

func _test_storage_grid_mapping_refresh() -> void:
	var sim := FactorySim.new()
	var source_id: int = sim.add_entity("smelter", Vector3.ZERO)
	var storage_id: int = sim.add_entity("storage", Vector3(0.0, 0.0, 10.0))
	sim.entities[storage_id].input_buffer["iron_ore"] = 3
	var belt_result: Dictionary = _connect(sim, "belt_mk1", source_id, "out0",
		storage_id, "in0")
	var belt_id: int = int(belt_result.get("id", -1))
	if belt_id >= 0:
		var belt: FactoryEntity = sim.entities[belt_id]
		belt.belt_items = [{
			"item": "copper_ore",
			"s": float(belt.extra["length"]) - 0.01,
			"born_at": -1.0
		}]
	var player := FactoryPlayer.new()
	get_root().add_child(player)
	var hud := FactoryHUD.new()
	hud.setup(sim, player)
	get_root().add_child(hud)
	hud.open_entity(storage_id)
	var initial_slot_item: String = str(hud.storage_slot_stacks[0].get("item_id", ""))
	sim.tick(0.05)
	hud._process(0.016)
	var rendered_slot_id: int = hud.storage_grid.get_child(0).get_instance_id()
	hud._refresh_storage_grid()
	var nodes_preserved: bool = hud.storage_grid.get_child(0).get_instance_id() == rendered_slot_id
	var copper_slot: int = -1
	for index: int in range(hud.storage_slot_stacks.size()):
		if str(hud.storage_slot_stacks[index].get("item_id", "")) == "copper_ore":
			copper_slot = index
			break
	var displayed_item: String = str(hud.storage_slot_stacks[copper_slot].get("item_id", "")) \
		if copper_slot >= 0 else ""
	hud._on_storage_slot_input(copper_slot, MOUSE_BUTTON_LEFT, false)
	_check("storage contents refresh keeps nodes stable and clicks withdraw the displayed belt item",
		belt_id >= 0 and sim.entities[storage_id].input_buffer.get("copper_ore", 0) == 0
		and sim.entities[storage_id].input_buffer.get("iron_ore", 0) == 3
		and nodes_preserved and displayed_item == "copper_ore"
		and initial_slot_item == "iron_ore"
		and hud.cursor_stack.get("item_id", "") == "copper_ore",
		str([belt_result, hud.storage_slot_stacks, hud.cursor_stack,
			sim.entities[storage_id].input_buffer, nodes_preserved]))
	hud.free()
	player.free()
	_finish_group()

func _test_storage_stack_withdrawals() -> void:
	var sim := FactorySim.new()
	var storage_id: int = sim.add_entity("storage", Vector3.ZERO)
	sim.entities[storage_id].input_buffer["iron_ore"] = 100
	var player := FactoryPlayer.new()
	get_root().add_child(player)
	var hud := FactoryHUD.new()
	hud.setup(sim, player)
	get_root().add_child(hud)
	hud.open_entity(storage_id)

	var displayed_36: bool = int(hud.storage_slot_stacks[1].get("count", 0)) == 36
	hud._on_storage_slot_input(1, MOUSE_BUTTON_LEFT, false)
	var left_count: int = int(hud.cursor_stack.get("count", 0))
	var left_total: int = int(sim.entities[storage_id].input_buffer.get("iron_ore", 0))
	var left_capped: bool = left_count <= Items.stack_size("iron_ore")
	hud._return_cursor_stack()

	hud._on_storage_slot_input(0, MOUSE_BUTTON_RIGHT, false)
	var right_count: int = int(hud.cursor_stack.get("count", 0))
	var right_total: int = int(sim.entities[storage_id].input_buffer.get("iron_ore", 0))
	var right_capped: bool = right_count <= Items.stack_size("iron_ore")
	hud._return_cursor_stack()

	var shift_slot_count: int = int(hud.storage_slot_stacks[1].get("count", 0))
	hud._on_storage_slot_input(1, MOUSE_BUTTON_LEFT, true)
	var shift_inventory_count: int = player.inventory.count("iron_ore")
	var shift_storage_count: int = int(sim.entities[storage_id].input_buffer.get("iron_ore", 0))
	_check("storage withdrawals use only the clicked rendered stack and cap cursor stacks",
		displayed_36 and left_count == 36 and left_total == 64 and left_capped
		and right_count == 32 and right_total == 68 and right_capped
		and shift_slot_count == 36 and shift_inventory_count == 36
		and shift_storage_count == 64 and hud.cursor_stack.is_empty(),
		str([displayed_36, left_count, left_total, left_capped,
			right_count, right_total, right_capped, shift_slot_count,
			shift_inventory_count, shift_storage_count]))
	hud.free()
	player.free()
	_finish_group()

func _test_storage_origin_return_gain() -> void:
	var sim := FactorySim.new()
	var storage_id: int = sim.add_entity("storage", Vector3.ZERO)
	sim.entities[storage_id].input_buffer["copper_ore"] = 1
	sim.take_storage_item(storage_id, "copper_ore", 1)
	sim.entities[storage_id].input_buffer = {"iron_ore": 1000}
	var survival := FrontierInventory.from_totals({"iron_ore": 64 * 48}, 48)
	var creative := CreativeMode.new()
	creative.enter(survival, 0)
	var player := FactoryPlayer.new()
	get_root().add_child(player)
	player.inventory = creative.inventory
	var hud := FactoryHUD.new()
	hud.setup(sim, player)
	get_root().add_child(hud)
	hud.set_creative_mode(true)
	hud.world_item_collected.connect(creative.record_world_gain)
	hud.cursor_stack = {"item_id": "copper_ore", "count": 1}
	hud._set_cursor_origin("storage", 0, storage_id, "copper_ore")
	hud._return_cursor_stack()
	var restored: Dictionary = creative.exit()
	var restored_inventory: FrontierInventory = restored.get("inventory")
	_check("Creative storage-origin cursor return records a gain when storage is full",
		sim.entities[storage_id].input_buffer.get("copper_ore", 0) == 0
		and hud.cursor_stack.is_empty()
		and restored_inventory.count("copper_ore") == 1
		and restored_inventory.slots.size() > restored_inventory.capacity,
		str([sim.entities[storage_id].input_buffer, restored_inventory.to_data()]))
	hud.free()
	player.free()
	_finish_group()

func _test_machine_view_and_transfers() -> void:
	var running_sim := FactorySim.new()
	var running_id: int = running_sim.add_entity("smelter", Vector3.ZERO, 0.0,
		{"recipe": "iron_ingot"})
	running_sim.entities[running_id].input_buffer["iron_ore"] = 1
	running_sim.power.bypass = true
	running_sim.tick(0.05)
	var running_view: Dictionary = running_sim.machine_view(running_id)
	var running_inputs: Array = running_view.get("inputs", [])
	_check("machine view exposes running recipe, buffers, rates, and progress",
		running_view.get("state", "") == "running"
		and running_view.get("recipe_id", "") == "iron_ingot"
		and is_equal_approx(float(running_view.get("cycle_seconds", 0.0)), 2.0)
		and is_equal_approx(float(running_view.get("progress", 0.0)), 0.025)
		and running_inputs.size() == 1
		and running_inputs[0].get("item_id", "") == "iron_ore"
		and int(running_inputs[0].get("count", 0)) == 1
		and int(running_inputs[0].get("maximum", 0)) == 10
		and is_equal_approx(float(running_inputs[0].get("needs_per_min", 0.0)), 30.0),
		str(running_view))

	var waiting_sim := FactorySim.new()
	var waiting_id: int = waiting_sim.add_entity("constructor", Vector3.ZERO)
	waiting_sim.tick(0.05)
	var waiting_view: Dictionary = waiting_sim.machine_view(waiting_id)
	_check("machine view reports waiting for input",
		waiting_view.get("state", "") == "waiting_input"
		and waiting_view.get("display_status", "") == "Waiting for input"
		and str(waiting_view.get("why", "")).contains("needs"),
		str(waiting_view))

	var full_sim := FactorySim.new()
	var full_id: int = full_sim.add_entity("assembler", Vector3.ZERO)
	full_sim.entities[full_id].output_buffer["hull_panel"] = 20
	full_sim.tick(0.05)
	var full_view: Dictionary = full_sim.machine_view(full_id)
	_check("machine view reports output-full status and buffered output",
		full_view.get("state", "") == "output_full"
		and full_view.get("display_status", "") == "Output full"
		and int(full_view.get("output_buffer", {}).get("hull_panel", 0)) == 20,
		str(full_view))

	var unpowered_sim := FactorySim.new()
	var unpowered_id: int = unpowered_sim.add_entity("smelter", Vector3.ZERO)
	unpowered_sim.entities[unpowered_id].input_buffer["iron_ore"] = 1
	unpowered_sim.power.bypass = false
	unpowered_sim.tick(0.05)
	var unpowered_view: Dictionary = unpowered_sim.machine_view(unpowered_id)
	_check("machine view reports real-power network state",
		unpowered_view.get("state", "") == "no_power"
		and not bool(unpowered_view.get("power_bypassed", true))
		and float(unpowered_view.get("power_draw_mw", -1.0)) == 0.0
		and str(unpowered_view.get("power_state", "")).contains("No connected network"),
		str(unpowered_view))

	var insert_sim := FactorySim.new()
	var insert_id: int = insert_sim.add_entity("smelter", Vector3.ZERO, 0.0,
		{"recipe": "iron_ingot"})
	var inserted: int = insert_sim.insert_input_items(insert_id, "iron_ore", 12)
	var wrong_item: int = insert_sim.insert_input_items(insert_id, "copper_ore", 1)
	_check("insert_input_items respects buffer maximum and rejects wrong items",
		inserted == 10 and wrong_item == 0
		and int(insert_sim.entities[insert_id].input_buffer.get("iron_ore", 0)) == 10,
		str([inserted, wrong_item, insert_sim.entities[insert_id].input_buffer]))

	var output_sim := FactorySim.new()
	var output_id: int = output_sim.add_entity("smelter", Vector3.ZERO)
	output_sim.entities[output_id].output_buffer["iron_ingot"] = 10
	var receiving_inventory := FrontierInventory.new(1)
	receiving_inventory.add("iron_ingot", 60)
	var fits: int = receiving_inventory.fit_count("iron_ingot", 10)
	var taken: int = output_sim.take_output_items(output_id, "iron_ingot", fits)
	receiving_inventory.add("iron_ingot", taken)
	_check("take_output_items transfers only the amount that fits",
		fits == 4 and taken == 4 and receiving_inventory.count("iron_ingot") == 64
		and int(output_sim.entities[output_id].output_buffer.get("iron_ingot", 0)) == 6,
		str([fits, taken, receiving_inventory.totals(),
			output_sim.entities[output_id].output_buffer]))

	var miner_sim := FactorySim.new()
	miner_sim.register_node(7, "iron_ore", "pure", Vector3(20.0, 0.0, 10.0), 120.0)
	var miner_id: int = miner_sim.add_entity("miner_mk1", Vector3(20.0, 0.0, 10.0),
		0.0, {"node_id": 7})
	var miner_view: Dictionary = miner_sim.machine_view(miner_id)
	_check("miner view exposes deposit item, purity, and rate",
		miner_view.get("deposit_item", "") == "iron_ore"
		and miner_view.get("deposit_purity", "") == "pure"
		and is_equal_approx(float(miner_view.get("deposit_rate", 0.0)), 120.0)
		and is_equal_approx(float(miner_view.get("maximum_rate", 0.0)), 120.0),
		str(miner_view))
	_finish_group()

func _test_machine_panel_refresh_and_close() -> void:
	var sim := FactorySim.new()
	var entity_id: int = sim.add_entity("smelter", Vector3.ZERO)
	var player := FactoryPlayer.new()
	get_root().add_child(player)
	var hud := FactoryHUD.new()
	hud.setup(sim, player)
	get_root().add_child(hud)
	hud.open_entity(entity_id)
	var machine_panel: FactoryMachinePanel = hud.machine_panel
	var child_ids: Array[int] = []
	for child: Node in machine_panel.get_children():
		child_ids.append(child.get_instance_id())
	var recipe_selector_id: int = machine_panel.recipe_selector.get_instance_id()
	machine_panel.refresh()
	machine_panel.refresh()
	var refreshed_ids: Array[int] = []
	for child: Node in machine_panel.get_children():
		refreshed_ids.append(child.get_instance_id())
	var preserved: bool = child_ids == refreshed_ids \
		and recipe_selector_id == machine_panel.recipe_selector.get_instance_id()
	sim.remove_entity_with_refund(entity_id)
	hud._process(0.2)
	_check("machine refresh preserves child IDs and closes when its entity is removed",
		preserved and not hud.panel_is_open() and hud.machine_panel == null,
		str([child_ids, refreshed_ids, hud.panel_is_open()]))
	hud.free()
	player.free()
	_finish_group()

func _test_machine_panel_creative_transfers() -> void:
	var sim := FactorySim.new()
	var entity_id: int = sim.add_entity("smelter", Vector3.ZERO, 0.0, {
		"recipe": "iron_ingot"
	})
	sim.entities[entity_id].output_buffer["iron_ingot"] = 2
	var creative := CreativeMode.new()
	creative.enter(FrontierInventory.new(), 0)
	var player := FactoryPlayer.new()
	get_root().add_child(player)
	player.inventory = creative.inventory
	var hud := FactoryHUD.new()
	hud.setup(sim, player)
	get_root().add_child(hud)
	hud.set_creative_mode(true)
	hud.world_item_collected.connect(creative.record_world_gain)
	hud.open_entity(entity_id)
	var machine_panel: FactoryMachinePanel = hud.machine_panel
	player.inventory.add("iron_ore", 5)
	machine_panel._on_inventory_slot_input(0, MOUSE_BUTTON_LEFT, true)
	var creative_input_blocked: bool = player.inventory.count("iron_ore") == 5 \
		and sim.entities[entity_id].input_buffer.is_empty()
	machine_panel._take_output()
	var output_count: int = int(creative.world_gains.get("iron_ingot", 0))
	var restored: Dictionary = creative.exit()
	var survival_inventory: FrontierInventory = restored.get("inventory")
	hud.set_creative_mode(false)
	player.inventory = FrontierInventory.from_totals({"iron_ore": 3})
	machine_panel._on_inventory_slot_input(0, MOUSE_BUTTON_LEFT, true)
	_check("Creative blocks machine input deposits but tracks collected output as a gain",
		creative_input_blocked and output_count == 2
		and survival_inventory.count("iron_ingot") == 2
		and sim.entities[entity_id].input_buffer.get("iron_ore", 0) == 3
		and player.inventory.count("iron_ore") == 0,
		str([creative_input_blocked, output_count, survival_inventory.totals(),
			sim.entities[entity_id].input_buffer]))
	hud.free()
	player.free()
	_finish_group()

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
		port.get("pos", Vector3.ZERO).is_equal_approx(Vector3(-1.0, 1.0, 2.0))
		and port.get("normal", Vector3.ZERO).is_equal_approx(Vector3.BACK),
		str(port))
	_finish_group()

func _test_glb_model_ports() -> void:
	var model_kinds: Array[String] = [
		"miner_mk1", "smelter", "constructor", "assembler", "storage", "geo_tap",
		"splitter", "merger", "belt_pole", "power_pole", "spire"
	]
	for kind: String in model_kinds:
		var asset_name: String = "ascent_spire" if kind == "spire" else kind
		var packed: PackedScene = load("res://assets/models/%s.glb" % asset_name) as PackedScene
		if packed == null:
			_check("%s model asset exists" % kind, false, asset_name)
			continue
		var model: Node3D = packed.instantiate() as Node3D
		for definition: Dictionary in BuildingDefs.all().get(kind, {}).get("ports", []):
			var direction: String = str(definition["dir"])
			var index: int = int(str(definition["id"]).trim_prefix(direction))
			var port: Node3D = model.find_child("Port_%s_%d" % [direction.capitalize(), index], true, false) as Node3D
			if port == null:
				_check("%s %s GLB port exists" % [kind, definition["id"]], false, str(model.get_children()))
				continue
			var transform: Transform3D = port.transform
			var ancestor: Node = port.get_parent()
			while ancestor != null and ancestor != model:
				transform = (ancestor as Node3D).transform * transform
				ancestor = ancestor.get_parent()
			var normal: Vector3 = (transform.basis * Vector3.FORWARD).normalized()
			_check("%s %s GLB port matches BuildingDefs within 5 cm" % [kind, definition["id"]],
				transform.origin.distance_to(definition["pos"]) <= 0.05
				and normal.distance_to(definition["normal"]) <= 0.05,
				str([transform.origin, definition["pos"], normal, definition["normal"]]))
		model.free()
	_finish_group()

func _test_ore_node_model() -> void:
	var packed: PackedScene = load("res://assets/models/ore_node.glb") as PackedScene
	_check("radial ore-node GLB is available", packed != null, "assets/models/ore_node.glb")
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		for variant: String in ["OreNode_A", "OreNode_B", "OreNode_C"]:
			var part: Node3D = model.find_child(variant, true, false) as Node3D
			var meshes: Array[Node] = part.find_children("*", "MeshInstance3D", true, false) if part != null else []
			_check("%s contains radial slab geometry" % variant,
				part != null and not meshes.is_empty()
				and (meshes[0] as MeshInstance3D).mesh.get_surface_count() > 0,
				str(meshes.size()))
			var maximum_height: float = -1000000.0
			for raw_mesh: Node in meshes:
				var mesh_node: MeshInstance3D = raw_mesh as MeshInstance3D
				if mesh_node.mesh == null:
					continue
				var mesh_transform: Transform3D = mesh_node.transform
				var ancestor: Node = mesh_node.get_parent()
				while ancestor != null and ancestor != model:
					mesh_transform = (ancestor as Node3D).transform * mesh_transform
					ancestor = ancestor.get_parent()
				var bounds: AABB = mesh_node.mesh.get_aabb()
				for corner_x: int in range(2):
					for corner_y: int in range(2):
						for corner_z: int in range(2):
							var corner: Vector3 = bounds.position + Vector3(
								bounds.size.x * float(corner_x),
								bounds.size.y * float(corner_y),
								bounds.size.z * float(corner_z))
							maximum_height = maxf(maximum_height, (mesh_transform * corner).y)
			_check("%s ore slabs stay nearly flush with terrain" % variant,
				maximum_height >= 0.15 and maximum_height <= 0.35,
				"max height %.3f m" % maximum_height)
		model.free()
	_check("shared ore-node shader is available",
		load("res://shaders/resource_node.gdshader") is Shader,
		"shaders/resource_node.gdshader")
	_finish_group()

func _test_ore_node_world_normal() -> void:
	var terrain: FactoryTerrain = FactoryTerrain.new()
	terrain._configure_noise()
	var x: float = 15.0
	var z: float = 340.0
	var slope_x: float = (terrain.height_at(x + 1.0, z) - terrain.height_at(x - 1.0, z)) * 0.5
	var slope_z: float = (terrain.height_at(x, z + 1.0) - terrain.height_at(x, z - 1.0)) * 0.5
	var expected: Vector3 = Vector3(-slope_x, 1.0, -slope_z).normalized()
	var actual: Vector3 = terrain.world_surface_normal_at(x, z)
	_check("sloped resource-node normal follows world height gradient",
		expected.y < 0.99999 and actual.distance_to(expected) < 0.00001,
		str([actual, expected, slope_x, slope_z]))
	terrain.free()
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
	incompatible.entities[copper_smelter].output_buffer["copper_ingot"] = 1
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

func _test_recipe_less_smelter_repro() -> void:
	var sim: FactorySim = FactorySim.new()
	sim.power.bypass = true
	sim.register_node(51, "iron_ore", "normal", Vector3.ZERO, 60.0)
	var miner: int = sim.add_entity("miner_mk1", Vector3.ZERO, 0.0, {"node_id": 51})
	var smelter: int = sim.add_entity("smelter", Vector3(0.0, 0.0, 6.0))
	var belt_id: int = int(_connect(sim, "belt_mk1", miner, "out0", smelter, "in0").get("id", -1))
	_run_for(sim, 25.0)
	var smelter_entity: FactoryEntity = sim.entities[smelter]
	var belt: FactoryEntity = sim.entities[belt_id]
	_check("recipe-less smelter receives miner ore and produces iron ingots",
		miner > 0 and smelter > 0 and belt_id > 0
		and int(smelter_entity.output_buffer.get("iron_ingot", 0)) > 0,
		str([smelter_entity.recipe_id, belt.belt_items,
			smelter_entity.input_buffer, smelter_entity.output_buffer]))
	_finish_group()

func _test_recipe_defaults_and_input_autoselect() -> void:
	_check("machine recipe defaults use the first recipe in definitions",
		Recipes.default_for("smelter") == "iron_ingot"
		and Recipes.default_for("constructor") == "iron_plate"
		and Recipes.default_for("assembler") == "hull_panel",
		str([Recipes.default_for("smelter"), Recipes.default_for("constructor"),
			Recipes.default_for("assembler")]))

	var copper_sim: FactorySim = FactorySim.new()
	var copper_smelter: int = copper_sim.add_entity("smelter", Vector3.ZERO)
	var switched: bool = copper_sim.try_insert(copper_smelter, "copper_ore", "in0")
	_run_for(copper_sim, 2.1)
	var copper_entity: FactoryEntity = copper_sim.entities[copper_smelter]
	_check("fresh smelter auto-selects copper ingots and processes copper ore",
		copper_entity.recipe_id == "copper_ingot" and switched
		and int(copper_entity.output_buffer.get("copper_ingot", 0)) > 0,
		str([copper_entity.recipe_id, copper_entity.input_buffer, copper_entity.output_buffer]))
	var recipe_hud: FactoryHUD = FactoryHUD.new()
	var recipe_select: OptionButton = recipe_hud.create_recipe_selector(copper_entity)
	_check("recipe dropdown can reselect its current automatic recipe",
		recipe_select.allow_reselect and recipe_select.selected > 0
		and recipe_select.get_item_text(recipe_select.selected) == "Copper Ingot (auto)",
		str([recipe_select.allow_reselect, recipe_select.selected,
			recipe_select.get_item_text(recipe_select.selected)]))
	recipe_select.free()
	recipe_hud.free()
	_check("machine panel marks unlocked recipes as automatic",
		FactoryHUD.recipe_option_text(copper_entity, "copper_ingot") == "Copper Ingot (auto)",
		FactoryHUD.recipe_option_text(copper_entity, "copper_ingot"))

	var input_buffer_sim: FactorySim = FactorySim.new()
	var input_buffer_smelter: int = input_buffer_sim.add_entity("smelter", Vector3.ZERO)
	input_buffer_sim.entities[input_buffer_smelter].input_buffer["iron_ore"] = 1
	var input_buffer_switch: bool = input_buffer_sim.try_insert(input_buffer_smelter, "copper_ore", "in0")
	_check("smelter with input buffered never switches recipes",
		not input_buffer_switch
		and input_buffer_sim.entities[input_buffer_smelter].recipe_id == "iron_ingot",
		str(input_buffer_sim.entities[input_buffer_smelter].input_buffer))

	var output_buffer_sim: FactorySim = FactorySim.new()
	var output_buffer_smelter: int = output_buffer_sim.add_entity("smelter", Vector3.ZERO)
	output_buffer_sim.entities[output_buffer_smelter].output_buffer["iron_ingot"] = 1
	var output_buffer_switch: bool = output_buffer_sim.try_insert(output_buffer_smelter, "copper_ore", "in0")
	_check("smelter with output buffered never switches recipes",
		not output_buffer_switch
		and output_buffer_sim.entities[output_buffer_smelter].recipe_id == "iron_ingot",
		str(output_buffer_sim.entities[output_buffer_smelter].output_buffer))

	var locked_sim: FactorySim = FactorySim.new()
	var locked_smelter: int = locked_sim.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "copper_ingot"})
	var locked_accept: bool = locked_sim.try_insert(locked_smelter, "iron_ore", "in0")
	var mismatch_diagnostic: String = "Input Iron Ore doesn't match recipe Copper Ingot"
	_check("explicit recipe remains locked when a different input arrives",
		not locked_accept and locked_sim.entities[locked_smelter].recipe_id == "copper_ingot"
		and bool(locked_sim.entities[locked_smelter].extra.get("recipe_locked", false))
		and locked_sim.diagnostics(locked_smelter).has(mismatch_diagnostic),
		str([locked_sim.entities[locked_smelter].recipe_id,
			locked_sim.entities[locked_smelter].extra, locked_sim.diagnostics(locked_smelter)]))
	_check("machine panel omits automatic marker for locked recipes",
		FactoryHUD.recipe_option_text(locked_sim.entities[locked_smelter], "copper_ingot") == "Copper Ingot",
		FactoryHUD.recipe_option_text(locked_sim.entities[locked_smelter], "copper_ingot"))

	var menu_sim: FactorySim = FactorySim.new()
	var menu_smelter: int = menu_sim.add_entity("smelter", Vector3.ZERO)
	_check("machine-panel recipe selection locks the selected recipe",
		menu_sim.set_recipe(menu_smelter, "copper_ingot")
		and menu_sim.entities[menu_smelter].recipe_id == "copper_ingot"
		and bool(menu_sim.entities[menu_smelter].extra.get("recipe_locked", false)),
		str(menu_sim.entities[menu_smelter].extra))

	var progress_sim: FactorySim = FactorySim.new()
	var progress_smelter: int = progress_sim.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "iron_ingot"})
	var progress_entity: FactoryEntity = progress_sim.entities[progress_smelter]
	progress_entity.progress = 1.2
	progress_entity.extra["input_mismatch"] = "copper_ore"
	var relock_result: bool = progress_sim.set_recipe(progress_smelter, "iron_ingot")
	_check("reselecting the current recipe preserves progress and mismatch",
		relock_result and progress_entity.progress == 1.2
		and bool(progress_entity.extra.get("recipe_locked", false))
		and progress_entity.extra.get("input_mismatch") == "copper_ore",
		str([progress_entity.recipe_id, progress_entity.progress, progress_entity.extra]))
	var change_result: bool = progress_sim.set_recipe(progress_smelter, "copper_ingot")
	_check("changing recipes clears progress and mismatch",
		change_result and progress_entity.recipe_id == "copper_ingot"
		and progress_entity.progress == 0.0
		and not progress_entity.extra.has("input_mismatch"),
		str([progress_entity.recipe_id, progress_entity.progress, progress_entity.extra]))

	var default_saved_sim: FactorySim = FactorySim.new()
	var default_saved_smelter: int = default_saved_sim.add_entity("smelter", Vector3.ZERO)
	var default_saved_data: Dictionary = default_saved_sim.to_dict()
	var default_restored: FactorySim = FactorySim.new()
	default_restored.from_dict(default_saved_data)
	var default_restored_entity: FactoryEntity = default_restored.entities.get(default_saved_smelter) as FactoryEntity
	var auto_switch_after_load: bool = (
		default_restored_entity != null
		and not bool(default_restored_entity.extra.get("recipe_locked", true))
		and default_restored.try_insert(default_saved_smelter, "copper_ore", "in0"))
	_check("default recipe remains auto-selectable after save/load",
		auto_switch_after_load and default_restored_entity.recipe_id == "copper_ingot",
		str(default_restored.entities.get(default_saved_smelter)))

	var saved_sim: FactorySim = FactorySim.new()
	var saved_smelter: int = saved_sim.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "copper_ingot"})
	var saved_data: Dictionary = saved_sim.to_dict()
	var restored: FactorySim = FactorySim.new()
	restored.from_dict(saved_data)
	_check("save/load retains an explicitly selected machine recipe",
		restored.entities.has(saved_smelter)
		and restored.entities[saved_smelter].recipe_id == "copper_ingot"
		and bool(restored.entities[saved_smelter].extra.get("recipe_locked", false)),
		str(restored.entities.get(saved_smelter).recipe_id if restored.entities.has(saved_smelter) else "missing"))

	var legacy_locked_data: Dictionary = saved_data.duplicate(true)
	var legacy_locked_entities: Array = legacy_locked_data["entities"]
	var legacy_locked_smelter: Dictionary = legacy_locked_entities[0].duplicate(true)
	legacy_locked_smelter["extra"].erase("recipe")
	legacy_locked_smelter["extra"].erase("recipe_locked")
	legacy_locked_entities[0] = legacy_locked_smelter
	legacy_locked_data["entities"] = legacy_locked_entities
	var legacy_locked_restored: FactorySim = FactorySim.new()
	legacy_locked_restored.from_dict(legacy_locked_data)
	var legacy_locked_entity: FactoryEntity = legacy_locked_restored.entities.get(saved_smelter) as FactoryEntity
	var legacy_rejects_wrong_input: bool = (
		legacy_locked_entity != null
		and not legacy_locked_restored.try_insert(saved_smelter, "iron_ore", "in0"))
	_check("legacy save with a recipe but no lock flag restores the recipe as locked",
		legacy_rejects_wrong_input and legacy_locked_entity.recipe_id == "copper_ingot"
		and bool(legacy_locked_entity.extra.get("recipe_locked", false)),
		str(legacy_locked_restored.entities.get(saved_smelter)))

	var legacy_data: Dictionary = saved_data.duplicate(true)
	var legacy_entities: Array = legacy_data["entities"]
	var legacy_smelter: Dictionary = legacy_entities[0].duplicate(true)
	legacy_smelter.erase("recipe")
	legacy_smelter["extra"].erase("recipe")
	legacy_entities[0] = legacy_smelter
	legacy_data["entities"] = legacy_entities
	var legacy_restored: FactorySim = FactorySim.new()
	legacy_restored.from_dict(legacy_data)
	_check("saved machines without a recipe receive the machine default",
		legacy_restored.entities.has(saved_smelter)
		and legacy_restored.entities[saved_smelter].recipe_id == "iron_ingot",
		str(legacy_restored.entities.get(saved_smelter).recipe_id
			if legacy_restored.entities.has(saved_smelter) else "missing"))
	_finish_group()

func _test_mismatched_input_does_not_halt_production() -> void:
	var sim: FactorySim = FactorySim.new()
	sim.power.bypass = true
	var storage: int = sim.add_entity("storage", Vector3(0.0, 0.0, -8.0))
	var smelter: int = sim.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "iron_ingot"})
	var belt_id: int = int(_connect(sim, "belt_mk1", storage, "out0", smelter, "in0").get("id", -1))
	sim.entities[smelter].input_buffer["iron_ore"] = 2
	var belt: FactoryEntity = sim.entities[belt_id]
	belt.belt_items = [{
		"item": "copper_ore",
		"s": float(belt.extra["length"]),
		"born_at": -1.0
	}]
	sim.tick(4.1)
	var mismatch: String = "Input Copper Ore doesn't match recipe Iron Ingot"
	var smelter_entity: FactoryEntity = sim.entities[smelter]
	_check("locked mismatch backs up while buffered iron still produces",
		int(smelter_entity.output_buffer.get("iron_ingot", 0)) == 1
		and smelter_entity.status == mismatch
		and sim.diagnostics(smelter).has(mismatch),
		str([smelter_entity.input_buffer, smelter_entity.output_buffer,
			smelter_entity.status, sim.diagnostics(smelter)]))
	sim.remove_entity_with_refund(belt_id)
	sim.tick(0.05)
	_check("removing the rejecting belt clears the transient mismatch",
		not smelter_entity.extra.has("input_mismatch")
		and not sim.diagnostics(smelter).has(mismatch)
		and not smelter_entity.status.contains("doesn't match"),
		str([smelter_entity.extra, smelter_entity.status, sim.diagnostics(smelter)]))
	_finish_group()

func _belt_items_match(expected: Array, actual: Array) -> bool:
	if expected.size() != actual.size():
		return false
	for index: int in range(expected.size()):
		var expected_item: Dictionary = expected[index]
		var actual_item: Dictionary = actual[index]
		if str(expected_item.get("item", "")) != str(actual_item.get("item", "")):
			return false
		for field: String in ["s", "born_at"]:
			if not expected_item.has(field) or not actual_item.has(field):
				return false
			if absf(float(expected_item[field]) - float(actual_item[field])) > 0.0001:
				return false
	return true

func _test_full_chain_power_and_round_trip() -> void:
	var sim: FactorySim = FactorySim.new()
	sim.power.bypass = true
	sim.register_node(41, "iron_ore", "normal", Vector3.ZERO, 60.0)
	var miner: int = sim.add_entity("miner_mk1", Vector3.ZERO, 0.0, {"node_id": 41})
	var smelter: int = sim.add_entity("smelter", Vector3(0.0, 0.0, 6.0), 0.0, {"recipe": "iron_ingot"})
	var constructor: int = sim.add_entity("constructor", Vector3(0.0, 0.0, 12.0), 0.0, {"recipe": "iron_plate"})
	var storage: int = sim.add_entity("storage", Vector3(0.0, 0.0, 19.0))
	var first_belt: int = int(_connect(sim, "belt_mk1", miner, "out0", smelter, "in0").get("id", -1))
	var second_belt: int = int(_connect(sim, "belt_mk1", smelter, "out0", constructor, "in0").get("id", -1))
	var third_belt: int = int(_connect(sim, "belt_mk1", constructor, "out0", storage, "in0").get("id", -1))
	_run_for(sim, 120.0)
	var bypass_rate: float = sim.get_rate(storage, "iron_plate")
	_check("full chain delivers bypass-on plates at the expected 20/min ±10%",
		miner > 0 and smelter > 0 and constructor > 0 and storage > 0
		and first_belt > 0 and second_belt > 0 and third_belt > 0
		and absf(bypass_rate - 20.0) <= 2.0,
		"rate=%.1f/min expected=20/min" % bypass_rate)

	sim.power.bypass = false
	_run_for(sim, 90.0)
	var no_power_diagnostics: bool = (
		not sim.diagnostics(miner).is_empty()
		and sim.diagnostics(miner)[0].begins_with("No power")
		and sim.diagnostics(smelter)[0].begins_with("No power")
		and sim.diagnostics(constructor)[0].begins_with("No power"))
	_check("full chain stops without power and diagnostics report No power",
		no_power_diagnostics and is_equal_approx(sim.get_rate(storage, "iron_plate"), 0.0),
		str([sim.get_rate(storage, "iron_plate"), sim.diagnostics(smelter)]))

	sim.register_vent("vent_full_chain", Vector3(-8.0, 0.0, 0.0))
	var tap: int = sim.add_entity("geo_tap", Vector3(-8.0, 0.0, 0.0))
	var pole_a: int = sim.add_entity("power_pole", Vector3(-4.0, 0.0, 0.0))
	var pole_b: int = sim.add_entity("power_pole", Vector3(-4.0, 0.0, 12.0))
	_run_for(sim, 120.0)
	var recovered_rate: float = sim.get_rate(storage, "iron_plate")
	_check("Geo Tap and poles restore full-chain production",
		tap > 0 and pole_a > 0 and pole_b > 0 and recovered_rate >= 18.0
		and not sim.diagnostics(smelter)[0].begins_with("No power"),
		"rate=%.1f/min diagnostics=%s" % [recovered_rate, str(sim.diagnostics(smelter))])

	_run_for(sim, 0.37)
	var belt_ids: Array[int] = [first_belt, second_belt, third_belt]
	var entity_ids: Array[int] = [miner, smelter, constructor, storage]
	var saved_belt_items: Dictionary = {}
	var saved_buffers: Dictionary = {}
	var belt_items_present: bool = false
	for belt_id: int in belt_ids:
		var belt: FactoryEntity = sim.entities[belt_id]
		saved_belt_items[belt_id] = belt.belt_items.duplicate(true)
		belt_items_present = belt_items_present or not belt.belt_items.is_empty()
	for entity_id: int in entity_ids:
		var entity: FactoryEntity = sim.entities[entity_id]
		saved_buffers[entity_id] = {
			"input": entity.input_buffer.duplicate(true),
			"output": entity.output_buffer.duplicate(true)
		}
	var buffered_items_present: bool = not sim.entities[storage].input_buffer.is_empty()
	var save_system: FactorySaveSystem = FactorySaveSystem.new()
	save_system.save_path = "user://full_chain_qa_test.json"
	var player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(player)
	var save_ok: bool = save_system.save_game(sim, player, 0, {}, {}, sim.power.bypass)
	var restored: FactorySim = FactorySim.new()
	restored.register_node(41, "iron_ore", "normal", Vector3.ZERO, 60.0)
	restored.register_vent("vent_full_chain", Vector3(-8.0, 0.0, 0.0))
	var restored_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(restored_player)
	var loaded: Dictionary = save_system.load_game(restored, restored_player) if save_ok else {}
	var belt_items_preserved: bool = not loaded.is_empty()
	for belt_id: int in belt_ids:
		var restored_belt: FactoryEntity = restored.entities.get(belt_id)
		belt_items_preserved = belt_items_preserved and restored_belt != null
		if restored_belt != null:
			belt_items_preserved = (belt_items_preserved
				and _belt_items_match(saved_belt_items[belt_id], restored_belt.belt_items))
	var buffers_preserved: bool = not loaded.is_empty()
	for entity_id: int in entity_ids:
		var restored_entity: FactoryEntity = restored.entities.get(entity_id)
		var expected_buffers: Dictionary = saved_buffers[entity_id]
		buffers_preserved = (buffers_preserved and restored_entity != null
			and restored_entity.input_buffer == expected_buffers["input"]
			and restored_entity.output_buffer == expected_buffers["output"])
	_check("mid-run save/load preserves moving belt items and non-empty buffers",
		save_ok and belt_items_present and buffered_items_present
		and belt_items_preserved and buffers_preserved,
		str([belt_items_present, buffered_items_present, belt_items_preserved, buffers_preserved]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.save_path))
	player.queue_free()
	restored_player.queue_free()
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
	player.inventory.set_count("cable", 17)
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
		restored.entities.has(42) and restored.next_id > belt_id and restored_player.inventory.count("cable") == 17,
		str([restored.entities.keys(), restored.next_id, restored_player.inventory.totals()]))
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

	var creative_builder: Node = (load("res://scripts/main.gd") as Script).new() as Node
	var creative_build_mode: CreativeMode = creative_builder.get("creative_mode") as CreativeMode
	creative_build_mode.enter(FrontierInventory.from_totals({"wire": 3}), 0)
	var creative_sim: FactorySim = FactorySim.new()
	var creative_source_data: Dictionary = creative_builder.call("_creative_build_extra",
		{"recipe": "iron_ingot"})
	var creative_source: int = creative_sim.add_entity("smelter", Vector3.ZERO, 0.0, creative_source_data)
	var creative_target: int = creative_sim.add_entity("storage", Vector3(0.0, 0.0, 8.0))
	var creative_belt_data: Dictionary = creative_builder.call("_creative_build_extra")
	var creative_belt_result: Dictionary = creative_sim.add_belt("belt_mk1", creative_source, "out0",
		creative_target, "in0", _port_curve(creative_sim, creative_source, "out0", creative_target, "in0"),
		creative_belt_data)
	var creative_belt_id: int = int(creative_belt_result.get("id", -1))
	creative_sim.entities[creative_source].input_buffer["iron_ore"] = 2
	var creative_belt: FactoryEntity = creative_sim.entities[creative_belt_id]
	creative_belt.belt_items = [{"item": "copper_ore", "s": 0.5}]
	var creative_saved: Dictionary = creative_sim.to_dict()
	var creative_loaded_sim: FactorySim = FactorySim.new()
	creative_loaded_sim.from_dict(creative_saved)
	var machine_flag_saved: bool = bool(creative_loaded_sim.entities[creative_source].extra.get("creative_built", false))
	var belt_flag_saved: bool = bool(creative_loaded_sim.entities[creative_belt_id].extra.get("creative_built", false))
	var survival_after_exit: FrontierInventory = creative_build_mode.exit().get(
		"inventory", FrontierInventory.new())
	var buffered_items: Dictionary = {}
	var creative_refund: Dictionary = creative_loaded_sim.remove_entity_with_refund(
		creative_source, buffered_items)
	creative_build_mode.add_refund(creative_refund, survival_after_exit)
	_check("Creative-built entity and belt persist flags, skip costs, and refund contents",
		creative_belt_id > 0 and machine_flag_saved and belt_flag_saved
		and not creative_refund.has("iron_plate") and not creative_refund.has("concrete")
		and survival_after_exit.totals() == {"wire": 3, "iron_ore": 2, "copper_ore": 1}
		and buffered_items == {"iron_ore": 2, "copper_ore": 1},
		str([creative_refund, survival_after_exit.totals(), buffered_items,
			machine_flag_saved, belt_flag_saved]))
	creative_builder.free()

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
		idle.get("status", "") == "Missing input: Iron Ore"
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

func _test_belt_audio_localization() -> void:
	var audio_manager: FactoryAudioManager = FactoryAudioManager.new()
	var curve: PackedVector3Array = PackedVector3Array([
		Vector3.ZERO, Vector3(0.0, 0.0, 12.0),
		Vector3(20.0, 0.0, 12.0), Vector3(20.0, 0.0, 0.0)
	])
	var listener_position: Vector3 = Vector3(19.0, 0.0, 0.0)
	var nearest: Vector3 = audio_manager._nearest_belt_point(curve, listener_position)
	_check("belt-rattle source follows the closest sampled point on a long curve",
		nearest.distance_to(listener_position) < 3.0
		and nearest.distance_to(curve[0]) > 10.0,
		str(nearest))
	audio_manager.free()
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

func _test_foliage_density_persistence() -> void:
	var terrain: FactoryTerrain = FactoryTerrain.new()
	terrain.call("_configure_noise")
	var high_density: FactoryFoliage = FactoryFoliage.new()
	high_density.terrain = terrain
	high_density.density_multiplier = 1.25
	high_density.density_built_multiplier = 1.25
	high_density.call("_generate_definitions")
	var base_tree_ids: Array[String] = []
	var extra_tree: Dictionary = {}
	for definition: Dictionary in high_density.foliage_definitions:
		if definition["type"] != "tree":
			continue
		var foliage_id: String = str(definition["id"])
		if foliage_id.begins_with("tree_extra_"):
			if extra_tree.is_empty():
				extra_tree = definition
		else:
			base_tree_ids.append(foliage_id)
	var building_position: Vector3 = extra_tree.get("position", Vector3.ZERO)
	var building_size: Vector3 = Vector3(12.0, 4.0, 12.0)
	high_density.remove_in_world_footprint(building_position, 0.0, building_size)
	var save_sim: FactorySim = FactorySim.new()
	var building_id: int = save_sim.add_entity("smelter", building_position)
	var saved_data: Dictionary = {
		"entities": save_sim.to_dict(),
		"foliage": high_density.state.to_dict()
	}

	var loaded_sim: FactorySim = FactorySim.new()
	loaded_sim.from_dict(saved_data["entities"])
	var low_density: FactoryFoliage = FactoryFoliage.new()
	low_density.terrain = terrain
	low_density.density_multiplier = 0.5
	low_density.density_built_multiplier = 0.5
	low_density.call("_generate_definitions")
	low_density.restore_state(saved_data["foliage"])
	var reloaded_base_tree_ids: Array[String] = []
	var overlaps_building: bool = false
	for definition: Dictionary in low_density.foliage_definitions:
		if definition["type"] != "tree":
			continue
		var foliage_id: String = str(definition["id"])
		if not foliage_id.begins_with("tree_extra_"):
			reloaded_base_tree_ids.append(foliage_id)
		var local: Vector3 = definition["position"] - building_position
		if absf(local.x) <= building_size.x * 0.5 and absf(local.z) <= building_size.z * 0.5 \
				and not low_density.state.is_removed(foliage_id):
			overlaps_building = true
	_check("density change reload keeps saved buildings clear and base tree IDs stable",
		building_id > 0 and loaded_sim.entities.has(building_id)
		and base_tree_ids == reloaded_base_tree_ids
		and not extra_tree.is_empty() and not overlaps_building,
		str([building_id, base_tree_ids.size(), reloaded_base_tree_ids.size(),
			high_density.state.to_dict(), overlaps_building]))
	low_density.free()
	high_density.free()
	terrain.free()
	_finish_group()

func _test_foliage_chunk_visibility() -> void:
	var terrain: FactoryTerrain = FactoryTerrain.new()
	terrain.call("_configure_noise")
	var foliage: FactoryFoliage = FactoryFoliage.new()
	foliage.terrain = terrain
	foliage.tree_view_distance = 100.0
	get_root().add_child(foliage)
	var first_tree: Dictionary = {}
	var second_tree: Dictionary = {}
	for definition: Dictionary in foliage.foliage_definitions:
		if definition["type"] != "tree":
			continue
		if first_tree.is_empty():
			first_tree = definition
		elif definition["chunk"] != first_tree["chunk"]:
			second_tree = definition
			break
	foliage.foliage_definitions = [first_tree, second_tree]
	foliage.call("_build_tree_multimeshes")
	var chunks: Dictionary = {}
	var all_near_trees_visible: bool = not foliage.tree_multimesh_instances.is_empty()
	for instance: MultiMeshInstance3D in foliage.tree_multimesh_instances:
		var chunk: Vector2i = instance.get_meta("tree_chunk")
		chunks[chunk] = true
		var expected_center: Vector3 = Vector3(
			-FactoryFoliage.WORLD_HALF_EXTENT + (float(chunk.x) + 0.5) * FactoryFoliage.CHUNK_SIZE,
			0.0,
			-FactoryFoliage.WORLD_HALF_EXTENT + (float(chunk.y) + 0.5) * FactoryFoliage.CHUNK_SIZE)
		all_near_trees_visible = all_near_trees_visible \
			and instance.position.is_equal_approx(expected_center) \
			and instance.visibility_range_end >= foliage.tree_view_distance \
				+ FactoryFoliage.TREE_CHUNK_HALF_DIAGONAL \
				+ FactoryFoliage.TREE_VISIBILITY_FADE_MARGIN \
			and instance.visibility_range_end - FactoryFoliage.TREE_VISIBILITY_FADE_MARGIN \
				>= FactoryFoliage.TREE_COLLISION_RADIUS \
					+ FactoryFoliage.TREE_CHUNK_HALF_DIAGONAL \
			and instance.multimesh.instance_count == 1
	_check("Tree batches are chunk-local and include collision-radius visibility margin",
		chunks.size() == 2 and all_near_trees_visible,
		str([chunks, foliage.tree_multimesh_instances.size()]))
	foliage.free()
	terrain.free()
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
	var inventory: FrontierInventory = FrontierInventory.from_totals({
		"iron_ore": 4, "iron_rod": 22, "wire": 24, "iron_plate": 5
	})
	_check("item quantity follows inventory changes", model.quantity(8, inventory) == 4, str(model.quantity(8, inventory)))
	inventory.set_count("iron_ore", 9)
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

func _test_creative_mode() -> void:
	var inventory: FrontierInventory = FrontierInventory.from_totals({"iron_plate": 7, "wire": 13})
	var original_inventory: Dictionary = inventory.totals()
	var original_tiers: int = 1
	var creative: CreativeMode = CreativeMode.new()
	var entered: bool = creative.enter(inventory, original_tiers)
	inventory.clear()
	var smelter_cost: Dictionary = BuildingDefs.all()["smelter"]["cost"]
	var can_place: bool = creative.can_afford(smelter_cost, creative.inventory, 1)
	creative.pay_cost(smelter_cost, creative.inventory, 1)
	var sim: FactorySim = FactorySim.new()
	var placed: int = sim.add_entity("smelter", Vector3.ZERO) if can_place else -1
	var restored: Dictionary = creative.exit()
	_check("creative placement with empty inventory restores survival inventory and tiers",
		entered and placed > 0 and inventory.is_empty()
		and restored.get("inventory", FrontierInventory.new()).totals() == original_inventory
		and int(restored.get("unlocked_tiers", -1)) == original_tiers,
		str([entered, placed, inventory.totals(), restored]))
	var grant_inventory := FrontierInventory.new()
	creative.enter(grant_inventory, 0)
	var granted: bool = creative.grant_stack("iron_ore")
	creative.add_refund({"iron_plate": 5}, creative.inventory)
	_check("creative item clicks grant one full stack and suppress construction refunds",
		granted and creative.inventory.count("iron_ore") == 64
		and creative.inventory.count("iron_plate") == 0
		and creative.world_gains.is_empty(),
		str(creative.inventory.totals()))
	creative.exit()

	var gain_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(gain_player)
	gain_player.inventory = FrontierInventory.from_totals({"iron_plate": 7, "wire": 13})
	var gain_snapshot: Dictionary = gain_player.inventory.totals()
	var gain_creative: CreativeMode = CreativeMode.new()
	gain_creative.enter(gain_player.inventory, 1)
	gain_player.inventory = gain_creative.inventory
	var gain_sim: FactorySim = FactorySim.new()
	var gain_storage_id: int = gain_sim.add_entity("storage", Vector3.ZERO)
	gain_sim.entities[gain_storage_id].input_buffer = {"iron_ore": 5}
	var gain_hud: FactoryHUD = FactoryHUD.new()
	gain_hud.setup(gain_sim, gain_player)
	get_root().add_child(gain_hud)
	gain_hud.selected_entity_id = gain_storage_id
	gain_hud.world_item_collected.connect(gain_creative.record_world_gain)
	gain_hud._take_storage()
	var gain_terrain: FactoryTerrain = FactoryTerrain.new()
	gain_terrain._configure_noise()
	gain_terrain._build_boulders()
	var hand_mined: Dictionary = gain_terrain.mine_boulder("near_iron_00")
	var hand_mined_item: String = str(hand_mined.get("item", ""))
	gain_player.inventory.add(hand_mined_item, 1)
	gain_creative.record_world_gain(hand_mined_item, 1)
	gain_terrain.free()
	var gain_restored: Dictionary = gain_creative.exit()
	var expected_gain_inventory: Dictionary = gain_snapshot.duplicate(true)
	expected_gain_inventory[hand_mined_item] = int(expected_gain_inventory.get(hand_mined_item, 0)) + 6
	_check("storage pickups and a hand-mined item survive Creative exit",
		hand_mined_item == "iron_ore" and gain_player.inventory.count("iron_ore") == 6
		and gain_restored.get("inventory", FrontierInventory.new()).totals() == expected_gain_inventory
		and gain_creative.world_gains.is_empty(),
		str([gain_player.inventory.totals(), gain_restored, gain_creative.world_gains]))
	gain_hud.queue_free()
	gain_player.queue_free()

	var output_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(output_player)
	output_player.inventory = FrontierInventory.from_totals({"wire": 4})
	var output_creative: CreativeMode = CreativeMode.new()
	output_creative.enter(output_player.inventory, 0)
	output_player.inventory = output_creative.inventory
	var output_sim: FactorySim = FactorySim.new()
	var output_machine: int = output_sim.add_entity("smelter", Vector3.ZERO, 0.0,
		{"recipe": "iron_ingot"})
	output_sim.entities[output_machine].output_buffer["iron_ingot"] = 2
	var output_hud: FactoryHUD = FactoryHUD.new()
	output_hud.setup(output_sim, output_player)
	get_root().add_child(output_hud)
	output_hud.selected_entity_id = output_machine
	output_hud.world_item_collected.connect(output_creative.record_world_gain)
	output_hud._take_output()
	var output_restored: Dictionary = output_creative.exit()
	_check("machine output collection is retained when leaving Creative",
		output_restored.get("inventory", FrontierInventory.new()).totals() == {"wire": 4, "iron_ingot": 2},
		str(output_restored))
	output_hud.queue_free()
	output_player.queue_free()

	var salvage_mode: CreativeMode = CreativeMode.new()
	var salvage_inventory: FrontierInventory = FrontierInventory.from_totals({"wire": 2})
	salvage_mode.enter(salvage_inventory, 0)
	var salvage_sim: FactorySim = FactorySim.new()
	var salvage_storage: int = salvage_sim.add_entity("storage", Vector3.ZERO)
	salvage_sim.entities[salvage_storage].input_buffer["iron_ore"] = 2
	var salvaged_items: Dictionary = {}
	var salvage_refund: Dictionary = salvage_sim.remove_entity_with_refund(
		salvage_storage, salvaged_items)
	for item_id: String in salvaged_items:
		salvage_mode.record_world_gain(item_id, int(salvaged_items[item_id]))
	salvage_mode.add_refund(salvage_refund, salvage_mode.inventory)
	var salvaged_state: Dictionary = salvage_mode.exit()
	_check("dismantled machine contents are restored without Creative construction refunds",
		salvaged_items == {"iron_ore": 2}
		and salvaged_state.get("inventory", FrontierInventory.new()).totals() == {"wire": 2, "iron_ore": 2},
		str([salvaged_items, salvage_refund, salvaged_state]))

	var save_system: FactorySaveSystem = FactorySaveSystem.new()
	save_system.save_path = "user://creative_mode_round_trip_test.json"
	var saved_sim: FactorySim = FactorySim.new()
	var saved_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(saved_player)
	saved_player.inventory = FrontierInventory.from_totals({"iron_plate": 100, "copper_ore": 100})
	var survival_snapshot: FrontierInventory = FrontierInventory.from_totals({"iron_plate": 21, "iron_rod": 9})
	creative.enter(survival_snapshot, 2)
	saved_player.inventory = creative.inventory
	creative.record_world_gain("copper_ore", 2)
	var save_ok: bool = save_system.save_game(saved_sim, saved_player, 2, {}, {},
		saved_sim.power.bypass, creative.to_dict())
	var restored_sim: FactorySim = FactorySim.new()
	var restored_player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(restored_player)
	var loaded: Dictionary = save_system.load_game(restored_sim, restored_player) if save_ok else {}
	var loaded_creative: CreativeMode = CreativeMode.new()
	loaded_creative.load_dict(loaded.get("creative", {}))
	var creative_was_active: bool = loaded_creative.active
	var loaded_snapshot := FrontierInventory.new()
	loaded_snapshot.from_data(loaded_creative.survival_inventory)
	var creative_snapshot: Dictionary = loaded_snapshot.totals()
	var gains_snapshot: Dictionary = loaded_creative.world_gains.duplicate(true)
	var restored_state: Dictionary = loaded_creative.exit()
	var snapshot_saved: bool = creative_snapshot == survival_snapshot.totals()
	var expected_loaded_inventory: Dictionary = survival_snapshot.totals()
	expected_loaded_inventory["copper_ore"] = 2
	var inventory_restored: bool = restored_state.get(
		"inventory", FrontierInventory.new()).totals() == expected_loaded_inventory
	var tiers_restored: bool = int(restored_state.get("unlocked_tiers", -1)) == 2
	_check("save/load retains Creative snapshot and collected world gains",
		save_ok and creative_was_active and snapshot_saved
		and gains_snapshot == {"copper_ore": 2}
		and inventory_restored and tiers_restored
		and loaded_creative.world_gains.is_empty(),
		str([save_ok, creative_was_active, snapshot_saved, inventory_restored,
			tiers_restored, loaded, creative_snapshot, gains_snapshot, restored_state]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_system.save_path))
	saved_player.queue_free()
	restored_player.queue_free()
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

func _test_creative_cursor_focus() -> void:
	var main_script: Script = load("res://scripts/main.gd") as Script
	var app: Node = main_script.new() as Node
	var sim: FactorySim = app.get("sim") as FactorySim
	var machine_id: int = sim.add_entity("smelter", Vector3.ZERO, 0.0, {"recipe": "iron_ingot"})
	var player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(player)
	var model: HotbarModel = app.get("hotbar_model") as HotbarModel
	model.assign(0, "building", "smelter")
	model.selected_index = 0
	var hud: FactoryHUD = FactoryHUD.new()
	hud.setup(sim, player, model)
	get_root().add_child(hud)
	app.set("player", player)
	app.set("hud", hud)

	hud.show_build_menu(["smelter"])
	player.set_panel_open(true)
	app.call("_toggle_creative_mode")
	_check("Creative toggle keeps cursor visible with the build menu open",
		player.panel_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and hud.build_menu.visible,
		str([player.panel_open, Input.mouse_mode, hud.build_menu.visible, hud.panel_is_open()]))

	hud.close_build_menu()
	hud.open_hub()
	app.call("_toggle_creative_mode")
	_check("Creative toggle keeps cursor visible with the HUB panel open",
		player.panel_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and hud.panel_is_open(),
		str([player.panel_open, Input.mouse_mode, hud.panel_is_open()]))

	hud.close_panel()
	hud.open_entity(machine_id)
	app.call("_toggle_creative_mode")
	_check("Creative toggle keeps cursor visible with a machine panel open",
		player.panel_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and hud.panel_is_open(),
		str([player.panel_open, Input.mouse_mode, hud.panel_is_open()]))

	hud.close_panel()
	app.free()
	hud.queue_free()
	player.queue_free()
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

func _test_graphics_settings_and_persistence() -> void:
	var settings: FrontierGraphicsSettings = FrontierGraphicsSettings.new()
	settings.apply_preset("low")
	_check("Low preset uses requested shadow, fog, foliage, and AA values",
		settings.shadow_atlas_size == 2048 and settings.shadow_distance == 180.0
		and not settings.ssao and not settings.ssil and not settings.volumetric_fog
		and settings.foliage_density == 0.5 and settings.grass_radius == 35.0
		and settings.antialiasing == "fxaa", str(settings.to_dict()))
	settings.apply_preset("medium")
	_check("Medium preset uses requested shadow, AO, foliage, and TAA values",
		settings.shadow_atlas_size == 4096 and settings.shadow_distance == 300.0
		and settings.ssao and not settings.ssil and not settings.volumetric_fog
		and settings.foliage_density == 0.75 and settings.grass_radius == 48.0
		and settings.antialiasing == "taa", str(settings.to_dict()))
	settings.apply_preset("high")
	_check("High preset uses requested shadow, AO, fog, and foliage values",
		settings.shadow_atlas_size == 4096 and settings.shadow_distance == 450.0
		and settings.ssao and settings.ssil and settings.volumetric_fog
		and settings.foliage_density == 1.0 and settings.grass_radius == 60.0,
		str(settings.to_dict()))
	settings.apply_preset("ultra")
	_check("Ultra preset uses requested distance, density, and full-scale FSR2-off values",
		settings.shadow_atlas_size == 8192 and settings.shadow_distance == 700.0
		and settings.ssao and settings.ssil and settings.volumetric_fog
		and settings.foliage_density == 1.25 and settings.grass_radius == 75.0
		and settings.scaling_mode == "bilinear" and settings.render_scale == 1.0,
		str(settings.to_dict()))
	settings.window_mode = "borderless"
	settings.vsync = false
	settings.max_fps = 120
	settings.render_scale = 0.85
	settings.scaling_mode = "fsr1"
	settings.antialiasing = "smaa"
	settings.shadow_split_2 = 0.37
	settings.glow = false
	var path: String = "user://m1-graphics-settings-test.cfg"
	_check("Graphics settings save succeeds", settings.save_settings(path), path)
	var loaded: FrontierGraphicsSettings = FrontierGraphicsSettings.new()
	_check("Graphics settings load succeeds", loaded.load_settings(path), path)
	_check("Graphics settings round-trip persists all option categories",
		loaded.preset == settings.preset and loaded.window_mode == settings.window_mode
		and loaded.vsync == settings.vsync and loaded.max_fps == settings.max_fps
		and is_equal_approx(loaded.render_scale, settings.render_scale)
		and loaded.scaling_mode == settings.scaling_mode
		and loaded.antialiasing == settings.antialiasing
		and loaded.shadow_atlas_size == settings.shadow_atlas_size
		and is_equal_approx(loaded.shadow_split_2, settings.shadow_split_2) and not loaded.glow,
		str(loaded.to_dict()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_finish_group()

func _test_graphics_pending_preset() -> void:
	var player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(player)
	var hud: FactoryHUD = FactoryHUD.new()
	hud.setup(FactorySim.new(), player)
	get_root().add_child(hud)
	var settings: FrontierGraphicsSettings = FrontierGraphicsSettings.new()
	hud.open_graphics_settings(settings)
	var window_mode: OptionButton = hud.graphics_setting_controls["window_mode"] as OptionButton
	var vsync: OptionButton = hud.graphics_setting_controls["vsync"] as OptionButton
	var preset: OptionButton = hud.graphics_setting_controls["preset"] as OptionButton
	window_mode.select(1)
	vsync.select(1)
	preset.select(3)
	hud.call("_on_graphics_preset_selected", 3)
	_check("Preset selection preserves pending window and VSync edits without applying",
		str(settings.window_mode) == "windowed" and bool(settings.vsync)
		and str(window_mode.get_item_metadata(window_mode.selected)) == "borderless"
		and str(vsync.get_item_metadata(vsync.selected)) == "off"
		and int((hud.graphics_setting_controls["shadow_atlas_size"] as SpinBox).value) == 8192
		and is_equal_approx(float((hud.graphics_setting_controls["grass_radius"] as SpinBox).value),
			75.0),
		str([settings.to_dict(), window_mode.selected, vsync.selected]))
	hud.close_panel()
	hud.open_graphics_settings(settings)
	var reopened_window: OptionButton = hud.graphics_setting_controls["window_mode"] as OptionButton
	var reopened_vsync: OptionButton = hud.graphics_setting_controls["vsync"] as OptionButton
	var reopened_preset: OptionButton = hud.graphics_setting_controls["preset"] as OptionButton
	_check("Closing settings without Apply discards pending form changes",
		str(reopened_window.get_item_metadata(reopened_window.selected)) == "windowed"
		and str(reopened_vsync.get_item_metadata(reopened_vsync.selected)) == "on"
		and str(reopened_preset.get_item_metadata(reopened_preset.selected)) == "high",
		str([reopened_window.selected, reopened_vsync.selected, reopened_preset.selected]))
	hud.queue_free()
	player.queue_free()
	_finish_group()

func _test_grass_fade_settings() -> void:
	var settings: FrontierGraphicsSettings = FrontierGraphicsSettings.new()
	settings.apply_preset("ultra")
	var foliage: FactoryFoliage = FactoryFoliage.new()
	foliage.set_graphics_options(settings.foliage_density, settings.grass_radius,
		settings.tree_view_distance)
	var material: ShaderMaterial = foliage.call(
		"_wind_material", Color.WHITE, 0.12, foliage.grass_fade_start,
		foliage.grass_fade_end)
	_check("Grass fade uniforms follow Ultra radius through the full 75 m",
		foliage.grass_fade_start == 67.0 and foliage.grass_fade_end == 75.0
		and float(material.get_shader_parameter("fade_start")) == 67.0
		and float(material.get_shader_parameter("fade_end")) == 75.0,
		str([foliage.grass_radius, foliage.grass_fade_start, foliage.grass_fade_end]))
	foliage.free()
	_finish_group()

func _test_graphics_shortcuts() -> void:
	var previous_mouse_mode: Input.MouseMode = Input.mouse_mode
	var app: Node = load("res://scripts/main.gd").new()
	var player: FactoryPlayer = FactoryPlayer.new()
	get_root().add_child(player)
	var hud: FactoryHUD = FactoryHUD.new()
	hud.setup(app.get("sim") as FactorySim, player, app.get("hotbar_model") as HotbarModel)
	get_root().add_child(hud)
	var settings: FrontierGraphicsSettings = FrontierGraphicsSettings.new()
	var overlay: FrontierPerfOverlay = FrontierPerfOverlay.new()
	overlay.configure(settings)
	get_root().add_child(overlay)
	app.set("player", player)
	app.set("hud", hud)
	app.set("graphics_settings", settings)
	app.set("perf_overlay", overlay)
	app.set("benchmark_mode", false)

	var f3: InputEventKey = InputEventKey.new()
	f3.pressed = true
	f3.keycode = KEY_F3
	app.call("_unhandled_input", f3)
	_check("F3 opens the performance overlay",
		overlay.panel.visible and overlay.summary_label.text.begins_with("PERFORMANCE"),
		str([overlay.panel.visible, overlay.summary_label.text]))
	app.call("_unhandled_input", f3)
	_check("F3 closes the performance overlay",
		not overlay.panel.visible, str(overlay.panel.visible))

	var f10: InputEventKey = InputEventKey.new()
	f10.pressed = true
	f10.keycode = KEY_F10
	app.call("_unhandled_input", f10)
	_check("F10 opens graphics settings",
		hud.graphics_settings_open and hud.panel_is_open()
		and player.panel_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		str([hud.graphics_settings_open, hud.panel_is_open(), player.panel_open, Input.mouse_mode]))
	var focused_control: Control = hud.graphics_setting_controls.get("preset") as Control
	if focused_control != null:
		focused_control.grab_focus()
	app.call("_input", f10)
	_check("F10 closes graphics settings while a HUD control is focused",
		not hud.graphics_settings_open and not hud.panel_is_open()
		and not player.panel_open,
		str([hud.graphics_settings_open, hud.panel_is_open(), player.panel_open]))
	hud.open_hub()
	app.call("_input", f10)
	_check("F10 opens settings from another open panel",
		hud.graphics_settings_open and hud.panel_is_open()
		and player.panel_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		str([hud.graphics_settings_open, hud.panel_is_open(), player.panel_open, Input.mouse_mode]))
	app.call("_input", f3)
	_check("F3 works with settings open without changing cursor state",
		overlay.panel.visible and player.panel_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		str([overlay.panel.visible, player.panel_open, Input.mouse_mode]))
	app.call("_input", f3)
	app.call("_input", f10)
	_check("F10 closes settings after overlay use",
		not hud.graphics_settings_open and not hud.panel_is_open(),
		str([hud.graphics_settings_open, hud.panel_is_open()]))

	hud.queue_free()
	player.queue_free()
	overlay.queue_free()
	app.free()
	Input.mouse_mode = previous_mouse_mode
	_finish_group()

func _test_benchmark_stats_and_cli() -> void:
	var times: Array[float] = [10.0, 20.0, 30.0, 40.0, 100.0]
	var stats: Dictionary = FrontierBenchmark.summarize_frame_times(times)
	_check("Synthetic frame-time average FPS is exact",
		is_equal_approx(float(stats["average_fps"]), 25.0), str(stats))
	_check("Synthetic 1% and 0.1% lows average the slowest frame",
		is_equal_approx(float(stats["one_percent_low_fps"]), 10.0)
		and is_equal_approx(float(stats["zero_point_one_percent_low_fps"]), 10.0),
		str(stats))
	_check("Synthetic percentiles and hitch thresholds are exact",
		float(stats["p50_ms"]) == 30.0 and float(stats["p99_ms"]) == 100.0
		and int(stats["hitches_over_33_3_ms"]) == 2
		and int(stats["hitches_over_50_ms"]) == 1, str(stats))
	var double_dash: Dictionary = FrontierBenchmark.parse_arguments(PackedStringArray([
		"--", "--benchmark=walk", "--preset=high", "--bench-seconds=10", "--bench-warmup=2"
	]))
	_check("CLI parser accepts standard -- user args",
		bool(double_dash["enabled"]) and double_dash["route"] == "walk"
		and double_dash["preset"] == "high" and float(double_dash["seconds"]) == 10.0
		and float(double_dash["warmup"]) == 2.0, str(double_dash))
	var double_plus: Dictionary = FrontierBenchmark.parse_arguments(PackedStringArray([
		"++benchmark=flythrough", "++preset=ultra", "++bench-seconds=30",
		"++bench-warmup=1"
	]))
	_check("CLI parser accepts raw ++-prefixed args",
		bool(double_plus["enabled"]) and double_plus["route"] == "flythrough"
		and double_plus["preset"] == "ultra" and float(double_plus["seconds"]) == 30.0
		and float(double_plus["warmup"]) == 1.0, str(double_plus))
	_finish_group()

func _test_benchmark_route_clearance() -> void:
	var terrain: FactoryTerrain = FactoryTerrain.new()
	terrain.call("_configure_noise")
	var start_xz: Vector2 = Vector2(110.0, 70.0)
	var end_xz: Vector2 = Vector2(245.0, -18.0)
	var walk: FrontierBenchmark = FrontierBenchmark.new()
	walk.terrain = terrain
	walk.route = "walk"
	var walk_start: Vector3 = Vector3(start_xz.x, terrain.height_at(start_xz.x, start_xz.y), start_xz.y)
	var walk_end: Vector3 = Vector3(end_xz.x, terrain.height_at(end_xz.x, end_xz.y), end_xz.y)
	walk.route_points.append(walk_start)
	walk.route_points.append(walk_end)
	walk.segment_lengths.append(walk_start.distance_to(walk_end))
	var walk_sample: Vector3 = walk.call("_sample_route", walk.segment_lengths[0] * 0.5)
	_check("Walk route samples ground height across the east ridge",
		is_equal_approx(walk_sample.y, terrain.height_at(walk_sample.x, walk_sample.z)),
		str([walk_sample, terrain.height_at(walk_sample.x, walk_sample.z)]))

	var flythrough: FrontierBenchmark = FrontierBenchmark.new()
	flythrough.terrain = terrain
	flythrough.route = "flythrough"
	for altitude: float in [-5.0, -1.0]:
		var fly_point: Vector2 = start_xz if flythrough.route_points.is_empty() else end_xz
		flythrough.route_altitudes.append(altitude)
		flythrough.route_points.append(Vector3(fly_point.x,
			terrain.height_at(fly_point.x, fly_point.y) + altitude, fly_point.y))
	flythrough.segment_lengths.append(
		flythrough.route_points[0].distance_to(flythrough.route_points[1]))
	var has_clearance: bool = true
	var clearances: Array[float] = []
	for fraction: float in [0.1, 0.25, 0.5, 0.75, 0.9]:
		var point: Vector3 = flythrough.call(
			"_sample_route", flythrough.segment_lengths[0] * fraction)
		var clearance: float = point.y - terrain.height_at(point.x, point.z)
		clearances.append(clearance)
		has_clearance = has_clearance \
			and clearance >= FrontierBenchmark.MIN_FLY_CLEARANCE - 0.001
	_check("Flythrough route keeps minimum terrain clearance",
		has_clearance, str(clearances))
	walk.free()
	flythrough.free()
	terrain.free()
	_finish_group()

func _test_benchmark_no_save() -> void:
	var path: String = "user://m1-benchmark-save-guard.json"
	var original: String = "{\"sentinel\":\"leave unchanged\"}"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var app: Node = load("res://scripts/main.gd").new()
	app.set("benchmark_mode", true)
	var save_system: FactorySaveSystem = FactorySaveSystem.new()
	save_system.save_path = path
	app.set("save_system", save_system)
	app.call("_save_game")
	app.call("_load_game")
	var unchanged: String = FileAccess.get_file_as_string(path)
	_check("Benchmark mode suppresses save and load without changing player save",
		not FrontierBenchmark.should_load_save({"enabled": true}) and unchanged == original,
		unchanged)
	app.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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
