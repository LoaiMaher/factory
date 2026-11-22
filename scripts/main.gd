extends Node3D

const SIM_STEP: float = 0.05
const BELT_BUILDINGS: Array[String] = ["belt_mk1", "belt_mk2"]

var sim: FactorySim = FactorySim.new()
var terrain: FactoryTerrain
var player: FactoryPlayer
var visuals: FactoryVisuals
var herd: BorebackHerd
var hud: FactoryHUD
var build_system: FactoryBuildSystem = FactoryBuildSystem.new()
var save_system: FactorySaveSystem = FactorySaveSystem.new()
var building_definitions: Dictionary = BuildingDefs.all()
var recipe_definitions: Dictionary = Recipes.all()
var tier_definitions: Array[Dictionary] = Progression.tiers()
var milestone_definitions: Array[Dictionary] = Progression.milestones()
var build_preview: MeshInstance3D
var belt_preview_cells: Array[MeshInstance3D] = []
var port_markers: Array[MeshInstance3D] = []
var sim_accumulator: float = 0.0
var autosave_elapsed: float = 0.0
var unlocked_tiers: int = 0
var hand_mine_elapsed: float = 0.0
var spire_entity_id: int = -1
var first_sighting: bool = false
var show_help: bool = true
var mining_node: Dictionary = {}
var aimed_entity_id: int = -1
var aim_time: float = 0.0
var last_spire_stage: int = 0
var dismantle_elapsed: float = 0.0
var dismantle_pending: bool = false
var demo_smelter_id: int = -1

func _ready() -> void:
	FactoryPlayer.configure_input()
	_configure_actions()
	terrain = FactoryTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	player = FactoryPlayer.new()
	player.name = "Player"
	player.position = Vector3(0.0, 1.0, 38.0)
	add_child(player)
	visuals = FactoryVisuals.new()
	visuals.name = "Visuals"
	visuals.setup(sim, terrain)
	add_child(visuals)
	herd = BorebackHerd.new()
	herd.name = "BorebackHerd"
	herd.setup(terrain)
	add_child(herd)
	hud = FactoryHUD.new()
	hud.setup(sim, player)
	add_child(hud)
	hud.building_selected.connect(_select_building)
	hud.panel_closed.connect(_on_panel_closed)
	hud.save_requested.connect(_save_game)
	hud.load_requested.connect(_load_game)
	hud.tier_requested.connect(_buy_tier)
	hud.craft_requested.connect(_hand_craft)
	hud.quit_requested.connect(_quit_game)
	spire_entity_id = sim.add_entity("spire", Vector2i(-3, -20))
	_create_preview()
	if OS.get_cmdline_user_args().has("--demo-factory"):
		_build_demo_factory()
		hud.show_toast("Demo factory loaded · diagnostics and item flow are live.", 8.0)
	else:
		hud.show_toast("Press H for controls · E to interact · B to build.", 6.0)
	visuals.refresh()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-"):
			call_deferred("_capture_screenshot", argument.trim_prefix("--capture-"))
			break

func _physics_process(delta: float) -> void:
	sim_accumulator += delta
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
	_update_preview()
	_update_sightings()
	_update_aim_status(delta)

