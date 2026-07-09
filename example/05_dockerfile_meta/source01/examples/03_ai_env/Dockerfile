# =====================================================================
# Stage 1: Build Environment & Cache Dependency Compilation
# =====================================================================
FROM ubuntu:26.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy
# Grab the modern uv binary directly from Astral's official release container
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
# Install base toolsets required to fetch the CLI and compile Python extensions
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates build-essential python3-dev python3-venv python3-pip git \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
# 1. Install the programmatic Python SDK using uv
RUN --mount=type=cache,target=/root/.cache/uv uv venv .venv \
 && uv pip install --no-cache-dir google-antigravity azure-cognitiveservices-speech openai matplotlib numpy pandas scipy tqdm xarray loguru nbdev requests ruff scikit-learn seaborn
# 2. Safely download, decompress, and run the installation script
RUN curl -fsSL --compressed https://antigravity.google/cli/install.sh -o install.sh \
 && chmod +x install.sh \
 && ./install.sh
# 3. Download and install Codex from OpenAI's official installer
RUN curl -fsSL https://chatgpt.com/codex/install.sh -o codex-install.sh \
 && CODEX_INSTALL_DIR=/usr/local/bin CODEX_NON_INTERACTIVE=true sh codex-install.sh \
 && rm codex-install.sh
# 4. Download and install GitHub Copilot CLI from the official installer
RUN curl -fsSL https://gh.io/copilot-install -o copilot-install.sh \
 && PREFIX=/usr/local VERSION=latest bash copilot-install.sh \
 && rm copilot-install.sh
# 5. Install kiro-cli from the upstream Git repository using uv
RUN uv tool install kiro-cli --from git+https://github.com/avelops/kiro-cli.git
# =====================================================================
# Stage 2: Insulated Runtime Runner
# =====================================================================
FROM ubuntu:26.04 AS runner
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /workspace
# Copy the modern uv binary directly from Astral's official release container
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
# Install the essential tool belt for agents
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates git jq less file findutils tree man-db procps psmisc iproute2 iputils-ping dnsutils ripgrep fd-find yq lsof strace moreutils tmux shellcheck fzf bat git-lfs openssh-client dos2unix parallel unzip zip xz-utils rsync build-essential gcc sbcl rlwrap emacs-nox python3-full \
 && rm -rf /var/lib/apt/lists/*
# Install rustup and stable Rust toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable \
 && chmod -R a+w /root/.rustup
ENV PATH=/root/.cargo/bin:$PATH
# Copy the isolated Python environment
COPY --from=builder /workspace/.venv /workspace/.venv
ENV PATH=/workspace/.venv/bin:$PATH
# Copy the actual agy CLI tool from the builder's local path to system binaries
COPY --from=builder /root/.local/bin/agy /usr/local/bin/agy
# Add the Antigravity clean environment tweaks and dangerous CLI alias to .bashrc
RUN echo 'if [[ -n "$ANTIGRAVITY_AGENT" ]]; then export TERM=dumb; export DEBIAN_FRONTEND=noninteractive; unalias -a; export PS1="\$ "; fi' >> /root/.bashrc \
 && echo "alias agy='agy --dangerously-skip-permissions'" >> /root/.bashrc
# Copy other AI CLI tools from the builder stage
COPY --from=builder /usr/local/bin/codex /usr/local/bin/codex
COPY --from=builder /usr/local/bin/copilot /usr/local/bin/copilot
COPY --from=builder /root/.local/bin/kiro-cli /usr/local/bin/kiro-cli
# Ensure executable permissions for copied CLI tools
RUN chmod +x /usr/local/bin/codex \
 && chmod +x /usr/local/bin/copilot \
 && chmod +x /usr/local/bin/kiro-cli
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
# Pre-install Emacs packages
RUN emacs --batch --eval "(require 'package)" --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\"))" --eval "(package-initialize)" --eval "(package-refresh-contents)" --eval "(dolist (pkg '(cmake-mode company gptel magit markdown-mode orderless paredit slime yaml-mode use-package)) (package-install pkg))"
# Copy the modified .emacs configuration from the build context if present
# Note: In real usage, ensure .emacs exists in the build context directory
COPY .emacs /root/.emacs
VOLUME ["/workspace/src", "/root/.config", "/root/.cache", "/root/.gemini", "/root/.cargo"]
# Default to launching a bash shell
CMD ["/bin/bash"]
