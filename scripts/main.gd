extends Control
## Navigation and presentation over the independent ship simulation.

const Simulation = preload("res://scripts/ship_simulation.gd")
const INK = Color("08121c")
const PANEL = Color("101f2c")
const BORDER = Color("294050")
const TEXT = Color("e6f1f5")
const MUTED = Color("93acbb")
const CYAN = Color("5ed9df")
const GREEN = Color("78e2af")
const AMBER = Color("f4c574")
const DIM = Color("466171")
const SYSTEMS = {
	"reactor": "Reactor", "power": "Power", "propulsion": "Propulsion", "cooling": "Cooling",
	"life_support": "Life support", "shielding": "Radiation protection", "sensors": "Sensors", "hull": "Hull & compartments",
}
const EQUIPMENT = {
	"reactor": {"name": "Reactor core", "short": "Reactor", "system": "power", "description": "Automatically follows ship demand up to its output limit. Supplies both distribution buses.", "control": "reactor_limit", "control_name": "Available output limit", "max": 200.0, "unit": "kW", "links": [["power", "main_bus", "Supplies: main bus"], ["power", "aux_bus", "Supplies: auxiliary bus B"], ["cooling", "pump_a", "Cooled by: loop A / pump A"]]},
	"main_bus": {"name": "Main distribution bus", "short": "Main bus", "system": "power", "description": "Supplies essential services, reactor cooling, and the main engine. Opening its breaker removes power from these loads.", "links": [["power", "reactor", "Source: reactor"], ["cooling", "pump_a", "Supplies: circulation pump A"], ["cooling", "main_engine", "Supplies: main engine"]]},
	"aux_bus": {"name": "Auxiliary bus B", "short": "Auxiliary bus B", "system": "power", "description": "Shares its supply between 18 kW of services and the propulsion coolant pump. The local limit applies to their combined load.", "control": "bus_b_limit", "control_name": "Local supply limit", "max": 60.0, "unit": "kW", "links": [["power", "reactor", "Source: reactor"], ["cooling", "pump_b", "Supplies: circulation pump B"]]},
	"battery": {"name": "Reserve battery", "short": "Reserve battery", "system": "power", "description": "An isolated reserve pack shown for future expansion. It supplies no power in this model.", "links": [["power", "main_bus", "Planned connection: main bus"]]},
	"pump_a": {"name": "Circulation pump A", "short": "Pump A", "system": "cooling", "description": "Drives reactor cooling and the shared radiator circulation. Powered by the main bus.", "control": "pump_a_command", "control_name": "Requested flow", "max": 36.0, "unit": "L/s", "links": [["power", "main_bus", "Electrical supply: main bus"], ["cooling", "heat_exchanger", "Feeds: core heat exchanger"]]},
	"pump_b": {"name": "Circulation pump B", "short": "Pump B", "system": "cooling", "description": "Circulates coolant through the main engine. Lower electrical supply reduces flow and the thrust the engine can sustain.", "control": "pump_b_command", "control_name": "Requested flow", "max": 40.0, "unit": "L/s", "links": [["power", "aux_bus", "Electrical supply: auxiliary bus B"], ["cooling", "main_engine", "Cools: main engine"]]},
	"heat_exchanger": {"name": "Core heat exchanger", "short": "Heat exchanger", "system": "cooling", "description": "Transfers reactor heat into loop A. Heat leaves the coolant through the shared radiator bank.", "links": [["power", "reactor", "Heat source: reactor"], ["cooling", "pump_a", "Flow source: pump A"], ["cooling", "radiator", "Heat rejection: radiator bank"]]},
	"radiator": {"name": "Radiator bank", "short": "Radiator bank", "system": "cooling", "description": "Rejects heat from both loops. Requires Pump A circulation; panel deployment controls heat rejection.", "control": "radiator_command", "control_name": "Panel deployment", "max": 100.0, "unit": "%", "links": [["cooling", "heat_exchanger", "Receives heat: loop A"], ["cooling", "main_engine", "Receives heat: loop B"]]},
	"main_engine": {"name": "Main engine", "short": "Main engine", "system": "cooling", "description": "Actual thrust follows the command as far as its electrical and cooling supplies allow. Automatic limiting keeps changes recoverable.", "control": "engine_command", "control_name": "Commanded thrust", "max": 60.0, "unit": "%", "links": [["cooling", "pump_b", "Cooling supply: loop B / pump B"], ["power", "main_bus", "Electrical supply: main bus"]]},
}
const POWER_NODES = {
	"reactor": Rect2(266, 432, 186, 106), "main_bus": Rect2(514, 366, 198, 106),
	"aux_bus": Rect2(514, 574, 198, 106), "battery": Rect2(266, 678, 186, 92),
	"pump_a": Rect2(770, 366, 190, 106), "pump_b": Rect2(770, 574, 190, 106),
}
const COOLING_NODES = {
	"pump_a": Rect2(266, 384, 186, 106), "heat_exchanger": Rect2(514, 384, 198, 106),
	"pump_b": Rect2(266, 610, 186, 106), "main_engine": Rect2(514, 610, 198, 106),
	"radiator": Rect2(770, 495, 190, 106),
}

