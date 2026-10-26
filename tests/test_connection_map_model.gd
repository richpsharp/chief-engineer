extends SceneTree
## Relationship maps retain real topology and choose workspaces by domain.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Presenter = preload("res://scripts/presentation/ship_presenter.gd")
const Fixtures = preload("res://tests/ship_fixtures.gd")
const Tern = preload("res://ships/tern.tres")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_complete_graph()
	_test_workspace_destinations()
	_test_live_connections()
	_test_bypass_connections()
	_test_renamed_and_reordered()
	print("%s: %d connection-map model checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _test_complete_graph() -> void:
	var ship = Simulation.new()
	var presenter = Presenter.new(ship)
	var before: Dictionary = ship.snapshot()
	var power: Array[Dictionary] = presenter.network_connections("power")
	var cooling: Array[Dictionary] = presenter.network_connections("cooling")
	_check(_has(power, "reactor", "main_bus") and _has(power, "main_bus", "main_engine"),
		"The full power graph exposes the reactor-to-engine path through the distribution bus.")
	_check(not _has(power, "reactor", "main_engine"), "The map does not invent a direct reactor-to-engine cable.")
	_check(_has(power, "main_bus", "life_support") and not ship.definition.component("life_support").inspectable,
		"Read-only life-support equipment remains visible at its true electrical endpoint.")
	_check(_has(cooling, "reactor", "heat_exchanger") and _has(cooling, "heat_exchanger", "coolant_reservoir")
		and _has(cooling, "coolant_reservoir", "radiator"), "Cooling shows the complete reactor heat path through shared coolant.")
	_check(_has(cooling, "main_engine", "coolant_reservoir") and not _has(cooling, "heat_exchanger", "radiator"),
		"The full map retains thermal inventory instead of drawing a misleading direct exchanger-to-radiator link.")
	_check(not cooling.any(func(edge): return edge.from_component == "life_support" or edge.to_component == "life_support"),
		"The map does not imply unmodelled life-support cooling.")
	_check(power.all(func(edge): return edge.domain == "power")
		and cooling.all(func(edge): return edge.domain in ["coolant", "thermal"]), "Electrical and cooling graphs stay distinct.")
	_check(presenter.network_connections("unknown").is_empty(), "Unknown domains expose no accidental graph.")
	_check(presenter.network_connections("thermal") == cooling and presenter.network_connections("coolant") == cooling,
		"Heat-transfer and circulation relationships both route to the complete Cooling map.")
	power[0].from_component = "changed_copy"
	_check(not presenter.network_connections("power").any(func(edge): return edge.from_component == "changed_copy")
		and ship.snapshot() == before, "Reading or changing returned map data does not mutate live topology or machinery.")
	var tern = Simulation.new(Tern)
	var tern_power: Array[Dictionary] = Presenter.new(tern).network_connections("power")
	_check(_has(tern_power, "utility_reactor", "distribution_bus") and _has(tern_power, "distribution_bus", "port_bus")
		and _has(tern_power, "port_bus", "port_engine") and _has(tern_power, "distribution_bus", "starboard_bus")
		and _has(tern_power, "starboard_bus", "starboard_engine"), "Tern exposes both complete engine supply branches.")


func _test_workspace_destinations() -> void:
	var presenter = Presenter.new(Simulation.new())
	for id in ["reactor", "main_engine", "pump_a", "pump_b"]:
		var workspaces: Array[Dictionary] = presenter.equipment_workspaces(id)
		_check(workspaces.size() == 2 and workspaces[0].system == "power" and workspaces[1].system == "cooling",
			"Multi-domain equipment has separate electrical and thermal inspection destinations: " + id)
	_check(presenter.workspace_for_domain("main_engine", "power") == "power"
		and presenter.workspace_for_domain("reactor", "thermal") == "cooling",
		"The relationship domain takes precedence over a component's original home workspace.")
	_check(presenter.equipment_workspaces("life_support") == [{"system": "power", "name": "Power", "domain": "power"}],
		"Life support offers only its modelled electrical workspace.")
	_check(presenter.equipment_workspaces("coolant_reservoir") == [{"system": "cooling", "name": "Cooling", "domain": "cooling"}],
		"Read-only coolant inventory can be inspected in Cooling.")
	_check(presenter.equipment_workspaces("battery") == [{"system": "power", "name": "Power", "domain": "power"}],
		"A disconnected standby battery retains an electrical workspace without an invented cable.")
	_check(presenter.equipment_workspaces("missing").is_empty()
		and presenter.workspace_for_domain("missing", "power").is_empty()
		and presenter.workspace_for_domain("reactor", "unknown").is_empty(), "Invalid inspection targets have no navigation destination.")
	_check(presenter.links("main_engine").any(func(link): return link.equipment == "main_bus" and link.domain == "power")
		and presenter.links("main_engine").any(func(link): return link.equipment == "pump_b" and link.domain == "coolant"),
		"Existing dependency links expose their domain without changing their local-selection behavior.")
	var mixed = Fixtures.copy_kestrel()
	mixed.view("power").members.append("pump_a")
	var mixed_ship = Simulation.new(mixed)
	var mixed_presenter = Presenter.new(mixed_ship)
	_check(mixed_ship.validation_errors.is_empty() and mixed_presenter.workspace_domain("power") == "power"
		and mixed_presenter.workspace_for_domain("pump_a", "power") == "power",
		"Adding a pump to electrical workspace membership does not reclassify that workspace as Cooling.")


func _test_live_connections() -> void:
	var ship = Simulation.new()
	var presenter = Presenter.new(ship)
	_check(_edge(presenter.network_connections("power"), "main_bus", "main_engine").active,
		"The electrical path reports active committed supply.")
	ship.command("main_bus", "closed", false)
	_check(_edge(presenter.network_connections("power"), "main_bus", "main_engine").active,
		"Queued breaker input does not alter map activity ahead of the fixed step.")
	ship.tick(0.1)
	_check(not _edge(presenter.network_connections("power"), "main_bus", "main_engine").active
		and _has(presenter.network_connections("power"), "main_bus", "main_engine"),
		"An isolated circuit remains drawn but loses its active-supply indication.")
	ship.reset()
	ship.command("radiator", "deployment", 0.0)
	ship.tick(0.1)
	var stopped: Dictionary = _edge(presenter.network_connections("cooling"), "coolant_reservoir", "radiator")
	_check(not stopped.active and is_zero_approx(stopped.transfer_kw), "A closed radiator shows no heat transfer on its own connection.")
	var warm = Fixtures.copy_kestrel()
	warm.component("coolant_reservoir").initial_state.temperature = 60.0
	var reversed = Presenter.new(Simulation.new(warm))
	var heat: Dictionary = _edge(reversed.network_connections("cooling"), "reactor", "heat_exchanger")
	_check(heat.active and heat.transfer_kw < 0.0, "Signed reverse heat transfer remains available to render the actual direction.")


func _test_bypass_connections() -> void:
	var ship = Simulation.new()
	var presenter = Presenter.new(ship)
	_check(not presenter.network_connections("cooling").any(func(edge): return edge.get("bypass", false)),
		"An uninstalled kit adds no physical connection.")
	for id in ["pump_a_feed", "pump_b_feed"]:
		ship.command(id, "closed", false)
	for id in ["core_loop", "drive_loop"]:
		ship.bypass_command("set_primary", {"circuit_id": id, "open": false})
	ship.tick(0.1)
	_check(ship.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"}).accepted,
		"The test fits a real player bypass through the simulation commands.")
	ship.tick(11.0)
	var fitted: Dictionary = _edge(presenter.network_connections("cooling"), "pump_b", "heat_exchanger")
	_check(fitted.get("bypass", false) and not fitted.active, "A fitted closed bypass appears as an inactive physical connection.")
	ship.bypass_command("set_primary", {"circuit_id": "drive_loop", "open": true})
	ship.command("pump_b_feed", "closed", true)
	ship.command("pump_b", "flow", 40.0)
	ship.bypass_command("set_flow", {"flow": 24.0})
	ship.bypass_command("open")
	ship.tick(30.0)
	var operating: Dictionary = _edge(presenter.network_connections("cooling"), "pump_b", "heat_exchanger")
	_check(operating.active and is_equal_approx(operating.delivered_flow, 24.0),
		"The installed route exposes actual donor flow without rebuilding the presenter.")
	_check(not _edge(presenter.network_connections("cooling"), "pump_a", "heat_exchanger").active,
		"The isolated native inlet stays inactive while the bypass serves the same destination.")
	ship.reset()
	_check(not presenter.network_connections("cooling").any(func(edge): return edge.get("bypass", false)),
		"Reset removes fitted routes from the live map.")


func _test_renamed_and_reordered() -> void:
	var definition = Fixtures.copy_kestrel()
	var mapping: Dictionary = {}
	for spec in definition.components:
		mapping[spec.id] = "custom_" + spec.id
		spec.id = mapping[spec.id]
	for assembly in definition.assemblies:
		for port in assembly.ports.values():
			port.component = mapping.get(port.component, port.component)
	for edge in definition.connections:
		edge.from_component = mapping.get(edge.from_component, edge.from_component)
		edge.to_component = mapping.get(edge.to_component, edge.to_component)
	var layouts: Dictionary = {}
	for view in definition.views:
		var previous: String = view.id
		view.id = "custom_" + previous
		view.members = view.members.map(func(id): return mapping.get(id, id))
		if definition.layouts.has(previous):
			var nodes: Dictionary = {}
			for id in definition.layouts[previous].nodes:
				nodes[mapping.get(id, id)] = definition.layouts[previous].nodes[id]
			layouts[view.id] = {"nodes": nodes}
	definition.layouts = layouts
	for circuit in definition.coolant_circuits:
		circuit.pump = mapping[circuit.pump]
		circuit.service_component = mapping[circuit.service_component]
		circuit.members = circuit.members.map(func(id): return mapping[id])
	definition.components.reverse()
	definition.connections.reverse()
	definition.assemblies.reverse()
	definition.views.reverse()
	var ship = Simulation.new(definition)
	_check(ship.validation_errors.is_empty(), "Renamed and reordered equipment and workspace definitions remain valid.")
	var presenter = Presenter.new(ship)
	_check(presenter.workspace_for_domain("custom_main_engine", "power") == "custom_power"
		and presenter.workspace_for_domain("custom_reactor", "thermal") == "custom_cooling",
		"Domain navigation does not depend on authored equipment IDs, workspace IDs, or declaration order.")
	_check(_has(presenter.network_connections("power"), "custom_main_bus", "custom_main_engine")
		and _has(presenter.network_connections("cooling"), "custom_reactor", "custom_heat_exchanger"),
		"Renamed full maps still expose the actual electrical and thermal paths.")
	var dedicated: Dictionary = definition.view("custom_power").duplicate(true)
	dedicated.id = "drive_electrical"
	dedicated.members = ["custom_main_engine"]
	definition.views.append(dedicated)
	_check(presenter.workspace_for_domain("custom_main_engine", "power") == "drive_electrical",
		"When several domain workspaces exist, explicit equipment membership selects its relevant workspace.")
	definition.views.reverse()
	_check(presenter.workspace_for_domain("custom_main_engine", "power") == "drive_electrical",
		"Reordering domain workspaces does not change the preferred destination.")
	definition.view("custom_cooling").summary_kind = "thrust"
	_check(presenter.workspace_for_domain("custom_reactor", "cooling") == "custom_cooling",
		"Cooling equipment kinds provide a fallback for a workspace with a different summary metric.")


func _has(edges: Array[Dictionary], source: String, destination: String) -> bool:
	return not _edge(edges, source, destination).is_empty()


func _edge(edges: Array[Dictionary], source: String, destination: String) -> Dictionary:
	for edge in edges:
		if edge.from_component == source and edge.to_component == destination:
			return edge
	return {}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
