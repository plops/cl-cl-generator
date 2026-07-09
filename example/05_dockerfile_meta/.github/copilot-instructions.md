# Copilot Instructions

## Build and test

- Generate the transpiler and example outputs:
  ```bash
  sbcl --load gen.lisp --eval "(quit)"
  ```
- Run the full test suite:
  ```bash
  sbcl --load source01/run_tests.lisp --eval "(quit)"
  ```
- Run a single check by loading the tests and evaluating one `assert-df` form in the `cl-dockerfile-generator` package:
  ```bash
  sbcl \
    --load source01/run_tests.lisp \
    --eval '(in-package :cl-dockerfile-generator)' \
    --eval '(assert-df "FROM alpine:3.18" (from |ALPINE:3.18|))' \
    --eval '(quit)'
  ```

## High-level architecture

- `gen.lisp` is the meta-generator. It loads `cl-cl-generator`, switches the reader to `:invert`, defines the `#r` raw-string reader macro, and emits `source01/dock.lisp` from a single `toplevel` S-expression.
- `source01/dock.lisp` is the generated library. It defines the `cl-dockerfile-generator` package, `emit-df`, `write-df`, and the dispatcher that turns Lisp forms into Dockerfile text.
- `source01/run_tests.lisp` is the generated test entrypoint. It loads the library and uses `assert-df` to compare emitted Dockerfile text against expected strings.
- `source01/cl-dockerfile-generator.asd` wires the library and test system together.

## Key conventions

- Treat `source01/dock.lisp` and `source01/run_tests.lisp` as generated artifacts; change `gen.lisp` and regenerate them instead of editing them by hand.
- The reader runs with `readtable-case` set to `:invert`. Uppercase symbols are emitted as uppercase Dockerfile keywords, while vertical-bar symbols are used for literal shell text, paths, and URLs.
- `#r` is the raw-string reader macro for shell fragments and other text that should not be escaped.
- `emit-df` is recursive and form-driven: `toplevel` joins top-level instructions, `run` supports normal commands plus `:mount` and `:heredoc`, and `copy`/`add` parse positional paths alongside keyword options such as `:from` and `:chown`.
- `write-df` hashes emitted text with `sxhash` and skips rewriting identical content so file mtimes stay stable.
