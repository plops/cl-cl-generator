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
  --docker-sock  Bind mount the host Docker socket. This grants the container
                 root-equivalent control over the host Docker daemon.
  -v, --verbose  Print the executed commands.
  -h, --help     Show this help text and exit.

Environment:
  ENV_FILE            Override the env file path. Default: $script_dir/.env.ai
  IMAGE_NAME          Override the image name. Default: my-ai-env:latest
  HOST_SRC_ROOT       Override the mounted source root.
  WORKSPACE_SRC_ROOT  Fallback source root override.
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
    --docker-sock)
      enable_docker_sock=1
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

mkdir -p "$HOME/.gemini"
mkdir -p "$HOME/.kiro"
mkdir -p "$HOME/.local/share/kiro-cli"
mkdir -p "$HOME/.aws"
mkdir -p "$HOME/.azure"
mkdir -p "$HOME/.copilot"
mkdir -p "$HOME/.openai"
mkdir -p "$HOME/.codex"
mkdir -p "$HOME/.config/tc"
mkdir -p "$HOME/.config/github-copilot"
mkdir -p "$HOME/.config/openai"
mkdir -p "$HOME/.config/codex"

if [ ! -f "$env_file" ]; then
  echo "Missing env file: $env_file" >&2
  echo "Create it or set ENV_FILE=/path/to/your.env before running this script." >&2
  exit 1
fi

set -- docker run -it \
  --env-file "$env_file" \
  -e ANTIGRAVITY_PLAINTEXT_AUTH=1 \
  -e AZURE_CONFIG_DIR=/root/.azure \
  -v "$HOME/.gemini:/root/.gemini" \
  -v "$HOME/.kiro:/root/.kiro" \
  -v "$HOME/.local/share/kiro-cli:/root/.local/share/kiro-cli" \
  -v "$HOME/.aws:/root/.aws" \
  -v "$HOME/.azure:/root/.azure" \
  -v "$HOME/.copilot:/root/.copilot" \
  -v "$HOME/.openai:/root/.openai" \
  -v "$HOME/.codex:/root/.codex" \
  -v "$HOME/.config/tc:/root/.config/tc" \
  -v "$HOME/.config/github-copilot:/root/.config/github-copilot" \
  -v "$HOME/.config/openai:/root/.config/openai" \
  -v "$HOME/.config/codex:/root/.config/codex" \
  -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  -v "$host_src_root:/workspace/src" \
  -v my-ai-env-cargo-cache:/root/.cargo

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
    set -- "$@" -v "$xauth_file:/root/.Xauthority:ro" -e XAUTHORITY=/root/.Xauthority
  fi
fi

if [ "$enable_docker_sock" -eq 1 ]; then
  if [ ! -S /var/run/docker.sock ]; then
    echo "Docker socket is not available at /var/run/docker.sock" >&2
    exit 1
  fi
  set -- "$@" -v /var/run/docker.sock:/var/run/docker.sock
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

exec "$@" "$image_name"
