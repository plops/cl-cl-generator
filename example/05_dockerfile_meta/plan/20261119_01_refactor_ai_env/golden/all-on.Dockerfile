# ====================================================================
# Stage: Python Dependencies (runs in parallel with other builders)
# ====================================================================
FROM nvidia/cuda:13.3.1-cudnn-devel-ubuntu26.04 AS builder-python
ENV DEBIAN_FRONTEND=noninteractive
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy
# Grab the modern uv binary directly from Astral's official release container
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
# Install base toolsets required to compile Python extensions
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends python3-pip python3-venv python3-dev build-essential ca-certificates
WORKDIR /workspace
# Install the programmatic Python SDK using uv
RUN --mount=type=cache,target=/root/.cache/uv uv venv .venv \
 && uv pip install numpy pandas loguru requests ruff polars pyarrow
# ====================================================================
# Stage: Antigravity CLI Download
# ====================================================================
FROM ubuntu:26.04 AS builder-agy
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl
WORKDIR /workspace
# Download, decompress, and run the Antigravity installation script
RUN curl -fsSL --compressed https://antigravity.google/cli/install.sh -o install.sh \
 && chmod +x install.sh \
 && ./install.sh
# ====================================================================
# Stage: GitHub Copilot CLI Download
# ====================================================================
FROM ubuntu:26.04 AS builder-copilot
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl
WORKDIR /workspace
# Download and install GitHub Copilot CLI from the official installer
RUN curl -fsSL https://gh.io/copilot-install -o copilot-install.sh \
 && PREFIX=/usr/local VERSION=latest bash copilot-install.sh \
 && rm copilot-install.sh
# ====================================================================
# Stage: Claude Code CLI Download
# ====================================================================
FROM ubuntu:26.04 AS builder-claude
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl
WORKDIR /workspace
# Install Claude Code with Anthropic's native installer and resolve the launcher symlink to a standalone binary
RUN curl -fsSL https://claude.ai/install.sh -o claude-install.sh \
 && bash claude-install.sh \
 && cp -L /root/.local/bin/claude /usr/local/bin/claude \
 && /usr/local/bin/claude --version \
 && rm claude-install.sh
# ====================================================================
# Stage: Kiro CLI Download
# ====================================================================
FROM ubuntu:26.04 AS builder-kiro
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip
WORKDIR /workspace
# Install kiro-cli from Amazon using the official zip package
RUN curl -fsSL https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip -o /tmp/kirocli.zip \
 && unzip -q /tmp/kirocli.zip -d /tmp/kirocli-extracted \
 && chmod +x /tmp/kirocli-extracted/kirocli/install.sh \
 && KIRO_CLI_SKIP_SETUP=1 /tmp/kirocli-extracted/kirocli/install.sh \
 && rm -rf /tmp/kirocli.zip /tmp/kirocli-extracted
# ====================================================================
# Stage: KiroCrew signed wheel installation
# ====================================================================
FROM ubuntu:26.04 AS builder-kirocrew
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl openssl python3-full
# Use KiroCrew's official signed-channel installer; it verifies the release manifest and wheel checksum
RUN curl -fsSL https://download.crew.kiro.dev/cli.sh -o /tmp/kirocrew-install.sh \
 && KIROCREW_HOME=/root/.kiro/crew-yolo KIROCREW_VENV=/opt/kirocrew-venv KIROCREW_PYTHON_DIR=/opt/kirocrew-python sh /tmp/kirocrew-install.sh --managed-python --version 0.7.2 \
 && ln -s /root/.local/bin/kirocrew /usr/local/bin/kirocrew \
 && rm -f /tmp/kirocrew-install.sh
# ====================================================================
# Stage: TeamCity CLI Download
# ====================================================================
FROM ubuntu:26.04 AS builder-teamcity
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl
WORKDIR /workspace
# Install TeamCity CLI from the official JetBrains installer
RUN curl -fsSL https://jb.gg/tc/install -o /tmp/teamcity-install.sh \
 && bash /tmp/teamcity-install.sh \
 && rm -f /tmp/teamcity-install.sh \
 && command -v teamcity >/dev/null
