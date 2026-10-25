extends SceneTree
## Schematic activity follows committed connection transfers, not component totals.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Presenter = preload("res://scripts/presentation/ship_presenter.gd")
const Fixtures = preload("res://tests/ship_fixtures.gd")
const Connection = preload("res://scripts/definitions/connection_definition.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_exposed_reservoir()
	_test_independent_radiator_inlets()
	_test_independent_radiators()
	_test_reverse_transfer()
	_test_collapsed_path()
	print("%s: %d thermal-connection checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _test_exposed_reservoir() -> void:
	var definition = _exposed_reservoir()
	_check(definition.validate().is_empty(), "The existing reservoir can be exposed as inspectable equipment.")
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	_check(ship.has_method("thermal_transfer"), "The simulation publishes committed connection transfer readings.")
	_check(_near(ship.components["radiator"].state.heat_rejected, 55.22), "The exposed reservoir leaves healthy radiator rejection unchanged.")
	_check(_edge(presenter, "coolant_reservoir", "radiator").get("active", false),
		"An exposed reservoir's thermal connection is active while its radiator rejects heat.")
	_check(_near(_transfer(ship, "coolant_to_radiator"), 55.22), "The radiator connection reports its actual transfer in kW.")
	_check(_near(_transfer(ship, "core_heat"), _transfer(ship, "core_to_coolant"))
		and _transfer(ship, "core_heat") > 0.0, "Both sides of a single-path exchanger report its committed transfer.")
	_check(_near(_transfer(ship, "missing"), 0.0) and _near(_transfer(ship, "feed_engine"), 0.0),
		"Unknown and nonthermal connections have no thermal transfer.")
	_check(ship.command("radiator", "deployment", 0.0).accepted, "The radiator can be closed through its operating control.")
	ship.tick(0.1)
	_check(_near(_transfer(ship, "coolant_to_radiator"), 0.0)
		and not _edge(presenter, "coolant_reservoir", "radiator").get("active", true),
		"Closing the radiator clears its transfer reading and thermal connection activity.")
	ship.reset()
	_check(_near(_transfer(ship, "coolant_to_radiator"), 55.22)
		and _edge(presenter, "coolant_reservoir", "radiator").get("active", false),
		"Reset restores healthy transfer readings and activity without stale closed-state evidence.")
	_check(ship.command("pump_a", "flow", 0.0).accepted, "Radiator circulation can be stopped independently of deployment.")
	ship.tick(0.1)
	_check(_near(ship.components["radiator"].state.heat_rejected, 0.0)
		and _near(_transfer(ship, "coolant_to_radiator"), 0.0)
		and not _edge(presenter, "coolant_reservoir", "radiator").get("active", true),
		"Stopping circulation clears connection activity even while the radiator remains deployed.")
	ship.reset()
	definition.schema_version = -1
	ship.reset()
	_check(not ship.validation_errors.is_empty() and _near(_transfer(ship, "coolant_to_radiator"), 0.0),
		"An invalid reset exposes no stale transfer from the previous runtime.")


func _test_independent_radiator_inlets() -> void:
	for reversed in [false, true]:
		var definition = _exposed_reservoir()
		var cold = definition.component("coolant_reservoir").duplicate(true)
		cold.id = "cold_reservoir"
		cold.initial_state["temperature"] = definition.ambient_temperature
		definition.components.append(cold)
		definition.view("cooling").members.append(cold.id)
		definition.component("radiator").definition.ports["second_heat_in"] = {"domain": "thermal", "direction": "in"}
		definition.connections.append(_link("cold_to_radiator", cold.id, "heat_out", "radiator", "second_heat_in"))
		if reversed:
			definition.connections.reverse()
		_check(definition.validate().is_empty(), "A radiator can receive separate hot and ambient-temperature reservoirs.")
		var ship = Simulation.new(definition)
		var presenter = Presenter.new(ship)
		_check(_near(ship.components["radiator"].state.heat_rejected, 55.22), "Only the hot inlet contributes to aggregate rejection.")
		_check(_transfer(ship, "coolant_to_radiator") > 0.0 and _near(_transfer(ship, "cold_to_radiator"), 0.0),
			"Separate inlets retain their own transfer readings regardless of connection order.")
		_check(_edge(presenter, "coolant_reservoir", "radiator").get("active", false)
			and not _edge(presenter, "cold_reservoir", "radiator").get("active", true),
			"A radiator's aggregate rejection cannot activate its zero-transfer inlet.")


func _test_independent_radiators() -> void:
	var definition = _exposed_reservoir()
	var closed = definition.component("radiator").duplicate(true)
	closed.id = "closed_radiator"
	closed.initial_settings["deployment"] = 0.0
	definition.components.append(closed)
	definition.view("cooling").members.append(closed.id)
	definition.connections.append(_link("coolant_to_closed", "coolant_reservoir", "heat_out", closed.id, "heat_in"))
	definition.connections.append(_link("closed_circulation", "pump_a", "flow_out", closed.id, "flow_in"))
	for circuit in definition.coolant_circuits:
		if circuit.pump == "pump_a":
			circuit.members.append(closed.id)
	_check(definition.validate().is_empty(), "A reservoir can supply independently controlled radiator banks.")
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	_check(_transfer(ship, "coolant_to_radiator") > 0.0 and _near(_transfer(ship, "coolant_to_closed"), 0.0),
		"The shared source retains separate open- and closed-radiator transfer readings.")
	_check(_edge(presenter, "coolant_reservoir", "radiator").get("active", false)
		and not _edge(presenter, "coolant_reservoir", closed.id).get("active", true),
		"An active sibling radiator cannot activate a closed radiator's thermal connection.")


func _test_reverse_transfer() -> void:
	var definition = _exposed_reservoir()
	definition.component("coolant_reservoir").initial_state["temperature"] = 60.0
	_check(definition.validate().is_empty(), "A reservoir warmer than the engine and core is valid.")
	var ship = Simulation.new(definition)
	var presenter = Presenter.new(ship)
	_check(_transfer(ship, "engine_to_coolant") < 0.0 and _transfer(ship, "core_to_coolant") < 0.0
		and _near(_transfer(ship, "core_heat"), _transfer(ship, "core_to_coolant")),
		"Connections retain signed reverse transfer through engines and exchangers.")
	_check(_edge(presenter, "main_engine", "coolant_reservoir").get("active", false)
		and _edge(presenter, "heat_exchanger", "coolant_reservoir").get("active", false)
		and _edge(presenter, "reactor", "heat_exchanger").get("active", false),
		"Reverse thermal transfer remains active instead of being mistaken for no exchange.")


func _test_collapsed_path() -> void:
	var ship = Simulation.new()
	var presenter = Presenter.new(ship)
	_check(_edge(presenter, "heat_exchanger", "radiator").get("active", false)
		and _edge(presenter, "main_engine", "radiator").get("active", false),
		"The standard schematic collapses active thermal paths through its hidden reservoir.")
	ship.command("radiator", "deployment", 0.0)
	ship.tick(0.1)
	_check(_transfer(ship, "engine_to_coolant") > 0.0 and _near(_transfer(ship, "coolant_to_radiator"), 0.0),
		"Heat can enter storage even when its outgoing radiator connection has stopped.")
	_check(not _edge(presenter, "main_engine", "radiator").get("active", true)
		and not _edge(presenter, "heat_exchanger", "radiator").get("active", true),
		"A collapsed route is inactive when an intermediate connection stops transferring heat.")
	ship.reset()
	_check(_edge(presenter, "main_engine", "radiator").get("active", false), "Reset restores activity through the collapsed route.")
	var definition = _exposed_reservoir()
	ship = Simulation.new(definition)
	presenter = Presenter.new(ship)
	_check(_edge(presenter, "main_engine", "radiator").is_empty(),
		"An inspectable reservoir stops path collapsing even when omitted from the selected schematic endpoints.")


func _exposed_reservoir():
	var definition = Fixtures.copy_kestrel()
	definition.component("coolant_reservoir").inspectable = true
	definition.layouts["cooling"].nodes["coolant_reservoir"] = Rect2(750, 700, 190, 96)
	return definition


func _link(id: String, source: String, source_port: String, target: String, target_port: String):
	var link = Connection.new()
	link.id = id
	link.from_component = source
	link.from_port = source_port
	link.to_component = target
	link.to_port = target_port
	return link


func _edge(presenter, source: String, target: String) -> Dictionary:
	for edge in presenter.schematic_edges([source, target]):
		if edge.domain == "thermal" and edge.from_component == source and edge.to_component == target:
			return edge
	return {}


func _transfer(ship, connection_id: String) -> float:
	return float(ship.call("thermal_transfer", connection_id)) if ship.has_method("thermal_transfer") else 0.0


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.00001


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
