# Component implementation contract

This document describes the shared interfaces for the component refactor.

## Authored data (Resources)

- `scripts/definitions/component_type.gd`: `kind: String`, `ports: Dictionary` mapping port key to `{domain: String, direction: String}` (`in`/`out`), `defaults: Dictionary` for parameters, `controls: Array[Dictionary]` entries `{id, label, unit, min, max, default}`. Boolean breaker control uses `{id: "closed", label, kind: "toggle", default: true}`.
- `component_spec.gd`: `id`, `display_name`, `short_name`, `description`, `parent_id`, `definition: Resource`, `parameters: Dictionary`, `initial_settings: Dictionary`, `initial_state: Dictionary`, `inspectable: bool`. `config()` merges type defaults with instance parameters.
- `assembly_definition.gd`: `id`, `display_name`, `parent_id`, `ports: Dictionary` mapping exposed port to `{component, port}`. Aliases may point into nested assemblies; resolution must terminate at a leaf.
- `connection_definition.gd`: `id`, `from_component`, `from_port`, `to_component`, `to_port`, `capacity: float = -1` (unlimited). Domain inferred from resolved ports.
- `ship_definition.gd`: `schema_version=1`, `id`, `display_name`, `ambient_temperature=10`, `components: Array[Resource]`, `assemblies: Array[Resource]`, `connections: Array[Resource]`, `views: Array[Dictionary]`, `layouts: Dictionary`.
- Ship `maintenance_supplies` contains nonnegative integer `patches` and `spares` counts (defaults 3 and 2). Each simulation copies the inventory; a ship definition never holds an active repair job.
- Optional ship `coolant_circuits: Array[Dictionary]` entries have `{id, name, pump, members, service_component, reference_flow}`. Each names one primary pump, its serial circulation consumers, and an inspectable member with a service coupling. `bypass_capacity: float = 24` rates the shared kit, and `bypass_kits: int = 0` sets the initial inventory. Kestrel opts into two circuits and one kit; Tern retains its existing fixed circulation graph.
- Ship methods: `component(id) -> Resource`, `assembly(id) -> Resource`, `resolve_port(owner, port) -> Dictionary` returning `{component, port, domain, direction}` or `{}`, `resolved_connections() -> Array[Dictionary]` entries `{id, from_component, from_port, to_component, to_port, domain, capacity}`, `validate() -> Array[String]`, `view(id) -> Dictionary`, `workspace_for(component_id) -> String` (first workspace containing component).
- Default ship: `load("res://ships/kestrel.tres")`. Definitions are treated as immutable; runtime copies settings/state.
- Playable definitions are listed in `scripts/ship_catalog.gd` as `DEFINITIONS: Array[Resource]`, currently Kestrel and Tern. The catalog contains authored data references, not equipment behavior.

## Network conventions

- Kinds: `reactor`, `bus`, `pump`, `engine`, `load`, `heat_exchanger`, `radiator`, `coolant`, `battery`.
- Electrical ports: source/bus `power_out`; bus/load/pump/engine `power_in`, domain `power`.
- Pump `flow_out` to exchanger/engine/radiator `flow_in`, domain `coolant`. These carry circulation capability, not pressure-solved pipes. A pump can feed several consumers of its circuit without duplicating a fluid inventory. Explicit service circuits share one allocation among their serial members; an installed bypass divides the donor pump's flow between circuits. Legacy connections on ships without explicit circuits retain their existing capability semantics.
- Thermal: reactor `heat_out` -> exchanger `heat_in`; exchanger `heat_out` -> coolant `heat_in`; engine `heat_out` -> coolant `heat_in`; coolant `heat_out` -> radiator `heat_in`, domain `thermal`.
- Bus settings: `limit`, `closed`; reactor `limit`; pump `flow`; engine `thrust`; radiator `deployment`. Loads have no controls.
- Common parameters: `priority` (smaller served first), `rated_power` (reactor/bus/load), `heat_capacity`, `passive_loss`, `warning_temperature`.
- Pump: `kw_per_flow`, `response_seconds=1.5`.
- Engine: `kw_per_thrust=2.4`, `flow_per_thrust=1`, `response_seconds=2.5`, `heat_fraction=.55`, `transfer_coefficient=36.9/23/30`.
- Reactor: `heat_fraction=.08`, `service_heat_fraction=.12` (lumps heat from its downstream non-engine consumers into core, preserving current simplified model).
- Exchanger: `transfer_coefficient=.08`.
- Radiator: `rejection_coefficient=2.51`, `reference_flow=24`.
- States initially: pump `flow`; engine `thrust`, `temperature`; reactor/coolant `temperature`. Settings provide initial requests.
- Supported electrical graph: radial source/bus distribution, one power input per consumer, no cycles/crossfeeds; explicitly validated. Load priority is ship data, tie broken by stable instance ID. Initial phases preserve existing priority and do not redistribute unused ramp allocations within the same step.

