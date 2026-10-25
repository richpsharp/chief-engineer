extends Control
## A player-installed circulation connection, with previews from committed state.
const TEXT = Color("e6f1f5")
const MUTED = Color("93acbb")
const CYAN = Color("5ed9df")
const GREEN = Color("78e2af")
const AMBER = Color("f4c574")
signal close_requested
signal inspect_requested(system: String, equipment: String)
var ship
var presenter
var source_selector: OptionButton
var target_selector: OptionButton
var action_buttons: Dictionary = {}
var primary_buttons: Dictionary = {}
var supply_buttons: Dictionary = {}
var pump_buttons: Dictionary = {}
var info_labels: Dictionary = {}
var flow_slider: HSlider
var status_label: Label
var result_label: Label
var job_label: Label
var progress: ProgressBar
var pause_button: Button
var _surface: Panel
var _circuit_labels: Dictionary = {}
var _focus_controls: Array[Control] = []
var _last_event: String = ""


func configure(simulation, ship_presenter, selection: Dictionary = {}) -> void:
	ship = simulation
	presenter = ship_presenter
	_last_event = str(ship.events.back()) if not ship.events.is_empty() else ""
	_build()
	_select_value(source_selector, str(selection.get("source_id", "")))
	_selection_changed(source_selector.selected)
	_select_value(target_selector, str(selection.get("circuit_id", "")))
	_selection_changed(source_selector.selected)
	refresh()


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.03, 0.045, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_surface = Panel.new()
	_surface.add_theme_stylebox_override("panel", _box(Color("101f2c")))
	_place(_surface, Rect2(145, 55, 1150, 790), self)
	_label("PLAYER-INSTALLED COOLANT BYPASS", Rect2(24, 18, 1000, 38), 26, TEXT)
	_label("Choose service couplings, isolate the machinery, then fit and commission a rated kit.", Rect2(24, 63, 1040, 24), 15, MUTED)
	_button("×", Rect2(1080, 18, 46, 40), func(): close_requested.emit())
	_label("DONOR PUMP / OUTLET COUPLING", Rect2(24, 105, 300, 20), 12, MUTED)
	_label("DESTINATION / CIRCUIT COUPLING", Rect2(354, 105, 336, 20), 12, MUTED)
	source_selector = _selector(Rect2(24, 133, 310, 38))
	target_selector = _selector(Rect2(354, 133, 336, 38))
	var info: Dictionary = ship.bypass_info()
	for pump in info.pumps:
		source_selector.add_item(str(pump.name))
		source_selector.set_item_metadata(source_selector.item_count - 1, str(pump.id))
	for circuit in info.circuits:
		target_selector.add_item(str(circuit.name))
		target_selector.set_item_metadata(target_selector.item_count - 1, str(circuit.id))
	source_selector.item_selected.connect(_selection_changed)
	target_selector.item_selected.connect(func(_index): refresh())
	_selection_changed(0)
	status_label = _label("", Rect2(24, 189, 666, 70), 16, TEXT, true)
	_label("CIRCUIT ISOLATION & SUPPLIES", Rect2(24, 271, 666, 20), 13, CYAN)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_place(scroll, Rect2(24, 305, 666, 373), _surface)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	for circuit in info.circuits:
		var card := Panel.new()
		card.custom_minimum_size = Vector2(650, 161)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _box(Color("0c1924")))
		column.add_child(card)
		var title := _label(str(circuit.name), Rect2(14, 10, 620, 28), 19, TEXT, false, card)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_circuit_labels[circuit.id] = _label("", Rect2(14, 43, 620, 48), 14, MUTED, true, card)
		primary_buttons[circuit.id] = _button("", Rect2(14, 106, 194, 39), _toggle_primary.bind(str(circuit.id)), card)
		supply_buttons[circuit.pump] = _button("Electrical supply ›", Rect2(220, 106, 200, 39), _inspect_supply.bind(str(circuit.pump)), card)
		pump_buttons[circuit.pump] = _button("Pump controls ›", Rect2(432, 106, 200, 39), _inspect_pump.bind(str(circuit.pump)), card)
	_label("BYPASS KIT", Rect2(714, 105, 412, 20), 13, CYAN)
	info_labels.route = _label("", Rect2(714, 132, 412, 54), 18, TEXT, true)
	info_labels.capacity = _label("", Rect2(714, 191, 412, 24), 14, MUTED)
	info_labels.flow = _label("", Rect2(714, 229, 412, 28), 20, GREEN)
	info_labels.split = _label("", Rect2(714, 264, 412, 46), 14, MUTED, true)
	info_labels.request = _label("", Rect2(714, 321, 412, 23), 14, CYAN)
	flow_slider = HSlider.new()
	flow_slider.min_value = 0.0
	flow_slider.max_value = float(info.capacity)
	flow_slider.step = 1.0
	flow_slider.tooltip_text = "Flow reserved for the destination, up to the kit rating. Only the remaining donor flow is available to its native circuit."
	_place(flow_slider, Rect2(714, 350, 412, 27), _surface)
	flow_slider.value_changed.connect(func(value): _send("set_flow", {"flow": value}))
	_focus_controls.append(flow_slider)
	action_buttons.install = _button("Install kit · 10 s", Rect2(714, 395, 412, 38), _install)
	action_buttons.open = _button("Open bypass", Rect2(714, 443, 198, 38), _send.bind("open", {}))
	action_buttons.close = _button("Close bypass", Rect2(924, 443, 202, 38), _send.bind("close", {}))
	action_buttons.remove = _button("Remove & recover kit · 10 s", Rect2(714, 491, 412, 38), _send.bind("remove", {}))
	action_buttons.cancel = _button("Cancel work", Rect2(714, 539, 198, 38), _send.bind("cancel", {}))
	pause_button = _button("Pause [P]", Rect2(924, 539, 202, 38), _toggle_pause)
	job_label = _label("", Rect2(714, 597, 412, 48), 14, MUTED, true)
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", _box(Color("08121c")))
	progress.add_theme_stylebox_override("fill", _box(Color("327c80")))
	_place(progress, Rect2(714, 661, 412, 10), _surface)
	result_label = _label("", Rect2(24, 697, 1102, 24), 14, AMBER)
	result_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result_label.clip_text = true
	_label("Installation and removal require both endpoint pumps electrically isolated and both primary valves closed.\nThe kit includes supply, return, and isolation fittings. Circuit members share one circulation flow; flow is not duplicated.\nActive bypass lines are green. Close the bypass before restoring the destination's primary valve.", Rect2(24, 731, 1102, 48), 12, MUTED, true)
	pause_button.grab_focus()


