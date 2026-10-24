class_name ShipDefinition
extends Resource
## Authored blueprint, topology validation, and assembly-port resolution.
## Definitions never hold operating state and can be reused by independent ships.

const KINDS = ["reactor", "bus", "pump", "engine", "load", "heat_exchanger", "radiator", "coolant", "battery"]
const DOMAINS = ["power", "coolant", "thermal"]
const SpecResource = preload("res://scripts/definitions/component_spec.gd")
const TypeResource = preload("res://scripts/definitions/component_type.gd")
const AssemblyResource = preload("res://scripts/definitions/assembly_definition.gd")
const ConnectionResource = preload("res://scripts/definitions/connection_definition.gd")

@export var schema_version: int = 1
@export var id: String = ""
@export var display_name: String = ""
@export var ambient_temperature: float = 10.0
@export var components: Array[Resource] = []
@export var assemblies: Array[Resource] = []
@export var connections: Array[Resource] = []
@export var views: Array[Dictionary] = []
@export var layouts: Dictionary = {}


func component(component_id: String) -> Resource:
	for item in components:
		if item is SpecResource and item.id == component_id:
			return item
	return null


func assembly(assembly_id: String) -> Resource:
	for item in assemblies:
		if item is AssemblyResource and item.id == assembly_id:
			return item
	return null


func view(view_id: String) -> Dictionary:
	for item in views:
		if item.get("id", "") == view_id:
			return item
	return {}


func workspace_for(component_id: String) -> String:
	for item in views:
		if item.get("kind", "") == "workspace" and item.get("members", []) is Array and component_id in item.get("members", []):
			return item.id
	return ""


func resolve_port(owner: String, port: String) -> Dictionary:
	var visited: Dictionary = {}
	while not owner.is_empty() and not port.is_empty():
		var key: String = owner + ":" + port
		if visited.has(key):
			return {}
		visited[key] = true
		var leaf = component(owner)
		if leaf != null:
			if not leaf.definition is TypeResource or not leaf.definition.ports.has(port):
				return {}
			var descriptor = leaf.definition.ports[port]
			if not descriptor is Dictionary:
				return {}
			return {"component": owner, "port": port, "domain": descriptor.get("domain", ""), "direction": descriptor.get("direction", "")}
		var parent = assembly(owner)
		if parent == null or not parent.ports.has(port) or not parent.ports[port] is Dictionary:
			return {}
		var alias: Dictionary = parent.ports[port]
		owner = str(alias.get("component", ""))
		port = str(alias.get("port", ""))
	return {}


func resolved_connections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for link in connections:
		if not link is ConnectionResource:
			continue
		var source: Dictionary = resolve_port(link.from_component, link.from_port)
		var target: Dictionary = resolve_port(link.to_component, link.to_port)
		if source.is_empty() or target.is_empty():
			continue
		result.append({"id": link.id, "from_component": source.component, "from_port": source.port,
			"to_component": target.component, "to_port": target.port, "domain": source.domain, "capacity": link.capacity})
	return result


