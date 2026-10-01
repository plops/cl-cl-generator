# AI-Focused Docker Environment with Common Lisp, GCC, and AI CLIs

This example demonstrates how to use the Lisp `cl-dockerfile-generator` to create a highly customizable, minimal Docker image containing development tools and AI command-line utilities.

It is based on `02_agy_env` but adds support for multiple AI CLI tools (`codex`, `copilot`, `kiro-cli`, and `grok`) and provides a simple way to toggle individual components on/off to produce minimal images.

---

## Supported Features & Configuration

Customize the generated image by changing the parameters near the top of [`gen_ai_env.lisp`](gen_ai_env.lisp), then regenerate `Dockerfile`. The defaults below match the checked-in generator.

### Base image and shared behavior

| Parameter | Default | What it controls |
| :--- | :--- | :--- |
| `*enable-cuda*` | `t` | Selects the NVIDIA CUDA base image, exports CUDA runtime/development paths, and enables the CUDA smoke test. Set it to `nil` for plain `ubuntu:26.04`. |
| `*cuda-flavor*` | `:devel` | CUDA image variant: `:cudnn-devel`, `:devel`, `:cudnn-runtime`, `:runtime`, or `:base`. Compiler smoke coverage is useful with a `devel` variant; runtime/base variants intentionally may not contain `nvcc`. |
| `*cuda-version*` | `"13.4.1"` | Version part of the NVIDIA CUDA image tag. |
| `*cuda-ubuntu-version*` | `"ubuntu26.04"` | Ubuntu suffix of the NVIDIA CUDA image tag. |
| `*base-image*` | computed | Final runner and Python-builder base. It is computed from the CUDA settings; override it only when deliberately replacing that selection. |
| `*builder-base-image*` | `"ubuntu:26.04"` | Small base used by independent CLI download stages. |
| `*ubuntu-packages*` | utility list | Extra interactive and firmware-development Ubuntu packages installed in the runner. Edit the list to trim or extend the general tool belt. |
| `*enable-tests*` | `t` | Emits build-time smoke tests for enabled features. Setting this to `nil` skips all smoke tests but does not disable any installation. |

### Languages, firmware, and system tools

| Parameter | Default | What it controls |
| :--- | :--- | :--- |
| `*install-gcc*` | `nil` | GCC, `build-essential`, and a compile/run smoke test. Rust also pulls in these build packages. |
| `*install-sbcl*` | `t` | SBCL and `rlwrap`, so the Lisp generator can run in the working container. |
| `*install-quicklisp*` | `nil` | When SBCL is enabled, optionally install Quicklisp and cached Lisp systems. |
| `*install-emacs*` | `nil` | Terminal Emacs. SLIME setup and the Emacs/SLIME integration test require both this and `*install-sbcl*`. |
| `*install-python*` | `t` | System Python 3 runtime. |
| `*install-python-libs*` | `t` | A separate uv-built virtual environment containing `*python-libs*`; this also ensures system Python is present. |
| `*python-libs*` | package list | Python packages installed into `/workspace/.venv`. CUDA-specific packages are appended only when CUDA is enabled. |
| `*install-rust*` | `nil` | Stable Rust via rustup, including `rustc`, Cargo, Clippy, rustfmt, and a compile/run smoke test. |
| `*install-difftastic*` | `t` | Installs and configures difftastic when Rust is enabled. It has no effect when `*install-rust*` is `nil`. |
| `*rust-cache-volume*` | `t` | Declares `/root/.cargo` as a Docker volume when Rust is enabled. |
| `*install-docker-cli*` | `t` | Docker CLI and Buildx only—not a daemon. Combine it with `setup02_run.sh --docker-sock` to use the host daemon. |
| `*install-arm-none-eabi*` | `nil` | Arm GNU bare-metal toolchain and Cortex-M7 compile smoke test. |
| `*arm-none-eabi-version*` | `"15.3.rel1"` | Pinned Arm GNU toolchain release used to derive its download name/path. |
| `*install-jlink*` | `nil` | SEGGER J-Link command-line tools and version smoke test. The download accepts SEGGER's license terms. |
| `*jlink-version*` | `"9.30"` | Pinned J-Link release used to derive its download name/path. |

