---
name: cl-dockerfile-generator
description: Guidelines and reference for using cl-dockerfile-generator to write and generate Dockerfiles from Common Lisp S-expressions.
---

# cl-dockerfile-generator Agent Skill

`cl-dockerfile-generator` is a Common Lisp DSL and transpiler that allows you to dynamically compile Dockerfiles using S-expressions. It leverages the Lisp reader's `:invert` readtable-case and raw-string reader macros to achieve clean, readable code generation without backslash escaping.

---

## 1. System Setup & Loading

To use the transpiler, you must register its directory in ASDF and quickload it:

```lisp
(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    ;; Register the directory containing cl-dockerfile-generator.asd
    (push (merge-pathnames "path/to/source01/" current-dir) asdf:*central-registry*))
  (ql:quickload :cl-dockerfile-generator))
```

This imports the `:cl-dockerfile-generator` package, which exports the two primary functions:
- `emit-df`: Transpiles a single S-expression instruction or a `toplevel` block and returns the Dockerfile string.
- `write-df`: Transpiles an S-expression and writes the output directly to a target file.

---

## 2. Syntax & Case Rules

The generator runs under `:invert` readtable-case:
- **Lisp Symbols**: Capitalize keywords or instructions to output in uppercase (`FROM` -> `FROM`). Lowercase symbols yield lowercase output (`ubuntu` -> `ubuntu`).
- **Vertical Bars `|...|`**: Use vertical bars to preserve spaces, colons, or dashes in symbols. Remember to capitalize them to ensure lowercase output (`|APT-GET UPDATE|` -> `apt-get update`).
- **Strings**: Double-quoted strings are output exactly as-is without any case conversion.

---

## 3. Inline Scripts with `#r`

For multi-line scripts or commands that contain quotes, parentheses, or brackets, use the `#r` raw-string reader macro:

- **Brackets**: `#r(...)`, `#r[...]`, `#r{...}` support nested, balanced brackets.
- **Custom Delimiters**: `#r#...#`, `#r@...@` prevent quote escaping.

**Example**:
```lisp
(run #r#sbcl --load quicklisp.lisp --eval "(quicklisp-quickstart:install)"#)
```
Outputs:
```dockerfile
RUN sbcl --load quicklisp.lisp --eval "(quicklisp-quickstart:install)"
```

---

## 4. Reusability & Splicing

You can use standard Lisp helper functions to generate list structures and splice them into templates using `,@`:

```lisp
(defun copy-config-files (files dest-dir)
  (loop for file in files
        collect `(copy ,(format nil "config/~a" file) ,(format nil "~a/~a" dest-dir file))))

;; Inside template:
(toplevel
  (from "ubuntu:26.04")
  ,@(copy-config-files '("make.conf" "package.use") "/etc/portage"))
```

---

## 5. Running Tests

Load the test system and trigger the runner function:

```bash
sbcl --eval '(push (truename "path/to/source01/") asdf:*central-registry*)' \
     --eval '(asdf:load-system :cl-dockerfile-generator/tests)' \
     --eval '(cl-dockerfile-generator::run-all-tests)'
```
