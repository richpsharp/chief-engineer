extends SceneTree

const Simulation = preload("res://scripts/ship_simulation.gd")
const Presenter = preload("res://scripts/presentation/ship_presenter.gd")
const MAIN_LOADS = ["life_support", "avionics", "hull_services", "shielding"]
const AUX_LOADS = ["sensors", "habitat"]
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_healthy_continuous_operation()
	_test_auxiliary_limit_coupling()
	_test_breakers_and_recovery()
	_test_reactor_capacity_and_conservation()
	_test_thermal_response_and_recovery()
	_test_stopped_circulation_warning()
	_test_pause_and_reset()
	_test_inputs_and_bounded_ticks()
	_test_log_and_reading_contract()
	print("%s: %d continuous-simulation checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _test_healthy_continuous_operation() -> void:
	var ship = Simulation.new()
	_check(ship.validation_errors.is_empty(), "Kestrel is a valid ship definition.")
	_check(not ship.paused, "Construction starts the healthy simulation running.")
	_near(ship.totals().output, 152.0, "Normal ship demand is 152 kW.")
	_near(_s(ship, "main_bus", "draw"), 122.0, "Main bus includes base loads, Pump A, and engine.")
	_near(_s(ship, "aux_bus", "draw"), 30.0, "Auxiliary bus supplies 18 kW base and a 12 kW pump.")
	_near(_s(ship, "pump_a", "flow"), 24.0, "Normal core-loop flow is 24 L/s.")
	_near(_s(ship, "pump_b", "flow"), 30.0, "Normal engine-loop flow is 30 L/s.")
	_near(_s(ship, "main_engine", "thrust"), 30.0, "Normal thrust is 30 percent.")
	_check(_loads_powered(ship, MAIN_LOADS) and _loads_powered(ship, AUX_LOADS), "Both buses' service loads start powered.")
	_check(Presenter.new(ship).conditions().is_empty(), "A healthy ship has no active warning conditions.")
	_advance_for(ship, 86400.0)
	_near(ship.elapsed, 86400.0, "Healthy operation continues for an entire simulated day.", 0.001)
	_near(_s(ship, "reactor", "temperature"), 42.0, "Core remains at thermal equilibrium.", 0.05)
	_near(_s(ship, "main_engine", "temperature"), 55.0, "Engine remains at thermal equilibrium.", 0.05)
	_near(_s(ship, "coolant_reservoir", "temperature"), 32.0, "Coolant remains at thermal equilibrium.", 0.05)
	_near(ship.totals().output, 152.0, "Long operation does not consume a hidden reserve.")
	_check(Presenter.new(ship).conditions().is_empty(), "Steady operation does not invent emergencies.")


func _test_auxiliary_limit_coupling() -> void:
	var ship = Simulation.new()
	_command(ship, "aux_bus", "limit", 22.0)
	_near(_s(ship, "aux_bus", "draw"), 22.0, "The auxiliary limit includes its base load.")
	_near(_s(ship, "pump_b", "power"), 4.0, "After 18 kW base load, the limit leaves 4 kW for Pump B.")
	_near(_s(ship, "pump_b", "flow"), 10.0, "Four kW supports ten L/s of engine coolant.")
	_near(_s(ship, "main_engine", "thrust"), 10.0, "Ten L/s limits thrust to ten percent.")
	_near(_s(ship, "main_engine", "power"), 24.0, "Cooling-limited thrust reduces electrical draw too.")
	_near(ship.totals().output, 96.0, "Source output matches reduced 74 + 22 kW loads.")
	_check(Presenter.new(ship).equipment_status("pump_b") == "Power limited", "Pump reports its electrical restriction.")
	_check(Presenter.new(ship).equipment_status("main_engine") == "Cooling limited", "Engine reports the downstream cooling restriction.")
	_command(ship, "aux_bus", "limit", 40.0)
	_check(_s(ship, "pump_b", "flow") > 10.0 and _s(ship, "pump_b", "flow") < 30.0, "Restoring capacity starts a gradual pump recovery.")
	ship.tick(0.5)
	_check(_s(ship, "pump_b", "flow") < 30.0, "Flow does not jump to its full request.")
	_check(_s(ship, "main_engine", "thrust") <= _s(ship, "pump_b", "flow"), "Engine cannot outrun available cooling during recovery.")
	_advance_for(ship, 60.0)
	_near(_s(ship, "pump_b", "flow"), 30.0, "Pump recovers to original flow.", 0.001)
	_near(_s(ship, "main_engine", "thrust"), 30.0, "Engine recovers without restart or repair.", 0.001)
	_command(ship, "main_engine", "thrust", 60.0)
	_check(_s(ship, "main_engine", "thrust") <= 30.0, "An excessive request cannot bypass the cooling limit.")
	_command(ship, "pump_b", "flow", 40.0)
	_advance_for(ship, 60.0)
	_near(_s(ship, "main_engine", "thrust"), 40.0, "Increasing engine-loop flow raises attainable thrust.", 0.001)
	_near(_s(ship, "pump_b", "power"), 16.0, "Higher flow costs more power.", 0.001)


func _test_breakers_and_recovery() -> void:
	var ship = Simulation.new()
	_command(ship, "aux_bus", "closed", false)
	_near(_s(ship, "aux_bus", "draw"), 0.0, "An open auxiliary breaker supplies no power.")
	_near(_s(ship, "pump_b", "flow"), 0.0, "An unpowered Pump B has no useful coolant output.")
	_near(_s(ship, "main_engine", "thrust"), 0.0, "Loss of engine cooling reduces thrust to zero.")
	_near(ship.totals().output, 50.0, "Only main-bus base and Pump A remain.")
	_check(_loads_powered(ship, MAIN_LOADS) and not _loads_powered(ship, AUX_LOADS), "Auxiliary isolation leaves main services supplied.")
	_command(ship, "aux_bus", "closed", true)
	_advance_for(ship, 60.0)
	_near(ship.totals().output, 152.0, "Closing the breaker restores healthy operation.", 0.001)
	_command(ship, "main_bus", "closed", false)
	_near(_s(ship, "main_bus", "draw"), 0.0, "An open main breaker supplies no power.")
	_near(_s(ship, "pump_a", "power"), 0.0, "Isolated Pump A has no free energy.")
	_near(_s(ship, "main_engine", "power"), 0.0, "The isolated engine has no free energy.")
	_near(ship.totals().output, 30.0, "Auxiliary loads remain independently supplied.", 0.001)
	_check(not _loads_powered(ship, MAIN_LOADS) and _loads_powered(ship, AUX_LOADS), "Main isolation has the correct load consequences.")
	_command(ship, "aux_bus", "closed", false)
	_near(ship.totals().output, 0.0, "Opening both buses removes all electrical load.")
	_command(ship, "main_bus", "closed", true)
	_command(ship, "aux_bus", "closed", true)
	_advance_for(ship, 90.0)
	_near(ship.totals().output, 152.0, "Both buses recover after complete isolation.", 0.001)


func _test_reactor_capacity_and_conservation() -> void:
	var ship = Simulation.new()
	for capacity in [0.0, 5.0, 20.0, 28.0, 35.0, 40.0, 45.0, 50.0, 65.0, 80.0, 100.0, 152.0, 180.0, 200.0]:
		_command(ship, "reactor", "limit", capacity)
		_advance_for(ship, 60.0)
		_check(ship.totals().output >= 0.0 and ship.totals().output <= capacity + 0.00001, "Supply honors reactor capacity %.0f." % capacity)
		_near(ship.totals().output, _s(ship, "main_bus", "draw") + _s(ship, "aux_bus", "draw"), "Source equals the sum of both buses.")
		_near(_s(ship, "main_bus", "draw"), _sum_power(ship, MAIN_LOADS) + _s(ship, "pump_a", "power") + _s(ship, "main_engine", "power"), "Main-bus accounting includes every actual load.")
		_near(_s(ship, "aux_bus", "draw"), _sum_power(ship, AUX_LOADS) + _s(ship, "pump_b", "power"), "Auxiliary accounting includes every actual load.")
		_check(_s(ship, "aux_bus", "draw") <= _setting(ship, "aux_bus", "limit") + 0.00001, "Local bus limit cannot be exceeded.")
		_check(_s(ship, "main_engine", "thrust") <= _s(ship, "pump_b", "flow") + 0.00001, "Cooling always constrains actual thrust.")
	_command(ship, "reactor", "limit", 45.0)
	_near(_sum_power(ship, MAIN_LOADS), 40.0, "Critical main-bus loads receive priority.")
	_near(_s(ship, "pump_a", "power"), 5.0, "Pump A receives the next five kW.")
	_near(_sum_power(ship, AUX_LOADS), 0.0, "Lower-priority loads receive no unavailable power.")
	_near(_s(ship, "main_engine", "power"), 0.0, "Propulsion receives no unavailable power.")
	_command(ship, "reactor", "limit", 100.0)
	_advance_for(ship, 60.0)
	_near(_s(ship, "main_engine", "power"), 20.0, "At 100 kW, propulsion receives the remaining 20 kW.", 0.001)
	_command(ship, "reactor", "limit", 20.0)
	_check(not _loads_powered(ship, MAIN_LOADS), "Insufficient source produces a service brownout.")
	_check(Presenter.new(ship).system_summary("life_support").state == "Brownout", "Partial power is distinguished from full supply.")


func _test_thermal_response_and_recovery() -> void:
	var ship = Simulation.new()
	_command(ship, "radiator", "deployment", 0.0)
	_near(_s(ship, "radiator", "heat_rejected"), 0.0, "Closed radiator rejects no active heat.")
	_advance_for(ship, 900.0)
	_check(_s(ship, "coolant_reservoir", "temperature") > 45.0, "Waste heat raises coolant temperature with a closed radiator.")
	_check(_s(ship, "reactor", "temperature") > 50.0 and _s(ship, "main_engine", "temperature") > 60.0, "Hot coolant raises equipment temperatures.")
	_check(not Presenter.new(ship).conditions().is_empty(), "Elevated temperatures create visible conditions.")
	var hot_coolant: float = _s(ship, "coolant_reservoir", "temperature")
	_command(ship, "radiator", "deployment", 100.0)
	_advance_for(ship, 300.0)
	_check(_s(ship, "coolant_reservoir", "temperature") < hot_coolant, "Reopening radiator reverses the temperature trend.")
	_advance_for(ship, 3600.0)
	_near(_s(ship, "coolant_reservoir", "temperature"), 32.0, "Coolant returns to healthy equilibrium.", 0.05)
	_near(_s(ship, "reactor", "temperature"), 42.0, "Core recovers without damage.", 0.05)
	_near(_s(ship, "main_engine", "temperature"), 55.0, "Engine recovers without repair/reset.", 0.05)
	_command(ship, "pump_a", "flow", 0.0)
	_advance_for(ship, 300.0)
	_check(_s(ship, "reactor", "temperature") > 50.0, "Stopping Pump A heats the core with radiator open.")
	_near(_s(ship, "radiator", "heat_rejected"), 0.0, "Radiator needs circulation rather than cooling for free.")
	_command(ship, "pump_a", "flow", 24.0)
	_advance_for(ship, 3600.0)
	_near(_s(ship, "reactor", "temperature"), 42.0, "Restoring Pump A recovers the core.", 0.05)


func _test_stopped_circulation_warning() -> void:
	var ship = Simulation.new()
	_command(ship, "pump_a", "flow", 0.0)
	_check(absf(_s(ship, "reactor", "temperature") - 42.0) < 0.05, "Stopping circulation does not instantly overheat the core.")
	var circulation_flagged := false
	for condition in Presenter.new(ship).conditions():
		if condition.equipment == "pump_a" or condition.cause_id == "pump_a":
			circulation_flagged = true
	_check(circulation_flagged, "Loss of radiator circulation immediately identifies Pump A before heat rises.")
	_command(ship, "pump_a", "flow", 24.0)
	_advance_for(ship, 60.0)
	_check(Presenter.new(ship).conditions().is_empty(), "Restored circulation clears the warning without reset.")


func _test_pause_and_reset() -> void:
	var ship = Simulation.new()
	ship.tick(4.0)
	ship.toggle_pause()
	var before: Dictionary = _physical_snapshot(ship)
	ship.tick(20.0)
	_check(not ship.command("reactor", "limit", 0.0).accepted, "Paused source commands are rejected.")
	_check(not ship.command("pump_b", "flow", 0.0).accepted, "Paused pump commands are rejected.")
	_check(not ship.command("main_bus", "closed", false).accepted, "Paused breaker commands are rejected.")
	_check(_physical_snapshot(ship) == before, "Paused time, settings, and physical state stay frozen.")
	ship.toggle_pause()
	ship.tick(1.0)
	_near(ship.elapsed, 5.0, "Resume excludes paused time.")
	_command(ship, "aux_bus", "limit", 0.0)
	ship.toggle_pause()
	ship.reset()
	_check(not ship.paused, "Reset resumes healthy operation.")
	_near(ship.elapsed, 0.0, "Reset clears elapsed time.")
	_near(ship.totals().output, 152.0, "Reset restores physical operating state.")
	_check(ship.events.size() == 1 and Presenter.new(ship).conditions().is_empty(), "Reset clears old conditions and events.")


func _test_inputs_and_bounded_ticks() -> void:
	var ship = Simulation.new()
	var before: Dictionary = _physical_snapshot(ship)
	for delta in [0.0, -1.0, INF, NAN]:
		ship.tick(delta)
	for request in [["reactor", "limit", INF], ["pump_a", "flow", NAN], ["unknown", "limit", 2.0], ["reactor", "unknown", 2.0], ["main_bus", "closed", 3.0], ["reactor", "limit", 10000.0], ["aux_bus", "limit", 10000.0], ["pump_a", "flow", -2.0], ["pump_b", "flow", 10000.0], ["main_engine", "thrust", 10000.0], ["radiator", "deployment", -1.0]]:
		_check(not ship.command(request[0], request[1], request[2]).accepted, "Malformed or out-of-range commands are rejected.")
	_check(_physical_snapshot(ship) == before, "Invalid inputs cannot poison committed state or queue commands.")
	ship.tick(1.0e20)
	_check(ship.elapsed > 0.0 and ship.elapsed <= 30.00001, "Huge delta advances bounded work.")
	_check(is_finite(_s(ship, "reactor", "temperature")) and is_finite(_s(ship, "coolant_reservoir", "temperature")), "Large delta keeps temperatures finite.")
	_check(ship.totals().output <= _setting(ship, "reactor", "limit") + 0.00001, "Large delta preserves the source limit.")


func _test_log_and_reading_contract() -> void:
	var ship = Simulation.new()
	for index in range(80):
		_command(ship, "main_engine", "thrust", float(index % 2) * 20.0)
	_check(ship.events.size() == 50 and ship.command_results.size() == 50, "Event and command history stay bounded.")
	var presenter = Presenter.new(ship)
	for spec in ship.definition.components:
		if not spec.inspectable:
			continue
		var rows: Array = presenter.readings(spec.id)
		_check(not rows.is_empty() and rows.size() <= 7, "Inspectable equipment has at most seven reading rows, including thermal trend.")
		for row in rows:
			_check(row.size() == 2 and row[0] is String and row[1] is String, "Presentation readings are label/value string pairs.")
		_check(not presenter.equipment_status(spec.id).is_empty(), "Equipment provides a readable status.")
	for view in ship.definition.views:
		var summary: Dictionary = presenter.system_summary(view.id)
		_check(summary.has_all(["state", "value", "detail", "tone"]), "Department summaries have the UI contract.")
		_check(summary.tone in ["good", "warn", "neutral"], "Department tone is supported by UI.")
	_near(_s(ship, "battery", "power"), 0.0, "The isolated battery is not an active energy source.")
	_command(ship, "aux_bus", "limit", 0.0)
	for condition in presenter.conditions():
		_check(condition.has_all(["code", "text", "system", "equipment", "cause_id"]), "Conditions identify their affected machinery and cause.")
		_check(ship.definition.component(condition.equipment) != null and ship.definition.workspace_for(condition.equipment) == condition.system, "Condition links target a valid equipment workspace.")


func _command(ship, component: String, action: String, value: Variant) -> void:
	_check(ship.command(component, action, value).accepted, "Valid addressed command is accepted: %s.%s." % [component, action])
	ship.tick(0.1)


func _physical_snapshot(ship) -> Dictionary:
	var result: Dictionary = ship.snapshot()
	# Rejected attempts are recorded for feedback without changing machinery.
	result.erase("command_sequence")
	return result


func _s(ship, component: String, key: String) -> float:
	return float(ship.components[component].state.get(key, 0.0))


func _setting(ship, component: String, key: String) -> float:
	return float(ship.components[component].settings[key])


func _loads_powered(ship, ids: Array) -> bool:
	for id in ids:
		if _s(ship, id, "power") < float(ship.components[id].config.rated_power) - 0.00001:
			return false
	return true


func _sum_power(ship, ids: Array) -> float:
	var total := 0.0
	for id in ids:
		total += _s(ship, id, "power")
	return total


func _advance_for(ship, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.000001:
		var step: float = minf(remaining, 30.0)
		ship.tick(step)
		remaining -= step


func _near(actual: float, expected: float, description: String, tolerance: float = 0.00001) -> void:
	_check(absf(actual - expected) < tolerance, "%s Expected %.6f, got %.6f." % [description, expected, actual])


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
