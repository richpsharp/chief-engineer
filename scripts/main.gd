extends Control
## Navigation and presentation over the independent ship simulation.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Presenter = preload("res://scripts/presentation/ship_presenter.gd")
const INK = Color("08121c")
const PANEL = Color("101f2c")
const BORDER = Color("294050")
const TEXT = Color("e6f1f5")
const MUTED = Color("93acbb")
const CYAN = Color("5ed9df")
const GREEN = Color("78e2af")
const AMBER = Color("f4c574")
const DIM = Color("466171")
var ship = Simulation.new()
var presenter = Presenter.new(ship)
var current_system: String = "overview"
var selected_equipment: String = ""
var history: Array[Dictionary] = []
var nav_buttons: Dictionary = {}
var overview_buttons: Dictionary = {}
var equipment_buttons: Dictionary = {}
var dependency_buttons: Array[Button] = []
var overview_labels: Dictionary = {}
var equipment_labels: Dictionary = {}
var workspace_layer: Control
var breadcrumb_layer: Control
var pause_button: Button
var reset_button: Button
var back_button: Button
var breaker_button: Button
var control_slider: HSlider
var control_value: Label
var control_widgets: Array[Dictionary] = []
var inspector_title: Label
var inspector_condition: Label
var reading_rows: Array = []
var supply_label: Label
var cooling_label: Label
var ship_status: Label
var running_label: Label
var view_title: Label
var view_description: Label
var conditions_label: Label
var condition_button: Button
var event_log: RichTextLabel
var log_dialog: AcceptDialog
var summary_value: Label
var summary_state: Label
var summary_detail: Label
var refresh_remaining: float = 0.0


func _ready() -> void:
	get_window().min_size = Vector2i(1152, 720)
	theme = Theme.new()
	theme.default_font_size = 17
	if not ship.validation_errors.is_empty():
		_label("Unable to load this ship", Rect2(48, 48, 1300, 60), 32, TEXT, self)
		var error_label := _label("Correct the ship configuration and restart:\n\n" + "\n".join(ship.validation_errors), Rect2(48, 130, 1300, 700), 18, AMBER, self, true)
		error_label.name = "ConfigurationError"
		set_process(false)
		set_process_unhandled_key_input(false)
		return
	_build_shell()
	_build_view()
	_refresh()


func _process(delta: float) -> void:
	ship.tick(delta)
	refresh_remaining -= delta
	if refresh_remaining <= 0.0:
		refresh_remaining = 0.1
		_refresh()
	queue_redraw()


func _style(fill: Color, border: Color = BORDER, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(6)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


func _place(control: Control, rect: Rect2, parent: Node) -> void:
	parent.add_child(control)
	control.position = rect.position
	control.size = rect.size


func _panel(rect: Rect2, parent: Node) -> Panel:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(panel, rect, parent)
	return panel


func _text(value: String, font_size: int = 17, color: Color = TEXT, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _label(value: String, rect: Rect2, font_size: int, color: Color, parent: Node, wrap: bool = false) -> Label:
	var label := _text(value, font_size, color, wrap)
	_place(label, rect, parent)
	return label


func _new_button(value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_disabled_color", DIM)
	button.add_theme_stylebox_override("normal", _style(Color("152d3b")))
	button.add_theme_stylebox_override("hover", _style(Color("214657"), CYAN))
	button.add_theme_stylebox_override("pressed", _style(Color("2a5961"), CYAN))
	button.add_theme_stylebox_override("disabled", _style(Color("101c26")))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), CYAN, 2))
	button.pressed.connect(callback)
	return button


func _button(value: String, rect: Rect2, callback: Callable, parent: Node) -> Button:
	var button := _new_button(value, callback)
	_place(button, rect, parent)
	return button


