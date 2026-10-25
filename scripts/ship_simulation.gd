class_name ShipSimulation
extends RefCounted

## Simulation coordinator. Definitions are immutable authoring data; each reset
## builds independent runtime state. Network models contain no installed IDs.
const ComponentRuntime = preload("res://scripts/simulation/component_runtime.gd")
const SimulationCommand = preload("res://scripts/simulation/simulation_command.gd")
const CoolantNetwork = preload("res://scripts/simulation/coolant_network.gd")
const PowerNetwork = preload("res://scripts/simulation/power_network.gd")
const ThermalNetwork = preload("res://scripts/simulation/thermal_network.gd")
const MaintenanceModel = preload("res://scripts/simulation/maintenance_model.gd")
const MAX_INPUT_DELTA: float = 30.0
const FIXED_STEP_SECONDS: float = 0.1
const HISTORY_LIMIT: int = 50

var definition
var components: Dictionary = {}
var paused: bool = false
var elapsed: float = 0.0
var events: Array[String] = []
var validation_errors: Array[String] = []
var command_results: Array[Dictionary] = []
var step_seconds: float:
	get:
		return FIXED_STEP_SECONDS

var _accumulator: float = 0.0
var _step_number: int = 0
var _command_sequence: int = 0
var _commands: Array = []
var _coolant
var _power
var _thermal
var _maintenance


func _init(ship_definition = null) -> void:
	definition = ship_definition if ship_definition != null else load("res://ships/kestrel.tres")
	reset()


func reset() -> void:
	components.clear()
	paused = false
	elapsed = 0.0
	_accumulator = 0.0
	_step_number = 0
	_command_sequence = 0
	_commands.clear()
	events.clear()
	command_results.clear()
	validation_errors.clear()
	_coolant = null
	_power = null
	_thermal = null
	_maintenance = null
	if definition == null:
		validation_errors.append("A ship definition is required.")
	elif not definition.has_method("validate"):
		validation_errors.append("The supplied Resource is not a ship definition.")
	else:
		validation_errors.assign(definition.validate())
	if not validation_errors.is_empty():
		_record("Simulation unavailable: ship definition is invalid.")
		return
	var ordered_specs: Array = definition.components.duplicate()
	ordered_specs.sort_custom(func(a, b) -> bool: return String(a.id) < String(b.id))
	for spec in ordered_specs:
		components[String(spec.id)] = ComponentRuntime.new(spec, float(definition.ambient_temperature))
	var connections: Array = definition.resolved_connections()
	connections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	_coolant = CoolantNetwork.new(components, connections)
	_power = PowerNetwork.new(components, connections, _coolant)
	_thermal = ThermalNetwork.new(components, connections, _power, float(definition.ambient_temperature))
	_maintenance = MaintenanceModel.new(components, connections, definition.maintenance_supplies)
	_power.solve(0.0)
	_thermal.solve(0.0)
	_record("Ship online. Configuration loaded; systems are operating.")


func tick(delta: float) -> void:
	if paused or not validation_errors.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	# Preserve fractional time and process identical 0.1s steps. The 30s input
	# clamp intentionally limits catch-up after a suspended app or huge input.
	_accumulator += minf(delta, MAX_INPUT_DELTA)
	while _accumulator + 0.000000001 >= FIXED_STEP_SECONDS:
		_apply_commands()
		_power.solve(FIXED_STEP_SECONDS)
		for message in _maintenance.advance(FIXED_STEP_SECONDS):
			_record(message)
		# Commit newly worn, failed, or repaired output before the thermal solve.
		if _maintenance.output_changed:
			_power.solve(0.0)
		_thermal.solve(FIXED_STEP_SECONDS)
		# Publish readings at the newly committed temperatures.
		_thermal.solve(0.0)
		_step_number += 1
		elapsed = float(_step_number) * FIXED_STEP_SECONDS
		_accumulator = maxf(0.0, _accumulator - FIXED_STEP_SECONDS)


func toggle_pause() -> void:
	paused = not paused
	_record("Simulation paused. Commands are frozen." if paused else "Simulation resumed.")