An engine's published electrical demand is the demand considered during allocation. If a lower-priority pump subsequently increases circulation, that extra capability becomes available for allocation on the next step. Falling circulation still immediately reduces engine demand, allocation, and output to keep operation safe. This prevents pump startup from appearing as an electrical shortage.

## Runtime API

`ShipSimulation.new(optional_definition)`; default Kestrel. Properties `definition`, `components: Dictionary`, `paused`, `elapsed`, `events: Array[String]` (bounded to 50), `validation_errors: Array[String]`, `command_results: Array[Dictionary]` (bounded to 50), read-only `step_seconds=.1`.

Each component runtime has `spec`, `kind: String`, `config: Dictionary`, `settings: Dictionary`, `state: Dictionary`. Common state `power`, `allocated_power`, `requested_power`; source/bus `draw`; pump `flow`, `target_flow`; engine `thrust`, `target_thrust`, `cooling_limit` (maximum thrust supported by committed circulation); exchanger `heat_transfer`; radiator `heat_rejected`; heat producers `heat_generated`. Thermal masses (reactor, engine, coolant) publish `temperature` (°C), `temperature_rate` (°C/s), and `net_heat` (kW, positive adds stored heat). These are refreshed at committed temperatures, including initialization. Missing optional power/flow readings display zero; missing temperature measurements remain absent.

Runtime `power_constraint: Dictionary` is derived diagnostic evidence, rebuilt each solve rather than saved as operating state. It is empty when electrical demand is satisfied. Otherwise `kind` is `node`, `connection`, or `disconnected`, and `component_id` identifies the limiting node, receiving endpoint, or unfed endpoint. Connection constraints also contain `connection_id`, `source_id`, and `capacity` (kW). The allocator records the actual limiting constraint before reserving capacity; the presenter does not infer it from unrelated upstream equipment. A bus inherits only constraints on its own supply path, not restrictions in its downstream consumers.

Methods `tick(delta)`, `reset()`, `toggle_pause()`, `command(target_id, action, value) -> Dictionary` with `{accepted, reason, sequence}`; action matches control ID, toggle callers supply desired boolean. Invalid/paused commands rejected, valid commands queued and applied on next fixed step. `snapshot() -> Dictionary` returns a detached state/settings map for testing/saves. `totals() -> Dictionary` with `output`, `capacity`, `spare`, `heat_generated`, `heat_rejected`. Runtime owns physical calculations, command validation, committed readings, and the human-readable command history. Equipment IDs come from definitions; panel formatting lives in the presenter.

`thermal_transfer(connection_id) -> float` returns committed net heat transfer in kW along that thermal connection, positive in the authored direction and negative for reverse exchange. Unknown or inactive connections return zero. The thermal model refreshes this derived telemetry on every solve, including initialization and reset; it is not additional saved state. Exchanger inlet and outlet readings account for the heat actually exchanged, and each radiator inlet reports its own contribution to rejection.

## Presentation API

`ShipPresenter.new(simulation)` in `scripts/presentation/ship_presenter.gd`. Methods `readings(id) -> Array[Array]`, `equipment_status(id) -> String`, `equipment_reason(id) -> String`, `system_summary(view_id) -> Dictionary {state,value,detail,tone}`, `conditions() -> Array[Dictionary]` entries `{code,text,system,equipment,cause_id}`, `links(id) -> Array[Dictionary]` entries `{system,equipment,label}`, `caption(id) -> String`. Derive dependencies from current runtime presentation connections, including installed bypasses; no named Kestrel IDs. Readings raw values remain runtime numeric; formatting only presenter.

