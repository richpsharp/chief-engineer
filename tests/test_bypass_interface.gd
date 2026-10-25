extends SceneTree
## Build, use, repair around, and recover a bypass through the player controls.
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
	console.navigate("cooling")
	await process_frame
	_check(is_instance_valid(console.bypass_button), "Cooling exposes installation without selecting equipment.")
	await _click(console.bypass_button)
	await process_frame
	_check(is_instance_valid(console.bypass_panel), "A real mouse click opens the coolant bypass panel.")
	var panel = console.bypass_panel
	_choose(panel.source_selector, "pump_b")
	_choose(panel.target_selector, "core_loop")
	_check(panel.action_buttons.install.disabled, "Live connection points prevent installation.")
	_check(panel.source_selector.item_count >= 2 and panel.target_selector.item_count >= 1,
		"The player selects authored pump and circuit service ports.")
	var focus_contained := true
	for step in range(15):
		await _key(KEY_TAB)
		var focus = root.gui_get_focus_owner()
		focus_contained = focus_contained and focus != null and panel.is_ancestor_of(focus)
	_check(focus_contained, "Keyboard focus remains inside the bypass panel.")
	await _key(KEY_P)
	_check(console.ship.paused, "P pauses the simulation inside the bypass panel.")
	await _key(KEY_P)
	await _capture("bypass-planning.png")
	_press(panel.supply_buttons.pump_b)
	_check(console.selected_equipment == "pump_b_feed", "The donor supply shortcut opens its local feeder.")
	await _capture("bypass-power.png")
	console.open_bypass()
	await process_frame
	panel = console.bypass_panel
	_check(panel.selected_endpoints() == {"source_id": "pump_b", "circuit_id": "core_loop"},
		"Endpoint choices survive a trip to the supply controls.")
	console.close_bypass()
	console.navigate("cooling", "pump_a")
	console.open_maintenance("pump_a")
	_press(console.maintenance_panel.action_buttons.simulate_wear)
	_tick(0.1)
	console.close_maintenance()
	for feed in ["pump_a_feed", "pump_b_feed"]:
		console.navigate("power", feed)
		_press(console.breaker_button)
		_tick(0.1)
	console.navigate("cooling")
	console.open_bypass()
	await process_frame
	panel = console.bypass_panel
	_choose(panel.source_selector, "pump_b")
	_choose(panel.target_selector, "core_loop")
	for circuit in ["core_loop", "drive_loop"]:
		_press(panel.primary_buttons[circuit])
		_tick(0.1)
	_check(not panel.action_buttons.install.disabled, "Electrical and coolant isolation enable installation.")
	_press(panel.action_buttons.install)
	_tick(0.1)
	_check(console.ship.bypass_info().job == "install", "Installing the chosen route starts physical work.")
	_check(panel.source_selector.disabled and panel.target_selector.disabled,
		"Endpoint selection cannot silently alter an installation in progress.")
	_tick(11.0)
	var info: Dictionary = console.ship.bypass_info()
	_check(info.installed and info.source_id == "pump_b" and info.circuit_id == "core_loop" and not info.open,
		"The kit is installed closed on the player-selected route.")
	_check(_near(panel.flow_slider.max_value, 24.0), "The operating control exposes the kit's 24 L/s rating.")
	_press(panel.primary_buttons.drive_loop)
	_tick(0.1)
	panel.flow_slider.value = 24.0
	_press(panel.action_buttons.open)
	_tick(0.1)
	_check(panel.primary_buttons.core_loop.disabled,
		"The target's native route cannot be reopened against an open bypass.")
	console.close_bypass()
	console.navigate("power", "pump_b_feed")
	_press(console.breaker_button)
	_tick(0.1)
	console.navigate("cooling", "pump_b")
	console.control_slider.value = 40.0
	_tick(60.0)
	info = console.ship.bypass_info()
	_check(_near(info.delivered_flow, 24.0) and _near(info.source_remaining_flow, 16.0)
		and _near(console.ship.components.main_engine.state.thrust, 16.0),
		"B's finite flow is split between the core circuit and reduced engine thrust.")
	_check(console.ship.components.main_bus.settings.closed and console.ship.components.life_support.state.power > 0.0,
		"Pump A's local isolation leaves the main bus and life support powered.")
	var links: Array = console.presenter.links("pump_b")
	_check(links.any(func(link): return link.equipment == "heat_exchanger"),
		"The installed bypass adds a navigable dependency to the destination equipment.")
	var edges: Array = console.presenter.schematic_edges(["pump_a", "pump_b", "heat_exchanger", "main_engine", "radiator"])
	_check(edges.any(func(edge): return edge.from_component == "pump_b" and edge.to_component == "heat_exchanger" and edge.active),
		"The cooling schematic shows the live installed route.")
	await _capture("bypass-schematic.png")
	console.open_bypass()
	await process_frame
	await _capture("bypass-operating.png")
	console.close_bypass()
	console.navigate("cooling", "pump_a")
	console.open_maintenance("pump_a")
	_check(not console.maintenance_panel.action_buttons.replace.disabled,
		"An incoming bypass can supply the core while pump A remains safe to repair.")
	_press(console.maintenance_panel.action_buttons.replace)
	_tick(5.0)
	_check(console.ship.maintenance_info("pump_a").job == "replace"
		and _near(console.ship.components.main_engine.state.thrust, 16.0),
		"The engine continues running while A is being repaired.")
	await _capture("bypass-during-repair.png")
	console.close_maintenance()
	console.open_bypass()
	await process_frame
	var kestrel = console.ship
	var parked: Dictionary = kestrel.snapshot()
	console.select_ship("tern")
	await process_frame
	_check(not is_instance_valid(console.bypass_panel), "Ship switching closes the old runtime's bypass controls.")
	_tick(30.0)
	_check(kestrel.snapshot() == parked, "An inactive ship retains its installed route and unfinished repair without advancing.")
	console.select_ship("kestrel")
	_tick(30.0)
	_check(_near(kestrel.maintenance_info("pump_a").efficiency, 1.0), "Replacement completes while backup cooling remains available.")
	console.open_bypass()
	await process_frame
	panel = console.bypass_panel
	_press(panel.action_buttons.close)
	_tick(0.1)
	_press(panel.primary_buttons.core_loop)
	_tick(0.1)
	console.close_bypass()
	console.navigate("power", "pump_a_feed")
	_press(console.breaker_button)
	_tick(0.1)
	console.navigate("cooling", "pump_b")
	console.control_slider.value = 30.0
	_tick(120.0)
	_check(_near(kestrel.components.main_engine.state.thrust, 30.0) and _near(kestrel.totals().output, 152.0),
		"Normal routing restores the original Kestrel cruise point.")
	for feed in ["pump_a_feed", "pump_b_feed"]:
		console.navigate("power", feed)
		_press(console.breaker_button)
		_tick(0.1)
	console.open_bypass()
	await process_frame
	panel = console.bypass_panel
	for circuit in ["core_loop", "drive_loop"]:
		_press(panel.primary_buttons[circuit])
		_tick(0.1)
	_press(panel.action_buttons.remove)
	_tick(11.0)
	info = kestrel.bypass_info()
	_check(not info.installed and info.kits == 1, "Safe removal recovers the reusable bypass kit.")
	_check(not console.presenter.links("pump_b").any(func(link): return link.equipment == "heat_exchanger"),
		"Removing a bypass removes its dependency link.")
	await _key(KEY_ESCAPE)
	_check(not is_instance_valid(console.bypass_panel), "Escape closes the bypass panel.")
	_press(console.reset_button)
	_check(not kestrel.bypass_info().installed and kestrel.bypass_info().kits == 1
		and console.presenter.conditions().is_empty(), "Reset restores healthy native routing and the uninstalled kit.")
	print("%s: %d bypass interface checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _choose(selector: OptionButton, id: String) -> void:
	for index in range(selector.item_count):
		if str(selector.get_item_metadata(index)) == id:
			selector.select(index)
			selector.item_selected.emit(index)
			return
	_check(false, "Missing selectable service port: " + id)


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
		_check(false, "Required control is unavailable.")
		return
	button.pressed.emit()


func _click(button: Button) -> void:
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
