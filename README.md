# Chief Engineer

A Godot prototype for exploring operating starships through their engineering systems. Kestrel and Tern start healthy and run continuously. Change a setting, follow its effects through connected equipment, and restore the ship to normal operation.

The overview presents eight ship systems: Reactor, Power, Propulsion, Cooling, Life support, Radiation protection, Sensors, and Hull & compartments. **Power** and **Cooling** have detailed operating workspaces. **Connections** shows the whole ship's electrical and cooling relationships and opens equipment in the matching workspace. The other departments open a local equipment/connection view with the same inspector and any available controls; they do not yet have the same depth of simulation.

## Play

On this Windows checkout, double-click **play.cmd**. It uses the portable Godot engine in `.tools/godot/`, when available, or `godot.exe` / `godot4.exe` on your PATH.

For a fresh checkout:

1. Download the **standard edition of Godot 4.6** from [the official archive](https://godotengine.org/download/archive/4.6-stable/). No .NET SDK or Python is required.
2. Open Godot's project manager, choose **Import**, and select `project.godot` in this folder.
3. Open the project and press **F5** (Run Project).

The project uses the Compatibility renderer. The portable engine is a local convenience and is not tracked by Git.

## Explore the ship

- Use the **Ship** selector at the top to switch between **Kestrel** and **Tern**. Each keeps its settings, operating state, and pause state for this session; only the selected ship advances. Switching returns to its overview.
- The sidebar contains **Ship overview**, **Connections**, **Power**, and **Cooling**. Open other departments from their overview cards. **Reactor**, for example, selects the reactor and exposes its controls immediately.
- Open **Connections** to trace the full network. Its **Power** layer shows the reactor, intermediate buses, engines, pumps, and service loads. Its **Cooling** layer shows circulation and heat transfer, including the reactor, exchanger, shared coolant, engines, and radiator. Clicking a component opens it in the layer's operating workspace; **Back** restores the map and its focus.
- Select equipment in the diagram to see operating controls on its selected block and in the inspector. Both control the same machinery and show committed settings.
- Ordinary equipment selection and dependency links keep the current view. Selecting pump B in Power does not send you to Cooling. The inspector's explicit **Power** and **Cooling** shortcuts retain the selected equipment while changing networks. **Connections ↗** opens the whole-ship map with that equipment highlighted.
- Compact endpoints expose engines in the operating Power schematic and the reactor in Cooling. Their labelled destination links open the related operating workspace without issuing a machinery command.
- The workspace equipment list also opens equipment that has no schematic placement or connections.
- Use the breadcrumbs or **Back** to move between the overview, workspaces, and equipment.
- Follow **Connected equipment** links to inspect dependencies in place. A cooling problem may originate in an electrical feeder, whose controls are available in the same inspector.
- Supported pumps show routine maintenance actions in the inspector. Expand **Service history & reliability** for charts, operating history, and the worn-pump sandbox action.
- **Pause** freezes the simulation and operating controls so you can examine the current state. Resume to continue.
- **Reset ship** restores the selected ship's healthy starting configuration. The other ship keeps its state. Closing the app ends both sessions.

Press **P** to pause or resume. **Escape** leaves bypass editing or collapses expanded service details first; otherwise it goes back.

There is no countdown, win condition, or loss screen. Leaving the initial controls alone keeps the ship running normally. Equipment performance and recovery evolve over time as you experiment.

The connection map distinguishes electrical supply, coolant circulation, heat transfer, and fitted bypasses. Inactive physical connections remain visible. Direction markers describe the authored connection relationship; heat can reverse as temperatures change. Life support currently has an electrical load only, so it appears in Power without an invented connection to the exchanger. Its map entry opens read-only power telemetry. The shared coolant similarly exposes its own temperature without adding a control that the model does not have.

| Ship | Engines at cruise | Buses / pumps | Cruise draw / capacity |
| --- | --- | --- | --- |
| Kestrel | One at 30% | 4 / 2 | 152 / 200 kW |
| Tern, a twin-engine utility ship | Two at 20% each | 5 / 3 | 144 / 220 kW |

## Controls currently modeled

### Power

The reactor automatically supplies the demand it can meet, up to its configured capacity limit. That limit is available capacity, not a command to generate a fixed amount of power.

Kestrel's main and auxiliary buses have breaker controls. Each pump also has a dedicated feeder breaker, so isolating pump A leaves the main bus and its other loads connected. The auxiliary bus has a total power limit shared by its loads. Its healthy demand is **30 kW**: **18 kW** of base loads plus **12 kW** for cooling pump B. The normal auxiliary limit is **40 kW**.

A selected pump exposes its flow request and upstream feeder breaker together. Kestrel's pumps also expose their primary coolant valves. **Zero requested flow**, **electrical isolation**, and **coolant isolation** are separate actions. Their controls are available on the selected diagram block and in the inspector, including while viewing Cooling.

Tern has a shared distribution trunk and separate port and starboard drive buses. Each drive includes a dedicated pump feeder: opening that feeder cuts its coolant pump's power while leaving the engine's electrical feed connected.

Tern's core pump uses the shared main trunk. Its supply control names that trunk and marks it as shared: opening it disconnects every downstream load, including both drives.

### Cooling

Kestrel's pump A normally runs at a flow setting of **24 L/s**, and pump B at **30 L/s**. Their delivered flow depends on available electrical power as well as the requested setting. Radiator deployment starts at **100%**.

Pump A normally circulates coolant through the core exchanger and shared radiator. Stopping it prevents active heat rejection unless a bypass supplies that circuit. Temperatures respond to the heat still being produced.

Kestrel's main-engine inspector in Cooling includes an engine command, initially **30%**. Actual engine performance is constrained by the cooling it receives. Power, flow, temperatures, and engine output provide different views of the same dependencies.

Tern's three pumps each start at **20 L/s**. The port and starboard pumps serve their own engines, initially at **20%** thrust each. The core pump serves the reactor exchanger and shared radiator. Both engines reject heat into the shared coolant reservoir.

Temperature readings include their current rate of change in °C/min. Heat exchangers show the temperatures of both connected thermal masses. A temperature advisory reports the measurement, trend, and amount above the configured advisory level; changing that level does not change the simulation's heat flow or equipment output.

## Kestrel experiment

1. Open **Power** and select the **auxiliary bus**. Observe its normal 30 kW demand against a 40 kW limit.
2. Lower its limit to **24 kW**. The 18 kW base load leaves only **6 kW** for pump B, half of its normal 12 kW supply.
3. Select **pump B** in the Power diagram or follow the feeder's equipment link. Its inspector stays in Power, and flow settles from **30** toward **15**. Open **Cooling** to see the full cooling network.
4. Inspect the **main engine**. With its command still at 30%, reduced cooling limits its delivered output toward **15%**.
5. Restore the auxiliary bus limit to **40 kW** and watch the pump and engine recover gradually.

This is a way to learn the ship through cause and effect: the reduced engine output originates at a power-distribution setting. You can also change pump settings, radiator deployment, reactor capacity, or breakers and observe the resulting readings.

These are simplified gameplay relationships, not a real electrical or thermal engineering solver.

## Install a coolant bypass on Kestrel

Kestrel carries one reusable **24 L/s bypass kit**, initially uninstalled. Open **Cooling → Install / inspect bypass** to select service couplings on the live schematic. The connection uses the right-hand inspector, leaving equipment and flow visible throughout planning, fitting, and operation.

Try keeping the core cool while repairing pump A:

1. Optionally select **Pump A**, expand **Service history & reliability**, and choose **Try worn-pump condition** to create a repair need. Collapse the details when finished.
2. Choose **Install / inspect bypass**, click pump B's **Outlet coupling**, then the heat exchanger's **Circuit coupling** for the core/radiator circuit. An amber proposed route appears. The connection inspector also provides endpoint selectors for keyboard use.
3. Select A and B in turn. Use their **Feeder** controls to open **Pump A feed** and **Pump B feed**, and close each **Primary coolant valve**. These controls work directly on the blocks or in the inspector. The main and auxiliary buses can stay on. Installation briefly interrupts both pumps, including engine cooling.
4. Click **Proposed bypass · inspect / fit** to return to the connection inspector and choose **Install kit**. Its prerequisites explain any missing isolation. After 10 simulated seconds, the kit is fitted with its bypass valve closed. Installation and pump repair share one work station.
5. Open B's primary coolant valve, then select the bypass badge and choose **Open bypass valve**. Leave A's primary valve closed. Select B, reconnect its feeder, and raise its flow request to **40 L/s**.
6. At full diversion, B supplies **24 L/s** to the core/radiator circuit and **16 L/s** to its engine circuit. The engine settles at **16%** instead of its requested 30%. The exchanger and radiator share one circulation flow; they do not each consume another 24 L/s.
7. Select A and use its inline **Field patch** or **Replace wear parts** action. A stays electrically isolated with its primary valve closed while B supplies cooling. Work progress and the functioning network remain visible; life support stays powered.
8. After replacement, select the bypass badge and close its valve. Reopen A's primary valve, reconnect **Pump A feed**, and return B's request to **30 L/s**. The normal 152 kW cruise point recovers. A temporary patch leaves A at 85% efficiency: its 24 L/s request delivers 20.4 L/s, so allow for that reduced cooling before ending backup operation.
9. The fitted kit can stay closed for another emergency. To remove it, isolate both pumps and close both primary valves again, then select the bypass badge and choose **Remove & recover kit**. After 10 seconds, the kit returns to inventory. Restore the primary valves and feeders afterward.

Requested diversion, actual delivery, and each circuit's remaining flow are shown together. A worn or underpowered donor delivers less, and diverting more flow leaves less for its own circuit. The kit enforces its rating; there is no overload override or trip model yet. Click a fitted bypass line or its badge to inspect the connection. Green schematic lines and equipment links follow the installed connection, including after switching away from and back to the ship.

The kit represents paired supply/return connections and isolation fittings. This first version models circulation budgets and safe work states, without pipe pressure, drainage, or coolant inventory. Installation choices and work are retained for this app session; reset restores the uninstalled kit.

## Tern experiment

1. Choose **Ship: Tern**, open **Cooling**, and select **Port pump**.
2. Use its **Feeder** control on the selected block or inspector to isolate the pump. The port engine's electrical branch remains connected.
3. Watch the adjacent **Port engine** lose thrust as cooling stops. The starboard engine continues at 20%. Select either engine to inspect it without leaving Cooling.
4. Select the port pump and reconnect its feeder. Watch the pump and engine recover gradually to cruise.
5. Repeat with **Starboard pump** to test the other branch. The same feeder breakers can also be selected and operated in Power.

For a shared-system experiment, reduce the utility reactor's capacity to **100 kW**. Services and pumps retain priority; the port engine receives enough power for 18% thrust and the starboard engine stops. Reset ship restores healthy cruise. Closing the shared radiator instead warms both engines and the common coolant.

## Pump service life and maintenance

Equipment keeps an operating-hour counter. Pumps also have an authored reference service life and a separate, load-weighted wear-part service age. Tern's pumps begin with 1,000 operating hours against a 10,000-hour reference rating; they still start at full efficiency. Normal cruising does not require repeated maintenance clicks.

Select a pump and expand **Service history & reliability** in its inspector to compare estimated failure rate and expected flow efficiency against service age. Routine repair actions are available above those details; no separate maintenance screen is required. The bathtub curve represents failure risk per operating hour; the performance chart has normal, degraded, and severe-loss bands. These are illustrative gameplay curves, not manufacturer predictions, confidence intervals, or guaranteed expiry dates. The current-age marker follows equivalent wear-part hours: heavy operation ages them faster than the actual clock. Replacing them does not erase the assembly's lifetime running hours.

Try this on Tern:

1. Open **Cooling → Port pump**, expand **Service history & reliability**, and choose **Try worn-pump condition**. This explicit sandbox action gives the pump a worn service history immediately. Collapse the details to return to the compact repair controls.
2. Compare nominal requested flow, delivered flow, electrical draw, and port-engine output. The starboard drive continues operating normally. Raising the pump request can compensate for wear, at the cost of more power and faster wear.
3. Isolate **Port pump feed** with the selected pump's **Feeder** control. Selection stays on the pump in Cooling. A zero flow request or lack of spare reactor capacity is not electrical isolation.
4. Use the inspector's **Field patch** or **Replace wear parts** action. The ship has three patch kits and two replacement spares, with one maintenance job at a time. Its progress is visible alongside the network.
5. A patch takes 10 simulated seconds and provides limited capability for 100 operating hours. Replacing wear parts takes 30 simulated seconds, restores efficiency, and resets wear-part age. Supplies are spent when work starts; cancelling does not refund them.
6. Close the feeder after work finishes and observe the pump and engine recover. The other drive remains available throughout the repair.

Reconnecting a pump during maintenance holds the job and keeps the pump unavailable until isolation is restored. On Kestrel, maintenance also requires the pump's primary coolant valve closed and any bypass it supplies closed; an incoming bypass from the other pump can keep its circuit running. Pause freezes work; an unselected ship's work remains parked. Reset restores its authored history, machinery, and supplies. Current sessions are not saved when the app closes.

Failures are repeatable for the same authored seed and operating history. Their probability accumulates with operating time and the age-dependent hazard; a failed pump needs replacement. A temporary patch improves output but does not rejuvenate its worn parts or remove their failure risk.

The lifetime distinction is inspired by [bearing life ratings](https://www.jtekt.co.jp/products/bearing/en/support/bearing-knowledge/5-2000.html) and [NIST's explanation of the bathtub failure-rate curve](https://www.itl.nist.gov/div898/handbook/apr/section1/apr124.htm). The values and repair durations here are authored for play. Tern demonstrates independent propulsion branches; Kestrel demonstrates installing a shared-capacity coolant bypass. Electrical crossfeeds, pressure, and conserved coolant inventory remain future extensions.

## How the prototype is built

- `scenes/main.tscn` is the starting scene.
- `ships/kestrel.tres` defines Kestrel's equipment, assemblies, connections, initial settings, views, and schematic layouts.
- `ships/tern.tres` defines Tern using the same equipment types and domain models. `scripts/ship_catalog.gd` lists the selectable definitions.
- `scripts/definitions/` contains the Resource schemas for reusable component types, component instances, assemblies, typed connections, and ships.
- `scripts/ship_simulation.gd` creates independent runtime state from a ship definition and advances its machinery in fixed 0.1-second steps. It owns command validation and physical calculations.
- `scripts/simulation/maintenance_model.gd` owns operating history, pump wear and failure risk, repair supplies, and maintenance jobs.
- `scripts/simulation/coolant_bypass.gd` owns circuit isolation, the installed route, finite flow allocation, kit inventory, and installation/removal work. `scripts/presentation/coolant_bypass_panel.gd` presents its controls and prerequisites.
- `scripts/presentation/ship_presenter.gd` turns numerical runtime readings into labels, status explanations, conditions, and dependency links.
- `scripts/presentation/connection_map.gd` lays out the complete runtime graph by domain, including read-only service loads and shared coolant. It emits inspection requests; it never commands or advances equipment.
- `scripts/presentation/equipment_controls.gd` supplies the same addressed controls to selected schematic blocks and inspectors. `maintenance_panel.gd` is an inline repair section with expandable history/charts; `coolant_bypass_panel.gd` is the connection inspector.
- `scripts/main.gd` builds the interface from the ship's view and equipment metadata. Controls send addressed commands; they do not directly change physical state.
- `tests/test_simulation.gd` checks the simulation rules.
- `tests/test_interface.gd` exercises scene navigation and control connections.
- `tests/test_architecture.gd` checks definition validation, runtime isolation, fixed-step behavior, and renamed/reordered copies of Kestrel.
- `tests/test_control_validation.gd` checks authored operating ranges, labels, and safe zero settings.
- `tests/test_power_ramp.gd` checks allocation diagnostics when pumps ramp after their engines; `tests/test_cooling_diagnostics.gd` checks diagnosis across multiple coolant supplies. The test suites share detached ship fixtures from `tests/ship_fixtures.gd`.
- `tests/test_thermal_connections.gd` checks thermal connection readings and schematic activity for exposed reservoirs, multiple inlets, and stopped or reversed heat transfer.
- `tests/test_tern.gd` checks sustained healthy cruise and the two independent propulsion branches. `tests/test_ship_selection.gd` exercises selection, retained sessions, both ships' navigation, and the Tern experiment through the console.
- `tests/test_maintenance.gd` checks lifetime accounting, wear, repair safety, and repeatable failures. `tests/test_maintenance_interface.gd` exercises inline repair, expanded service-life details, and narrow chart/value layouts.
- `tests/test_coolant_bypass.gd` checks installation, isolation, shared flow, donor limits, job conflicts, restoration, inventory, and independent runtime state. `tests/test_bypass_interface.gd` performs the complete pump A/B repair loop through the player controls and checks live schematic links.
- `tests/test_console_consistency.gd` checks direct department inspection, selection without view changes, synchronized node/inspector controls, input handling, and equipment/control geometry on both ships.
- `tests/test_connection_map_model.gd` checks domain-aware network data and navigation, including renamed definitions and changing bypass topology. `tests/test_connection_navigation.gd` checks pointer/keyboard map navigation, Back context, read-only telemetry, live connection activity, and both ships' map geometry.

### Components, ports, and assemblies

A component type defines its behavior, parameters, controls, and typed ports. A component instance gives that type a stable ID, a name, parameter overrides, and initial settings/state. Each runtime copies that data, so two simulations using the same authored ship do not share mutable machinery state.

Connections join compatible output and input ports in one of three domains:

| Domain | What the connection carries |
| --- | --- |
| Power | Electrical supply and allocated demand, subject to source and bus limits. |
| Coolant | A pump's circulation capability available to connected equipment. |
| Thermal | Heat transferred between equipment, coolant storage, and heat rejection. |

Assemblies group equipment and expose named ports that resolve to internal components, including through nested assemblies. Equipment inspection follows the resolved connections. Definitions are validated before a runtime can operate; duplicate IDs, missing endpoints, incompatible ports, and unsupported cycles are rejected.

Controls address a component ID and control ID, such as an auxiliary bus's `limit`. Accepted commands are queued and applied at the next simulation step. Invalid values and commands submitted while paused are rejected. Inspectors show committed readings rather than treating a requested setting as an instantaneous physical result.

The electrical solver currently supports radial distribution with one power input per consumer. Load priority is authored data; equal priorities are ordered by stable component ID. It does not simulate electrical loops or crossfeeds. Coolant connections describe circulation capability, not pipe pressure or a conserved fluid inventory. Ships can opt into authored coolant circuits and service couplings: runtime bypasses divide a donor's available circulation between circuits without modifying the ship Resource. Thermal behavior is a simplified heat-storage and transfer model. The battery remains an isolated reference component, and the summary departments are not detailed environmental simulations.

**Kestrel and Tern are playable ship definitions.** Tern adds equipment and topology entirely as data: five nested buses, three pumps, two engines, and a shared thermal plant. It required no changes to equipment behaviors, network solvers, or the presenter. The shared console adds a catalog-driven selector and retains independent runtimes for the selected ships.

Start in a ship's `.tres` file to change equipment configuration or connections, in component type parameters to tune behavior, and in the presenter/interface to change how readings are explained. Register additional playable definitions in `ship_catalog.gd`. The shared API is documented in [the component contract](docs/component-contract.md).

The older `tracer.py` and `fact-mod-example/` remain as earlier experiments and are not used by this Godot prototype.

## Run checks

With Godot on your PATH:

```powershell
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_architecture.gd
godot --headless --path . --script tests/test_control_validation.gd
godot --headless --path . --script tests/test_power_ramp.gd
godot --headless --path . --script tests/test_cooling_diagnostics.gd
godot --headless --path . --script tests/test_thermal_connections.gd
godot --headless --path . --script tests/test_tern.gd
godot --headless --path . --script tests/test_ship_selection.gd
godot --headless --path . --script tests/test_maintenance.gd
godot --headless --path . --script tests/test_maintenance_interface.gd
godot --headless --path . --script tests/test_coolant_bypass.gd
godot --headless --path . --script tests/test_bypass_interface.gd
godot --headless --path . --script tests/test_interface.gd
godot --headless --path . --script tests/test_console_consistency.gd
godot --headless --path . --script tests/test_connection_map_model.gd
godot --headless --path . --script tests/test_connection_navigation.gd
godot --headless --path . --quit-after 3
```

Or use this checkout's portable runtime:

```powershell
& ./.tools/godot/Godot_v4.6-stable_win64_console.exe --headless --path . --script tests/test_simulation.gd
```

A successful test run exits with code 0. Checks cover stable operation, equipment dependencies, reduced supply and recovery, pause, reset, interface interaction, component isolation, definition validation, and power accounting.
