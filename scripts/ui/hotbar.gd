extends Control
class_name FactoryHotbar

signal slot_selected(index: int)
signal slot_cleared(index: int)

const SLOT_SIZE: int = 64
const SLOT_GAP: int = 6
const SLOT_ROW_WIDTH: int = SLOT_SIZE * HotbarModel.SLOT_COUNT + SLOT_GAP * (HotbarModel.SLOT_COUNT - 1)

var model: HotbarModel
var icon_cache: FactoryIconCache
var inventory: Dictionary = {}
var unlocked_tiers: int = 0
var slot_buttons: Array[Button] = []
var slot_icons: Array[TextureRect] = []
var slot_abbreviations: Array[Label] = []
var slot_quantities: Array[Label] = []
var slot_locks: Array[Control] = []
var selected_name: Label
var selected_name_time: float = 0.0
var displayed_selection: int = -2
var displayed_action: Dictionary = {}
var interactive: bool = false

func configure(factory_model: HotbarModel, factory_icons: FactoryIconCache) -> void:
	model = factory_model
	icon_cache = factory_icons

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_create_slot_row()
	_create_selected_name()
	refresh(model, inventory, unlocked_tiers)

func _process(delta: float) -> void:
	if selected_name_time > 0.0:
		selected_name_time = maxf(0.0, selected_name_time - delta)
		if selected_name_time == 0.0 and selected_name != null:
			selected_name.text = ""

func refresh(factory_model: HotbarModel, current_inventory: Dictionary, tier: int) -> void:
	if factory_model != null:
		model = factory_model
	inventory = current_inventory
	unlocked_tiers = tier
	if model == null or slot_buttons.is_empty():
		return
	if displayed_selection != model.selected_index:
		displayed_selection = model.selected_index
		displayed_action = model.selected_action()
		_animate_selection(displayed_selection)
	elif displayed_action != model.selected_action():
		displayed_action = model.selected_action()
		if displayed_selection >= 0:
			show_selected_name(displayed_action)
	for index: int in range(HotbarModel.SLOT_COUNT):
		var slot: Dictionary = model.slot_at(index)
		var locked: bool = model.is_locked(index, unlocked_tiers)
		var quantity: int = model.quantity(index, inventory)
		var has_count: bool = quantity > 0
		var icon: Texture2D = icon_cache.get_icon(str(slot.get("type", "")), str(slot.get("id", ""))) if icon_cache != null else null
		slot_icons[index].texture = icon
		slot_icons[index].visible = icon != null
		slot_abbreviations[index].visible = icon == null and not slot.is_empty()
		slot_abbreviations[index].text = _abbreviation(slot)
		slot_quantities[index].text = str(quantity) if not slot.is_empty() else ""
		slot_locks[index].visible = locked
		if locked:
			var building_id: String = str(slot.get("id", ""))
			var tier: int = int(BuildingDefs.all().get(building_id, {}).get("tier", 0))
			var lock_label: Label = slot_locks[index].get_node("LockLabel") as Label
			lock_label.text = "LOCK T%d" % tier
		slot_buttons[index].modulate = Color(0.55, 0.58, 0.6, 0.5) if not has_count else Color.WHITE
		slot_buttons[index].mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE

func set_interactive(enabled: bool) -> void:
	interactive = enabled
	for button: Button in slot_buttons:
		button.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE

func show_selected_name(action: Dictionary) -> void:
	if selected_name == null:
		return
	var slot_type: String = str(action.get("type", ""))
	var id: String = str(action.get("id", ""))
	if slot_type == "item":
		selected_name.text = Items.item_name(id)
	elif slot_type == "building":
		selected_name.text = id.replace("_", " ").capitalize()
	else:
		selected_name.text = "Empty hands"
	selected_name_time = 1.5

