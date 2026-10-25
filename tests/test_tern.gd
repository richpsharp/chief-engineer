extends SceneTree
## Acceptance checks for Tern's independent propulsion branches and shared plant.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Presenter = preload("res://scripts/presentation/ship_presenter.gd")
const Tern = preload("res://ships/tern.tres")
const Kestrel = preload("res://ships/kestrel.tres")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_definition_and_routes()
	_test_healthy_operation()
	for side in ["port", "starboard"]:
		_test_pump_feed_experiment(side)
	_test_shared_infrastructure()
	_test_isolation_pause_and_reset()
	print("%s: %d Tern checks (%d failures)%s." % ["PASS" if failures == 0 else "FAIL", checks, failures,
		" [quick run: 300-second watch]" if "--quick" in OS.get_cmdline_user_args() else " [full simulated day]"])
	quit(0 if failures == 0 else 1)


func _test_definition_and_routes() -> void:
	_check(Tern.validate().is_empty(), "The playable Tern definition validates.")
	_check(Tern.id != Kestrel.id and Tern.components.size() != Kestrel.components.size(),
		"Tern has its own identity and a different installed-equipment count from Kestrel.")
	var kinds: Dictionary = {}
	var shared_types := true
	for spec in Tern.components:
		kinds[spec.definition.kind] = int(kinds.get(spec.definition.kind, 0)) + 1
		shared_types = shared_types and spec.definition.resource_path.begins_with("res://ships/types/")
		shared_types = shared_types and spec.definition == load(spec.definition.resource_path)
	_check(shared_types, "Every Tern component reuses an existing shared equipment type Resource.")
	_check(kinds.get("engine") == 2 and kinds.get("pump") == 3 and kinds.get("bus") == 5,
		"Tern installs two engines, separate branch pumps, and nested radial distribution.")
	for side in ["port", "starboard"]:
		var engine_path: Array[String] = _power_path(side + "_engine")
		var pump_path: Array[String] = _power_path(side + "_pump")
		_check(side + "_bus" in engine_path and side + "_pump_feed" not in engine_path
			and side + "_pump_feed" in pump_path and side + "_bus" in pump_path,
			"The %s pump feed can be isolated without interrupting its engine's electrical path." % side)
		_check("distribution_bus" in engine_path and "utility_reactor" in engine_path,
			"The %s drive shares the common distribution trunk and reactor." % side)
		var coolant_sources: Array[String] = []
		for edge in Tern.resolved_connections():
			if edge.domain == "coolant" and edge.to_component == side + "_engine":
				coolant_sources.append(edge.from_component)
		_check(coolant_sources == [side + "_pump"], "The %s engine has an independent circulation supply." % side)
	var ship = Simulation.new(Tern)
	var presenter = Presenter.new(ship)
	var valid_routes := true
	for spec in Tern.components:
		if spec.inspectable:
			valid_routes = valid_routes and not Tern.workspace_for(spec.id).is_empty()
			valid_routes = valid_routes and not presenter.readings(spec.id).is_empty()
		for link in presenter.links(spec.id):
			valid_routes = valid_routes and Tern.component(link.equipment).inspectable
			valid_routes = valid_routes and link.system == Tern.workspace_for(link.equipment)
	_check(valid_routes, "Tern's equipment and dependency links resolve to reusable workspace inspectors.")
	_check(presenter.system_summary("propulsion").value == "20.0% mean thrust",
		"The existing propulsion summary aggregates both engines.")


