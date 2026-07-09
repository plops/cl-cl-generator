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
 && apt-get install -y --no-install-recommends curl ca-certificates build-essential python3-dev python3-venv python3-pip nodejs npm git \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
# 1. Install the programmatic Python SDK using uv
RUN --mount=type=cache,target=/root/.cache/uv uv venv .venv \
 && uv pip install --no-cache-dir google-antigravity azure-cognitiveservices-speech openai matplotlib numpy pandas scipy tqdm xarray loguru nbdev requests ruff scikit-learn seaborn
# 2. Safely download, decompress, and run the installation script
RUN curl -fsSL --compressed https://antigravity.google/cli/install.sh -o install.sh \
 && chmod +x install.sh \
 && ./install.sh
# 3. Install Codex from the official npm package
RUN npm install -g @openai/codex
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
# Rename the original binary and install a wrapper that skips permissions by default
RUN mv /usr/local/bin/agy /usr/local/bin/agy.real
COPY <<'EOF' /usr/local/bin/agy
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" --dangerously-skip-permissions "*) exec /usr/local/bin/agy.real "$@" ;;
  *) exec /usr/local/bin/agy.real --dangerously-skip-permissions "$@" ;;
esac

EOF
RUN chmod +x /usr/local/bin/agy
# Add the Antigravity clean environment tweaks to .bashrc
RUN echo 'if [[ -n "$ANTIGRAVITY_AGENT" ]]; then export TERM=dumb; export DEBIAN_FRONTEND=noninteractive; unalias -a; export PS1="\$ "; fi' >> /root/.bashrc \
 && echo "alias agy='agy --dangerously-skip-permissions'" >> /root/.bashrc
# Copy other AI CLI tools from the builder stage
COPY --from=builder /usr/local/bin/codex /usr/local/bin/codex
# Rename the original binary and install a wrapper that bypasses approvals and sandboxing by default
RUN mv /usr/local/bin/codex /usr/local/bin/codex.real
COPY <<'EOF' /usr/local/bin/codex
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" --dangerously-bypass-approvals-and-sandbox "*) exec /usr/local/bin/codex.real "$@" ;;
  *) exec /usr/local/bin/codex.real --dangerously-bypass-approvals-and-sandbox "$@" ;;
esac

EOF
RUN chmod +x /usr/local/bin/codex
COPY --from=builder /usr/local/bin/copilot /usr/local/bin/copilot
# Rename the original binary and install a wrapper that allows all actions by default
RUN mv /usr/local/bin/copilot /usr/local/bin/copilot.real
COPY <<'EOF' /usr/local/bin/copilot
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" --allow-all "*) exec /usr/local/bin/copilot.real "$@" ;;
  *) exec /usr/local/bin/copilot.real --allow-all "$@" ;;
esac

EOF
RUN chmod +x /usr/local/bin/copilot
COPY --from=builder /root/.local/bin/kiro-cli /usr/local/bin/kiro-cli
# Rename the original binary and install a wrapper that skips confirmation for init
RUN mv /usr/local/bin/kiro-cli /usr/local/bin/kiro-cli.real
COPY <<'EOF' /usr/local/bin/kiro-cli
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == init ]]; then
  for arg in "$@"; do
    if [[ $arg == --force ]]; then
      exec /usr/local/bin/kiro-cli.real "$@"
    fi
  done
  exec /usr/local/bin/kiro-cli.real init --force "${@:2}"
fi
exec /usr/local/bin/kiro-cli.real "$@"

EOF
RUN chmod +x /usr/local/bin/kiro-cli
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
RUN emacs --batch --eval "(require 'package)" --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\"))" --eval "(package-initialize)" --eval "(package-refresh-contents)" --eval "(dolist (pkg '(compat cmake-mode company gptel magit markdown-mode orderless paredit slime yaml-mode use-package)) (package-install pkg))"
# Recompile installed Emacs packages with their dependencies available
RUN emacs --batch --eval "(require 'package)" --eval "(package-initialize)" --eval "(byte-recompile-directory package-user-dir 0 t)"
# Copy the modified .emacs configuration from the build context if present
# Note: In real usage, ensure .emacs exists in the build context directory
COPY .emacs /root/.emacs
# 7. Smoke test the C toolchain
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
# Smoke test Python
# Smoke test Python by running a tiny script
RUN <<'EOF'
set -eu
python3 - <<'PY_EOF'
print("python-ok")
PY_EOF

EOF
# Smoke test SBCL
# Smoke test SBCL by evaluating a simple expression
RUN <<'EOF'
set -eu
sbcl --non-interactive --eval '(princ (+ 1 2))' --eval '(quit)'

EOF
# Smoke test Emacs
# Smoke test Emacs by opening a file with the configured init
RUN <<'EOF'
set -eu
tmpdir="$(mktemp -d /tmp/ai-env-emacs-open.XXXXXX)"
cat > "$tmpdir/open-me" <<'T_EOF'
hello
T_EOF
cat > "$tmpdir/check.el" <<'EMACS_EOF'
(find-file "/tmp/ai-env-emacs-open.XXXXXX/open-me")
(unless (and buffer-file-name (eq major-mode 'fundamental-mode))
  (error "Emacs failed to open a plain file"))
EMACS_EOF
sed -i "s#/tmp/ai-env-emacs-open.XXXXXX#$tmpdir#g" "$tmpdir/check.el"
emacs --batch -l /root/.emacs -l "$tmpdir/check.el"

EOF
# Smoke test Emacs + SLIME
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

EOF
VOLUME ["/workspace/src", "/root/.config", "/root/.cache", "/root/.gemini", "/root/.cargo"]
# Default to launching a bash shell
CMD ["/bin/bash"]