func validate() -> Array[String]:
	var errors: Array[String] = []
	if schema_version != 1:
		errors.append("Unsupported ship schema version: %d." % schema_version)
	if id.is_empty() or not is_finite(ambient_temperature):
		errors.append("Ship identity and finite ambient temperature are required.")
	for item in components:
		if not item is SpecResource:
			errors.append("Components must be ComponentSpec resources.")
		elif not item.definition is TypeResource:
			errors.append("Component requires an EquipmentType resource: " + item.id)
	for item in assemblies:
		if not item is AssemblyResource:
			errors.append("Assemblies must be AssemblyDefinition resources.")
	for item in connections:
		if not item is ConnectionResource:
			errors.append("Connections must be EquipmentConnection resources.")
	if not errors.is_empty():
		return errors
	var owners: Dictionary = {}
	for item in components + assemblies:
		if item == null:
			errors.append("Null component or assembly.")
			continue
		if item.id.is_empty() or owners.has(item.id):
			errors.append("Duplicate or empty component/assembly ID: " + item.id)
		owners[item.id] = item
	for item in components:
		if item != null:
			_validate_component(item, errors)
	for item in components + assemblies:
		if item == null:
			continue
		var seen: Dictionary = {item.id: true}
		var parent: String = item.parent_id
		while not parent.is_empty():
			if seen.has(parent):
				errors.append("Assembly containment cycle at " + item.id)
				break
			seen[parent] = true
			var ancestor = assembly(parent)
			if ancestor == null:
				errors.append("Unknown parent assembly for " + item.id)
				break
			parent = ancestor.parent_id
	for item in assemblies:
		if item == null:
			continue
		for port in item.ports:
			var endpoint: Dictionary = resolve_port(item.id, str(port))
			if endpoint.is_empty() or not _is_descendant(str(endpoint.get("component", "")), item.id):
				errors.append("Invalid assembly port %s:%s; must resolve to a descendant." % [item.id, port])
	var link_ids: Dictionary = {}
	var occupied: Dictionary = {}
	var power_inputs: Dictionary = {}
	var endpoint_pairs: Dictionary = {}
	for link in connections:
		if link == null:
			errors.append("Null connection.")
			continue
		if link.id.is_empty() or link_ids.has(link.id):
			errors.append("Duplicate or empty connection ID: " + link.id)
		link_ids[link.id] = true
		var source: Dictionary = resolve_port(link.from_component, link.from_port)
		var target: Dictionary = resolve_port(link.to_component, link.to_port)
		if source.is_empty() or target.is_empty():
			errors.append("Missing connection endpoint: " + link.id)
			continue
		if source.direction != "out" or target.direction != "in" or source.domain != target.domain:
			errors.append("Incompatible port direction/domain: " + link.id)
			continue
		var pair: String = "%s:%s>%s:%s" % [source.component, source.port, target.component, target.port]
		if endpoint_pairs.has(pair):
			errors.append("Duplicate resolved connection: " + pair)
		endpoint_pairs[pair] = true
		if not is_finite(link.capacity) or (link.capacity < 0.0 and link.capacity != -1.0) or (source.domain != "power" and link.capacity != -1.0):
			errors.append("Invalid connection capacity: " + link.id)
		var input_key: String = target.component + ":" + target.port
		if source.domain == "power":
			if power_inputs.has(target.component):
				errors.append("Multiple power feeds to one component are not supported: " + target.component)
			power_inputs[target.component] = true
		if source.domain in ["power", "coolant"] or component(target.component).definition.kind != "coolant":
			if occupied.has(input_key):
				errors.append("Multiple sources on a single-input port: " + input_key)
		occupied[input_key] = true
		var from_kind: String = component(source.component).definition.kind
		var to_kind: String = component(target.component).definition.kind
		var valid_pair: bool = false
		match source.domain:
			"power": valid_pair = from_kind in ["reactor", "bus"] and to_kind in ["bus", "pump", "engine", "load"]
			"coolant": valid_pair = from_kind == "pump" and to_kind in ["heat_exchanger", "engine", "radiator"]
			"thermal": valid_pair = (from_kind == "reactor" and to_kind == "heat_exchanger") or (from_kind in ["heat_exchanger", "engine"] and to_kind == "coolant") or (from_kind == "coolant" and to_kind == "radiator")
		if not valid_pair:
			errors.append("Unsupported network relationship: " + link.id)
	# Only power needs an acyclic graph across its own connections; combined
	# domains intentionally couple reactor -> pump -> reactor cooling.
	var power_edges: Dictionary = {}
	for link in resolved_connections():
		if link.domain == "power":
			if not power_edges.has(link.from_component):
				power_edges[link.from_component] = []
			power_edges[link.from_component].append(link.to_component)
	var complete: Dictionary = {}
	for owner in power_edges:
		if _has_cycle(str(owner), power_edges, {}, complete):
			errors.append("Electrical cycles/crossfeeds are not supported.")
			break
	_validate_views(errors)
	return errors


