#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dockerfile="$script_dir/Dockerfile"
emacs_file="$script_dir/.emacs"
image_name=${IMAGE_NAME:-my-ai-env:latest}
created_emacs=0

cleanup() {
  if [ "$created_emacs" -eq 1 ]; then
    rm -f "$emacs_file"
  fi
}

trap cleanup EXIT INT TERM HUP

if [ ! -f "$dockerfile" ]; then
  echo "Missing Dockerfile: $dockerfile" >&2
  echo "Run setup00_generate_dockerfile.sh first if you need to regenerate it." >&2
  exit 1
fi

if [ ! -f "$emacs_file" ]; then
  created_emacs=1
  cat > "$emacs_file" <<'EOF'
;; Minimal Emacs configuration for Common Lisp / SLIME

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; Configure SLIME with SBCL
(setq inferior-lisp-program "sbcl")
EOF
fi

DOCKER_BUILDKIT=1 docker build -t "$image_name" "$script_dir"
