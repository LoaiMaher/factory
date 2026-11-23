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
signal creative_toggle_requested
signal creative_item_requested(item_id: String)
signal world_item_collected(item_id: String, quantity: int)
signal graphics_settings_apply_requested

var sim: FactorySim
var building_definitions: Dictionary = BuildingDefs.all()
var recipe_definitions: Dictionary = Recipes.all()
var milestone_definitions: Array[Dictionary] = Progression.milestones()
var tier_definitions: Array[Dictionary] = Progression.tiers()
var root: Control
var info_label: Label
var power_bypass_label: Label
var creative_mode_label: Label
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
var creative_mode_active: bool = false
var graphics_settings_open: bool = false
var graphics_settings_ref: FrontierGraphicsSettings
var graphics_setting_controls: Dictionary = {}
var loading_graphics_settings: bool = false
var storage_open: bool = false
var inventory_category_filter: String = "all"
var inventory_grid: FactoryInventoryPanel
var storage_grid: FactoryInventoryPanel
var cursor_stack: Dictionary = {}
var cursor_stack_panel: PanelContainer
var cursor_stack_icon: TextureRect
var cursor_stack_count: Label
var cursor_origin_type: String = ""
var cursor_origin_slot: int = -1
var cursor_origin_entity: int = -1
var cursor_origin_item: String = ""

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.resized.connect(_center_panel)
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
	creative_mode_label = Label.new()
	creative_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	creative_mode_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	creative_mode_label.position = Vector2(-690, 78)
	creative_mode_label.size = Vector2(170, 22)
	creative_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	creative_mode_label.add_theme_font_size_override("font_size", 14)
	creative_mode_label.add_theme_color_override("font_color", Color("e8792b"))
	creative_mode_label.text = "CREATIVE"
	creative_mode_label.visible = false
	root.add_child(creative_mode_label)
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
	_create_cursor_stack_visual()
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
		creative_mode_label.visible = creative_mode_active
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
	_update_cursor_stack_visual()

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
	if entity.kind == "storage":
		_open_storage_panel(entity)
		return
	storage_open = false
	inventory_open = false
	_set_inventory_panel_size(false)
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
		var recipe_select: OptionButton = create_recipe_selector(entity)
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
	storage_open = false
	selected_entity_id = -1
	_set_inventory_panel_size(true)
	_set_panel("Inventory & hand crafting")
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 24)
	panel_body.add_child(content)
	var inventory_column := VBoxContainer.new()
	inventory_column.custom_minimum_size.x = 548.0
	content.add_child(inventory_column)
	var toolbar := HBoxContainer.new()
	inventory_column.add_child(toolbar)
	var creative_toggle := Button.new()
	creative_toggle.text = "Return to Survival" if creative_mode_active else "Switch to Creative"
	creative_toggle.pressed.connect(creative_toggle_requested.emit)
	toolbar.add_child(creative_toggle)
	var sort_button := Button.new()
	sort_button.text = "Sort"
	sort_button.pressed.connect(_sort_inventory)
	toolbar.add_child(sort_button)
	assignment_hint = _label("Hover an item, press 1–0 to assign · Right-click a slot to clear", 13)
	inventory_column.add_child(assignment_hint)
	var categories := HBoxContainer.new()
	inventory_column.add_child(categories)
	var category_ids: Array[String] = ["all", "raw", "processed", "component", "special"]
	var category_labels: Array[String] = ["All", "Raw", "Processed", "Components", "Special"]
	for category_index: int in range(category_ids.size()):
		var category_button := Button.new()
		category_button.text = category_labels[category_index]
		category_button.pressed.connect(_set_inventory_category.bind(category_ids[category_index]))
		categories.add_child(category_button)
	inventory_grid = FactoryInventoryPanel.new()
	inventory_grid.slot_input.connect(_on_player_slot_input)
	inventory_grid.slot_hovered.connect(_on_inventory_slot_hovered)
	inventory_column.add_child(inventory_grid)
	inventory_grid.configure(player.inventory, icon_cache, inventory_category_filter)
	var craft_column := VBoxContainer.new()
	craft_column.custom_minimum_size.x = 440.0
	content.add_child(craft_column)
	craft_column.add_child(_label("Hand crafting", 19))
	var items: Array[String] = []
	for item_id: String in Items.all():
		items.append(item_id)
	items.sort()
	if creative_mode_active:
		craft_column.add_child(_label("Creative items · click for one full stack", 14))
	for item_id: String in items:
		if creative_mode_active:
			var item_button := Button.new()
			item_button.text = Items.item_name(item_id)
			item_button.icon = icon_cache.get_icon("item", item_id) if icon_cache != null else null
			item_button.pressed.connect(creative_item_requested.emit.bind(item_id))
			craft_column.add_child(item_button)
	for recipe_id: String in recipe_definitions:
		var recipe: Dictionary = recipe_definitions[recipe_id]
		var output_id: String = str(recipe["outputs"].keys()[0])
		var output_count: int = int(recipe["outputs"][output_id])
		var recipe_button := Button.new()
		recipe_button.text = "Craft %s × %d" % [Items.item_name(output_id), output_count]
		recipe_button.icon = icon_cache.get_icon("item", output_id) if icon_cache != null else null
		recipe_button.tooltip_text = "%s → %s" % [str(recipe["inputs"]), Items.description(output_id)]
		recipe_button.pressed.connect(_request_craft.bind(recipe_id))
		craft_column.add_child(recipe_button)
	var close := Button.new()
	close.text = "Close  [Tab / Esc]"
	close.pressed.connect(close_panel)
	panel_body.add_child(close)
	active_panel = true
	player.set_panel_open(true)
	panel.visible = true

