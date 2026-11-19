#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
enable_host_kmsg=0
enable_host_opt=0
enable_docker_sock=0
enable_gpus=0
enable_graphics=0
enable_display=0
enable_usb=0
enable_source_isolation=1
enable_host_network=0
enable_host_ssh=0
lbw_host_port=7878
lbw_port_explicit=0
gpus_spec="all"
verbose=0
dry_run=0

# Repositories mounted below /workspace/src with --source-isolation.
# Override with SOURCE_REPOS="repo1 repo2 ..." (names relative to HOST_SRC_ROOT).
default_source_repos="cl-py-generator cl-cl-generator cl-cpp-generator2 cl-rust-generator
rs-summarizer mosh-tcp rs_disk_treemap pge_treemap transpiled_treemap parenmedic mbti
github plops.github.io copernicus-radar"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Run the AI environment container with the project source mounted in.

Options:
  --gpus [SPEC]  Pass through NVIDIA GPUs via NVIDIA Container Toolkit (default: all).
                 If Docker has no NVIDIA support, a warning is printed and the
                 container starts without GPUs (set FORCE_NVIDIA=1 to skip the check).
  --gpu          Alias for --gpus all.
  --graphics     Enable GPU graphics/display: /dev/dri, X11/display and --ipc=host;
                 with NVIDIA additionally all driver capabilities (OpenGL, Vulkan,
                 EGL, video). Works with Intel/AMD iGPUs via /dev/dri.
  --display, --x11
                 Pass through host X11 display, .Xauthority, and sockets (supports SSH X11 forwarding).
  --host-kmsg    Run the container privileged so host kernel messages (/dev/kmsg)
                 can be read from inside the container.
  --host-opt     Bind mount host /opt read-only at /host/opt. The container's
                 /opt must remain intact for the NVIDIA CUDA entrypoint.
  --usb          Run privileged so the host USB bus is available (needed for
                 J-Link probes; grants broad access to host devices).
  --source-isolation
                 Mount only the configured project sources (default).
  --no-source-isolation
                 Mount the complete source root at /workspace/src.
  --docker-sock  Bind mount the host Docker socket and add its numeric group.
                 This grants root-equivalent control over the host Docker daemon.
  --host-ssh     Allow ssh from the container to the host (default: off).
                 Creates a temporary ed25519 key, appends it (restricted to the
                 Docker bridge subnet / loopback) to ~/.ssh/authorized_keys,
                 maps it to /root/.ssh/id_host and configures "ssh host".
                 The key and the authorized_keys entry are removed on exit.
                 Requires a running sshd on the host. Not usable with --dry-run.
  --lbw-port PORT
                 Use PORT on host loopback for container port 7878 (default 7878).
                 Publishes the lbw-server port; the server must listen on
                 0.0.0.0 inside the container (1-65535).
  --host-network Share the host network for login flows that need host localhost.
                 Port publishing is unavailable in this mode.
  -n, --dry-run  Do not start a container. Print only the docker run options
                 (without "docker run -it" and without the image name) as one
                 shell-quoted line on stdout, e.g. for the CLion Docker
                 toolchain "Container settings" field. The image name is
                 printed to stderr.
  -v, --verbose  Print the executed commands.
  -h, --help     Show this help text and exit.

Environment:
  ENV_FILE            Override the env file path. Default: $script_dir/.env.ai
  IMAGE_NAME          Override the image name. Default: my-ai-env:latest
  HOST_SRC_ROOT       Override the source root (default: parent of cl-cl-generator).
  WORKSPACE_SRC_ROOT  Fallback source root override.
  SOURCE_REPOS        Space separated repo names for --source-isolation.
  CONTAINER_NAME      Container name (default: ai-env-<pid>).
  HOST_SSH_PORT       sshd port on the host for --host-ssh (default: 22).
  HOST_SSH_USER       Host user for --host-ssh (default: $(id -un)).
  FORCE_NVIDIA        Set to 1 to pass --gpus without checking Docker's NVIDIA support.

Example:
  ./setup02_run.sh --gpu --host-kmsg --usb --no-source-isolation --docker-sock --x11 --graphics
  ./setup02_run.sh --gpu --host-kmsg --usb --source-isolation --docker-sock --x11 --graphics --host-ssh
  ./setup02_run.sh --dry-run --gpu --host-kmsg --usb --source-isolation --docker-sock --x11 --graphics