func _build_shell() -> void:
	_label("C H I E F   E N G I N E E R", Rect2(26, 20, 700, 25), 14, CYAN, self)
	_label(ship.definition.display_name + " / Engineering", Rect2(24, 48, 800, 46), 34, TEXT, self)
	running_label = _label("", Rect2(900, 20, 508, 27), 14, MUTED, self)
	running_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pause_button = _button("Pause [P]", Rect2(1110, 59, 142, 42), _pause, self)
	reset_button = _button("Reset ship", Rect2(1264, 59, 144, 42), _reset_ship, self)
	_panel(Rect2(24, 128, 196, 742), self)
	_label("ENGINEERING", Rect2(40, 145, 166, 22), 12, MUTED, self)
	nav_buttons["overview"] = _button("Ship overview", Rect2(36, 181, 172, 44), navigate.bind("overview", ""), self)
	_label("WORKSPACES", Rect2(40, 247, 168, 22), 12, MUTED, self)
	var y: float = 278
	for view in ship.definition.views:
		if view.get("kind", "") != "workspace":
			continue
		_add_navigation(view, y)
		y += 54
	_label("SYSTEM STATUS", Rect2(40, y + 17, 168, 22), 12, MUTED, self)
	y += 50
	for view in ship.definition.views:
		if view.get("kind", "") == "workspace":
			continue
		_add_navigation(view, y)
		y += 50
	_button("Engineering log", Rect2(36, 810, 172, 42), _show_log, self).add_theme_font_size_override("font_size", 15)
	_panel(Rect2(244, 128, 1164, 74), self)
	_label("ELECTRICAL SUPPLY", Rect2(262, 138, 345, 20), 12, MUTED, self)
	supply_label = _label("", Rect2(262, 162, 345, 28), 21, CYAN, self)
	_label("HEAT PRODUCED / RADIATED", Rect2(657, 138, 330, 20), 12, MUTED, self)
	cooling_label = _label("", Rect2(657, 162, 330, 28), 21, TEXT, self)
	_label("SHIP CONDITION", Rect2(1040, 138, 340, 20), 12, MUTED, self)
	ship_status = _label("", Rect2(1040, 162, 340, 28), 21, GREEN, self)
	breadcrumb_layer = Control.new()
	breadcrumb_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(breadcrumb_layer)
	workspace_layer = Control.new()
	workspace_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(workspace_layer)
	log_dialog = AcceptDialog.new()
	log_dialog.title = "Engineering log"
	log_dialog.min_size = Vector2i(800, 420)
	add_child(log_dialog)
	event_log = RichTextLabel.new()
	event_log.add_theme_font_size_override("normal_font_size", 17)
	event_log.scroll_following = true
	log_dialog.add_child(event_log)
	event_log.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	event_log.offset_left = 14
	event_log.offset_top = 14
	event_log.offset_right = -14
	event_log.offset_bottom = -50


func _add_navigation(view: Dictionary, y: float) -> void:
	var button := _new_button(str(view.get("nav_name", view.name)), navigate.bind(str(view.id), ""))
	button.add_theme_font_size_override("font_size", 15)
	button.clip_text = true
	_place(button, Rect2(36, y, 172, 42), self)
	button.tooltip_text = str(view.name)
	nav_buttons[view.id] = button

func navigate(system: String, equipment: String = "") -> void:
	var view: Dictionary = ship.definition.view(system)
	if system != "overview" and view.is_empty():
		return
	if not equipment.is_empty():
		var spec = ship.definition.component(equipment)
		if spec == null or not spec.inspectable:
			return
		if view.get("kind", "") != "workspace" or equipment not in view.get("members", []):
			system = ship.definition.workspace_for(equipment)
			if system.is_empty():
				return
	if current_system == system and selected_equipment == equipment:
		return
	history.append({"system": current_system, "equipment": selected_equipment})
	if history.size() > 32:
		history.pop_front()
	current_system = system
	selected_equipment = equipment
	_build_view()
	_refresh()

