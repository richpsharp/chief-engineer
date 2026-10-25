extends RefCounted
## Illustrative wear-part life model, not a manufacturer reliability prediction.
## Physical operating time, stress-weighted service age, and hazard are distinct.

const PATCH_SECONDS: float = 10.0
const REPLACE_SECONDS: float = 30.0
const PATCH_HOURS: float = 100.0
const PATCH_EFFICIENCY: float = 0.85
const ACTIONS = ["simulate_wear", "patch", "replace", "cancel"]

var _components: Dictionary
var _incoming: Dictionary = {}
var supplies: Dictionary
var job: Dictionary = {}
var output_changed: bool = false


func _init(components: Dictionary, connections: Array, initial_supplies: Dictionary) -> void:
	_components = components
	supplies = initial_supplies.duplicate(true)
	for edge in connections:
		if edge.domain == "power":
			_incoming[edge.to_component] = edge.from_component
	for part in _components.values():
		if supported(part):
			part.state["failure_threshold"] = _failure_threshold(part)
	refresh()


static func supported(part) -> bool:
	return part != null and part.kind == "pump" and float(part.config.get("rated_life_hours", 0.0)) > 0.0


static func efficiency_at(age_hours: float, rated_hours: float) -> float:
	if rated_hours <= 0.0:
		return 1.0
	return clampf(1.0 - 1.5 * maxf(age_hours / rated_hours - 0.8, 0.0), 0.2, 1.0)


static func hazard_at(age_hours: float, rated_hours: float) -> float:
	if rated_hours <= 0.0:
		return 0.0
	# Beyond the plotted lifetime, cap the game hazard instead of overflowing
	# on deliberately extreme sandbox ages. This is a rate, not a probability.
	var ratio: float = clampf(age_hours / rated_hours, 0.0, 1000.0)
	return 0.00015 * exp(-ratio / 0.025) + 0.000001 + 0.02 * pow(maxf(ratio - 0.8, 0.0), 3.0)


func refresh() -> void:
	for id in _components:
		var part = _components[id]
		if not supported(part):
			continue
		var efficiency: float = efficiency_at(part.state.service_age_hours, part.config.rated_life_hours)
		if part.state.patch_remaining_hours > 0.0:
			efficiency = maxf(efficiency, PATCH_EFFICIENCY)
		part.state["efficiency"] = efficiency
		part.state["failure_rate"] = hazard_at(part.state.service_age_hours, part.config.rated_life_hours)
		part.state["maintenance_locked"] = 1.0 if job.get("component_id", "") == id else 0.0


func advance(delta: float) -> Array[String]:
	var messages: Array[String] = []
	var previous: Dictionary = {}
	for id in _components:
		var part = _components[id]
		if supported(part):
			previous[id] = [part.state.efficiency, part.pump_available()]
	var hours: float = delta / 3600.0
	for part in _components.values():
		if not _running(part):
			continue
		part.state["running_hours"] += hours
		if not supported(part):
			continue
		var nominal_flow: float = float(part.state.flow) / maxf(float(part.state.efficiency), 0.2)
		var stress: float = pow(clampf(nominal_flow / float(part.config.get("life_reference_flow", 30.0)), 0.0, 4.0), 2.0)
		part.state["service_age_hours"] += hours * maxf(0.25, stress)
		part.state["patch_remaining_hours"] = maxf(0.0, part.state.patch_remaining_hours - hours)
		# Integrate hazard in operating hours. Stress already changes service age;
		# it does not secretly accelerate the lifetime-hour counter.
		part.state["risk_exposure"] += hazard_at(part.state.service_age_hours, part.config.rated_life_hours) * hours
		if part.state.risk_exposure >= part.state.failure_threshold:
			part.state["failed"] = 1.0
			messages.append("%s: wear-part failure; isolate supply and replace wear parts." % part.spec.display_name)
	if not job.is_empty() and isolated(job.component_id):
		job.remaining = maxf(0.0, float(job.remaining) - delta)
		if job.remaining <= 0.000001:
			var part = _components[job.component_id]
			if job.action == "patch":
				part.state["patch_remaining_hours"] = PATCH_HOURS
			else:
				part.state["service_age_hours"] = 0.0
				part.state["risk_exposure"] = 0.0
				part.state["failed"] = 0.0
				part.state["patch_remaining_hours"] = 0.0
				part.state["replacement_count"] += 1.0
				part.state["failure_threshold"] = _failure_threshold(part)
			messages.append("%s: %s complete. Supply remains isolated; inspect and restore it when ready." % [part.spec.display_name, "temporary patch" if job.action == "patch" else "wear-part replacement"])
			job.clear()
	refresh()
	output_changed = false
	for id in previous:
		var part = _components[id]
		if previous[id] != [part.state.efficiency, part.pump_available()]:
			output_changed = true
	return messages


func isolated(id: String) -> bool:
	# Zero demand or an exhausted generator is not safe electrical isolation.
	var cursor: String = id
	var visited: Dictionary = {}
	while _incoming.has(cursor) and not visited.has(cursor):
		visited[cursor] = true
		cursor = _incoming[cursor]
		var upstream = _components[cursor]
		if upstream.kind == "bus" and not bool(upstream.settings.get("closed", true)):
			return true
	return false


