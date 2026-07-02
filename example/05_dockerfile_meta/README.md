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

### HyperSpec-Style Syntax & Docker Reference

#### 1. `toplevel`
**toplevel** `{`*instruction*`}`\*
- **DSL Description**: Groups multiple instructions and prints them sequentially, one per line.
- **Docker Context**: A generator-specific meta-construct. It has no direct Docker counterpart, but serves to format multiple top-level instructions sequentially.
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
**directive** *name* *value*
- **DSL Description**: Emits parser directives.
- **Docker Context**: Special comments at the very top of a Dockerfile that configure how the builder parses it (e.g., enabling BuildKit features like build mounts).
- **Example**: `(directive syntax "docker/dockerfile:1")`
- **Output**: `# syntax=docker/dockerfile:1`

#### 3. `from`
**from** *image* `[&key` *as*`]`
- **DSL Description**: Sets the base image.
- **Docker Context**: Defines the starting container image for subsequent commands. Every Dockerfile must begin with `FROM`. In multi-stage builds, the optional `:as` parameter names the build stage (e.g. `builder` or `runner`), allowing you to copy files from it later.
- **Examples**:
  - `(from "ubuntu:26.04")` -> `FROM ubuntu:26.04`
  - `(from "ubuntu:26.04" :as builder)` -> `FROM ubuntu:26.04 AS builder`

#### 4. `arg`
**arg** *name* `[`*value*`]`
- **DSL Description**: Defines a build-time argument.
- **Docker Context**: Declares a variable that users can pass during `docker build --build-arg name=value`. Arguments are only available during the build process and are not persisted in the final container.
- **Examples**:
  - `(arg VERSION)` -> `ARG VERSION`
  - `(arg DEBIAN_FRONTEND noninteractive)` -> `ARG DEBIAN_FRONTEND=noninteractive`

#### 5. `env`
**env** `{`*key* *value*`}`\*
- **DSL Description**: Sets environment variables.
- **Docker Context**: Sets environment variables inside the container. These are available both during build-time and at runtime when the container is executed. Multi-variable declarations are formatted across lines with backslashes to reduce image layers.
- **Examples**:
  - `(env MY_VAR 123)` -> `ENV MY_VAR=123`
  - `(env VAR1 val1 VAR2 val2)`
    - **Output**:
      ```dockerfile
      ENV VAR1=val1 \
          VAR2=val2
      ```

#### 6. `run`
**run** `[&key` *mount* *heredoc*`]` *command*
- **DSL Description**: Runs commands.
- **Docker Context**: Executes shell commands to install packages, compile code, or configure settings, creating a new layer on top of the image.
  - `:mount` allows caching files (like package manager databases or package downloads) across builds without saving them in the final image layers (e.g., `RUN --mount=type=cache,...`).
  - `:heredoc` writes multi-line scripts inline directly to the layer, avoiding long chains of `&&`.
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
**and** `{`*command*`}`\*  
**seq** `{`*command*`}`\*  
**pipe** `{`*command*`}`\*
- **DSL Description**: Logical chaining operators.
- **Docker Context**: Helper structures to join shell operations inside a `RUN` layer:
  - **`and`** links commands using `&&` (stops executing if any command fails).
  - **`seq`** links commands using `;` (executes all commands sequentially).
  - **`pipe`** links commands using `|` (streams stdout of the first into stdin of the second).
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

#### 8. `copy`
**copy** `[&key` *from* *chown*`]` `{`*source*`}`\* *destination*  
**copy** `:heredoc` *destination* *content*
- **DSL Description**: Copies files or writes inline file contents.
- **Docker Context**: Copies files/folders from your host machine (build context) into the container image.
  - `:from` copies files from a previous stage of a multi-stage build (crucial for keeping the runner image small).
  - `:chown` changes ownership directly during copying, saving space by avoiding extra `RUN chown` commands.
  - `:heredoc` writes inline text directly to a file inside the container.
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

#### 9. `add`
**add** `[&key` *chown*`]` `{`*source*`}`\* *destination*
- **DSL Description**: Adds remote resources or files.
- **Docker Context**: Similar to `copy`, but has extra capabilities: it can download remote files from URLs and automatically extract local tar/zip archives into the target folder.
- **Example**:
  - `(add "http://example.com/file.tar.gz" "/dest")` -> `ADD http://example.com/file.tar.gz /dest`

#### 10. `expose`
**expose** `{`*port*`}`\*
- **DSL Description**: Declares container ports.
- **Docker Context**: Documents which network ports the container intends to listen on at runtime. It does not publish the ports; it acts as a metadata contract for networking and orchestrators.
- **Example**: `(expose 80 443)` -> `EXPOSE 80 443`

#### 11. `label`
**label** `{`*key* *value*`}`\*
- **DSL Description**: Adds metadata key-value pairs.
- **Docker Context**: Adds descriptive metadata labels (e.g. maintainer, version, description) to the image.
- **Example**: `(label maintainer "alice" version "1.0")`
- **Output**:
  ```dockerfile
  LABEL maintainer="alice" \
        version="1.0"
  ```

