# Copilot instructions for `cl-cl-generator`

## Build and test

- Load the system from the repository root:
  ```lisp
  (push "/path/to/cl-cl-generator/" asdf:*central-registry*)
  (ql:quickload :cl-cl-generator)
  ```
- Run the full test suite:
  ```bash
  ./run-tests.sh
  ```
- Run one test case directly from `tests.lisp`:
  ```bash
  sbcl --disable-debugger \
    --eval "(push \"/path/to/cl-cl-generator/\" asdf:*central-registry*)" \
    --eval '(ql:quickload :cl-cl-generator)' \
    --load tests.lisp \
    --eval "(let ((tc (find \"basic-toplevel\" cl-cl-generator/tests::*test-cases*
                            :key (lambda (x) (getf x :name))
                            :test #'string=)))
             (format t \"~a~%\" (cl-cl-generator:emit-cl (getf tc :input))))" \
    --eval '(quit)'
  ```

## High-level architecture

- `cl.lisp` is the core formatter. It builds a custom `*cl-pprint-dispatch*` table on top of Common Lisp `pprint` rather than implementing a separate code generator.
- `package.lisp` exports the small public surface: `emit-cl`, `write-source`, `*cl-pprint-dispatch*`, and the DSL forms `toplevel`, `do0`, `comment`, `comments`, and `raw`.
- `emit-cl` binds pretty-printer state and returns formatted source as a string; `write-source` hashes emitted text and skips rewriting identical content so file mtimes stay stable.
- The formatter is centered on a few DSL nodes: top-level wrappers (`toplevel`/`do0`), line comments (`comment`/`comments`), and literal insertion (`raw`).
- Nested forms containing comments are forced into multiline layout so comments do not accidentally swallow surrounding code.
- `tests.lisp` contains the formatter cases and the hashing/mtime check that guards `write-source`.
- Example directories are self-contained generator projects. Their committed `source*/` files are generated artifacts, and some examples carry their own local Copilot instructions that take precedence in that subtree.

## Key conventions

- Generated Lisp is printed in lowercase via `emit-cl`.
- Wrap generated files in `toplevel`/`do0`; use `comment`, `comments`, and `raw` only when the output needs generator-specific formatting.
- When adding a new block-like form, update the block-form registration and the header/list-position handling together.
- Preserve the hashing behavior in `write-source`; identical output must not touch file mtimes.
- Prefer the repo’s existing generated outputs and example scaffolding as references instead of hand-editing generated files.