`temperature_readings(id) -> Array[Dictionary]` returns detached observations `{component_id, temperature, rate, net_heat}` using the runtime units above. A thermal mass observes itself; transfer equipment observes adjacent thermal masses through resolved thermal connections, in stable ID order. No connection or measurement returns an empty array. If the observed mass has an optional finite `warning_temperature`, its observation also includes `advisory_temperature` and `margin` (advisory minus temperature, in °C). This setting is presentation policy only: physics never consults it. The current UI shows an advisory when the margin is negative, with the actual temperature and trend. `conditions()` reports each mass's advisory once, adds its numeric `measurement`, and routes hidden masses to connected inspectable equipment. Presentation reads committed coolant flow and thermal telemetry; it does not solve networks again.

Operating conditions and thermal advisories are independent. A closed radiator with hot coolant reports both facts; an offline reactor can still hold heat. The equipment status gives operating restrictions precedence, while its explanation also includes connected temperature advisories. `conditions()` retains every applicable condition regardless of the single status label. Engine supply and cooling status use the simulation's published `requested_power`, `allocated_power`, and `cooling_limit`; the presenter does not repeat the physical conversion formulas.

Cooling diagnostics consider every contributing pump, independently of connection declaration order. They prefer a demonstrated electrical restriction, then an idle or ramping pump. A sole supply remains an inspection target for insufficient flow settings. When several pumps meet their settings but their combined circulation is insufficient, the condition stays on the affected equipment and explains the aggregate shortfall; links expose each contributing supply.

Conditions with no inspectable equipment route to a view containing the affected component, with `equipment` empty. If no authored view contains it, both `system` and `equipment` are empty: the warning still counts and displays without an inspect button. A connection-limited condition includes `connection_id` and routes to the receiving equipment when possible.

Views: `{id,name,kind,summary_kind,description,detail,members}`. Kind workspace or summary. Summary kinds power/temperature/thrust/load/reactor. Members are leaf IDs for aggregation/navigation; departments may overlap. Layouts keyed by view ID: `{nodes: Dictionary}` maps leaf IDs to `Rect2`. Schematic edges derive from connections and the visible endpoints (no duplicated wiring lists). Thermal-only hidden coolant reservoir may be omitted from initial schematic.

Schematic activity follows committed connection readings. A thermal connection is active when its transfer magnitude exceeds 0.01 kW, including reverse exchange. A collapsed route through hidden components is active only when an active path connects its endpoints. This indicates exchange along the route, not attribution of a particular source's heat through shared storage; animation direction remains the authored connection direction.

Cards, connection endpoints, and routing obstacles share the same layout filtered to inspectable equipment. Hidden equipment may retain authored positions without producing dangling lines or invisible obstacles; its network connections still participate in collapsed routes.

Views may supply `nav_name` as a shorter sidebar label. Power summaries count network boundaries once even with nested member buses; multi-engine summaries report mean thrust. The heat strip reports active radiator rejection; passive thermal losses account for the remaining equilibrium heat loss.

The view ID `overview` is reserved for the built-in ship overview. Authored workspaces and summaries must use other IDs; the validator rejects this collision before the console starts.

An unselected workspace inspector lists its inspectable `members`, independently of schematic placement or network connections. This keeps isolated equipment accessible and allows workspaces with no authored schematic positions. Hidden (`inspectable=false`) members stay out of the list. Selecting equipment opens its normal inspector, and Back restores the list.

Snapshots include schema version, definition ID, step count, fractional time accumulator, queued commands, and detached component settings/state. They are a serialization boundary, not a save/load UI. Incoming frame deltas are capped at 30 seconds to bound catch-up after suspension. Numerical thermal integration uses fixed 0.1-second explicit steps; conductance and heat-capacity tuning should stay within a stable regime. It is not an arbitrary-stiffness engineering solver.

Tests use addressed component state/commands; no legacy named A/B getters. Kestrel and Tern are playable authored resources. Detached, transformed copies of definitions remain useful fixtures for exercising validation and topology boundaries.

Control descriptors may specify `max_parameter` (e.g. `rated_power`, `max_flow`). Use `spec.controls()` for effective descriptors resolved against instance parameters, rather than accessing the type's raw list. Kestrel models six separate service loads and one hidden `coolant_reservoir`; main and auxiliary buses both expose capacity and breaker controls.

Every authored control requires a nonempty String `label`; missing, blank, and non-string labels are configuration errors. This includes toggle controls. Omitting the controls themselves for fixed-capacity equipment remains supported.

