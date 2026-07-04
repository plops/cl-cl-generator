# Walkthrough: Expanse Orbital Space Combat Simulator

This document provides a detailed walkthrough of the implementation, mathematical models, and controls for the **Expanse-style 2D Orbital Space Combat Simulator** (Example 08).

---

## 1. Core Architecture

The simulation is built by combining two dynamically generated sub-modules of the `cl-cl-generator` project:
1. **`pure-x11-gen`**: Communicates directly with the X11 server over a network socket to handle layout, canvas drawings, and event loop processing.
2. **`hpipm-cffi`**: Binds to the high-performance interior point optimal control solver to calculate real-time evasive trajectories.

```
       +---------------------------------------------+
       |           X11 Event Loop (run-gui)          |
       +---------------------------------------------+
              |                               |
          (Key Press)                      (Tick)
              v                               v
   Apply Manual Thrusters            Run Physics Update
              |                               |
              |                               v
              |                     Run Autopilot (MPC)
              |                               |
              +---------------+---------------+
                              |
                              v
                Propagate States (CW Model)
                              |
                              v
                  Re-render Canvas & GUI
```

---

## 2. 2D Relative Orbit Mechanics (Physics Engine)

We model the motion of all orbital bodies (the player ship *Rocinante*, the enemy gunship, torpedoes, and railgun slugs) relative to the docking station using **2D Hill-Clohessy-Wiltshire (CW) equations**.

In LEO orbit:
- The origin $(0, 0)$ is the docking port, moving in a circular orbit of radius $R_0$ with angular speed (mean motion) $n \approx 0.00113\text{ rad/s}$ (~90 minute orbit).
- The radial direction $x$ points away from the center of Earth.
- The along-track direction $y$ points tangent to the orbit.

The relative acceleration equations are:
$$\ddot{x} - 2n\dot{y} - 3n^2 x = u_x$$
$$\ddot{y} + 2n\dot{x} = u_y$$

We integrate these analytical equations discretely into a state transition matrix equation for a time step $dt = 0.05\text{ s}$:
$$x_{k+1} = A_d x_k + B_d u_k$$
where:
- State: $x = [x, y, v_x, v_y]^T$
- Control: $u = [u_x, u_y]^T$ (thrust acceleration vector)

Because of the Coriolis cross-coupling terms ($2n\dot{y}$ and $-2n\dot{x}$), unguided railgun slugs fired at high velocity follow curved orbital drift paths on the player's screen, rather than straight lines.

---

## 3. Real-Time Trajectory Optimization (MPC)

The player ship's autopilot uses Model Predictive Control (MPC) to find the optimal thrust path to the docking target.

### Cost Function
The MPC solves a Quadratic Program (QP) to minimize:
- **Target Distance**: Penalty weights on $x$ and $y$ positions to drive the ship toward the hangar.
- **Velocity**: Penalty on $v_x$ and $v_y$ to ensure the ship approaches the hangar at safe docking speeds.
- **Fuel/Control Effort**: Penalty on inputs $u_x$ and $u_y$ to conserve thruster propellant.
- **Terminal State**: 10x higher penalty on the final stage of the horizon $N = 15$ to guarantee convergence.

### Autopilot Safe vs. High-G Bounds
- **Safe Mode**: Control constraints set to $-30\text{ m/s}^2 \le u_i \le 30\text{ m/s}^2$ (~3 G).
- **Emergency Mode**: Constraints relaxed to $-150\text{ m/s}^2 \le u_i \le 150\text{ m/s}^2$ (~15 G) to allow high-g maneuvers, accumulating crew strain.

### Dynamically Linearized Collision Avoidance
To avoid obstacles (torpedo coordinates and railgun paths), we enforce general linear constraints:
$$lg \le C x_k \le ug$$
Because circular exclusion bounds $(x - x_{obs})^2 + (y - y_{obs})^2 \ge R^2$ are non-convex, we linearize them at each step around the ship's current position $(x_s, y_s)$:
Let $d_x = x_s - x_{obs}$ and $d_y = y_s - y_{obs}$, and normal components $n_x = d_x / d_{dist}$, $n_y = d_y / d_{dist}$.
We enforce:
$$n_x x + n_y y \ge n_x x_{obs} + n_y y_{obs} + R_{margin}$$
This creates a dynamic linear half-space constraint at each stage $k$ pushing the ship's predicted trajectory away from the danger zone.

---

## 4. Weapon & Combat Systems

1. **Point Defense Cannon (PDC)**: The ship checks for torpedoes inside a 45-meter range bubble. It fires a flak curtain (green line vectors) that intercepts and destroys the nearest torpedo.
2. **Subsystems Targeting**: The player can target specific components of the enemy cruiser:
   - **Reactor**: Neutralizes the ship and forces the crew to escape.
   - **Fuel**: Disables the enemy's thrusters, leaving it to drift helplessly in orbit.
   - **Weapons**: Prevents the enemy from launching further attacks.
   - **Radar**: Blinds the enemy, stopping its autopilot tracking and weapon locking.
3. **The Juice**: Managing high-g burns requires injecting stimulant syringes to clear the crew strain bar before they lose consciousness and disable autopilot systems.