func reason_for(id: String, action: String) -> String:
	if not _components.has(id):
		return "Unknown component."
	var part = _components[id]
	if not supported(part):
		return "Maintenance is available for pumps with an authored life rating."
	if action not in ACTIONS:
		return "Unknown maintenance action."
	if action == "cancel":
		return "" if job.get("component_id", "") == id else "No maintenance job on this component."
	if not job.is_empty():
		return "The maintenance station is occupied; finish or cancel its current job."
	if action == "simulate_wear":
		return "Reset or repair this pump before introducing another worn-pump condition." if part.state.failed > 0.0 or part.state.service_age_hours >= float(part.config.rated_life_hours) * 1.05 else ""
	if not isolated(id):
		return "Open an upstream supply breaker before working on this pump."
	if action == "patch":
		if part.state.failed > 0.0:
			return "A failed wear part needs replacement; a patch cannot restart it."
		if part.state.efficiency >= PATCH_EFFICIENCY - 0.000001:
			return "A patch only helps a pump below 85% flow efficiency."
		if int(supplies.get("patches", 0)) <= 0:
			return "No patch kits remain."
	else:
		if part.state.service_age_hours <= 0.000001 and part.state.failed <= 0.0:
			return "These wear parts are already new."
		if int(supplies.get("spares", 0)) <= 0:
			return "No spare wear-part sets remain."
	return ""


func apply(id: String, action: String) -> String:
	# Recheck on the simulation step: earlier queued commands may have changed
	# isolation, the shared work slot, or the remaining supplies.
	var reason: String = reason_for(id, action)
	if not reason.is_empty():
		return "Maintenance rejected: " + reason
	var part = _components[id]
	if action == "cancel":
		job.clear()
		refresh()
		return "%s: work cancelled; the consumed supply is not refunded." % part.spec.display_name
	if action == "simulate_wear":
		var age: float = float(part.config.rated_life_hours) * 1.05
		part.state["running_hours"] = maxf(part.state.running_hours, age)
		part.state["service_age_hours"] = age
		part.state["patch_remaining_hours"] = 0.0
		refresh()
		return "%s: sandbox setup loaded an experienced pump at %.0f service hours." % [part.spec.display_name, age]
	var duration: float = PATCH_SECONDS if action == "patch" else REPLACE_SECONDS
	var supply: String = "patches" if action == "patch" else "spares"
	supplies[supply] -= 1
	job = {"component_id": id, "action": action, "remaining": duration, "duration": duration}
	refresh()
	return "%s: %s started. Keep its supply breaker open; %.0f seconds of isolated work required." % [part.spec.display_name, action, duration]


func info(id: String, paused: bool = false) -> Dictionary:
	var part = _components.get(id)
	var valid: bool = supported(part)
	var active: bool = job.get("component_id", "") == id and not job.is_empty()
	var state: Dictionary = part.state if part != null else {}
	var result: Dictionary = {
		"supported": valid, "running_hours": float(state.get("running_hours", 0.0)),
		"service_age_hours": float(state.get("service_age_hours", 0.0)),
		"rated_life_hours": float(part.config.get("rated_life_hours", 0.0)) if part != null else 0.0,
		"efficiency": float(state.get("efficiency", 1.0)), "failure_rate": float(state.get("failure_rate", 0.0)),
		"failed": float(state.get("failed", 0.0)) > 0.0,
		"patch_remaining_hours": float(state.get("patch_remaining_hours", 0.0)),
		"job": str(job.get("action", "")) if active else "",
		"job_remaining": float(job.get("remaining", 0.0)) if active else 0.0,
		"job_duration": float(job.get("duration", 0.0)) if active else 0.0,
		"isolated": isolated(id), "patches": int(supplies.get("patches", 0)), "spares": int(supplies.get("spares", 0)),
		"reason": "No pump wear model is assigned to this component.", "actions": {},
	}
	for action in ACTIONS:
		var reason: String = "Simulation is paused." if paused else reason_for(id, action)
		result.actions[action] = {"enabled": reason.is_empty(), "reason": reason}
	if active:
		result.reason = "Maintenance paused; reopen an upstream supply breaker." if not result.isolated else "Isolated maintenance in progress; supply stays open after completion."
	elif valid:
		if result.failed:
			result.reason = "Wear-part failure. Isolate the pump and replace its wear parts."
		elif result.patch_remaining_hours > 0.0:
			result.reason = "Temporary patch: at least 85% flow efficiency for its remaining operating hours. Age and failure risk remain."
		elif result.efficiency < 0.999:
			result.reason = "Wear reduces delivered flow per kilowatt. Compensating with a higher setting uses more power and ages the wear parts faster."
		else:
			result.reason = "Within the normal performance envelope. Life rating and risk are illustrative estimates, not a failure deadline."
	return result


func profile(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var part = _components.get(id)
	if not supported(part):
		return result
	var rating: float = float(part.config.rated_life_hours)
	for index in range(121):
		var age: float = rating * 1.5 * float(index) / 120.0
		result.append({"age_hours": age, "efficiency": efficiency_at(age, rating), "failure_rate": hazard_at(age, rating)})
	return result


func snapshot() -> Dictionary:
	return {"supplies": supplies.duplicate(true), "job": job.duplicate(true)}


func _running(part) -> bool:
	match part.kind:
		"pump": return float(part.state.get("flow", 0.0)) > 0.000001
		"reactor", "bus", "engine", "load": return float(part.state.get("power", 0.0)) > 0.000001
		"heat_exchanger": return float(part.state.get("coolant_flow", 0.0)) > 0.000001
		"radiator": return float(part.state.get("coolant_flow", 0.0)) > 0.000001 and float(part.settings.get("deployment", 0.0)) > 0.0
	return false


func _failure_threshold(part) -> float:
	# Authored seeds survive equipment renaming and list reordering. A local RNG
	# is sampled once per replacement, never once per frame or shared globally.
	var random := RandomNumberGenerator.new()
	random.seed = int(part.config.get("reliability_seed", 1)) + int(part.state.replacement_count) * 104729
	return -log(clampf(random.randf(), 0.000001, 0.999999))
