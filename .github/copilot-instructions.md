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
- Run a single test case by loading `tests.lisp` in SBCL, switching to `cl-cl-generator/tests`, and evaluating one entry from `*test-cases*` (for example `basic-toplevel`) against `emit-cl`.

## High-level architecture

- `cl.lisp` is the core formatter. It builds a custom `*cl-pprint-dispatch*` table on top of Common Lisp `pprint` instead of implementing a separate code formatter.
- The DSL nodes are `toplevel`/`do0` for top-level output, `comment`/`comments` for line comments, and `raw` for literal insertion.
- `emit-cl` binds the pretty-printer environment and returns formatted source as a string; `write-source` hashes the emitted text and skips rewriting identical content so file mtimes stay stable.
- Most formatting behavior lives in the pprint dispatch functions plus the shared block-form printer. The comment-detection logic is intentionally coupled to block formatting so comments inside nested forms force multiline layout.
- The repository’s example directories are self-contained generator projects. Their committed `source*/` files are generated outputs, not hand-edited sources.

## Key conventions

- Generated Lisp is printed in lowercase via `emit-cl`.
- Wrap generated files in `toplevel`/`do0`; use `comment`, `comments`, and `raw` only when the output needs generator-specific formatting.
- When adding support for a new block-like form, update the block-form registration and the header/list-position handling together.
- Keep the hashing behavior in `write-source` intact; tests rely on identical output not changing `file-write-date`.
- Example-specific instructions live next to the example they apply to. If a directory has its own Copilot instructions, follow the most local file.