### Agent, cloud, and quality tools

| Parameter | Default | What it controls |
| :--- | :--- | :--- |
| `*install-agy*` | `nil` | Google Antigravity CLI and its permissive wrapper. |
| `*install-codex*` | `t` | Latest npm Codex CLI plus a wrapper that bypasses approvals/sandboxing by default. |
| `*install-copilot*` | `nil` | GitHub Copilot CLI plus an `--allow-all` wrapper. |
| `*install-kiro-cli*` | `t` | Kiro CLI and helper binaries plus a wrapper that defaults to trusted/non-interactive operation. |
| `*install-kirocrew*` | `t` | KiroCrew 0.7.2 with its managed Python runtime and gateway wrapper. |
| `*install-azure-cli*` | `nil` | Azure CLI from Microsoft's apt repository. |
| `*install-teamcity-cli*` | `nil` | TeamCity CLI from JetBrains' installer. |
| `*install-grok*` | `nil` | Grok Build and its permissive wrapper. |
| `*install-muse*` | `nil` | Meta Muse Code CLI, installed with Meta's official installer. |
| `*install-habit-hooks*` | `nil` | Habit Hooks with all optional integrations, installed as an isolated uv tool. |
| `*install-deptry*` | `nil` | Deptry installed as an isolated uv tool. |
| `*install-jscpd*` | `nil` | JSCPD installed globally with npm. |
| `*install-archify*` | `nil` | Archify's Codex skill, Chrome for Testing, its shared libraries, browser environment, and Archify/browser smoke test. |
| `*archify-chrome-build*` | `"stable"` | Chrome for Testing channel or exact version. Use an exact version for reproducible builds. |

Derived parameters such as `*arm-none-eabi-toolchain*`, `*jlink-version-code*`, `*jlink-directory*`, and `*archify-browser-packages*` normally should not be edited independently; they keep emitted names and dependency lists centralized.

---

## Upstream install sources

The generated Dockerfile now installs the AI CLI tools during the image build instead of copying host binaries from `bin/`.
This makes the example reproducible on any machine with Docker and network access.

- `agy`: `https://antigravity.google/cli/install.sh`
- `codex`: `npm install -g @openai/codex`
- `copilot`: `https://gh.io/copilot-install`
- `kiro-cli`: `https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip`
- `grok`: `https://x.ai/cli/install.sh`
- `muse`: `https://dev.meta.ai/install.sh`
- Archify: `npx skills add tt-a1i/archify` from `https://github.com/tt-a1i/archify`
- Chrome for Testing: `npx @puppeteer/browsers install chrome@<build>`
- Arm GNU Toolchain: `https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads`
- SEGGER J-Link: `https://www.segger.com/downloads/jlink/`

The generated image also wraps `agy`, `copilot`, `codex`, and `grok` so they launch with permissive agent flags by default (`--dangerously-skip-permissions`, `--allow-all`, `--dangerously-bypass-approvals-and-sandbox`, and `--always-approve`), `kiro-cli` so `init` skips confirmation by default with `--force`, while still keeping the original binaries available as `*.real`.

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

`setup02_run.sh` starts the container with the invoking host user's numeric UID, GID and supplementary groups. This is important for bind mounts: files created or modified below `/workspace/src` are therefore owned by the host user instead of container `root`. With `--docker-sock`, it also passes the socket's numeric group. The generator makes `/root` traversable so the existing credential mounts below `/root` remain usable by that numeric user. Run the container through `setup02_run.sh` rather than calling `docker run` without `--user`.

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
- `setup02_run.sh` starts the image with portable defaults. Override `ENV_FILE`, `HOST_SRC_ROOT`, or `IMAGE_NAME` if you need a different env file, source mount, or tag. Pass `--gpus all` (or `--gpu`) to enable NVIDIA GPU passthrough, `--usb` for privileged J-Link USB access, and `--docker-sock` to mount the host Docker socket. `--host-opt` exposes host `/opt` read-only at `/host/opt`; it deliberately does not replace the image's `/opt` because CUDA's entrypoint lives there.
- `setup03_save.sh` exports the image with `docker save`. It writes a tar file next to the script by default and also creates a `.zst` copy when `zstd` is installed.
- `setup04_cleanup.sh` performs targeted cleanup for this example: it stops and removes containers created from `IMAGE_NAME`, removes that image tag, can optionally remove the Cargo cache volume or prune dangling images, can suggest cleanup command variants with estimated reclaimable space, and can list or remove other local images sorted by size or age.

