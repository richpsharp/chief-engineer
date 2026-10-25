extends SceneTree
## Architecture fixtures are transformed copies of Kestrel, not another ship.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Presenter = preload("res://scripts/presentation/ship_presenter.gd")
const Fixtures = preload("res://tests/ship_fixtures.gd")
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
	_test_view_identifiers()
	_test_connection_capacity_and_accounting()
	_test_thermal_energy_accounting()
	_test_continuous_temperature_readings()
	_test_temperature_advisory_policy()
	_test_connected_temperature_readings()
	_test_simultaneous_equipment_conditions()
	_test_engine_limit_telemetry()
	_test_power_constraint_diagnostics()
	_test_nested_power_constraints()
	_test_disconnected_service_conditions()
	_test_equipment_without_controls()
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
	var transformed = Fixtures.copy_kestrel()
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
	for circuit in transformed.coolant_circuits:
		circuit.pump = mapping[circuit.pump]
		circuit.service_component = mapping[circuit.service_component]
		circuit.members = circuit.members.map(func(member): return mapping[member])
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


func _test_view_identifiers() -> void:
	for original_id in ["power", "reactor"]:
		var definition = Fixtures.copy_kestrel()
		definition.view(original_id)["id"] = "overview"
		if definition.layouts.has(original_id):
			definition.layouts["overview"] = definition.layouts[original_id]
			definition.layouts.erase(original_id)
		var errors: Array[String] = definition.validate()
		_check(errors.any(func(error): return error.contains("overview") and error.contains("reserved")),
			"Workspace and summary views cannot shadow the reserved overview route: " + original_id)
		var ship = Simulation.new(definition)
		_check(not ship.validation_errors.is_empty() and ship.components.is_empty(),
			"A reserved view ID prevents machinery initialization: " + original_id)
		ship.tick(0.1)
		_check(ship.elapsed == 0.0 and not ship.command("reactor", "limit", 100.0).accepted,
			"A ship with a reserved view ID cannot advance or accept commands: " + original_id)
		definition.view("overview")["id"] = "renamed_" + original_id
		if definition.layouts.has("overview"):
			definition.layouts["renamed_" + original_id] = definition.layouts["overview"]
			definition.layouts.erase("overview")
		_check(definition.validate().is_empty(), "Other authored workspace and summary IDs remain supported: " + original_id)


