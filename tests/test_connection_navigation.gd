extends SceneTree
## Follow actual ship connections into operating workspaces without commanding machinery.

const MainScene = preload("res://scenes/main.tscn")
const Fixtures = preload("res://tests/ship_fixtures.gd")
const Simulation = preload("res://scripts/ship_simulation.gd")
const Presenter = preload("res://scripts/presentation/ship_presenter.gd")
var console
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var collision = Fixtures.copy_kestrel()
	collision.views.append({"id": "connections", "name": "Collision", "kind": "summary", "summary_kind": "load", "members": ["life_support"]})
	_check(collision.validate().any(func(error): return error.contains("'connections' is reserved")),
		"Authored departments cannot shadow the built-in Connections destination.")
	console = MainScene.instantiate()
	root.add_child(console)
	current_scene = console
	console.set_process(false)
	await _settle()
	var before: Dictionary = console.ship.snapshot()
	await _click(console.nav_buttons.connections)
	_check(console.current_system == "connections" and console.map_domain == "power",
		"Connections opens the electrical map from the sidebar.")
	_check(_has_edge("reactor", "main_bus", "power") and _has_edge("main_bus", "main_engine", "power"),
		"Kestrel's engine has a visible electrical path through its actual distribution bus.")
	_check(_has_edge("main_bus", "life_support", "power") and console.connection_map.buttons.has("life_support"),
		"The electrical map includes life support and its real supplying bus.")
	_check(console.connection_map.buttons.has("battery")
		and not console.connection_map.edges.any(func(edge): return edge.from_component == "battery" or edge.to_component == "battery"),
		"The reserve battery remains visibly disconnected instead of receiving an invented supply path.")
	_check_map_geometry("Kestrel power")
	await _capture("connections-kestrel-power.png")
	console.connection_map.buttons.main_engine.grab_focus()
	await _key(KEY_ENTER)
	_check(console.current_system == "power" and console.selected_equipment == "main_engine",
		"Keyboard selection of an engine in the electrical map opens its Power inspector.")
	_check(console.ship.snapshot() == before, "Entering equipment through the map does not advance or operate the ship.")
	_check(console.workspace_buttons.has("power") and console.workspace_buttons.has("cooling"),
		"An engine offers explicit links to both of its operating networks.")
	await _click(console.workspace_buttons.cooling)
	_check(console.current_system == "cooling" and console.selected_equipment == "main_engine",
		"The Cooling shortcut retains the engine being inspected.")
	await _click(console.trace_button)
	_check(console.current_system == "connections" and console.map_domain == "cooling"
		and console.connection_map.focus_id == "main_engine",
		"Tracing an engine from Cooling opens its highlighted cooling relationships.")
	_check(_has_edge("reactor", "heat_exchanger", "thermal")
		and _has_edge("heat_exchanger", "coolant_reservoir", "thermal")
		and _has_edge("main_engine", "coolant_reservoir", "thermal")
		and _has_edge("coolant_reservoir", "radiator", "thermal"),
		"Cooling shows the reactor and engine heat paths through the explicit shared coolant inventory.")
	_check(not console.connection_map.buttons.has("life_support")
		and console.connection_map.edges.all(func(edge): return edge.domain in ["coolant", "thermal"]),
		"Cooling does not imply a cabin thermal model or an electrical path where none exists.")
	_check_map_geometry("Kestrel cooling")
	await _capture("connections-kestrel-cooling.png")
	await _click(console.connection_map.buttons.reactor)
	_check(console.current_system == "cooling" and console.selected_equipment == "reactor",
		"Clicking the cooling map's reactor opens its thermal context, despite its Power home workspace.")
	_press(console.back_button)
	_check(console.current_system == "connections" and console.map_domain == "cooling"
		and console.connection_map.focus_id == "main_engine",
		"Back restores the previous map layer and highlighted component.")
	_press(console.back_button)
	_check(console.current_system == "cooling" and console.selected_equipment == "main_engine",
		"A second Back returns to the originating equipment and workspace.")

	console.navigate("cooling")
	_check(console.endpoint_buttons.has("reactor"), "The operating Cooling schematic exposes its missing reactor endpoint.")
	await _click(console.endpoint_buttons.reactor)
	_check(console.current_system == "power" and console.selected_equipment == "reactor",
		"The reactor's labelled endpoint opens its Power workspace.")
	console.navigate("power")
	_check(console.endpoint_buttons.has("main_engine"), "The operating Power schematic exposes its engine consumer.")
	await _click(console.endpoint_buttons.main_engine)
	_check(console.current_system == "cooling" and console.selected_equipment == "main_engine",
		"The engine's labelled endpoint opens its Cooling workspace.")
	_check(console.ship.snapshot() == before, "Following operating-schematic endpoints remains read-only navigation.")

	console.open_connections("power", "life_support")
	await _click(console.connection_map.buttons.life_support)
	_check(console.current_system == "power" and console.selected_equipment == "life_support"
		and console.inspector_title.text == "Life support",
		"A service load can be inspected directly from its electrical connection.")
	_check(console.control_widgets.is_empty() and not is_instance_valid(console.maintenance_panel),
		"Read-only life-support telemetry does not invent machinery or repair controls.")
	_check(console.workspace_buttons.has("power") and not console.workspace_buttons.has("cooling")
		and console.reading_rows.any(func(row): return row.key.text == "Power supplied"),
		"Life support reports electrical supply and offers only its modelled network.")
	_press(console.back_button)
	_check(console.current_system == "connections" and console.map_domain == "power"
		and console.connection_map.focus_id == "life_support",
		"Back also restores map focus for a read-only service component.")
	await _click(console.map_domain_buttons.cooling)
	_check(console.map_domain == "cooling", "The Cooling layer selector changes the visible relationship domain.")
	await _click(console.connection_map.buttons.coolant_reservoir)
	_check(console.current_system == "cooling" and console.selected_equipment == "coolant_reservoir"
		and console.reading_rows.any(func(row): return row.key.text == "Temperature"),
		"Shared coolant has a read-only inspector with its own temperature measurement.")
	_check(console.ship.snapshot() == before, "Reading service loads and shared coolant never changes simulation state.")

	console.open_connections("power", "main_engine")
	_press(console.pause_button)
	before = console.ship.snapshot()
	await _click(console.connection_map.buttons.main_engine)
	_check(console.current_system == "power" and not console.inspector_controls.sliders.thrust.editable,
		"Paused navigation still opens equipment while its operating control remains locked.")
	_press(console.back_button)
	_tick(10.0)
	_check(console.ship.snapshot() == before, "Map navigation and refresh preserve a paused snapshot.")
	_press(console.pause_button)
	var engine_button: Button = console.connection_map.buttons.main_engine
	engine_button.grab_focus()
	console.ship.command("main_bus", "closed", false)
	_tick(0.1)
	_check(_has_edge("main_bus", "main_engine", "power", false)
		and _has_edge("main_bus", "life_support", "power", false),
		"Opening the main breaker leaves its physical paths visible but inactive.")
	_check(console.connection_map.buttons.main_engine == engine_button and engine_button.has_focus(),
		"Reading updates preserve the focused map button instead of rebuilding the whole map.")
	await _capture("connections-isolated-power.png")
	console.ship.reset()
	console._refresh()
	_check(_has_edge("main_bus", "main_engine", "power", true),
		"Reset restores the live electrical path in the already-open map.")
	await _test_bypass_refresh()
	await _test_tern()
	await _check_operating_routes()
	await _test_overlapping_workspace_members()
	print("%s: %d connection-navigation checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _test_bypass_refresh() -> void:
	console.open_connections("cooling", "pump_b")
	for feeder in ["pump_a_feed", "pump_b_feed"]:
		console.ship.command(feeder, "closed", false)
	for circuit in ["core_loop", "drive_loop"]:
		console.ship.bypass_command("set_primary", {"circuit_id": circuit, "open": false})
	_tick(0.1)
	_check(console.ship.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"}).accepted,
		"A valid isolated installation can change topology while the map is open.")
	_tick(11.0)
	_check(console.connection_map.edges.filter(func(edge): return edge.get("bypass", false)).size() == 2
		and console.connection_map.edges.filter(func(edge): return edge.get("bypass", false)).all(func(edge): return not edge.active),
		"A fitted closed bypass appears immediately as inactive connections to the destination circuit.")
	var distinct_ports: bool = true
	for bypass in console.connection_map.edges.filter(func(edge): return edge.get("bypass", false)):
		for native in console.connection_map.edges.filter(func(edge): return edge.domain == "coolant" and not edge.get("bypass", false) and edge.to_component == bypass.to_component):
			var bypass_path: PackedVector2Array = console.connection_map.edge_path(bypass)
			var native_path: PackedVector2Array = console.connection_map.edge_path(native)
			distinct_ports = distinct_ports and not bypass_path[-1].is_equal_approx(native_path[-1])
	_check(distinct_ports, "Bypass and native routes enter separate visible ports so the fitted line does not hide the isolated route.")
	_check_map_geometry("Kestrel fitted bypass")
	console.ship.command("pump_b_feed", "closed", true)
	console.ship.bypass_command("set_primary", {"circuit_id": "drive_loop", "open": true})
	_tick(0.1)
	console.ship.bypass_command("open")
	_tick(30.0)
	_check(console.connection_map.edges.filter(func(edge): return edge.get("bypass", false)).all(func(edge): return edge.active),
		"Opening the supplied bypass lights its actual circulation paths in the map.")
	await _capture("connections-bypass-open.png")
	console.ship.bypass_command("close")
	_tick(0.1)
	_check(console.connection_map.edges.filter(func(edge): return edge.get("bypass", false)).size() == 2
		and console.connection_map.edges.filter(func(edge): return edge.get("bypass", false)).all(func(edge): return not edge.active),
		"Closing the bypass preserves fitted topology while removing its active-flow indication.")
	console.ship.command("pump_b_feed", "closed", false)
	console.ship.bypass_command("set_primary", {"circuit_id": "drive_loop", "open": false})
	_tick(0.1)
	console.ship.bypass_command("remove")
	_tick(11.0)
	_check(not console.connection_map.edges.any(func(edge): return edge.get("bypass", false)),
		"Removing the kit removes its map paths without reopening the view.")
	console.ship.reset()
	console._refresh()


func _test_tern() -> void:
	console.select_ship("tern")
	var before: Dictionary = console.ship.snapshot()
	console.open_connections("power")
	_check(_has_edge("utility_reactor", "distribution_bus", "power")
		and _has_edge("distribution_bus", "port_bus", "power")
		and _has_edge("distribution_bus", "starboard_bus", "power")
		and _has_edge("port_bus", "port_engine", "power")
		and _has_edge("starboard_bus", "starboard_engine", "power"),
		"Tern's power map traces both engines through their separate buses and shared source.")
	_check_map_geometry("Tern power")
	await _capture("connections-tern-power.png")
	await _click(console.connection_map.buttons.starboard_engine)
	_check(console.current_system == "power" and console.selected_equipment == "starboard_engine",
		"A real pointer click reaches the selected Tern engine in its electrical context.")
	await _click(console.workspace_buttons.cooling)
	await _click(console.trace_button)
	_check(_has_edge("utility_reactor", "core_exchanger", "thermal")
		and _has_edge("port_engine", "coolant_reservoir", "thermal")
		and _has_edge("starboard_engine", "coolant_reservoir", "thermal"),
		"Tern's cooling map includes both engines and the reactor's shared heat-rejection dependency.")
	_check_map_geometry("Tern cooling")
	_check(console.ship.snapshot() == before, "Exploring Tern's two domains leaves its healthy initial state unchanged.")
	await _capture("connections-tern-cooling.png")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1152, 720)
		await _settle()
		await _capture("connections-minimum-cooling.png")
		await _click(console.map_domain_buttons.power)
		_check(console.map_domain == "power", "Layer controls remain clickable at the minimum supported window size.")
		await _capture("connections-minimum-power.png")
		await _click(console.connection_map.buttons.port_engine)
		_check(console.current_system == "power" and console.selected_equipment == "port_engine",
			"Equipment navigation remains clickable at the minimum supported window size.")


