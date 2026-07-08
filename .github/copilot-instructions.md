# Copilot instructions for `cl-cl-generator`

## Project snapshot
- This is a Common Lisp code generator that emits formatted Lisp source by driving the standard pretty printer (`pprint`) rather than building a separate code formatter.
- The main system files are `cl-cl-generator.asd`, `package.lisp`, and `cl.lisp`.
- The examples under `example/` are not just demos; several of them are generator scripts that bootstrap the system and emit committed output files.

## Build / load
- Load the system with ASDF + Quicklisp from the repository root:
  ```lisp
  (push "/path/to/cl-cl-generator/" asdf:*central-registry*)
  (ql:quickload :cl-cl-generator)
  ```
- There is no separate compile step beyond loading the system in SBCL/Quicklisp.

## Test
- Full test run:
  ```bash
  ./run-tests.sh
  ```
- The test script uses SBCL with `--disable-debugger`, pushes the repo root into `asdf:*central-registry*`, quickloads `:cl-cl-generator`, loads `tests.lisp`, and calls `cl-cl-generator/tests:run-tests`.
- For a targeted check, load `tests.lisp` in SBCL and evaluate one named case from `cl-cl-generator/tests::*test-cases*` instead of running the whole suite, for example:
  ```bash
  sbcl --disable-debugger \
    --eval "(push \"$(pwd)/\" asdf:*central-registry*)" \
    --eval '(ql:quickload :cl-cl-generator)' \
    --load tests.lisp
  ```
  Then in the REPL, find the case by `:name` and compare `emit-cl` against `:expected`.

## Architecture
- `cl.lisp` defines a custom `*cl-pprint-dispatch*` table and registers pretty-printers for a small DSL plus standard block forms.
- The DSL nodes are:
  - `toplevel` / `do0` for top-level output without outer parentheses
  - `comment` / `comments` for line comments
  - `raw` for unquoted literal insertion
- `emit-cl` binds the printer environment and returns formatted source as a string.
- `write-source` wraps `emit-cl`, hashes the emitted string, and skips rewriting identical content so file mtimes stay stable.
- The code generator is intentionally thin: most formatting behavior lives in pprint dispatch functions and a shared block-form printer.

## Conventions
- Generated Lisp is printed in lowercase via `emit-cl`.
- Wrap generated files in `toplevel`/`do0`; use `comment`, `comments`, and `raw` only when the output really needs generator-specific formatting.
- When adding support for a new block-like form, update the block-form registration and any header/list-position logic together; those two pieces are coupled.
- Comments inside nested forms are expected to force multiline layout so they do not swallow surrounding code.
- The hashing behavior in `write-source` is part of the expected behavior; tests check that identical output does not change `file-write-date`.
- Example scripts usually load the system by pushing a repo-relative path into `asdf:*central-registry*` from `*load-pathname*` before calling `ql:quickload`.
