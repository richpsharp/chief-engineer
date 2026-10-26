extends SceneTree
## Both playable ships use the same console and retain independent parked sessions.

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
	console.set_process(false)
	await process_frame
	await process_frame
	_check(console.ship.definition.id == "kestrel" and _selected_id() == "kestrel",
		"The console and ship selector start on Kestrel.")
	_check(_choice_index("kestrel") >= 0 and _choice_index("tern") >= 0,
		"The selector offers both playable ship definitions.")
	console.navigate("power", "aux_bus")
	console.control_slider.value = 24.0
	_tick(1.0)
	var kestrel = console.ship
	var parked_kestrel: Dictionary = kestrel.snapshot()
	_check(_near(kestrel.components["aux_bus"].settings.limit, 24.0),
		"Kestrel can be operated before switching ships.")
	if DisplayServer.get_name() != "headless":
		await _click_at_center(console.ship_selector)
		_check(console.ship_selector.get_popup().visible, "A real mouse click opens the ship selector.")
	_select("tern")
	await process_frame
	_check(console.ship.definition.id == "tern" and console.ship != kestrel and _selected_id() == "tern",
		"Selecting the popup item loads Tern through the OptionButton signal chain.")
	_check(console.current_system == "overview" and console.selected_equipment.is_empty()
		and console.history.is_empty() and console.back_button.disabled,
		"Switching ships starts a fresh navigation trail without a stale inspector.")
	_check(root.title.contains("Tern") and console.presenter.conditions().is_empty()
		and console.ship_status.text == "All systems nominal",
		"Tern's title and healthy overview readings replace Kestrel's display.")
	await _capture("tern-overview.png")
	_test_navigation()
	console.navigate("power", "port_pump_feed")
	await _capture("tern-power.png")
	console.navigate("cooling")
	await _capture("tern-cooling.png")
	for side in ["port", "starboard"]:
		await _test_branch_controls(side)
	_test_session_isolation(kestrel, parked_kestrel)
	_test_invalid_catalog_choice()
	await process_frame
	print("%s: %d ship-selection interface checks%s." % ["PASS" if failures == 0 else "FAIL", checks,
		"" if failures == 0 else " (%d failures)" % failures])
	quit(0 if failures == 0 else 1)


func _test_navigation() -> void:
	var before: Dictionary = console.ship.snapshot()
	var pages_open := true
	for view in console.ship.definition.views:
		console.navigate("overview")
		_press(console.overview_buttons[view.id])
		pages_open = pages_open and console.current_system == view.id
	_check(pages_open and console.overview_buttons.is_empty(), "Every Tern system opens directly from the shared overview.")
	var inspectors_open := true
	for spec in console.ship.definition.components:
		if not spec.inspectable:
			continue
		console.navigate(console.ship.definition.workspace_for(spec.id))
		if not console.equipment_list_buttons.has(spec.id):
			inspectors_open = false
			continue
		_press(console.equipment_list_buttons[spec.id])
		inspectors_open = inspectors_open and console.selected_equipment == spec.id
		inspectors_open = inspectors_open and is_instance_valid(console.inspector_title)
		inspectors_open = inspectors_open and console.inspector_title.text == spec.display_name and not console.reading_rows.is_empty()
	_check(inspectors_open, "Every inspectable Tern component is reachable through its workspace equipment list.")
	_check(console.ship.snapshot() == before, "Exploring Tern does not mutate its operating state.")
	console.navigate("propulsion")
	_check(console.summary_value.text.contains("mean thrust"), "The shared propulsion summary handles Tern's two engines.")
	console.navigate("power")
	_check(not console.equipment_buttons.has("aux_bus") and console.equipment_list_buttons.has("port_pump_feed"),
		"Workspace controls contain Tern equipment rather than stale Kestrel cards.")


func _test_branch_controls(side: String) -> void:
	console.ship.reset()
	var other: String = "starboard" if side == "port" else "port"
	var feed: String = side + "_pump_feed"
	var pump: String = side + "_pump"
	var engine: String = side + "_engine"
	var healthy_thrust: float = console.ship.components[engine].state.thrust
	console.navigate("power", feed)
	_check(console.breaker_button != null and not console.breaker_button.disabled,
		"The %s pump feeder exposes a working breaker." % side)
	_press(console.breaker_button)
	_tick(0.1)
	_check(not console.ship.components[feed].settings.closed and _near(console.ship.components[pump].state.flow, 0.0)
		and _near(console.ship.components[engine].state.thrust, 0.0)
		and _near(console.ship.components[other + "_engine"].state.thrust, healthy_thrust),
		"Opening the %s pump feeder stops only its associated engine's thrust." % side)
	_check(console.ship.components[side + "_bus"].settings.closed
		and console.presenter.equipment_status(engine) == "Cooling limited",
		"The %s engine retains its electrical branch and correctly reports a cooling limitation." % side)
	_follow_link(pump)
	_check(console.current_system == "power" and console.selected_equipment == pump,
		"The %s feeder's dependency link selects its pump while retaining Power." % side)
	_follow_link(engine)
	_check(console.selected_equipment == engine and console.inspector_condition.text.begins_with("Cooling limited"),
		"Following the %s pump reaches the affected engine inspector." % side)
	if side == "port":
		await _capture("tern-port-fault.png")
	_follow_link(pump)
	_follow_link(feed)
	_press(console.breaker_button)
	_tick(1.0)
	_check(console.ship.components[pump].state.flow > 0.0 and console.ship.components[engine].state.thrust < healthy_thrust,
		"Restoring the %s feeder begins gradual recovery through the same controls." % side)
	_tick(120.0)
	_check(_near(console.ship.components[engine].state.thrust, healthy_thrust)
		and _near(console.ship.components[other + "_engine"].state.thrust, healthy_thrust)
		and console.presenter.conditions().is_empty(), "The %s branch returns to healthy cruise." % side)


