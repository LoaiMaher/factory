extends CanvasLayer
class_name FactoryHUD

signal building_selected(building_id: String)
signal panel_closed
signal save_requested
signal load_requested
signal tier_requested(tier_index: int)
signal craft_requested(recipe_id: String)
signal quit_requested
signal hotbar_selected(index: int)
signal hotbar_changed(index: int)

var sim: FactorySim
var building_definitions: Dictionary = BuildingDefs.all()
var recipe_definitions: Dictionary = Recipes.all()
var milestone_definitions: Array[Dictionary] = Progression.milestones()
var tier_definitions: Array[Dictionary] = Progression.tiers()
var root: Control
var info_label: Label
var power_bypass_label: Label
var toast_label: Label
var hint_label: Label
var crosshair_hint: Label
var build_info_label: RichTextLabel
var panel: PanelContainer
var panel_body: VBoxContainer
var build_menu: PanelContainer
var build_grid: GridContainer
var help_panel: PanelContainer
var hotbar: FactoryHotbar
var hotbar_model: HotbarModel
var icon_cache: FactoryIconCache
var icon_machine_models: MachineModels
var icon_visuals: FactoryVisuals
var assignment_target: Dictionary = {}
var assignment_hint: Label
var entity_status_label: RichTextLabel
var diagnostic_labels: Array[Label] = []
var inventory_open: bool = false
var active_panel: bool = false
var toast_time: float = 0.0
var help_elapsed: float = 0.0
var selected_entity_id: int = -1
var player: FactoryPlayer
var unlocked_tiers: int = 0
var audio_manager: Node

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var crosshair: Label = Label.new()
	crosshair.text = "+"
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.add_theme_font_size_override("font_size", 28)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-20, -24)
	crosshair.size = Vector2(40, 48)
	root.add_child(crosshair)
	crosshair_hint = Label.new()
	crosshair_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair_hint.add_theme_font_size_override("font_size", 15)
	crosshair_hint.add_theme_color_override("font_color", Color("fff3d0"))
	crosshair_hint.add_theme_color_override("font_outline_color", Color("141a17"))
	crosshair_hint.add_theme_constant_override("outline_size", 3)
	crosshair_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair_hint.position = Vector2(-180, 18)
	crosshair_hint.size = Vector2(360, 28)
	root.add_child(crosshair_hint)
	info_label = Label.new()
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_label.position = Vector2(-500, 18)
	info_label.size = Vector2(480, 126)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_label.add_theme_font_size_override("font_size", 14)
	root.add_child(info_label)
	power_bypass_label = Label.new()
	power_bypass_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_bypass_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	power_bypass_label.position = Vector2(-500, 78)
	power_bypass_label.size = Vector2(480, 22)
	power_bypass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	power_bypass_label.add_theme_font_size_override("font_size", 14)
	power_bypass_label.add_theme_color_override("font_color", Color("e8792b"))
	power_bypass_label.text = "DEV: POWER BYPASS"
	root.add_child(power_bypass_label)
	hint_label = Label.new()
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label.position = Vector2(18, 660)
	hint_label.add_theme_font_size_override("font_size", 18)
	root.add_child(hint_label)
	build_info_label = RichTextLabel.new()
	build_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_info_label.bbcode_enabled = true
	build_info_label.fit_content = true
	build_info_label.scroll_active = false
	build_info_label.custom_minimum_size.x = 680.0
	build_info_label.position = Vector2(18, 690)
	build_info_label.add_theme_font_size_override("normal_font_size", 15)
	root.add_child(build_info_label)
	toast_label = Label.new()
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.position = Vector2(20, 840)
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_color", Color("f2d992"))
	root.add_child(toast_label)
	_create_panel()
	_create_build_menu()
	_create_help_panel()
	_create_hotbar()
	_update_hotbar()
	call_deferred("_prepare_hotbar_icons")

func setup(factory_sim: FactorySim, factory_player: FactoryPlayer,
		factory_hotbar: HotbarModel = null, models: MachineModels = null,
		factory_visuals: FactoryVisuals = null) -> void:
	sim = factory_sim
	player = factory_player
	hotbar_model = factory_hotbar if factory_hotbar != null else HotbarModel.new()
	icon_cache = FactoryIconCache.new()
	icon_cache.icons_ready.connect(_on_hotbar_icons_ready)
	icon_machine_models = models
	icon_visuals = factory_visuals

