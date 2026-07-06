#!/bin/bash
set -e

# Navigate to the script's directory
cd "$(dirname "$0")"

# Ensure host folders for persistent caching exist
mkdir -p distfiles binpkgs output

echo "Generating Gentoo Dockerfile via SBCL..."
sbcl --load gen_gentoo.lisp --eval "(quit)"
echo "Dockerfile generated successfully."

echo "Starting BuildKit Docker build and exporting output directly to ./output ..."
# Redirect logs to output/build.log on host
export DOCKER_BUILDKIT=1
docker build -o ./output . 2>&1 | tee output/build.log

echo "Synchronizing newly downloaded distfiles and built packages to host cache..."
# Use rsync if available, otherwise fallback to cp
if command -v rsync >/dev/null 2>&1; then
  rsync -a --ignore-existing output/distfiles/ distfiles/ || true
  rsync -a --ignore-existing output/binpkgs/ binpkgs/ || true
else
  cp -rn output/distfiles/. distfiles/ 2>/dev/null || true
  cp -rn output/binpkgs/. binpkgs/ 2>/dev/null || true
fi

echo "Build and Export completed successfully!"