func command(target_id: Variant, action: Variant, value: Variant) -> Dictionary:
	_command_sequence += 1
	var reason: String = ""
	if not target_id is String or not action is String:
		reason = "Command target and action must be strings."
	elif paused:
		reason = "Simulation is paused."
	elif not validation_errors.is_empty():
		reason = "Ship definition is invalid."
	elif not components.has(target_id):
		reason = "Unknown component."
	else:
		var descriptor: Dictionary = components[target_id].control(action)
		if descriptor.is_empty():
			reason = "Unsupported control action."
		elif String(descriptor.get("kind", "numeric")) == "toggle":
			if not value is bool:
				reason = "This control requires a boolean value."
		else:
			if not (value is float or value is int):
				reason = "This control requires a numeric value."
			elif not is_finite(float(value)):
				reason = "Control value must be finite."
			elif float(value) < float(descriptor.get("min", 0.0)) or float(value) > float(descriptor.get("max", 0.0)):
				reason = "Control value is outside the permitted range."
	var accepted: bool = reason.is_empty()
	var result: Dictionary = {"accepted": accepted, "reason": "Queued for next simulation step." if accepted else reason, "sequence": _command_sequence}
	if accepted:
		_commands.append(SimulationCommand.new(String(target_id), String(action), value, _command_sequence))
	command_results.append(result.duplicate(true))
	while command_results.size() > HISTORY_LIMIT:
		command_results.pop_front()
	return result


func snapshot() -> Dictionary:
	var state: Dictionary = {}
	var ids: Array = components.keys()
	ids.sort()
	for id in ids:
		state[id] = components[id].detached_snapshot()
	var queued: Array[Dictionary] = []
	for item in _commands:
		queued.append(item.snapshot())
	return {
		"schema_version": int(definition.schema_version) if definition != null and definition.get("schema_version") != null else 1,
		"definition_id": String(definition.id) if definition != null and definition.get("id") != null else "",
		"components": state, "paused": paused, "elapsed": elapsed, "step": _step_number,
		"accumulator": snappedf(_accumulator, 0.000000001),
		"pending_commands": queued,
		"maintenance": _maintenance.snapshot() if _maintenance != null else {},
	}


func maintenance_command(target_id: Variant, action: Variant) -> Dictionary:
	_command_sequence += 1
	var reason: String = ""
	if not target_id is String or not action is String:
		reason = "Command target and action must be strings."
	elif paused:
		reason = "Simulation is paused."
	elif _maintenance == null:
		reason = "Ship definition is invalid."
	else:
		reason = _maintenance.reason_for(target_id, action)
	var accepted: bool = reason.is_empty()
	var result: Dictionary = {"accepted": accepted, "reason": "Queued for next simulation step." if accepted else reason, "sequence": _command_sequence}
	if accepted:
		_commands.append(SimulationCommand.new(target_id, "maintenance." + action, true, _command_sequence))
	command_results.append(result.duplicate(true))
	while command_results.size() > HISTORY_LIMIT:
		command_results.pop_front()
	return result


func maintenance_info(id: String) -> Dictionary:
	return _maintenance.info(id, paused) if _maintenance != null else {}


func reliability_profile(id: String) -> Array[Dictionary]:
	return _maintenance.profile(id) if _maintenance != null else []


func thermal_transfer(connection_id: String) -> float:
	return float(_thermal.transfers.get(connection_id, 0.0)) if _thermal != null else 0.0


func totals() -> Dictionary:
	var output: float = 0.0
	var capacity: float = 0.0
	var generated: float = 0.0
	var rejected: float = 0.0
	for part in components.values():
		if part.kind == "reactor":
			output += float(part.state.get("draw", 0.0))
			capacity += float(part.state.get("capacity", 0.0))
		generated += float(part.state.get("heat_generated", 0.0))
		rejected += float(part.state.get("heat_rejected", 0.0))
	return {"output": output, "capacity": capacity, "spare": maxf(0.0, capacity - output), "heat_generated": generated, "heat_rejected": rejected}


func _apply_commands() -> void:
	for item in _commands:
		if item.action.begins_with("maintenance."):
			_record(_maintenance.apply(item.target_id, item.action.trim_prefix("maintenance.")))
			continue
		var part = components[item.target_id]
		part.settings[item.action] = item.value
		var descriptor: Dictionary = part.control(item.action)
		var label: String = String(descriptor.get("label", item.action))
		var rendered: String = str(item.value)
		if item.value is bool:
			rendered = "closed" if item.value else "open"
		else:
			rendered = "%.1f %s" % [float(item.value), String(descriptor.get("unit", ""))]
		_record("%s: %s set to %s." % [String(part.spec.display_name), label, rendered.strip_edges()])
	_commands.clear()


func _record(message: String) -> void:
	events.append(message)
	while events.size() > HISTORY_LIMIT:
		events.pop_front()