func _back() -> void:
	if history.is_empty():
		return
	var previous: Dictionary = history.pop_back()
	current_system = previous.system
	selected_equipment = previous.equipment
	_build_view()
	_refresh()


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _build_view() -> void:
	_clear(workspace_layer)
	_clear(breadcrumb_layer)
	overview_buttons.clear()
	overview_labels.clear()
	equipment_buttons.clear()
	equipment_labels.clear()
	dependency_buttons.clear()
	reading_rows.clear()
	control_widgets.clear()
	control_slider = null
	control_value = null
	breaker_button = null
	inspector_title = null
	inspector_condition = null
	summary_value = null
	conditions_label = null
	condition_button = null
	back_button = _button("‹ Back", Rect2(244, 218, 94, 30), _back, breadcrumb_layer)
	back_button.add_theme_font_size_override("font_size", 14)
	back_button.disabled = history.is_empty()
	_button("Engineering", Rect2(348, 218, 124, 30), navigate.bind("overview", ""), breadcrumb_layer).add_theme_font_size_override("font_size", 14)
	var view: Dictionary = ship.definition.view(current_system)
	if current_system != "overview":
		_button(str(view.name), Rect2(484, 218, 204, 30), navigate.bind(current_system, ""), breadcrumb_layer).add_theme_font_size_override("font_size", 14)
	if not selected_equipment.is_empty():
		_label("›  " + ship.definition.component(selected_equipment).display_name, Rect2(704, 218, 700, 30), 14, MUTED, breadcrumb_layer)
	for id in nav_buttons:
		nav_buttons[id].add_theme_stylebox_override("normal", _style(Color("214452") if id == current_system else Color("152735"), CYAN if id == current_system else BORDER))
	view_title = _label("Ship overview" if current_system == "overview" else str(view.name), Rect2(244, 264, 710, 44), 32, TEXT, workspace_layer)
	view_description = _label("", Rect2(246, 313, 720, 28), 16, MUTED, workspace_layer)
	if current_system == "overview":
		_build_overview()
	elif view.get("kind", "") == "workspace":
		_build_workspace()
	else:
		_build_summary()
	queue_redraw()

func _build_overview() -> void:
	var i: int = 0
	for view in ship.definition.views:
		var id: String = view.id
		var x: int = 244 + (i % 2) * 592
		var y: int = 356 + floori(i / 2.0) * 120
		var card := _button("", Rect2(x, y, 572, 108), navigate.bind(id, ""), workspace_layer)
		card.tooltip_text = "Open " + str(view.name)
		overview_buttons[id] = card
		_label(str(view.name), Rect2(16, 10, 330, 25), 18, TEXT, card)
		var state := _label("", Rect2(350, 13, 204, 22), 13, GREEN, card)
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var value := _label("", Rect2(16, 38, 530, 32), 25, TEXT, card)
		var detail := _label("", Rect2(16, 77, 532, 23), 14, MUTED, card)
		overview_labels[id] = {"state": state, "value": value, "detail": detail}
		i += 1
	conditions_label = _label("", Rect2(246, 838, 1156, 28), 15, MUTED, workspace_layer)
	condition_button = _button("", Rect2(244, 834, 1164, 36), _inspect_condition, workspace_layer)
	condition_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	condition_button.add_theme_font_size_override("font_size", 15)

func _build_workspace() -> void:
	var layout: Dictionary = _workspace_nodes()
	for id in layout:
		var spec = ship.definition.component(id)
		if spec == null or not spec.inspectable:
			continue
		var rect: Rect2 = layout[id]
		var card := _button("", rect, navigate.bind(current_system, str(id)), workspace_layer)
		card.tooltip_text = "Inspect " + spec.display_name
		if id == selected_equipment:
			card.add_theme_stylebox_override("normal", _style(Color("214452"), CYAN, 2))
		equipment_buttons[id] = card
		var caption_text: String = str(spec.definition.kind).replace("_", " ").to_upper()
		var target: String = ship.definition.workspace_for(id)
		if id not in ship.definition.view(current_system).get("members", []) and not target.is_empty():
			caption_text = str(ship.definition.view(target).get("name", caption_text)).to_upper() + " ↗"
		_label(caption_text, Rect2(12, 8, rect.size.x - 24, 18), 11, MUTED, card)
		_label(spec.short_name if not spec.short_name.is_empty() else spec.display_name, Rect2(12, 30, rect.size.x - 24, 28), 20, TEXT, card)
		equipment_labels[id] = _label("", Rect2(12, 66, rect.size.x - 24, 25), 14, CYAN, card)
	_label(str(ship.definition.view(current_system).get("detail", "")), Rect2(266, 813, 690, 42), 15, MUTED, workspace_layer, true)
	_build_inspector()


func _workspace_nodes() -> Dictionary:
	return ship.definition.layouts.get(current_system, {}).get("nodes", {})

