extends VBoxContainer
class_name FactoryMachinePanel

signal items_collected(item_id: String, quantity: int)
signal inventory_changed
signal toast_requested(message: String)
signal output_slot_requested(slot_index: int, item_id: String, quantity: int,
		button_index: int, shift_pressed: bool)
signal player_slot_input_requested(slot_index: int, button_index: int,
		shift_pressed: bool)

var sim: FactorySim
var player: FactoryPlayer
var icon_cache: FactoryIconCache
var entity_id: int = -1
var miner_mode: bool = false
var creative_mode_active: bool = false
var recipe_ids: Array[String] = []
var recipe_selector: OptionButton
var building_icon: TextureRect
var machine_name: Label
var status_panel: PanelContainer
var status_label: Label
var status_style: StyleBoxFlat
var recipe_input_slots: Array[Dictionary] = []
var recipe_output_slots: Array[Dictionary] = []
var input_cards: Array[Dictionary] = []
var output_slots: Array[Dictionary] = []
var progress_bar: ProgressBar
var take_button: Button
var cycle_label: Label
var production_label: Label
var deposit_label: Label
var power_label: Label
var why_label: Label
var inventory_grid: FactoryInventoryPanel

func configure(factory_sim: FactorySim, factory_player: FactoryPlayer,
		icons: FactoryIconCache, target_entity_id: int) -> bool:
	sim = factory_sim
	player = factory_player
	icon_cache = icons
	entity_id = target_entity_id
	var view: Dictionary = sim.machine_view(entity_id) if sim != null else {}
	if view.is_empty():
		return false
	_build(view)
	refresh()
	return true

func refresh() -> bool:
	if sim == null:
		return false
	var view: Dictionary = sim.machine_view(entity_id)
	if view.is_empty():
		return false
	_update_header(view)
	_update_recipe(view)
	_update_slots(view)
	_update_progress_and_rates(view)
	_update_power_and_diagnostics(view)
	return true

func _build(view: Dictionary) -> void:
	miner_mode = str(view.get("kind", "")) == "miner_mk1"
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(columns)
	var production_column := VBoxContainer.new()
	production_column.custom_minimum_size.x = 500.0
	production_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(production_column)
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 96.0
	production_column.add_child(header)
	building_icon = TextureRect.new()
	building_icon.custom_minimum_size = Vector2(96.0, 96.0)
	building_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	building_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	building_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(building_icon)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(identity)
	machine_name = _label("", 24)
	identity.add_child(machine_name)
	recipe_selector = OptionButton.new()
	recipe_selector.custom_minimum_size.y = 38.0
	recipe_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_selector.get_popup().index_pressed.connect(_on_recipe_selected)
	production_column.add_child(recipe_selector)
	_load_recipe_options(view)

	var recipe_row := HBoxContainer.new()
	recipe_row.custom_minimum_size.y = 62.0
	recipe_row.visible = not miner_mode
	recipe_row.add_theme_constant_override("separation", 6)
	production_column.add_child(recipe_row)
	var recipe_flow := HBoxContainer.new()
	recipe_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_flow.add_theme_constant_override("separation", 6)
	recipe_row.add_child(recipe_flow)
	var input_slot_count: int = int(view.get("input_slot_count", 0))
	var output_slot_count: int = maxi(1, maxi(int(view.get("output_slot_count", 1)),
		(view.get("outputs", []) as Array).size()))
	for _index: int in range(input_slot_count):
		recipe_input_slots.append(_make_rate_slot(recipe_flow))
	var arrow := _label("→", 22)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	recipe_flow.add_child(arrow)
	for _index: int in range(output_slot_count):
		recipe_output_slots.append(_make_rate_slot(recipe_flow))

	status_panel = PanelContainer.new()
	status_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	status_style = StyleBoxFlat.new()
	status_style.set_border_width_all(1)
	status_style.set_corner_radius_all(12)
	status_panel.add_theme_stylebox_override("panel", status_style)
	identity.add_child(status_panel)
	status_label = _label("", 15)
	status_label.add_theme_color_override("font_color", Color("f4f2eb"))
	status_panel.add_child(status_label)

	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 10)
	production_column.add_child(slot_row)
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	input_row.visible = not miner_mode
	slot_row.add_child(input_row)
	for _index: int in range(input_slot_count):
		input_cards.append(_make_input_card(input_row))
	var process_column := VBoxContainer.new()
	process_column.custom_minimum_size.x = 92.0
	if miner_mode:
		process_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	process_column.alignment = BoxContainer.ALIGNMENT_CENTER
	process_column.add_theme_constant_override("separation", 6)
	slot_row.add_child(process_column)
	var process_arrow := _label("→", 24)
	process_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	process_arrow.visible = not miner_mode
	process_column.add_child(process_arrow)
	progress_bar = ProgressBar.new()
	progress_bar.max_value = 100.0
	progress_bar.custom_minimum_size = Vector2(88.0, 14.0)
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	process_column.add_child(progress_bar)
	var output_column := VBoxContainer.new()
	output_column.custom_minimum_size.x = mini(output_slot_count, 2) * 68.0
	output_column.visible = not miner_mode
	slot_row.add_child(output_column)
	var output_heading := _label("Output", 12)
	output_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	output_column.add_child(output_heading)
	var output_slot_row := GridContainer.new()
	output_slot_row.columns = 2
	output_slot_row.add_theme_constant_override("h_separation", 3)
	output_slot_row.add_theme_constant_override("v_separation", 3)
	output_column.add_child(output_slot_row)
	for index: int in range(output_slot_count):
		output_slots.append(_make_output_slot(output_slot_row, index))
	take_button = Button.new()
	take_button.text = "Take"
	take_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_button.visible = not miner_mode
	take_button.pressed.connect(_take_output)
	output_column.add_child(take_button)

	cycle_label = _label("", 13)
	production_column.add_child(cycle_label)
	production_label = _label("", 14)
	production_column.add_child(production_label)
	deposit_label = _label("", 13)
	production_column.add_child(deposit_label)
	power_label = _label("", 13)
	production_column.add_child(power_label)

	if not miner_mode:
		var inventory_column := VBoxContainer.new()
		inventory_column.custom_minimum_size.x = 540.0
		inventory_column.size_flags_horizontal = Control.SIZE_SHRINK_END
		var inventory_heading := _label("Player inventory · Shift-click to insert", 14)
		inventory_grid = FactoryInventoryPanel.new()
		inventory_grid.slot_input.connect(_on_inventory_slot_input)
		columns.add_child(inventory_column)
		inventory_column.add_child(inventory_heading)
		inventory_column.add_child(inventory_grid)
		if player != null:
			inventory_grid.configure(player.inventory, icon_cache)

	why_label = _label("", 12)
	why_label.clip_text = true
	why_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why_label.max_lines_visible = 2
	why_label.custom_minimum_size.y = 34.0
	why_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(why_label)