func _set_inventory_category(category: String) -> void:
	inventory_category_filter = category
	if inventory_grid != null:
		inventory_grid.configure(player.inventory, icon_cache, inventory_category_filter)

func _sort_inventory() -> void:
	player.inventory.sort()
	if inventory_grid != null:
		inventory_grid.configure(player.inventory, icon_cache, inventory_category_filter)
	refresh_hotbar()

func _on_inventory_slot_hovered(slot_index: int, entered: bool) -> void:
	if inventory_grid == null or slot_index >= player.inventory.slots.size():
		return
	var item_id: String = str(player.inventory.slots[slot_index].get("item_id", ""))
	if entered and not item_id.is_empty():
		_set_assignment_target("item", item_id)
	else:
		_clear_assignment_target("item", item_id)

func _on_player_slot_input(slot_index: int, button_index: int, shift_pressed: bool) -> void:
	if slot_index >= player.inventory.slots.size():
		return
	var slot: Dictionary = player.inventory.slots[slot_index]
	var item_id: String = str(slot.get("item_id", ""))
	var quantity: int = int(slot.get("count", 0))
	if shift_pressed and storage_open and not item_id.is_empty():
		var moved: int = sim.insert_storage_item(selected_entity_id, item_id, quantity)
		player.inventory.take_slot(slot_index, moved)
		_refresh_open_inventory()
		return
	if slot_index >= player.inventory.capacity and not cursor_stack.is_empty():
		return
	if button_index == MOUSE_BUTTON_RIGHT:
		if cursor_stack.is_empty():
			cursor_stack = player.inventory.split(slot_index)
			_set_cursor_origin("player", slot_index, -1, item_id)
		else:
			_place_one_in_player_slot(slot_index)
	else:
		if cursor_stack.is_empty():
			if quantity > 0:
				cursor_stack = player.inventory.take_slot(slot_index, quantity)
				_set_cursor_origin("player", slot_index, -1, item_id)
		else:
			var held_item_id: String = str(cursor_stack.get("item_id", ""))
			var held_count: int = int(cursor_stack.get("count", 0))
			cursor_stack = player.inventory.place_into(slot_index, cursor_stack)
			var moved_count: int = held_count
			if not cursor_stack.is_empty() and str(cursor_stack.get("item_id", "")) == held_item_id:
				moved_count -= int(cursor_stack.get("count", 0))
			if cursor_origin_type == "storage" and moved_count > 0:
				world_item_collected.emit(held_item_id, moved_count)
			if not cursor_stack.is_empty():
				if str(cursor_stack.get("item_id", "")) != held_item_id:
					_set_cursor_origin("player", slot_index, -1,
						str(cursor_stack.get("item_id", "")))
			else:
				_clear_cursor_origin()
	_refresh_open_inventory()
	refresh_hotbar()

