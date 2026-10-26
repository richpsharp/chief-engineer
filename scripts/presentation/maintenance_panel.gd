extends VBoxContainer
## Routine service stays in the equipment inspector; charts expand in place.
const ReliabilityChart = preload("res://scripts/presentation/reliability_chart.gd")
const TEXT = Color("e6f1f5")
const MUTED = Color("93acbb")
const CYAN = Color("5ed9df")
const AMBER = Color("f4c574")
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
var details_button: Button
var details: VBoxContainer
var _last_component_event: String = ""


func configure(simulation, ship_presenter, id: String) -> void:
	ship = simulation
	presenter = ship_presenter
	component_id = id
	_last_component_event = _latest_component_event()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	add_child(HSeparator.new())
	add_child(_label("MAINTENANCE", 13, CYAN))
	job_label = _label("", 14, TEXT)
	add_child(job_label)
	status_label = _label("", 13, MUTED)
	add_child(status_label)
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 8
	progress.add_theme_stylebox_override("background", _box(Color("08121c")))
	progress.add_theme_stylebox_override("fill", _box(Color("327c80")))
	add_child(progress)
	inventory_label = _label("", 12, MUTED)
	add_child(inventory_label)
	action_buttons.patch = _button("Field patch · 10 s · 1 kit", _act.bind("patch"))
	action_buttons.replace = _button("Replace wear parts · 30 s · 1 spare", _act.bind("replace"))
	action_buttons.cancel = _button("Cancel work", _act.bind("cancel"))
	result_label = _label("", 12, AMBER)
	add_child(result_label)
	details_button = _button("Service history & reliability ▸", func(): set_details_visible(not details.visible))
	details = VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	add_child(details)
	for item in [["running_hours", "Lifetime running"], ["rated_life_hours", "Reference life"], ["service_age_hours", "Wear-part age"], ["efficiency", "Flow efficiency"]]:
		var row := HBoxContainer.new()
		details.add_child(row)
		var key: Label = _label(item[1], 13, MUTED)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		var value: Label = _label("", 13, TEXT)
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(value)
		info_labels[item[0]] = value
	performance_chart = ReliabilityChart.new()
	performance_chart.mode = "performance"
	performance_chart.custom_minimum_size = Vector2(0, 200)
	details.add_child(performance_chart)
	failure_chart = ReliabilityChart.new()
	failure_chart.mode = "failure"
	failure_chart.custom_minimum_size = Vector2(0, 200)
	details.add_child(failure_chart)
	details.add_child(_label("Illustrative gameplay estimates, not guaranteed expiry dates. Wear-part age is load-weighted; replacing parts preserves lifetime running hours.", 12, MUTED))
	supply_button = _button("Select electrical supply ›", _inspect_supply, details)
	action_buttons.simulate_wear = _button("Try worn-pump condition", _act.bind("simulate_wear"), details)
	details.add_child(_label("Sandbox setup: advances only this pump's history.", 12, MUTED))
	set_details_visible(false)
	refresh()


func set_details_visible(expanded: bool) -> void:
	details.visible = expanded
	details_button.text = "Service history & reliability ▾" if expanded else "Service history & reliability ▸"
	if expanded:
		refresh()


func details_visible() -> bool:
	return is_instance_valid(details) and details.visible


func refresh() -> void:
	var info: Dictionary = ship.maintenance_info(component_id)
	info_labels.running_hours.text = "%.1f h" % float(info.running_hours)
	info_labels.rated_life_hours.text = "%.0f h" % float(info.rated_life_hours)
	info_labels.service_age_hours.text = "%.1f eq h" % float(info.service_age_hours)
	info_labels.efficiency.text = "FAILED" if info.failed else "%.1f%%" % (float(info.efficiency) * 100.0)
	if details.visible:
		var profile: Array = ship.reliability_profile(component_id)
		performance_chart.update_profile(profile, info)
		failure_chart.update_profile(profile, info)
	var active: bool = not str(info.job).is_empty()
	job_label.text = "%s · %.1f s remaining%s" % [str(info.job).capitalize(), float(info.job_remaining), " · paused" if ship.paused else (" · awaiting isolation" if not info.isolated else "")] if active else ("Failed · replacement required" if info.failed else "Efficiency %.1f%%" % (float(info.efficiency) * 100.0))
	if info.patch_remaining_hours > 0 and not active:
		job_label.text += " · patch %.1f h left" % float(info.patch_remaining_hours)
	status_label.text = str(info.reason)
	if not active and not info.actions.replace.enabled:
		status_label.text = str(info.actions.replace.reason)
	progress.visible = active
	progress.value = 100.0 * (1.0 - float(info.job_remaining) / maxf(float(info.job_duration), 0.001)) if active else 0.0
	inventory_label.text = "%d patch kits · %d spare sets" % [info.patches, info.spares]
	for action in action_buttons:
		var availability: Dictionary = info.actions[action]
		action_buttons[action].disabled = not availability.enabled
		action_buttons[action].tooltip_text = str(availability.reason)
	action_buttons.cancel.visible = active
	supply_button.disabled = _supply_link().is_empty()
	var event: String = _latest_component_event()
	if event != _last_component_event:
		_last_component_event = event
		result_label.text = event
	result_label.visible = not result_label.text.is_empty()


func _latest_component_event() -> String:
	var name_prefix: String = str(ship.definition.component(component_id).display_name) + ":"
	for index in range(ship.events.size() - 1, -1, -1):
		var event: String = str(ship.events[index])
		if event.begins_with(name_prefix) or event.begins_with("Maintenance rejected:"):
			return event
	return ""


func _act(action: String) -> void:
	var result: Dictionary = ship.maintenance_command(component_id, action)
	result_label.text = str(result.reason)
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


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(value: String, callback: Callable, parent: Node = self) -> Button:
	var button := Button.new()
	button.text = value
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("65808e"))
	button.add_theme_stylebox_override("normal", _box(Color("152d3b")))
	button.add_theme_stylebox_override("hover", _box(Color("214657"), CYAN))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), CYAN))
	button.add_theme_stylebox_override("disabled", _box(Color("101c26")))
	button.custom_minimum_size.y = 32
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _box(color: Color, border: Color = Color("294050")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box