func _has_edge(source: String, target: String, domain: String, active = null) -> bool:
	return console.connection_map.edges.any(func(edge):
		return (edge.from_component == source and edge.to_component == target and edge.domain == domain
			and (active == null or edge.active == active)))


func _test_overlapping_workspace_members() -> void:
	var definition = Fixtures.copy_kestrel()
	for view in definition.views:
		if view.id == "power":
			view.members.append("pump_a")
	console.ship = Simulation.new(definition)
	console.presenter = Presenter.new(console.ship)
	console.current_system = "overview"
	console.selected_equipment = ""
	console.history.clear()
	console._build_console()
	console.navigate("power")
	_check(not console._is_cooling_view("power") and console.endpoint_buttons.has("main_engine")
		and not is_instance_valid(console.bypass_button),
		"Adding a pump to Power's membership does not reclassify its domain or replace its engine endpoint with cooling UI.")
	await _click(console.trace_button)
	_check(console.current_system == "connections" and console.map_domain == "power"
		and _has_edge("main_bus", "main_engine", "power"),
		"Tracing a mixed-membership Power workspace still opens the electrical graph.")


func _check_operating_routes() -> void:
	for ship_id in ["kestrel", "tern"]:
		console.select_ship(ship_id)
		for workspace in ["power", "cooling"]:
			console.navigate(workspace)
			var selections: Array = [""]
			selections.append_array(console.equipment_buttons.keys())
			var crossing: String = ""
			var own_domain: bool = true
			var critical_paths: bool = true
			for selected in selections:
				console.navigate(workspace, selected)
				await _settle()
				var layout: Dictionary = console._workspace_nodes()
				var rendered: Array = console._schematic_edges(layout)
				own_domain = own_domain and rendered.all(func(edge): return edge.domain == "power" if workspace == "power" else edge.domain in ["coolant", "thermal"])
				for actual in console.presenter.connections:
					var engine_supply: bool = workspace == "power" and actual.domain == "power" and console.ship.components[actual.to_component].kind == "engine"
					var reactor_heat: bool = workspace == "cooling" and actual.domain == "thermal" and console.ship.components[actual.from_component].kind == "reactor"
					if engine_supply or reactor_heat:
						critical_paths = critical_paths and rendered.any(func(edge): return edge.from_component == actual.from_component and edge.to_component == actual.to_component and edge.domain == actual.domain)
				for edge in rendered:
					var path: PackedVector2Array = console._route_edge(layout[edge.from_component], layout[edge.to_component], layout)
					if path.size() < 2:
						crossing = "Missing route for %s → %s" % [edge.from_component, edge.to_component]
						continue
					if not layout[edge.from_component].grow(0.1).has_point(path[0]) or not layout[edge.to_component].grow(0.1).has_point(path[-1]):
						crossing = "Detached endpoint for %s → %s" % [edge.from_component, edge.to_component]
					for id in layout:
						if id in [edge.from_component, edge.to_component]:
							continue
						for index in range(path.size() - 1):
							var start: Vector2 = path[index]
							var finish: Vector2 = path[index + 1]
							var segment := Rect2(Vector2(minf(start.x, finish.x), minf(start.y, finish.y)),
								Vector2(maxf(absf(start.x - finish.x), 0.01), maxf(absf(start.y - finish.y), 0.01)))
							if segment.intersects(layout[id].grow(-0.1)):
								crossing = "%s → %s crosses %s while %s is selected" % [edge.from_component, edge.to_component, id, selected]
			_check(crossing.is_empty(), "%s / %s routes avoid unrelated machinery: %s" % [ship_id, workspace, crossing])
			_check(own_domain, "%s / %s renders only its own network domain, without presenting coolant as electrical supply." % [ship_id, workspace])
			_check(critical_paths, "%s / %s retains the actual engine supply or reactor heat path in every selection state." % [ship_id, workspace])


