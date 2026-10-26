extends Control
## Navigation and presentation over the independent ship simulation.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Presenter = preload("res://scripts/presentation/ship_presenter.gd")
const ShipCatalog = preload("res://scripts/ship_catalog.gd")
const MaintenancePanel = preload("res://scripts/presentation/maintenance_panel.gd")
const CoolantBypassPanel = preload("res://scripts/presentation/coolant_bypass_panel.gd")
const EquipmentControls = preload("res://scripts/presentation/equipment_controls.gd")
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
var _ship_sessions: Dictionary = {}
var ship_selector: OptionButton
var current_system: String = "overview"
var selected_equipment: String = ""
var history: Array[Dictionary] = []
var nav_buttons: Dictionary = {}
var overview_buttons: Dictionary = {}
var equipment_buttons: Dictionary = {}
var equipment_list_buttons: Dictionary = {}
var dependency_buttons: Array[Button] = []
var _dependency_container: VBoxContainer
var _dependency_links: Array[Dictionary] = []
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
var inspector_close_button: Button
var maintenance_button: Button
var maintenance_panel: Control
var bypass_button: Button
var bypass_panel: Control
var _bypass_choices: Dictionary = {}
var inspector_controls
var quick_controls
var bypass_mode: bool = false
var inspector_mode: String = "equipment"
var coupling_buttons: Dictionary = {}
var route_button: Button
var _quick_extra: float = 0.0
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
	_ship_sessions[ship.definition.id] = ship
	_build_console()


func select_ship(ship_id: String) -> bool:
	var definition: Resource = null
	for candidate in ShipCatalog.DEFINITIONS:
		if candidate.id == ship_id:
			definition = candidate
			break
	if definition == null:
		return false
	if ship.definition.id == ship_id:
		return true
	var next_ship = _ship_sessions.get(ship_id)
	if next_ship == null:
		next_ship = Simulation.new(definition)
	if not next_ship.validation_errors.is_empty():
		return false
	_ship_sessions[ship.definition.id] = ship
	_ship_sessions[ship_id] = next_ship
	ship = next_ship
	presenter = Presenter.new(ship)
	current_system = "overview"
	selected_equipment = ""
	history.clear()
	refresh_remaining = 0.0
	_build_console()
	return true


func _build_console() -> void:
	_release_inspector()
	bypass_mode = false
	inspector_mode = "equipment"
	_clear(self)
	nav_buttons.clear()
	get_window().title = "Chief Engineer / " + ship.definition.display_name
	_build_shell()
	_build_view()
	_refresh()


func _on_ship_selected(index: int) -> void:
	if select_ship(str(ship_selector.get_item_metadata(index))):
		return
	# A rejected definition must not leave the menu naming an unloaded ship.
	ship_selector.select(-1)
	for item in range(ship_selector.item_count):
		if ship_selector.get_item_metadata(item) == ship.definition.id:
			ship_selector.select(item)
			break


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
	_style_button(button)
	button.pressed.connect(callback)
	return button


func _style_button(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_disabled_color", DIM)
	button.add_theme_stylebox_override("normal", _style(Color("152d3b")))
	button.add_theme_stylebox_override("hover", _style(Color("214657"), CYAN))
	button.add_theme_stylebox_override("pressed", _style(Color("2a5961"), CYAN))
	button.add_theme_stylebox_override("disabled", _style(Color("101c26")))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), CYAN, 2))


func _button(value: String, rect: Rect2, callback: Callable, parent: Node) -> Button:
	var button := _new_button(value, callback)
	_place(button, rect, parent)
	return button


