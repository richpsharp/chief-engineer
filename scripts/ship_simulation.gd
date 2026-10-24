class_name ShipSimulation
extends RefCounted

## Continuous ship-systems model. Units: kW, L/s, degrees C, and percentages.
## Pause freezes controls as well as time; only resume/reset remain available.

const REACTOR_RATING: float = 200.0
const BASE_A_DEMAND: float = 40.0
const BASE_B_DEMAND: float = 18.0
const PUMP_A_KW_PER_FLOW: float = 10.0 / 24.0
const PUMP_B_KW_PER_FLOW: float = 12.0 / 30.0
const ENGINE_KW_PER_THRUST: float = 72.0 / 30.0
const AMBIENT_TEMPERATURE: float = 10.0
const MAX_TICK_SECONDS: float = 30.0
const MAX_SUBSTEP: float = 0.25
const LOG_LIMIT: int = 50

var paused: bool = false
var elapsed: float = 0.0
var events: Array[String] = []
var reactor_limit: float = 200.0
var bus_a_closed: bool = true
var bus_b_closed: bool = true
var bus_b_limit: float = 40.0
var pump_a_command: float = 24.0
var pump_b_command: float = 30.0
var radiator_command: float = 100.0
var engine_command: float = 30.0

var pump_a_flow: float = 24.0
var pump_b_flow: float = 30.0
var engine_thrust: float = 30.0
var reactor_output: float = 152.0
var bus_a_draw: float = 122.0
var bus_b_draw: float = 30.0
var pump_a_power: float = 10.0
var pump_b_power: float = 12.0
var engine_power: float = 72.0
var base_a_power: float = 40.0
var base_b_power: float = 18.0
var pump_a_target: float = 24.0
var pump_b_target: float = 30.0
var engine_target: float = 30.0
var engine_power_available: float = 120.0
var main_temperature: float = 42.0
var engine_temperature: float = 55.0
var coolant_temperature: float = 32.0
var radiator_rejection: float = 55.22
var heat_produced: float = 61.36
var heat_transferred: float = 56.1
var life_support_powered: bool = true
var sensors_powered: bool = true


func _init() -> void:
	reset()


func reset() -> void:
	paused = false
	elapsed = 0.0
	reactor_limit = 200.0
	bus_a_closed = true
	bus_b_closed = true
	bus_b_limit = 40.0
	pump_a_command = 24.0
	pump_b_command = 30.0
	radiator_command = 100.0
	engine_command = 30.0
	pump_a_flow = 24.0
	pump_b_flow = 30.0
	engine_thrust = 30.0
	main_temperature = 42.0
	engine_temperature = 55.0
	coolant_temperature = 32.0
	events.clear()
	_recompute_power()
	_update_heat_readings()
	_record("Ship online. All systems are at their normal operating settings.")


func tick(delta: float) -> void:
	if paused or not is_finite(delta) or delta <= 0.0:
		return
	# Bound unusually long frames to 30 simulated seconds and 120 substeps.
	var remaining: float = minf(delta, MAX_TICK_SECONDS)
	while remaining > 0.0000001:
		var step: float = minf(remaining, MAX_SUBSTEP)
		_advance(step)
		elapsed += step
		remaining -= step


func toggle_pause() -> void:
	paused = not paused
	_record("Simulation paused. Settings are frozen." if paused else "Simulation resumed.")


func set_control(id: String, value: float) -> void:
	if paused or not is_finite(value):
		return
	var previous: float
	var applied: float
	var label: String
	var unit: String
	match id:
		"reactor_limit", "reactor":
			previous = reactor_limit
			reactor_limit = clampf(value, 0.0, REACTOR_RATING)
			applied = reactor_limit
			label = "Reactor output limit"
			unit = "kW"
		"bus_b_limit", "aux_bus":
			previous = bus_b_limit
			bus_b_limit = clampf(value, 0.0, 60.0)
			applied = bus_b_limit
			label = "Auxiliary bus limit"
			unit = "kW"
		"pump_a_command", "pump_a":
			previous = pump_a_command
			pump_a_command = clampf(value, 0.0, 36.0)
			applied = pump_a_command
			label = "Pump A flow request"
			unit = "L/s"
		"pump_b_command", "pump_b":
			previous = pump_b_command
			pump_b_command = clampf(value, 0.0, 40.0)
			applied = pump_b_command
			label = "Pump B flow request"
			unit = "L/s"
		"radiator_command", "radiator":
			previous = radiator_command
			radiator_command = clampf(value, 0.0, 100.0)
			applied = radiator_command
			label = "Radiator opening"
			unit = "%"
		"engine_command", "main_engine":
			previous = engine_command
			engine_command = clampf(value, 0.0, 60.0)
			applied = engine_command
			label = "Main engine request"
			unit = "%"
		_:
			return
	if is_equal_approx(previous, applied):
		return
	_recompute_power()
	_update_heat_readings()
	_record("%s set to %.1f %s." % [label, applied, unit])