func _input(event: InputEvent) -> void:
	if audio_manager == null or player == null:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and panel_is_open():
		audio_manager.call("play_one_shot", "ui_click", player.global_position)

func _process(delta: float) -> void:
	toast_time = maxf(0.0, toast_time - delta)
	if toast_time <= 0.0:
		toast_label.text = ""
	if sim != null:
		var totals: Vector2 = sim.power.totals_near(player.global_position if player != null else Vector3.ZERO)
		var milestone_status: String = "SHIPYARD COMPLETE"
		var requirement_status: String = ""
		if sim.spire_stage < milestone_definitions.size():
			var milestone: Dictionary = milestone_definitions[sim.spire_stage]
			var stage_progress: float = sim.spire_progress[sim.spire_stage]
			milestone_status = "%s  %d%%" % [milestone["name"], roundi(stage_progress / float(milestone["duration"]) * 100.0)]
			var spire: FactoryEntity = null
			for entity: FactoryEntity in sim.entities.values():
				if entity.kind == "spire":
					spire = entity
					break
			var rates: Array[String] = []
			for item_id: String in milestone["requirements"]:
				var current_rate: float = spire.rate(item_id, sim.time) if spire != null else 0.0
				rates.append("%s %.1f/%.1f" % [Items.item_name(item_id), current_rate, float(milestone["requirements"][item_id])])
			requirement_status = " · ".join(rates)
		info_label.text = "Power %0.0f / %0.0f MW\nTIER %d  ·  %s\n%s" % [totals.y, totals.x, unlocked_tiers, milestone_status, requirement_status]
		info_label.add_theme_color_override("font_color", Color("e35c4e") if totals.y > totals.x else Color("d4ddd1"))
		power_bypass_label.visible = sim.power.bypass
		if selected_entity_id >= 0 and sim.entities.has(selected_entity_id) and entity_status_label != null:
			var entity: FactoryEntity = sim.entities[selected_entity_id]
			entity_status_label.text = _status_markup("%s  ·  %s" % [entity.kind.replace("_", " ").capitalize(), entity.status])
			var lines: Array[String] = sim.diagnostics(selected_entity_id)
			for index: int in range(mini(lines.size(), diagnostic_labels.size())):
				diagnostic_labels[index].text = lines[index]
	if help_panel.visible:
		help_elapsed += delta
		if help_elapsed >= 20.0:
			help_panel.visible = false
			help_elapsed = 0.0
	if hotbar != null:
		hotbar.set_interactive(active_panel or build_menu.visible)
		_update_hotbar()

func show_toast(message: String, duration: float = 4.0) -> void:
	toast_label.text = message
	toast_time = duration

func set_build_info(text_value: String) -> void:
	build_info_label.text = text_value

func set_crosshair_hint(text_value: String) -> void:
	crosshair_hint.text = text_value

func open_entity(entity_id: int) -> void:
	if sim == null or not sim.entities.has(entity_id):
		return
	selected_entity_id = entity_id
	var entity: FactoryEntity = sim.entities[entity_id]
	_set_panel("%s diagnostics" % entity.kind.replace("_", " ").capitalize())
	entity_status_label = RichTextLabel.new()
	entity_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entity_status_label.bbcode_enabled = true
	entity_status_label.fit_content = true
	entity_status_label.custom_minimum_size.y = 30.0
	entity_status_label.add_theme_font_size_override("normal_font_size", 18)
	entity_status_label.text = _status_markup("%s  ·  %s" % [entity.kind.replace("_", " ").capitalize(), entity.status])
	panel_body.add_child(entity_status_label)
	if entity.kind in ["smelter", "constructor", "assembler"]:
		var recipe_select: OptionButton = OptionButton.new()
		recipe_select.add_item("Choose recipe")
		var recipe_names: Array[String] = Recipes.for_machine(entity.kind)
		for recipe_id: String in recipe_names:
			recipe_select.add_item(recipe_id.replace("_", " ").capitalize())
			if recipe_id == entity.recipe_id:
				recipe_select.select(recipe_select.item_count - 1)
		recipe_select.item_selected.connect(_on_recipe_selected.bind(recipe_names))
		panel_body.add_child(recipe_select)
		for line: String in sim.diagnostics(entity_id):
			var diagnostic: Label = _label(line, 15)
			diagnostic_labels.append(diagnostic)
			panel_body.add_child(diagnostic)
		var take: Button = Button.new()
		take.text = "Take output"
		take.pressed.connect(_take_output)
		panel_body.add_child(take)
		var insert: Button = Button.new()
		insert.text = "Insert from inventory"
		insert.pressed.connect(_insert_inventory)
		panel_body.add_child(insert)
		panel_body.add_child(_label(_buffer_summary(entity), 15))
	elif entity.kind == "storage":
		panel_body.add_child(_label(_buffer_summary(entity), 15))
		var take_all: Button = Button.new()
		take_all.text = "Take all"
		take_all.pressed.connect(_take_storage)
		panel_body.add_child(take_all)
	elif entity.kind == "spire":
		_add_spire_panel(entity)
	else:
		panel_body.add_child(_label(_buffer_summary(entity), 15))
	var close: Button = Button.new()
	close.text = "Close  [Esc]"
	close.pressed.connect(close_panel)
	panel_body.add_child(close)
	active_panel = true
	player.set_panel_open(true)
	panel.visible = true

