extends SceneTree
## Complete the A/B repair loop in Cooling, with the live schematic always visible.
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
	_check(is_instance_valid(console.bypass_button), "Cooling exposes bypass installation beside the diagram.")
	await _click(console.bypass_button)
	await process_frame
	var panel = console.bypass_panel
	_check(is_instance_valid(panel) and panel is VBoxContainer and console.workspace_layer.is_ancestor_of(panel),
		"Bypass work occupies the equipment inspector, without a modal overlay.")
	_check(panel.selected_endpoints() == {"source_id": "", "circuit_id": ""},
		"Planning starts without silently selecting either coupling.")
	_check(panel.action_buttons.install.disabled and panel.target_selector.disabled,
		"Choose a donor before a compatible destination or installation.")
	await _click(console.coupling_buttons["source:pump_b"])
	await process_frame
	_check(console.bypass_panel.selected_endpoints() == {"source_id": "pump_b", "circuit_id": ""},
		"A real click chooses the donor coupling on the schematic.")
	_check(console.coupling_buttons["target:drive_loop"].disabled,
		"The donor's own circuit is not an eligible bypass destination.")
	await _click(console.coupling_buttons["target:core_loop"])
	await process_frame
	panel = console.bypass_panel
	_check(panel.selected_endpoints() == {"source_id": "pump_b", "circuit_id": "core_loop"},
		"A second schematic coupling completes the proposed route.")
	_check(panel.action_buttons.install.disabled and not panel.action_reason.text.is_empty(),
		"The proposal explains why installation is blocked while pumps are energized.")
	_check(_network_visible(), "The full network remains visible beside the bypass prerequisites.")
	_check(_couplings_fit(), "Planning coupling controls fit inside their cards without overlapping each other.")
	await _capture("bypass-planning.png")
	await _key(KEY_P)
	_check(console.ship.paused and panel.action_buttons.install.disabled,
		"The console pause shortcut freezes work without hiding the diagram.")
	await _key(KEY_P)

	_select_pump("pump_a")
	console.open_maintenance("pump_a")
	_press(console.maintenance_panel.action_buttons.simulate_wear)
	_tick(0.1)
	console.close_maintenance()
	_check(console.ship.maintenance_info("pump_a").efficiency < 0.9,
		"The inline service section can introduce pump A's worn condition.")
	for id in ["pump_a", "pump_b"]:
		_select_pump(id)
		_press(console.quick_controls.buttons.feeder)
		_tick(0.1)
		_press(console.inspector_controls.buttons.primary)
		_tick(0.1)
		_check(console.current_system == "cooling", "Electrical and coolant isolation keep the Cooling view in place.")
		await process_frame
		_check(_couplings_fit(), "Couplings remain inside cards and clear of the expanded isolation controls.")
	console.open_bypass()
	await process_frame
	panel = console.bypass_panel
	_check(panel.selected_endpoints() == {"source_id": "pump_b", "circuit_id": "core_loop"},
		"The proposed route survives selecting and isolating its equipment.")
	_check(not panel.action_buttons.install.disabled, "Isolated endpoints enable installation in the same inspector.")
	_press(panel.action_buttons.install)
	_tick(0.1)
	_check(console.ship.bypass_info().job == "install", "The install action starts timed physical work.")
	_check(panel.source_selector.disabled and panel.target_selector.disabled,
		"Endpoints remain locked throughout installation.")
	panel.set_source("pump_a")
	_check(panel.selected_endpoints().source_id == "pump_b", "Programmatic endpoint selection also respects active work.")
	_check(_network_visible(), "Installation progress leaves the live network visible.")
	_tick(11.0)
	var info: Dictionary = console.ship.bypass_info()
	_check(info.installed and info.source_id == "pump_b" and info.circuit_id == "core_loop" and not info.open,
		"The completed bypass is fitted closed on the chosen route.")
	_check(is_instance_valid(console.route_button), "The fitted connection is selectable on the schematic.")
	_check(_near(panel.flow_slider.max_value, 24.0), "Diversion is limited by the kit's 24 L/s rating.")
	_press(panel.action_buttons.open)
	_tick(0.1)
	_select_pump("pump_a")
	_check(console.inspector_controls.buttons.primary.disabled and console.quick_controls.buttons.primary.disabled,
		"Both operating surfaces enforce the destination valve interlock.")
	_select_pump("pump_b")
	_press(console.quick_controls.buttons.primary)
	_tick(0.1)
	_press(console.quick_controls.buttons.feeder)
	_tick(0.1)
	console.quick_controls.sliders.flow.value = 40.0
	_tick(60.0)
	_check(_near(console.inspector_controls.sliders.flow.value, 40.0),
		"Diagram flow changes synchronize the inspector's requested value.")
	info = console.ship.bypass_info()
	_check(_near(info.delivered_flow, 24.0) and _near(info.source_remaining_flow, 16.0)
		and _near(console.ship.components.main_engine.state.thrust, 16.0),
		"B's actual flow is split into 24 L/s core cooling and 16 percent engine thrust.")
	_check(console.ship.components.main_bus.settings.closed and console.ship.components.life_support.state.power > 0.0,
		"Local pump isolation leaves the main bus and life support energized.")
	var links: Array = console.presenter.links("pump_b")
	_check(links.any(func(link): return link.equipment == "heat_exchanger"),
		"Installed routing appears in equipment dependencies.")
	var edges: Array = console.presenter.schematic_edges(["pump_a", "pump_b", "heat_exchanger", "main_engine", "radiator"])
	_check(edges.any(func(edge): return edge.from_component == "pump_b" and edge.to_component == "heat_exchanger" and edge.active),
		"The schematic shows committed circulation through the installed route.")
	await _capture("bypass-schematic.png")
	var before_line_click: Dictionary = console.ship.snapshot()
	var line_point: Vector2 = _exposed_bypass_point()
	_check(line_point.is_finite(), "The installed bypass has an exposed line segment outside equipment and control targets.")
	if line_point.is_finite():
		await _click_at(root.get_final_transform() * (console.get_global_transform_with_canvas() * line_point))
		_check(is_instance_valid(console.bypass_panel) and console.bypass_panel.info_labels.flow.text.contains("24.0"),
			"A real mouse click on the green bypass line opens the connection inspector.")
		_check(console.ship.snapshot() == before_line_click,
			"Selecting the bypass line submits no operating command or simulation mutation.")
	_select_pump("pump_b")
	await _click(console.route_button)
	await process_frame
	_check(is_instance_valid(console.bypass_panel) and console.bypass_panel.info_labels.flow.text.contains("24.0"),
		"Clicking the fitted connection exposes its committed delivery in the inspector.")
	await _capture("bypass-operating.png")

	_select_pump("pump_a")
	_check(is_instance_valid(console.maintenance_panel) and not console.maintenance_panel.action_buttons.replace.disabled,
		"Pump A's normal inspector offers repair while incoming bypass cooling remains active.")
	_press(console.maintenance_panel.action_buttons.replace)
	_tick(5.0)
	_check(console.ship.maintenance_info("pump_a").job == "replace"
		and _near(console.ship.components.main_engine.state.thrust, 16.0) and _network_visible(),
		"Repair progresses while reduced propulsion and the live network remain visible.")
	await _capture("bypass-during-repair.png")
	var kestrel = console.ship
	var parked: Dictionary = kestrel.snapshot()
	console.select_ship("tern")
	await process_frame
	_check(not is_instance_valid(console.bypass_panel), "Changing ships detaches the previous ship's connection controls.")
	_tick(30.0)
	_check(kestrel.snapshot() == parked, "The inactive ship parks its route, inventory, and unfinished repair.")
	console.select_ship("kestrel")
	console.navigate("cooling")
	_tick(30.0)
	_check(_near(kestrel.maintenance_info("pump_a").efficiency, 1.0), "Replacement finishes under bypass supply when the ship is active again.")
	console.open_bypass()
	await process_frame
	_press(console.bypass_panel.action_buttons.close)
	_tick(0.1)
	_select_pump("pump_a")
	_press(console.quick_controls.buttons.primary)
	_tick(0.1)
	_press(console.quick_controls.buttons.feeder)
	_tick(0.1)
	_select_pump("pump_b")
	console.inspector_controls.sliders.flow.value = 30.0
	_tick(120.0)
	_check(_near(kestrel.components.main_engine.state.thrust, 30.0) and _near(kestrel.totals().output, 152.0),
		"Restoring the original routes returns Kestrel to normal cruise.")
	for id in ["pump_a", "pump_b"]:
		_select_pump(id)
		_press(console.quick_controls.buttons.feeder)
		_tick(0.1)
		_press(console.quick_controls.buttons.primary)
		_tick(0.1)
	console.open_bypass()
	await process_frame
	_press(console.bypass_panel.action_buttons.remove)
	_tick(11.0)
	info = kestrel.bypass_info()
	_check(not info.installed and info.kits == 1, "Isolated removal recovers the reusable kit.")
	_check(not console.presenter.links("pump_b").any(func(link): return link.equipment == "heat_exchanger"),
		"Removing the kit removes its dependency edge.")
	_check(console.current_system == "cooling" and _network_visible(),
		"The complete install, operate, repair, restore, and remove workflow stays in Cooling.")
	await _key(KEY_ESCAPE)
	_check(not is_instance_valid(console.bypass_panel), "Escape returns from connection editing to equipment.")
	_press(console.reset_button)
	_check(not kestrel.bypass_info().installed and kestrel.bypass_info().kits == 1
		and console.presenter.conditions().is_empty(), "Reset restores native routing and the uninstalled inventory.")
	print("%s: %d bypass interface checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _select_pump(id: String) -> void:
	_press(console.equipment_buttons[id])
	_check(console.current_system == "cooling" and console.selected_equipment == id,
		"Selecting " + id + " retains the Cooling workspace.")


func _network_visible() -> bool:
	for id in ["pump_a", "pump_b", "heat_exchanger", "main_engine", "radiator"]:
		if not console.equipment_buttons.has(id) or not console.equipment_buttons[id].is_visible_in_tree():
			return false
		if is_instance_valid(console.bypass_panel) and console.bypass_panel.get_global_rect().intersects(console.equipment_buttons[id].get_global_rect()):
			return false
	return true


func _couplings_fit() -> bool:
	var occupied: Array[Rect2] = []
	for button in console.coupling_buttons.values():
		var bounds: Rect2 = button.get_global_rect()
		var card = button.get_parent()
		if not card is Button or not card.get_global_rect().encloses(bounds):
			return false
		for other in occupied:
			if bounds.intersects(other):
				return false
		if is_instance_valid(console.quick_controls) and bounds.intersects(console.quick_controls.get_global_rect()):
			return false
		occupied.append(bounds)
	return not occupied.is_empty()


func _exposed_bypass_point() -> Vector2:
	var layout: Dictionary = console._workspace_nodes()
	var longest: float = 0.0
	var point := Vector2.INF
	for edge in console.presenter.schematic_edges(layout.keys()):
		if not edge.get("bypass", false) or not edge.active:
			continue
		var path: PackedVector2Array = console._route_edge(layout[edge.from_component], layout[edge.to_component], layout)
		for index in range(path.size() - 1):
			var length: float = path[index].distance_to(path[index + 1])
			var candidate: Vector2 = path[index].lerp(path[index + 1], 0.5)
			if length <= maxf(longest, 32.0):
				continue
			if layout.values().any(func(rect): return rect.grow(8).has_point(candidate)):
				continue
			if is_instance_valid(console.route_button) and console.route_button.get_rect().has_point(candidate):
				continue
			point = candidate
			longest = length
	return point


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
	await _click_at(position)


func _click_at(position: Vector2) -> void:
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
