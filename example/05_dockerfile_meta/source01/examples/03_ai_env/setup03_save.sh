#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
image_name=${IMAGE_NAME:-my-ai-env:latest}
output_tar=${OUTPUT_TAR:-$script_dir/my-ai-env.tar}

docker save "$image_name" -o "$output_tar"

if command -v zstd >/dev/null 2>&1; then
  zstd -f -q -k "$output_tar"
  echo "Saved $output_tar and $output_tar.zst"
else
  echo "Saved $output_tar"
fi
