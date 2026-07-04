# Task Summary: 08_expanse_combat

## Goal
Devise and implement a 2D space combat simulation game demonstrating Model Predictive Control (MPC) optimal trajectory planning ([06_hpipm_cffi](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi)) and raw socket-based X11 visual rendering ([07_pure_x11](file:///workspace/src/cl-cl-generator/example/07_pure_x11)) in Common Lisp.

---

## Key Features Implemented

1. **2D Relative Orbital Physics**:
   - Implemented analytical Clohessy-Wiltshire (CW) discretization equations for LEO space flight.
   - Unguided railgun slugs follow Coriolis-curved orbital paths relative to the spacecraft.
   - Steerable torpedoes track the ship using Proportional Navigation, draining fuel budgets before drifting.
2. **Dual-MPC Autopilot**:
   - **Player ship**: Autonomous navigation using a 15-stage horizon solver with LQR costs, G-force limits, and dynamic half-space collision-avoidance constraints.
   - **Enemy ship**: Maneuvers dynamically under its own MPC to follow and maintain tactical range to fire on the player.
3. **Subsystems Combat HUD**:
   - Targetable subsystems: Fuel, Weapons, Radar, and Reactor.
   - Damaging the reactor triggers a safe shutdown and crew escape pod launch.
   - Disabling fuel cuts the thrusters; disabling radar blinds the tracking system; disabling weapons stops firing.
4. **Juice & G-Strain Mechanics**:
   - Autopilot can run in "Safe Mode" ($3\text{ G}$) or "High-G Burn" ($15\text{ G}$) which increases maneuverability but accumulates strain on the crew.
   - Players must monitor and inject "Juice" syringes to prevent the crew from passing out.
5. **X11 GUI Dashboard**:
   - Created canvas drawing scripts mapping ship coordinates, predicted paths, weapon vectors, and PDC ranges.
   - Implemented sidebar buttons, check-boxes, and health status indicators.
6. **GUI Event Loop Extension**:
   - Extended the X11 socket client's event loop (`pure-x11-gen/event-loop`) to forward unhandled keyboard events to the application update loop, enabling WASD keyboard steering.
7. **Git Integration**:
   - Staged all files warning-free and successfully recorded the git commit locally (`2e0857a72658b4e3618aaafa1181e47edb06db90`).