Operating ranges for `limit`, `flow`, `thrust`, and `deployment` must have nonnegative minima; negative Celsius temperatures remain valid. Reactor and bus controls may be omitted for fixed-capacity equipment, in which case capacity defaults to `rated_power` and an uncontrolled bus breaker defaults closed. Source status, summaries, and capacity captions read the solver's committed `capacity`, including when no limit control exists. An omitted control cannot receive commands.

## Extension boundary

The component framework currently composes a fixed family of equipment behaviors. A new ship can reuse types with different instances, parameters, connections, and nested assemblies. Adding a new machinery behavior requires updating the relevant domain model, validation, and presentation. Assemblies expose descendant ports and ownership; they do not run an additional simulation or consume resources themselves.

Commands are addressed messages queued at fixed-step boundaries. Physical connections describe relationships solved together by the power, coolant, and thermal models; they do not deliver arbitrary messages to component callbacks. This keeps allocation and heat accounting in one place. Runtime topology changes currently support one installed coolant bypass between authored service circuits. A general event protocol, behavior plug-in registry, arbitrary ship editing, and save restoration are not implemented. The current console uses authored positions and a fixed-size panel layout; it is not an automatic layout engine for arbitrarily large ships.

## Ship selection and Tern authoring

The console's `select_ship(ship_id) -> bool` selects a catalog definition after the console is ready; unknown IDs are rejected. Invalid catalog definitions are disabled in the selector with validation feedback in their tooltips; a rejected choice keeps the menu on the current ship. Each visited ship has an independent runtime retained for the current app session. Switching clears navigation history and returns to the selected ship's overview. The inactive runtime receives no ticks, so its settings, queued commands, elapsed time, and pause state remain parked. Reset acts only on the current runtime. No sessions survive app restart.

Tern reuses the existing equipment types with 20 components, nine assemblies, and 25 connections. A common reactor and distribution trunk feed independent port and starboard drive branches. Each engine is wired directly to its drive bus, while its pump sits behind a separate feeder bus. Opening a pump feeder therefore tests a cooling dependency without removing the engine's electrical connection. Both engines share coolant storage and heat rejection.

Tern's 144 kW cruise comprises 44 kW of service loads, an 8 kW core pump, two 6 kW drive pumps, and two 40 kW engines. The 220 kW source leaves 76 kW spare. Its authored equilibrium is 40°C reactor, 50°C engines, and 30°C coolant at a 10°C ambient reference: 59.2 kW generated balances 52 kW radiated plus 7.2 kW passive losses. Parameter overrides tune those readings using the unchanged thermal model.

The second ship required only authored ship data, a small catalog, and console selection/session handling. Equipment models, definition schemas, and presentation rules required no ship-specific branches or new behaviors. Different priorities and nested buses exercise the existing radial allocator, while the propulsion summary already supports mean thrust across multiple engines.

## Operating history and pump maintenance

`scripts/simulation/maintenance_model.gd` owns operating history, pump wear, reliability, and the single onboard maintenance station. All component runtimes contain `running_hours`, initialized from authored numeric state or zero. A pump counts time while it delivers flow; reactors, buses, engines, and loads count time while supplying or consuming power. Exchangers count circulating time; radiators count circulating time while deployed. Passive coolant storage and the isolated battery reference do not accrue fictitious running hours. An inactive or paused ship never advances any of these clocks.

An optional `rated_life_hours` parameter describes a reference service life. Shared pumps provide `rated_life_hours=10000`, `life_reference_flow=30`, and an integer `reliability_seed`. Tern overrides reference flow to 20 L/s and gives each pump a distinct seed and 1,000 hours of initial history. Equipment without a rating is displayed as unrated. Wear behavior currently applies to rated pumps; a rating on another kind is metadata, not an implemented failure model.

For pumps, `service_age_hours` tracks equivalent wear-part age separately from lifetime `running_hours`. Actual running hours increase by simulation seconds / 3600. Service age advances at the square of nominal mechanical flow / reference flow, bounded to a 0.25–16 multiplier while running. The nominal flow is delivered flow divided by efficiency. Working harder to compensate for wear therefore consumes more electrical power and service life, without changing the meaning of a clock hour.

Life ratings and reference flow must be finite and within 1e-6–1e12; authored hour counters are bounded to 0–1e12. Seeds and replacement counts have integer bounds, supplies are integer counts, and pump-specific maintenance history requires a rated pump. Derived efficiency, hazard, failure threshold, and maintenance lock cannot be authored as initial state. These validation rules and a bounded extreme-age hazard keep deliberately extreme fixtures numerically finite.

