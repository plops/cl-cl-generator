# AI-Focused Docker Environment with Common Lisp, GCC, and AI CLIs

This example demonstrates how to use the Lisp `cl-dockerfile-generator` to create a highly customizable, minimal Docker image containing development tools and AI command-line utilities.

It is based on `02_agy_env` but adds support for multiple AI CLI tools (`muse`, `claude`, `kiro-cli`, `copilot`, `codex`, and more) and provides a simple way to toggle individual components on/off to produce minimal images.

---

## Supported Features & Configuration

Customize the generated image by changing the parameters in section 1 (“Configuration”) of [`gen_ai_env.lisp`](gen_ai_env.lisp), then regenerate `Dockerfile`. The defaults below match the checked-in generator; `test_ai_env_generation.sh` fails when a default in this README drifts from the code.

Sub-features (difftastic, probe-rs, Quicklisp, SLIME) are only installed when their parent switch is on. Values such as the CUDA base image, the Python package list, and toolchain directory names are derived at generation time, so switches can also be changed with `setf` after loading the generator (see [How to Regenerate the Dockerfile](#how-to-regenerate-the-dockerfile)).

### Base image and shared behavior

| Parameter | Default | What it controls |
| :--- | :--- | :--- |
| `*enable-cuda*` | `t` | Selects the NVIDIA CUDA base image, exports CUDA runtime/development paths, and adds CUDA-only Python packages. Set it to `nil` for plain `ubuntu:26.04`. |
| `*cuda-flavor*` | `:cudnn-devel` | CUDA image variant: `:cudnn-devel`, `:devel`, `:cudnn-runtime`, `:runtime`, or `:base`. The `nvcc` smoke test is only generated for the two `devel` flavors. |
| `*cuda-version*` | `"13.3.1"` | Version part of the NVIDIA CUDA image tag. |
| `*cuda-ubuntu-version*` | `"ubuntu26.04"` | Ubuntu suffix of the NVIDIA CUDA image tag. |
| `*ubuntu-image*` | `"ubuntu:26.04"` | Runner/Python-builder base when CUDA is disabled. |
| `*base-image*` | `nil` | `nil` means “computed from the CUDA settings”; set a string to force a base image for the runner and the Python builder. |
| `*builder-base-image*` | `"ubuntu:26.04"` | Small base used by the independent CLI download stages. |
| `*ubuntu-packages*` | utility list | Interactive and firmware-development Ubuntu packages installed in the runner. |
| `*enable-tests*` | `t` | Emits build-time smoke tests for enabled features. `nil` skips all smoke tests but does not disable any installation. |

### Languages, firmware, and system tools

| Parameter | Default | What it controls |
| :--- | :--- | :--- |
| `*install-gcc*` | `t` | GCC, `build-essential`, the C/C++ tools in `*gcc-ubuntu-packages*` (clang-format, clang-tidy, ninja, cmake, pkg-config, gdb), and a compile/run smoke test. Rust also pulls in the build packages. |
| `*install-sbcl*` | `t` | SBCL and `rlwrap`, so the Lisp generator can run in the working container. |
| `*install-quicklisp*` | `t` | With SBCL: Quicklisp, `.sbclrc`, local-project symlinks (`*quicklisp-local-projects*`) and pre-fetched systems (`*quicklisp-systems*`). |
| `*install-emacs*` | `nil` | Terminal Emacs, the packages in `*emacs-packages*` and the `.emacs` from the build context. SLIME and its smoke test are added only when SBCL is installed too. |
| `*install-python*` | `t` | System Python 3 runtime (`python3-full`). |
| `*install-python-libs*` | `t` | A separate uv-built virtual environment `/workspace/.venv` containing `*python-libs*` (plus `*python-cuda-libs*` with CUDA); a smoke test imports every package. |
| `*install-rust*` | `t` | Stable Rust via rustup and a compile/run smoke test. |
| `*install-difftastic*` | `t` | With Rust: difftastic, configured as git's external diff. |
| `*install-probe-rs*` | `t` | With Rust: probe-rs embedded debugging tools. |
| `*install-conan*` | `t` | Conan C/C++ package manager as an isolated uv tool. |
| `*install-docker-cli*` | `t` | Docker CLI and Buildx only—not a daemon. Combine it with `setup02_run.sh --docker-sock`. |
| `*install-arm-none-eabi*` | `t` | Arm GNU bare-metal toolchain and a Cortex-M7 compile smoke test. |
| `*arm-none-eabi-version*` | `"15.3.rel2"` | Pinned Arm GNU toolchain release used to derive its download name/path. |
| `*install-jlink*` | `t` | SEGGER J-Link command-line tools and a version smoke test. The download accepts SEGGER's license terms. |
| `*jlink-version*` | `"9.92"` | Pinned J-Link release used to derive its download name/path. |

### Agent CLIs

Every agent CLI is installed as `/usr/local/bin/<name>.real` plus a small wrapper `/usr/local/bin/<name>` that adds permissive default flags.

| Parameter | Default | What it controls |
| :--- | :--- | :--- |
| `*install-muse*` | `t` | Meta Muse Code CLI; the wrapper adds `--yolo`. |
| `*install-claude*` | `t` | Claude Code (native build); the wrapper adds `--dangerously-skip-permissions`. State lives in `CLAUDE_CONFIG_DIR=/root/.claude`, which `setup02_run.sh` bind-mounts from the host; auto-updates are disabled because the binary is image-managed. |
| `*install-kiro-cli*` | `t` | Kiro CLI; the wrapper turns `kiro-cli init` into `init --force`. |
| `*install-copilot*` | `t` | GitHub Copilot CLI; the wrapper adds `--allow-all`. |
| `*install-codex*` | `t` | Latest npm Codex CLI; the wrapper adds `--dangerously-bypass-approvals-and-sandbox --no-daemon`. |
| `*install-agy*` | `nil` | Google Antigravity CLI; the wrapper adds `--dangerously-skip-permissions`. |
| `*install-grok*` | `nil` | Grok Build (`grok` and `agent`); the `grok` wrapper adds `--always-approve`. |
| `*install-devin-cli*` | `nil` | Devin CLI; the wrapper adds `--permission-mode bypass`. |
| `*install-kirocrew*` | `nil` | KiroCrew with its managed Python runtime and gateway wrapper. Requires `*install-kiro-cli*`. See [KiroCrew](#kirocrew). |
| `*kirocrew-version*` | `"0.7.2"` | Pinned signed KiroCrew release. |

### Cloud, CI, and quality tools

| Parameter | Default | What it controls |
| :--- | :--- | :--- |
| `*install-azure-cli*` | `nil` | Azure CLI from Microsoft's apt repository. |
| `*install-teamcity-cli*` | `nil` | TeamCity CLI from JetBrains' installer. |
| `*install-habit-hooks*` | `nil` | Habit Hooks with all optional integrations, installed as an isolated uv tool. |
| `*install-deptry*` | `nil` | Deptry installed as an isolated uv tool. |
| `*install-jscpd*` | `nil` | JSCPD installed globally with npm. |
| `*install-archify*` | `nil` | Archify's Codex skill, Chrome for Testing, its shared libraries (`*archify-browser-packages*`), browser environment, and Archify/browser smoke test. |
| `*archify-chrome-build*` | `"stable"` | Chrome for Testing channel or exact version. Use an exact version for reproducible builds. |

---

## Upstream install sources

The generated Dockerfile now installs the AI CLI tools during the image build instead of copying host binaries from `bin/`.
This makes the example reproducible on any machine with Docker and network access.

- `muse`: `https://dev.meta.ai/install.sh`
- `claude`: `https://claude.ai/install.sh`
- `kiro-cli`: `https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip`
- `copilot`: `https://gh.io/copilot-install`
- `codex`: `npm install -g @openai/codex@<latest>`
- `agy`: `https://antigravity.google/cli/install.sh`
- `grok`: `https://x.ai/cli/install.sh`
- `devin`: `https://cli.devin.ai/install.sh`
- KiroCrew: `https://download.crew.kiro.dev/cli.sh` (signed release manifest)
- TeamCity CLI: `https://jb.gg/tc/install`
- uv: `ghcr.io/astral-sh/uv:latest`
- Rust: `https://sh.rustup.rs`; probe-rs: GitHub release installer; difftastic: `cargo install`
- Archify: `npx skills add tt-a1i/archify` from `https://github.com/tt-a1i/archify`
- Chrome for Testing: `npx @puppeteer/browsers install chrome@<build>`
- Arm GNU Toolchain: `https://gitlab.arm.com/tooling/gnu-toolchains-for-arm/` (pinned by `*arm-none-eabi-version*`)
- SEGGER J-Link: `https://www.segger.com/downloads/jlink/` (pinned by `*jlink-version*`)

### Reproducibility

Only the Arm toolchain, J-Link, KiroCrew and the CUDA base image are pinned. Everything else follows its upstream “latest/stable” channel (`uv:latest`, the newest Codex npm release, the Kiro/Copilot/Claude/Muse installers, rustup `stable`, probe-rs `latest`, Chrome for Testing `stable`), so two builds on different days can differ. Several tools are installed with `curl … | sh`; for this development image that is a deliberate trade-off of convenience over supply-chain hardening.

`libxml2-utils` is only worth adding if your agents need XML tooling such as `xmllint`; it’s not a general-purpose default for this image.

### Archify

With `*install-archify*` enabled, the generated image installs the skill at `/root/.agents/skills/archify` and Chrome for Testing below `/opt/archify-browser`. `/usr/local/bin/archify-chrome` is a stable symlink to the versioned browser executable, and these variables let Archify use it while running as root in the container:

```text
ARCHIFY_CHROME=/usr/local/bin/archify-chrome
ARCHIFY_CHROME_NO_SANDBOX=1
```

The browser deliberately lives under `/opt`, not `/root/.cache`: `setup02_run.sh` mounts the host cache over `/root/.cache`, which would hide a browser stored there. The skill remains under `/root/.agents`, which that script does not mask.

Use an exact `*archify-chrome-build*` value instead of `"stable"` when byte-for-byte repeatability matters. The skill installer follows the selected upstream repository state; production users should additionally pin a reviewed Archify revision when the `skills` CLI supports that workflow.

After the image is built, the same essential checks used during the build can be run manually:

```bash
docker run --rm my-ai-env:latest \
  node /root/.agents/skills/archify/bin/archify.mjs doctor

docker run --rm my-ai-env:latest \
  /usr/local/bin/archify-chrome --headless --no-sandbox \
  --disable-gpu --dump-dom about:blank
```

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

`setup02_run.sh` runs the container as root (`--user 0:0`, `HOME=/root`); running with the host UID did not work reliably with the installed tools. Consequently, files created below `/workspace/src` from inside the container are owned by root on the host (unless Docker runs rootless). The host credential directories are bind-mounted below `/root`. Containers are started with `--rm` and named `ai-env-<pid>` (override with `CONTAINER_NAME`).

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
- `setup02_run.sh` starts the image with portable defaults. Override `ENV_FILE`, `HOST_SRC_ROOT`, `SOURCE_REPOS` or `IMAGE_NAME` if you need a different env file, source mount, or tag. With `--source-isolation` (default) only the repos in `SOURCE_REPOS` below `HOST_SRC_ROOT` are mounted; missing ones are skipped with a warning. Pass `--gpus all` (or `--gpu`) to enable NVIDIA GPU passthrough; if Docker has no NVIDIA support (no NVIDIA Container Toolkit/CDI, e.g. on an Intel/AMD laptop) the script warns and starts without GPUs (`FORCE_NVIDIA=1` skips the check). `--graphics` passes `/dev/dri`, X11 and `--ipc=host`. `--usb`/`--host-kmsg` run privileged (all host devices visible), `--docker-sock` mounts the host Docker socket. `--host-opt` exposes host `/opt` read-only at `/host/opt`; it deliberately does not replace the image's `/opt` because CUDA's entrypoint lives there.
- `setup02_run.sh --host-ssh` (default off) lets the container ssh into the host: it creates a temporary ed25519 key, appends it to `~/.ssh/authorized_keys` restricted with `from="<docker bridge subnet>,127.0.0.1,::1"`, maps the private key to `/root/.ssh/id_host` and installs `/etc/ssh/ssh_config.d/00-ai-env-host.conf`, so `ssh host` works inside the container. The host's own host keys are pinned (`StrictHostKeyChecking yes`). Key and `authorized_keys` entry are removed when the container exits. The alias lives in `ssh_config.d` rather than `/root/.ssh/config`, because `/root/.ssh` is the bind-mounted host `~/.ssh` (a change there would alter the host config, and OpenSSH rejects a user config not owned by root). Requires a running sshd that listens on the Docker bridge; `HOST_SSH_PORT`/`HOST_SSH_USER` override port and user.
- `setup03_save.sh` exports the image with `docker save`. It writes a tar file next to the script by default and also creates a `.zst` copy when `zstd` is installed.
- `setup04_cleanup.sh` performs targeted cleanup for this example: it stops and removes containers created from `IMAGE_NAME`, removes that image tag, can optionally remove the Cargo cache volume or prune dangling images, can suggest cleanup command variants with estimated reclaimable space, and can list or remove other local images sorted by size or age.

On Linux/macOS, run the scripts with the system shell or `sh`. On Windows, they work when you have a compatible shell such as Git Bash or WSL plus Docker Desktop.

## How to Regenerate the Dockerfile

If you changed `gen_ai_env.lisp`, regenerate the Dockerfile with:

```bash
./setup00_generate_dockerfile.sh
```

Most users do not need this step because the generated `Dockerfile` is already committed.

Loading the generator writes `./Dockerfile` (only when its content changes). To generate a variant without touching it, set `AI_ENV_NO_AUTOGEN=1`, change switches with `setf`, and call `generate-ai-env` with another path:

```bash
AI_ENV_NO_AUTOGEN=1 sbcl --non-interactive --eval '(require "asdf")' --load gen_ai_env.lisp \
  --eval '(in-package :cl-dockerfile-generator)' \
  --eval '(setf *enable-cuda* nil *install-emacs* t)' \
  --eval '(generate-ai-env #p"/tmp/no-cuda.Dockerfile")'
```

`./test_ai_env_generation.sh` checks the generator without a Docker build: a golden matrix of 8 switch combinations (`../../../plan/20261119_01_refactor_ai_env/golden/`) must produce byte-identical Dockerfiles, derived values must follow `setf`, the wrappers of the daily-use CLIs must be present, and the README defaults must match the code. After an intended change of the output, refresh the golden files with `golden/check.sh --update` and review the diff.

When `*enable-tests*` is `t`, the generated image runs the smoke-test entry for each enabled feature during `docker build`. Coverage includes real GCC/Rust/Arm/CUDA compilation, version checks through the wrappers of muse, claude, kiro-cli (including `acp`), copilot and codex, Python venv imports, an Emacs/SLIME workflow, and Archify `doctor`, demo rendering, and a real headless-Chrome DOM render. Tests are conditional on the same feature flags as their installations. Run Archify `visual-check` on delivered diagrams at runtime; its multi-viewport screenshot inspection is deliberately not a build gate because Chrome DevTools capture can be flaky in container builds.

## Fountain firmware development

The image contains the tool versions expected by `~/stage/fountain/sensor/vscode/wsl/setup.sh`, so mounting the host's `/opt` is not required. Build and start a firmware-development shell with:

```bash
./setup01_build.sh
./setup02_run.sh --usb
```

Add `--gpus all` when the same session also needs CUDA. Use `--host-opt` only when unrelated host-installed software must be inspected under `/host/opt`.


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

# Nvidia Container Toolkit 

# Installation On Pop-OS

Make sure the pop-os host has the newest nvidia driver. Install and validate the container toolkit:
```bash
sudo apt install nvidia-docker2
sudo systemctl restart docker
docker run --rm --gpus all nvidia/cuda:13.3.1-base-ubuntu26.04 nvidia-smi
```

# Installation on Gentoo

```
sudo emerge -av app-containers/nvidia-container-toolkit
```

### Enabling CUDA in this Environment

To build an image with NVIDIA GPU and CUDA support:
1. In `gen_ai_env.lisp`, set `(defparameter *enable-cuda* t)`. Optionally select your flavor (e.g. `(defparameter *cuda-flavor* :devel)` or `:cudnn-devel`).
2. Regenerate the Dockerfile and build the image:
   ```bash
   ./setup00_generate_dockerfile.sh
   ./setup01_build.sh
   ```
3. Run the container with GPU passthrough enabled:
   ```bash
   ./setup02_run.sh --gpus all
   ```

NVIDIA's CUDA 13.3.1 (Ubuntu 26.04) Docker images offer varying sizes based on build-time components or runtime-only environments, ranging from 199.7 MB (base) to 4.38 GB (devel). The cudnn-devel image supports heavy development, while the base image provides minimal deployment capabilities.

| Image Tag Variant | Size (amd64) | Size (arm64) | Primary Purpose |
|---|---|---|---|
| cudnn-devel | 4.38 GB | 4.58 GB | AI/Deep Learning development (cuDNN + compiler) |
| devel | 3.86 GB | 3.97 GB | General GPU development (compiler only) |
| cudnn-runtime | 2.12 GB | 2.51 GB | AI/Deep Learning production (cuDNN) |
| runtime | 1.6 GB | 1.9 GB | General GPU production |
| base | 199.7 MB | 345.86 MB | Minimal deployment/driver linking |

For production, prioritize the runtime or cudnn-runtime images, while the devel options are recommended for compilation.
# KiroCrew

Mit `*install-kirocrew* t` enthält das Image KiroCrew 0.7.2 (Default: aus). Der offizielle Installer prüft eine signierte
Release-Meldung und den SHA-256-Prüfwert des Wheels und richtet CPython 3.12
mit dem von KiroCrew gepinnten `uv` ein.

`setup02_run.sh` unterstützt KiroCrew nicht mehr: es gibt kein Portmapping für 5476,
kein `KIROCREW_HOME`/`KIROCREW_BIND` und keine `--kirocrew-*`-Optionen. Wer KiroCrew
trotzdem nutzt, muss Port, Datenpfad (`~/.kiro/crew-yolo`) und ggf. Seccomp-Profil
selbst an `docker run` übergeben.