func _validate_component(item: Resource, errors: Array[String]) -> void:
	if item.definition == null or item.definition.kind not in KINDS:
		errors.append("Unknown component type: " + item.id)
		return
	for key in item.definition.ports:
		var port = item.definition.ports[key]
		if not port is Dictionary or port.get("domain", "") not in DOMAINS or port.get("direction", "") not in ["in", "out"]:
			errors.append("Invalid port declaration: %s:%s" % [item.id, key])
	var config: Dictionary = item.config()
	var required: Dictionary = {
		"reactor": ["rated_power", "heat_capacity", "passive_loss", "heat_fraction", "service_heat_fraction"],
		"bus": ["rated_power"], "load": ["rated_power", "priority"],
		"pump": ["kw_per_flow", "max_flow", "response_seconds", "priority"],
		"engine": ["kw_per_thrust", "flow_per_thrust", "response_seconds", "heat_fraction", "transfer_coefficient", "heat_capacity", "passive_loss", "priority"],
		"heat_exchanger": ["transfer_coefficient"], "radiator": ["rejection_coefficient", "reference_flow"],
		"coolant": ["heat_capacity", "passive_loss"], "battery": [],
	}
	for key in required[item.definition.kind]:
		if not config.has(key) or not _number(config[key]):
			errors.append("Missing numeric parameter: %s:%s" % [item.id, key])
	for key in config:
		if config[key] is float and not is_finite(config[key]):
			errors.append("Non-finite parameter: %s:%s" % [item.id, key])
	for key in ["heat_capacity", "kw_per_flow", "kw_per_thrust", "flow_per_thrust", "response_seconds", "reference_flow"]:
		if config.has(key) and (not _number(config[key]) or float(config[key]) <= 0.0):
			errors.append("Parameter must be positive: %s:%s" % [item.id, key])
	for key in ["rated_power", "max_flow", "passive_loss", "heat_fraction", "service_heat_fraction", "transfer_coefficient", "rejection_coefficient"]:
		if config.has(key) and (not _number(config[key]) or float(config[key]) < 0.0):
			errors.append("Parameter must be non-negative: %s:%s" % [item.id, key])
	var control_ids: Dictionary = {}
	var supported_controls: Dictionary = {
		"reactor": ["limit"], "bus": ["limit", "closed"], "pump": ["flow"],
		"engine": ["thrust"], "radiator": ["deployment"], "load": [],
		"heat_exchanger": [], "coolant": [], "battery": [],
	}
	for control in item.controls():
		var key: String = str(control.get("id", ""))
		if key.is_empty() or control_ids.has(key):
			errors.append("Duplicate or empty control on " + item.id)
		control_ids[key] = true
		if key not in supported_controls[item.definition.kind]:
			errors.append("Unsupported behavior control: %s:%s" % [item.id, key])
		var control_kind: String = str(control.get("kind", "number"))
		if (key == "closed" and control_kind != "toggle") or (key != "closed" and control_kind not in ["number", "numeric"]):
			errors.append("Control value kind does not match behavior: %s:%s" % [item.id, key])
		var initial = item.initial_settings.get(key, control.get("default"))
		if control.get("kind", "number") == "toggle":
			if not initial is bool:
				errors.append("Boolean control requires boolean setting: " + item.id)
		elif not _number(initial) or not _number(control.get("min")) or not _number(control.get("max")) or float(control.min) > float(control.max) or float(initial) < float(control.min) or float(initial) > float(control.max):
			errors.append("Invalid control range/setting: %s:%s" % [item.id, key])
	for key in item.initial_settings:
		if not control_ids.has(key):
			errors.append("Unknown initial setting: %s:%s" % [item.id, key])
	for key in item.initial_state:
		if not _number(item.initial_state[key]):
			errors.append("Initial state must contain finite numeric readings: %s:%s" % [item.id, key])
		elif key in ["flow", "thrust"] and float(item.initial_state[key]) < 0.0:
			errors.append("Initial output cannot be negative: %s:%s" % [item.id, key])
	if item.definition.kind in ["reactor", "engine", "coolant"] and not _number(item.initial_state.get("temperature")):
		errors.append("Thermal component requires an initial temperature: " + item.id)


func _validate_views(errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for item in views:
		var view_id: String = str(item.get("id", ""))
		if view_id.is_empty() or seen.has(view_id) or item.get("kind", "") not in ["workspace", "summary"]:
			errors.append("Invalid or duplicate department view: " + view_id)
		if str(item.get("name", "")).is_empty() or item.get("summary_kind", "") not in ["power", "temperature", "thrust", "load", "reactor"]:
			errors.append("View requires a name and supported summary kind: " + view_id)
		seen[view_id] = true
		if not item.get("members", []) is Array:
			errors.append("View members must be an array: " + view_id)
			continue
		for member in item.get("members", []):
			if component(str(member)) == null:
				errors.append("Unknown view member: " + str(member))
	for view_id in layouts:
		if not seen.has(view_id) or not layouts[view_id] is Dictionary:
			errors.append("Unknown/invalid layout: " + str(view_id))
			continue
		if not layouts[view_id].get("nodes", {}) is Dictionary:
			errors.append("Layout nodes must be a dictionary: " + str(view_id))
			continue
		for member in layouts[view_id].get("nodes", {}):
			if component(str(member)) == null or not layouts[view_id].nodes[member] is Rect2:
				errors.append("Invalid layout node: " + str(member))
	for item in components:
		if item.inspectable and workspace_for(item.id).is_empty():
			errors.append("Inspectable equipment needs a workspace: " + item.id)


func _is_descendant(child: String, parent: String) -> bool:
	var item = component(child)
	var visited: Dictionary = {}
	while item != null and not visited.has(item.id):
		visited[item.id] = true
		if item.parent_id == parent:
			return true
		item = assembly(item.parent_id)
	return false


func _has_cycle(owner: String, edges: Dictionary, active: Dictionary, complete: Dictionary) -> bool:
	if active.has(owner):
		return true
	if complete.has(owner):
		return false
	active[owner] = true
	for child in edges.get(owner, []):
		if _has_cycle(str(child), edges, active, complete):
			return true
	active.erase(owner)
	complete[owner] = true
	return false


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
