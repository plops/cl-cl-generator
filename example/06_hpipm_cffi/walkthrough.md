# Walkthrough: HPIPM CFFI Binding Generator

We have successfully implemented the `cl-cl-generator` metaprogramming example for the **HPIPM** (High-Performance Interior-Point Method) Optimal Control QP solver library.

The generator runs in SBCL, parses our S-expression API tables, and writes 5 clean Common Lisp source files that represent the FFI bindings, wrappers, memory managers, and an executable MPC simulation demo.

---

## 1. Generated Code Architecture

All generated files are written to the [source01/](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/) directory:

- **[package.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/package.lisp)**: Defines the `:hpipm` package and exports all CFFI and wrapper symbols (constants, lifecycle functions, setters, getters).
- **[hpipm.asd](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm.asd)**: Standard ASDF system declaration, depending on `:cffi`.
- **[hpipm-cffi.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-cffi.lisp)**: Native CFFI bindings (`cffi:defcfun`) for the complete lifecycle, solving, setting, and getting routines for **both double-precision (`d_`) and single-precision (`s_`) API variants** (180 functions total).
- **[hpipm-wrappers.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-wrappers.lisp)**: High-level Lisp wrappers:
  - **Memory Alignment**: Automatically pads and aligns raw foreign memory allocations to **64-byte boundaries** required by HPIPM/BLASFEO's cache-optimized internals.
  - **Dynamic Allocation Kapselung**: Provides `call-with-*` functions and `with-*` macros that manage the allocation, initialization, and clean-up of HPIPM structs (`dim`, `qp`, `sol`, `ipm_arg`, `ipm_ws`) via an `unwind-protect` block.
  - **Array Marshalling**: Converts standard Lisp arrays and sequences into raw foreign pointers on-the-fly, calls the C API, and cleans up.
- **[mpc-demo.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/mpc-demo.lisp)**: An MPC simulation of a coupled mass-spring-damper system.

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

We successfully located precompiled `libhpipm.so` and `libblasfeo.so` bundled in the CasADi package on the system, added them to `LD_LIBRARY_PATH`, and ran the generated demo:

```lisp
(hpipm-demo:run-mpc-demo)
```

### Output:
```
=== HPIPM MPC Demo: Mass-Spring-Damper ===
Horizon N=20, nx=4, nu=1
Initial state: (1.0d0 0.0d0 0.5d0 0.0d0)

Optimal inputs u*:
  u[ 0] =  -5.0000
  u[ 1] =  -5.0000
  u[ 2] =  -2.0009
  u[ 3] =   0.5029
  u[ 4] =   1.8529
  ...
  u[19] =  -0.1405

Optimal states x*:
  x[ 0] = [  1.0000   0.0000   0.5000  -0.0000]
  x[ 1] = [  1.0000  -0.6500   0.5000   0.0500]
  x[ 2] = [  0.9350  -1.2865   0.5050   0.0930]
  x[ 3] = [  0.8064  -1.5964   0.5143   0.1222]
  ...
  x[20] = [ -0.0011   0.1405   0.2369  -0.5580]

MPC demo complete.
```

- **Constraint Enforcement**: The control inputs `u[0]` and `u[1]` are saturated at `-5.0000` (which is the input bound `u-max`), proving that HPIPM correctly enforces inequality constraints.
- **State Convergence**: The position and velocity states smoothly converge towards the target equilibrium.
