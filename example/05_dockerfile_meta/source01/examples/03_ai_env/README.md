# AI-Focused Docker Environment with Common Lisp, GCC, and AI CLIs

This example demonstrates how to use the Lisp `cl-dockerfile-generator` to create a highly customizable, minimal Docker image containing development tools and AI command-line utilities.

It is based on `02_agy_env` but adds support for multiple AI CLI tools (`codex`, `copilot`, and `kiro-cli`) and provides a simple way to toggle individual components on/off to produce minimal images.

---

## Supported Features & Configuration

You can easily customize the generated image directly in [gen_ai_env.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/gen_ai_env.lisp) by toggling the parameters at the top of the file:

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `*base-image*` | String | `"ubuntu:26.04"` | The base OS image to build upon. |
| `*install-gcc*` | Boolean | `t` | Installs the GCC compiler (`build-essential` and `gcc`). |
| `*install-sbcl*` | Boolean | `t` | Installs Common Lisp (`sbcl`, `rlwrap`), Quicklisp, and pre-caches systems (`alexandria`, `jonathan`, `cl-ppcre`, etc.). |
| `*install-emacs*` | Boolean | `t` | Installs terminal Emacs (`emacs-nox`), pre-installs SLIME/magit/gptel, and copies `.emacs`. (Only runs if `*install-sbcl*` is `t`). |
| `*install-python*` | Boolean | `t` | Installs Python 3 runtime. |
| `*install-python-libs*` | Boolean | `t` | Installs Python libraries (like `google-antigravity` SDK) using a cache-mounted multi-stage builder. |
| `*install-agy*` | Boolean | `t` | Fetches, compiles, and installs the Google Antigravity CLI tool (`agy`). |
| `*install-codex*` | Boolean | `t` | Copies the `codex` CLI tool from the local build context. |
| `*install-copilot*` | Boolean | `t` | Copies the `copilot` CLI tool from the local build context. |
| `*install-kiro-cli*` | Boolean | `t` | Copies the `kiro-cli` CLI tool from the local build context. |
| `*install-rust*` | Boolean | `t` | Installs the Rust toolchain (via `rustup`) including `rustc`, `cargo`, `clippy`, and `rustfmt`. |
| `*rust-cache-volume*` | Boolean | `t` | Appends `/root/.cargo` to the list of Docker `VOLUME` mounts to enable Cargo registry caching. |

---

## Handling Local Host CLI Tools

For the proprietary or user-installed CLI tools (`codex`, `copilot`, and `kiro-cli`), the generator relies on copying them from a local `bin/` directory within the Docker build context. 

The provided [build.sh](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/build.sh) script automatically takes care of this:
1. It searches the host machine for `codex`, `copilot`, and `kiro-cli` using `which`.
2. If found, it copies the actual binary/executable to `./bin/` (dereferencing symlinks using `cp -L`).
3. If not found on the host, it prints a note and proceeds (you can manually place the binary at `bin/<tool>` if desired).

---

## External Volume Sharing (Credentials, Cache, and Chat Logs)

To avoid authenticating every time you run a new container and to persist chat histories or intermediate results across container lifecycles, the Dockerfile defines four volumes:
- `/workspace/src` (where your source code directories are mounted)
- `/root/.config` (shared config directory, containing configuration files for `codex`, `copilot`, and `kiro-cli`)
- `/root/.cache` (shared cache files for various runtimes/commands)
- `/root/.gemini` (holds `agy` authentication details)
- `/root/.cargo` (holds Cargo's downloaded crates, indexes, and git repositories, preventing re-downloads)

### How to Run

Mount your host's home directories and the cargo cache volume when running the container:

```bash
docker run -it \
  -v "$(pwd)/../../../:/workspace/src" \
  -v "$HOME/.config:/root/.config" \
  -v "$HOME/.cache:/root/.cache" \
  -v "$HOME/.gemini:/root/.gemini" \
  -v my-ai-env-cargo-cache:/root/.cargo \
  my-ai-env:latest
```

This mapping allows all CLI tools inside the Docker container to seamlessly share login state and outputs with the host machine, while the named volume `my-ai-env-cargo-cache` keeps your Rust dependencies cached across container rebuilds.

---

## How to Generate the Dockerfile

To compile the `gen_ai_env.lisp` file into the final `Dockerfile`, simply run:

```bash
./build.sh
```

This will run the SBCL generation script and prepare the build context for `docker build`.
