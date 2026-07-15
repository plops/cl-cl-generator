#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

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

# Pass through currently attached serial adapters from the host.
for dev in /dev/ttyUSB* /dev/ttyACM*; do
  if [ -e "$dev" ]; then
    set -- "$@" --device "$dev:$dev"
  fi
done

exec "$@" "$image_name"
