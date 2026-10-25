class_name ComponentSpec
extends Resource
## Installed identity and initial configuration; labels never determine behavior.

@export var id: String = ""
@export var display_name: String = ""
@export var short_name: String = ""
@export_multiline var description: String = ""
@export var parent_id: String = ""
@export var definition: Resource
@export var parameters: Dictionary = {}
@export var initial_settings: Dictionary = {}
@export var initial_state: Dictionary = {}
@export var inspectable: bool = true


func config() -> Dictionary:
	var result: Dictionary = definition.defaults.duplicate(true) if definition != null else {}
	result.merge(parameters, true)
	return result


func controls() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if definition == null:
		return result
	var parameters_by_key: Dictionary = config()
	for descriptor in definition.controls:
		var control: Dictionary = descriptor.duplicate(true)
		if control.has("max_parameter"):
			control["max"] = parameters_by_key.get(control.max_parameter, control.get("max", 0.0))
		result.append(control)
	return result
