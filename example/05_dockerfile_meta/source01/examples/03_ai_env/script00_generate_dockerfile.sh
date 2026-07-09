#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dockerfile="$script_dir/Dockerfile"

if ! command -v sbcl >/dev/null 2>&1; then
  echo "sbcl is required to regenerate $dockerfile" >&2
  exit 1
fi

sbcl --load "$script_dir/gen_ai_env.lisp" --eval "(quit)"