func open_inventory() -> void:
	inventory_open = true
	selected_entity_id = -1
	_set_panel("Inventory & hand crafting")
	panel_body.add_child(_label("Starter cargo and delivered items", 15))
	assignment_hint = _label("Hover an item, press 1–0 to assign · Right-click a slot to clear", 13)
	panel_body.add_child(assignment_hint)
	var items: Array[String] = []
	for item_id: String in Items.all():
		items.append(item_id)
	items.sort_custom(func(first: String, second: String) -> bool:
		return Items.item_name(first) < Items.item_name(second))
	for item_id: String in items:
		var item_button: Button = Button.new()
		item_button.text = "%s  ×  %d" % [Items.item_name(item_id), int(player.inventory.get(item_id, 0))]
		item_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_button.mouse_entered.connect(_set_assignment_target.bind("item", item_id))
		item_button.mouse_exited.connect(_clear_assignment_target.bind("item", item_id))
		panel_body.add_child(item_button)
	for recipe_id: String in recipe_definitions:
		var recipe_button: Button = Button.new()
		recipe_button.text = "Craft %s" % recipe_id.replace("_", " ")
		recipe_button.pressed.connect(_request_craft.bind(recipe_id))
		panel_body.add_child(recipe_button)
	var close: Button = Button.new()
	close.text = "Close  [Esc]"
	close.pressed.connect(close_panel)
	panel_body.add_child(close)
	active_panel = true
	player.set_panel_open(true)
	panel.visible = true

func open_hub() -> void:
	selected_entity_id = -1
	_set_panel("HUB · Tier unlocks")
	for index: int in range(1, tier_definitions.size()):
		var tier: Dictionary = tier_definitions[index]
		var button: Button = Button.new()
		button.text = "Tier %d · %s  —  %s" % [index, tier["name"], str(tier["cost"])]
		button.disabled = index > unlocked_tiers + 1
		button.pressed.connect(tier_requested.emit.bind(index))
		panel_body.add_child(button)
	var close: Button = Button.new()
	close.text = "Close  [Esc]"
	close.pressed.connect(close_panel)
	panel_body.add_child(close)
	active_panel = true
	player.set_panel_open(true)
	panel.visible = true

func open_pause() -> void:
	selected_entity_id = -1
	_set_panel("Paused")
	for title: String in ["Save", "Load", "Quit"]:
		var button: Button = Button.new()
		button.text = title
		if title == "Save":
			button.pressed.connect(save_requested.emit)
		elif title == "Load":
			button.pressed.connect(load_requested.emit)
		else:
			button.pressed.connect(quit_requested.emit)
		panel_body.add_child(button)
	var close: Button = Button.new()
	close.text = "Resume"
	close.pressed.connect(close_panel)
	panel_body.add_child(close)
	active_panel = true
	player.set_panel_open(true)
	panel.visible = true

func show_build_menu(available: Array[String]) -> void:
	for child: Node in build_grid.get_children():
		child.queue_free()
	for building_id: String in available:
		if not building_definitions.has(building_id):
			continue
		var definition: Dictionary = building_definitions[building_id]
		var button: Button = Button.new()
		var label: String = building_id.replace("_", " ").capitalize()
		if int(definition.get("tier", 0)) > unlocked_tiers:
			label += "\nLOCKED · Tier %d" % int(definition["tier"])
		button.text = "%s\n%s" % [label, _cost_text(definition.get("cost", {}))]
		button.custom_minimum_size = Vector2(145.0, 64.0)
		button.mouse_entered.connect(_set_assignment_target.bind("building", building_id))
		button.mouse_exited.connect(_clear_assignment_target.bind("building", building_id))
		button.pressed.connect(_select_building.bind(building_id))
		build_grid.add_child(button)
	build_menu.visible = true