func _build_shell() -> void:
	_label("C H I E F   E N G I N E E R", Rect2(26, 20, 700, 25), 14, CYAN, self)
	_label(ship.definition.display_name + " / Engineering", Rect2(24, 48, 800, 46), 34, TEXT, self)
	running_label = _label("", Rect2(900, 20, 508, 27), 14, MUTED, self)
	running_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ship_selector = OptionButton.new()
	_style_button(ship_selector)
	ship_selector.clip_text = true
	ship_selector.tooltip_text = "Switch ships. Each keeps its settings; only the selected ship advances."
	var selected_index: int = -1
	for definition in ShipCatalog.DEFINITIONS:
		var index: int = ship_selector.item_count
		ship_selector.add_item("Ship: " + definition.display_name)
		ship_selector.set_item_metadata(index, definition.id)
		var errors: Array[String] = definition.validate()
		if not errors.is_empty():
			ship_selector.set_item_disabled(index, true)
			ship_selector.set_item_tooltip(index, "Invalid ship configuration:\n" + "\n".join(errors))
		if definition.id == ship.definition.id:
			selected_index = index
	ship_selector.select(selected_index)
	ship_selector.item_selected.connect(_on_ship_selected)
	_place(ship_selector, Rect2(836, 59, 260, 42), self)
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
	elif system != "overview" and view.get("kind", "") != "workspace":
		for id in view.get("members", []):
			var spec = ship.definition.component(id)
			if spec != null and spec.inspectable:
				equipment = id
				break
	if current_system == system and selected_equipment == equipment and inspector_mode == "equipment":
		return
	history.append({"system": current_system, "equipment": selected_equipment})
	if history.size() > 32:
		history.pop_front()
	if current_system != system:
		bypass_mode = false
	current_system = system
	selected_equipment = equipment
	inspector_mode = "equipment"
	_build_view()
	_refresh()


func select_equipment(equipment: String) -> void:
	navigate(current_system, equipment)


func _deselect_equipment() -> void:
	if selected_equipment.is_empty():
		return
	history.append({"system": current_system, "equipment": selected_equipment})
	if history.size() > 32:
		history.pop_front()
	selected_equipment = ""
	inspector_mode = "equipment"
	_build_view()
	_refresh()

