class_name AssemblyDefinition
extends Resource
## Containment is independent of networks and department views.
## An exposed port aliases a descendant port; it contributes no extra load.

@export var id: String = ""
@export var display_name: String = ""
@export var parent_id: String = ""
@export var ports: Dictionary = {}