func _process(delta: float) -> void:
	if not mining_node.is_empty() and Input.is_key_pressed(KEY_E):
		hand_mine_elapsed += delta
		if hand_mine_elapsed >= 0.6:
			var item_id: String = str(mining_node.get("item", "iron_ore"))
			player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + 1
			hand_mine_elapsed -= 0.6
			hud.show_toast("Hand-mined 1 %s." % Items.item_name(item_id), 1.0)
	elif not mining_node.is_empty():
		hand_mine_elapsed = 0.0
		mining_node.clear()
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
			if hud.panel_is_open():
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
			build_system.rotate()
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
		elif key == KEY_0 or key == KEY_Q:
			build_system.choose("")
		elif key >= KEY_1 and key <= KEY_9:
			_select_hotbar(int(key) - int(KEY_1))
	elif event is InputEventMouseButton and event.pressed and not hud.panel_is_open() and not hud.build_menu.visible:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_hotbar(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_build_click()

func _configure_actions() -> void:
	var interact_event: InputEventKey = InputEventKey.new()
	interact_event.physical_keycode = KEY_E
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		InputMap.action_add_event("interact", interact_event)

func _select_hotbar(index: int) -> void:
	var choices: Array[String] = _available_buildings()
	if index >= 0 and index < choices.size():
		_select_building(choices[index])

func _cycle_hotbar(step: int) -> void:
	var choices: Array[String] = _available_buildings()
	if choices.is_empty():
		return
	var index: int = choices.find(build_system.selected)
	_select_building(choices[posmod(index + step, choices.size())])

func _available_buildings() -> Array[String]:
	var all: Array[String] = []
	for id: String in building_definitions:
		if int(building_definitions[id]["tier"]) <= unlocked_tiers and id not in ["spire"]:
			all.append(id)
	return all

func _building_size(kind: String, rotation: int = 0) -> Vector2i:
	var size: Vector2i = building_definitions.get(kind, {}).get("size", Vector2i.ONE)
	return size if posmod(rotation, 2) == 0 else Vector2i(size.y, size.x)

func _select_building(building_id: String) -> void:
	build_system.choose(building_id)
	if player.panel_open and not hud.panel_is_open():
		player.set_panel_open(false)
	hud.show_toast("Selected %s · R rotates · click places" % building_id.replace("_", " "), 3.0)

func _toggle_build_menu() -> void:
	if hud.build_menu.visible:
		hud.close_build_menu()
		player.set_panel_open(false)
	else:
		hud.show_build_menu(_available_buildings())
		player.set_panel_open(true)

func _aim_hit(max_distance: float = 80.0) -> Dictionary:
	var origin: Vector3 = player.camera.global_position
	var end: Vector3 = origin + -player.camera.global_transform.basis.z * max_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

func _build_click() -> void:
	if build_system.dismantle_mode:
		_dismantle_aimed()
		build_system.dismantle_mode = false
		return
	if build_system.selected.is_empty():
		return
	var hit: Dictionary = _aim_hit()
	if hit.is_empty():
		return
	var cell: Vector2i = terrain.cell_from_world(hit["position"])
	if BELT_BUILDINGS.has(build_system.selected):
		if build_system.belt_start == null:
			build_system.belt_start = _belt_endpoint_cell(hit, true)
			hud.show_toast("Belt start set · click the end cell.")
			return
		var target_entity: FactoryEntity = _entity_from_hit(hit)
		var path: Array[Dictionary]
		if target_entity != null and target_entity.kind.begins_with("belt_"):
			path = build_system.belt_path_to_belt(build_system.belt_start, target_entity.cell, target_entity.rotation)
		else:
			cell = _belt_endpoint_cell(hit, false)
			var end_rotation: int = target_entity.rotation if target_entity != null and cell == sim.back_port_for(target_entity.id) else -1
			path = build_system.belt_path(build_system.belt_start, cell, end_rotation)
		var cost: Dictionary = building_definitions[build_system.selected]["cost"]
		var total: int = path.size()
		if path.is_empty():
			hud.show_toast("No valid belt connection from this point.")
			return
		for path_cell: Dictionary in path:
			if not terrain.is_buildable(path_cell["cell"], build_system.selected, int(path_cell["rotation"])):
				hud.show_toast("Belt route crosses terrain that is too steep.")
				return
		if not _can_afford(cost, total):
			hud.show_toast("Not enough materials for %d belts." % total)
			return
		if build_system.place_path(sim, path, build_system.selected):
			_pay_cost(cost, total)
			build_system.belt_start = null
			hud.show_toast("Placed %d belts." % total)
		else:
			hud.show_toast("Belt path blocked.")
	else:
		_place_building(cell)

func _belt_endpoint_cell(hit: Dictionary, is_start: bool) -> Vector2i:
	var entity: FactoryEntity = _entity_from_hit(hit)
	if entity != null:
		return sim.front_port_for(entity.id) if is_start else sim.back_port_for(entity.id)
	return terrain.cell_from_world(hit["position"])

func _entity_from_hit(hit: Dictionary) -> FactoryEntity:
	var object: Node = hit.get("collider") as Node
	while object != null:
		if object.has_meta("entity_id"):
			var entity_id: int = int(object.get_meta("entity_id"))
			return sim.entities.get(entity_id)
		object = object.get_parent()
	return null

func _place_building(cell: Vector2i) -> void:
	var cost: Dictionary = building_definitions[build_system.selected]["cost"]
	if not _can_afford(cost, 1):
		hud.show_toast("Not enough materials.")
		return
	if not terrain.is_buildable(cell, build_system.selected, build_system.rotation):
		hud.show_toast("That footprint is too steep to build on.")
		return
	var entity_data: Dictionary = {}
	if build_system.selected == "miner_mk1":
		var node: Dictionary = _find_node(cell)
		if node.is_empty():
			hud.show_toast("Place a Miner over a resource node.")
			return
		entity_data["node"] = node
	if build_system.selected == "geo_tap":
		if not terrain.has_vent_in_footprint(cell, build_system.selected, build_system.rotation):
			hud.show_toast("Place a Geo Tap over a thermal vent.")
			return
		entity_data["supply"] = 50.0
	var entity_id: int = sim.add_entity(build_system.selected, cell, build_system.rotation, entity_data)
	if entity_id < 0:
		hud.show_toast("That footprint is blocked.")
		return
	_pay_cost(cost, 1)
	hud.show_toast("Placed %s." % build_system.selected.replace("_", " "))

func _find_node(cell: Vector2i) -> Dictionary:
	var size: Vector2i = _building_size("miner_mk1", build_system.rotation)
	for node: Dictionary in terrain.nodes:
		if bool(node.get("hidden", false)) and not sim.discovered_nodes.get("hidden_iron", false):
			continue
		var node_cell: Vector2i = terrain.cell_from_world(node["position"])
		if node_cell.x >= cell.x and node_cell.x < cell.x + size.x and node_cell.y >= cell.y and node_cell.y < cell.y + size.y:
			return {"item": node["item"], "rate": node["rate"], "purity": node["purity"]}
	return {}

func _can_afford(cost: Dictionary, multiplier: int) -> bool:
	for item_id: String in cost:
		if int(player.inventory.get(item_id, 0)) < int(cost[item_id]) * multiplier:
			return false
	return true

func _pay_cost(cost: Dictionary, multiplier: int) -> void:
	for item_id: String in cost:
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) - int(cost[item_id]) * multiplier

