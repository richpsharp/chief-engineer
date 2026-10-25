extends RefCounted
## One player-installed paired hose/valve kit. Circuit members share a serial
## circulation allocation; the donor's output is divided, never duplicated.

const WORK_SECONDS: float = 10.0
const EDGE_PREFIX: String = "__bypass:"
var _components: Dictionary
var _connections: Array
var _circuits: Dictionary = {}
var _pump_circuits: Dictionary = {}
var _member_circuits: Dictionary = {}
var _power_parent: Dictionary = {}
var valves: Dictionary = {}
var capacity: float
var kits: int
var installed: Dictionary = {}
var job: Dictionary = {}
var output_changed: bool = false


func _init(components: Dictionary, connections: Array, circuits: Array, kit_capacity: float, kit_count: int) -> void:
	_components = components
	_connections = connections.duplicate(true)
	capacity = kit_capacity
	kits = kit_count
	for circuit in circuits:
		_circuits[circuit.id] = circuit.duplicate(true)
		_pump_circuits[circuit.pump] = circuit.id
		valves[circuit.id] = true
		for member in circuit.members:
			_member_circuits[member] = circuit.id
	for edge in connections:
		if edge.domain == "power":
			_power_parent[edge.to_component] = edge.from_component


func has_circuit(member: String) -> bool:
	return _member_circuits.has(member)


func pump_can_run(id: String) -> bool:
	if not _pump_circuits.has(id):
		return true
	if not job.is_empty() and id in [job.source_id, _circuits[job.circuit_id].pump]:
		return false
	if valves[_pump_circuits[id]]:
		return true
	return not installed.is_empty() and installed.open and installed.source_id == id and installed.requested_flow > 0.0


func pump_info(id: String) -> Dictionary:
	var locked: bool = not job.is_empty() and id in [job.source_id, _circuits[job.circuit_id].pump]
	var circuit_id: String = str(_pump_circuits.get(id, ""))
	return {"connected": _components.has(id) and _components[id].kind == "pump" and pump_can_run(id), "job_locked": locked,
		"circuit_id": circuit_id, "primary_open": bool(valves.get(circuit_id, true))}


func flow_for(member: String) -> float:
	if not _member_circuits.has(member):
		return 0.0
	return circuit_flow(_member_circuits[member])


func circuit_flow(id: String) -> float:
	if not _circuits.has(id):
		return 0.0
	var circuit: Dictionary = _circuits[id]
	if not installed.is_empty() and installed.open and installed.circuit_id == id:
		return delivered_flow()
	if not valves[id]:
		return 0.0
	var flow: float = _pump_flow(circuit.pump)
	if not installed.is_empty() and installed.open and installed.source_id == circuit.pump:
		flow = maxf(0.0, flow - delivered_flow())
	return flow


func delivered_flow() -> float:
	if installed.is_empty() or not installed.open or not job.is_empty():
		return 0.0
	return minf(float(installed.requested_flow), minf(capacity, _pump_flow(installed.source_id)))


func _pump_flow(id: String) -> float:
	var part = _components.get(id)
	if part == null or not part.pump_available() or not pump_can_run(id):
		return 0.0
	return maxf(0.0, float(part.state.get("flow", 0.0)))


func electrical_isolated(id: String) -> bool:
	var cursor: String = id
	var visited: Dictionary = {}
	while _power_parent.has(cursor) and not visited.has(cursor):
		visited[cursor] = true
		cursor = _power_parent[cursor]
		var upstream = _components[cursor]
		if upstream.kind == "bus" and not bool(upstream.settings.get("closed", true)):
			return true
	return false


func maintenance_isolated(id: String) -> bool:
	# An incoming bypass feeds the circuit beyond this closed primary valve;
	# it does not reenergize the primary pump being repaired.
	if not _pump_circuits.has(id):
		return true
	return not valves[_pump_circuits[id]] and not (not installed.is_empty() and installed.open and installed.source_id == id)


func maintenance_reason(id: String) -> String:
	if not job.is_empty():
		return "The maintenance station is occupied by bypass work."
	if not maintenance_isolated(id):
		return "Close this pump's primary coolant valve and any bypass it supplies before working on it."
	return ""


func _endpoint_reason(source_id: String, circuit_id: String) -> String:
	if not _pump_circuits.has(source_id):
		return "Choose a pump with an authored coolant service coupling."
	if not _circuits.has(circuit_id):
		return "Choose an authored destination circuit service coupling."
	if _pump_circuits[source_id] == circuit_id:
		return "A bypass must connect different coolant circuits."
	return ""


func _work_isolation_reason(source_id: String, circuit_id: String) -> String:
	var destination_pump: String = _circuits[circuit_id].pump
	if not electrical_isolated(source_id) or not electrical_isolated(destination_pump):
		return "Open both endpoint pumps' electrical supply breakers before fitting or removing the kit."
	if valves[_pump_circuits[source_id]] or valves[circuit_id]:
		return "Close both endpoint circuits' primary coolant valves before fitting or removing the kit."
	return ""


