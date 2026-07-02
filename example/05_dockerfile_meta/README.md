# cl-dockerfile-generator

`cl-dockerfile-generator` is a Common Lisp DSL and transpiler that allows you to dynamically construct Dockerfiles using S-expressions. By leveraging Common Lisp's case-inversion reader and raw-string macro (`#r`), it eliminates boilerplate, simplifies multi-line shell scripting, and guarantees clean formatting.

🇩🇪 [Deutsche Version dieser Dokumentation / German version of this documentation](README.de.md)

---

## English Documentation

### Case Inversion & Symbols
The generator loads under the `:invert` readtable-case.
- **Normal Symbols**: Write standard commands or variables in uppercase to print in uppercase (e.g., `DEBIAN_FRONTEND` -> `DEBIAN_FRONTEND`), and in lowercase to print in lowercase (e.g., `noninteractive` -> `noninteractive`).
- **Vertical Bars `|...|`**: Use vertical bars to preserve spaces and special characters. For example, `|apt-get update|` prints as `apt-get update`. Make sure to capitalize vertical-bar symbols if you want them to print as lowercase (e.g., `|APT-GET UPDATE|` -> `apt-get update`).
- **Strings**: Standard double-quoted strings (e.g., `"ubuntu:26.04"`) are printed exactly as-is without any case inversion.

---

### Supported Lisp Forms

#### 1. `toplevel`
Groups multiple instructions and prints them sequentially, one per line.
- **Example**:
  ```lisp
  (toplevel
    (from "ubuntu:26.04")
    (run "apt-get update"))
  ```
- **Output**:
  ```dockerfile
  FROM ubuntu:26.04
  RUN apt-get update
  ```

#### 2. `directive`
Emits parser directives (like syntax extensions).
- **Example**: `(directive syntax "docker/dockerfile:1")`
- **Output**: `# syntax=docker/dockerfile:1`

#### 3. `from`
Sets the base image for a build stage. Supports keyword argument `:as` for multi-stage builds.
- **Examples**:
  - `(from "ubuntu:26.04")` -> `FROM ubuntu:26.04`
  - `(from "ubuntu:26.04" :as builder)` -> `FROM ubuntu:26.04 AS builder`

#### 4. `arg`
Defines a build-time argument. Optional default value.
- **Examples**:
  - `(arg VERSION)` -> `ARG VERSION`
  - `(arg DEBIAN_FRONTEND noninteractive)` -> `ARG DEBIAN_FRONTEND=noninteractive`

#### 5. `env`
Sets environment variables. Key-value pairs. Multi-variable declarations are formatted across lines with backslash continuations.
- **Examples**:
  - `(env MY_VAR 123)` -> `ENV MY_VAR=123`
  - `(env VAR1 val1 VAR2 val2)`
    - **Output**:
      ```dockerfile
      ENV VAR1=val1 \
          VAR2=val2
      ```

#### 6. `run`
Runs commands in a new shell layer. Supports:
- **Mounts**: Keyword `:mount` to pass build mount flags.
- **Heredocs**: Keyword `:heredoc` to supply multi-line scripts.
- **Examples**:
  - `(run "apt-get update")` -> `RUN apt-get update`
  - `(run :mount "type=cache,target=/root/.cache/uv" "uv pip install google-antigravity")`
    - **Output**: `RUN --mount=type=cache,target=/root/.cache/uv uv pip install google-antigravity`
  - `(run :heredoc "echo 'hello'\necho 'world'")`
    - **Output**:
      ```dockerfile
      RUN <<EOF
      echo 'hello'
      echo 'world'
      EOF
      ```