func _back() -> void:
	if history.is_empty():
		return
	var previous: Dictionary = history.pop_back()
	bypass_mode = false
	inspector_mode = "equipment"
	current_system = previous.system
	selected_equipment = previous.equipment
	_build_view()
	_refresh()


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _build_view() -> void:
	_release_inspector()
	_clear(workspace_layer)
	_clear(breadcrumb_layer)
	overview_buttons.clear()
	overview_labels.clear()
	equipment_buttons.clear()
	equipment_list_buttons.clear()
	equipment_labels.clear()
	dependency_buttons.clear()
	_dependency_container = null
	_dependency_links.clear()
	reading_rows.clear()
	control_widgets.clear()
	coupling_buttons.clear()
	quick_controls = null
	inspector_controls = null
	route_button = null
	_quick_extra = 0.0
	control_slider = null
	control_value = null
	breaker_button = null
	inspector_title = null
	inspector_condition = null
	inspector_close_button = null
	maintenance_button = null
	bypass_button = null
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
	if inspector_mode == "bypass":
		_label("›  Coolant bypass", Rect2(704, 218, 700, 30), 14, MUTED, breadcrumb_layer)
	elif not selected_equipment.is_empty():
		_label("›  " + ship.definition.component(selected_equipment).display_name, Rect2(704, 218, 700, 30), 14, MUTED, breadcrumb_layer)
	for id in nav_buttons:
		nav_buttons[id].add_theme_stylebox_override("normal", _style(Color("214452") if id == current_system else Color("152735"), CYAN if id == current_system else BORDER))
	view_title = _label("Ship overview" if current_system == "overview" else str(view.name), Rect2(244, 264, 710, 44), 32, TEXT, workspace_layer)
	view_description = _label("", Rect2(246, 313, 720, 28), 16, MUTED, workspace_layer)
	if current_system == "overview":
		_build_overview()
	else:
		_build_workspace()
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
	var view: Dictionary = ship.definition.view(current_system)
	var coolant_view: bool = _is_cooling_view(current_system)
	if coolant_view and ship.bypass_info().supported:
		view_title.size.x = 440
		bypass_button = _button("Install / inspect bypass", Rect2(718, 272, 250, 34), open_bypass, workspace_layer)
		bypass_button.add_theme_font_size_override("font_size", 15)
	if not selected_equipment.is_empty() and _base_nodes().has(selected_equipment):
		quick_controls = EquipmentControls.new()
		workspace_layer.add_child(quick_controls)
		quick_controls.configure(ship, presenter, selected_equipment, true)
		_quick_extra = quick_controls.get_combined_minimum_size().y + 10.0
		if _quick_extra <= 10.0:
			quick_controls.queue_free()
			quick_controls = null
			_quick_extra = 0.0
	var layout: Dictionary = _workspace_nodes()
	for id in layout:
		var spec = ship.definition.component(id)
		var rect: Rect2 = layout[id]
		# Selection is separate from controls; pressing the card never actuates it.
		var card := _button("", rect, select_equipment.bind(str(id)), workspace_layer)
		card.tooltip_text = "Inspect " + spec.display_name + " in this view"
		if id == selected_equipment:
			card.add_theme_stylebox_override("normal", _style(Color("214452"), CYAN, 2))
		equipment_buttons[id] = card
		_label(str(spec.definition.kind).replace("_", " ").to_upper(), Rect2(12, 8, rect.size.x - 24, 18), 11, MUTED, card)
		_label(spec.short_name if not spec.short_name.is_empty() else spec.display_name, Rect2(12, 30, rect.size.x - 24, 28), 19, TEXT, card)
		equipment_labels[id] = _label("", Rect2(12, 66, rect.size.x - 24, 25), 13, CYAN, card)
		if id == selected_equipment and is_instance_valid(quick_controls):
			quick_controls.reparent(card)
			quick_controls.position = Vector2(8, 100)
			quick_controls.size.x = rect.size.x - 16
		if bypass_mode:
			_add_coupling(id, card, rect)
	if view.get("kind", "") != "workspace":
		summary_value = _label("", Rect2(246, 315, 310, 26), 16, CYAN, workspace_layer)
		summary_state = _label("", Rect2(566, 315, 400, 26), 15, GREEN, workspace_layer)
		summary_detail = view_description
		view_description.hide()
	_build_inspector()
	if coolant_view and ship.bypass_info().supported:
		route_button = _button("", Rect2(440, 830, 330, 32), open_bypass, workspace_layer)
		route_button.add_theme_font_size_override("font_size", 13)
	_refresh_couplings()


func _is_cooling_view(id: String) -> bool:
	var view: Dictionary = ship.definition.view(id)
	return view.get("kind", "") == "workspace" and view.get("members", []).any(func(member):
		return ship.components.has(member) and ship.components[member].kind in ["pump", "heat_exchanger", "radiator"])


func _base_nodes() -> Dictionary:
	var visible: Dictionary = {}
	var authored: Dictionary = ship.definition.layouts.get(current_system, {}).get("nodes", {})
	for id in authored:
		var spec = ship.definition.component(id)
		if spec != null and spec.inspectable:
			visible[id] = authored[id]
	if ship.definition.view(current_system).get("kind", "") == "workspace":
		return visible
	# Summary departments use the same inspector and a small local connection view.
	var ids: Array[String] = []
	for member in ship.definition.view(current_system).get("members", []):
		var spec = ship.definition.component(member)
		if spec != null and spec.inspectable and member not in ids:
			ids.append(member)
		for link in presenter.links(member):
			if link.equipment not in ids:
				ids.append(link.equipment)
	for i in mini(ids.size(), 6):
		visible[ids[i]] = Rect2(266 + (i % 3) * 238, 380 + floori(i / 3.0) * 210, 210, 106)
	return visible

