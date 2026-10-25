extends SceneTree
## Exercises navigation and the power -> coolant -> thrust dependency through
## the real scene controls. Add -- --capture to a graphical run for screenshots.

const MainScene = preload("res://scenes/main.tscn")
const CAPTURE_DIR = "res://.tools/captures"
var console
var checks: int = 0
var failures: int = 0
var capture_requested: bool = false


func _initialize() -> void:
	capture_requested = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	console = MainScene.instantiate()
	root.add_child(console)
	current_scene = console
	# Advance only with explicit ticks so renders and navigation do not alter
	# the measurements under test.
	console.set_process(false)
	await process_frame
	await process_frame
	_check(console.current_system == "overview" and console.overview_buttons.size() == 8,
		"The healthy ship opens with eight overview systems.")
	_check(console.presenter.conditions().is_empty(), "The ship starts without active limitations.")
	_tick(3600.0)
	_check(console.presenter.conditions().is_empty() and is_equal_approx(_s("main_engine", "thrust"), 30.0),
		"An unattended healthy ship remains operational for a simulated hour.")
	await _capture("overview.png")
	await _click_at_center(console.overview_buttons["power"])
	_check(console.current_system == "power", "A real mouse click reaches a card through the workspace layer.")
	_press(console.nav_buttons["overview"])

	var initial_state: Dictionary = _state()
	var all_pages_opened := true
	for view in console.ship.definition.views:
		var id: String = view.id
		_press(console.nav_buttons[id])
		all_pages_opened = all_pages_opened and console.current_system == id
	_check(all_pages_opened, "All eight departments have reachable pages.")
	var all_inspectors_valid := true
	for spec in console.ship.definition.components:
		if not spec.inspectable:
			continue
		var id: String = spec.id
		_press(console.nav_buttons[console.ship.definition.workspace_for(id)])
		_press(console.equipment_buttons[id])
		all_inspectors_valid = all_inspectors_valid and console.selected_equipment == id
		all_inspectors_valid = all_inspectors_valid and console.inspector_title.text != "" and not console.reading_rows.is_empty()
	_check(all_inspectors_valid, "All nine equipment inspectors have titles and live readings.")
	_check(_state() == initial_state, "Exploring pages and equipment does not mutate the ship.")

	_press(console.nav_buttons["power"])
	_press(console.equipment_buttons["aux_bus"])
	_check(console.control_slider.value == 40.0 and console.breaker_button != null,
		"Auxiliary bus exposes its healthy capacity setting and breaker.")
	await _capture("power.png")
	_follow_link("pump_b")
	_check(console.current_system == "cooling" and console.selected_equipment == "pump_b",
		"The auxiliary bus supply link opens cooling pump B.")
	await _capture("cooling.png")
	_press(console.back_button)
	_check(console.current_system == "power" and console.selected_equipment == "aux_bus",
		"Back restores the previous workspace and selected equipment.")

	console.control_slider.value = 24.0
	_check(_setting("aux_bus", "limit") == 40.0, "A slider command waits for the next fixed step.")
	_tick(0.1)
	_check(_setting("aux_bus", "limit") == 24.0, "The fixed step commits the inspector command.")
	_tick(120.0)
	_follow_link("pump_b")
	_check(_near(_s("pump_b", "power"), 6.0) and _near(_s("pump_b", "flow"), 15.0),
		"The shared auxiliary limit leaves 6 kW and 15 L/s for pump B.")
	_check(not console.presenter.equipment_reason("pump_b").is_empty() and console.inspector_condition.text != "",
		"The pump inspector explains its reduced performance.")
	_follow_link("main_engine")
	_check(console.selected_equipment == "main_engine" and _near(_s("main_engine", "thrust"), 15.0),
		"Following pump B to the engine shows the resulting 15 percent thrust.")
	_check(console.reading_rows.size() == 7 and console.reading_rows[6].value.text.contains("°C/min"),
		"The engine inspector includes the continuous temperature trend alongside its operating readings.")
	await _capture("limited.png")
	_press(console.back_button)
	_check(console.selected_equipment == "pump_b", "Back retraces the engine's cooling dependency.")
	_follow_link("aux_bus")
	_check(console.current_system == "power" and console.selected_equipment == "aux_bus" and console.control_slider.value == 24.0,
		"Following the power source preserves the changed limit.")
	_press(console.nav_buttons["overview"])
	var first_condition: Dictionary = console.presenter.conditions()[0]
	_press(console.condition_button)
	_check(console.selected_equipment == str(first_condition.equipment),
		"An overview condition opens the affected equipment inspector.")
	console.navigate("power", "aux_bus")
	console.control_slider.value = 40.0
	_tick(1.0)
	_check(_s("pump_b", "flow") > 15.0 and _s("pump_b", "flow") < 30.0,
		"Restoring electrical capacity starts gradual coolant recovery.")
	_tick(120.0)
	_check(_near(_s("pump_b", "flow"), 30.0) and _near(_s("main_engine", "thrust"), 30.0) and console.presenter.conditions().is_empty(),
		"Restored capacity returns the ship to its healthy operating point.")

	_press(console.pause_button)
	var paused_state: Dictionary = _state()
	_tick(120.0)
	_check(console.ship.paused and _state() == paused_state, "Pause freezes the simulation.")
	_check(not console.control_slider.editable and console.breaker_button.disabled,
		"Pause disables both capacity and breaker controls.")
	_press(console.pause_button)
	_check(not console.ship.paused and console.control_slider.editable and not console.breaker_button.disabled,
		"Resume restores operating controls.")
	console.control_slider.value = 24.0
	_tick(10.0)
	_press(console.reset_button)
	_check(console.current_system == "power" and console.selected_equipment == "aux_bus",
		"Reset preserves the current inspection view.")
	_check(console.control_slider.value == 40.0 and console.presenter.conditions().is_empty() and _near(_s("pump_b", "flow"), 30.0),
		"Reset restores the healthy ship and refreshes inspector controls.")
	_check_condition_route("reactor", "limit", 70.0)
	_check_condition_route("main_engine", "thrust", 45.0)
	console.ship.reset()
	console.ship.command("radiator", "deployment", 0.0)
	_tick(600.0)
	console.navigate("cooling", "heat_exchanger")
	_check(console.inspector_condition.text.contains("Temperature advisory") and console.inspector_condition.text.contains("°C/min"),
		"A temperature advisory explains connected temperatures and their trends in the inspector.")
	_check(console.reading_rows.size() == 6 and console.reading_rows[4].value.text.contains("°C/min") and console.reading_rows[5].value.text.contains("°C/min"),
		"The exchanger inspector shows separate readings for both connected thermal masses.")
	await _capture("thermal.png")
	console.navigate("cooling", "radiator")
	_check(console.inspector_condition.text.begins_with("Closed") and console.inspector_condition.text.contains("°C/min"),
		"The radiator inspector shows its closed state together with the hot coolant observation.")
	var simultaneous_codes: Array = console.presenter.conditions().map(func(condition): return condition.code)
	_check("radiator.closed" in simultaneous_codes and "coolant.temperature_advisory" in simultaneous_codes,
		"The overview retains both the closed radiator and its thermal consequences.")
	await _capture("radiator-advisory.png")
	var invalid_definition = console.ship.definition.duplicate(true)
	invalid_definition.schema_version = -1
	var invalid_console = MainScene.instantiate()
	invalid_console.ship = console.Simulation.new(invalid_definition)
	invalid_console.presenter = console.Presenter.new(invalid_console.ship)
	root.add_child(invalid_console)
	await process_frame
	_check(invalid_console.has_node("ConfigurationError") and not invalid_console.is_processing()
		and invalid_console.nav_buttons.is_empty(), "An invalid ship shows configuration errors instead of an operating console.")
	invalid_console.queue_free()

	print("%s: %d interface checks%s." % ["PASS" if failures == 0 else "FAIL", checks,
		"" if failures == 0 else " (%d failures)" % failures])
	quit(0 if failures == 0 else 1)