func _build_inspector() -> void:
	_panel(Rect2(990, 264, 418, 606), workspace_layer)
	if selected_equipment == "":
		_label("EQUIPMENT INSPECTOR", Rect2(1010, 282, 370, 25), 12, MUTED, workspace_layer)
		_label("Follow the connections", Rect2(1010, 324, 370, 45), 25, TEXT, workspace_layer)
		_label("Select equipment on the schematic to see its live readings and controls.", Rect2(1010, 390, 365, 85), 20, MUTED, workspace_layer, true)
		_label("Connected equipment links let you follow a supply or a load into another workspace. Back retraces your route.", Rect2(1010, 508, 365, 123), 17, MUTED, workspace_layer, true)
		_label("The ship keeps running as you explore. Pause freezes the simulation and controls.", Rect2(1010, 710, 365, 110), 17, CYAN, workspace_layer, true)
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_place(scroll, Rect2(1008, 279, 382, 572), workspace_layer)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	scroll.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var tag := _text("EQUIPMENT INSPECTOR", 12, MUTED)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(tag)
	var close_button := _new_button("×", navigate.bind(current_system, ""))
	var close_style := _style(Color("152d3b"))
	close_style.content_margin_top = 1
	close_style.content_margin_bottom = 1
	close_button.add_theme_stylebox_override("normal", close_style)
	close_button.add_theme_font_size_override("font_size", 14)
	heading.add_child(close_button)
	var spec = ship.definition.component(selected_equipment)
	inspector_title = _text(spec.display_name, 25, TEXT, true)
	column.add_child(inspector_title)
	var context: String = presenter.assembly_context(selected_equipment)
	if not context.is_empty():
		column.add_child(_text(context, 12, CYAN, true))
	column.add_child(_text(spec.description, 14, MUTED, true))
	inspector_condition = _text("", 14, GREEN, true)
	column.add_child(inspector_condition)
	column.add_child(HSeparator.new())
	for reading in presenter.readings(selected_equipment):
		var row := HBoxContainer.new()
		column.add_child(row)
		var key := _text(str(reading[0]), 14, MUTED)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		var value := _text(str(reading[1]), 14, TEXT)
		row.add_child(value)
		reading_rows.append({"key": key, "value": value})
	for descriptor in spec.controls():
		column.add_child(HSeparator.new())
		var action: String = str(descriptor.id)
		if descriptor.get("kind", "") == "toggle":
			var toggle := _new_button("", _toggle_control.bind(action))
			toggle.add_theme_font_size_override("font_size", 14)
			toggle.custom_minimum_size.y = 34
			column.add_child(toggle)
			control_widgets.append({"descriptor": descriptor, "button": toggle})
			if breaker_button == null:
				breaker_button = toggle
		else:
			var control_heading := HBoxContainer.new()
			column.add_child(control_heading)
			var control_name := _text(str(descriptor.label), 14, MUTED)
			control_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			control_heading.add_child(control_name)
			var value_label := _text("", 16, CYAN)
			control_heading.add_child(value_label)
			var slider := HSlider.new()
			slider.min_value = float(descriptor.get("min", 0))
			slider.max_value = float(descriptor.get("max", 100))
			slider.step = float(descriptor.get("step", 1))
			slider.custom_minimum_size = Vector2(0, 26)
			slider.tooltip_text = str(descriptor.label)
			slider.value_changed.connect(_change_control.bind(action))
			column.add_child(slider)
			control_widgets.append({"descriptor": descriptor, "slider": slider, "value": value_label})
			if control_slider == null:
				control_slider = slider
				control_value = value_label
	column.add_child(HSeparator.new())
	column.add_child(_text("CONNECTED EQUIPMENT", 12, MUTED))
	var connected: Array[Dictionary] = presenter.links(selected_equipment)
	if connected.is_empty():
		column.add_child(_text("No active connections", 14, MUTED))
	for link in connected:
		var button := _new_button(link.label + "  ›", navigate.bind(link.system, link.equipment))
		button.add_theme_font_size_override("font_size", 14)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 32
		column.add_child(button)
		dependency_buttons.append(button)

func _build_summary() -> void:
	_panel(Rect2(244, 356, 1164, 454), workspace_layer)
	_label("SYSTEM STATUS", Rect2(270, 378, 1000, 24), 13, MUTED, workspace_layer)
	summary_value = _label("", Rect2(270, 420, 1000, 60), 38, TEXT, workspace_layer)
	summary_state = _label("", Rect2(270, 494, 1000, 30), 20, GREEN, workspace_layer)
	summary_detail = _label("", Rect2(270, 544, 1050, 62), 18, MUTED, workspace_layer, true)
	var targets: Array[Dictionary] = []
	var seen: Dictionary = {}
	for id in ship.definition.view(current_system).get("members", []):
		var spec = ship.definition.component(id)
		var workspace: String = ship.definition.workspace_for(id)
		if spec != null and spec.inspectable and not workspace.is_empty() and not seen.has(id):
			targets.append({"system": workspace, "equipment": id, "label": "Inspect " + spec.short_name})
			seen[id] = true
		for link in presenter.links(id):
			if not seen.has(link.equipment):
				targets.append(link)
				seen[link.equipment] = true
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_place(scroll, Rect2(270, 644, 1100, 140), workspace_layer)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for link in targets:
		var button := _new_button(link.label + "  ›", navigate.bind(link.system, link.equipment))
		button.custom_minimum_size = Vector2(520, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 16)
		grid.add_child(button)
		dependency_buttons.append(button)

