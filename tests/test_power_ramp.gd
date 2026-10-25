extends SceneTree
## Allocation diagnostics remain truthful when a coolant pump runs after its engine.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Presenter = preload("res://scripts/presentation/ship_presenter.gd")
const Fixtures = preload("res://tests/ship_fixtures.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_rising_circulation()
	_test_real_electrical_limit()
	_test_falling_circulation()
	print("%s: %d power-ramp checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _ramp_definition():
	var definition = Fixtures.copy_kestrel()
	definition.component("main_engine").parameters["priority"] = 0
	definition.component("main_engine").initial_state["thrust"] = 0.0
	definition.component("pump_b").initial_state["flow"] = 0.0
	return definition


func _test_rising_circulation() -> void:
	var definition = _ramp_definition()
	_check(definition.validate().is_empty(), "An engine may be allocated before its initially stopped coolant pump.")
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	ship.tick(0.1)
	var engine = ship.components["main_engine"]
	_check(engine.state.cooling_limit > 0.0 and _near(engine.state.thrust, 0.0),
		"Final pump flow is published without granting the earlier engine extra power during the same step.")
	_check(_near(engine.state.requested_power, 0.0) and _near(engine.state.allocated_power, 0.0),
		"An engine that requested no power before pump startup records no unsatisfied electrical demand.")
	_check(presenter.equipment_status("main_engine") == "Cooling limited",
		"The engine reports its actual startup cooling restriction rather than an electrical shortage.")
	var no_false_warnings := true
	var power_balanced := true
	for step in range(50):
		ship.tick(0.1)
		for id in ["main_engine", "reactor", "main_bus"]:
			no_false_warnings = no_false_warnings and presenter.equipment_status(id) not in ["Power limited", "Limited"]
			no_false_warnings = no_false_warnings and ship.components[id].power_constraint.is_empty()
		power_balanced = power_balanced and _near(engine.state.requested_power, engine.state.allocated_power)
		power_balanced = power_balanced and engine.state.power <= engine.state.allocated_power + 0.0001
	_check(no_false_warnings, "Pump ramp-up cannot invent electrical limitations on the engine or its healthy supply path.")
	_check(power_balanced, "Every recorded engine demand is fully granted throughout unconstrained pump ramp-up.")
	_check(ship.totals().spare > 40.0 and engine.state.thrust > 0.0,
		"The engine starts normally while the reactor retains ample spare capacity.")
	ship.tick(30.0)
	_check(_near(engine.state.thrust, 30.0) and presenter.equipment_status("main_engine") == "Online",
		"The reordered startup reaches the normal operating point.")


func _test_real_electrical_limit() -> void:
	var definition = _ramp_definition()
	for edge in definition.connections:
		if edge.id == "feed_engine":
			edge.capacity = 12.0
	_check(definition.validate().is_empty(), "The same startup can include a finite engine power cable.")
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	ship.tick(5.0)
	var engine = ship.components["main_engine"]
	_check(engine.state.requested_power > 12.0 and _near(engine.state.allocated_power, 12.0),
		"Rising coolant capability still exposes a genuine unmet electrical demand.")
	_check(presenter.equipment_status("main_engine") == "Power limited"
		and engine.power_constraint.get("connection_id") == "feed_engine",
		"A real supply restriction retains its electrical warning and limiting cable evidence.")
	_check(engine.state.power <= 12.0 and presenter.equipment_status("reactor") == "Online",
		"The cable limit bounds actual engine draw without blaming its healthy reactor.")


func _test_falling_circulation() -> void:
	var definition = Fixtures.copy_kestrel()
	definition.component("main_engine").parameters["priority"] = 0
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	_check(_near(ship.components["main_engine"].state.thrust, 30.0), "The safety fixture begins at healthy cruise thrust.")
	_check(ship.command("aux_bus", "closed", false).accepted, "The downstream coolant pump can lose its electrical supply.")
	ship.tick(0.1)
	var engine = ship.components["main_engine"]
	_check(_near(engine.state.cooling_limit, 0.0) and _near(engine.state.thrust, 0.0)
		and _near(engine.state.target_thrust, 0.0),
		"A later pump shutdown immediately clamps the earlier engine to its final safe circulation limit.")
	_check(_near(engine.state.requested_power, 0.0) and _near(engine.state.allocated_power, 0.0)
		and _near(engine.state.power, 0.0),
		"Falling circulation removes engine demand, allocation, and actual draw in the same step.")
	_check(engine.power_constraint.is_empty() and presenter.equipment_status("main_engine") == "Cooling limited",
		"The stopped engine retains its cooling diagnosis without an obsolete power constraint.")
	_check(ship.command("aux_bus", "closed", true).accepted, "Restoring the pump feed is accepted.")
	ship.tick(5.0)
	_check(engine.state.thrust > 0.0 and presenter.equipment_status("reactor") == "Online"
		and presenter.equipment_status("main_engine") != "Power limited",
		"Recovery through the same priority order also avoids false electrical warnings.")


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.001


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
