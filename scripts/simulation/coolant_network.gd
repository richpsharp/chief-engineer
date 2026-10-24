extends RefCounted

## Circuit circulation capability, not a pressure or fluid-inventory solver.
var _components: Dictionary
var _incoming: Dictionary = {}


func _init(components: Dictionary, connections: Array) -> void:
	_components = components
	for edge in connections:
		if String(edge["domain"]) != "coolant":
			continue
		var target: String = String(edge["to_component"])
		if not _incoming.has(target):
			_incoming[target] = []
		_incoming[target].append(edge.duplicate(true))


func flow_for(component_id: String) -> float:
	var contributions: Dictionary = {}
	for edge in _incoming.get(component_id, []):
		var source_id: String = String(edge["from_component"])
		var source = _components[source_id]
		var flow: float = maxf(0.0, float(source.state.get("flow", 0.0)))
		var capacity: float = float(edge.get("capacity", -1.0))
		if capacity >= 0.0:
			flow = minf(flow, capacity)
		# Multiple links from the same pump expose one circuit capability.
		contributions[source_id] = maxf(float(contributions.get(source_id, 0.0)), flow)
	var total: float = 0.0
	var ids: Array = contributions.keys()
	ids.sort()
	for id in ids:
		total += float(contributions[id])
	return total


func refresh() -> void:
	for id in _components:
		_components[id].state["coolant_flow"] = flow_for(String(id))