func _refresh() -> void:
	if not is_instance_valid(supply_label):
		return
	var totals: Dictionary = ship.totals()
	supply_label.text = "%.0f / %.0f kW  •  %.0f spare" % [totals.output, totals.capacity, totals.spare]
	cooling_label.text = "%.1f / %.1f kW" % [totals.heat_generated, totals.heat_rejected]
	var conditions: Array = presenter.conditions()
	ship_status.text = "All systems nominal" if conditions.is_empty() else "%d condition%s to inspect" % [conditions.size(), "" if conditions.size() == 1 else "s"]
	ship_status.add_theme_color_override("font_color", GREEN if conditions.is_empty() else AMBER)
	running_label.text = "SIMULATION PAUSED" if ship.paused else "CRUISE CONFIGURATION  /  RUNNING"
	pause_button.text = "Resume [P]" if ship.paused else "Pause [P]"
	if current_system == "overview":
		view_description.text = "Live systems and connected machinery. Select a system to explore."
		for id in overview_labels:
			var summary: Dictionary = presenter.system_summary(id)
			var labels: Dictionary = overview_labels[id]
			labels.state.text = summary.state
			labels.state.add_theme_color_override("font_color", _tone(summary.tone))
			labels.value.text = summary.value
			labels.detail.text = summary.detail + "   ›"
		conditions_label.text = "Standing watch • no active limitations" if conditions.is_empty() else str(conditions[0].text)
		conditions_label.add_theme_color_override("font_color", MUTED if conditions.is_empty() else AMBER)
		condition_button.visible = not conditions.is_empty()
		conditions_label.visible = conditions.is_empty()
		if not conditions.is_empty():
			condition_button.text = str(conditions[0].text) + "   •   Inspect ›"
	else:
		var view: Dictionary = ship.definition.view(current_system)
		view_description.text = str(view.get("description", "Summary readings and connections"))
		if view.get("kind", "") == "workspace":
			for id in equipment_labels:
				equipment_labels[id].text = presenter.caption(id)
				equipment_labels[id].add_theme_color_override("font_color", _equipment_tone(id))
			_refresh_inspector()
		else:
			var summary: Dictionary = presenter.system_summary(current_system)
			summary_value.text = summary.value
			summary_state.text = summary.state
			summary_state.add_theme_color_override("font_color", _tone(summary.tone))
			summary_detail.text = summary.detail
	if log_dialog.visible:
		_refresh_log()

func _refresh_inspector() -> void:
	if selected_equipment == "":
		return
	var reason: String = presenter.equipment_reason(selected_equipment)
	var status: String = presenter.equipment_status(selected_equipment)
	var warning: bool = status not in ["Online", "Idle", "Standby reference"]
	inspector_condition.text = status + (" • " + reason if warning and not reason.is_empty() else "")
	inspector_condition.add_theme_color_override("font_color", _equipment_tone(selected_equipment))
	var readings: Array = presenter.readings(selected_equipment)
	for i in mini(readings.size(), reading_rows.size()):
		reading_rows[i].key.text = str(readings[i][0])
		reading_rows[i].value.text = str(readings[i][1])
	var settings: Dictionary = ship.components[selected_equipment].settings
	for widget in control_widgets:
		var descriptor: Dictionary = widget.descriptor
		var value = settings.get(descriptor.id, descriptor.get("default", 0))
		if widget.has("slider"):
			widget.slider.set_value_no_signal(float(value))
			widget.slider.editable = not ship.paused
			widget.value.text = "%.0f %s%s" % [float(value), descriptor.get("unit", ""), "  (paused)" if ship.paused else ""]
		else:
			widget.button.text = str(descriptor.label) + ": " + ("ON  •  Switch off" if value else "OFF  •  Switch on")
			widget.button.disabled = ship.paused

