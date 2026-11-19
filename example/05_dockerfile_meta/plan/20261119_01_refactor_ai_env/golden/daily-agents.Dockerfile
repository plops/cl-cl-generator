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
FROM ubuntu:26.04 AS runner
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /workspace
RUN chmod 755 /root
# Copy the modern uv binary directly from Astral's official release container
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
ENV UV_TOOL_BIN_DIR=/usr/local/bin
# Install the essential tool belt for agents
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates jq less file findutils tree man-db procps psmisc iproute2 iputils-ping ripgrep fd-find yq picocom git usbutils sudo libusb-1.0-0-dev moreutils tmux fzf git-lfs openssh-client parallel unzip zip xz-utils
# Install component dependencies in separate layers for caching
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends python3-full
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
# Smoke test Python by running a tiny script
RUN <<'EOF'
set -eu
python3 -c 'print("python-ok")' | grep -qx 'python-ok'

EOF
# Default to launching a bash shell
CMD ["/bin/bash"]
