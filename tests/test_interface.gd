extends SceneTree
## Exercises navigation and the power -> coolant -> thrust dependency through
## the real scene controls. Add -- --capture to a graphical run for screenshots.

const MainScene = preload("res://scenes/main.tscn")
const Fixtures = preload("res://tests/ship_fixtures.gd")
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
		console.navigate("overview")
		_press(console.overview_buttons[id])
		all_pages_opened = all_pages_opened and console.current_system == id
	_check(all_pages_opened, "All eight systems remain reachable from the ship overview.")
	var all_inspectors_valid := true
	for spec in console.ship.definition.components:
		if not spec.inspectable:
			continue
		var id: String = spec.id
		_press(console.nav_buttons[console.ship.definition.workspace_for(id)])
		_press(console.equipment_buttons[id])
		all_inspectors_valid = all_inspectors_valid and console.selected_equipment == id
		all_inspectors_valid = all_inspectors_valid and console.inspector_title.text != "" and not console.reading_rows.is_empty()
	_check(all_inspectors_valid, "All inspectable equipment has a title and live readings.")
	_check(_state() == initial_state, "Exploring pages and equipment does not mutate the ship.")

	_press(console.nav_buttons["power"])
	_press(console.equipment_buttons["aux_bus"])
	_check(console.control_slider.value == 40.0 and console.breaker_button != null,
		"Auxiliary bus exposes its healthy capacity setting and breaker.")
	await _capture("power.png")
	_follow_link("pump_b_feed")
	_follow_link("pump_b")
	_check(console.current_system == "power" and console.selected_equipment == "pump_b",
		"The auxiliary bus and local feeder links select pump B without leaving Power.")
	await _capture("cooling.png")
	_press(console.back_button)
	_check(console.selected_equipment == "pump_b_feed", "Back first returns to the pump's local feeder.")
	_press(console.back_button)
	_check(console.current_system == "power" and console.selected_equipment == "aux_bus",
		"Back restores the previous workspace and selected equipment.")

	console.control_slider.value = 24.0
	_check(_setting("aux_bus", "limit") == 40.0, "A slider command waits for the next fixed step.")
	_tick(0.1)
	_check(_setting("aux_bus", "limit") == 24.0, "The fixed step commits the inspector command.")
	_tick(120.0)
	_follow_link("pump_b_feed")
	_follow_link("pump_b")
	_check(_near(_s("pump_b", "power"), 6.0) and _near(_s("pump_b", "flow"), 15.0),
		"The shared auxiliary limit leaves 6 kW and 15 L/s for pump B.")
	_check(not console.presenter.equipment_reason("pump_b").is_empty() and console.inspector_condition.text != "",
		"The pump inspector explains its reduced performance.")
	_follow_link("main_engine")
	_check(console.selected_equipment == "main_engine" and _near(_s("main_engine", "thrust"), 15.0),
		"Following pump B to the engine shows the resulting 15 percent thrust.")
	_check(console.reading_rows.any(func(row): return row.key.text == "Temperature trend" and row.value.text.contains("°C/min")),
		"The engine inspector includes the continuous temperature trend alongside its operating readings.")
	await _capture("limited.png")
	_press(console.back_button)
	_check(console.selected_equipment == "pump_b", "Back retraces the engine's cooling dependency.")
	_follow_link("pump_b_feed")
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
	_check(console.reading_rows.filter(func(row): return row.value.text.contains("°C/min")).size() == 2,
		"The exchanger inspector shows separate readings for both connected thermal masses.")
	await _capture("thermal.png")
	console.navigate("cooling", "radiator")
	_check(console.inspector_condition.text.begins_with("Closed") and console.inspector_condition.text.contains("°C/min"),
		"The radiator inspector shows its closed state together with the hot coolant observation.")
	var simultaneous_codes: Array = console.presenter.conditions().map(func(condition): return condition.code)
	_check("radiator.closed" in simultaneous_codes and "coolant.temperature_advisory" in simultaneous_codes,
		"The overview retains both the closed radiator and its thermal consequences.")
	await _capture("radiator-advisory.png")
	await _test_configuration_diagnostics()
	await _test_equipment_without_schematic()
	await _test_hidden_equipment_with_schematic_position()
	await _test_view_id_navigation()
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
	var missing_label = Fixtures.copy_kestrel()
	missing_label.component("reactor").definition.controls[0].erase("label")
	invalid_console = MainScene.instantiate()
	invalid_console.ship = console.Simulation.new(missing_label)
	invalid_console.presenter = console.Presenter.new(invalid_console.ship)
	root.add_child(invalid_console)
	await process_frame
	_check(invalid_console.has_node("ConfigurationError") and invalid_console.get_node("ConfigurationError").text.contains("label")
		and invalid_console.nav_buttons.is_empty(), "Missing control labels show a configuration error before an inspector can fail.")
	invalid_console.queue_free()

	print("%s: %d interface checks%s." % ["PASS" if failures == 0 else "FAIL", checks,
		"" if failures == 0 else " (%d failures)" % failures])
	quit(0 if failures == 0 else 1)


