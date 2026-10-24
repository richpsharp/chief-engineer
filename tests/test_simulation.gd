extends SceneTree

const Simulation = preload("res://scripts/ship_simulation.gd")
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
	if failures == 0:
		print("PASS: %d continuous-simulation checks." % checks)
	else:
		printerr("FAIL: %d of %d continuous-simulation checks failed." % [failures, checks])
	quit(0 if failures == 0 else 1)


func _test_healthy_continuous_operation() -> void:
	var ship = Simulation.new()
	_check(not ship.paused, "Construction starts the healthy simulation running.")
	_near(ship.reactor_output, 152.0, "Normal ship demand is 152 kW.")
	_near(ship.bus_a_draw, 122.0, "Main bus includes base loads, Pump A, and engine.")
	_near(ship.bus_b_draw, 30.0, "Auxiliary bus supplies 18 kW base and a 12 kW pump.")
	_near(ship.pump_a_flow, 24.0, "Normal core-loop flow is 24 L/s.")
	_near(ship.pump_b_flow, 30.0, "Normal engine-loop flow is 30 L/s.")
	_near(ship.engine_thrust, 30.0, "Normal thrust is 30 percent.")
	_check(ship.life_support_powered and ship.sensors_powered, "Both buses' essential loads start powered.")
	_check(ship.conditions().is_empty(), "A healthy ship has no active warning conditions.")
	_advance_for(ship, 86400.0)
	_near(ship.elapsed, 86400.0, "Healthy operation continues for an entire simulated day.")
	_near(ship.main_temperature, 42.0, "Core remains at thermal equilibrium.", 0.01)
	_near(ship.engine_temperature, 55.0, "Engine remains at thermal equilibrium.", 0.01)
	_near(ship.coolant_temperature, 32.0, "Coolant remains at thermal equilibrium.", 0.01)
	_near(ship.reactor_output, 152.0, "Long operation does not consume a hidden reserve.")
	_check(ship.conditions().is_empty(), "Steady operation does not invent emergencies.")


func _test_auxiliary_limit_coupling() -> void:
	var ship = Simulation.new()
	ship.set_control("bus_b_limit", 22.0)
	_near(ship.bus_b_draw, 22.0, "The auxiliary limit includes its base load.")
	_near(ship.pump_b_power, 4.0, "After 18 kW base load, the limit leaves 4 kW for Pump B.")
	_near(ship.pump_b_flow, 10.0, "Four kW supports ten L/s of engine coolant.")
	_near(ship.engine_thrust, 10.0, "Ten L/s limits thrust to ten percent.")
	_near(ship.engine_power, 24.0, "Cooling-limited thrust reduces electrical draw too.")
	_near(ship.reactor_output, 96.0, "Source output matches reduced 74 + 22 kW loads.")
	_check(ship.equipment_status("pump_b") == "Power limited", "Pump reports its electrical restriction.")
	_check(ship.equipment_status("main_engine") == "Cooling limited", "Engine reports the downstream cooling restriction.")
	ship.set_control("bus_b_limit", 40.0)
	_near(ship.pump_b_flow, 10.0, "Restoring capacity does not instantly accelerate the pump.")
	ship.tick(0.5)
	_check(ship.pump_b_flow > 10.0 and ship.pump_b_flow < 30.0, "Flow recovers smoothly.")
	_check(ship.engine_thrust <= ship.pump_b_flow, "Engine cannot outrun available cooling during recovery.")
	_advance_for(ship, 60.0)
	_near(ship.pump_b_flow, 30.0, "Pump recovers to original flow.", 0.001)
	_near(ship.engine_thrust, 30.0, "Engine recovers without restart or repair.", 0.001)
	ship.set_control("engine_command", 60.0)
	_check(ship.engine_thrust <= 30.0, "An excessive request cannot bypass the cooling limit.")
	ship.set_control("pump_b_command", 40.0)
	_advance_for(ship, 60.0)
	_near(ship.engine_thrust, 40.0, "Increasing engine-loop flow raises attainable thrust.", 0.001)
	_near(ship.pump_b_power, 16.0, "Higher flow costs more power.", 0.001)


