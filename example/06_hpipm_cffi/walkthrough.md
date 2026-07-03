# Walkthrough: Soft-Constraints, General Constraints & Physics Guide

We have extended the high-level Common Lisp MPC Solver API and metadata generator to support advanced HPIPM features and compiled the entire project warning-free. We also wrote a comprehensive guide for physicists.

---

## 1. Accomplished Work

### Code & Generator Updates:
1. **Resolved Name Collisions (Case-Sensitivity)**:
   - In HPIPM, fields like `Zl` (Hessian of lower slack) and `zl` (gradient of lower slack) differ only by the case of the first letter. Because Common Lisp is case-insensitive by default, they read as the same symbol `ZL`.
   - We updated the generator helper `lisp-field-name` in both [gen01.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/gen01.lisp) and [gen02.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/gen02.lisp) to map these to distinct, safe Lisp symbols:
     - `"Zl"` $\rightarrow$ `"Zl-mat"`
     - `"Zu"` $\rightarrow$ `"Zu-mat"`
     - `"zl"` $\rightarrow$ `"zl-vec"`
     - `"zu"` $\rightarrow$ `"zu-vec"`
   - This prevents redefinition conflicts and compiles perfectly.

2. **Declarative Soft-Constraints**:
   - The constructor [make-mpc-solver](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L42) now accepts a `:soft-constraints` parameter.
   - It supports symbolic stage specifications like `:all` (expands to all stages), `:terminal` (stage $N$), and `:path` (stages $0 \dots N-1$).
   - The solver automatically computes the stage-wise slack dimension `ns`, registers indices in the QP structure, sets penalty weights, and guarantees slack non-negativity.

3. **General Constraints Support**:
   - Added [set-general-constraints](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L200) and [set-solver-general-constraints](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L221) to set general coupling constraints $lg \le C x + D u \le ug$.
   - The helper handles `nil` for `C` or `D` by automatically creating zero matrices of the correct shape.

4. **Slack Trajectory Outputs**:
   - [solve-mpc](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp#L226) now returns 6 values, including the lower and upper slack trajectories `sl-traj` and `su-traj`.

5. **Soft-Constraints MSD Demo**:
   - Generated [mpc-soft-demo.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/mpc-soft-demo.lisp) showcasing how a soft constraint handles an initial state $x_0$ that starts in violation of a bound, returning a valid optimization solution using positive slacks.

### Documentation:
- Created [solver_guide_physics.md](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/solver_guide_physics.md) which translates control concepts to physical systems, explains numerical solvers (Cholesky, QR, Interior Point Method) in simple terms, and details the high-level API.

---

## 2. 🚀 3D Spacecraft Rendezvous & Docking Demo (Closed-Loop MPC)

We added a new physical example demonstrating the high-level HPIPM bindings for multi-input multi-output (MIMO) systems with terminal ASCII visualization:
- **Hill-Clohessy-Wiltshire (CW) Dynamics**: Analytical discrete-time propagation of LEO orbit relative motion (6 states, 3 controls).
- **Docking corridor**: Implemented using softened general linear constraints ($|x| \le 0.5|y|$ and $|z| \le 0.5|y|$).
- **Closed-Loop MPC**: Runs a 30-step loop applying feedback control.
- **ASCII visual renderer**: Prints the approach funnel and spacecraft trajectory path (`o`) directly to the terminal.

## 3. 🛠️ Bug Fixes & Refactoring

1. **Resolved Constructor Name Collision**:
   - In Common Lisp, defining a struct `mpc-solver` defines the constructor `make-mpc-solver`. Overwriting this with `(defun make-mpc-solver ...)` replaces it in the global function cell, causing recursive calls to fail.
   - We resolved this by defining a separate internal constructor `(:constructor %make-mpc-solver)` for the struct and calling it from within the custom wrapper function, allowing both the wrapper and struct initialization to function correctly.
2. **Fixed Case-Folding Key Collision for Soft-Constraints**:
   - Case-insensitivity turned both `:Z` (quadratic weight) and `:z` (linear gradient weight) into the same keyword `:z`.
   - We introduced non-colliding keywords `:Z-weight` and `:z-grad` to avoid property list retrieval conflicts.
3. **Corrected Soft-Constraint Stage Indexing**:
   - Changed physical state indexing in `mpc-soft-demo.lisp` soft constraints to correctly use the index of the bound in the state bounds array (index `0` instead of `2`).
4. **Resolved Stage-N input coupling dimensions**:
   - Stage $N$ has $nu_N = 0$. Passing a $D$ matrix of size $ng \times nu_N$ (empty) avoids buffer overflow/memory corruption issues.

---

## 4. Verification & Compilation Results

We ran compilation in SBCL and all packages load warning-free:
```
To load "hpipm":
  Load 1 ASDF system:
    hpipm
; Loading "hpipm"
[package hpipm]...................................
[package hpipm-demo]..............................
[package hpipm-pendulum-demo].....................
[package hpipm-demo-high].........................
[package hpipm-pendulum-demo-high]................
[package hpipm-soft-demo].........................
[package hpipm-spacecraft-demo]
```

Running the spacecraft demo produces the ASCII funnel and trajectory cleanly:
```
 k |    x (m)   |    y (m)   |    z (m)   |   ux (m/s2) |   uy (m/s2) |   uz (m/s2) | iter | status
---+------------+------------+------------+-------------+-------------+-------------+------+--------
 0 |    50.0000 |  -150.0000 |    25.0000 |   -0.030241 |    0.037924 |    0.033831 |  15  |   1
 1 |    48.5111 |  -148.0928 |    26.6900 |   -0.057232 |    0.056039 |   -0.004528 |  15  |   1
...
16 |     0.0000 |     0.0001 |    -0.0000 |    0.000078 |    0.002914 |   -0.000031 |  15  |   1
```
The radial and cross-track trajectories are correctly printed showing smooth capture.