# =====================================================================
# Stage 2: Insulated Runtime Runner
# =====================================================================
FROM nvidia/cuda:13.3.1-cudnn-devel-ubuntu26.04 AS runner
ENV DEBIAN_FRONTEND=noninteractive
ENV KIROCREW_BIND=0.0.0.0 \
    KIROCREW_HOME=/root/.kiro/crew-yolo \
    KIROCREW_KIRO_BIN=/usr/local/bin/kiro-cli.real
# Configure NVIDIA Container Toolkit runtime and CUDA development paths
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    CUDA_HOME=/usr/local/cuda \
    CUDA_PATH=/usr/local/cuda \
    CUDACXX=/usr/local/cuda/bin/nvcc \
    PATH=/usr/local/cuda/bin:$PATH \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
WORKDIR /workspace
RUN chmod 755 /root
# Copy the signed KiroCrew installation and its managed Python 3.12 runtime
COPY --from=builder-kirocrew --link /opt/kirocrew-venv /opt/kirocrew-venv
COPY --from=builder-kirocrew --link /opt/kirocrew-venv-current /opt/kirocrew-venv-current
COPY --from=builder-kirocrew --link /opt/kirocrew-python /opt/kirocrew-python
COPY --from=builder-kirocrew --link --chmod=755 /root/.local/bin/kirocrew /usr/local/bin/kirocrew
RUN mv /usr/local/bin/kirocrew /usr/local/bin/kirocrew.real
COPY <<'EOF' /usr/local/bin/kirocrew
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  "")
    exec /usr/local/bin/kirocrew.real gateway --approval yolo --no-open
    ;;
  gateway)
    shift
    gateway_args=()
    while (($#)); do
      case "$1" in
        --approval) shift; (($#)) && shift ;;
        --approval=*) shift ;;
        *) gateway_args+=("$1"); shift ;;
      esac
    done
    exec /usr/local/bin/kirocrew.real gateway --approval yolo "${gateway_args[@]}"
    ;;
  *)
    exec /usr/local/bin/kirocrew.real "$@"
    ;;
esac

EOF
RUN chmod +x /usr/local/bin/kirocrew
# Copy the modern uv binary directly from Astral's official release container
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV UV_TOOL_BIN_DIR=/usr/local/bin
# Install the essential tool belt for agents
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates jq clang-format clang-tidy ninja-build cmake build-essential pkg-config gdb less file findutils tree man-db procps psmisc iproute2 iputils-ping ripgrep fd-find yq picocom git usbutils sudo libusb-1.0-0-dev moreutils tmux fzf git-lfs openssh-client parallel unzip zip xz-utils
# Install component dependencies in separate layers for caching
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends build-essential gcc
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends sbcl rlwrap
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends emacs-nox
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends python3-full
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends nodejs npm
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends gnupg
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends lsb-release
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends fonts-liberation libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 libcairo2 libcups2t64 libdbus-1-3 libdrm2 libexpat1 libfontconfig1 libgbm1 libglib2.0-0t64 libnspr4 libnss3 libpango-1.0-0 libudev1 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2
# Install Habit Hooks with all optional integrations
RUN --mount=type=cache,target=/root/.cache/uv uv tool install 'habit-hooks[all]'
# Install Deptry as an isolated CLI tool
RUN --mount=type=cache,target=/root/.cache/uv uv tool install deptry
# Install Conan as an isolated CLI tool
RUN --mount=type=cache,target=/root/.cache/uv uv tool install conan
# Install JSCPD globally so it is available in every mounted project
RUN --mount=type=cache,target=/root/.npm npm install -g jscpd
# Install Archify for Codex and provision Chrome for visual checks
ARG ARCHIFY_CHROME_BUILD=stable
RUN --mount=type=cache,target=/root/.npm npx -y skills add tt-a1i/archify --skill archify --agent codex --global --copy --yes \
 && npx -y @puppeteer/browsers install "chrome@${ARCHIFY_CHROME_BUILD}" --path /opt/archify-browser \
 && chrome_path="$(find /opt/archify-browser -type f -path '*/chrome-linux*/chrome' -perm -111 -print -quit)" \
 && test -n "$chrome_path" \
 && ln -s "$chrome_path" /usr/local/bin/archify-chrome