func _test_breakers_and_recovery() -> void:
	var ship = Simulation.new()
	ship.toggle_breaker("aux_bus")
	_near(ship.bus_b_draw, 0.0, "An open auxiliary breaker supplies no power.")
	_near(ship.pump_b_flow, 0.0, "An unpowered Pump B has no useful coolant output.")
	_near(ship.engine_thrust, 0.0, "Loss of engine cooling reduces thrust to zero.")
	_near(ship.reactor_output, 50.0, "Only main-bus base and Pump A remain.")
	_check(ship.life_support_powered and not ship.sensors_powered, "Auxiliary isolation leaves life support on its separate supply.")
	ship.toggle_breaker("aux_bus")
	_advance_for(ship, 60.0)
	_near(ship.reactor_output, 152.0, "Closing the breaker restores healthy operation.", 0.001)
	ship.toggle_breaker("main_bus")
	_near(ship.bus_a_draw, 0.0, "An open main breaker supplies no power.")
	_near(ship.pump_a_power, 0.0, "Isolated Pump A has no free energy.")
	_near(ship.engine_power, 0.0, "The isolated engine has no free energy.")
	_near(ship.reactor_output, 30.0, "Auxiliary loads remain independently supplied.", 0.001)
	_check(not ship.life_support_powered and ship.sensors_powered, "Main isolation has the correct load consequences.")
	ship.toggle_breaker("aux_bus")
	_near(ship.reactor_output, 0.0, "Opening both buses removes all electrical load.")
	ship.toggle_breaker("main_bus")
	ship.toggle_breaker("aux_bus")
	_advance_for(ship, 90.0)
	_near(ship.reactor_output, 152.0, "Both buses recover after complete isolation.", 0.001)


func _test_reactor_capacity_and_conservation() -> void:
	var ship = Simulation.new()
	for capacity in [0.0, 5.0, 20.0, 28.0, 35.0, 40.0, 45.0, 50.0, 65.0, 80.0, 100.0, 152.0, 180.0, 200.0]:
		ship.set_control("reactor_limit", capacity)
		_advance_for(ship, 60.0)
		_check(ship.reactor_output >= 0.0 and ship.reactor_output <= capacity + 0.00001, "Supply honors reactor capacity %.0f." % capacity)
		_near(ship.reactor_output, ship.bus_a_draw + ship.bus_b_draw, "Source equals the sum of both buses.")
		_near(ship.bus_a_draw, ship.base_a_power + ship.pump_a_power + ship.engine_power, "Main-bus accounting includes every actual load.")
		_near(ship.bus_b_draw, ship.base_b_power + ship.pump_b_power, "Auxiliary accounting includes every actual load.")
		_check(ship.bus_b_draw <= ship.bus_b_limit + 0.00001, "Local bus limit cannot be exceeded.")
		_check(ship.engine_thrust <= ship.pump_b_flow + 0.00001, "Cooling always constrains actual thrust.")
	ship.set_control("reactor_limit", 45.0)
	_near(ship.base_a_power, 40.0, "Critical main-bus loads receive priority.")
	_near(ship.pump_a_power, 5.0, "Pump A receives the next five kW.")
	_near(ship.base_b_power, 0.0, "Lower-priority loads receive no unavailable power.")
	_near(ship.engine_power, 0.0, "Propulsion receives no unavailable power.")
	ship.set_control("reactor_limit", 100.0)
	_advance_for(ship, 60.0)
	_near(ship.engine_power, 20.0, "At 100 kW, propulsion receives the remaining 20 kW.", 0.001)
	ship.set_control("reactor_limit", 20.0)
	_check(not ship.life_support_powered, "Insufficient source produces a life-support brownout.")
	_check(ship.system_summary("life_support")["state"] == "Brownout", "Partial power is distinguished from full supply.")


