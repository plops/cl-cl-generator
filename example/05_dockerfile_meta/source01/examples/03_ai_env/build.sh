#!/bin/bash
set -e

# Navigate to the script's directory
cd "$(dirname "$0")"

echo "=== Preparing Build Context ==="

# 1. Create a minimal .emacs config if not present
if [ ! -f .emacs ]; then
  echo "Creating default .emacs..."
  cat << 'EOF' > .emacs
;; Minimal Emacs configuration for Common Lisp / SLIME

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; Configure SLIME with SBCL
(setq inferior-lisp-program "sbcl")
EOF
fi

# 2. Check and copy local binaries from host if they exist
mkdir -p bin

echo "Searching for host CLI tools to copy..."
for tool in codex copilot kiro-cli; do
  TOOL_PATH=$(which $tool 2>/dev/null || true)
  if [ -n "$TOOL_PATH" ] && [ -f "$TOOL_PATH" ]; then
    echo "Found $tool at $TOOL_PATH, copying to build context..."
    cp -L "$TOOL_PATH" bin/$tool
  else
    echo "Note: $tool not found on host. If enabled, ensure you put a binary at bin/$tool before building Docker."
  fi
done

echo ""
echo "=== Generating Dockerfile via SBCL ==="
sbcl --load gen_ai_env.lisp --eval "(quit)"

echo ""
echo "=== Done! ==="
echo "Dockerfile generated successfully in $(pwd)/Dockerfile"
echo "You can build the Docker image using:"
echo "  docker build -t my-ai-env ."
