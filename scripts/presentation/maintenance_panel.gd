extends Control
## Service-life readings and maintenance actions for a single current runtime.
const ReliabilityChart = preload("res://scripts/presentation/reliability_chart.gd")
const TEXT = Color("e6f1f5")
const MUTED = Color("93acbb")
const CYAN = Color("5ed9df")
const AMBER = Color("f4c574")
signal close_requested
signal inspect_requested(system: String, equipment: String)
var ship
var presenter
var component_id: String = ""
var action_buttons: Dictionary = {}
var info_labels: Dictionary = {}
var failure_chart
var performance_chart
var status_label: Label
var progress: ProgressBar
var supply_button: Button
var result_label: Label
var inventory_label: Label
var job_label: Label
var pause_button: Button
var _surface: Panel
var _focus_controls: Array[Button] = []
var _last_component_event: String = ""


func configure(simulation, ship_presenter, id: String) -> void:
	ship = simulation
	presenter = ship_presenter
	component_id = id
	_last_component_event = _latest_component_event()
	_build()
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
	_label("SERVICE LIFE / " + ship.definition.component(component_id).display_name, Rect2(24, 18, 1000, 38), 27, TEXT)
	_label("Operating history, capability, and a safe route back to service.", Rect2(24, 61, 1000, 24), 16, MUTED)
	_button("×", Rect2(1080, 18, 46, 40), func(): close_requested.emit())
	var index: int = 0
	for item in [["running_hours", "LIFETIME OPERATING HOURS"], ["rated_life_hours", "NOMINAL SERVICE LIFE"], ["service_age_hours", "WEAR-PART AGE / EQUIVALENT H"], ["efficiency", "FLOW EFFICIENCY"]]:
		var x: float = 24 + index * 278
		_label(item[1], Rect2(x, 102, 265, 20), 12, MUTED)
		info_labels[item[0]] = _label("", Rect2(x, 127, 265, 34), 25, CYAN)
		index += 1
	performance_chart = ReliabilityChart.new()
	performance_chart.mode = "performance"
	_place(performance_chart, Rect2(24, 184, 666, 240), _surface)
	failure_chart = ReliabilityChart.new()
	failure_chart.mode = "failure"
	_place(failure_chart, Rect2(24, 438, 666, 240), _surface)
	_label("MAINTENANCE", Rect2(714, 184, 412, 24), 14, CYAN)
	status_label = _label("", Rect2(714, 215, 412, 76), 16, TEXT, true)
	job_label = _label("", Rect2(714, 301, 412, 23), 14, MUTED)
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", _box(Color("08121c")))
	progress.add_theme_stylebox_override("fill", _box(Color("327c80")))
	_place(progress, Rect2(714, 331, 412, 10), _surface)
	inventory_label = _label("", Rect2(714, 353, 412, 23), 14, MUTED)
	action_buttons.patch = _button("Field patch · 10 s · 1 kit", Rect2(714, 388, 412, 39), _act.bind("patch"))
	action_buttons.replace = _button("Replace wear parts · 30 s · 1 spare", Rect2(714, 437, 412, 39), _act.bind("replace"))
	action_buttons.cancel = _button("Cancel work", Rect2(714, 486, 198, 36), _act.bind("cancel"))
	pause_button = _button("Pause", Rect2(924, 486, 202, 36), _toggle_pause)
	supply_button = _button("Inspect electrical supply ›", Rect2(714, 534, 412, 38), _inspect_supply)
	action_buttons.simulate_wear = _button("Try worn-pump condition", Rect2(714, 593, 412, 38), _act.bind("simulate_wear"))
	_label("Sandbox setup: advance this pump's history to a worn condition.", Rect2(714, 639, 412, 42), 12, MUTED, true)
	result_label = _label("", Rect2(24, 696, 1102, 27), 14, AMBER)
	_label("Illustrative gameplay estimates. White dot: current condition; amber line: nominal life. Bands are capability ranges, not confidence intervals.\nWear-part age is load-weighted equivalent hours; compensating with a higher flow request ages parts faster.\nReplacing wear parts resets their age while preserving this component's lifetime operating hours.", Rect2(24, 727, 1102, 50), 12, MUTED, true)
	# Keyboard focus stays on a visible dialog control instead of an obscured
	# inspector control. Escape closes through the owning console.
	pause_button.grab_focus()