func reason_for(action: Variant, payload: Variant, station_busy: bool = false) -> String:
	if not action is String or not payload is Dictionary:
		return "Bypass action must be a string and its payload a dictionary."
	if action not in ["install", "remove", "cancel", "open", "close", "set_flow", "set_primary"]:
		return "Unknown bypass action."
	if _circuits.is_empty():
		return "This ship has no authored coolant service circuits."
	var expected: Array = []
	match action:
		"install": expected = ["source_id", "circuit_id"]
		"set_flow": expected = ["flow"]
		"set_primary": expected = ["circuit_id", "open"]
	if payload.size() != expected.size() or not payload.has_all(expected):
		return "Bypass command has missing or unexpected fields."
	if action == "set_primary":
		if not payload.circuit_id is String or not _circuits.has(payload.circuit_id) or not payload.open is bool:
			return "Choose a valid coolant circuit and a boolean valve position."
		if payload.open and not installed.is_empty() and installed.open and installed.circuit_id == payload.circuit_id:
			return "Close the bypass before reconnecting this circuit's primary pump."
		return ""
	if action == "cancel":
		return "No bypass work is in progress." if job.is_empty() else ""
	if not job.is_empty():
		return "Finish or cancel the current bypass work first."
	if action == "install":
		if not payload.source_id is String or not payload.circuit_id is String:
			return "Bypass endpoints must be string identifiers."
		var endpoint_reason: String = _endpoint_reason(payload.source_id, payload.circuit_id)
		if not endpoint_reason.is_empty():
			return endpoint_reason
		if not installed.is_empty():
			return "Remove the installed kit before choosing a different route."
		if kits <= 0:
			return "No bypass kit is available."
		if station_busy:
			return "The maintenance station is occupied by pump work."
		return _work_isolation_reason(payload.source_id, payload.circuit_id)
	if installed.is_empty():
		return "Install a coolant bypass first."
	if action == "set_flow":
		if not (payload.flow is float or payload.flow is int) or not is_finite(float(payload.flow)) or float(payload.flow) < 0.0 or float(payload.flow) > capacity:
			return "Requested bypass flow must be finite and within the kit rating."
		return ""
	if action == "open":
		if installed.open:
			return "The bypass is already open."
		if valves[installed.circuit_id]:
			return "Close the destination circuit's primary coolant valve before opening the bypass."
		if not _components[installed.source_id].pump_available():
			return "The donor pump is failed or locked for maintenance."
		return ""
	if action == "close":
		return "The bypass is already closed." if not installed.open else ""
	if installed.open:
		return "Close the bypass before removing it."
	if station_busy:
		return "The maintenance station is occupied by pump work."
	return _work_isolation_reason(installed.source_id, installed.circuit_id)


func apply(action: String, payload: Dictionary, station_busy: bool = false) -> String:
	var reason: String = reason_for(action, payload, station_busy)
	if not reason.is_empty():
		return "Bypass rejected: " + reason
	match action:
		"set_primary":
			valves[payload.circuit_id] = payload.open
			return "%s: primary coolant valve %s." % [_circuits[payload.circuit_id].name, "open" if payload.open else "closed"]
		"install":
			kits -= 1
			job = {"action": "install", "source_id": payload.source_id, "circuit_id": payload.circuit_id, "remaining": WORK_SECONDS, "duration": WORK_SECONDS}
			return "Bypass: installation started; keep both endpoint pumps and primary coolant valves isolated."
		"remove":
			job = {"action": "remove", "source_id": installed.source_id, "circuit_id": installed.circuit_id, "remaining": WORK_SECONDS, "duration": WORK_SECONDS}
			return "Bypass: removal started; keep both endpoint pumps and primary coolant valves isolated."
		"cancel":
			if job.action == "install":
				kits += 1
			job.clear()
			return "Bypass: work cancelled; the kit remains available or installed and closed."
		"open", "close":
			installed.open = action == "open"
			return "Bypass: valve %s." % action
		"set_flow":
			installed.requested_flow = float(payload.flow)
			return "Bypass: diversion request set to %.1f L/s." % float(payload.flow)
	return ""


func advance(delta: float) -> Array[String]:
	output_changed = false
	if job.is_empty() or not _work_isolation_reason(job.source_id, job.circuit_id).is_empty():
		return []
	job.remaining = maxf(0.0, float(job.remaining) - delta)
	if job.remaining > 0.000001:
		return []
	var message: String
	if job.action == "install":
		installed = {"source_id": job.source_id, "circuit_id": job.circuit_id, "open": false, "requested_flow": capacity}
		message = "Bypass: installation complete. Kit valve is closed; configure the routes before restoring flow."
	else:
		installed.clear()
		kits += 1
		message = "Bypass: removal complete; the reusable kit is back in stores."
	job.clear()
	output_changed = true
	return [message]