func close_build_menu() -> void:
	build_menu.visible = false
	assignment_target.clear()

func toggle_help() -> void:
	help_panel.visible = not help_panel.visible
	help_elapsed = 0.0

func close_panel() -> void:
	if not active_panel:
		return
	active_panel = false
	inventory_open = false
	panel.visible = false
	assignment_target.clear()
	player.set_panel_open(false)
	panel_closed.emit()

func panel_is_open() -> bool:
	return active_panel

func refresh_entity_panel() -> void:
	if active_panel and selected_entity_id >= 0:
		open_entity(selected_entity_id)

func has_assignment_target() -> bool:
	return not assignment_target.is_empty()

func assign_hovered_to_slot(index: int) -> bool:
	if hotbar_model == null or assignment_target.is_empty():
		return false
	if not hotbar_model.assign(index, str(assignment_target.get("type", "")),
			str(assignment_target.get("id", ""))):
		return false
	hotbar_changed.emit(index)
	_update_hotbar()
	return true

func refresh_hotbar() -> void:
	_update_hotbar()

func _create_panel() -> void:
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-310.0, -255.0)
	panel.size = Vector2(620.0, 510.0)
	panel.visible = false
	root.add_child(panel)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600.0, 490.0)
	panel.add_child(scroll)
	panel_body = VBoxContainer.new()
	panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_body)

func _create_build_menu() -> void:
	build_menu = PanelContainer.new()
	build_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	build_menu.position = Vector2(220.0, 130.0)
	build_menu.size = Vector2(520.0, 420.0)
	build_menu.visible = false
	root.add_child(build_menu)
	var wrapper: VBoxContainer = VBoxContainer.new()
	build_menu.add_child(wrapper)
	var title: Label = _label("Build menu · click to select · hover and press 1–0 to assign", 18)
	wrapper.add_child(title)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500.0, 360.0)
	wrapper.add_child(scroll)
	build_grid = GridContainer.new()
	build_grid.columns = 3
	scroll.add_child(build_grid)

func _create_help_panel() -> void:
	help_panel = PanelContainer.new()
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.position = Vector2(18.0, 84.0)
	help_panel.custom_minimum_size = Vector2(720.0, 150.0)
	root.add_child(help_panel)
	var guide: VBoxContainer = VBoxContainer.new()
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.add_child(guide)
	guide.add_child(_label("PLANETARY FIELD GUIDE", 19))
	guide.add_child(_label("WASD move · Shift sprint · Space jump · Mouse look\nE interact / mine · B build · R rotate · F dismantle · X dismantle mode\nTab inventory and craft · F5 save · F9 load · H toggle this guide", 15))

func _create_hotbar() -> void:
	hotbar = FactoryHotbar.new()
	hotbar.name = "Hotbar"
	hotbar.configure(hotbar_model, icon_cache)
	hotbar.slot_selected.connect(hotbar_selected.emit)
	hotbar.slot_cleared.connect(_clear_hotbar_slot)
	root.add_child(hotbar)

func _prepare_hotbar_icons() -> void:
	if icon_cache == null or icon_machine_models == null or icon_visuals == null:
		return
	await icon_cache.prepare(self, icon_machine_models, icon_visuals)
	_update_hotbar()

func _on_hotbar_icons_ready() -> void:
	_update_hotbar()

func _update_hotbar() -> void:
	if hotbar != null:
		hotbar.refresh(hotbar_model, player.inventory if player != null else {}, unlocked_tiers)

func _clear_hotbar_slot(index: int) -> void:
	if hotbar_model != null and hotbar_model.clear_slot(index):
		hotbar_changed.emit(index)
		_update_hotbar()

func _set_assignment_target(slot_type: String, id: String) -> void:
	assignment_target = {"type": slot_type, "id": id}
	if assignment_hint != null:
		var item_name: String = Items.item_name(id) if slot_type == "item" else id.replace("_", " ").capitalize()
		assignment_hint.text = "Assign %s: press 1–0 · Right-click a slot to clear" % item_name

func _clear_assignment_target(slot_type: String, id: String) -> void:
	if assignment_target.get("type", "") == slot_type and assignment_target.get("id", "") == id:
		assignment_target.clear()
		if assignment_hint != null:
			assignment_hint.text = "Hover an item, press 1–0 to assign · Right-click a slot to clear"