func refresh() -> void:
	if not is_instance_valid(status_label):
		return
	var info: Dictionary = ship.bypass_info(_selected(source_selector), _selected(target_selector))
	var fixed: bool = info.installed or not str(info.job).is_empty()
	if fixed:
		_select_value(source_selector, str(info.source_id))
		_select_value(target_selector, str(info.circuit_id))
	source_selector.disabled = fixed or ship.paused
	target_selector.disabled = fixed or ship.paused
	status_label.text = str(info.reason)
	var source_name: String = _pump_name(str(info.source_id)) if info.installed else source_selector.get_item_text(source_selector.selected)
	var target_name: String = _circuit_name(str(info.circuit_id), info.circuits) if info.installed else target_selector.get_item_text(target_selector.selected)
	info_labels.route.text = ("OPEN · " if info.open else "CLOSED · ") + source_name + " → " + target_name if info.installed else "Uninstalled · choose connection points"
	info_labels.capacity.text = "Kit rating %.0f L/s  ·  %d kit%s available" % [float(info.capacity), int(info.kits), "" if int(info.kits) == 1 else "s"]
	info_labels.flow.text = "Bypass delivers %.1f L/s" % float(info.delivered_flow)
	info_labels.split.text = "Donor %.1f L/s available\n%.1f L/s remains for its native circuit" % [float(info.source_flow), float(info.source_remaining_flow)]
	if float(info.get("unallocated_flow", 0.0)) > 0.01:
		info_labels.split.text = "Donor %.1f L/s available\nNative %.1f L/s · unused %.1f L/s" % [float(info.source_flow), float(info.source_remaining_flow), float(info.unallocated_flow)]
	info_labels.request.text = "Requested diversion: %.0f / %.0f L/s rated" % [float(info.requested_flow), float(info.capacity)]
	flow_slider.set_value_no_signal(float(info.requested_flow))
	flow_slider.editable = info.installed and str(info.job).is_empty() and not ship.paused
	for circuit in info.circuits:
		if not primary_buttons.has(circuit.id):
			continue
		var button: Button = primary_buttons[circuit.id]
		button.text = "Primary: OPEN · close" if circuit.primary_open else "Primary: CLOSED · open"
		var action: String = "close" if circuit.primary_open else "open"
		var control: Dictionary = circuit.get("actions", {}).get(action, {"enabled": true, "reason": ""})
		button.disabled = ship.paused or not control.enabled
		button.tooltip_text = "Simulation is paused." if ship.paused else str(control.reason)
		_circuit_labels[circuit.id].text = "%s · power %s\nDelivered %.1f L/s (primary %.1f + bypass %.1f) · cruise reference %.0f" % [_pump_name(str(circuit.pump)), "ISOLATED" if circuit.electrically_isolated else "CONNECTED", float(circuit.delivered_flow), float(circuit.primary_flow), float(circuit.bypass_flow), float(circuit.reference_flow)]
		var link: Dictionary = _supply_link(str(circuit.pump))
		supply_buttons[circuit.pump].disabled = link.is_empty()
	for action in action_buttons:
		var state: Dictionary = info.actions.get(action, {"enabled": false, "reason": "Action unavailable."})
		action_buttons[action].disabled = ship.paused or not state.enabled
		action_buttons[action].tooltip_text = "Simulation is paused." if ship.paused else str(state.reason)
	pause_button.text = "Resume [P]" if ship.paused else "Pause [P]"
	job_label.text = "%s · %.1f s remaining%s" % [str(info.job).capitalize(), float(info.job_remaining), " · paused" if ship.paused else ""] if not str(info.job).is_empty() else "One shared work station. The kit is recovered after safe removal."
	progress.value = 100.0 * (1.0 - float(info.job_remaining) / maxf(float(info.job_duration), 0.001)) if not str(info.job).is_empty() else 0.0
	var event: String = str(ship.events.back()) if not ship.events.is_empty() else ""
	if event != _last_event:
		_last_event = event
		result_label.text = event
		result_label.tooltip_text = event


