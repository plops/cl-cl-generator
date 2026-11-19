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
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates jq less file findutils tree man-db procps psmisc iproute2 iputils-ping ripgrep fd-find yq picocom git usbutils sudo libusb-1.0-0-dev moreutils tmux fzf git-lfs openssh-client parallel unzip zip xz-utils
# Install component dependencies in separate layers for caching
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt/lists,sharing=locked apt-get update \
 && apt-get install -y --no-install-recommends python3-full
# Install or copy other AI CLI tools
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
# Smoke test Kiro CLI ACP command
RUN <<'EOF'
set -eu
kiro-cli acp --help > /tmp/kiro-cli-acp-help.txt
grep -qi 'acp' /tmp/kiro-cli-acp-help.txt

EOF
# Default to launching a bash shell
CMD ["/bin/bash"]
