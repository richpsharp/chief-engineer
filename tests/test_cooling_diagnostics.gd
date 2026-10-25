extends SceneTree
## Circulation diagnostics must follow contributing restrictions, not link order.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Presenter = preload("res://scripts/presentation/ship_presenter.gd")
const Fixtures = preload("res://tests/ship_fixtures.gd")
const Connection = preload("res://scripts/definitions/connection_definition.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	for reversed in [false, true]:
		_test_failed_contributor(reversed)
		_test_healthy_aggregate_shortfall(reversed)
		_test_idle_and_ramping_contributor(reversed)
	_test_single_supply()
	_test_disconnected_supply()
	print("%s: %d cooling-diagnostic checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _test_failed_contributor(reversed: bool) -> void:
	var definition = _dual_feed(reversed)
	definition.component("aux_bus").initial_settings["closed"] = false
	_check(definition.validate().is_empty(), "Independent coolant inlets are a valid authored configuration.")
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	_check(presenter.equipment_status("pump_a") == "Online" and presenter.equipment_status("pump_b") == "Power limited",
		"Only the auxiliary pump loses electrical supply.")
	_check(is_equal_approx(ship.components["main_engine"].state.coolant_flow, 24.0)
		and presenter.equipment_status("main_engine") == "Cooling limited",
		"The healthy contributor supplies 24 L/s but cannot meet the engine's 30-percent request.")
	var condition: Dictionary = _engine_condition(presenter)
	_check(condition.get("cause_id") == "aux_bus" and condition.get("equipment") == "aux_bus"
		and condition.get("system") == "power", "Both connection orders route the cooling shortfall to the failed pump's power supply.")
	_check(presenter.equipment_reason("main_engine").contains("Inspect Auxiliary bus B")
		and not presenter.equipment_reason("main_engine").contains("Inspect Pump A"),
		"The inspector identifies the electrical restriction instead of blaming the healthy contributor.")


func _test_healthy_aggregate_shortfall(reversed: bool) -> void:
	var definition = _dual_feed(reversed)
	for id in ["pump_a", "pump_b"]:
		definition.component(id).initial_settings["flow"] = 10.0
		definition.component(id).initial_state["flow"] = 10.0
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	_check(ship.validation_errors.is_empty() and presenter.equipment_status("pump_a") == "Online"
		and presenter.equipment_status("pump_b") == "Online", "Both pumps meet their individual requests.")
	_check(is_equal_approx(ship.components["main_engine"].state.coolant_flow, 20.0)
		and presenter.equipment_status("main_engine") == "Cooling limited",
		"The sum of healthy contributions can still fall short of engine demand.")
	var condition: Dictionary = _engine_condition(presenter)
	_check(condition.get("cause_id") == "main_engine" and condition.get("equipment") == "main_engine",
		"An aggregate shortfall stays at the affected equipment rather than arbitrarily naming one healthy pump.")
	var reason: String = presenter.equipment_reason("main_engine")
	_check(reason.contains("Combined circulation") and not reason.contains("Inspect Pump"),
		"The inspector explains the combined shortfall without attributing a fault to a healthy pump.")
	var targets: Array = presenter.links("main_engine").map(func(link): return link.equipment)
	_check("pump_a" in targets and "pump_b" in targets, "Both coolant supplies remain reachable for adjusting their settings.")


func _test_idle_and_ramping_contributor(reversed: bool) -> void:
	for idle in [false, true]:
		var definition = _dual_feed(reversed)
		definition.component("pump_b").initial_state["flow"] = 0.0
		if idle:
			definition.component("pump_b").initial_settings["flow"] = 0.0
		var ship = Simulation.new(definition)
		var presenter = Presenter.new(ship)
		_check(presenter.equipment_status("pump_a") == "Online"
			and presenter.equipment_status("pump_b") == ("Idle" if idle else "Ramping"),
			"The contributing pump is explicitly idle or still building circulation.")
		_check(_engine_condition(presenter).get("cause_id") == "pump_b"
			and presenter.equipment_reason("main_engine").contains("Inspect Pump B"),
			"A demonstrated idle or ramping contributor is selected instead of the healthy pump, regardless of link order.")


func _test_single_supply() -> void:
	var definition = Fixtures.copy_kestrel()
	definition.component("aux_bus").initial_settings["closed"] = false
	var presenter = Presenter.new(Simulation.new(definition))
	_check(_engine_condition(presenter).get("cause_id") == "aux_bus",
		"A single electrically restricted coolant supply still routes to the electrical cause.")
	definition = Fixtures.copy_kestrel()
	definition.component("pump_b").initial_settings["flow"] = 10.0
	definition.component("pump_b").initial_state["flow"] = 10.0
	presenter = Presenter.new(Simulation.new(definition))
	_check(_engine_condition(presenter).get("cause_id") == "pump_b"
		and presenter.equipment_reason("main_engine").contains("Inspect Pump B"),
		"The only coolant supply remains the useful inspection target when its setting is too low.")


func _test_disconnected_supply() -> void:
	var definition = Fixtures.copy_kestrel()
	for edge in definition.connections.duplicate():
		var target: Dictionary = definition.resolve_port(edge.to_component, edge.to_port)
		if target.get("component") == "main_engine" and target.get("domain") == "coolant":
			definition.connections.erase(edge)
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	_check(ship.validation_errors.is_empty() and presenter.equipment_status("main_engine") == "Cooling limited",
		"A disconnected engine retains its circulation condition.")
	_check(_engine_condition(presenter).get("cause_id") == "main_engine"
		and _engine_condition(presenter).get("equipment") == "main_engine",
		"A missing coolant supply routes to the affected engine without inventing an upstream cause.")


func _dual_feed(reversed: bool):
	var definition = Fixtures.copy_kestrel()
	definition.component("main_engine").definition.ports["flow_secondary"] = {"domain": "coolant", "direction": "in"}
	var link = Connection.new()
	link.id = "backup_engine_circulation"
	link.from_component = "pump_a"
	link.from_port = "flow_out"
	link.to_component = "main_engine"
	link.to_port = "flow_secondary"
	definition.connections.push_front(link)
	if reversed:
		definition.connections.reverse()
	return definition


func _engine_condition(presenter) -> Dictionary:
	for condition in presenter.conditions():
		if condition.component_id == "main_engine" and condition.code == "engine.cooling_limited":
			return condition
	return {}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