func _test_healthy_operation() -> void:
	var ship = Simulation.new(Tern)
	var presenter = Presenter.new(ship)
	_check(_near(ship.totals().output, 144.0) and _near(ship.totals().capacity, 220.0),
		"Healthy cruise draws 144 kW from 220 kW of shared generation.")
	_check(presenter.conditions().is_empty() and _near(_state(ship, "port_engine", "thrust"), 20.0)
		and _near(_state(ship, "starboard_engine", "thrust"), 20.0), "Both engines begin at healthy 20-percent cruise.")
	var initial_temperatures: Dictionary = {}
	var balanced_heat := true
	for id in ["utility_reactor", "port_engine", "starboard_engine", "coolant_reservoir"]:
		initial_temperatures[id] = _state(ship, id, "temperature")
		balanced_heat = balanced_heat and absf(_state(ship, id, "net_heat")) < 0.0001
	_check(balanced_heat, "Tern's authored initial thermal state is an equilibrium of the shared models.")
	var duration: float = 300.0 if "--quick" in OS.get_cmdline_user_args() else 86400.0
	var remained_healthy := true
	var remaining: float = duration
	while remaining > 0.0:
		var interval: float = minf(remaining, 3600.0)
		_advance_for(ship, interval)
		remained_healthy = remained_healthy and presenter.conditions().is_empty() and _power_balanced(ship)
		remaining -= interval
	_check(_near(ship.elapsed, duration) and remained_healthy,
		"The unattended ship stays healthy and electrically balanced throughout %.0f simulated seconds." % duration)
	var stable_temperatures := true
	for id in initial_temperatures:
		stable_temperatures = stable_temperatures and absf(_state(ship, id, "temperature") - initial_temperatures[id]) < 0.05
	_check(stable_temperatures, "Core, engines, and shared coolant remain at their authored equilibrium temperatures.")
	_check(_near(ship.totals().output, 144.0) and _near(_state(ship, "port_engine", "thrust"), 20.0)
		and _near(_state(ship, "starboard_engine", "thrust"), 20.0), "Long operation preserves both propulsion outputs and cruise power.")


func _test_pump_feed_experiment(side: String) -> void:
	var other: String = "starboard" if side == "port" else "port"
	var feeder: String = side + "_pump_feed"
	var pump: String = side + "_pump"
	var engine: String = side + "_engine"
	var ship = Simulation.new(Tern)
	var presenter = Presenter.new(ship)
	_check(ship.command(feeder, "closed", false).accepted, "Opening the %s pump feeder is an addressed operating command." % side)
	ship.tick(0.1)
	_check(_near(_state(ship, pump, "power"), 0.0) and _near(_state(ship, pump, "flow"), 0.0),
		"The isolated %s pump loses electrical power and circulation." % side)
	_check(_near(_state(ship, engine, "thrust"), 0.0) and presenter.equipment_status(engine) == "Cooling limited"
		and ship.components[engine].power_constraint.is_empty() and ship.components[side + "_bus"].settings.closed,
		"The %s engine stops from lost cooling while its own electrical branch remains available." % side)
	_check(_near(_state(ship, other + "_engine", "thrust"), 20.0) and _near(_state(ship, other + "_pump", "flow"), 20.0),
		"The %s propulsion branch continues normally during the %s pump fault." % [other, side])
	var condition: Dictionary = _condition_for(presenter, engine)
	_check(condition.get("cause_id") == feeder and condition.get("equipment") == feeder
		and condition.get("system") == "power", "The %s engine condition leads to the actual isolated pump feed." % side)
	_check(_has_link(presenter, feeder, pump) and _has_link(presenter, pump, engine)
		and _has_link(presenter, engine, pump) and _has_link(presenter, pump, feeder),
		"The %s power-pump-engine dependency is explorable in both directions." % side)
	_advance_for(ship, 60.0)
	_check(_near(_state(ship, other + "_engine", "thrust"), 20.0) and _services_powered(ship) and _power_balanced(ship),
		"The sustained local fault leaves other propulsion and shared services operating normally.")
	_check(ship.command(feeder, "closed", true).accepted, "The %s pump feed can be restored without resetting the ship." % side)
	ship.tick(0.1)
	_check(_state(ship, pump, "flow") > 0.0 and _state(ship, pump, "flow") < 20.0
		and _state(ship, engine, "thrust") <= _state(ship, engine, "cooling_limit"),
		"Restoration starts gradual pump recovery while the engine stays within its cooling capability.")
	_advance_for(ship, 120.0)
	_check(_near(_state(ship, pump, "flow"), 20.0) and _near(_state(ship, engine, "thrust"), 20.0)
		and _near(_state(ship, other + "_engine", "thrust"), 20.0), "Both engines recover to healthy cruise after the local fault.")
	_check(_near(ship.totals().output, 144.0) and presenter.conditions().is_empty(), "Restored cruise clears all operating conditions.")


