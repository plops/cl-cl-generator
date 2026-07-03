# Walkthrough: HPIPM CFFI Binding Generator & High-Level Lisp API

We have implemented the `cl-cl-generator` metaprogramming example for the **HPIPM** (High-Performance Interior-Point Method) Optimal Control QP solver library.

The generator consists of two steps:
1. **[gen01.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/gen01.lisp)**: Generates low-level CFFI bindings (`hpipm-cffi.lisp`, `hpipm-wrappers.lisp`) including bindings for solver status and iteration retrieval (`d_ocp_qp_ipm_get_status` and `d_ocp_qp_ipm_get_iter`), and the original low-level MPC demos.
2. **[gen02.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/gen02.lisp)**: Generates a high-level, Lisp-like MPC solver API (`hpipm-high.lisp`) and the rewritten high-level MPC demos, unifying all exports and registration.

All generated files are written to the [source01/](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/) directory.

---

## 1. Generated Code Architecture

All generated files in [source01/](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/) are:

- **[package.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/package.lisp)**: Defines the `:hpipm` package and exports all CFFI, low-level wrapper, and high-level solver API symbols.
- **[hpipm.asd](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm.asd)**: Standard ASDF system declaration, compiling and loading all components in dependency order.
- **[hpipm-cffi.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-cffi.lisp)**: Low-level CFFI bindings for the full HPIPM lifecycle, solve, and get-status/iter functions.
- **[hpipm-wrappers.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-wrappers.lisp)**: Low-level wrappers handling memory alignment, lifecycle functions, marshalling, and status/iter value extraction.
- **[hpipm-high.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp)**: The Lisp-like high-level solver API (defining the `mpc-solver` struct, `make-mpc-solver` constructor, `free-mpc-solver` destructor, `with-mpc-solver` resource macro, batch setters like `set-solver-cost`, and `solve-mpc` solver call).
- **[mpc-demo.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/mpc-demo.lisp)**: The original MSD demo using the low-level nested callback architecture.
- **[pendulum-demo.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/pendulum-demo.lisp)**: The original cart-pole inverted pendulum demo using the low-level callback architecture.
- **[mpc-demo-high.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/mpc-demo-high.lisp)**: The MSD demo rewritten using the new high-level Lisp-like API.
- **[pendulum-demo-high.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/pendulum-demo-high.lisp)**: The cart-pole inverted pendulum demo rewritten using the new high-level Lisp-like API.

---

## 2. API Design Showcase

### Comparison: Old Callback Pyramid vs. New Lisp-like API

#### Low-Level Nested Callbacks (mpc-demo.lisp):
```lisp
(call-with-d-ocp-qp-dim n
  (lambda (dim)
    (dotimes (k (+ n 1))
      (d-ocp-qp-dim-set-nx k nx dim) ...)
    (call-with-d-ocp-qp dim
      (lambda (qp)
        (dotimes (k n)
          (d-ocp-qp-set-a k ad qp) ...)
        (call-with-d-ocp-qp-sol dim
          (lambda (sol)
            (call-with-d-ocp-qp-ipm-arg dim
              (lambda (arg)
                (d-ocp-qp-ipm-arg-set-default +hpipm-mode-balance+ arg)
                (call-with-d-ocp-qp-ipm-ws dim arg
                  (lambda (ws)
                    (d-ocp-qp-ipm-solve qp sol arg ws)
                    (d-ocp-qp-sol-get-u k nu sol) ...)))))))))))
```

#### High-Level Clean API (mpc-demo-high.lisp):
```lisp
(with-mpc-solver (solver :horizon N :nx nx :nu nu :precision :double :mode :balance)
  (set-solver-dynamics solver Ad Bd)
  (set-solver-cost solver Q R)
  (set-control-bounds solver 0 (- u-max) u-max)
  
  (multiple-value-bind (u-traj x-traj status iterations)
      (solve-mpc solver x0)
    (format t "Solved status ~a in ~a iterations.~%" status iterations)
    ;; u-traj and x-traj are native Lisp vectors containing optimal trajectories
    ...))
```

---

## 3. Verification & Compilation Results

Since `libhpipm.so` and `libblasfeo.so` are not available by default in the test environment, we mocked CFFI's foreign library loading mechanism in SBCL and loaded the ASDF system. The system compiles and loads completely warning-free:

```
To load "hpipm":
  Load 1 ASDF system:
    hpipm
; Loading "hpipm"
..................................................
[package hpipm-demo]..............................
[package hpipm-pendulum-demo].....................
[package hpipm-demo-high].........................
[package hpipm-pendulum-demo-high]
```
This verifies that all generated Lisp-like functions, macro expansions, structures, and package exports are fully integrated, syntactically correct, and load smoothly under SBCL.