var ship = Simulation.new()
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
	_label("Kestrel / Engineering", Rect2(24, 48, 800, 46), 34, TEXT, self)
	running_label = _label("", Rect2(900, 20, 508, 27), 14, MUTED, self)
	running_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pause_button = _button("Pause [P]", Rect2(1110, 59, 142, 42), _pause, self)
	reset_button = _button("Reset ship", Rect2(1264, 59, 144, 42), _reset_ship, self)
	_panel(Rect2(24, 128, 196, 742), self)
	_label("ENGINEERING", Rect2(40, 145, 166, 22), 12, MUTED, self)
	nav_buttons["overview"] = _button("Ship overview", Rect2(36, 181, 172, 44), navigate.bind("overview", ""), self)
	_label("WORKSPACES", Rect2(40, 247, 168, 22), 12, MUTED, self)
	nav_buttons["power"] = _button("Power", Rect2(36, 278, 172, 44), navigate.bind("power", ""), self)
	nav_buttons["cooling"] = _button("Cooling", Rect2(36, 332, 172, 44), navigate.bind("cooling", ""), self)
	_label("SYSTEM STATUS", Rect2(40, 403, 168, 22), 12, MUTED, self)
	var i := 0
	for id in SYSTEMS:
		if id in ["power", "cooling"]:
			continue
		var name_text: String = "Radiation" if id == "shielding" else ("Hull" if id == "hull" else SYSTEMS[id])
		nav_buttons[id] = _button(name_text, Rect2(36, 436 + i * 50, 172, 42), navigate.bind(id, ""), self)
		i += 1
	_button("Engineering log", Rect2(36, 810, 172, 42), _show_log, self).add_theme_font_size_override("font_size", 15)
	_panel(Rect2(244, 128, 1164, 74), self)
	_label("ELECTRICAL SUPPLY", Rect2(262, 138, 345, 20), 12, MUTED, self)
	supply_label = _label("", Rect2(262, 162, 345, 28), 21, CYAN, self)
	_label("COOLANT / ENGINE", Rect2(657, 138, 330, 20), 12, MUTED, self)
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


func navigate(system: String, equipment: String = "") -> void:
	if system != "overview" and not SYSTEMS.has(system):
		return
	if equipment != "" and (not EQUIPMENT.has(equipment) or EQUIPMENT[equipment].system != system):
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
	if current_system != "overview":
		_button(SYSTEMS[current_system], Rect2(484, 218, 204, 30), navigate.bind(current_system, ""), breadcrumb_layer).add_theme_font_size_override("font_size", 14)
	if selected_equipment != "":
		_label("›  " + EQUIPMENT[selected_equipment].name, Rect2(704, 218, 700, 30), 14, MUTED, breadcrumb_layer)
	for id in nav_buttons:
		nav_buttons[id].add_theme_stylebox_override("normal", _style(Color("214452") if id == current_system else Color("152735"), CYAN if id == current_system else BORDER))
	view_title = _label("Ship overview" if current_system == "overview" else SYSTEMS[current_system], Rect2(244, 264, 710, 44), 32, TEXT, workspace_layer)
	view_description = _label("", Rect2(246, 313, 720, 28), 16, MUTED, workspace_layer)
	if current_system == "overview":
		_build_overview()
	elif current_system in ["power", "cooling"]:
		_build_workspace()
	else:
		_build_summary()
	queue_redraw()


