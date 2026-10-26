extends VBoxContainer
## Connection editing shares the equipment inspector; the schematic stays usable.
const TEXT = Color("e6f1f5")
const MUTED = Color("93acbb")
const CYAN = Color("5ed9df")
const GREEN = Color("78e2af")
const AMBER = Color("f4c574")
signal close_requested
signal inspect_requested(system: String, equipment: String)
signal selection_changed(source_id: String, circuit_id: String)
var ship
var presenter
var source_selector: OptionButton
var target_selector: OptionButton
var action_buttons: Dictionary = {}
var pump_buttons: Dictionary = {}
var info_labels: Dictionary = {}
var flow_slider: HSlider
var status_label: Label
var result_label: Label
var job_label: Label
var requirements_label: Label
var action_reason: Label
var progress: ProgressBar
var _source_id: String = ""
var _circuit_id: String = ""
var _last_selection: Dictionary = {}
var _last_event: String = ""
var _pump_links: VBoxContainer
var _linked_pumps: Array[String] = []


func configure(simulation, ship_presenter, selection: Dictionary = {}) -> void:
	ship = simulation
	presenter = ship_presenter
	_source_id = str(selection.get("source_id", ""))
	_circuit_id = str(selection.get("circuit_id", ""))
	_last_event = str(ship.events.back()) if not ship.events.is_empty() else ""
	_build()
	_validate_selection()
	var info: Dictionary = ship.bypass_info()
	if info.installed or not str(info.job).is_empty():
		_source_id = str(info.source_id)
		_circuit_id = str(info.circuit_id)
	_last_selection = selected_endpoints()
	refresh()


func _build() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_label("COOLANT CONNECTION", 12, CYAN)
	info_labels.route = _label("Install bypass", 23, TEXT)
	info_labels.capacity = _label("", 13, MUTED)
	_label("Donor coupling", 13, MUTED)
	source_selector = _selector()
	source_selector.item_selected.connect(func(index): set_source(str(source_selector.get_item_metadata(index))))
	_label("Destination coupling", 13, MUTED)
	target_selector = _selector()
	target_selector.item_selected.connect(func(index): set_target(str(target_selector.get_item_metadata(index))))
	status_label = _label("", 14, TEXT)
	info_labels.flow = _label("", 18, GREEN)
	info_labels.split = _label("", 13, MUTED)
	info_labels.request = _label("", 14, CYAN)
	flow_slider = HSlider.new()
	flow_slider.min_value = 0.0
	flow_slider.max_value = float(ship.bypass_info().capacity)
	flow_slider.step = 1.0
	flow_slider.custom_minimum_size.y = 24
	flow_slider.tooltip_text = "Reserve donor flow for this circuit. Only the remainder reaches the donor's native circuit."
	flow_slider.value_changed.connect(func(value): _send("set_flow", {"flow": value}))
	add_child(flow_slider)
	action_buttons.open = _button("Open bypass valve", _send.bind("open", {}))
	action_buttons.close = _button("Close bypass valve", _send.bind("close", {}))
	requirements_label = _label("", 13, MUTED)
	action_buttons.install = _button("Install kit · 10 s", _install)
	action_buttons.remove = _button("Remove & recover kit · 10 s", _send.bind("remove", {}))
	action_buttons.cancel = _button("Cancel work", _send.bind("cancel", {}))
	action_reason = _label("", 13, AMBER)
	job_label = _label("", 13, MUTED)
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 8
	progress.add_theme_stylebox_override("background", _box(Color("08121c")))
	progress.add_theme_stylebox_override("fill", _box(Color("327c80")))
	add_child(progress)
	_pump_links = VBoxContainer.new()
	_pump_links.add_theme_constant_override("separation", 4)
	add_child(_pump_links)
	result_label = _label("", 13, AMBER)
	_button("Back to equipment", func(): close_requested.emit())