func _load_recipe_options(view: Dictionary) -> void:
	recipe_selector.clear()
	recipe_selector.add_item("Choose recipe")
	recipe_ids.clear()
	var recipes: Array = view.get("recipes", [])
	for recipe: Dictionary in recipes:
		recipe_ids.append(str(recipe.get("id", "")))
		recipe_selector.add_item(str(recipe.get("label", "")))

func _update_header(view: Dictionary) -> void:
	machine_name.text = str(view.get("name", "Machine"))
	var kind: String = str(view.get("kind", ""))
	building_icon.texture = icon_cache.get_icon("building", kind) \
		if icon_cache != null else null
	status_label.text = str(view.get("display_status", view.get("status", "Idle")))
	var tint: Color = Color("59c98b")
	match str(view.get("state", "idle")):
		"waiting_input", "output_full", "low_power":
			tint = Color("e1b854")
		"no_power":
			tint = Color("e15d51")
		"idle":
			tint = Color("9da6a3")
	status_style.bg_color = tint.darkened(0.65)
	status_style.border_color = tint

func _update_recipe(view: Dictionary) -> void:
	var inputs: Array = view.get("inputs", [])
	var outputs: Array = view.get("outputs", [])
	_update_rate_slots(recipe_input_slots, inputs, "needs_per_min")
	_update_rate_slots(recipe_output_slots, outputs, "per_min")
	var recipe_id: String = str(view.get("recipe_id", ""))
	var selected_index: int = recipe_ids.find(recipe_id) + 1
	if selected_index > 0 and recipe_selector.selected != selected_index:
		recipe_selector.select(selected_index)
	var options: Array = view.get("recipes", [])
	for index: int in range(mini(options.size(), recipe_ids.size())):
		var label: String = str(options[index].get("label", ""))
		if recipe_selector.get_item_text(index + 1) != label:
			recipe_selector.set_item_text(index + 1, label)
	recipe_selector.visible = not recipe_ids.is_empty()

func _update_rate_slots(slots: Array[Dictionary], items: Array, rate_key: String) -> void:
	for index: int in range(slots.size()):
		var slot: Dictionary = slots[index]
		var container: Control = slot["container"]
		var visible: bool = index < items.size()
		container.visible = visible
		if not visible:
			continue
		var item: Dictionary = items[index]
		var item_id: String = str(item.get("item_id", ""))
		var icon: TextureRect = slot["icon"]
		icon.texture = icon_cache.get_icon("item", item_id) if icon_cache != null else null
		icon.tooltip_text = Items.item_name(item_id)
		var rate_label: Label = slot["rate"]
		rate_label.text = "%.0f/min" % float(item.get(rate_key, 0.0))
		rate_label.tooltip_text = Items.item_name(item_id)

