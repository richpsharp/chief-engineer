class_name ShipPresenter
extends RefCounted

## Human-readable views over committed component state. No ship-specific IDs.
var ship
var connections: Array[Dictionary] = []


func _init(simulation) -> void:
	ship = simulation
	if ship.validation_errors.is_empty():
		connections = ship.definition.resolved_connections()


func temperature_readings(id: String) -> Array[Dictionary]:
	## A thermal mass reports itself; transfer equipment reports the connected
	## masses it exchanges heat with. Missing measurements stay absent.
	var result: Array[Dictionary] = []
	if not ship.components.has(id):
		return result
	var thermal_fields: Array[String] = ["temperature", "temperature_rate", "net_heat"]
	var observed: Array[String] = []
	if ship.components[id].state.has_all(thermal_fields):
		observed.append(id)
	else:
		for edge in connections:
			if edge.domain != "thermal":
				continue
			var neighbor: String = ""
			if edge.from_component == id:
				neighbor = edge.to_component
			elif edge.to_component == id:
				neighbor = edge.from_component
			if ship.components.has(neighbor) and ship.components[neighbor].state.has_all(thermal_fields) and neighbor not in observed:
				observed.append(neighbor)
	observed.sort()
	for component_id in observed:
		var component = ship.components[component_id]
		var reading: Dictionary = {"component_id": component_id, "temperature": float(component.state.temperature),
			"rate": float(component.state.temperature_rate), "net_heat": float(component.state.net_heat)}
		if component.config.has("warning_temperature"):
			reading["advisory_temperature"] = float(component.config.warning_temperature)
			reading["margin"] = reading.advisory_temperature - reading.temperature
		result.append(reading)
	return result


func readings(id: String) -> Array[Array]:
	if not ship.components.has(id):
		return []
	var runtime = ship.components[id]
	var state: Dictionary = runtime.state
	var settings: Dictionary = runtime.settings
	var result: Array[Array] = []
	var thermal: Array[Dictionary] = temperature_readings(id)
	match runtime.kind:
		"reactor":
			result = [["Output", _kw(_number(id, "draw"))], ["Output limit", _kw(float(settings.get("limit", 0)))], ["Unused capacity", _kw(maxf(0, float(settings.get("limit", 0)) - _number(id, "draw")))], ["Core temperature", _temp(_number(id, "temperature"))], ["Heat generated", _kw(_number(id, "heat_generated"))]]
		"bus":
			result = [["Breaker", "CLOSED" if settings.get("closed", true) else "OPEN"], ["Total draw", _kw(_number(id, "draw"))], ["Local limit", _kw(float(settings.get("limit", runtime.config.get("rated_power", 0))))], ["Requested power", _kw(_number(id, "requested_power"))], ["Allocated supply", _kw(_number(id, "allocated_power"))]]
		"pump":
			result = [["Flow request", _flow(float(settings.get("flow", 0)))], ["Actual flow", _flow(_number(id, "flow"))], ["Power draw", _kw(_number(id, "power"))], ["Available flow", _flow(_number(id, "target_flow"))], ["Electrical supply", _source_names(id, "power")]]
		"engine":
			result = [["Thrust request", _percent(float(settings.get("thrust", 0)))], ["Actual thrust", _percent(_number(id, "thrust"))], ["Power draw", _kw(_number(id, "power"))], ["Allocated power", _kw(_number(id, "allocated_power"))], ["Cooling flow", _flow(_number(id, "coolant_flow"))], ["Temperature", _temp(_number(id, "temperature"))]]
		"heat_exchanger":
			result = [["Heat transfer", _kw(_number(id, "heat_transfer"))], ["Circulation", _flow(_number(id, "coolant_flow"))], ["Heat source", _source_names(id, "thermal")], ["Flow source", _source_names(id, "coolant")]]
		"radiator":
			result = [["Deployment", _percent(float(settings.get("deployment", 0)))], ["Heat rejected", _kw(_number(id, "heat_rejected"))], ["Circulation", _flow(_number(id, "coolant_flow"))], ["Coolant", _temp(thermal[0].temperature) if not thermal.is_empty() else "No connection"], ["Ambient reference", _temp(ship.definition.ambient_temperature)]]
		"coolant":
			result = [["Temperature", _temp(_number(id, "temperature"))]]
		"load":
			result = [["Power supplied", _kw(_number(id, "power"))], ["Power requested", _kw(_number(id, "requested_power"))], ["Electrical supply", _source_names(id, "power")]]
		"battery":
			result = [["State", "Standby reference"], ["Output", _kw(_number(id, "power"))], ["Energy storage", "Not simulated"]]
		_:
			for key in state:
				if state[key] is float or state[key] is int:
					result.append([str(key).capitalize(), "%.1f" % float(state[key])])
	for reading in thermal:
		var label: String = "Temperature trend" if thermal.size() == 1 else _name(reading.component_id)
		var value: String = "%.2f °C/min" % (reading.rate * 60.0)
		if thermal.size() > 1:
			value = _temp(reading.temperature) + " / " + value
		result.append([label, value])
	return result