Pump efficiency is 1 through 80% of reference life, then falls linearly with equivalent age to a minimum of 0.2. The nominal requested flow and its electrical demand are allocated normally; useful flow is multiplied by efficiency. Actual draw is useful flow × `kw_per_flow` / efficiency. A failed pump or one locked for maintenance has zero demand and output. Availability and wear changes are committed before thermal integration, so current flow, engine constraints, and power accounting agree.

The illustrative bathtub hazard is a rate per actual operating hour, with independent early-life, baseline, and wear-out terms. It is not a survival probability, an MTBF rating, or a calibrated prediction. Cumulative `risk_exposure` integrates that rate while the pump runs; failure latches when it crosses a locally seeded exponential threshold. The threshold is sampled once at installation and again after wear-part replacement. Authored seeds preserve results across component renaming, ordering, independent runtimes, and different frame partitions. Runtime state includes the exposure, threshold, failed flag, replacement count, efficiency, and patch life. Reset reloads the same authored history and seed.

`maintenance_command(id, action) -> {accepted, reason, sequence}` submits `simulate_wear`, `patch`, `replace`, or `cancel` to the shared fixed-step command queue. Validity is checked both when queued and when applied. A command can be queued and subsequently rejected if earlier commands occupy the station, consume supplies, or reconnect the supply; the engineering log records that rejection. Maintenance commands reject paused or invalid simulations just like ordinary controls.

- `simulate_wear` is an explicit sandbox setup, loading 105% of rated equivalent age and at least that many lifetime hours. It does not silently age the rest of the ship.
- `patch` requires a functioning pump below 85% efficiency, an open upstream breaker, one patch kit, and 10 isolated seconds of work. It provides an efficiency floor of 85% for 100 running hours. It does not reduce age or accumulated failure risk.
- `replace` requires an open upstream breaker, one spare wear-part set, and 30 isolated seconds of work. It clears failure, patch, and exposure, renews the threshold, and resets wear-part age to zero. Assembly lifetime hours remain unchanged.
- `cancel` releases the station without refunding the supply consumed when work began.

Electrical isolation means an explicit open bus breaker on the component's resolved supply path. Zero demand, a zero source limit, or power starvation does not qualify. Reconnection holds job progress and keeps the pump unavailable; reopening a supply breaker permits work to resume. Completion never closes the breaker automatically. The other propulsion branch remains available according to its own connected equipment and shared resources.

For a pump in an explicit service circuit, repair additionally requires its primary coolant valve closed and any bypass it supplies closed. An incoming bypass can feed the circuit downstream of that isolation valve while the primary pump is repaired. Losing either electrical or coolant isolation holds the job. Tern's existing maintenance behavior is unchanged because it does not declare service circuits.

`maintenance_info(id)` returns detached UI data: `supported`, `running_hours`, `service_age_hours`, `rated_life_hours`, `efficiency`, `failure_rate`, `failed`, `patch_remaining_hours`, `job`, `job_remaining`, `job_duration`, `isolated`, `patches`, `spares`, `reason`, and `actions`. Each action entry contains `enabled` and a rejection `reason`. `reliability_profile(id)` returns ordered samples containing `age_hours`, `efficiency`, and `failure_rate`, computed by the same functions used in the simulation. The chart shows reference performance and hazard separately; colored performance bands are gameplay classifications, not statistical confidence envelopes.

Snapshots include a detached `maintenance` object with inventory and the current job, alongside each component's operating history. They remain a serialization boundary rather than a save/load feature. The current repair model has no crew agents, arbitrary crossfeeds, pressure safety, or fluid inventory; those require their own physical and operational rules.

## Player-installed coolant bypass

`scripts/simulation/coolant_bypass.gd` owns primary valves, one installed route, kit inventory, and installation/removal jobs. These are runtime state, not edits to the authored Resource. Both primary valves start open and no bypass is installed. Kestrel adds ordinary feeder buses for its pumps so isolating a pump does not require opening the main distribution bus.

Service circuit validation requires unique nonempty IDs, an inspectable primary pump, a nonempty member array of circulation consumers, an inspectable service member, and a finite positive reference flow. A pump or consumer belongs to at most one explicit circuit. Every native coolant output of a managed pump must be included in that circuit, and each member's native supplies must come from its declared primary pump. This prevents undeclared outlets from receiving unbudgeted donor flow. Kit capacity is finite and within 1e-6–1e12, inventory is a nonnegative bounded integer, and a positive inventory requires at least two service circuits. Authored connection IDs cannot use the reserved `__bypass:` prefix.

