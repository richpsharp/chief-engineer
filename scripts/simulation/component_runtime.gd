extends RefCounted

## Mutable state for one installed component. Authored Resources stay untouched.
var spec
var kind: String
var config: Dictionary = {}
var settings: Dictionary = {}
var state: Dictionary = {}
## Derived allocation evidence, refreshed each solve; not saved operating state.
var power_constraint: Dictionary = {}


func _init(component_spec, ambient_temperature: float = 10.0) -> void:
	spec = component_spec
	kind = String(spec.definition.kind)
	config = spec.config().duplicate(true)
	for control in spec.controls():
		settings[String(control["id"])] = control.get("default")
	settings.merge(spec.initial_settings.duplicate(true), true)
	state = spec.initial_state.duplicate(true)
	for key in ["power", "allocated_power", "requested_power", "draw", "heat_generated", "heat_rejected", "heat_transfer", "coolant_flow"]:
		if not state.has(key):
			state[key] = 0.0
	match kind:
		"pump":
			state["flow"] = float(state.get("flow", 0.0))
			state["target_flow"] = 0.0
		"engine":
			state["thrust"] = float(state.get("thrust", 0.0))
			state["target_thrust"] = 0.0
	if kind in ["reactor", "engine", "coolant"] and not state.has("temperature"):
		state["temperature"] = ambient_temperature


func control(action: String) -> Dictionary:
	for item in spec.controls():
		if String(item["id"]) == action:
			return item
	return {}


func detached_snapshot() -> Dictionary:
	return {"settings": settings.duplicate(true), "state": state.duplicate(true)}
