# Walkthrough: HPIPM CFFI Binding Generator

We have implemented the `cl-cl-generator` metaprogramming example for the **HPIPM** (High-Performance Interior-Point Method) Optimal Control QP solver library.

The generator is defined in [gen01.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/gen01.lisp), which reads our S-expression API tables and writes 5 Common Lisp source files representing the bindings, wrappers, memory managers, and two complete MPC simulation demos.

---

## 1. Generated Code Architecture

All generated files are written to the [source01/](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/) directory:

- **[package.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/package.lisp)**: Defines the `:hpipm` package and exports all CFFI and wrapper symbols (constants, lifecycle functions, setters, getters).
- **[hpipm.asd](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm.asd)**: Standard ASDF system declaration, depending on `:cffi`. Includes both demos in its component list so they load automatically.
- **[hpipm-cffi.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-cffi.lisp)**: Native CFFI bindings (`cffi:defcfun`) for the complete lifecycle, solving, setting, and getting routines for **both double-precision (`d_`) and single-precision (`s_`) API variants** (180 functions total).
- **[hpipm-wrappers.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-wrappers.lisp)**: High-level Lisp wrappers:
  - **Memory Alignment**: Automatically pads and aligns raw foreign memory allocations to **64-byte boundaries** required by HPIPM/BLASFEO's cache-optimized internals.
  - **Dynamic Allocation Kapselung**: Provides `call-with-*` functions and `with-*` macros that manage the allocation, initialization, and clean-up of HPIPM structs (`dim`, `qp`, `sol`, `ipm_arg`, `ipm_ws`) via an `unwind-protect` block.
  - **Array Marshalling**: Converts standard Lisp arrays and sequences into raw foreign pointers on-the-fly, calls the C API, and cleans up.
- **[mpc-demo.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/mpc-demo.lisp)**: MPC simulation of a coupled mass-spring-damper system, containing extensive, inline documentation comments explaining the physical equations, discretization, and solver steps.
- **[pendulum-demo.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/pendulum-demo.lisp)**: MPC simulation of an unstable cart-pole inverted pendulum, stabilized around the upright equilibrium.

---

## 2. Key Engineering Challenges Resolved

### 1. Case-Sensitivity Symbol Collision
In HPIPM's C API, matrices are represented by uppercase strings (e.g. `"B"`, `"Q"`, `"R"`) and their corresponding vectors by lowercase strings (e.g. `"b"`, `"q"`, `"r"`).
Since Common Lisp symbols are case-insensitive by default, the symbols `B` and `b` collide.
- **Solution**: We implemented `lisp-field-name` to automatically map the lowercase vector fields `"b"`, `"q"`, and `"r"` to the distinct Lisp names `b-vec`, `q-vec`, and `r-vec`.

### 2. 64-Byte Cache Line Alignment
BLASFEO/HPIPM internals make heavy use of SIMD assembly instructions and expect memory blocks to be aligned to cache lines (64 bytes). Standard `cffi:foreign-alloc` does not guarantee this.
- **Solution**: We created an `align-pointer` helper and wrapped the struct allocations:
  ```lisp
  (let* ((mem-size (d-ocp-qp-sol-memsize dim))
         (backing (cffi:foreign-alloc :char :count (+ mem-size 64)))
         (aligned-backing (align-pointer backing 64))
         ...)
  ```
  This guarantees memory safety and prevents segmentation faults.

### 3. API Signature Swapping
HPIPM's C-APIs are generally regular, but `d_ocp_qp_sol_get` has a swapped signature compared to `d_ocp_qp_set` (it takes the struct pointer before the data pointer, whereas set takes the data pointer before the struct pointer).
- **Solution**: Corrected the parameter order mapping inside the CFFI definition and `make-sol-get-body`.

---

## 3. MPC Demo Simulation Results

We loaded the generated system using ASDF and executed both demos:

### Demo 1: Coupled Mass-Spring-Damper (`run-mpc-demo`)
```
=== HPIPM MPC Demo: Mass-Spring-Damper ===
Horizon N=20, nx=4, nu=1
Initial state: (1.0d0 0.0d0 0.5d0 0.0d0)

Optimal control force input trajectory u* (Newtons):
  u[ 0] =  -5.0000
  u[ 1] =  -5.0000
  u[ 2] =  -2.0009
  u[ 3] =   0.5029
  ...
```
- **Constraint Enforcement**: The control inputs `u[0]` and `u[1]` are saturated at `-5.0000` (which is the input bound `u-max`), proving that HPIPM correctly enforces inequality constraints.

### Demo 2: Inverted Pendulum on a Cart (`run-pendulum-demo`)
```
=== HPIPM MPC Demo: Inverted Pendulum on Cart ===
Horizon N=30, nx=4, nu=1
Initial state: (0.0d0 0.0d0 0.2d0 0.0d0) (tilted by 11.46 deg)

Optimal force trajectory u* (Newtons):
  u[ 0] = -10.0000
  u[ 1] =  -5.7482
  u[ 2] =  -1.9329
  u[ 3] =  -0.1339
  ...

Optimal state trajectory x* (predicted cart position & pole angle):
  x[ 0] = [cart_pos:  0.0000 cart_vel:  0.0000 pole_ang:  0.2000 pole_vel: -0.0000]
  x[ 1] = [cart_pos:  0.0000 cart_vel: -0.4806 pole_ang:  0.2000 pole_vel: -0.5738]
  x[ 2] = [cart_pos: -0.0240 cart_vel: -0.7515 pole_ang:  0.1713 pole_vel: -0.8330]
  ...
```
- **Stabilization Behavior**: To balance the pendulum tilted right (angle `0.2` rad), the cart accelerates to the left (negative force `u[0] = -10.0` N, moving velocity to `-0.48` m/s). This drives the cart under the pendulum, catching it and stabilizing the pole angle back to `0.0`.
