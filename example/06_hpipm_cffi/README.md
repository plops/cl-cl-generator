# HPIPM CFFI Binding Generator

This example demonstrates the power of the `cl-cl-generator` metaprogramming system to generate complete Common Lisp CFFI bindings for highly repetitive, structured C APIs.

Specifically, it targets the **HPIPM** (High-Performance Interior-Point Method) Optimal Control QP solver library.

## What is HPIPM?

HPIPM is an extremely fast Interior Point QP solver optimized for Model Predictive Control (MPC) and optimal control problems. It exploits the block-tridiagonal sparsity structure of optimal control problems using Riccati recursion, achieving O(N) complexity (linear in the horizon length N).

## Metaprogramming Showcase

The HPIPM C-API has over 180 functions that follow extremely repetitive naming and signature patterns. Writing bindings and safe Lisp wrapper functions for all of them manually is tedious and error-prone.

With `cl-cl-generator`, we define the API using structured S-expression metadata tables inside [gen.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/gen.lisp). The generator then uses Lisp loops (`,@(loop ...)`) to expand these tables into:
- **`hpipm-cffi.lisp`**: The low-level `cffi:defcfun` declarations for both double-precision (`d_`) and single-precision (`s_`) API variants.
- **`hpipm-wrappers.lisp`**: Typsichere Lisp wrapper functions (e.g. `d-ocp-qp-set-a`, `d-ocp-qp-sol-get-x`) that handle automatic copying of Lisp arrays to foreign memory, type conversions, and boundary checks.
- **`call-with-*` functions and `with-*` macros**: Convenience macros that wrap HPIPM's custom `memsize`/`create`/`free` memory-management cycle into clean Lisp blocks (e.g. `with-d-ocp-qp`).
- **`package.lisp`**: Export lists for all generated symbols.
- **`hpipm.asd`**: ASDF system definition.
- **`mpc-demo.lisp`**: A complete, executable MPC simulation of a coupled mass-spring-damper system.

## Generated Files

All generated files are written to the [source01/](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/) directory:
1. [package.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/package.lisp)
2. [hpipm.asd](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm.asd)
3. [hpipm-cffi.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-cffi.lisp)
4. [hpipm-wrappers.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-wrappers.lisp)
5. [mpc-demo.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/mpc-demo.lisp)

## Running the Generator

To re-run the generator and update the files:
```bash
sbcl --load gen.lisp
```

## Running the MPC Demo

To run the generated MPC demo, you must have the HPIPM and BLASFEO shared libraries installed on your system.

Once they are installed, load the generated system and run the demo function:
```lisp
(ql:quickload :hpipm)
(hpipm-demo:run-mpc-demo)
```
