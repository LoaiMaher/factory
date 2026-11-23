extends GridContainer
class_name FactoryInventoryPanel

signal slot_input(slot_index: int, button_index: int, shift_pressed: bool)
signal slot_hovered(slot_index: int, entered: bool)

const SLOT_SIZE: Vector2 = Vector2(62.0, 62.0)

var inventory: FrontierInventory
var icon_cache: FactoryIconCache
var category_filter: String = "all"

func configure(value: FrontierInventory, icons: FactoryIconCache, filter: String = "all") -> void:
	inventory = value
	icon_cache = icons
	category_filter = filter
	columns = 8
	_rebuild()

func _rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if inventory == null:
		return
	for index: int in range(maxi(FrontierInventory.DEFAULT_CAPACITY, inventory.slots.size())):
		var slot: Dictionary = inventory.slots[index] if index < inventory.slots.size() else {}
		var item_id: String = str(slot.get("item_id", ""))
		var quantity: int = int(slot.get("count", 0))
		var overflow: bool = index >= inventory.capacity
		var filtered: bool = not item_id.is_empty() and category_filter != "all" \
			and Items.category(item_id) != category_filter
		var display_item_id: String = "" if filtered else item_id
		var display_quantity: int = 0 if filtered else quantity
		var button := Button.new()
		button.custom_minimum_size = SLOT_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = filtered
		button.tooltip_text = "Filtered slot" if filtered else _tooltip(item_id, quantity, overflow)
		button.add_theme_stylebox_override("normal", _style(overflow, false))
		button.add_theme_stylebox_override("hover", _style(overflow, true))
		button.add_theme_stylebox_override("pressed", _style(overflow, true))
		if not display_item_id.is_empty() and icon_cache != null:
			var icon: Texture2D = icon_cache.get_icon("item", display_item_id)
			if icon != null:
				button.icon = icon
				button.expand_icon = true
				button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
				button.add_theme_constant_override("icon_max_width", 40)
		if display_quantity > 1:
			var count_label := Label.new()
			count_label.text = str(display_quantity)
			count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			count_label.offset_left = 3.0
			count_label.offset_top = 34.0
			count_label.offset_right = -5.0
			count_label.offset_bottom = -2.0
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			count_label.add_theme_color_override("font_color", Color("f4ead5"))
			count_label.add_theme_color_override("font_outline_color", Color("15191a"))
			count_label.add_theme_constant_override("outline_size", 4)
			button.add_child(count_label)
		if overflow and not filtered:
			var overflow_label := Label.new()
			overflow_label.text = "OVR"
			overflow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overflow_label.position = Vector2(2.0, 1.0)
			overflow_label.add_theme_font_size_override("font_size", 9)
			overflow_label.add_theme_color_override("font_color", Color("f2b46f"))
			button.add_child(overflow_label)
		button.gui_input.connect(_on_slot_input.bind(index))
		button.mouse_entered.connect(slot_hovered.emit.bind(index, true))
		button.mouse_exited.connect(slot_hovered.emit.bind(index, false))
		add_child(button)

func _tooltip(item_id: String, quantity: int, overflow: bool) -> String:
	if item_id.is_empty():
		return "Empty slot"
	var result: String = "%s\n%s\n%s\nstack %d/%d" % [
		Items.item_name(item_id), Items.category(item_id).capitalize(),
		Items.description(item_id), quantity, Items.stack_size(item_id)]
	if overflow:
		result += "\nOverflow · removal only"
	return result

func _style(overflow: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("30383a") if hovered else Color("242a2b")
	style.border_color = Color("f2b46f") if overflow else Color("536063")
	style.set_border_width_all(2 if overflow else 1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style

func _on_slot_input(event: InputEvent, slot_index: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	slot_input.emit(slot_index, int(event.button_index), event.shift_pressed)
	accept_event()