func _test_invalid_definitions() -> void:
	var invalid = Fixtures.copy_kestrel()
	invalid.components[0] = Resource.new()
	_check(not invalid.validate().is_empty(), "An untyped Resource is rejected without invoking missing component properties.")
	invalid = Fixtures.copy_kestrel()
	invalid.component("reactor").definition = null
	_check(not invalid.validate().is_empty(), "A component with no type definition is rejected safely.")
	invalid = Fixtures.copy_kestrel()
	invalid.component("reactor").initial_state.erase("temperature")
	_check(not invalid.validate().is_empty(), "A heat-storing component requires an authored initial temperature.")
	invalid = Fixtures.copy_kestrel()
	invalid.component("reactor").parameters["heat_capacity"] = 0.0
	_check(not invalid.validate().is_empty(), "A zero thermal capacity cannot enter the simulation.")
	invalid = Fixtures.copy_kestrel()
	invalid.view("power")["members"] = 17
	_check(not invalid.validate().is_empty(), "Malformed view membership is rejected without crashing workspace lookup.")
	invalid = Fixtures.copy_kestrel()
	invalid.component("pump_b").definition.ports["backup_power_in"] = {"domain": "power", "direction": "in"}
	var second_feed = _power_link("separate_power_port", "main_bus", "pump_b")
	second_feed.to_port = "backup_power_in"
	invalid.connections.append(second_feed)
	_check(not invalid.validate().is_empty(), "A second named electrical input cannot bypass the single-feed component rule.")
	invalid = Fixtures.copy_kestrel()
	invalid.component("pump_b").definition.controls[0]["id"] = "unsupported_speed"
	invalid.component("pump_b").initial_settings = {"unsupported_speed": 30.0}
	_check(not invalid.validate().is_empty(), "An authored control must correspond to behavior supported by the component kind.")
	invalid = Fixtures.copy_kestrel()
	for control in invalid.component("aux_bus").definition.controls:
		if control.id == "closed":
			control["kind"] = "number"
			control["min"] = 0.0
			control["max"] = 1.0
			control["default"] = 1.0
	invalid.component("aux_bus").initial_settings["closed"] = 1.0
	_check(not invalid.validate().is_empty(), "A breaker cannot redefine its Boolean setting as a numeric control.")
	invalid = Fixtures.copy_kestrel()
	invalid.component("pump_b").definition.controls[0]["kind"] = "toggle"
	invalid.component("pump_b").definition.controls[0]["default"] = true
	invalid.component("pump_b").initial_settings["flow"] = true
	_check(not invalid.validate().is_empty(), "A pump cannot redefine its numeric flow setting as a toggle.")
	for bad_capacity in [-2.0, NAN]:
		invalid = Fixtures.copy_kestrel()
		invalid.connections[0].capacity = bad_capacity
		_check(not invalid.validate().is_empty(), "Invalid negative and nonfinite wire ratings are rejected.")
	invalid = Fixtures.copy_kestrel()
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
	invalid = Fixtures.copy_kestrel()
	invalid.components.append(invalid.components[0].duplicate(true))
	_check(not invalid.validate().is_empty(), "Duplicate component IDs are rejected.")
	invalid = Fixtures.copy_kestrel()
	invalid.connections[0].to_component = "not_installed"
	_check(not invalid.validate().is_empty(), "Missing connection endpoints are rejected.")
	invalid = Fixtures.copy_kestrel()
	invalid.connections[0].from_port = "missing_port"
	_check(not invalid.validate().is_empty(), "Missing ports are rejected.")
	invalid = Fixtures.copy_kestrel()
	invalid.connections[0].to_component = "coolant_reservoir"
	invalid.connections[0].to_port = "heat_in"
	_check(not invalid.validate().is_empty(), "Power cannot connect to a thermal port.")
	invalid = Fixtures.copy_kestrel()
	invalid.connections[0].to_component = "main_bus"
	invalid.connections[0].to_port = "power_out"
	_check(not invalid.validate().is_empty(), "Output-to-output connections are rejected.")
	invalid = Fixtures.copy_kestrel()
	var duplicate = invalid.connections[0].duplicate(true)
	duplicate.id = "extra_source"
	invalid.connections.append(duplicate)
	_check(not invalid.validate().is_empty(), "Consumers cannot have multiple electrical sources.")
	invalid = Fixtures.copy_kestrel()
	invalid.assembly("drive_unit").ports["power_in"] = {"component": "propulsion", "port": "power_in"}
	_check(invalid.resolve_port("propulsion", "power_in").is_empty() and not invalid.validate().is_empty(), "Cyclic assembly aliases terminate safely and are rejected.")
	invalid = Fixtures.copy_kestrel()
	invalid.assembly("propulsion").parent_id = "drive_unit"
	_check(not invalid.validate().is_empty(), "Assembly containment cycles are rejected.")
	invalid = Fixtures.copy_kestrel()
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
	var limited = Fixtures.copy_kestrel()
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


func _test_thermal_energy_accounting() -> void:
	var hotter = Fixtures.copy_kestrel()
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
	var extra_state = Fixtures.copy_kestrel()
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

	var hot = Fixtures.copy_kestrel()
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
	var advisory = Fixtures.copy_kestrel()
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
	var definition = Fixtures.copy_kestrel()
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


func _test_simultaneous_equipment_conditions() -> void:
	var definition = Fixtures.copy_kestrel()
	definition.component("coolant_reservoir").initial_state["temperature"] = 65.0
	definition.component("radiator").initial_settings["deployment"] = 0.0
	var presenter = Presenter.new(Simulation.new(definition))
	var codes: Array = presenter.conditions().map(func(condition): return condition.code)
	_check("radiator.closed" in codes and "coolant.temperature_advisory" in codes,
		"Hot coolant cannot hide a closed radiator; the cause and thermal symptom remain separate conditions.")
	_check(presenter.equipment_status("radiator") == "Closed" and presenter.equipment_reason("radiator").contains("65.0 °C"),
		"The radiator inspector explains its closed state and connected temperature together.")
	definition.component("reactor").initial_state["temperature"] = 80.0
	definition.component("reactor").initial_settings["limit"] = 0.0
	presenter = Presenter.new(Simulation.new(definition))
	codes = presenter.conditions().map(func(condition): return condition.code)
	_check("reactor.offline" in codes and "reactor.temperature_advisory" in codes,
		"An offline reactor can independently retain stored heat above its advisory level.")
	_check(presenter.equipment_status("reactor") == "Offline" and presenter.equipment_reason("reactor").contains("80.0 °C"),
		"An offline reactor inspector preserves both operating state and temperature evidence.")


