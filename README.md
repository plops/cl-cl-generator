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

## Running Tests
Run the test runner script:
```bash
./run-tests.sh
```