func toggle_breaker(id: String) -> void:
	if paused:
		return
	match id:
		"main_bus":
			bus_a_closed = not bus_a_closed
			_record("Main bus breaker " + ("closed." if bus_a_closed else "opened."))
		"aux_bus":
			bus_b_closed = not bus_b_closed
			_record("Auxiliary bus breaker " + ("closed." if bus_b_closed else "opened."))
		_:
			return
	_recompute_power()
	_update_heat_readings()


func _advance(delta: float) -> void:
	_recompute_power()
	var pump_response: float = 1.0 - exp(-delta / 1.5)
	pump_a_flow = lerpf(pump_a_flow, pump_a_target, pump_response)
	pump_b_flow = lerpf(pump_b_flow, pump_b_target, pump_response)
	engine_target = minf(engine_command, minf(pump_b_flow, engine_power_available / ENGINE_KW_PER_THRUST))
	engine_thrust = minf(engine_thrust, engine_target)
	engine_thrust = lerpf(engine_thrust, engine_target, 1.0 - exp(-delta / 2.5))
	_update_actual_power()
	_update_heat_readings()
	# Transfers conserve heat between thermal masses; passive losses permit a
	# finite, recoverable hot equilibrium even with the radiator closed.
	var main_heat: float = _main_heat()
	var engine_heat: float = engine_power * 0.55
	var main_transfer: float = _main_transfer()
	var engine_transfer: float = _engine_transfer()
	main_temperature += delta * (main_heat - main_transfer - 0.08 * (main_temperature - AMBIENT_TEMPERATURE)) / 80.0
	engine_temperature += delta * (engine_heat - engine_transfer - 0.06 * (engine_temperature - AMBIENT_TEMPERATURE)) / 100.0
	coolant_temperature += delta * (main_transfer + engine_transfer - radiator_rejection - 0.04 * (coolant_temperature - AMBIENT_TEMPERATURE)) / 200.0
	_update_heat_readings()


func _recompute_power() -> void:
	var available: float = reactor_limit
	base_a_power = minf(BASE_A_DEMAND, available) if bus_a_closed else 0.0
	available -= base_a_power
	var allocated_a: float = minf(pump_a_command * PUMP_A_KW_PER_FLOW, available) if bus_a_closed else 0.0
	available -= allocated_a
	pump_a_target = allocated_a / PUMP_A_KW_PER_FLOW
	var available_b: float = minf(bus_b_limit, available) if bus_b_closed else 0.0
	base_b_power = minf(BASE_B_DEMAND, available_b)
	available_b -= base_b_power
	var allocated_b: float = minf(pump_b_command * PUMP_B_KW_PER_FLOW, available_b)
	available -= base_b_power + allocated_b
	pump_b_target = allocated_b / PUMP_B_KW_PER_FLOW
	engine_power_available = maxf(0.0, available) if bus_a_closed else 0.0
	# Safety reductions are immediate; restored output ramps up in tick().
	# A motor's unused allocation is unused source capacity, not consumed power.
	pump_a_flow = minf(pump_a_flow, pump_a_target)
	pump_b_flow = minf(pump_b_flow, pump_b_target)
	engine_target = minf(engine_command, minf(pump_b_flow, engine_power_available / ENGINE_KW_PER_THRUST))
	engine_thrust = minf(engine_thrust, engine_target)
	_update_actual_power()


func _update_actual_power() -> void:
	pump_a_power = pump_a_flow * PUMP_A_KW_PER_FLOW
	pump_b_power = pump_b_flow * PUMP_B_KW_PER_FLOW
	engine_power = engine_thrust * ENGINE_KW_PER_THRUST
	bus_a_draw = base_a_power + pump_a_power + engine_power
	bus_b_draw = base_b_power + pump_b_power
	reactor_output = bus_a_draw + bus_b_draw
	life_support_powered = base_a_power >= 28.0 - 0.00001
	sensors_powered = base_b_power >= 8.0 - 0.00001