func _test_shared_infrastructure() -> void:
	var ship = Simulation.new(Tern)
	_check(ship.command("utility_reactor", "limit", 100.0).accepted, "The shared reactor's available capacity can be reduced.")
	_advance_for(ship, 60.0)
	_check(_near(ship.totals().output, 100.0) and _power_balanced(ship), "Shared supply respects its 100 kW limit and load accounting.")
	_check(_state(ship, "port_engine", "thrust") < 20.0 and _state(ship, "starboard_engine", "thrust") < 20.0,
		"A common generation shortage affects both propulsion branches.")
	_check(_near(_state(ship, "port_engine", "thrust"), 18.0) and _near(_state(ship, "starboard_engine", "thrust"), 0.0)
		and _services_powered(ship), "Authored priorities preserve services and allocate the remaining 36 kW to the port engine.")
	ship.reset()
	var initial: Dictionary = {}
	for id in ["coolant_reservoir", "port_engine", "starboard_engine"]:
		initial[id] = _state(ship, id, "temperature")
	_check(ship.command("radiator", "deployment", 0.0).accepted, "The shared radiator can stop active rejection.")
	_advance_for(ship, 300.0)
	var heating := true
	for id in initial:
		heating = heating and _state(ship, id, "temperature") > initial[id] + 0.1
	_check(heating and _near(_state(ship, "radiator", "heat_rejected"), 0.0),
		"Closing common heat rejection warms shared coolant and both engines.")


func _test_isolation_pause_and_reset() -> void:
	var left = Simulation.new(Tern)
	var right = Simulation.new(Tern)
	var kestrel = Simulation.new(Kestrel)
	var right_initial: Dictionary = right.snapshot()
	var kestrel_initial: Dictionary = kestrel.snapshot()
	var authored_settings: Dictionary = Tern.component("port_pump_feed").initial_settings.duplicate(true)
	left.command("port_pump_feed", "closed", false)
	left.tick(0.1)
	_check(right.snapshot() == right_initial and kestrel.snapshot() == kestrel_initial,
		"Operating Tern leaves another Tern runtime and Kestrel untouched.")
	_check(Tern.component("port_pump_feed").initial_settings == authored_settings,
		"Runtime commands do not mutate the shared authored ship definition.")
	left.toggle_pause()
	var paused: Dictionary = left.snapshot()
	left.tick(30.0)
	_check(left.snapshot() == paused and not left.command("port_pump_feed", "closed", true).accepted,
		"Pause freezes Tern's machinery and rejects operating commands.")
	left.reset()
	_check(left.snapshot() == right_initial and Presenter.new(left).conditions().is_empty(),
		"Reset restores Tern's own healthy cruise, settings, and elapsed time.")
	_check(kestrel.snapshot() == kestrel_initial, "Resetting Tern cannot alter Kestrel.")


func _power_path(id: String) -> Array[String]:
	var path: Array[String] = []
	var current: String = id
	for attempt in range(Tern.components.size()):
		var parent: String = ""
		for edge in Tern.resolved_connections():
			if edge.domain == "power" and edge.to_component == current:
				parent = edge.from_component
				break
		if parent.is_empty():
			break
		path.append(parent)
		current = parent
	return path


func _condition_for(presenter, id: String) -> Dictionary:
	for condition in presenter.conditions():
		if condition.component_id == id:
			return condition
	return {}


func _has_link(presenter, source: String, target: String) -> bool:
	return presenter.links(source).any(func(link): return link.equipment == target)


func _services_powered(ship) -> bool:
	for part in ship.components.values():
		if part.kind == "load" and not _near(part.state.power, part.config.rated_power):
			return false
	return true


func _power_balanced(ship) -> bool:
	var consumption: float = 0.0
	for part in ship.components.values():
		if part.kind in ["load", "pump", "engine"]:
			consumption += float(part.state.power)
		if part.kind in ["reactor", "bus"] and part.state.draw > part.state.capacity + 0.0001:
			return false
	return _near(consumption, ship.totals().output)


func _state(ship, id: String, key: String) -> float:
	return float(ship.components[id].state.get(key, 0.0))


func _advance_for(ship, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.000001:
		var step: float = minf(remaining, 30.0)
		ship.tick(step)
		remaining -= step


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.001


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