func refresh() -> void:
	var info: Dictionary = ship.maintenance_info(component_id)
	var clock_available: bool = ship.components[component_id].kind not in ["battery", "coolant"]
	info_labels.running_hours.text = "%.1f h" % float(info.running_hours) if clock_available else "Not tracked"
	info_labels.rated_life_hours.text = "%.0f h" % float(info.rated_life_hours) if info.rated_life_hours > 0 else "Not rated"
	info_labels.service_age_hours.text = "%.1f eq h" % float(info.service_age_hours) if info.supported else "—"
	info_labels.efficiency.text = "%.1f%%" % (float(info.efficiency) * 100.0) if info.supported else "—"
	if info.failed:
		info_labels.efficiency.text = "FAILED"
	var profile: Array = ship.reliability_profile(component_id)
	performance_chart.update_profile(profile, info)
	failure_chart.update_profile(profile, info)
	status_label.text = str(info.reason)
	if not info.supported:
		status_label.text = "Operating history is recorded when this equipment is active. No repair or reliability model is authored for this type."
		if not clock_available:
			status_label.text = "This passive or reference component has no active operating-hour counter or maintenance model."
	job_label.text = "No work in progress"
	if not str(info.job).is_empty():
		job_label.text = "%s · %.1f s remaining%s" % [str(info.job).capitalize(), float(info.job_remaining), " · paused" if ship.paused else (" · awaiting isolation" if not info.isolated else "")]
	elif info.failed:
		job_label.text = "Failed · replacement required"
	elif info.patch_remaining_hours > 0:
		job_label.text = "Temporary patch · %.1f operating h left" % float(info.patch_remaining_hours)
	else:
		job_label.text = "Isolate supply before starting work" if info.supported and not info.isolated else ("Isolated · ready for maintenance" if info.supported else "No lifetime prediction available")
	progress.value = 100.0 * (1.0 - float(info.job_remaining) / maxf(float(info.job_duration), 0.001)) if not str(info.job).is_empty() else 0.0
	inventory_label.text = "%d patch kits  ·  %d replacement spares" % [info.patches, info.spares]
	for action in action_buttons:
		var state: Dictionary = info.actions.get(action, {"enabled": false, "reason": "Not supported for this equipment."})
		action_buttons[action].disabled = ship.paused or not state.enabled
		action_buttons[action].tooltip_text = "Simulation is paused." if ship.paused else str(state.reason)
		if not action_buttons[action].disabled:
			var descriptions: Dictionary = {
				"patch": "Restore at least 85% flow efficiency for 100 operating hours. Age and failure risk remain.",
				"replace": "Restore full efficiency and renew the wear parts. Lifetime operating hours remain.",
				"cancel": "Stop this job. The patch kit or spare already used is not refunded.",
				"simulate_wear": "Sandbox setup: advance only this pump's operating history and wear-part age. Ship time does not advance.",
			}
			action_buttons[action].tooltip_text = descriptions[action]
	pause_button.text = "Resume [P]" if ship.paused else "Pause [P]"
	supply_button.disabled = _supply_link().is_empty()
	var event: String = _latest_component_event()
	if event != _last_component_event:
		_last_component_event = event
		result_label.text = event
		result_label.tooltip_text = event
	result_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result_label.clip_text = true


func _latest_component_event() -> String:
	var name_prefix: String = str(ship.definition.component(component_id).display_name) + ":"
	for index in range(ship.events.size() - 1, -1, -1):
		var event: String = str(ship.events[index])
		if event.begins_with(name_prefix) or event.begins_with("Maintenance rejected:"):
			return event
	return ""


func _input(event: InputEvent) -> void:
	if not is_inside_tree() or not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_requested.emit()
	elif event.keycode == KEY_P:
		get_viewport().set_input_as_handled()
		_toggle_pause()
	elif event.keycode == KEY_TAB:
		# Keep keyboard navigation inside the overlay, including when a running
		# job or pause changes which actions are available.
		var choices: Array[Button] = []
		for button in _focus_controls:
			if not button.disabled and button.is_visible_in_tree():
				choices.append(button)
		if not choices.is_empty():
			var current: int = choices.find(get_viewport().gui_get_focus_owner())
			var next: int = posmod(current + (-1 if event.shift_pressed else 1), choices.size())
			choices[next].grab_focus()
		get_viewport().set_input_as_handled()


func _act(action: String) -> void:
	var result: Dictionary = ship.maintenance_command(component_id, action)
	result_label.text = str(result.reason)
	refresh()


func _toggle_pause() -> void:
	ship.toggle_pause()
	refresh()


func _supply_link() -> Dictionary:
	for link in presenter.links(component_id):
		if str(link.label).begins_with("Supply:"):
			return link
	return {}


func _inspect_supply() -> void:
	var link: Dictionary = _supply_link()
	if not link.is_empty():
		inspect_requested.emit(str(link.system), str(link.equipment))


func _place(control: Control, rect: Rect2, parent: Node) -> void:
	parent.add_child(control)
	control.position = rect.position
	control.size = rect.size


func _label(value: String, rect: Rect2, font_size: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place(label, rect, _surface)
	return label


func _button(value: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("65808e"))
	button.add_theme_stylebox_override("normal", _box(Color("152d3b")))
	button.add_theme_stylebox_override("hover", _box(Color("214657"), CYAN))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), CYAN))
	button.add_theme_stylebox_override("disabled", _box(Color("101c26")))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	_place(button, rect, _surface)
	_focus_controls.append(button)
	return button


func _box(color: Color, border: Color = Color("294050")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	return box
