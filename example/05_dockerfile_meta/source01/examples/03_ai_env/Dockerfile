# ====================================================================
# Stage: Python Dependencies (runs in parallel with other builders)
# ====================================================================
FROM ubuntu:26.04 AS builder-python
ENV DEBIAN_FRONTEND=noninteractive
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy
# Grab the modern uv binary directly from Astral's official release container
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
# Install base toolsets required to compile Python extensions
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get install -y --no-install-recommends python3-pip python3-venv python3-dev build-essential ca-certificates
WORKDIR /workspace
# Install the programmatic Python SDK using uv
RUN --mount=type=cache,target=/root/.cache/uv uv venv .venv \
 && uv pip install google-antigravity azure-cognitiveservices-speech huggingface_hub openai matplotlib numpy pandas scipy tqdm xarray loguru nbdev requests ruff scikit-learn seaborn
# =====================================================================
# Stage 2: Insulated Runtime Runner
# =====================================================================
FROM ubuntu:26.04 AS runner
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /workspace
RUN chmod 755 /root
# Copy the modern uv binary directly from Astral's official release container
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV UV_TOOL_BIN_DIR=/usr/local/bin
# Install the essential tool belt for agents
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get install -y --no-install-recommends curl ca-certificates git jq less file findutils tree man-db procps psmisc iproute2 iputils-ping dnsutils ripgrep fd-find yq picocom cmake build-essential git pkg-config usbutils libusb-1.0-0-dev lsof strace moreutils tmux shellcheck fzf cmake pkg-config clang-format clang-tidy clangd ninja-build bat git-lfs openssh-client dos2unix parallel unzip zip xz-utils rsync
# Install component dependencies in separate layers for caching
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get install -y --no-install-recommends build-essential gcc
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get install -y --no-install-recommends sbcl rlwrap
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get install -y --no-install-recommends python3-full
# Install rustup and stable Rust toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable \
 && chmod -R a+w /root/.rustup
ENV PATH=/root/.cargo/bin:$PATH
# Install difftastic syntax-aware diff tool
RUN --mount=type=cache,target=/root/.cargo/registry --mount=type=cache,target=/root/.cargo/git cargo install difftastic \
 && ln -sf /root/.cargo/bin/difft /usr/local/bin/difft
# Configure Git to use difftastic as default diff tool
RUN git config --global diff.external difft
# Copy the isolated Python environment
COPY --from=builder-python --link /workspace/.venv /workspace/.venv
ENV PATH=/workspace/.venv/bin:$PATH
# Install the Arm GNU bare-metal toolchain used by fountain firmware
RUN curl -fL https://gitlab.arm.com/api/v4/projects/tooling%2Fgnu-toolchains-for-arm/packages/generic/gnu-toolchain/15.3.rel1/arm-gnu-toolchain-15.3.rel1-x86_64-arm-none-eabi.tar.xz -o /tmp/arm-none-eabi.tar.xz \
 && tar -xJf /tmp/arm-none-eabi.tar.xz -C /opt \
 && rm /tmp/arm-none-eabi.tar.xz
ENV PATH=/opt/arm-gnu-toolchain-15.3.rel1-x86_64-arm-none-eabi/bin:$PATH
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
# Smoke test Meta Muse Code by checking the CLI version
RUN <<'EOF'
set -eu
muse --version > /tmp/muse-version.txt
[ -s /tmp/muse-version.txt ]
grep -Eq '[0-9]+\.[0-9]+\.[0-9]+-R[0-9]+' /tmp/muse-version.txt

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
grep -Eq 'Machine:[[:space:]]+ARM' "$tmpdir/readelf.txt"
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
"$tmpdir/test"

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
"$tmpdir/test"

EOF
# Smoke test Python by running a tiny script
RUN <<'EOF'
set -eu
python3 - <<'PY_EOF'
print("python-ok")
PY_EOF

EOF
# Smoke test SBCL by evaluating a simple expression
RUN <<'EOF'
set -eu
sbcl --non-interactive --eval '(princ (+ 1 2))' --eval '(quit)'

EOF
VOLUME ["/workspace/src", "/root/.config", "/root/.config/tc", "/root/.cache", "/root/.gemini", "/root/.grok", "/root/.codex", "/root/.azure", "/root/.cargo"]
# Default to launching a bash shell
CMD ["/bin/bash"]
