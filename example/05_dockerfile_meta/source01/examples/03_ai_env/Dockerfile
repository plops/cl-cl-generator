# ====================================================================
# Stage: Python Dependencies (runs in parallel with other builders)
# ====================================================================
FROM nvidia/cuda:13.4.1-cudnn-devel-ubuntu26.04 AS builder-python
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
# =====================================================================
# Stage 2: Insulated Runtime Runner
# =====================================================================
FROM nvidia/cuda:13.4.1-cudnn-devel-ubuntu26.04 AS runner
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
ENV KIROCREW_BIND=0.0.0.0
# Copy the modern uv binary directly from Astral's official release container
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV UV_TOOL_BIN_DIR=/usr/local/bin
# Install the essential tool belt for agents
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates jq ninja-build cmake build-essential pkg-config less file findutils tree man-db procps psmisc iproute2 ripgrep fd-find yq picocom git usbutils sudo libusb-1.0-0-dev moreutils tmux fzf git-lfs openssh-client parallel unzip zip xz-utils
# Install component dependencies in separate layers for caching
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends build-essential gcc
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends sbcl rlwrap
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends python3-full
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends nodejs npm
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends gnupg
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
# Install or copy other AI CLI tools
# Install the newest Codex release directly in the runner image
RUN --mount=type=cache,target=/root/.npm npm install -g @openai/codex@$(npm view @openai/codex version)
# Rename the original binary and install a wrapper that bypasses approvals and sandboxing by default
RUN mv /usr/local/bin/codex /usr/local/bin/codex.real
COPY <<'EOF' /usr/local/bin/codex
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/codex.real --dangerously-bypass-approvals-and-sandbox "$@"

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
COPY --from=builder-kiro --link --chmod=755 /root/.local/bin/kiro-cli /usr/local/bin/kiro-cli
COPY --from=builder-kiro --link --chmod=755 /root/.local/bin/kiro-cli-chat /usr/local/bin/kiro-cli-chat
COPY --from=builder-kiro --link --chmod=755 /root/.local/bin/kiro-cli-term /usr/local/bin/kiro-cli-term
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
# Install Docker CLI for an optionally mounted host Docker socket
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && chmod a+r /etc/apt/keyrings/docker.gpg \
 && suite="$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-$VERSION_CODENAME}")" \
 && printf '%s\n' 'Types: deb' 'URIs: https://download.docker.com/linux/ubuntu' "Suites: ${suite}" 'Components: stable' 'Signed-By: /etc/apt/keyrings/docker.gpg' > /etc/apt/sources.list.d/docker.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin
# Install the Arm GNU bare-metal toolchain used by fountain firmware
RUN curl -fL https://gitlab.arm.com/api/v4/projects/tooling%2Fgnu-toolchains-for-arm/packages/generic/gnu-toolchain/15.3.rel1/arm-gnu-toolchain-15.3.rel1-x86_64-arm-none-eabi.tar.xz -o /tmp/arm-none-eabi.tar.xz \
 && tar -xJf /tmp/arm-none-eabi.tar.xz -C /opt \
 && rm /tmp/arm-none-eabi.tar.xz
ENV PATH=/opt/arm-gnu-toolchain-15.3.rel1-x86_64-arm-none-eabi/bin:$PATH
# Install SEGGER J-Link tools (the download accepts SEGGER's license terms)
RUN curl -fL --data 'accept_license_agreement=accepted&non_eu_market=true' https://www.segger.com/downloads/jlink/JLink_Linux_V930_x86_64.tgz -o /tmp/jlink.tgz \
 && tar -xzf /tmp/jlink.tgz -C /opt \
 && rm /tmp/jlink.tgz
ENV PATH=/opt/JLink_Linux_V930_x86_64:$PATH
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
# Smoke test Kiro CLI ACP command
RUN <<'EOF'
set -eu
kiro-cli acp --help > /tmp/kiro-cli-acp-help.txt
grep -qi 'acp' /tmp/kiro-cli-acp-help.txt

EOF
# Default to launching a bash shell
CMD ["/bin/bash"]