func _update_slots(view: Dictionary) -> void:
	var inputs: Array = view.get("inputs", [])
	for index: int in range(input_cards.size()):
		var card: Dictionary = input_cards[index]
		var visible: bool = index < inputs.size()
		(card["container"] as Control).visible = visible
		if not visible:
			continue
		var item: Dictionary = inputs[index]
		var item_id: String = str(item.get("item_id", ""))
		var input_button: Button = card["button"]
		input_button.icon = icon_cache.get_icon("item", item_id) \
			if icon_cache != null else null
		var input_count: int = int(item.get("count", 0))
		var input_maximum: int = int(item.get("maximum", 0))
		input_button.tooltip_text = Items.item_name(item_id)
		(card["count"] as Label).text = str(input_count) if input_count > 0 else ""
		(card["capacity"] as Label).text = "%d / %d" % [
			input_count, input_maximum]
		(card["rate"] as Label).text = "needs %.0f/min\ngetting %.0f/min" % [
			float(item.get("needs_per_min", 0.0)),
			float(item.get("getting_per_min", 0.0))]
		var old_item_id: String = str(card.get("item_id", ""))
		if old_item_id != item_id:
			_style_slot_button(input_button, item_id)
			card["item_id"] = item_id
		input_cards[index] = card
	var outputs: Array = view.get("outputs", [])
	for index: int in range(output_slots.size()):
		var slot: Dictionary = output_slots[index]
		var button: Button = slot["button"]
		var container: Control = slot["container"]
		var visible: bool = index < outputs.size()
		container.visible = visible or index == 0
		var output_item: Dictionary = outputs[index] if visible else {}
		var item_id: String = str(output_item.get("item_id", ""))
		var count: int = int(output_item.get("count", 0))
		var maximum: int = int(output_item.get("maximum", 0))
		slot["item_id"] = item_id
		slot["count"] = count
		button.icon = icon_cache.get_icon("item", item_id) \
			if icon_cache != null and not item_id.is_empty() else null
		(slot["count_label"] as Label).text = str(count) if count > 0 else ""
		(slot["capacity_label"] as Label).text = "%d / %d" % [count, maximum]
		button.tooltip_text = "%s · %d" % [Items.item_name(item_id), count] \
			if not item_id.is_empty() else "No output"
		button.disabled = item_id.is_empty() or count <= 0
		var old_item_id: String = str(slot.get("styled_item_id", ""))
		if old_item_id != item_id:
			_style_slot_button(button, item_id)
			slot["styled_item_id"] = item_id
		output_slots[index] = slot

func _update_progress_and_rates(view: Dictionary) -> void:
	var cycle_seconds: float = float(view.get("cycle_seconds", 0.0))
	var progress: float = float(view.get("progress", 0.0))
	progress_bar.value = progress * 100.0
	cycle_label.text = "Cycle %.1f / %.1f s" % [progress * cycle_seconds, cycle_seconds]
	production_label.text = "Production %.1f / %.1f items/min · %.0f%% efficiency" % [
		float(view.get("current_rate", 0.0)), float(view.get("maximum_rate", 0.0)),
		float(view.get("efficiency", 0.0))]
	var deposit_item: String = str(view.get("deposit_item", ""))
	deposit_label.visible = not deposit_item.is_empty()
	if not deposit_item.is_empty():
		deposit_label.text = "Deposit %s · Purity: %s · %.0f/min" % [
			Items.item_name(deposit_item), str(view.get("deposit_purity", "unknown")),
			float(view.get("deposit_rate", 0.0))]

func _update_power_and_diagnostics(view: Dictionary) -> void:
	var bypassed: bool = bool(view.get("power_bypassed", false))
	if bypassed:
		power_label.text = "Free power (dev bypass) · %.1f MW nominal" % \
			float(view.get("power_need_mw", 0.0))
	else:
		power_label.text = "Draw %.1f / %.1f MW · %s" % [
			float(view.get("power_draw_mw", 0.0)), float(view.get("power_need_mw", 0.0)),
			str(view.get("power_state", ""))]
	why_label.text = "Why: %s" % str(view.get("why", ""))
	why_label.tooltip_text = str(view.get("why", ""))