func equipment_status(id: String) -> String:
	if not ship.components.has(id):
		return "Unavailable"
	var runtime = ship.components[id]
	var settings: Dictionary = runtime.settings
	# Advisories are a presentation policy over numerical readings. They do
	# not change equipment dynamics or collapse the thermal model to a flag.
	for reading in temperature_readings(id):
		if reading.has("margin") and reading.margin < 0.0:
			return "Temperature advisory"
	match runtime.kind:
		"reactor":
			if float(settings.get("limit", 0)) <= 0:
				return "Offline"
			return "Limited" if _number(id, "requested_power") > _number(id, "allocated_power") + 0.1 else "Online"
		"bus":
			if not settings.get("closed", true):
				return "Isolated"
			return "Limited" if _number(id, "requested_power") > _number(id, "allocated_power") + 0.1 else "Online"
		"pump":
			var request: float = float(settings.get("flow", 0))
			if request <= 0:
				return "Idle"
			if _number(id, "target_flow") < request - 0.1:
				return "Power limited"
			return "Ramping" if _number(id, "flow") < request - 0.1 else "Online"
		"engine":
			var request: float = float(settings.get("thrust", 0))
			if request <= 0:
				return "Idle"
			var cooling_limit: float = _number(id, "coolant_flow") / maxf(0.0001, float(runtime.config.get("flow_per_thrust", 1)))
			var power_needed: float = minf(request, cooling_limit) * float(runtime.config.get("kw_per_thrust", 0))
			if _number(id, "allocated_power") < power_needed - 0.1:
				return "Power limited"
			if cooling_limit < request - 0.1:
				return "Cooling limited"
			return "Ramping" if _number(id, "thrust") < request - 0.1 else "Online"
		"radiator":
			if float(settings.get("deployment", 0)) <= 0:
				return "Closed"
			if _number(id, "coolant_flow") < 0.1:
				return "No circulation"
			if float(settings.get("deployment", 0)) < float(runtime.config.get("warning_deployment", 0)) and float(ship.totals().get("heat_generated", 0)) > 1.0:
				return "Limited rejection"
			return "Online"
		"heat_exchanger":
			return "No circulation" if _number(id, "coolant_flow") < 0.1 else "Online"
		"coolant":
			return "Online"
		"load":
			if _number(id, "power") < _number(id, "requested_power") - 0.1:
				return "Unpowered" if _number(id, "power") < 0.1 else "Brownout"
			return "Online"
		"battery":
			return "Standby reference"
	return "Reference"


func equipment_reason(id: String) -> String:
	if not ship.components.has(id):
		return "This equipment is unavailable."
	var status: String = equipment_status(id)
	match status:
		"Power limited", "Limited", "Brownout", "Unpowered":
			var cause: String = _power_cause(id)
			return "Available electrical supply limits output. Inspect " + _name(cause) + "."
		"Cooling limited", "No circulation":
			return "Circulation limits this equipment. Inspect " + _name(_cooling_cause(id)) + "."
		"Isolated":
			return "Its breaker is open. Close it to restore downstream supply."
		"Offline":
			return "Its output limit is zero. Raise the limit to make power available."
		"Closed":
			return "Heat rejection is disabled. Restore deployment to reject waste heat."
		"Limited rejection":
			return "Deployment is below its configured warning level while the ship produces heat. Increase deployment to improve heat rejection."
		"Temperature advisory":
			var explanations: PackedStringArray = []
			for reading in temperature_readings(id):
				if reading.has("margin") and reading.margin < 0.0:
					explanations.append("%s: %.1f °C, changing %.2f °C/min; %.1f °C above its %.1f °C advisory." % [_name(reading.component_id), reading.temperature, reading.rate * 60.0, -reading.margin, reading.advisory_temperature])
			return " ".join(explanations)
		"Ramping":
			return "Output is settling toward the requested setting."
	return str(ship.components[id].spec.description)