func _main_heat() -> float:
	return (reactor_output - engine_power) * 0.12 + reactor_output * 0.08


func _main_transfer() -> float:
	return pump_a_flow * 0.08 * (main_temperature - coolant_temperature)


func _engine_transfer() -> float:
	return pump_b_flow * (36.9 / 23.0 / 30.0) * (engine_temperature - coolant_temperature)


func _update_heat_readings() -> void:
	heat_produced = _main_heat() + engine_power * 0.55
	heat_transferred = _main_transfer() + _engine_transfer()
	radiator_rejection = maxf(0.0, coolant_temperature - AMBIENT_TEMPERATURE) * 2.51 * (radiator_command / 100.0) * (pump_a_flow / 24.0)


func readings(id: String) -> Array[Array]:
	match id:
		"reactor":
			return [["Output", _kw(reactor_output)], ["Output limit", _kw(reactor_limit)], ["Unused capacity", _kw(maxf(0.0, reactor_limit - reactor_output))], ["Core temperature", _temp(main_temperature)], ["Ship waste heat", _kw(heat_produced)]]
		"main_bus":
			return [["Breaker", "CLOSED" if bus_a_closed else "OPEN"], ["Total draw", _kw(bus_a_draw)], ["Base loads", "%.1f / 40 kW" % base_a_power], ["Pump A", _kw(pump_a_power)], ["Main engine", _kw(engine_power)]]
		"aux_bus":
			return [["Breaker", "CLOSED" if bus_b_closed else "OPEN"], ["Total draw", _kw(bus_b_draw)], ["Local limit", _kw(bus_b_limit)], ["Base loads", "%.1f / 18 kW" % base_b_power], ["Pump B", _kw(pump_b_power)]]
		"pump_a":
			return [["Flow request", _flow(pump_a_command)], ["Actual flow", _flow(pump_a_flow)], ["Power draw", _kw(pump_a_power)], ["Supply", "Main bus"], ["Core temperature", _temp(main_temperature)]]
		"pump_b":
			return [["Flow request", _flow(pump_b_command)], ["Actual flow", _flow(pump_b_flow)], ["Power draw", _kw(pump_b_power)], ["Supply", "Auxiliary bus"], ["Cooling limit", "%.1f %% thrust" % pump_b_flow]]
		"heat_exchanger":
			return [["Core", _temp(main_temperature)], ["Coolant", _temp(coolant_temperature)], ["Loop A flow", _flow(pump_a_flow)], ["Core heat transfer", _kw(_main_transfer())], ["Core heat input", _kw(_main_heat())]]
		"radiator":
			return [["Opening", "%.1f %%" % radiator_command], ["Heat rejected", _kw(radiator_rejection)], ["Coolant", _temp(coolant_temperature)], ["Circulation", _flow(pump_a_flow)], ["Ambient reference", _temp(AMBIENT_TEMPERATURE)]]
		"battery":
			return [["State", "Standby reference"], ["Output", "0.0 kW"], ["Energy storage", "Not simulated"], ["Role", "Not a power source"]]
		"main_engine":
			return [["Thrust request", "%.1f %%" % engine_command], ["Actual thrust", "%.1f %%" % engine_thrust], ["Power draw", _kw(engine_power)], ["Available power", _kw(engine_power_available)], ["Cooling limit", "%.1f %%" % pump_b_flow], ["Temperature", _temp(engine_temperature)]]
	return []


func equipment_status(id: String) -> String:
	match id:
		"reactor":
			if reactor_limit <= 0.0:
				return "Offline"
			return "Limited" if _requested_power() > reactor_limit + 0.1 else "Online"
		"main_bus":
			if not bus_a_closed:
				return "Isolated"
			var engine_power_limited: bool = engine_power_available < minf(engine_command, pump_b_flow) * ENGINE_KW_PER_THRUST - 0.1
			return "Limited" if base_a_power < BASE_A_DEMAND - 0.1 or pump_a_target < pump_a_command - 0.1 or engine_power_limited else "Online"
		"aux_bus":
			if not bus_b_closed:
				return "Isolated"
			return "Limited" if base_b_power < BASE_B_DEMAND - 0.1 or pump_b_target < pump_b_command - 0.1 else "Online"
		"pump_a":
			return _pump_status(pump_a_command, pump_a_flow, pump_a_target)
		"pump_b":
			return _pump_status(pump_b_command, pump_b_flow, pump_b_target)
		"heat_exchanger":
			return "Hot" if main_temperature > 70.0 or coolant_temperature > 55.0 else ("Low flow" if pump_a_flow < 12.0 else "Online")
		"radiator":
			if radiator_command <= 0.0:
				return "Closed"
			if pump_a_flow < 0.1:
				return "No circulation"
			return "Hot" if coolant_temperature > 55.0 else "Online"
		"battery":
			return "Standby reference"
		"main_engine":
			if engine_command <= 0.0:
				return "Idle"
			if not bus_a_closed or engine_power_available < minf(engine_command, pump_b_flow) * ENGINE_KW_PER_THRUST - 0.1:
				return "Power limited"
			if pump_b_flow < engine_command - 0.1:
				return "Cooling limited"
			return "Ramping" if engine_thrust < engine_command - 0.1 else "Online"
	return "Reference"


