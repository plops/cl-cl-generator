# Proposal: cl-dockerfile-generator (Updated)

This document outlines the design and syntax specifications for `cl-dockerfile-generator`, a S-expression based generator for Dockerfiles using Common Lisp.

---

## 1. Symbol-based DSL & Case Inversion

By default, we set `(setf (readtable-case *readtable*) :invert)` (similar to `cl-py-generator`). This allows case-sensitive symbols to be read natively (e.g., lower-case symbols stay lower-case, upper-case symbols stay upper-case).

We will emit symbols directly as strings by writing their `symbol-name`. Strings are only used as fallbacks when symbols would conflict with Lisp syntax (e.g. containing `:` for packages, like `ubuntu:26.04`).

### Examples

- `(arg DEBIAN_FRONTEND noninteractive)` $\rightarrow$ `ARG DEBIAN_FRONTEND=noninteractive`
- `(env UV_COMPILE_BYTECODE 1)` $\rightarrow$ `ENV UV_COMPILE_BYTECODE=1`
- `(from "ubuntu:26.04" :as builder)` $\rightarrow$ `FROM ubuntu:26.04 AS builder` (strings are used for `:` package prefixes, but symbols work for keyword arguments and names).

---

## 2. Alternatives for Shell Commands & Escaping

To avoid double-quote escaping (`\"`) and backslash continuation hell in S-expressions, we propose three alternative strategies:

### Alternative A: Built-in Vertical Bar Symbols (`|...|`)
Common Lisp has built-in support for symbols containing arbitrary characters (including spaces, quotes, and backslashes) when enclosed in vertical bars.

#### Usage
```lisp
(run (and |apt-get update|
          |apt-get install -y --no-install-recommends ca-certificates curl|
          |echo "Hello World" >> /etc/motd|))
```

#### Emitted Dockerfile
```dockerfile
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && echo "Hello World" >> /etc/motd
```

- **Pros:** Native to Common Lisp; requires no custom reader macros; preserves case, quotes, and spacing exactly.
- **Cons:** IDE syntax highlighting might treat the contents inside `|...|` as a single symbol name (which is technically correct in Lisp).

---

### Alternative B: Raw String Reader Macro (`#r"..."` or `#r(...)`)
We define a custom Lisp reader macro (e.g., `#r`) that reads everything up to a matching delimiter as a raw string without parsing Lisp escape sequences.

#### Usage
```lisp
(run :heredoc #r(
set -e
echo "Building gentoo.ext4..."
rm -rf /tmp/ext4_root
))
```

#### Emitted Dockerfile
```dockerfile
RUN <<EOF
set -e
echo "Building gentoo.ext4..."
rm -rf /tmp/ext4_root
EOF
```

- **Pros:** Very clean; familiar to developers who use raw strings in Python (`r"..."`) or C++ (`R"..."`).
- **Cons:** Requires registering a reader macro (`set-dispatch-macro-character`) before loading any S-expression templates.

---

### Alternative C: Structured Shell DSL
We map shell constructs to Lisp list expressions, converting them to strings during emission.

#### Usage
```lisp
(run (and (apt-get update)
          (apt-get install -y --no-install-recommends ca-certificates curl)
          (>> (echo "Hello World") /etc/motd)))
```

- **Pros:** Highly structured; can perform validation/checks at Lisp compile time.
- **Cons:** Very complex to maintain for general shell programming (handling redirecting, pipes, variables, etc.).

---

## 3. Revised Project Structure & Meta-Generation

To avoid redundancy and keep code duplication at a minimum, we will implement this project using a meta-generator:

1. **`example/05_dockerfile_meta/gen.lisp`**:
   - The generator template. It uses Lisp helper functions and `,@(loop ...)` splicing to build the transpiler.
   - Using `cl-cl-generator`, it writes the transpiler source code to the output file.
2. **`example/05_dockerfile_meta/source01/dock.lisp`**:
   - The generated transpiler. It implements the pretty printer / dispatch table for Dockerfile S-expressions.
3. **`example/05_dockerfile_meta/source01/test_gen.lisp`**:
   - A script that uses `dock.lisp` to generate example Dockerfiles (like `110_gentoo` and `172_docker_agy_env`), confirming correct behavior.