func _make_rate_slot(parent: HBoxContainer) -> Dictionary:
	var container := VBoxContainer.new()
	container.custom_minimum_size = Vector2(46.0, 62.0)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(32.0, 34.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(icon)
	var rate_label := _label("", 11)
	rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(rate_label)
	parent.add_child(container)
	return {"container": container, "icon": icon, "rate": rate_label}

func _make_input_card(parent: HBoxContainer) -> Dictionary:
	var card := VBoxContainer.new()
	card.custom_minimum_size.x = 112.0
	card.add_theme_constant_override("separation", 1)
	var button := _make_slot_button()
	card.add_child(button)
	var count_label := _make_slot_count_label(button)
	var capacity_label := _label("0 / 0", 11)
	capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(capacity_label)
	var rate_label := _label("", 9)
	rate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rate_label.max_lines_visible = 2
	rate_label.custom_minimum_size.y = 24.0
	card.add_child(rate_label)
	parent.add_child(card)
	return {"container": card, "button": button, "icon": button,
		"count": count_label, "capacity": capacity_label, "rate": rate_label,
		"item_id": ""}

func _make_output_slot(parent: GridContainer, slot_index: int) -> Dictionary:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 1)
	var button := _make_slot_button()
	button.gui_input.connect(_on_output_slot_input.bind(slot_index))
	container.add_child(button)
	var count_label := _make_slot_count_label(button)
	var capacity_label := _label("0 / 0", 11)
	capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(capacity_label)
	parent.add_child(container)
	return {"container": container, "button": button, "count_label": count_label,
		"capacity_label": capacity_label, "item_id": "", "count": 0}

func _make_slot_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(64.0, 64.0)
	button.focus_mode = Control.FOCUS_NONE
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 52)
	_style_slot_button(button, "")
	return button

func _make_slot_count_label(button: Button) -> Label:
	var label := _label("", 12)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 3.0
	label.offset_top = 35.0
	label.offset_right = -5.0
	label.offset_bottom = -2.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.add_theme_color_override("font_color", Color("f4ead5"))
	label.add_theme_color_override("font_outline_color", Color("15191a"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	return label

func _style_slot_button(button: Button, item_id: String) -> void:
	button.add_theme_stylebox_override("normal",
		FactoryInventoryPanel.make_slot_style(item_id))
	button.add_theme_stylebox_override("hover",
		FactoryInventoryPanel.make_slot_style(item_id, true))
	button.add_theme_stylebox_override("pressed",
		FactoryInventoryPanel.make_slot_style(item_id, true))

func _on_output_slot_input(event: InputEvent, slot_index: int) -> void:
	if miner_mode:
		return
	if not event is InputEventMouseButton or not event.pressed \
			or event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	if slot_index < 0 or slot_index >= output_slots.size():
		return
	var slot: Dictionary = output_slots[slot_index]
	output_slot_requested.emit(slot_index, str(slot.get("item_id", "")),
		int(slot.get("count", 0)), int(event.button_index), event.shift_pressed)
	(slot["button"] as Button).accept_event()

func _on_inventory_slot_input(slot_index: int, button_index: int, shift_pressed: bool) -> void:
	if miner_mode:
		return
	if not shift_pressed or button_index != MOUSE_BUTTON_LEFT \
			or player == null or sim == null:
		player_slot_input_requested.emit(slot_index, button_index, shift_pressed)
		return
	if creative_mode_active:
		toast_requested.emit("Creative items can't be inserted into machines")
		return
	if slot_index < 0 or slot_index >= player.inventory.slots.size():
		return
	var slot: Dictionary = player.inventory.slots[slot_index]
	var item_id: String = str(slot.get("item_id", ""))
	var quantity: int = int(slot.get("count", 0))
	if item_id.is_empty() or quantity <= 0:
		return
	var moved: int = sim.insert_input_items(entity_id, item_id, quantity)
	if moved <= 0:
		return
	player.inventory.take_slot(slot_index, moved)
	inventory_grid.configure(player.inventory, icon_cache)
	inventory_changed.emit()
	refresh()

func set_creative_mode(active: bool) -> void:
	creative_mode_active = active

func refresh_inventory() -> void:
	if not miner_mode and player != null and inventory_grid != null:
		inventory_grid.configure(player.inventory, icon_cache)

func _take_output() -> void:
	if miner_mode or player == null or sim == null:
		return
	var view: Dictionary = sim.machine_view(entity_id)
	if view.is_empty():
		return
	var output_buffer: Dictionary = view.get("output_buffer", {})
	for item_variant: Variant in output_buffer:
		var item_id: String = str(item_variant)
		var quantity: int = int(output_buffer[item_variant])
		if quantity <= 0:
			continue
		var fit: int = player.inventory.fit_count(item_id, quantity)
		var moved: int = sim.take_output_items(entity_id, item_id, fit)
		if moved > 0:
			player.inventory.add(item_id, moved)
			items_collected.emit(item_id, moved)
		if moved < quantity:
			toast_requested.emit("Some output could not fit")
	inventory_grid.configure(player.inventory, icon_cache)
	inventory_changed.emit()
	refresh()

func _on_recipe_selected(index: int) -> void:
	if sim == null or index <= 0 or index - 1 >= recipe_ids.size():
		return
	sim.set_recipe(entity_id, recipe_ids[index - 1], true)
	refresh()

func _label(text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