func system_summary(view_id: String) -> Dictionary:
	var view: Dictionary = ship.definition.view(view_id)
	var members: Array = view.get("members", [])
	var summary_kind: String = str(view.get("summary_kind", ""))
	var value: String = "—"
	var total: float = 0
	var requested: float = 0
	var engines: int = 0
	var temperatures: Array[float] = []
	var statuses: Array[String] = []
	for id in members:
		if not ship.components.has(id):
			continue
		var kind: String = ship.components[id].kind
		statuses.append(equipment_status(id))
		match summary_kind:
			"reactor":
				if kind == "reactor":
					total += _number(id, "draw")
					requested += float(ship.components[id].settings.get("limit", 0))
			"power":
				if kind in ["reactor", "bus"] and not _has_member_power_upstream(id, members):
					total += _number(id, "draw")
					requested += float(ship.components[id].settings.get("limit", 0))
			"thrust":
				if kind == "engine":
					engines += 1
					total += _number(id, "thrust")
					requested += float(ship.components[id].settings.get("thrust", 0))
			"load":
				if kind == "load":
					total += _number(id, "power")
					requested += _number(id, "requested_power")
			"temperature":
				for reading in temperature_readings(id):
					temperatures.append(reading.temperature)
	match summary_kind:
		"reactor", "load": value = "%.0f / %.0f kW" % [total, requested]
		"power": value = "%.0f kW distributed" % total
		"thrust": value = "%.1f%% mean thrust" % (total / engines) if engines > 1 else "%.1f%% thrust" % total
		"temperature": value = "%.1f°C peak temperature" % temperatures.max() if not temperatures.is_empty() else "No temperature readings"
	var status: String = "Online"
	for candidate in ["Temperature advisory", "Unpowered", "Offline", "Isolated", "Power limited", "Cooling limited", "No circulation", "Limited", "Brownout", "Closed", "Limited rejection", "Ramping"]:
		if candidate in statuses:
			status = candidate
			break
	if not statuses.is_empty() and statuses.all(func(item): return item in ["Idle", "Standby reference"]):
		status = "Idle"
	return {"state": status, "value": value, "detail": str(view.get("detail", "")), "tone": "good" if status == "Online" else ("neutral" if status == "Idle" else "warn")}


func conditions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in ship.components:
		var status: String = equipment_status(id)
		if status in ["Online", "Idle", "Standby reference", "Reference", "Ramping"]:
			continue
		# Report each physical measurement once. Exchangers/radiators display
		# connected temperatures but do not own duplicate temperature alarms.
		if status == "Temperature advisory" and not ship.components[id].state.has("temperature"):
			continue
		var cause: String = id
		if status in ["Power limited", "Limited", "Unpowered", "Brownout"]:
			cause = _power_cause(id)
		elif status in ["Cooling limited", "No circulation"]:
			cause = _cooling_cause(id)
		var target: String = cause if _inspectable(cause) else id
		if not _inspectable(target):
			for link in links(id):
				target = link.equipment
				break
		var workspace: String = ship.definition.workspace_for(target)
		if workspace.is_empty():
			continue
		var condition: Dictionary = {"code": ship.components[id].kind + "." + status.to_lower().replace(" ", "_"), "text": _name(id) + ": " + status.to_lower() + ".", "system": workspace, "equipment": target, "cause_id": cause, "component_id": id}
		if status == "Temperature advisory":
			condition["text"] = equipment_reason(id)
			condition["measurement"] = temperature_readings(id)[0]
		result.append(condition)
	return result