func _create_slot_row() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "SlotRow"
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = -float(SLOT_ROW_WIDTH) * 0.5
	row.offset_right = float(SLOT_ROW_WIDTH) * 0.5
	row.offset_top = -76.0
	row.offset_bottom = -12.0
	row.add_theme_constant_override("separation", SLOT_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(row)
	for index: int in range(HotbarModel.SLOT_COUNT):
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		button.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.pivot_offset = Vector2(SLOT_SIZE * 0.5, SLOT_SIZE * 0.5)
		button.add_theme_stylebox_override("normal", _slot_style(false))
		button.add_theme_stylebox_override("hover", _slot_style(true))
		button.add_theme_stylebox_override("pressed", _slot_style(true))
		button.pressed.connect(slot_selected.emit.bind(index))
		button.gui_input.connect(_on_slot_gui_input.bind(index))
		row.add_child(button)
		var notch: ColorRect = ColorRect.new()
		notch.position = Vector2(SLOT_SIZE - 11.0, 0.0)
		notch.size = Vector2(9.0, 2.0)
		notch.color = Color("e8792b")
		notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(notch)
		var key_label: Label = Label.new()
		key_label.position = Vector2(4.0, 1.0)
		key_label.size = Vector2(18.0, 18.0)
		key_label.text = "0" if index == 9 else str(index + 1)
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_color", Color("c6ccd0"))
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(key_label)
		var icon: TextureRect = TextureRect.new()
		icon.position = Vector2(9.0, 9.0)
		icon.size = Vector2(46.0, 46.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		var abbreviation: Label = Label.new()
		abbreviation.position = Vector2(8.0, 20.0)
		abbreviation.size = Vector2(48.0, 24.0)
		abbreviation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		abbreviation.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		abbreviation.add_theme_font_size_override("font_size", 16)
		abbreviation.add_theme_color_override("font_color", Color("e6e1d9"))
		abbreviation.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(abbreviation)
		var quantity: Label = Label.new()
		quantity.position = Vector2(31.0, 44.0)
		quantity.size = Vector2(29.0, 17.0)
		quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quantity.add_theme_font_size_override("font_size", 12)
		quantity.add_theme_color_override("font_color", Color("f1f0e8"))
		quantity.add_theme_color_override("font_shadow_color", Color("101316"))
		quantity.add_theme_constant_override("shadow_offset_x", 1)
		quantity.add_theme_constant_override("shadow_offset_y", 1)
		quantity.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(quantity)
		var lock_overlay: Control = _make_lock_overlay()
		button.add_child(lock_overlay)
		slot_buttons.append(button)
		slot_icons.append(icon)
		slot_abbreviations.append(abbreviation)
		slot_quantities.append(quantity)
		slot_locks.append(lock_overlay)

func _create_selected_name() -> void:
	selected_name = Label.new()
	selected_name.anchor_left = 0.5
	selected_name.anchor_right = 0.5
	selected_name.anchor_top = 1.0
	selected_name.anchor_bottom = 1.0
	selected_name.offset_left = -220.0
	selected_name.offset_right = 220.0
	selected_name.offset_top = -108.0
	selected_name.offset_bottom = -80.0
	selected_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_name.add_theme_font_size_override("font_size", 17)
	selected_name.add_theme_color_override("font_color", Color("f2e5d1"))
	selected_name.add_theme_color_override("font_shadow_color", Color("101316"))
	selected_name.add_theme_constant_override("shadow_offset_x", 2)
	selected_name.add_theme_constant_override("shadow_offset_y", 2)
	selected_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(selected_name)

func _slot_style(hovered: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.85)
	style.set_border_width_all(2)
	style.border_color = Color("e8792b") if hovered else Color("69757b")
	style.set_corner_radius_all(3)
	if hovered:
		style.shadow_color = Color(0.91, 0.47, 0.17, 0.52)
		style.shadow_size = 5
	return style

func _make_lock_overlay() -> Control:
	var overlay: Control = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.04, 0.05, 0.06, 0.42)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(shade)
	var label: Label = Label.new()
	label.name = "LockLabel"
	label.text = "LOCK"
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.position = Vector2(-30.0, -8.0)
	label.size = Vector2(60.0, 16.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("f1c26d"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(label)
	overlay.visible = false
	return overlay

func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and interactive:
		slot_cleared.emit(index)
		get_viewport().set_input_as_handled()

func _animate_selection(index: int) -> void:
	for slot_index: int in range(slot_buttons.size()):
		var button: Button = slot_buttons[slot_index]
		button.add_theme_stylebox_override("normal", _selected_style() if slot_index == index else _slot_style(false))
		var tween: Tween = create_tween()
		tween.tween_property(button, "scale", Vector2(1.08, 1.08) if slot_index == index else Vector2.ONE, 0.12)
	if index >= 0 and index < HotbarModel.SLOT_COUNT:
		show_selected_name(model.selected_action())
	elif selected_name != null:
		selected_name.text = ""
		selected_name_time = 0.0

func _selected_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = _slot_style(false)
	style.border_color = Color("e8792b")
	style.shadow_color = Color(0.91, 0.47, 0.17, 0.58)
	style.shadow_size = 7
	return style

func _abbreviation(slot: Dictionary) -> String:
	if slot.is_empty():
		return ""
	var item_name: String = Items.item_name(str(slot.get("id", ""))) if slot.get("type", "") == "item" else str(slot.get("id", "")).replace("_", " ").capitalize()
	var words: PackedStringArray = item_name.split(" ", false)
	if words.size() >= 2:
		return "%s%s" % [words[0].substr(0, 1), words[1].substr(0, 1)]
	return item_name.substr(0, mini(2, item_name.length())).to_upper()
