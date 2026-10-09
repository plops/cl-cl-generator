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
kirocrew_host_port=5476
kirocrew_publish_port=1
kirocrew_port_explicit=0
lbw_host_port=7878
lbw_publish_port=1
lbw_port_explicit=0
kirocrew_seccomp_profile=""
gpus_spec="all"
verbose=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Run the AI environment container with the project source mounted in.

Options:
  --gpus [SPEC]  Pass through GPUs to the container via NVIDIA Container Toolkit (default: all).
  --gpu          Alias for --gpus all.
  --graphics     Enable GPU graphics/display capabilities (OpenGL, Vulkan, EGL, display, video)
                 and pass through /dev/dri and X11/display if available (works headless and over SSH).
  --display      Pass through host X11 display, .Xauthority, and sockets (supports SSH X11 forwarding).
  --host-kmsg    Run the container privileged and bind /dev/kmsg so host kernel
                 messages can be read from inside the container.
  --host-opt     Bind mount host /opt read-only at /host/opt. The container's
                 /opt must remain intact for the NVIDIA CUDA entrypoint.
  --usb          Pass through the host USB bus in privileged mode (needed for
                 J-Link probes; grants broad access to host devices).
  --source-isolation
                 Mount only the configured project sources (default).
  --no-source-isolation
                 Mount the complete source root at /workspace/src.
  --docker-sock  Bind mount the host Docker socket and add its numeric group.
                 This grants root-equivalent control over the host Docker daemon.
  --kirocrew-port PORT
                 Use PORT on host loopback for container port 5476 (default 5476).
                 The container still starts in Bash (1-65535).
  --lbw-port PORT
                 Use PORT on host loopback for container port 7878 (default 7878).
                 Publishes the lbw-server port; the server must listen on
                 0.0.0.0 inside the container (1-65535).
  --host-network  Share the host network for login flows that need host localhost.
                 KiroCrew port publishing is unavailable in this mode.
  --kirocrew-sandbox-profile FILE
                 Use KiroCrew's seccomp profile and AppArmor opt-out so its
                 inner user-namespace sandbox can run.
  -v, --verbose  Print the executed commands.
  -h, --help     Show this help text and exit.

Environment:
  ENV_FILE            Override the env file path. Default: $script_dir/.env.ai
  IMAGE_NAME          Override the image name. Default: my-ai-env:latest
  HOST_SRC_ROOT       Override the mounted source root.
  WORKSPACE_SRC_ROOT  Fallback source root override.

Example:
  ./setup02_run.sh --gpu --host-kmsg --usb --no-source-isolation --docker-sock --x11 --graphics
  ./setup02_run.sh --gpu --host-kmsg --usb --source-isolation --docker-sock --x11 --graphics
EOF
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
    --kirocrew-port)
      if [ "$#" -lt 2 ]; then
        echo "--kirocrew-port requires a port number." >&2
        exit 1
      fi
      kirocrew_host_port=$2
      kirocrew_publish_port=1
      kirocrew_port_explicit=1
      shift
      ;;
    --lbw-port)
      if [ "$#" -lt 2 ]; then
        echo "--lbw-port requires a port number." >&2
        exit 1
      fi
      lbw_host_port=$2
      lbw_publish_port=1
      lbw_port_explicit=1
      shift
      ;;
    --host-network)
      enable_host_network=1
      ;;
    --kirocrew-sandbox-profile)
      if [ "$#" -lt 2 ]; then
        echo "--kirocrew-sandbox-profile requires a profile path." >&2
        exit 1
      fi
      kirocrew_seccomp_profile=$2
      shift
      ;;
    -v|--verbose)
      verbose=1
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

if [ "$kirocrew_publish_port" -eq 1 ]; then
  case "$kirocrew_host_port" in
    ''|*[!0-9]*) echo "KiroCrew host port must be an integer from 1 to 65535." >&2; exit 1 ;;
  esac
  if [ "$kirocrew_host_port" -lt 1 ] || [ "$kirocrew_host_port" -gt 65535 ]; then
    echo "KiroCrew host port must be an integer from 1 to 65535." >&2
    exit 1
  fi
fi
if [ "$enable_host_network" -eq 1 ] && [ "$kirocrew_port_explicit" -eq 1 ]; then
  echo "--kirocrew-port cannot be used with --host-network; use gateway --port inside the container." >&2
  exit 1
fi
if [ "$lbw_publish_port" -eq 1 ]; then
  case "$lbw_host_port" in
    ''|*[!0-9]*) echo "lbw host port must be an integer from 1 to 65535." >&2; exit 1 ;;
  esac
  if [ "$lbw_host_port" -lt 1 ] || [ "$lbw_host_port" -gt 65535 ]; then
    echo "lbw host port must be an integer from 1 to 65535." >&2
    exit 1
  fi