On Linux/macOS, run the scripts with the system shell or `sh`. On Windows, they work when you have a compatible shell such as Git Bash or WSL plus Docker Desktop.

## How to Regenerate the Dockerfile

If you changed `gen_ai_env.lisp`, regenerate the Dockerfile with:

```bash
./setup00_generate_dockerfile.sh
```

Most users do not need this step because the generated `Dockerfile` is already committed.

When `*enable-tests*` is `t`, the generated image runs the smoke-test entry for each enabled feature. Coverage includes real GCC/Rust/Arm/CUDA compilation, CLI version/help checks, an Emacs/SLIME workflow, and Archify `doctor`, demo rendering, and a real headless-Chrome DOM render. Tests are conditional on the same feature flags as their installations. Run Archify `visual-check` on delivered diagrams at runtime; its multi-viewport screenshot inspection is deliberately not a build gate because Chrome DevTools capture can be flaky in container builds.

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

Das Image enthält KiroCrew 0.7.2. Der offizielle Installer prüft eine signierte
Release-Meldung und den SHA-256-Prüfwert des Wheels und richtet CPython 3.12
mit dem von KiroCrew gepinnten `uv` ein.

Für einen kleinen Integrations-Build ohne CUDA und ohne die übrigen AI-Tools:

```sh
./test_kirocrew_minimal_build.sh
```

Der Test erzeugt vorübergehend ein Ubuntu-26-Image mit KiroCrew, kiro-cli,
Docker-CLI, Python und SBCL, baut es und prüft Gateway,
Authentisierungsgrenze und Persistenz. CUDA, weitere AI-Tools, schwere
Python-Bibliotheken und Quicklisp fehlen in dieser Variante.
Voraussetzungen sind `sbcl`, `uv` und Zugriff auf einen Docker-Daemon.

Zum Start des regulären Arbeitscontainers mit Zugriff auf den Docker-Daemon:

```sh
./setup02_run.sh --docker-sock --no-source-isolation
```

Falls das vorhandene Image Codex oder Docker-CLI noch nicht enthält, vorher
neu bauen:

```sh
./setup00_generate_dockerfile.sh
./setup01_build.sh
./setup02_run.sh --docker-sock --no-source-isolation
```

Das reguläre Image enthält weiterhin den Codex-Launcher. Das oben erzeugte
kleine `kirocrew-validation:local` ist ausschließlich das Prüfimage und enthält
keinen Codex-Launcher. Es wird vom Integrationstest automatisch gestartet.
Der normale Generator ist derzeit ohne CUDA konfiguriert. Der separate
KiroCrew-Validierungsbuild ist ebenfalls CUDA-frei und schaltet weitere große
Komponenten gezielt ab.

`setup02_run.sh` führt die Programme im Container als Root aus und setzt
`HOME=/root`. Die Credential-Verzeichnisse des Host-Benutzers werden dort
eingehängt. Ein Lauf mit Host-UID 1000 (`kiel`) war das gewünschte Ziel,
funktionierte mit den installierten Programmen aber nicht zuverlässig; daher
bleibt Root der geprüfte Betriebsmodus. Mit `--docker-sock` wird zusätzlich
der Docker-Socket eingebunden und seine numerische Gruppe ergänzt. Dadurch
kann die Docker-CLI im Container den Host-Daemon ansprechen; diese Option
verleiht weitreichende Host-Rechte. Prüfe nach dem Start `id`, `docker info`
und `kirocrew --version`.