ENV ARCHIFY_CHROME=/usr/local/bin/archify-chrome \
    ARCHIFY_CHROME_NO_SANDBOX=1
# Install rustup and stable Rust toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable \
 && chmod -R a+w /root/.rustup
ENV PATH=/root/.cargo/bin:$PATH
# Install difftastic syntax-aware diff tool
RUN --mount=type=cache,target=/root/.cargo/registry --mount=type=cache,target=/root/.cargo/git cargo install difftastic \
 && ln -sf /root/.cargo/bin/difft /usr/local/bin/difft
# Configure Git to use difftastic as default diff tool
RUN git config --global diff.external difft
# Install probe-rs
RUN curl --proto '=https' --tlsv1.2 -LsSf https://github.com/probe-rs/probe-rs/releases/latest/download/probe-rs-tools-installer.sh | sh \
 && chmod -R a+w /root/.cargo/bin/probe-rs
# Copy the isolated Python environment
COPY --from=builder-python --link /workspace/.venv /workspace/.venv
ENV PATH=/workspace/.venv/bin:$PATH
# Copy the actual agy CLI tool from the builder's local path to system binaries
COPY --from=builder-agy --link --chmod=755 /root/.local/bin/agy /usr/local/bin/agy
# Rename the original binary and install a wrapper that skips permissions by default
RUN mv /usr/local/bin/agy /usr/local/bin/agy.real
COPY <<'EOF' /usr/local/bin/agy
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/agy.real --dangerously-skip-permissions "$@"

EOF
RUN chmod +x /usr/local/bin/agy
# Add the Antigravity clean environment tweaks to .bashrc
RUN echo 'if [[ -n "$ANTIGRAVITY_AGENT" ]]; then export TERM=dumb; export DEBIAN_FRONTEND=noninteractive; unalias -a; export PS1="\$ "; fi' >> /root/.bashrc \
 && echo "alias agy='agy --dangerously-skip-permissions'" >> /root/.bashrc
# Install or copy other AI CLI tools
# Install the newest Codex release directly in the runner image
RUN --mount=type=cache,target=/root/.npm npm install -g @openai/codex@$(npm view @openai/codex version)
# Rename the original binary and install a wrapper that bypasses approvals and sandboxing by default
RUN mv /usr/local/bin/codex /usr/local/bin/codex.real
COPY <<'EOF' /usr/local/bin/codex
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/codex.real --dangerously-bypass-approvals-and-sandbox --no-daemon "$@"

EOF
RUN chmod +x /usr/local/bin/codex
COPY --from=builder-copilot --link --chmod=755 /usr/local/bin/copilot /usr/local/bin/copilot
# Rename the original binary and install a wrapper that allows all actions by default
RUN mv /usr/local/bin/copilot /usr/local/bin/copilot.real
COPY <<'EOF' /usr/local/bin/copilot
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/copilot.real --allow-all "$@"

EOF
RUN chmod +x /usr/local/bin/copilot
COPY --from=builder-claude --link --chmod=755 /usr/local/bin/claude /usr/local/bin/claude.real
# Keep all Claude state (incl. .claude.json and .credentials.json) in one bind-mountable directory.
# IS_SANDBOX allows --dangerously-skip-permissions as root; the binary is image-managed, so no self-updates.
ENV CLAUDE_CONFIG_DIR=/root/.claude \
    IS_SANDBOX=1 \
    DISABLE_AUTOUPDATER=1
# Install a wrapper that skips permission prompts by default
COPY <<'EOF' /usr/local/bin/claude
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/claude.real --dangerously-skip-permissions "$@"

EOF
RUN chmod +x /usr/local/bin/claude
COPY --from=builder-kiro --link --chmod=755 /root/.local/bin/kiro-cli /usr/local/bin/kiro-cli
# Rename the original binary and install a wrapper that skips confirmation for init
RUN mv /usr/local/bin/kiro-cli /usr/local/bin/kiro-cli.real
COPY <<'EOF' /usr/local/bin/kiro-cli
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  init) exec /usr/local/bin/kiro-cli.real init --force "${@:2}" ;;
  *) exec /usr/local/bin/kiro-cli.real "$@" ;;
