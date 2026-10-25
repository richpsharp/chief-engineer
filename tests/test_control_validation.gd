extends SceneTree
## Authored operating ranges must not permit negative physical outputs.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Fixtures = preload("res://tests/ship_fixtures.gd")
const Kestrel = preload("res://ships/kestrel.tres")
const OPERATING_CONTROLS = [["reactor", "limit"], ["main_bus", "limit"],
	["pump_a", "flow"], ["main_engine", "thrust"], ["radiator", "deployment"]]
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_check(Kestrel.validate().is_empty(), "The shipped operating ranges remain valid.")
	_test_negative_operating_ranges()
	_test_zero_operating_settings()
	_test_negative_temperatures()
	print("%s: %d control-validation checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _test_negative_operating_ranges() -> void:
	for entry in OPERATING_CONTROLS:
		var definition = Fixtures.copy_kestrel()
		var component_id: String = entry[0]
		var action: String = entry[1]
		for control in definition.component(component_id).definition.controls:
			if control.id == action:
				control["min"] = -10.0
		_check(not definition.validate().is_empty(),
			"A healthy initial value cannot legitimize a negative %s.%s control range." % [component_id, action])
		var ship = Simulation.new(definition)
		_check(not ship.command(component_id, action, -10.0).accepted,
			"An invalid authored range cannot authorize a negative %s command." % action)
		ship.tick(0.1)
		_check(ship.elapsed == 0.0 and ship.components.is_empty(),
			"A ship with a negative %s range cannot create or advance machinery." % action)


func _test_zero_operating_settings() -> void:
	for entry in OPERATING_CONTROLS:
		var ship = Simulation.new(Kestrel)
		_check(ship.command(entry[0], entry[1], 0.0).accepted,
			"Zero remains a valid operating command for %s.%s." % [entry[0], entry[1]])
		ship.tick(0.1)
		var nonnegative: bool = ship.elapsed > 0.0 and ship.totals().output >= 0.0
		for component in ship.components.values():
			for key in ["flow", "thrust", "power"]:
				nonnegative = nonnegative and float(component.state.get(key, 0.0)) >= 0.0
		_check(nonnegative, "Valid zero settings preserve nonnegative flow, thrust, and power.")


func _test_negative_temperatures() -> void:
	var definition = Fixtures.copy_kestrel()
	definition.component("reactor").initial_state["temperature"] = -20.0
	definition.component("reactor").parameters["warning_temperature"] = -5.0
	_check(definition.validate().is_empty(), "Negative Celsius temperatures and advisory levels remain valid.")
	var ship = Simulation.new(definition)
	_check(ship.components.has("reactor") and ship.components["reactor"].state.temperature == -20.0,
		"Range validation preserves a negative initial temperature without clamping it.")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
