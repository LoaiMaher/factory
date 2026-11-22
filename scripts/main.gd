extends Node3D

const SIM_STEP: float = 0.05
const BELT_BUILDINGS: Array[String] = ["belt_mk1", "belt_mk2"]
const TERRAIN_COLLISION_MASK: int = 1
const ENTITY_COLLISION_LAYER: int = 2

var sim: FactorySim = FactorySim.new()
var terrain: FactoryTerrain
var player: FactoryPlayer
var visuals: FactoryVisuals
var machine_models: MachineModels = MachineModels.new()
var foliage: FactoryFoliage
var herd: BorebackHerd
var hud: FactoryHUD
var viewmodel: FactoryViewmodel
var build_system: FactoryBuildSystem = FactoryBuildSystem.new()
var hotbar_model: HotbarModel = HotbarModel.new()
var placement: FactoryPlacement = FactoryPlacement.new()
var belt_start: Dictionary = {}
var save_system: FactorySaveSystem = FactorySaveSystem.new()
var building_definitions: Dictionary = BuildingDefs.all()
var recipe_definitions: Dictionary = Recipes.all()
var tier_definitions: Array[Dictionary] = Progression.tiers()
var milestone_definitions: Array[Dictionary] = Progression.milestones()
var build_preview: Node3D
var preview_kind: String = ""
var preview_material: ShaderMaterial
var belt_preview_visual: MeshInstance3D
var belt_preview_mesh: ImmediateMesh
var belt_preview_cells: Array[MeshInstance3D] = []
var port_markers: Array[MeshInstance3D] = []
var sim_accumulator: float = 0.0
var autosave_elapsed: float = 0.0
var autosave_enabled: bool = true
var save_backup_pending: bool = false
var unlocked_tiers: int = 0
var hand_mine_elapsed: float = 0.0
var spire_entity_id: int = -1
var first_sighting: bool = false
var show_help: bool = true
var mining_boulder_id: String = ""
var aimed_entity_id: int = -1
var aim_time: float = 0.0
var last_spire_stage: int = 0
var dismantle_elapsed: float = 0.0
var dismantle_pending: bool = false
var demo_smelter_id: int = -1
var capture_preview_override: bool = false

func _ready() -> void:
	FactoryPlayer.configure_input()
	_configure_actions()
	terrain = FactoryTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	for node: Dictionary in terrain.nodes:
		sim.register_node(int(node["id"]), str(node["item"]), str(node["purity"]), node["position"], float(node["rate"]))
	for index: int in range(terrain.vents.size()):
		sim.register_vent("vent_%02d" % index, terrain.vents[index])
	player = FactoryPlayer.new()
	player.name = "Player"
	player.collision_mask = TERRAIN_COLLISION_MASK | ENTITY_COLLISION_LAYER
	player.position = Vector3(0.0, terrain.height_at(0.0, 38.0) + 0.1, 38.0)
	add_child(player)
	foliage = FactoryFoliage.new()
	foliage.name = "Foliage"
	foliage.setup(terrain, player)
	add_child(foliage)
	visuals = FactoryVisuals.new()
	visuals.name = "Visuals"
	visuals.setup(sim, terrain)
	add_child(visuals)
	herd = BorebackHerd.new()
	herd.name = "BorebackHerd"
	herd.setup(terrain)
	add_child(herd)
	hud = FactoryHUD.new()
	hud.setup(sim, player, hotbar_model, machine_models, visuals)
	add_child(hud)
	hud.building_selected.connect(_select_building)
	hud.hotbar_selected.connect(_select_hotbar)
	hud.hotbar_changed.connect(_on_hotbar_changed)
	hud.panel_closed.connect(_on_panel_closed)
	hud.save_requested.connect(_save_game)
	hud.load_requested.connect(_load_game)
	hud.tier_requested.connect(_buy_tier)
	hud.craft_requested.connect(_hand_craft)
	hud.quit_requested.connect(_quit_game)
	viewmodel = FactoryViewmodel.new()
	viewmodel.name = "Viewmodel"
	viewmodel.setup(player, hud, visuals, machine_models, hotbar_model, build_system)
	add_child(viewmodel)
	var spire_position := Vector3(0.0, terrain.height_at(0.0, -34.0), -34.0)
	spire_entity_id = sim.add_entity("spire", spire_position)
	_create_preview()
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.has("--demo-factory"):
		autosave_enabled = false
		save_backup_pending = FileAccess.file_exists(save_system.save_path)
		_build_demo_factory()
		hud.show_toast("Demo factory loaded · diagnostics and item flow are live.", 8.0)
	elif arguments.has("--new-game"):
		save_backup_pending = FileAccess.file_exists(save_system.save_path)
		hud.show_toast("New game started.", 6.0)
	elif FileAccess.file_exists(save_system.save_path):
		if _load_saved_game(false):
			hud.show_toast("Loaded save.", 6.0)
		else:
			save_backup_pending = true
			hud.show_toast("Save couldn't be loaded; starting a new game.", 6.0)
	else:
		hud.show_toast("Press H for controls · E to interact · B to build.", 6.0)
	sim.power.apply_launch_flags(OS.get_cmdline_user_args())
	visuals.refresh()
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--capture-all":
			call_deferred("_capture_all")
			break
		if argument == "--capture-machine-set":
			call_deferred("_capture_machine_set")
			break
		if argument == "--capture-v7":
			call_deferred("_capture_v7_shots")
			break
		if argument.begins_with("--capture-"):
			call_deferred("_capture_screenshot", argument.trim_prefix("--capture-"))
			break

func _physics_process(delta: float) -> void:
	sim_accumulator += delta
	if autosave_enabled:
		autosave_elapsed += delta
		if autosave_elapsed >= 120.0:
			autosave_elapsed = 0.0
			_save_game()
	while sim_accumulator >= SIM_STEP:
		sim.tick(SIM_STEP)
		sim_accumulator -= SIM_STEP
	if sim.spire_stage > last_spire_stage:
		last_spire_stage = sim.spire_stage
		hud.show_toast("Milestone complete · gantry lifting the next ship section.", 8.0)
		if sim.spire_stage >= milestone_definitions.size():
			hud.show_toast("Era 2 — Heavy Industry coming soon. Keep building.", 10.0)
	visuals.interpolation_alpha = sim_accumulator / SIM_STEP
	visuals.refresh()
	_update_aim_status(delta)
	if not capture_preview_override:
		_update_preview()
	_update_sightings()

func _process(delta: float) -> void:
	if not mining_boulder_id.is_empty() and Input.is_key_pressed(KEY_E):
		hand_mine_elapsed += delta
		if hand_mine_elapsed >= 0.6:
			var result: Dictionary = terrain.mine_boulder(mining_boulder_id)
			if result.is_empty():
				mining_boulder_id = ""
				hand_mine_elapsed = 0.0
				return
			var item_id: String = str(result["item"])
			player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + 1
			hud.refresh_hotbar()
			viewmodel.play_mining_swing()
			hand_mine_elapsed -= 0.6
			hud.show_toast("Hand-mined 1 %s · %d left." % [Items.item_name(item_id), int(result["remaining"])], 1.0)
			if bool(result["depleted"]):
				mining_boulder_id = ""
	elif not mining_boulder_id.is_empty():
		hand_mine_elapsed = 0.0
		mining_boulder_id = ""
	if dismantle_pending and Input.is_key_pressed(KEY_F):
		dismantle_elapsed += delta
		if dismantle_elapsed >= 0.35:
			_dismantle_aimed()
			dismantle_pending = false
	elif dismantle_pending:
		dismantle_pending = false
		dismantle_elapsed = 0.0

