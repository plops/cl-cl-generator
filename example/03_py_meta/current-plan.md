# Current Plan: Cleanup and Fix cl-py-generator Example

## Context and Goal
We are refactoring the self-contained Lisp-to-Python transpiler in `example/03_py_meta`.
The stash has been popped and we have three modified files:
- `gen.lisp` — the meta-generator
- `py.lisp` — the generated transpiler
- `package.lisp` — the package definition

The changes implement a large set of renames and improvements from the previous sessions:
- `do` → `body`, `cl-py-generator:do0` → `progn`
- `dictionary` → `dict*`, `~` → `lognot`
- `return_` removed, `return` now handles bare return
- `imports`/`imports-from` removed; `import` now takes variadic args
- `string` now uses `parse-explicit-string` with keyword modifiers (`:f`, `:raw`, `:triple`, `:bytes`)
- Bare strings in code blocks now auto-detect f-string syntax via `parse-and-emit-fstring`
- `raw` form added for literal string insertion

## Current Problem
Two issues need fixing:

### 1. `gen.lisp` — Unmatched close parenthesis at line 712
SBCL reports: `READ error: unmatched close parenthesis at line 712, col 30`.
The `paren*` clause (around line 543) has one extra closing parenthesis — it closes
the outer `case` form prematurely, leaving the remaining clauses outside the `case`.
**Fix**: Remove one closing parenthesis from the end of the `paren*` clause at line 543.

Note: I think that has been fixed already

### 2. `transpiler-tests.lisp` — `do0` references
The test file still uses `do0` in 6 test cases. Since `do0` is no longer exported by
`:cl-py-generator`, these tests will fail to compile.
**Fix**: Replace all `(do0 ...)` in transpiler-tests.lisp with `(progn ...)`.

## Step-by-Step Actions

1. **Fix gen.lisp line 543** — Resolved (unmatched close parenthesis fixed).
2. **Fix transpiler-tests.lisp** — Resolved (all `do0` replaced with `progn`, test package references/exports verified, and tests updated to use `dict*`, `raw`, and `lognot`).
3. **Rebuild py.lisp** — Re-generated successfully via `gen.lisp`.
4. **Run the test suite** — Successfully executed. All 144 transpilation and execution tests are passing!
5. **Verify and finalize** — Unused debug artifacts cleaned up. Ready to commit.
