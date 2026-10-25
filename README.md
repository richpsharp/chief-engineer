# Chief Engineer

A Godot prototype for exploring an operating starship through its engineering systems. The ship starts healthy and runs continuously. Change a setting, follow its effects through connected equipment, and restore the ship to normal operation.

The overview presents eight ship systems: Reactor, Power, Propulsion, Cooling, Life support, Radiation protection, Sensors, and Hull & compartments. **Power** and **Cooling** have detailed workspaces, equipment inspectors, and working controls. The other six currently provide summaries and basic load references; they do not yet have the same depth of simulation.

## Play

On this Windows checkout, double-click **play.cmd**. It uses the portable Godot engine in `.tools/godot/`, when available, or `godot.exe` / `godot4.exe` on your PATH.

For a fresh checkout:

1. Download the **standard edition of Godot 4.6** from [the official archive](https://godotengine.org/download/archive/4.6-stable/). No .NET SDK or Python is required.
2. Open Godot's project manager, choose **Import**, and select `project.godot` in this folder.
3. Open the project and press **F5** (Run Project).

The project uses the Compatibility renderer. The portable engine is a local convenience and is not tracked by Git.

## Explore the ship

- Select **Power** or **Cooling** from the overview to open its equipment workspace.
- Select a piece of equipment to see its readings, dependencies, and available controls.
- Use the breadcrumbs or **Back** to move between the overview, workspaces, and equipment.
- Follow equipment crosslinks to inspect a dependency in another system. A cooling problem may originate in its electrical supply.
- **Pause** freezes the simulation and operating controls so you can examine the current state. Resume to continue.
- **Reset** restores the healthy starting configuration.

Press **P** to pause or resume, and **Escape** to go back.

There is no countdown, win condition, or loss screen. Leaving the initial controls alone keeps the ship running normally. Equipment performance and recovery evolve over time as you experiment.

## Controls currently modeled

### Power

The reactor automatically supplies the demand it can meet, up to its configured capacity limit. That limit is available capacity, not a command to generate a fixed amount of power.

The main and auxiliary buses have breaker controls. The auxiliary bus also has a total power limit shared by its loads. Its healthy demand is **30 kW**: **18 kW** of base loads plus **12 kW** for cooling pump B. The normal auxiliary limit is **40 kW**.

### Cooling

Pump A normally runs at a flow setting of **24 L/s**, and pump B at **30 L/s**. Their delivered flow depends on available electrical power as well as the requested setting. Radiator deployment starts at **100%**.

Pump A also circulates coolant through the shared radiator. Stopping it prevents active heat rejection even with the radiator fully deployed; temperatures then respond to the heat still being produced.

The main-engine inspector in Cooling includes an engine command, initially **30%**. Actual engine performance is constrained by the cooling it receives. Power, flow, temperatures, and engine output provide different views of the same dependencies.

Temperature readings include their current rate of change in °C/min. Heat exchangers show the temperatures of both connected thermal masses. A temperature advisory reports the measurement, trend, and amount above the configured advisory level; changing that level does not change the simulation's heat flow or equipment output.

## A first experiment

1. Open **Power** and select the **auxiliary bus**. Observe its normal 30 kW demand against a 40 kW limit.
2. Lower its limit to **24 kW**. The 18 kW base load leaves only **6 kW** for pump B, half of its normal 12 kW supply.
3. Follow the cooling dependency or open **Cooling**, then inspect **pump B**. Its flow settles from **30** toward **15**.
4. Inspect the **main engine**. With its command still at 30%, reduced cooling limits its delivered output toward **15%**.
5. Restore the auxiliary bus limit to **40 kW** and watch the pump and engine recover gradually.

This is a way to learn the ship through cause and effect: the reduced engine output originates at a power-distribution setting. You can also change pump settings, radiator deployment, reactor capacity, or breakers and observe the resulting readings.

These are simplified gameplay relationships, not a real electrical or thermal engineering solver.

## How the prototype is built

- `scenes/main.tscn` is the starting scene.
- `ships/kestrel.tres` defines Kestrel's equipment, assemblies, connections, initial settings, views, and schematic layouts.
- `scripts/definitions/` contains the Resource schemas for reusable component types, component instances, assemblies, typed connections, and ships.
- `scripts/ship_simulation.gd` creates independent runtime state from a ship definition and advances its machinery in fixed 0.1-second steps. It owns command validation and physical calculations.
- `scripts/presentation/ship_presenter.gd` turns numerical runtime readings into labels, status explanations, conditions, and dependency links.
- `scripts/main.gd` builds the interface from the ship's view and equipment metadata. Controls send addressed commands; they do not directly change physical state.
- `tests/test_simulation.gd` checks the simulation rules.
- `tests/test_interface.gd` exercises scene navigation and control connections.
- `tests/test_architecture.gd` checks definition validation, runtime isolation, fixed-step behavior, and renamed/reordered copies of Kestrel.
- `tests/test_control_validation.gd` checks authored operating ranges and safe zero settings. The test suites share detached ship fixtures from `tests/ship_fixtures.gd`.

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

The electrical solver currently supports radial distribution with one power input per consumer. Load priority is authored data; equal priorities are ordered by stable component ID. It does not simulate electrical loops or crossfeeds. Coolant connections describe circulation capability, not pipe pressure or a conserved fluid inventory. Thermal behavior is a simplified heat-storage and transfer model. The battery remains an isolated reference component, and the summary departments are not detailed environmental simulations.

**Kestrel is the only playable ship included.** Tests use modified copies of its definition to verify the architecture; they do not add another ship or a ship-selection feature.

Start in `kestrel.tres` to change equipment configuration or connections, in component type parameters to tune behavior, and in the presenter/interface to change how readings are explained. The shared API is documented in [the component contract](docs/component-contract.md).

The older `tracer.py` and `fact-mod-example/` remain as earlier experiments and are not used by this Godot prototype.

## Run checks

With Godot on your PATH:

```powershell
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_architecture.gd
godot --headless --path . --script tests/test_control_validation.gd
godot --headless --path . --script tests/test_interface.gd
godot --headless --path . --quit-after 3
```

Or use this checkout's portable runtime:

```powershell
& ./.tools/godot/Godot_v4.6-stable_win64_console.exe --headless --path . --script tests/test_simulation.gd
```

A successful test run exits with code 0. Checks cover stable operation, equipment dependencies, reduced supply and recovery, pause, reset, interface interaction, component isolation, definition validation, and power accounting.