func _place_one_in_player_slot(slot_index: int) -> void:
	if cursor_stack.is_empty():
		return
	var item_id: String = str(cursor_stack["item_id"])
	var slot: Dictionary = player.inventory.slots[slot_index]
	if not slot.is_empty() and str(slot.get("item_id", "")) != item_id:
		return
	var remainder: Dictionary = player.inventory.place_into(
		slot_index, {"item_id": item_id, "count": 1})
	if remainder.is_empty():
		cursor_stack["count"] = int(cursor_stack["count"]) - 1
		if cursor_origin_type == "storage":
			world_item_collected.emit(item_id, 1)
		if int(cursor_stack["count"]) <= 0:
			cursor_stack.clear()
			_clear_cursor_origin()

func _refresh_open_inventory() -> void:
	if inventory_grid != null and is_instance_valid(inventory_grid):
		inventory_grid.configure(player.inventory, icon_cache, inventory_category_filter)
	if storage_open:
		_refresh_storage_grid()

func _set_inventory_panel_size(wide: bool) -> void:
	if panel == null:
		return
	var scroll: ScrollContainer = panel.get_child(0) as ScrollContainer
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	if wide:
		panel.size = Vector2(1130.0, 700.0)
		if scroll != null:
			scroll.custom_minimum_size = Vector2(1110.0, 680.0)
	else:
		panel.size = Vector2(620.0, 510.0)
		if scroll != null:
			scroll.custom_minimum_size = Vector2(600.0, 490.0)
	_center_panel()

func _center_panel() -> void:
	if panel != null and root != null:
		panel.position = (root.size - panel.size) * 0.5

func _open_storage_panel(entity: FactoryEntity) -> void:
	storage_open = true
	inventory_open = false
	_set_inventory_panel_size(true)
	_set_panel("%s · transfer" % entity.kind.capitalize())
	panel_body.add_child(_label("Shift-click to transfer · Take all moves only what fits", 15))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	panel_body.add_child(columns)
	var player_column := VBoxContainer.new()
	player_column.add_child(_label("Player inventory", 18))
	inventory_grid = FactoryInventoryPanel.new()
	inventory_grid.slot_input.connect(_on_player_slot_input)
	inventory_grid.slot_hovered.connect(_on_inventory_slot_hovered)
	player_column.add_child(inventory_grid)
	inventory_grid.configure(player.inventory, icon_cache)
	columns.add_child(player_column)
	var storage_column := VBoxContainer.new()
	storage_column.add_child(_label("Storage", 18))
	storage_grid = FactoryInventoryPanel.new()
	storage_grid.slot_input.connect(_on_storage_slot_input)
	storage_column.add_child(storage_grid)
	_refresh_storage_grid()
	var take_all := Button.new()
	take_all.text = "Take all that fits"
	take_all.pressed.connect(_take_storage)
	storage_column.add_child(take_all)
	columns.add_child(storage_column)
	var close := Button.new()
	close.text = "Close  [Tab / Esc]"
	close.pressed.connect(close_panel)
	panel_body.add_child(close)
	active_panel = true
	player.set_panel_open(true)
	panel.visible = true

func _refresh_storage_grid() -> void:
	if not storage_open or storage_grid == null or not is_instance_valid(storage_grid) \
			or not sim.entities.has(selected_entity_id):
		return
	var storage: FactoryEntity = sim.entities[selected_entity_id]
	storage_grid.configure(FrontierInventory.from_totals(storage.input_buffer), icon_cache)