func _test_thermal_response_and_recovery() -> void:
	var ship = Simulation.new()
	ship.set_control("radiator_command", 0.0)
	_near(ship.radiator_rejection, 0.0, "Closed radiator rejects no active heat.")
	_advance_for(ship, 900.0)
	_check(ship.coolant_temperature > 45.0, "Waste heat raises coolant temperature with a closed radiator.")
	_check(ship.main_temperature > 50.0 and ship.engine_temperature > 60.0, "Hot coolant raises equipment temperatures.")
	_check(not ship.conditions().is_empty(), "Elevated temperatures create visible conditions.")
	var hot_coolant: float = ship.coolant_temperature
	ship.set_control("radiator_command", 100.0)
	_advance_for(ship, 300.0)
	_check(ship.coolant_temperature < hot_coolant, "Reopening radiator reverses the temperature trend.")
	_advance_for(ship, 3600.0)
	_near(ship.coolant_temperature, 32.0, "Coolant returns to healthy equilibrium.", 0.05)
	_near(ship.main_temperature, 42.0, "Core recovers without damage.", 0.05)
	_near(ship.engine_temperature, 55.0, "Engine recovers without repair/reset.", 0.05)
	ship.set_control("pump_a_command", 0.0)
	_advance_for(ship, 300.0)
	_check(ship.main_temperature > 50.0, "Stopping Pump A heats the core with radiator open.")
	_near(ship.radiator_rejection, 0.0, "Radiator needs circulation rather than cooling for free.")
	ship.set_control("pump_a_command", 24.0)
	_advance_for(ship, 3600.0)
	_near(ship.main_temperature, 42.0, "Restoring Pump A recovers the core.", 0.05)


func _test_stopped_circulation_warning() -> void:
	var ship = Simulation.new()
	ship.set_control("pump_a_command", 0.0)
	_near(ship.main_temperature, 42.0, "Stopping circulation does not instantly change core temperature.")
	var circulation_flagged: bool = false
	for condition in ship.conditions():
		if condition["system"] == "cooling" and condition["equipment"] == "pump_a":
			circulation_flagged = true
	_check(circulation_flagged, "Loss of radiator circulation immediately flags Pump A before heat rises.")
	ship.set_control("pump_a_command", 24.0)
	_advance_for(ship, 60.0)
	_check(ship.conditions().is_empty(), "Restored circulation clears the warning without reset.")


func _test_pause_and_reset() -> void:
	var ship = Simulation.new()
	ship.tick(4.0)
	ship.toggle_pause()
	var before: Dictionary = _snapshot(ship)
	ship.tick(20.0)
	ship.set_control("reactor_limit", 0.0)
	ship.set_control("pump_b_command", 0.0)
	ship.toggle_breaker("main_bus")
	_check(_snapshot(ship) == before, "Paused time, controls, temperatures, and events stay frozen.")
	ship.toggle_pause()
	ship.tick(1.0)
	_near(ship.elapsed, 5.0, "Resume excludes paused time.")
	ship.set_control("bus_b_limit", 0.0)
	ship.toggle_pause()
	ship.reset()
	_check(not ship.paused, "Reset resumes healthy operation.")
	_near(ship.elapsed, 0.0, "Reset clears elapsed time.")
	_near(ship.reactor_output, 152.0, "Reset restores physical operating state.")
	_check(ship.events.size() == 1 and ship.conditions().is_empty(), "Reset clears old conditions and events.")


