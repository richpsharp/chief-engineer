extends SceneTree
## Maintenance acceptance checks use authored boundary fixtures, not long waits.

const Simulation = preload("res://scripts/ship_simulation.gd")
const Ship = preload("res://scripts/definitions/ship_definition.gd")
const Tern = preload("res://ships/tern.tres")
const Kestrel = preload("res://ships/kestrel.tres")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_operating_hours()
	_test_profile_and_validation()
	_test_wear_and_compensation()
	_test_repair_isolation_and_races()
	_test_patch_and_replacement()
	_test_expiry_and_failure()
	_test_inventory_and_job_ownership()
	_test_pause_reset_and_detached_state()
	_test_reproducibility()
	print("%s: %d maintenance checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _test_operating_hours() -> void:
	var ship = Simulation.new(Tern)
	var initial: Dictionary = ship.maintenance_info("port_pump")
	_check(initial.supported and _near(initial.running_hours, 1000.0) and _near(initial.service_age_hours, 1000.0)
		and _near(initial.rated_life_hours, 10000.0), "Tern starts with authored pump history and a separate nominal life rating.")
	var original_hours: Dictionary = {}
	for id in ["utility_reactor", "distribution_bus", "life_support", "port_engine", "port_pump"]:
		original_hours[id] = ship.maintenance_info(id).running_hours
	_advance(ship, 36.0)
	var all_advanced := true
	for id in original_hours:
		all_advanced = all_advanced and _near(ship.maintenance_info(id).running_hours, original_hours[id] + 0.01)
	_check(all_advanced, "Running equipment counts 36 seconds as 0.01 operating hours across component kinds.")
	_check(_near(ship.totals().output, 144.0) and _near(_state(ship, "port_engine", "thrust"), 20.0)
		and _near(ship.maintenance_info("port_pump").efficiency, 1.0), "A healthy service history preserves Tern's original cruise point.")
	ship.command("port_pump_feed", "closed", false)
	ship.tick(0.1)
	var stopped_hours: float = ship.maintenance_info("port_pump").running_hours
	var stopped_age: float = ship.maintenance_info("port_pump").service_age_hours
	var starboard_hours: float = ship.maintenance_info("starboard_pump").running_hours
	_advance(ship, 36.0)
	_check(_near(ship.maintenance_info("port_pump").running_hours, stopped_hours)
		and _near(ship.maintenance_info("port_pump").service_age_hours, stopped_age), "An isolated pump accumulates neither operating hours nor service wear.")
	_check(_near(ship.maintenance_info("starboard_pump").running_hours, starboard_hours + 0.01),
		"The independent drive keeps accumulating operating hours while the other is offline.")
	ship.command("starboard_pump", "flow", 0.0)
	ship.tick(0.1)
	var idle_hours: float = ship.maintenance_info("starboard_pump").running_hours
	_advance(ship, 10.0)
	_check(_near(ship.maintenance_info("starboard_pump").running_hours, idle_hours), "An idle but electrically connected pump does not accrue running time.")
	var kestrel = Simulation.new(Kestrel)
	_advance(kestrel, 10.0)
	_check(_near(kestrel.maintenance_info("battery").running_hours, 0.0), "The isolated reference battery has no fictitious operating hours.")


func _test_profile_and_validation() -> void:
	var ship = Simulation.new(Tern)
	var profile: Array = ship.reliability_profile("port_pump")
	_check(profile.size() > 10, "The lifetime view receives a sampled equipment profile.")
	if profile.is_empty():
		return
	var middle: Dictionary = profile[profile.size() / 3]
	_check(profile.front().failure_rate > middle.failure_rate and profile.back().failure_rate > middle.failure_rate,
		"The illustrative failure-rate profile has early-life, useful-life, and wear-out regions.")
	_check(_near(profile.front().efficiency, 1.0) and profile.back().efficiency < middle.efficiency,
		"Performance loss is separate from the early-life failure-risk curve.")
	var ordered_and_finite := true
	var previous_age: float = -1.0
	for point in profile:
		ordered_and_finite = ordered_and_finite and is_finite(point.age_hours) and point.age_hours > previous_age \
			and is_finite(point.efficiency) and point.efficiency >= 0.0 and point.efficiency <= 1.0 \
			and is_finite(point.failure_rate) and point.failure_rate >= 0.0
		previous_age = point.age_hours
	_check(ordered_and_finite, "Graph samples are finite, ordered, and bounded in physically meaningful units.")
	_check(not ship.maintenance_info("utility_reactor").supported and ship.maintenance_info("utility_reactor").rated_life_hours == 0.0,
		"Equipment without an authored lifetime is reported as unrated, not expired.")
	for invalid in [-1.0, NAN, INF, "10000", 1.0e-300]:
		var definition = _copy_tern()
		definition.component("port_pump").parameters["rated_life_hours"] = invalid
		_check(not definition.validate().is_empty(), "A nonnumeric, negative, or nonfinite life rating is rejected.")
	for field in ["running_hours", "service_age_hours"]:
		for invalid in [-1.0, NAN]:
			var definition = _copy_tern()
			definition.component("port_pump").initial_state[field] = invalid
			_check(not definition.validate().is_empty(), "Invalid authored operating and service ages are rejected.")
	for invalid in [0.0, -1.0, NAN, 1.0e-300]:
		var definition = _copy_tern()
		definition.component("port_pump").parameters["life_reference_flow"] = invalid
		_check(not definition.validate().is_empty(), "A zero, nonfinite, or numerically unusable reference flow is rejected.")
	var excessive_age = _copy_tern()
	excessive_age.component("port_pump").initial_state["service_age_hours"] = 1.0e308
	var extreme = Simulation.new(excessive_age)
	_check(not extreme.validation_errors.is_empty() or is_finite(extreme.maintenance_info("port_pump").failure_rate),
		"Extreme finite authored ages cannot publish infinite failure-risk telemetry.")
	for invalid in [-1, 0.5, "2"]:
		var definition = _copy_tern()
		definition.maintenance_supplies["spares"] = invalid
		_check(not definition.validate().is_empty(), "Maintenance inventory requires whole nonnegative material counts.")
	var unrated = _copy_tern()
	unrated.component("port_pump").definition.defaults.erase("rated_life_hours")
	var unrated_ship = Simulation.new(unrated)
	_advance(unrated_ship, 1.0)
	_check(unrated_ship.validation_errors.is_empty() and not unrated_ship.maintenance_info("port_pump").supported
		and _near(_state(unrated_ship, "port_pump", "flow"), 20.0),
		"An unprofiled pump retains ordinary behavior without being assigned an invented lifetime.")


func _test_wear_and_compensation() -> void:
	var ship = Simulation.new(Tern)
	var authored: Dictionary = Tern.component("port_pump").initial_state.duplicate(true)
	var before: Dictionary = ship.maintenance_info("port_pump")
	_check(ship.maintenance_command("port_pump", "simulate_wear").accepted,
		"The sandbox wear experiment is available as an addressed command.")
	_check(ship.maintenance_info("port_pump").service_age_hours == before.service_age_hours,
		"The wear experiment waits for a committed fixed step.")
	ship.tick(0.1)
	_advance(ship, 20.0)
	var worn: Dictionary = ship.maintenance_info("port_pump")
	var worn_flow: float = _state(ship, "port_pump", "flow")
	var worn_power: float = _state(ship, "port_pump", "power")
	_check(worn.service_age_hours > worn.rated_life_hours and worn.efficiency < 0.9 and not worn.failed,
		"The experiment introduces readable wear without immediately destroying the pump.")
	_check(worn_flow < 20.0 and worn_power / worn_flow > 0.3,
		"A worn pump delivers less circulation per kilowatt than its healthy rating.")
	_check(_state(ship, "port_engine", "thrust") < 20.0 and _near(_state(ship, "starboard_engine", "thrust"), 20.0),
		"Local pump degradation reduces only its own propulsion branch.")
	_check(_power_balanced(ship), "Degradation preserves radial electrical capacity and load accounting.")
	ship.command("port_pump", "flow", 30.0)
	_advance(ship, 20.0)
	_check(_state(ship, "port_pump", "flow") > worn_flow and _state(ship, "port_pump", "power") > worn_power,
		"Increasing pump command trades extra power for additional worn-pump circulation.")
	_check(_power_balanced(ship) and Tern.component("port_pump").initial_state == authored,
		"Compensation neither creates power nor mutates the authored ship.")
	var stress = Simulation.new(Tern)
	stress.command("port_pump", "flow", 30.0)
	_advance(stress, 36.0)
	var info: Dictionary = stress.maintenance_info("port_pump")
	_check(info.service_age_hours - 1000.0 > info.running_hours - 1000.0,
		"Heavy operation consumes service life faster while the running-hour clock stays literal.")


func _test_repair_isolation_and_races() -> void:
	var ship = _worn_ship()
	_check(not ship.maintenance_command("port_pump", "patch").accepted,
		"Maintenance is rejected while the pump's electrical path is connected.")
	ship.command("port_pump", "flow", 0.0)
	ship.tick(0.1)
	_check(not ship.maintenance_info("port_pump").isolated and not ship.maintenance_command("port_pump", "replace").accepted,
		"Setting demand to zero is not electrical isolation.")
	ship.command("utility_reactor", "limit", 0.0)
	ship.tick(0.1)
	_check(not ship.maintenance_command("port_pump", "replace").accepted,
		"Zero available generation is not a safe substitute for an open breaker.")
	ship.command("utility_reactor", "limit", 220.0)
	ship.command("port_pump_feed", "closed", false)
	ship.tick(0.1)
	_check(ship.maintenance_info("port_pump").isolated, "An explicit upstream open breaker establishes isolation.")
	var supplies: int = ship.maintenance_info("port_pump").spares
	ship.command("port_pump_feed", "closed", true)
	_check(ship.maintenance_command("port_pump", "replace").accepted,
		"A request can be queued against the currently isolated state.")
	ship.tick(0.1)
	_check(ship.maintenance_info("port_pump").job.is_empty() and ship.maintenance_info("port_pump").spares == supplies,
		"Reconnection earlier in the command queue invalidates work without spending a spare.")
	ship.command("port_pump_feed", "closed", false)
	ship.tick(0.1)
	ship.maintenance_command("port_pump", "replace")
	ship.command("port_pump_feed", "closed", true)
	ship.tick(0.1)
	var info: Dictionary = ship.maintenance_info("port_pump")
	_check(info.job == "replace" and not info.isolated and _near(_state(ship, "port_pump", "flow"), 0.0),
		"Reconnection after a repair starts leaves the pump locked out and the job held.")
	var remaining: float = info.job_remaining
	_advance(ship, 10.0)
	_check(_near(ship.maintenance_info("port_pump").job_remaining, remaining)
		and _near(_state(ship, "port_pump", "power"), 0.0), "Energizing the feeder cannot advance maintenance or run equipment under repair.")
	ship.command("port_pump_feed", "closed", false)
	ship.tick(0.1)
	_advance(ship, 5.0)
	_check(ship.maintenance_info("port_pump").job_remaining < remaining,
		"Re-establishing isolation resumes held maintenance.")


func _test_patch_and_replacement() -> void:
	var ship = _worn_ship()
	ship.command("port_pump_feed", "closed", false)
	ship.tick(0.1)
	var before: Dictionary = ship.maintenance_info("port_pump")
	var risk_before: float = _state(ship, "port_pump", "risk_exposure")
	_check(ship.maintenance_command("port_pump", "patch").accepted, "An isolated worn pump accepts a field patch.")
	ship.tick(0.1)
	var started: Dictionary = ship.maintenance_info("port_pump")
	_check(started.job == "patch" and started.patches == before.patches - 1,
		"Starting a patch reserves one material unit and exposes a timed job.")
	_advance(ship, started.job_duration + 0.2)
	var patched: Dictionary = ship.maintenance_info("port_pump")
	_check(patched.job.is_empty() and patched.efficiency > before.efficiency and patched.efficiency < 1.0
		and patched.patch_remaining_hours > 0.0, "The patch restores limited capability with an explicit operating-time lifetime.")
	_check(_near(patched.running_hours, before.running_hours) and _near(patched.service_age_hours, before.service_age_hours),
		"A patch does not roll back accumulated hours or wear-part age.")
	_check(_state(ship, "port_pump", "risk_exposure") == risk_before and patched.failure_rate == before.failure_rate,
		"Restoring circulation with a patch does not erase the old wear part's accumulated failure risk.")
	_check(not ship.components["port_pump_feed"].settings.closed and _near(_state(ship, "starboard_engine", "thrust"), 20.0),
		"Completing work leaves the feeder isolated while the other drive remains available.")
	ship.command("port_pump_feed", "closed", true)
	_advance(ship, 20.0)
	_check(_state(ship, "port_engine", "thrust") > 0.0 and _state(ship, "port_engine", "thrust") < 20.0,
		"Recommissioning a patched pump restores useful but limited propulsion.")
	ship.command("port_pump_feed", "closed", false)
	ship.tick(0.1)
	var lifetime_before: float = ship.maintenance_info("port_pump").running_hours
	var spares: int = ship.maintenance_info("port_pump").spares
	_check(ship.maintenance_command("port_pump", "replace").accepted, "A replacement can supersede a temporary patch.")
	ship.tick(0.1)
	_advance(ship, ship.maintenance_info("port_pump").job_duration + 0.2)
	var repaired: Dictionary = ship.maintenance_info("port_pump")
	_check(repaired.job.is_empty() and repaired.spares == spares - 1 and _near(repaired.efficiency, 1.0)
		and _near(repaired.service_age_hours, 0.0) and _near(repaired.patch_remaining_hours, 0.0),
		"Replacing wear parts consumes a spare and restores capability without retaining a patch.")
	_check(_near(repaired.running_hours, lifetime_before), "Replacement preserves the equipment's lifetime running-hour record.")
	ship.command("port_pump_feed", "closed", true)
	_advance(ship, 60.0)
	_check(_near(_state(ship, "port_engine", "thrust"), 20.0) and _near(_state(ship, "starboard_engine", "thrust"), 20.0)
		and _power_balanced(ship), "Recommissioning the repaired pump restores both drives with balanced power.")


func _test_expiry_and_failure() -> void:
	var expiring = _copy_tern()
	expiring.component("port_pump").initial_state["service_age_hours"] = 10500.0
	expiring.component("port_pump").initial_state["running_hours"] = 10500.0
	expiring.component("port_pump").initial_state["patch_remaining_hours"] = 0.0001
	var ship = Simulation.new(expiring)
	var patched_efficiency: float = ship.maintenance_info("port_pump").efficiency
	ship.command("port_pump_feed", "closed", false)
	ship.tick(0.1)
	_advance(ship, 1.0)
	_check(_near(ship.maintenance_info("port_pump").patch_remaining_hours, 0.0001),
		"A temporary patch's remaining life counts running hours, not time parked offline.")
	ship.command("port_pump_feed", "closed", true)
	_advance(ship, 1.0)
	_check(_near(ship.maintenance_info("port_pump").patch_remaining_hours, 0.0)
		and ship.maintenance_info("port_pump").efficiency < patched_efficiency and _power_balanced(ship),
		"An exhausted patch returns to the underlying wear performance without creating power.")
	var imminent = _copy_tern()
	imminent.component("port_pump").initial_state["service_age_hours"] = 11000.0
	imminent.component("port_pump").initial_state["running_hours"] = 11000.0
	imminent.component("port_pump").initial_state["risk_exposure"] = 1000000.0
	var failed = Simulation.new(imminent)
	var replay = Simulation.new(imminent)
	failed.tick(0.1)
	replay.tick(0.04)
	replay.tick(0.06)
	_check(failed.snapshot() == replay.snapshot() and failed.maintenance_info("port_pump").failed,
		"Crossing a seeded risk budget produces the same failure under different frame partitions.")
	_check(_near(_state(failed, "port_pump", "flow"), 0.0) and _near(_state(failed, "port_pump", "power"), 0.0)
		and _near(_state(failed, "port_engine", "thrust"), 0.0) and _near(_state(failed, "starboard_engine", "thrust"), 20.0)
		and _power_balanced(failed), "A wear-part failure stops its pump and engine in the committed step while the other branch runs.")
	var stopped: float = failed.maintenance_info("port_pump").running_hours
	_advance(failed, 5.0)
	_check(_near(failed.maintenance_info("port_pump").running_hours, stopped),
		"A failed pump does not accumulate running hours merely because its feeder remains connected.")
	failed.command("port_pump_feed", "closed", false)
	failed.tick(0.1)
	_check(not failed.maintenance_command("port_pump", "patch").accepted,
		"A temporary patch cannot restart a failed wear part.")
	failed.command("port_pump_feed", "closed", true)
	_advance(failed, 1.0)
	_check(failed.maintenance_info("port_pump").failed and _near(_state(failed, "port_pump", "flow"), 0.0),
		"Cycling the feeder does not clear a permanent mechanical failure.")
	failed.command("port_pump_feed", "closed", false)
	failed.tick(0.1)
	failed.maintenance_command("port_pump", "replace")
	_advance(failed, 31.0)
	_check(not failed.maintenance_info("port_pump").failed and _near(failed.maintenance_info("port_pump").running_hours, stopped),
		"Replacement clears permanent failure while preserving the equipment's accumulated history.")
	failed.command("port_pump_feed", "closed", true)
	_advance(failed, 60.0)
	_check(not failed.maintenance_info("port_pump").failed and _near(_state(failed, "port_engine", "thrust"), 20.0),
		"Replacement resets the expended risk budget so the restarted pump does not immediately fail again.")


func _test_inventory_and_job_ownership() -> void:
	var ship = _worn_ship()
	ship.maintenance_command("starboard_pump", "simulate_wear")
	ship.command("port_pump_feed", "closed", false)
	ship.command("starboard_pump_feed", "closed", false)
	ship.tick(0.1)
	var before: Dictionary = ship.maintenance_info("port_pump")
	ship.maintenance_command("port_pump", "patch")
	ship.maintenance_command("starboard_pump", "patch")
	ship.tick(0.1)
	_check(ship.maintenance_info("port_pump").job == "patch" and ship.maintenance_info("starboard_pump").job.is_empty()
		and ship.maintenance_info("port_pump").patches == before.patches - 1,
		"Queued simultaneous requests start only one job and spend materials only once.")
	_check(not ship.maintenance_command("starboard_pump", "cancel").accepted,
		"A different equipment inspector cannot cancel another pump's repair.")
	_check(ship.maintenance_command("port_pump", "cancel").accepted, "The owning pump can cancel its repair.")
	ship.tick(0.1)
	_check(ship.maintenance_info("port_pump").job.is_empty() and ship.maintenance_info("port_pump").patches == before.patches - 1
		and ship.maintenance_info("port_pump").patch_remaining_hours == 0.0,
		"Canceling started work spends its materials without granting the repair benefit.")
	var exhausted = _copy_tern()
	exhausted.maintenance_supplies = {"patches": 0, "spares": 0}
	var empty_ship = Simulation.new(exhausted)
	empty_ship.maintenance_command("port_pump", "simulate_wear")
	empty_ship.command("port_pump_feed", "closed", false)
	empty_ship.tick(0.1)
	_check(not empty_ship.maintenance_command("port_pump", "patch").accepted
		and not empty_ship.maintenance_command("port_pump", "replace").accepted,
		"An otherwise safe repair cannot start without its required consumable.")
	for args in [["missing", "patch"], ["port_engine", "replace"], ["port_pump", "invented_action"]]:
		_check(not ship.maintenance_command(args[0], args[1]).accepted, "Unknown equipment, unsupported kinds, and unknown maintenance actions are rejected.")


func _test_pause_reset_and_detached_state() -> void:
	var left = _worn_ship()
	var right = Simulation.new(Tern)
	var original: Dictionary = right.snapshot()
	left.command("port_pump_feed", "closed", false)
	left.tick(0.1)
	left.maintenance_command("port_pump", "replace")
	left.tick(0.1)
	left.toggle_pause()
	var paused: Dictionary = left.snapshot()
	left.tick(30.0)
	_check(left.snapshot() == paused and not left.maintenance_command("port_pump", "cancel").accepted,
		"Pause freezes work, operating hours, wear, and maintenance commands.")
	_check(right.snapshot() == original, "Maintenance and shared material use remain local to one ship runtime.")
	var info: Dictionary = left.maintenance_info("port_pump")
	info.running_hours = -100.0
	info.actions.clear()
	_check(left.maintenance_info("port_pump").running_hours >= 0.0 and not left.maintenance_info("port_pump").actions.is_empty(),
		"Returned maintenance observations cannot mutate runtime state or action availability.")
	left.reset()
	_check(left.snapshot() == original, "Reset restores authored history and supplies and discards in-progress work.")
	left.maintenance_command("port_pump", "simulate_wear")
	left.toggle_pause()
	left.tick(1.0)
	_check(_near(left.maintenance_info("port_pump").service_age_hours, 1000.0), "A queued maintenance action does not slip through pause.")
	left.toggle_pause()
	left.tick(0.1)
	_check(left.maintenance_info("port_pump").service_age_hours > 10000.0, "Resume applies the maintenance action retained through pause.")


func _test_reproducibility() -> void:
	var reordered = _copy_tern()
	reordered.components.reverse()
	reordered.connections.reverse()
	reordered.assemblies.reverse()
	var whole = _worn_ship()
	var split = Simulation.new(reordered)
	split.maintenance_command("port_pump", "simulate_wear")
	split.tick(0.1)
	whole.command("port_pump", "flow", 30.0)
	split.command("port_pump", "flow", 30.0)
	whole.tick(10.0)
	for frame in range(100):
		split.tick(0.03)
		split.tick(0.02)
		split.tick(0.05)
	_check(whole.snapshot() == split.snapshot(), "Operating age, wear, risk, and physical state are reproducible across component order and render-frame partitions.")
	var accelerated = _copy_tern()
	# This fixture deliberately starts far beyond a short rating so a real hazard
	# crossing can be observed without waiting thousands of operating hours.
	accelerated.component("port_pump").parameters["rated_life_hours"] = 1.0
	accelerated.component("port_pump").parameters["reliability_seed"] = 73
	accelerated.component("port_pump").initial_state["service_age_hours"] = 20.0
	var first = Simulation.new(accelerated)
	accelerated.components.reverse()
	accelerated.connections.reverse()
	var second = Simulation.new(accelerated)
	var initial: Dictionary = first.snapshot()
	var failure_time: float = -1.0
	for step in range(3000):
		first.tick(0.1)
		second.tick(0.03)
		second.tick(0.07)
		if first.maintenance_info("port_pump").failed:
			failure_time = first.elapsed
			break
	_check(failure_time > 0.0 and first.snapshot() == second.snapshot(),
		"Naturally accumulated seeded hazard fails at the same operating step despite ordering and frame changes.")
	first.reset()
	_check(first.snapshot() == initial, "Reset restores the original reliability state and reproducible risk budget.")
	if failure_time > 0.0:
		_advance(first, failure_time)
		_check(first.maintenance_info("port_pump").failed and first.snapshot() == second.snapshot(),
			"Replaying the same seed and duty produces the same failure time and resulting machinery state.")


func _copy_tern():
	var copied = Ship.new()
	for key in ["id", "display_name", "schema_version", "ambient_temperature"]:
		copied.set(key, Tern.get(key))
	for item in Tern.components:
		var spec = item.duplicate(true)
		spec.definition = item.definition.duplicate(true)
		copied.components.append(spec)
	for item in Tern.assemblies:
		copied.assemblies.append(item.duplicate(true))
	for item in Tern.connections:
		copied.connections.append(item.duplicate(true))
	copied.views = Tern.views.duplicate(true)
	copied.layouts = Tern.layouts.duplicate(true)
	copied.maintenance_supplies = Tern.maintenance_supplies.duplicate(true)
	return copied


func _worn_ship():
	var ship = Simulation.new(Tern)
	ship.maintenance_command("port_pump", "simulate_wear")
	ship.tick(0.1)
	return ship


func _state(ship, id: String, key: String) -> float:
	return float(ship.components[id].state.get(key, 0.0))


func _power_balanced(ship) -> bool:
	var consumption: float = 0.0
	for part in ship.components.values():
		if part.kind in ["load", "pump", "engine"]:
			consumption += float(part.state.power)
		if part.kind in ["reactor", "bus"] and part.state.draw > part.state.capacity + 0.0001:
			return false
	return _near(consumption, ship.totals().output)


func _advance(ship, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.000001:
		var step: float = minf(remaining, 30.0)
		ship.tick(step)
		remaining -= step


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.0001


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  FAIL: " + description)
