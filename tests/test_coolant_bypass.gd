extends SceneTree
## Player-installed circulation routes conserve donor flow and respect work isolation.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Ship = preload("res://scripts/definitions/ship_definition.gd")
const Kestrel = preload("res://ships/kestrel.tres")
const Tern = preload("res://ships/tern.tres")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_baseline_and_local_isolation()
	_test_install_repair_restore_remove()
	_test_donor_limits_and_reverse_route()
	_test_invalid_commands_and_isolation()
	_test_queued_route_interlocks()
	_test_work_interruption_and_station_races()
	_test_pause_reset_and_detached_state()
	_test_definition_validation()
	_test_ordering_and_renaming()
	print("%s: %d coolant-bypass checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _test_baseline_and_local_isolation() -> void:
	var ship = Simulation.new(Kestrel)
	_check(ship.validation_errors.is_empty() and ship.bypass_info().supported,
		"Kestrel authors compatible service circuits and a usable bypass kit.")
	_check(not ship.bypass_info().installed and ship.bypass_info().kits == 1,
		"The bypass begins in inventory, not preinstalled as a scripted solution.")
	_check(_near(ship.totals().output, 152.0) and _near(_s(ship, "main_engine", "thrust"), 30.0)
		and _near(_s(ship, "heat_exchanger", "coolant_flow"), 24.0)
		and _near(_s(ship, "radiator", "coolant_flow"), 24.0), "Explicit circuits preserve Kestrel's healthy cruise and serial core circulation.")
	ship.command("pump_a_feed", "closed", false)
	ship.tick(0.1)
	_check(ship.components.main_bus.settings.closed and _near(_s(ship, "life_support", "power"), 28.0)
		and _near(_s(ship, "main_engine", "thrust"), 30.0) and _near(_s(ship, "pump_a", "flow"), 0.0),
		"Pump A's local breaker isolates the pump without cutting the engine or essential services.")
	ship.command("pump_a_feed", "closed", true)
	ship.bypass_command("set_primary", {"circuit_id": "core_loop", "open": false})
	ship.tick(0.1)
	_check(_near(_s(ship, "pump_a", "flow"), 0.0) and _near(_s(ship, "pump_a", "power"), 0.0)
		and not ship.maintenance_info("pump_a").isolated,
		"A closed coolant outlet stops pump demand but does not count as electrical isolation.")
	var tern = Simulation.new(Tern)
	_advance(tern, 30.0)
	_check(not tern.bypass_info().supported and _near(tern.totals().output, 144.0)
		and _near(_s(tern, "port_engine", "thrust"), 20.0), "A ship without bypass ports retains its existing circulation behavior.")


func _test_install_repair_restore_remove() -> void:
	var ship = Simulation.new(Kestrel)
	ship.maintenance_command("pump_a", "simulate_wear")
	ship.tick(0.1)
	_isolate_endpoints(ship)
	var before: Dictionary = ship.bypass_info()
	_check(ship.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"}).accepted,
		"The player can choose pump B and the core service port for installation.")
	_check(ship.bypass_info().job.is_empty() and ship.bypass_info().kits == before.kits,
		"Installation waits for the fixed-step boundary before reserving the kit.")
	ship.tick(0.1)
	_check(ship.bypass_info().job == "install" and ship.bypass_info().kits == 0,
		"Starting installation reserves a kit and exposes a timed job.")
	_advance(ship, 11.0)
	var installed: Dictionary = ship.bypass_info()
	_check(installed.installed and not installed.open and installed.job.is_empty()
		and installed.source_id == "pump_b" and installed.circuit_id == "core_loop",
		"Installation creates the chosen closed route while retaining its endpoints.")
	_start_backup(ship)
	_assert_backup_balance(ship)
	_check(ship.maintenance_info("pump_a").isolated and ship.maintenance_command("pump_a", "replace").accepted,
		"Incoming bypass circulation does not prevent repairing the isolated native pump.")
	var lifetime: float = ship.maintenance_info("pump_a").running_hours
	ship.tick(0.1)
	_advance(ship, 31.0)
	_check(ship.maintenance_info("pump_a").job.is_empty() and _near(ship.maintenance_info("pump_a").efficiency, 1.0)
		and _near(ship.maintenance_info("pump_a").running_hours, lifetime),
		"Pump A is repaired without erasing its operating history.")
	_check(_near(_s(ship, "main_engine", "thrust"), 16.0) and _near(_s(ship, "life_support", "power"), 28.0),
		"Propulsion and essential services remain available through the repair.")
	_check(not ship.bypass_command("set_primary", {"circuit_id": "core_loop", "open": true}).accepted,
		"The native path cannot be reopened while the conflicting bypass remains open.")
	ship.bypass_command("close")
	ship.tick(0.1)
	ship.bypass_command("set_primary", {"circuit_id": "core_loop", "open": true})
	ship.command("pump_a_feed", "closed", true)
	ship.command("pump_b", "flow", 30.0)
	_advance(ship, 60.0)
	_check(_near(_s(ship, "main_engine", "thrust"), 30.0) and _near(ship.totals().output, 152.0)
		and _near(_s(ship, "heat_exchanger", "coolant_flow"), 24.0),
		"Restoring the native route recovers full cruise without needing a ship reset.")
	_check(not ship.bypass_command("remove").accepted,
		"Closing the bypass alone does not make energized hose removal safe.")
	_isolate_endpoints(ship)
	_check(ship.bypass_command("remove").accepted, "Both isolated service points permit removal.")
	_advance(ship, 11.0)
	_check(not ship.bypass_info().installed and ship.bypass_info().kits == 1,
		"Completed removal returns the reusable kit to inventory.")
	_check(ship.bypass_command("install", {"source_id": "pump_a", "circuit_id": "drive_loop"}).accepted,
		"The recovered kit can be installed in the opposite compatible arrangement.")


func _test_donor_limits_and_reverse_route() -> void:
	var ship = _installed_ship()
	_start_backup(ship)
	ship.bypass_command("set_primary", {"circuit_id": "drive_loop", "open": false})
	ship.tick(0.1)
	var closed_native: Dictionary = ship.bypass_info()
	_check(_near(closed_native.delivered_flow, 24.0) and _near(closed_native.source_remaining_flow, 0.0)
		and _near(closed_native.unallocated_flow, 16.0) and _near(_s(ship, "main_engine", "coolant_flow"), 0.0),
		"Closing the donor's native valve reports zero native delivery and 16 L/s of unused capability.")
	ship.bypass_command("set_primary", {"circuit_id": "drive_loop", "open": true})
	ship.tick(0.1)
	_check(_near(ship.bypass_info().source_remaining_flow, 16.0) and _near(ship.bypass_info().unallocated_flow, 0.0)
		and _near(_s(ship, "main_engine", "coolant_flow"), 16.0),
		"Reopening the donor's native valve restores its real 16 L/s delivery.")
	ship.bypass_command("set_flow", {"flow": 12.0})
	_advance(ship, 20.0)
	_check(_near(_s(ship, "heat_exchanger", "coolant_flow"), 12.0)
		and _near(_s(ship, "radiator", "coolant_flow"), 12.0)
		and _near(_s(ship, "main_engine", "coolant_flow"), 28.0),
		"The player can trade core circulation for additional native engine circulation.")
	ship.bypass_command("set_flow", {"flow": 24.0})
	ship.command("aux_bus", "limit", 30.0)
	_advance(ship, 20.0)
	_check(_near(_s(ship, "pump_b", "flow"), 30.0) and _near(ship.bypass_info().delivered_flow, 24.0)
		and _near(_s(ship, "main_engine", "coolant_flow"), 6.0) and _power_balanced(ship),
		"An auxiliary power shortage reduces the donor budget instead of creating free bypass flow.")
	ship.command("aux_bus", "limit", 40.0)
	ship.maintenance_command("pump_b", "simulate_wear")
	_advance(ship, 20.0)
	_check(ship.bypass_info().source_flow < 40.0 and _flow_balanced(ship)
		and _power_balanced(ship), "Donor degradation reduces total available cooling while preserving flow and power accounting.")
	ship.command("pump_b", "flow", 20.0)
	_advance(ship, 20.0)
	_check(ship.bypass_info().delivered_flow < ship.bypass_info().requested_flow
		and _near(ship.bypass_info().delivered_flow, _s(ship, "pump_b", "flow"))
		and _near(_s(ship, "main_engine", "coolant_flow"), 0.0),
		"An undersized donor exposes a shortfall and cannot supply its native circuit with the same flow twice.")
	_check(not ship.bypass_command("set_flow", {"flow": ship.bypass_info().capacity + 1.0}).accepted,
		"The installed kit cannot be commanded beyond its authored rating.")
	var reverse = _installed_ship("pump_a", "drive_loop")
	reverse.bypass_command("set_primary", {"circuit_id": "core_loop", "open": true})
	reverse.command("pump_a_feed", "closed", true)
	reverse.command("pump_a", "flow", 36.0)
	reverse.bypass_command("set_flow", {"flow": 12.0})
	reverse.bypass_command("open")
	_advance(reverse, 30.0)
	_check(_near(_s(reverse, "main_engine", "coolant_flow"), 12.0)
		and _near(_s(reverse, "heat_exchanger", "coolant_flow"), 24.0)
		and _near(_s(reverse, "radiator", "coolant_flow"), 24.0)
		and _power_balanced(reverse), "The same equipment model supports pump A donating to the drive circuit.")


func _test_invalid_commands_and_isolation() -> void:
	var ship = Simulation.new(Kestrel)
	for request in [["install", {}], ["install", {"source_id": "pump_a", "circuit_id": "core_loop"}],
		["install", {"source_id": "reactor", "circuit_id": "core_loop"}],
		["install", {"source_id": "pump_b", "circuit_id": "missing"}], ["missing", {}],
		["set_primary", {"circuit_id": "core_loop", "open": 1}], ["set_primary", {"circuit_id": "missing", "open": false}],
		["set_flow", {"flow": NAN}], ["set_flow", {"flow": -1}], ["open", []], [1, {}]]:
		_check(not ship.bypass_command(request[0], request[1]).accepted, "Malformed, incompatible, or unsafe bypass commands are rejected.")
	ship.command("pump_a", "flow", 0.0)
	ship.command("pump_b", "flow", 0.0)
	ship.bypass_command("set_primary", {"circuit_id": "core_loop", "open": false})
	ship.bypass_command("set_primary", {"circuit_id": "drive_loop", "open": false})
	ship.tick(0.1)
	_check(not ship.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"}).accepted,
		"Zero requested flow does not substitute for electrical isolation at either service point.")
	ship.command("pump_a_feed", "closed", false)
	ship.tick(0.1)
	_check(not ship.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"}).accepted,
		"Isolating only the receiving pump leaves installation unsafe at the donor.")
	ship.command("pump_b_feed", "closed", false)
	ship.bypass_command("set_primary", {"circuit_id": "core_loop", "open": true})
	ship.tick(0.1)
	_check(not ship.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"}).accepted,
		"Electrical isolation also requires isolation of the destination coolant service connection.")
	_check(not ship.maintenance_command("pump_a", "replace").accepted,
		"A local electrical breaker alone cannot authorize repair while its coolant connection is open.")
	var unsupported = Simulation.new(Tern)
	_check(not unsupported.bypass_command("install", {"source_id": "port_pump", "circuit_id": "core_loop"}).accepted,
		"A ship without authored couplings cannot acquire an invented bypass route.")


func _test_queued_route_interlocks() -> void:
	var first = _installed_ship()
	first.bypass_command("open")
	first.bypass_command("set_primary", {"circuit_id": "core_loop", "open": true})
	first.tick(0.1)
	_check(first.bypass_info().open and not _circuit(first, "core_loop").primary_open,
		"Opening the bypass first makes a later queued native-valve opening fail safely.")
	var second = _installed_ship()
	second.bypass_command("set_primary", {"circuit_id": "core_loop", "open": true})
	second.bypass_command("open")
	second.tick(0.1)
	_check(not second.bypass_info().open and _circuit(second, "core_loop").primary_open,
		"Opening the native valve first prevents a conflicting queued bypass opening.")
	_start_backup(first)
	first.command("pump_b_feed", "closed", false)
	first.bypass_command("set_primary", {"circuit_id": "drive_loop", "open": false})
	first.tick(0.1)
	_check(not first.maintenance_command("pump_b", "replace").accepted,
		"An open bypass remains a coolant connection that must be isolated before donor-pump repair.")
	first.bypass_command("close")
	first.tick(0.1)
	_check(first.maintenance_command("pump_b", "replace").accepted,
		"Closing both donor coolant routes and its breaker allows maintenance.")


func _test_work_interruption_and_station_races() -> void:
	var ship = Simulation.new(Kestrel)
	ship.maintenance_command("pump_a", "simulate_wear")
	ship.tick(0.1)
	_isolate_endpoints(ship)
	ship.command("pump_b_feed", "closed", true)
	_check(ship.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"}).accepted,
		"An installation request can queue against an isolated state.")
	ship.tick(0.1)
	_check(ship.bypass_info().job.is_empty() and ship.bypass_info().kits == 1,
		"Earlier queued reconnection invalidates installation without reserving a kit.")
	ship.command("pump_b_feed", "closed", false)
	ship.tick(0.1)
	ship.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"})
	ship.maintenance_command("pump_a", "replace")
	ship.tick(0.1)
	_check(ship.bypass_info().job == "install" and ship.maintenance_info("pump_a").job.is_empty()
		and ship.maintenance_info("pump_a").spares == 2,
		"A queued installation and repair cannot occupy the same work station or spend both supplies.")
	ship.command("pump_b_feed", "closed", true)
	ship.bypass_command("set_primary", {"circuit_id": "drive_loop", "open": true})
	ship.tick(0.1)
	var remaining: float = ship.bypass_info().job_remaining
	_advance(ship, 20.0)
	_check(_near(ship.bypass_info().job_remaining, remaining)
		and _near(_s(ship, "pump_b", "flow"), 0.0) and not ship.bypass_info().installed,
		"Reconnecting an endpoint holds installation and keeps machinery locked out.")
	_isolate_endpoints(ship)
	_advance(ship, 11.0)
	_check(ship.bypass_info().installed and ship.bypass_info().job.is_empty(), "Restored endpoint isolation lets the held installation finish.")
	ship.bypass_command("remove")
	ship.tick(0.1)
	ship.bypass_command("cancel")
	ship.tick(0.1)
	_check(ship.bypass_info().installed and not ship.bypass_info().open and ship.bypass_info().kits == 0,
		"Cancelling removal keeps the installed closed kit instead of duplicating inventory.")
	ship.bypass_command("remove")
	ship.tick(0.1)
	ship.command("pump_a_feed", "closed", true)
	ship.tick(0.1)
	remaining = ship.bypass_info().job_remaining
	_advance(ship, 20.0)
	_check(ship.bypass_info().installed and _near(ship.bypass_info().job_remaining, remaining)
		and ship.bypass_info().kits == 0, "Unsafe removal pauses without prematurely recovering the installed kit.")
	var cancelled = Simulation.new(Kestrel)
	_isolate_endpoints(cancelled)
	cancelled.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"})
	cancelled.tick(0.1)
	cancelled.bypass_command("cancel")
	cancelled.tick(0.1)
	_check(not cancelled.bypass_info().installed and cancelled.bypass_info().kits == 1,
		"Cancelling unfinished installation recovers exactly its reserved reusable kit.")
	var repair_first = Simulation.new(Kestrel)
	repair_first.maintenance_command("pump_a", "simulate_wear")
	repair_first.tick(0.1)
	_isolate_endpoints(repair_first)
	repair_first.maintenance_command("pump_a", "replace")
	repair_first.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"})
	repair_first.tick(0.1)
	_check(repair_first.maintenance_info("pump_a").job == "replace"
		and repair_first.bypass_info().job.is_empty() and repair_first.bypass_info().kits == 1,
		"The shared work-slot interlock also holds when a repair was queued first.")


func _test_pause_reset_and_detached_state() -> void:
	var ship = _installed_ship()
	var other = Simulation.new(Kestrel)
	var other_before: Dictionary = other.snapshot()
	_start_backup(ship)
	ship.toggle_pause()
	var paused: Dictionary = ship.snapshot()
	ship.tick(30.0)
	_check(ship.snapshot() == paused and not ship.bypass_command("close").accepted,
		"Pause freezes route commands, circulation state, and operating history.")
	_check(other.snapshot() == other_before and not other.bypass_info().installed,
		"A player-installed route belongs only to its ship runtime.")
	var observation: Dictionary = ship.bypass_info()
	observation.circuits.clear()
	observation.actions.clear()
	_check(not ship.bypass_info().circuits.is_empty() and not ship.bypass_info().actions.is_empty(),
		"UI observations cannot mutate circuit definitions or available actions.")
	var snapshot: Dictionary = ship.snapshot()
	if snapshot.has("bypass"):
		snapshot.bypass.clear()
	_check(ship.bypass_info().installed, "Detached snapshots do not remove the live installation.")
	ship.reset()
	_check(ship.snapshot() == other_before and ship.bypass_info().kits == 1,
		"Reset discards the player's installation and reloads native valves and inventory.")
	_isolate_endpoints(ship)
	ship.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"})
	ship.tick(0.1)
	ship.toggle_pause()
	paused = ship.snapshot()
	ship.tick(30.0)
	_check(ship.snapshot() == paused and not ship.bypass_command("cancel").accepted,
		"Pause also freezes an unfinished installation and its reserved kit.")


func _test_definition_validation() -> void:
	var invalid_definition = _copy_kestrel()
	invalid_definition.schema_version = -1
	var invalid = Simulation.new(invalid_definition)
	_check(not invalid.validation_errors.is_empty() and invalid.presentation_connections().is_empty()
		and invalid.coolant_connections().is_empty() and invalid.bypass_info().is_empty()
		and not invalid.coolant_pump_info("pump_a").connected,
		"Invalid runtimes expose empty, safely typed routing observations without a partial graph.")
	for capacity in [0.0, -1.0, NAN, INF]:
		var definition = _copy_kestrel()
		definition.bypass_capacity = capacity
		_check(not definition.validate().is_empty(), "Bypass capacity must be finite and positive.")
	var missing = _copy_kestrel()
	missing.coolant_circuits[0].pump = "missing"
	_check(not missing.validate().is_empty(), "A service circuit requires an installed pump.")
	var duplicate = _copy_kestrel()
	duplicate.coolant_circuits[1].id = duplicate.coolant_circuits[0].id
	_check(not duplicate.validate().is_empty(), "Service circuit IDs must be unique.")
	var reused = _copy_kestrel()
	reused.coolant_circuits[1].pump = "pump_a"
	_check(not reused.validate().is_empty(), "A native pump cannot secretly provide a duplicated circuit budget.")
	var wrong_member = _copy_kestrel()
	wrong_member.coolant_circuits[0].members = ["main_engine"]
	_check(not wrong_member.validate().is_empty(), "Circuit members must match their authored primary circulation.")
	var partial = _copy_kestrel()
	partial.coolant_circuits[0].members = ["heat_exchanger"]
	_check(not partial.validate().is_empty(), "A primary pump's ungrouped legacy outlet cannot escape the finite circuit budget.")
	var wrong_port = _copy_kestrel()
	wrong_port.coolant_circuits[0].service_component = "reactor"
	_check(not wrong_port.validate().is_empty(), "The receiving service point belongs to its compatible circuit.")
	var duplicate_member = _copy_kestrel()
	duplicate_member.coolant_circuits[0].members.append("heat_exchanger")
	_check(not duplicate_member.validate().is_empty(), "Duplicate serial members cannot be authored as additional flow consumers.")
	for demand in [0.0, -1.0, NAN, INF]:
		var definition = _copy_kestrel()
		definition.coolant_circuits[0].reference_flow = demand
		_check(not definition.validate().is_empty(), "Circuit reference demand must be finite and positive.")
	var no_kit = _copy_kestrel()
	no_kit.bypass_kits = 0
	var no_supplies = Simulation.new(no_kit)
	_isolate_endpoints(no_supplies)
	_check(not no_supplies.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"}).accepted,
		"Compatible isolated ports cannot install a bypass without a physical kit.")


func _test_ordering_and_renaming() -> void:
	var ordered = Simulation.new(Kestrel)
	var reordered = _copy_kestrel()
	reordered.components.reverse()
	reordered.connections.reverse()
	reordered.assemblies.reverse()
	reordered.coolant_circuits.reverse()
	var split = Simulation.new(reordered)
	for ship in [ordered, split]:
		_isolate_endpoints(ship)
		ship.bypass_command("install", {"source_id": "pump_b", "circuit_id": "core_loop"})
	ordered.tick(11.0)
	for index in range(110):
		split.tick(0.03)
		split.tick(0.07)
	_check(ordered.snapshot() == split.snapshot(), "Installation and circuit state are independent of declaration order and frame partitions.")
	var renamed = _copy_kestrel()
	var mapping: Dictionary = {}
	for spec in renamed.components:
		mapping[spec.id] = "custom_" + spec.id
		spec.id = mapping[spec.id]
	for assembly in renamed.assemblies:
		for port in assembly.ports:
			var endpoint: Dictionary = assembly.ports[port]
			endpoint.component = mapping.get(endpoint.component, endpoint.component)
	for link in renamed.connections:
		link.from_component = mapping.get(link.from_component, link.from_component)
		link.to_component = mapping.get(link.to_component, link.to_component)
	for view in renamed.views:
		view.members = view.members.map(func(id): return mapping.get(id, id))
	for view_id in renamed.layouts:
		var nodes: Dictionary = {}
		for id in renamed.layouts[view_id].nodes:
			nodes[mapping.get(id, id)] = renamed.layouts[view_id].nodes[id]
		renamed.layouts[view_id].nodes = nodes
	for circuit in renamed.coolant_circuits:
		circuit.pump = mapping[circuit.pump]
		circuit.service_component = mapping[circuit.service_component]
		circuit.members = circuit.members.map(func(id): return mapping[id])
	var generic = Simulation.new(renamed)
	_check(generic.validation_errors.is_empty(), "Renaming installed equipment preserves a valid authored bypass configuration.")
	if not generic.validation_errors.is_empty():
		return
	_isolate_endpoints(generic, "custom_")
	generic.bypass_command("install", {"source_id": "custom_pump_b", "circuit_id": "core_loop"})
	_advance(generic, 11.0)
	_start_backup(generic, "custom_")
	_check(_near(_s(generic, "custom_main_engine", "thrust"), 16.0)
		and _near(_s(generic, "custom_heat_exchanger", "coolant_flow"), 24.0),
		"A renamed ship can perform the same backup operation without equipment-ID branches.")


func _copy_kestrel():
	var copied = Ship.new()
	for key in ["id", "display_name", "schema_version", "ambient_temperature", "bypass_capacity", "bypass_kits"]:
		copied.set(key, Kestrel.get(key))
	for item in Kestrel.components:
		var spec = item.duplicate(true)
		spec.definition = item.definition.duplicate(true)
		copied.components.append(spec)
	for item in Kestrel.assemblies: copied.assemblies.append(item.duplicate(true))
	for item in Kestrel.connections: copied.connections.append(item.duplicate(true))
	copied.views = Kestrel.views.duplicate(true)
	copied.layouts = Kestrel.layouts.duplicate(true)
	copied.maintenance_supplies = Kestrel.maintenance_supplies.duplicate(true)
	copied.coolant_circuits = Kestrel.coolant_circuits.duplicate(true)
	return copied


func _installed_ship(source: String = "pump_b", circuit: String = "core_loop"):
	var ship = Simulation.new(Kestrel)
	_isolate_endpoints(ship)
	ship.bypass_command("install", {"source_id": source, "circuit_id": circuit})
	_advance(ship, 11.0)
	return ship


func _isolate_endpoints(ship, prefix: String = "") -> void:
	ship.command(prefix + "pump_a_feed", "closed", false)
	ship.command(prefix + "pump_b_feed", "closed", false)
	ship.bypass_command("set_primary", {"circuit_id": "core_loop", "open": false})
	ship.bypass_command("set_primary", {"circuit_id": "drive_loop", "open": false})
	ship.tick(0.1)


func _start_backup(ship, prefix: String = "") -> void:
	ship.bypass_command("set_primary", {"circuit_id": "drive_loop", "open": true})
	ship.command(prefix + "pump_b_feed", "closed", true)
	ship.command(prefix + "pump_b", "flow", 40.0)
	ship.bypass_command("set_flow", {"flow": 24.0})
	ship.bypass_command("open")
	_advance(ship, 30.0)


func _assert_backup_balance(ship) -> void:
	_check(_near(_s(ship, "pump_b", "flow"), 40.0) and _near(ship.bypass_info().delivered_flow, 24.0)
		and _near(_s(ship, "heat_exchanger", "coolant_flow"), 24.0)
		and _near(_s(ship, "radiator", "coolant_flow"), 24.0)
		and _near(_s(ship, "main_engine", "coolant_flow"), 16.0),
		"Forty L/s is shared once: 24 through the serial core/radiator circuit and 16 through the drive.")
	_check(_near(_s(ship, "main_engine", "thrust"), 16.0) and _near(_s(ship, "aux_bus", "draw"), 34.0)
		and ship.components.main_bus.settings.closed and _near(_s(ship, "life_support", "power"), 28.0),
		"Backup operation respects pump power and auxiliary capacity while retaining useful propulsion and main-bus services.")
	_check(_flow_balanced(ship) and _power_balanced(ship), "The bypass cannot duplicate donor flow or electrical power.")
	var active_bypass := false
	for edge in ship.coolant_connections():
		if edge.from_component == "pump_b" and edge.to_component == "heat_exchanger":
			active_bypass = bool(edge.get("active", false))
	_check(active_bypass, "The installed active route is exposed to dependency navigation and schematic presentation.")


func _flow_balanced(ship) -> bool:
	var info: Dictionary = ship.bypass_info()
	return info.delivered_flow >= -0.0001 and info.source_remaining_flow >= -0.0001 \
		and info.delivered_flow + info.source_remaining_flow <= info.source_flow + 0.0001 \
		and info.delivered_flow <= info.capacity + 0.0001


func _power_balanced(ship) -> bool:
	var consumed: float = 0.0
	for part in ship.components.values():
		if part.kind in ["load", "pump", "engine"]:
			consumed += float(part.state.power)
		if part.kind in ["reactor", "bus"] and part.state.draw > part.state.capacity + 0.0001:
			return false
	return _near(consumed, ship.totals().output)


func _s(ship, id: String, key: String) -> float:
	return float(ship.components[id].state.get(key, 0.0))


func _circuit(ship, id: String) -> Dictionary:
	for circuit in ship.bypass_info().circuits:
		if circuit.id == id:
			return circuit
	return {}


func _advance(ship, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.000001:
		var step: float = minf(remaining, 30.0)
		ship.tick(step)
		remaining -= step


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.001


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
