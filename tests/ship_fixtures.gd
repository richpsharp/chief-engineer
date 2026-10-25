extends RefCounted
## Detached authored resources for tests; never mutate the playable ship.

const Ship = preload("res://scripts/definitions/ship_definition.gd")
const Kestrel = preload("res://ships/kestrel.tres")


static func copy_kestrel():
	var copied = Ship.new()
	copied.id = Kestrel.id
	copied.display_name = Kestrel.display_name
	copied.schema_version = Kestrel.schema_version
	copied.ambient_temperature = Kestrel.ambient_temperature
	copied.maintenance_supplies = Kestrel.maintenance_supplies.duplicate(true)
	for item in Kestrel.components:
		var spec = item.duplicate(true)
		spec.definition = item.definition.duplicate(true)
		copied.components.append(spec)
	for item in Kestrel.assemblies: copied.assemblies.append(item.duplicate(true))
	for item in Kestrel.connections: copied.connections.append(item.duplicate(true))
	copied.views = Kestrel.views.duplicate(true)
	copied.layouts = Kestrel.layouts.duplicate(true)
	return copied