esac

EOF
RUN chmod +x /usr/local/bin/kiro-cli
# Copy TeamCity CLI from the builder image
COPY --from=builder-teamcity --link --chmod=755 /usr/local/bin/teamcity /usr/local/bin/teamcity
# Install Azure CLI from Microsoft's official apt repository
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
 && chmod go+r /etc/apt/keyrings/microsoft.gpg \
 && arch="$(dpkg --print-architecture)" \
 && suite="$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-$VERSION_CODENAME}")" \
 && repo_suite="$suite" \
 && if ! curl -fsI "https://packages.microsoft.com/repos/azure-cli/dists/${repo_suite}/Release" >/dev/null; then repo_suite="noble"; fi \
 && printf '%s\n' 'Types: deb' 'URIs: https://packages.microsoft.com/repos/azure-cli/' "Suites: ${repo_suite}" 'Components: main' "Architectures: ${arch}" 'Signed-By: /etc/apt/keyrings/microsoft.gpg' > /etc/apt/sources.list.d/azure-cli.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends azure-cli
# Install Docker CLI for an optionally mounted host Docker socket
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && chmod a+r /etc/apt/keyrings/docker.gpg \
 && suite="$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-$VERSION_CODENAME}")" \
 && printf '%s\n' 'Types: deb' 'URIs: https://download.docker.com/linux/ubuntu' "Suites: ${suite}" 'Components: stable' 'Signed-By: /etc/apt/keyrings/docker.gpg' > /etc/apt/sources.list.d/docker.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin
# Install the Arm GNU bare-metal toolchain used by fountain firmware
RUN curl -fL https://gitlab.arm.com/api/v4/projects/tooling%2Fgnu-toolchains-for-arm/packages/generic/gnu-toolchain/15.3.rel2/arm-gnu-toolchain-15.3.rel2-x86_64-arm-none-eabi.tar.xz -o /tmp/arm-none-eabi.tar.xz \
 && tar -xJf /tmp/arm-none-eabi.tar.xz -C /opt \
 && rm /tmp/arm-none-eabi.tar.xz
ENV PATH=/opt/arm-gnu-toolchain-15.3.rel2-x86_64-arm-none-eabi/bin:$PATH
# Install SEGGER J-Link tools (the download accepts SEGGER's license terms)
RUN curl -fL --data 'accept_license_agreement=accepted&non_eu_market=true' https://www.segger.com/downloads/jlink/JLink_Linux_V992_x86_64.tgz -o /tmp/jlink.tgz \
 && tar -xzf /tmp/jlink.tgz -C /opt \
 && rm /tmp/jlink.tgz
ENV PATH=/opt/JLink_Linux_V992_x86_64:$PATH
# Download and install Quicklisp
RUN curl -O https://beta.quicklisp.org/quicklisp.lisp \
 && sbcl --non-interactive --load quicklisp.lisp --eval "(quicklisp-quickstart:install)" \
 && rm quicklisp.lisp
# Configure Quicklisp in .sbclrc
COPY <<'EOF' /root/.sbclrc
#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

EOF
# Pre-create local-projects symlinks (which resolve dynamically when /workspace/src is mounted)
RUN mkdir -p /root/quicklisp/local-projects \
 && ln -s /workspace/src/cl-py-generator /root/quicklisp/local-projects/cl-py-generator \
 && ln -s /workspace/src/cl-cpp-generator2 /root/quicklisp/local-projects/cl-cpp-generator2 \
 && ln -s /workspace/src/cl-rust-generator /root/quicklisp/local-projects/cl-rust-generator
# Pre-fetch and cache Quicklisp systems and common dependencies
RUN sbcl --non-interactive --load /root/quicklisp/setup.lisp --eval '(ql:quickload "quicklisp-slime-helper")' --eval '(ql:quickload "alexandria")' --eval '(ql:quickload "jonathan")' --eval '(ql:quickload "external-program")' --eval '(ql:quickload "cl-ppcre")'
# Install Grok Build from the official x.ai installer
RUN curl -fsSL https://x.ai/cli/install.sh -o grok-install.sh \
 && bash grok-install.sh \
 && rm grok-install.sh
