# Proposal: cl-dockerfile-generator

This document outlines the design and syntax specifications for `cl-dockerfile-generator`, a S-expression based generator for Dockerfiles using Common Lisp.

---

## 1. Dockerfile Syntax & Semantics Analysis

Based on the official Dockerfile specification and modern features (BuildKit), a Dockerfile is parsed as a series of instructions. Key features and their semantics include:

- **Parser Directives:** Special comments at the beginning of the file (e.g., `# syntax=docker/dockerfile:1`) that affect how the parser builds the file.
- **Multi-Stage Builds:** Standardized using `FROM image AS stage_name` and referencing other stages using `COPY --from=stage_name`.
- **Environment & Arguments:** Persistent environment variables via `ENV key=value` and build-time variables via `ARG key=value`.
- **Here-Documents (BuildKit):** Modern Dockerfiles support Here-Documents for `RUN` and `COPY` instructions. This allows writing multi-line shell scripts or file content directly in the Dockerfile without backslash continuation and escape characters. E.g.:
  ```dockerfile
  RUN <<EOF
  apt-get update
  apt-get install -y curl git
  EOF
  ```
- **Exec vs. Shell form:** Many instructions (like `CMD`, `ENTRYPOINT`, `RUN`) support both list-based Exec form (e.g., `["/bin/bash", "-c"]`) and raw Shell form.

---

## 2. DSL (S-Expression) Design

To represent Dockerfiles cleanly in Common Lisp, we propose a direct mapping from S-expressions to Dockerfile instructions.

### Core Mappings

| Dockerfile Instruction | S-Expression Example | Emitted Code |
| :--- | :--- | :--- |
| `# syntax=...` | `(directive syntax "docker/dockerfile:1")` | `# syntax=docker/dockerfile:1` |
| `FROM` | `(from "ubuntu:26.04")`<br>`(from "ubuntu:26.04" :as "builder")` | `FROM ubuntu:26.04`<br>`FROM ubuntu:26.04 AS builder` |
| `ARG` | `(arg "DEBIAN_FRONTEND" "noninteractive")` | `ARG DEBIAN_FRONTEND=noninteractive` |
| `ENV` | `(env "UV_COMPILE_BYTECODE" 1)` | `ENV UV_COMPILE_BYTECODE=1` |
| `ENV` (Multi-line) | `(env "VAR1" "val1" "VAR2" "val2")` | `ENV VAR1=val1 \<br>    VAR2=val2` |
| `WORKDIR` | `(workdir "/workspace")` | `WORKDIR /workspace` |
| `USER` | `(user "kiel")` | `USER kiel` |
| `VOLUME` | `(volume '("/workspace/src"))` | `VOLUME ["/workspace/src"]` |
| `EXPOSE` | `(expose 80 443)` | `EXPOSE 80 443` |
| `COPY` | `(copy "src" "dest")`<br>`(copy "src" "dest" :from "builder")`<br>`(copy "src" "dest" :chown "kiel")` | `COPY src dest`<br>`COPY --from=builder src dest`<br>`COPY --chown=kiel src dest` |
| `ENTRYPOINT` | `(entrypoint '("agy" "--dangerously"))`<br>`(entrypoint "agy --dangerously")` | `ENTRYPOINT ["agy", "--dangerously"]`<br>`ENTRYPOINT agy --dangerously` |
| `CMD` | `(cmd '("/bin/bash"))` | `CMD ["/bin/bash"]` |

---

## 3. Handling Complex Shell Command Sequences

A major pain point in Dockerfiles is long shell command chains. We propose three distinct strategies to make this clean, readable, and free of manual backslash escaping in S-expressions:

### Strategy A: Automatically Formatted Sequences (`and`, `seq`/`progn`)
The generator parses a list of command strings and formats them into a single `RUN` block joined by line continuations and logic gates.

```lisp
(run (and "apt-get update"
          "apt-get install -y --no-install-recommends ca-certificates curl"
          "rm -rf /var/lib/apt/lists/*"))
```
Emits:
```dockerfile
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
```

Similarly, sequencing commands sequentially (e.g. joined by `;` or `\n`):
```lisp
(run (seq "cd /tmp"
          "tar -xf archive.tar"
          "make install"))
```
Emits:
```dockerfile
RUN cd /tmp; \
    tar -xf archive.tar; \
    make install
```

### Strategy B: BuildKit Here-Documents (`:heredoc`)
To write complex multiline shell script scripts without backslashes or line continuations, we can leverage BuildKit Here-Documents.

```lisp
(run :heredoc "set -e
echo \"Building gentoo.ext4 with DAX capabilities...\"
rm -rf /tmp/ext4_root
mkdir -p /tmp/ext4_root
cd /")
```
Emits:
```dockerfile
RUN <<EOF
set -e
echo "Building gentoo.ext4 with DAX capabilities..."
rm -rf /tmp/ext4_root
mkdir -p /tmp/ext4_root
cd /
EOF
```

This completely bypasses escaping issues since BuildKit digests the script block literally.

### Strategy C: COPY Here-Documents for Inline Files
For inline configuration files or scripts (like a custom script or a small configuration file), we can write the file content directly inside the `COPY` instruction.

```lisp
(copy :heredoc "install.sh"
      "#!/bin/bash
       echo 'Installing...'
       ./setup.sh")
```
Emits:
```dockerfile
COPY <<EOF install.sh
#!/bin/bash
echo 'Installing...'
./setup.sh
EOF
```

---

## 4. Programmatic Code Generation (Conditionals & Macros)

Because the template is written in Common Lisp, we can use standard Lisp macro expansion and list splicing to conditionally generate Dockerfile structures based on parameters.

### Example: Dynamic Developer & Production Build Stages

```lisp
(defun make-dockerfile (&key (dev-mode t) packages custom-entrypoint)
  `(toplevel
     (directive syntax "docker/dockerfile:1")
     (from "ubuntu:26.04" :as "base")
     (env "DEBIAN_FRONTEND" "noninteractive")
     
     ;; Emerges core packages
     (run (and "apt-get update"
               ,(format nil "apt-get install -y --no-install-recommends ~{~A~^ ~}" packages)
               "rm -rf /var/lib/apt/lists/*"))

     ;; Conditionally include development tools
     ,@(when dev-mode
         `((run (and "apt-get update"
                     "apt-get install -y --no-install-recommends gdb strace htop"
                     "rm -rf /var/lib/apt/lists/*"))
           (env "ENV" "development")))

     (workdir "/app")

     ;; Determine entrypoint/cmd
     ,@(if custom-entrypoint
           `((entrypoint ,custom-entrypoint))
           `((cmd '("/bin/bash"))))))
```

Calling `(make-dockerfile :dev-mode t :packages '("git" "curl") :custom-entrypoint '("python" "main.py"))` returns a complete, structured S-expression tree that can be emitted straight into a formatted Dockerfile.

---

## 5. Proposed Project Structure

We suggest the following design for the `cl-dockerfile-generator` project:

1. **`cl-dockerfile-generator.asd`**: System definition.
2. **`package.lisp`**: Exposes compiler API (e.g. `emit-dockerfile`, `write-dockerfile`) and generator symbols.
3. **`generator.lisp`**: The transpiler implementation. Implements:
   - A custom pprint table (using `set-pprint-dispatch`) to format S-expressions into Dockerfile instructions.
   - Handlers for `and`, `seq`, `:heredoc` block structures.
   - Automatic formatting for array formats (`cmd`, `entrypoint`, `volume`).
4. **`example.lisp`**: Demonstrates usage by generating the `110_gentoo` and `172_docker_agy_env` Dockerfiles using the transpiler.