func _workspace_nodes() -> Dictionary:
	var layout: Dictionary = _base_nodes()
	if layout.is_empty():
		return layout
	var first: float = INF
	var last: float = -INF
	var base_height: float = 0.0
	for rect in layout.values():
		first = minf(first, rect.position.y)
		last = maxf(last, rect.position.y)
		base_height = maxf(base_height, rect.size.y)
	var port_space: float = 34.0 if bypass_mode else 0.0
	var selected_y: float = layout[selected_equipment].position.y if layout.has(selected_equipment) else INF
	# Reserve room for the selected card's controls; preserve authored columns
	# and row order, with connections routed against the same expanded geometry.
	var bottom: float = (818.0 if _is_cooling_view(current_system) and ship.bypass_info().supported else 850.0) - base_height - port_space - _quick_extra
	for id in layout:
		var rect: Rect2 = layout[id]
		if _quick_extra > 0.0 or port_space > 0.0:
			var original_y: float = rect.position.y
			rect.position.y = lerpf(360.0, maxf(360.0, bottom), (original_y - first) / maxf(1.0, last - first))
			if original_y > selected_y:
				rect.position.y += _quick_extra
			rect.size.y += port_space + (_quick_extra if id == selected_equipment else 0.0)
		layout[id] = rect
	return layout


func _add_coupling(id: String, card: Button, rect: Rect2) -> void:
	var info: Dictionary = ship.bypass_info()
	for pump in info.pumps:
		if pump.id == id:
			var button := _coupling_button("Outlet coupling", _choose_coupling.bind("source", id), card, rect)
			coupling_buttons["source:" + id] = button
	for circuit in info.circuits:
		if circuit.service_component == id:
			var button := _coupling_button("Circuit coupling", _choose_coupling.bind("target", str(circuit.id)), card, rect)
			coupling_buttons["target:" + str(circuit.id)] = button


func _coupling_button(label: String, callback: Callable, card: Button, rect: Rect2) -> Button:
	var button := _new_button(label, callback)
	button.add_theme_font_size_override("font_size", 12)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box: StyleBoxFlat = button.get_theme_stylebox(state).duplicate()
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		button.add_theme_stylebox_override(state, box)
	_place(button, Rect2(8, rect.size.y - 30, rect.size.x - 16, 26), card)
	return button


func _choose_coupling(kind: String, id: String) -> void:
	if inspector_mode != "bypass":
		open_bypass()
	if not is_instance_valid(bypass_panel):
		return
	if kind == "source":
		bypass_panel.set_source(id)
	else:
		bypass_panel.set_target(id)


func _refresh_couplings() -> void:
	var info: Dictionary = ship.bypass_info()
	var choices: Dictionary = _bypass_choices.get(ship.definition.id, {})
	for key in coupling_buttons:
		var button: Button = coupling_buttons[key]
		button.disabled = ship.paused or info.installed or not str(info.job).is_empty()
		if str(key).begins_with("target:"):
			for circuit in info.circuits:
				if key == "target:" + str(circuit.id):
					button.disabled = button.disabled or str(choices.get("source_id", "")).is_empty() or circuit.pump == choices.get("source_id")
	if is_instance_valid(route_button):
		route_button.visible = info.installed or (bypass_mode and not str(choices.get("source_id", "")).is_empty() and not str(choices.get("circuit_id", "")).is_empty())
		route_button.text = "Bypass: %.1f / %.1f L/s · %s" % [info.delivered_flow, info.capacity, "OPEN" if info.open else "CLOSED"] if info.installed else "Proposed bypass · inspect / fit"
		# Place the connection's selectable badge in a free route lane.
		if route_button.visible:
			route_button.position = Vector2(440, 833)