EOF
}

warn() {
  echo "Warning: $*" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --gpus)
      enable_gpus=1
      if [ "$#" -gt 1 ] && [ "$(printf '%s' "$2" | cut -c1-2)" != "--" ]; then
        gpus_spec="$2"
        shift
      fi
      ;;
    --gpu)
      enable_gpus=1
      ;;
    --graphics|--gpu-graphics)
      enable_graphics=1
      enable_gpus=1
      ;;
    --display|--x11)
      enable_display=1
      ;;
    --host-kmsg)
      enable_host_kmsg=1
      ;;
    --host-opt)
      enable_host_opt=1
      ;;
    --usb)
      enable_usb=1
      ;;
    --source-isolation)
      enable_source_isolation=1
      ;;
    --no-source-isolation)
      enable_source_isolation=0
      ;;
    --docker-sock)
      enable_docker_sock=1
      ;;
    --host-ssh)
      enable_host_ssh=1
      ;;
    --lbw-port)
      if [ "$#" -lt 2 ]; then
        echo "--lbw-port requires a port number." >&2
        exit 1
      fi
      lbw_host_port=$2
      lbw_port_explicit=1
      shift
      ;;
    --host-network)
      enable_host_network=1
      ;;
    -v|--verbose)
      verbose=1
      ;;
    -n|--dry-run)
      dry_run=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use -h for usage." >&2
      exit 1
      ;;
  esac
  shift
done

case "$lbw_host_port" in
  ''|*[!0-9]*) echo "lbw host port must be an integer from 1 to 65535." >&2; exit 1 ;;
esac
if [ "$lbw_host_port" -lt 1 ] || [ "$lbw_host_port" -gt 65535 ]; then
  echo "lbw host port must be an integer from 1 to 65535." >&2
  exit 1
fi
if [ "$enable_host_network" -eq 1 ] && [ "$lbw_port_explicit" -eq 1 ]; then
  echo "--lbw-port cannot be used with --host-network; bind the server to 127.0.0.1 inside the container." >&2
  exit 1
fi
if [ "$enable_host_ssh" -eq 1 ] && [ "$dry_run" -eq 1 ]; then
  echo "--host-ssh cannot be used with --dry-run: the temporary key could not be removed afterwards." >&2
  exit 1
fi

if [ -n "${ENV_FILE:-}" ]; then
  env_file=$ENV_FILE
else
  env_file="$script_dir/.env.ai"
fi

if [ -n "${HOST_SRC_ROOT:-}" ]; then
  host_src_root=$HOST_SRC_ROOT
elif [ -n "${WORKSPACE_SRC_ROOT:-}" ]; then
  host_src_root=$WORKSPACE_SRC_ROOT
else
  host_src_root=$(CDPATH= cd -- "$script_dir/../../../../../../" && pwd)
fi

image_name=${IMAGE_NAME:-my-ai-env:latest}
host_user_name=root
DHOME=/root

if [ ! -f "$env_file" ]; then
  echo "Missing env file: $env_file" >&2
  echo "Create it or set ENV_FILE=/path/to/your.env before running this script." >&2
  exit 1
fi

for d in .gemini .kiro .local/share/kiro-cli .local/share/muse .aws .azure \
         .copilot .openai .codex .claude .conan2 .ssh .config/tc \
         .config/github-copilot .config/openai .config/codex .config/muse \
         .cache/huggingface .cache/uv; do
  mkdir -p "$HOME/$d"
done

