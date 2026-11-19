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
# Default to launching a bash shell
CMD ["/bin/bash"]