`bypass_command(action: Variant, payload: Variant = {}) -> {accepted, reason, sequence}` uses the shared fixed-step command queue. Payloads have exactly the fields below; types, finite values, supported endpoints, pause state, and current prerequisites are validated both at submission and application. Queued payloads and snapshots are detached copies.

| Action | Payload | Behavior |
| --- | --- | --- |
| `install` | `{source_id, circuit_id}` | Reserve a kit and start 10 seconds of work between different service circuits. |
| `remove` | `{}` | Start 10 seconds of work on the closed installed kit; return it to inventory on completion. |
| `cancel` | `{}` | Cancel work; refund a reserved installation kit or leave the existing closed kit fitted. |
| `open`, `close` | `{}` | Change the installed bypass valve. Opening requires the destination primary valve closed and an available donor pump. |
| `set_flow` | `{flow}` | Set requested diversion in the inclusive range 0–kit capacity. |
| `set_primary` | `{circuit_id, open: bool}` | Change a circuit's primary isolation valve. The destination primary cannot open against an open bypass. |

Fitting or removing a kit requires both endpoint pumps electrically isolated, both primary valves closed, and the bypass closed. Installation finishes with the kit closed. The single maintenance station is shared with pump repair: queued competing jobs are rechecked before any inventory is consumed. During bypass work both endpoint pumps are unavailable. Reconnecting power or reopening a primary valve holds work until isolation is restored; nothing automatically restores breakers or valves on completion.

Delivered diversion is `min(requested diversion, kit capacity, donor actual flow)`. With the donor's primary valve open, its own circuit receives only the remainder. With that valve closed, its own circuit receives zero. The model reports unused capability separately; it does not invent circulation through a closed valve. A pump with no open outlet has no demand or output. Its existing electrical supply, ramp, wear efficiency, and failure state constrain the available flow before it is allocated.

At Kestrel's emergency setting, B supplies 40 L/s: 24 to the core/radiator circuit and 16 to its engine circuit. The exchanger and radiator each observe that same 24 L/s serial circulation allocation. They do not each reserve another 24 L/s from B. This represents a complete paired supply/return kit, not a pressure network or conserved fluid volume. Opening a bypass never increases either pump's output capacity or electrical supply capacity.

`bypass_info(source_id = "", circuit_id = "")` returns detached panel data: `supported`, `capacity`, `kits`, `installed`, `source_id`, `circuit_id`, `open`, `requested_flow`, `delivered_flow`, `source_flow`, `source_remaining_flow` (actual delivery to the donor's native circuit), `available_remainder_flow`, `unallocated_flow`, `job`, `job_remaining`, `job_duration`, `reason`, `actions`, `circuits`, and `pumps`. Action entries contain `enabled` and a rejection reason. Circuit rows include their authored identity plus primary valve state, electrical isolation, primary/bypass/total delivered flow, active source, and valve actions. `coolant_pump_info(id)` exposes circuit membership, primary state, and work lock for equipment diagnostics.

`presentation_connections()` returns the current graph for all domains. Explicit coolant edges include `active`, `delivered_flow`, `circuit_id`, and `bypass`; fitted kits add edges from the donor to every destination circuit member. Closing a kit keeps its fitted edges visible but inactive; removal drops them. `coolant_connections()` and `coolant_connection_active(edge)` let diagnostics follow the route actually serving the equipment, while dependency links still expose fitted connections for inspection. The presenter and console refresh these links after runtime topology changes.

Snapshots include a detached `bypass` object with `primary_valves`, `kits`, `installed`, and `job`. Pause and inactive-ship sessions park work and queued commands. Reset restores native routing and the authored inventory. The console also retains uncommitted endpoint selections per ship while navigating to feeder and pump controls. Neither sessions nor installed modifications persist after app restart.

`tests/test_coolant_bypass.gd` covers validation, finite allocation, reduced donor capability, job interlocks and queue races, repair under bypass supply, removal/reuse, snapshots, reset, and renamed/reordered definitions. `tests/test_bypass_interface.gd` exercises the complete A/B loop through player controls, live schematic/dependency updates, navigation, modal input, and parked sessions. Add `-- --capture` to a graphical run of the interface test to save screenshots under `.tools/captures/`.