func _test_session_isolation(kestrel, parked_kestrel: Dictionary) -> void:
	var tern = console.ship
	_check(tern.command("port_engine", "thrust", 16.0).accepted, "Tern accepts a command queued before switching ships.")
	_press(console.pause_button)
	var parked_tern: Dictionary = tern.snapshot()
	_select("kestrel")
	_check(console.ship == kestrel and kestrel.snapshot() == parked_kestrel,
		"Returning to Kestrel restores its existing runtime without advancing it while parked.")
	var before_elapsed: float = kestrel.elapsed
	console._process(0.1)
	_check(kestrel.elapsed > before_elapsed and tern.snapshot() == parked_tern,
		"The console advances only the selected ship, leaving Tern's pause and queued command intact.")
	_press(console.reset_button)
	_check(_near(kestrel.components["aux_bus"].settings.limit, 40.0) and tern.snapshot() == parked_tern,
		"Reset affects the selected Kestrel without resetting parked Tern.")
	_select("tern")
	_check(console.ship == tern and tern.snapshot() == parked_tern and console.pause_button.text.contains("Resume")
		and console.running_label.text.contains("PAUSED"), "Tern's paused runtime and pause controls return together.")
	_tick(1.0)
	_check(tern.snapshot() == parked_tern, "A paused ship's pending command stays queued after reselection.")
	_press(console.pause_button)
	_tick(0.1)
	_check(_near(tern.components["port_engine"].settings.thrust, 16.0)
		and _near(kestrel.components["aux_bus"].settings.limit, 40.0),
		"Resuming commits Tern's own queued command without changing Kestrel.")
	console._show_log()
	_check(console.event_log.text == "\n\n".join(tern.events), "The rebuilt engineering log contains only the selected ship's history.")
	console.log_dialog.hide()
	console.navigate("cooling", "port_engine")
	var before: Dictionary = tern.snapshot()
	var history_size: int = console.history.size()
	_check(not console.select_ship("missing_ship") and console.ship == tern and tern.snapshot() == before
		and console.selected_equipment == "port_engine" and console.history.size() == history_size,
		"An unknown ship selection leaves the current simulation and navigation unchanged.")
	_check(console.select_ship("tern") and console.selected_equipment == "port_engine" and tern.snapshot() == before,
		"Selecting the current ship does not reset its inspector or state.")
	_press(console.reset_button)
	_check(console.presenter.conditions().is_empty() and _near(tern.components["port_engine"].settings.thrust, 20.0),
		"Reset restores the selected Tern to its authored healthy configuration.")


func _test_invalid_catalog_choice() -> void:
	var tern_definition: Resource = load("res://ships/tern.tres")
	var original_schema: int = tern_definition.schema_version
	tern_definition.schema_version = -1
	# A fresh console cannot reuse the valid Tern runtime from the earlier checks.
	var previous_console = console
	console = MainScene.instantiate()
	root.add_child(console)
	console.set_process(false)
	console.navigate("power", "aux_bus")
	console.control_slider.value = 24.0
	_tick(1.0)
	var kestrel = console.ship
	var before: Dictionary = kestrel.snapshot()
	var previous_history: Array = console.history.duplicate(true)
	var tern_index: int = _choice_index("tern")
	var disabled_choice: bool = console.ship_selector.is_item_disabled(tern_index)
	var tooltip: String = console.ship_selector.get_item_tooltip(tern_index)
	# Deliver the native signal even if the popup item is disabled, so a rejected
	# callback must also restore the displayed selection to the running ship.
	_select("tern")
	var rejected_runtime_unchanged: bool = console.ship == kestrel and kestrel.snapshot() == before
	var rejected_navigation_unchanged: bool = console.current_system == "power" \
		and console.selected_equipment == "aux_bus" and console.history == previous_history
	var rejected_selection: String = _selected_id()
	# Restore the shared cached resource before assertions or leaving this helper.
	tern_definition.schema_version = original_schema
	root.remove_child(console)
	console.queue_free()
	console = previous_console
	_check(disabled_choice and tooltip.contains("Unsupported ship schema version: -1"),
		"An invalid catalog ship is disabled with its definition validation error as a tooltip.")
	_check(rejected_runtime_unchanged and rejected_navigation_unchanged,
		"A rejected invalid ship preserves Kestrel's runtime, settings, and navigation.")
	_check(rejected_selection == "kestrel",
		"A rejected popup selection restores the selector to the ship that is still running.")


func _choice_index(ship_id: String) -> int:
	for i in range(console.ship_selector.item_count):
		if str(console.ship_selector.get_item_metadata(i)) == ship_id:
			return i
	return -1


func _selected_id() -> String:
	return str(console.ship_selector.get_item_metadata(console.ship_selector.selected))


func _select(ship_id: String) -> void:
	var index: int = _choice_index(ship_id)
	if index < 0:
		_check(false, "Missing ship selector choice: " + ship_id)
		return
	# Exercise PopupMenu -> OptionButton -> console, including rebuilding the
	# selector while its popup callback is still executing.
	var selector: OptionButton = console.ship_selector
	selector.get_popup().index_pressed.emit(index)


func _tick(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0:
		var step: float = minf(remaining, 10.0)
		console.ship.tick(step)
		remaining -= step
	console._refresh()
	console.queue_redraw()


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


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.01


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
