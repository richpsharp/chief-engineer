extends SceneTree
## Repair from the same equipment inspector while the live network stays visible.
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
	var panel = console.maintenance_panel
	_check(is_instance_valid(panel) and console.workspace_layer.is_ancestor_of(panel),
		"Supported pump maintenance is already part of the current workspace inspector.")
	_check(not panel.details_visible() and not panel.failure_chart.is_visible_in_tree(),
		"Routine repair actions do not require opening reliability charts.")
	_check(panel.action_buttons.patch.visible and panel.action_buttons.replace.visible
		and console.equipment_buttons.port_engine.is_visible_in_tree(),
		"Repair actions and the affected engine remain visible in the same workspace.")
	_check(panel.action_buttons.patch.disabled and panel.action_buttons.replace.disabled,
		"An energized healthy pump does not offer unsafe maintenance.")
	await _click_at_center(panel.details_button)
	_check(panel.details_visible() and panel.failure_chart.is_visible_in_tree()
		and panel.performance_chart.is_visible_in_tree(), "One inline disclosure reveals separate reliability and performance charts.")
	await _key(KEY_P)
	_check(console.ship.paused and panel.action_buttons.simulate_wear.disabled,
		"The console's P shortcut pauses work without an overlay capturing input.")
	await _key(KEY_P)
	var healthy: Dictionary = console.ship.snapshot()
	await _click_at_center(panel.action_buttons.simulate_wear)
	_check(console.ship.snapshot().components == healthy.components, "The sandbox action waits for a fixed step.")
	_tick(0.1)
	var info: Dictionary = console.ship.maintenance_info("port_pump")
	_check(info.efficiency < 0.9 and info.running_hours >= 1000.0,
		"The inline sandbox action creates an aged pump with reduced efficiency.")
	_check(console.presenter.equipment_status("port_pump") == "Degraded",
		"Wear is diagnosed as degradation rather than an electrical shortage.")
	_check(console.ship.components.port_engine.state.thrust < 20.0
		and _near(console.ship.components.starboard_engine.state.thrust, 20.0),
		"The live diagram's port engine loses capability while the other drive stays available.")
	console.close_maintenance()
	_check(console.maintenance_panel == panel and not panel.details_visible()
		and panel.action_buttons.replace.visible, "Collapsing charts leaves routine service and operating controls in place.")
	await _capture("maintenance-inline-worn.png")
	_press(console.inspector_controls.buttons.feeder)
	_tick(0.1)
	_check(console.current_system == "cooling" and console.selected_equipment == "port_pump"
		and not console.ship.components.port_pump_feed.settings.closed,
		"The pump's local feeder can be isolated without leaving its Cooling inspector.")
	_check(not panel.action_buttons.patch.disabled and not panel.action_buttons.replace.disabled,
		"Actual local electrical isolation enables Tern's repair choices.")
	_press(panel.action_buttons.patch)
	_tick(0.1)
	_check(console.ship.maintenance_info("port_pump").job == "patch", "Patch starts inline maintenance work.")
	_tick(11.0)
	_check(console.ship.maintenance_info("port_pump").patch_remaining_hours > 0.0,
		"A completed patch retains a visible, finite operating life.")
	var lifetime: float = console.ship.maintenance_info("port_pump").running_hours
	_press(panel.action_buttons.replace)
	_tick(5.0)
	_check(console.ship.maintenance_info("port_pump").job == "replace" and panel.progress.visible,
		"Replacement progress stays in the pump inspector.")
	_check(console.equipment_buttons.starboard_engine.is_visible_in_tree()
		and _near(console.ship.components.starboard_engine.state.thrust, 20.0),
		"The functioning drive remains visible and running during repair.")
	await _capture("maintenance-inline-repair.png")
	_press(console.pause_button)
	var paused: Dictionary = console.ship.snapshot()
	_tick(5.0)
	_check(console.ship.snapshot() == paused and panel.action_buttons.cancel.disabled,
		"Pause freezes the repair and disables job cancellation.")
	_press(console.pause_button)
	var tern = console.ship
	var parked: Dictionary = tern.snapshot()
	console.select_ship("kestrel")
	await process_frame
	_check(not is_instance_valid(console.maintenance_panel),
		"Ship switching cannot retain a service inspector on the previous runtime.")
	_tick(30.0)
	_check(tern.snapshot() == parked, "A parked ship's repair and supplies remain unchanged.")
	console.select_ship("tern")
	_tick(30.0)
	info = tern.maintenance_info("port_pump")
	_check(info.job.is_empty() and _near(info.efficiency, 1.0) and _near(info.running_hours, lifetime),
		"Replacement restores capability while preserving lifetime hours.")
	console.navigate("cooling", "port_pump")
	_press(console.inspector_controls.buttons.feeder)
	_tick(60.0)
	_check(_near(tern.components.port_engine.state.thrust, 20.0)
		and _near(tern.components.starboard_engine.state.thrust, 20.0)
		and console.presenter.conditions().is_empty(), "Recommissioning in Cooling restores both drives to healthy cruise.")
	console.open_maintenance("port_pump")
	await process_frame
	panel = console.maintenance_panel
	_check(panel.details_visible(), "The service-life shortcut expands details in the existing inspector.")
	await _ensure_visible(panel.performance_chart)
	_check(panel.info_labels.values().all(func(label): return label.size.y < 30.0),
		"Narrow service-history value columns keep each numeric reading on one line.")
	await _capture("maintenance-inline-charts.png")
	await _ensure_visible(panel.failure_chart)
	await _capture("maintenance-inline-risk.png")
	await _key(KEY_ESCAPE)
	_check(not panel.details_visible() and console.selected_equipment == "port_pump",
		"Escape collapses details while retaining equipment selection and routine repair controls.")
	_press(console.reset_button)
	info = tern.maintenance_info("port_pump")
	_check(_near(info.running_hours, 1000.0) and info.patches == 3 and info.spares == 2,
		"Reset restores authored history and repair supplies.")
	console.navigate("power", "distribution_bus")
	console.open_maintenance("distribution_bus")
	await process_frame
	_check(not is_instance_valid(console.maintenance_panel) and not is_instance_valid(console.maintenance_button),
		"Equipment without a wear model does not advertise an unsupported repair menu.")
	_check(console.selected_equipment == "distribution_bus", "Unsupported service requests do not change selection.")
	print("%s: %d maintenance interface checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _tick(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.000001:
		var step: float = minf(remaining, 10.0)
		console.ship.tick(step)
		remaining -= step
	console._refresh()
	console.queue_redraw()


func _press(button: Button) -> void:
	if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
		_check(false, "Required interface control is unavailable.")
		return
	button.pressed.emit()


func _ensure_visible(control: Control) -> void:
	await process_frame
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
		parent = parent.get_parent()
	await process_frame
	await process_frame


func _click_at_center(button: Button) -> void:
	await _ensure_visible(button)
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