func _test_configuration_diagnostics() -> void:
	var definition = Fixtures.copy_kestrel()
	for i in range(definition.connections.size() - 1, -1, -1):
		if definition.connections[i].id == "feed_life_support":
			definition.connections.remove_at(i)
	for id in ["reactor", "aux_bus"]:
		definition.component(id).definition.controls.clear()
		definition.component(id).initial_settings.clear()
	console.hide()
	var original_console = console
	console = MainScene.instantiate()
	console.ship = console.Simulation.new(definition)
	console.presenter = console.Presenter.new(console.ship)
	root.add_child(console)
	console.set_process(false)
	await process_frame
	_check(console.ship_status.text == "1 condition to inspect" and console.condition_button.visible,
		"A disconnected service remains visible in the ship-wide condition display.")
	_press(console.condition_button)
	_check(console.current_system == "life_support" and console.selected_equipment == "" and console.summary_state.text == "Unpowered",
		"The disconnected service condition opens its summary without an equipment inspector.")
	await _capture("disconnected-service.png")
	console.navigate("power", "reactor")
	_check(console.inspector_condition.text == "Online" and console.control_widgets.is_empty()
		and console.reading_rows[1].value.text == "200.0 kW",
		"A fixed-capacity reactor inspector is online and exposes no unauthored controls.")
	await _capture("fixed-reactor.png")
	for view in definition.views:
		view.members.erase("life_support")
	console.ship.reset()
	console.presenter = console.Presenter.new(console.ship)
	console.navigate("overview")
	_check(console.ship_status.text == "1 condition to inspect" and console.conditions_label.visible
		and console.conditions_label.text.contains("unpowered") and not console.condition_button.visible,
		"A condition with no authored destination stays visible without a broken navigation button.")
	console.queue_free()
	console = original_console
	console.show()
	await process_frame


func _test_equipment_without_schematic() -> void:
	var definition = Fixtures.copy_kestrel()
	definition.layouts["power"].nodes.erase("battery")
	definition.view("power").members.append("life_support")
	console.hide()
	var original_console = console
	console = MainScene.instantiate()
	console.ship = console.Simulation.new(definition)
	console.presenter = console.Presenter.new(console.ship)
	root.add_child(console)
	console.set_process(false)
	await process_frame
	console.navigate("power")
	var listed = console.get("equipment_list_buttons")
	var reachable: bool = listed is Dictionary and listed.has("battery")
	_check(reachable and not console.equipment_buttons.has("battery"),
		"An isolated battery without schematic placement remains reachable in its workspace equipment list.")
	if reachable:
		_check(not listed.has("life_support"), "The equipment list respects non-inspectable service components.")
		await _capture("equipment-list.png")
		await _click_at_center(listed["battery"])
		_check(console.selected_equipment == "battery" and console.inspector_title.text == definition.component("battery").display_name,
			"A real click in the equipment list opens the isolated battery inspector.")
		_press(console.back_button)
		_check(console.selected_equipment == "" and console.equipment_list_buttons.has("battery"), "Back restores the workspace equipment list.")
		definition.layouts["power"].nodes.clear()
		console.navigate("overview")
		console.navigate("power")
		var inspectable_members: Array = definition.view("power").members.filter(func(id): return definition.component(id).inspectable)
		_check(console.equipment_buttons.is_empty() and console.equipment_list_buttons.size() == inspectable_members.size(),
			"A workspace without any schematic positions still lists every inspectable member.")
		_press(console.equipment_list_buttons["reactor"])
		console.control_slider.value = 150.0
		_tick(0.1)
		_check(console.selected_equipment == "reactor" and _setting("reactor", "limit") == 150.0,
			"Equipment opened from the list retains its working operating controls.")
	console.queue_free()
	console = original_console
	console.show()
	await process_frame