# Collect only the docker run options here; "docker run -it" and the image
# name are added at the end so --dry-run can print the bare options.
set -- \
  --env-file "$env_file" \
  -e HOME=$DHOME \
  -e USER="$host_user_name" \
  -e LOGNAME="$host_user_name" \
  -e ANTIGRAVITY_PLAINTEXT_AUTH=1 \
  -e AZURE_CONFIG_DIR=$DHOME/.azure \
  -e CLAUDE_CONFIG_DIR=$DHOME/.claude \
  -v "$HOME/.gemini:$DHOME/.gemini" \
  -v "$HOME/.kiro:$DHOME/.kiro" \
  -v "$HOME/.local/share/kiro-cli:$DHOME/.local/share/kiro-cli" \
  -v "$HOME/.local/share/muse:$DHOME/.local/share/muse" \
  -v "$HOME/.aws:$DHOME/.aws" \
  -v "$HOME/.azure:$DHOME/.azure" \
  -v "$HOME/.copilot:$DHOME/.copilot" \
  -v "$HOME/.openai:$DHOME/.openai" \
  -v "$HOME/.codex:$DHOME/.codex" \
  -v "$HOME/.claude:$DHOME/.claude" \
  -v "$HOME/.conan2:$DHOME/.conan2" \
  -v "$HOME/.ssh:$DHOME/.ssh" \
  -v "$HOME/.config/tc:$DHOME/.config/tc" \
  -v "$HOME/.config/github-copilot:$DHOME/.config/github-copilot" \
  -v "$HOME/.config/openai:$DHOME/.config/openai" \
  -v "$HOME/.config/codex:$DHOME/.config/codex" \
  -v "$HOME/.config/muse:$DHOME/.config/muse" \
  -v "$HOME/.cache/huggingface:$DHOME/.cache/huggingface" \
  -v "$HOME/.cache/uv:$DHOME/.cache/uv" \
  -v my-ai-env-cargo-cache:$DHOME/.cargo \
  --rm \
  --user 0:0

# A fixed name would collide when CLion reuses the printed options.
if [ "$dry_run" -eq 0 ]; then
  set -- "$@" --name "${CONTAINER_NAME:-ai-env-$$}"
fi

if [ "$enable_host_network" -eq 1 ]; then
  set -- "$@" --network host
else
  set -- "$@" --hostname ai-env -p "127.0.0.1:${lbw_host_port}:7878"
fi

if [ "$enable_source_isolation" -eq 1 ]; then
  for repo in ${SOURCE_REPOS:-$default_source_repos}; do
    if [ -d "$host_src_root/$repo" ]; then
      set -- "$@" -v "$host_src_root/$repo:/workspace/src/$repo"
    else
      warn "source repo not found, not mounted: $host_src_root/$repo"
    fi
  done
else
  set -- "$@" -v "$host_src_root:/workspace/src"
fi

# --privileged exposes all host devices (/dev/kmsg, /dev/bus/usb, /dev/dri,
# serial adapters), so the individual device mounts are only needed without it.
privileged=0
if [ "$enable_host_kmsg" -eq 1 ] || [ "$enable_usb" -eq 1 ]; then
  privileged=1
fi
if [ "$enable_usb" -eq 1 ] && [ ! -d /dev/bus/usb ]; then
  echo "USB bus is not available at /dev/bus/usb" >&2
  exit 1
fi
if [ "$privileged" -eq 1 ]; then
  set -- "$@" --privileged
fi

if [ "$enable_host_opt" -eq 1 ]; then
  set -- "$@" -v /opt:/host/opt:ro
fi

# Docker can only satisfy --gpus when the NVIDIA Container Toolkit is set up
# (legacy hook/runtime or a CDI spec). Without it, docker run fails with
# 'could not select device driver "" with capabilities: [[gpu]]'.
nvidia_docker_available() {
  [ "${FORCE_NVIDIA:-0}" = "1" ] && return 0
  command -v nvidia-container-runtime-hook >/dev/null 2>&1 && return 0
  docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q nvidia && return 0
  for spec in /etc/cdi/nvidia*.yaml /etc/cdi/nvidia*.json /var/run/cdi/nvidia*.yaml /var/run/cdi/nvidia*.json; do
    [ -e "$spec" ] && return 0
  done
  return 1
}

if [ "$enable_gpus" -eq 1 ] && ! nvidia_docker_available; then
  if [ -e /dev/nvidia0 ]; then
    warn "NVIDIA GPU found, but Docker has no NVIDIA support (install nvidia-container-toolkit and run 'nvidia-ctk runtime configure --runtime=docker'). Starting without --gpus."
  else
    warn "no NVIDIA GPU/Container Toolkit available. Starting without --gpus."
  fi
  enable_gpus=0
fi