func links(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for outgoing in [false, true]:
		for domain in ["power", "coolant", "thermal"]:
			for neighbor in _visible_neighbors(id, domain, outgoing):
				var target: String = neighbor
				var key: String = target + ":" + domain + ":" + str(outgoing)
				var workspace: String = ship.definition.workspace_for(target)
				if seen.has(key) or workspace.is_empty():
					continue
				seen[key] = true
				var relation: String = "Supplies" if outgoing else "Supply"
				if domain == "coolant":
					relation = "Circulates to" if outgoing else "Circulation"
				elif domain == "thermal":
					relation = "Heat destination" if outgoing else "Heat source"
				result.append({"system": workspace, "equipment": target, "label": relation + ": " + _name(target)})
	return result


func caption(id: String) -> String:
	if not ship.components.has(id):
		return "UNAVAILABLE"
	var settings: Dictionary = ship.components[id].settings
	match ship.components[id].kind:
		"reactor", "bus": return "%.0f / %.0f kW" % [_number(id, "draw"), float(settings.get("limit", 0))]
		"pump": return "%.1f / %.0f L/s" % [_number(id, "flow"), float(settings.get("flow", 0))]
		"engine": return "%.1f / %.0f %% thrust" % [_number(id, "thrust"), float(settings.get("thrust", 0))]
		"radiator": return "%.0f %%  •  %.0f kW" % [float(settings.get("deployment", 0)), _number(id, "heat_rejected")]
		"heat_exchanger": return "%.1f kW transferred" % _number(id, "heat_transfer")
		"battery": return "STANDBY / ISOLATED"
		"coolant": return _temp(_number(id, "temperature"))
	return equipment_status(id)


func assembly_context(id: String) -> String:
	var spec = ship.definition.component(id)
	if spec == null:
		return ""
	var parent_id: String = spec.parent_id
	var names: Array[String] = []
	var visited: Dictionary = {}
	while not parent_id.is_empty() and not visited.has(parent_id):
		visited[parent_id] = true
		var assembly = ship.definition.assembly(parent_id)
		if assembly == null:
			break
		names.push_front(assembly.display_name)
		parent_id = assembly.parent_id
	return " / ".join(names)


func schematic_edges(visible_ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in visible_ids:
		for domain in ["power", "coolant", "thermal"]:
			for target in _visible_neighbors(id, domain, true):
				if target in visible_ids:
					result.append({"from_component": id, "to_component": target, "domain": domain, "active": _edge_active(id, target, domain)})
	return result


func _visible_neighbors(id: String, domain: String, outgoing: bool) -> Array[String]:
	var result: Array[String] = []
	var queue: Array[String] = [id]
	var visited: Dictionary = {id: true}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for edge in connections:
			var start: String = edge.from_component if outgoing else edge.to_component
			if edge.domain != domain or start != current:
				continue
			var target: String = edge.to_component if outgoing else edge.from_component
			if visited.has(target):
				continue
			visited[target] = true
			if _inspectable(target):
				result.append(target)
			else:
				queue.append(target)
	return result


func _power_cause(id: String) -> String:
	var current: String = id
	var visited: Dictionary = {}
	while ship.components.has(current) and not visited.has(current):
		visited[current] = true
		var runtime = ship.components[current]
		if runtime.kind == "bus" and not runtime.settings.get("closed", true):
			return current
		if runtime.kind in ["reactor", "bus"]:
			var capacity: float = float(runtime.settings.get("limit", runtime.config.get("rated_power", INF)))
			if _number(current, "requested_power") > capacity + 0.1 or capacity <= 0:
				return current
		var upstream: String = ""
		for edge in connections:
			if edge.domain == "power" and edge.to_component == current:
				upstream = edge.from_component
				break
		if upstream.is_empty():
			return current
		current = upstream
	return id


func _cooling_cause(id: String) -> String:
	for edge in connections:
		if edge.domain == "coolant" and edge.to_component == id:
			var pump_id: String = edge.from_component
			if equipment_status(pump_id) == "Power limited":
				return _power_cause(pump_id)
			return pump_id
	return id


func _has_member_power_upstream(id: String, members: Array) -> bool:
	var visited: Dictionary = {}
	var current: String = id
	while not visited.has(current):
		visited[current] = true
		var upstream: String = ""
		for edge in connections:
			if edge.domain == "power" and edge.to_component == current:
				upstream = edge.from_component
				break
		if upstream.is_empty():
			return false
		if upstream in members and ship.components[upstream].kind in ["reactor", "bus"]:
			return true
		current = upstream
	return false


func _source_names(id: String, domain: String) -> String:
	var names: Array[String] = []
	for edge in connections:
		if edge.domain == domain and edge.to_component == id:
			names.append(_name(edge.from_component))
	return ", ".join(names) if not names.is_empty() else "No connection"


func _edge_active(from_id: String, to_id: String, domain: String) -> bool:
	match domain:
		"power": return maxf(_number(to_id, "power"), _number(to_id, "draw")) > 0.01
		"coolant": return _number(from_id, "flow") > 0.01
		"thermal": return maxf(_number(from_id, "heat_transfer"), _number(from_id, "heat_generated")) > 0.01
	return false


func _inspectable(id: String) -> bool:
	var spec = ship.definition.component(id)
	return spec != null and spec.inspectable


func _name(id: String) -> String:
	var spec = ship.definition.component(id)
	return str(spec.short_name if not spec.short_name.is_empty() else spec.display_name) if spec != null else id


func _number(id: String, key: String) -> float:
	return float(ship.components[id].state.get(key, 0)) if ship.components.has(id) else 0.0


func _kw(value: float) -> String:
	return "%.1f kW" % value


func _flow(value: float) -> String:
	return "%.1f L/s" % value


func _temp(value: float) -> String:
	return "%.1f °C" % value


func _percent(value: float) -> String:
	return "%.1f %%" % value