# Move the installed Grok binaries out of ~/.grok so they survive optional auth volume mounts
RUN cp /root/.grok/bin/grok /usr/local/bin/grok.real
RUN cp /root/.grok/bin/agent /usr/local/bin/agent.real
COPY <<'EOF' /usr/local/bin/grok
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/grok.real --always-approve "$@"

EOF
COPY <<'EOF' /usr/local/bin/agent
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/agent.real "$@"

EOF
RUN chmod +x /usr/local/bin/grok /usr/local/bin/grok.real /usr/local/bin/agent /usr/local/bin/agent.real
# Install Meta Muse Code from the official installer
RUN curl -fsSL https://dev.meta.ai/install.sh | MUSE_INSTALL_DIR=/usr/local/bin bash \
 && command -v muse
RUN cp /usr/local/bin/muse /usr/local/bin/muse.real
COPY <<'EOF' /usr/local/bin/muse
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/muse.real --yolo "$@"

EOF
RUN chmod +x /usr/local/bin/muse /usr/local/bin/muse.real
# Install Devin CLI from the official installer
RUN curl -fsSL https://cli.devin.ai/install.sh | XDG_DATA_HOME=/usr/local/share bash || true # tries to run `devin setup` which fails
RUN mv /usr/local/share/devin/cli/_versions/current/bin/devin /usr/local/bin/devin.real
COPY <<'EOF' /usr/local/bin/devin
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/devin.real --permission-mode bypass "$@"

EOF
RUN chmod +x /usr/local/bin/devin /usr/local/bin/devin.real
# Pre-install Emacs packages
RUN emacs --batch --eval "(require 'package)" --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\"))" --eval "(package-initialize)" --eval "(package-refresh-contents)" --eval "(setq custom-file null-device)" --eval "(dolist (pkg '(compat cmake-mode company gptel magit markdown-mode orderless paredit slime yaml-mode use-package)) (setq package-selected-packages nil) (package-install pkg))"
# Recompile installed Emacs packages with their dependencies available
RUN emacs --batch --eval "(require 'package)" --eval "(package-initialize)" --eval "(byte-recompile-directory package-user-dir 0 t)"
# Copy the modified .emacs configuration from the build context if present
# Note: In real usage, ensure .emacs exists in the build context directory
COPY --link .emacs /root/.emacs
# Smoke test Meta Muse Code by checking the CLI version
RUN <<'EOF'
set -eu
muse --version > /tmp/muse-version.txt
grep -Eq '[0-9]+\.[0-9]+\.[0-9]+' /tmp/muse-version.txt

EOF
# Smoke test Claude Code by checking the CLI version through its wrapper
RUN <<'EOF'
set -eu
claude --version > /tmp/claude-version.txt
grep -Eq '[0-9]+\.[0-9]+\.[0-9]+' /tmp/claude-version.txt

EOF
# Smoke test Kiro CLI and its ACP command
RUN <<'EOF'
set -eu
kiro-cli --help > /tmp/kiro-cli-help.txt
grep -qi 'kiro' /tmp/kiro-cli-help.txt
kiro-cli acp --help > /tmp/kiro-cli-acp-help.txt
grep -qi 'acp' /tmp/kiro-cli-acp-help.txt

EOF
# Smoke test GitHub Copilot CLI by checking the CLI version through its wrapper
RUN <<'EOF'
set -eu
copilot --version > /tmp/copilot-version.txt
grep -Eq '[0-9]+\.[0-9]+' /tmp/copilot-version.txt

EOF
# Smoke test Codex by checking the CLI version
RUN <<'EOF'
set -eu
codex --version > /tmp/codex-version.txt
grep -Eq '[0-9]+\.[0-9]+\.[0-9]+' /tmp/codex-version.txt

EOF
# Smoke test Grok Build by checking the CLI version
RUN <<'EOF'
set -eu
grok --version
agent --version