func _test_engine_limit_telemetry() -> void:
	var definition = Fixtures.copy_kestrel()
	definition.component("main_engine").parameters["flow_per_thrust"] = 2.0
	definition.component("main_engine").parameters["kw_per_thrust"] = 3.0
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	_check(_near(ship.components["main_engine"].state.get("cooling_limit", -1.0), 15.0)
		and _near(ship.components["main_engine"].state.requested_power, 45.0),
		"An engine publishes its cooling limit and power demand using its own configured conversion factors.")
	_check(presenter.equipment_status("main_engine") == "Cooling limited", "Engine status explains the committed cooling limit.")
	ship.command("main_bus", "limit", 70.0)
	ship.tick(0.1)
	_check(presenter.equipment_status("main_engine") == "Power limited", "Engine status distinguishes insufficient allocation from its cooling limit.")
	ship.command("main_bus", "limit", 200.0)
	ship.tick(10.0)
	_check(presenter.equipment_status("main_engine") == "Cooling limited", "Restored electrical supply leaves the independent cooling restriction visible.")


func _test_power_constraint_diagnostics() -> void:
	var definition = Fixtures.copy_kestrel()
	for edge in definition.connections:
		if edge.id == "feed_propulsion_pump": edge.capacity = 6.0
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	var condition: Dictionary = _condition_for(presenter, "pump_b")
	_check(_near(ship.components["pump_b"].state.power, 6.0) and presenter.equipment_status("reactor") == "Online",
		"A limited pump feed leaves the healthy reactor online.")
	_check(condition.get("connection_id") == "feed_propulsion_pump" and condition.equipment == "pump_b_feed",
		"A wire-limited pump condition identifies the connection and opens its receiving equipment.")
	_check(presenter.equipment_reason("pump_b").contains("6.0 kW") and not presenter.equipment_reason("pump_b").contains("Inspect Reactor"),
		"The explanation names the wire rating instead of blaming a healthy reactor.")
	ship.command("aux_bus", "limit", 20.0)
	ship.tick(0.1)
	_check(_condition_for(presenter, "pump_b").cause_id == "aux_bus", "A tighter bus constraint supersedes the cable rating.")
	ship.command("aux_bus", "limit", 40.0)
	ship.tick(0.1)
	_check(_condition_for(presenter, "pump_b").get("connection_id") == "feed_propulsion_pump", "Restoring the bus reveals the remaining cable constraint.")
	ship.command("pump_b", "flow", 10.0)
	ship.tick(10.0)
	_check(_condition_for(presenter, "pump_b").is_empty() and ship.components["pump_b"].power_constraint.is_empty(), "Reducing demand below the cable rating clears the old power condition and evidence.")

	definition = Fixtures.copy_kestrel()
	for edge in definition.connections:
		if edge.id == "source_aux": edge.capacity = 24.0
	ship = Simulation.new(definition)
	presenter = Presenter.new(ship)
	condition = _condition_for(presenter, "aux_bus")
	_check(condition.get("connection_id") == "source_aux" and condition.equipment == "aux_bus",
		"A bus input wire limitation routes to the receiving bus.")
	ship.command("reactor", "limit", 70.0)
	ship.tick(0.1)
	_check(_condition_for(presenter, "pump_b").cause_id == "reactor", "A source shortage retains the actual reactor constraint.")
	ship.command("reactor", "limit", 200.0)
	ship.command("pump_b", "flow", 10.0)
	ship.tick(10.0)
	_check(_condition_for(presenter, "aux_bus").is_empty() and ship.components["aux_bus"].power_constraint.is_empty(), "Recovered bus allocation clears propagated diagnostics.")

	definition = Fixtures.copy_kestrel()
	definition.component("main_engine").parameters["priority"] = 0
	definition.component("reactor").initial_settings["limit"] = 70.0
	ship = Simulation.new(definition)
	_check(_near(ship.components["main_engine"].state.requested_power, 0.0) and ship.components["main_engine"].power_constraint.is_empty(),
		"A later loss of pump flow clears the engine's obsolete electrical constraint when cooling removes its power demand.")


