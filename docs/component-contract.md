# Component implementation contract

This document describes the shared interfaces for the component refactor.

## Authored data (Resources)

- `scripts/definitions/component_type.gd`: `kind: String`, `ports: Dictionary` mapping port key to `{domain: String, direction: String}` (`in`/`out`), `defaults: Dictionary` for parameters, `controls: Array[Dictionary]` entries `{id, label, unit, min, max, default}`. Boolean breaker control uses `{id: "closed", label, kind: "toggle", default: true}`.
- `component_spec.gd`: `id`, `display_name`, `short_name`, `description`, `parent_id`, `definition: Resource`, `parameters: Dictionary`, `initial_settings: Dictionary`, `initial_state: Dictionary`, `inspectable: bool`. `config()` merges type defaults with instance parameters.
- `assembly_definition.gd`: `id`, `display_name`, `parent_id`, `ports: Dictionary` mapping exposed port to `{component, port}`. Aliases may point into nested assemblies; resolution must terminate at a leaf.
- `connection_definition.gd`: `id`, `from_component`, `from_port`, `to_component`, `to_port`, `capacity: float = -1` (unlimited). Domain inferred from resolved ports.
- `ship_definition.gd`: `schema_version=1`, `id`, `display_name`, `ambient_temperature=10`, `components: Array[Resource]`, `assemblies: Array[Resource]`, `connections: Array[Resource]`, `views: Array[Dictionary]`, `layouts: Dictionary`.
- Ship methods: `component(id) -> Resource`, `assembly(id) -> Resource`, `resolve_port(owner, port) -> Dictionary` returning `{component, port, domain, direction}` or `{}`, `resolved_connections() -> Array[Dictionary]` entries `{id, from_component, from_port, to_component, to_port, domain, capacity}`, `validate() -> Array[String]`, `view(id) -> Dictionary`, `workspace_for(component_id) -> String` (first workspace containing component).
- Default ship: `load("res://ships/kestrel.tres")`. Definitions are treated as immutable; runtime copies settings/state.

## Network conventions

- Kinds: `reactor`, `bus`, `pump`, `engine`, `load`, `heat_exchanger`, `radiator`, `coolant`, `battery`.
- Electrical ports: source/bus `power_out`; bus/load/pump/engine `power_in`, domain `power`.
- Pump `flow_out` to exchanger/engine/radiator `flow_in`, domain `coolant`. These carry circulation capability, not pressure-solved pipes. A pump can feed several consumers of its circuit without duplicating a fluid inventory.
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

## Runtime API

`ShipSimulation.new(optional_definition)`; default Kestrel. Properties `definition`, `components: Dictionary`, `paused`, `elapsed`, `events: Array[String]` (bounded to 50), `validation_errors: Array[String]`, `command_results: Array[Dictionary]` (bounded to 50), read-only `step_seconds=.1`.

Each component runtime has `spec`, `config: Dictionary`, `settings: Dictionary`, `state: Dictionary`. Common state `power`, `allocated_power`, `requested_power`; source/bus `draw`; pump `flow`, `target_flow`; engine `thrust`, `target_thrust`, `temperature`; reactor/coolant `temperature`; exchanger `heat_transfer`; radiator `heat_rejected`; heat producers `heat_generated`. Missing numeric state keys are read as zero by presentation.

Methods `tick(delta)`, `reset()`, `toggle_pause()`, `command(target_id, action, value) -> Dictionary` with `{accepted, reason, sequence}`; action matches control ID, toggle callers supply desired boolean. Invalid/paused commands rejected, valid commands queued and applied on next fixed step. `snapshot() -> Dictionary` returns a detached state/settings map for testing/saves. `totals() -> Dictionary` with `output`, `capacity`, `spare`, `heat_generated`, `heat_rejected`. Runtime owns physical calculations, command validation and committed readings, no UI formatting or hard-coded equipment IDs.

## Presentation API

`ShipPresenter.new(simulation)` in `scripts/presentation/ship_presenter.gd`. Methods `readings(id) -> Array[Array]`, `equipment_status(id) -> String`, `equipment_reason(id) -> String`, `system_summary(view_id) -> Dictionary {state,value,detail,tone}`, `conditions() -> Array[Dictionary]` entries `{code,text,system,equipment,cause_id}`, `links(id) -> Array[Dictionary]` entries `{system,equipment,label}`, `caption(id) -> String`. Derive dependencies from resolved connections; no named Kestrel IDs. Readings raw values remain runtime numeric; formatting only presenter.

Views: `{id,name,kind,summary_kind,description,detail,members}`. Kind workspace or summary. Summary kinds power/temperature/thrust/load/reactor. Members are leaf IDs for aggregation/navigation; departments may overlap. Layouts keyed by view ID: `{nodes: Dictionary}` maps leaf IDs to `Rect2`. Schematic edges derive from connections and the visible endpoints (no duplicated wiring lists). Thermal-only hidden coolant reservoir may be omitted from initial schematic.

Views may supply `nav_name` as a shorter sidebar label. Power summaries count network boundaries once even with nested member buses; multi-engine summaries report mean thrust. The heat strip reports active radiator rejection; passive thermal losses account for the remaining equilibrium heat loss.

Snapshots include schema version, definition ID, step count, fractional time accumulator, queued commands, and detached component settings/state. They are a serialization boundary, not a save/load UI. Incoming frame deltas are capped at 30 seconds to bound catch-up after suspension. Numerical thermal integration uses fixed 0.1-second explicit steps; conductance and heat-capacity tuning should stay within a stable regime. It is not an arbitrary-stiffness engineering solver.

Tests migrate to addressed component state/commands; no legacy named A/B getters. Only Kestrel is shipped in this issue. Mutated copies of its definition are permitted as test fixtures, not a second playable ship.

Control descriptors may specify `max_parameter` (e.g. `rated_power`, `max_flow`). Use `spec.controls()` for effective descriptors resolved against instance parameters, rather than accessing the type's raw list. Kestrel models six separate service loads and one hidden `coolant_reservoir`; main and auxiliary buses both expose capacity and breaker controls.