EOF
# Smoke test Devin CLI by checking the CLI version
RUN <<'EOF'
set -eu
devin --version > /tmp/devin-version.txt
[ -s /tmp/devin-version.txt ]

EOF
# Smoke test KiroCrew CLI and its chat/gateway commands
RUN <<'EOF'
set -eu
kirocrew --help > /tmp/kirocrew-help.txt
grep -q 'chat' /tmp/kirocrew-help.txt
grep -q 'gateway' /tmp/kirocrew-help.txt
kirocrew chat --help > /tmp/kirocrew-chat-help.txt
grep -q 'Interactive mode' /tmp/kirocrew-chat-help.txt
kirocrew gateway --help > /tmp/kirocrew-gateway-help.txt
grep -q -- '--port' /tmp/kirocrew-gateway-help.txt

EOF
# Smoke test Azure CLI by checking the installed version
RUN <<'EOF'
set -eu
az version > /tmp/az-version.json
grep -q '"azure-cli"' /tmp/az-version.json

EOF
# Smoke test Docker CLI and Buildx by checking their client versions
RUN <<'EOF'
set -eu
docker --version > /tmp/docker-version.txt
grep -Eq 'Docker version [0-9]+\.[0-9]+' /tmp/docker-version.txt
docker buildx version > /tmp/docker-buildx-version.txt
grep -Eq 'github\.com/docker/buildx v[0-9]+\.[0-9]+' /tmp/docker-buildx-version.txt

EOF
# Smoke test TeamCity CLI by checking the installed version
RUN <<'EOF'
set -eu
teamcity --version > /tmp/teamcity-version.txt
grep -Eq '[0-9]+\.[0-9]+' /tmp/teamcity-version.txt

EOF
# Smoke test Conan by checking the CLI version
RUN <<'EOF'
set -eu
conan --version

EOF
# Smoke test Habit Hooks by checking the CLI help
RUN <<'EOF'
set -eu
habit-hooks --help > /tmp/habit-hooks-help.txt
[ -s /tmp/habit-hooks-help.txt ]

EOF
# Smoke test Deptry by checking the CLI version
RUN <<'EOF'
set -eu
deptry --version

EOF
# Smoke test JSCPD by checking the CLI version
RUN <<'EOF'
set -eu
jscpd --version

EOF
# Smoke test Archify and its headless Chrome runtime
RUN <<'EOF'
set -eu
archify_dir=/root/.agents/skills/archify
test -f "$archify_dir/SKILL.md"
test -f "$archify_dir/bin/archify.mjs"
node "$archify_dir/bin/archify.mjs" doctor
test -x "$ARCHIFY_CHROME"
"$ARCHIFY_CHROME" --headless --no-sandbox --disable-gpu --dump-dom about:blank > /tmp/archify-chrome.html
grep -qi '<html' /tmp/archify-chrome.html
tmpdir="$(mktemp -d /tmp/ai-env-archify.XXXXXX)"
node "$archify_dir/bin/archify.mjs" demo "$tmpdir"
test -s "$tmpdir/archify-demo.html"
rm -rf "$tmpdir"

EOF
# Smoke test Arm GNU bare-metal toolchain by compiling a Cortex-M7 object
RUN <<'EOF'
set -eu
tmpdir="$(mktemp -d /tmp/ai-env-arm-none-eabi.XXXXXX)"
cat > "$tmpdir/test.c" <<'C_EOF'
void Reset_Handler(void) {}
C_EOF
arm-none-eabi-gcc -mcpu=cortex-m7 -mthumb -ffreestanding -c "$tmpdir/test.c" -o "$tmpdir/test.o"
arm-none-eabi-readelf -h "$tmpdir/test.o" > "$tmpdir/readelf.txt"
grep -Eq 'Machine.+ARM' "$tmpdir/readelf.txt"
rm -rf "$tmpdir"

EOF
# Smoke test SEGGER J-Link command-line tools by checking their pinned version
RUN <<'EOF'
set -eu
JLinkGDBServerCLExe -version > /tmp/jlink-version.txt || true
grep -F 'V9.92 ' /tmp/jlink-version.txt
command -v JLinkExe >/dev/null

