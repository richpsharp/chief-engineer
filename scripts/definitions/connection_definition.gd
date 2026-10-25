class_name EquipmentConnection
extends Resource

@export var id: String = ""
@export var from_component: String = ""
@export var from_port: String = ""
@export var to_component: String = ""
@export var to_port: String = ""
## Negative one denotes unlimited capacity; finite limits currently apply to power.
@export var capacity: float = -1.0