func _check_condition_route(component: String, control: String, value: float) -> void:
	console.ship.reset()
	console.ship.command(component, control, value)
	_tick(1.0)
	console.navigate("overview")
	var route: Dictionary = {}
	for condition in console.presenter.conditions():
		if condition.get("component_id", condition.equipment) == component:
			route = condition
			break
	_check(not route.is_empty(), "Changing %s.%s creates an inspectable equipment condition." % [component, control])
	if route.is_empty():
		return
	console.navigate(route.system, route.equipment)
	var target = console.ship.definition.component(route.equipment)
	_check(target != null and console.current_system == console.ship.definition.workspace_for(route.equipment)
		and console.selected_equipment == route.equipment and console.inspector_title != null
		and console.inspector_title.text == target.display_name,
		"The %s condition opens a valid actionable equipment inspector." % component)


func _tick(seconds: float) -> void:
	# Respect the model's bounded per-frame delta while simulating a long watch.
	var remaining: float = seconds
	while remaining > 0.0:
		var step: float = minf(remaining, 10.0)
		console.ship.tick(step)
		remaining -= step
	console._refresh()
	console.queue_redraw()


func _state() -> Dictionary:
	return console.ship.snapshot()


func _s(component: String, key: String) -> float:
	return float(console.ship.components[component].state.get(key, 0.0))


func _setting(component: String, key: String) -> float:
	return float(console.ship.components[component].settings[key])


func _follow_link(target: String) -> void:
	var links: Array = console.presenter.links(console.selected_equipment)
	for i in range(links.size()):
		if links[i].equipment == target:
			_press(console.dependency_buttons[i])
			return
	_check(false, "Missing connected-equipment link to " + target)


func _press(button: Button) -> void:
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, "Required interface control is unavailable.")
		return
	button.pressed.emit()


func _click_at_center(button: Button) -> void:
	await process_frame
	var position: Vector2 = root.get_final_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = position
	press.global_position = position
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = position
	release.global_position = position
	Input.parse_input_event(release)
	await process_frame


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.01


func _capture(filename: String) -> void:
	if not capture_requested:
		return
	if DisplayServer.get_name() == "headless":
		_check(false, "Captures require a graphical run; omit --headless.")
		return
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	console.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	_check(not frame.is_empty() and frame.save_png(CAPTURE_DIR.path_join(filename)) == OK,
		"Rendered capture saved: " + filename)
	print("CAPTURE: " + ProjectSettings.globalize_path(CAPTURE_DIR.path_join(filename)))


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
