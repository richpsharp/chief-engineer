extends SceneTree
## The same equipment can be operated in place through its schematic and inspector.

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
	await _settle()
	var workspace_count: int = console.ship.definition.views.filter(func(view): return view.kind == "workspace").size()
	_check(console.nav_buttons.size() == workspace_count + 1 and not console.nav_buttons.has("reactor"),
		"Navigation contains the overview and operating workspaces without duplicate status destinations.")
	var before: Dictionary = console.ship.snapshot()
	await _click(console.overview_buttons.reactor)
	_check(console.selected_equipment == "reactor" and is_instance_valid(console.inspector_controls)
		and console.inspector_controls.sliders.has("limit"),
		"One click on Reactor exposes its power control directly.")
	_check(console.ship.snapshot() == before, "Selecting Reactor does not operate it.")
	_check(not is_instance_valid(console.maintenance_panel), "Reactor does not offer an unsupported repair panel.")
	await _click(console.inspector_close_button)
	_check(console.current_system == "reactor" and console.selected_equipment.is_empty()
		and not is_instance_valid(console.inspector_controls),
		"Closing Reactor's inspector clears selection without selecting its default equipment again.")
	_press(console.back_button)
	_check(console.current_system == "reactor" and console.selected_equipment == "reactor",
		"Back restores the reactor selection after closing its inspector.")
	console.inspector_controls.sliders.limit.value = 150.0
	_check(_near(console.ship.components.reactor.settings.limit, 200.0), "Direct reactor controls still queue validated commands.")
	_tick(0.1)
	_check(_near(console.ship.components.reactor.settings.limit, 150.0), "The direct reactor command reaches the next simulation step.")
	await _capture("console-reactor-direct.png")
	_press(console.reset_button)
	await _click(console.nav_buttons.power)
	before = console.ship.snapshot()
	await _click(console.equipment_buttons.pump_b)
	_check(console.current_system == "power" and console.selected_equipment == "pump_b",
		"Selecting a pump drawn in Power keeps the Power schematic visible.")
	_check(console.ship.snapshot() == before, "Selecting a pump does not change a breaker, valve, or flow request.")
	_check(is_instance_valid(console.quick_controls) and console.quick_controls.sliders.has("flow")
		and console.inspector_controls.sliders.has("flow"),
		"The selected pump exposes flow control on both the diagram and inspector.")
	var sequence: int = console.ship.command_results.size()
	console.quick_controls.sliders.flow.value = 35.0
	_check(_near(console.ship.components.pump_b.settings.flow, 30.0)
		and console.ship.command_results.size() == sequence + 1,
		"A diagram flow adjustment queues one command without changing physical state early.")
	_tick(0.1)
	_check(_near(console.ship.components.pump_b.settings.flow, 35.0)
		and _near(console.inspector_controls.sliders.flow.value, 35.0),
		"A committed diagram adjustment is reflected in the inspector.")
	console.inspector_controls.sliders.flow.value = 32.0
	_tick(0.1)
	_check(_near(console.quick_controls.sliders.flow.value, 32.0),
		"A committed inspector adjustment is reflected on the diagram.")
	console.quick_controls.sliders.flow.grab_focus()
	await _key(KEY_RIGHT)
	_tick(0.1)
	_check(_near(console.ship.components.pump_b.settings.flow, 33.0)
		and _near(console.inspector_controls.sliders.flow.value, 33.0),
		"The diagram flow control accepts native keyboard input and synchronizes the inspector.")
	console.inspector_controls.sliders.flow.value = 0.0
	_tick(0.1)
	_check(console.ship.components.pump_b_feed.settings.closed
		and _circuit("drive_loop").primary_open and not console.ship.maintenance_info("pump_b").isolated,
		"Zero flow is distinct from electrical and coolant isolation.")
	console.inspector_controls.sliders.flow.value = 30.0
	_tick(60.0)
	await _click(console.quick_controls.buttons.feeder)
	_check(console.ship.components.pump_b_feed.settings.closed, "The diagram feeder control also waits for a simulation step.")
	_tick(0.1)
	_check(not console.ship.components.pump_b_feed.settings.closed and console.ship.components.aux_bus.settings.closed
		and console.ship.components.main_bus.settings.closed,
		"The pump's direct feeder control isolates its local feeder, leaving both distribution buses on.")
	_check(console.current_system == "power" and console.selected_equipment == "pump_b"
		and _near(console.ship.components.main_engine.state.thrust, 0.0),
		"Operating a node retains selection and exposes the downstream loss of thrust.")
	_press(console.inspector_controls.buttons.feeder)
	_tick(0.1)
	_check(console.ship.components.pump_b_feed.settings.closed, "The inspector reconnects the same local feeder.")
	await _capture("console-power-pump.png")
	_follow_link("main_engine")
	_check(console.current_system == "power" and console.selected_equipment == "main_engine",
		"Following equipment dependencies selects them in the current view.")
	await _click(console.nav_buttons.cooling)
	await _click(console.equipment_buttons.pump_b)
	_check(console.current_system == "cooling" and is_instance_valid(console.maintenance_panel),
		"Explicit workspace navigation changes context, with pump service available inline.")
	_press(console.quick_controls.buttons.primary)
	_tick(0.1)
	_check(not _circuit("drive_loop").primary_open and console.ship.components.pump_b_feed.settings.closed,
		"The diagram valve control closes coolant isolation without operating the feeder.")
	_press(console.pause_button)
	before = console.ship.snapshot()
	_check(not console.quick_controls.sliders.flow.editable and not console.inspector_controls.sliders.flow.editable
		and console.quick_controls.buttons.feeder.disabled and console.inspector_controls.buttons.primary.disabled,
		"Pause disables both copies of flow, electrical, and coolant controls.")
	_tick(30.0)
	_check(console.ship.snapshot() == before, "Viewing paused controls does not advance the ship.")
	_press(console.pause_button)
	_press(console.reset_button)
	_check(console.current_system == "cooling" and console.selected_equipment == "pump_b"
		and _near(console.quick_controls.sliders.flow.value, 30.0)
		and _near(console.inspector_controls.sliders.flow.value, 30.0)
		and _circuit("drive_loop").primary_open,
		"Reset keeps the inspection context and refreshes both copies from healthy state.")
	await _capture("console-cooling-pump.png")
	await _test_control_geometry("kestrel")
	await _test_control_geometry("tern")
	console.navigate("propulsion", "starboard_engine")
	before = console.ship.snapshot()
	await _click(console.inspector_close_button)
	_check(console.current_system == "propulsion" and console.selected_equipment.is_empty()
		and console.ship.snapshot() == before,
		"Closing starboard's inspector in Propulsion clears selection without switching to the port engine.")
	_press(console.back_button)
	_check(console.current_system == "propulsion" and console.selected_equipment == "starboard_engine",
		"Back restores the exact engine selected before closing the inspector.")
	console.navigate("cooling", "core_pump")
	_check(console.quick_controls.buttons.feeder.text.contains("Main trunk")
		and console.quick_controls.buttons.feeder.text.contains("shared supply")
		and console.inspector_controls.buttons.feeder.tooltip_text.contains("every load downstream"),
		"The core pump names its main-trunk breaker and discloses its shared downstream scope.")
	await _capture("console-tern-core-shared-supply.png")
	await _click(console.quick_controls.buttons.feeder)
	_check(console.ship.components.distribution_bus.settings.closed,
		"The shared-supply breaker queues its command before disconnecting the trunk.")
	_tick(0.1)
	_check(not console.ship.components.distribution_bus.settings.closed
		and console.ship.components.port_bus.settings.closed and console.ship.components.starboard_bus.settings.closed
		and _near(console.ship.components.port_engine.state.thrust, 0.0)
		and _near(console.ship.components.starboard_engine.state.thrust, 0.0),
		"The disclosed shared-supply command opens the main trunk and takes both downstream engines offline.")
	_press(console.reset_button)
	console.navigate("cooling", "port_pump")
	_check(not console.quick_controls.buttons.feeder.text.contains("shared")
		and not console.inspector_controls.buttons.feeder.text.contains("shared")
		and console.quick_controls.buttons.feeder.tooltip_text.contains("Port pump feed"),
		"The port pump identifies its dedicated feeder without claiming a shared supply.")
	await _settle()
	await _capture("console-tern-selected.png")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1152, 720)
		await _settle()
		await _capture("console-minimum-window.png")
		_check(root.get_visible_rect().size.x >= 1152, "The minimum window retains the supported engineering console viewport.")
	print("%s: %d console-consistency checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _test_control_geometry(ship_id: String) -> void:
	console.select_ship(ship_id)
	for view in console.ship.definition.views:
		if view.kind != "workspace":
			continue
		console.navigate(view.id)
		var ids: Array = console.equipment_buttons.keys()
		for id in ids:
			console.navigate(view.id, id)
			await _settle()
			if not is_instance_valid(console.quick_controls):
				continue
			var card: Rect2 = console.equipment_buttons[id].get_global_rect()
			var controls: Rect2 = console.quick_controls.get_global_rect()
			_check(card.grow(1.0).encloses(controls), "%s / %s quick controls fit inside their equipment card." % [ship_id, id])
			var overlap := false
			for other in console.equipment_buttons:
				if other != id and card.intersects(console.equipment_buttons[other].get_global_rect()):
					overlap = true
			_check(not overlap and card.end.y <= 871.0, "%s / %s expanded card preserves surrounding equipment and stays inside the schematic." % [ship_id, id])


func _circuit(id: String) -> Dictionary:
	for circuit in console.ship.bypass_info().circuits:
		if circuit.id == id:
			return circuit
	return {}


func _tick(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.000001:
		var step: float = minf(remaining, 10.0)
		console.ship.tick(step)
		remaining -= step
	console._refresh()
	console.queue_redraw()


func _follow_link(target: String) -> void:
	var links: Array = console.presenter.links(console.selected_equipment)
	for index in range(links.size()):
		if links[index].equipment == target:
			_press(console.dependency_buttons[index])
			return
	_check(false, "Missing connected-equipment link to " + target)


func _press(button: Button) -> void:
	if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
		_check(false, "Required control is unavailable.")
		return
	button.pressed.emit()


func _click(control: Control) -> void:
	await _settle()
	# Expanded equipment cards contain real controls; select through their heading.
	var local_position: Vector2 = Vector2(control.size.x * 0.5, 40.0) if control in console.equipment_buttons.values() else control.size * 0.5
	var position: Vector2 = root.get_final_transform() * (control.get_global_transform_with_canvas() * local_position)
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
	await _settle()


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _settle() -> void:
	await process_frame
	await process_frame


func _capture(filename: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	if DisplayServer.get_name() == "headless":
		_check(false, "Captures require a graphical run.")
		return
	DirAccess.make_dir_recursive_absolute("res://.tools/captures")
	await _settle()
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