fi
if [ "$enable_host_network" -eq 1 ] && [ "$lbw_port_explicit" -eq 1 ]; then
  echo "--lbw-port cannot be used with --host-network; bind the server to 127.0.0.1 inside the container." >&2
  exit 1
fi
if [ -n "$kirocrew_seccomp_profile" ] && [ ! -r "$kirocrew_seccomp_profile" ]; then
  echo "KiroCrew sandbox profile is not readable: $kirocrew_seccomp_profile" >&2
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
host_uid=$(id -u)
host_gid=$(id -g)
host_user_name=root #$(id -un)

mkdir -p "$HOME/.gemini"
mkdir -p "$HOME/.kiro"
mkdir -p "$HOME/.kiro/crew-yolo"
mkdir -p "$HOME/.local/share/kiro-cli"
mkdir -p "$HOME/.local/share/muse"
mkdir -p "$HOME/.aws"
mkdir -p "$HOME/.azure"
mkdir -p "$HOME/.copilot"
mkdir -p "$HOME/.openai"
mkdir -p "$HOME/.codex"
mkdir -p "$HOME/.conan2"
mkdir -p "$HOME/.ssh"
mkdir -p "$HOME/.config/tc"
mkdir -p "$HOME/.config/github-copilot"
mkdir -p "$HOME/.config/openai"
mkdir -p "$HOME/.config/codex"
mkdir -p "$HOME/.config/muse"
mkdir -p "$HOME/.cache/huggingface"
mkdir -p "$HOME/.cache/uv"

export DHOME=/root #home/ubuntu/

if [ ! -f "$env_file" ]; then
  echo "Missing env file: $env_file" >&2
  echo "Create it or set ENV_FILE=/path/to/your.env before running this script." >&2
  exit 1
fi

set -- docker run -it \
  --env-file "$env_file" \
  -e HOME=$DHOME \
  -e USER="$host_user_name" \
  -e LOGNAME="$host_user_name" \
  -e KIROCREW_HOME=$DHOME/.kiro/crew-yolo \
  -e ANTIGRAVITY_PLAINTEXT_AUTH=1 \
  -e AZURE_CONFIG_DIR=$DHOME/.azure \
  -v "$HOME/.gemini:$DHOME/.gemini" \
  -v "$HOME/.kiro:$DHOME/.kiro" \
  -v "$HOME/.kiro/crew-yolo:$DHOME/.kiro/crew-yolo" \
  -v "$HOME/.local/share/kiro-cli:$DHOME/.local/share/kiro-cli" \
  -v "$HOME/.local/share/muse:$DHOME/.local/share/muse" \
  -v "$HOME/.aws:$DHOME/.aws" \
  -v "$HOME/.azure:$DHOME/.azure" \
  -v "$HOME/.copilot:$DHOME/.copilot" \
  -v "$HOME/.openai:$DHOME/.openai" \
  -v "$HOME/.codex:$DHOME/.codex" \
  -v "$HOME/.conan2:$DHOME/.conan2" \
  -v "$HOME/.ssh:$DHOME/.ssh" \
  -v "$HOME/.config/tc:$DHOME/.config/tc" \
  -v "$HOME/.config/github-copilot:$DHOME/.config/github-copilot" \
  -v "$HOME/.config/openai:$DHOME/.config/openai" \
  -v "$HOME/.config/codex:$DHOME/.config/codex" \
  -v "$HOME/.config/muse:$DHOME/.config/muse" \
  -v "$HOME/.cache/huggingface:$DHOME/.cache/huggingface" \
  -v "$HOME/.cache/uv:$DHOME/.cache/uv" \
  -v my-ai-env-cargo-cache:$DHOME/.cargo

if [ "$enable_host_network" -eq 1 ]; then
  set -- "$@" --network host -e KIROCREW_BIND=127.0.0.1
elif [ "$kirocrew_publish_port" -eq 1 ]; then
  set -- "$@" -e KIROCREW_BIND=0.0.0.0 -p "127.0.0.1:${kirocrew_host_port}:5476"
fi
if [ "$enable_host_network" -eq 0 ] && [ "$lbw_publish_port" -eq 1 ]; then
  set -- "$@" -p "127.0.0.1:${lbw_host_port}:7878"
fi
if [ -n "$kirocrew_seccomp_profile" ]; then
  set -- "$@" --security-opt "seccomp=$kirocrew_seccomp_profile" --security-opt apparmor=unconfined
fi

set -- "$@" --user 0:0 #"$host_uid:$host_gid"

# Preserve the invoking user's supplementary numeric groups for bind mounts.
# Docker's --user UID:GID alone drops these groups.
for host_group in $(id -G); do
  if [ "$host_group" != "$host_gid" ]; then
    set -- "$@" --group-add "$host_group"
  fi
done

