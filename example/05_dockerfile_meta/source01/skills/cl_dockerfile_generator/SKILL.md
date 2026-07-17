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

## 5. Heredocs for Inline Files and Scripts (`:heredoc`)

To avoid complex multi-line shell strings with chained `&&` or backslashes, `cl-dockerfile-generator` supports native heredocs in `copy` and `run` statements:

- **Creating/Overwriting inline files (`copy :heredoc`)**:
  ```lisp
  (copy :heredoc "/etc/conf.d/modules" "modules=\"amdgpu mt7921e\"")
  ```
  Generates:
  ```dockerfile
  COPY <<EOF /etc/conf.d/modules
  modules="amdgpu mt7921e"
  EOF
  ```

- **Executing inline multi-line scripts (`run :heredoc`)**:
  ```lisp
  (run :heredoc #r(set -e
  echo "Setting up locales"
  locale-gen
  env-update))
  ```
  Generates:
  ```dockerfile
  RUN <<EOF
  set -e
  echo "Setting up locales"
  locale-gen
  env-update
  EOF
  ```

---

## 6. BuildKit Cache Mounts (`:mount`)

The `:mount` option supports both a single cache mount string or a list of cache mount strings for configuring multiple mounts:

- **Single Mount**:
  ```lisp
  (run :mount "type=cache,target=/root/.npm" "npm install -g @openai/codex")
  ```
  Generates:
  ```dockerfile
  RUN --mount=type=cache,target=/root/.npm npm install -g @openai/codex
  ```

- **Multiple Mounts**:
  ```lisp
  (run :mount ("type=cache,target=/var/cache/apt,sharing=locked"
               "type=cache,target=/var/lib/apt/lists,sharing=locked")
       (and "apt-get update" "apt-get install -y ca-certificates"))
  ```
  Generates:
  ```dockerfile
  RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update && apt-get install -y ca-certificates
  ```

---

## 7. Modern BuildKit COPY/ADD Options

The `copy` and `add` DSL constructs support modern BuildKit optimization parameters:

- **COPY options**: `:from`, `:chown`, `:link` (Boolean), `:chmod`, `:parents` (Boolean), and `:exclude`.
- **ADD options**: `:chown`, `:link` (Boolean), `:chmod`, and `:checksum`.

**Example**:
```lisp
(copy "src" "dest" :from stage :chown owner :link t :chmod 755 :parents t :exclude "*.log")
```
Generates:
```dockerfile
COPY --from=stage --chown=owner --link --chmod=755 --parents --exclude=*.log src dest
```

---

## 8. Compiler Diagnostics & Validations

To safeguard against typos and syntax errors, the transpiler runs validations during compilation:
- **Typo Warnings**: Emitting an unknown Dockerfile instruction (e.g. `(runn "apt-get update")`) triggers a warning (`Unknown Dockerfile instruction: RUNN`) in the fallback case.
- **Option Value Validation**: Specifying a keyword option (like `:from` or `:chown`) without a following value throws a compile-time error.

---

## 9. File Writing & Cache Optimization

The `write-df` function writes the generated Dockerfile to the filesystem. To avoid touching the file's modification time (`mtime`) unnecessarily (which triggers downstream rebuilds), it verifies content state:

- **Disk-Based Check**: Uses `file-contents-equal-p` to verify the actual disk file content against the generated output.
- **Robustness**: This approach is 100% collision-free (not reliant on `sxhash`) and handles cases where the target file was deleted or modified externally.

---

## 10. Generation-Time Parameterization & Lisp Splicing

Leverage Common Lisp parameterization (`*variables*` and `format` evaluation) at generation time to build paths, comments, or commands dynamically instead of hardcoding them. Because S-expressions in templates are backquoted, you can evaluate them with `,` or `,@`.

**Example**:
```lisp
(defparameter *kver* "6.18.36")

;; Inside template:
(toplevel
  (comment ,(format nil "Recreate the gentoo-sources-~a ebuild" *kver*))
  (copy :heredoc ,(format nil "/var/db/repos/gentoo/sys-kernel/gentoo-sources/gentoo-sources-~a.ebuild" *kver*)
        #r(EAPI="8"
ETYPE="sources"
...)))
```

This keeps version configuration in a single location while producing clean, compile-safe Dockerfiles.

---

## 11. Running Tests

Load the test system and trigger the runner function:

```bash
sbcl --eval '(push (truename "path/to/source01/") asdf:*central-registry*)' \
     --eval '(asdf:load-system :cl-dockerfile-generator/tests)' \
     --eval '(cl-dockerfile-generator::run-all-tests)'
```