func _on_storage_slot_input(slot_index: int, button_index: int, shift_pressed: bool) -> void:
	if not sim.entities.has(selected_entity_id):
		return
	var storage: FactoryEntity = sim.entities[selected_entity_id]
	var storage_inventory: FrontierInventory = FrontierInventory.from_totals(storage.input_buffer)
	if slot_index < 0 or slot_index >= storage_inventory.capacity:
		return
	var slot: Dictionary = storage_inventory.slots[slot_index]
	var item_id: String = str(slot.get("item_id", ""))
	var quantity: int = int(slot.get("count", 0))
	if shift_pressed:
		if item_id.is_empty() or quantity <= 0:
			return
		var transfer_count: int = player.inventory.fit_count(item_id, quantity)
		if transfer_count > 0:
			var moved: int = sim.take_storage_item(selected_entity_id, item_id, transfer_count)
			player.inventory.add(item_id, moved)
			world_item_collected.emit(item_id, moved)
	elif cursor_stack.is_empty():
		if item_id.is_empty() or quantity <= 0:
			return
		var amount: int = ceili(float(quantity) / 2.0) if button_index == MOUSE_BUTTON_RIGHT \
			else mini(quantity, Items.stack_size(item_id))
		var moved: int = sim.take_storage_item(selected_entity_id, item_id, amount)
		if moved > 0:
			cursor_stack = {"item_id": item_id, "count": moved}
			_set_cursor_origin("storage", slot_index, selected_entity_id, item_id)
	else:
		var held_item_id: String = str(cursor_stack.get("item_id", ""))
		var held_count: int = int(cursor_stack.get("count", 0))
		if button_index == MOUSE_BUTTON_RIGHT \
				and not item_id.is_empty() and item_id != held_item_id:
			return
		var next_inventory := FrontierInventory.new()
		next_inventory.from_data(storage_inventory.to_data())
		var place_stack: Dictionary = {"item_id": held_item_id, "count": held_count}
		if button_index == MOUSE_BUTTON_RIGHT:
			place_stack["count"] = 1
		var remainder: Dictionary = next_inventory.place_into(slot_index, place_stack)
		if button_index == MOUSE_BUTTON_RIGHT and not remainder.is_empty():
			return
		if not _replace_storage_inventory(selected_entity_id, next_inventory.totals()):
			return
		if button_index == MOUSE_BUTTON_RIGHT:
			cursor_stack["count"] = held_count - 1
			if int(cursor_stack["count"]) <= 0:
				cursor_stack.clear()
				_clear_cursor_origin()
		else:
			cursor_stack = remainder
			if cursor_stack.is_empty():
				_clear_cursor_origin()
			elif str(cursor_stack.get("item_id", "")) != held_item_id:
				_set_cursor_origin("storage", slot_index, selected_entity_id,
					str(cursor_stack.get("item_id", "")))
	_refresh_open_inventory()
	refresh_hotbar()

func _replace_storage_inventory(entity_id: int, next_totals: Dictionary) -> bool:
	var next_total: int = 0
	for item_variant: Variant in next_totals:
		next_total += int(next_totals[item_variant])
	if next_total > 1000 or not sim.entities.has(entity_id):
		return false
	var current_totals: Dictionary = sim.entities[entity_id].input_buffer.duplicate(true)
	for item_variant: Variant in current_totals:
		var item_id: String = str(item_variant)
		var remove_count: int = int(current_totals[item_variant]) \
			- int(next_totals.get(item_id, 0))
		if remove_count > 0 \
				and sim.take_storage_item(entity_id, item_id, remove_count) != remove_count:
			return false
	for item_variant: Variant in next_totals:
		var item_id: String = str(item_variant)
		var insert_count: int = int(next_totals[item_variant]) \
			- int(current_totals.get(item_id, 0))
		if insert_count > 0 \
				and sim.insert_storage_item(entity_id, item_id, insert_count) != insert_count:
			return false
	return true

func _set_cursor_origin(source: String, slot_index: int, entity_id: int, item_id: String) -> void:
	cursor_origin_type = source
	cursor_origin_slot = slot_index
	cursor_origin_entity = entity_id
	cursor_origin_item = item_id

func _clear_cursor_origin() -> void:
	cursor_origin_type = ""
	cursor_origin_slot = -1
	cursor_origin_entity = -1
	cursor_origin_item = ""

