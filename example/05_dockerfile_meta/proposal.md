# Proposal: cl-dockerfile-generator (Updated)

This document outlines the design and syntax specifications for `cl-dockerfile-generator`, a S-expression based generator for Dockerfiles using Common Lisp.

---

## 1. Symbol-based DSL & Case Inversion

By default, we set `(setf (readtable-case *readtable*) :invert)` (similar to `cl-py-generator`). This allows case-sensitive symbols to be read natively.

We emit symbols directly as strings by writing their `symbol-name`. Strings are only used as fallbacks when symbols would conflict with Lisp syntax (e.g. containing `:` for packages, like `ubuntu:26.04`).

---

## 2. Alternatives for Shell Commands & Escaping

To avoid double-quote escaping (`\"`) and backslash continuation hell in S-expressions, we support both **Alternative A** and **Alternative B**.

### Alternative A: Built-in Vertical Bar Symbols (`|...|`)
Common Lisp supports symbols containing arbitrary characters when enclosed in vertical bars.

#### How to handle the shell pipe `|`?
Because `|` is the delimiter for the symbol, a literal `|` inside the symbol will close it. To handle pipes:
1. **Backslash escaping inside vertical bars:**
   ```lisp
   |cat file.txt \| grep "pattern"|
   ```
   Lisp reads this as a single symbol with name `"cat file.txt | grep \"pattern\""`.
2. **Lisp `pipe` operator:**
   We define a structured `pipe` operator in the generator to chain commands:
   ```lisp
   (pipe |cat file.txt| |grep "pattern"|)
   ```
   Emits:
   ```dockerfile
   cat file.txt | grep "pattern"
   ```
   This keeps individual commands clean without any escaping!

---

### Alternative B: Raw String Reader Macro (`#r`)
We define a custom Lisp reader macro `#r` to read raw strings.

#### Delimiter Strategies & Pitfalls
To avoid escaping, the macro can use different delimiters:
1. **Balanced Delimiters:**
   We can define `#r(...)`, `#r[...]`, and `#r{...}` to keep track of nested brackets.
   * **Pitfall:** Unbalanced brackets inside the script (e.g., an unmatched `)` in an `awk` script or shell subshell) will prematurely close the raw string.
2. **Character-delimited Raw Strings:**
   We can define `#r` to take the next character as the delimiter. For example:
   * `#r#cat file | grep "pattern"#` (delimiter is `#`)
   * `#r%echo "hello" && echo "world"%` (delimiter is `%`)
   * **Pitfall:** The chosen delimiter character cannot be used inside the raw string. However, since the delimiter is dynamic, you can always choose a character that does not appear in your command.

---

## 3. Revised Project Structure & Example Folders

To keep code duplication at a minimum and show clear usage:

1. **`example/05_dockerfile_meta/gen.lisp`**:
   - The generator template. It uses Lisp helper functions and `,@(loop ...)` splicing to build the transpiler.
   - It writes the transpiler source code to `/workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/dock.lisp`.
2. **`example/05_dockerfile_meta/source01/dock.lisp`**:
   - The generated transpiler.
3. **`example/05_dockerfile_meta/source01/examples/`**:
   - **`01_gentoo/Dockerfile`**: Generated Gentoo build stage example.
   - **`02_agy_env/Dockerfile`**: Generated Antigravity environment build stage example.