func _update_preview() -> void:
	if build_preview == null:
		return
	if build_system.selected.is_empty() or hud.panel_is_open() or hud.build_menu.visible:
		build_preview.visible = false
		_hide_belt_previews()
		_set_port_markers_visible(false)
		hud.set_build_info("")
		return
	var hit: Dictionary = _aim_hit()
	if hit.is_empty():
		build_preview.visible = false
		_hide_belt_previews()
		_set_port_markers_visible(false)
		hud.set_build_info("")
		return
	if BELT_BUILDINGS.has(build_system.selected):
		build_preview.visible = false
		_set_port_markers_visible(false)
		_update_belt_preview(hit)
		return
	_hide_belt_previews()
	build_preview.visible = true
	var cell: Vector2i = terrain.cell_from_world(hit["position"])
	var size: Vector2i = _building_size(build_system.selected, build_system.rotation)
	build_preview.position = terrain.point_for_cell(cell) + Vector3((float(size.x) - 1.0), 0.12, float(size.y) - 1.0)
	build_preview.position.y = terrain.footprint_height(cell, build_system.selected, build_system.rotation) + 0.12
	build_preview.scale = Vector3(float(size.x) * 2.0, 0.15, float(size.y) * 2.0)
	var valid: bool = sim.can_place(build_system.selected, cell, build_system.rotation) and terrain.is_buildable(cell, build_system.selected, build_system.rotation)
	if build_system.selected == "miner_mk1":
		valid = valid and not _find_node(cell).is_empty()
	elif build_system.selected == "geo_tap":
		valid = valid and terrain.has_vent_in_footprint(cell, build_system.selected, build_system.rotation)
	valid = valid and _can_afford(building_definitions[build_system.selected]["cost"], 1)
	var material: StandardMaterial3D = build_preview.material_override as StandardMaterial3D
	material.albedo_color = Color(0.25, 0.9, 0.5, 0.36) if valid else Color(0.95, 0.2, 0.18, 0.4)
	_update_port_markers(cell)
	hud.set_build_info("%s · cost %s" % [build_system.selected.replace("_", " "), str(building_definitions[build_system.selected]["cost"])])

