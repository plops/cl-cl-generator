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

echo ""
echo "=== Generating Dockerfile via SBCL ==="
sbcl --load gen_ai_env.lisp --eval "(quit)"

echo ""
echo "=== Done! ==="
echo "Dockerfile generated successfully in $(pwd)/Dockerfile"
echo "You can build the Docker image using:"
echo "  docker build -t my-ai-env ."
