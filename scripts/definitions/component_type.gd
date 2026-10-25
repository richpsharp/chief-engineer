class_name EquipmentType
extends Resource
## Shared immutable equipment specification. Mutable state belongs to an instance.

@export var kind: String = ""
@export var ports: Dictionary = {}
@export var defaults: Dictionary = {}
@export var controls: Array[Dictionary] = []