#### 7. `and` / `seq` / `pipe`
Logical operators for chain-linking shell commands.
- **`and`** links commands using `&&` with line continuations.
- **`seq`** links commands using `;` with line continuations.
- **`pipe`** links commands with a pipe `|`.
- **Examples**:
  - `(run (and "apt-get update" "apt-get install -y curl"))`
    - **Output**:
      ```dockerfile
      RUN apt-get update \
       && apt-get install -y curl
      ```
  - `(run (seq "cd /tmp" "tar -xf src.tar.gz"))`
    - **Output**:
      ```dockerfile
      RUN cd /tmp \
      ; tar -xf src.tar.gz
      ```
  - `(run (pipe "cat a.txt" "grep -i hello"))`
    - **Output**: `RUN cat a.txt | grep -i hello`

#### 8. `copy` / `add`
Copies files, folders, or remote URLs.
- **Options**: Supports keyword arguments `:from` (build stage) and `:chown` (user/group ownership).
- **Heredocs**: `copy` supports `:heredoc` to write contents directly to a file.
- **Examples**:
  - `(copy "src" "dest")` -> `COPY src dest`
  - `(copy "src" "dest" :from builder :chown "root:root")` -> `COPY --from=builder --chown=root:root src dest`
  - `(copy :heredoc "dest" "hello world")`
    - **Output**:
      ```dockerfile
      COPY <<EOF dest
      hello world
      EOF
      ```
  - `(add "http://example.com/file.tar.gz" "/dest")` -> `ADD http://example.com/file.tar.gz /dest`

#### 9. `expose`
Exposes container network ports.
- **Example**: `(expose 80 443)` -> `EXPOSE 80 443`

#### 10. `label`
Adds descriptive metadata tags to the image.
- **Example**: `(label maintainer "alice" version "1.0")`
- **Output**:
  ```dockerfile
  LABEL maintainer="alice" \
        version="1.0"
  ```

#### 11. `onbuild`
Registers trigger instructions to run when this image is used as a base.
- **Example**: `(onbuild (run "echo 'triggered'"))` -> `ONBUILD RUN echo 'triggered'`

#### 12. `comment`
Writes comments starting with `#`.
- **Example**: `(comment "This is a comment")` -> `# This is a comment`

#### 13. `shell`
Overrides the default shell used to execute commands.
- **Example**: `(shell ("/bin/bash" "-c"))` -> `SHELL ["/bin/bash", "-c"]`

#### 14. `stopsignal`
Sets the system call signal that will be sent to the container to exit.
- **Example**: `(stopsignal SIGTERM)` -> `STOPSIGNAL SIGTERM`

#### 15. `cmd` / `entrypoint` / `volume`
Defines runtime configurations.
- **Lists** are formatted as JSON arrays (exec form).
- **Single symbols/strings** are formatted as shell strings (shell form).
- **Examples**:
  - `(cmd ("echo" "hello"))` -> `CMD ["echo", "hello"]`
  - `(cmd "echo hello")` -> `CMD echo hello`
  - `(entrypoint ("/bin/bash" "-c"))` -> `ENTRYPOINT ["/bin/bash", "-c"]`
  - `(volume ("/data"))` -> `VOLUME ["/data"]`
  - `(volume "/data")` -> `VOLUME /data`

#### 16. `healthcheck`
Sets the health status checks for the container. Options: `:interval`, `:timeout`, `:start-period`, `:retries`.
- **Examples**:
  - `(healthcheck (cmd ("curl" "-f" "http://localhost/")) :interval "5s" :timeout "3s" :retries 3)`
    - **Output**: `HEALTHCHECK --interval=5s --timeout=3s --retries=3 CMD ["curl", "-f", "http://localhost/"]`
  - `(healthcheck NONE :start-period "10s")` -> `HEALTHCHECK --start-period=10s NONE`

#### 17. `#r` (Raw Strings)
Reads multi-line scripts or strings case-sensitively without escaping characters.
- **Bracket Delimiters**: `#r(...)`, `#r[...]`, `#r{...}` (captures everything between brackets, supporting balanced nesting).
- **Arbitrary Delimiters**: `#r#...#`, `#r@...@` (captures everything up to the matching ending character).
- **Example**:
  ```lisp
  #r(echo "hello (world)")
  ```
- **Output**: `echo "hello (world)"`

---