`setup02_run.sh` startet den Container immer in Bash. `kirocrew` startet danach
manuell das Gateway mit `--approval yolo`; `kirocrew gateway` erzwingt denselben
Modus auch dann, wenn ein anderes `--approval` angegeben wurde. Der geprüfte
KiroCrew-Release 0.7.2 bietet für `kirocrew chat` keinen YOLO-Schalter; dieser
Befehl bleibt deshalb unverändert beim interaktiven Freigabeverhalten. Für
YOLO-Betrieb `kirocrew` oder `kirocrew gateway` verwenden.

```sh
./setup02_run.sh
# In der Bash des Containers: startet das Gateway mit YOLO.
kirocrew
```

Port 5476 ist standardmäßig auf `127.0.0.1` des Hosts veröffentlicht.
Der Container bleibt in Bash; Gateway startest du danach im Container wie oben.
Mit `--kirocrew-port` lässt sich der Host-Port ändern:

```sh
./setup02_run.sh --kirocrew-port 15476
# Im Container: kirocrew gateway --no-open --port 5476 --approval interactive
# Der Wrapper setzt die Approval-Option dennoch auf yolo.
```

Der Browser öffnet `http://localhost:15476/`. Das Gateway bindet im Container
an `0.0.0.0`, während das Host-Mapping nur `127.0.0.1` verwendet.
Das Startskript verwendet hierfür Docker-Bridge-Netzwerk. Für Anmeldeabläufe,
die ausdrücklich Host-`localhost` benötigen, gibt es `--host-network`.
In diesem Modus entfällt das Docker-Portmapping; `--kirocrew-port` ist damit
nicht kombinierbar. Das Skript setzt `KIROCREW_BIND=127.0.0.1`, sodass das
Gateway auf dem Host nur an dessen Loopback-Adresse auf Port 5476 lauscht.

Die Login-Konfiguration von kiro-cli bleibt auf dem Host unter
`~/.local/share/kiro-cli`. KiroCrew-Konfiguration, Sessions und Gedächtnis
liegen persistent unter `~/.kiro/crew-yolo`; `setup02_run.sh` bindet beide
Verzeichnisse ein. Der getrennte KiroCrew-Pfad ist erforderlich, damit der
Gateway-YOLO-Modus als expliziter, vom Standard isolierter Datenpfad erkannt
wird. AWS-SSO-Daten bleiben zusätzlich unter `~/.aws` erhalten.

Einmalig im laufenden Container anmelden:

```sh
kiro-cli login
```

Das Dashboard benötigt einen Token. Erzeuge im Container einen kurzlebigen
Link und öffne ihn zeitnah im Browser:

```sh
kirocrew token --ttl 2h
```

Für LAN-Zugriff ist eine passende Dashboard-Origin-Konfiguration erforderlich;
für entfernte Nutzung sollte ein TLS-Reverse-Proxy davorstehen. YOLO erlaubt
Tool-Aufrufe ohne Rückfrage. Die Agent-Ausführung kann dennoch fail-closed
bleiben, wenn die innere Sandbox nicht verfügbar ist. Das Containerstartskript
aktiviert weder `--privileged` noch unsandboxierte Ausführung. KiroCrew 0.7.2
verweigert Agent-Prozesse ohne Sandbox-Backend standardmäßig. Für die innere
Linux-Namespace-Sandbox kann ein KiroCrew-kompatibles Seccomp-Profil mit
`--kirocrew-sandbox-profile /pfad/kirocrew-seccomp.json` aktiviert werden;
das Startskript setzt dabei auch `apparmor=unconfined`. Das offizielle Profil
liegt in KiroCrews Repository unter `docker/seccomp/kirocrew-seccomp.json`.
Falls der Betreiber bewusst auf die innere Sandbox verzichtet, ist die
explizite KiroCrew-Konfigurationsoption
`agent.sandbox_allow_unsandboxed_exec=true` erforderlich. In diesem Fall sind
die eingehängten Host-Verzeichnisse für Agent-Prozesse zugänglich.
