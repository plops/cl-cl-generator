#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${1:-ai-env:latest}"
WORKSPACE_SRC="${WORKSPACE_SRC:-$(pwd)/src}"

# Lokale Konfigurationsverzeichnisse auf dem Host anlegen, falls nicht vorhanden
mkdir -p "$WORKSPACE_SRC" \
         "${HOME}/.config" \
         "${HOME}/.config/tc" \
         "${HOME}/.cache" \
         "${HOME}/.gemini" \
         "${HOME}/.grok" \
         "${HOME}/.codex" \
         "${HOME}/.azure" \
         "${HOME}/.cargo"

echo "Starte Container aus Image '$IMAGE_NAME'..."

exec docker run -it --rm \
  --net=host \
  -v "${WORKSPACE_SRC}:/workspace/src" \
  -v "${HOME}/.config:/root/.config" \
  -v "${HOME}/.config/tc:/root/.config/tc" \
  -v "${HOME}/.cache:/root/.cache" \
  -v "${HOME}/.gemini:/root/.gemini" \
  -v "${HOME}/.grok:/root/.grok" \
  -v "${HOME}/.codex:/root/.codex" \
  -v "${HOME}/.azure:/root/.azure" \
  -v "${HOME}/.cargo:/root/.cargo" \
  "$IMAGE_NAME" "$@"