func _build_overview() -> void:
	var i := 0
	for id in SYSTEMS:
		var x: int = 244 + (i % 2) * 592
		var y: int = 356 + (i / 2) * 120
		var card := _button("", Rect2(x, y, 572, 108), navigate.bind(id, ""), workspace_layer)
		card.tooltip_text = "Open " + SYSTEMS[id]
		overview_buttons[id] = card
		_label(SYSTEMS[id], Rect2(16, 10, 330, 25), 18, TEXT, card)
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
	var layout: Dictionary = POWER_NODES if current_system == "power" else COOLING_NODES
	for id in layout:
		var rect: Rect2 = layout[id]
		var target_system: String = EQUIPMENT[id].system
		var card := _button("", rect, navigate.bind(target_system, id), workspace_layer)
		card.tooltip_text = "Inspect " + EQUIPMENT[id].name
		if id == selected_equipment:
			card.add_theme_stylebox_override("normal", _style(Color("214452"), CYAN, 2))
		equipment_buttons[id] = card
		var caption: String = "EQUIPMENT"
		if id in ["pump_a", "pump_b"]:
			caption = "COOLING ↗" if current_system == "power" else ("LOOP A / REACTOR" if id == "pump_a" else "LOOP B / ENGINE")
		elif id == "battery":
			caption = "REFERENCE / ISOLATED"
		_label(caption, Rect2(12, 8, rect.size.x - 24, 18), 11, MUTED, card)
		_label(EQUIPMENT[id].short, Rect2(12, 30, rect.size.x - 24, 28), 20, TEXT, card)
		equipment_labels[id] = _label("", Rect2(12, 66, rect.size.x - 24, 25), 14, CYAN, card)
	if current_system == "power":
		_label("Main loads: essential services, pump A, engine", Rect2(493, 486, 474, 46), 15, MUTED, workspace_layer, true)
		_label("Aux loads: 18 kW services + pump B", Rect2(496, 690, 466, 40), 15, MUTED, workspace_layer, true)
		_label("Supply follows demand • local limits can constrain a single bus", Rect2(266, 813, 690, 42), 15, MUTED, workspace_layer, true)
	else:
		_label("LOOP A / REACTOR COOLING", Rect2(266, 352, 600, 22), 12, MUTED, workspace_layer)
		_label("LOOP B / PROPULSION COOLING", Rect2(266, 577, 600, 22), 12, MUTED, workspace_layer)
		_label("Both loops reject heat through the radiator bank", Rect2(266, 813, 690, 38), 15, MUTED, workspace_layer)
	_build_inspector()


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
	var metadata: Dictionary = EQUIPMENT[selected_equipment]
	inspector_title = _text(metadata.name, 25, TEXT, true)
	column.add_child(inspector_title)
	column.add_child(_text(metadata.description, 14, MUTED, true))
	inspector_condition = _text("", 14, GREEN, true)
	column.add_child(inspector_condition)
	column.add_child(HSeparator.new())
	for reading in ship.readings(selected_equipment):
		var row := HBoxContainer.new()
		column.add_child(row)
		var key := _text(str(reading[0]), 14, MUTED)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		var value := _text(str(reading[1]), 14, TEXT)
		row.add_child(value)
		reading_rows.append({"key": key, "value": value})
	if metadata.has("control"):
		column.add_child(HSeparator.new())
		var control_heading := HBoxContainer.new()
		column.add_child(control_heading)
		var control_name := _text(metadata.control_name, 14, MUTED)
		control_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control_heading.add_child(control_name)
		control_value = _text("", 16, CYAN)
		control_heading.add_child(control_value)
		control_slider = HSlider.new()
		control_slider.min_value = 0
		control_slider.max_value = metadata.max
		control_slider.step = 1
		control_slider.custom_minimum_size = Vector2(0, 26)
		control_slider.tooltip_text = metadata.control_name
		control_slider.value_changed.connect(_change_control.bind(metadata.control))
		column.add_child(control_slider)
	if selected_equipment in ["main_bus", "aux_bus"]:
		breaker_button = _new_button("", _toggle_breaker)
		breaker_button.add_theme_font_size_override("font_size", 14)
		breaker_button.custom_minimum_size.y = 34
		column.add_child(breaker_button)
	column.add_child(HSeparator.new())
	column.add_child(_text("CONNECTED EQUIPMENT", 12, MUTED))
	for link in metadata.links:
		var button := _new_button(link[2] + "  ›", navigate.bind(link[0], link[1]))
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
	var links: Array = []
	match current_system:
		"reactor": links = [["power", "reactor", "Inspect reactor controls"], ["cooling", "pump_a", "Explore reactor cooling"]]
		"propulsion": links = [["cooling", "main_engine", "Inspect main engine"], ["cooling", "pump_b", "Explore propulsion cooling"]]
		"sensors": links = [["power", "aux_bus", "Inspect auxiliary supply"]]
		_: links = [["power", "main_bus", "Inspect main electrical supply"]]
	var i := 0
	for link in links:
		var button := _button(link[2] + "  ›", Rect2(270 + i * 420, 644, 396, 48), navigate.bind(link[0], link[1]), workspace_layer)
		dependency_buttons.append(button)
		i += 1
	if current_system in ["life_support", "shielding", "sensors", "hull"]:
		_label("Summary model • detailed equipment and environmental simulation will be added here.", Rect2(270, 732, 1050, 46), 15, MUTED, workspace_layer, true)