func _update_belt_preview(hit: Dictionary) -> void:
	var is_start: bool = build_system.belt_start == null
	var target_entity: FactoryEntity = _entity_from_hit(hit)
	var path: Array[Dictionary]
	if is_start:
		var start_cell: Vector2i = _belt_endpoint_cell(hit, true)
		path = build_system.belt_path(start_cell, start_cell)
	elif target_entity != null and target_entity.kind.begins_with("belt_"):
		path = build_system.belt_path_to_belt(build_system.belt_start, target_entity.cell, target_entity.rotation)
	else:
		var end_cell: Vector2i = _belt_endpoint_cell(hit, false)
		var end_rotation: int = target_entity.rotation if target_entity != null and end_cell == sim.back_port_for(target_entity.id) else -1
		path = build_system.belt_path(build_system.belt_start, end_cell, end_rotation)
	var kind: String = build_system.selected
	var cost: Dictionary = building_definitions[kind]["cost"]
	var valid: bool = _can_afford(cost, path.size())
	for point: Dictionary in path:
		var path_cell: Vector2i = point["cell"]
		var path_rotation: int = int(point["rotation"])
		if not sim.can_place(kind, path_cell, path_rotation) or not terrain.is_buildable(path_cell, kind, path_rotation):
			valid = false
	for index: int in range(path.size()):
		while belt_preview_cells.size() <= index:
			belt_preview_cells.append(_new_preview_cell())
		var ghost: MeshInstance3D = belt_preview_cells[index]
		var point: Dictionary = path[index]
		var cell: Vector2i = point["cell"]
		ghost.visible = true
		ghost.position = terrain.point_for_cell(cell) + Vector3(0.0, 0.12, 0.0)
		ghost.scale = Vector3(2.0, 0.15, 2.0)
		ghost.rotation.y = float(point["rotation"]) * PI / 2.0
		var material: StandardMaterial3D = ghost.material_override as StandardMaterial3D
		material.albedo_color = Color(0.25, 0.9, 0.5, 0.36) if valid else Color(0.95, 0.2, 0.18, 0.4)
	for index: int in range(path.size(), belt_preview_cells.size()):
		belt_preview_cells[index].visible = false
	hud.set_build_info("Belt route · %d cells · %s × %d" % [path.size(), str(cost), path.size()])

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
	for ghost: MeshInstance3D in belt_preview_cells:
		ghost.visible = false

func _update_port_markers(cell: Vector2i) -> void:
	var ports: Dictionary = sim.port_cells(build_system.selected, cell, build_system.rotation)
	var input_ports: Array[Vector2i] = ports["input"]
	var output_ports: Array[Vector2i] = ports["output"]
	for index: int in range(port_markers.size()):
		var marker: MeshInstance3D = port_markers[index]
		marker.visible = index < output_ports.size() + input_ports.size()
		if not marker.visible:
			continue
		var port_cell: Vector2i = output_ports[index] if index < output_ports.size() else input_ports[index - output_ports.size()]
		marker.position = terrain.point_for_cell(port_cell) + Vector3(0.0, 0.35, 0.0)

func _set_port_markers_visible(visible: bool) -> void:
	for marker: MeshInstance3D in port_markers:
		marker.visible = visible

