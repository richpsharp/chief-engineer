extends VBoxContainer
## The same addressed operating actions in a node and the equipment inspector.
const TEXT = Color("e6f1f5")
const MUTED = Color("93acbb")
const CYAN = Color("5ed9df")
const BORDER = Color("294050")

var ship
var presenter
var component_id: String = ""
var compact: bool = false
var widgets: Array[Dictionary] = []
var buttons: Dictionary = {}
var sliders: Dictionary = {}
var feeder_id: String = ""
var shared_feeder: bool = false
var circuit_id: String = ""
var _restriction: Label


func configure(simulation, ship_presenter, id: String, use_compact: bool = false) -> void:
	ship = simulation
	presenter = ship_presenter
	component_id = id
	compact = use_compact
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4 if compact else 6)
	for descriptor in ship.definition.component(id).controls():
		var action: String = str(descriptor.id)
		if descriptor.get("kind", "numeric") == "toggle":
			var button: Button = _button(_toggle_control.bind(component_id, action))
			widgets.append({"descriptor": descriptor, "button": button})
			buttons[action] = button
		else:
			var header := HBoxContainer.new()
			add_child(header)
			var label: Label = _label(str(descriptor.label))
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			header.add_child(label)
			var value: Label = _label("")
			value.add_theme_color_override("font_color", CYAN)
			header.add_child(value)
			# Narrow nodes shorten only the label; authored control semantics stay.
			if compact:
				label.text = {"flow": "Request", "limit": "Limit", "thrust": "Command", "deployment": "Deploy"}.get(action, str(descriptor.label))
			label.tooltip_text = str(descriptor.label)
			var slider := HSlider.new()
			slider.min_value = float(descriptor.get("min", 0.0))
			slider.max_value = float(descriptor.get("max", 100.0))
			slider.step = float(descriptor.get("step", 1.0))
			slider.custom_minimum_size.y = 20 if compact else 26
			slider.tooltip_text = str(descriptor.label)
			if ship.components[id].kind == "pump" and action == "flow":
				slider.tooltip_text = "Nominal flow request. Zero flow does not isolate electrical power or coolant. Wear and available power constrain delivery."
			slider.value_changed.connect(_set_control.bind(action))
			add_child(slider)
			sliders[action] = slider
			widgets.append({"descriptor": descriptor, "slider": slider, "value": value})
	if ship.components[id].kind == "pump":
		feeder_id = _nearest_breaker(id)
		if not feeder_id.is_empty():
			shared_feeder = _has_other_consumers(feeder_id)
			buttons.feeder = _button(_toggle_control.bind(feeder_id, "closed"))
			if compact and shared_feeder:
				buttons.feeder.custom_minimum_size.y = 44
		for circuit in ship.bypass_info().get("circuits", []):
			if circuit.pump == id:
				circuit_id = str(circuit.id)
				buttons.primary = _button(_toggle_primary)
				break
	if not compact:
		_restriction = _label("")
		_restriction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_restriction)
	refresh()