func _return_cursor_stack() -> void:
	if cursor_stack.is_empty():
		_clear_cursor_origin()
		return
	var item_id: String = str(cursor_stack.get("item_id", ""))
	var quantity: int = int(cursor_stack.get("count", 0))
	if cursor_origin_type == "storage" and sim.entities.has(cursor_origin_entity):
		var remaining: int = quantity - sim.insert_storage_item(cursor_origin_entity, item_id, quantity)
		if remaining > 0:
			player.inventory.add_restored(item_id, remaining)
	elif cursor_origin_type == "player" and cursor_origin_slot >= 0:
		var remainder: Dictionary = player.inventory.place_into(cursor_origin_slot, cursor_stack)
		if not remainder.is_empty():
			player.inventory.add_restored(
				str(remainder.get("item_id", item_id)), int(remainder.get("count", 0)))
	else:
		player.inventory.add_restored(item_id, quantity)
	cursor_stack.clear()
	_clear_cursor_origin()
	refresh_hotbar()

func discard_cursor_stack() -> void:
	cursor_stack.clear()
	_clear_cursor_origin()
	_update_cursor_stack_visual()

func open_hub() -> void:
	selected_entity_id = -1
	_set_panel("HUB · Tier unlocks")
	for index: int in range(1, tier_definitions.size()):
		var tier: Dictionary = tier_definitions[index]
		var button: Button = Button.new()
		button.text = "Tier %d · %s  —  %s" % [
			index, tier["name"], "Unlocked" if creative_mode_active else str(tier["cost"])]
		button.disabled = creative_mode_active or index > unlocked_tiers + 1
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

func open_graphics_settings(settings: FrontierGraphicsSettings) -> void:
	graphics_settings_ref = settings
	graphics_settings_open = true
	selected_entity_id = -1
	_set_panel("Graphics settings")
	graphics_setting_controls.clear()
	loading_graphics_settings = true
	_add_graphics_option("Preset", "preset",
		["low", "medium", "high", "ultra", "custom"],
		["Low", "Medium", "High", "Ultra", "Custom"], settings.preset)
	_add_graphics_option("Window mode", "window_mode",
		["windowed", "borderless", "exclusive"],
		["Windowed", "Borderless fullscreen", "Exclusive fullscreen"], settings.window_mode)
	_add_graphics_option("VSync", "vsync", ["on", "off"], ["On", "Off"], "on" if settings.vsync else "off")
	_add_graphics_spin("Max FPS (0 = uncapped)", "max_fps", 0.0, 500.0, 10.0, float(settings.max_fps))
	_add_graphics_spin("Render scale", "render_scale", 0.5, 1.0, 0.05, settings.render_scale)
	_add_graphics_option("Scaling mode", "scaling_mode",
		["bilinear", "fsr1", "fsr2"], ["Bilinear", "FSR 1", "FSR 2"], settings.scaling_mode)
	_add_graphics_option("Antialiasing", "antialiasing",
		["off", "fxaa", "taa", "smaa", "msaa2x", "msaa4x"],
		["Off", "FXAA", "TAA", "SMAA", "MSAA 2×", "MSAA 4×"], settings.antialiasing)
	_add_graphics_spin("Directional shadow atlas", "shadow_atlas_size", 1024.0, 8192.0, 1024.0,
		float(settings.shadow_atlas_size))
	_add_graphics_option("Soft shadow filter", "soft_shadow_quality",
		["very_low", "low", "medium", "high", "ultra"],
		["Very low", "Low", "Medium", "High", "Ultra"], settings.soft_shadow_quality)
	_add_graphics_spin("Shadow distance (m)", "shadow_distance", 60.0, 1100.0, 10.0,
		settings.shadow_distance)
	_add_graphics_spin("Shadow split 1", "shadow_split_1", 0.0, 1.0, 0.01, settings.shadow_split_1)
	_add_graphics_spin("Shadow split 2", "shadow_split_2", 0.0, 1.0, 0.01, settings.shadow_split_2)
	_add_graphics_spin("Shadow split 3", "shadow_split_3", 0.0, 1.0, 0.01, settings.shadow_split_3)
	_add_graphics_check("SSAO", "ssao", settings.ssao)
	_add_graphics_check("SSIL", "ssil", settings.ssil)
	_add_graphics_check("Glow", "glow", settings.glow)
	_add_graphics_check("Volumetric fog", "volumetric_fog", settings.volumetric_fog)
	_add_graphics_spin("Foliage density", "foliage_density", 0.5, 1.25, 0.05,
		settings.foliage_density)
	_add_graphics_spin("Grass radius (m)", "grass_radius", 20.0, 100.0, 1.0, settings.grass_radius)
	_add_graphics_spin("Tree view distance (m)", "tree_view_distance", 100.0, 720.0, 10.0,
		settings.tree_view_distance)
	panel_body.add_child(_label(
		"Grass density/radius update now; tree and scatter density are rebuilt on restart.", 13))
	var buttons: HBoxContainer = HBoxContainer.new()
	var apply_button: Button = Button.new()
	apply_button.text = "Apply"
	apply_button.pressed.connect(_apply_graphics_settings_from_controls)
	buttons.add_child(apply_button)
	var close: Button = Button.new()
	close.text = "Close  [Esc]"
	close.pressed.connect(close_panel)
	buttons.add_child(close)
	panel_body.add_child(buttons)
	loading_graphics_settings = false
	active_panel = true
	player.set_panel_open(true)
	panel.visible = true