if [ "$enable_gpus" -eq 1 ]; then
  if [ "$enable_graphics" -eq 1 ]; then
    # Request full NVIDIA driver capabilities (compute, utility, graphics, display, video)
    set -- "$@" -e NVIDIA_DRIVER_CAPABILITIES=all
    if [ "$gpus_spec" = "all" ]; then
      set -- "$@" --gpus 'all,"capabilities=compute,utility,graphics,display,video"'
    else
      set -- "$@" --gpus "$gpus_spec"
    fi
  else
    set -- "$@" --gpus "$gpus_spec"
  fi
fi

if [ "$enable_graphics" -eq 1 ]; then
  # DRM render nodes for direct/headless rendering (Intel/AMD/NVIDIA).
  if [ "$privileged" -eq 0 ] && [ -d /dev/dri ]; then
    set -- "$@" --device /dev/dri:/dev/dri
  fi
  # Host IPC for shared memory performance (MIT-SHM / X11 / Vulkan)
  set -- "$@" --ipc=host
fi

if [ "$enable_display" -eq 1 ] || [ "$enable_graphics" -eq 1 ]; then
  if [ -n "${DISPLAY:-}" ]; then
    set -- "$@" -e DISPLAY="$DISPLAY"
  fi
  # X11 socket directory (local X11; SSH X11 forwarding needs --host-network)
  if [ -d /tmp/.X11-unix ]; then
    set -- "$@" -v /tmp/.X11-unix:/tmp/.X11-unix:rw
  fi
  xauth_file="${XAUTHORITY:-$HOME/.Xauthority}"
  if [ -f "$xauth_file" ]; then
    set -- "$@" -v "$xauth_file:$DHOME/.Xauthority:ro" -e XAUTHORITY=$DHOME/.Xauthority
  fi
fi

if [ "$enable_docker_sock" -eq 1 ]; then
  if [ ! -S /var/run/docker.sock ]; then
    echo "Docker socket is not available at /var/run/docker.sock" >&2
    exit 1
  fi
  set -- "$@" --group-add "$(stat -c '%g' /var/run/docker.sock)" \
    -e DOCKER_HOST=unix:///var/run/docker.sock \
    -v /var/run/docker.sock:/var/run/docker.sock
fi

# Pass through currently attached serial adapters from the host.
if [ "$privileged" -eq 0 ]; then
  for dev in /dev/ttyUSB* /dev/ttyACM*; do
    if [ -e "$dev" ]; then
      set -- "$@" --device "$dev:$dev"
    fi
  done
fi

# Quote a single argument for POSIX shells; plain arguments stay unquoted.
shell_quote() {
  case "$1" in
    ''|*[!A-Za-z0-9_./:=,@%+-]*)
      printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

if [ "$dry_run" -eq 1 ]; then
  sep=""
  for arg in "$@"; do
    printf '%s' "$sep"
    shell_quote "$arg"
    sep=" "
  done
  printf '\n'
  echo "Image: $image_name" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# --host-ssh: temporary key for ssh from the container into the host.
# /root/.ssh in the container is the host's ~/.ssh, so the "host" alias goes
# into /etc/ssh/ssh_config.d instead of ~/.ssh/config: this leaves the host
# config untouched and avoids OpenSSH's "Bad owner" check on a config file
# owned by the host UID.
# ---------------------------------------------------------------------------
ssh_tmpdir=""
ssh_marker=""
auth_keys="$HOME/.ssh/authorized_keys"
auth_keys_created=0
id_host_placeholder=0

cleanup_host_ssh() {
  if [ -n "$ssh_marker" ] && [ -f "$auth_keys" ]; then
    if grep -qF "$ssh_marker" "$auth_keys"; then
      # Rewrite in place to keep inode, owner and mode of authorized_keys.
      grep -vF "$ssh_marker" "$auth_keys" > "$ssh_tmpdir/authorized_keys.new" || true
      cat "$ssh_tmpdir/authorized_keys.new" > "$auth_keys"
    fi
    if [ "$auth_keys_created" -eq 1 ] && [ ! -s "$auth_keys" ]; then
      rm -f "$auth_keys"
    fi
  fi
  # Docker creates an empty mount point file for /root/.ssh/id_host in ~/.ssh.
  if [ "$id_host_placeholder" -eq 1 ] && [ -f "$HOME/.ssh/id_host" ] && [ ! -s "$HOME/.ssh/id_host" ]; then
    rm -f "$HOME/.ssh/id_host"
  fi
  if [ -n "$ssh_tmpdir" ]; then
    rm -rf "$ssh_tmpdir"
  fi
}

