# AI-Focused Docker Environment with Common Lisp, GCC, and AI CLIs

This example demonstrates how to use the Lisp `cl-dockerfile-generator` to create a highly customizable, minimal Docker image containing development tools and AI command-line utilities.

It is based on `02_agy_env` but adds support for multiple AI CLI tools (`codex`, `copilot`, `kiro-cli`, and `grok`) and provides a simple way to toggle individual components on/off to produce minimal images.

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
| `*install-docker-cli*` | Boolean | `t` | Installs Docker CLI and Buildx. Set to `nil` to omit both; use with `setup02_run.sh --docker-sock` when access to the host Docker daemon is needed. |
| `*ubuntu-packages*` | List of strings | `("less" "file" "findutils" "tree" "man-db" "procps" "psmisc" "iproute2" "iputils-ping" "dnsutils" "ripgrep" "fd-find" "yq" "lsof" "strace" "moreutils" "tmux" "shellcheck" "fzf" "bat" "git-lfs" "openssh-client" "dos2unix" "parallel" "unzip" "zip" "xz-utils" "rsync")` | Extra Ubuntu utilities installed into the final runtime image. |
| `*install-agy*` | Boolean | `t` | Fetches, compiles, and installs the Google Antigravity CLI tool (`agy`). |
| `*install-codex*` | Boolean | `t` | Downloads and installs the official OpenAI Codex CLI installer. |
| `*install-copilot*` | Boolean | `t` | Downloads and installs the official GitHub Copilot CLI installer. |
| `*install-kiro-cli*` | Boolean | `t` | Installs `kiro-cli` from Amazon using the official zip package. |
| `*install-grok*` | Boolean | `nil` | Downloads and installs Grok Build from the official x.ai installer. |
| `*install-rust*` | Boolean | `t` | Installs the Rust toolchain (via `rustup`) including `rustc`, `cargo`, `clippy`, and `rustfmt`. |
| `*rust-cache-volume*` | Boolean | `t` | Appends `/root/.cargo` to the list of Docker `VOLUME` mounts to enable Cargo registry caching. |
| `*enable-tests*` | Boolean | `t` | Runs image smoke tests for GCC, Rust, Python, SBCL, Grok Build, and Emacs/SLIME during `docker build`. |

---

## Upstream install sources

The generated Dockerfile now installs the AI CLI tools during the image build instead of copying host binaries from `bin/`.
This makes the example reproducible on any machine with Docker and network access.

- `agy`: `https://antigravity.google/cli/install.sh`
- `codex`: `npm install -g @openai/codex`
- `copilot`: `https://gh.io/copilot-install`
- `kiro-cli`: `https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip`
- `grok`: `https://x.ai/cli/install.sh`

The generated image also wraps `agy`, `copilot`, `codex`, and `grok` so they launch with permissive agent flags by default (`--dangerously-skip-permissions`, `--allow-all`, `--dangerously-bypass-approvals-and-sandbox`, and `--always-approve`), `kiro-cli` so `init` skips confirmation by default with `--force`, while still keeping the original binaries available as `*.real`.

`libxml2-utils` is only worth adding if your agents need XML tooling such as `xmllint`; it’s not a general-purpose default for this image.

---

## External Volume Sharing (Credentials, Cache, and Chat Logs)

To avoid authenticating every time you run a new container and to persist chat histories or intermediate results across container lifecycles, the Dockerfile defines shared volumes:
- `/workspace/src` (where your source code directories are mounted)
- `/root/.config` (shared config directory, containing configuration files for `copilot`, `kiro-cli`, and Grok)
- `/root/.codex` (holds OpenAI Codex CLI authentication and configuration)
- `/root/.cache` (shared cache files for various runtimes/commands)
- `/root/.gemini` (holds `agy` authentication details)
- `/root/.grok` (holds Grok auth, downloads, and completions)
- `/root/.cargo` (holds Cargo's downloaded crates, indexes, and git repositories, preventing re-downloads)

### How to Run

Mount your host's home directories and the cargo cache volume when running the container:

```bash
docker run -it \
  -v "$(pwd)/../../../:/workspace/src" \
  -v "$HOME/.config:/root/.config" \
  -v "$HOME/.cache:/root/.cache" \
  -v "$HOME/.gemini:/root/.gemini" \
  -v "$HOME/.codex:/root/.codex" \
  -v "$HOME/.grok:/root/.grok" \
  -v my-ai-env-cargo-cache:/root/.cargo \
  my-ai-env:latest
```

This mapping allows all CLI tools inside the Docker container to seamlessly share login state and outputs with the host machine, while the named volume `my-ai-env-cargo-cache` keeps your Rust dependencies cached across container rebuilds.

---

## Environment File for Provider Secrets

`setup02_run.sh` reads a local env file at startup. By default it looks for `.env.ai` next to the script, or you can override the path with `ENV_FILE=/path/to/file`.

Use that file for provider-specific secrets and startup settings, for example:

```bash
COPILOT_PROVIDER_TYPE=azure
COPILOT_PROVIDER_BASE_URL=https://eastus2-gpt4-turbo-o.services.ai.azure.com/openai/v1
OPENAI_API_KEY=...
AZURE_OPENAI_API_KEY=...
ANTIGRAVITY_PLAINTEXT_AUTH=1
```

Keep the file out of git; `.gitignore` already excludes `.env` and `.env.*` files in this example directory.

---

## Script Overview

- `setup00_generate_dockerfile.sh` regenerates `Dockerfile` from `gen_ai_env.lisp`. It is the only script that needs SBCL and is mainly for maintainers.
- `setup01_build.sh` builds the image from the checked-in `Dockerfile`. It only needs Docker and a shell, and it creates a temporary `.emacs` if needed for the build context.
- `setup02_run.sh` starts the image with portable defaults. Override `ENV_FILE`, `HOST_SRC_ROOT`, or `IMAGE_NAME` if you need a different env file, source mount, or tag. Pass `--docker-sock` to mount the host Docker socket; this grants the container root-equivalent control of the host Docker daemon.
- `setup03_save.sh` exports the image with `docker save`. It writes a tar file next to the script by default and also creates a `.zst` copy when `zstd` is installed.
- `setup04_cleanup.sh` performs targeted cleanup for this example: it stops and removes containers created from `IMAGE_NAME`, removes that image tag, can optionally remove the Cargo cache volume or prune dangling images, can suggest cleanup command variants with estimated reclaimable space, and can list or remove other local images sorted by size or age.

On Linux/macOS, run the scripts with the system shell or `sh`. On Windows, they work when you have a compatible shell such as Git Bash or WSL plus Docker Desktop.

## How to Regenerate the Dockerfile

If you changed `gen_ai_env.lisp`, regenerate the Dockerfile with:

```bash
./setup00_generate_dockerfile.sh
```

Most users do not need this step because the generated `Dockerfile` is already committed.

When `*enable-tests*` is `t`, the generated image also runs small build-time checks for the installed tools, including Grok Build, and a SLIME workflow test that opens and loads a Lisp file.


## Example Docker Image

As of 2026-07-09 the docker image with all features has a size of 4.3GB

```
$ docker images
                                                                                                           i Info →   U  In Use
IMAGE                                            ID             DISK USAGE   CONTENT SIZE   EXTRA
my-ai-env:latest                                 6486ad1b813a        4.3GB             0B
```
The image can be exported using `setup03_save.sh`
Compressed the image is 1.2G. 
```
-rw------- 1 kiel kiel 1.2G Jul  9 05:49 my-ai-env.tar.zst
```