#### 12. `onbuild`
**onbuild** *instruction*
- **DSL Description**: Registers an on-build trigger.
- **Docker Context**: Registers a trigger instruction that will execute *later*, when this image is used as a base image for another build (i.e. in another Dockerfile starting with `FROM this-image`).
- **Example**: `(onbuild (run "echo 'triggered'"))` -> `ONBUILD RUN echo 'triggered'`

#### 13. `comment`
**comment** *string*
- **DSL Description**: Writes comment lines.
- **Docker Context**: Formats comments starting with `#` for human documentation.
- **Example**: `(comment "This is a comment")` -> `# This is a comment`

#### 14. `shell`
**shell** `('(` `{`*arg*`}`\* `))`
- **DSL Description**: Configures the default shell.
- **Docker Context**: Overrides the default shell used for executing subsequent `RUN`, `CMD`, and `ENTRYPOINT` instructions (e.g. switching from `/bin/sh -c` to `["/bin/bash", "-c"]`).
- **Example**: `(shell ("/bin/bash" "-c"))` -> `SHELL ["/bin/bash", "-c"]`

#### 15. `stopsignal`
**stopsignal** *signal*
- **DSL Description**: Sets the container stop signal.
- **Docker Context**: Specifies the system call signal that will be sent to the container process to trigger an exit (e.g. `SIGTERM` or `SIGKILL`).
- **Example**: `(stopsignal SIGTERM)` -> `STOPSIGNAL SIGTERM`

#### 16. `cmd`
**cmd** *value*
- **DSL Description**: Sets default command arguments.
- **Docker Context**: Defines the default command that runs when starting a container. If the user runs the container with custom arguments (e.g. `docker run my-image custom-command`), the `cmd` is overridden.
  - If *value* is a **list of strings**, it runs in *exec form* (directly executes the binary without a shell wrapper: `["echo", "hello"]`).
  - If *value* is a **single string or symbol**, it runs in *shell form* (executes as a subcommand of `/bin/sh -c`: `"echo hello"`).
- **Examples**:
  - `(cmd ("echo" "hello"))` -> `CMD ["echo", "hello"]`
  - `(cmd "echo hello")` -> `CMD echo hello`

#### 17. `entrypoint`
**entrypoint** *value*
- **DSL Description**: Sets the default executable entry point.
- **Docker Context**: Configures the container to run as a command-line executable. Unlike `cmd`, the `entrypoint` is *not* overridden when running the container with arguments; instead, those arguments are appended to the entrypoint command. Often used in combination with `cmd` (which then provides default arguments).
- **Examples**:
  - `(entrypoint ("/bin/bash" "-c"))` -> `ENTRYPOINT ["/bin/bash", "-c"]`
  - `(entrypoint "/bin/bash")` -> `ENTRYPOINT /bin/bash`

#### 18. `volume`
**volume** *value*
- **DSL Description**: Creates a storage mount point.
- **Docker Context**: Declares a mount point inside the container. It tells Docker that this directory will hold externally mounted volumes from the host or other containers, bypassing the container's copy-on-write filesystem to persist database files, logs, or source code.
- **Examples**:
  - `(volume ("/data"))` -> `VOLUME ["/data"]`
  - `(volume "/data")` -> `VOLUME /data`

#### 19. `healthcheck`
**healthcheck** *command* `[&key` *interval* *timeout* *start-period* *retries*`]`  
**healthcheck** `NONE`
- **DSL Description**: Configures periodic health checks.
- **Docker Context**: Configures a command to periodically check if the container is running correctly (e.g. testing if a web server is up).
  - `:interval` defines how often to run the check.
  - `:timeout` defines the maximum execution time for each check.
  - `:start-period` is a bootstrap grace period before health checks begin.
  - `:retries` is the number of consecutive failures before marking the container as unhealthy.
  - `NONE` disables any health checks inherited from the parent image.
- **Examples**:
  - `(healthcheck (cmd ("curl" "-f" "http://localhost/")) :interval "5s" :timeout "3s" :retries 3)`
    - **Output**: `HEALTHCHECK --interval=5s --timeout=3s --retries=3 CMD ["curl", "-f", "http://localhost/"]`
  - `(healthcheck NONE :start-period "10s")` -> `HEALTHCHECK --start-period=10s NONE`

#### 20. `#r` (Raw Strings)
**#r** *bracket-delimited-form*  
**#r** *custom-delimiter* *content* *custom-delimiter*
- **DSL Description**: Reads strings literally without Lisp-level escaping.
- **Docker Context**: A reader macro that makes it easy to pass raw text (like regex patterns, sed expressions, or multi-line configuration blocks) to `run` or `copy` without escaping quotes and slashes.
- **Examples**:
  - `#r(echo "hello (world)")` -> `echo "hello (world)"`
  - `#r#echo "custom delimiter"#` -> `echo "custom delimiter"`