func _selection_changed(_index: int) -> void:
	var info: Dictionary = ship.bypass_info()
	var source: String = _selected(source_selector)
	for index in range(target_selector.item_count):
		var target: String = str(target_selector.get_item_metadata(index))
		var same_circuit := false
		for circuit in info.circuits:
			if circuit.id == target:
				same_circuit = circuit.pump == source
		target_selector.set_item_disabled(index, same_circuit)
	if target_selector.selected < 0 or target_selector.is_item_disabled(target_selector.selected):
		for index in range(target_selector.item_count):
			if not target_selector.is_item_disabled(index):
				target_selector.select(index)
				break
	refresh()


func _install() -> void:
	_send("install", {"source_id": _selected(source_selector), "circuit_id": _selected(target_selector)})


func _toggle_primary(id: String) -> void:
	for circuit in ship.bypass_info().circuits:
		if circuit.id == id:
			_send("set_primary", {"circuit_id": id, "open": not circuit.primary_open})
			return


func _send(action: String, payload: Dictionary) -> void:
	var result: Dictionary = ship.bypass_command(action, payload)
	result_label.text = str(result.reason)
	result_label.tooltip_text = str(result.reason)
	refresh()


func _inspect_supply(pump_id: String) -> void:
	var link: Dictionary = _supply_link(pump_id)
	if not link.is_empty():
		inspect_requested.emit(str(link.system), str(link.equipment))


func _inspect_pump(id: String) -> void:
	inspect_requested.emit(ship.definition.workspace_for(id), id)


func _supply_link(pump_id: String) -> Dictionary:
	for link in presenter.links(pump_id):
		if str(link.label).begins_with("Supply:"):
			return link
	return {}


func _pump_name(id: String) -> String:
	var spec = ship.definition.component(id)
	return str(spec.short_name if not spec.short_name.is_empty() else spec.display_name) if spec != null else "No donor"


func _circuit_name(id: String, circuits: Array) -> String:
	for circuit in circuits:
		if circuit.id == id:
			return str(circuit.name)
	return "No destination"


func _selected(selector: OptionButton) -> String:
	return str(selector.get_item_metadata(selector.selected)) if selector.selected >= 0 else ""


func selected_endpoints() -> Dictionary:
	return {"source_id": _selected(source_selector), "circuit_id": _selected(target_selector)}


func _select_value(selector: OptionButton, value: String) -> void:
	for index in range(selector.item_count):
		if str(selector.get_item_metadata(index)) == value:
			selector.select(index)
			return


func _toggle_pause() -> void:
	ship.toggle_pause()
	refresh()


func _input(event: InputEvent) -> void:
	if not is_inside_tree() or not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if source_selector.get_popup().visible or target_selector.get_popup().visible:
		return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_requested.emit()
	elif event.keycode == KEY_P:
		get_viewport().set_input_as_handled()
		_toggle_pause()
	elif event.keycode == KEY_TAB:
		var choices: Array[Control] = []
		for control in _focus_controls:
			if not control.is_visible_in_tree():
				continue
			if control is BaseButton and control.disabled:
				continue
			if control is Slider and not control.editable:
				continue
			choices.append(control)
		if not choices.is_empty():
			var current: int = choices.find(get_viewport().gui_get_focus_owner())
			choices[posmod(current + (-1 if event.shift_pressed else 1), choices.size())].grab_focus()
		get_viewport().set_input_as_handled()


func _place(control: Control, rect: Rect2, parent: Node) -> void:
	parent.add_child(control)
	control.position = rect.position
	control.size = rect.size


func _label(value: String, rect: Rect2, font_size: int, color: Color, wrap: bool = false, parent: Node = null) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place(label, rect, _surface if parent == null else parent)
	return label


func _button(value: String, rect: Rect2, callback: Callable, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = value
	_style_button(button)
	button.pressed.connect(callback)
	_place(button, rect, _surface if parent == null else parent)
	_focus_controls.append(button)
	return button


func _selector(rect: Rect2) -> OptionButton:
	var selector := OptionButton.new()
	_style_button(selector)
	_place(selector, rect, _surface)
	_focus_controls.append(selector)
	return selector


func _style_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("65808e"))
	button.add_theme_stylebox_override("normal", _box(Color("152d3b")))
	button.add_theme_stylebox_override("hover", _box(Color("214657"), CYAN))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), CYAN))
	button.add_theme_stylebox_override("disabled", _box(Color("101c26")))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _box(color: Color, border: Color = Color("294050")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	return box
