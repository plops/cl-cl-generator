# Code Improvement Plan for cl-cl-generator

Improve the Lisp code generator by resolving key limitations, adding safety bindings, and extending standard Common Lisp form formatting.

## Proposed Changes

We will modify three files: `cl.lisp`, `tests.lisp`, and `example/01_meta/gen.lisp`.

---

### Core Generator Module

#### [MODIFY] [cl.lisp](file:///workspace/src/cl-cl-generator/cl.lisp)

- **`split-lines` helper**: Add a helper function to safely split any comment string containing newline characters into individual lines.
- **`pprint-comment` and `pprint-comments`**: Update comment pretty printers to split input string(s) using `split-lines` so nested newlines in a single string are formatted with `;; ` prefix on every line, avoiding syntax errors.
- **`emit-cl` printer bindings**: Explicitly bind `*print-length*`, `*print-level*`, `*print-lines*`, `*print-circle*`, and `*print-readably*` to `nil` (and `*print-escape*` to `t`) to shield code generation from the caller's environment.
- **Additional formatting support**:
  - Update `list-position-p` to include:
    - Index 1 list positions: `defclass`, `defgeneric`.
    - Index 0 list positions: `lambda`, `eval-when`, `dolist`, `dotimes`, `handler-bind`, `restart-bind`.
  - Update `header-length` mapping in `pprint-block-form` for:
    - 2-length headers: `defclass`, `defgeneric`.
    - 1-length headers: `lambda`, `eval-when`, `dolist`, `dotimes`, `handler-case`, `restart-case`, `handler-bind`, `restart-bind`, `unwind-protect`.
  - Register all these new symbols under `pprint-block-form`.

---

### Examples

#### [MODIFY] [gen.lisp](file:///workspace/src/cl-cl-generator/example/01_meta/gen.lisp)

- Synchronize the meta-emitter generator script to match the changes made to `cl.lisp`.

---

### Tests

#### [MODIFY] [tests.lisp](file:///workspace/src/cl-cl-generator/tests.lisp)

- Add a test case for multiline comments inside a single string to verify correct line-by-line prefixing.
- Add a test case for formatting the new block forms (`lambda`, `eval-when`, `defclass`, `dolist`) to verify correct indentation, list rendering `()`, and layout.

## Verification Plan

### Automated Tests
- Run `./run-tests.sh` to execute the expanded test suite.
