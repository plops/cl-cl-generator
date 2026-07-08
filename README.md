# cl-cl-generator

An elegant, robust, and highly condensed S-expression code generator for Common Lisp, leveraging Lisp's built-in pretty-printer (`pprint`).

## Design Philosophy

Unlike transpilers targeting other languages (like [cl-py-generator](https://github.com/plops/cl-py-generator)), `cl-cl-generator` targets Common Lisp itself. Since the source S-expressions and target language share the same syntax, a custom recursive code emitter is redundant and fragile. 

Instead, `cl-cl-generator` is built around the standard Lisp pretty printer. It works by:
1. **Leveraging Built-in Logic**: The standard Lisp `pprint` system already contains highly tuned formatting templates for `defun`, `let`, `cond`, `loop`, and all other standard constructs.
2. **Custom Pretty Print Dispatches**: It registers a small set of custom `pprint-dispatch` functions to format non-standard, generator-specific DSL nodes:
   - `toplevel` / `do0`: Prints child forms at the top level of a file without outer parentheses, separating them with blank lines.
   - `comment` / `comments`: Prints single- or multi-line comments (`;;`) aligned to the correct block indentation.
   - `raw`: Inserts raw text/strings directly without quotes.
3. **Automated Layout Breaking**: Registers a custom dispatch rule that detects any nested list containing comments and formats it on separate lines. This guarantees that comments inside forms like `cond` clauses never comment out the surrounding code.
4. **File Hashing**: Includes automatic hashing of the generated code. If the code is identical, `write-source` skips writing to avoid changing the file's modification time (mtime), which prevents unnecessary recompilations in build tools.

## Quick Start

### 1. Load the System
```lisp
(push "/path/to/cl-cl-generator/" asdf:*central-registry*)
(ql:quickload :cl-cl-generator)
```

### 2. Generate Code
```lisp
(cl-cl-generator:write-source 
  "output_example"
  '(toplevel
     (in-package :cl-user)
     
     (comment "Calculate square of a number")
     (defun square (x)
       (* x x)))
  #P"/tmp/")
```

This writes the following beautifully formatted code to `/tmp/output_example.lisp`:

```lisp
(in-package :cl-user)

;; Calculate square of a number
(defun square (x)
  (* x x))
```

## Examples

The repository contains several example projects in the [example/](file:///workspace/src/cl-cl-generator/example) directory:

1. **[00_test](file:///workspace/src/cl-cl-generator/example/00_test)**: Minimal generator that emits a small Lisp file with functions, bindings, comments, conditionals, and git/time metadata.
2. **[01_meta](file:///workspace/src/cl-cl-generator/example/01_meta)**: Bootstrapping meta-generator where `cl-cl-generator` is used to generate its own core codebase.
3. **[03_py_meta](file:///workspace/src/cl-cl-generator/example/03_py_meta)**: Meta-generator for `cl-py-generator` that expands Python DSL templates into Lisp helpers for f-strings, imports, decorators, and precedence handling.
4. **[04_tui_cockpit](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit)**: Generates terminal utilities, from a fast `/proc` parser to an interactive TUI dashboard built with `tuition`.
5. **[05_dockerfile_meta](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta)**: Generates `cl-dockerfile-generator`, a Dockerfile DSL/compiler with case inversion and custom instruction templates.
6. **[06_hpipm_cffi](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi)**: Generates HPIPM CFFI bindings, Lisp wrappers, and MPC demos from repetitive C API metadata.
7. **[07_pure_x11](file:///workspace/src/cl-cl-generator/example/07_pure_x11)**: Generates a pure-Lisp raw-socket X11 client, widget/layout engine, and demo GUI application.
8. **[08_expanse_combat](file:///workspace/src/cl-cl-generator/example/08_expanse_combat)**: Builds a 2D orbital space-combat game combining pure X11 rendering with HPIPM-based MPC control.
9. **[09_protobuf_grpc](file:///workspace/src/cl-cl-generator/example/09_protobuf_grpc)**: Generates protobuf-like binary serialization and gRPC-like TCP RPC code from a schema DSL.
10. **[10_multi_domain_solver](file:///workspace/src/cl-cl-generator/example/10_multi_domain_solver)**: Generates a symbolic multi-domain lumped-element circuit compiler plus GUI demos for oscillators and diode circuits.
11. **[11_barium](file:///workspace/src/cl-cl-generator/example/11_barium/barium_src)**: Vendored Barium toolkit sources, tests, and demos for a Common Lisp X11 widget toolkit with Cairo/OpenGL support.

## Running Tests
Run the test runner script:
```bash
./run-tests.sh
```