func refresh() -> void:
	if ship == null or not ship.components.has(component_id):
		return
	var settings: Dictionary = ship.components[component_id].settings
	for widget in widgets:
		var descriptor: Dictionary = widget.descriptor
		var value = settings.get(descriptor.id, descriptor.get("default", 0))
		if widget.has("slider"):
			widget.slider.set_value_no_signal(float(value))
			widget.slider.editable = not ship.paused
			widget.value.text = "%.0f %s" % [float(value), descriptor.get("unit", "")]
		else:
			widget.button.text = ("Breaker: " + ("CLOSED" if value else "OPEN")) if descriptor.id == "closed" else str(descriptor.label) + (": ON" if value else ": OFF")
			widget.button.tooltip_text = "Open breaker to isolate downstream power." if value else "Close breaker to reconnect downstream power."
			widget.button.disabled = ship.paused
	if buttons.has("feeder"):
		var connected: bool = bool(ship.components[feeder_id].settings.get("closed", true))
		buttons.feeder.text = ("Feeder: " if compact else ship.definition.component(feeder_id).display_name + ": ") + ("ON · isolate" if connected else "OFF · connect")
		buttons.feeder.tooltip_text = ship.definition.component(feeder_id).display_name + (": breaker closed; open to isolate this pump." if connected else ": breaker open; close to restore this pump's supply.")
		if shared_feeder:
			var spec = ship.definition.component(feeder_id)
			var short_name: String = spec.short_name if not spec.short_name.is_empty() else spec.display_name
			buttons.feeder.text = (short_name + "\n" if compact else spec.display_name + ": ") + ("ON · shared supply" if connected else "OFF · shared supply")
			buttons.feeder.tooltip_text = "This breaker controls " + spec.display_name + " and every load downstream, including other systems."
		buttons.feeder.disabled = ship.paused
	var restriction: String = "Simulation is paused." if ship.paused else ""
	if buttons.has("primary"):
		for circuit in ship.bypass_info().get("circuits", []):
			if circuit.id != circuit_id:
				continue
			var action: String = "close" if circuit.primary_open else "open"
			var availability: Dictionary = circuit.actions[action]
			buttons.primary.text = ("Valve: " if compact else "Primary coolant valve: ") + ("OPEN · close" if circuit.primary_open else "CLOSED · open")
			buttons.primary.disabled = not availability.enabled
			buttons.primary.tooltip_text = str(availability.reason) if not availability.enabled else "Change only the primary coolant valve. The pump's electrical feeder is a separate control."
			if not availability.enabled and not ship.paused:
				restriction = str(availability.reason)
	if is_instance_valid(_restriction):
		if shared_feeder:
			restriction += ("\n" if not restriction.is_empty() else "") + "Shared supply: opening this breaker disconnects all downstream equipment."
		_restriction.text = restriction
		_restriction.visible = not restriction.is_empty()


func _nearest_breaker(id: String) -> String:
	var incoming: Dictionary = {}
	for edge in ship.presentation_connections():
		if edge.domain == "power":
			incoming[edge.to_component] = edge.from_component
	var cursor: String = id
	var seen: Dictionary = {}
	while incoming.has(cursor) and not seen.has(cursor):
		seen[cursor] = true
		cursor = str(incoming[cursor])
		if ship.components[cursor].kind == "bus" and not ship.components[cursor].control("closed").is_empty():
			return cursor
	return ""


func _has_other_consumers(source_id: String) -> bool:
	var pending: Array[String] = [source_id]
	var seen: Dictionary = {}
	var edges: Array = ship.presentation_connections()
	while not pending.is_empty():
		var cursor: String = pending.pop_back()
		if seen.has(cursor):
			continue
		seen[cursor] = true
		for edge in edges:
			if edge.domain != "power" or edge.from_component != cursor:
				continue
			if edge.to_component != component_id and ship.components[edge.to_component].kind != "bus":
				return true
			pending.append(str(edge.to_component))
	return false


func _set_control(value: float, action: String) -> void:
	ship.command(component_id, action, value)


func _toggle_control(id: String, action: String) -> void:
	ship.command(id, action, not bool(ship.components[id].settings.get(action, false)))


func _toggle_primary() -> void:
	for circuit in ship.bypass_info().get("circuits", []):
		if circuit.id == circuit_id:
			ship.bypass_command("set_primary", {"circuit_id": circuit_id, "open": not circuit.primary_open})
			return


func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 12 if compact else 14)
	label.add_theme_color_override("font_color", MUTED)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(callback: Callable) -> Button:
	var button := Button.new()
	button.add_theme_font_size_override("font_size", 12 if compact else 14)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("65808e"))
	button.add_theme_stylebox_override("normal", _box(Color("152d3b")))
	button.add_theme_stylebox_override("hover", _box(Color("214657"), CYAN))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), CYAN))
	button.add_theme_stylebox_override("disabled", _box(Color("101c26")))
	button.custom_minimum_size.y = 28 if compact else 32
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	add_child(button)
	return button


func _box(color: Color, border: Color = BORDER) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 5 if compact else 8
	box.content_margin_right = 5 if compact else 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box
