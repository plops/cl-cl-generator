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

The repository contains several example generators in the [example/](file:///workspace/src/cl-cl-generator/example) directory:

1. **[00_test](file:///workspace/src/cl-cl-generator/example/00_test)**: A basic helper generating a simple Lisp file with function definitions, local bindings, single/multi-line comments, and conditional statements. Shows how to embed Git commit hashes and generation timestamps.
2. **[01_meta](file:///workspace/src/cl-cl-generator/example/01_meta)**: A bootstrapping meta-generator example where `cl-cl-generator` is used to generate its own core codebase ([cl.lisp](file:///workspace/src/cl-cl-generator/cl.lisp)).
3. **[03_py_meta](file:///workspace/src/cl-cl-generator/example/03_py_meta)**: A meta-generator for the `cl-py-generator` transpiler's `py.lisp` compiler. Compiles Python generation templates into Lisp helper builders, supporting Python f-strings, imports, decorators, and operator precedence rules.
4. **[04_tui_cockpit](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit)**: Code generators emitting interactive Lisp terminal utilities:
   - `gen01.lisp` generates a non-interactive bandwidth-optimized `/proc` parser.
   - `gen02.lisp` generates a fully featured interactive TUI application utilizing a system definition (`.asd`), package declarations, and an interactive dashboard using the `tuition` framework.
5. **[05_dockerfile_meta](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta)**: Generates `cl-dockerfile-generator`, a domain-specific language (DSL) and compiler for writing Dockerfiles as S-expressions. Features case-inversion configuration and custom Lisp templates for Dockerfile instructions.

## Running Tests
Run the test runner script:
```bash
./run-tests.sh
```