func refresh() -> void:
	if not is_instance_valid(status_label):
		return
	var info: Dictionary = ship.bypass_info(_source_id, _circuit_id)
	var working: bool = not str(info.job).is_empty()
	var fixed: bool = info.installed or working
	if fixed:
		_source_id = str(info.source_id)
		_circuit_id = str(info.circuit_id)
	_validate_selection()
	_fill_selectors(info)
	source_selector.disabled = fixed
	target_selector.disabled = fixed or _source_id.is_empty()
	info_labels.route.text = "Bypass · " + ("OPEN" if info.open else "CLOSED") if info.installed else "Install bypass"
	info_labels.capacity.text = "Rated %.0f L/s · %d kit%s available" % [float(info.capacity), int(info.kits), "" if int(info.kits) == 1 else "s"]
	status_label.text = str(info.reason)
	info_labels.flow.text = "Delivered %.1f L/s" % float(info.delivered_flow)
	info_labels.split.text = "Donor %.1f · native circuit %.1f L/s" % [float(info.source_flow), float(info.source_remaining_flow)]
	if float(info.get("unallocated_flow", 0.0)) > 0.01:
		info_labels.split.text += " · %.1f unused" % float(info.unallocated_flow)
	info_labels.request.text = "Divert %.0f / %.0f L/s rated" % [float(info.requested_flow), float(info.capacity)]
	for key in ["flow", "split", "request"]:
		info_labels[key].visible = info.installed
	flow_slider.visible = info.installed
	flow_slider.set_value_no_signal(float(info.requested_flow))
	flow_slider.editable = info.installed and not working and not ship.paused
	for action in action_buttons:
		var control: Dictionary = info.actions.get(action, {"enabled": false, "reason": "Action unavailable."})
		action_buttons[action].disabled = not control.enabled
		action_buttons[action].tooltip_text = str(control.reason)
	action_buttons.install.visible = not info.installed and not working
	action_buttons.remove.visible = info.installed and not working
	action_buttons.open.visible = info.installed and not info.open and not working
	action_buttons.close.visible = info.installed and info.open and not working
	action_buttons.cancel.visible = working
	_refresh_prerequisites(info)
	var next_action: String = "cancel" if working else ("remove" if info.installed else "install")
	var reason: String = str(info.actions[next_action].reason)
	if info.installed and not info.open and not info.actions.open.enabled and not working:
		reason = str(info.actions.open.reason)
	action_reason.text = reason
	action_reason.visible = not reason.is_empty() and reason != status_label.text
	job_label.text = "%s · %.1f s remaining%s" % [str(info.job).capitalize(), float(info.job_remaining), " · paused" if ship.paused else ""] if working else "One work station is shared with pump repairs."
	progress.visible = working
	progress.value = 100.0 * (1.0 - float(info.job_remaining) / maxf(float(info.job_duration), 0.001)) if working else 0.0
	_refresh_pump_links(info)
	var event: String = str(ship.events.back()) if not ship.events.is_empty() else ""
	if event != _last_event:
		_last_event = event
		result_label.text = event if event.begins_with("Bypass") else ""
	result_label.visible = not result_label.text.is_empty()
	_notify_selection()


func set_source(id: String) -> void:
	if _endpoints_locked():
		return
	_source_id = id
	_validate_selection()
	refresh()


func set_target(id: String) -> void:
	if _endpoints_locked():
		return
	_circuit_id = id
	_validate_selection()
	refresh()


func selected_endpoints() -> Dictionary:
	return {"source_id": _source_id, "circuit_id": _circuit_id}


func _endpoints_locked() -> bool:
	var info: Dictionary = ship.bypass_info()
	return info.installed or not str(info.job).is_empty()


func _validate_selection() -> void:
	var info: Dictionary = ship.bypass_info()
	if not info.pumps.any(func(pump): return pump.id == _source_id):
		_source_id = ""
	if _source_id.is_empty() or not info.circuits.any(func(circuit): return circuit.id == _circuit_id and circuit.pump != _source_id):
		_circuit_id = ""