func _update_aim_status(delta: float) -> void:
	var hit: Dictionary = _aim_hit(6.0)
	var found_id: int = -1
	if not hit.is_empty():
		var object: Node = hit.get("collider") as Node
		while object != null:
			if object.has_meta("entity_id"):
				found_id = int(object.get_meta("entity_id"))
				break
			object = object.get_parent()
	if found_id == aimed_entity_id:
		aim_time += delta
	else:
		aimed_entity_id = found_id
		aim_time = 0.0
	if found_id >= 0 and aim_time >= 0.3 and sim.entities.has(found_id):
		var entity: FactoryEntity = sim.entities[found_id]
		hud.hint_label.text = "%s  ·  %s  [E]" % [entity.kind.replace("_", " ").capitalize(), entity.status]
	else:
		hud.hint_label.text = ""

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.keycode
		if key == KEY_ESCAPE:
			if not belt_start.is_empty():
				belt_start.clear()
				hud.show_toast("Belt connection cancelled.")
			elif hud.panel_is_open():
				hud.close_panel()
			else:
				hud.open_pause()
			get_viewport().set_input_as_handled()
		elif key == KEY_H:
			show_help = not show_help
			hud.toggle_help()
			get_viewport().set_input_as_handled()
		elif key == KEY_B and not hud.panel_is_open():
			_toggle_build_menu()
			get_viewport().set_input_as_handled()
		elif key == KEY_TAB:
			if not hud.panel_is_open():
				hud.open_inventory()
			else:
				hud.close_panel()
			get_viewport().set_input_as_handled()
		elif key == KEY_E and not hud.panel_is_open():
			_interact()
			get_viewport().set_input_as_handled()
		elif key == KEY_R and not build_system.selected.is_empty():
			placement.rotate_step(-1 if event.shift_pressed else 1)
			get_viewport().set_input_as_handled()
		elif key == KEY_G and not build_system.selected.is_empty():
			placement.grid_snap_enabled = not placement.grid_snap_enabled
			hud.show_toast("Grid snap %s" % ("on" if placement.grid_snap_enabled else "off"))
			get_viewport().set_input_as_handled()
		elif key == KEY_F and not hud.panel_is_open():
			dismantle_pending = true
			dismantle_elapsed = 0.0
			get_viewport().set_input_as_handled()
		elif key == KEY_X:
			build_system.dismantle_mode = not build_system.dismantle_mode
			hud.show_toast("Dismantle mode %s · click an entity" % ("on" if build_system.dismantle_mode else "off"))
		elif key == KEY_F5:
			_save_game()
			get_viewport().set_input_as_handled()
		elif key == KEY_F9:
			_load_game()
			get_viewport().set_input_as_handled()
		elif key == KEY_F8:
			sim.power.bypass = not sim.power.bypass
			hud.show_toast("Power bypass %s." % ("enabled" if sim.power.bypass else "disabled"))
			get_viewport().set_input_as_handled()
		elif key == KEY_Q:
			_clear_hotbar_selection()
			get_viewport().set_input_as_handled()
		elif key == KEY_0:
			_select_hotbar(9)
			get_viewport().set_input_as_handled()
		elif key >= KEY_1 and key <= KEY_9:
			_select_hotbar(int(key) - int(KEY_1))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not hud.panel_is_open() and not hud.build_menu.visible:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.ctrl_pressed:
				placement.rotate_step(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			else:
				_cycle_hotbar(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_build_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT and not belt_start.is_empty():
			belt_start.clear()
			hud.show_toast("Belt connection cancelled.")

func _configure_actions() -> void:
	var interact_event: InputEventKey = InputEventKey.new()
	interact_event.physical_keycode = KEY_E
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		InputMap.action_add_event("interact", interact_event)

func _select_hotbar(index: int) -> void:
	if hud.has_assignment_target() and (hud.panel_is_open() or hud.build_menu.visible):
		var was_selected: bool = hotbar_model.selected_index == index
		if hud.assign_hovered_to_slot(index):
			var slot: Dictionary = hotbar_model.slot_at(index)
			if was_selected and hotbar_model.is_locked(index, unlocked_tiers):
				var tier: int = int(building_definitions.get(str(slot.get("id", "")), {}).get("tier", 0))
				hud.show_toast("Unlocks at Tier %d" % tier)
			else:
				hud.show_toast("Assigned %s to slot %s." % [str(slot.get("id", "")).replace("_", " "),
					"0" if index == 9 else str(index + 1)])
		return
	if hud.panel_is_open() or hud.build_menu.visible:
		return
	var result: Dictionary = hotbar_model.select_slot(index, unlocked_tiers)
	if not bool(result.get("ok", false)):
		hud.show_toast(str(result.get("reason", "Hotbar slot unavailable")))
		return
	_apply_hotbar_selection()

func _cycle_hotbar(step: int) -> void:
	var result: Dictionary = hotbar_model.cycle(step, unlocked_tiers)
	if not bool(result.get("ok", false)):
		hud.show_toast(str(result.get("reason", "No unlocked hotbar slots")))
		return
	_apply_hotbar_selection()

func _available_buildings() -> Array[String]:
	var all: Array[String] = []
	for id: String in building_definitions:
		if id != "spire":
			all.append(id)
	return all

func _apply_hotbar_selection(show_toast: bool = true) -> void:
	var action: Dictionary = hotbar_model.apply_to_build_system(build_system)
	if viewmodel != null:
		viewmodel.set_action(action)
	placement.preview_initialized = false
	belt_start.clear()
	if action.get("type", "") == "building":
		if player.panel_open and not hud.panel_is_open():
			player.set_panel_open(false)
		if show_toast:
			hud.show_toast("Selected %s · R rotates · click places" % str(action["id"]).replace("_", " "), 3.0)
	elif action.get("type", "") == "item" and show_toast:
		hud.show_toast("Holding %s." % Items.item_name(str(action["id"])), 2.0)
	elif show_toast:
		hud.show_toast("Empty hands.", 1.5)
	hud.refresh_hotbar()

func _clear_hotbar_selection() -> void:
	if hud.panel_is_open() or hud.build_menu.visible:
		return
	hotbar_model.selected_index = -1
	_apply_hotbar_selection()

func _on_hotbar_changed(index: int) -> void:
	if hotbar_model.selected_index == index:
		if hotbar_model.is_locked(index, unlocked_tiers):
			var slot: Dictionary = hotbar_model.slot_at(index)
			var tier: int = int(building_definitions.get(str(slot.get("id", "")), {}).get("tier", 0))
			hotbar_model.selected_index = -1
			hud.show_toast("Unlocks at Tier %d" % tier)
			_apply_hotbar_selection(false)
		else:
			_apply_hotbar_selection(false)
	else:
		hud.refresh_hotbar()

func _building_size(kind: String, rotation: int = 0) -> Vector2i:
	var size_m: Vector3 = BuildingDefs.size_of(kind)
	var size := Vector2i(maxi(1, roundi(size_m.x * 0.5)), maxi(1, roundi(size_m.z * 0.5)))
	return size if posmod(rotation, 2) == 0 else Vector2i(size.y, size.x)

func _select_building(building_id: String) -> void:
	var tier: int = int(building_definitions.get(building_id, {}).get("tier", 0))
	if tier > unlocked_tiers:
		hud.show_toast("Unlocks at Tier %d" % tier)
		hud.close_build_menu()
		if player.panel_open and not hud.panel_is_open():
			player.set_panel_open(false)
		return
	var result: Dictionary = hotbar_model.select_or_assign("building", building_id, unlocked_tiers)
	if not bool(result.get("ok", false)):
		hud.show_toast(str(result.get("reason", "Unable to select building")))
		if bool(result.get("full", false)):
			build_system.choose(building_id)
			hud.refresh_hotbar()
		hud.close_build_menu()
		if player.panel_open and not hud.panel_is_open():
			player.set_panel_open(false)
		return
	_apply_hotbar_selection()
	if player.panel_open and not hud.panel_is_open():
		player.set_panel_open(false)
	hud.close_build_menu()

func _toggle_build_menu() -> void:
	if hud.build_menu.visible:
		hud.close_build_menu()
		player.set_panel_open(false)
	else:
		hud.show_build_menu(_available_buildings())
		player.set_panel_open(true)

func _aim_hit(max_distance: float = 80.0, collision_mask: int = 0xFFFFFFFF) -> Dictionary:
	var origin: Vector3 = player.camera.global_position
	var end: Vector3 = origin + -player.camera.global_transform.basis.z * max_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [player.get_rid()]
	query.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_ray(query)

func _build_click() -> void:
	if build_system.dismantle_mode:
		_dismantle_aimed()
		build_system.dismantle_mode = false
		return
	if build_system.selected.is_empty():
		return
	var hit: Dictionary = _aim_hit(25.0, 0xFFFFFFFF if BELT_BUILDINGS.has(build_system.selected) else TERRAIN_COLLISION_MASK)
	if hit.is_empty():
		return
	if BELT_BUILDINGS.has(build_system.selected):
		_build_belt_click(hit)
	else:
		_place_building(hit)

func _build_belt_click(hit: Dictionary) -> void:
	var position: Vector3 = hit["position"]
	if belt_start.is_empty():
		var source: Dictionary = _nearest_port(position, "out", true)
		if source.is_empty():
			hud.show_toast("Aim within 1.2 m of a free output port.")
			return
		if not sim.is_port_free(int(source["id"]), str(source["port"])):
			hud.show_toast("Port already connected.")
			return
		belt_start = source
		hud.show_toast("Belt start set · select a free input or open ground.")
		return
	var target: Dictionary = _nearest_port(position, "in", true)
	if not target.is_empty():
		if not sim.is_port_free(int(target["id"]), str(target["port"])):
			hud.show_toast("Port already connected.")
			return
		var curve: PackedVector3Array = _belt_curve(belt_start, target)
		var reason: String = _belt_curve_reason(curve, int(belt_start["id"]), int(target["id"]))
		if not reason.is_empty():
			hud.show_toast(reason)
			return
		var count: int = ceili(_curve_length(curve) / 2.0)
		if not _can_afford(building_definitions[build_system.selected]["cost"], count):
			hud.show_toast("Not enough materials for this belt.")
			return
		var result: Dictionary = sim.add_belt(build_system.selected, int(belt_start["id"]), str(belt_start["port"]),
			int(target["id"]), str(target["port"]), curve)
		if int(result["id"]) < 0:
			hud.show_toast(str(result["reason"]))
		else:
			_pay_cost(building_definitions[build_system.selected]["cost"], count)
			belt_start.clear()
		return
	var other_output: Dictionary = _nearest_port(position, "out", true)
	if not other_output.is_empty():
		hud.show_toast("Can't connect output to output.")
		return
	var source_port: Dictionary = sim.port_world(int(belt_start["id"]), str(belt_start["port"]))
	var direction: Vector3 = position - source_port["pos"]
	var pole_yaw: float = atan2(direction.x, direction.z)
	var ground_position := Vector3(position.x, terrain.height_at(position.x, position.z), position.z)
	var pole_validation: Dictionary = placement.fit_and_validate("belt_pole", ground_position, sim, terrain, player.global_position)
	if not pole_validation["ok"]:
		hud.show_toast(str(pole_validation["reason"]))
		return
	var belt_curve: PackedVector3Array
	var pole_basis: Basis = Basis(Vector3.UP, pole_yaw)
	var pole_input := {"pos": ground_position + pole_basis * Vector3(0.0, 1.0, -0.4), "normal": pole_basis * Vector3(0.0, 0.0, -1.0)}
	var pole_curve_distance: float = source_port["pos"].distance_to(pole_input["pos"])
	var pole_handle: float = _belt_handle(pole_curve_distance)
	belt_curve = PackedVector3Array([source_port["pos"], source_port["pos"] + source_port["normal"] * pole_handle,
		pole_input["pos"] + pole_input["normal"] * pole_handle, pole_input["pos"]])
	var pole_cost: Dictionary = building_definitions["belt_pole"]["cost"]
	var belt_count: int = ceili(_curve_length(belt_curve) / 2.0)
	var total_cost: Dictionary = pole_cost.duplicate(true)
	for item_id: String in building_definitions[build_system.selected]["cost"]:
		total_cost[item_id] = int(total_cost.get(item_id, 0)) + int(building_definitions[build_system.selected]["cost"][item_id]) * belt_count
	if not _can_afford(total_cost, 1):
		hud.show_toast("Not enough materials for a belt pole and segment.")
		return
	var pole_id: int = sim.add_entity("belt_pole", ground_position, pole_yaw)
	if pole_id < 0:
		hud.show_toast("Can't place a belt pole here.")
		return
	var route_reason: String = _belt_curve_reason(belt_curve, int(belt_start["id"]), pole_id)
	if not route_reason.is_empty():
		sim.remove_entity(pole_id)
		hud.show_toast(route_reason)
		return
	var result: Dictionary = sim.add_belt(build_system.selected, int(belt_start["id"]), str(belt_start["port"]), pole_id, "in0", belt_curve)
	if int(result["id"]) < 0:
		sim.remove_entity(pole_id)
		hud.show_toast(str(result["reason"]))
	else:
		_pay_cost(total_cost, 1)
		belt_start = {"id": pole_id, "port": "out0"}

func _nearest_port(position: Vector3, direction: String, include_occupied: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = 1.2
	for entity: FactoryEntity in sim.entities.values():
		for port: Dictionary in building_definitions.get(entity.kind, {}).get("ports", []):
			if str(port["dir"]) != direction or (not include_occupied and not sim.is_port_free(entity.id, str(port["id"]))):
				continue
			var world: Dictionary = sim.port_world(entity.id, str(port["id"]))
			var distance: float = position.distance_to(world["pos"])
			if distance <= best_distance:
				best = {"id": entity.id, "port": str(port["id"])}
				best_distance = distance
	return best

func _belt_curve(from_port: Dictionary, to_port: Dictionary) -> PackedVector3Array:
	var a: Dictionary = sim.port_world(int(from_port["id"]), str(from_port["port"]))
	var b: Dictionary = sim.port_world(int(to_port["id"]), str(to_port["port"]))
	var handle: float = _belt_handle(a["pos"].distance_to(b["pos"]))
	return PackedVector3Array([a["pos"], a["pos"] + a["normal"] * handle,
		b["pos"] + b["normal"] * handle, b["pos"]])

func _belt_handle(distance: float) -> float:
	return clampf(distance * 0.45, 0.5, 8.0)

func _entity_from_hit(hit: Dictionary) -> FactoryEntity:
	var object: Node = hit.get("collider") as Node
	while object != null:
		if object.has_meta("entity_id"):
			var entity_id: int = int(object.get_meta("entity_id"))
			return sim.entities.get(entity_id)
		object = object.get_parent()
	return null

func _place_building(hit: Dictionary) -> void:
	var cost: Dictionary = building_definitions[build_system.selected]["cost"]
	if not _can_afford(cost, 1):
		hud.show_toast("Not enough materials.")
		return
	var candidate: Vector3 = placement.snap_position(hit["position"], sim)
	var node_id: int = _nearest_node_id(candidate, 3.0) if build_system.selected == "miner_mk1" else -1
	if node_id >= 0:
		var node_position: Vector3 = sim.nodes[node_id]["position"]
		candidate = Vector3(node_position.x, terrain.height_at(node_position.x, node_position.z), node_position.z)
	var validation: Dictionary = placement.fit_and_validate(build_system.selected, candidate, sim, terrain, player.global_position, node_id)
	if not validation["ok"]:
		hud.show_toast(str(validation["reason"]))
		return
	var entity_data: Dictionary = {"node_id": node_id}
	if build_system.selected == "miner_mk1":
		entity_data["supply"] = 50.0
	var entity_id: int = sim.add_entity(build_system.selected, validation["position"], placement.yaw, entity_data)
	if entity_id < 0:
		var check: Dictionary = sim.check_place(build_system.selected, validation["position"], placement.yaw, node_id)
		hud.show_toast(str(check["reason"]))
		return
	_pay_cost(cost, 1)
	foliage.remove_in_world_footprint(validation["position"], placement.yaw, BuildingDefs.size_of(build_system.selected))
	hud.show_toast("Placed %s." % build_system.selected.replace("_", " "))

func _nearest_node_id(position: Vector3, max_distance: float = 1.5) -> int:
	var closest: int = -1
	var distance: float = max_distance
	for node_id: Variant in sim.nodes:
		var node_position: Vector3 = sim.nodes[node_id]["position"]
		var candidate: float = Vector2(position.x - node_position.x, position.z - node_position.z).length()
		if candidate <= distance:
			closest = int(node_id)
			distance = candidate
	return closest

func _can_afford(cost: Dictionary, multiplier: int) -> bool:
	for item_id: String in cost:
		if int(player.inventory.get(item_id, 0)) < int(cost[item_id]) * multiplier:
			return false
	return true

func _pay_cost(cost: Dictionary, multiplier: int) -> void:
	for item_id: String in cost:
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) - int(cost[item_id]) * multiplier

func _build_info(kind: String, status: String, cost: Dictionary, multiplier: int = 1) -> String:
	var parts: Array[String] = []
	for item_id: String in cost:
		var amount: int = int(cost[item_id]) * multiplier
		var part: String = "%d %s" % [amount, Items.item_name(item_id)]
		if int(player.inventory.get(item_id, 0)) < amount:
			part = "[color=#ff6258]%s[/color]" % part
		parts.append(part)
	return "%s · %s · %s" % [kind.replace("_", " ").capitalize(), status, ", ".join(parts)]

func _update_preview() -> void:
	if build_preview == null:
		return
	if build_system.selected.is_empty() or hud.panel_is_open() or hud.build_menu.visible:
		build_preview.visible = false
		_hide_belt_previews()
		_set_port_markers_visible(false)
		hud.set_build_info("")
		hud.set_crosshair_hint("")
		return
	var hit: Dictionary = _aim_hit(25.0, 0xFFFFFFFF if BELT_BUILDINGS.has(build_system.selected) else TERRAIN_COLLISION_MASK)
	if hit.is_empty():
		build_preview.visible = false
		_hide_belt_previews()
		_set_port_markers_visible(false)
		hud.set_build_info("")
		hud.set_crosshair_hint("")
		return
	if BELT_BUILDINGS.has(build_system.selected):
		build_preview.visible = false
		_set_port_markers_visible(false)
		_update_belt_preview(hit)
		return
	_hide_belt_previews()
	if preview_kind != build_system.selected:
		_create_model_preview(build_system.selected)
	var candidate: Vector3 = placement.snap_position(hit["position"], sim)
	var node_id: int = _nearest_node_id(candidate, 3.0) if build_system.selected == "miner_mk1" else -1
	if node_id >= 0:
		var node_position: Vector3 = sim.nodes[node_id]["position"]
		candidate = Vector3(node_position.x, terrain.height_at(node_position.x, node_position.z), node_position.z)
	var validation: Dictionary = placement.fit_and_validate(build_system.selected, candidate, sim, terrain, player.global_position, node_id)
	var valid: bool = bool(validation["ok"]) and _can_afford(building_definitions[build_system.selected]["cost"], 1)
	var reason: String = str(validation["reason"])
	if valid and not _can_afford(building_definitions[build_system.selected]["cost"], 1):
		valid = false
		reason = "Not enough materials"
	var target: Vector3 = validation["position"]
	if not placement.preview_initialized:
		placement.preview_position = target
		placement.preview_initialized = true
	else:
		placement.preview_position = placement.preview_position.lerp(target, 1.0 - exp(-20.0 * get_physics_process_delta_time()))
	build_preview.visible = true
	build_preview.position = placement.preview_position
	build_preview.rotation.y = placement.yaw
	preview_material.set_shader_parameter("tint", Color(0.2, 1.0, 0.5) if valid else Color(1.0, 0.12, 0.1))
	hud.set_build_info(_build_info(build_system.selected, reason if not valid else "Ready",
		building_definitions[build_system.selected]["cost"]))
	hud.set_crosshair_hint(reason if not valid else "")

func _update_belt_preview(hit: Dictionary) -> void:
	if belt_start.is_empty():
		hud.set_build_info("Aim at an output port · click to start")
		hud.set_crosshair_hint("")
		return
	var target: Dictionary = _nearest_port(hit["position"], "in", true)
	if target.is_empty():
		if not _nearest_port(hit["position"], "out", true).is_empty():
			_show_belt_preview(PackedVector3Array(), false, "Can't connect output to output")
			return
		var source_port: Dictionary = sim.port_world(int(belt_start["id"]), str(belt_start["port"]))
		var ground: Vector3 = Vector3(hit["position"].x, terrain.height_at(hit["position"].x, hit["position"].z), hit["position"].z)
		var direction: Vector3 = ground - source_port["pos"]
		var yaw: float = atan2(direction.x, direction.z)
		var basis: Basis = Basis(Vector3.UP, yaw)
		var target_port := {"pos": ground + basis * Vector3(0.0, 1.0, -0.4), "normal": basis * Vector3(0.0, 0.0, -1.0)}
		var handle: float = _belt_handle(source_port["pos"].distance_to(target_port["pos"]))
		var curve := PackedVector3Array([source_port["pos"], source_port["pos"] + source_port["normal"] * handle,
			target_port["pos"] + target_port["normal"] * handle, target_port["pos"]])
		var reason: String = ""
		var pole_validation: Dictionary = placement.fit_and_validate("belt_pole", ground, sim, terrain, player.global_position)
		if not pole_validation["ok"]:
			reason = str(pole_validation["reason"])
		else:
			reason = _belt_curve_reason(curve, int(belt_start["id"]), -1)
		var count: int = ceili(_curve_length(curve) / 2.0)
		var total_cost: Dictionary = building_definitions["belt_pole"]["cost"].duplicate(true)
		for item_id: String in building_definitions[build_system.selected]["cost"]:
			total_cost[item_id] = int(total_cost.get(item_id, 0)) + int(building_definitions[build_system.selected]["cost"][item_id]) * count
		if reason.is_empty() and not _can_afford(total_cost, 1):
			reason = "Not enough materials for a belt pole and segment"
		_show_belt_preview(curve, reason.is_empty(), reason if not reason.is_empty() else "Belt pole · %.1f m" % _curve_length(curve))
		return
	var curve: PackedVector3Array = _belt_curve(belt_start, target)
	var reason: String = "Port already connected" if not sim.is_port_free(int(target["id"]), str(target["port"])) else _belt_curve_reason(curve, int(belt_start["id"]), int(target["id"]))
	var valid: bool = reason.is_empty() and _can_afford(building_definitions[build_system.selected]["cost"], ceili(_curve_length(curve) / 2.0))
	if not valid and reason.is_empty():
		reason = "Not enough materials"
	_show_belt_preview(curve, valid, reason if not valid else "Belt · %.1f m" % _curve_length(curve))

func _show_belt_preview(curve: PackedVector3Array, valid: bool, label: String) -> void:
	belt_preview_mesh.clear_surfaces()
	if curve.size() == 4:
		belt_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for index: int in range(33):
			belt_preview_mesh.surface_add_vertex(_bezier_point(curve, float(index) / 32.0))
		belt_preview_mesh.surface_end()
	(belt_preview_visual.material_override as StandardMaterial3D).albedo_color = Color(0.2, 1.0, 0.5) if valid else Color(1.0, 0.12, 0.1)
	belt_preview_visual.visible = true
	hud.set_build_info(label)
	hud.set_crosshair_hint("" if valid else label)

func _new_preview_cell() -> MeshInstance3D:
	var ghost: MeshInstance3D = MeshInstance3D.new()
	ghost.mesh = BoxMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = material
	add_child(ghost)
	return ghost

func _hide_belt_previews() -> void:
	if belt_preview_visual != null:
		belt_preview_visual.visible = false
	for ghost: MeshInstance3D in belt_preview_cells:
		ghost.visible = false

func _update_port_markers(_cell: Vector2i) -> void:
	pass

func _set_port_markers_visible(visible: bool) -> void:
	for marker: MeshInstance3D in port_markers:
		marker.visible = visible

func _create_preview() -> void:
	if DisplayServer.get_name() == "headless":
		return
	build_preview = Node3D.new()
	build_preview.name = "PlacementPreview"
	build_preview.visible = false
	add_child(build_preview)
	belt_preview_mesh = ImmediateMesh.new()
	belt_preview_visual = MeshInstance3D.new()
	belt_preview_visual.mesh = belt_preview_mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	belt_preview_visual.material_override = material
	belt_preview_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	belt_preview_visual.visible = false
	add_child(belt_preview_visual)

func _create_model_preview(kind: String) -> void:
	for child: Node in build_preview.get_children():
		child.queue_free()
	var model_root: Node3D = Node3D.new()
	build_preview.add_child(model_root)
	var size: Vector3 = BuildingDefs.size_of(kind)
	machine_models.build(kind, model_root, Vector2i(roundi(size.x * 0.5), roundi(size.z * 0.5)), Vector3.ZERO)
	var ghost_shader: Shader = load("res://shaders/placement_ghost.gdshader") as Shader
	preview_material = ShaderMaterial.new()
	preview_material.shader = ghost_shader
	preview_material.set_shader_parameter("tint", Color(0.2, 1.0, 0.5))
	for node: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		mesh_instance.material_override = preview_material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node: Node in model_root.find_children("*", "CPUParticles3D", true, false):
		(node as CPUParticles3D).emitting = false
	visuals.add_preview_port_markers(model_root, kind)
	preview_kind = kind

func _bezier_point(curve: PackedVector3Array, t: float) -> Vector3:
	var u: float = 1.0 - t
	return curve[0] * u * u * u + curve[1] * 3.0 * u * u * t + curve[2] * 3.0 * u * t * t + curve[3] * t * t * t

func _curve_length(curve: PackedVector3Array) -> float:
	var total: float = 0.0
	var previous: Vector3 = curve[0]
	for index: int in range(1, 33):
		var current: Vector3 = _bezier_point(curve, float(index) / 32.0)
		total += previous.distance_to(current)
		previous = current
	return total

func _belt_curve_reason(curve: PackedVector3Array, from_id: int, to_id: int) -> String:
	var length: float = _curve_length(curve)
	if length < 0.5 or length > 56.0:
		return "Belt length must be 0.5–56 m"
	var points: Array[Vector3] = []
	var sample_count: int = maxi(32, ceili(length / 0.5))
	for index: int in range(sample_count + 1):
		var point: Vector3 = _bezier_point(curve, float(index) / float(sample_count))
		points.append(point)
		if point.y < terrain.height_at(point.x, point.z) - 0.05:
			return "Belt crosses terrain"
		if index > 0:
			var tangent: Vector3 = point - points[index - 1]
			if atan2(absf(tangent.y), Vector2(tangent.x, tangent.z).length()) > deg_to_rad(35.0):
				return "Belt slope exceeds 35°"
	for index: int in range(1, points.size() - 1):
		var ab: Vector3 = points[index] - points[index - 1]
		var bc: Vector3 = points[index + 1] - points[index]
		var ac: Vector3 = points[index + 1] - points[index - 1]
		var area: float = ab.cross(ac).length() * 0.5
		if area > 0.0001 and ab.length() * bc.length() * ac.length() / (4.0 * area) < 1.5:
			return "Bend too tight"
	for point: Vector3 in points:
		var blocker: String = sim.blocked_kind(point, Vector3(0.2, 0.2, 0.2), 0.0, [from_id, to_id])
		if not blocker.is_empty():
			return "Blocked by %s" % blocker
	return ""

func _preview_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _interact() -> void:
	var hit: Dictionary = _aim_hit(6.0)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider is Node:
		var object: Node = collider
		while object != null:
			if object.has_meta("entity_id"):
				hud.open_entity(int(object.get_meta("entity_id")))
				return
			if object.has_meta("ore_boulder"):
				mining_boulder_id = str(object.get_meta("ore_boulder"))
				hand_mine_elapsed = 0.0
				hud.show_toast("Hold E to mine this ore boulder.", 4.0)
				return
			if object.has_meta("resource_node"):
				mining_boulder_id = ""
				hud.show_toast("Place a Miner here.", 4.0)
				return
			if object.has_meta("interactable"):
				if str(object.get_meta("interactable")) == "hub":
					hud.open_hub()
				return
			object = object.get_parent()
	if player.global_position.distance_to(terrain.spire_position) < 12.0:
		hud.open_entity(spire_entity_id)
	elif player.global_position.distance_to(terrain.landing_position + Vector3(4.0, 0.0, 0.0)) < 8.0:
		hud.open_hub()

func _dismantle_aimed() -> void:
	var hit: Dictionary = _aim_hit(6.0)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if not collider is Node:
		return
	var object: Node = collider
	while object != null and not object.has_meta("entity_id"):
		object = object.get_parent()
	if object == null:
		return
	var entity_id: int = int(object.get_meta("entity_id"))
	if not sim.entities.has(entity_id) or sim.entities[entity_id].kind == "spire":
		return
	var refund: Dictionary = sim.remove_entity_with_refund(entity_id)
	for item_id: String in refund:
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + int(refund[item_id])
	hud.show_toast("Dismantled · connected belts, materials and buffers refunded.")

func _save_game() -> void:
	if save_backup_pending:
		if not save_system.backup_existing_save():
			hud.show_toast("Save skipped · couldn't back up the existing save.", 6.0)
			return
		save_backup_pending = false
	var world_state: Dictionary = {
		"boulders": terrain.ore_boulders.to_dict(),
		"foliage": foliage.state.to_dict()
	}
	if save_system.save_game(sim, player, unlocked_tiers, world_state, hotbar_model.to_dict(), sim.power.bypass):
		hud.show_toast("Saved to user://save.json")
	else:
		hud.show_toast("Save failed.")

func _load_game() -> void:
	_load_saved_game(true)

func _load_saved_game(show_toast: bool) -> bool:
	var loaded: Dictionary = save_system.load_game(sim, player)
	if loaded.is_empty():
		if show_toast:
			hud.show_toast("No compatible save found.")
		return false
	var restore_position: Vector3 = player.position
	restore_position.x = clampf(restore_position.x, -FactoryTerrain.WORLD_HALF_EXTENT + 1.0,
		FactoryTerrain.WORLD_HALF_EXTENT - 1.0)
	restore_position.z = clampf(restore_position.z, -FactoryTerrain.WORLD_HALF_EXTENT + 1.0,
		FactoryTerrain.WORLD_HALF_EXTENT - 1.0)
	player.position = SafePlayerPosition.adjust(restore_position,
		terrain.height_at(restore_position.x, restore_position.z), FactoryTerrain.WORLD_HALF_EXTENT)
	unlocked_tiers = int(loaded["unlocked_tiers"])
	hotbar_model.load_dict(loaded.get("hotbar", {}))
	if hotbar_model.selected_index >= 0 and hotbar_model.is_locked(hotbar_model.selected_index, unlocked_tiers):
		hotbar_model.selected_index = -1
	_apply_hotbar_selection(false)
	for item_id: String in loaded.get("belt_refund", {}):
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + int(loaded["belt_refund"][item_id])
	if int(loaded.get("migrated_from", 0)) > 0:
		for entity: FactoryEntity in sim.entities.values():
			if entity.kind not in ["belt_mk1", "belt_mk2"]:
				entity.position.y = terrain.height_at(entity.position.x, entity.position.z)
	var world_state: Dictionary = loaded.get("world", {})
	terrain.restore_boulders(world_state.get("boulders", {}))
	foliage.restore_state(world_state.get("foliage", []))
	hud.unlocked_tiers = unlocked_tiers
	hud._update_hotbar()
	last_spire_stage = sim.spire_stage
	for entity: FactoryEntity in sim.entities.values():
		if entity.kind == "spire":
			spire_entity_id = entity.id
			break
	visuals.refresh()
	_reveal_discovered_nodes()
	if show_toast:
		var load_message: String = "Old belts were refunded — reconnect machines with new belts" if int(loaded.get("migrated_from", 0)) > 0 else "Factory loaded."
		if sim.restore_failure_count > 0:
			load_message += " %d machines couldn't be restored and were refunded." % sim.restore_failure_count
		hud.show_toast(load_message)
	return true

func _buy_tier(index: int) -> void:
	if index != unlocked_tiers + 1:
		return
	var tier: Dictionary = tier_definitions[index]
	if not _can_afford(tier["cost"], 1):
		hud.show_toast("Missing materials for %s." % tier["name"])
		return
	_pay_cost(tier["cost"], 1)
	unlocked_tiers = index
	hud.unlocked_tiers = unlocked_tiers
	hud._update_hotbar()
	hud.show_toast("Tier %d unlocked · %s." % [index, tier["name"]])
	hud.open_hub()

func _hand_craft(recipe_id: String) -> void:
	if not recipe_definitions.has(recipe_id):
		return
	var recipe: Dictionary = recipe_definitions[recipe_id]
	for item_id: String in recipe["inputs"]:
		if int(player.inventory.get(item_id, 0)) < int(recipe["inputs"][item_id]):
			hud.show_toast("Missing %s." % Items.item_name(item_id))
			return
	await get_tree().create_timer(0.5).timeout
	for item_id: String in recipe["inputs"]:
		if int(player.inventory.get(item_id, 0)) < int(recipe["inputs"][item_id]):
			hud.show_toast("Missing %s." % Items.item_name(item_id))
			return
	for item_id: String in recipe["inputs"]:
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) - int(recipe["inputs"][item_id])
	for item_id: String in recipe["outputs"]:
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + int(recipe["outputs"][item_id])
	hud.show_toast("Crafted %s." % Items.item_name(str(recipe["outputs"].keys()[0])))
	hud.open_inventory()

func _on_panel_closed() -> void:
	hud.close_build_menu()

func _update_sightings() -> void:
	if herd.members.is_empty():
		return
	var distance: float = player.global_position.distance_to(herd.members[0].global_position)
	if distance < 30.0 and not first_sighting:
		first_sighting = true
		hud.show_toast("Borebacks follow mineral seams...", 7.0)
	if Input.is_action_pressed("sprint"):
		herd.alert_sprint(player.global_position)
	if distance < 15.0 and not sim.discovered_nodes.get("hidden_iron", false):
		var herd_to_hidden: float = herd.members[0].global_position.distance_to(terrain.hidden_iron)
		if herd_to_hidden < 24.0:
			sim.discovered_nodes["hidden_iron"] = true
			for node: Dictionary in terrain.nodes:
				if bool(node.get("hidden", false)):
					node["hidden"] = false
					terrain._make_node_visual(node)
			hud.show_toast("A Boreback herd led you to a PURE iron deposit!", 8.0)

func _reveal_discovered_nodes() -> void:
	if not sim.discovered_nodes.get("hidden_iron", false):
		return
	for node: Dictionary in terrain.nodes:
		if bool(node.get("hidden", false)):
			node["hidden"] = false
			terrain._make_node_visual(node)

func _quit_game() -> void:
	get_tree().quit()

func _capture_all() -> void:
	hud.show_toast("", 0.0)
	for mode: String in ["spawn", "overview", "forestlake", "mountains", "line", "factory", "orepatch",
			"boulder-before", "boulder-mid", "boulder-after", "panel"]:
		await _capture_screenshot(mode)
	get_tree().quit()

func _capture_v7_shots() -> void:
	hud.show_toast("", 0.0)
	if hud.help_panel.visible:
		hud.toggle_help()
	player.set_physics_process(false)
	for _frame: int in range(120):
		if hud.icon_cache.prepared:
			break
		await get_tree().process_frame
	player.position = Vector3(0.0, terrain.height_at(0.0, 38.0) + 0.1, 38.0)
	player.rotation.y = 0.0
	player.pitch = 0.0
	player.camera.rotation.x = 0.0
	player.velocity = Vector3.ZERO
	capture_preview_override = false
	hotbar_model.selected_index = -1
	_apply_hotbar_selection(false)
	await get_tree().create_timer(0.5).timeout
	_write_capture("empty-hands")

	hotbar_model.select_slot(1, unlocked_tiers)
	_apply_hotbar_selection(false)
	await get_tree().create_timer(0.55).timeout
	_write_capture("selected-hotbar")
	hotbar_model.assign(7, "item", "iron_ore")
	player.inventory["iron_ore"] = 40
	hotbar_model.selected_index = -1
	hotbar_model.select_slot(7, unlocked_tiers)
	_apply_hotbar_selection(false)
	await get_tree().create_timer(0.45).timeout
	_write_capture("iron-ore-held")

	hotbar_model.assign(8, "item", "iron_plate")
	player.inventory["iron_plate"] = 80
	hotbar_model.selected_index = -1
	hotbar_model.select_slot(8, unlocked_tiers)
	_apply_hotbar_selection(false)
	await get_tree().create_timer(0.45).timeout
	_write_capture("iron-plate-held")

	hotbar_model.selected_index = -1
	hotbar_model.select_slot(1, unlocked_tiers)
	_apply_hotbar_selection(false)
	var ghost_position: Vector3 = Vector3(0.0, terrain.height_at(0.0, 30.0), 30.0)
	capture_preview_override = true
	_set_placement_preview("smelter", ghost_position)
	await get_tree().create_timer(0.45).timeout
	_write_capture("build-tool-smelter-ghost")

	var boulder_position: Vector3 = terrain.boulder_definitions[0]["position"]
	capture_preview_override = false
	hotbar_model.selected_index = -1
	_apply_hotbar_selection(false)
	_set_capture_view(boulder_position + Vector3(0.0, 0.9, 0.0),
		boulder_position + Vector3(0.0, 2.0, 2.8))
	await get_tree().create_timer(0.2).timeout
	viewmodel.play_mining_swing()
	await get_tree().create_timer(0.18).timeout
	_write_capture("boulder-mining-swing")

	player.position = Vector3(0.0, terrain.height_at(0.0, 38.0) + 0.1, 38.0)
	player.rotation.y = 0.0
	player.pitch = 0.0
	player.camera.rotation.x = 0.0
	hud.open_inventory()
	hud._set_assignment_target("item", "iron_ore")
	await get_tree().create_timer(0.45).timeout
	_write_capture("inventory-hover-assign")
	hud.close_panel()
	get_tree().quit()

func _capture_machine_set() -> void:
	hud.show_toast("", 0.0)
	hud.hide()
	visuals.visible = false
	for kind: String in ["miner_mk1", "smelter", "constructor", "assembler", "geo_tap",
			"power_pole", "storage", "splitter", "merger", "belt", "spire", "hub", "drop_pod"]:
		var model_kind: String = "belt_mk1" if kind == "belt" else kind
		var model_size: Vector3 = BuildingDefs.size_of(model_kind)
		if kind == "hub":
			model_size = Vector3(4.0, 3.5, 3.0)
		elif kind == "drop_pod":
			model_size = Vector3(3.0, 4.0, 3.0)
		var capture_root: Node3D = Node3D.new()
		capture_root.position = Vector3(0.0, terrain.height_at(0.0, 0.0), 0.0)
		add_child(capture_root)
		machine_models.build(model_kind, capture_root,
			Vector2i(maxi(1, roundi(model_size.x * 0.5)), maxi(1, roundi(model_size.z * 0.5))), Vector3.ZERO)
		var target: Vector3 = capture_root.position + Vector3(0.0, model_size.y * 0.52, 0.0)
		var camera_distance: float = maxf(4.5, maxf(model_size.x, maxf(model_size.z, model_size.y)) * 1.25)
		_set_capture_view(target, target + Vector3(camera_distance * 0.35, camera_distance * 0.32, camera_distance))
		await get_tree().create_timer(0.7).timeout
		_write_capture("machine-" + kind)
		capture_root.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _build_demo_factory() -> void:
	var node_id: int = _nearest_node_id(Vector3(-17.0, 0.0, -2.0))
	var miner: int = sim.add_entity("miner_mk1", Vector3(-17.0, terrain.height_at(-17.0, -2.0), -2.0), 0.0, {"node_id": node_id})
	demo_smelter_id = sim.add_entity("smelter", Vector3(-17.0, terrain.height_at(-17.0, 4.0), 4.0), 0.0, {"recipe": "iron_ingot"})
	var constructor: int = sim.add_entity("constructor", Vector3(-17.0, terrain.height_at(-17.0, 11.0), 11.0), 0.0, {"recipe": "iron_plate"})
	var storage: int = sim.add_entity("storage", Vector3(-17.0, terrain.height_at(-17.0, 19.0), 19.0))
	var vent_position: Vector3 = terrain.vents[0]
	var tap: int = sim.add_entity("geo_tap", vent_position)
	var pole: int = sim.add_entity("power_pole", Vector3(-48.0, terrain.height_at(-48.0, 5.0), 5.0))
	for x: float in [-36.0, -24.0, -12.0, -5.0]:
		sim.add_entity("power_pole", Vector3(x, terrain.height_at(x, 5.0), 5.0))
	if miner >= 0 and demo_smelter_id >= 0 and constructor >= 0 and storage >= 0 and pole >= 0 and tap >= 0:
		var miner_out := {"id": miner, "port": "out0"}
		var smelter_in := {"id": demo_smelter_id, "port": "in0"}
		var smelter_out := {"id": demo_smelter_id, "port": "out0"}
		var constructor_in := {"id": constructor, "port": "in0"}
		var constructor_out := {"id": constructor, "port": "out0"}
		var storage_in := {"id": storage, "port": "in0"}
		sim.add_belt("belt_mk1", miner, "out0", demo_smelter_id, "in0", _belt_curve(miner_out, smelter_in))
		sim.add_belt("belt_mk1", demo_smelter_id, "out0", constructor, "in0", _belt_curve(smelter_out, constructor_in))
		sim.add_belt("belt_mk1", constructor, "out0", storage, "in0", _belt_curve(constructor_out, storage_in))
		visuals.refresh()
		hud.show_toast("Demo line: Miner → Smelter → Constructor → Storage", 5.0)
		player.inventory["iron_plate"] = 500
		player.inventory["concrete"] = 100

func _capture_screenshot(mode: String) -> void:
	if mode.begins_with("v5-"):
		capture_preview_override = true
		await _capture_phase2_scenario(mode)
		await get_tree().process_frame
		_write_capture(mode)
		get_tree().quit()
		return
	if hud.help_panel.visible:
		hud.toggle_help()
	var needs_demo: bool = mode in ["line", "panel", "overview", "factory", "orepatch", "fps-demo"] or mode.begins_with("machine-")
	if needs_demo:
		if sim.entities.size() <= 1:
			_build_demo_factory()
			visuals.refresh()
	if mode.begins_with("machine-"):
		var kind: String = mode.trim_prefix("machine-")
		var target: Vector3 = Vector3.ZERO
		var camera_distance: float = 8.0
		if kind == "hub":
			target = terrain.landing_position + Vector3(4.0, 1.7, 0.0)
		elif kind == "drop_pod":
			target = terrain.landing_position + Vector3(-5.0, 2.2, 0.0)
		else:
			var entity_kind: String = "spire" if kind == "spire" else "belt_mk1" if kind == "belt" else kind
			for entity_id: Variant in sim.entities:
				var entity: FactoryEntity = sim.entities[entity_id]
				if entity.kind != entity_kind:
					continue
				var size: Vector3 = BuildingDefs.size_of(entity.kind)
				var height: float = {"miner_mk1": 6.5, "smelter": 5.0, "constructor": 3.8,
					"assembler": 4.2, "geo_tap": 4.2, "power_pole": 6.3, "storage": 3.4,
					"splitter": 1.9, "merger": 1.9, "spire": 17.0, "belt_mk1": 0.9}.get(entity.kind, 3.0)
				var visual: Node3D = visuals.entity_nodes.get(entity.id) as Node3D
				var base_position: Vector3 = visual.global_position if visual != null else entity.position
				target = base_position + Vector3(0.0, height * 0.5, 0.0)
				camera_distance = maxf(7.0, maxf(size.x, maxf(size.z, height)) * 1.35)
				break
		var camera_position: Vector3 = target + Vector3(camera_distance * 0.3, camera_distance * 0.32, camera_distance)
		if kind == "belt":
			camera_position = target + Vector3(camera_distance, camera_distance * 0.28, 0.0)
		elif kind in ["splitter", "merger"]:
			camera_position = target + Vector3(camera_distance * 0.8, camera_distance * 0.28, camera_distance * 0.65)
		_set_capture_view(target, camera_position)
		await get_tree().create_timer(0.8).timeout
	elif mode == "overview" or mode == "factory":
		player.position = Vector3(-17.0, terrain.height_at(-17.0, 33.0) + 25.0, 33.0)
		player.velocity = Vector3.ZERO
		player.rotation.y = 0.0
		player.pitch = -PI / 4.0
		player.camera.rotation.x = player.pitch
		player.set_physics_process(false)
		await get_tree().create_timer(0.8).timeout
	elif mode == "spawn" or mode == "fps-spawn":
		player.position = Vector3(0.0, terrain.height_at(0.0, 38.0) + 0.1, 38.0)
		player.velocity = Vector3.ZERO
		player.rotation.y = 0.0
		player.pitch = 0.0
		player.camera.rotation.x = 0.0
		player.set_physics_process(false)
		await get_tree().create_timer(7.0).timeout
	elif mode == "forestlake":
		_set_capture_view(Vector3(-90.0, terrain.height_at(-90.0, 120.0) + 30.0, 120.0),
			Vector3(-205.0, terrain.height_at(-205.0, 190.0) + 7.0, 190.0))
		await get_tree().create_timer(0.8).timeout
	elif mode == "mountains":
		_set_capture_view(Vector3(0.0, terrain.height_at(0.0, -500.0) + 80.0, -500.0),
			Vector3(0.0, terrain.height_at(0.0, -300.0) + 6.0, -300.0))
		await get_tree().create_timer(0.8).timeout
	elif mode == "orepatch":
		_set_capture_view(terrain.point_for_cell(Vector2i(-9, -2)) + Vector3(0.0, 0.5, 0.0),
			terrain.point_for_cell(Vector2i(-5, 0)) + Vector3(0.0, 4.0, 4.0))
		await get_tree().create_timer(5.0).timeout
	elif mode in ["boulder-before", "boulder-mid", "boulder-after"]:
		var definition: Dictionary = terrain.boulder_definitions[0]
		var boulder_id: String = str(definition["id"])
		var boulder_position: Vector3 = definition["position"]
		if mode == "boulder-mid":
			for _index: int in range(int(definition["remaining"]) / 2):
				terrain.mine_boulder(boulder_id)
		elif mode == "boulder-after":
			while terrain.ore_boulders.remaining_for(boulder_id) > 0:
				terrain.mine_boulder(boulder_id)
			await get_tree().process_frame
			print("BOULDER_CAPTURE remaining: %d, visual_present: %s" % [
				terrain.ore_boulders.remaining_for(boulder_id), terrain.boulder_nodes.has(boulder_id)
			])
		_set_capture_view(boulder_position + Vector3(0.0, 0.8, 0.0), boulder_position + Vector3(0.0, 3.5, 7.5))
		await get_tree().create_timer(0.8).timeout
	elif mode == "line" or mode == "panel":
		player.position = Vector3(-34.0, terrain.height_at(-34.0, 12.0) + 10.0, 12.0)
		player.velocity = Vector3.ZERO
		player.set_physics_process(false)
		player.rotation.y = -PI / 2.0
		player.pitch = -0.55
		player.camera.rotation.x = player.pitch
		if mode == "line":
			player.camera.fov = 58.0
		await get_tree().create_timer(13.0).timeout
		if mode == "panel" and demo_smelter_id >= 0:
			player.position = Vector3(-30.0, terrain.height_at(-30.0, 5.0) + 1.0, 5.0)
			player.rotation.y = -PI / 2.0
			player.pitch = -0.08
			player.camera.rotation.x = player.pitch
			player.camera.fov = 70.0
			hud.open_entity(demo_smelter_id)
			await get_tree().create_timer(0.8).timeout
	elif mode == "fps-demo":
		player.position = Vector3(-34.0, terrain.height_at(-34.0, 12.0) + 10.0, 12.0)
		player.rotation.y = -PI / 2.0
		player.pitch = -0.4
		player.camera.rotation.x = player.pitch
		player.set_physics_process(false)
		await get_tree().create_timer(2.0).timeout
		var fps_total: float = 0.0
		for _frame: int in range(30):
			await get_tree().process_frame
			fps_total += float(Engine.get_frames_per_second())
		print("FPS_CAPTURE %s: %.1f" % [mode, fps_total / 30.0])
	else:
		await get_tree().create_timer(1.5).timeout
	await get_tree().process_frame
	if mode == "fps-spawn":
		await get_tree().create_timer(2.0).timeout
		var fps_total: float = 0.0
		for _frame: int in range(30):
			await get_tree().process_frame
			fps_total += float(Engine.get_frames_per_second())
		print("FPS_CAPTURE %s: %.1f" % [mode, fps_total / 30.0])
	_write_capture(mode)

func _write_capture(mode: String) -> void:
	var capture_directory: String = OS.get_environment("FACTORY_CAPTURE_DIR")
	if capture_directory.is_empty():
		capture_directory = "/home/ubuntu/specs/shots/v7"
	DirAccess.make_dir_recursive_absolute(capture_directory)
	var filename_mode: String = mode.trim_prefix("v5-") if mode.begins_with("v5-") else mode.trim_prefix("machine-") if mode.begins_with("machine-") else mode
	var filename: String = "%s/%s.png" % [capture_directory, filename_mode]
	var error: Error = get_viewport().get_texture().get_image().save_png(filename)
	print("SCREENSHOT: %s (%s)" % [filename, error_string(error)])

func _capture_phase2_scenario(mode: String) -> void:
	if hud.help_panel.visible:
		hud.toggle_help()
	if mode == "v5-green-preview":
		var position: Vector3 = _find_valid_capture_position("smelter", Vector3(40.0, 0.0, 70.0))
		_set_placement_preview("smelter", position)
		_set_capture_view(position + Vector3(0.0, 2.5, 0.0), position + Vector3(8.0, 5.0, 9.0))
	elif mode == "v5-red-overlap":
		var position: Vector3 = _find_valid_capture_position("constructor", Vector3(50.0, 0.0, 82.0))
		sim.add_entity("constructor", position)
		visuals.refresh()
		_set_placement_preview("smelter", position)
		build_preview.position += Vector3(0.22, 0.0, 0.22)
		_set_capture_view(position + Vector3(0.0, 2.5, 0.0), position + Vector3(8.0, 5.0, 9.0))
	elif mode == "v5-red-miner":
		var node_id: int = 0
		var node_position: Vector3 = sim.nodes[node_id]["position"]
		sim.add_entity("miner_mk1", node_position, 0.0, {"node_id": node_id})
		visuals.refresh()
		_set_placement_preview("miner_mk1", node_position)
		build_preview.position += Vector3(0.22, 0.0, 0.22)
		_set_capture_view(node_position + Vector3(0.0, 2.5, 0.0), node_position + Vector3(7.0, 4.5, 8.0))
	elif mode in ["v5-belt-to-smelter", "v5-belt-port-closeup"]:
		var node_id: int = 0
		var node_position: Vector3 = sim.nodes[node_id]["position"]
		var miner: int = sim.add_entity("miner_mk1", node_position, 0.0, {"node_id": node_id})
		var smelter_position := Vector3(node_position.x, terrain.height_at(node_position.x, node_position.z + 6.0), node_position.z + 6.0)
		var smelter: int = sim.add_entity("smelter", smelter_position, 0.0, {"recipe": "iron_ingot"})
		var result: Dictionary = _connect_belt("belt_mk1", miner, "out0", smelter, "in0")
		if int(result["id"]) > 0:
			var belt: FactoryEntity = sim.entities[int(result["id"])]
			belt.belt_items = [
				{"item": "iron_ore", "s": maxf(0.0, float(belt.extra["length"]) - 1.1), "born_at": -1.0},
				{"item": "iron_ore", "s": maxf(0.0, float(belt.extra["length"]) - 2.2), "born_at": -1.0}
			]
			sim.tick(0.05)
		visuals.refresh()
		var smelter_port: Dictionary = sim.port_world(smelter, "in0")
		var target: Vector3 = smelter_port["pos"]
		var camera_offset: Vector3 = Vector3(2.5, 1.5, 0.7) if mode == "v5-belt-port-closeup" else Vector3(4.0, 2.2, 1.0)
		_set_capture_view(target + Vector3(0.0, 0.5, 0.0), target + camera_offset)
	elif mode == "v5-pole-turn":
		var source_position := Vector3(70.0, terrain.height_at(70.0, 70.0), 70.0)
		var pole_position := Vector3(70.0, terrain.height_at(70.0, 76.0), 76.0)
		var target_position := Vector3(76.0, terrain.height_at(76.0, 76.0), 76.0)
		var source: int = sim.add_entity("smelter", source_position, 0.0, {"recipe": "iron_ingot"})
		var pole: int = sim.add_entity("belt_pole", pole_position, 0.0)
		var merger: int = sim.add_entity("merger", target_position, 0.0)
		var first_belt: Dictionary = _connect_belt("belt_mk1", source, "out0", pole, "in0")
		var second_belt: Dictionary = _connect_belt("belt_mk1", pole, "out0", merger, "in0")
		if int(first_belt["id"]) > 0:
			var first: FactoryEntity = sim.entities[int(first_belt["id"])]
			first.belt_items = [{"item": "iron_ore", "s": 0.8, "born_at": -1.0}]
		if int(second_belt["id"]) > 0:
			var second: FactoryEntity = sim.entities[int(second_belt["id"])]
			second.belt_items = [{"item": "iron_ore", "s": 0.4, "born_at": -1.0}]
		visuals.refresh()
		_set_capture_view(Vector3(73.0, terrain.height_at(73.0, 74.0) + 1.0, 74.0),
			Vector3(64.0, terrain.height_at(64.0, 74.0) + 7.0, 82.0))
	elif mode == "v5-hill-belt":
		var source_position := Vector3(150.0, terrain.height_at(150.0, 20.0), 20.0)
		var target_position := Vector3(190.0, terrain.height_at(190.0, 20.0), 20.0)
		var source: int = sim.add_entity("smelter", source_position, 0.0, {"recipe": "iron_ingot"})
		var target: int = sim.add_entity("storage", target_position)
		build_system.choose("belt_mk1")
		belt_start = {"id": source, "port": "out0"}
		var curve: PackedVector3Array = _belt_curve(belt_start, {"id": target, "port": "in0"})
		var reason: String = _belt_curve_reason(curve, source, target)
		var route_height: float = maxf(curve[0].y, curve[3].y)
		for index: int in range(33):
			var route_point: Vector3 = curve[0].lerp(curve[3], float(index) / 32.0)
			route_height = maxf(route_height, terrain.height_at(route_point.x, route_point.z))
		var control_height: float = route_height + 50.0
		curve[1] = Vector3(lerpf(curve[0].x, curve[3].x, 0.33), control_height,
			lerpf(curve[0].z, curve[3].z, 0.33))
		curve[2] = Vector3(lerpf(curve[0].x, curve[3].x, 0.66), control_height,
			lerpf(curve[0].z, curve[3].z, 0.66))
		if reason.is_empty():
			reason = "Belt crosses terrain"
		_show_belt_preview(curve, false, reason if not reason.is_empty() else "Belt crosses terrain")
		var focus: Vector3 = _bezier_point(curve, 0.5)
		focus.y = route_height + 15.0
		_set_capture_view(focus, focus + Vector3.UP * 70.0)
	else:
		_build_demo_factory()
		for _step: int in range(1200):
			sim.tick(0.05)
		visuals.refresh()
		_set_capture_view(Vector3(-17.0, terrain.height_at(-17.0, 8.0) + 1.8, 8.0),
			Vector3(-31.0, terrain.height_at(-31.0, 10.0) + 8.0, 10.0))
	await get_tree().create_timer(1.0).timeout

func _find_valid_capture_position(kind: String, origin: Vector3) -> Vector3:
	for radius: float in [0.0, 4.0, 8.0, 12.0, 16.0]:
		for angle_index: int in range(8):
			var angle: float = TAU * float(angle_index) / 8.0
			var x: float = origin.x + cos(angle) * radius
			var z: float = origin.z + sin(angle) * radius
			var candidate := Vector3(x, terrain.height_at(x, z), z)
			var validation: Dictionary = placement.fit_and_validate(kind, candidate, sim, terrain, player.global_position)
			if bool(validation["ok"]):
				return validation["position"]
	return Vector3(origin.x, terrain.height_at(origin.x, origin.z), origin.z)

func _set_placement_preview(kind: String, position: Vector3) -> void:
	build_system.choose(kind)
	placement.yaw = 0.0
	placement.preview_initialized = true
	_create_model_preview(kind)
	var node_id: int = _nearest_node_id(position, 3.0) if kind == "miner_mk1" else -1
	if node_id >= 0:
		var node_position: Vector3 = sim.nodes[node_id]["position"]
		position = Vector3(node_position.x, terrain.height_at(node_position.x, node_position.z), node_position.z)
	var validation: Dictionary = placement.fit_and_validate(kind, position, sim, terrain, player.global_position, node_id)
	build_preview.position = validation["position"]
	build_preview.rotation.y = placement.yaw
	build_preview.visible = true
	var valid: bool = bool(validation["ok"])
	preview_material.set_shader_parameter("tint", Color(0.2, 1.0, 0.5) if valid else Color(1.0, 0.12, 0.1))
	var reason: String = "" if valid else str(validation["reason"])
	hud.set_crosshair_hint(reason)
	hud.set_build_info(_build_info(kind, "Ready" if valid else reason, building_definitions[kind]["cost"]))

func _connect_belt(kind: String, from_id: int, from_port: String, to_id: int, to_port: String) -> Dictionary:
	return sim.add_belt(kind, from_id, from_port, to_id, to_port, _belt_curve({"id": from_id, "port": from_port}, {"id": to_id, "port": to_port}))

func _set_capture_view(target: Vector3, camera_position: Vector3) -> void:
	player.position = camera_position - player.camera.position
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	var direction: Vector3 = target - camera_position
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	player.camera.rotation.x = player.pitch
	player.camera.fov = 65.0