func _build_inspector() -> void:
	_panel(Rect2(990, 264, 418, 606), workspace_layer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_place(scroll, Rect2(1008, 279, 382, 572), workspace_layer)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	if inspector_mode == "bypass":
		bypass_panel = CoolantBypassPanel.new()
		column.add_child(bypass_panel)
		bypass_panel.close_requested.connect(close_bypass)
		bypass_panel.inspect_requested.connect(_inspect_bypass_equipment)
		bypass_panel.selection_changed.connect(_bypass_selection_changed)
		bypass_panel.configure(ship, presenter, _bypass_choices.get(ship.definition.id, {}))
		_bypass_choices[ship.definition.id] = bypass_panel.selected_endpoints()
		return
	if selected_equipment.is_empty():
		column.add_child(_text("EQUIPMENT", 12, MUTED))
		column.add_child(_text("Select equipment", 24, TEXT, true))
		column.add_child(_text("Select a diagram block or an entry below. Its controls stay in this view.", 14, MUTED, true))
		var ids: Array = ship.definition.view(current_system).get("members", []).duplicate()
		for id in _base_nodes():
			if id not in ids:
				ids.append(id)
		for id in ids:
			var member = ship.definition.component(id)
			if member == null or not member.inspectable or equipment_list_buttons.has(id):
				continue
			var button := _new_button(member.display_name, select_equipment.bind(str(id)))
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.clip_text = true
			button.tooltip_text = member.display_name
			button.custom_minimum_size.y = 40
			column.add_child(button)
			equipment_list_buttons[id] = button
		if equipment_list_buttons.is_empty():
			column.add_child(_text("No inspectable equipment in this department.", 14, MUTED, true))
		return
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var tag := _text("EQUIPMENT · " + str(ship.definition.view(current_system).get("name", "")), 12, MUTED)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(tag)
	inspector_close_button = _new_button("×", _deselect_equipment)
	heading.add_child(inspector_close_button)
	var spec = ship.definition.component(selected_equipment)
	inspector_title = _text(spec.display_name, 25, TEXT, true)
	column.add_child(inspector_title)
	inspector_condition = _text("", 14, GREEN, true)
	column.add_child(inspector_condition)
	inspector_controls = EquipmentControls.new()
	column.add_child(inspector_controls)
	inspector_controls.configure(ship, presenter, selected_equipment)
	control_widgets = inspector_controls.widgets
	for widget in control_widgets:
		if widget.has("slider") and control_slider == null:
			control_slider = widget.slider
			control_value = widget.value
		elif widget.has("button") and breaker_button == null:
			breaker_button = widget.button
	if ship.maintenance_info(selected_equipment).supported:
		column.add_child(HSeparator.new())
		maintenance_panel = MaintenancePanel.new()
		column.add_child(maintenance_panel)
		maintenance_panel.inspect_requested.connect(_inspect_maintenance_supply)
		maintenance_panel.configure(ship, presenter, selected_equipment)
		maintenance_button = maintenance_panel.details_button
	column.add_child(HSeparator.new())
	column.add_child(_text("LIVE READINGS", 12, MUTED))
	for reading in presenter.readings(selected_equipment):
		var row := HBoxContainer.new()
		column.add_child(row)
		var key := _text(str(reading[0]), 14, MUTED)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		var value := _text(str(reading[1]), 14, TEXT)
		row.add_child(value)
		reading_rows.append({"key": key, "value": value})
	column.add_child(_text(spec.description, 13, MUTED, true))
	column.add_child(HSeparator.new())
	column.add_child(_text("CONNECTED EQUIPMENT", 12, MUTED))
	_dependency_container = VBoxContainer.new()
	column.add_child(_dependency_container)
	_refresh_dependency_links(true)

func _refresh_dependency_links(force: bool = false) -> void:
	if not is_instance_valid(_dependency_container) or selected_equipment.is_empty():
		return
	var connected: Array[Dictionary] = presenter.links(selected_equipment)
	if not force and connected == _dependency_links:
		return
	_dependency_links = connected.duplicate(true)
	_clear(_dependency_container)
	dependency_buttons.clear()
	if connected.is_empty():
		_dependency_container.add_child(_text("No active connections", 14, MUTED))
	for link in connected:
		var button := _new_button(link.label + "  ›", select_equipment.bind(str(link.equipment)))
		button.add_theme_font_size_override("font_size", 14)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 32
		_dependency_container.add_child(button)
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
		view_description.text = "Live systems and connected machinery. Select a system to operate."
		for id in overview_labels:
			var summary: Dictionary = presenter.system_summary(id)
			var labels: Dictionary = overview_labels[id]
			labels.state.text = summary.state
			labels.state.add_theme_color_override("font_color", _tone(summary.tone))
			labels.value.text = summary.value
			labels.detail.text = summary.detail + "   ›"
		conditions_label.text = "Standing watch • no active limitations" if conditions.is_empty() else str(conditions[0].text)
		conditions_label.add_theme_color_override("font_color", MUTED if conditions.is_empty() else AMBER)
		condition_button.visible = not conditions.is_empty() and not str(conditions[0].system).is_empty()
		conditions_label.visible = not condition_button.visible
		if condition_button.visible:
			condition_button.text = str(conditions[0].text) + "   •   Inspect ›"
	else:
		var view: Dictionary = ship.definition.view(current_system)
		view_description.text = str(view.get("description", "Live readings and connections"))
		for id in equipment_labels:
			equipment_labels[id].text = presenter.caption(id)
			equipment_labels[id].add_theme_color_override("font_color", _equipment_tone(id))
		if is_instance_valid(summary_value):
			var summary: Dictionary = presenter.system_summary(current_system)
			summary_value.text = summary.value
			summary_state.text = summary.state
			summary_state.add_theme_color_override("font_color", _tone(summary.tone))
		_refresh_inspector()
		if is_instance_valid(quick_controls):
			quick_controls.refresh()
		_refresh_couplings()
	if log_dialog.visible:
		_refresh_log()
	if is_instance_valid(maintenance_panel):
		maintenance_panel.refresh()
	if is_instance_valid(bypass_panel):
		bypass_panel.refresh()

func _refresh_inspector() -> void:
	if selected_equipment.is_empty() or inspector_mode == "bypass":
		return
	_refresh_dependency_links()
	var reason: String = presenter.equipment_reason(selected_equipment)
	var status: String = presenter.equipment_status(selected_equipment)
	var warning: bool = status not in ["Online", "Idle", "Standby reference"]
	inspector_condition.text = status + (" • " + reason if warning and not reason.is_empty() else "")
	inspector_condition.add_theme_color_override("font_color", _equipment_tone(selected_equipment))
	var readings: Array = presenter.readings(selected_equipment)
	for i in mini(readings.size(), reading_rows.size()):
		reading_rows[i].key.text = str(readings[i][0])
		reading_rows[i].value.text = str(readings[i][1])
	if is_instance_valid(inspector_controls):
		inspector_controls.refresh()

func _tone(name_text: String) -> Color:
	return AMBER if name_text == "warn" else (GREEN if name_text == "good" else MUTED)


func _equipment_tone(id: String) -> Color:
	var status: String = presenter.equipment_status(id)
	if status == "Online":
		return CYAN
	return MUTED if status in ["Idle", "Standby reference"] else AMBER

func _inspect_condition() -> void:
	var conditions: Array = presenter.conditions()
	if not conditions.is_empty() and not str(conditions[0].system).is_empty():
		navigate(conditions[0].system, conditions[0].equipment)

func _pause() -> void:
	ship.toggle_pause()
	_refresh()


func _reset_ship() -> void:
	_release_inspector()
	bypass_mode = false
	inspector_mode = "equipment"
	_bypass_choices.erase(ship.definition.id)
	ship.reset()
	_build_view()
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
			if inspector_mode == "bypass" or bypass_mode:
				close_bypass()
			elif is_instance_valid(maintenance_panel) and maintenance_panel.details_visible():
				close_maintenance()
			else:
				_back()

func open_maintenance(id: String) -> void:
	if not ship.components.has(id) or not ship.definition.component(id).inspectable or not ship.maintenance_info(id).supported:
		return
	select_equipment(id)
	if is_instance_valid(maintenance_panel):
		maintenance_panel.set_details_visible(true)

func close_maintenance() -> void:
	if is_instance_valid(maintenance_panel):
		maintenance_panel.set_details_visible(false)

func _inspect_maintenance_supply(_system: String, equipment: String) -> void:
	select_equipment(equipment)

func open_bypass() -> void:
	if not ship.bypass_info().supported:
		return
	if not _is_cooling_view(current_system):
		for view in ship.definition.views:
			if _is_cooling_view(view.id):
				navigate(view.id)
				break
	bypass_mode = true
	inspector_mode = "bypass"
	_build_view()
	_refresh()

func close_bypass() -> void:
	_release_inspector()
	bypass_mode = false
	inspector_mode = "equipment"
	_build_view()
	_refresh()


func _release_inspector() -> void:
	if is_instance_valid(bypass_panel):
		_bypass_choices[bypass_panel.ship.definition.id] = bypass_panel.selected_endpoints()
	bypass_panel = null
	maintenance_panel = null


func _bypass_selection_changed(source_id: String, circuit_id: String) -> void:
	_bypass_choices[ship.definition.id] = {"source_id": source_id, "circuit_id": circuit_id}
	_refresh_couplings()
	queue_redraw()

func _inspect_bypass_equipment(_system: String, equipment: String) -> void:
	select_equipment(equipment)

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
	if current_system == "overview":
		return
	draw_style_box(_style(Color("0c1a25")), Rect2(244, 350, 732, 520))
	for x in range(258, 968, 24):
		for y in range(360, 860, 24):
			draw_circle(Vector2(x, y), 0.7, Color("1e3443"))
	var layout: Dictionary = _workspace_nodes()
	for edge in presenter.schematic_edges(layout.keys()):
		var points: PackedVector2Array = _route_edge(layout[edge.from_component], layout[edge.to_component], layout)
		_line(points, GREEN if edge.get("bypass", false) else (AMBER if edge.domain == "thermal" else CYAN), edge.active)

	if bypass_mode and not ship.bypass_info().installed:
		var choice: Dictionary = _bypass_choices.get(ship.definition.id, {})
		var source: String = str(choice.get("source_id", ""))
		for circuit in ship.bypass_info().circuits:
			if circuit.id == choice.get("circuit_id") and layout.has(source) and layout.has(circuit.service_component):
				var path: PackedVector2Array = _route_edge(layout[source], layout[circuit.service_component], layout)
				for i in range(path.size() - 1):
					draw_dashed_line(path[i], path[i + 1], AMBER, 3, 7, true)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _is_cooling_view(current_system) or not ship.bypass_info().installed:
		return
	var layout: Dictionary = _workspace_nodes()
	for edge in presenter.schematic_edges(layout.keys()):
		if not edge.get("bypass", false):
			continue
		var path: PackedVector2Array = _route_edge(layout[edge.from_component], layout[edge.to_component], layout)
		for i in range(path.size() - 1):
			if event.position.distance_to(Geometry2D.get_closest_point_to_segment(event.position, path[i], path[i + 1])) <= 8.0:
				open_bypass()
				accept_event()
				return


func _route_edge(source: Rect2, destination: Rect2, layout: Dictionary) -> PackedVector2Array:
	# Connect to the machinery readings, not to the middle of expanded controls.
	var start: Vector2 = Vector2(source.get_center().x, source.position.y + minf(53.0, source.size.y * 0.5))
	var finish: Vector2 = Vector2(destination.get_center().x, destination.position.y + minf(53.0, destination.size.y * 0.5))
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
			var lane: float = 356 if use_top else 862
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