func _tone(name_text: String) -> Color:
	return AMBER if name_text == "warn" else (GREEN if name_text == "good" else MUTED)


func _equipment_tone(id: String) -> Color:
	var status: String = presenter.equipment_status(id)
	if status == "Online":
		return CYAN
	return MUTED if status in ["Idle", "Standby reference"] else AMBER

func _inspect_condition() -> void:
	var conditions: Array = presenter.conditions()
	if not conditions.is_empty():
		navigate(conditions[0].system, conditions[0].equipment)

func _change_control(value: float, action: String) -> void:
	ship.command(selected_equipment, action, value)


func _toggle_control(action: String) -> void:
	var settings: Dictionary = ship.components[selected_equipment].settings
	ship.command(selected_equipment, action, not bool(settings.get(action, false)))

func _pause() -> void:
	ship.toggle_pause()
	_refresh()


func _reset_ship() -> void:
	ship.reset()
	_refresh()
	queue_redraw()


func _show_log() -> void:
	_refresh_log()
	log_dialog.popup_centered(Vector2i(960, 520))


func _refresh_log() -> void:
	var content: String = "\n\n".join(ship.events)
	if event_log.text != content:
		event_log.text = content


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			_pause()
		elif event.keycode == KEY_ESCAPE:
			_back()


func _line(points: PackedVector2Array, color: Color, energized: bool) -> void:
	for i in range(points.size() - 1):
		if energized:
			draw_line(points[i], points[i + 1], Color(color, 0.12), 10, true)
			draw_line(points[i], points[i + 1], color, 2, true)
		else:
			draw_dashed_line(points[i], points[i + 1], DIM, 2, 6, true)
	if energized:
		var segment: int = int(ship.elapsed) % (points.size() - 1)
		draw_circle(points[segment].lerp(points[segment + 1], fmod(ship.elapsed, 1.0)), 3, TEXT)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1440, 900), INK)
	if not ship.validation_errors.is_empty():
		return
	if ship.definition.view(current_system).get("kind", "") != "workspace":
		return
	draw_style_box(_style(Color("0c1a25")), Rect2(244, 350, 732, 520))
	for x in range(258, 968, 24):
		for y in range(360, 860, 24):
			draw_circle(Vector2(x, y), 0.7, Color("1e3443"))
	var layout: Dictionary = _workspace_nodes()
	for edge in presenter.schematic_edges(layout.keys()):
		var points: PackedVector2Array = _route_edge(layout[edge.from_component], layout[edge.to_component], layout)
		_line(points, AMBER if edge.domain == "thermal" else CYAN, edge.active)


func _route_edge(source: Rect2, destination: Rect2, layout: Dictionary) -> PackedVector2Array:
	var start: Vector2 = source.get_center()
	var finish: Vector2 = destination.get_center()
	var forward: bool = finish.x >= start.x
	start.x = source.end.x if forward else source.position.x
	finish.x = destination.position.x if forward else destination.end.x
	var middle_x: float = (start.x + finish.x) * 0.5
	var points := PackedVector2Array([start, Vector2(middle_x, start.y), Vector2(middle_x, finish.y), finish])
	for rect in layout.values():
		if rect == source or rect == destination:
			continue
		if _route_intersects(points, rect.grow(8)):
			var use_top: bool = (source.get_center().y + destination.get_center().y) * 0.5 < 575
			var lane: float = 356 if use_top else 794
			var source_edge: Vector2 = Vector2(source.get_center().x, source.position.y if use_top else source.end.y)
			var destination_edge: Vector2 = Vector2(destination.get_center().x, destination.position.y if use_top else destination.end.y)
			return PackedVector2Array([source_edge, Vector2(source_edge.x, lane), Vector2(destination_edge.x, lane), destination_edge])
	return points


func _route_intersects(points: PackedVector2Array, rect: Rect2) -> bool:
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		if is_equal_approx(a.y, b.y) and a.y > rect.position.y and a.y < rect.end.y:
			if maxf(a.x, b.x) > rect.position.x and minf(a.x, b.x) < rect.end.x:
				return true
		if is_equal_approx(a.x, b.x) and a.x > rect.position.x and a.x < rect.end.x:
			if maxf(a.y, b.y) > rect.position.y and minf(a.y, b.y) < rect.end.y:
				return true
	return false