func _add_graphics_option(label_text: String, key: String, values: Array[String],
		labels: Array[String], selected_value: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(_graphics_control_label(label_text))
	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index: int in range(values.size()):
		option.add_item(labels[index])
		option.set_item_metadata(index, values[index])
	var selected_index: int = values.find(selected_value)
	option.select(maxi(0, selected_index))
	if key == "preset":
		option.item_selected.connect(_on_graphics_preset_selected)
	else:
		option.item_selected.connect(_mark_graphics_preset_custom)
	row.add_child(option)
	panel_body.add_child(row)
	graphics_setting_controls[key] = option

func _add_graphics_spin(label_text: String, key: String, minimum: float, maximum: float,
		step: float, initial_value: float) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(_graphics_control_label(label_text))
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = initial_value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(_mark_graphics_preset_custom)
	row.add_child(spin)
	panel_body.add_child(row)
	graphics_setting_controls[key] = spin

func _add_graphics_check(label_text: String, key: String, checked: bool) -> void:
	var check: CheckBox = CheckBox.new()
	check.text = label_text
	check.button_pressed = checked
	check.toggled.connect(_mark_graphics_preset_custom)
	panel_body.add_child(check)
	graphics_setting_controls[key] = check

func _graphics_control_label(text_value: String) -> Label:
	var label: Label = _label(text_value, 14)
	label.custom_minimum_size.x = 210.0
	return label

func _on_graphics_preset_selected(index: int) -> void:
	if loading_graphics_settings:
		return
	var option: OptionButton = graphics_setting_controls["preset"] as OptionButton
	var selected_preset: String = str(option.get_item_metadata(index))
	if selected_preset != "custom" and FrontierGraphicsSettings.PRESETS.has(selected_preset):
		loading_graphics_settings = true
		var preset_values: Dictionary = FrontierGraphicsSettings.PRESETS[selected_preset]
		for key: String in preset_values:
			_set_graphics_form_value(key, preset_values[key])
		loading_graphics_settings = false
	else:
		_mark_graphics_preset_custom()

func _set_graphics_form_value(key: String, value: Variant) -> void:
	if not graphics_setting_controls.has(key):
		return
	var control: Control = graphics_setting_controls[key]
	if control is OptionButton:
		var option: OptionButton = control as OptionButton
		for index: int in range(option.item_count):
			if str(option.get_item_metadata(index)) == str(value):
				option.select(index)
				return
	elif control is SpinBox:
		(control as SpinBox).value = float(value)
	elif control is CheckBox:
		(control as CheckBox).button_pressed = bool(value)

func _mark_graphics_preset_custom(_value: Variant = null) -> void:
	if loading_graphics_settings or not graphics_setting_controls.has("preset"):
		return
	var preset_option: OptionButton = graphics_setting_controls["preset"] as OptionButton
	for index: int in range(preset_option.item_count):
		if str(preset_option.get_item_metadata(index)) == "custom":
			preset_option.select(index)
			return

func _apply_graphics_settings_from_controls() -> void:
	var preset_option: OptionButton = graphics_setting_controls["preset"] as OptionButton
	graphics_settings_ref.preset = str(preset_option.get_item_metadata(preset_option.selected))
	graphics_settings_ref.window_mode = _graphics_option_value("window_mode")
	graphics_settings_ref.vsync = _graphics_option_value("vsync") == "on"
	graphics_settings_ref.max_fps = roundi(_graphics_spin_value("max_fps"))
	graphics_settings_ref.render_scale = _graphics_spin_value("render_scale")
	graphics_settings_ref.scaling_mode = _graphics_option_value("scaling_mode")
	graphics_settings_ref.antialiasing = _graphics_option_value("antialiasing")
	graphics_settings_ref.shadow_atlas_size = roundi(_graphics_spin_value("shadow_atlas_size"))
	graphics_settings_ref.soft_shadow_quality = _graphics_option_value("soft_shadow_quality")
	graphics_settings_ref.shadow_distance = _graphics_spin_value("shadow_distance")
	graphics_settings_ref.shadow_split_1 = _graphics_spin_value("shadow_split_1")
	graphics_settings_ref.shadow_split_2 = _graphics_spin_value("shadow_split_2")
	graphics_settings_ref.shadow_split_3 = _graphics_spin_value("shadow_split_3")
	graphics_settings_ref.ssao = (graphics_setting_controls["ssao"] as CheckBox).button_pressed
	graphics_settings_ref.ssil = (graphics_setting_controls["ssil"] as CheckBox).button_pressed
	graphics_settings_ref.glow = (graphics_setting_controls["glow"] as CheckBox).button_pressed
	graphics_settings_ref.volumetric_fog = \
		(graphics_setting_controls["volumetric_fog"] as CheckBox).button_pressed
	graphics_settings_ref.foliage_density = _graphics_spin_value("foliage_density")
	graphics_settings_ref.grass_radius = _graphics_spin_value("grass_radius")
	graphics_settings_ref.tree_view_distance = _graphics_spin_value("tree_view_distance")
	graphics_settings_apply_requested.emit()

func _graphics_option_value(key: String) -> String:
	var option: OptionButton = graphics_setting_controls[key] as OptionButton
	return str(option.get_item_metadata(option.selected))

func _graphics_spin_value(key: String) -> float:
	return (graphics_setting_controls[key] as SpinBox).value

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
		var cost_label: String = "Free" if creative_mode_active else _cost_text(definition.get("cost", {}))
		button.text = "%s\n%s" % [label, cost_label]
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
	_return_cursor_stack()
	active_panel = false
	inventory_open = false
	storage_open = false
	graphics_settings_open = false
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
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = Vector2(620.0, 510.0)
	panel.visible = false
	root.add_child(panel)
	_center_panel()
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
	guide.add_child(_label("WASD move · Shift sprint · Space jump · Mouse look\nE interact / mine · B build · R rotate · F dismantle · X dismantle mode\nTab inventory and craft · F7 creative · F10 graphics · F3 performance\nF5 save · F9 load · H toggle this guide", 15))

func _create_hotbar() -> void:
	hotbar = FactoryHotbar.new()
	hotbar.name = "Hotbar"
	hotbar.configure(hotbar_model, icon_cache)
	hotbar.slot_selected.connect(hotbar_selected.emit)
	hotbar.slot_cleared.connect(_clear_hotbar_slot)
	root.add_child(hotbar)

func _create_cursor_stack_visual() -> void:
	cursor_stack_panel = PanelContainer.new()
	cursor_stack_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_stack_panel.visible = false
	cursor_stack_panel.custom_minimum_size = Vector2(56.0, 48.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171c1d")
	style.border_color = Color("d3a15d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	cursor_stack_panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_stack_panel.add_child(row)
	cursor_stack_icon = TextureRect.new()
	cursor_stack_icon.custom_minimum_size = Vector2(36.0, 36.0)
	cursor_stack_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor_stack_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cursor_stack_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cursor_stack_icon)
	cursor_stack_count = _label("", 13)
	cursor_stack_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	row.add_child(cursor_stack_count)
	root.add_child(cursor_stack_panel)

func _update_cursor_stack_visual() -> void:
	if cursor_stack_panel == null:
		return
	var held: bool = not cursor_stack.is_empty()
	cursor_stack_panel.visible = held and active_panel
	if not held:
		return
	cursor_stack_panel.position = get_viewport().get_mouse_position() + Vector2(14.0, 14.0)
	var item_id: String = str(cursor_stack.get("item_id", ""))
	cursor_stack_icon.texture = icon_cache.get_icon("item", item_id) \
		if icon_cache != null else null
	var quantity: int = int(cursor_stack.get("count", 0))
	cursor_stack_count.text = str(quantity) if quantity > 1 else ""

func _prepare_hotbar_icons() -> void:
	if icon_cache == null or icon_machine_models == null or icon_visuals == null:
		return
	await icon_cache.prepare(self, icon_machine_models, icon_visuals)
	_update_hotbar()

func _on_hotbar_icons_ready() -> void:
	_update_hotbar()

func _update_hotbar() -> void:
	if hotbar != null:
		hotbar.refresh(hotbar_model,
			player.inventory if player != null else FrontierInventory.new(),
			unlocked_tiers, creative_mode_active)

func set_creative_mode(active: bool) -> void:
	creative_mode_active = active
	if creative_mode_label != null:
		creative_mode_label.visible = active
	_update_hotbar()

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

func create_recipe_selector(entity: FactoryEntity) -> OptionButton:
	var recipe_select: OptionButton = OptionButton.new()
	recipe_select.allow_reselect = true
	recipe_select.add_item("Choose recipe")
	var recipe_names: Array[String] = Recipes.for_machine(entity.kind)
	for recipe_id: String in recipe_names:
		recipe_select.add_item(recipe_option_text(entity, recipe_id))
		if recipe_id == entity.recipe_id:
			recipe_select.select(recipe_select.item_count - 1)
	recipe_select.item_selected.connect(_on_recipe_selected.bind(recipe_names))
	return recipe_select

static func recipe_option_text(entity: FactoryEntity, recipe_id: String) -> String:
	var text_value: String = recipe_id.replace("_", " ").capitalize()
	if recipe_id == entity.recipe_id and not bool(entity.extra.get("recipe_locked", false)):
		text_value += " (auto)"
	return text_value

func _on_recipe_selected(index: int, recipe_names: Array[String]) -> void:
	if index > 0 and selected_entity_id >= 0 and index - 1 < recipe_names.size():
		sim.set_recipe(selected_entity_id, recipe_names[index - 1])
		refresh_entity_panel()

func _take_output() -> void:
	if not sim.entities.has(selected_entity_id):
		return
	var items: Dictionary = sim.entities[selected_entity_id].output_buffer.duplicate(true)
	for item_id: String in items:
		var quantity: int = player.inventory.fit_count(item_id, int(items[item_id]))
		var moved: int = sim.take_output_item(selected_entity_id, item_id, quantity)
		if moved > 0:
			player.inventory.add(item_id, moved)
			world_item_collected.emit(item_id, moved)
		if moved < int(items[item_id]):
			show_toast("Inventory full")
	refresh_entity_panel()

func _take_storage() -> void:
	if not sim.entities.has(selected_entity_id) or sim.entities[selected_entity_id].kind != "storage":
		return
	var items: Dictionary = sim.entities[selected_entity_id].input_buffer.duplicate(true)
	for item_id: String in items:
		var quantity: int = player.inventory.fit_count(item_id, int(items[item_id]))
		var moved: int = sim.take_storage_item(selected_entity_id, item_id, quantity)
		if moved > 0:
			player.inventory.add(item_id, moved)
			world_item_collected.emit(item_id, moved)
		if moved < int(items[item_id]):
			show_toast("Some items could not fit")
	_refresh_open_inventory()
	refresh_hotbar()

func _insert_inventory() -> void:
	for item_variant: Variant in player.inventory.totals():
		var item_id: String = str(item_variant)
		var amount: int = sim.insert_input(
			selected_entity_id, item_id, player.inventory.count(item_id))
		player.inventory.remove(item_id, amount)
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
