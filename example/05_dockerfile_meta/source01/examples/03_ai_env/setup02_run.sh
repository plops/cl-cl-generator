#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
enable_host_kmsg=0
enable_host_opt=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Run the AI environment container with the project source mounted in.

Options:
  --host-kmsg   Run the container privileged and bind /dev/kmsg so host kernel
                messages can be read from inside the container.
  --host-opt    Bind mount host /opt to /opt inside the container.
  -h, --help    Show this help text and exit.

Environment:
  ENV_FILE            Override the env file path. Default: $script_dir/.env.ai
  IMAGE_NAME          Override the image name. Default: my-ai-env:latest
  HOST_SRC_ROOT       Override the mounted source root.
  WORKSPACE_SRC_ROOT  Fallback source root override.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host-kmsg)
      enable_host_kmsg=1
      ;;
    --host-opt)
      enable_host_opt=1
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

if [ ! -f "$env_file" ]; then
  echo "Missing env file: $env_file" >&2
  echo "Create it or set ENV_FILE=/path/to/your.env before running this script." >&2
  exit 1
fi

set -- docker run -it \
  --env-file "$env_file" \
  -e ANTIGRAVITY_PLAINTEXT_AUTH=1 \
  -v "$HOME/.gemini:/root/.gemini" \
  -v "$host_src_root:/workspace/src" \
  -v my-ai-env-cargo-cache:/root/.cargo

if [ "$enable_host_kmsg" -eq 1 ]; then
  set -- "$@" --privileged -v /dev/kmsg:/dev/kmsg
fi

if [ "$enable_host_opt" -eq 1 ]; then
  set -- "$@" -v /opt:/opt
fi

# Pass through currently attached serial adapters from the host.
for dev in /dev/ttyUSB* /dev/ttyACM*; do
  if [ -e "$dev" ]; then
    set -- "$@" --device "$dev:$dev"
  fi
done

exec "$@" "$image_name"