if [ "$enable_source_isolation" -eq 1 ]; then
  set -- "$@" \
    -v "/home/kiel/stage/cl-py-generator:/workspace/src/cl-py-generator" \
    -v "/home/kiel/stage/cl-cl-generator:/workspace/src/cl-cl-generator" \
    -v "/home/kiel/stage/cl-cpp-generator2:/workspace/src/cl-cpp-generator2" \
    -v "/home/kiel/stage/cl-rust-generator:/workspace/src/cl-rust-generator" \
    -v "/home/kiel/stage/rs-summarizer:/workspace/src/rs-summarizer" \
    -v "/home/kiel/stage/mosh-tcp:/workspace/src/mosh-tcp" \
    -v "/home/kiel/stage/rs_disk_treemap:/workspace/src/rs_disk_treemap" \
    -v "/home/kiel/stage/pge_treemap:/workspace/src/pge_treemap" \
    -v "/home/kiel/stage/transpiled_treemap:/workspace/src/transpiled_treemap" \
    -v "/home/kiel/stage/parenmedic:/workspace/src/parenmedic" \
    -v "/home/kiel/stage/mbti:/workspace/src/mbti" \
    -v "/home/kiel/stage/github:/workspace/src/github" \
    -v "/home/kiel/stage/plops.github.io:/workspace/src/plops.github.io" \
    -v "/home/kiel/stage/copernicus-radar:/workspace/src/copernicus-radar"
else
  set -- "$@" -v "$host_src_root:/workspace/src"
fi

if [ "$enable_host_kmsg" -eq 1 ]; then
  set -- "$@" --privileged -v /dev/kmsg:/dev/kmsg
fi

if [ "$enable_host_opt" -eq 1 ]; then
  set -- "$@" -v /opt:/host/opt:ro
fi

if [ "$enable_usb" -eq 1 ]; then
  if [ ! -d /dev/bus/usb ]; then
    echo "USB bus is not available at /dev/bus/usb" >&2
    exit 1
  fi
  set -- "$@" --privileged -v /dev/bus/usb:/dev/bus/usb
fi

if [ "$enable_graphics" -eq 1 ]; then
  # Request full NVIDIA driver capabilities (compute, utility, graphics, display, video)
  set -- "$@" -e NVIDIA_DRIVER_CAPABILITIES=all
  if [ "$enable_gpus" -eq 1 ]; then
    if [ "$gpus_spec" = "all" ]; then
      set -- "$@" --gpus 'all,"capabilities=compute,utility,graphics,display,video"'
    else
      set -- "$@" --gpus "$gpus_spec"
    fi
  fi
  # Mount DRM render nodes if present on host for direct/headless rendering
  if [ -d /dev/dri ]; then
    set -- "$@" --device /dev/dri:/dev/dri
  fi
  # Enable host IPC for shared memory performance (MIT-SHM / X11 / Vulkan)
  set -- "$@" --ipc=host
elif [ "$enable_gpus" -eq 1 ]; then
  set -- "$@" --gpus "$gpus_spec"
fi

if [ "$enable_display" -eq 1 ] || [ "$enable_graphics" -eq 1 ]; then
  # Forward DISPLAY if set in host/SSH environment
  if [ -n "${DISPLAY:-}" ]; then
    set -- "$@" -e DISPLAY="$DISPLAY"
  fi

  # Mount X11 socket directory if present (supports local X11 and SSH X11 forwarding)
  if [ -d /tmp/.X11-unix ]; then
    set -- "$@" -v /tmp/.X11-unix:/tmp/.X11-unix:rw
  fi

  # Forward Xauthority for X11 authentication over SSH or local session
  xauth_file="${XAUTHORITY:-${HOME:-/root}/.Xauthority}"
  if [ -f "$xauth_file" ]; then
    set -- "$@" -v "$xauth_file:$DHOME/.Xauthority:ro" -e XAUTHORITY=$DHOME/.Xauthority
  fi
fi

if [ "$enable_docker_sock" -eq 1 ]; then
  if [ ! -S /var/run/docker.sock ]; then
    echo "Docker socket is not available at /var/run/docker.sock" >&2
    exit 1
  fi
  docker_socket_gid=$(stat -c '%g' /var/run/docker.sock)
  case " $(id -G) " in
    *" $docker_socket_gid "*) ;;
    *) set -- "$@" --group-add "$docker_socket_gid" ;;
  esac
  set -- "$@" -e DOCKER_HOST=unix:///var/run/docker.sock \
    -v /var/run/docker.sock:/var/run/docker.sock
fi

# Pass through currently attached serial adapters from the host.
for dev in /dev/ttyUSB* /dev/ttyACM*; do
  if [ -e "$dev" ]; then
    set -- "$@" --device "$dev:$dev"
  fi
done

if [ "$verbose" -eq 1 ]; then
  echo "+ $* $image_name" >&2
fi

set -- "$@" "$image_name"
exec "$@"
