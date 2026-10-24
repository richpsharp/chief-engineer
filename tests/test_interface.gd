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
	_check(console.ship.conditions().is_empty(), "The ship starts without active limitations.")
	_tick(3600.0)
	_check(console.ship.conditions().is_empty() and is_equal_approx(console.ship.engine_thrust, 30.0),
		"An unattended healthy ship remains operational for a simulated hour.")
	await _capture("overview.png")
	await _click_at_center(console.overview_buttons["power"])
	_check(console.current_system == "power", "A real mouse click reaches a card through the workspace layer.")
	_press(console.nav_buttons["overview"])

	var initial_state: Array = _state()
	var all_pages_opened := true
	for id in console.SYSTEMS:
		_press(console.nav_buttons[id])
		all_pages_opened = all_pages_opened and console.current_system == id
	_check(all_pages_opened, "All eight departments have reachable pages.")
	var all_inspectors_valid := true
	for id in console.EQUIPMENT:
		_press(console.nav_buttons[console.EQUIPMENT[id].system])
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
	_press(console.dependency_buttons[1])
	_check(console.current_system == "cooling" and console.selected_equipment == "pump_b",
		"The auxiliary bus supply link opens cooling pump B.")
	await _capture("cooling.png")
	_press(console.back_button)
	_check(console.current_system == "power" and console.selected_equipment == "aux_bus",
		"Back restores the previous workspace and selected equipment.")

	console.control_slider.value = 24.0
	_check(console.ship.bus_b_limit == 24.0, "Changing the inspector slider updates the model.")
	_tick(120.0)
	_press(console.dependency_buttons[1])
	_check(_near(console.ship.pump_b_power, 6.0) and _near(console.ship.pump_b_flow, 15.0),
		"The shared auxiliary limit leaves 6 kW and 15 L/s for pump B.")
	_check(not console.ship.equipment_reason("pump_b").is_empty() and console.inspector_condition.text != "",
		"The pump inspector explains its reduced performance.")
	_press(console.dependency_buttons[1])
	_check(console.selected_equipment == "main_engine" and _near(console.ship.engine_thrust, 15.0),
		"Following pump B to the engine shows the resulting 15 percent thrust.")
	await _capture("limited.png")
	_press(console.back_button)
	_check(console.selected_equipment == "pump_b", "Back retraces the engine's cooling dependency.")
	_press(console.dependency_buttons[0])
	_check(console.current_system == "power" and console.selected_equipment == "aux_bus" and console.control_slider.value == 24.0,
		"Following the power source preserves the changed limit.")
	_press(console.nav_buttons["overview"])
	var first_condition: Dictionary = console.ship.conditions()[0]
	_press(console.condition_button)
	_check(console.selected_equipment == str(first_condition.equipment),
		"An overview condition opens the affected equipment inspector.")
	console.navigate("power", "aux_bus")
	console.control_slider.value = 40.0
	_tick(1.0)
	_check(console.ship.pump_b_flow > 15.0 and console.ship.pump_b_flow < 30.0,
		"Restoring electrical capacity starts gradual coolant recovery.")
	_tick(120.0)
	_check(_near(console.ship.pump_b_flow, 30.0) and _near(console.ship.engine_thrust, 30.0) and console.ship.conditions().is_empty(),
		"Restored capacity returns the ship to its healthy operating point.")

	_press(console.pause_button)
	var paused_state: Array = _state()
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
	_check(console.control_slider.value == 40.0 and console.ship.conditions().is_empty() and _near(console.ship.pump_b_flow, 30.0),
		"Reset restores the healthy ship and refreshes inspector controls.")
	_check_condition_route("reactor_limit", 70.0, "power", "reactor")
	_check_condition_route("engine_command", 45.0, "cooling", "main_engine")

	print("%s: %d interface checks%s." % ["PASS" if failures == 0 else "FAIL", checks,
		"" if failures == 0 else " (%d failures)" % failures])
	quit(0 if failures == 0 else 1)


func _check_condition_route(control: String, value: float, system: String, equipment: String) -> void:
	console.ship.reset()
	console.ship.set_control(control, value)
	_tick(1.0)
	console.navigate("overview")
	var route: Dictionary = {}
	for condition in console.ship.conditions():
		if condition.equipment == equipment:
			route = condition
			break
	_check(not route.is_empty(), "Changing %s creates an inspectable equipment condition." % control)
	if route.is_empty():
		return
	console.navigate(route.system, route.equipment)
	_check(console.current_system == system and console.selected_equipment == equipment
		and console.inspector_title != null and console.inspector_title.text == console.EQUIPMENT[equipment].name,
		"The %s condition opens its actual equipment inspector." % equipment)


func _tick(seconds: float) -> void:
	# Respect the model's bounded per-frame delta while simulating a long watch.
	var remaining: float = seconds
	while remaining > 0.0:
		var step: float = minf(remaining, 10.0)
		console.ship.tick(step)
		remaining -= step
	console._refresh()
	console.queue_redraw()


func _state() -> Array:
	return [console.ship.elapsed, console.ship.reactor_limit, console.ship.bus_b_limit,
		console.ship.bus_a_closed, console.ship.bus_b_closed, console.ship.pump_a_flow,
		console.ship.pump_b_flow, console.ship.engine_thrust, console.ship.main_temperature,
		console.ship.engine_temperature, console.ship.coolant_temperature, console.ship.events.duplicate()]


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