func _test_inputs_and_bounded_ticks() -> void:
	var ship = Simulation.new()
	var before: Dictionary = _snapshot(ship)
	for delta in [0.0, -1.0, INF, NAN]:
		ship.tick(delta)
	ship.set_control("reactor_limit", INF)
	ship.set_control("pump_a_command", NAN)
	ship.set_control("unknown", 2.0)
	ship.toggle_breaker("unknown")
	_check(_snapshot(ship) == before, "Invalid inputs cannot poison the model.")
	ship.set_control("reactor_limit", 10000.0)
	_near(ship.reactor_limit, 200.0, "Reactor command cannot exceed its rating.")
	ship.set_control("bus_b_limit", 10000.0)
	_near(ship.bus_b_limit, 60.0, "Bus command is bounded.")
	ship.set_control("pump_a_command", -2.0)
	_near(ship.pump_a_command, 0.0, "Negative flow clamps to zero.")
	ship.set_control("pump_b_command", 10000.0)
	_near(ship.pump_b_command, 40.0, "Pump B has finite maximum flow.")
	ship.set_control("engine_command", 10000.0)
	_near(ship.engine_command, 60.0, "Engine request stays within range.")
	ship.set_control("radiator_command", -1.0)
	_near(ship.radiator_command, 0.0, "Radiator opening cannot be negative.")
	ship.tick(1.0e20)
	_check(ship.elapsed > 0.0 and ship.elapsed <= 60.0, "Huge delta advances bounded work.")
	_check(is_finite(ship.main_temperature) and is_finite(ship.coolant_temperature), "Large delta keeps temperatures finite.")
	_check(ship.reactor_output <= ship.reactor_limit + 0.00001, "Large delta preserves power conservation.")


func _test_log_and_reading_contract() -> void:
	var ship = Simulation.new()
	for index in range(80):
		ship.set_control("engine_command", float(index % 2) * 20.0)
	_check(ship.events.size() == 50, "Event history is bounded to fifty entries.")
	for equipment in ["reactor", "main_bus", "aux_bus", "pump_a", "pump_b", "heat_exchanger", "radiator", "battery", "main_engine"]:
		var rows: Array = ship.readings(equipment)
		_check(not rows.is_empty() and rows.size() <= 6, "Equipment %s has at most six reading rows." % equipment)
		for row in rows:
			_check(row.size() == 2 and row[0] is String and row[1] is String, "Readings are label/value string pairs.")
		_check(not ship.equipment_status(equipment).is_empty() and not ship.equipment_reason(equipment).is_empty(), "Equipment provides status and explanation.")
	for department in ["reactor", "power", "propulsion", "cooling", "life_support", "shielding", "sensors", "hull"]:
		var summary: Dictionary = ship.system_summary(department)
		_check(summary.has_all(["state", "value", "detail", "tone"]), "Department summaries have the UI contract.")
		_check(summary["tone"] in ["good", "warn", "neutral"], "Department tone is supported by UI.")
	_check(ship.readings("battery")[1][1] == "0.0 kW", "Battery is explicitly not an active energy source.")
	ship.set_control("bus_b_limit", 0.0)
	for condition in ship.conditions():
		_check(condition.has_all(["text", "system", "equipment"]), "Conditions identify system and equipment.")


func _advance_for(ship, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.000001:
		var step: float = minf(remaining, 30.0)
		ship.tick(step)
		remaining -= step


func _snapshot(ship) -> Dictionary:
	return {
		"paused": ship.paused, "elapsed": ship.elapsed, "events": ship.events.duplicate(),
		"reactor_limit": ship.reactor_limit, "bus_b_limit": ship.bus_b_limit,
		"bus_a_closed": ship.bus_a_closed, "bus_b_closed": ship.bus_b_closed,
		"pump_a_command": ship.pump_a_command, "pump_b_command": ship.pump_b_command,
		"engine_command": ship.engine_command, "radiator_command": ship.radiator_command,
		"pump_a_flow": ship.pump_a_flow, "pump_b_flow": ship.pump_b_flow,
		"engine_thrust": ship.engine_thrust, "reactor_output": ship.reactor_output,
		"bus_a_draw": ship.bus_a_draw, "bus_b_draw": ship.bus_b_draw,
		"main_temperature": ship.main_temperature, "engine_temperature": ship.engine_temperature,
		"coolant_temperature": ship.coolant_temperature, "radiator_rejection": ship.radiator_rejection,
	}


func _near(actual: float, expected: float, description: String, tolerance: float = 0.00001) -> void:
	_check(absf(actual - expected) < tolerance, "%s Expected %.6f, got %.6f." % [description, expected, actual])


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