func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id: String in cost:
		parts.append("%d %s" % [int(cost[item_id]), Items.item_name(item_id)])
	return "Free" if parts.is_empty() else ", ".join(parts)

func _set_panel(title: String) -> void:
	for child: Node in panel_body.get_children():
		child.queue_free()
	assignment_hint = null
	assignment_target.clear()
	entity_status_label = null
	diagnostic_labels.clear()
	var heading: Label = _label(title, 22)
	panel_body.add_child(heading)

func _label(text_value: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _status_markup(text_value: String) -> String:
	var color: Color = Color("64c887")
	if text_value.contains("No power") or text_value.contains("full") or text_value.contains("Starved") or text_value.contains("No "):
		color = Color("e26d59")
	elif text_value.contains("Low") or text_value.contains("power"):
		color = Color("e4b94d")
	return "[color=#%s][b]● %s[/b][/color]" % [color.to_html(false), text_value]

func _buffer_summary(entity: FactoryEntity) -> String:
	var recipe: Dictionary = recipe_definitions.get(entity.recipe_id, {})
	var inputs: Dictionary = recipe.get("inputs", entity.input_buffer)
	var outputs: Dictionary = recipe.get("outputs", entity.output_buffer)
	return "Buffer: %s → %s" % [_format_counts(inputs, entity.input_buffer), _format_counts(outputs, entity.output_buffer)]

func _format_counts(item_types: Dictionary, buffer: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id: String in item_types:
		parts.append("%s ×%d" % [Items.item_name(item_id), int(buffer.get(item_id, 0))])
	return "Empty" if parts.is_empty() else ", ".join(parts)

func _on_recipe_selected(index: int, recipe_names: Array[String]) -> void:
	if index > 0 and selected_entity_id >= 0 and index - 1 < recipe_names.size():
		sim.set_recipe(selected_entity_id, recipe_names[index - 1])
		refresh_entity_panel()

func _take_output() -> void:
	var items: Dictionary = sim.take_output(selected_entity_id)
	for item_id: String in items:
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + int(items[item_id])
	refresh_entity_panel()

func _take_storage() -> void:
	var items: Dictionary = sim.take_storage(selected_entity_id)
	for item_id: String in items:
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + int(items[item_id])
	refresh_entity_panel()

func _insert_inventory() -> void:
	var entity: FactoryEntity = sim.entities[selected_entity_id]
	for item_id: String in player.inventory.keys():
		var amount: int = sim.insert_input(selected_entity_id, str(item_id), int(player.inventory[item_id]))
		player.inventory[item_id] = int(player.inventory[item_id]) - amount
	refresh_entity_panel()

func _add_spire_panel(entity: FactoryEntity) -> void:
	var milestones: Array[Dictionary] = milestone_definitions
	var stage: int = mini(sim.spire_stage, milestones.size() - 1)
	var milestone: Dictionary = milestones[stage]
	panel_body.add_child(_label("Milestone %d · %s" % [stage + 1, milestone["name"]], 19))
	for item_id: String in milestone["requirements"]:
		var target: float = float(milestone["requirements"][item_id])
		var current: float = entity.rate(item_id, sim.time)
		var last_status: String = "OK" if current >= target else "STARVED — never delivered"
		if current < target and entity.last_delivery_time.has(item_id):
			last_status = "STARVED — last item %d s ago" % int(sim.time - float(entity.last_delivery_time[item_id]))
		var line: String = "%s  %.1f / %.1f per min  %s" % [Items.item_name(item_id), current, target, last_status]
		panel_body.add_child(_label(line, 15))
	var duration: float = float(milestone["duration"])
	var progress_value: float = minf(duration, sim.spire_progress[stage])
	panel_body.add_child(_label("Progress  %d%%  (%.0f / %.0f s)" % [roundi(progress_value / duration * 100.0), progress_value, duration], 17))
	var progress_bar: ProgressBar = ProgressBar.new()
	progress_bar.max_value = duration
	progress_bar.value = progress_value
	progress_bar.custom_minimum_size = Vector2(500.0, 20.0)
	panel_body.add_child(progress_bar)

func _select_building(building_id: String) -> void:
	building_selected.emit(building_id)
	close_build_menu()

func _request_craft(recipe_id: String) -> void:
	craft_requested.emit(recipe_id)