func _test_nested_power_constraints() -> void:
	var definition = Fixtures.copy_kestrel()
	for edge in definition.connections:
		if edge.id == "source_aux":
			edge.from_component = "main_bus"
			edge.from_port = "power_out"
	definition.component("main_bus").initial_settings["limit"] = 50.0
	definition.component("aux_bus").initial_settings["limit"] = 10.0
	definition.component("life_support").parameters["priority"] = 60
	var ship = Simulation.new(definition)
	_check(ship.components["aux_bus"].power_constraint.get("component_id") == "aux_bus"
		and ship.components["main_bus"].power_constraint.get("component_id") == "main_bus",
		"An early child-bus shortage cannot overwrite the parent bus's separate supply constraint.")
	_check(ship.components["reactor"].power_constraint.is_empty() and Presenter.new(ship).equipment_status("reactor") == "Online",
		"Downstream restrictions do not create a false source diagnostic.")


func _test_disconnected_service_conditions() -> void:
	var definition = Fixtures.copy_kestrel()
	_remove_power_input(definition, "life_support")
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	var condition: Dictionary = _condition_for(presenter, "life_support")
	_check(definition.validate().is_empty() and presenter.equipment_status("life_support") == "Unpowered", "Disconnected service loads are supported and report their actual power state.")
	_check(not condition.is_empty(), "A missing inspector route never discards an unpowered service warning.")
	_check(condition.get("system") == "life_support" and condition.get("equipment") == "", "A disconnected hidden service routes to its department summary.")
	_check(presenter.equipment_reason("life_support").contains("no connected power source"), "Disconnected equipment explains its missing source rather than a capacity shortage.")
	for view in definition.views:
		view.members.erase("life_support")
	presenter = Presenter.new(Simulation.new(definition))
	condition = _condition_for(presenter, "life_support")
	_check(not condition.is_empty() and condition.get("system") == "", "A service without any authored view retains an unrouted ship-wide condition.")


func _test_equipment_without_controls() -> void:
	var definition = Fixtures.copy_kestrel()
	for id in ["reactor", "aux_bus"]:
		definition.component(id).definition.controls.clear()
		definition.component(id).initial_settings.clear()
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	_check(definition.validate().is_empty() and ship.components["reactor"].settings.is_empty(), "Fixed-capacity equipment does not require player controls.")
	_check(_near(ship.totals().output, 152.0) and presenter.equipment_status("reactor") == "Online" and presenter.conditions().is_empty(),
		"A fixed-capacity reactor supplies the ship without a contradictory offline warning.")
	_check(presenter.readings("reactor")[1][1] == "200.0 kW" and presenter.readings("reactor")[2][1] == "48.0 kW",
		"A fixed reactor inspector reports committed capacity and spare power.")
	_check(presenter.caption("reactor") == "152 / 200 kW" and presenter.caption("aux_bus") == "30 / 60 kW",
		"Reactor and bus captions consistently display fixed capacity.")
	_check(presenter.system_summary("reactor").value == "152 / 200 kW", "The reactor summary uses the same fixed capacity as the solver.")
	_check(not ship.command("reactor", "limit", 100.0).accepted, "Fixed equipment does not gain an unauthored operating control.")
	definition.component("reactor").parameters["rated_power"] = 0.0
	presenter = Presenter.new(Simulation.new(definition))
	_check(presenter.equipment_status("reactor") == "Offline", "Zero fixed capacity is correctly reported as offline.")


func _condition_for(presenter, id: String) -> Dictionary:
	for condition in presenter.conditions():
		if condition.component_id == id and not condition.has("measurement"):
			return condition
	return {}


func _thermal_energy(ship) -> float:
	var energy := 0.0
	for runtime in ship.components.values():
		if runtime.state.has("temperature"):
			energy += float(runtime.state.temperature) * float(runtime.config.get("heat_capacity", 0.0))
	return energy


func _test_nested_bus_summary() -> void:
	var nested = Fixtures.copy_kestrel()
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