func _check_map_geometry(description: String) -> void:
	var map = console.connection_map
	var missing_endpoint: bool = map.edges.any(func(edge): return not map.buttons.has(edge.from_component) or not map.buttons.has(edge.to_component))
	_check(not missing_endpoint, description + " draws both endpoints of every shown connection.")
	var overlap: bool = false
	var ids: Array = map.node_rects.keys()
	for index in range(ids.size()):
		for other in range(index + 1, ids.size()):
			if map.node_rects[ids[index]].intersects(map.node_rects[ids[other]]):
				overlap = true
	_check(not overlap, description + " keeps all component cards separate.")
	var all_visible: bool = true
	for button in map.buttons.values():
		all_visible = all_visible and map.get_global_rect().grow(1.0).encloses(button.get_global_rect())
	_check(all_visible, description + " exposes every component within the full-width map.")
	var crossing: String = ""
	for edge in map.edges:
		var path: PackedVector2Array = map.edge_path(edge)
		if path.size() < 2:
			crossing = "Missing route for %s → %s" % [edge.from_component, edge.to_component]
			continue
		if not map.node_rects[edge.from_component].grow(0.1).has_point(path[0]) or not map.node_rects[edge.to_component].grow(0.1).has_point(path[-1]):
			crossing = "Detached endpoint for %s → %s" % [edge.from_component, edge.to_component]
		for id in map.node_rects:
			if id in [edge.from_component, edge.to_component]:
				continue
			for index in range(path.size() - 1):
				var start: Vector2 = path[index]
				var finish: Vector2 = path[index + 1]
				var segment := Rect2(Vector2(minf(start.x, finish.x), minf(start.y, finish.y)),
					Vector2(maxf(absf(start.x - finish.x), 0.01), maxf(absf(start.y - finish.y), 0.01)))
				if segment.intersects(map.node_rects[id].grow(-0.1)):
					crossing = "%s → %s crosses %s" % [edge.from_component, edge.to_component, id]
	_check(crossing.is_empty(), description + " routes avoid unrelated machinery: " + crossing)


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
		_check(false, "Required navigation control is unavailable.")
		return
	button.pressed.emit()


func _click(control: Control) -> void:
	await _settle()
	var position: Vector2 = root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
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


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