EOF
# Smoke test CUDA nvcc compiler by compiling a test CUDA kernel
RUN <<'EOF'
set -eu
nvcc --version
tmpdir="$(mktemp -d /tmp/ai-env-cuda.XXXXXX)"
cat > "$tmpdir/test.cu" <<'CU_EOF'
#include <stdio.h>
__global__ void test_kernel(void) {}
int main(void) {
  test_kernel<<<1, 1>>>();
  puts("cuda-build-ok");
  return 0;
}
CU_EOF
nvcc "$tmpdir/test.cu" -o "$tmpdir/test"
rm -rf "$tmpdir"

EOF
# Smoke test GCC by compiling and running a tiny C program
RUN <<'EOF'
set -eu
tmpdir="$(mktemp -d /tmp/ai-env-gcc.XXXXXX)"
cat > "$tmpdir/test.c" <<'C_EOF'
#include <stdio.h>
int main(void) {
  puts("gcc-ok");
  return 0;
}
C_EOF
gcc "$tmpdir/test.c" -o "$tmpdir/test"
"$tmpdir/test" | grep -qx 'gcc-ok'
rm -rf "$tmpdir"

EOF
# Smoke test Rust by compiling and running a tiny program
RUN <<'EOF'
set -eu
tmpdir="$(mktemp -d /tmp/ai-env-rust.XXXXXX)"
cat > "$tmpdir/test.rs" <<'R_EOF'
fn main() {
    println!("rust-ok");
}
R_EOF
rustc "$tmpdir/test.rs" -o "$tmpdir/test"
"$tmpdir/test" | grep -qx 'rust-ok'
rm -rf "$tmpdir"

EOF
# Smoke test Python by running a tiny script
RUN <<'EOF'
set -eu
python3 -c 'print("python-ok")' | grep -qx 'python-ok'

EOF
# Smoke test the Python virtual environment by importing its packages
RUN <<'EOF'
set -eu
python3 -c 'import numpy, pandas, loguru, requests, ruff, polars, pyarrow'

EOF
# Smoke test SBCL by evaluating a simple expression
RUN <<'EOF'
set -eu
sbcl --non-interactive --eval '(princ (+ 1 2))' --eval '(quit)' | grep -q 3

EOF
# Smoke test Emacs by opening a file with the configured init
RUN <<'EOF'
set -eu
tmpdir="$(mktemp -d /tmp/ai-env-emacs-open.XXXXXX)"
echo hello > "$tmpdir/open-me"
emacs --batch -l /root/.emacs --eval "(progn (find-file \"$tmpdir/open-me\") (unless (and buffer-file-name (eq major-mode 'fundamental-mode)) (error \"Emacs failed to open a plain file\")))"
rm -rf "$tmpdir"

EOF
# Smoke test Emacs + SLIME by opening and loading a Lisp file
RUN <<'EOF'
set -eu
tmpdir="$(mktemp -d /tmp/ai-env-slime.XXXXXX)"
cat > "$tmpdir/example.lisp" <<'LISP_EOF'
(+ 1 2)
LISP_EOF
cat > "$tmpdir/slime-check.el" <<'SLIME_EOF'
(require 'slime)
(setq inferior-lisp-program "sbcl")
(slime-setup '(slime-repl))
(slime)
(let ((deadline (+ (float-time) 120)))
  (while (and (not (slime-connected-p)) (< (float-time) deadline))
    (sleep-for 0.2))
  (unless (slime-connected-p)
    (error "SLIME connection timed out")))
(find-file "/tmp/ai-env-slime.XXXXXX/example.lisp")
(slime-load-file "/tmp/ai-env-slime.XXXXXX/example.lisp")
(unless (= 3 (slime-eval '(cl:+ 1 2)))
  (error "SLIME evaluation returned the wrong value"))
SLIME_EOF
sed -i "s#/tmp/ai-env-slime.XXXXXX#$tmpdir#g" "$tmpdir/slime-check.el"
emacs --batch -l /root/.emacs -l "$tmpdir/slime-check.el"
rm -rf "$tmpdir"

EOF
# Default to launching a bash shell
CMD ["/bin/bash"]
