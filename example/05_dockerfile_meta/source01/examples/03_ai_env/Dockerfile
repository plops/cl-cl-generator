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
# Stage: Runner (final image)
# ====================================================================
FROM nvidia/cuda:13.3.1-cudnn-devel-ubuntu26.04 AS runner
ENV DEBIAN_FRONTEND=noninteractive
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
 && apt-get install -y --no-install-recommends python3-full
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends nodejs npm
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends gnupg
# Install Conan as an isolated CLI tool
RUN --mount=type=cache,target=/root/.cache/uv uv tool install conan
# Install rustup and stable Rust toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable \
 && chmod -R a+w /root/.rustup
ENV PATH=/root/.cargo/bin:$PATH
# Install additional Rust targets for cross-compilation
RUN rustup target add thumbv7em-none-eabihf && chmod -R a+w /root/.rustup
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
# Install the newest Codex release directly in the runner image
RUN --mount=type=cache,target=/root/.npm npm install -g @openai/codex@$(npm view @openai/codex version)
RUN mv /usr/local/bin/codex /usr/local/bin/codex.real
# Install a wrapper that bypasses approvals and sandboxing by default
COPY --chmod=755 <<'EOF' /usr/local/bin/codex
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/codex.real --dangerously-bypass-approvals-and-sandbox --no-daemon "$@"

EOF
# Copy GitHub Copilot CLI from the builder image
COPY --from=builder-copilot --link --chmod=755 /usr/local/bin/copilot /usr/local/bin/copilot.real
# Install a wrapper that allows all actions by default
COPY --chmod=755 <<'EOF' /usr/local/bin/copilot
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/copilot.real --allow-all "$@"

EOF
# Keep all Claude state (incl. .claude.json and .credentials.json) in one bind-mountable directory.
# IS_SANDBOX allows --dangerously-skip-permissions as root; the binary is image-managed, so no self-updates.
ENV CLAUDE_CONFIG_DIR=/root/.claude \
    IS_SANDBOX=1 \
    DISABLE_AUTOUPDATER=1
# Copy Claude Code from the builder image
COPY --from=builder-claude --link --chmod=755 /usr/local/bin/claude /usr/local/bin/claude.real
# Install a wrapper that skips permission prompts by default
COPY --chmod=755 <<'EOF' /usr/local/bin/claude
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/claude.real --dangerously-skip-permissions "$@"

EOF
# Copy Kiro CLI from the builder image
COPY --from=builder-kiro --link --chmod=755 /root/.local/bin/kiro-cli /usr/local/bin/kiro-cli.real
# Install a wrapper that skips confirmation for init
COPY --chmod=755 <<'EOF' /usr/local/bin/kiro-cli
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  init) exec /usr/local/bin/kiro-cli.real init --force "${@:2}" ;;
  *) exec /usr/local/bin/kiro-cli.real "$@" ;;
esac

EOF
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
# Install Meta Muse Code from the official installer
RUN curl -fsSL https://dev.meta.ai/install.sh | MUSE_INSTALL_DIR=/usr/local/bin bash \
 && command -v muse
RUN mv /usr/local/bin/muse /usr/local/bin/muse.real
# Install a wrapper that runs Muse in YOLO mode by default
COPY --chmod=755 <<'EOF' /usr/local/bin/muse
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/muse.real --yolo "$@"

EOF
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
# Smoke test Docker CLI and Buildx by checking their client versions
RUN <<'EOF'
set -eu
docker --version > /tmp/docker-version.txt
grep -Eq 'Docker version [0-9]+\.[0-9]+' /tmp/docker-version.txt
docker buildx version > /tmp/docker-buildx-version.txt
grep -Eq 'github\.com/docker/buildx v[0-9]+\.[0-9]+' /tmp/docker-buildx-version.txt

EOF
# Smoke test Conan by checking the CLI version
RUN <<'EOF'
set -eu
conan --version

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
# Smoke test Rust cross targets by compiling a no_std library for each target
RUN <<'EOF'
set -eu
tmpdir="$(mktemp -d /tmp/ai-env-rust-target.XXXXXX)"
printf '#![no_std]\npub fn inc(x: u32) -> u32 { x + 1 }\n' > "$tmpdir/lib.rs"
for target in thumbv7em-none-eabihf; do
  rustc --edition 2021 --crate-type=lib --target "$target" -O "$tmpdir/lib.rs" -o "$tmpdir/lib-$target.rlib"
done
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
# Default to launching a bash shell
CMD ["/bin/bash"]
