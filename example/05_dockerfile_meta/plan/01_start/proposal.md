# Proposal: cl-dockerfile-generator (Updated)

This document outlines the design and syntax specifications for `cl-dockerfile-generator`, a S-expression based generator for Dockerfiles using Common Lisp.

---

## 1. Symbol-based DSL & Case Inversion

By default, we set `(setf (readtable-case *readtable*) :invert)` (similar to `cl-py-generator`). This allows case-sensitive symbols to be read natively.

We emit symbols directly as strings by writing their `symbol-name`. Strings are only used as fallbacks when symbols would conflict with Lisp syntax (e.g. containing `:` for packages, like `ubuntu:26.04`).

---

## 2. Unified Argument Handling

All S-expression forms and instruction arguments will accept any of the following types interchangeably, converted automatically by a unified formatter:

1. **Symbols:** Emitted via their `symbol-name` (e.g., `DEBIAN_FRONTEND` $\rightarrow$ `DEBIAN_FRONTEND`).
2. **Escaped/Vertical Bar Symbols:** Emitted via their literal name (e.g., `|apt-get update|` $\rightarrow$ `apt-get update`).
3. **Strings (Raw or Normal):** Emitted as-is (e.g., `#r"echo 'hello'"` $\rightarrow$ `echo 'hello'`).
4. **Numbers:** Emitted via standard formatting.
5. **Lists:** Recursively formatted.

### Formatter Logic
```lisp
(defun emit-val (x)
  (cond
    ((stringp x) x)
    ((symbolp x) (symbol-name x))
    ((numberp x) (format nil "~a" x))
    ((listp x) (emit-list x))
    (t (format nil "~a" x))))
```

---

## 3. Handling Shell Pipes and Sequences

To make shell commands readable and free of escaping, the transpiler supports both **Alternative A** and **Alternative B**:

### Alternative A: Built-in Vertical Bar Symbols (`|...|`)
Common Lisp supports symbols containing arbitrary characters when enclosed in vertical bars.

#### How to handle the shell pipe `|`?
1. **Backslash escaping inside vertical bars:**
   ```lisp
   |cat file.txt \| grep "pattern"|
   ```
2. **Lisp `pipe` operator:**
   We define a structured `pipe` operator in the generator to chain commands:
   ```lisp
   (pipe |cat file.txt| |grep "pattern"|)
   ```
   Emits:
   ```dockerfile
   cat file.txt | grep "pattern"
   ```

---

### Alternative B: Raw String Reader Macro (`#r`)
We define a custom Lisp reader macro `#r` to read raw strings.

#### Delimiter Strategies & Pitfalls
To avoid escaping, the macro can use different delimiters:
1. **Balanced Delimiters:**
   We can define `#r(...)`, `#r[...]`, and `#r{...}` to keep track of nested brackets.
2. **Character-delimited Raw Strings:**
   We can define `#r` to take the next character as the delimiter. For example:
   * `#r#cat file | grep "pattern"#` (delimiter is `#`)
   * `#r%echo "hello" && echo "world"%` (delimiter is `%`)

---

## 4. Revised Project Structure & Example Folders

To keep code duplication at a minimum and show clear usage:

1. **`example/05_dockerfile_meta/gen.lisp`**:
   - The generator template. It uses Lisp helper functions and `,@(loop ...)` splicing to build the transpiler.
   - It writes the transpiler source code to `/workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/dock.lisp`.
2. **`example/05_dockerfile_meta/source01/dock.lisp`**:
   - The generated transpiler.
3. **`example/05_dockerfile_meta/source01/examples/`**:
   - **`01_gentoo/Dockerfile`**: Generated Gentoo build stage example.
   - **`02_agy_env/Dockerfile`**: Generated Antigravity environment build stage example.