if [ "$enable_host_ssh" -eq 1 ]; then
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "--host-ssh requires ssh-keygen on the host." >&2
    exit 1
  fi
  trap cleanup_host_ssh EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  ssh_tmpdir=$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ai-env-host-ssh.XXXXXX")
  chmod 700 "$ssh_tmpdir"
  ssh_marker=$(basename "$ssh_tmpdir")
  ssh-keygen -q -t ed25519 -N '' -C "$ssh_marker" -f "$ssh_tmpdir/id_host"

  # Restrict the key to connections from the Docker bridge and loopback.
  if [ "$enable_host_network" -eq 1 ]; then
    ssh_from="127.0.0.1,::1"
  else
    bridge_subnets=$(docker network inspect bridge --format '{{range .IPAM.Config}}{{.Subnet}},{{end}}' 2>/dev/null || true)
    ssh_from="${bridge_subnets}127.0.0.1,::1"
    if [ -z "$bridge_subnets" ]; then
      warn "could not determine the Docker bridge subnet; the host key is limited to loopback and may not work."
    fi
  fi

  [ -e "$auth_keys" ] || auth_keys_created=1
  touch "$auth_keys"
  chmod 600 "$auth_keys"
  # Make sure the appended entry starts on its own line.
  if [ -s "$auth_keys" ] && [ "$(tail -c 1 "$auth_keys" | od -An -c | tr -d ' ')" != '\n' ]; then
    echo >> "$auth_keys"
  fi
  printf 'from="%s",no-agent-forwarding %s\n' "$ssh_from" "$(cat "$ssh_tmpdir/id_host.pub")" >> "$auth_keys"

  # Pin the host's own host keys, so StrictHostKeyChecking can stay on.
  : > "$ssh_tmpdir/known_hosts"
  for pub in /etc/ssh/ssh_host_*_key.pub; do
    [ -r "$pub" ] && printf 'ai-env-host %s\n' "$(cut -d' ' -f1,2 "$pub")" >> "$ssh_tmpdir/known_hosts"
  done
  if [ -s "$ssh_tmpdir/known_hosts" ]; then
    strict_host_key=yes
  else
    warn "no readable /etc/ssh/ssh_host_*_key.pub; using StrictHostKeyChecking=accept-new."
    strict_host_key=accept-new
  fi

  if [ "$enable_host_network" -eq 1 ]; then
    ssh_host_addr=127.0.0.1
  else
    ssh_host_addr=host.docker.internal
    set -- "$@" --add-host host.docker.internal:host-gateway
  fi
  cat > "$ssh_tmpdir/host.conf" <<EOF
# Generated by setup02_run.sh --host-ssh; removed when the container exits.
Host host
  HostName $ssh_host_addr
  Port ${HOST_SSH_PORT:-22}
  User ${HOST_SSH_USER:-$(id -un)}
  IdentityFile $DHOME/.ssh/id_host
  IdentitiesOnly yes
  HostKeyAlias ai-env-host
  UserKnownHostsFile /run/ai-env-host-ssh/known_hosts
  StrictHostKeyChecking $strict_host_key
EOF

  [ -e "$HOME/.ssh/id_host" ] || id_host_placeholder=1
  set -- "$@" \
    -v "$ssh_tmpdir:/run/ai-env-host-ssh" \
    -v "$ssh_tmpdir/id_host:$DHOME/.ssh/id_host:ro" \
    -v "$ssh_tmpdir/host.conf:/etc/ssh/ssh_config.d/00-ai-env-host.conf:ro"
fi

set -- docker run -it "$@" "$image_name"

if [ "$verbose" -eq 1 ]; then
  echo "+ $*" >&2
fi

if [ "$enable_host_ssh" -eq 1 ]; then
  # Keep the shell alive so the EXIT trap can remove the key afterwards.
  rc=0
  "$@" || rc=$?
  exit "$rc"
fi

exec "$@"