func _fill_selectors(info: Dictionary) -> void:
	# Rebuild only when option identities change, preserving an open keyboard menu.
	var sources: Array[Dictionary] = [{"id": "", "name": "Choose on diagram…"}]
	for pump in info.pumps:
		sources.append({"id": str(pump.id), "name": str(pump.name)})
	var targets: Array[Dictionary] = [{"id": "", "name": "Choose compatible coupling…"}]
	for circuit in info.circuits:
		if not _source_id.is_empty() and circuit.pump != _source_id:
			targets.append({"id": str(circuit.id), "name": str(circuit.name)})
	_fill_selector(source_selector, sources, _source_id)
	_fill_selector(target_selector, targets, _circuit_id)


func _fill_selector(selector: OptionButton, choices: Array[Dictionary], selected: String) -> void:
	var changed: bool = selector.item_count != choices.size()
	if not changed:
		for index in choices.size():
			if selector.get_item_metadata(index) != choices[index].id or selector.get_item_text(index) != choices[index].name:
				changed = true
				break
	if changed:
		selector.clear()
		for choice in choices:
			selector.add_item(str(choice.name))
			selector.set_item_metadata(selector.item_count - 1, str(choice.id))
	for index in selector.item_count:
		if selector.get_item_metadata(index) == selected:
			selector.select(index)
			break


func _refresh_prerequisites(info: Dictionary) -> void:
	var rows: Array[String] = []
	if not _source_id.is_empty() and not _circuit_id.is_empty():
		for circuit in info.circuits:
			if circuit.pump == _source_id or circuit.id == _circuit_id:
				rows.append("%s: power %s · primary %s" % [_pump_name(str(circuit.pump)), "isolated" if circuit.electrically_isolated else "connected", "closed" if not circuit.primary_open else "open"])
	if not rows.is_empty():
		rows.push_front("Fitting / removal isolation")
	requirements_label.text = "\n".join(rows)
	requirements_label.visible = not rows.is_empty()


func _refresh_pump_links(info: Dictionary) -> void:
	var wanted: Array[String] = []
	if not _source_id.is_empty():
		wanted.append(_source_id)
	for circuit in info.circuits:
		if circuit.id == _circuit_id and circuit.pump not in wanted:
			wanted.append(str(circuit.pump))
	if wanted == _linked_pumps:
		return
	_linked_pumps = wanted
	for child in _pump_links.get_children():
		_pump_links.remove_child(child)
		child.queue_free()
	pump_buttons.clear()
	for id in wanted:
		pump_buttons[id] = _button(_pump_name(id) + " controls ›", _inspect_pump.bind(id), _pump_links)


func _notify_selection() -> void:
	var current: Dictionary = selected_endpoints()
	if current == _last_selection:
		return
	_last_selection = current.duplicate(true)
	selection_changed.emit(_source_id, _circuit_id)


func _install() -> void:
	_send("install", selected_endpoints())


func _send(action: String, payload: Dictionary) -> void:
	var result: Dictionary = ship.bypass_command(action, payload)
	result_label.text = str(result.reason)
	refresh()


func _inspect_pump(id: String) -> void:
	inspect_requested.emit(ship.definition.workspace_for(id), id)


func _pump_name(id: String) -> String:
	var spec = ship.definition.component(id)
	return str(spec.short_name if not spec.short_name.is_empty() else spec.display_name) if spec != null else "No donor"


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
	return label


func _button(value: String, callback: Callable, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = value
	_style_button(button)
	button.pressed.connect(callback)
	(parent if parent != null else self).add_child(button)
	return button


func _selector() -> OptionButton:
	var selector := OptionButton.new()
	_style_button(selector)
	selector.clip_text = true
	add_child(selector)
	return selector


func _style_button(button: Button) -> void:
	button.custom_minimum_size.y = 32
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	box.set_corner_radius_all(5)
	box.content_margin_left = 8
	box.content_margin_right = 8
	return box
