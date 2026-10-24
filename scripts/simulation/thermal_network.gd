extends RefCounted

## One committed-temperature snapshot supplies every transfer calculation.
## Internal transfers are equal and opposite; only ambient rejection leaves ship.
var _components: Dictionary
var _power
var _ambient: float
var _ids: Array = []
var _incoming: Dictionary = {}
var _outgoing: Dictionary = {}
var _edge_remaining: Dictionary = {}


func _init(components: Dictionary, connections: Array, power, ambient: float) -> void:
	_components = components
	_power = power
	_ambient = ambient
	_ids = components.keys()
	_ids.sort()
	for edge in connections:
		if String(edge["domain"]) != "thermal":
			continue
		var source: String = String(edge["from_component"])
		var target: String = String(edge["to_component"])
		if not _incoming.has(target):
			_incoming[target] = []
		if not _outgoing.has(source):
			_outgoing[source] = []
		_incoming[target].append(edge.duplicate(true))
		_outgoing[source].append(edge.duplicate(true))
	for edges in _outgoing.values():
		edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	for edges in _incoming.values():
		edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))


func solve(delta: float) -> void:
	_edge_remaining.clear()
	for edges in _outgoing.values():
		for edge in edges:
			var capacity: float = float(edge.get("capacity", -1.0))
			if capacity >= 0.0:
				_edge_remaining[String(edge["id"])] = capacity
	var net_heat: Dictionary = {}
	var temperatures: Dictionary = {}
	for id in _ids:
		var part = _components[id]
		part.state["heat_generated"] = 0.0
		part.state["heat_transfer"] = 0.0
		part.state["heat_rejected"] = 0.0
		part.state["passive_heat_loss"] = 0.0
		if part.state.has("temperature") and float(part.config.get("heat_capacity", 0.0)) > 0.0:
			temperatures[id] = float(part.state["temperature"])
			net_heat[id] = 0.0
	for id in _ids:
		var part = _components[id]
		var generated: float = 0.0
		if part.kind() == "reactor":
			var engine_draw: float = 0.0
			for candidate in _ids:
				if _components[candidate].kind() == "engine" and _power.source_for(String(candidate)) == String(id):
					engine_draw += float(_components[candidate].state["power"])
			var output: float = float(part.state["draw"])
			generated = output * float(part.config.get("heat_fraction", 0.08))
			generated += maxf(0.0, output - engine_draw) * float(part.config.get("service_heat_fraction", 0.12))
		elif part.kind() == "engine":
			generated = float(part.state["power"]) * float(part.config.get("heat_fraction", 0.55))
		part.state["heat_generated"] = generated
		if net_heat.has(id):
			var loss: float = (float(temperatures[id]) - _ambient) * float(part.config.get("passive_loss", 0.0))
			part.state["passive_heat_loss"] = loss
			net_heat[id] = generated - loss
	for id in _ids:
		var part = _components[id]
		if part.kind() == "heat_exchanger":
			for inlet in _incoming.get(id, []):
				var source: String = String(inlet["from_component"])
				for outlet in _outgoing.get(id, []):
					var target: String = String(outlet["to_component"])
					if not temperatures.has(source) or not temperatures.has(target):
						continue
					var transfer: float = float(part.config.get("transfer_coefficient", 0.08)) * float(part.state["coolant_flow"]) * (float(temperatures[source]) - float(temperatures[target]))
					transfer = _limit_transfer(transfer, [inlet, outlet])
					net_heat[source] -= transfer
					net_heat[target] += transfer
					part.state["heat_transfer"] += transfer
		elif part.kind() == "engine" and temperatures.has(id):
			for outlet in _outgoing.get(id, []):
				var target: String = String(outlet["to_component"])
				if not temperatures.has(target):
					continue
				var transfer: float = float(part.config.get("transfer_coefficient", 0.0)) * float(part.state["coolant_flow"]) * (float(temperatures[id]) - float(temperatures[target]))
				transfer = _limit_transfer(transfer, [outlet])
				net_heat[id] -= transfer
				net_heat[target] += transfer
				part.state["heat_transfer"] += transfer
		elif part.kind() == "radiator":
			for inlet in _incoming.get(id, []):
				var source: String = String(inlet["from_component"])
				if not temperatures.has(source):
					continue
				var rejection: float = maxf(0.0, float(temperatures[source]) - _ambient) * float(part.config.get("rejection_coefficient", 2.51))
				rejection *= float(part.settings.get("deployment", 0.0)) / 100.0
				rejection *= float(part.state["coolant_flow"]) / float(part.config.get("reference_flow", 24.0))
				rejection = _limit_transfer(rejection, [inlet])
				net_heat[source] -= rejection
				part.state["heat_rejected"] += rejection
	if delta > 0.0:
		for id in temperatures:
			var capacity: float = float(_components[id].config["heat_capacity"])
			_components[id].state["temperature"] = float(temperatures[id]) + float(net_heat[id]) * delta / capacity


func _limit_transfer(amount: float, edges: Array) -> float:
	var permitted: float = absf(amount)
	for edge in edges:
		var id: String = String(edge["id"])
		if _edge_remaining.has(id):
			permitted = minf(permitted, float(_edge_remaining[id]))
	for edge in edges:
		var id: String = String(edge["id"])
		if _edge_remaining.has(id):
			_edge_remaining[id] = maxf(0.0, float(_edge_remaining[id]) - permitted)
	return permitted * signf(amount)