func _create_preview() -> void:
	if DisplayServer.get_name() == "headless":
		return
	build_preview = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE
	build_preview.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	build_preview.material_override = material
	build_preview.visible = false
	add_child(build_preview)
	for color: Color in [Color("eb8c43"), Color("eb8c43"), Color("eb8c43"), Color("54a9d2"), Color("54a9d2"), Color("54a9d2")]:
		var marker: MeshInstance3D = MeshInstance3D.new()
		var marker_mesh: BoxMesh = BoxMesh.new()
		marker_mesh.size = Vector3(0.5, 0.24, 0.5)
		marker.mesh = marker_mesh
		marker.material_override = _preview_material(color)
		marker.visible = false
		add_child(marker)
		port_markers.append(marker)

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
			if object.has_meta("resource_node"):
				var node: Dictionary = object.get_meta("resource_node")
				mining_node = node
				hand_mine_elapsed = 0.0
				hud.show_toast("Hold E to mine %s" % Items.item_name(str(node["item"])), 4.0)
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
	var entity: FactoryEntity = sim.remove_entity(entity_id)
	for item_id: String in entity.cost:
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + int(entity.cost[item_id])
	for item_id: String in entity.input_buffer:
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + int(entity.input_buffer[item_id])
	for item_id: String in entity.output_buffer:
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + int(entity.output_buffer[item_id])
	for item: Dictionary in entity.belt_items:
		var item_id: String = str(item["item"])
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + 1
	hud.show_toast("Dismantled · materials and buffers refunded.")

func _save_game() -> void:
	if save_system.save_game(sim, player, unlocked_tiers):
		hud.show_toast("Saved to user://save.json")
	else:
		hud.show_toast("Save failed.")

func _load_game() -> void:
	var loaded: Dictionary = save_system.load_game(sim, player)
	if loaded.is_empty():
		hud.show_toast("No compatible save found.")
		return
	unlocked_tiers = int(loaded["unlocked_tiers"])
	hud.unlocked_tiers = unlocked_tiers
	hud._update_hotbar()
	last_spire_stage = sim.spire_stage
	for entity: FactoryEntity in sim.entities.values():
		if entity.kind == "spire":
			spire_entity_id = entity.id
			break
	visuals.refresh()
	_reveal_discovered_nodes()
	hud.show_toast("Factory loaded.")

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

func _build_demo_factory() -> void:
	var node: Dictionary = _find_node(Vector2i(-9, -2))
	var miner: int = sim.add_entity("miner_mk1", Vector2i(-9, -2), 0, {"node": node})
	sim.add_entity("belt_mk1", Vector2i(-9, 0), 0)
	sim.add_entity("belt_mk1", Vector2i(-9, 1), 0)
	demo_smelter_id = sim.add_entity("smelter", Vector2i(-9, 2), 0, {"recipe": "iron_ingot"})
	sim.add_entity("belt_mk1", Vector2i(-9, 4), 0)
	sim.add_entity("belt_mk1", Vector2i(-9, 5), 0)
	var constructor: int = sim.add_entity("constructor", Vector2i(-9, 6), 0, {"recipe": "iron_plate"})
	sim.add_entity("belt_mk1", Vector2i(-9, 9), 0)
	var storage: int = sim.add_entity("storage", Vector2i(-9, 10), 0)
	var pole: int = sim.add_entity("power_pole", Vector2i(-26, 2))
	sim.add_entity("power_pole", Vector2i(-16, 3))
	sim.add_entity("power_pole", Vector2i(-10, 3))
	sim.add_entity("geo_tap", Vector2i(-28, 2))
	if miner >= 0 and demo_smelter_id >= 0 and constructor >= 0 and storage >= 0 and pole >= 0:
		hud.show_toast("Demo line: Miner → Smelter → Constructor → Storage", 5.0)
		player.inventory["iron_plate"] = 500
		player.inventory["concrete"] = 100

func _capture_screenshot(mode: String) -> void:
	if hud.help_panel.visible:
		hud.toggle_help()
	if mode == "line" or mode == "panel" or mode == "overview":
		if sim.entities.size() <= 1:
			_build_demo_factory()
			visuals.refresh()
	if mode == "overview":
		player.position = Vector3(-17.0, terrain.height_at(-17.0, 33.0) + 25.0, 33.0)
		player.velocity = Vector3.ZERO
		player.rotation.y = 0.0
		player.pitch = -PI / 4.0
		player.camera.rotation.x = player.pitch
		player.set_physics_process(false)
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
	else:
		await get_tree().create_timer(1.5).timeout
	await get_tree().process_frame
	var filename: String = "/home/ubuntu/specs/shots/v2/%s.png" % mode
	var error: Error = get_viewport().get_texture().get_image().save_png(filename)
	print("SCREENSHOT: %s (%s)" % [filename, error_string(error)])
