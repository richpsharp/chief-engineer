extends RefCounted

var target_id: String
var action: String
var value: Variant
var sequence: int


func _init(target: String, requested_action: String, requested_value: Variant, number: int) -> void:
	target_id = target
	action = requested_action
	value = requested_value
	sequence = number


func snapshot() -> Dictionary:
	return {"target_id": target_id, "action": action, "value": value, "sequence": sequence}