func _refresh() -> void:
	if not is_instance_valid(supply_label):
		return
	supply_label.text = "%.0f / %.0f kW  •  %.0f spare" % [ship.reactor_output, ship.reactor_limit, maxf(0.0, ship.reactor_limit - ship.reactor_output)]
	cooling_label.text = "%.1f °C  /  %.1f °C" % [ship.coolant_temperature, ship.engine_temperature]
	var conditions: Array = ship.conditions()
	ship_status.text = "All systems nominal" if conditions.is_empty() else "%d condition%s to inspect" % [conditions.size(), "" if conditions.size() == 1 else "s"]
	ship_status.add_theme_color_override("font_color", GREEN if conditions.is_empty() else AMBER)
	running_label.text = "SIMULATION PAUSED" if ship.paused else "CRUISE CONFIGURATION  /  RUNNING"
	pause_button.text = "Resume [P]" if ship.paused else "Pause [P]"
	if current_system == "overview":
		view_description.text = "Live systems and connected machinery. Select a system to explore."
		for id in overview_labels:
			var summary: Dictionary = ship.system_summary(id)
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
	elif current_system in ["power", "cooling"]:
		view_description.text = "Generation, distribution, and connected loads" if current_system == "power" else "Coolant loops, heat transfer, and heat rejection"
		for id in equipment_labels:
			equipment_labels[id].text = _equipment_caption(id)
			equipment_labels[id].add_theme_color_override("font_color", _equipment_tone(id))
		_refresh_inspector()
	else:
		view_description.text = "Summary readings and connections"
		var summary: Dictionary = ship.system_summary(current_system)
		summary_value.text = summary.value
		summary_state.text = summary.state
		summary_state.add_theme_color_override("font_color", _tone(summary.tone))
		summary_detail.text = summary.detail
	if log_dialog.visible:
		_refresh_log()


func _refresh_inspector() -> void:
	if selected_equipment == "":
		return
	var reason: String = ship.equipment_reason(selected_equipment)
	var status: String = ship.equipment_status(selected_equipment)
	var warning: bool = status not in ["Online", "Idle", "Standby reference"]
	inspector_condition.text = status + (" • " + reason if warning and not reason.is_empty() else "")
	inspector_condition.add_theme_color_override("font_color", _equipment_tone(selected_equipment))
	var readings: Array = ship.readings(selected_equipment)
	for i in mini(readings.size(), reading_rows.size()):
		reading_rows[i].key.text = str(readings[i][0])
		reading_rows[i].value.text = str(readings[i][1])
	if control_slider != null:
		var meta: Dictionary = EQUIPMENT[selected_equipment]
		var value: float = float(ship.get(meta.control))
		control_slider.set_value_no_signal(value)
		control_slider.editable = not ship.paused
		control_value.text = "%.0f %s%s" % [value, meta.unit, "  (paused)" if ship.paused else ""]
	if breaker_button != null:
		var closed: bool = ship.bus_a_closed if selected_equipment == "main_bus" else ship.bus_b_closed
		breaker_button.text = "Open breaker / isolate bus" if closed else "Close breaker / restore bus"
		breaker_button.disabled = ship.paused


