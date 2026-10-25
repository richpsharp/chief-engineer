extends RefCounted

## Deterministic radial distribution with configured global load priorities.
## Allocations reserve capacity; ramping equipment draws only its actual load.
var _components: Dictionary
var _coolant
var _incoming: Dictionary = {}
var _children: Dictionary = {}
var _paths: Dictionary = {}
var _loads: Array[String] = []
var _ids: Array = []
var _remaining: Dictionary = {}


func _init(components: Dictionary, connections: Array, coolant) -> void:
	_components = components
	_coolant = coolant
	_ids = components.keys()
	_ids.sort()
	for edge in connections:
		if String(edge["domain"]) != "power":
			continue
		var child: String = String(edge["to_component"])
		var parent: String = String(edge["from_component"])
		_incoming[child] = edge.duplicate(true)
		if not _children.has(parent):
			_children[parent] = []
		_children[parent].append(child)
	for id in _ids:
		var part = _components[id]
		if part.kind in ["load", "pump", "engine"]:
			_loads.append(String(id))
		_paths[id] = _path_for(String(id))
	_loads.sort_custom(func(a: String, b: String) -> bool:
		var a_priority: float = float(_components[a].config.get("priority", 100))
		var b_priority: float = float(_components[b].config.get("priority", 100))
		return a_priority < b_priority if a_priority != b_priority else a < b
	)
	for children in _children.values():
		children.sort()


func solve(delta: float) -> void:
	_remaining.clear()
	for id in _ids:
		var part = _components[id]
		for key in ["power", "allocated_power", "requested_power", "draw"]:
			part.state[key] = 0.0
		if part.kind in ["reactor", "bus"]:
			var capacity: float = _capacity(part)
			part.state["capacity"] = capacity
			_remaining["node:" + String(id)] = capacity
	for edge in _incoming.values():
		var capacity: float = float(edge.get("capacity", -1.0))
		if capacity >= 0.0:
			_remaining["edge:" + String(edge["id"])] = capacity
	for id in _loads:
		var part = _components[id]
		var request: float = _request(part, id)
		part.state["requested_power"] = request
		var grant: float = _allocate(id, request)
		part.state["allocated_power"] = grant
		match part.kind:
			"load":
				part.state["power"] = grant
			"pump":
				var coefficient: float = float(part.config.get("kw_per_flow", 1.0))
				var target: float = minf(float(part.settings.get("flow", 0.0)), grant / coefficient)
				part.state["target_flow"] = target
				part.state["flow"] = _respond(float(part.state.get("flow", 0.0)), target, float(part.config.get("response_seconds", 1.5)), delta)
				part.state["power"] = float(part.state["flow"]) * coefficient
			"engine":
				var coefficient: float = float(part.config.get("kw_per_thrust", 2.4))
				var target: float = minf(float(part.settings.get("thrust", 0.0)), grant / coefficient)
				target = minf(target, _cooling_thrust(part, id))
				part.state["target_thrust"] = target
				part.state["thrust"] = _respond(float(part.state.get("thrust", 0.0)), target, float(part.config.get("response_seconds", 2.5)), delta)
				part.state["power"] = float(part.state["thrust"]) * coefficient
	# A lower-priority pump may have lost power after an earlier engine was
	# allocated. Recheck safety against final circulation without reallocating.
	for id in _loads:
		var part = _components[id]
		if part.kind == "engine":
			var limit: float = _cooling_thrust(part, id)
			part.state["target_thrust"] = minf(float(part.state["target_thrust"]), limit)
			part.state["thrust"] = minf(float(part.state["thrust"]), limit)
			part.state["requested_power"] = _request(part, id)
			part.state["allocated_power"] = minf(float(part.state["allocated_power"]), float(part.state["requested_power"]))
			part.state["power"] = float(part.state["thrust"]) * float(part.config.get("kw_per_thrust", 2.4))
	for id in _loads:
		var part = _components[id]
		for ancestor in _paths[id]:
			var upstream = _components[ancestor]
			upstream.state["draw"] += float(part.state["power"])
			upstream.state["power"] += float(part.state["power"])
			upstream.state["allocated_power"] += float(part.state["allocated_power"])
	for id in _ids:
		if _components[id].kind in ["reactor", "bus"]:
			_components[id].state["requested_power"] = _downstream_request(String(id))
	_coolant.refresh()


func source_for(id: String) -> String:
	for ancestor in _paths.get(id, []):
		if _components[ancestor].kind == "reactor":
			return String(ancestor)
	return ""


func _path_for(id: String) -> Array[String]:
	var path: Array[String] = []
	var cursor: String = id
	var visited: Dictionary = {}
	while _incoming.has(cursor) and not visited.has(cursor):
		visited[cursor] = true
		cursor = String(_incoming[cursor]["from_component"])
		path.append(cursor)
	return path


func _capacity(part) -> float:
	if part.kind == "bus" and not bool(part.settings.get("closed", true)):
		return 0.0
	var rating: float = float(part.config.get("rated_power", 0.0))
	return maxf(0.0, minf(rating, float(part.settings.get("limit", rating))))


func _request(part, id: String) -> float:
	match part.kind:
		"load":
			return maxf(0.0, float(part.config.get("rated_power", 0.0)))
		"pump":
			return maxf(0.0, float(part.settings.get("flow", 0.0)) * float(part.config.get("kw_per_flow", 1.0)))
		"engine":
			return maxf(0.0, minf(float(part.settings.get("thrust", 0.0)), _cooling_thrust(part, id)) * float(part.config.get("kw_per_thrust", 2.4)))
	return 0.0


func _cooling_thrust(part, id: String) -> float:
	return _coolant.flow_for(id) / float(part.config.get("flow_per_thrust", 1.0))


func _allocate(id: String, request: float) -> float:
	if source_for(id).is_empty():
		return 0.0
	var keys: Array[String] = []
	for ancestor in _paths[id]:
		keys.append("node:" + String(ancestor))
	var cursor: String = id
	while _incoming.has(cursor):
		var edge: Dictionary = _incoming[cursor]
		if float(edge.get("capacity", -1.0)) >= 0.0:
			keys.append("edge:" + String(edge["id"]))
		cursor = String(edge["from_component"])
	var grant: float = request
	for key in keys:
		grant = minf(grant, float(_remaining.get(key, 0.0)))
	for key in keys:
		_remaining[key] = maxf(0.0, float(_remaining[key]) - grant)
	return grant


func _downstream_request(id: String) -> float:
	var total: float = 0.0
	for child in _children.get(id, []):
		var part = _components[child]
		var request: float = float(part.state.get("requested_power", 0.0))
		if part.kind == "bus":
			request = minf(_downstream_request(String(child)), _capacity(part))
		var edge: Dictionary = _incoming[child]
		var edge_capacity: float = float(edge.get("capacity", -1.0))
		if edge_capacity >= 0.0:
			request = minf(request, edge_capacity)
		total += request
	return total


func _respond(actual: float, target: float, seconds: float, delta: float) -> float:
	actual = minf(actual, target)
	if delta <= 0.0:
		return actual
	if seconds <= 0.0:
		return target
	return lerpf(actual, target, 1.0 - exp(-delta / seconds))