func equipment_reason(id: String) -> String:
	match id:
		"reactor":
			return "Supplies actual demand up to the output limit. Main-bus base loads and Pump A are served first, then auxiliary loads, then propulsion."
		"main_bus":
			return "Feeds life support 28 kW, avionics 5 kW, hull services 3 kW, shielding 4 kW, Pump A, and the main engine."
		"aux_bus":
			return "Its local limit covers sensors 8 kW, habitat 10 kW, and Pump B. Reducing pump power reduces engine cooling and thrust."
		"pump_a":
			return "Main-bus power drives core cooling and radiator circulation. Each 24 L/s uses 10 kW. Low flow increases temperatures over time."
		"pump_b":
			return "Auxiliary-bus power drives engine cooling. Each 30 L/s uses 12 kW; each 1 L/s permits 1% engine thrust."
		"heat_exchanger":
			return "Pump A moves core heat through this exchanger into the shared coolant. Restoring circulation reverses core heating."
		"radiator":
			return "Opening and Pump A circulation determine heat rejection. Closing it traps waste heat; no permanent damage is simulated."
		"battery":
			return "A schematic reference only. The battery supplies no power and has no charge, discharge, or consumable timer in this model."
		"main_engine":
			if not bus_a_closed:
				return "Main bus is open. Close its breaker to restore engine power."
			if engine_power_available < minf(engine_command, pump_b_flow) * ENGINE_KW_PER_THRUST - 0.1:
				return "Propulsion receives power left after both buses' base loads and pumps. Raise reactor capacity or reduce those loads."
			if pump_b_flow < engine_command - 0.1:
				return "Pump B supplies %.1f L/s, limiting thrust to %.1f%%. Inspect its flow request and auxiliary-bus power limit." % [pump_b_flow, pump_b_flow]
			return "Uses 2.4 kW per 1% thrust. Output follows the request within available reactor power and Pump B cooling capacity."
	return "A supporting ship system."


func system_summary(id: String) -> Dictionary:
	match id:
		"reactor":
			return _summary(equipment_status("reactor"), "%.0f / %.0f kW" % [reactor_output, reactor_limit], "Source output follows actual electrical demand.", "good" if equipment_status("reactor") == "Online" else "warn")
		"power":
			var healthy: bool = equipment_status("main_bus") == "Online" and equipment_status("aux_bus") == "Online"
			return _summary("Online" if healthy else "Limited", "A %.0f · B %.0f kW" % [bus_a_draw, bus_b_draw], "Two buses supply base loads, pumps, and propulsion.", "good" if healthy else "warn")
		"propulsion":
			var state: String = equipment_status("main_engine")
			return _summary(state, "%.1f%% thrust" % engine_thrust, "Thrust follows main-bus power and Pump B cooling capacity.", "good" if state == "Online" else ("neutral" if state == "Idle" else "warn"))
		"cooling":
			var healthy: bool = not _running_hot() and pump_a_flow >= 12.0 and pump_b_flow >= 15.0
			return _summary("Hot" if _running_hot() else ("Online" if healthy else "Low flow"), "%.1f°C coolant" % coolant_temperature, "Two loops move core and engine heat to a shared radiator.", "good" if healthy else "warn")
		"life_support":
			return _load_summary(minf(base_a_power, 28.0), 28.0, "Continuous critical load on the main bus.")
		"shielding":
			return _load_summary(clampf(base_a_power - 36.0, 0.0, 4.0), 4.0, "Shield standby electronics on the main bus.")
		"sensors":
			return _load_summary(minf(base_b_power, 8.0), 8.0, "Sensor electronics have priority on the auxiliary bus.")
		"hull":
			return _load_summary(clampf(base_a_power - 33.0, 0.0, 3.0), 3.0, "Hull service electronics; structural damage is not modeled.")
	return _summary("Reference", "—", "No active model for this department.", "neutral")


