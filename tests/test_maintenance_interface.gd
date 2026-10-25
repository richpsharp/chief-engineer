extends SceneTree
## Exercise the maintenance loop through the same controls the player uses.

const MainScene = preload("res://scenes/main.tscn")
var console
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	console = MainScene.instantiate()
	root.add_child(console)
	current_scene = console
	console.set_process(false)
	await process_frame
	console.select_ship("tern")
	console.navigate("cooling", "port_pump")
	await process_frame
	_check(is_instance_valid(console.maintenance_button), "The pump inspector exposes service life and maintenance.")
	await _click_at_center(console.maintenance_button)
	await process_frame
	_check(is_instance_valid(console.maintenance_panel) and console.maintenance_panel.visible,
		"The inspector opens the maintenance panel.")
	var panel = console.maintenance_panel
	_check(is_instance_valid(panel.failure_chart) and is_instance_valid(panel.performance_chart),
		"Risk and performance have separate charts.")
	var contained_focus := true
	for index in range(15):
		await _key(KEY_TAB)
		var focused = root.gui_get_focus_owner()
		contained_focus = contained_focus and focused != null and panel.is_ancestor_of(focused)
	_check(contained_focus, "Tab navigation stays inside the visible maintenance panel.")
	await _key(KEY_P)
	_check(console.ship.paused and panel.action_buttons.simulate_wear.disabled,
		"The panel's P shortcut pauses the simulation and disables work controls.")
	await _key(KEY_P)
	_check(panel.action_buttons.patch.disabled and panel.action_buttons.replace.disabled,
		"An energized healthy pump does not offer unsafe maintenance.")
	_check(not panel.action_buttons.simulate_wear.disabled, "The sandbox can introduce wear without waiting years.")
	await _capture("maintenance-healthy.png")
	var healthy: Dictionary = console.ship.snapshot()
	await _click_at_center(panel.action_buttons.simulate_wear)
	_check(console.ship.snapshot().components == healthy.components, "The sandbox action waits for a fixed step.")
	_tick(0.1)
	var info: Dictionary = console.ship.maintenance_info("port_pump")
	_check(info.efficiency < 0.9 and info.running_hours >= 1000.0,
		"The panel action creates an aged pump with reduced efficiency.")
	_check(console.presenter.equipment_status("port_pump") == "Degraded",
		"Wear is diagnosed as degradation rather than an electrical shortage.")
	_check(console.ship.components.port_engine.state.thrust < 20.0
		and _near(console.ship.components.starboard_engine.state.thrust, 20.0),
		"The worn pump affects its own engine while the other branch continues.")
	var routed := false
	for condition in console.presenter.conditions():
		if condition.component_id == "port_engine":
			routed = condition.equipment == "port_pump"
	_check(routed, "The affected engine points the player to its degraded pump.")
	await _capture("maintenance-worn.png")
	_press(panel.supply_button)
	await process_frame
	_check(console.selected_equipment == "port_pump_feed" and console.current_system == "power",
		"The supply shortcut reaches the pump's actual feeder.")
	_check(not is_instance_valid(console.maintenance_panel) or not console.maintenance_panel.visible,
		"Navigating to the supply closes the maintenance overlay.")
	_press(console.breaker_button)
	_tick(0.1)
	console.navigate("cooling", "port_pump")
	_press(console.maintenance_button)
	await process_frame
	panel = console.maintenance_panel
	_check(not panel.action_buttons.patch.disabled and not panel.action_buttons.replace.disabled,
		"Isolation enables the repair choices.")
	_press(panel.action_buttons.patch)
	_tick(0.1)
	_check(console.ship.maintenance_info("port_pump").job == "patch", "Patch starts a maintenance job.")
	_tick(11.0)
	_check(console.ship.maintenance_info("port_pump").patch_remaining_hours > 0.0,
		"A completed patch retains a visible, finite operating life.")
	await _capture("maintenance-patched.png")
	var lifetime: float = console.ship.maintenance_info("port_pump").running_hours
	_press(panel.action_buttons.replace)
	_tick(0.1)
	_check(console.ship.maintenance_info("port_pump").job == "replace", "Replacement can supersede a field patch.")
	_tick(5.0)
	await _capture("maintenance-repair.png")
	console.close_maintenance()
	_press(console.pause_button)
	console.open_maintenance("port_pump")
	await process_frame
	panel = console.maintenance_panel
	var paused: Dictionary = console.ship.snapshot()
	_tick(5.0)
	_check(console.ship.snapshot() == paused and panel.action_buttons.cancel.disabled,
		"Pause freezes the repair and its operating controls.")
	console.close_maintenance()
	_press(console.pause_button)
	console.open_maintenance("port_pump")
	await process_frame
	var tern = console.ship
	var parked: Dictionary = tern.snapshot()
	console.select_ship("kestrel")
	await process_frame
	_check(not is_instance_valid(console.maintenance_panel) or not console.maintenance_panel.visible,
		"Switching ships cannot leave a repair panel attached to the previous runtime.")
	_tick(30.0)
	_check(tern.snapshot() == parked, "A parked ship's repair and supplies remain unchanged.")
	console.select_ship("tern")
	_tick(30.0)
	info = tern.maintenance_info("port_pump")
	_check(info.job.is_empty() and _near(info.efficiency, 1.0) and _near(info.running_hours, lifetime),
		"Replacement restores capability while preserving lifetime hours.")
	console.navigate("power", "port_pump_feed")
	_press(console.breaker_button)
	_tick(60.0)
	_check(_near(tern.components.port_engine.state.thrust, 20.0)
		and _near(tern.components.starboard_engine.state.thrust, 20.0)
		and console.presenter.conditions().is_empty(), "Recommissioning restores both drives to healthy cruise.")
	console.navigate("cooling", "port_pump")
	console.open_maintenance("port_pump")
	await process_frame
	await _capture("maintenance-restored.png")
	console.close_maintenance()
	_press(console.reset_button)
	info = tern.maintenance_info("port_pump")
	_check(_near(info.running_hours, 1000.0) and info.patches == 3 and info.spares == 2,
		"Reset restores authored history and onboard repair supplies.")
	console.navigate("power", "distribution_bus")
	console.open_maintenance("distribution_bus")
	await process_frame
	_check(not tern.maintenance_info("distribution_bus").supported
		and tern.maintenance_info("distribution_bus").rated_life_hours == 0.0,
		"Equipment without a lifetime profile does not acquire a fictional expiry rating.")
	await _capture("maintenance-unrated.png")
	await _key(KEY_ESCAPE)
	_check(not is_instance_valid(console.maintenance_panel) or not console.maintenance_panel.visible,
		"Escape closes the service panel without changing the selected equipment.")
	_check(console.selected_equipment == "distribution_bus", "Closing a panel preserves the underlying inspection route.")
	print("%s: %d maintenance interface checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _tick(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.000001:
		var step: float = minf(remaining, 10.0)
		console.ship.tick(step)
		remaining -= step
	console._refresh()
	if is_instance_valid(console.maintenance_panel) and console.maintenance_panel.has_method("refresh"):
		console.maintenance_panel.refresh()
	console.queue_redraw()


func _press(button: Button) -> void:
	if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
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
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = position
		event.global_position = position
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _capture(filename: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	if DisplayServer.get_name() == "headless":
		_check(false, "Captures require a graphical run.")
		return
	DirAccess.make_dir_recursive_absolute("res://.tools/captures")
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	_check(not frame.is_empty() and frame.save_png("res://.tools/captures/" + filename) == OK,
		"Rendered capture saved: " + filename)


func _near(value: float, expected: float) -> bool:
	return absf(value - expected) < 0.01


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
