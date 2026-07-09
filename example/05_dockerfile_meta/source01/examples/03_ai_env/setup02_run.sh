#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="${ENV_FILE:-$script_dir/.env.ai}"

# Create the folder on your host first so Docker doesn't generate it as 'root'
mkdir -p "$HOME/.gemini"

if [ ! -f "$env_file" ]; then
  echo "Missing env file: $env_file" >&2
  echo "Create it or set ENV_FILE=/path/to/your.env before running this script." >&2
  exit 1
fi

docker run -it \
  --env-file "$env_file" \
  -e ANTIGRAVITY_PLAINTEXT_AUTH=1 \
  -v "$HOME/.gemini:/root/.gemini" \
  -v "/home/kiel/stage:/workspace/src" \
  -v my-ai-env-cargo-cache:/root/.cargo \
  my-ai-env:latest