func conditions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not bus_a_closed:
		result.append(_condition("Main bus open: life support, Pump A, and the engine have no power.", "power", "main_bus"))
	if not bus_b_closed:
		result.append(_condition("Auxiliary bus open: sensors and Pump B have no power.", "power", "aux_bus"))
	if _requested_power() > reactor_limit + 0.1:
		result.append(_condition("Reactor limit constrains requested electrical loads.", "power", "reactor"))
	if bus_b_closed and BASE_B_DEMAND + pump_b_command * PUMP_B_KW_PER_FLOW > bus_b_limit + 0.1:
		result.append(_condition("Auxiliary bus limit reduces power available to Pump B.", "power", "aux_bus"))
	if pump_a_command > 0.1 and pump_a_flow < pump_a_command - 0.3:
		result.append(_condition("Pump A flow below request: " + equipment_status("pump_a").to_lower() + ".", "cooling", "pump_a"))
	if pump_b_command > 0.1 and pump_b_flow < pump_b_command - 0.3:
		result.append(_condition("Pump B flow below request: " + equipment_status("pump_b").to_lower() + ".", "cooling", "pump_b"))
	if engine_thrust < engine_command - 0.3:
		result.append(_condition("Main engine: " + equipment_status("main_engine").to_lower() + ".", "cooling", "main_engine"))
	if radiator_command < 30.0 and heat_produced > 1.0:
		result.append(_condition("Radiator opening is low; waste heat is accumulating.", "cooling", "radiator"))
	if pump_a_flow < 0.1 and heat_produced > 1.0:
		result.append(_condition("Radiator circulation stopped. Restore Pump A flow to reject waste heat.", "cooling", "pump_a"))
	if main_temperature > 70.0:
		result.append(_condition("Core temperature elevated. Check Pump A and radiator circulation.", "cooling", "pump_a"))
	if engine_temperature > 90.0:
		result.append(_condition("Engine temperature elevated. Check both cooling loops and the radiator.", "cooling", "main_engine"))
	if coolant_temperature > 55.0:
		result.append(_condition("Coolant temperature elevated. Increase radiator opening or reduce heat load.", "cooling", "radiator"))
	return result


func _requested_power() -> float:
	var request: float = BASE_A_DEMAND + pump_a_command * PUMP_A_KW_PER_FLOW if bus_a_closed else 0.0
	var locally_available_flow: float = 0.0
	if bus_b_closed:
		var local_request: float = minf(bus_b_limit, BASE_B_DEMAND + pump_b_command * PUMP_B_KW_PER_FLOW)
		request += local_request
		locally_available_flow = maxf(0.0, local_request - BASE_B_DEMAND) / PUMP_B_KW_PER_FLOW
	if bus_a_closed and bus_b_closed:
		request += minf(engine_command, locally_available_flow) * ENGINE_KW_PER_THRUST
	return request


func _pump_status(command: float, actual: float, target: float) -> String:
	if command <= 0.0:
		return "Idle"
	if target < command - 0.1:
		return "Power limited"
	return "Ramping" if actual < command - 0.1 else "Online"


func _running_hot() -> bool:
	return main_temperature > 70.0 or engine_temperature > 90.0 or coolant_temperature > 55.0


func _summary(state: String, value: String, detail: String, tone: String) -> Dictionary:
	return {"state": state, "value": value, "detail": detail, "tone": tone}


func _load_summary(actual: float, demand: float, detail: String) -> Dictionary:
	var state: String = "Online" if actual >= demand - 0.01 else ("Unpowered" if actual < 0.01 else "Brownout")
	return _summary(state, "%.0f / %.0f kW" % [actual, demand], detail, "good" if state == "Online" else "warn")


func _condition(text: String, system: String, equipment: String) -> Dictionary:
	return {"text": text, "system": system, "equipment": equipment}


func _kw(value: float) -> String:
	return "%.1f kW" % value


func _flow(value: float) -> String:
	return "%.1f L/s" % value


func _temp(value: float) -> String:
	return "%.1f°C" % value


func _record(message: String) -> void:
	events.append(message)
	while events.size() > LOG_LIMIT:
		events.pop_front()
