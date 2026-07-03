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

## 2. Verification & Compilation Results

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
[package hpipm-soft-demo]
```
This confirms that the entire codebase (bindings, wrappers, high-level API, and the 3 demos) is syntactically correct and loads cleanly.