func info(source_id: String = "", circuit_id: String = "", paused: bool = false, station_busy: bool = false) -> Dictionary:
	var current: Dictionary = installed if not installed.is_empty() else job
	var source: String = str(current.get("source_id", source_id))
	var target: String = str(current.get("circuit_id", circuit_id))
	var source_flow: float = _pump_flow(source)
	var diverted: float = delivered_flow()
	var native_flow: float = circuit_flow(_pump_circuits[source]) if _pump_circuits.has(source) else 0.0
	var result: Dictionary = {"supported": not _circuits.is_empty(), "capacity": capacity, "kits": kits,
		"installed": not installed.is_empty(), "source_id": source, "circuit_id": target,
		"open": bool(installed.get("open", false)), "requested_flow": float(installed.get("requested_flow", capacity)),
		"delivered_flow": diverted, "source_flow": source_flow, "source_remaining_flow": native_flow,
		"available_remainder_flow": maxf(0.0, source_flow - diverted), "unallocated_flow": maxf(0.0, source_flow - diverted - native_flow),
		"job": str(job.get("action", "")), "job_remaining": float(job.get("remaining", 0.0)), "job_duration": float(job.get("duration", 0.0)),
		"reason": "Choose two service couplings to preview installation.", "actions": {}, "circuits": [], "pumps": []}
	var circuit_ids: Array = _circuits.keys()
	circuit_ids.sort()
	for id in circuit_ids:
		var circuit: Dictionary = _circuits[id].duplicate(true)
		var bypass_flow: float = diverted if result.open and target == id else 0.0
		circuit.merge({"primary_open": valves[id], "delivered_flow": circuit_flow(id),
			"primary_flow": circuit_flow(id) if valves[id] else 0.0, "bypass_flow": bypass_flow,
			"electrically_isolated": electrical_isolated(circuit.pump),
			"source_id": source if result.open and target == id else (circuit.pump if valves[id] else ""), "actions": {}}, true)
		for mode in ["open", "close"]:
			var valve_reason: String = "Simulation is paused." if paused else reason_for("set_primary", {"circuit_id": id, "open": mode == "open"}, station_busy)
			circuit.actions[mode] = {"enabled": valve_reason.is_empty(), "reason": valve_reason}
		result.circuits.append(circuit)
		result.pumps.append({"id": circuit.pump, "name": str(_components[circuit.pump].spec.display_name), "circuit_id": id, "flow": _pump_flow(circuit.pump)})
	for action in ["install", "remove", "cancel", "open", "close"]:
		var payload: Dictionary = {"source_id": source_id, "circuit_id": circuit_id} if action == "install" else {}
		var reason: String = "Simulation is paused." if paused else reason_for(action, payload, station_busy)
		result.actions[action] = {"enabled": reason.is_empty(), "reason": reason}
	if not job.is_empty():
		var isolation_reason: String = _work_isolation_reason(source, target)
		result.reason = ("Work held: " + isolation_reason) if not isolation_reason.is_empty() else "Bypass work in progress. Both endpoint pumps remain locked out."
	elif result.installed:
		if not result.open:
			result.reason = "Installed and closed. Close the destination primary valve before opening this route."
		elif source_flow + 0.001 < result.requested_flow:
			result.reason = "Donor flow is below the diversion request. Check its electrical supply, flow setting, and condition."
		elif not bool(valves.get(str(_pump_circuits.get(source, "")), false)):
			result.reason = "The donor's native circuit is isolated. Only the bypass receives circulation; remaining pump capability is unused."
		else:
			result.reason = "Diverted flow is reserved from the donor; only its remainder reaches the donor's native circuit."
	elif not source_id.is_empty() and not circuit_id.is_empty():
		result.reason = result.actions.install.reason if not result.actions.install.enabled else "Both service couplings are isolated. Ready to install the rated kit."
	return result


func presentation_connections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for original in _connections:
		var edge: Dictionary = original.duplicate(true)
		if edge.domain == "coolant" and _member_circuits.has(edge.to_component):
			var id: String = _member_circuits[edge.to_component]
			var flow: float = circuit_flow(id) if valves[id] else 0.0
			edge.merge({"active": flow > 0.01, "delivered_flow": flow, "circuit_id": id, "bypass": false}, true)
		result.append(edge)
	if not installed.is_empty():
		var circuit: Dictionary = _circuits[installed.circuit_id]
		var source_port: String = ""
		for edge in _connections:
			if edge.domain == "coolant" and edge.from_component == installed.source_id:
				source_port = edge.from_port
				break
		for member in circuit.members:
			var destination_port: String = ""
			for edge in _connections:
				if edge.domain == "coolant" and edge.to_component == member and edge.from_component == circuit.pump:
					destination_port = edge.to_port
					break
			result.append({"id": EDGE_PREFIX + circuit.id + ":" + member, "from_component": installed.source_id, "from_port": source_port,
				"to_component": member, "to_port": destination_port, "domain": "coolant", "capacity": capacity,
				"active": delivered_flow() > 0.01, "delivered_flow": delivered_flow(), "bypass": true, "circuit_id": circuit.id})
	return result


func snapshot() -> Dictionary:
	return {"primary_valves": valves.duplicate(true), "kits": kits, "installed": installed.duplicate(true), "job": job.duplicate(true)}