func _test_hidden_equipment_with_schematic_position() -> void:
	var definition = Fixtures.copy_kestrel()
	# This fixture tests hidden routing on a ship without player service ports.
	# A fitted service port requires an inspectable pump for operating shortcuts.
	definition.coolant_circuits.clear()
	definition.bypass_kits = 0
	definition.component("pump_b").inspectable = false
	# Put the hidden equipment's retained rectangle across another connection
	# so it would also force a visible detour if used as a routing obstacle.
	var pump_rect: Rect2 = definition.layouts["cooling"].nodes["pump_a"]
	var exchanger_rect: Rect2 = definition.layouts["cooling"].nodes["heat_exchanger"]
	var gap_x: float = (pump_rect.end.x + exchanger_rect.position.x) * 0.5
	definition.layouts["cooling"].nodes["pump_b"] = Rect2(gap_x - 8, pump_rect.get_center().y - 16, 16, 32)
	var authored_nodes: Dictionary = definition.layouts["cooling"].nodes.duplicate(true)
	_check(definition.validate().is_empty(), "Hidden equipment may retain an authored schematic position.")
	console.hide()
	var original_console = console
	console = MainScene.instantiate()
	console.ship = console.Simulation.new(definition)
	console.presenter = console.Presenter.new(console.ship)
	root.add_child(console)
	console.set_process(false)
	await process_frame
	console.navigate("cooling")
	_check(not console.equipment_buttons.has("pump_b") and not console.equipment_list_buttons.has("pump_b"),
		"A hidden pump has neither a schematic card nor an equipment-list entry.")
	var layout: Dictionary = console._workspace_nodes()
	var edges: Array = console._schematic_edges(layout)
	_check(edges.all(func(edge): return console.equipment_buttons.has(edge.from_component) and console.equipment_buttons.has(edge.to_component)),
		"Every drawn connection terminates at displayed equipment, with no dangling hidden-pump endpoint.")
	_check(not layout.has("pump_b"), "The drawing layout excludes the hidden pump as both an endpoint and a routing obstacle.")
	pump_rect = layout["pump_a"]
	exchanger_rect = layout["heat_exchanger"]
	var visible_route: PackedVector2Array = console._route_edge(pump_rect, exchanger_rect, layout)
	# Other visible context nodes can legitimately require a bend. Compare the
	# same physical ship with only its hidden placement removed, not an assumed
	# straight route that depends on the surrounding presentation layout.
	definition.layouts["cooling"].nodes.erase("pump_b")
	var without_hidden: Dictionary = console._workspace_nodes()
	var unretained_route: PackedVector2Array = console._route_edge(without_hidden["pump_a"], without_hidden["heat_exchanger"], without_hidden)
	definition.layouts["cooling"].nodes["pump_b"] = authored_nodes["pump_b"]
	_check(visible_route.size() >= 2 and visible_route == unretained_route,
		"A retained hidden rectangle cannot change the visible route compared with the same ship without that placement.")
	_check(edges.any(func(edge): return edge.from_component == "pump_a" and edge.to_component == "heat_exchanger" and edge.domain == "coolant" and edge.active),
		"Connections between the remaining visible equipment still appear active.")
	_check(edges.any(func(edge): return edge.from_component == "heat_exchanger" and edge.to_component == "radiator" and edge.domain == "thermal" and edge.active),
		"Thermal routes still collapse through the hidden coolant reservoir between visible equipment.")
	_check(definition.layouts["cooling"].nodes == authored_nodes,
		"Filtering the displayed schematic preserves the authored positions, including the hidden pump.")
	_check(_near(_s("pump_b", "flow"), 30.0) and _near(_s("main_engine", "thrust"), 30.0),
		"Hiding equipment does not remove its physical contribution to the running ship.")
	await _capture("hidden-equipment.png")
	console.queue_free()
	console = original_console
	console.show()
	await process_frame


func _test_view_id_navigation() -> void:
	var definition = Fixtures.copy_kestrel()
	definition.view("power")["id"] = "electrical"
	definition.layouts["electrical"] = definition.layouts["power"]
	definition.layouts.erase("power")
	console.hide()
	var original_console = console
	console = MainScene.instantiate()
	console.ship = console.Simulation.new(definition)
	console.presenter = console.Presenter.new(console.ship)
	root.add_child(console)
	console.set_process(false)
	await process_frame
	_press(console.nav_buttons["electrical"])
	_press(console.equipment_list_buttons["battery"])
	_check(console.current_system == "electrical" and console.selected_equipment == "battery"
		and is_instance_valid(console.inspector_title), "A renamed workspace still opens its equipment inspector.")
	_press(console.nav_buttons["overview"])
	_check(console.current_system == "overview" and console.overview_buttons.size() == 8,
		"The built-in overview remains reachable alongside renamed workspaces.")
	console.queue_free()
	definition.view("electrical")["id"] = "overview"
	definition.layouts["overview"] = definition.layouts["electrical"]
	definition.layouts.erase("electrical")
	console = MainScene.instantiate()
	console.ship = console.Simulation.new(definition)
	console.presenter = console.Presenter.new(console.ship)
	root.add_child(console)
	await process_frame
	_check(console.has_node("ConfigurationError") and console.get_node("ConfigurationError").text.contains("overview")
		and console.nav_buttons.is_empty(), "A reserved view ID shows a configuration error instead of broken navigation.")
	console.queue_free()
	console = original_console
	console.show()
	await process_frame


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
	_check(target != null and console.current_system == route.system
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
