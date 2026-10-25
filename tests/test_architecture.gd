extends SceneTree
## Architecture fixtures are transformed copies of Kestrel, not another ship.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Presenter = preload("res://scripts/presentation/ship_presenter.gd")
const Ship = preload("res://scripts/definitions/ship_definition.gd")
const Connection = preload("res://scripts/definitions/connection_definition.gd")
const Kestrel = preload("res://ships/kestrel.tres")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_definition_and_nested_ports()
	_test_independent_runtimes_and_snapshots()
	_test_commands_and_fixed_steps()
	_test_renamed_and_reordered_definition()
	_test_invalid_definitions()
	_test_connection_capacity_and_accounting()
	_test_thermal_energy_accounting()
	_test_continuous_temperature_readings()
	_test_temperature_advisory_policy()
	_test_connected_temperature_readings()
	_test_nested_bus_summary()
	print("%s: %d architecture checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _test_definition_and_nested_ports() -> void:
	_check(Kestrel.validate().is_empty(), "The shipped Kestrel Resource validates.")
	var endpoint: Dictionary = Kestrel.resolve_port("propulsion", "power_in")
	_check(endpoint == {"component": "main_engine", "port": "power_in", "domain": "power", "direction": "in"},
		"A propulsion assembly port resolves through drive_unit to the engine's typed leaf port.")
	_check(Kestrel.resolve_port("propulsion", "missing").is_empty(), "An unknown assembly port cannot resolve.")
	var engine_inputs := 0
	for link in Kestrel.resolved_connections():
		if link.to_component == "main_engine" and link.domain == "power":
			engine_inputs += 1
	_check(engine_inputs == 1, "Nested assembly exposure contributes exactly one electrical connection.")
	var main_max := 0.0
	var aux_max := 0.0
	for control in Kestrel.component("main_bus").controls():
		if control.id == "limit": main_max = control.max
	for control in Kestrel.component("aux_bus").controls():
		if control.id == "limit": aux_max = control.max
	_check(main_max == 200.0 and aux_max == 60.0, "Shared bus types derive control bounds from each instance's rating.")


func _test_independent_runtimes_and_snapshots() -> void:
	var left = Simulation.new(Kestrel)
	var right = Simulation.new(Kestrel)
	var untouched: Dictionary = right.snapshot()
	var authored_settings: Dictionary = Kestrel.component("aux_bus").initial_settings.duplicate(true)
	left.command("aux_bus", "limit", 22.0)
	left.tick(0.1)
	_check(right.snapshot() == untouched, "Two runtimes sharing one definition have independent state and commands.")
	_check(Kestrel.component("aux_bus").initial_settings == authored_settings, "Operating a ship does not mutate its authored settings.")
	left.components["pump_a"].config["priority"] = -500
	_check(right.components["pump_a"].config.priority == Kestrel.component("pump_a").config().priority,
		"Runtime parameter dictionaries are detached from other ships.")
	var snapshot: Dictionary = right.snapshot()
	snapshot.components["pump_b"].state["flow"] = -100.0
	snapshot.components["pump_b"].settings["flow"] = 0.0
	_check(right.components["pump_b"].state.flow == 30.0 and right.components["pump_b"].settings.flow == 30.0,
		"A returned snapshot cannot mutate live machinery.")
	left.reset()
	_check(_equivalent_components(left, right), "Reset creates healthy state from the original authored definition.")


func _test_commands_and_fixed_steps() -> void:
	var ship = Simulation.new(Kestrel)
	var result: Dictionary = ship.command("aux_bus", "limit", 24.0)
	_check(result.has_all(["accepted", "reason", "sequence"]) and result.accepted, "Valid commands return a structured acceptance result.")
	_check(ship.components["aux_bus"].settings.limit == 40.0, "Accepted commands do not mutate committed settings before a step.")
	ship.tick(0.04)
	_check(ship.elapsed == 0.0 and ship.components["aux_bus"].settings.limit == 40.0, "A partial timestep leaves the queued command unapplied.")
	ship.tick(0.06)
	_check(_near(ship.elapsed, 0.1) and ship.components["aux_bus"].settings.limit == 24.0, "Accumulated partial deltas apply commands at the fixed-step boundary.")
	var first: Dictionary = ship.command("aux_bus", "limit", 30.0)
	var second: Dictionary = ship.command("aux_bus", "limit", 20.0)
	_check(second.sequence > first.sequence, "Command sequence numbers preserve submission order.")
	ship.tick(0.1)
	_check(ship.components["aux_bus"].settings.limit == 20.0, "Multiple queued settings apply in submission order.")
	for args in [["missing", "limit", 1.0], ["aux_bus", "missing", 1.0], ["aux_bus", "limit", 61.0], ["aux_bus", "limit", -1.0], ["aux_bus", "limit", NAN], ["main_bus", "closed", "false"], ["pump_a", "flow", true]]:
		_check(not ship.command(args[0], args[1], args[2]).accepted, "Unknown, ill-typed, nonfinite, and out-of-range commands are rejected.")
	ship.command("reactor", "limit", 70.0)
	ship.toggle_pause()
	ship.tick(1.0)
	_check(ship.components["reactor"].settings.limit == 200.0, "Pause freezes already queued commands.")
	_check(not ship.command("reactor", "limit", 10.0).accepted, "Pause rejects new operating commands.")
	ship.toggle_pause()
	ship.tick(0.1)
	_check(ship.components["reactor"].settings.limit == 70.0, "Resume applies the command retained through the pause.")
	ship.command("reactor", "limit", 0.0)
	ship.reset()
	ship.tick(0.1)
	_check(ship.components["reactor"].settings.limit == 200.0, "Reset discards pending commands.")

	var whole = Simulation.new(Kestrel)
	var split = Simulation.new(Kestrel)
	whole.command("aux_bus", "limit", 24.0)
	split.command("aux_bus", "limit", 24.0)
	whole.tick(10.0)
	for frame in range(100):
		split.tick(0.03)
		split.tick(0.02)
		split.tick(0.05)
	_check(_equivalent_components(whole, split) and _near(whole.elapsed, split.elapsed),
		"The same commands produce equal state with different render-frame partitions.")


func _test_renamed_and_reordered_definition() -> void:
	var transformed = _copy_kestrel()
	var ids: Array[String] = []
	for item in transformed.components + transformed.assemblies:
		ids.append(item.id)
	ids.sort()
	var mapping: Dictionary = {}
	for i in range(ids.size()):
		mapping[ids[i]] = "fixture_%03d" % i
	for item in transformed.components:
		item.id = mapping[item.id]
		item.parent_id = mapping.get(item.parent_id, "")
		item.display_name = "Renamed equipment " + item.id
	for item in transformed.assemblies:
		item.id = mapping[item.id]
		item.parent_id = mapping.get(item.parent_id, "")
		for alias in item.ports.values():
			alias.component = mapping[alias.component]
	for link in transformed.connections:
		link.from_component = mapping[link.from_component]
		link.to_component = mapping[link.to_component]
		link.id = "fixture_" + link.id
	for view in transformed.views:
		var renamed_members: Array = []
		for member in view.get("members", []): renamed_members.append(mapping[member])
		view.members = renamed_members
	for layout in transformed.layouts.values():
		var renamed_nodes: Dictionary = {}
		for old_id in layout.nodes: renamed_nodes[mapping[old_id]] = layout.nodes[old_id]
		layout.nodes = renamed_nodes
	transformed.components.reverse()
	transformed.assemblies.reverse()
	transformed.connections.reverse()
	_check(transformed.validate().is_empty(), "Renamed and reordered Kestrel remains a valid definition.")
	var original = Simulation.new(Kestrel)
	var renamed = Simulation.new(transformed)
	for args in [["aux_bus", "limit", 24.0], ["reactor", "limit", 100.0], ["pump_b", "flow", 36.0], ["radiator", "deployment", 55.0]]:
		original.command(args[0], args[1], args[2])
		renamed.command(mapping[args[0]], args[1], args[2])
		original.tick(20.0)
		renamed.tick(20.0)
		_check(_equivalent_components(original, renamed, mapping), "Behavior follows component kinds and connections rather than IDs or declaration order.")
	_check(_near(original.totals().output, renamed.totals().output), "Source accounting is invariant under the transformed Kestrel fixture.")


func _test_invalid_definitions() -> void:
	var invalid = _copy_kestrel()
	invalid.components[0] = Resource.new()
	_check(not invalid.validate().is_empty(), "An untyped Resource is rejected without invoking missing component properties.")
	invalid = _copy_kestrel()
	invalid.component("reactor").definition = null
	_check(not invalid.validate().is_empty(), "A component with no type definition is rejected safely.")
	invalid = _copy_kestrel()
	invalid.component("reactor").initial_state.erase("temperature")
	_check(not invalid.validate().is_empty(), "A heat-storing component requires an authored initial temperature.")
	invalid = _copy_kestrel()
	invalid.component("reactor").parameters["heat_capacity"] = 0.0
	_check(not invalid.validate().is_empty(), "A zero thermal capacity cannot enter the simulation.")
	invalid = _copy_kestrel()
	invalid.view("power")["members"] = 17
	_check(not invalid.validate().is_empty(), "Malformed view membership is rejected without crashing workspace lookup.")
	invalid = _copy_kestrel()
	invalid.component("pump_b").definition.ports["backup_power_in"] = {"domain": "power", "direction": "in"}
	var second_feed = _power_link("separate_power_port", "main_bus", "pump_b")
	second_feed.to_port = "backup_power_in"
	invalid.connections.append(second_feed)
	_check(not invalid.validate().is_empty(), "A second named electrical input cannot bypass the single-feed component rule.")
	invalid = _copy_kestrel()
	invalid.component("pump_b").definition.controls[0]["id"] = "unsupported_speed"
	invalid.component("pump_b").initial_settings = {"unsupported_speed": 30.0}
	_check(not invalid.validate().is_empty(), "An authored control must correspond to behavior supported by the component kind.")
	invalid = _copy_kestrel()
	for control in invalid.component("aux_bus").definition.controls:
		if control.id == "closed":
			control["kind"] = "number"
			control["min"] = 0.0
			control["max"] = 1.0
			control["default"] = 1.0
	invalid.component("aux_bus").initial_settings["closed"] = 1.0
	_check(not invalid.validate().is_empty(), "A breaker cannot redefine its Boolean setting as a numeric control.")
	invalid = _copy_kestrel()
	invalid.component("pump_b").definition.controls[0]["kind"] = "toggle"
	invalid.component("pump_b").definition.controls[0]["default"] = true
	invalid.component("pump_b").initial_settings["flow"] = true
	_check(not invalid.validate().is_empty(), "A pump cannot redefine its numeric flow setting as a toggle.")
	for bad_capacity in [-2.0, NAN]:
		invalid = _copy_kestrel()
		invalid.connections[0].capacity = bad_capacity
		_check(not invalid.validate().is_empty(), "Invalid negative and nonfinite wire ratings are rejected.")
	invalid = _copy_kestrel()
	for edge in invalid.resolved_connections():
		if edge.domain == "thermal" and edge.from_component == "main_engine":
			var alias_duplicate = Connection.new()
			alias_duplicate.id = "same_heat_through_leaf"
			alias_duplicate.from_component = edge.from_component
			alias_duplicate.from_port = edge.from_port
			alias_duplicate.to_component = edge.to_component
			alias_duplicate.to_port = edge.to_port
			invalid.connections.append(alias_duplicate)
			break
	_check(not invalid.validate().is_empty(), "A leaf edge cannot duplicate heat already connected through an assembly alias.")
	invalid = _copy_kestrel()
	invalid.components.append(invalid.components[0].duplicate(true))
	_check(not invalid.validate().is_empty(), "Duplicate component IDs are rejected.")
	invalid = _copy_kestrel()
	invalid.connections[0].to_component = "not_installed"
	_check(not invalid.validate().is_empty(), "Missing connection endpoints are rejected.")
	invalid = _copy_kestrel()
	invalid.connections[0].from_port = "missing_port"
	_check(not invalid.validate().is_empty(), "Missing ports are rejected.")
	invalid = _copy_kestrel()
	invalid.connections[0].to_component = "coolant_reservoir"
	invalid.connections[0].to_port = "heat_in"
	_check(not invalid.validate().is_empty(), "Power cannot connect to a thermal port.")
	invalid = _copy_kestrel()
	invalid.connections[0].to_component = "main_bus"
	invalid.connections[0].to_port = "power_out"
	_check(not invalid.validate().is_empty(), "Output-to-output connections are rejected.")
	invalid = _copy_kestrel()
	var duplicate = invalid.connections[0].duplicate(true)
	duplicate.id = "extra_source"
	invalid.connections.append(duplicate)
	_check(not invalid.validate().is_empty(), "Consumers cannot have multiple electrical sources.")
	invalid = _copy_kestrel()
	invalid.assembly("drive_unit").ports["power_in"] = {"component": "propulsion", "port": "power_in"}
	_check(invalid.resolve_port("propulsion", "power_in").is_empty() and not invalid.validate().is_empty(), "Cyclic assembly aliases terminate safely and are rejected.")
	invalid = _copy_kestrel()
	invalid.assembly("propulsion").parent_id = "drive_unit"
	_check(not invalid.validate().is_empty(), "Assembly containment cycles are rejected.")
	invalid = _copy_kestrel()
	_remove_power_input(invalid, "main_bus")
	_remove_power_input(invalid, "aux_bus")
	invalid.connections.append(_power_link("cycle_ab", "main_bus", "aux_bus"))
	invalid.connections.append(_power_link("cycle_ba", "aux_bus", "main_bus"))
	_check(not invalid.validate().is_empty(), "Electrical cycles are rejected.")
	var bad_runtime = Simulation.new(invalid)
	_check(not bad_runtime.validation_errors.is_empty(), "Invalid topology is exposed by runtime validation.")
	_check(not bad_runtime.command("main_bus", "closed", true).accepted, "An invalid runtime rejects operating commands.")
	bad_runtime.tick(1.0)
	_check(bad_runtime.elapsed == 0.0, "An invalid runtime cannot advance the simulation.")


func _test_connection_capacity_and_accounting() -> void:
	var limited = _copy_kestrel()
	for edge in limited.resolved_connections():
		if edge.to_component == "pump_b" and edge.domain == "power":
			for authored in limited.connections:
				if authored.id == edge.id: authored.capacity = 6.0
	_check(limited.validate().is_empty(), "A finite electrical connection rating is supported.")
	var ship = Simulation.new(limited)
	ship.tick(0.1)
	_check(_near(ship.components["pump_b"].state.power, 6.0) and _near(ship.components["pump_b"].state.flow, 15.0),
		"An authored wire capacity limits its connected pump without ID-specific rules.")
	for setting in [200.0, 100.0, 45.0, 0.0]:
		ship.command("reactor", "limit", setting)
		ship.tick(20.0)
		var actual_load := 0.0
		for item in ship.components.values():
			if item.spec.definition.kind in ["load", "pump", "engine"]:
				actual_load += float(item.state.get("power", 0.0))
		_check(_near(actual_load, ship.totals().output) and actual_load <= setting + 0.00001,
			"Total delivered consumer power equals source output within its rating.")


func _copy_kestrel():
	var copied = Ship.new()
	copied.id = Kestrel.id
	copied.display_name = Kestrel.display_name
	copied.schema_version = Kestrel.schema_version
	copied.ambient_temperature = Kestrel.ambient_temperature
	for item in Kestrel.components:
		var spec = item.duplicate(true)
		spec.definition = item.definition.duplicate(true)
		copied.components.append(spec)
	for item in Kestrel.assemblies: copied.assemblies.append(item.duplicate(true))
	for item in Kestrel.connections: copied.connections.append(item.duplicate(true))
	copied.views = Kestrel.views.duplicate(true)
	copied.layouts = Kestrel.layouts.duplicate(true)
	return copied


func _test_thermal_energy_accounting() -> void:
	var hotter = _copy_kestrel()
	hotter.component("reactor").initial_state["temperature"] = 60.0
	var ship = Simulation.new(hotter)
	for deployment in [100.0, 0.0]:
		ship.command("radiator", "deployment", deployment)
		ship.tick(0.1)
		var before: float = _thermal_energy(ship)
		var passive_loss := 0.0
		for runtime in ship.components.values():
			passive_loss += float(runtime.state.get("passive_heat_loss", 0.0))
		var expected_change: float = (ship.totals().heat_generated - ship.totals().heat_rejected - passive_loss) * 0.1
		ship.tick(0.1)
		_check(absf((_thermal_energy(ship) - before) - expected_change) < 0.00001,
			"Internal thermal transfers conserve energy; only generation and external rejection change total stored heat.")


func _test_continuous_temperature_readings() -> void:
	var ship = Simulation.new(Kestrel)
	var presenter = Presenter.new(ship)
	var reading: Dictionary = presenter.temperature_readings("reactor")[0]
	_check(_near(reading.temperature, 42.0) and _near(reading.rate, 0.0) and _near(reading.net_heat, 0.0),
		"A thermal reading exposes temperature, rate, and net heat at equilibrium.")
	_check(_near(reading.margin, 28.0), "Advisory headroom remains a numerical temperature difference.")
	_check(presenter.temperature_readings("pump_a").is_empty() and presenter.temperature_readings("missing").is_empty(),
		"Equipment without a thermal measurement does not invent a zero temperature.")
	var extra_state = _copy_kestrel()
	extra_state.component("pump_a").initial_state["temperature"] = 20.0
	_check(Presenter.new(Simulation.new(extra_state)).temperature_readings("pump_a").is_empty(),
		"An unused authored state field cannot masquerade as committed thermal telemetry.")
	ship.command("pump_a", "flow", 0.0)
	ship.tick(0.1)
	reading = presenter.temperature_readings("reactor")[0]
	_check(reading.rate > 0.0 and reading.net_heat > 0.0 and reading.margin > 0.0 and presenter.equipment_status("reactor") == "Online",
		"Rising temperature is observable before a temperature advisory is reached.")
	var before: Dictionary = ship.snapshot()
	reading["temperature"] = -999.0
	presenter.readings("reactor")
	presenter.conditions()
	_check(ship.snapshot() == before, "Reading and modifying returned telemetry cannot change physical state.")

	var hot = _copy_kestrel()
	hot.component("reactor").initial_state["temperature"] = 80.0
	ship = Simulation.new(hot)
	presenter = Presenter.new(ship)
	reading = presenter.temperature_readings("reactor")[0]
	_check(reading.rate < 0.0 and reading.net_heat < 0.0 and _near(reading.margin, -10.0),
		"Temperature above an advisory can still have a negative cooling trend.")
	_check(presenter.equipment_status("reactor") == "Temperature advisory" and presenter.equipment_reason("reactor").contains("°C/min"),
		"The advisory explains the actual temperature and trend rather than just saying hot.")
	ship.tick(0.1)
	_check(_near(ship.components["reactor"].state.temperature, reading.temperature + reading.rate * 0.1),
		"Published temperature rate agrees with the next fixed-step temperature change.")
	var current: Dictionary = presenter.temperature_readings("reactor")[0]
	_check(_near(current.net_heat, current.rate * ship.components["reactor"].config.heat_capacity),
		"Published heat balance and rate agree at committed temperatures.")


func _test_temperature_advisory_policy() -> void:
	var advisory = _copy_kestrel()
	advisory.component("reactor").parameters["warning_temperature"] = 40.0
	var left = Simulation.new(advisory)
	var right = Simulation.new(Kestrel)
	_check(Presenter.new(left).equipment_status("reactor") == "Temperature advisory" and Presenter.new(right).equipment_status("reactor") == "Online",
		"Changing an advisory setting changes the presentation policy.")
	for ship in [left, right]:
		ship.command("radiator", "deployment", 0.0)
		ship.tick(20.0)
	_check(_equivalent_components(left, right), "Advisory thresholds do not change physical trajectories or equipment output.")
	advisory.component("reactor").parameters.erase("warning_temperature")
	advisory.component("reactor").definition.defaults.erase("warning_temperature")
	advisory.component("reactor").initial_state["temperature"] = 80.0
	_check(advisory.validate().is_empty(), "Thermal observations do not require an advisory threshold.")
	var presenter = Presenter.new(Simulation.new(advisory))
	var reading: Dictionary = presenter.temperature_readings("reactor")[0]
	_check(_near(reading.temperature, 80.0) and not reading.has("margin") and not reading.has("advisory_temperature") and presenter.equipment_status("reactor") == "Online",
		"An absent advisory preserves the measurement without inventing a threshold.")
	for value in ["hot", true, INF]:
		advisory.component("reactor").parameters["warning_temperature"] = value
		_check(not advisory.validate().is_empty(), "An authored temperature advisory must be finite numeric data.")


func _test_connected_temperature_readings() -> void:
	var definition = _copy_kestrel()
	definition.component("reactor").initial_state["temperature"] = -20.0
	definition.component("main_engine").initial_state["temperature"] = -30.0
	definition.component("coolant_reservoir").initial_state["temperature"] = -40.0
	var presenter = Presenter.new(Simulation.new(definition))
	var radiator_reading: Dictionary = presenter.temperature_readings("radiator")[0]
	_check(radiator_reading.component_id == "coolant_reservoir" and _near(radiator_reading.temperature, -40.0),
		"Transfer equipment observes its connected mass, including temperatures below ambient.")
	_check(presenter.system_summary("cooling").value == "-20.0°C peak temperature",
		"Temperature summaries preserve negative readings instead of clamping them to zero.")
	var observations: Array = presenter.temperature_readings("heat_exchanger")
	_check(observations.size() == 2 and observations[0].component_id == "coolant_reservoir" and observations[1].component_id == "reactor",
		"An exchanger exposes both connected thermal masses with identifiable measurements.")
	definition.component("coolant_reservoir").initial_state["temperature"] = 65.0
	presenter = Presenter.new(Simulation.new(definition))
	_check(presenter.equipment_status("heat_exchanger") == "Temperature advisory" and presenter.equipment_reason("heat_exchanger").contains("65.0 °C"),
		"An exchanger observes an advisory on its outlet mass, not only its inlet.")
	var conditions: Array = presenter.conditions()
	_check(conditions.size() == 1 and conditions[0].measurement.component_id == "coolant_reservoir" and conditions[0].equipment != "coolant_reservoir",
		"A shared hidden thermal mass reports one numerical advisory routed to inspectable equipment.")
	for i in range(definition.connections.size() - 1, -1, -1):
		if definition.connections[i].id == "coolant_to_radiator":
			definition.connections.remove_at(i)
	presenter = Presenter.new(Simulation.new(definition))
	_check(presenter.temperature_readings("radiator").is_empty() and presenter.readings("radiator")[3][1] == "No connection",
		"Disconnected transfer equipment reports missing observations rather than ambient temperature.")


func _thermal_energy(ship) -> float:
	var energy := 0.0
	for runtime in ship.components.values():
		if runtime.state.has("temperature"):
			energy += float(runtime.state.temperature) * float(runtime.config.get("heat_capacity", 0.0))
	return energy


func _test_nested_bus_summary() -> void:
	var nested = _copy_kestrel()
	for edge in nested.resolved_connections():
		if edge.domain == "power" and edge.to_component == "aux_bus":
			for link in nested.connections:
				if link.id == edge.id:
					link.from_component = "main_bus"
					link.from_port = "power_out"
	nested.views.append({"id": "fixture_nested_power", "name": "Nested supply", "kind": "summary", "summary_kind": "power", "members": ["main_bus", "aux_bus"]})
	_check(nested.validate().is_empty(), "Kestrel can express a valid nested bus distribution fixture.")
	var ship = Simulation.new(nested)
	var expected: String = "%.0f kW distributed" % ship.totals().output
	_check(Presenter.new(ship).system_summary("fixture_nested_power").value == expected,
		"A summary including parent and child buses counts delivered power only once.")


func _remove_power_input(definition, target: String) -> void:
	var ids: Array = []
	for link in definition.resolved_connections():
		if link.domain == "power" and link.to_component == target: ids.append(link.id)
	for i in range(definition.connections.size() - 1, -1, -1):
		if definition.connections[i].id in ids: definition.connections.remove_at(i)


func _power_link(id: String, source: String, target: String):
	var link = Connection.new()
	link.id = id
	link.from_component = source
	link.from_port = "power_out"
	link.to_component = target
	link.to_port = "power_in"
	return link


func _equivalent_components(left, right, mapping: Dictionary = {}) -> bool:
	for id in left.components:
		var other_id: String = mapping.get(id, id)
		if not right.components.has(other_id): return false
		if not _equivalent_values(left.components[id].settings, right.components[other_id].settings): return false
		if not _equivalent_values(left.components[id].state, right.components[other_id].state): return false
	return true


func _equivalent_values(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size(): return false
	for key in left:
		if not right.has(key): return false
		if left[key] is float or left[key] is int:
			if not _near(float(left[key]), float(right[key])): return false
		elif left[key] != right[key]: return false
	return true


func _near(left: float, right: float) -> bool:
	return absf(left - right) < 0.00001


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
