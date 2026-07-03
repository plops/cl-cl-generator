# Implementation Plan: Spacecraft Docking MPC Example with Terminal Visualization

We will extend the high-level Lisp interface generator (`gen02.lisp`) to support multi-variable control bounds and implement a closed-loop **3D Spacecraft Rendezvous and Docking** simulation with an **ASCII-art trajectory renderer** in the terminal.

## Proposed Changes

### High-Level API
#### [MODIFY] [gen02.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/gen02.lisp)
- Extend `hpipm-high.lisp` by adding:
  - `set-control-bounds-stage`: Sets bounds for multiple input channels at a specific stage.
  - `set-control-bounds-all-stages`: Sets bounds for multiple input channels uniformly across all stages.
- Export these functions in the `hpipm` package.
- Include `:file "spacecraft-demo-high"` in `hpipm.asd` components.
- Add the generation template for `spacecraft-demo-high.lisp`.

### Demos
#### [NEW] [spacecraft-demo-high.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/spacecraft-demo-high.lisp) (via generator)
- Implement a closed-loop 3D Spacecraft Rendezvous and Docking simulation:
  - **Dynamics**: Hill-Clohessy-Wiltshire (CW) equations (6 states $[x, y, z, v_x, v_y, v_z]^T$, 3 control inputs $[u_x, u_y, u_z]^T$).
  - **Orbit Model**: LEO orbit with mean motion $n = 0.001107 \, \text{rad/s}$ and sampling time $dt = 10.0$ seconds.
  - **Constraints**:
    - Hard control bounds: $-0.05 \le u_i \le 0.05 \, \text{m/s}^2$ for all 3 axes.
    - 3D Approach corridor (general constraints): $|x| \le 0.5 |y|$ and $|z| \le 0.5 |y|$.
    - Softened corridor constraints for robustness.
  - **Simulation**: Closed-loop execution for 30 steps. In each step, solve the MPC problem for the current state, apply the first control input $u_0$, propagate using the analytical discrete-time dynamics, and repeat.
  - **ASCII Visualization**: Render the $y-x$ (along-track vs. radial) plane in the terminal, showing the docking cone boundaries (e.g. using `\` and `/`), the docking port at the apex `(0, 0)`, and the spacecraft's path (`o` for history, `*` for current position).
  - **Detailed Output**: Print a tabular summary of the state, inputs, and slack variables.

---

## Technical Design

### 1. ASCII Trajectory Renderer
We will implement an ASCII grid renderer.
- Horizontal axis: $y$ (along-track), columns from $-150$ to $0$ meters.
- Vertical axis: $x$ (radial offset), rows from $-80$ to $+80$ meters.
- The docking corridor boundaries $x = \pm 0.5 y$ will be drawn as lines of `.` or `/` and `\`.
- The spacecraft positions will be plotted as `o` (historical trajectory) and `*` (current position).

```
   +--------------------------------------------------+
   | \                                              / |
   |  \                                            /  |
   |   \                                          /   |
   |    \                   o                    /    |
   |     \               o                      /     |
   |      \           o                        /      |
   |       \       o                          /       |
   |        \   *                            /        |
   |         \                              /         |
   |          \                            /          |
   |           \                          /           |
   |            \                        /            |
   |             \                      /             |
   |              \                    /              |
   |               \                  /               |
   |                \                /                |
   |                 \              /                 |
   |                  \            /                  |
   |                   \          /                   |
   |                    \        /                    |
   |                     \      /                     |
   |                      \    /                      |
   |                       \  /                       |
   |                        \/                        | [Target Docking Port]
   +--------------------------------------------------+
```

---

## Verification Plan

### Automated Tests
1. **Run the generator**:
   ```bash
   sbcl --load gen02.lisp --eval '(quit)'
   ```
2. **Execute the spacecraft demo**:
   ```bash
   sbcl --noinform --non-interactive \
        --eval '(push "/workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/" asdf:*central-registry*)' \
        --eval '(ql:quickload :hpipm)' \
        --load "/workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/spacecraft-demo-high.lisp" \
        --eval '(hpipm-spacecraft-demo:run-spacecraft-demo)'
   ```

### Manual Verification
- Confirm convergence (status 0 at each step).
- Confirm that the printed trajectory stays inside the corridor and reaches the docking port.
- Visually inspect the terminal ASCII plot.
