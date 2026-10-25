extends RefCounted

## Circuit circulation capability, not a pressure or fluid-inventory solver.
var _components: Dictionary
var _incoming: Dictionary = {}
var _bypass


func _init(components: Dictionary, connections: Array, bypass = null) -> void:
	_components = components
	_bypass = bypass
	for edge in connections:
		if String(edge["domain"]) != "coolant":
			continue
		var target: String = String(edge["to_component"])
		if not _incoming.has(target):
			_incoming[target] = []
		_incoming[target].append(edge.duplicate(true))


func flow_for(component_id: String) -> float:
	if _bypass != null and _bypass.has_circuit(component_id):
		return _bypass.flow_for(component_id)
	var contributions: Dictionary = {}
	for edge in _incoming.get(component_id, []):
		var source_id: String = String(edge["from_component"])
		var source = _components[source_id]
		var flow: float = maxf(0.0, float(source.state.get("flow", 0.0)))
		# Multiple links from the same pump expose one circuit capability.
		contributions[source_id] = maxf(float(contributions.get(source_id, 0.0)), flow)
	var total: float = 0.0
	var ids: Array = contributions.keys()
	ids.sort()
	for id in ids:
		total += float(contributions[id])
	return total


func pump_can_run(component_id: String) -> bool:
	return _bypass == null or _bypass.pump_can_run(component_id)


func refresh() -> void:
	for id in _components:
		_components[id].state["coolant_flow"] = flow_for(String(id))