func _equipment_caption(id: String) -> String:
	match id:
		"reactor": return "%.0f / %.0f kW" % [ship.reactor_output, ship.reactor_limit]
		"main_bus": return "%.0f kW  •  %s" % [ship.bus_a_draw, "CLOSED" if ship.bus_a_closed else "OPEN"]
		"aux_bus": return "%.0f / %.0f kW" % [ship.bus_b_draw, ship.bus_b_limit]
		"battery": return "STANDBY / ISOLATED"
		"pump_a": return "%.1f / %.0f L/s" % [ship.pump_a_flow, ship.pump_a_command]
		"pump_b": return "%.1f / %.0f L/s" % [ship.pump_b_flow, ship.pump_b_command]
		"heat_exchanger": return "CORE  %.1f °C" % ship.main_temperature
		"main_engine": return "%.1f / %.0f %% thrust" % [ship.engine_thrust, ship.engine_command]
		"radiator": return "%.0f %%  •  %.0f kW" % [ship.radiator_command, ship.radiator_rejection]
	return ""


func _tone(name_text: String) -> Color:
	return AMBER if name_text == "warn" else (GREEN if name_text == "good" else MUTED)


func _equipment_tone(id: String) -> Color:
	var status: String = ship.equipment_status(id)
	if status == "Online":
		return CYAN
	return MUTED if status in ["Idle", "Standby reference"] else AMBER


func _inspect_condition() -> void:
	var conditions: Array = ship.conditions()
	if not conditions.is_empty():
		navigate(conditions[0].system, conditions[0].equipment)


func _change_control(value: float, id: String) -> void:
	ship.set_control(id, value)
	_refresh()


func _toggle_breaker() -> void:
	ship.toggle_breaker(selected_equipment)
	_refresh()


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
	if current_system not in ["power", "cooling"]:
		return
	draw_style_box(_style(Color("0c1a25")), Rect2(244, 350, 732, 520))
	for x in range(258, 968, 24):
		for y in range(360, 860, 24):
			draw_circle(Vector2(x, y), 0.7, Color("1e3443"))
	if current_system == "power":
		_line(PackedVector2Array([Vector2(452, 485), Vector2(482, 485), Vector2(482, 419), Vector2(514, 419)]), CYAN, ship.bus_a_draw > 0)
		_line(PackedVector2Array([Vector2(452, 485), Vector2(482, 485), Vector2(482, 627), Vector2(514, 627)]), CYAN, ship.bus_b_draw > 0)
		_line(PackedVector2Array([Vector2(712, 419), Vector2(770, 419)]), CYAN, ship.pump_a_power > 0)
		_line(PackedVector2Array([Vector2(712, 627), Vector2(770, 627)]), CYAN, ship.pump_b_power > 0)
	else:
		_line(PackedVector2Array([Vector2(452, 437), Vector2(514, 437)]), CYAN, ship.pump_a_flow > 0.01)
		_line(PackedVector2Array([Vector2(712, 437), Vector2(744, 437), Vector2(744, 525), Vector2(770, 525)]), AMBER, ship.pump_a_flow > 0.01)
		_line(PackedVector2Array([Vector2(452, 663), Vector2(514, 663)]), CYAN, ship.pump_b_flow > 0.01)
		_line(PackedVector2Array([Vector2(712, 663), Vector2(744, 663), Vector2(744, 573), Vector2(770, 573)]), AMBER, ship.pump_b_flow > 0.01)
		_line(PackedVector2Array([Vector2(866, 495), Vector2(866, 344), Vector2(252, 344), Vector2(252, 437), Vector2(266, 437)]), CYAN, ship.pump_a_flow > 0.01)
		_line(PackedVector2Array([Vector2(866, 601), Vector2(866, 764), Vector2(252, 764), Vector2(252, 663), Vector2(266, 663)]), CYAN, ship.pump_b_flow > 0.01)
